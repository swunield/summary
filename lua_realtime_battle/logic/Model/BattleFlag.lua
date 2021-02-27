---
--- class BattleFlag
-- @classmod BattleFlag
-- 标记类
class('BattleFlag')

local TSFlag = gModel.TSFlag

---Constructor
function BattleFlag:ctor( ... )
	self.flagList = {}
end

function BattleFlag:Serialize( ... )
	local tFlag = nil
	for flag, value in pairs(self.flagList) do
		if value ~= 0 then
			if not tFlag then
				tFlag = TSFlag:new{}
				tFlag.FlagMap = {}
			end 
			tFlag.FlagMap[flag] = value
		end
	end
	return tFlag
end

function BattleFlag:DeSerialize( _tFlag, ... )
	if not _tFlag then
		return
	end
	self.flagList = {}
	for flag, value in pairs(_tFlag.FlagMap) do
		self.flagList[flag] = value
	end
end

-- 添加标记
function BattleFlag:AddFlag( _flag, _value, ... )
	local value = _value or 1
	if not self.flagList[_flag] then
		self.flagList[_flag] = value
	else
		self.flagList[_flag] = value + self.flagList[_flag]
	end
end

-- 移除标记
function BattleFlag:ClearFlag( _flag, ... )
	self.flagList[_flag] = 0
end

-- 是否有标记
function BattleFlag:HasFlag( _flag )
	return self.flagList[_flag] and self.flagList[_flag] ~= 0
end

-- 标记数值
function BattleFlag:GetFlagValue( _flag, ... )
	return self.flagList[_flag] or 0
end

-- 统计拥有标记数量
function BattleFlag:StatFlagCount( ... )
	local flags = { ... }
	local statCount = 0
	local flagCount = #flags
	for i = 1, flagCount do
		if self:HasFlag(flags[i]) then
			statCount = statCount + 1
		end
	end 
	return statCount
end

classend()
export('BattleFlag', BattleFlag)