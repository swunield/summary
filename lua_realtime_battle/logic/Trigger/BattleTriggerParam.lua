---
--- class BattleTriggerParam
-- @classmod BattleTriggerParam
class('BattleTriggerParam')

---Constructor
function BattleTriggerParam:ctor( _triggerUnit, _attackerUnit, _targetUnits, _triggerValue, _triggerFrame, _isLogic, _randNum, ...)
	self.triggerUnit = NilDefault(_triggerUnit, false)
	self.attackerUnit = NilDefault(_attackerUnit, false)
	self.targetUnits = NilDefault(_targetUnits, {})
	self.triggerValue = tostring(NilDefault(_triggerValue, '0'))
	self.triggerFrame = NilDefault(_triggerFrame, false)
	self.isLogic = NilDefault(_isLogic, true)
	self.randNum = NilDefault(_randNum, false)
	self.extraDamage = 0
end

classend()