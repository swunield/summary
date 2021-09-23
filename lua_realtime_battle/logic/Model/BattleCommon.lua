-- 属性列表
-- 带分支的必然为百分比
-- 常规属性默认只有branch 1一条分支
AttributeList = xclass('AttributeList')

local table_insert = table.insert

local TSAttributeList = gModel.TSAttributeList
local TSAttributeBranchMap = gModel.TSAttributeBranchMap
local TS2Int = gModel.TS2Int

function AttributeList:ctor( ... )
	self.valueList = {}
	self.dirtyList = {}
	self.finalValueList = {}
end

function AttributeList:Serialize( ... )
	local tAttri = nil
	for attrType, branchValueList in pairs(self.valueList) do
		local tAttriBranchMap = false
		for branch, value in pairs(branchValueList) do
			if value ~= 0 then
				if not tAttri then
					tAttri = TSAttributeList:new{}
					tAttri.ValueMap = {}
				end
				if not tAttriBranchMap then
					tAttriBranchMap = TSAttributeBranchMap:new{}
					tAttriBranchMap.AttriType = attrType
					tAttriBranchMap.BranchList = {}
					table_insert(tAttri.ValueMap, tAttriBranchMap)
				end
				local tValue = TS2Int:new{}
				tValue.Arg0 = branch
				tValue.Arg1 = value
				table_insert(tAttriBranchMap.BranchList, tValue)
			end
		end
	end
	return tAttri
end

function AttributeList:DeSerialize( _tAttribute, ... )
	if not _tAttribute then
		return
	end
	local max = 0
	local allValueList = {}
	self.valueList = allValueList
	for n = 1, #_tAttribute.ValueMap do
		local tAttriBranchMap = _tAttribute.ValueMap[n]
		local attrType = tAttriBranchMap.AttriType
		local attrValueList = {}
		allValueList[attrType] = attrValueList
		max = 0
		for i = 1, #tAttriBranchMap.BranchList do
			local tValue = tAttriBranchMap.BranchList[i]
			local branch = tValue.Arg0
			local value = tValue.Arg1
			attrValueList[branch] = value
			if branch > max then
				max = branch
			end
		end
		for i = 1, max do
			if not attrValueList[i] then
				attrValueList[i] = 0
			end
		end
	end
end

function AttributeList:UpdateAttribute( _attrType, _branch, _value, _add, ... )
	local baseType = _attrType % 100
	if baseType <= AttriType.ALL or baseType >= AttriType.MAX then
		return 0, 0
	end
	local isAdd = _add == nil and true or _add
	local branch = _branch or 1
	branch = branch == 0 and 1 or branch
	local valueList = self.valueList[_attrType]
	if not valueList then
		valueList = {}
		self.valueList[_attrType] = valueList
	end
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
		result = result * (1 + (valueList[i] or 0) * s_PercentScale)
	end
	self.finalValueList[_attrType] = result
	self.dirtyList[_attrType] = false
	return result
end