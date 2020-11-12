---
--- class LQueue
-- @classmod LQueue
-- 队列，先进先出
class('LQueue')

---Constructor
function LQueue:ctor( _capacity, ... )
	self.capacity = _capacity and _capacity or 256
	self.queue = {}
	self.size = 0
	self.head = -1
	self.rear = -1
end

function LQueue:EnQueue( _element, ... )
	if self.size == 0 then
		self.head = 1
		self.rear = 1
		self.size = 1
		self.queue[self.rear] = _element
	else
		local index = self.rear % self.capacity + 1
		if index == self.head then
			error('LQueue capacity is full')
			return
		end
		self.rear = index
		self.queue[self.rear] = _element
		self.size = self.size + 1
	end
end

function LQueue:DeQueue( ... )
	if self:IsEmpty() then
		return nil
	end
	self.size = self.size - 1
	local element = self.queue[self.head]
	self.head = self.head % self.capacity + 1
	return element
end

function LQueue:Peek( ... )
	if self:IsEmpty() then
		return nil
	end
	return self.queue[self.head]
end

function LQueue:Clear( ... )
	self.queue = nil
	self.queue = {}
	self.size = 0
	self.head = -1
	self.rear = -1
end

function LQueue:IsEmpty( ... )
	return self:Size() == 0
end

function LQueue:Size( ... )
	return self.size
end

classend()
export('LQueue', LQueue)