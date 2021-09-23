---
--- class GBUnit
-- @classmod GBUnit
GBUnit = xclass('GBUnit', GBFrameChasingObject)

local os_clock = os.time

local FireBattleUnitEvent = LUBattleUnit.FireUnitEvent

---Constructor
function GBUnit:ctor( ... )
	self.gbPlayer = false 					-- 玩家
	self.gbUnit = false 					-- GBUnit
	self.battleUnit = false					-- BattleUnit，逻辑单位

	self.bufferMap = {}						-- 状态特效
	self.damageMap = false
	self.unitId = 0
	self.unitFlagMap = {}					-- 单位标记
end

function GBUnit:Init( ... )
	-- body
end

function GBUnit:Destroy( ... )
	-- 状态特效
	for effectResId, bufferInfo in pairs(self.bufferMap) do
		if bufferInfo.effectId ~= 0 then
			gGBField:RemoveGBEffect(bufferInfo.effectId, true)
		end
	end

	-- 清除标记
	for unitFlag, value in pairs(self.unitFlagMap) do
		if value == 1 then
			self.gbUnit:OnUnitFlagChange(unitFlag, false)
		end
	end

	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self.super:Destroy()
end

function GBUnit:OnBufferChange( _isAdd, _bufferRes, ... )
	if not _bufferRes then
		return
	end
	local bufferResId = _bufferRes.id
	local effectResId = self.battleUnit.unitType == BattleUnitType.GRID and _bufferRes.gridEffectId or _bufferRes.effectId
	local eventNameList = _bufferRes.eventNameList
	if effectResId == 0 and #eventNameList == 0 then
		return
	end
	local bufferInfo = self.bufferMap[bufferResId]
	if _isAdd then
		-- 添加特效
		if not bufferInfo then
			bufferInfo = { effectId = 0, count = 0 }
			self.bufferMap[bufferResId] = bufferInfo
		end
		if bufferInfo.count == 0 then
			if effectResId ~= 0 then
				local gbEffect = gGBField:AddGBEffect(nil, self.gbPlayer, effectResId, self.gbUnit)
				if gbEffect then
					bufferInfo.effectId = gbEffect.effectId
				end
			end
			local addBufferEvent = eventNameList[1]
			if addBufferEvent and addBufferEvent ~= 0 then
				self:FireUnitEvent(addBufferEvent)
			end
		end
		bufferInfo.count = bufferInfo.count + 1
		return
	end
	-- 移除特效
	if not bufferInfo or bufferInfo.count == 0 then
		return
	end
	bufferInfo.count = bufferInfo.count - 1
	if bufferInfo.count == 0 then
		if bufferInfo.effectId ~= 0 then
			gGBField:RemoveGBEffect(bufferInfo.effectId, true)
			bufferInfo.effectId = 0
		end
		local removeBufferEvent = eventNameList[2]
		if removeBufferEvent and removeBufferEvent ~= 0 then
			self:FireUnitEvent(removeBufferEvent)
		end
	end
end

-- 状态变化
local UnitFlagChangeSwitcher = 
{
}

function GBUnit:OnUnitFlagChange( _unitFlag, _isAdd )
	local switcher = UnitFlagChangeSwitcher[_unitFlag]
	if switcher and switcher(self, _isAdd) then
		if _isAdd then
			self.unitFlagMap[_unitFlag] = 1
		else
			self.unitFlagMap[_unitFlag] = nil
		end
	end
end

function GBUnit:CheckAllUnitFlag( ... )
	for unitFlag, value in pairs(self.unitFlagMap) do
		if value <= 0 then
			self.gbUnit:OnUnitFlagChange(unitFlag, value == -1)
		end
	end
end

local UnitEventSwitcher = {
	[GameStringType.SZPoint] = function( self, _eventName, _eventParam, _isReconnect )
		if not _eventParam then
			return
		end
		local bufferResId = tonumber(_eventParam.value)
		local buffer = self.battleUnit:GetBufferByResId(bufferResId)
		local point = buffer and #buffer.layerList or 0
		local eventName = _eventName + 1 + point
		if not _isReconnect and point == 0 then
			eventName = _eventName
		end
		FireBattleUnitEvent(self.unitId, eventName)
	end
}

function GBUnit:FireUnitEvent( _eventName, _eventParam, _isReconnect, ... )
	if self.unitId ~= 0 then
		local switcher = UnitEventSwitcher[_eventName]
		if switcher then
			switcher(self, _eventName, _eventParam, _isReconnect)
		else
			FireBattleUnitEvent(self.unitId, _eventName)
		end
		return true
	end
	return false
end

function GBUnit:ShowDamage( _gbUnit, _damage, _damageType, ... )
	if _damage and _damageType then
		self.gbPlayer:ShowDamage(self, _damage, _damageType)
	end
end

function GBUnit:HasSameDamage( _damage, _damageType, ... )
	local key = _damage .. '_' .. _damageType .. '_' .. gamebattle.gBattleFrameCount
	if not self.damageMap then
		self.damageMap = {}
	end
	if self.damageMap[key] then
		return true
	end
	self.damageMap[key] = 1
	return false
end