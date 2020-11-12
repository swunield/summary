---
--- class BattleAction
-- @classmod BattleAction
-- 战斗行动，回合维护行动队列，队列从前向后依次执行，执行完成后从队列移除
-- 直至队列清空，即可开始下一回合
class('BattleAction')

---Constructor
function BattleAction:ctor( _battleHero, _realAction, ... )
	self.actionHero = _battleHero					-- 行动英雄
	self.skillId = '0'								-- 行动技能ID
	self.skillRes = false							-- 行动技能配置
	self.targetHeroesList = {}						-- 目标英雄列表
	self.curTargetHero = false 						-- 当前目标英雄
	self.forceTargetHeroes = {}						-- 指定目标英雄列表
	self.realAction = NilDefault(_realAction, true)	-- 是否真实行动，非追加行动
	self.curPreHitIndex = 0							-- 当前预命中索引
	self.curHitIndex = 0 							-- 当前命中索引
	self.triggerFlagList = {}						-- 触发器标识记录
	self.comboHeroIdList = {} 						-- 合体英雄Id列表
	self.comboRes = false 							-- 当前合体技配置	
	self.normalAttackFuryed = false 				-- 普攻怒气已加
end

-- 指定行动技能和目标
function BattleAction:ForceSkillAndTarget( _forceSkillId, _forceTarget, ... )
	local skillRes = GameResMgr.GetSkillRes(_forceSkillId)
	if skillRes then
		self.skillId = _forceSkillId
	else
		self.skillId = gBattleAction.skillId
	end
	
	if _forceTarget and #_forceTarget ~= 0 then
		self.forceTargetHeroes = _forceTarget
	end
end

-- 回合行动开始
function BattleAction:ActionBegin( ... )
	if not self.actionHero or gBattleManager:IsBattleEnd() then
		return
	end

	-- 记录当前真实行动英雄
	if self.realAction then
		gBattleManager.realActionHero = self.actionHero
	end
	
	-- 英雄行动开始
	if not self.actionHero:ActionBegin(self.realAction) then
		return self:ActionEnd()
	end
	
	-- 行动技能预处理
	if not self:PreExecSkill() then
		return self:ActionEnd()
	end
	
	-- 通知表现层英雄行动
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ACTION, self.actionHero.heroId, self.skillRes.actionType, self.skillRes.skillType)
end

-- 回合行动结束
function BattleAction:ActionEnd( ... )
	if gBattleManager:IsBattleEnd() then
		return
	end

	-- 通知行动英雄行动结束
	self.actionHero:ActionEnd(self.realAction)

	-- 合体技重置
	self.comboHeroIdList = {}
	self.comboRes = false

	-- 继续下一次行动
	gBattleManager:NextRoundAction()
end

-- 预处理行动技能，行为目标
function BattleAction:PreExecSkill( ... )
	self.skillRes = GameResMgr.GetSkillRes(self.skillId)
	if not self.skillRes then
		error(string.format('Hero[%d--%d] PreExecSkill Skill Type Not Avalid %s', self.actionHero.heroId, self.actionHero.heroRes.heroId, self.skillId))
		return false
	end

	if self.skillRes.damageCount > #self.skillRes.damageScaleList or self.skillRes.damageCount > #self.skillRes.damageFlagList or 
		self.skillRes.damageCount > #self.skillRes.damageTypeList or self.skillRes.damageCount > #self.skillRes.targetIdList or
		self.skillRes.damageCount > #self.skillRes.triggerFlagList then
		error('PreExecSkill Skill DamageCount Not Avalid ' .. self.skillId)
		return false
	end

	-- 若强制指定目标，检查所有目标是否存活
	if self.forceTargetHeroes and #self.forceTargetHeroes ~= 0 then
		for i = #self.forceTargetHeroes, 1, -1 do
			if self.forceTargetHeroes[i]:HasHeroFlag(BattleHeroFlag.DEATH) then
				table.remove(self.forceTargetHeroes, i)
			end
		end
		if #self.forceTargetHeroes == 0 then
			return false
		end
	end

	-- 预处理第一次伤害
	self:PreExecSkillHit(1)

	return true
end

-- 预处理技能伤害
function BattleAction:PreExecSkillHit( _hitIndex, ... )
	-- 伤害索引+1
	self.curPreHitIndex = self.curPreHitIndex + 1
	-- 校验命中索引是否有效
	if (_hitIndex and _hitIndex ~= self.curPreHitIndex) or self.curPreHitIndex > self:GetDamageCount() then
		return false
	end

	local targetHeroes = {}
	if self.forceTargetHeroes and #self.forceTargetHeroes ~= 0 then
		-- 若强制指定目标，检查所有目标是否存活
		targetHeroes = self.forceTargetHeroes
		for i = #targetHeroes, 1, -1 do
			if targetHeroes[i]:HasHeroFlag(BattleHeroFlag.DEATH) then
				table.remove(targetHeroes, i)
			end
		end
		if #targetHeroes == 0 then
			table.insert(self.targetHeroesList, targetHeroes)
			return false
		end
	else
		local lockedHeroId = self.actionHero:GetHeroFlagValue(BattleHeroFlag.TARGETLOCKED)
		local lockedHero = gBattleManager:GetBattleHero(lockedHeroId)
		local cxHero = gBattleManager:GetBattleHero(self.actionHero.cxHeroId)
		if cxHero and not cxHero:HasHeroFlag(BattleHeroFlag.DEATH) then
			-- 被嘲讽时，攻击目标为嘲讽英雄
			targetHeroes = { cxHero }
		elseif lockedHero and not lockedHero:HasHeroFlag(BattleHeroFlag.DEATH) then
			-- 有锁定目标
			targetHeroes = { lockedHero }
		elseif self:GetCurTargetId(true) == '0' and #self:GetLastTargetHeroes(true) ~= 0 then
			-- 上一次目标
			targetHeroes = self:GetLastTargetHeroes(true) 
		else
			-- 未指定目标时，寻找行动目标
			targetHeroes = BattleTarget.FindTargetHero(self:GetCurTargetId(true), self.actionHero)
		end

		if not targetHeroes or #targetHeroes == 0 then
			targetHeroes = self:GetLastTargetHeroes(true)
			if not targetHeroes or #targetHeroes == 0 then
				table.insert(self.targetHeroesList, {})

				warn('skillid:',self.skillId,self.actionHero.heroId, self.curPreHitIndex, gBattleManager:CheckBattleEnd())
				error('PreExecSkillHit Can Not Find Target ' .. self:GetCurTargetId(true))
				return false
			end
		end
	end

	table.insert(self.targetHeroesList, targetHeroes)
	return true
end

-- 处理技能命中
function BattleAction:ExecSkillHit( ... )
	self.curHitIndex = self.curHitIndex + 1
end

-- 获取当前目标
function BattleAction:GetCurTargetHeroes( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if hitIndex <= 0 or hitIndex > #self.targetHeroesList then
		return {}
	end
	return self.targetHeroesList[hitIndex]
end

-- 获取上一次目标
function BattleAction:GetLastTargetHeroes( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if hitIndex <= 1 or hitIndex - 1 > #self.targetHeroesList then
		return {}
	end
	return self.targetHeroesList[hitIndex - 1]
end

-- 行动总伤害次数
function BattleAction:GetDamageCount( ... )
	if not self.skillRes then
		return 0
	end

	return self.skillRes.damageCount
end

-- 行动主行为伤害系数
function BattleAction:GetCurDamageScale( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return 0
	end

	local damageScale = 0
	local result = Split(self.skillRes.damageScaleList[hitIndex], '_')
	if #result == 2 then
		damageScale = gBattleRandNum:NextInt(ToInt(result[1]), ToInt(result[2]))
	else
		damageScale = ToInt(result[1])
	end

	return damageScale
end

-- 当前伤害类型
function BattleAction:GetCurDamageType( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return 0
	end

	return self.skillRes.damageTypeList[hitIndex]
end

-- 当前目标ID
function BattleAction:GetCurTargetId( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return '0'
	end

	return self.skillRes.targetIdList[hitIndex]
end

-- 当前伤害触发器标记
function BattleAction:GetCurTriggerFlag( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return 0
	end

	return self.skillRes.triggerFlagList[hitIndex]
end

-- 当前伤害特效
function BattleAction:GetCurEffectId( _isPreHit, _hitIndex, _isSubEffect, ... )
	if _isSubEffect then
		return self:GetCurSubEffectId(_isPreHit, _hitIndex)
	end

	local hitIndex = ToInt(NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex))
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.effectIdList then
		return 0
	end

	return self.skillRes.effectIdList[hitIndex]
end

-- 当前伤害附属特效
function BattleAction:GetCurSubEffectId( _isPreHit, _hitIndex, ... )
	local hitIndex = ToInt(NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex))
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.subEffectIdList then
		return 0
	end

	return self.skillRes.subEffectIdList[hitIndex]
end

-- 当前伤害命中特效
function BattleAction:GetCurHitEffectId( _isPreHit, _hitIndex, ... )
	local hitIndex = ToInt(NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex))
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.hitEffectIdList then
		return 0
	end

	return self.skillRes.hitEffectIdList[hitIndex]
end

-- 当前震屏
function BattleAction:GetCurShakeId( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.shakeIdList then
		return 0
	end

	return self.skillRes.shakeIdList[hitIndex]
end

-- 当前命中音效
function BattleAction:GetCurHitSound( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.attackHitSound then
		return ''
	end

	return self.skillRes.attackHitSound[hitIndex]
end

-- 行动技能类型
function BattleAction:GetSkillType()
	if not self.skillRes then
		return SkillType.ALL
	end
	
	return self.skillRes.skillType
end

-- 行动技能作用类型
function BattleAction:GetSkillEffectType( ... )
	if not self.skillRes then
		return SkillEffectType.DAMAGE
	end

	return self.skillRes.effectType
end

-- 当前伤害是否必中
function BattleAction:IsCurDamageMustHit( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return damageFlag % 10 == 1
end

-- 当前伤害是否无视护甲
function BattleAction:IsCurDamageIgnoreDefence( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return ToInt(damageFlag * 0.1) % 10 == 1
end

-- 当前伤害是否必暴击
function BattleAction:IsCurDamageMustCritical( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return ToInt(damageFlag * 0.01) % 10 == 1
end

-- 校验触发器标记是否触发过
function BattleAction:IsTriggerFlagFired( _triggerKey, ... )
	if self.triggerFlagList[_triggerKey] then
		return true
	end

	self.triggerFlagList[_triggerKey] = 1
	return false
end

classend()