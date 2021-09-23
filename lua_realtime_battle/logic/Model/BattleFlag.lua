---
--- class BattleFlag
-- @classmod BattleFlag
-- 标记类
BattleFlag = xclass('BattleFlag')

local table_insert = table.insert

local TSFlag = gModel.TSFlag
local TS2Int = gModel.TS2Int

function BattleFlag.New()
	return {}
end
NewBattleFlag = BattleFlag.New

function BattleFlag.Serialize( _flag, ... )
	local tFlag = nil
	for flag, value in pairs(_flag) do
		if value ~= 0 then
			if not tFlag then
				tFlag = TSFlag:new{}
				tFlag.FlagList = {}
			end
			local tValue = TS2Int:new{}
			tValue.Arg0 = flag
			tValue.Arg1 = value
			table_insert(tFlag.FlagList, tValue)
		end
	end
	return tFlag
end
SerializeBattleFlag = BattleFlag.Serialize

function BattleFlag.DeSerialize( _flag, _tFlag, ... )
	if not _tFlag then
		return
	end
	for i = 1, #_tFlag.FlagList do
		local tValue = _tFlag.FlagList[i]
		_flag[tValue.Arg0] = tValue.Arg1
	end
end
DeSerializeBattleFlag = BattleFlag.DeSerialize

function BattleFlag.AddFlag( _flag, _type, _value, ... )
	local value = _value or 1
	local oldValue = _flag[_type]
	if not oldValue then
		_flag[_type] = value
		return true
	end
	_flag[_type] = value + oldValue
	return oldValue == 0
end
AddBattleFlag = BattleFlag.AddFlag

function BattleFlag.ClearFlag( _flag, _type, _value, ... )
	local oldValue = _flag[_type]
	if not oldValue then
		return false
	end
	if _value then
		local newValue = oldValue - _value
		_flag[_type] = newValue
		return newValue == 0 and oldValue ~= 0
	end
	_flag[_type] = 0
	return oldValue ~= 0
end
ClearBattleFlag = BattleFlag.ClearFlag

-- 是否有标记
function BattleFlag.HasFlag( _flag, _type )
	local value = _flag[_type]
	return value and value ~= 0
end
HasBattleFlag = BattleFlag.HasFlag

-- 标记数值
function BattleFlag.GetFlagValue( _flag, _type, ... )
	return _flag[_type] or 0
end
GetBattleFlagValue = BattleFlag.GetFlagValue