require 'Thrift'
require 'TMemoryBuffer'
require 'TBinaryProtocol'

---
--- class BattleManager
-- @classmod BattleManager
-- 战斗管理器
BattleManager = xclass('BattleManager')

local table_insert = table.insert
local os_clock = os.clock
local math_floor = math.floor

local TSSnapShot = gModel.TSSnapShot

---Constructor
function BattleManager:ctor( ... )  
	self.battleId = false						-- 战斗种子
	self.battleTimer = false					-- 战斗计时器
	self.battleRecord = false 					-- 战斗记录器
	self.battleLogic = false 					-- 战斗逻辑
	self.battleTrigger = false					-- 战斗触发器

	self.isClientMode = false 					-- 是否客户端

	self.battleState = BattleState.ALL			-- 当前战斗状态
	self.lastBattleState = BattleState.ALL		-- 上一个战斗状态
	self.nextBattleState = BattleState.ALL		-- 下一个战斗状态，用于切换状态

	self.battleFrameCount = 0 					-- 战斗帧数
	self.battleTime = 0							-- 战斗计时
	self.updateTime = 0							-- 渲染帧更新剩余时间
	self.updateDeltaTime = 0					-- 渲染帧转换到逻辑帧单帧时间增量，正常情况通逻辑帧单帧时间一致

	self.bufferIdGenerator = 0					-- 状态ID生成器

	self.isSnapShotPushing = false				-- 是否快照推送中
	self.snapShotPushEndEventList = {}			-- 快照推送结束事件列表
	self.isFrameChasing = false					-- 是否追帧
end

function BattleManager:Finalize( ... ) 
	Global.gBattleFinalizing = true

	if self.battleLogic then
		self.battleLogic:Finalize()
	end
	self.battleLogic = false
	Global.gBattleLogic = nil

	if self.battleRecord then
		self.battleRecord:Finalize()
	end
	self.battleRecord = false
	Global.gBattleRecord = nil

	if self.battleTrigger then
		self.battleTrigger:Finalize()
	end
	self.battleTrigger = false
	Global.gBattleTrigger = nil
	
	if self.battleTimer then
		self.battleTimer:Finalize()
	end
	self.battleTimer = false
	Global.gBattleTimer = nil

	Global.gBattleTime = nil
	Global.gBattleFrameCount = nil
	Global.gBattleType = nil
	Global.gBattleFinalizing = nil
	Global.gBattleFreezing = nil
end

function BattleManager:Initialize( _battleRecord, ... )  
	Global.gBattleFreezing = false

	-- 战斗时间
	self.battleTime = 0
	Global.gBattleTime = 0
	Global.gBattleFrameCount = 0
	self.battleId = _battleRecord.battleId
	Global.gBattleType = _battleRecord.battleType

	-- gBattleManager:AddBattleLog('log_reset', true)
	-- gBattleManager:AddBattleLog(string.format("Battle Begin Seed[%d] BattleId[%s] BattleType[%d]", _battleRecord.battleSeed, _battleRecord.battleId, _battleRecord.battleType))	

	-- 初始化计时器
	self.battleTimer = BattleTimer()
	Global.gBattleTimer = self.battleTimer
	gBattleTimer:Initialize()

	-- 初始化战斗触发器
	self.battleTrigger = BattleTrigger()
	Global.gBattleTrigger = self.battleTrigger
	gBattleTrigger:Initialize()

	-- 初始化战斗逻辑
	self.battleLogic = self:BuildBattleLogic(_battleRecord.battleType, _battleRecord.isLocal)
	Global.gBattleLogic = self.battleLogic
	gBattleLogic:Initialize(_battleRecord.battleType, _battleRecord.battleResId)

	-- 初始化战斗记录器
	self.battleRecord = _battleRecord
	Global.gBattleRecord = self.battleRecord
	gBattleRecord:Initialize()

	-- 渲染帧转逻辑帧，时间增量
	self.updateDeltaTime = Constants.BATTLE_FRAME_TIME
end

function BattleManager:Update( _deltaTime, ... )  
	-- 修正战斗状态
	local battleState = self:CheckNextBattleState()

	if battleState ~= BattleState.BATTLEING then
		return 0
	end

	-- 性能优化
	local battleRecord = self.battleRecord
	-- 校验快照
	if battleRecord.tSnapShot then
		self:PushSnapShot(battleRecord.tSnapShot)
		battleRecord.tSnapShot = false
	end

	local updateTime = self.updateTime + _deltaTime
	local updateDeltaTime = self.updateDeltaTime
	local battleFrameTime = Constants.BATTLE_FRAME_TIME
	local isRealTime = battleRecord.isRealTime
	local realFrameCount = battleRecord:GetFrameCount()
	local battleFrameCount = self.battleFrameCount
	local battleTime = self.battleTime

	-- 实时战斗需要根据帧差修复帧，将前后端帧差维持在10帧
	local frameDistance = realFrameCount - battleFrameCount
	if frameDistance > Constants.BATTLE_SERVER_LEAD_FRAME_COUNT + Constants.BATTLE_FRAME_PACKAGE_LENGTH then
		-- 暴力追帧
		updateTime = (frameDistance - Constants.BATTLE_SERVER_LEAD_FRAME_COUNT) * updateDeltaTime
		if not self.isFrameChasing then
			-- 通知前端开始追帧
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FRAMECHASING, true)
			self.isFrameChasing = true
		end
		-- warn('暴力追帧开始', battleFrameCount, frameDistance)
	elseif frameDistance > Constants.BATTLE_SERVER_LEAD_FRAME_COUNT + 1 and updateDeltaTime == battleFrameTime then
		-- 平缓追帧
		updateDeltaTime = battleFrameTime - 8
		self.updateDeltaTime = updateDeltaTime
		-- 通知前端停止追帧
		if self.isFrameChasing then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FRAMECHASING, false)
			self.isFrameChasing = false
		end
		-- warn('平缓追帧开始', battleFrameCount, frameDistance)
	elseif frameDistance <= Constants.BATTLE_SERVER_LEAD_FRAME_COUNT and updateDeltaTime ~= battleFrameTime then
		-- 正常帧
		updateDeltaTime = battleFrameTime
		self.updateDeltaTime = updateDeltaTime
		-- 通知前端停止追帧
		if self.isFrameChasing then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FRAMECHASING, false)
			self.isFrameChasing = false
		end
		-- warn('追帧结束', battleFrameCount, frameDistance)
	else
		if self.isFrameChasing then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FRAMECHASING, false)
			self.isFrameChasing = false
		end
	end
	-- 逻辑主循环
	local realDeltaTime = 0
	while (updateTime >= updateDeltaTime) do
		-- 逻辑帧校验战斗状态
		if battleState ~= BattleState.BATTLEING then
			updateTime = 0
			break
		end
		-- 逻辑帧超过即时战斗最大帧，则需要缓冲，等待收到后续帧再执行
		if isRealTime and battleFrameCount >= realFrameCount then 
			self:ChangeBattleState(BattleState.PENDING)
			break
		end

		updateTime = updateTime - updateDeltaTime
		-- realDeltaTime = realDeltaTime + battleFrameTime
		
		-- 战斗逻辑帧
		battleFrameCount = battleFrameCount + 1
		Global.gBattleFrameCount = battleFrameCount

		-- 战斗记录中，取出当前应该执行的所有帧
		while true do 
			local nextFrameCount, nextFramePlayer = battleRecord:GetNextFrameCount()
			if nextFrameCount > battleFrameCount then
				break
			end
			-- 执行战斗帧
			local nextFrame = nextFramePlayer:GetNextFrame(true)
			self:ExecBattleFrame(nextFramePlayer.playerId, nextFrame, nextFramePlayer)
		end

		-- 战斗计时器
		gBattleTimer:Update(battleFrameTime)

		if not gBattleFreezing then
			-- 战斗时间
			battleTime = battleTime + battleFrameTime 
			Global.gBattleTime = battleTime
			realDeltaTime = realDeltaTime + battleFrameTime

			-- 战斗逻辑
			gBattleLogic:Update(battleFrameTime, battleTime)

			-- 战斗录像
			battleRecord:Update(battleFrameTime, battleTime)
		end

		-- 检查战斗是否结束
		if gBattleLogic:CheckBattleEnd() then
			warn(string.format('Battle End Frame[%d] WinPlayer[%d] RoundNum[%d]', gBattleFrameCount, gBattleResult.winPlayerId, gBattleResult.roundNum))
			-- gBattleManager:AddBattleLog('log_end', true)

			self:ChangeBattleState(BattleState.END)
		end

		-- 修正战斗状态
		battleState = self:CheckNextBattleState(battleState)
	end

	-- 同步时间
	self.updateTime = updateTime
	self.battleFrameCount = battleFrameCount
	self.battleTime = battleTime

	-- 修正战斗状态
	self:CheckNextBattleState(battleState)

	return realDeltaTime
end

function BattleManager:BeginBattle( ... )  
	-- 战斗开始
	self:ChangeBattleState(BattleState.BATTLEING)
end

function BattleManager:ChangeBattleState( _state )  
	if _state == self.nextBattleState or self.nextBattleState == BattleState.END then
		return
	end
	self.nextBattleState = _state
end

-- 战斗状态选择器
local BattleStateSwitcher = {
	[BattleState.BATTLEING] = function( _lastState, ... )  
		if not _lastState or _lastState < BattleState.BATTLEING then
			gBattleManager:OnBattleBegin()
		elseif _lastState == BattleState.PAUSE then
			gBattleManager:OnBattleResume()
		elseif _lastState == BattleState.PENDING then
			
		end
	end,
	[BattleState.END] = function( _lastState, ... )  
		gBattleManager:OnBattleEnd()
	end,
	[BattleState.SETTLE] = function( _lastState, ... )  
		gBattleManager:OnBattleSettle()
	end,
	[BattleState.PAUSE] = function( _lastState, ... )  
		gBattleManager:OnBattlePause()
	end,
	[BattleState.PENDING] = function( _lastState, ... )  
		gBattleManager:OnBattlePending()
	end
}

function BattleManager:CheckNextBattleState( _battleState, ... )  
	local battleState = _battleState or self.battleState
	if self.nextBattleState == battleState then
		return battleState
	end

	self.lastBattleState = battleState
	battleState = self.nextBattleState
	self.battleState = battleState

	local switcher = BattleStateSwitcher[battleState]
	if switcher then
		switcher(self.lastBattleState)
	end
	return battleState
end

-- 战斗帧处理器
local BattleFrameSwitcher = {
	-- 抽卡
	[BattleFrameType.ROLL] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecRoll(_playerId, _frame, _player, true)
	end,
	-- 合成
	[BattleFrameType.MERGE] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecMerge(_playerId, _frame, _player, true)
	end,
	-- 升级
	[BattleFrameType.UPGRADE] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecUpgrade(_playerId, _frame, _player, true)
	end,
	-- 投降
	[BattleFrameType.SURRENDER] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecSurrender(_playerId, _frame, _player, true)
	end,
	-- 英雄天赋
	[BattleFrameType.HEROTALENT] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecHeroTalent(_playerId, _frame, _player, true)
	end,
	-- 表情
	[BattleFrameType.EMOJI] = function( _playerId, _frame, _player, ... )
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EMOJI, _playerId, _frame.param1)
		return true
	end,
	-- 引导
	[BattleFrameType.GUIDE] = function( _playerId, _frame, _player, ... )
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.GUIDE, _frame.param1)
		return true
	end
}

function BattleManager:ExecBattleFrame( _playerId, _frame, _player, ... )
	if not _frame then
		return
	end
	-- gBattleManager:AddBattleLog(string.format('ExecBattleFrame Frame[%d] Player[%s] Type[%d]', gBattleFrameCount, tostring(_playerId), _frame.frameType))
	local switcher = BattleFrameSwitcher[_frame.frameType]
	if switcher then
		local result = false
		local code = -1
		result, code = switcher(_playerId, _frame, _player)
		if not result and code ~= 0 then
			warn(string.format('ExecBattleFrame Error %d %d %d %d %s %s', code, _playerId, _frame.frameType, _frame.frameCount, _frame.param1, _frame.param2))
		end
	end
end

function BattleManager:OnBattleBegin( ... )  
	self.battleFrameCount = 0
	self.battleTime = 0
	self.updateTime = 0
	Global.gBattleFrameCount = 0
	Global.gBattleTime = 0

	-- 触发战斗开始
	gBattleLogic:OnBattleBegin()
end

function BattleManager:OnBattleEnd( ... )  
	-- 最后一帧
	gBattleResult:SetFrameCount(gBattleFrameCount)
	warn('OnBattleEnd', gBattleResult.winPlayerId, gBattleResult.frameCount, gBattleResult.roundNum, gBattleRandNum:NextInt(), gBattleRandNum:GetCount(), gBattleRandNum:GetPoolNum())

	-- 通知前端战斗结束
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.BATTLEEND, gBattleResult, gBattleRecord.battleId)
end

function BattleManager:OnBattlePause( ... )  
	-- body
end

function BattleManager:OnBattleResume( ... )  
	-- body
end

function BattleManager:OnBattleSettle( ... )  
	-- body
end

-- 逻辑帧已运行至服务器通知的最大帧数，缓冲等待下一次通知
function BattleManager:OnBattlePending( ... )  
	self.updateTime = 0
end

function BattleManager:GetBattleFrameCount( ... )  
	return self.battleFrameCount
end

-- 战斗逻辑创建
local BattleLogicSwitcher = {
	[BattleType.PK] = function( _isLocal, ... )
		return BattlePkLogic(_isLocal)
	end,
	[BattleType.COOP] = function( _isLocal, ... )
		return BattleCoopLogic(_isLocal)
	end,
	[BattleType.PKRANDOM] = function( _isLocal, ... )
		return BattlePkLogic(_isLocal)
	end,
}

function BattleManager:BuildBattleLogic( _battleType, _isLocal, ... )
	local builder = BattleLogicSwitcher[_battleType]
	if builder then
		return builder(_isLocal)
	end
	return false
end

function BattleManager:SetBattleRecordFrameCount( _frameCount, ... )
	-- 同步录像帧数
	gBattleRecord.frameCount = _frameCount

	if self.battleTime == 0 then
		return true
	end

	if self.battleState == BattleState.PENDING and self.lastBattleState == BattleState.BATTLEING then
		self:ChangeBattleState(BattleState.BATTLEING)
	end
	return false
end

-- 生成状态ID
function BattleManager:GenerateBufferId()
	self.bufferIdGenerator = self.bufferIdGenerator + 1
	return self.bufferIdGenerator
end

-- 获取快照
function BattleManager:TakeSnapShot( ... )
	local time = Time.realtimeSinceStartup
	local tSnapShot = TSSnapShot:new{}
	tSnapShot.FrameCount = gBattleFrameCount
	tSnapShot.BattleTime = gBattleTime
	tSnapShot.BufferIdGenerator = self.bufferIdGenerator
	tSnapShot.Record = gBattleRecord:Serialize()
	tSnapShot.Timer = gBattleTimer:Serialize()
	tSnapShot.Logic = gBattleLogic:Serialize()
	-- warn(string.format('TakeSnapShot CostTime[%.4fms] Frame[%d]', (Time.realtimeSinceStartup - time), gBattleFrameCount))

	-- local transport = TMemoryBuffer:new{}
 --    local protocol = TBinaryProtocolFactory:getProtocol(transport)
 --    tSnapShot:write(protocol)
 --    local buffer = Slua.ToBytes(transport.buffer)
 --    local detail = gameutils.JSON:encode(tSnapShot)
 --    warn(string.format('TakeSnapShot Frame[%d] Pending[%s] Length[%d] MD5[%s]', gBattleFrameCount, tostring(gBattleRecord:HavePendingFrame()), buffer.Length, GameSecurity.ComputeStringMd5(detail)))
 --    warn('TakeSnapShot Detail ' .. detail)
	return tSnapShot
end

-- 推送快照
function BattleManager:PushSnapShot( _tSnapShot, ... )
	if not _tSnapShot then
		return
	end
	self.isSnapShotPushing = true
	Global.gSnapShotPushing = true
	local time = os_clock()
	self.battleFrameCount = _tSnapShot.FrameCount
	self.bufferIdGenerator = _tSnapShot.BufferIdGenerator
	self.battleTime = _tSnapShot.BattleTime
	Global.gBattleTime = self.battleTime
	Global.gBattleFrameCount = self.battleFrameCount
	gBattleLogic:DeSerialize(_tSnapShot.Logic)
	gBattleTimer:DeSerialize(_tSnapShot.Timer)
	gBattleRecord:DeSerialize(_tSnapShot.Record)
	-- 处理推送结束
	local priorityEventList = self.snapShotPushEndEventList
	for i = 1, #priorityEventList do
		local eventList = priorityEventList[i]
		for n = 1, #eventList do
			eventList[n]()
		end
		priorityEventList[i] = nil
	end
	self.isSnapShotPushing = false
	Global.gSnapShotPushing = false
	warn(string.format('Push SnapShot CostTime[%.2fms] Frame[%d] RecordFrame[%d]', (os_clock() - time) * 1000, gBattleFrameCount, gBattleRecord.frameCount))
end

function BattleManager:RegisterSnapShotPushEndEvent( _event, _priority, ... )
	local priority = _priority or 1
	local priorityEventList = self.snapShotPushEndEventList
	if #priorityEventList < priority then
		for i = 1, priority do
			if not priorityEventList[i] then
				priorityEventList[i] = {}
			end
		end
	end
	table_insert(priorityEventList[priority], _event)
end

-- 添加战斗日志
function BattleManager:AddBattleLog( _log, _isSignal, ... )  
	-- 打印日志
	print(_log, ...)
	
	-- 记录到结果日志中
	if _isSignal then
		log(self.battleId, _log)
	else
		log(self.battleId, string.format('[%d] %s\n', gBattleFrameCount, _log))
	end
	-- if self.curSingleResult then
	-- 	table.insert(self.curSingleResult.battleLogList, _log)
	-- end
end