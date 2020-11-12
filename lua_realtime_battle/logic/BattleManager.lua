---
--- class BattleManager
-- @classmod BattleManager
-- 战斗管理器
class('BattleManager')

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
end

function BattleManager:Finalize( ... )
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
end

function BattleManager:Initialize( _battleRecord, ... )
	-- 战斗时间
	self.battleTime = 0
	Global.gBattleTime = 0
	Global.gBattleFrameCount = 0
	self.battleId = _battleRecord.battleId

	gBattleManager:AddBattleLog('log_reset', true)
	gBattleManager:AddBattleLog(string.format("Battle Begin Seed[%d] BattleId[%s] BattleType[%d]", _battleRecord.battleSeed, _battleRecord.battleId, _battleRecord.battleType))	

	-- 初始化计时器
	self.battleTimer = LTimer()
	Global.gBattleTimer = self.battleTimer
	gBattleTimer:Initialize()

	-- 初始化战斗触发器
	self.battleTrigger = BattleTrigger()
	Global.gBattleTrigger = self.battleTrigger
	gBattleTrigger:Initialize()

	-- 初始化战斗逻辑
	self.battleLogic = self:BuildBattleLogic(_battleRecord.battleType)
	Global.gBattleLogic = self.battleLogic
	gBattleLogic:Initialize(_battleRecord.battleType)

	-- 初始化战斗记录器
	self.battleRecord = _battleRecord
	Global.gBattleRecord = self.battleRecord
	gBattleRecord:Initialize()

	-- 渲染帧转逻辑帧，时间增量
	self.updateDeltaTime = Constants.BATTLE_FRAME_TIME
end

function BattleManager:Update( _deltaTime, ... )
	-- 修正战斗状态
	self:CheckNextBattleState()

	if self.battleState ~= BattleState.BATTLEING then
		return
	end

	self.updateTime = self.updateTime + _deltaTime
	-- 实时战斗需要根据帧差修复帧，将前后端帧差维持在10帧
	if self.battleRecord.isRealTime then
		local frameDistance = self.battleRecord:GetRealTimeFrameCount() - self.battleFrameCount
		if frameDistance > Constants.BATTLE_SERVER_LEAD_FRAME_COUNT + Constants.BATTLE_FPS then
			-- 暴力追帧
			self.updateTime = (frameDistance - Constants.BATTLE_SERVER_LEAD_FRAME_COUNT) * self.updateDeltaTime
			-- warn('暴力追帧', self.updateTime, self.updateDeltaTime, frameDistance, self.battleFrameCount)
		elseif frameDistance > Constants.BATTLE_SERVER_LEAD_FRAME_COUNT + 1 and self.updateDeltaTime == Constants.BATTLE_FRAME_TIME then
			-- 平缓追帧
			self.updateDeltaTime = Constants.BATTLE_FRAME_TIME - 4
			-- warn('平缓追帧', self.updateTime, self.updateDeltaTime, frameDistance, self.battleFrameCount)
		elseif frameDistance <= Constants.BATTLE_SERVER_LEAD_FRAME_COUNT + 1 and self.updateDeltaTime ~= Constants.BATTLE_FRAME_TIME then
			-- 正常帧
			self.updateDeltaTime = Constants.BATTLE_FRAME_TIME
			-- warn('正常帧', self.updateTime, self.updateDeltaTime, frameDistance, self.battleFrameCount)
		end
	end
	while (self.updateTime >= self.updateDeltaTime) do
		-- 逻辑帧校验战斗状态
		if self.battleState ~= BattleState.BATTLEING then
			self.updateTime = 0
			break
		end
		-- 逻辑帧超过即时战斗最大帧，则需要缓冲，等待收到后续帧再执行
		if self.battleFrameCount >= self.battleRecord:GetRealTimeFrameCount() then
			self:ChangeBattleState(BattleState.PENDING)
			break
		end

		self.updateTime = self.updateTime - self.updateDeltaTime
		
		-- 战斗逻辑帧
		self.battleFrameCount = self.battleFrameCount + 1
		self.battleTime = self.battleTime + Constants.BATTLE_FRAME_TIME 
		Global.gBattleTime = self.battleTime
		Global.gBattleFrameCount = self.battleFrameCount

		-- 战斗记录中，取出当前应该执行的所有帧
		while true do
			local nextFrameCount, nextFramePlayer = gBattleRecord:GetNextFrameCount()
			if nextFrameCount > self.battleFrameCount then
				break
			end
			-- 执行战斗帧
			local nextFrame = nextFramePlayer:GetNextFrame(true)
			self:ExecBattleFrame(nextFramePlayer.playerId, nextFrame, nextFramePlayer)
		end

		-- 战斗计时器
		gBattleTimer:Update(Constants.BATTLE_FRAME_TIME)

		-- 战斗逻辑
		gBattleLogic:Update(Constants.BATTLE_FRAME_TIME)

		-- 战斗录像
		gBattleRecord:Update(Constants.BATTLE_FRAME_TIME)

		-- 检查战斗是否结束
		if gBattleLogic:CheckBattleEnd() then
			self:ChangeBattleState(BattleState.END)
		end

		if self.battleFrameCount % (Constants.BATTLE_FPS / 2) == 0 then
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.STAT)
		end

		-- 修正战斗状态
		self:CheckNextBattleState()
	end

	-- 修正战斗状态
	self:CheckNextBattleState()
end

function BattleManager:BeginBattle( ... )
	-- 战斗开始
	self:ChangeBattleState(BattleState.BATTLEING)
end

function BattleManager:ChangeBattleState( _state )
	if _state == self.nextBattleState then
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

function BattleManager:CheckNextBattleState( ... )
	if self.nextBattleState == self.battleState then
		return
	end

	self.lastBattleState = self.battleState
	self.battleState = self.nextBattleState

	local switcher = BattleStateSwitcher[self.battleState]
	if switcher then
		switcher(self.lastBattleState)
	end
end

-- 战斗帧处理器
local BattleFrameSwitcher = {
	-- 抽卡
	[BattleFrameType.ROLL] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecRoll(_playerId, _frame, _player, true)
	end,
	-- 选卡
	[BattleFrameType.SELECT] = function( _playerId, _frame, _player, ... )
	end,
	-- 合成
	[BattleFrameType.MERGE] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecMerge(_playerId, _frame, _player, true)
	end,
	-- 释放魔法
	[BattleFrameType.MAGIC] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecMagic(_playerId, _frame, _player, true)
	end,
	-- 投降
	[BattleFrameType.SURRENDER] = function( _playerId, _frame, _player, ... )
		return gBattleRecord:ExecSurrender(_playerId, _frame, _player, true)
	end,
	-- 表情
	[BattleFrameType.EMOJI] = function( _playerId, _frame, _player, ... )
	end,
}

function BattleManager:ExecBattleFrame( _playerId, _frame, _player, ... )
	if not _frame then
		return
	end
	gBattleManager:AddBattleLog(string.format('ExecBattleFrame Frame[%d] Player[%d] Type[%d]', self.battleFrameCount, _playerId, _frame.frameType))
	local switcher = BattleFrameSwitcher[_frame.frameType]
	if switcher then
		local result = false
		local code = -1
		result, code = switcher(_playerId, _frame, _player)
		if not result and code ~= 0 then
			error(string.format('ExecBattleFrame Error %d %d %d %d %s %s', code, _playerId, _frame.frameType, _frame.frameCount, _frame.param1, _frame.param2))
		end
	end
end

function BattleManager:OnBattleBegin( ... )
	self.battleFrameCount = 0
	self.battleTime = 0
	self.updateTime = 0

	-- 触发战斗开始
	gBattleLogic:OnBattleBegin()
end

function BattleManager:OnBattleEnd( ... )
	-- 最后一帧
	gBattleResult:SetFrameCount(self.battleFrameCount)

	-- 通知前端战斗结束
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.BATTLEEND, gBattleResult, gBattleRecord.battleId)

	warn('OnBattleEnd', gBattleResult.winPlayerId, gBattleResult.frameCount)
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
	[BattleType.PK] = function( ... )
		return BattlePkLogic()
	end,
	[BattleType.COOP] = function( ... )
		return BattleCoopLogic()
	end
}

function BattleManager:BuildBattleLogic( _battleType, ... )
	local builder = BattleLogicSwitcher[_battleType]
	if builder then
		return builder()
	end
	return false
end

function BattleManager:SetBattleRecordFrameCount( _frameCount, ... )
	-- 同步录像帧数
	gBattleRecord.frameCount = _frameCount

	if self.battleTime == 0 then
		-- 开始战斗
		self:BeginBattle()
		return
	end

	if self.battleState == BattleState.PENDING and self.lastBattleState == BattleState.BATTLEING then
		self:ChangeBattleState(BattleState.BATTLEING)
	end
end

-- 生成状态ID
function BattleManager:GenerateBufferId()
	self.bufferIdGenerator = self.bufferIdGenerator + 1
	return self.bufferIdGenerator
end

-- 添加战斗日志
function BattleManager:AddBattleLog( _log, _isSignal, ... )
	-- 打印日志
	print(_log, ...)
	
	-- 记录到结果日志中
	if _isSignal then
		log(self.battleId, _log)
	else
		log(self.battleId, string.format('[%d] %s\n', self.battleFrameCount, _log))
	end
	-- if self.curSingleResult then
	-- 	table.insert(self.curSingleResult.battleLogList, _log)
	-- end
end

classend()