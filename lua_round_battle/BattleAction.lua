---
--- class BattleAction
-- @classmod BattleAction
-- ս���ж����غ�ά���ж����У����д�ǰ�������ִ�У�ִ����ɺ�Ӷ����Ƴ�
-- ֱ��������գ����ɿ�ʼ��һ�غ�
class('BattleAction')

---Constructor
function BattleAction:ctor( _battleHero, _realAction, ... )
	self.actionHero = _battleHero					-- �ж�Ӣ��
	self.skillId = '0'								-- �ж�����ID
	self.skillRes = false							-- �ж���������
	self.targetHeroesList = {}						-- Ŀ��Ӣ���б�
	self.curTargetHero = false 						-- ��ǰĿ��Ӣ��
	self.forceTargetHeroes = {}						-- ָ��Ŀ��Ӣ���б�
	self.realAction = NilDefault(_realAction, true)	-- �Ƿ���ʵ�ж�����׷���ж�
	self.curPreHitIndex = 0							-- ��ǰԤ��������
	self.curHitIndex = 0 							-- ��ǰ��������
	self.triggerFlagList = {}						-- ��������ʶ��¼
	self.comboHeroIdList = {} 						-- ����Ӣ��Id�б�
	self.comboRes = false 							-- ��ǰ���弼����	
	self.normalAttackFuryed = false 				-- �չ�ŭ���Ѽ�
end

-- ָ���ж����ܺ�Ŀ��
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

-- �غ��ж���ʼ
function BattleAction:ActionBegin( ... )
	if not self.actionHero or gBattleManager:IsBattleEnd() then
		return
	end

	-- ��¼��ǰ��ʵ�ж�Ӣ��
	if self.realAction then
		gBattleManager.realActionHero = self.actionHero
	end
	
	-- Ӣ���ж���ʼ
	if not self.actionHero:ActionBegin(self.realAction) then
		return self:ActionEnd()
	end
	
	-- �ж�����Ԥ����
	if not self:PreExecSkill() then
		return self:ActionEnd()
	end
	
	-- ֪ͨ���ֲ�Ӣ���ж�
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ACTION, self.actionHero.heroId, self.skillRes.actionType, self.skillRes.skillType)
end

-- �غ��ж�����
function BattleAction:ActionEnd( ... )
	if gBattleManager:IsBattleEnd() then
		return
	end

	-- ֪ͨ�ж�Ӣ���ж�����
	self.actionHero:ActionEnd(self.realAction)

	-- ���弼����
	self.comboHeroIdList = {}
	self.comboRes = false

	-- ������һ���ж�
	gBattleManager:NextRoundAction()
end

-- Ԥ�����ж����ܣ���ΪĿ��
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

	-- ��ǿ��ָ��Ŀ�꣬�������Ŀ���Ƿ���
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

	-- Ԥ�����һ���˺�
	self:PreExecSkillHit(1)

	return true
end

-- Ԥ�������˺�
function BattleAction:PreExecSkillHit( _hitIndex, ... )
	-- �˺�����+1
	self.curPreHitIndex = self.curPreHitIndex + 1
	-- У�����������Ƿ���Ч
	if (_hitIndex and _hitIndex ~= self.curPreHitIndex) or self.curPreHitIndex > self:GetDamageCount() then
		return false
	end

	local targetHeroes = {}
	if self.forceTargetHeroes and #self.forceTargetHeroes ~= 0 then
		-- ��ǿ��ָ��Ŀ�꣬�������Ŀ���Ƿ���
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
			-- ������ʱ������Ŀ��Ϊ����Ӣ��
			targetHeroes = { cxHero }
		elseif lockedHero and not lockedHero:HasHeroFlag(BattleHeroFlag.DEATH) then
			-- ������Ŀ��
			targetHeroes = { lockedHero }
		elseif self:GetCurTargetId(true) == '0' and #self:GetLastTargetHeroes(true) ~= 0 then
			-- ��һ��Ŀ��
			targetHeroes = self:GetLastTargetHeroes(true) 
		else
			-- δָ��Ŀ��ʱ��Ѱ���ж�Ŀ��
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

-- ����������
function BattleAction:ExecSkillHit( ... )
	self.curHitIndex = self.curHitIndex + 1
end

-- ��ȡ��ǰĿ��
function BattleAction:GetCurTargetHeroes( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if hitIndex <= 0 or hitIndex > #self.targetHeroesList then
		return {}
	end
	return self.targetHeroesList[hitIndex]
end

-- ��ȡ��һ��Ŀ��
function BattleAction:GetLastTargetHeroes( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if hitIndex <= 1 or hitIndex - 1 > #self.targetHeroesList then
		return {}
	end
	return self.targetHeroesList[hitIndex - 1]
end

-- �ж����˺�����
function BattleAction:GetDamageCount( ... )
	if not self.skillRes then
		return 0
	end

	return self.skillRes.damageCount
end

-- �ж�����Ϊ�˺�ϵ��
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

-- ��ǰ�˺�����
function BattleAction:GetCurDamageType( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return 0
	end

	return self.skillRes.damageTypeList[hitIndex]
end

-- ��ǰĿ��ID
function BattleAction:GetCurTargetId( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return '0'
	end

	return self.skillRes.targetIdList[hitIndex]
end

-- ��ǰ�˺����������
function BattleAction:GetCurTriggerFlag( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return 0
	end

	return self.skillRes.triggerFlagList[hitIndex]
end

-- ��ǰ�˺���Ч
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

-- ��ǰ�˺�������Ч
function BattleAction:GetCurSubEffectId( _isPreHit, _hitIndex, ... )
	local hitIndex = ToInt(NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex))
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.subEffectIdList then
		return 0
	end

	return self.skillRes.subEffectIdList[hitIndex]
end

-- ��ǰ�˺�������Ч
function BattleAction:GetCurHitEffectId( _isPreHit, _hitIndex, ... )
	local hitIndex = ToInt(NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex))
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.hitEffectIdList then
		return 0
	end

	return self.skillRes.hitEffectIdList[hitIndex]
end

-- ��ǰ����
function BattleAction:GetCurShakeId( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.shakeIdList then
		return 0
	end

	return self.skillRes.shakeIdList[hitIndex]
end

-- ��ǰ������Ч
function BattleAction:GetCurHitSound( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > #self.skillRes.attackHitSound then
		return ''
	end

	return self.skillRes.attackHitSound[hitIndex]
end

-- �ж���������
function BattleAction:GetSkillType()
	if not self.skillRes then
		return SkillType.ALL
	end
	
	return self.skillRes.skillType
end

-- �ж�������������
function BattleAction:GetSkillEffectType( ... )
	if not self.skillRes then
		return SkillEffectType.DAMAGE
	end

	return self.skillRes.effectType
end

-- ��ǰ�˺��Ƿ����
function BattleAction:IsCurDamageMustHit( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return damageFlag % 10 == 1
end

-- ��ǰ�˺��Ƿ����ӻ���
function BattleAction:IsCurDamageIgnoreDefence( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return ToInt(damageFlag * 0.1) % 10 == 1
end

-- ��ǰ�˺��Ƿ�ر���
function BattleAction:IsCurDamageMustCritical( _isPreHit, _hitIndex, ... )
	local hitIndex = NilDefault(_hitIndex, _isPreHit and self.curPreHitIndex or self.curHitIndex)
	if not self.skillRes or hitIndex <= 0 or hitIndex > self.skillRes.damageCount then
		return false
	end

	local damageFlag = self.skillRes.damageFlagList[hitIndex]
	return ToInt(damageFlag * 0.01) % 10 == 1
end

-- У�鴥��������Ƿ񴥷���
function BattleAction:IsTriggerFlagFired( _triggerKey, ... )
	if self.triggerFlagList[_triggerKey] then
		return true
	end

	self.triggerFlagList[_triggerKey] = 1
	return false
end

classend()