---
--- class BattleTriggerParam
-- @classmod BattleTriggerParam
class('BattleTriggerParam')

---Constructor
function BattleTriggerParam:ctor( _triggerUnit, _attackerUnit, _targetUnits, _triggerValue, _triggerFrame, _isLogic, _randNum, ... )
	self.triggerUnit = _triggerUnit or false
	self.attackerUnit = _attackerUnit or false
	self.targetUnits = _targetUnits or {}
	self.triggerValue = _triggerValue or '0'
	self.triggerFrame = _triggerFrame or false
	self.isLogic = _isLogic == nil and true or _isLogic
	self.randNum = _randNum or false
	self.extraDamage = 0
end

function BattleTriggerParam.New( _triggerUnit, _attackerUnit, _targetUnits, _triggerValue, _triggerFrame, _isLogic, _randNum, ... )
	return {
		triggerUnit = _triggerUnit or false,
		attackerUnit = _attackerUnit or false,
		targetUnits = _targetUnits or {},
		triggerValue = _triggerValue or '0',
		triggerFrame = _triggerFrame or false,
		isLogic = _isLogic == nil and true or _isLogic,
		randNum = _randNum or false,
		extraDamage = 0
	}
end

classend()