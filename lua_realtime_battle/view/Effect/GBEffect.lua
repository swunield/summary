---
--- class GBEffect
-- @classmod GBEffect
class('GBEffect', GBFrameChasingObject)

---Constructor
function GBEffect:ctor( _effectId, ... )
	self.super = Super()

	self.gameObject = false
	self.transform = false
	self.uEffect = false

	self.effectId = _effectId
	self.effectRes = false					-- 特效配置

	self.gbUnit = false
	self.gbTargetUnit = false

	self.endCallback = false
	self.duration = 0

	self.singleKey = false
end

function GBEffect:Destroy( _stopEffect, ... )
	if _stopEffect and self.uEffect then
		self.uEffect:Stop(true)
	end
	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBEffect:Init( _effectRes, _gbUnit, _gbTargetUnit, _duration, _endCallback, ... )
	self.effectRes = _effectRes
	if not self.effectRes or self.effectRes.prefabName == '' then
		return false
	end

	self.gbUnit = _gbUnit
	self.gbTargetUnit = _gbTargetUnit or false
	self.endCallback = _endCallback or false
	self.duration = _duration or BattleConstants.BATTLE_MISSILE_TIME
	
	self:CheckFrameChasing('Init', function( ... )
		self.gameObject = GameObjectPool.INSTANCE:Request(self.effectRes.prefabName, 'animation/other/prefabs/tower/', true).gameObject
		self.transform = self.gameObject.transform
		self.uEffect = self.gameObject:GetComponent(UBattleEffect)
		self:InitEffect()
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
	if not self.uEffect then
		return false
	end
	self.gameObject.name = string.format('Single-%d-%d-[%s]', self.effectRes.id, self.effectId, self.gbUnit.battleUnit.unitId)
	local uBattleUnit = self.effectRes.targetType == EffectTargetType.TARGET and self.gbUnit.uBattleUnit or self.gbUnit.gbPlayer.uBattleUnit
	local objLayer = self.effectRes.zOrderType == EffectZOrderType.TOP and uBattleUnit.objTop or uBattleUnit.objBottom
	UIUtils.SetObjectParent(self.gameObject, objLayer)
	self.uEffect:Play(self.gbUnit.uBattleUnit, function( _isHit, ... )
		if self.endCallback then
			self.endCallback(_isHit, self)
		end
		gGBField:RemoveGBEffect(self.effectId)
	end)

	if self.effectRes.targetType == EffectTargetType.TARGET then
		self.singleKey = self.gbUnit.battleUnit.unitId .. '-' .. self.effectRes.id
	end

	return true
end

function GBEffect:InitAOE( ... )
	if not self.uEffect then
		return false
	end
	self.gameObject.name = string.format('AOE-%d-%d', self.effectRes.id, self.effectId)

	return true
end

function GBEffect:InitMissile( ... )
	if not self.uEffect then
		return false
	end
	UIUtils.SetObjectParent(self.gameObject, self.gbUnit.gbPlayer.objTop)
	if self.effectRes.targetType == EffectTargetType.TARGET then
		if not self.gbTargetUnit then
			return false
		end
		self.gameObject.name = string.format('Missile-%d-%d-[%s]-[%s]', self.effectRes.id, self.effectId, self.gbUnit.battleUnit.unitId, self.gbTargetUnit.battleUnit.unitId)
		self.uEffect:Fire(self.gbUnit.uBattleUnit, self.gbTargetUnit.uBattleUnit, gGBField.looper, self.duration - Constants.BATTLE_FRAME_TIME, nil, function( _isHit, ... )
			if self.endCallback then
				self.endCallback(_isHit, self)
			end
			gGBField:RemoveGBEffect(self.effectId)
		end)
	else

	end
	return true
end

function GBEffect:Restart( ... )
	if not self.uEffect then
		return
	end
	self.uEffect:Restart()
end

classend()