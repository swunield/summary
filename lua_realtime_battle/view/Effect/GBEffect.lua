---
--- class GBEffect
-- @classmod GBEffect
class('GBEffect')

---Constructor
function GBEffect:ctor( _effectId, ... )
	self.gameObject = false
	self.transform = false

	self.effectId = _effectId
	self.effectRes = false					-- 特效配置
	self.objName = false					-- 特效名字
	self.poolName = false 					-- 特效物件池名字

	self.gbUnit = false
	self.gbTargetUnit = false

	self.endCallback = false
end

function GBEffect:Destroy( ... )
	if self.gameObject then
		if self.effectRes.effectType == EffectType.MISSILE then
			UIUtils.SelectActionSelector(self.gameObject, 'Fade')
		else
			GameObjectPool.ReleaseObject(self.gameObject)
		end
	end
	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBEffect:Init( _effectRes, _gbUnit, _gbTargetUnit, _endCallback, ... )
	self.effectRes = _effectRes
	if not self.effectRes then
		return false
	end

	self.gbUnit = _gbUnit
	if self.effectRes.effectType == EffectType.AOE then
		self.objName = string.format('Effect-%d-%d-%s-AOE', _effectRes.id, self.effectId, _gbUnit.unit.unitId)
	else
		self.gbTargetUnit = _gbTargetUnit
		if not self.gbTargetUnit then
			return false
		end
		self.objName = string.format('Effect-%d-%d-%s-%s', _effectRes.id, self.effectId, _gbUnit.unit.unitId, _gbTargetUnit.unit.unitId)
	end

	self.poolName = self:GetPoolName()
	self.gameObject = GameObjectPool.INSTANCE:Request(self.poolName, true).gameObject
	self.gameObject.name = self.objName
	self.transform = self.gameObject.transform
	self.endCallback = _endCallback

	self:InitEffect()
	return true
end

function GBEffect:GetPoolName( ... )
	if not self.effectRes then
		return 'battle/battle_effect'
	end
	local effectType = self.effectRes.effectType
	if effectType == EffectType.MISSILE then
		return 'battle/battle_missile'
	end
	return 'battle/battle_effect'
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

function GBEffect:InitMissile( ... )
	local uBattleMissile = self.gameObject:GetComponent(UBattleMissile)
	if not uBattleMissile then
		return false
	end
	UIUtils.SetObjectParent(self.gameObject, self.gbUnit.gbPlayer.objTop)
	if self.effectRes.targetType == EffectTargetType.TARGET then
		if not self.gbTargetUnit then
			return false
		end
		uBattleMissile:Fire(self.gbUnit.gameObject, self.gbTargetUnit.uBattleUnit, gGBField.looper, BattleConstants.BATTLE_MISSILE_TIME, nil, function( _isHit, ... )
			if self.endCallback then
				self.endCallback(_isHit, self)
			end
			gGBField:RemoveGBEffect(self.effectId)
		end)
	else

	end
	return true
end

classend()