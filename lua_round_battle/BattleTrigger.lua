---
--- class BattleTrigger
-- @classmod BattleTrigger
-- 战斗触发器，用于行为触发管理
class('BattleTrigger')

---Constructor
function BattleTrigger:ctor( ... )
	self.triggerMap = {}	 		-- 触发器Map，Key--BattleTriggerType  Value--ActionTrigger Array
	self.triggerIdGenerator = 0
end

-- 注册行为
function BattleTrigger:RegisterAction( _skillActionId, _battleHero, _ownerHero, ... )
	local skillAcionRes = GameResMgr.GetBattleActionRes(_skillActionId)
	if not skillAcionRes then
		return 0
	end
	
	local triggerRes = GameResMgr.GetBattleTriggerRes(skillAcionRes.triggerId)
	if not triggerRes then
		return 0
	end

	-- 注册进触发器Map
	local triggerType = triggerRes.triggerType
	local triggerValue = triggerRes.triggerValue
	local triggerKey = triggerType
	if triggerType == BattleTriggerType.TRIGGER or triggerType == BattleTriggerType.BUFFERROUNDACTION or triggerType == BattleTriggerType.BUFFER then
		triggerKey = string.format('%d_%s', triggerType, triggerValue)
	end
	if self.triggerMap[triggerKey] == nil then
		self.triggerMap[triggerKey] = {}
	end

	local triggerId = self:GenerateTriggerId()
	local actionTrigger = ActionTrigger(_battleHero, _ownerHero, skillAcionRes, triggerRes, triggerId)
	table.insert(self.triggerMap[triggerKey], actionTrigger)

	return triggerId
end

-- 移除行为
function BattleTrigger:UnRegisterAction( _skillActionId, _battleHeroId, ... )
	local skillAcionRes = GameResMgr.GetBattleActionRes(_skillActionId)
	if not skillAcionRes then
		return
	end
	
	local triggerRes = GameResMgr.GetBattleTriggerRes(skillAcionRes.triggerId)
	if not triggerRes then
		return
	end

	local triggerType = triggerRes.triggerType
	local triggerValue = triggerRes.triggerValue
	local triggerKey = triggerType
	if triggerType == BattleTriggerType.TRIGGER or triggerType == BattleTriggerType.BUFFERROUNDACTION or triggerType == BattleTriggerType.BUFFER then
		triggerKey = string.format('%d_%s', triggerType, triggerValue)
	end

	local triggerList = self.triggerMap[triggerKey]
	if not triggerList or #triggerList == 0 then
		return
	end
	
	local triggerNum = #triggerList
	for i = triggerNum, 1, -1 do
		local actTrigger = triggerList[i]
		if actTrigger.actionRes.id == _skillActionId and actTrigger.battleHero.heroId == _battleHeroId then
			actTrigger.isRemove = true
			return
		end
	end
end

-- 移除行为触发
function BattleTrigger:UnRegisterActionTrigger( _triggerId, ... )
	for k,v in pairs(self.triggerMap) do
		local triggerList = v
		local triggerNum = #triggerList
		for i = triggerNum, 1, -1 do
			if triggerList[i].triggerId == _triggerId then
				triggerList[i].isRemove = true
				return
			end
		end
	end
end

-- 移除英雄所有行为
function BattleTrigger:UnRegisterHeroAllActions( _battleHeroId, ... )
	for k,v in pairs(self.triggerMap) do
		local triggerList = v
		local triggerNum = #triggerList
		for i = triggerNum, 1, -1 do
			if triggerList[i].battleHero.heroId == _battleHeroId then
				triggerList[i].isRemove = true
			end
		end
	end
end

-- 触发行为
function BattleTrigger:FireTrigger( _triggerType, _triggerParam, _ignoreTriggerFlag, ... )
	local ignoreTriggerFlag = NilDefault(_ignoreTriggerFlag, false)
	if not ignoreTriggerFlag and gBattleAction then
		local targetHeroId = _triggerParam.targetHeroes and #_triggerParam.targetHeroes ~= 0 and _triggerParam.targetHeroes[1].heroId or 0
		local triggerFlagKey = string.format('%d_%d_%d_%d', _triggerType, gBattleAction:GetCurTriggerFlag(), _triggerParam.triggerHero.heroId, targetHeroId)
		if gBattleAction:IsTriggerFlagFired(triggerFlagKey) then
			return
		end
	end

	local triggerKey = _triggerType
	if _triggerType == BattleTriggerType.TRIGGER or _triggerType == BattleTriggerType.BUFFERROUNDACTION or triggerType == BattleTriggerType.BUFFER then
		triggerKey = string.format('%d_%s', _triggerType, _triggerParam.triggerValue)
	end

	local triggerList = self.triggerMap[triggerKey]
	if not triggerList or #triggerList == 0 then
		return
	end
	
	local triggerNum = #triggerList
	for i = 1, triggerNum do
		if not triggerList[i].isRemove then
			triggerList[i]:FireTrigger(_triggerParam)
		end
	end
end

-- 生成触发器ID
function BattleTrigger:GenerateTriggerId( ... )
	self.triggerIdGenerator = self.triggerIdGenerator + 1
	return self.triggerIdGenerator
end

classend()


-- 战斗行为触发
class('ActionTrigger')

function ActionTrigger:ctor( _battleHero, _ownerHero, _actionRes, _triggerRes, _triggerId, ... )
	self.triggerId = NilDefault(_triggerId, 0)
	self.battleHero = NilDefault(_battleHero, false)
	self.ownerHero = NilDefault(_ownerHero, false)
	self.actionRes = NilDefault(_actionRes, false)
	self.triggerRes = NilDefault(_triggerRes, false)
	self.realTriggerHero = false
	self.isRemove = false
end

-- 触发行为枚举
local TriggerActionSwitcher = 
{
	-- 额外伤害
	[BattleActionType.EXTRADAMAGE] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecExtraDamage(_triggerParam, _targetHeroes, ...)
	end,
	-- 直接伤害
	[BattleActionType.DIRECTDAMAGE] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecDirectDamage(_triggerParam, _targetHeroes, ...)
	end,
	-- 额外伤害系数
	[BattleActionType.DAMAGESCALE] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecDamageScale(_triggerParam, _targetHeroes, ...)
	end,
	-- 回血
	[BattleActionType.HEAL] = function( _actionTrigger, _triggerParam, _targetHeroes, ...  )
		return _actionTrigger:ExecHeal(_triggerParam, _targetHeroes, ...)
	end,
	-- 增加状态
	[BattleActionType.BUFF] = function( _actionTrigger, _triggerParam, _targetHeroes, ...  )
		return _actionTrigger:ExecBuff(_triggerParam, _targetHeroes, _triggerParam.targetHeroes, ...)
	end,
	-- 移除状态
	[BattleActionType.REMOVEBUFF] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecRemoveBuff(_triggerParam, _targetHeroes, ...)
	end,
	-- 替换普攻
	[BattleActionType.NEWNORMAL] = function( _actionTrigger, _triggerParam, _targetHeroes, ...  )
		return _actionTrigger:ExecNewNormal(_triggerParam, _targetHeroes, ...)
	end,
	-- 增加行动，反击，追击
	[BattleActionType.NEWACTION] = function( _actionTrigger, _triggerParam, _targetHeroes, ...  )
		return _actionTrigger:ExecNewAction(_triggerParam, _targetHeroes, ...)
	end,
	-- 偷取怒气
	[BattleActionType.STEALFURY] = function( _actionTrigger, _triggerParam, _targetHeroes, ...  )
		return _actionTrigger:ExecStealFury(_triggerParam, _targetHeroes, ...)
	end,
	-- 复活
	[BattleActionType.FUHUO] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecReBirth(_triggerParam, _targetHeroes, ...)
	end,
	-- 改变怒气
	[BattleActionType.CHANGEFURY] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecChangeFury(_triggerParam, _targetHeroes, ...)
	end,
	-- 标记
	[BattleActionType.FLAG] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecFlag(_triggerParam, _targetHeroes, ...)
	end,
	-- 清除标记
	[BattleActionType.CLEARFLAG] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecClearFlag(_triggerParam, _targetHeroes, ...)
	end,
	-- 驱散
	[BattleActionType.QUSAN] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecQuSanBuffer(_triggerParam, _targetHeroes, ...)
	end,
	-- 格挡
	[BattleActionType.GEDANG] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecGeDang(_triggerParam, _targetHeroes, ...)
	end,
	-- 反弹
	[BattleActionType.FANTAN] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecFanTan(_triggerParam, _targetHeroes)
	end,
	-- 净化
	[BattleActionType.JINGHUA] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecJingHuaBuffer(_triggerParam, _targetHeroes, _triggerParam.targetHeroes, ...)
	end,
	-- 反噬
	[BattleActionType.FANSHI] = function( _actionTrigger, _triggerParam, _targetHeroes, ... )
		return _actionTrigger:ExecFanShi(_triggerParam, _targetHeroes, ...)
	end,
}

-- 触发行为
function ActionTrigger:FireTrigger( _triggerParam, ... )
	-- 校验触发条件
	local isFire, isFireTwice = self:CheckCondition(_triggerParam)
	if not isFire then
		return false
	end 

	-- 寻找目标英雄
	local actionType = self.actionRes.actionType
	local targetHeroes = BattleTarget.FindTargetHero(self.actionRes.targetId, self.battleHero, _triggerParam.targetHeroes, _triggerParam.attackerHero, _triggerParam.triggerHero)
	if (not targetHeroes or #targetHeroes == 0) and actionType ~= BattleActionType.NEWACTION then
		return false
	end

	-- 执行行为
	local actionExcutor = TriggerActionSwitcher[actionType]
	if actionExcutor then
		if actionExcutor(self, _triggerParam, targetHeroes, ...) then
			-- 触发者播放触发特效
			if self.actionRes.triggerEffectId ~= '' then
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.EFFECT, self.actionRes.triggerEffectId, self.realTriggerHero.heroId, self.realTriggerHero.heroId)
			end

			-- 触发器生效触发
			local triggerParam = TriggerParam(nil, nil, _triggerParam.triggerHero, _triggerParam.attackerHero, targetHeroes, _triggerParam.attackDamage + _triggerParam.extraDamage, _triggerParam.triggerHeroHP, self.triggerRes.id)
			gBattleTrigger:FireTrigger(BattleTriggerType.TRIGGER, triggerParam, true)

			-- 额外伤害累积
			_triggerParam.extraDamage = _triggerParam.extraDamage + triggerParam.extraDamage

			-- 记录触发器触发
			self.realTriggerHero:RecordTriggerFire(self.triggerRes, self.triggerId)
		end
	end

	-- 再触发一次
	if isFireTwice then
		self:FireTrigger(_triggerParam)
	end

	return true
end

-- 额外伤害
function ActionTrigger:ExecExtraDamage( _triggerParam, _targetHeroes, ... )
	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end

	local result = Split(self.actionRes.value, '|')
	if #result ~= 3 then
		return false
	end

	local damageScale = ToInt(result[1])
	local damageType = ToInt(result[2])
	local damageFlag = ToInt(result[3])
	local isMustHit = damageFlag % 10 == 1
	local isIgnoreDefence = ToInt(damageFlag * 0.1) % 10 == 1
	local isMustCritical = ToInt(damageFlag * 0.01) % 10 == 1
	
	-- 增加额外伤害
	_triggerParam.extraDamage = _triggerParam.extraDamage + _triggerParam.attackerHero:CalcAttackDamage(_targetHeroes[1], SkillType.TALENT, nil, damageType, damageScale, isMustHit, isMustCritical, isIgnoreDefence)

	return true
end

-- 伤害
function ActionTrigger:ExecDirectDamage( _triggerParam, _targetHeroes, ... )
	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end

	local result = Split(self.actionRes.value, '|')
	if #result ~= 3 then
		return false
	end

	local damageScale = ToInt(result[1])
	local damageType = ToInt(result[2])
	local damageFlag = ToInt(result[3])
	local isMustHit = damageFlag % 10 == 1
	local isIgnoreDefence = ToInt(damageFlag * 0.1) % 10 == 1
	local isMustCritical = ToInt(damageFlag * 0.01) % 10 == 1

	for i = 1, #_targetHeroes do
		local damage = self.realTriggerHero:CalcAttackDamage(_targetHeroes[i], SkillType.TALENT, nil, damageType, damageScale, isMustHit, isMustCritical, isIgnoreDefence)
		_targetHeroes[i]:OnAttackDamage(self.realTriggerHero, SkillType.TALENT, nil, damage)
		-- 触发者播放触发特效
		if self.actionRes.hitEffectId ~= '' then
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.EFFECT, self.actionRes.hitEffectId, _targetHeroes[i].heroId, _targetHeroes[i].heroId)
		end
	end

	return true
end

-- 额外伤害系数
function ActionTrigger:ExecDamageScale( _triggerParam, _targetHeroes, ... )
	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end

	-- 增加额外伤害百分比
	_triggerParam.damageScale = _triggerParam.damageScale + ToInt(self.actionRes.value)

	return true
end

-- 回血
function ActionTrigger:ExecHeal( _triggerParam, _targetHeroes, ... )
	local result = Split(self.actionRes.value, '|')
	if #result ~= 3 then
		return false
	end

	local healScale = ToInt(result[1])
	local damageType = ToInt(result[2])

	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			local healerHero = self.ownerHero and self.ownerHero or self.battleHero
			local healHP = healerHero:CalcHealHP(_targetHeroes[i], healScale, damageType, SkillType.TALENT)
			_targetHeroes[i]:HealHP(healHP, healerHero)
			isTriggered = true
		end
	end
	
	return isTriggered
end

-- 增加状态
function ActionTrigger:ExecBuff( _triggerParam, _targetHeroes, _triggerTargetHeroes, ... )
	local bufferId = ToInt(self.actionRes.value)
	local heroNum = #_targetHeroes
	local isTriggered = false
	local isActionEnd = (self.triggerRes.triggerType == BattleTriggerType.ATTACKEND or self.triggerRes.triggerType == BattleTriggerType.SPELLEND 
		or self.triggerRes.triggerType == BattleTriggerType.ATTACKHITEND or self.triggerRes.triggerType == BattleTriggerType.SPELLHITEND)
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			local bufferHero = self.ownerHero and self.ownerHero or self.battleHero
			_targetHeroes[i]:AddBuffer(bufferId, bufferHero, isActionEnd, isActionEnd and _triggerTargetHeroes or nil)
			isTriggered = true
		end
	end
	
	return isTriggered
end

-- 移除状态
function ActionTrigger:ExecRemoveBuff( _triggerParam, _targetHeroes, ... )
	local bufferId = ToInt(self.actionRes.value)
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			_targetHeroes[i]:RemoveBufferByTypeId(bufferId)
		end
	end

	return isTriggered
end

-- 替换普攻
function ActionTrigger:ExecNewNormal( _triggerParam, _targetHeroes, ... )
	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end	
	
	self.battleHero:ReplaceNormalAttack(ToInt(self.actionRes.value))
	
	return true
end

-- 增加行动，反击，追击
function ActionTrigger:ExecNewAction( _triggerParam, _targetHeroes, ... )
	-- 非追击才能触发
	if not gBattleAction.realAction and not gBattleManager.isRoundEndTriggered then
		return false
	end

	if #_targetHeroes > 0 then
		for i = #_targetHeroes, 1, -1 do
			if _targetHeroes[i]:HasHeroFlag(BattleHeroFlag.GHOST) then
				table.remove(_targetHeroes, i)
			end
		end
		if #_targetHeroes == 0 then
			return false
		end
	end

	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end
	
	local attackId = self.actionRes.value
	attackId = attackId == '' and gBattleAction.skillId or attackId
	if ToInt(attackId) == SkillType.NORMAL then
		attackId = self.realTriggerHero.heroRes.attackId
	elseif ToInt(attackId) == SkillType.SPELL then
		attackId = self.realTriggerHero.heroRes.skillId
	end
	
	gBattleManager:AddExtraAction(self.realTriggerHero, attackId, _targetHeroes)
	
	return true
end

-- 偷取怒气
function ActionTrigger:ExecStealFury( _triggerParam, _targetHeroes, ... )
	local furyNum = ToInt(self.actionRes.value)
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			self.battleHero:StealFury(_targetHeroes[i], furyNum)
			isTriggered = true
		end
	end

	if isTriggered then
		-- 播放怒气变化特效
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.EFFECT, Constants.BT_furyUpEffect, self.battleHero.heroId, self.battleHero.heroId)
	end
	
	return isTriggered
end

-- 复活
function ActionTrigger:ExecReBirth( _triggerParam, _targetHeroes, ... )
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			-- 每个英雄只能复活一次
			local targetHero = _targetHeroes[i]
			if not targetHero:HasHeroFlag(BattleHeroFlag.REBIRTH) then
				-- 恢复血量
				local _healHP = targetHero.heroData.maxHP * (ToInt(self.actionRes.value) * s_PercentScale)
				targetHero:HealHP(_healHP, targetHero)
				
				-- 标记复活
				targetHero:AddHeroFlag(BattleHeroFlag.REBIRTH)

				-- 播放复活动作
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.ACTION, targetHero.heroId, HeroActionType.REBIRTH)

				isTriggered = true
			end
		end
	end
	
	return isTriggered
end

-- 改变怒气
function ActionTrigger:ExecChangeFury( _triggerParam, _targetHeroes, ... )
	local furyNum = ToInt(self.actionRes.value)
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			_targetHeroes[i]:AddHeroFury(furyNum)
--			warn('ExecChangeFury', _triggerParam.triggerHero.heroId, _targetHeroes[i].heroId, furyNum, _targetHeroes[i].heroData.fury)
			isTriggered = true

			if not _targetHeroes[i].isPetHero then
				-- 播放怒气变化特效
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.EFFECT, furyNum > 0 and Constants.BT_furyUpEffect or Constants.BT_furyDownEffect, _targetHeroes[i].heroId, _targetHeroes[i].heroId)
			end
		end
	end

	return isTriggered
end

-- 标记
function ActionTrigger:ExecFlag( _triggerParam, _targetHeroes, ... )
	local result = Split(self.actionRes.value, '|')
	local flagType = ToInt(result[1])
	local flagValue = result[2] and ToInt(result[2]) or 1
	if flagType == BattleHeroFlag.TARGETLOCKED then
		-- 目标锁定
		flagValue = _triggerParam.targetHeroes and #_triggerParam.targetHeroes > 0 and _triggerParam.targetHeroes[1].heroId or 0
	end

	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			_targetHeroes[i]:AddHeroFlag(flagType, flagValue)
			isTriggered = true
		end
	end

	return isTriggered
end

-- 清除标记
function ActionTrigger:ExecClearFlag( _triggerParam, _targetHeroes, ... )
	local flag = ToInt(self.actionRes.value)

	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			_targetHeroes[i]:ClearHeroFlag(flag)
			isTriggered = true
		end
	end

	return isTriggered
end

-- 驱散
function ActionTrigger:ExecQuSanBuffer( _triggerParam, _targetHeroes, ... )
	local targetAttrType = ToInt(self.actionRes.value)
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			_targetHeroes[i]:QuSanBuffer(targetAttrType)
			isTriggered = true
		end
	end
	
	return isTriggered
end

-- 格挡
function ActionTrigger:ExecGeDang( _triggerParam, _targetHeroes, ... )
	-- 格挡只针对普攻和大招
	if _triggerParam.triggerSkillType == SkillType.TALENT then
		return
	end

	-- 校验触发概率
	if not self:CheckTriggerRate() then
		return false
	end

	local gdScale = ToInt(self.actionRes.value) * s_PercentScale
	local baseDamage = _triggerParam.attackDamage + _triggerParam.extraDamage
	_triggerParam.extraDamage = _triggerParam.extraDamage - baseDamage * gdScale
	
	return true
end

-- 反弹
function ActionTrigger:ExecFanTan( _triggerParam, _targetHeroes, ... )
	-- 反弹只针对普攻和大招
	if _triggerParam.triggerSkillType == SkillType.TALENT then
		return
	end
	
	-- 校验触发概率
	if not self:CheckTriggerRate(true) then
		return false
	end

	local attackDamage = _triggerParam.attackDamage + _triggerParam.extraDamage
	if _triggerParam.triggerHeroHP and attackDamage > _triggerParam.triggerHeroHP then
		attackDamage = _triggerParam.triggerHeroHP
	end

	local ftScale = ToInt(self.actionRes.value) * s_PercentScale
	local ftDamage = attackDamage * ftScale
	local heroNum = #_targetHeroes
	for i = 1, heroNum do
		_targetHeroes[i]:OnAttackDamage(self.battleHero, SkillType.TALENT, nil, ftDamage)
	end
	
	return true
end

-- 净化
function ActionTrigger:ExecJingHuaBuffer( _triggerParam, _targetHeroes, _triggerTargetHeroes, ... )
	local result = Split(self.actionRes.value, '|')
	local typeNum = ToInt(result[1])
	local jhCount = result[2] and ToInt(result[2]) or 0
	local copyCount = result[3] and ToInt(result[3]) or 0
	local targetPNType = ToInt(typeNum / 1000)
	local targetBufferType = ToInt(typeNum % 1000)
	local heroNum = #_targetHeroes
	local isTriggered = false
	for i = 1, heroNum do
		-- 校验触发概率
		if self:CheckTriggerRate() then
			local jhBufferList = _targetHeroes[i]:JingHuaBuffer(targetPNType, targetBufferType, jhCount)
			isTriggered = isTriggered or #jhBufferList ~= 0
			if isTriggered then
				-- 播放净化特效
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.EFFECT, targetPNType == BufferPNType.POSITIVE and Constants.BT_quSanEffect or Constants.BT_jingHuaEffect, _targetHeroes[i].heroId, _targetHeroes[i].heroId)
			end

			if copyCount > 0 then
				local isActionEnd = (self.triggerRes.triggerType == BattleTriggerType.ATTACKEND or self.triggerRes.triggerType == BattleTriggerType.SPELLEND 
					or self.triggerRes.triggerType == BattleTriggerType.ATTACKHITEND or self.triggerRes.triggerType == BattleTriggerType.SPELLHITEND)
				for n = 1, #jhBufferList do
					if n > copyCount then
						break
					end
					self.battleHero:AddBuffer(jhBufferList[n], self.battleHero, isActionEnd, isActionEnd and _triggerTargetHeroes or nil)
				end
			end
		end
	end

	return isTriggered
end

-- 反噬
function ActionTrigger:ExecFanShi( _triggerParam, _targetHeroes, ... )
	-- 校验触发概率
	if not self:CheckTriggerRate(true) then
		return false
	end

	local attackerHero = _triggerParam.attackerHero
	local attackDamage = _triggerParam.attackDamage + _triggerParam.extraDamage
	local fsDamage = attackDamage * (ToInt(self.actionRes.value) * s_PercentScale)
	attackerHero:OnAttackDamage(self.battleHero, SkillType.TALENT, nil, fsDamage)
end

local BaseTriggerSkillTypeValue = { 1, 10, 100, 1000 }
local BaseTriggerSkillEffectTypeValue = { 1, 10, 100 }

-- 校验触发条件，返回参数1当前是否符合条件 参数2是否连续触发
function ActionTrigger:CheckCondition( _triggerParam, ... )
	if gBattleManager.roundNum < self.triggerRes.startRound then
		return false, false
	end

	-- 校验触发技能类型
	if self.triggerRes.triggerSkillType ~= SkillType.ALL and _triggerParam.triggerSkillType ~= SkillType.ALL then
		local baseValue = BaseTriggerSkillTypeValue[_triggerParam.triggerSkillType]
		if ToInt(self.triggerRes.triggerSkillType / baseValue) % 2 == 0 then
			return false, false
		end
	end

	-- 校验触发技能作用类型
	if self.triggerRes.triggerEffectType ~= SkillEffectType.ALL and _triggerParam.triggerSkillEffectType ~= SkillEffectType.ALL then
		local baseValue = BaseTriggerSkillEffectTypeValue[_triggerParam.triggerSkillEffectType]
		if ToInt(self.triggerRes.triggerEffectType / baseValue) % 2 == 0 then
			return false, false 
		end
	end

	local triggerHero = _triggerParam.triggerHero
	if self.triggerRes.triggerHeroType == TriggerHeroType.ATTACKER then
		triggerHero = _triggerParam.attackerHero
	elseif self.triggerRes.triggerHeroType == TriggerHeroType.TARGET and #_triggerParam.targetHeroes >= 1 then
		triggerHero = _triggerParam.targetHeroes[1]
	end

	if not triggerHero then
		return false, false
	end

	-- 真实触发英雄
	self.realTriggerHero = triggerHero

	-- 校验是否超过触发次数上限
	if triggerHero:IsTriggerFireOverTimes(self.triggerRes, self.triggerId) then
		return false, false
	end

	-- 血量降低判定
	local isNeedFireTwice = false
	if self.triggerRes.triggerType == BattleTriggerType.SUBHP and self.triggerRes.maxTriggerTimes ~= 0 then
		local triggerTimes = triggerHero:GetTriggerFireTimes(self.triggerRes, self.triggerId)
		local triggerValue = ToInt(self.triggerRes.triggerValue)
		local startHPPer = self.triggerRes.maxTriggerTimes * triggerValue
		isNeedFireTwice = startHPPer - (triggerTimes + 2) * triggerValue >= triggerHero.heroData.curHPPercent
		if startHPPer - (triggerTimes + 1) * triggerValue < triggerHero.heroData.curHPPercent then
			return false, false
		end
	end
	
	-- 校验触发单位是否符合类型
	if not self:CheckTriggerTarget(triggerHero, _triggerParam.attackerHero) then
		return false, false
	end
	
	-- 触发类型判定
	if not self:CheckTrigger(triggerHero, _triggerParam) then
		return false, false
	end

	-- 特殊逻辑校验
	if not self:CheckSpecialTriggerLogic(triggerHero) then
		return false, false
	end

	return true, isNeedFireTwice
end

-- 目标判定枚举
local TriggerTargetSwitcher = 
{
	-- 自己
	[BattleTargetType.SELF] = function( _battleHero, _triggerHero, _attackerHero, ... )
		return _triggerHero.heroId == _battleHero.heroId
	end,
	-- 友方
	[BattleTargetType.FRIEND] = function( _battleHero, _triggerHero, _attackerHero, ... )
		return _triggerHero.heroCamp == _battleHero.heroCamp
	end,
	-- 敌人
	[BattleTargetType.ENEMY] = function( _battleHero, _triggerHero, _attackerHero, ... )
		return _triggerHero.heroCamp ~= _battleHero.heroCamp
	end,
	-- 友方排除自己
	[BattleTargetType.FRIENDNOTME] = function( _battleHero, _triggerHero, _attackerHero, ... )
		return _triggerHero.heroCamp == _battleHero.heroCamp and _triggerHero.heroId ~= _battleHero.heroId
	end,
	-- 敌方攻击目标
	[BattleTargetType.ENEMYTARGETS] = function( _battleHero, _triggerHero, _attackerHero, ... )
		if not _attackerHero  then
			return false
		end
		-- 必须是敌方阵营
		if _triggerHero.heroCamp == _battleHero.heroCamp then
			return false
		end
		-- 触发器英雄攻击
		local targetHeroes = gBattleAction:GetCurTargetHeroes()
		for i = 1, #targetHeroes do
			if _attackerHero.heroId == _battleHero.heroId and _triggerHero.heroId == targetHeroes[i].heroId then
				return true
			end
		end
		-- 触发器英雄被击
		if _attackerHero.heroId ~= _battleHero.heroId and _triggerHero.heroId == _attackerHero.Id and self.battleHero.heroId == gBattleAction.curTargetHero.heroId then
			return true
		end
		return false
	end,
	-- 攻击目标
	[BattleTargetType.TARGETS] = function( _battleHero, _triggerHero, _attackerHero, ... )
		if not _attackerHero  then
			return false
		end
		-- 触发器英雄攻击
		local targetHeroes = gBattleAction:GetCurTargetHeroes()
		for i = 1, #targetHeroes do
			if _attackerHero.heroId == _battleHero.heroId and _triggerHero.heroId == targetHeroes[i].heroId then
				return true
			end
		end
		-- 触发器英雄被击
		if _attackerHero.heroId ~= _battleHero.heroId and _triggerHero.heroId == _attackerHero.Id and self.battleHero.heroId == gBattleAction.curTargetHero.heroId then
			return true
		end
		return false
	end,
	-- 任意单位
	[BattleTargetType.ALL] = function( ... )
		return true
	end
}

-- 校验触发单位是否符合类型
function ActionTrigger:CheckTriggerTarget( _triggerHero, _attackerHero, ... )
	-- 目标判定
	local targetType = self.triggerRes.targetType
	local targetExecutor = TriggerTargetSwitcher[targetType]
	if targetExecutor then
		return targetExecutor(self.battleHero, _triggerHero, _attackerHero)
	end
	
	return false
end

-- 触发逻辑判定
local TriggerSwitcher = 
{
	-- 添加移除状态
	[BattleTriggerType.BUFFER] = function( self, _triggerParam )
		return self.triggerRes.triggerValue == _triggerParam.triggerValue
	end,
	-- 回合开始
	[BattleTriggerType.ROUNDSTART] = function( self, _triggerParam, ... )
		if self.triggerRes.triggerValue == '0' then
			return true
		end
		return self.triggerRes.triggerValue == tostring(_triggerParam.triggerValue)
	end,
	-- 回合结束
	[BattleTriggerType.ROUNDEND] = function( self, _triggerParam, ... )
		if self.triggerRes.triggerValue == '0' then
			return true
		end
		return self.triggerRes.triggerValue == tostring(_triggerParam.triggerValue)
	end,
	-- 行动开始
	[BattleTriggerType.ACTIONBEGIN] = function( self, _triggerParam, ... )
		if self.triggerRes.triggerValue == '0' then
			return true
		end
		return self.triggerRes.triggerValue == tostring(_triggerParam.triggerValue)
	end,
	-- 行动结束
	[BattleTriggerType.ACTIONEND] = function( self, _triggerParam, ... )
		if self.triggerRes.triggerValue == '0' then
			return true
		end
		return self.triggerRes.triggerValue == tostring(_triggerParam.triggerValue)
	end,
	-- 技能开始
	[BattleTriggerType.SKILLBEGIN] = function( self, _triggerParam, ... )
		if self.triggerRes.triggerValue == '0' then
			return true
		end
		return self.triggerRes.triggerValue == tostring(_triggerParam.triggerValue)
	end
}

-- 触发逻辑判定
function ActionTrigger:CheckTrigger( _triggerHero, _triggerParam, ... )
	-- 触发类型
	local triggerType = self.triggerRes.triggerType
	local triggerExecutor = TriggerSwitcher[triggerType]
	if triggerExecutor then
		return triggerExecutor(self, _triggerParam)
	end
	
	return true
end

-- 特殊逻辑判定枚举
local SpecialLogicSwitcher = 
{
	-- 血量低于 高于
	[TriggerSpecialLogicType.HPPER] = function( _triggerHero, _valueList, ... )
		return  _valueList[1] >= 0 and _triggerHero.heroData.curHPPercent >= _valueList[1] or _triggerHero.heroData.curHPPercent < -_valueList[1]
	end,
	-- 怒气低于 高于
	[TriggerSpecialLogicType.FURY] = function( _triggerHero, _valueList, ... )
		return _valueList[1] >= 0 and _triggerHero.heroData.fury >= _valueList[1] or _triggerHero.heroData.fury < -_valueList[1]
	end,
	-- 状态标记
	[TriggerSpecialLogicType.HEROFLAG] = function( _triggerHero, _valueList, ... )
		for i = 1, #_valueList do
			if (_valueList[i] > 0 and _triggerHero:HasHeroFlag(_valueList[i])) or (_valueList[i] < 0 and not _triggerHero:HasHeroFlag(-_valueList[i])) then
				return true
			end
		end
		return false
	end,
	-- 站位
	[TriggerSpecialLogicType.HEROPOS] = function( _triggerHero, _valueList, ... )
		for i = 1, #_valueList do
			if (_valueList[i] > 0 and _triggerHero.heroPosRes.posType == _valueList[i]) or (_valueList[i] < 0 and _triggerHero.heroPosRes.posType ~= -_valueList[i]) then
				return true
			end
		end
		return false
	end,
	-- 职业
	[TriggerSpecialLogicType.MAJOR] = function( _triggerHero, _valueList, ... )
		for i = 1, #_valueList do
			if (_valueList[i] > 0 and _triggerHero.heroRes.major == _valueList[i]) or (_valueList[i] < 0 and _triggerHero.heroRes.major ~= -_valueList[i]) then
				return true
			end
		end
		return false
	end,
	-- 种族
	[TriggerSpecialLogicType.RACE] = function( _triggerHero, _valueList, ... )
		for i = 1, #_valueList do
			if (_valueList[i] > 0 and _triggerHero.heroRes.race == _valueList[i]) or (_valueList[i] < 0 and _triggerHero.heroRes.race ~= -_valueList[i]) then
				return true
			end
		end
		return false
	end,
	-- 携带Buffer
	[TriggerSpecialLogicType.BUFFER] = function( _triggerHero, _valueList, ... )
		for i = 1, #_valueList do
			if (_valueList[i] > 0 and _triggerHero:HasBuffer(_valueList[i])) or (_valueList[i] < 0 and not _triggerHero:HasBuffer(-_valueList[i])) then
				return true
			end
		end
		return false
	end,
}

-- 校验特殊触发逻辑
function ActionTrigger:CheckSpecialTriggerLogic( _triggerHero, ... )
	-- 特殊逻辑
	local specialLogicType = self.triggerRes.specialLogic
	local specialLogicExecutor = SpecialLogicSwitcher[specialLogicType]
	if specialLogicExecutor then
		return specialLogicExecutor(_triggerHero, self.triggerRes.specialLogicValue)
	end
	
	return true
end

-- 校验触发概率
function ActionTrigger:CheckTriggerRate( isFanTan,... )
	local triggerRate = self.triggerRes.triggerRate
	return (triggerRate == s_PercentMax or triggerRate == 0 or gBattleRandNum:NextInt(s_PercentMax) <= triggerRate)
end
	
classend()


-- 触发参数
class('TriggerParam')

function TriggerParam:ctor( _triggerSkillType, _triggerSkillEffectType, _triggerHero, _attackerHero, _targetHeroes, _attackDamage, _triggerHeroHP, _triggerValue, ... )
	self.triggerHero = NilDefault(_triggerHero, false)		-- 触发英雄
	self.attackerHero = NilDefault(_attackerHero, false)	-- 攻击英雄
	self.targetHeroes = TableDefault(_targetHeroes, {})		-- 目标英雄列表
	self.attackDamage = NilDefault(_attackDamage, 0)		-- 触发时伤害
	self.triggerHeroHP = NilDefault(_triggerHeroHP, false)	-- 触发英雄血量
	self.damageScale = 0									-- 伤害加成
	self.extraDamage = 0									-- 额外伤害
	self.triggerValue = NilDefault(_triggerValue, '0')		-- 触发器参数值
	self.triggerSkillType = NilDefault(_triggerSkillType, SkillType.ALL)  										-- 触发技能类型
	self.triggerSkillEffectType = NilDefault(_triggerSkillEffectType, SkillEffectType.ALL)  					-- 触发技能作用类型
end

classend()