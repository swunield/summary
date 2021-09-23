---
--- class BattleMissile
-- @classmod BattleMissile
BattleMissile = xclass('BattleMissile')

local TSMissile = gModel.TSMissile

MissilePool = {}
MissileFreeCount = 0

---Constructor
function BattleMissile.New( _towerUnitId, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes, ... )
	if MissileFreeCount > 0 then
		local missile = MissilePool[MissileFreeCount]
		MissilePool[MissileFreeCount] = nil
		MissileFreeCount = MissileFreeCount - 1

		missile.towerUnitId = _towerUnitId
		missile.targetUnitId = _targetUnitId
		missile.damage = _damage
		missile.hitFrame = _hitFrame
		missile.starIndex = _starIndex
		missile.attackTimes = _attackTimes
		missile.effectId = _effectId
		return missile
	end
	return {
		towerUnitId = _towerUnitId,
		targetUnitId = _targetUnitId,
		damage = _damage,
		hitFrame = _hitFrame,
		starIndex = _starIndex,
		attackTimes = _attackTimes,
		effectId = _effectId
	}
end

function BattleMissile.Destroy( _missile )
	MissileFreeCount = MissileFreeCount + 1
	MissilePool[MissileFreeCount] = _missile
end

function BattleMissile.Serialize( _missile, ... )
	local tMissille = TSMissile:new{}
	tMissille.TowerUnitId = _missile.towerUnitId
	tMissille.TargetUnitId = _missile.targetUnitId
	tMissille.Damage = _missile.damage
	tMissille.HitFrame = _missile.hitFrame
	tMissille.StarIndex = _missile.starIndex
	tMissille.AttackTimes = _missile.attackTimes
	tMissille.EffectId = _missile.effectId
	return tMissille
end

function BattleMissile.DeSerialize( _missile, _tMissile, ... )
	if not _tMissile then
		return
	end
	_missile.towerUnitId = _tMissile.TowerUnitId
	_missile.targetUnitId = _tMissile.TargetUnitId
	_missile.damage = _tMissile.Damage
	_missile.hitFrame = _tMissile.HitFrame
	_missile.starIndex = _tMissile.StarIndex
	_missile.attackTimes = _tMissile.AttackTimes
	_missile.effectId = _tMissile.EffectId
end