---
--- class BattleTriggerAction
-- @classmod BattleTriggerAction
class('BattleTriggerAction')

local math_floor = math.floor
local os_clock = os.clock
local FLAGMAP = Utils.BuildFlagMap

---Constructor
function BattleTriggerAction:ctor( _battleUnit, _owner, _actionRes, _triggerRes, _triggerId, ... )
	self.triggerId = _triggerId or 0
	self.battleUnit = _battleUnit or false
	self.owner = _owner or false					-- 所有者，{ unitId, player }
	self.actionRes = _actionRes or false
	self.triggerRes = _triggerRes or false
	self.isRemove = false
	self.node = false
end

-- 触发行为枚举
local TriggerActionSwitcher = 
{
	-- 伤害
	[BattleActionType.DAMAGE] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecDamage(_triggerParam, _targetUnits)
	end,
	-- 额外伤害
	[BattleActionType.EXTRADAMAGE] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecExtraDamage(_triggerParam, _targetUnits)
	end,
	-- 状态
	[BattleActionType.BUFFER] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecBuffer(_triggerParam, _targetUnits)
	end,
	-- 移除Buffer
	[BattleActionType.REMOVEBUFFER] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecRemoveBuffer(_triggerParam, _targetUnits)
	end,
	-- 生成碰撞体
	[BattleActionType.COLLIDER] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecCollider(_triggerParam, _targetUnits)
	end,
	-- 生成塔
	[BattleActionType.TOWER] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecAddTower(_triggerParam, _targetUnits)
	end,
	-- 生成怪物
	[BattleActionType.MONSTER] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecAddMonster(_triggerParam, _targetUnits)
	end,
	-- 秒杀
	[BattleActionType.SECKILL] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecSecKill(_triggerParam, _targetUnits)
	end,
	-- 塔点数
	[BattleActionType.STAR] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecStar(_triggerParam, _targetUnits)
	end,
	-- 移除单位
	[BattleActionType.REMOVEUNIT] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecRemoveUnit(_triggerParam, _targetUnits)
	end,
	-- 添加SP
	[BattleActionType.POINT] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecAddPoint(_triggerParam, _targetUnits)
	end,
	-- 替换目标
	[BattleActionType.REPLACETARGET] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecReplaceTarget(_triggerParam, _targetUnits)
	end,
	-- 瞬移
	[BattleActionType.TELEPORT] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecTeleport(_triggerParam, _targetUnits)
	end,
	-- 偷取SP
	[BattleActionType.STEALSP] = function( self, _triggerParam, _targetUnits, ... )
		return self:ExecStealSP(_triggerParam, _targetUnits)
	end
}

-- 触发行为
T_ACTION = 0
function BattleTriggerAction:FireTrigger( _triggerParam, ... )
	-- 校验是否有已经缓存战斗帧
	if self:CheckPendingFrame(_triggerParam) then
		return false
	end
	if not self:CheckCondition(_triggerParam) then
		return false
	end
	local actionType = self.actionRes.actionType
	local targetUnits = BattleTarget.FindTarget(self.actionRes.targetId, self.battleUnit, _triggerParam.targetUnits, _triggerParam.attackerUnit, _triggerParam.triggerUnit)
	if not targetUnits or #targetUnits == 0 then
		return false
	end
	-- 执行行为
	local switcher = TriggerActionSwitcher[actionType]
	if switcher then
		if switcher(self, _triggerParam, targetUnits) then
			-- 行为执行成功
			local eventName = self.actionRes.eventName
			if eventName ~= '' then
				-- 通知前端单位事件
				local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.UNITEVENT, self.battleUnit.unitId, eventName)
			end
		end
	end
	return true
end

-- 校验触发条件
function BattleTriggerAction:CheckCondition( _triggerParam, ... )
	if not self.triggerRes or self.triggerRes.triggerType == 0 then
		return true
	end

	local triggerUnit = _triggerParam.triggerUnit
	local attackerUnit = _triggerParam.attackerUnit
	local triggerPlayer = triggerUnit.player

	-- 校验触发参数
	if not self:CheckTriggerValue(_triggerParam) then
		return false
	end
	-- 校验触发玩家
	if not self:CheckTriggerPlayer(triggerPlayer) then
		return false
	end
	-- 校验触发单位
	if not self:CheckTriggerUnit(triggerUnit) then
		return false
	end
	-- 校验触发目标
	if not self:CheckTriggerTarget(triggerUnit, attackerUnit) then
		return false
	end
	return true
end

-- 触发玩家判定
local TriggerPlayerSwitcher = 
{
	-- 所有玩家
	[BattlePlayerType.ALL] = function( _battlePlayer, _triggerPlayer, ... )
		return true
	end,
	-- 自己
	[BattlePlayerType.SELF] = function( _battlePlayer, _triggerPlayer, ... )
		return _battlePlayer.playerId == _triggerPlayer.playerId
	end,
	-- 对手
	[BattlePlayerType.OPPONENT] = function( _battlePlayer, _triggerPlayer, ... )
		return _battlePlayer.playerId ~= _triggerPlayer.playerId
	end
}

-- 校验触发玩家
function BattleTriggerAction:CheckTriggerPlayer( _triggerPlayer,  ... )
	local triggerPlayerType = self.triggerRes.triggerPlayerType
	local switcher = TriggerPlayerSwitcher[triggerPlayerType]
	if switcher then
		return switcher(self.battleUnit.player, _triggerPlayer)
	end
	return false
end

-- 校验触发单位
function BattleTriggerAction:CheckTriggerUnit( _triggerUnit, ... )
	if self.triggerRes.triggerUnitType == BattleUnitType.ALL then
		return true
	end
	return _triggerUnit.unitType == self.triggerRes.triggerUnitType
end

-- 触发目标判定
local TriggerTargetSwitcher = 
{
	-- 任意单位
	[BattleTargetType.ALL] = function( _battleUnit, _triggerUnit, _attackerUnit, ... )
		return true
	end,
	-- 自己
	[BattleTargetType.SELF] = function( _battleUnit, _triggerUnit, _attackerUnit, ... )
		return _battleUnit.unitId == _triggerUnit.unitId
	end,
}

-- 校验触发目标关系
function BattleTriggerAction:CheckTriggerTarget( _triggerUnit, _attackerUnit, ... )
	local targetType = self.triggerRes.triggerTargetType
	local switcher = TriggerTargetSwitcher[targetType]
	if switcher then
		return switcher(self.battleUnit, _triggerUnit, _attackerUnit)
	end
	return false
end

-- 触发参数判定
local TriggerValueSwitcher = 
{
	-- 状态添加移除
	[BattleTriggerType.BUFFER] = function( self, _triggerParam, ... )
		return self.triggerRes.value == _triggerParam.triggerValue
	end,
	-- 攻击
	[BattleTriggerType.ATTACK] = function( self, _triggerParam, ... )
		if self.triggerRes.value == '0' then
			return true
		end
		local value = tonumber(self.triggerRes.value)
		if value > 0 then
			local starIndex = _triggerParam.triggerValue.starIndex
			return starIndex == value
		end
		local attackTimes = _triggerParam.triggerValue.attackTimes
		return attackTimes % (-value) == 0
	end,
	-- 额外攻击
	[BattleTriggerType.EXATTACK] = function( self, _triggerParam, ... )
		if self.triggerRes.value == '0' then
			return true
		end
		local value = tonumber(self.triggerRes.value)
		if value > 0 then
			local starIndex = _triggerParam.triggerValue.starIndex
			return starIndex == value
		end
		local attackTimes = _triggerParam.triggerValue.attackTimes
		return attackTimes % (-value) == 0
	end,
	-- 总星级比较
	[BattleTriggerType.TOTALSTAR] = function( self, _triggerParam, ... )
		return _triggerParam.triggerValue == self.triggerRes.value
	end,
	-- 离场
	[BattleTriggerType.LEAVE] = function( self, _triggerParam, ... )
		local leaveType = tonumber(self.triggerRes.value)
		if leaveType == BattleUnitLeaveType.ALL then
			return true
		end
		return _triggerParam.triggerValue[leaveType] == 1
	end
}

-- 校验触发参数
function BattleTriggerAction:CheckTriggerValue( _triggerParam, ... )
	local triggerType = self.triggerRes.triggerType
	local switcher = TriggerValueSwitcher[triggerType]
	if switcher then
		return switcher(self, _triggerParam)
	end
	return true
end

-- 校验触发概率
function BattleTriggerAction:CheckTriggerRate( _randNum, ... )
	if not self.triggerRes then
		return true
	end
	local formulaId = self.triggerRes.triggerRate
	local triggerRate = BattleFormula.GetValue(formulaId, self.battleUnit, nil)
	local randNum = _randNum or gBattleRandNum
	return (triggerRate == s_PercentMax or triggerRate == 0 or randNum:NextInt(s_PercentMax) <= triggerRate)
end

-- 校验是否有战斗帧缓存
function BattleTriggerAction:CheckPendingFrame( _triggerParam, ... )
	local frame = _triggerParam.triggerFrame
	if not frame then
		return false
	end
	local isLogic = _triggerParam.isLogic
	local needPending = not isLogic
	local isPended = self.battleUnit.player:CheckPendingFrame(frame, needPending)
	if isPended then
		return true
	end
	return false
end

-- 伤害
function BattleTriggerAction:ExecDamage( _triggerParam, _targetUnits, ... )
	-- 只对怪物造成伤害
	if _targetUnits[1].unitType ~= BattleUnitType.MONSTER then
		return false
	end
	if not self:CheckTriggerRate(_triggerParam.randNum) then
		return false
	end
	local formulaId = tonumber(self.actionRes.value)
	local damage = 0
	if formulaId == 0 then
		damage = self.battleUnit:GetAttack()
	end
	local count = #_targetUnits
	for i = 1, count do
		local target = _targetUnits[i]
		if formulaId ~= 0 then
			damage = BattleFormula.GetValue(formulaId, self.battleUnit, target, i)
		end
		target:OnAttackDamage(self.battleUnit, damage, nil, self.actionRes.effectId)
	end
	return true
end

-- 额外伤害
function BattleTriggerAction:ExecExtraDamage( _triggerParam, _targetUnits, ... )
	-- 只对怪物造成伤害
	if _targetUnits[1].unitType ~= BattleUnitType.MONSTER then
		return false
	end
	if not self:CheckTriggerRate(_triggerParam.randNum) then
		return false
	end
	local formulaId = tonumber(self.actionRes.value)
	local damage = BattleFormula.GetValue(formulaId, self.battleUnit, _targetUnits[1])
	_triggerParam.extraDamage = _triggerParam.extraDamage + damage
	return true
end

-- 增加状态
function BattleTriggerAction:ExecBuffer( _triggerParam, _targetUnits, ... )
	local bufferId = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	local owner = self.owner and self.owner or self.battleUnit
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			_targetUnits[i]:AddBuffer(bufferId, owner)
			isTriggered = true
		end
	end
	return isTriggered
end

-- 移除状态
function BattleTriggerAction:ExecRemoveBuffer( _triggerParam, _targetUnits, ... )
	local result = Split(self.actionRes.value, '|')
	local bufferResId = tonumber(result[1])
	local layerCount = result[2] and tonumber(result[2]) or 0
	local isTriggered = false
	local owner = self.owner and self.owner or self.battleUnit
	for i = 1, #_targetUnits do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			_targetUnits[i]:RemoveBufferLayer(bufferResId, owner, layerCount)
			isTriggered = true
		end
	end
	return isTriggered
end

-- 生成碰撞体
function BattleTriggerAction:ExecCollider( _triggerParam, _targetUnits, ... )
	local result = Split(self.actionRes.value, '|')
	local colliderResId = tonumber(result[1])
	local colliderCount = result[2] and tonumber(result[2]) or 1
	local count = #_targetUnits
	local isTriggered = false
	local owner = self.owner and self.owner or self.battleUnit
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			for n = 1, colliderCount do
				_targetUnits[i].player:AddCollider(colliderResId, owner, _triggerParam.triggerUnit)
			end
			isTriggered = true
		end
	end
	return isTriggered
end

-- 生成怪物
function BattleTriggerAction:ExecAddMonster( _triggerParam, _targetUnits, ... )
	local result = Split(self.actionRes.value, '|')
	local monsterResId = tonumber(result[1])
	local monsterCount = BattleFormula.GetValue(tonumber(result[2] or 1), self.battleUnit)
	local maxPosition = tonumber(result[3] or 0)
	local isTriggered = false

	for i = 1, #_targetUnits do
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local player = _targetUnits[i].player
			for n = 1, monsterCount do
				local position = maxPosition ~= 0 and gBattleRandNum:NextInt(maxPosition) or 0
				position = position * BattleConstants.BATTLE_ROAD_LENGTH / Constants.PERCENT_MAX
				player:AddMonster(monsterResId, nil, position)
			end
			isTriggered = true
		end
	end
	return isTriggered
end

-- 生成塔
function BattleTriggerAction:ExecAddTower( _triggerParam, _targetUnits, ... )
	local addType = tonumber(self.actionRes.value)
	local star = 1
	local posIndex = 0
	local towerRes = false
	local isTriggered = false
	if addType == BattleTowerAddType.ALL then
		for i = 1, #_targetUnits do
			-- 校验触发概率
			if self:CheckTriggerRate(_triggerParam.randNum) then
				local player = _targetUnits[i].player
				posIndex = player:RandomTowerPosIndex(gBattleRandNum)
				if posIndex ~= 0 then
					local towerResId = player:RandomTowerResId(gBattleRandNum)
					towerRes = GameResMgr.GetBattleTowerRes(towerResId)
					if towerRes then
						player:AddTowerByFrame(nil, towerRes, star, posIndex, false, BattleTowerAddType.ALL)
						isTriggered = true
					end
				end
			end
		end
	elseif addType == BattleTowerAddType.GROWUP then
		if _triggerParam.triggerUnit.star == Constants.BATTLE_MAX_STAR then
			return false
		end
		for i = 1, #_targetUnits do
			-- 校验触发概率
			if self:CheckTriggerRate(_triggerParam.randNum) then
				local player = _targetUnits[i].player
				posIndex = _triggerParam.triggerUnit.posIndex
				if posIndex ~= 0 then
					local towerResId = player:RandomTowerResId(gBattleRandNum)
					towerRes = GameResMgr.GetBattleTowerRes(towerResId)
					if towerRes then
						star = _triggerParam.triggerUnit.star + 1
						player:RemoveTowerByFrame(nil, posIndex, FLAGMAP(BattleUnitLeaveType.GROWUP))
						player:AddTowerByFrame(nil, towerRes, star, posIndex, false, BattleTowerAddType.GROWUP)
						isTriggered = true
					end
				end
			end
		end
	end
	return isTriggered
end

-- 秒杀
function BattleTriggerAction:ExecSecKill( _triggerParam, _targetUnits, ... )
	local isTriggered = false
	local formulaId = tonumber(self.actionRes.value)
	local secKillRate = BattleFormula.GetValue(formulaId, self.battleUnit, nil)
	for i = 1, #_targetUnits do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local targetMonster = _targetUnits[i]
			local damage = self.battleUnit:CalcDamage(0, targetMonster, false, secKillRate)
			if damage > 0 then
				targetMonster:OnAttackDamage(self.battleUnit, damage, true)
				isTriggered = true
			end
		end
	end
	return isTriggered
end

-- 塔加减点数
function BattleTriggerAction:ExecStar( _triggerParam, _targetUnits, ... )
	local change = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local unit = _targetUnits[i]
			if unit.unitType == BattleUnitType.TOWER then
				unit.player:ChangeTowerStar(unit, change, _triggerParam.triggerFrame, _triggerParam.isLogic)
				isTriggered = true
			end
		end
	end
	return isTriggered
end

-- 移除单位
function BattleTriggerAction:ExecRemoveUnit( _triggerParam, _targetUnits, ... )
	local leaveType = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local unit = _targetUnits[i]
			unit.player:RemoveUnit(unit, FLAGMAP(leaveType))

			isTriggered = true
		end
	end
	return isTriggered
end

-- 添加SP
function BattleTriggerAction:ExecAddPoint( _triggerParam, _targetUnits, ... )
	local formulaId = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local unit = _targetUnits[i]
			local point = BattleFormula.GetValue(formulaId, unit, unit)
			unit.player:AddPoint(point)

			-- 通知前端添加SP
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.DAMAGE, unit.unitId, point, BattleDamageType.POINT)

			isTriggered = true
		end
	end
	return isTriggered
end

-- 替换目标
function BattleTriggerAction:ExecReplaceTarget( _triggerParam, _targetUnits, ... )
	local targetId = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			local unit = _targetUnits[i]
			if unit.unitType == BattleUnitType.TOWER then
				unit.replaceTargetId = targetId
			end
			isTriggered = true
		end
	end
	return isTriggered
end

-- 瞬移
function BattleTriggerAction:ExecTeleport( _triggerParam, _targetUnits, ... )
	local distance = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		local targetMonster = _targetUnits[i]
		-- 校验触发概率
		if (distance ~= 0 or not targetMonster:HasUnitFlag(BattleUnitFlag.TELEPORTED)) and self:CheckTriggerRate(_triggerParam.randNum) and not targetMonster:CheckAttributeIgnore(AttriType.TELEPORT) then
			isTriggered = true
			-- 设置位置
			local position = distance == 0 and 0 or (targetMonster.position + distance)
			position = position < 0 and 0 or position
			targetMonster:SetPosition(position, -1)
			-- 添加瞬移标记
			if distance == 0 then
				targetMonster:AddBuffer(Constants.BATTLE_TELEPORTED_BUFFER, targetMonster)
			end
		end
	end
	return isTriggered
end

-- 偷取SP
function BattleTriggerAction:ExecStealSP( _triggerParam, _targetUnits, ... )
	local point = tonumber(self.actionRes.value)
	local count = #_targetUnits
	local isTriggered = false
	for i = 1, count do
		-- 校验触发概率
		if self:CheckTriggerRate(_triggerParam.randNum) then
			self.battleUnit.player:StealPoint(_targetUnits[i].player, point)
			isTriggered = true
		end
	end
	return isTriggered
end

classend()