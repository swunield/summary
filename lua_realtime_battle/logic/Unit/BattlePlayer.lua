---
--- class BattlePlayer
-- @classmod BattlePlayer
-- 玩家
BattlePlayer = xclass('BattlePlayer', BattleUnit)

local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local math_ceil = math.ceil
local os_clock = os.clock
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy
local BattleMissile_New = BattleMissile.New
local BattleMissile_Destroy = BattleMissile.Destroy
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
local TS2Int = gModel.TS2Int
local TS3Int = gModel.TS3Int

local SortMonster = false
local EncodePosList = false

---Constructor
function BattlePlayer:ctor( _isCoop, ... )  
	self.super.unitType = BattleUnitType.PLAYER

	-- 序列化数据
	self.playerId = false 							-- 玩家Id
	self.playerIndex = 0							-- 玩家索引
	self.playerSeed = false 						-- 玩家种子，用于抽卡、选卡、合成随机
	self.fieldId = 0								-- 战场背景Id
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
	self.towerInfoList = {}							-- 玩家塔信息列表
	self.towerBaseInfoList = {}						-- 玩家塔基础Id信息
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
	self.posList = {}								-- 空位置列表
	self.emptyPosCount = 0							-- 空格子数量
	self.maxHPMonster = false						-- 最大血量怪物
	self.minHPMonster = false						-- 最小血量怪物
	self.missileList = {}							-- 子弹列表
	self.skillList = {}								-- 技能列表

	self.isConnectDirty = false						-- 连接池是否脏

	self.isSurrender = false 						-- 是否投降
	self.isCoop = _isCoop or false					-- 是否协作

	self.playerAI = false							-- 玩家AI

	self.totalStar = 0								-- 总星级
	self.isTotalStarDirty = false					-- 总星级标记						
end

function BattlePlayer:Serialize( ... )
	local tPlayer = TSPlayer:new{}
	tPlayer.Unit = self.super:Serialize()
	tPlayer.Point = self.point ~= 0 and self.point or nil
	tPlayer.CostPoint = self.costPoint
	tPlayer.CurHP = self.curHP
	tPlayer.TowerGradeList = {}
	for i = 1, #self.towerPool do
		table_insert(tPlayer.TowerGradeList, self.towerInfoList[self.towerPool[i]].grade)
	end
	tPlayer.GridList = {}
	for i = 1, #self.gridList do
		local grid = self.gridList[i]
		table_insert(tPlayer.GridList, grid:Serialize())
	end
	tPlayer.PosList = {}
	for i = 1, #self.posList do
		tPlayer.PosList[i] = self.posList[i]
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
	-- 技能
	tPlayer.SkillList = {}
	for i = 1, #self.skillList do
		local tSkill = self.skillList[i]:Serialize()
		if tSkill then
			table_insert(tPlayer.SkillList, tSkill)
		end
	end
	-- 参数列表
	for paramType, param in pairs(self.paramMap) do
		if not tPlayer.ParamList then
			tPlayer.ParamList = {}
		end
		local tValue = TS3Int:new{}
		tValue.Arg0 = paramType
		tValue.Arg1 = param.value ~= 0 and param.value or nil
		tValue.Arg2 = param.nextValue ~= 0 and param.nextValue or nil
		table_insert(tPlayer.ParamList, tValue)
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
		local towerInfo = self.towerInfoList[self.towerPool[i]]
		towerInfo.grade = _tPlayer.TowerGradeList[i]
		towerInfo.cost = Constants.BATTLE_GRADE_COST[towerInfo.grade]
		towerInfo.localGrade = towerInfo.grade
		if self.playerAI and towerInfo.grade > 1 then
			self.playerAI:OnTowerUpgrade(self.towerPool[i], towerInfo.grade)
		end
	end
	self.totalStar = 0
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
	self.posList = {}
	self.emptyPosCount = 0
	for i = 1, #_tPlayer.PosList do
		self.posList[i] = _tPlayer.PosList[i]
		if self.posList[i] == 0 then
			self.emptyPosCount = self.emptyPosCount + 1
		end
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
	-- 技能
	self.skillList = {}
	for i = 1, #_tPlayer.SkillList do
		local tSkill = _tPlayer.SkillList[i]
		local skill = BattleSkill.Create(tSkill.Type)
		skill:DeSerialize(tSkill)
		table_insert(self.skillList, skill)
	end
	-- 参数列表
	if _tPlayer.ParamList then
		for i = 1, #_tPlayer.ParamList do
			local tValue = _tPlayer.ParamList[i]
			local param = self.paramMap[tValue.Arg0]
			param.value = tValue.Arg1 or 0
			param.nextValue = tValue.Arg2 or 0
			if (param.default.notifyParam and param.value ~= param.nextValue) or param.nextValue == 1 then
				self.isParamDirty = true
			end
		end
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知前端更新点数，更新血量
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
		_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERHP, self.playerId, self.curHP, self.maxHP, false)
		_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.UPGRADE, self.playerId)
		self:NotifyPlayerParam()
	end)
end

function BattlePlayer:Load( _tPlayer, _index, ... )  
	if not _tPlayer then
		return
	end

	self.playerId = _tPlayer.PlayerId
	self.playerIndex = _index
	self.playerSeed = _tPlayer.PlayerSeed
	self.playerName = _tPlayer.PlayerName
	self.playerLevel = _tPlayer.PlayerLevel
	self.fieldId = _tPlayer.FieldId or 0
	self.towerPool = {}
	for i = 1, #_tPlayer.TowerPool do
		local towerResId, awakenIndex, awakenLevel = DecodeAwaken(_tPlayer.TowerPool[i])
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if towerRes then
			table_insert(self.towerPool, towerResId)
			local towerInfo = {
				grade = 1,
				level = towerRes.level,
				cost = Constants.BATTLE_GRADE_COST[1],
				localGrade = 1,
				bufferLayerList = nil,
				poolIndex = i,
				awakenTalentId = GameResMgr.GetAwakenTalentId(towerRes, awakenIndex, awakenLevel),
				awakenIndex = awakenIndex,
				awakenLevel = awakenLevel
			}
			self.towerInfoList[towerResId] = towerInfo
			self.towerBaseInfoList[towerRes.baseId] = towerInfo
			self:InitParam(towerRes.paramList) 
		end
	end
	self.criticalScale = _tPlayer.CriticalScale or 0
	local tPlayerAI = _tPlayer.PlayerAI
	self.hero = BattleHero()
	self.hero:Load(_tPlayer.Hero, tPlayerAI and tPlayerAI.HeroFactor)
	self.playerFrame = BattlePlayerFrame()
	self.playerFrame:Load(_tPlayer.PlayerFrame)
	if tPlayerAI then
		self.playerAI = BattlePlayerAI(tPlayerAI)
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
	self.unitId = self:GenerateUnitId(0)
	self.playerIndex = _index
	self.point = Constants.BATTLE_INIT_POINT
	self.costPoint = Constants.BATTLE_COST_POINT_STEP
	self.maxHP = BattleConstants.BATTLE_PLAYER_TOTAL_HP
	self.curHP = BattleConstants.BATTLE_PLAYER_TOTAL_HP

	-- 初始化塔列表
	self.emptyPosCount = BattleConstants.BATTLE_MAX_TOWER
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		self.towerList[i] = false
		self.posList[i] = 0

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
	self:InitHero()

	-- 初始化AI
	if self.playerAI then
		self.playerAI:Init(self)
	end

	-- 父类初始化
	self.super:Init(true)

	-- 通知前端添加玩家，更新点数，更新血量
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDPLAYER, self.playerId)
	_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.POINT, self.playerId, self.point, self.costPoint)
	_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERHP, self.playerId, self.curHP, self.maxHP, true)
end


-- 初始化英雄
function BattlePlayer:InitHero( ... )
	self.hero:Init(self)

	-- 初始化参数列表
	local paramType = self.hero.heroRes.param
	if paramType ~= 0 then
		self:InitParam({ paramType }) 
	end
end

T_TOWER = 0
T_MONSTER = 0

function BattlePlayer:Update( _deltaTime, _battleTime, ... )  
	-- 更新状态
	local carryBufferList = self.carryBufferList
	local bufferCount = #carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end
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
	-- 技能
	local skillList = self.skillList
	for i = #skillList, 1, -1 do
		if not skillList[i]:Update(_deltaTime) then
			skillList[i]:Destroy()
			table_remove(skillList, i)
		end
	end
	-- 碰撞
	local colliderNode = self.colliderList.first
	while colliderNode do
		colliderNode.value:Update(_deltaTime)
		colliderNode = colliderNode.next
	end
	-- AI更新
	if self.playerAI then
		self.playerAI:Update(_battleTime)
	end
end

function BattlePlayer:LateUpdate( ... )
	-- 刷新总星级
	self:UpdateTotalStar()
	-- 刷新参数
	self:UpdateParam()
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
	-- local needPending = not isLogic
	-- local isPended = self:CheckPendingFrame(_frame, needPending)
	-- if isPended then
	-- 	return ErrorCode.SUCCESS
	-- end
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return ErrorCode.SUCCESS
	end

	local towerPoolIndex = tonumber(_frame.param1)
	local cost = self:GetTowerUpgradeCostByPoolIndex(towerPoolIndex)
	if cost == 0 then
		return ErrorCode.UPGRADE_FULLLEVEL
	end
	-- 校验点数是否充足
	if not self:IsPointEnough(cost) then
		warn(string.format('Exec Upgrade Not Enough %d %d %d', self.playerId, self.point, cost))
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
	-- warn('ExecRoll', gBattleFrameCount, _frame.frameCount, self.playerId, isLogic, self.point, self.costPoint, self.randNum:GetPoolNum(), self.randNum:GetCount())
	-- local needPending = not isLogic
	-- local isPended = self:CheckPendingFrame(_frame, needPending)
	-- if isPended then
	-- 	return ErrorCode.SUCCESS
	-- end
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
		return ErrorCode.SUCCESS
	end
	
	-- 校验点数是否充足
	if not self:IsPointEnough() then
		warn(string.format('Exec Roll Point Not Enough %d %d %d', self.playerId, self.point, self.costPoint))
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
	-- warn('ConsumePoint Roll', self.playerId, self.costPoint - Constants.BATTLE_COST_POINT_STEP, self.point)

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

local MergeLeaveFlags = {
	[BattleUnitFlag.SUMMON] = BattleUnitLeaveType.SUMMON,
	[BattleUnitFlag.KILL] = BattleUnitLeaveType.KILL,
	[BattleUnitFlag.HACKER] = BattleUnitLeaveType.HACKER,
}

local MergeAddFlags = {
	[BattleUnitFlag.KILL] = BattleTowerAddType.KILL,
}

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
		local dragTowerLeaveFlags = FLAGMAP(BattleUnitLeaveType.MERGE, 1, BattleUnitLeaveType.POSINDEX, _targetTowerIndex)
		local targetTowerLeaveFlags = FLAGMAP(BattleUnitLeaveType.MERGED, 1, BattleUnitLeaveType.POSINDEX, _targetTowerIndex)
		local mergeLeaveFlag = MergeLeaveFlags[_mergeUnitFlag]
		if mergeLeaveFlag then
			-- 召唤
			local dragTower = self:GetTowerByPos(_dragTowerIndex)
			local targetTower = self:GetTowerByPos(_targetTowerIndex)
			if dragTower.towerRes.birthFlag == _mergeUnitFlag then
				dragTowerLeaveFlags[mergeLeaveFlag] = 1
			else
				targetTowerLeaveFlags[mergeLeaveFlag] = 1
			end
		end

		-- 触发合成
		local triggerParam = BattleTriggerParam_New(self)
		gBattleTrigger:FireTrigger(BattleTriggerType.MERGE, triggerParam)
		local extraStar = triggerParam.extraStar
		BattleTriggerParam_Destroy(triggerParam)

		-- 额外星级处理
		if extraStar + star > Constants.BATTLE_MAX_STAR then
			extraStar = Constants.BATTLE_MAX_STAR - star
		end
		star = star + extraStar

		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _dragTowerIndex, dragTowerLeaveFlags)
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, targetTowerLeaveFlags)
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, star, _targetTowerIndex, false, MergeAddFlags[_mergeUnitFlag] or BattleTowerAddType.MERGE, extraStar > 0)
		
		if _mergeUnitFlag == BattleUnitFlag.REPRODUCE then
			-- 繁衍
			self:ReproduceTower(_frame, _star)
		elseif _mergeUnitFlag == BattleUnitFlag.COMBO then
			-- 连接
			self:AddParamValue(BattleParamType.COMBO, 1)
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
	-- 重构
	[BattleTowerMergeType.REBUILD] = function( self, _frame, _isRealTime, _isLogic, _needPending, _dragTowerIndex, _targetTowerIndex, _star, _targetTowerResId, ... )
		local star = _star
		local towerResId = self:RandomTowerResId(nil, _targetTowerResId)
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if not towerRes then
			return ErrorCode.MERGE_TOWERRESINVALID
		end
		-- 尝试添加缓冲帧
		self:AddPenddingFrame(_frame, _isRealTime, _needPending, _isLogic)
		-- 通知前端移除塔，并缓存移除塔行为至逻辑帧
		self:RemoveTowerByFrame(_frame, _targetTowerIndex, FLAGMAP(BattleUnitLeaveType.MERGED))
		-- 通知前端添加塔，并缓存添加塔行为至逻辑帧
		self:AddTowerByFrame(_frame, towerRes, star, _targetTowerIndex, false, BattleTowerAddType.REBUILD)
		-- 源塔重新触发进场
		local dragTower = self:GetTowerByPos(_dragTowerIndex)
		if dragTower then
			dragTower:Enter()
		end
		-- 战斗逻辑调用，立即通知缓存帧生效
		if _isLogic then
			_frame:OnPendingOver()
		end
		return ErrorCode.SUCCESS
	end
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
	-- local needPending = not isLogic
	-- local isPended = self:CheckPendingFrame(_frame, needPending)
	-- if isPended then
	-- 	return ErrorCode.SUCCESS
	-- end
	self:AddPenddingFrame(_frame, _isRealTime, false, isLogic)
	if not isLogic then
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
		-- gBattleManager:AddBattleLog(string.format('ExecMerge Frame[%d] Player[%d] CaneMerge[%s] LogicMergeType[%d] FrameMergeType[%d] DragTower[%d] TargetTower[%d]', gBattleFrameCount, self.playerId, tostring(canMerge), logicMergeType or 0, mergeType, dragTower.towerRes.birthFlag, targetTower.towerRes.birthFlag))
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

function BattlePlayer:AddTower( _towerRes, _star, _posIndex, _isRoll, _pendingId, ... )  
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

	if _pendingId then
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PENDINGTOWER, self.playerId, tower, _pendingId)
	end

	-- 进入
	tower:Enter()

	-- 进入格子
	self.gridList[_posIndex]:OnTowerEnter(tower)
	-- 通知AI添加塔
	if self.playerAI then
		self.playerAI:OnTowerEnter(tower)
	end

	-- 标记连接池已脏
	if HasBattleFlag(tower.unitFlag, BattleUnitFlag.CONNECT) then
		self.isConnectDirty = true
	end

	-- 改变总星级缓存
	self.totalStar = self.totalStar + _star
	self.isTotalStarDirty = true

	-- 更新参数
	if #_towerRes.paramList > 0 then
		self:AddParamValue(_towerRes.paramList[1], 1, _towerRes.baseId)
	end

	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Add Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d] Random[%d-%d]', gBattleFrameCount, self.playerId, towerId, _towerRes.baseId, _towerRes.level, _posIndex, self.randNum:GetPoolNum(), self.randNum:GetCount()))
	
	return tower
end

function BattlePlayer:AddTowerByFrame( _frame, _towerRes, _star, _posIndex, _isRoll, _addType, _hasExtraStar, ... )
	if not _towerRes or _star <= 0 then
		return
	end
	local gbTower, pendingId = false, false
	if G_SendGBCommand then
		gbTower, pendingId = G_SendGBCommand(GBCommandType.ADDTOWER, self.playerId, _towerRes, _star, _posIndex, false, _addType, _hasExtraStar)
	end
	if _frame then
		_frame:AddFrameAction(BattleFrameActionType.ADDTOWER, self, _towerRes, _star, _posIndex, pendingId)
	else
		local tower = self:AddTower(_towerRes, _star, _posIndex, _isRoll, pendingId)
	end
	self:BusyTowerPos(_posIndex)
end

function BattlePlayer:UpgradeTower( _towerPoolIndex, ... )
	local towerResId = self.towerPool[_towerPoolIndex]
	if not towerResId then
		return
	end
	local towerInfo = self.towerInfoList[towerResId]
	if not towerInfo or towerInfo.grade == Constants.BATTLE_MAX_GRADE then
		return
	end
	-- 等级+1
	towerInfo.grade = towerInfo.grade + 1
	-- towerInfo.cost = Constants.BATTLE_GRADE_COST[towerInfo.grade]
	-- 通知同类塔升级
	for i = 1, #self.towerList do
		local tower = self.towerList[i]
		if tower and tower.towerRes.id == towerResId then
			tower:OnUpgrade(towerInfo.grade)
		end
	end

	-- 通知AI塔升阶
	if self.playerAI then
		self.playerAI:OnTowerUpgrade(towerResId, towerInfo.grade)
	end

	-- 通知关联状态层刷新
	local bufferLayerList = towerInfo.bufferLayerList
	if bufferLayerList then
		for i = 1, #bufferLayerList do
			local layer = bufferLayerList[i]
			layer.buffer:RefreshBufferLayer(layer)
		end
	end

	-- 通知前端升级
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.UPGRADE, self.playerId, _towerPoolIndex)

	-- gBattleManager:AddBattleLog(string.format('Upgrade Tower Frame[%d] Player[%d] Tower[%d] Grade[%d]', gBattleFrameCount, self.playerId, towerResId, towerInfo.grade))
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

	local towerRes = tower.towerRes

	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Remove Tower Frame[%d] Player[%d] Tower[%d-%d-%d] Pos[%d]', gBattleFrameCount, self.playerId, tower.towerId, tower.towerRes.baseId, tower.towerRes.level, tower.posIndex))

	-- 标记连接池已脏
	if HasBattleFlag(tower.unitFlag, BattleUnitFlag.CONNECT) then
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
	self.isTotalStarDirty = true

	-- 更新参数
	if #towerRes.paramList > 0 then
		self:AddParamValue(towerRes.paramList[1], -1, towerRes.baseId)
	end
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
	dragTower:Leave(FLAGMAP(BattleUnitLeaveType.EXCHANGE))
	targetTower:Leave(FLAGMAP(BattleUnitLeaveType.EXCHANGE))

	-- 列表中交换位置
	self.towerList[_dragIndex] = targetTower
	self.towerList[_targetIndex] = dragTower

	dragTower:SetPosIndex(_targetIndex)
	targetTower:SetPosIndex(_dragIndex)

	-- 进入格子
	self.gridList[_dragIndex]:OnTowerEnter(targetTower)
	self.gridList[_targetIndex]:OnTowerEnter(dragTower)
	if self.playerAI then
		self.playerAI:OnTowerEnter(targetTower)
		self.playerAI:OnTowerEnter(dragTower)
	end
	dragTower:Enter(BattleUnitEnterType.EXCHANGE)
	targetTower:Enter(BattleUnitEnterType.EXCHANGE)

	-- 标记连接池已脏
	if HasBattleFlag(targetTower.unitFlag, BattleUnitFlag.CONNECT) or HasBattleFlag(dragTower.unitFlag, BattleUnitFlag.CONNECT) then
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

function BattlePlayer:RandomTowerResId( _randNum, _exceptResId, ... )
	local randNum = _randNum or self.randNum
	local towerPool = self.towerPool
	local count = _exceptResId and #towerPool - 1 or #towerPool
	local index = randNum:NextInt(count)
	local towerResId = 0
	if _exceptResId then
		for i = 1, count + 1 do
			towerResId = towerPool[i]
			if towerResId ~= _exceptResId then
				index = index - 1
			end
			if index == 0 then
				break
			end
		end
	else
		towerResId = towerPool[index]
	end
	return towerResId
end

function BattlePlayer:RandomTowerPosIndex( _randNum, ... )
	-- 塔满，没有空余位置
	if self.emptyPosCount == 0 then
		return 0
	end
	local index = 1
	local randNum = _randNum or self.randNum
	if self.emptyPosCount > 1 then
		index = randNum:NextInt(self.emptyPosCount)
	end
	local posList = self.posList
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		if posList[i] == 0 then
			index = index - 1
		end
		if index == 0 then
			return i
		end
	end
	return 0
end

function BattlePlayer:FreeTowerPos( _posIndex, ... )
	self.posList[_posIndex] = 0
	self.emptyPosCount = self.emptyPosCount + 1
end

function BattlePlayer:BusyTowerPos( _posIndex, ... )
	self.posList[_posIndex] = 1
	self.emptyPosCount = self.emptyPosCount - 1
end

function BattlePlayer:HasEmptyPos( ... )
	return self.emptyPosCount ~= 0
end

function BattlePlayer:GetTowerResIdByPoolIndex( _index, ... )
	return self.towerPool[_index]
end

function BattlePlayer:GetPoolIndexByTowerResId( _towerResId )
	return self.towerInfoList[_towerResId].poolIndex
end

function BattlePlayer:GetTowerAwaken( _towerResId )
	local towerInfo = self.towerInfoList[_towerResId]
	return towerInfo.awakenTalentId, towerInfo.awakenIndex, towerInfo.awakenLevel
end

function BattlePlayer:GetTowerGrade( _towerResId, ... )
	local towerInfo = self.towerInfoList[_towerResId]
	if not towerInfo then
		return 1
	end
	return towerInfo.grade
end

function BattlePlayer:GetTowerGradeByBaseId( _towerBaseId )
	local towerInfo = self.towerBaseInfoList[_towerBaseId]
	if not towerInfo then
		return 1
	end
	return towerInfo.grade
end

function BattlePlayer:GetTowerLevelByBaseId( _towerBaseId )
	local towerInfo = self.towerBaseInfoList[_towerBaseId]
	if not towerInfo then
		return 1
	end
	return towerInfo.level
end

function BattlePlayer:GetTowerGradeByPoolIndex( _index, ... )
	local towerResId = self.towerPool[_index]
	return self:GetTowerGrade(towerResId)
end

function BattlePlayer:GetTowerUpgradeCostByPoolIndex( _index, ... )
	local towerResId = self.towerPool[_index]
	local towerInfo = self.towerInfoList[towerResId]
	if not towerInfo then
		return Constants.BATTLE_GRADE_COST[1]
	end
	return towerInfo.cost
end

function BattlePlayer:UpdateTowerUpgradeCostByIndex( _index, _isUpgrade, ... )
	local towerResId = self.towerPool[_index]
	local towerInfo = self.towerInfoList[towerResId]
	if not towerInfo then
		return
	end
	if _isUpgrade then
		towerInfo.localGrade = towerInfo.localGrade + 1
		towerInfo.cost = Constants.BATTLE_GRADE_COST[towerInfo.localGrade]
	else
		towerInfo.localGrade = towerInfo.grade
		towerInfo.cost = Constants.BATTLE_GRADE_COST[towerInfo.grade]
	end
	-- warn('UpdateTowerUpgradeCostByIndex', _index, towerInfo.cost, towerInfo.grade, towerInfo.localGrade)
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

	-- 进场
	monster:Enter()
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
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.REMOVEMONSTER, self.playerId, _monsterId, _leaveFlags)
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
SortMonster = BattlePlayer.SortMonster

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
	local maxHPMonster = false
	local minHPMonster = false
	for i = 1, #nextMonsterList do
		local monster = nextMonsterList[i]
		monsterList[i] = monster
		monster.sortIndex = i
		nextMonsterList[i] = nil

		if monster.curHP then
			-- 最大血量怪物
			if not maxHPMonster then
				maxHPMonster = monster
			elseif maxHPMonster.curHP < monster.curHP then
				maxHPMonster = monster
			end
			-- 最小血量怪物
			if not minHPMonster then
				minHPMonster = monster
			elseif minHPMonster.curHP > monster.curHP then
				minHPMonster = monster
			end
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

	local maxHPMonster = false
	local minHPMonster = false
	local commonMonsterCount = #_commonMonsterList
	for i = 1, commonMonsterCount do
		local monster = _commonMonsterList[i]
		monsterList[i] = monster
		monster.sortIndex = i
		if _clearCommon then
			_commonMonsterList[i] = nil
		end

		if monster.curHP then
			-- 最大血量怪物
			if not maxHPMonster then
				maxHPMonster = monster
			elseif maxHPMonster.curHP < monster.curHP then
				maxHPMonster = monster
			end
			-- 最小血量怪物
			if not minHPMonster then
				minHPMonster = monster
			elseif minHPMonster.curHP > monster.curHP then
				minHPMonster = monster
			end
		end
	end
	for i = 1, #nextMonsterList do
		local monster = nextMonsterList[i]
		monsterList[i + commonMonsterCount] = monster
		monster.sortIndex = i + commonMonsterCount
		nextMonsterList[i] = nil

		if monster.curHP then
			-- 最大血量怪物
			if not maxHPMonster then
				maxHPMonster = monster
			elseif maxHPMonster.curHP < monster.curHP then
				maxHPMonster = monster
			end
			-- 最小血量怪物
			if not minHPMonster then
				minHPMonster = monster
			elseif minHPMonster.curHP > monster.curHP then
				minHPMonster = monster
			end
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
	local pendingFrameCount = colliderRes.pendingTime == 0 and 0 or math_ceil(colliderRes.pendingTime / Constants.BATTLE_FRAME_TIME)
	if colliderRes.isRandomPos == 0 and _triggerUnit and _triggerUnit.unitType == BattleUnitType.MONSTER then
		position = _triggerUnit.position
	else
		position = gBattleRandNum:NextInt(1000, BattleConstants.BATTLE_ROAD_LENGTH - 1000)
		local ownerUnit = gBattleRecord:GetBattleUnit(_owner.unitId)
		if ownerUnit then
			pendingFrameCount = pendingFrameCount + ownerUnit:GetPositionDistance(position)
		end
	end
	
	local colliderId = self:GenerateColliderId()
	local collider = BattleCollider()
	if not collider:Init(colliderRes, colliderId, _owner, self, position, pendingFrameCount) then
		return false
	end

	-- 添加到怪物列表
	collider.node = LMLinkList_Add(self.colliderList, collider)
	-- 通知前端添加碰撞
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDCOLLIDER, self.playerId, colliderId, _owner.unitId, pendingFrameCount)
	-- 打印log
	-- gBattleManager:AddBattleLog(string.format('Add Collider Frame[%d] Player[%d] Collider[%d-%d-%d-%d]', gBattleFrameCount, self.playerId, colliderId, _id, position, _owner.unitId))
	
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
		self.costPoint = self.costPoint + Constants.BATTLE_COST_POINT_STEP
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

function BattlePlayer:AddMissile( _tower, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes, ... )
	local missile = BattleMissile_New(_tower.unitId, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes)
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
			local attacker = gBattleRecord:GetBattleUnit(missile.towerUnitId)
			if attacker then
				-- 刷新同怪物攻击次数
				local sameAttackTimes = attacker:RefreshSameMonsterAttackTimes(targetMonster)
				-- 攻击者未死亡，方可触发攻击 
				local triggerParam = BattleTriggerParam_New(attacker, attacker, { targetMonster }, { sameAttackTimes = sameAttackTimes, attackTimes = missile.attackTimes })
				gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
				BattleTriggerParam_Destroy(triggerParam)
				-- 计算伤害
				local isCritical = false
				local damage = missile.damage + triggerParam.extraDamage
				damage, isCritical = attacker:CalcDamage(damage, targetMonster, nil, nil, false)
				-- 怪物被击
				targetMonster:OnAttackDamage(attacker, damage, nil, nil, damage >= 0 and (isCritical and BattleDamageType.CRITICAL or BattleDamageType.NORMAL) or BattleDamageType.HEAL)
			end
		end
		BattleMissile_Destroy(missile)
	end
	self.missileList[gBattleFrameCount] = nil
end

function BattlePlayer:BindGradeBufferLayer( _towerResId, _bufferLayer, ... )
	local bufferLayerList = self.towerInfoList[_towerResId].bufferLayerList
	if not bufferLayerList then
		bufferLayerList = {}
		self.towerInfoList[_towerResId].bufferLayerList = bufferLayerList
	end
	table_insert(bufferLayerList, _bufferLayer)
end

function BattlePlayer:UnBindGradeBufferLayer( _towerResId, _bufferLayer, ... )
	local bufferLayerList = self.towerInfoList[_towerResId].bufferLayerList
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

function BattlePlayer:ExecSkill( _battleUnit, _targetUnit, _skillType, _delayTime, _param, _startPosIndex, _effectResId, ... )
	local skill = BattleSkill.Create(_skillType)
	if not skill then
		return false
	end
	if skill:Init(_battleUnit, _targetUnit, _delayTime, _param, _startPosIndex, _effectResId) then
		table_insert(self.skillList, skill)
		return true
	end
	return false
end

-- 刷新连接池
function BattlePlayer:RefreshTowerConnect( ... )
	local connectTowerList = {}
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local tower = self.towerList[i]
		if tower and HasBattleFlag(tower.unitFlag, BattleUnitFlag.CONNECT) then
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

function BattlePlayer:UpdateTotalStar( ... )
	if not self.isTotalStarDirty then
		return
	end
	self.isTotalStarDirty = false
	self.opponent.isTotalStarDirty = false
	local isLowerOpponent = self.totalStar < self.opponent.totalStar
	local isOpponentLower = self.opponent.totalStar < self.totalStar
	self:FireAllTowerTrigger(true, BattleTriggerType.TOTALSTAR, isLowerOpponent and -1 or 1)
	self.opponent:FireAllTowerTrigger(true, BattleTriggerType.TOTALSTAR, isOpponentLower and -1 or 1)
end

function BattlePlayer:FireAllTowerTrigger( _isFlagTrigger, _triggerType, _triggerValue, _towerBaseId, ... )
	for i = 1, #self.towerList do
		local tower = self.towerList[i]
		if tower then
			tower:FireTrigger(_isFlagTrigger, _triggerType, _triggerValue, _towerBaseId)
		end
	end
end

function BattlePlayer:AddParamValue( _paramType, _addValue, _towerBaseId )
	local param = self.paramMap[_paramType]
	if not param then
		return
	end
	if _towerBaseId ~= param.default.towerBaseId then
		return
	end
	if param.default.notifyParam then
		param.nextValue = param.nextValue + _addValue
	else
		param.nextValue = 1
		param.value = param.value + _addValue
	end
	self.isParamDirty = true
end

function BattlePlayer:UpdateParam( ... )
	if not self.isParamDirty then
		return
	end
	self.isParamDirty = false

	for paramType, param in pairs(self.paramMap) do
		if param.default.notifyParam then
			if param.value ~= param.nextValue then
				param.value = param.nextValue
				local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERPARAM, self.playerId, paramType, param.value)
			end
		elseif param.nextValue == 1 then
			param.netxtValue = 0
			if param.default.triggerType then
				if param.default.hitValues then
					local hitValue = param.default.hitValues[param.value] or 1
					self:FireAllTowerTrigger(param.default.isFlagTrigger, param.default.triggerType, hitValue, param.default.towerBaseId)
				else
					self:FireAllTowerTrigger(param.default.isFlagTrigger, param.default.triggerType, param.value, param.default.towerBaseId)
				end
			end
		end
	end
end

function BattlePlayer:NotifyPlayerParam( _paramType, _param )
	if not G_SendGBCommand then
		return
	end
	if _paramType then
		_param = _param or self.paramMap[_paramType]
		if _param.default.notifyParam then
			G_SendGBCommand(GBCommandType.PLAYERPARAM, self.playerId, _paramType, _param.value)
		end
		return
	end
	for paramType, param in pairs(self.paramMap) do
		if param.default.notifyParam then
			G_SendGBCommand(GBCommandType.PLAYERPARAM, self.playerId, paramType, param.value)
		end
	end
end

local Pow2List = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384 }
function BattlePlayer.EncodePosList( _posList )
	local result = 0
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		if _posList[i] == 1 then
			result = result + Pow2List[i]
		end
	end
	return result
end
EncodePosList = BattlePlayer.EncodePosList
