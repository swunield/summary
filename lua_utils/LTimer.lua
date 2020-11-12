---
--- class LTimerTask
-- @classmod LTimerTask
-- 计时器任务
class('LTimerTask')

---Constructor
function LTimerTask:ctor( ... )
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
--- class LTimer
-- @classmod LTimer
-- 计时器，所有时间都以毫秒计
class('LTimer')

---Constructor
function LTimer:ctor( ... )
	self.taskList = {}				-- LTimerTask列表
	self.time = 0 					-- 当前时间
	self.isRunning = false 			-- 是否运行中
	self.taskIdGenerator = 0		-- 任务Id生成器
end

function LTimer:Finalize( ... )

end

function LTimer:Initialize( ... )

end

function LTimer:Update( _delta, ... )
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

function LTimer:RunTask( _taskName, _delayTime, _repeatTime, _repeatCount, _taskEvent, _repeatEvent, _completeEvent, ... )
	local task = self:GetTask(_taskName)
	if not task then
		task = LTimerTask()
		task.taskId = self:GenerateTaskId()
		task.taskName = Utils.EmptyDefault(_taskName, string.format('Task_%d', task.taskId))
		task.taskEvent = Utils.NilDefault(_taskEvent, false)
		task.repeatEvent = Utils.NilDefault(_repeatEvent, false)
		task.completeEvent = Utils.NilDefault(_completeEvent, false)

		table_insert(self.taskList, task)
	end

	task.delayTimeList = false
	task.delayIndex = 0
	task.delayTime = Utils.NilDefault(_delayTime, task.delayTime)
	task.repeatTime = Utils.NilDefault(_repeatTime, task.repeatTime)
	task.repeatCount = Utils.NilDefault(_repeatCount, task.repeatCount)
	task.beginTime = self.time
	task.time = self.time
	task.allreadyRepeat = -1
	task.isPause = false

	self.isRunning = true

	return task
end

function LTimer:RunQueueTask( _taskName, _delayTimeList, _repeatTime, _repeatCount, _taskEvent, _repeatEvent, _completeEvent, ... )
	if not _delayTimeList or #_delayTimeList == 0 then
		return false
	end

	local task = self:GetTask(_taskName)
	if not task then
		task = LTimerTask()
		task.taskId = self:GenerateTaskId()
		task.taskName = Utils.EmptyDefault(_taskName, string.format('Task_%d', task.taskId))
		task.taskEvent = Utils.NilDefault(_taskEvent, false)
		task.repeatEvent = Utils.NilDefault(_repeatEvent, false)
		task.completeEvent = Utils.NilDefault(_completeEvent, false)

		table_insert(self.taskList, task)
	end

	task.delayTimeList = _delayTimeList
	task.delayIndex = 1
	task.delayTime = task.delayTimeList[task.delayIndex]
	task.repeatTime = Utils.NilDefault(_repeatTime, task.repeatTime)
	task.repeatCount = Utils.NilDefault(_repeatCount, task.repeatCount)
	task.beginTime = self.time
	task.time = self.time
	task.allreadyRepeat = -1
	task.isPause = false

	self.isRunning = true

	return task
end

function LTimer:StopTask( _taskName, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	task.beginTime = -1
	task.allreadyRepeat = -1
end

function LTimer:StopAllTask( ... )
	local count = #self.taskList
	for i = 1, count do
		local task = self.taskList[i]
		task.beginTime = -1
		task.allreadyRepeat = -1
	end
	self.isRunning = false
end

function LTimer:PauseTask( _taskName, _isPause, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	task.isPause = Utils.NilDefault(_isPause, true)
end

function LTimer:PauseAllTask( _isPause, ... )
	local isPause = Utils.NilDefault(_isPause, true)
	local count = #self.taskList
	for i = 1, count do
		local task = self.taskList[i]
		task.isPause = isPause
	end
end

function LTimer:SetTaskEvent( _taskName, _taskEvent, _repeatEvent, _completeEvent, ... )
	local task = self:GetTask(_taskName)
	if not task then
		return
	end
	task.taskEvent = Utils.NilDefault(_taskEvent, false)
	task.repeatEvent = Utils.NilDefault(_repeatEvent, false)
	task.completeEvent = Utils.NilDefault(_completeEvent, false)
end

function LTimer:GetTask( _taskName )
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

function LTimer:GenerateTaskId( ... )
	self.taskIdGenerator = self.taskIdGenerator + 1
	return self.taskIdGenerator
end

classend()
export('LTimer', LTimer)