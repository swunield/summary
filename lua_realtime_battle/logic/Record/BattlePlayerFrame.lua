---
--- class BattlePlayerFrame
-- @classmod BattlePlayerFrame
BattlePlayerFrame = xclass('BattlePlayerFrame')

local table_insert = table.insert
local LMQueue = plugins.gameutils.LMQueue
local LMQueue_New = LMQueue.New
local LMQueue_Peek = LMQueue.Peek
local LMQueue_EnQueue = LMQueue.EnQueue
local LMQueue_DeQueue = LMQueue.DeQueue
local LMQueue_SetCapacity = LMQueue.SetCapacity
local LMQueue_ForEach = LMQueue.ForEach
local LMQueue_Clear = LMQueue.Clear

---Constructor
function BattlePlayerFrame:ctor( ... )
	self.frameList = {}							-- 战斗帧列表，BattleFrame

	self.pendingFrameQueue = false				-- 战斗缓冲帧队列，BattleFrame
	self.nextIndex = 1							-- 运行时下一帧列表索引
	self.player = false							-- 玩家
end

function BattlePlayerFrame:Load( _tPlayerFrame, ... )
	if not _tPlayerFrame then
		return
	end

	self.frameList = {}
	for i = 1, #_tPlayerFrame.FrameList do
		local frame = BattleFrame()
		frame:Load(_tPlayerFrame.FrameList[i])
		table_insert(self.frameList, frame)
	end
end

function BattlePlayerFrame:Destroy( ... )
	self.player = false
end

function BattlePlayerFrame:Init( _player, ... )
	self.player = _player

	self.pendingFrameQueue = LMQueue_New()
	LMQueue_SetCapacity(self.pendingFrameQueue, 32)
end

function BattlePlayerFrame:GetNextFrame( _moveToNext, ... )
	local nextIndex = self.nextIndex
	local frameList = self.frameList
	if nextIndex > #frameList then
		return false
	end
	if _moveToNext then
		nextIndex = nextIndex + 1
		self.nextIndex = nextIndex
		return frameList[nextIndex - 1]
	end
	return frameList[nextIndex]
end

function BattlePlayerFrame:GetNextFrameCount( ... )
	local nextFrame = self:GetNextFrame()
	if not nextFrame then
		return 0
	end
	return nextFrame.frameCount
end

function BattlePlayerFrame:AddBattleFrame( _frame, _frameCount, _frameType, _param1, _param2, _point, ... )
	if not _frame then
		_frame = self.player:GenerateBattleFrame(_frameType, _param1, _param2, _frameCount)
	end
	table_insert(self.frameList, _frame)

	-- 打印Log
	-- gBattleManager:AddBattleLog(string.format('Add Battle Frame Frame[%d] Type[%d] Param1[%s] Param2[%s] Point[%d]', _frame.frameCount, _frame.frameType, tostring(_frame.param1), tostring(_frame.param2), _frame.point))
end

function BattlePlayerFrame:AddBattlePendingFrame( _frame, ... )
	LMQueue_EnQueue(self.pendingFrameQueue, _frame)
end

function BattlePlayerFrame:CheckBattlePendingFrame( _frame, ... )
	if not _frame then
		return false
	end
	local pendingFrame = LMQueue_Peek(self.pendingFrameQueue)
	if not pendingFrame or pendingFrame.frameId ~= _frame.frameId then
		return false
	end
	-- 移除缓冲帧
	LMQueue_DeQueue(self.pendingFrameQueue)
	-- 通知战斗帧结束缓冲
	pendingFrame:OnPendingOver()
	return true
end

function BattlePlayerFrame:HavePendingFrame( ... )
	return self.pendingFrameQueue.size ~= 0
end
