---
--- class GBMain
-- @classmod GBMain
class('GBMain')

-- 战斗主入口，战斗开始时实例化且战斗全程唯一，战斗结束时销毁
local s_instance = false
function GBMain.INSTANCE( ... )
	if not s_instance then
		s_instance = GBMain()
	end
	return s_instance
end

function GBMain.Destroy( ... )
	if s_instance then
		s_instance:Finalize()
		s_instance = nil
	end
end

local ServerCommandSwitcher = {
	-- 战斗帧包
	[60002] = function( _frameCount, _frameList, ... )
		GBMain.INSTANCE():OnServerFramePackage(_frameCount, _frameList)
	end,
	-- 战斗结算
	[60003] = function( _tBattleSettle, ... )
		GBMain.INSTANCE():OnServerBattleSettle(_tBattleSettle)
	end
}

function GBMain.OnServerCommand( _commandId, _data1, _data2, ... )
	if not s_instance then
		return
	end
	if s_instance.blockServerCommand then
		table.insert(s_instance.serverCommandList, { commandId = _commandId, data1 = _data1, data2 = _data2 })
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
	if not s_instance.blockServerCommand and #s_instance.serverCommandList ~= 0 then
		for i = 1, #s_instance.serverCommandList do
			local command = s_instance.serverCommandList[i]
			GBMain.OnServerCommand(command.commandId, command.data1, command.data2)
		end
		s_instance.serverCommandList = {}
	end
end

-- 请求快照
function GBMain.RequestSnapShot( ... )
	if not s_instance then
		return
	end
	gamebattle.gBattleManager.isSnapShotTaking = true
end

---Constructor
function GBMain:ctor( ... )
	self.playerId = 1				-- 玩家Id

	self.gbField = false 			-- 战场
	self.gbManager = false 			-- 战斗管理器

	-- 测试相关
	self.blockServerCommand = false
	self.serverCommandList = {}
end

function GBMain:Finalize( ... )
	BattleMain.Destroy()
	Global.gBattleMain = nil

	if self.gbManager then
		self.gbManager:Finalize()
	end
	self.gbManager = false
	Global.gGBManager = nil

	if self.gbField then
		self.gbField:Finalize()
	end
	self.gbField = false
	Global.gGBField = nil

	-- 对象池清理
	GameObjectPool.AutoClean(true)
	gGameClient:StartGC()

	GBCommand.Destroy()
end

function GBMain:Initialize( _playerId, _battleRecord, _uBattle, ... )
	self.playerId = _playerId

	-- 游戏战斗显示命令中心初始化
	local gbCommand = GBCommand.INSTANCE()

	-- 初始化战场
	self.gbField = GBField()
	Global.gGBField = self.gbField
	gGBField:Initialize(_playerId, _uBattle)

	-- 初始化管理器
	self.gbManager = GBManager()
	Global.gGBManager = self.gbManager
	gGBManager:Initialize()

	-- 战斗逻辑初始化
	Global.gBattleMain = BattleMain.INSTANCE()
	gBattleMain:Initialize(_battleRecord, gbCommand)
end

function GBMain:Update( _deltaTime, _time, ... )
	-- 战斗逻辑
	local realDeltaTime = BattleMain.INSTANCE():Update(_deltaTime)

	local battleState = gamebattle.gBattleManager.battleState
	if battleState == BattleState.BATTLEING or battleState == BattleState.PENDING then
		-- 显示层
		gGBManager:Update(_deltaTime)
		-- 战场
		gGBField:Update(_deltaTime, _time)
	end

	-- 调试信息
	if not gamebattle.gBattleRecord.isRealTime and gamebattle.gBattleManager.battleFrameCount % 10 == 0 then
		UIUtils.RefreshUIPage('battle', 'ServerFrame', { ServerFrame = 0, LocalFrame = gamebattle.gBattleManager.battleFrameCount })
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
				local frame = BattleFrame()
				frame:Load(frameDetail.Frame)
				player.playerFrame:AddBattleFrame(frame)
			end
		end
	end

	-- 同步帧数
	gamebattle.gBattleManager:SetBattleRecordFrameCount(_frameCount)

	UIUtils.RefreshUIPage('battle', 'ServerFrame', { ServerFrame = _frameCount, LocalFrame = gamebattle.gBattleManager.battleFrameCount })
end

function GBMain:BeginBattle( ... )
	gamebattle.gBattleManager:BeginBattle()
end

function GBMain:IsPlayerSelf( _playerId, ... )
	return _playerId == self.playerId
end

-- 快照
function GBMain:SendSnapShot( _tSnapShot, ... )
	GameNetRequest.SendBattleSnapShotRequest(_tSnapShot, function( ... )
		-- 倒计时
	end)
end

-- 投降
function GBMain:ExecSurrender( ... )
	local player = gamebattle.gBattleRecord:GetBattlePlayer(self.playerId)
	if not player then
		return
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.SURRENDER)
	local code = gamebattle.gBattleRecord:ExecSurrender(self.playerId, frame, player, false)
	-- 通知后端
	warn('GBMain ExecSurrender', frame.frameId, frame.frameCount, code)
	GameNetRequest.SendBattleOperationRequest(frame)
end

-- 随机抽塔
function GBMain:ExecRoll( ... )
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	if not player:IsPointEnough() then
		gGameDialog:ShowHint('点数不足')
		return false
	end
	if not player:HasEmptyPos() then
		gGameDialog:ShowHint('塔满，没有空余位置')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.ROLL)
	local code = gamebattle.gBattleRecord:ExecRoll(self.playerId, frame, player, false)
	-- 通知后端
	warn('GBMain ExecRoll', frame.frameId, frame.frameCount, code)
	GameNetRequest.SendBattleOperationRequest(frame)
	return true
end

-- 合并塔
function GBMain:ExecMerge( _towerIndex, _targetTowerIndex )
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
	local code = gamebattle.gBattleRecord:ExecMerge(self.playerId, frame, gbPlayer.player, false)
	-- 通知后端
	warn('GBMain ExecMerge', frame.frameId, _towerIndex, _targetTowerIndex, code, mergeType, mergeUnitFlag)
	GameNetRequest.SendBattleOperationRequest(frame)
	return true
end

-- 升级塔
function GBMain:ExecUpgrade( _towerPoolIndex, ... )
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	local cost = player:GetTowerUpgradeCostByPoolIndex(_towerPoolIndex)
	if cost == 0 then
		gGameDialog:ShowHint('塔已满级')
		return false
	end
	if not player:IsPointEnough(cost) then
		gGameDialog:ShowHint('点数不足')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.UPGRADE, _towerPoolIndex)
	local code = gamebattle.gBattleRecord:ExecUpgrade(self.playerId, frame, player, false)
	-- 通知后端
	warn('GBMain ExecUpgrade', frame.frameId, frame.frameCount, code, _towerPoolIndex)
	GameNetRequest.SendBattleOperationRequest(frame)
	return true
end

-- 英雄天赋
function GBMain:ExecHeroTalent( ... )
	local player = self:GetMyPlayer()
	if not player then
		return false
	end
	if not player.hero:IsHeroTalentReady() then
		gGameDialog:ShowHint('魔法冷却中')
		return false
	end
	local frame = player:GenerateBattleFrame(BattleFrameType.HEROTALENT)
	local code = gamebattle.gBattleRecord:ExecHeroTalent(self.playerId, frame, player, false)
	-- 通知后端
	warn('GBMain ExecHeroTalent', frame.frameId, frame.frameCount, code)
	GameNetRequest.SendBattleOperationRequest(frame)
	return true
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
	GameNetRequest.SendBattleEndRequest(_result, _battleId, function( _data, ... )
		-- body
	end, function( _error, ... )
		-- body
	end)
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

function GBMain:OnRoundStart( _duration, _roundNum, ... )
	UIUtils.RefreshUIPage('battle', 'RoundStart', { duration = _duration, roundNum = _roundNum })
	return true
end

function GBMain:OnBattlePeriodUpdate( _periodName, _param1, _param2, ... )
	UIUtils.RefreshUIPage('battle', _periodName, { param1 = _param1, param2 = _param2, params = ... })
end

classend()