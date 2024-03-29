---
--- class BattleTarget
-- @classmod BattleTarget
BattleTarget = xclass('BattleTarget')

local table_insert = table.insert
local table_remove = table.remove

local GetTargetPlayer = false
local FindFrontMonster = false
local FindBackMonster = false
local FindMaxHPMonster = false
local FindMinHPMonster = false
local RandomTargets = false
local FindRandomUnit = false
local FindSubRangeTarget = false
local FindSubLinkTarget = false
local FindSubCrossTarget = false
local FindSubCrossGridTarget = false
local CheckCondition = false
local CheckTargetsCondition = false
local FindTarget = false

local TargetSwitcher = 
{
	-- 首位，只限怪物
	[BattleTargetType.FRONT] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindFrontMonster(_targetRes, _player, _targetCount)
	end,
	-- 末位，只限怪物
	[BattleTargetType.BACK] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindBackMonster(_targetRes, _player, _targetCount)
	end,
	-- 最大血量，只限怪物
	[BattleTargetType.MAXHP] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindMaxHPMonster(_targetRes, _player, _targetCount)
	end,
	-- 最小血量，只限怪物
	[BattleTargetType.MINHP] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindMinHPMonster(_targetRes, _player, _targetCount)
	end,
	-- 随机
	[BattleTargetType.RANDOM] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindRandomUnit(_targetRes, _player, _targetCount, true)
	end,
	-- 所有
	[BattleTargetType.ALL] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindRandomUnit(_targetRes, _player, _targetCount, false)
	end,
	-- 目标
	[BattleTargetType.TARGET] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return CheckTargetsCondition(_targetRes, _defaultTargets or {})
	end,
	-- 触发者
	[BattleTargetType.TRIGGER] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return CheckTargetsCondition(_targetRes, { _triggerUnit })
	end,
	-- 自己
	[BattleTargetType.SELF] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return { _battleUnit }
	end
}

local TargetSubSwitcher = 
{
	-- 范围
	[BattleTargetSubType.RANGE] = function( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
		return FindSubRangeTarget(_battleUnit, _targetRes, _player, _targets, _targetCount)
	end,
	-- 连接
	[BattleTargetSubType.LINK] = function( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
		return FindSubLinkTarget(_battleUnit, _targetRes, _player, _targets, _targetCount)
	end,
	-- 十字
	[BattleTargetSubType.CROSS] = function( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
		return FindSubCrossTarget(_battleUnit, _targetRes, _player, _targets, _targetCount)
	end,
	-- 十字格子
	[BattleTargetSubType.CROSSGRID] = function( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
		return FindSubCrossGridTarget(_battleUnit, _targetRes, _player, _targets, _targetCount)
	end,
}

local TargetPlayerSwitcher = 
{
	-- 自己
	[BattlePlayerType.SELF] = function( _player, ... )
		return _player
	end,
	-- 对手
	[BattlePlayerType.OPPONENT] = function( _player, ... )
		return gBattleRecord.playerList[_player.playerIndex % 2 + 1]
	end
}

local AllTargetUnitSwitcher = 
{
	-- 玩家
	[BattleUnitType.PLAYER] = function( _targets, _player, _isRandom, ... )
		if _isRandom then
			for i = 1, #gBattleRecord.playerList do
				table_insert(_targets, gBattleRecord.playerList[i])
			end
		else
			table_insert(_targets, _player)
		end
		return _targets
	end,
	-- 塔
	[BattleUnitType.TOWER] = function( _targets, _player, _isRandom, _baseId, ... )
		for i = 1, #_player.towerList do
			local tower = _player.towerList[i]
			if tower and (_baseId == 0 or tower.towerRes.baseId == _baseId) then
				table_insert(_targets, tower)
			end
		end
		return _targets
	end,
	-- 格子
	[BattleUnitType.GRID] = function( _targets, _player, ... )
		for i = 1, #_player.gridList do
			local grid = _player.gridList[i]
			table_insert(_targets, grid)
		end
		return _targets
	end,
	-- 怪物
	[BattleUnitType.MONSTER] = function( _targets, _player, ... )
		local monsterList = _player.monsterList
		for i = 1, #monsterList do
			local monster = monsterList[i]
			if monster:IsValid() then
				table_insert(_targets, monster)
			end
		end
		return _targets
	end,
	-- 碰撞物
	[BattleUnitType.COLLIDER] = function( _targets, _player, ... )
		local node = _player.colliderList.first
		while node do
			if node.value:IsValid() then
				table_insert(_targets, node.value)
			end
			node = node.next
		end
		return _targets
	end,
	-- 英雄
	[BattleUnitType.HERO] = function( _targets, _player, ... )
		return _player.hero
	end
}

function BattleTarget.FindTarget( _targetId, _battleUnit, _defaultTargets, _attackerUnit, _triggerUnit, ... )
	if not _battleUnit then
		return false
	end
	local targetRes = GameResMgr.GetBattleTargetRes(_targetId)
	if not targetRes then
		return FindFrontMonster(targetRes, _battleUnit.player, 1)
	end
	local player = GetTargetPlayer(_battleUnit.player, targetRes.targetPlayerType)
	if not player then
		return false
	end
	local targets = {}
	local switcher = TargetSwitcher[targetRes.targetType]
	if switcher then
		local targetCount = BattleFormula.GetValue(targetRes.countId, _battleUnit, nil)
		targets = switcher(targetRes, _battleUnit, player, targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ...)
	end

	switcher = TargetSubSwitcher[targetRes.targetSubType]
	if switcher then
		local subTargetCount = BattleFormula.GetValue(targetRes.subCountId, _battleUnit, nil)
		targets = switcher(_battleUnit, targetRes, player, targets, subTargetCount)
	end

	return targets
end
FindTarget = BattleTarget.FindTarget

function BattleTarget.CheckCondition( _targetRes, _targetUnit, ... )
	if not _targetRes then
		return true
	end
	local targetFlag = _targetRes.targetFlag
	if targetFlag ~= 0 then
		if targetFlag > 0 and not HasBattleFlag(_targetUnit.unitFlag, targetFlag) then
			return false
		end
		if targetFlag < 0 and HasBattleFlag(_targetUnit.unitFlag, -targetFlag) then
			return false
		end
	end
	return true
end
CheckCondition = BattleTarget.CheckCondition

function BattleTarget.CheckTargetsCondition( _targetRes, _targets, ... )
	if not _targetRes or _targetRes.targetFlag == 0 then
		return _targets
	end
	local targets = {}
	for i = 1, #_targets do
		local target = _targets[i]
		if CheckCondition(_targetRes, target) then
			table_insert(targets, target)
		end
	end
	return targets
end
CheckTargetsCondition = BattleTarget.CheckTargetsCondition

function BattleTarget.FindFrontMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	local monster = false
	local monsterList = _player.monsterList
	local monsterCount = #monsterList
	for i = 1, monsterCount do
		monster = monsterList[i]
		if monster:IsValid() and CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
			if #targets >= targetCount then
				break
			end
		end
	end
	if _targetRes and monsterCount > 0 and #targets == 0 then
		return FindFrontMonster(false, _player, _targetCount)
	end
	return targets
end
FindFrontMonster = BattleTarget.FindFrontMonster

function BattleTarget.FindBackMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	local monster = false
	local monsterList = _player.monsterList
	local monsterCount = #monsterList
	for i = monsterCount, 1, -1 do
		monster = monsterList[i]
		if monster:IsValid() and CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
			if #targets >= targetCount then
				break
			end
		end
	end
	if _targetRes and monsterCount > 0 and #targets == 0 then
		return FindBackMonster(false, _player, _targetCount)
	end
	return targets
end
FindBackMonster = BattleTarget.FindBackMonster

function BattleTarget.FindMaxHPMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	if CheckCondition(_targetRes, _player.maxHPMonster) then
		table_insert(targets, _player.maxHPMonster)
	end
	return targets
end
FindMaxHPMonster = BattleTarget.FindMaxHPMonster

function BattleTarget.FindMinHPMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	if CheckCondition(_targetRes, _player.minHPMonster) then
		table_insert(targets, _player.minHPMonster)
	end
	return targets
end
FindMinHPMonster = BattleTarget.FindMinHPMonster

function BattleTarget.RandomTargets( _targets, _targetCount )
	local count = #_targets
	if _targetCount >= count then
		return _targets
	end
	-- 随机索引列表
	local targets = {}
	gBattleRandNum:ClearUniqueRecord(UniqueRandType.TARGET)
	for i = 1, _targetCount do
		local index = gBattleRandNum:NextUniqueInt(UniqueRandType.TARGET, count)
		table_insert(targets, _targets[index])
	end
	return targets
end
RandomTargets = BattleTarget.RandomTargets

function BattleTarget.FindRandomUnit( _targetRes, _player, _targetCount, _isRandom, ... )
	local targets = {}
	if not _targetRes or not _player then
		return targets
	end
	targets = AllTargetUnitSwitcher[_targetRes.targetUnitType](targets, _player, _isRandom, _targetRes.targetSubType == BattleTargetSubType.BASEID and _targetRes.subCountId or 0)
	if _targetCount == 0 then
		return targets
	end
	return RandomTargets(targets, _targetCount)
end
FindRandomUnit = BattleTarget.FindRandomUnit

-- 范围目标
function BattleTarget.FindSubRangeTarget( _battleUnit, _targetRes, _player, _targets, _targetCount,... )
	if not _targetRes or not _player or #_targets == 0 or _targetCount == 0 then
		return _targets
	end
	local range = _targetCount
	local count = #_targets
	local unitType = _targets[1].unitType
	if unitType == BattleUnitType.MONSTER then
		-- 不去重，向前向后找
		local monsterList = _player.monsterList
		local monsterCount = #monsterList
		if monsterCount > 0 then
			for i = 1, count do
				local monster = _targets[i]
				local sortIndex = monster.sortIndex
				local position = _battleUnit.unitType == BattleUnitType.COLLIDER and _battleUnit.position or monster.position
				for n = sortIndex + 1, monsterCount do
					local nextMonster = monsterList[n]
					if nextMonster:IsValid() then
						if position - nextMonster.position <= range then
							table_insert(_targets, nextMonster)
						else
							break
						end
					end
				end
				for n = sortIndex - 1, 1, -1 do
					local preMonster = monsterList[n]
					if preMonster and preMonster:IsValid() then
						if preMonster.position - position <= range then
							table_insert(_targets, preMonster)
						else
							break
						end
					end
				end
			end
		end
	end
	return _targets
end
FindSubRangeTarget = BattleTarget.FindSubRangeTarget

-- 连接目标
function BattleTarget.FindSubLinkTarget( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
	if not _targetRes or not _player or #_targets == 0 or _targetCount == 0 then
		return _targets
	end
	local count = #_targets
	local unitType = _targets[1].unitType
	if unitType == BattleUnitType.MONSTER then
		local monsterList = _player.monsterList
		local monsterCount = #monsterList
		if monsterCount > 0 then
			for i = 1, count do
				if _targetCount > 1 then
					local monster = _targets[i]
					local sortIndex = monster.sortIndex
					local linkCount = 1
					for n = sortIndex + 1, monsterCount do
						local monster = monsterList[n]
						if monster:IsValid() then
							table_insert(_targets, monster)
							linkCount = linkCount + 1
							if linkCount >= _targetCount then
								break
							end
						end
					end
				end
			end
		end
	end
	return _targets
end
FindSubLinkTarget = BattleTarget.FindSubLinkTarget

-- 十字
function BattleTarget.FindSubCrossTarget( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
	if not _targetRes or not _player or #_targets == 0 then
		return _targets
	end
	local unitType = _targets[1].unitType
	if unitType ~= BattleUnitType.TOWER then
		return _targets
	end

	local player = _targets[1].player
	local targets = {}
	for i = 1, #_targets do
		local posIndex = _targets[i].posIndex
		local crossPosList = BattleConstants.BATTLE_TOWER_CROSS_MAP[posIndex]
		for n = 1, #crossPosList do
			local tower = player:GetTowerByPos(crossPosList[n])
			if tower then
				table_insert(targets, tower)
			end
		end
	end

	return targets
end
FindSubCrossTarget = BattleTarget.FindSubCrossTarget

-- 十字格子
function BattleTarget.FindSubCrossGridTarget( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
	if not _targetRes or not _player or #_targets == 0 then
		return _targets
	end
	local unitType = _targets[1].unitType
	if unitType ~= BattleUnitType.TOWER then
		return _targets
	end

	local player = _targets[1].player
	local targets = {}
	for i = 1, #_targets do
		local posIndex = _targets[i].posIndex
		local crossPosList = BattleConstants.BATTLE_TOWER_CROSS_MAP[posIndex]
		for n = 1, #crossPosList do
			local grid = player:GetGrid(crossPosList[n])
			if grid then
				table_insert(targets, grid)
			end
		end
	end

	return targets
end
FindSubCrossGridTarget = BattleTarget.FindSubCrossGridTarget

function BattleTarget.GetTargetPlayer( _player, _playerType, ... )
	local switcher = TargetPlayerSwitcher[_playerType]
	if switcher then
		return switcher(_player)
	end
	return _player
end
GetTargetPlayer = BattleTarget.GetTargetPlayer