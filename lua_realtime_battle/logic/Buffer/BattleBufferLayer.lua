---
--- class BattleBufferLayer
-- @classmod BattleBufferLayer
class('BattleBufferLayer')

local table_insert = table.insert
local TSBufferLayerValue = gModel.TSBufferLayerValue
local TSBufferLayer = gModel.TSBufferLayer

---Constructor
function BattleBufferLayer:ctor( _buffer, _time, _owner, _bindGrade, ... )
	self.buffer = _buffer
	self.time = _time or false 										-- 添加时间
	self.valueList = false											-- 数值列表
	self.owner = _owner or {} 										-- 所有者，{ unitId, player }
	self.bindGrade = _bindGrade or false							-- 绑定升阶
end

function BattleBufferLayer:Serialize( ... )
	local tLayer = TSBufferLayer:new{}
	tLayer.StartTime = self.time
	tLayer.OwnerId = self.owner.unitId
	for i = 1, #self.valueList do
		local value = self.valueList[i]
		if value.value ~= 0 then
			if not tLayer.ValueList then
				tLayer.ValueList = {}
			end
			local tValue = TSBufferLayerValue:new{}
			tValue.Type = value.type
			tValue.Value = value.value
			tValue.Branch = value.branch
			tValue.BindGrade = value.bindGrade and 1 or nil
			table_insert(tLayer.ValueList, tValue)
		end
	end
	return tLayer
end

function BattleBufferLayer:DeSerialize( _tLayer, ... )
	if not _tLayer then
		return
	end
	self.time = _tLayer.StartTime
	self.owner.unitId = _tLayer.OwnerId
	self.valueList = {}
	self.bindGrade = false
	if _tLayer.ValueList then
		for i = 1, #_tLayer.ValueList do
			local tValue = _tLayer.ValueList[i]
			local bindGrade = tValue.BindGrade == 1
			local value = { type = tValue.Type, branch = tValue.Branch, value = tValue.Value, bindGrade = bindGrade }
			table.insert(self.valueList, value)
			if bindGrade then
				self.bindGrade = true
			end
		end
	end
end

function BattleBufferLayer:IsTargetBetter( _targetValueList )
	for i = 1, #self.valueList do
		local value = math.abs(self.valueList[i].value)
		local targetValue = math.abs(_targetValueList[i] and _targetValueList[i].value or 0)
		if targetValue > value then
			return true
		end
	end
	return false
end

classend()