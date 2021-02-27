---
--- class BattleTimerTask
-- @classmod BattleTimerTask
-- 计时器任务
class('BattleTimerTask')

---Constructor
function BattleTimerTask:ctor( ... )
	self.taskId = false					-- 任务Id
	self.taskName = false 				-- 任务名称
	self.delayTime = 0 					-- 延迟时间
	self.delayTimeList = false			-- 延迟时间列表，队列执行
	self.delayIndex = 0					-- 延迟索引
	self.repeatTime = 0 				-- 重复时间，0不重复
	self.repeatCount = 0 				-- 重复次数，重复时间非0切次数0时，会无限重复
	self.taskEvent = false 				-- 计时器任务
	self.repeatEvent = false 			-- 计时器重复任务
	self.completeEvent = false 			-- 计时器结束任务

	self.beginTime = -1 				-- 开始时间，结束-1
	self.allreadyRepeat = -1 			-- 已经重复的次数，初始-1
	self.isPause = false 				-- 是否暂停
	self.time = 0						-- 任务时间
end

classend()


---
--- class BattleTimer
-- @classmod BattleTimer
-- 计时器，所有时间都以毫秒计
class('BattleTimer')

local table_insert = table.insert

local TSTimer = gModel.TSTimer
local TSTimerTask = gModel.TSTimerTask

---Constructor
function BattleTimer:ctor( ... )
	self.taskList = {}				-- BattleTimerTask列表
	self.time = 0 					-- 当前时间
	self.isRunning = false 			-- 是否运行中
	self.taskIdGenerator = 0		-- 任务Id生成器
end

function BattleTimer:Serialize( ... )
	local tTimer = TSTimer:new{}
	tTimer.Time = self.time
	tTimer.Running = self.isRunning and 1 or nil
	tTimer.TaskList = {}
	for i = 1, #self.taskList do
		local task = self.taskList[i]
		local tTask = TSTimerTask:new{}
		tTask.Name = task.taskName
		tTask.Delay = task.delayTime ~= 0 and task.delayTime or nil
		tTask.DelayIndex = task.delayIndex ~= 0 and task.delayIndex or nil
		if self.delayTimeList and #self.delayTimeList > 0 then
			tTask.DeayTimeList = {}
			for i = 1, #self.delayTimeList do
				table_insert(tTask.DelayTimeList, self.delayTimeList[i])
			end
		end
		tTask.RepeatTime = task.repeatTime ~= 0 and task.repeatTime or nil
		tTask.RepeatCount = task.repeatCount ~= 0 and task.repeatCount or nil
		tTask.BeginTime = task.beginTime
		tTask.AllReadyRepeat = task.allreadyRepeat
		tTask.Time = task.time ~= 0 and task.time or nil
		tTask.Pause = task.isPause and 1 or nil
		table_insert(tTimer.TaskList, tTask)
	end
	return tTimer
end

function BattleTimer:DeSerialize( _tTimer, ... )
	if not _tTimer then
		return
	end
	self.time = _tTimer.Time
	self.isRunning = _tTimer.Running == 1
	for i = 1, #_tTimer.TaskList do
		local tTask = _tTimer.TaskList[i]
		local task = self:GetTask(tTask.Name)
		if task then
			task.delayTime = tTask.Delay or 0
			task.delayIndex = tTask.DelayIndex or 0
			if tTask.DelayTimeList then
				task.delayTimeList = {}
				for i = 1, #tTask.DelayTimeList do
					table_insert(task.delayTimeList, tTask.DelayTimeList[i])
				end
			end
			task.repeatTime = tTask.RepeatTime or 0
			task.repeatCount = tTask.RepeatCount or 0
			task.beginTime = tTask.BeginTime
			task.allreadyRepeat = tTask.AllReadyRepeat
			task.time = tTask.Time or 0
			task.isPause = tTask.Pause == 1
		end
	end
end

function BattleTimer:Finalize( ... )

end

function BattleTimer:Initialize( ... )

end

function BattleTimer:Update( _delta, ... )
	-- 当前时间
	self.time = self.time + _delta

	-- 计时器未运行
	if not self.isRunning then
		return
	end

	local isAllTaskOver = true
	local count = #self.taskList
	for i = count, 1, -1 do
		local task = self.taskList[i]
		if task.beginTime ~= -1 and not task.isPause then
			isAllTaskOver = false
			task.time = task.time + _delta

			-- 触发计时器任务
			if task.time >= task.beginTime + task.delayTime and task.allreadyRepeat == -1 then
				local isLastDelayTask = not task.delayTimeList or task.delayIndex == #task.delayTimeList
				if isLastDelayTask then
					task.allreadyRepeat = 0
				end
				if task.taskEvent then
					task.taskEvent(task.delayIndex)
				end
				if not isLastDelayTask then
					task.delayIndex = task.delayIndex + 1
					task.delayTime = task.delayTimeList[task.delayIndex]
				elseif task.delayTime == 0 and task.repeatEvent then
					task.repeatEvent(task.allreadyRepeat)
				end
			end
			-- 触发计时器重复任务
			if task.allreadyRepeat ~= -1 and task.time >= task.beginTime + task.delayTime + task.repeatTime * (task.allreadyRepeat + 1) then
				task.allreadyRepeat = task.allreadyRepeat + 1

				if task.repeatEvent then
					task.repeatEvent(task.allreadyRepeat)
				end
			end
			-- 触发结束任务
			local isRepeatForever = task.repeatTime ~= 0 and task.repeatCount <= 0
			if not isRepeatForever and task.allreadyRepeat >= task.repeatCount then
				-- 结束任务
				task.beginTime = -1

				if task.completeEvent then
					task.completeEvent()
				end
			end
		end
	end

	self.isRunning = not isAllTaskOver
end

function BattleTimer:RunTask( _taskName, _delayTime, _repeatTime, _repeatCount, _taskEvent, _repeatEvent, _completeEvent, ... )
	local task = self:GetTask(_taskName)
	if not task then
		task = BattleTimerTask()
		task.taskId = self:GenerateTaskId()
		task.taskName = _taskName or string.format('Task_%d', task.taskId)
		task.taskEvent = _taskEvent or false
		task.repeatEvent = _repeatEvent or false
		task.completeEvent = _completeEvent or false

		table_insert(self.taskList, task)
	end

	task.delayTimeList = false
	task.delayIndex = 0
	task.delayTime = _delayTime or task.delayTime
	task.repeatTime = _repeatTime or task.repeatTime
	task.repeatCount = _repeatCount or task.repeatCount
	task.beginTime = self.time
	task.time = self.time
	task.allreadyRepeat = -1
	task.isPause = false

	if _taskEvent ~= nil then
		task.taskEvent = _taskEvent
	end
	if _repeatEvent ~= nil then
		task.repeatEvent = _repeatEvent
	end
	if _completeEvent ~= nil then
		task.completeEvent = _completeEvent
	end

	self.isRunning = true

	return task
end

function BattleTimer:RunQueueTask( _taskName, _delayTimeList, _repeatTime, _repeatCount, _taskEvent, _repeatEvent, _completeEvent, ... )
	if not _delayTimeList or #_delayTimeList == 0 then
		return false
	end

	local task = self:GetTask(_taskName)
	if not task then
		task = BattleTimerTask()
		task.taskId = self:GenerateTaskId()
		task.taskName = _taskName or string.format('Task_%d', task.taskId)
		task.taskEvent = _taskEvent or false
		task.repeatEvent = _repeatEvent or false
		task.completeEvent = _completeEvent or false

		table_insert(self.taskList, task)
	end

	task.delayTimeList = _delayTimeList
	task.delayIndex = 1
	task.delayTime = task.delayTimeList[task.delayIndex]
	task.repeatTime = _repeatTime or task.repeatTime
	task.repeatCount = _repeatCount or task.repeatCount
	task.beginTime = self.time
	task.time = self.time
	task.allreadyRepeat = -1
	task.isPause = false

	if _taskEvent ~= nil then
		task.taskEvent = _taskEvent
	end
	if _repeatEvent ~= nil then
		task.repeatEvent = _repeatEvent
	end
	if _completeEvent ~= nil then
		task.completeEvent = _completeEvent
	end

	self.isRunning = true

	return task
end

function BattleTimer:StopTask( _taskName, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	task.beginTime = -1
	task.allreadyRepeat = -1
end

function BattleTimer:StopAllTask( ... )
	local count = #self.taskList
	for i = 1, count do
		local task = self.taskList[i]
		task.beginTime = -1
		task.allreadyRepeat = -1
	end
	self.isRunning = false
end

function BattleTimer:PauseTask( _taskName, _isPause, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	task.isPause = _isPause == nil and true or _isPause
end

function BattleTimer:PauseAllTask( _isPause, ... )
	local isPause = _isPause == nil and true or _isPause
	local count = #self.taskList
	for i = 1, count do
		local task = self.taskList[i]
		task.isPause = isPause
	end
end

function BattleTimer:SetTaskEvent( _taskName, _taskEvent, _repeatEvent, _completeEvent, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	
	if _taskEvent ~= nil then
		task.taskEvent = _taskEvent
	end
	if _repeatEvent ~= nil then
		task.repeatEvent = _repeatEvent
	end
	if _completeEvent ~= nil then
		task.completeEvent = _completeEvent
	end
end

function BattleTimer:GetTask( _taskName )
	if not _taskName then
		return false
	end
	local count = #self.taskList
	for i = 1, count do
		local task = self.taskList[i]
		if task and task.taskName == _taskName then
			return task
		end
	end
	return false
end

function BattleTimer:GenerateTaskId( ... )
	self.taskIdGenerator = self.taskIdGenerator + 1
	return self.taskIdGenerator
end

classend()
export('BattleTimer', BattleTimer)