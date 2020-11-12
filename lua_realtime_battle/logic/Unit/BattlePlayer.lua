---
--- class BattlePlayer
-- @classmod BattlePlayer
-- 玩家
class('BattlePlayer', BattleUnit)

---Constructor
function BattlePlayer:ctor( ... )
	self.super = Super( ... )
	self.super.unitType = BattleUnitType.PLAYER

	-- 序列化数据
	self.playerId = false 							-- 玩家Id
	self.playerSeed = false 						-- 玩家种子，用于抽卡、选卡、合成随机
	self.towerPool = {} 							-- 玩家塔池
	self.magicPool = {} 							-- 玩家魔法池
	self.serverId = false 							-- 玩家服务器Id
	self.playerName = false							-- 玩家名字
	self.playerLevel = false						-- 玩家等级

	-- 可序列化可运行时数据
	self.playerFrame = BattlePlayerFrame()			-- 玩家战斗帧

	-- 运行时数据
	self.playerIndex = 0							-- 玩家索引
	self.randNum = false							-- 玩家随机数，独立种子，用于抽卡、合成、塔位置等运算
	self.towerIdGenerator = 0						-- 塔Id生成器
	self.monsterIdGenerator = 0						-- 怪物Id生成器
	self.colliderIdGenerator = 0					-- 碰撞Id生成器
	self.frameIdGenerator = 0						-- 帧Id生成器

	self.point = 0									-- 点数
	self.costPoint = 0								-- 下次消耗点数
	self.magicCostPoint = 0							-- 下次魔法点数
	self.magicSpellTimes = 0						-- 魔法施法次数
	self.curHP = 0									-- 当前血量

	self.gridList = {}								-- 格子列表，索引代表位置
	self.towerList = {}								-- 塔列表，索引代表位置
	self.monsterList = false						-- 怪物列表，不排序链表
	self.monsterSortList = false					-- 怪物临时列表，自动排序链表
	self.colliderList = {}							-- 碰撞体列表，链表
	self.emptyPosList = {}							-- 空位置列表
	self.maxHPMonster = false						-- 最大血量怪物
	self.minHPMonster = false						-- 最小血量怪物
	self.firstMonster = false						-- 首位怪物

	self.allMagicList = false						-- 全部魔法列表
	self.magicList = false							-- 当前魔法列表
	self.waitingMagicList = false					-- 等待中魔法列表
	self.emptyMagicSlotList = {}
	self.pendingMagicCount = 0						-- 等待魔法个数

	self.isConnectDirty = false						-- 连接池是否脏

	self.isSurrender = false 						-- 是否投降

	self.reverseMap = {}							-- 预留数据
	self.stat = BattleStat()						-- 玩家统计
end

function BattlePlayer:Load( _tPlayer, ... )
	if not _tPlayer then
		return
	end

	self.playerId = _tPlayer.PlayerId
	self.playerSeed = _tPlayer.PlayerSeed
	self.towerPool = {}
	self.magicPool = {}
	for i = 1, #_tPlayer.TowerPool do
		local towerResId = _tPlayer.TowerPool[i] + 0
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if towerRes then
			table_insert(self.towerPool, towerResId + 4)
			table_insert(self.magicPool, towerRes.magicId + 14)
		end
	end
	_tPlayer.MagicPool = {210101, 210501, 210401}
	for i = 1, #_tPlayer.MagicPool do
		table_insert(self.magicPool, _tPlayer.MagicPool[i] + 7)
	end
	self.playerFrame = BattlePlayerFrame()
	self.playerFrame:Load(_tPlayer.PlayerFrame)
end

function BattlePlayer:Destroy( ... )
	-- 销毁玩家帧
	self.playerFrame:Destroy()
	-- 销毁塔
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		if self.towerList[i] then
			self.towerList[i]:Destroy()
			self.towerList[i] = false
		end
	end
	self.towerList = {}
	-- 父类销毁
	self.super:Destroy()
end

function BattlePlayer:Init( _index, ... )
	-- 打印log
	gBattleManager:AddBattleLog(string.format('Init Player [%d] Seed[%d] Tower[%s] Magic[%s]', self.playerId, self.playerSeed, gameutils.JSON:encode(self.towerPool), gameutils.JSON:encode(self.magicPool)))

	self.randNum = RandNum(self.playerSeed)
	self.playerFrame:Init(self)

	-- 初始化
	self.player = self
	self.unitId = self:GenerateUnitId(self.playerId)
	self.playerIndex = _index
	self.point = BattleConstants.BATTLE_INIT_POINT
	self.costPoint = BattleConstants.BATTLE_COST_POINT_STEP
	self.curHP = BattleConstants.BATTLE_PLAYER_TOTAL_HP

	-- 初始化塔列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		self.towerList[i] = false
		self.emptyPosList[i] = i

		-- 格子
		self.gridList[i] = BattleGrid()
		self.gridList[i]:Init(i, self)
	end

	-- 初始化魔法
	self:InitMagic()

	-- 初始化怪物列表
	self.monsterList = LLinkList()
	self.monsterSortList = LLinkList(function( _lMonster, _rMonster, ... )
		return _lMonster.position > _rMonster.position and -1 or (_lMonster.position == _rMonster.position and 0 or 1)
	end)

	-- 初始化碰撞体列表
	self.colliderList = LLinkList(function( _lCollider, _rCollider, ... )
		return _lCollider.position < _rCollider.position and -1 or (_lCollider.position == _rCollider.position and 0 or 1)
	end)

	-- 初始化预留数据
	self:InitReverseMap()

	-- 父类初始化
	self.super:Init()

	-- 通知前端添加玩家，更新点数
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDPLAYER, self.playerId)
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint, self.magicCostPoint)
end

function BattlePlayer:Update( _deltaTime, ... )
	-- 父类更新
	self.super:Update(_deltaTime, ...)
	-- 统计
	if gBattleFrameCount % Constants.BATTLE_FPS == 0 then
		self.stat:ResetSecondDamage()
	end
	-- 连接池
	if self.isConnectDirty then
		self:RefreshTowerConnect()
		self.isConnectDirty = false
	end
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		-- 格子
		self.gridList[i]:Update(_deltaTime)
		-- 塔
		local tower = self.towerList[i]
		if tower then
			tower:Update(_deltaTime)
		end
	end
	-- 怪物
	self:UpdateMonster(_deltaTime)
	-- 碰撞
	local colliderNode = self.colliderList.first
	while colliderNode do
		colliderNode.value:Update(_deltaTime)
		colliderNode = colliderNode.next
	end
end

function BattlePlayer:GetNextFrame( _moveToNext, ... )
	return self.playerFrame:GetNextFrame(_moveToNext)
end

function BattlePlayer:GetNextFrameCount( ... )
	return self.playerFrame:GetNextFrameCount()
end

function BattlePlayer:AddBattleFrame( _frame, _frameType, _param1, _param2, _point, ... )
	self.playerFrame:AddBattleFrame(_frame, _frameType, _param1, _param2, _point)
end

function BattlePlayer:GenerateBattleFrame( _frameType, _param1, _param2, _param3, _frameCount, ... )
	local frame = BattleFrame()
	frame.frameCount = NilDefault(_frameCount, gBattleFrameCount + 1) 
	frame.frameType = _frameType
	frame.param1 = tostring(NilDefault(_param1, ''))
	frame.param2 = tostring(NilDefault(_param2, ''))
	frame.param3 = tostring(NilDefault(_param3, ''))
	frame.point = self.point
	frame.frameId = self:GenerateFrameId()
	return frame
end

function BattlePlayer:GenerateFrameId( ... )
	self.frameIdGenerator = self.frameIdGenerator + 1
	return self.frameIdGenerator
end

function BattlePlayer:GenerateTowerId( ... )
	self.towerIdGenerator = self.towerIdGenerator + 1
	return self.towerIdGenerator
end

function BattlePlayer:GenerateMonsterId( ... )
	self.monsterIdGenerator = self.monsterIdGenerator + 1
	return self.monsterIdGenerator
end

function BattlePlayer:GenerateColliderId( ... )
	self.colliderIdGenerator = self.colliderIdGenerator + 1
	return self.colliderIdGenerator
end

-- 缓冲帧处理，校验是否已经缓冲过当前帧，若已缓冲过无需再处理
function BattlePlayer:CheckPendingFrame( _frame, _needPending )
	local isPended = false
	if not _needPending and self.playerFrame:CheckBattlePendingFrame(_frame) then
		isPended = true
		return isPended
	end
	return isPended
end

function BattlePlayer:AddPenddingFrame( _frame, _isRealTime, _needPending, _isLogic )
	if _needPending then
		self.playerFrame:AddBattlePendingFrame(_frame)
	end
	if not _isLogic and not _isRealTime then
		self.playerFrame:AddBattleFrame(_frame)
	end
end

function BattlePlayer:ExecSurrender( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.SURRENDER then
		return false, 1
	end
	local isLogic = NilDefault(_isLogic, true)
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return true, 2
	end
	self.isSurrender = true
	return _isRealTime, 0
end

function BattlePlayer:ExecRoll( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.ROLL then
		return false, 1
	end
	
	local isLogic = NilDefault(_isLogic, true)
	local needPending = not isLogic
	warn('ExecRoll', gBattleFrameCount, _frame.frameCount, self.playerId, isLogic, self.point, self.costPoint)
	local isPended = self:CheckPendingFrame(_frame, needPending)
	if isPended then
		return true, 0
	end
	
	-- 校验点数是否充足
	if not self:IsPointEnough() then
		error(string.format('Exec Roll Point Not Enough %d %d %d', self.playerId, self.point, self.costPoint))
		return false, 3
	end
	
	-- 随机塔位置
	local posIndex = self:RandomTowerPosIndex()
	if posIndex == 0 then
		return false, 4
	end
	
	-- 随机塔类型
	local towerResId = self:RandomTowerResId()
	local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
	if not towerRes then
		return false, 5
	end

	-- 消耗点数
	self:ConsumePoint()
	warn('ConsumePoint Roll', self.playerId, self.costPoint - BattleConstants.BATTLE_COST_POINT_STEP, self.point)

	-- 尝试添加缓冲帧
	self:AddPenddingFrame(_frame, _isRealTime, needPending, isLogic)

	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:AddTowerByFrame(_frame, towerRes, 1, posIndex, true)

	-- 战斗逻辑调用，立即通知缓存帧生效
	if isLogic then
		_frame:OnPendingOver()
	end

	return _isRealTime, 0
end

-- 合并事件
local MergeSwitcher = {
	-- 普通合成
	[BattleTowerMergeType.MERGE] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _gunCount, ... )
		local gunCount = _gunCount + 1
		local towerResId = self:RandomTowerResId()
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return false, 5
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, BattleUnitLeaveType.MERGE)
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, BattleUnitLeaveType.MERGED)
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, gunCount, _targetTowerIndex, false)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return true
	end,
	-- 营养
	[BattleTowerMergeType.FIX] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _gunCount, _targetTowerResId, ... )
		local gunCount = _gunCount + 1
		local towerResId = _targetTowerResId
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return false, 5
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, BattleUnitLeaveType.MERGE)
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, BattleUnitLeaveType.MERGED)
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, gunCount, _targetTowerIndex, false)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return true
	end,
	-- 交换
	[BattleTowerMergeType.EXCHANGE] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _gunCount, ... )
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:ExchangeTowerByFrame(_frame, _dragTowerIndex, _targetTowerIndex)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return true
	end,
	-- 复制
	[BattleTowerMergeType.COPY] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _gunCount, _targetTowerResId, ... )
		local gunCount = _gunCount
		local towerResId = _targetTowerResId
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return false, 5
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, BattleUnitLeaveType.MERGED)
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, gunCount, _dragTowerIndex, false)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return true
	end,
}

function BattlePlayer:ExecMerge( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.MERGE then
		return false, 1
	end

	local isLogic = NilDefault(_isLogic, true)
	local needPending = not isLogic
	local isPended = self:CheckPendingFrame(_frame, needPending)
	if isPended then
		return true, 0
	end

	local dragTowerIndex = ToInt(_frame.param1)
	local targetTowerIndex = ToInt(_frame.param2)
	local mergeType = ToInt(_frame.param3) % 10
	local gunCount = ToInt(ToInt(_frame.param3) / 10) % 10
	local targetTowerResId = ToInt(ToInt(_frame.param3) / 100)

	if isLogic then
		-- 逻辑判定是否可以合并
		local dragTower = self:GetTowerByPos(dragTowerIndex)
		local targetTower = self:GetTowerByPos(targetTowerIndex)
		if not dragTower or not targetTower then
			return false, 3
		end
		local canMerge, logicMergeType = dragTower:CanMerge(targetTower)
		gBattleManager:AddBattleLog(string.format('ExecMerge Frame[%d] Player[%d] CaneMerge[%s] LogicMergeType[%d] FrameMergeType[%d] DragTower[%d] TargetTower[%d]', gBattleFrameCount, self.playerId, tostring(canMerge), logicMergeType, mergeType, dragTower.towerRes.birthFlag, targetTower.towerRes.birthFlag))
		warn(string.format('ExecMerge Frame[%d] Player[%d] CaneMerge[%s] LogicMergeType[%d] FrameMergeType[%d] DragTower[%d] TargetTower[%d]', gBattleFrameCount, self.playerId, tostring(canMerge), logicMergeType, mergeType, dragTower.towerRes.birthFlag, targetTower.towerRes.birthFlag))
		if not canMerge or (mergeType ~= 0 and mergeType ~= logicMergeType) then
			return false, 4
		end
		gunCount = dragTower.gunCount
		targetTowerResId = targetTower.towerRes.id
		mergeType = logicMergeType
	end

	local switcher = MergeSwitcher[mergeType]
	if not switcher then
		return false, 6
	end

	local success, code = switcher(self, _frame, _isRealTime, isLogic, needPending, dragTowerIndex, targetTowerIndex, gunCount, targetTowerResId)
	if not success then
		return false, code
	end

	return _isRealTime, 0
end

function BattlePlayer:ExecMagic( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.MAGIC then
		return false, 1
	end
	local isLogic = NilDefault(_isLogic, true)
	warn('ExecMagic', gBattleFrameCount, _frame.frameCount, self.playerId, isLogic, self.point)
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return true, 2
	end
	local magicIndex = ToInt(_frame.param1)
	local magic = self:GetMagic(magicIndex)
	if not magic then
		return false, 3
	end
	local magicResId = magic.magicId
	local magicRes = GameResMgr.GetMagicRes(magicResId)
	if not magicRes then
		return false, 4
	end

	-- 校验点数是否充足
	local costPoint = magic.costPoint
	-- costPoint = 0
	if not self:IsPointEnough(costPoint) then
		error(string.format('Exec Magic Point Not Enough %d %d %d %d', self.playerId, self.point, costPoint, magicResId))
		return false, 5
	end

	-- 执行魔法行为
	local talentId = magicRes.talentId
	local talentRes = GameResMgr.GetTalentRes(talentId)
	if talentRes then
		for i = 1, #talentRes.actionList do
			local actionId = talentRes.actionList[i]
			local triggerParam = BattleTriggerParam(self, nil, nil, nil)
			gBattleTrigger:FireAction(actionId, self, nil, triggerParam)
		end
	end

	self.stat:AddMagic(gBattleFrameCount, magicResId)

	-- 消耗点数
	self:ConsumePoint(costPoint)

	gBattleLogic:OnMagicSpell(self, magic)

	-- 打印log
	gBattleManager:AddBattleLog(string.format('Exec Magic Frame[%d] Player[%d] Magic[%d]', gBattleFrameCount, self.playerId, magicRes.id))

	return _isRealTime, 0
end

function BattlePlayer:GetGrid( _gridIndex, ... )
	return NilDefault(self.gridList[_gridIndex], false)
end

function BattlePlayer:AddTower( _towerRes, _gunCount, _posIndex, _isRoll, ... )
	if not _towerRes or _gunCount <= 0 then
		return false
	end

	local towerId = self:GenerateTowerId()
	local tower = BattleTower()
	if not tower:Init(_towerRes, _gunCount, towerId, _posIndex, self) then
		return false
	end

	-- 添加到塔列表
	self.towerList[_posIndex] = tower
	gBattleRecord:AddBattleUnit(tower.unitId, tower)

	-- 进入格子
	self.gridList[_posIndex]:OnTowerEnter(tower) 

	-- 标记连接池已脏
	self.isConnectDirty = true

	-- 打印log
	gBattleManager:AddBattleLog(string.format('Add Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d]', gBattleFrameCount, self.playerId, towerId, _towerRes.baseId, _towerRes.level, _posIndex))
	
	return tower
end

function BattlePlayer:AddTowerByFrame( _frame, _towerRes, _gunCount, _posIndex, _isRoll, ... )
	if not _towerRes or _gunCount <= 0 then
		return
	end
	local gbTower, pendingId = BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDTOWER, self.playerId, _towerRes, _gunCount, _posIndex)
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.ADDTOWER, self, _towerRes, _gunCount, _posIndex, pendingId)
	else
		local tower = _player:AddTower(_towerRes, _gunCount, _posIndex, _isRoll)
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.PENDINGTOWER, self.playerId, tower, pendingId)
	end
	self:BusyTowerPos(_posIndex)
end

function BattlePlayer:RemoveTower( _posIndex, _leaveType, ... )
	local tower = self.towerList[_posIndex]
	if not tower then
		return
	end

	-- 打印log
	gBattleManager:AddBattleLog(string.format('Remove Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d]', gBattleFrameCount, self.playerId, tower.towerId, tower.towerRes.baseId, tower.towerRes.level, tower.posIndex))

	-- 从格子移除
	self.gridList[_posIndex]:OnTowerLeave(self.towerList[_posIndex])

	-- 从列表移除
	self.towerList[_posIndex] = false
	gBattleRecord:RemoveBattleUnit(tower.unitId)
	-- 销毁
	tower:Destroy(_leaveType)

	-- 标记连接池已脏
	self.isConnectDirty = true
end

function BattlePlayer:RemoveTowerByFrame( _frame, _posIndex, _leaveType,  ... )
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVETOWER, self.playerId, _posIndex)
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.REMOVETOWER, self, _posIndex, _leaveType)
	else
		self:RemoveTower(_posIndex, _leaveType)
	end
	self:FreeTowerPos(_posIndex)
end

function BattlePlayer:ExchangeTower( _dragIndex, _targetIndex, ... )
	local dragTower = self.towerList[_dragIndex]
	local targetTower = self.towerList[_targetIndex]
	if not dragTower or not targetTower then
		return
	end

	-- 从格子移除
	self.gridList[_dragIndex]:OnTowerLeave(dragTower)
	self.gridList[_targetIndex]:OnTowerLeave(targetTower)

	-- 列表中交换位置
	self.towerList[_dragIndex] = targetTower
	self.towerList[_targetIndex] = dragTower

	dragTower.posIndex = _targetIndex
	targetTower.posIndex = _dragIndex

	-- 进入格子
	self.gridList[_dragIndex]:OnTowerEnter(targetTower)
	self.gridList[_targetIndex]:OnTowerEnter(dragTower)

	-- 标记连接池已脏
	self.isConnectDirty = true
end

function BattlePlayer:ExchangeTowerByFrame( _frame, _dragIndex, _targetIndex, ... )
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.EXCHANGETOWER, self.playerId, _dragIndex, _targetIndex)
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.EXCHANGETOWER, self, _dragIndex, _targetIndex)
	else
		self:ExchangeTower(_dragIndex, _targetIndex)
	end
end

function BattlePlayer:ChangeTowerGun( _tower, _change, _frame, ... )
	if not _tower or _change == 0 then
		return
	end

	local isLogic = _triggerParam.isLogic
	local needPending = not isLogic

	local towerRes = _tower.towerRes
	local gunCount = _tower.gunCount
	gunCount = gunCount + _change

	-- 尝试添加缓冲帧
	if _frame then
		self:AddPenddingFrame(_frame, gBattleRecord.isRealTime, needPending, isLogic)
	end

	-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
	local posIndex = _tower.posIndex
	self:RemoveTowerByFrame(_frame, posIndex, _change > 0 and BattleUnitLeaveType.ADDGUN or BattleUnitLeaveType.SUBGUN)

	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:AddTowerByFrame(_frame, towerRes, gunCount, posIndex, false)

	-- 战斗逻辑调用，立即通知缓存帧生效
	if isLogic and _frame then
		_frame:OnPendingOver()
	end
end

function BattlePlayer:GetTower( _towerId, ... )
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local tower = self.towerList[i]
		if tower and tower.towerId == _towerId then
			return tower
		end
	end
	return false
end

function BattlePlayer:GetTowerByPos( _posIndex, ... )
	return NilDefault(self.towerList[_posIndex], false)
end

function BattlePlayer:RandomTowerResId( ... )
	local index = self.randNum:NextInt(#self.towerPool)
	return self.towerPool[index]
end

function BattlePlayer:RandomTowerPosIndex( ... )
	-- 塔满，没有空余位置
	if #self.emptyPosList == 0 then
		return 0
	end
	local index = 1
	if #self.emptyPosList > 1 then
		index = self.randNum:NextInt(#self.emptyPosList)
	end
	return self.emptyPosList[index]
end

function BattlePlayer:FreeTowerPos( _posIndex, ... )
	table_insert(self.emptyPosList, _posIndex)
end

function BattlePlayer:BusyTowerPos( _posIndex, ... )
	for i = 1, #self.emptyPosList do
		if self.emptyPosList[i] == _posIndex then
			table_remove(self.emptyPosList, i)
			break
		end
	end
end

function BattlePlayer:HasEmptyPos( ... )
	return #self.emptyPosList ~= 0
end

function BattlePlayer:AddMonster( _id, _monsterHP, _isMagicMonster, ... )
	local monsterRes = GameResMgr.GetBattleMonsterRes(_id)
	if not monsterRes then
		return false
	end
	
	local monsterId = self:GenerateMonsterId()
	local monster = BattleMonster()
	if not monster:Init(monsterRes, monsterId, self, _monsterHP, _isMagicMonster) then
		return false
	end
	
	-- 添加到怪物列表
	monster.node = self.monsterList:Add(monster)
	gBattleRecord:AddBattleUnit(monster.unitId, monster)
	-- 通知前端添加怪物
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDMONSTER, self.playerId, monsterId)
	-- 打印log
	gBattleManager:AddBattleLog(string.format('Add Monster Frame[%d] Player[%d] Monster[%d-%d]', gBattleFrameCount, self.playerId, monsterId, _id))
	
	return monster
end

function BattlePlayer:RemoveMonster( _monsterId, _leaveType, _subHP, ... )
	local monster = self:GetMonster(_monsterId)
	if not monster then
		return false
	end

	local subHP = NilDefault(_subHP, 0)
	if _leaveType == BattleUnitLeaveType.END then
		self.curHP = self.curHP - subHP
	end

	-- 通知前端移除怪物
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVEMONSTER, self.playerId, _monsterId)
	-- 从列表移除
	local nextMonsterNode = self.monsterList:RemoveNode(monster.node)
	gBattleRecord:RemoveBattleUnit(monster.unitId)
	-- 销毁
	monster:Destroy(_leaveType)

	return nextMonsterNode
end

function BattlePlayer:RemoveAllMonster( _leaveType, _isBossRemove, ... )
	local isBossRemove = NilDefault(_isBossRemove, true)
	local monsterNode = self.monsterList.first
	while monsterNode do
		local monster = monsterNode.value
		if isBossRemove or monster.monsterRes.type ~= MonsterType.BOSS then
			monsterNode = self:RemoveMonster(monster.monsterId, _leaveType)
		else
			monsterNode = monsterNode.next
		end
	end
end

function BattlePlayer:UpdateMonster( _deltaTime, ... )
	-- 重置排序列表
	self.monsterSortList:Clear()
	self.maxHPMonster = false
	self.minHPMonster = false
	-- 遍历怪物
	local monsterNode = self.monsterList.first
	while monsterNode do
		local monster = monsterNode.value
		monster:Update(_deltaTime)
		if not monster:HasUnitFlag(BattleUnitFlag.DEATH) then
			-- 插入排序队列
			self.monsterSortList:Add(monster)
			-- 最大血量怪物
			if not self.maxHPMonster then
				self.maxHPMonster = monster
			elseif self.maxHPMonster.curHP < monster.curHP then
				self.maxHPMonster = monster
			end
			-- 最小血量怪物
			if not self.minHPMonster then
				self.minHPMonster = monster
			elseif self.minHPMonster.curHP > monster.curHP then
				self.minHPMonster = monster
			end
		end
		monsterNode = monsterNode.next
	end
	-- 按最新排序列表刷新怪物列表
	self.monsterList:Clear()
	monsterNode = self.monsterSortList.first
	self.firstMonster = monsterNode and monsterNode.value or false
	while monsterNode do
		local monster = monsterNode.value
		monster.node = self.monsterList:Add(monster)
		monsterNode = monsterNode.next
	end
end

function BattlePlayer:GetMonster( _monsterId, ... )
	local monsterNode = self.monsterList:Find(_monsterId, 'monsterId')
	if monsterNode then
		return monsterNode.value
	end
	return false
end

function BattlePlayer:GetMonsterCount( ... )
	return self.monsterList.count
end

function BattlePlayer:AddCollider( _id, _ownerUnitId, _triggerUnit, ... )
	local colliderRes = GameResMgr.GetBattleColliderRes(_id)
	if not colliderRes then
		return false
	end

	local ownerUnit = gBattleRecord:GetBattleUnit(_ownerUnitId)
	if not ownerUnit then
		return false
	end 

	local position = 0
	if colliderRes.isRandomPos == 0 and _triggerUnit and _triggerUnit.unitType == BattleUnitType.MONSTER then
		position = _triggerUnit.position
	else
		position = gBattleRandNum:NextInt(1000, BattleConstants.BATTLE_ROAD_LENGTH - 1000)
	end
	
	local colliderId = self:GenerateColliderId()
	local collider = BattleCollider()
	if not collider:Init(colliderRes, colliderId, ownerUnit, self, position) then
		return false
	end

	-- 添加到怪物列表
	collider.node = self.colliderList:Add(collider)
	gBattleRecord:AddBattleUnit(collider.unitId, collider)
	-- 通知前端添加碰撞
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDCOLLIDER, self.playerId, colliderId, _ownerUnitId)
	-- 打印log
	gBattleManager:AddBattleLog(string.format('Add Collider Frame[%d] Player[%d] Collider[%d-%d-%d-%s]', gBattleFrameCount, self.playerId, colliderId, _id, position, _ownerUnitId))
	
	return collider
end

function BattlePlayer:RemoveCollider( _colliderId, _leaveType, ... )
	local collider = self:GetCollider(_colliderId)
	if not collider then
		return
	end

	-- 通知前端移除碰撞
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVECOLLIDER, self.playerId, _colliderId)
	-- 从列表移除
	self.colliderList:RemoveNode(collider.node)
	gBattleRecord:RemoveBattleUnit(collider.unitId)
	-- 销毁
	collider:Destroy(_leaveType)
end

function BattlePlayer:GetCollider( _colliderId, ... )
	local colliderNode = self.colliderList:Find(_colliderId, 'colliderId')
	if colliderNode then
		return colliderNode.value
	end
	return false
end

local UnitRemoveSwitcher = {
	[BattleUnitType.TOWER] = function( self, _unit, _leaveType, ... )
		self:RemoveTower(_unit.posIndex, _leaveType)
	end,
	[BattleUnitType.MONSTER] = function( self, _unit, _leaveType, ... )
		self:RemoveMonster(unit.monsterId, _leaveType)
	end,
	[BattleUnitType.COLLIDER] = function( self, _unit, _leaveType, ... )
		self:RemoveCollider(unit.colliderId, _leaveType)
	end,
}

function BattlePlayer:RemoveUnit( _unit, _leaveType, ... )
	local switcher = UnitRemoveSwitcher[_unit.unitType]
	if switcher then
		switcher(self, _unit, _leaveType)
	end	
end

function BattlePlayer:IsPointEnough( _costPoint, ... )
	local costPoint = NilDefault(_costPoint, self.costPoint)
	return self.point >= costPoint
end

-- 消耗点数
function BattlePlayer:ConsumePoint( _costPoint, ... )
	local costPoint = NilDefault(_costPoint, self.costPoint)
	self.point = self.point - costPoint
	if _costPoint then
		self.stat:AddMagicPoint(_costPoint)
	else
		self.stat:AddRollPoint(costPoint)
	end
	if not _costPoint then
		self.costPoint = self.costPoint + BattleConstants.BATTLE_COST_POINT_STEP
	end

	-- 通知前端更新点数
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
end

-- 增加点数
function BattlePlayer:AddPoint( _point, ... )
	if not _point then
		return 0
	end

	if _point > 0 then
		-- Point收益百分比
		_point = ToInt(_point * (1 + self:GetAttribute(AttriType.POINTPERCENT) * s_PercentScale))
		_point = _point < 0 and 0 or _point
	else
		_point = (self.point + _point < 0) and -self.point or _point
	end

	self.point = self.point + _point
	self.stat:AddPoint(_point)

	-- 通知前端更新点数
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)

	return _point
end

-- 偷取SP
function BattlePlayer:StealPoint( _targetPlayer, _point, ... )
	if not _targetPlayer then
		return
	end
	
	local point = -_targetPlayer:AddPoint(-_point)
	self:AddPoint(point)
end

-- 初始化魔法
function BattlePlayer:InitMagic( ... )
	if self.allMagicList then
		return
	end

	self.allMagicList = {}
	for i = 1, #self.magicPool do
		local magic = {}
		magic.magicId = self.magicPool[i]
		magic.magicRes = GameResMgr.GetMagicRes(self.magicPool[i])
		magic.spellTimes = 0
		magic.index = 0
		magic.costPoint = 0
		magic.linkTowers = {}
		for i = 1, #magic.magicRes.linkTowerIdList do
			magic.linkTowers[magic.magicRes.linkTowerIdList[i]] = 1
		end
		table_insert(self.allMagicList, magic)
	end
end

-- 随机生成魔法列表
function BattlePlayer:GenerateMagic( ... )
	self.magicList = {}
	self.emptyMagicSlotList = { 1, 2, 3, 4, 5, 6 }
	for i = 1, #self.emptyMagicSlotList do
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, self.emptyMagicSlotList[i], nil)
	end

	-- 第一次释放魔法免费
	self.magicCostPoint = 0
	self.magicSpellTimes = 0

	local magicCount = #self.allMagicList
	gBattleRandNum:ClearUniqueRecord(UniqueRandType.MAGIC)
	local commonMagicCount = 2
	for i = 1, 4 do
		local index = 0
		if i <= commonMagicCount then
			index = gBattleRandNum:NextUniqueInt(UniqueRandType.MAGIC, 6, 8)
		else
			index = gBattleRandNum:NextUniqueInt(UniqueRandType.MAGIC, 5)
		end
		local magicData = self.allMagicList[index]
		magicData.costPoint = self.magicCostPoint
		magicData.index = i
		table_insert(self.magicList, magicData)

		-- 通知前端刷新魔法
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, i, magicData)
	end
end

-- 使用魔法
function BattlePlayer:OnMagicSpell( _magicData )
	self.magicCostPoint = self.magicCostPoint + gBattleLogic.roundNum * 50
	self.magicSpellTimes = self.magicSpellTimes + 1

	-- 魔法使用次数+1
	_magicData.spellTimes = _magicData.spellTimes + 1

	-- 刷新魔法消耗
	self:UpdateMagicCost()
end

-- 随机生成魔法列表
function BattlePlayer:GenerateCoopMagic( _count, _needReset, ... )
	if _needReset then
		self.magicList = {}
		self.emptyMagicSlotList = { 1, 2, 3, 4, 5, 6 }
		for i = 1, #self.emptyMagicSlotList do
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, self.emptyMagicSlotList[i], nil)
		end
	end

	local count = NilDefault(_count, 1)
	local magicCount = #self.allMagicList
	for i = 1, count do
		if #self.emptyMagicSlotList == 0 then
			self.pendingMagicCount = self.pendingMagicCount + count - i + 1
			return
		end

		local index = gBattleRandNum:NextInt(magicCount)
		local magicData = Clone(self.allMagicList[index])
		magicData.costPoint = 0
		magicData.index = self.emptyMagicSlotList[1]
		table_insert(self.magicList, magicData)
		table_remove(self.emptyMagicSlotList, 1)

		-- 通知前端刷新魔法
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, magicData.index, magicData)
	end
end

function BattlePlayer:OnCoopMagicSpell( _magicData, ... )
	warn('OnCoopMagicSpell', _magicData.index)

	self.magicCostPoint = 0
	self.magicSpellTimes = self.magicSpellTimes + 1

	local index = _magicData.index
	table_insert(self.emptyMagicSlotList, index)

	for i = 1, #self.magicList do
		if self.magicList[i].index == index then
			table_remove(self.magicList, i)
			break
		end
	end

	-- 魔法使用次数+1
	_magicData.spellTimes = _magicData.spellTimes + 1
	_magicData.index = 0

	-- 通知前端刷新魔法
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, index, nil)

	-- 缓冲魔法
	if self.pendingMagicCount > 0 then
		self.pendingMagicCount = self.pendingMagicCount - 1
		self:GenerateCoopMagic(1)
	end
end

-- 魔法节点
function BattlePlayer:GetMagic( _index, ... )
	for i = 1, #self.magicList do
		if self.magicList[i].index == _index then
			return self.magicList[i]
		end
	end
	return false
end

-- 魔法消耗
function BattlePlayer:GetMagicCostPoint( _index, ... )
	local magic = self:GetMagic(_index)
	if not magic then
		return -1
	end
	return magic.costPoint
end

-- 魔法消耗刷新
function BattlePlayer:UpdateMagicCost( ... )
	for i = 1, #self.magicList do
		local magicData = self.magicList[i]
		magicData.costPoint = self.magicCostPoint
		-- 通知前端刷新魔法点数
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.MAGICUPDATE, self.playerId, i, magicData)
	end
end

-- 魔法是否可用
function BattlePlayer:IsMagicEnable( _index, ... )
	local magic = self:GetMagic(_index)
	if not magic then
		return false
	end
	return magic.index == _index
end

-- 初始化预留数据
function BattlePlayer:InitReverseMap( ... )
	for i = 1, #self.allMagicList do
		local magicResId = self.allMagicList[i].magicId
		local magicRes = GameResMgr.GetMagicRes(magicResId)
		local talentRes = GameResMgr.GetTalentRes(magicRes.talentId)
		if talentRes then
			for n = 1, #talentRes.actionList do
				local actionRes = GameResMgr.GetBattleActionRes(talentRes.actionList[n])
				local targetRes = GameResMgr.GetBattleTargetRes(actionRes.targetId)
				if targetRes and targetRes.targetType == BattleTargetType.REVERSE then
					local subReverseMap = self.reverseMap[targetRes.targetSubType]
					if not subReverseMap then
						subReverseMap = {}
						subReverseMap.map = {}
						subReverseMap.allTargets = {}
						for i = 1, #self.gridList do
							subReverseMap.allTargets[i] = {}
							subReverseMap.allTargets[i].target = self.gridList[i]
							subReverseMap.allTargets[i].flag = 0
							subReverseMap.allTargets[i].index = i
						end
						subReverseMap.totalCount = #subReverseMap.allTargets
						subReverseMap.totalMinCount = 0
						self.reverseMap[targetRes.targetSubType] = subReverseMap
					end
					local reverse = subReverseMap.map[targetRes.subCountId]
					if not reverse then
						reverse = { minCount = 0, maxCount = 0, current = {}, curCount = 0 }
						subReverseMap.map[targetRes.subCountId] = reverse
					end
					local targetCount = BattleFormula.GetValue(targetRes.countId, self)
					if reverse.minCount < targetCount then
						subReverseMap.totalMinCount = subReverseMap.totalMinCount - reverse.minCount + targetCount
						reverse.minCount = targetCount
					end
				end
			end
		end
	end
	for subType, subReverseMap in pairs(self.reverseMap) do
		if subReverseMap.totalMinCount > subReverseMap.totalCount then
			pcall(function()
				error('Reverse Target OverLoad', self.playerId, subType, subReverseMap.totalMinCount, subReverseMap.totalCount)
			end)
			return
		end
		for subFlag, reverse in pairs(subReverseMap.map) do
			reverse.maxCount = subReverseMap.totalCount - (subReverseMap.totalMinCount - reverse.minCount)
		end
	end
end

-- 刷新连接池
function BattlePlayer:RefreshTowerConnect( ... )
	local connectTowerList = {}
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local tower = self.towerList[i]
		if tower and tower:HasUnitFlag(BattleUnitFlag.CONNECT) then
			tower.connectCount = -1
			table_insert(connectTowerList, tower)
		end
	end
	for i = 1, #connectTowerList do
		local tower = connectTowerList[i]
		if tower.connectCount == -1 then
			local list = {}
			tower:RefreshTowerConnect(list)
			local connectCount = #list
			for n = 1, #list do
				list[n]:SetConnectCount(connectCount)
			end
		end
	end
end

classend()
export('BattlePlayer', BattlePlayer)