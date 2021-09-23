---
--- class GBMain
-- @classmod GBMain
GBMain = xclass('GBMain')

local os_time = os.time

local BattleBeginFlag = {
	ALL = 0,
	LOGIC = 1,
	ANIMATION = 2,
	MAX = 3,
}
Global.BattleBeginFlag = BattleBeginFlag

local table_insert = table.insert

-- 自动快照间隔
local AutoSnapShotInterval = 5000
-- 缓冲服务器命令
local ServerPendingCommands = {}

-- 战斗主入口，战斗开始时实例化且战斗全程唯一，战斗结束时销毁
local s_instance = false
function GBMain.INSTANCE( ... )
	if not s_instance then
		s_instance = GBMain()
		Global.gGBMain = s_instance
	end
	return s_instance
end

function GBMain.Destroy( ... )
	if s_instance then
		s_instance:Finalize()
		s_instance = false
		Global.gGBMain = false
	end
end

function GBMain.Reset( ... )
	ServerPendingCommands = {}
end

function GBMain.IsDestroyed( ... )
	return s_instance == false
end

local ServerCommandSwitcher = {
	-- 战斗帧包
	[60002] = function( _frameCount, _frameList, ... )
		gGBMain:OnServerFramePackage(_frameCount, _frameList)
	end,
	-- 战斗结算
	[60003] = function( _tBattleSettle, ... )
		gGBMain:OnServerBattleSettle(_tBattleSettle)
	end
}

function GBMain.OnServerCommand( _commandId, _data1, _data2, ... )
	if not s_instance then
		warn('OnServerCommand No Instance')
		table_insert(ServerPendingCommands, { commandId = _commandId, data1 = _data1, data2 = _data2 })
		return
	end
	if s_instance.blockServerCommand then
		table_insert(ServerPendingCommands, { commandId = _commandId, data1 = _data1, data2 = _data2 })
		return
	end
	local cmdExecutor = ServerCommandSwitcher[_commandId]
	if cmdExecutor then
		cmdExecutor(_data1, _data2, ...)
	end
end

function GBMain.BlockServerCommand( _block, ... )
	if not s_instance then
		return
	end
	s_instance.blockServerCommand = _block
	if not _block and #ServerPendingCommands ~= 0 then
		for i = 1, #ServerPendingCommands do
			local command = ServerPendingCommands[i]
			GBMain.OnServerCommand(command.commandId, command.data1, command.data2)
			ServerPendingCommands[i] = nil
		end
	end
end

-- 请求快照
function GBMain.RequestSnapShot( ... )
	if not s_instance then
		return
	end
	s_instance.isSnapShotTaking = true
	s_instance.isSendSnapShot = true
end

---Constructor
function GBMain:ctor( ... )
	self.playerId = 1				-- 玩家Id

	self.gbField = false 			-- 战场

	-- 测试相关
	self.blockServerCommand = false

	self.isSnapShotTaking = false				-- 是否抓取快照中
	self.isSendSnapShot = false					-- 是否发送快照

	self.autoSnapShotCounter = 0				-- 自动快照计时

	self.isGuiding = false						-- 是否引导
	self.beginFlag = false						-- 战斗开始信号

	self.localFrameMap = {}						-- 本地帧
	self.frameResponseList = {}					-- 操作帧响应时间
end

function GBMain:Finalize( ... )
	BattleMain.Destroy()
	Global.gBattleMain = nil

	if self.gbField then
		self.gbField:Finalize()
	end
	self.gbField = false
	Global.gGBField = nil

	-- 对象池清理
	GameObjectPool.AutoClean(true)
	gGameClient:StartGC()

	GBCommand.Destroy()

	-- 打开网络Waiting
	gGameNetMgr:OpenWaiting(true)
end

function GBMain:Initialize( _playerId, _battleRecord, _uBattle, ... )
	-- 初始化战斗开始信号
	self.beginFlag = Flag()
	self.beginFlag:AddFlag(BattleBeginFlag.LOGIC)
	self.beginFlag:AddFlag(BattleBeginFlag.ANIMATION)

	self.playerId = _playerId
	self.isGuiding = _battleRecord.battleId == 'guide'
	local battleType = _battleRecord.battleType

	-- 游戏战斗显示命令中心初始化
	local gbCommand = GBCommand.INSTANCE()

	-- 初始化战场
	self.gbField = GBField()
	Global.gGBField = self.gbField
	gGBField:Initialize(_playerId, battleType, _uBattle)

	-- 战斗逻辑初始化
	Global.gBattleMain = BattleMain.INSTANCE()
	gBattleMain:Initialize(_battleRecord, gbCommand)

	-- 启动主循环
	_uBattle:Init(function( _delta, _time, ... )
		return self:Update(_delta, _time)
	end)

	-- 自动快照间隔
	self.autoSnapShotCounter = AutoSnapShotInterval
	-- 初始化本地快照
	local curSnapShotId = LocalDB:GetValue('SnapShotId', '')
	if curSnapShotId ~= _battleRecord.battleId then
		LocalDB:SetValue('SnapShotId', _battleRecord.battleId)
		LocalDB:SetValue('SnapShot', '')
	end
	-- 屏蔽网络Waiting
	if gGameClient:IsBattleing() then
		gGameNetMgr:OpenWaiting(false)
	end
	-- 加载缓存命令
	GBMain.BlockServerCommand(false)
end

function GBMain:Update( _deltaTime, _time, ... )
	-- 战斗逻辑
	local realDeltaTime = gBattleMain:Update(_deltaTime)
	self.autoSnapShotCounter = self.autoSnapShotCounter - realDeltaTime

	local battleManager = gamebattle.gBattleManager
	local battleState = battleManager.battleState
	if battleState == BattleState.BATTLEING or battleState == BattleState.PENDING then
		-- 战场
		gGBField:Update(_deltaTime, _time)
	end

	-- 每隔5秒自动抓取快照，保存到本地
	local isSnapShotTaking = self.isSnapShotTaking
	if not isSnapShotTaking and not battleManager.isFrameChasing and self.autoSnapShotCounter <= 0 then
		isSnapShotTaking = true
		self.isSendSnapShot = false
	end

	if isSnapShotTaking then
		-- 无缓冲帧的时抓取快照
		self.isSnapShotTaking = false
		self.autoSnapShotCounter = AutoSnapShotInterval
		local tSnapShot = battleManager:TakeSnapShot()
		-- 发送快照
		if self.isSendSnapShot then
			self:SendSnapShot(tSnapShot)
		end
		-- 保存到本地
		LocalDB:SetValue('SnapShot', gameutils.JSON:encode(tSnapShot))
		self.isSendSnapShot = false
	end

	return realDeltaTime
end

function GBMain:OnServerFramePackage( _frameCount, _frameList, ... )
	local battleRecord = gamebattle.gBattleRecord
	if _frameCount < 0 or not battleRecord then
		return
	end

	-- 插入缓冲帧
	if _frameList then
		for i = 1, #_frameList do
			local frameDetail = _frameList[i]
			local player = battleRecord:GetBattlePlayer(frameDetail.PlayerId)
			if player then
				local frame = gamebattle.BattleFrame()
				frame:Load(frameDetail.Frame)
				player.playerFrame:AddBattleFrame(frame)

				self:OnServerFrame(frame, frameDetail.PlayerId)
			end
		end
	end

	-- 同步帧数
	if gamebattle.gBattleManager:SetBattleRecordFrameCount(_frameCount) then
		-- 开始战斗
		self:BeginBattle(BattleBeginFlag.LOGIC)
	end
end

function GBMain:BeginBattle( _flag, ... )
	self.beginFlag:ClearFlag(_flag)
	if not self.beginFlag:IsAllFlagClear() then
		return
	end
	gamebattle.gBattleManager:BeginBattle()
end

function GBMain:IsPlayerSelf( _playerId, ... )
	return _playerId == self.playerId
end

-- 快照
function GBMain:SendSnapShot( _tSnapShot, ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	GameNetRequest.SendBattleSnapShotRequest(_tSnapShot, function( ... )
		-- 倒计时
	end)
end

-- 投降
function GBMain:ExecSurrender( ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = battleRecord:GetBattlePlayer(self.playerId)
	if not player then
		return
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.SURRENDER)
	local code = battleRecord:ExecSurrender(self.playerId, frame, player, false)
	-- 通知后端
	-- print('GBMain ExecSurrender', frame.frameId, frame.frameCount, code)
	self:SendBattleOperationRequest(frame)
end

-- 随机抽塔
function GBMain:ExecRoll( ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	if not player:IsPointEnough() then
		-- gGameDialog:ShowHint('点数不足')
		return false
	end
	if not player:HasEmptyPos() then
		-- gGameDialog:ShowHint('塔满，没有空余位置')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.ROLL)
	local code = battleRecord:ExecRoll(self.playerId, frame, player, false)
	-- 通知后端
	-- print('GBMain ExecRoll', frame.frameId, frame.frameCount, code, gameutils.JSON:encode(frame))
	self:SendBattleOperationRequest(frame)
	return true
end

-- 合并塔
function GBMain:ExecMerge( _towerIndex, _targetTowerIndex )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local gbPlayer = self:GetMyGBPlayer()
	if not gbPlayer then
		return false
	end
	local dragTower = gbPlayer:GetGBTowerByPos(_towerIndex)
	local targetTower = gbPlayer:GetGBTowerByPos(_targetTowerIndex)
	if not dragTower or not targetTower then
		return false
	end
	local canMerge, mergeType, mergeUnitFlag = dragTower:CanMerge(targetTower)
	if not canMerge then
		return false
	end

	local param = targetTower.towerRes.id * 10000 + dragTower.star * 1000 + mergeUnitFlag * 10 + mergeType
	local frame = gbPlayer.player:GenerateBattleFrame(BattleFrameType.MERGE, _towerIndex, _targetTowerIndex, param)
	local code = battleRecord:ExecMerge(self.playerId, frame, gbPlayer.player, false)
	if code == ErrorCode.SUCCESS and mergeType == BattleTowerMergeType.MERGE then
		-- 成功合成
		NewbieTaskPage.NewbieTaskDoneEvent(NewbieTaskType.MERGE)
	end
	-- 通知后端
	-- print('GBMain ExecMerge', frame.frameId, _towerIndex, _targetTowerIndex, code, mergeType, mergeUnitFlag, gameutils.JSON:encode(frame))
	self:SendBattleOperationRequest(frame)
	return true
end

-- 升级塔
function GBMain:ExecUpgrade( _towerPoolIndex, ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	local cost = player:GetTowerUpgradeCostByPoolIndex(_towerPoolIndex)
	if cost == 0 then
		-- gGameDialog:ShowHint('塔已满级')
		return false
	end
	if not player:IsPointEnough(cost) then
		-- gGameDialog:ShowHint('点数不足')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.UPGRADE, _towerPoolIndex)
	local code = battleRecord:ExecUpgrade(self.playerId, frame, player, false)
	-- 通知后端
	-- print('GBMain ExecUpgrade', frame.frameId, frame.frameCount, code, _towerPoolIndex)
	self:SendBattleOperationRequest(frame)
	return true
end

-- 英雄天赋
function GBMain:ExecHeroTalent( ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	if not player.hero:IsHeroTalentReady() then
		-- gGameDialog:ShowHint('魔法冷却中')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.HEROTALENT)
	local code = battleRecord:ExecHeroTalent(self.playerId, frame, player, false)
	if code == ErrorCode.SUCCESS then
		-- 成功使用技能
		NewbieTaskPage.NewbieTaskDoneEvent(NewbieTaskType.SKILL)
	end
	-- 通知后端
	-- print('GBMain ExecHeroTalent', frame.frameId, frame.frameCount, code)
	self:SendBattleOperationRequest(frame)
	return true
end

-- 上报
function GBMain:ExecReport( ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	local roundNum = gamebattle.gBattleLogic.roundNum
	local frame = player:GenerateBattleFrame(BattleFrameType.REPORT, roundNum)
	-- 通知后端
	-- print('GBMain ExecReport', frame.frameId, frame.frameCount, roundNum)
	self:SendBattleOperationRequest(frame)
end

-- 表情
function GBMain:ExecEmoji( _index, ... )
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	if battleRecord.isRealTime then
		local frame = player:GenerateBattleFrame(BattleFrameType.EMOJI, _index)
		-- 通知后端
		-- print('GBMain ExecEmoji', frame.frameId, frame.frameCount, _index)
		self:SendBattleOperationRequest(frame)
	else
		local enemyPlayerAI = self:GetEnemyPlayer().playerAI
		if enemyPlayerAI then
			enemyPlayerAI:OnTriggerEmoji(_index)
		end
	end
	self:OnPlayerEmoji(player.playerId, _index)
end

function GBMain:OnPlayerEmoji( _playerId, _index, _isLogic )
	if _isLogic and self.playerId == _playerId then
		return
	end
	UIUtils.RefreshUIPage('battle', 'PlayerEmoji', { playerId = _playerId, index = _index })
end

-- 点数刷新
function GBMain:UpdatePoint( _playerId, _point, _costPoint, ... )
	if self.playerId ~= _playerId then
		return false
	end
	UIUtils.RefreshUIPage('battle', 'UpdatePoint', { point = _point, costPoint = _costPoint })
	return true
end

-- 战斗结束
function GBMain:OnLogicBattleEnd( _result, _battleId, ... )
	-- 打开网络Waiting
	gGameNetMgr:OpenWaiting(true)
	-- 引导战斗直接结算
	if self.isGuiding then
		BattleSettlePage.OpenPage({ BattleType = gamebattle.gBattleRecord.battleType, IsMyWin = true, Success = true, IsGuiding = true })
		return
	end
	local battleRecord = gamebattle.gBattleRecord
	if battleRecord.isVideo then
		return
	end
	local isPoorNet = self:IsBattleNetPoor()
	GameNetRequest.SendBattleEndRequest(_result, _battleId, isPoorNet, function( _data, ... )
		-- body
	end, function( _error, ... )
		-- body
	end)
	if not gGameNetMgr:IsSessionActive(NetSessionType.LOGIC) then
		-- 逻辑服网络断开，直接弹窗
		gGameDialog:ShowNetError(GAMETEXT('Error'), GAMETEXT('NetError'), nil, function( _btnClick )
			_btnClick:Cancel()
			gGameDialog:ShowWaiting(false)
			gGameClient:RestartGame()
		end)
	end
	return true
end

-- 后端结算
	-- @table _tBattleSettle: TBattleSettle
function GBMain:OnServerBattleSettle( _tBattleSettle, ... )
	gamebattle.gBattleManager:ChangeBattleState(BattleState.SETTLE)
	BattleSettlePage.OpenPage(_tBattleSettle)
end

function GBMain:IsMyPlayer( _playerId, ... )
	return self.playerId == _playerId
end

function GBMain:GetMyPlayer( ... )
	return gamebattle.gBattleRecord:GetBattlePlayer(self.playerId)
end

function GBMain:GetMyGBPlayer( ... )
	return gGBField:GetGBPlayer(self.playerId)
end

function GBMain:GetEnemyPlayer( ... )
	return gamebattle.gBattleRecord:GetBattlePlayer(self.playerId, true)
end

function GBMain:GetEnemyGBPlayer( ... )
	local enemyPlayer = self:GetEnemyPlayer()
	return gGBField:GetGBPlayer(enemyPlayer.playerId)
end

function GBMain:RefreshHeroTalentCDTime( _playerId, _pastTime, _leftTime, ... )
	UIUtils.RefreshUIPage('battle', 'RefreshHeroTalentCDTime', { playerId = _playerId, pastTime = _pastTime, leftTime = _leftTime })
	return true
end

function GBMain:OnRoundStart( _duration, _roundNum, _bossIndex, _nextBossId, _roundType, ... )
	UIUtils.RefreshUIPage('battle', 'RoundStart', { duration = _duration, roundNum = _roundNum, bossIndex = _bossIndex, nextBossId = _nextBossId, roundType = _roundType })
	return true
end

function GBMain:OnBattlePeriodUpdate( _periodName, _param1, _param2, ... )
	UIUtils.RefreshUIPage('battle', _periodName, { param1 = _param1, param2 = _param2, params = ... })
end

function GBMain:IsBattleing( ... )
	return gamebattle.gBattleManager.battleState < BattleState.END
end

function GBMain:UpdatePlayerParam( _playerId, _paramType, _paramValue, ... )
	UIUtils.RefreshUIPage('battle', 'UpdatePlayerParam', { playerId = _playerId, paramType = _paramType, paramValue = _paramValue })
end

function GBMain:SendBattleOperationRequest( _frame )
	_frame.sendTime = Time.realtimeSinceStartup
	GameNetRequest.SendBattleOperationRequest(_frame, function( _data, _responseTime )
		_frame.responseTime = Time.realtimeSinceStartup
		self.localFrameMap[_frame.frameId] = _frame

		local responseTime = _responseTime and _responseTime >= 0 and _responseTime or (_frame.responseTime - _frame.sendTime) * 1000
		table_insert(self.frameResponseList, responseTime)
		warn('Battle Operate', _frame.responseTime - _frame.sendTime, responseTime)
	end, function( _error, _responseTime )
		_frame.responseTime = Time.realtimeSinceStartup
		self.localFrameMap[_frame.frameId] = _frame

		local responseTime = _responseTime and _responseTime >= 0 and _responseTime or (_frame.responseTime - _frame.sendTime) * 1000
		table_insert(self.frameResponseList, responseTime)
		warn('Battle Operate Error', _frame.responseTime - _frame.sendTime, responseTime)
	end)
end

function GBMain:OnServerFrame( _frame, _framePlayerId )
	if self.playerId ~= _framePlayerId then
		return
	end
	local frame = self.localFrameMap[_frame.frameId]
	if not frame then
		return
	end
	local battleManager = gamebattle.gBattleManager
	if not battleManager then
		return
	end
	frame.serverTime = Time.realtimeSinceStartup
	frame.execTime = frame.serverTime + (_frame.frameCount - battleManager.battleFrameCount) / Constants.BATTLE_FPS
	GameSDKEvents.TrackBattleFrame(battleManager.battleId, frame, _frame.frameCount, battleManager.battleFrameCount)
end

function GBMain:IsBattleNetPoor( ... )
	local totalCount = #self.frameResponseList
	if totalCount == 0 then
		warn('IsBattleNetPoor True TotalCount=0')
		return true
	end
	local poorCount = 0
	for i = 1, totalCount do
		if self.frameResponseList[i] > 350 then
			poorCount = poorCount + 1
		end
	end
	warn('IsBattleNetPoor', poorCount / totalCount > 0.2, poorCount, totalCount)
	return poorCount / totalCount > 0.2 
end