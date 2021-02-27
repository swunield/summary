---
--- class BattlePlayer
-- @classmod BattlePlayer
-- 玩家
class('BattlePlayer', BattleUnit)

local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local os_clock = os.clock
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleMissile_New = BattleMissile.New
local LMLinkList = plugins.gameutils.LMLinkList
local LMLinkNode = plugins.gameutils.LMLinkNode
local LMLinkList_New = LMLinkList.New
local LMLinkList_Add = LMLinkList.Add
local LMLinkList_AddNode = LMLinkList.AddNode
local LMLinkList_RemoveNode = LMLinkList.RemoveNode
local LMLinkList_Clear = LMLinkList.Clear
local LMLinkList_Find = LMLinkList.Find
local FLAGMAP = Utils.BuildFlagMap

local TSPlayer = gModel.TSPlayer
local TSRandom = gModel.TSRandom

---Constructor
function BattlePlayer:ctor( _isCoop, ... )  
	self.super = Super( ... )
	self.super.unitType = BattleUnitType.PLAYER

	-- 序列化数据
	self.playerId = false 							-- 玩家Id
	self.playerSeed = false 						-- 玩家种子，用于抽卡、选卡、合成随机
	self.towerPool = {} 							-- 玩家塔池
	self.hero = false								-- 玩家英雄
	self.serverId = false 							-- 玩家服务器Id
	self.playerName = false							-- 玩家名字
	self.playerLevel = false						-- 玩家等级
	self.criticalScale = 0							-- 额外暴击倍数

	-- 可序列化可运行时数据
	self.playerFrame = BattlePlayerFrame()			-- 玩家战斗帧

	-- 运行时数据
	self.playerIndex = 0							-- 玩家索引
	self.towerGradeList = {}						-- 玩家塔阶级列表
	self.randNum = false							-- 玩家随机数，独立种子，用于抽卡、合成、塔位置等运算
	self.idGenterator = {0, 0, 0, 0, 0, 0}			-- id生成器
	self.frameIdGenerator = 0						-- 帧Id生成器

	self.opponent = false							-- 对手

	self.point = 0									-- 点数
	self.costPoint = 0								-- 下次消耗点数
	self.curHP = 0									-- 当前血量
	self.maxHP = 0									-- 最大血量

	self.gridList = {}								-- 格子列表，索引代表位置
	self.towerList = {}								-- 塔列表，索引代表位置
	self.monsterList = {}							-- 怪物列表，不排序链表
	self.monsterSortList = {}						-- 怪物临时列表，自动排序链表
	self.colliderList = {}							-- 碰撞体列表，链表
	self.emptyPosList = {}							-- 空位置列表
	self.maxHPMonster = false						-- 最大血量怪物
	self.minHPMonster = false						-- 最小血量怪物
	self.missileList = {}							-- 子弹列表

	self.isConnectDirty = false						-- 连接池是否脏

	self.isSurrender = false 						-- 是否投降
	self.isCoop = _isCoop or false					-- 是否协作

	self.playerAI = false							-- 玩家AI

	self.totalStar = 0								-- 总星级
	self.isTotalStarDiry = false					-- 总星级标记						
end

function BattlePlayer:Serialize( ... )
	local tPlayer = TSPlayer:new{}
	tPlayer.Unit = self.super:Serialize()
	tPlayer.Point = self.point ~= 0 and self.point or nil
	tPlayer.CostPoint = self.costPoint
	tPlayer.CurHP = self.curHP
	tPlayer.TowerGradeList = {}
	for i = 1, #self.towerPool do
		table_insert(tPlayer.TowerGradeList, self.towerGradeList[self.towerPool[i]].grade)
	end
	tPlayer.GridList = {}
	for i = 1, #self.gridList do
		local grid = self.gridList[i]
		table_insert(tPlayer.GridList, grid:Serialize())
	end
	tPlayer.EmptyPosList = {}
	for i = 1, #self.emptyPosList do
		table_insert(tPlayer.EmptyPosList, self.emptyPosList[i])
	end
	tPlayer.MonsterList = {}
	for i = 1, #self.monsterList do
		local monster = self.monsterList[i]
		if not monster.isDie and monster.player == self then
			table_insert(tPlayer.MonsterList, monster:Serialize())
		end
	end
	tPlayer.ColliderList = {}
	local node = self.colliderList.first
	while node do
		table_insert(tPlayer.ColliderList, node.value:Serialize())
		node = node.next
	end
	tPlayer.MissileList = {}
	for frameCount, frameMissileList in pairs(self.missileList) do
		for i = 1, #frameMissileList do
			table_insert(tPlayer.MissileList, BattleMissile.Serialize(frameMissileList[i]))
		end
	end
	tPlayer.Hero = self.hero:Serialize()
	-- 随机数
	tPlayer.Random = TSRandom:new{}
	tPlayer.Random.PoolNum = tostring(self.randNum:GetPoolNum())
	tPlayer.Random.Count = self.randNum:GetCount()
	-- id生成器
	tPlayer.IdGenerator = {}
	for i = 1, #self.idGenterator do
		table_insert(tPlayer.IdGenerator, self.idGenterator[i])
	end
	-- 玩家帧下一帧索引
	tPlayer.NextFrameIndex = self.playerFrame.nextIndex
	-- AI
	if self.playerAI then
		tPlayer.PlayerAI = self.playerAI:Serialize()
	end

	return tPlayer
end

-- 先Load + Init，再反序列化
function BattlePlayer:DeSerialize( _tPlayer, _index, ... )
	if not _tPlayer or not _index then
		return
	end
	self.super:DeSerialize(_tPlayer.Unit)
	self.point = _tPlayer.Point or 0
	self.costPoint = _tPlayer.CostPoint
	self.curHP = _tPlayer.CurHP
	for i = 1, #self.towerPool do
		local towerGrade = self.towerGradeList[self.towerPool[i]]
		towerGrade.grade = _tPlayer.TowerGradeList[i]
		towerGrade.cost = Constants.BATTLE_GRADE_COST[towerGrade.grade]
		towerGrade.localGrade = towerGrade.grade
		if self.playerAI and towerGrade.grade > 1 then
			self.playerAI:OnTowerUpgrade(self.towerPool[i], towerGrade.grade)
		end
	end
	for i = 1, #self.gridList do
		local grid = self.gridList[i]
		grid:DeSerialize(_tPlayer.GridList[i], self, i)
		if grid.tower then
			self.towerList[i] = grid.tower
			self.totalStar = self.totalStar + grid.tower.star
			if self.playerAI then
				self.playerAI:OnTowerEnter(grid.tower)
			end
		end
	end
	self.emptyPosList = {}
	for i = 1, #_tPlayer.EmptyPosList do
		table_insert(self.emptyPosList, _tPlayer.EmptyPosList[i])
	end
	self.monsterList = {}
	for i = 1, #_tPlayer.MonsterList do
		local monster = BattleMonster()
		monster:DeSerialize(_tPlayer.MonsterList[i], self)
		monster.sortIndex = i
		table_insert(self.monsterList, monster)
	end
	LMLinkList_Clear(self.colliderList)
	for i = 1, #_tPlayer.ColliderList do
		local collider = BattleCollider()
		collider:DeSerialize(_tPlayer.ColliderList[i], self)
		collider.node = LMLinkList_Add(self.colliderList, collider)
	end
	self.missileList = {}
	for i = 1, #_tPlayer.MissileList do
		local missile = BattleMissile_New(false, false, false, false, false, false, false)
		BattleMissile.DeSerialize(missile, _tPlayer.MissileList[i])
		local frameMissileList = self.missileList[missile.hitFrame]
		if not frameMissileList then
			frameMissileList = {}
			self.missileList[missile.hitFrame] = frameMissileList
		end
		table_insert(frameMissileList, missile)
	end
	self.hero:DeSerialize(_tPlayer.Hero)
	self.randNum:Sync(tonumber(_tPlayer.Random.PoolNum), _tPlayer.Random.Count)
	for i = 1, #self.idGenterator do
		self.idGenterator[i] = _tPlayer.IdGenerator[i]
	end
	self.playerFrame.nextIndex = _tPlayer.NextFrameIndex
	-- AI 
	if self.playerAI then
		self.playerAI:DeSerialize(_tPlayer.PlayerAI)
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知前端更新点数，更新血量
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
		_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERHP, self.playerId, self.curHP, self.maxHP, false)-- 通知前端升级
		_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.UPGRADE, self.playerId)
	end)
end

function BattlePlayer:Load( _tPlayer, ... )  
	if not _tPlayer then
		return
	end

	self.playerId = _tPlayer.PlayerId
	self.playerSeed = _tPlayer.PlayerSeed
	self.towerPool = {}
	for i = 1, #_tPlayer.TowerPool do
		local towerResId = _tPlayer.TowerPool[i]
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if towerRes then
			table_insert(self.towerPool, towerResId)
			self.towerGradeList[towerResId] = {
				grade = 1,
				cost = Constants.BATTLE_GRADE_COST[1],
				localGrade = 1,
				bufferLayerList = nil
			}
		end
	end
	self.criticalScale = _tPlayer.CriticalScale or 0
	self.hero = BattleHero()
	self.hero:Load(_tPlayer.Hero)
	self.playerFrame = BattlePlayerFrame()
	self.playerFrame:Load(_tPlayer.PlayerFrame)
	if _tPlayer.PlayerAI then
		self.playerAI = BattlePlayerAI(_tPlayer.PlayerAI)
	end
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
	-- gBattleManager:AddBattleLog(string.format('Init Player [%d] Seed[%d] Tower[%s]', self.playerId, self.playerSeed, gameutils.JSON:encode(self.towerPool)))

	self.randNum = RandNum(self.playerSeed)
	self.playerFrame:Init(self)

	-- 初始化
	self.player = self
	self.unit = self
	self.opponent = gBattleRecord.playerList[_index % 2 + 1]
	self.unitId = self:GenerateUnitId(self.playerId)
	self.playerIndex = _index
	self.point = BattleConstants.BATTLE_INIT_POINT
	self.costPoint = BattleConstants.BATTLE_COST_POINT_STEP
	self.maxHP = BattleConstants.BATTLE_PLAYER_TOTAL_HP
	self.curHP = BattleConstants.BATTLE_PLAYER_TOTAL_HP

	-- 初始化塔列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		self.towerList[i] = false
		self.emptyPosList[i] = i

		-- 格子
		self.gridList[i] = BattleGrid()
		self.gridList[i]:Init(i, self)
	end

	-- 初始化碰撞体列表
	self.colliderList = LMLinkList_New(function( _lCollider, _rCollider, ... )
		return _lCollider.position < _rCollider.position and -1 or (_lCollider.position == _rCollider.position and 0 or 1)
	end)

	-- 初始化子弹列表
	self.missileList = {}

	-- 初始化英雄
	self.hero:Init(self)

	-- 初始化AI
	if self.playerAI then
		self.playerAI:Init(self)
	end

	-- 父类初始化
	self.super:Init()

	-- 通知前端添加玩家，更新点数，更新血量
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDPLAYER, self.playerId)
	_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
	_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERHP, self.playerId, self.curHP, self.maxHP, true)
end

T_TOWER = 0
T_MONSTER = 0

function BattlePlayer:Update( _deltaTime, ... )  
	-- 父类更新
	self.super:Update(_deltaTime, ...)
	-- 连接池
	if self.isConnectDirty then
		self:RefreshTowerConnect()
		self.isConnectDirty = false
	end
	-- 怪物
	-- PERF('MONSTER')
	-- time = os_clock()
	self:UpdateMonster(_deltaTime)
	-- T_MONSTER = T_MONSTER + os_clock() - time
	-- PERFEND()
	-- 英雄
	self.hero:Update(_deltaTime)
	local time = 0
	local gridList = self.gridList
	local towerList = self.towerList
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		-- 格子
		gridList[i]:Update(_deltaTime)
		-- 塔
		-- PERF('TOWER')
		-- time = os_clock()
		local tower = towerList[i]
		if tower then
			tower:Update(_deltaTime)
		end
		-- T_TOWER = T_TOWER + os_clock() - time
		-- PERFEND()
	end
	-- 子弹
	self:UpdateMissile()
	-- 碰撞
	local colliderNode = self.colliderList.first
	while colliderNode do
		colliderNode.value:Update(_deltaTime)
		colliderNode = colliderNode.next
	end
	-- AI更新
	if self.playerAI then
		self.playerAI:Update()
	end
	-- 刷新总星级
	self:UpdateTotalStar()
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
	frame.frameCount = _frameCount or (gBattleFrameCount + 1) 
	frame.frameType = _frameType
	frame.param1 = tostring(_param1 or '')
	frame.param2 = tostring(_param2 or '')
	frame.param3 = tostring(_param3 or '')
	frame.point = self.point
	frame.frameId = self:GenerateFrameId()
	return frame
end

function BattlePlayer:GenerateFrameId( ... )
	self.frameIdGenerator = self.frameIdGenerator + 1
	return self.frameIdGenerator
end

function BattlePlayer:GenerateId( _unitType, ... )
	local id = self.idGenterator[_unitType]
	id = id + 1
	self.idGenterator[_unitType] = id
	return id
end

function BattlePlayer:GenerateTowerId( ... )
	return self:GenerateId(BattleUnitType.TOWER)
end

function BattlePlayer:GenerateHeroId( ... )
	return self:GenerateId(BattleUnitType.HERO)
end

function BattlePlayer:GenerateMonsterId( ... )
	return self:GenerateId(BattleUnitType.MONSTER)
end

function BattlePlayer:GenerateColliderId( ... )
	return self:GenerateId(BattleUnitType.COLLIDER)
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

function BattlePlayer:ExecHeroTalent( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.HEROTALENT then
		return ErrorCode.FRAME_INVALID
	end
	local isLogic = _isLogic == nil and true or _isLogic
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return ErrorCode.SUCCESS
	end
	local code = self.hero:TryExecHeroTalent(BattleHeroTalentType.MANUAL)
	return code
end

function BattlePlayer:ExecSurrender( _frame, _isRealTime, _isLogic, ... )  
	if not _frame or _frame.frameType ~= BattleFrameType.SURRENDER then
		return ErrorCode.FRAME_INVALID
	end
	local isLogic = _isLogic == nil and true or _isLogic
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return ErrorCode.SUCCESS
	end
	self.isSurrender = true
	return ErrorCode.SUCCESS
end

function BattlePlayer:ExecUpgrade( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.UPGRADE then
		return ErrorCode.FRAME_INVALID
	end
	local isLogic = _isLogic == nil and true or _isLogic
	local needPending = not isLogic
	local isPended = self:CheckPendingFrame(_frame, needPending)
	if isPended then
		return ErrorCode.SUCCESS
	end

	local towerPoolIndex = tonumber(_frame.param1)
	local cost = self:GetTowerUpgradeCostByPoolIndex(towerPoolIndex)
	if cost == 0 then
		return ErrorCode.UPGRADE_FULLLEVEL
	end
	-- 校验点数是否充足
	if not self:IsPointEnough(cost) then
		error(string.format('Exec Upgrade Not Enough %d %d %d', self.playerId, self.point, cost))
		return ErrorCode.UPGRADE_POINTNOTENOUGH
	end

	-- 消耗点数
	self:ConsumePoint(cost)

	-- 消耗提升
	self:UpdateTowerUpgradeCostByIndex(towerPoolIndex, true)

	-- 尝试添加缓冲帧
	self:AddPenddingFrame(_frame, _isRealTime, needPending, isLogic)

	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:UpgradeTowerByFrame(_frame, towerPoolIndex)

	-- 战斗逻辑调用，立即通知缓存帧生效
	if isLogic then
		_frame:OnPendingOver()
	end

	return ErrorCode.SUCCESS
end

function BattlePlayer:ExecRoll( _frame, _isRealTime, _isLogic, ... )  
	if not _frame or _frame.frameType ~= BattleFrameType.ROLL then
		return ErrorCode.FRAME_INVALID
	end
	
	local isLogic = _isLogic == nil and true or _isLogic
	local needPending = not isLogic
	-- warn('ExecRoll', gBattleFrameCount, _frame.frameCount, self.playerId, isLogic, self.point, self.costPoint, self.randNum:GetPoolNum(), self.randNum:GetCount())
	local isPended = self:CheckPendingFrame(_frame, needPending)
	if isPended then
		return ErrorCode.SUCCESS
	end
	
	-- 校验点数是否充足
	if not self:IsPointEnough() then
		error(string.format('Exec Roll Point Not Enough %d %d %d', self.playerId, self.point, self.costPoint))
		return ErrorCode.ROLL_POINTNOTENOUGH
	end
	
	-- 随机塔位置
	local posIndex = self:RandomTowerPosIndex()
	if posIndex == 0 then
		return ErrorCode.ROLL_FULLGRID
	end
	
	-- 随机塔类型
	local towerResId = self:RandomTowerResId()
	local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
	if not towerRes then
		return ErrorCode.ROLL_TOWERRESINVALID
	end

	-- 消耗点数
	self:ConsumePoint()
	-- warn('ConsumePoint Roll', self.playerId, self.costPoint - BattleConstants.BATTLE_COST_POINT_STEP, self.point)

	-- 尝试添加缓冲帧
	self:AddPenddingFrame(_frame, _isRealTime, needPending, isLogic)

	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:AddTowerByFrame(_frame, towerRes, 1, posIndex, true, BattleTowerAddType.ROLL)

	-- 战斗逻辑调用，立即通知缓存帧生效
	if isLogic then
		_frame:OnPendingOver()
	end

	return ErrorCode.SUCCESS
end

-- 合并事件
local MergeSwitcher = {
	-- 普通合成
	[BattleTowerMergeType.MERGE] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _star, _targetTowerResId, _mergeUnitFlag, ... )
		local star = _star + 1
		local towerResId = self:RandomTowerResId()
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return ErrorCode.MERGE_TOWERRESINVALID
		end
		local dragTowerLeaveFlags = FLAGMAP(BattleUnitLeaveType.MERGE)
		local targetTowerLeaveFlags = FLAGMAP(BattleUnitLeaveType.MERGED)
		if _mergeUnitFlag == BattleUnitFlag.SUMMON then
			-- 召唤
			local dragTower = self:GetTowerByPos(_dragTowerIndex)
			local targetTower = self:GetTowerByPos(_targetTowerIndex)
			if dragTower.towerRes.birthFlag == BattleUnitFlag.SUMMON then
				dragTowerLeaveFlags[BattleUnitLeaveType.SUMMON] = 1
			else
				targetTowerLeaveFlags[BattleUnitLeaveType.SUMMON] = 1
			end
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, dragTowerLeaveFlags)
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, targetTowerLeaveFlags)
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, star, _targetTowerIndex, false, BattleTowerAddType.MERGE)
		-- 繁衍
		if _mergeUnitFlag == BattleUnitFlag.REPRODUCE then
			self:ReproduceTower(_frame, _star)
		end
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return ErrorCode.SUCCESS
	end,
	-- 营养
	[BattleTowerMergeType.FIX] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _star, _targetTowerResId, ... )
		local star = _star + 1
		local towerResId = _targetTowerResId
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return ErrorCode.MERGE_TOWERRESINVALID
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, FLAGMAP(BattleUnitLeaveType.MERGE))
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, FLAGMAP(BattleUnitLeaveType.MERGED))
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, star, _targetTowerIndex, false, BattleTowerAddType.FIX)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return ErrorCode.SUCCESS
	end,
	-- 交换
	[BattleTowerMergeType.EXCHANGE] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _star, ... )
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:ExchangeTowerByFrame(_frame, _dragTowerIndex, _targetTowerIndex)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return ErrorCode.SUCCESS
	end,
	-- 复制
	[BattleTowerMergeType.COPY] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _star, _targetTowerResId, ... )
		local star = _star
		local towerResId = _targetTowerResId
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return ErrorCode.MERGE_TOWERRESINVALID
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, FLAGMAP(BattleUnitLeaveType.MERGE))
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, star, _dragTowerIndex, false, BattleTowerAddType.COPY)
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return ErrorCode.SUCCESS
	end,
}

-- 繁衍
function BattlePlayer:ReproduceTower( _frame, _star, ... )
	local posIndex = self:RandomTowerPosIndex()
	if posIndex == 0 then
		return
	end
	local towerResId = self:RandomTowerResId()
	local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
	if not towerRes then
		return
	end
	local star = _star <= 2 and 1 or self.randNum:NextInt(_star - 1)
	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:AddTowerByFrame(_frame, towerRes, star, posIndex, false, BattleTowerAddType.REPRODUCE)
end

function BattlePlayer:ExecMerge( _frame, _isRealTime, _isLogic, ... )
	if not _frame or _frame.frameType ~= BattleFrameType.MERGE then
		return ErrorCode.FRAME_INVALID
	end

	local isLogic = _isLogic == nil and true or _isLogic
	local needPending = not isLogic
	local isPended = self:CheckPendingFrame(_frame, needPending)
	if isPended then
		return ErrorCode.SUCCESS
	end

	local dragTowerIndex = tonumber(_frame.param1)
	local targetTowerIndex = tonumber(_frame.param2)
	local param3 = tonumber(_frame.param3) or 0
	local mergeType = param3 % 10
	local star = 0
	local targetTowerResId = 0
	local mergeUnitFlag = 0

	if isLogic then
		-- 逻辑判定是否可以合并
		local dragTower = self:GetTowerByPos(dragTowerIndex)
		local targetTower = self:GetTowerByPos(targetTowerIndex)
		if not dragTower or not targetTower then
			return ErrorCode.MERGE_TOWERINVALID
		end
		local canMerge, logicMergeType, logicMergeUnitFlag = dragTower:CanMerge(targetTower)
		-- gBattleManager:AddBattleLog(string.format('ExecMerge Frame[%d] Player[%d] CaneMerge[%s] LogicMergeType[%d] FrameMergeType[%d] DragTower[%d] TargetTower[%d]', gBattleFrameCount, self.playerId, tostring(canMerge), logicMergeType, mergeType, dragTower.towerRes.birthFlag, targetTower.towerRes.birthFlag))
		-- warn(string.format('ExecMerge Frame[%d] Player[%d] CaneMerge[%s] LogicMergeType[%d] FrameMergeType[%d] DragTower[%d-%d] TargetTower[%d-%d]', gBattleFrameCount, self.playerId, tostring(canMerge), logicMergeType or 0, mergeType, dragTower.towerRes.baseId, dragTower.towerRes.birthFlag, targetTower.towerRes.baseId, targetTower.towerRes.birthFlag))
		if not canMerge or (mergeType ~= 0 and mergeType ~= logicMergeType) then
			return ErrorCode.MERGE_TYPENOTMATCH
		end
		star = dragTower.star
		targetTowerResId = targetTower.towerRes.id
		mergeType = logicMergeType
		mergeUnitFlag = logicMergeUnitFlag
	else
		mergeUnitFlag = math_floor(param3 / 10) % 100
		star = math_floor(param3 / 1000) % 10
		targetTowerResId = math_floor(param3 / 10000)
	end

	local switcher = MergeSwitcher[mergeType]
	if not switcher then
		return ErrorCode.MERGE_TYPENOTEXIST
	end

	local code = switcher(self, _frame, _isRealTime, isLogic, needPending, dragTowerIndex, targetTowerIndex, star, targetTowerResId, mergeUnitFlag)
	return code
end

function BattlePlayer:GetGrid( _gridIndex, ... )
	return self.gridList[_gridIndex] or false
end

function BattlePlayer:AddTower( _towerRes, _star, _posIndex, _isRoll, ... )  
	if not _towerRes or _star <= 0 then
		return false
	end

	local towerId = self:GenerateTowerId()
	local tower = BattleTower()
	-- _star = 7
	if not tower:Init(_towerRes, _star, towerId, _posIndex, self) then
		return false
	end

	-- 添加到塔列表
	self.towerList[_posIndex] = tower

	-- 进入格子
	self.gridList[_posIndex]:OnTowerEnter(tower)
	-- 通知AI添加塔
	if self.playerAI then
		self.playerAI:OnTowerEnter(tower)
	end

	-- 标记连接池已脏
	if tower:HasUnitFlag(BattleUnitFlag.CONNECT) then
		self.isConnectDirty = true
	end

	-- 改变总星级缓存
	self.totalStar = self.totalStar + _star
	self.isTotalStarDiry = true

	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Add Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d] Random[%d-%d]', gBattleFrameCount, self.playerId, towerId, _towerRes.baseId, _towerRes.level, _posIndex, self.randNum:GetPoolNum(), self.randNum:GetCount()))
	
	return tower
end

function BattlePlayer:AddTowerByFrame( _frame, _towerRes, _star, _posIndex, _isRoll, _addType, ... )
	if not _towerRes or _star <= 0 then
		return
	end
	local gbTower, pendingId = false, false
	if G_SendGBCommand then
		gbTower, pendingId = G_SendGBCommand(GBCommandType.ADDTOWER, self.playerId, _towerRes, _star, _posIndex, false, _addType)
	end
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.ADDTOWER, self, _towerRes, _star, _posIndex, pendingId)
	else
		local tower = self:AddTower(_towerRes, _star, _posIndex, _isRoll)
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PENDINGTOWER, self.playerId, tower, pendingId)
	end
	self:BusyTowerPos(_posIndex)
end

function BattlePlayer:UpgradeTower( _towerPoolIndex, ... )
	local towerResId = self.towerPool[_towerPoolIndex]
	if not towerResId then
		return
	end
	local towerGrade = self.towerGradeList[towerResId]
	if not towerGrade or towerGrade.grade == Constants.BATTLE_MAX_GRADE then
		return
	end
	-- 等级+1
	towerGrade.grade = towerGrade.grade + 1
	-- towerGrade.cost = Constants.BATTLE_GRADE_COST[towerGrade.grade]
	-- 通知同类塔升级
	for i = 1, #self.towerList do
		local tower = self.towerList[i]
		if tower and tower.towerRes.id == towerResId then
			tower:OnUpgrade(towerGrade.grade)
		end
	end

	-- 通知AI塔升阶
	if self.playerAI then
		self.playerAI:OnTowerUpgrade(towerResId, towerGrade.grade)
	end

	-- 通知关联状态层刷新
	local bufferLayerList = towerGrade.bufferLayerList
	if bufferLayerList then
		for i = 1, #bufferLayerList do
			local layer = bufferLayerList[i]
			layer.buffer:RefreshBufferLayer(layer)
		end
	end

	-- 通知前端升级
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.UPGRADE, self.playerId, _towerPoolIndex)

	-- gBattleManager:AddBattleLog(string.format('Upgrade Tower Frame[%d] Player[%d] Tower[%d] Grade[%d]', gBattleFrameCount, self.playerId, towerResId, towerGrade.grade))
end

function BattlePlayer:UpgradeTowerByFrame( _frame, _towerPoolIndex, ... )
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.UPGRADETOWER, self, _towerPoolIndex)
	else
		self:UpgradeTower(_towerPoolIndex)
	end
end

function BattlePlayer:RemoveTower( _posIndex, _leaveFlags, ... )
	local tower = self.towerList[_posIndex]
	if not tower then
		return
	end

	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Remove Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d]', gBattleFrameCount, self.playerId, tower.towerId, tower.towerRes.baseId, tower.towerRes.level, tower.posIndex))

	-- 标记连接池已脏
	if tower:HasUnitFlag(BattleUnitFlag.CONNECT) then
		self.isConnectDirty = true
	end

	-- 从格子移除
	self.gridList[_posIndex]:OnTowerLeave(self.towerList[_posIndex])
	-- 通知AI移除塔
	if self.playerAI then
		self.playerAI:OnTowerLeave(tower)
	end

	-- 从列表移除
	self.towerList[_posIndex] = false
	gBattleRecord:RemoveBattleUnit(tower.unitId)
	-- 销毁
	tower:Destroy(_leaveFlags)

	-- 改变总星级
	self.totalStar = self.totalStar - tower.star
	self.isTotalStarDiry = true
end

function BattlePlayer:RemoveTowerByFrame( _frame, _posIndex, _leaveFlags,  ... )  
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.REMOVETOWER, self.playerId, _posIndex)
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.REMOVETOWER, self, _posIndex, _leaveFlags)
	else
		self:RemoveTower(_posIndex, _leaveFlags)
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
	if self.playerAI then
		self.playerAI:OnTowerLeave(dragTower)
		self.playerAI:OnTowerLeave(targetTower)
	end

	-- 列表中交换位置
	self.towerList[_dragIndex] = targetTower
	self.towerList[_targetIndex] = dragTower

	dragTower.posIndex = _targetIndex
	targetTower.posIndex = _dragIndex

	-- 进入格子
	self.gridList[_dragIndex]:OnTowerEnter(targetTower)
	self.gridList[_targetIndex]:OnTowerEnter(dragTower)
	if self.playerAI then
		self.playerAI:OnTowerEnter(targetTower)
		self.playerAI:OnTowerEnter(dragTower)
	end

	-- 标记连接池已脏
	if targetTower:HasUnitFlag(BattleUnitFlag.CONNECT) or dragTower:HasUnitFlag(BattleUnitFlag.CONNECT) then
		self.isConnectDirty = true
	end
end

function BattlePlayer:ExchangeTowerByFrame( _frame, _dragIndex, _targetIndex, ... )  
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EXCHANGETOWER, self.playerId, _dragIndex, _targetIndex)
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.EXCHANGETOWER, self, _dragIndex, _targetIndex)
	else
		self:ExchangeTower(_dragIndex, _targetIndex)
	end
end

function BattlePlayer:ChangeTowerStar( _tower, _change, _frame, ... )
	if not _tower or _change == 0 then
		return
	end

	local isLogic = _triggerParam.isLogic
	local needPending = not isLogic

	local towerRes = _tower.towerRes
	local star = _tower.star
	star = star + _change

	-- 尝试添加缓冲帧
	if _frame then
		self:AddPenddingFrame(_frame, gBattleRecord.isRealTime, needPending, isLogic)
	end

	-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
	local posIndex = _tower.posIndex
	self:RemoveTowerByFrame(_frame, posIndex, FLAGMAP(_change > 0 and BattleUnitLeaveType.ADDSTAR or BattleUnitLeaveType.SUBSTAR))

	-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
	self:AddTowerByFrame(_frame, towerRes, star, posIndex, false)

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
	return self.towerList[_posIndex] or false
end

function BattlePlayer:RandomTowerResId( _randNum, ... )
	local randNum = _randNum or self.randNum
	local index = randNum:NextInt(#self.towerPool)
	return self.towerPool[index]
end

function BattlePlayer:RandomTowerPosIndex( _randNum, ... )
	-- 塔满，没有空余位置
	if #self.emptyPosList == 0 then
		return 0
	end
	local index = 1
	local randNum = _randNum or self.randNum
	if #self.emptyPosList > 1 then
		index = randNum:NextInt(#self.emptyPosList)
		-- warn('RandomTowerPosIndex', self.playerId, index, self.emptyPosList[index], gameutils.JSON:encode(self.emptyPosList),  #self.emptyPosList, self.randNum:GetPoolNum(), self.randNum:GetCount())
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

function BattlePlayer:GetTowerResIdByPoolIndex( _index, ... )
	return self.towerPool[_index]
end

function BattlePlayer:GetTowerGrade( _towerResId, ... )
	local towerGrade = self.towerGradeList[_towerResId]
	if not towerGrade then
		return 1
	end
	return towerGrade.grade
end

function BattlePlayer:GetTowerGradeByPoolIndex( _index, ... )
	local towerResId = self.towerPool[_index]
	return self:GetTowerGrade(towerResId)
end

function BattlePlayer:GetTowerUpgradeCostByPoolIndex( _index, ... )
	local towerResId = self.towerPool[_index]
	local towerGrade = self.towerGradeList[towerResId]
	if not towerGrade then
		return Constants.BATTLE_GRADE_COST[1]
	end
	return towerGrade.cost
end

function BattlePlayer:UpdateTowerUpgradeCostByIndex( _index, _isUpgrade, ... )
	local towerResId = self.towerPool[_index]
	local towerGrade = self.towerGradeList[towerResId]
	if not towerGrade then
		return
	end
	if _isUpgrade then
		towerGrade.localGrade = towerGrade.localGrade + 1
		towerGrade.cost = Constants.BATTLE_GRADE_COST[towerGrade.localGrade]
	else
		towerGrade.localGrade = towerGrade.grade
		towerGrade.cost = Constants.BATTLE_GRADE_COST[towerGrade.grade]
	end
	-- warn('UpdateTowerUpgradeCostByIndex', _index, towerGrade.cost, towerGrade.grade, towerGrade.localGrade)
end

function BattlePlayer:AddMonster( _id, _monsterHP, _position, ... )
	local monsterRes = GameResMgr.GetBattleMonsterRes(_id)
	if not monsterRes then
		return false
	end
	
	local monsterId = self:GenerateMonsterId()
	local monster = BattleMonster()
	if not monster:Init(monsterRes, monsterId, self, _monsterHP, _position) then
		return false
	end
	
	-- 添加到怪物列表
	monster.sortIndex = #self.monsterList + 1
	table_insert(self.monsterList, monster)
	-- 通知前端添加怪物
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDMONSTER, self.playerId, monsterId)
	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Add Monster Frame[%d] Player[%d] Monster[%d-%d]', gBattleFrameCount, self.playerId, monsterId, _id))
	
	return monster
end

function BattlePlayer:RemoveMonster( _monsterId, _leaveFlags, ... )
	local monster = self:GetMonster(_monsterId)
	if not monster then
		return false
	end

	-- 通知前端移除怪物
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.REMOVEMONSTER, self.playerId, _monsterId)
	-- 从列表移除
	gBattleRecord:RemoveBattleUnit(monster.unitId)
	-- 销毁
	monster:Destroy(_leaveFlags)

	return true
end

function BattlePlayer:RemoveAllMonster( _leaveFlags, _isBossRemove, ... ) 
	local isBossRemove = _isBossRemove == nil and true or _isBossRemove
	local nextMonsterList = {}
	for i = 1, #self.monsterList do
		local monster = self.monsterList[i]
		if isBossRemove or monster.monsterRes.type ~= MonsterType.BOSS then
			self:RemoveMonster(monster.monsterId, _leaveFlags)
		else
			table_insert(nextMonsterList, monster)
		end
	end
	self.monsterList = nextMonsterList
end

function BattlePlayer.SortMonster( _monster, _nextMonsterList, ... )
	local length = #_nextMonsterList
	if length == 0 then
		_nextMonsterList[1] = _monster
	else
		local canInsert = false
		local result = 0
		for n = length, 1, -1 do
			local preMonster = _nextMonsterList[n]
			canInsert = false
			result = preMonster.position - _monster.position
			if result > 0 then
				canInsert = true
			elseif result == 0 then
				-- 位置相同，比较怪物Id
				result = preMonster.monsterId - _monster.monsterId
				if result < 0 then
					canInsert = true
				elseif result == 0 then
					-- 位置相同，怪物Id相同，则比较玩家Id
					result = preMonster.player.playerId - _monster.player.playerId
					if result < 0 then
						canInsert = true
					end
				end
			end
			if canInsert then
				-- 插入
				if n == length then
					table_insert(_nextMonsterList, _monster)
				else
					table_insert(_nextMonsterList, n + 1, _monster)
				end
				break
			end
			if n == 1 then
				table_insert(_nextMonsterList, 1, _monster)
				break
			end
		end
	end
end

function BattlePlayer:UpdateMonster( _deltaTime, ... )
	if self.isCoop then
		-- self:CoopUpdateMonster(_deltaTime)
		return
	end
	self:PkUpdateMonster(_deltaTime)
end

function BattlePlayer:PkUpdateMonster( _deltaTime, ... )
	local monsterList = self.monsterList
	local nextMonsterList = self.monsterSortList
	for i = 1, #monsterList do
		local monster = monsterList[i]
		monster:Update(_deltaTime)
	end
	-- 排序
	for i = 1, #monsterList do
		local monster = monsterList[i]
		if not monster.isDie then
			-- 插入排序列表
			SortMonster(monster, nextMonsterList)
		end
		monsterList[i] = nil
	end
	local maxHPMonster = nextMonsterList[1] or false
	local minHPMonster = nextMonsterList[1] or false
	for i = 1, #nextMonsterList do
		local monster = nextMonsterList[i]
		monsterList[i] = monster
		monster.sortIndex = i
		nextMonsterList[i] = nil

		-- 最大血量怪物
		if maxHPMonster.curHP < monster.curHP then
			maxHPMonster = monster
		end
		-- 最小血量怪物
		if minHPMonster.curHP > monster.curHP then
			minHPMonster = monster
		end
	end
	self.maxHPMonster = maxHPMonster
	self.minHPMonster = minHPMonster
end

function BattlePlayer:CoopUpdateMonster( _deltaTime, _commonMonsterList, ... )
	local monsterList = self.monsterList
	local nextMonsterList = self.monsterSortList

	if _deltaTime > 0 then
		for i = 1, #monsterList do
			local monster = monsterList[i]
			if monster.player == self then
				monster:Update(_deltaTime)
			end
		end
	end
	for i = 1, #monsterList do
		local monster = monsterList[i]
		-- 共用怪物
		if not monster.isDie and monster.player == self then
			if monster.position >= BattleConstants.BATTLE_COOP_CORNER then
				SortMonster(monster, _commonMonsterList)
			else
				SortMonster(monster, nextMonsterList)
			end
		end
		monsterList[i] = nil
	end
end

function BattlePlayer:CoopSortMonster( _commonMonsterList, _clearCommon, ... )
	local monsterList = self.monsterList
	local nextMonsterList = self.monsterSortList

	local maxHPMonster = nextMonsterList[1] or _commonMonsterList[1] or false
	local minHPMonster = nextMonsterList[1] or _commonMonsterList[1] or false
	local commonMonsterCount = #_commonMonsterList
	for i = 1, commonMonsterCount do
		local monster = _commonMonsterList[i]
		monsterList[i] = monster
		monster.sortIndex = i
		if _clearCommon then
			_commonMonsterList[i] = nil
		end

		-- 最大血量怪物
		if maxHPMonster.curHP < monster.curHP then
			maxHPMonster = monster
		end
		-- 最小血量怪物
		if minHPMonster.curHP > monster.curHP then
			minHPMonster = monster
		end
	end
	for i = 1, #nextMonsterList do
		local monster = nextMonsterList[i]
		monsterList[i + commonMonsterCount] = monster
		monster.sortIndex = i + commonMonsterCount
		nextMonsterList[i] = nil

		-- 最大血量怪物
		if maxHPMonster.curHP < monster.curHP then
			maxHPMonster = monster
		end
		-- 最小血量怪物
		if minHPMonster.curHP > monster.curHP then
			minHPMonster = monster
		end
	end
	self.maxHPMonster = maxHPMonster
	self.minHPMonster = minHPMonster
end

function BattlePlayer:GetMonster( _monsterId, ... )
	for i = 1, #self.monsterList do
		local monster = self.monsterList[i]
		if monster.monsterId == _monsterId and monster.player == self then
			return monster
		end
	end
	return false
end

function BattlePlayer:GetMonsterCount( ... )
	local count = 0
	for i = 1,#self.monsterList do
		if not self.monsterList[i].isDie then
			count = count + 1
		end
	end
	return count
end

function BattlePlayer:AddCollider( _id, _owner, _triggerUnit, ... )
	local colliderRes = GameResMgr.GetBattleColliderRes(_id)
	if not colliderRes then
		return false
	end

	if not _owner then
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
	if not collider:Init(colliderRes, colliderId, _owner, self, position) then
		return false
	end

	-- 添加到怪物列表
	collider.node = LMLinkList_Add(self.colliderList, collider)
	-- 通知前端添加碰撞
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDCOLLIDER, self.playerId, colliderId)
	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Add Collider Frame[%d] Player[%d] Collider[%d-%d-%d-%s]', gBattleFrameCount, self.playerId, colliderId, _id, position, _owner.unitId))
	
	return collider
end

function BattlePlayer:RemoveCollider( _colliderId, _leaveFlags, ... )
	local collider = self:GetCollider(_colliderId)
	if not collider then
		return
	end

	-- 通知前端移除碰撞
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.REMOVECOLLIDER, self.playerId, _colliderId)
	-- 从列表移除
	LMLinkList_RemoveNode(self.colliderList, collider.node)
	gBattleRecord:RemoveBattleUnit(collider.unitId)
	-- 销毁
	collider:Destroy(_leaveFlags)
end

function BattlePlayer:GetCollider( _colliderId, ... )
	local colliderNode = LMLinkList_Find(self.colliderList, _colliderId, 'colliderId')
	if colliderNode then
		return colliderNode.value
	end
	return false
end

local UnitRemoveSwitcher = {
	[BattleUnitType.TOWER] = function( self, _unit, _leaveFlags, ... )  
		self:RemoveTower(_unit.posIndex, _leaveFlags)
	end,
	[BattleUnitType.MONSTER] = function( self, _unit, _leaveFlags, ... )  
		self:RemoveMonster(unit.monsterId, _leaveFlags)
	end,
	[BattleUnitType.COLLIDER] = function( self, _unit, _leaveFlags, ... )  
		self:RemoveCollider(unit.colliderId, _leaveFlags)
	end,
}

function BattlePlayer:RemoveUnit( _unit, _leaveFlags, ... )  
	local switcher = UnitRemoveSwitcher[_unit.unitType]
	if switcher then
		switcher(self, _unit, _leaveFlags)
	end	
end

function BattlePlayer:IsPointEnough( _costPoint, ... )
	local costPoint = _costPoint or self.costPoint
	return self.point >= costPoint
end

-- 消耗点数
function BattlePlayer:ConsumePoint( _costPoint, ... )
	local costPoint = _costPoint or self.costPoint
	self.point = self.point - costPoint
	if not _costPoint then
		self.costPoint = self.costPoint + BattleConstants.BATTLE_COST_POINT_STEP
		-- self.costPoint = 0
	end
	-- warn('ConsumePoint', self.playerId, self.point, costPoint)
	-- gBattleManager:AddBattleLog(string.format('ConsumePoint Player[%d] Cost[%d] Point[%d] Frame[%d]', self.playerId, costPoint, self.point, gBattleFrameCount))

	-- 通知前端更新点数
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
end

-- 增加点数
function BattlePlayer:AddPoint( _point, ... )
	if not _point then
		return 0
	end

	if _point > 0 then
		-- Point收益百分比
		_point = math_floor(_point * (1 + self:GetAttribute(AttriType.POINTPERCENT) * s_PercentScale))
		_point = _point < 0 and 0 or _point
	else
		_point = (self.point + _point < 0) and -self.point or _point
	end
	-- gBattleManager:AddBattleLog(string.format('AddPoint Player[%d] Add[%d] Point[%d] Frame[%d]', self.playerId, _point, self.point, gBattleFrameCount))
	self.point = self.point + _point

	-- 通知前端更新点数
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)

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

-- 刷新连接池
function BattlePlayer:RefreshTowerConnect( ... )
	local connectTowerList = {}
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local tower = self.towerList[i]
		if tower and tower:HasUnitFlag(BattleUnitFlag.CONNECT) then
			tower:ResetConnectCount()
			table_insert(connectTowerList, tower)
		end
	end
	for i = 1, #connectTowerList do
		local tower = connectTowerList[i]
		if tower:GetConnectCount() == -1 then
			local list = {}
			tower:RefreshTowerConnect(list)
			local connectCount = #list
			for n = 1, #list do
				list[n]:SetConnectCount(connectCount)
			end
		end
	end
end

function BattlePlayer:AddMissile( _tower, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes, ... )
	local missile = BattleMissile_New(_tower, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes)
	local frameMissileList = self.missileList[_hitFrame]
	if not frameMissileList then
		frameMissileList = {}
		self.missileList[_hitFrame] = frameMissileList
	end
	table_insert(frameMissileList, missile)
	-- 通知前端发射
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FIRE, _tower.unitId, missile)
end

function BattlePlayer:UpdateMissile( ... )
	local frameMissileList = self.missileList[gBattleFrameCount]
	if not frameMissileList then
		return
	end
	for i = 1, #frameMissileList do
		local missile = frameMissileList[i]
		local targetMonster = gBattleRecord:GetBattleUnit(missile.targetUnitId)
		if targetMonster then
			-- 触发攻击  
			local attacker = missile.tower
			local triggerParam = BattleTriggerParam_New(attacker, attacker, { targetMonster }, { starIndex = missile.starIndex, attackTimes = missile.attackTimes })
			gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
			-- 计算伤害
			local damage = missile.damage + triggerParam.extraDamage
			local isCritical = false
			damage, isCritical = attacker:CalcDamage(damage, targetMonster, nil, nil, false)
			-- 怪物被击
			targetMonster:OnAttackDamage(attacker, damage, nil, nil, isCritical and BattleDamageType.CRITICAL or BattleDamageType.NORMAL)
		end
	end
	self.missileList[gBattleFrameCount] = nil
end

function BattlePlayer:UpdateTotalStar( ... )
	if not self.isTotalStarDiry then
		return
	end
	local isLowerOpponent = self.totalStar < self.opponent.totalStar
	local isOpponentLower = self.opponent.totalStar < self.totalStar
	self:FireAllTowerTrigger(true, BattleTriggerType.TOTALSTAR, tostring(isLowerOpponent and -1 or 1))
	self.opponent:FireAllTowerTrigger(true, BattleTriggerType.TOTALSTAR, tostring(isOpponentLower and -1 or 1))
end

function BattlePlayer:FireAllTowerTrigger( _isFlagTrigger, _triggerType, _triggerValue, ... )
	for i = 1, #self.towerList do
		local tower = self.towerList[i]
		if tower then
			tower:FireTrigger(_isFlagTrigger, _triggerType, _triggerValue)
		end
	end
end

function BattlePlayer:BindGradeBufferLayer( _towerResId, _bufferLayer, ... )
	local bufferLayerList = self.towerGradeList[_towerResId].bufferLayerList
	if not bufferLayerList then
		bufferLayerList = {}
		self.towerGradeList[_towerResId].bufferLayerList = bufferLayerList
	end
	table_insert(bufferLayerList, _bufferLayer)
end

function BattlePlayer:UnBindGradeBufferLayer( _towerResId, _bufferLayer, ... )
	local bufferLayerList = self.towerGradeList[_towerResId].bufferLayerList
	if not bufferLayerList then
		return
	end
	for i = 1, #bufferLayerList do
		if bufferLayerList[i] == _bufferLayer then
			table_remove(bufferLayerList, i)
			break
		end 
	end
end

classend()
export('BattlePlayer', BattlePlayer)