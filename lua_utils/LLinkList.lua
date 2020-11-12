---
--- class LLinkListNode
-- @classmod LLinkListNode
-- 链表节点
class('LLinkListNode')

---Constructor
function LLinkListNode:ctor( _value, _list, ... )
	self.value = Utils.NilDefault(_value, false)
	self.next = false
	self.pre = false
	self.list = Utils.NilDefault(_list, false)
end

function LLinkListNode:Update( ... )
	self.list:UpdateNode(self)
end

classend()
export('LLinkListNode', LLinkListNode)


---
--- class LLinkList
-- @classmod LLinkList
-- 链表，支持自动排序
class('LLinkList')

---Constructor
function LLinkList:ctor( _compare, ... )
	self.first = false										-- 头节点
	self.last = false										-- 尾节点
	self.count = 0											-- 链表长度
	self.compare = Utils.NilDefault(_compare, false) 		-- 排序比较
end

function LLinkList:SetCompare( _compare, ... )
	self.compare = Utils.NilDefault(_compare, false)
end

function LLinkList:Add( _value, ... )
	local node = LLinkListNode(_value, self)
	return self:AddNode(node)
end

function LLinkList:AddNode( _node, ... )
	if self.count == 0 or not self.compare then
		return self:AddNodeLast(_node)
	end
	local node = self.first
	while node do
		if self.compare(_node.value, node.value) < 0 then
			return self:AddNodeBefore(node, _node)
		end
		node = node.next
	end
	return self:AddNodeLast(_node)
end

function LLinkList:UpdateNode( _node, ... )
	if not _node or not self.compare then
		return
	end
	local nextSwaped = false
	local nextNode = _node.next
	while nextNode do
		if self.compare(_node.value, nextNode.value) >= 0 then
			self:SwapNode(_node, nextNode)
			nextNode = _node.next
			nextSwaped = true
		else
			break
		end
	end
	if not nextSwaped then
		local preNode = _node.pre
		while preNode do
			if self.compare(preNode.value, _node.value) >= 0 then
				self:SwapNode(preNode, _node)
				preNode = _node.pre
			else
				break
			end
		end
	end
end

-- 相邻节点交换
function LLinkList:SwapNode( _lNode, _rNode, ... )
	if _lNode.next == _rNode then
		_rNode.pre = _lNode.pre
		_lNode.next = _rNode.next
		_rNode.next = _lNode
		_lNode.pre = _rNode
		if _rNode.pre then
			_rNode.pre.next = _rNode
		end
		if _lNode.next then
			_lNode.next.pre = _lNode
		end
	elseif _lNode.pre == _rNode then
		_lNode.pre = _rNode.pre
		_rNode.next = _lNode.next
		_lNode.next = _rNode
		_rNode.pre = _lNode
		if _lNode.pre then
			_lNode.pre.next = _lNode
		end
		if _rNode.next then
			_rNode.next.pre = _rNode
		end
	end
	if self.first == _lNode then
		self.first = _rNode
	elseif self.first == _rNode then
		self.first = _lNode
	end
	if self.last == _lNode then
		self.last = _rNode
	elseif self.last == _rNode then
		self.last = _lNode
	end
end

function LLinkList:AddAfter( _node, _value, ... )
	local newNode = LLinkListNode(_value, self)
	return self:AddAfter(_node, newNode)
end

function LLinkList:AddNodeAfter( _node, _newNode, ... )
	if not _node then
		return self:AddLast(_newNode)
	end

	self.count = self.count + 1
	
	local nextNode = _node.next
	_node.next = _newNode
	_newNode.pre = _node
	_newNode.next = nextNode
	if nextNode then
		nextNode.pre = _newNode
	else
		self.last = _newNode
	end
	return _newNode
end

function LLinkList:AddBefore( _node, _value, ... )
	local newNode = LLinkListNode(_value, self)
	return self:AddBefore(_node, newNode)
end

function LLinkList:AddNodeBefore( _node, _newNode, ... )
	if not _node then
		return self:AddFirst(_newNode)
	end

	self.count = self.count + 1
	
	local preNode = _node.pre
	_node.pre = _newNode
	_newNode.pre = preNode
	_newNode.next = _node
	if preNode then
		preNode.next = _newNode
	else
		self.first = _newNode
	end
	return _newNode
end

function LLinkList:AddFirst( _value, ... )
	local node = LLinkListNode(_value, self)
	return self:AddNodeFirst(node)
end

function LLinkList:AddNodeFirst( _node, ... )
	if not self.first then
		self.first = _node
		self.last = _node
		_node.next = false
		_node.pre = false
		self.count = 1
		return _node
	end
	return self:AddNodeBefore(self.first, _node)
end

function LLinkList:AddLast( _value, ... )
	local node = LLinkListNode(_value, self)
	return self:AddNodeLast(node)
end

function LLinkList:AddNodeLast( _node, ... )
	if not self.last then
		self.first = _node
		self.last = _node
		_node.next = false
		_node.pre = false
		self.count = 1
		return _node
	end
	return self:AddNodeAfter(self.last, _node)
end

function LLinkList:Clear( ... )
	self.first = false
	self.last = false
	self.count = 0
end

function LLinkList:Contains( _value, ... )
	return self:Find(_value) ~= false
end

function LLinkList:Remove( _value, ... )
	local node = self:Find(_value)
	if node then
		return self:RemoveNode(node)
	end
	return false
end

function LLinkList:RemoveNode( _node, ... )
	if not _node then
		return false
	end
	if _node == self.first then
		return self:RemoveFirst()
	end
	if _node == self.last then
		return self:RemoveLast()
	end
	local nextNode = _node.next
	local preNode = _node.pre
	preNode.next = nextNode
	nextNode.pre = preNode
	self.count = self.count - 1
	return nextNode
end

function LLinkList:RemoveFirst( ... )
	if not self.first then
		return false
	end
	if self.count == 1 then
		self:Clear()
		return false
	end
	local nextNode = self.first.next
	nextNode.pre = false
	self.first = nextNode
	self.count = self.count - 1
	return nextNode
end

function LLinkList:RemoveLast( ... )
	if not self.last then
		return false
	end
	if self.count == 1 then
		self:Clear()
		return false
	end
	local preNode = self.last.pre
	preNode.next = false
	self.last = preNode
	self.count = self.count - 1
	return preNode
end

function LLinkList:Find( _value, _fieldName, ... )
	if not self.first then
		return false
	end
	local node = self.first
	while node do
		if _fieldName and node.value[_fieldName] == _value then
			return node
		end
		if not _fieldName and node.value == _value then
			return node
		end
		node = node.next
	end
	return false
end

classend()
export('LLinkList', LLinkList)