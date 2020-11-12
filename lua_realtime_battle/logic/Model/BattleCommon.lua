-- 属性列表
-- 带分支的必然为百分比
-- 常规属性默认只有branch 1一条分支
class('AttributeList')

function AttributeList:ctor( ... )
	self.valueList = {}
	self.dirtyList = {}
	self.finalValueList = {}
end

function AttributeList:UpdateAttribute( _attrType, _branch, _value, _add, ... )
	local baseType = _attrType % 100
	if baseType <= AttriType.ALL or baseType >= AttriType.MAX then
		return 0, 0
	end
	local isAdd = NilDefault(_add, true)
	local branch = NilDefault(_branch, 1)
	branch = branch == 0 and 1 or branch
	if not self.valueList[_attrType] then
		self.valueList[_attrType] = {}
	end
	local valueList = self.valueList[_attrType]
	if not valueList[branch] then
		for i = #valueList + 1, branch do
			valueList[i] = 0
		end
	end
	local oldValue = valueList[branch]
	if isAdd then
		valueList[branch] = oldValue + _value 
	else
		valueList[branch] = oldValue - _value
	end
	self.dirtyList[_attrType] = true
	return valueList[branch], oldValue
end

function AttributeList:GetAttribute( _attrType, _branch, _isPercent, ... )
	local valueList = self.valueList[_attrType]
	if not valueList or (_branch and not valueList[_branch]) then
		return _isPercent and 1 or 0
	end
	if _branch then
		return _isPercent and (1 + valueList[_branch] * s_PercentScale) or valueList[_branch]
	end
	if #valueList == 1 then
		return _isPercent and (1 + valueList[1] * s_PercentScale) or valueList[1]
	end
	if self.dirtyList[_attrType] == false then
		return self.finalValueList[_attrType]
	end
	local result = 1
	for i = 1, #valueList do
		result = result * (1 + (valueList[i] and valueList[i] or 0) * s_PercentScale)
	end
	self.finalValueList[_attrType] = result
	self.dirtyList[_attrType] = false
	return result
end

classend()