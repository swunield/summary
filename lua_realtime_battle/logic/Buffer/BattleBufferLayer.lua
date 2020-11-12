---
--- class BattleBufferLayer
-- @classmod BattleBufferLayer
class('BattleBufferLayer')

---Constructor
function BattleBufferLayer:ctor( _time, _ownerUnit, ... )
	self.time = NilDefault(_time, false) 					-- 添加时间
	self.valueList = false									-- 数值列表
	self.ownerUnit = NilDefault(_ownerUnit, false) 			-- 所有者单位
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