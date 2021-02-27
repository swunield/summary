---
--- class GBUnit
-- @classmod GBUnit
class('GBUnit', GBFrameChasingObject)

---Constructor
function GBUnit:ctor( ... )
	self.super = Super()

	self.gameObject = false 				-- 单位物件
	self.transform = false 					-- 单位Transform
	self.uBattleUnit = false				-- 单位组件
	self.gbPlayer = false 					-- 玩家
	self.gbUnit = false 					-- GBUnit
	self.battleUnit = false					-- BattleUnit，逻辑单位

	self.bufferMap = {}						-- 状态特效
	self.damageMap = false
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

	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
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
			if addBufferEvent and addBufferEvent ~= '' then
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
		if removeBufferEvent and removeBufferEvent ~= '' then
			self:FireUnitEvent(removeBufferEvent)
		end
	end
end

function GBUnit:FireUnitEvent( _eventName, ... )
	if self.uBattleUnit then
		self.uBattleUnit:FireUnitEvent(_eventName)
	end
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

classend()