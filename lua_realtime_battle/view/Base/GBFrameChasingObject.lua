---
--- class GBFrameChasingObject
-- @classmod GBFrameChasingObject
GBFrameChasingObject = xclass('GBFrameChasingObject')

---Constructor
function GBFrameChasingObject:ctor( ... )
	self.actionOrderList = {}
	self.actionMap = {}
end

function GBFrameChasingObject:Destroy( ... )
	self.actionOrderList = nil
	self.actionMap = nil
end

function GBFrameChasingObject:CheckFrameChasing( _key, _callBack, ... )
	if not gGBField.isFrameChasing then
		_callBack()
		return false
	end
	if not self.actionMap[_key] then
		table.insert(self.actionOrderList, _key)
	end
	self.actionMap[_key] = _callBack
	return true
end

function GBFrameChasingObject:OnFrameChasingOver( ... )
	local actionCount = #self.actionOrderList
	if actionCount == 0 then
		return
	end
	for i = 1, actionCount do
		local key = self.actionOrderList[i]
		local callBack = self.actionMap[key]
		if callBack then
			callBack()
		end
	end
	self.actionOrderList = {}
	self.actionMap = {}
end