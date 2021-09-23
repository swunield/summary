---
--- class GBEffect
-- @classmod GBEffect
GBEffect = xclass('GBEffect', GBFrameChasingObject)

local PlayBattleEffect = LUBattleEffect.Play
local FireBattleEffect = LUBattleEffect.Fire
local StopBattleEffect = LUBattleEffect.Stop
local RestartBattleEffect = LUBattleEffect.Restart
local FireBattleEffectEvent = LUBattleEffect.FireEvent

---Constructor
function GBEffect:ctor( _effectId, ... )
	self.effectId = _effectId
	self.effectRes = false					-- 特效配置

	self.gbUnit = false
	self.gbTargetUnit = false

	self.endCallback = false
	self.duration = 0

	self.singleKey = false
end

function GBEffect:Destroy( _stopEffect, ... )
	if _stopEffect and self.effectId ~= 0 then
		StopBattleEffect(self.effectId, true)
	end
	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self.super:Destroy()
end

function GBEffect:Init( _effectRes, _gbUnit, _gbTargetUnit, _duration, _eventName, _endCallback, ... )
	self.effectRes = _effectRes
	if not self.effectRes or self.effectRes.prefabName == 0 then
		return false
	end

	self.gbUnit = _gbUnit
	self.gbTargetUnit = _gbTargetUnit or false
	self.endCallback = _endCallback or false
	self.duration = _duration or BattleConstants.BATTLE_MISSILE_TIME
	
	self:CheckFrameChasing('Init', function( ... )
		if self:InitEffect() then
			if _eventName then
				FireBattleEffectEvent(self.effectId, _eventName)
			end
		end
	end)

	return true
end

local EffectSwitcher = 
{
	-- 投射物
	[EffectType.MISSILE] = function( self, ... )
		return self:InitMissile()
	end,
	-- 单体
	[EffectType.SINGLE] = function( self, ... )
		return self:InitSingle()
	end,
	-- AOE
	[EffectType.AOE] = function( self, ... )
		return self:InitAOE()
	end
}

function GBEffect:InitEffect( ... )
	local switcher = EffectSwitcher[self.effectRes.effectType]
	if switcher then
		return switcher(self)
	end
	return false
end

function GBEffect:InitSingle( ... )
	if not self.gbUnit then
		return
	end
	local parentUnitId = self.effectRes.targetType == EffectTargetType.TARGET and self.gbUnit.unitId or self.gbUnit.gbPlayer.unitId
	local isTop = self.effectRes.zOrderType == EffectZOrderType.TOP
	self.effectId = PlayBattleEffect(self.effectId, self.effectRes.prefabName, GameStringType.EffectPath, parentUnitId, isTop, self.gbUnit.unitId)

	if self.effectRes.targetType == EffectTargetType.TARGET then
		self.singleKey = self.gbUnit.unitId .. '-' .. self.effectRes.id
	end

	return true
end

function GBEffect:InitAOE( ... )
	return true
end

function GBEffect:InitMissile( ... )
	if self.effectRes.targetType == EffectTargetType.TARGET then
		if not self.gbTargetUnit then
			return false
		end
		self.effectId = FireBattleEffect(self.effectId, self.effectRes.prefabName, GameStringType.EffectPath, self.gbUnit.gbPlayer.unitId, true, 
			self.gbUnit.unitId, self.gbTargetUnit.unitId, self.duration - Constants.BATTLE_FRAME_TIME, 0)
	else

	end
	return true
end

function GBEffect:Restart( ... )
	if not self.effectId == 0 then
		return
	end
	RestartBattleEffect(self.effectId)
end

function GBEffect:OnEffectEnd( _isHit, ... )
	if self.endCallback then
		self.endCallback(_isHit, self)
	end
	gGBField:RemoveGBEffect(self.effectId)
end