---
--- class BattleTriggerParam
-- @classmod BattleTriggerParam
BattleTriggerParam = xclass('BattleTriggerParam')

local EmptyTable = {}

TriggerParamPool = {}
ParamFreeCount = 0

function BattleTriggerParam.New( _triggerUnit, _attackerUnit, _targetUnits, _triggerValue, _triggerFrame, _isLogic, _randNum, ... )
	if ParamFreeCount > 0 then
		local param = TriggerParamPool[ParamFreeCount]
		TriggerParamPool[ParamFreeCount] = nil
		ParamFreeCount = ParamFreeCount - 1

		param.triggerUnit = _triggerUnit or false
		param.attackerUnit = _attackerUnit or false
		param.targetUnits = _targetUnits or EmptyTable
		param.triggerValue = _triggerValue or '0'
		param.triggerFrame = _triggerFrame or false
		param.isLogic = _isLogic == nil and true or _isLogic
		param.randNum = _randNum or false
		param.extraDamage = 0
		param.extraStar = 0
		return param
	end
	return {
		triggerUnit = _triggerUnit or false,
		attackerUnit = _attackerUnit or false,
		targetUnits = _targetUnits or EmptyTable,
		triggerValue = _triggerValue or '0',
		triggerFrame = _triggerFrame or false,
		isLogic = _isLogic == nil and true or _isLogic,
		randNum = _randNum or false,
		extraDamage = 0,
		extraStar = 0,
	}
end

function BattleTriggerParam.Destroy( _triggerParam )
	ParamFreeCount = ParamFreeCount + 1
	TriggerParamPool[ParamFreeCount] = _triggerParam
end