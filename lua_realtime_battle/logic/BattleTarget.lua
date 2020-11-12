---
--- class BattleTarget
-- @classmod BattleTarget
class('BattleTarget')

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
		return NilDefault(_defaultTargets, {})
	end,
	-- 触发者
	[BattleTargetType.TRIGGER] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return { _triggerUnit }
	end,
	-- 自己
	[BattleTargetType.SELF] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return { _battleUnit }
	end,
	-- 预留
	[BattleTargetType.REVERSE] = function( _targetRes, _battleUnit, _player, _targetCount, _defaultTargets, _attackerUnit, _triggerUnit, ... )
		return FindReverseUnit(_targetRes, _player, _targetCount)
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
	[BattleUnitType.TOWER] = function( _targets, _player, ... )
		for i = 1, #_player.towerList do
			local tower = _player.towerList[i]
			if tower then
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
		local node = _player.monsterList.first
		while node do
			table_insert(_targets, node.value)
			node = node.next
		end
		return _targets
	end,
	-- 碰撞物
	[BattleUnitType.COLLIDER] = function( _targets, _player, ... )
		local node = _player.colliderList.first
		while node do
			table_insert(_targets, node.value)
			node = node.next
		end
		return _targets
	end,
}

function BattleTarget.CheckCondition( _targetRes, _targetUnit, ... )
	if not _targetRes then
		return true
	end
	-- if _targetRes.targetBuffer > 0 and not _targetUnit:HasBuffer(_targetRes.targetBuffer) then
	-- 	return false
	-- end
	-- if _targetRes.targetBuffer < 0 and _targetUnit:HasBuffer(-_targetRes.targetBuffer) then
	-- 	return false
	-- end
	if _targetRes.targetFlag > 0 and not _targetUnit:HasUnitFlag(_targetRes.targetFlag) then
		return false
	end
	if _targetRes.targetFlag < 0 and _targetUnit:HasUnitFlag(-_targetRes.targetFlag) then
		return false
	end
	return true
end

function BattleTarget.FindFrontMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	local node = _player.monsterList.first
	local monster = false
	while node and #targets < targetCount do
		monster = node.value
		if CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
		end
		node = node.next
end
	if _targetRes and _player.monsterList.count > 0 and #targets == 0 then
		return FindFrontMonster(false, _player, _targetCount)
	end
	return targets
end

function BattleTarget.FindBackMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	local node = _player.monsterList.last
	local monster = false
	while node and #targets < targetCount do
		monster = node.value
		if CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
		end
		node = node.pre
	end
	if _targetRes and _player.monsterList.count > 0 and #targets == 0 then
		return FindBackMonster(false, _player, _targetCount)
	end
	return targets
end

function BattleTarget.FindMaxHPMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	if targetCount == 1 then
		if CheckCondition(_targetRes, _player.maxHPMonster) then
			table_insert(targets, _player.maxHPMonster)
			return targets
		end
	end
	local hpMonsterList = LLinkList(function( _lMonster, _rMonster, ... )
		return _lMonster.curHP > _rMonster.curHP and -1 or 1
	end)
	local node = _player.monsterList.first
	while node do
		hpMonsterList:Add(node.value)
		node = node.next
	end
	node = hpMonsterList.first
	local monster = false
	while node and #targets < targetCount do
		monster = node.value
		if CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
		end
		node = node.next
	end
	if _targetRes and _player.monsterList.count > 0 and #targets == 0 then
		return FindMaxHPMonster(false, _player, _targetCount)
	end
	return targets
end

function BattleTarget.FindMinHPMonster( _targetRes, _player, _targetCount, ... )
	local targets = {}
	if not _player then
		return targets
	end
	local targetCount = (not _targetCount or _targetCount == 0) and 1 or _targetCount
	if targetCount == 1 then
		if CheckCondition(_targetRes, _player.minHPMonster) then
			table_insert(targets, _player.minHPMonster)
			return targets
		end
	end
	local hpMonsterList = LLinkList(function( _lMonster, _rMonster, ... )
		return _lMonster.curHP < _rMonster.curHP and -1 or 1
	end)
	local node = _player.monsterList.first
	while node do
		hpMonsterList:Add(node.value)
		node = node.next
	end
	node = hpMonsterList.first
	local monster = false
	while node and #targets < targetCount do
		monster = node.value
		if CheckCondition(_targetRes, monster) then
			table_insert(targets, monster)
		end
		node = node.next
	end
	if _targetRes and _player.monsterList.count > 0 and #targets == 0 then
		return FindMinHPMonster(false, _player, _targetCount)
	end
	return targets
end

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

function BattleTarget.FindRandomUnit( _targetRes, _player, _targetCount, _isRandom, ... )
	local targets = {}
	if not _targetRes or not _player then
		return targets
	end
	targets = AllTargetUnitSwitcher[_targetRes.targetUnitType](targets, _player, _isRandom)
	if _targetCount == 0 then
		return targets
	end
	return RandomTargets(targets, _targetCount)
end

-- 范围目标
function BattleTarget.FindSubRangeTarget( _battleUnit, _targetRes, _player, _targets, _targetCount,... )
	if not _targetRes or not _player or #_targets == 0 or _targetCount == 0 then
		return _targets
	end
	local range = _targetCount
	local count = #_targets
	local unitType = _targets[1].unitType
	if unitType == BattleUnitType.MONSTER then
		-- 不去重，通过有序链表，向前向后找
		for i = 1, count do
			local monster = _targets[i]
			local position = _battleUnit.unitType == BattleUnitType.COLLIDER and _battleUnit.position or monster.position
			local nextNode = monster.node.next
			while nextNode do
				local nextMonster = nextNode.value
				if position - nextMonster.position <= range then
					table_insert(_targets, nextMonster)
					nextNode = nextNode.next
				else
					break
				end
			end
			local preNode = monster.node.pre
			while preNode do
				local preMonster = preNode.value
				if preMonster.position - position <= range then
					table_insert(_targets, preMonster)
					preNode = preNode.pre
				else
					break
				end
			end
		end
	end
	return _targets
end

-- 连接目标
function BattleTarget.FindSubLinkTarget( _battleUnit, _targetRes, _player, _targets, _targetCount, ... )
	if not _targetRes or not _player or #_targets == 0 or _targetCount == 0 then
		return _targets
	end
	local count = #_targets
	local unitType = _targets[1].unitType
	if unitType == BattleUnitType.MONSTER then
		for i = 1, count do
			local monster = _targets[i]
			local linkCount = 1
			local nextNode = monster.node.next
			while nextNode and linkCount < _targetCount do
				table_insert(_targets, nextNode.value)
				nextNode = nextNode.next
				linkCount = linkCount + 1
			end
		end
	end
	return _targets
end

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

-- 预留目标
function BattleTarget.FindReverseUnit( _targetRes, _player, _targetCount )
	local subType = _targetRes.targetSubType
	local subFlag = _targetRes.subCountId
	local subReverseMap = _player.reverseMap[subType]
	local reverse = subReverseMap.map[subFlag]
	local targets = {}
	local reverseTargets = {}
	local indexMap = {}
	if reverse.maxCount == subReverseMap.totalCount then
		-- 只有一种目标预留，只需要全局随机即可
		reverseTargets = RandomTargets(subReverseMap.allTargets, _targetCount)
		for i = 1, #reverseTargets do
			table_insert(targets, reverseTargets[i].target)
		end
		return targets
	end
	if reverse.curCount > 0 then
		for i = 1, #subReverseMap.allTargets do
			local target = subReverseMap.allTargets[i]
			if target.flag == subFlag then
				table_insert(reverseTargets, target)
			end
		end
		for i = 1, #reverseTargets do
			table_insert(targets, reverseTargets[i].target)
		end
		return targets
	end
	-- 多种目标预留，需要先在当前类型已有目标中随机，再在整个可用目标中随机剩余的
	local currentTargetCount = reverse.curCount + _targetCount - reverse.maxCount
	currentTargetCount = currentTargetCount < 0 and 0 or currentTargetCount
	local otherTargetCount = _targetCount - currentTargetCount
	if currentTargetCount > 0 then
		for i = 1, #subReverseMap.allTargets do
			local target = subReverseMap.allTargets[i]
			if target.flag == subFlag then
				table_insert(reverseTargets, target)
			end
		end
		reverseTargets = RandomTargets(reverseTargets, currentTargetCount)
		for i = 1, #reverseTargets do
			indexMap[reverseTargets[i].index] = 1
			table_insert(targets, reverseTargets[i].target)
		end
	end
	if otherTargetCount > 0 then
		reverseTargets = {}
		for i = 1, #subReverseMap.allTargets do
			local target = subReverseMap.allTargets[i]
			if not indexMap[target.index] and (target.flag == subFlag or target.flag == 0) then
				table_insert(reverseTargets, target)
			end 
		end
		reverseTargets = RandomTargets(reverseTargets, otherTargetCount)
		for i = 1, #reverseTargets do
			local target = reverseTargets[i]
			table_insert(targets, target.target)
			if target.flag == 0 then
				target.flag = subFlag
				reverse.curCount = reverse.curCount + 1
			end
		end
		if reverse.minCount < reverse.curCount then
			subReverseMap.totalMinCount = subReverseMap.totalMinCount - reverse.minCount + reverse.curCount
			reverse.minCount = reverse.curCount
			for tempFlag, tempReverse in pairs(subReverseMap.map) do
				tempReverse.maxCount = subReverseMap.totalCount - (subReverseMap.totalMinCount - tempReverse.minCount)
			end
		end
	end
	return targets
end

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

function BattleTarget.GetTargetPlayer( _player, _playerType, ... )
	local switcher = TargetPlayerSwitcher[_playerType]
	if switcher then
		return switcher(_player)
	end
	return _player
end

classend()