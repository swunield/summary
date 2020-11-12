---
--- class BattlePlayerFrame
-- @classmod BattlePlayerFrame
class('BattlePlayerFrame')

---Constructor
function BattlePlayerFrame:ctor( ... )
	self.frameList = {}							-- 战斗帧列表，BattleFrame

	self.pendingFrameQueue = LQueue(32)			-- 战斗缓冲帧队列，BattleFrame
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
end

function BattlePlayerFrame:GetNextFrame( _moveToNext, ... )
	if self.nextIndex > #self.frameList then
		return false
	end
	if _moveToNext then
		self.nextIndex = self.nextIndex + 1
		return self.frameList[self.nextIndex - 1]
	end
	return self.frameList[self.nextIndex]
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
	self.pendingFrameQueue:EnQueue(_frame)
end

function BattlePlayerFrame:CheckBattlePendingFrame( _frame, ... )
	if not _frame then
		return false
	end
	local pendingFrame = self.pendingFrameQueue:Peek()
	if not pendingFrame or pendingFrame.frameId ~= _frame.frameId then
		return false
	end
	-- 移除缓冲帧
	self.pendingFrameQueue:DeQueue()
	-- 通知战斗帧结束缓冲
	pendingFrame:OnPendingOver()
	return true
end

classend()
export('BattlePlayerFrame', BattlePlayerFrame)