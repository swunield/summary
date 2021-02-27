---
--- class BattleMissile
-- @classmod BattleMissile
class('BattleMissile')

local TSMissile = gModel.TSMissile

---Constructor
function BattleMissile.New( _tower, _targetUnitId, _damage, _hitFrame, _effectId, _starIndex, _attackTimes, ... )
	return {
		tower = _tower,
		targetUnitId = _targetUnitId,
		damage = _damage,
		hitFrame = _hitFrame,
		starIndex = _starIndex,
		attackTimes = _attackTimes,
		effectId = _effectId
	}
end

function BattleMissile.Serialize( _missile, ... )
	local tMissille = TSMissile:new{}
	tMissille.TowerUnitId = _missile.tower.unitId
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
	_missile.targetUnitId = _tMissile.TargetUnitId
	_missile.damage = _tMissile.Damage
	_missile.hitFrame = _tMissile.HitFrame
	_missile.starIndex = _tMissile.StarIndex
	_missile.attackTimes = _tMissile.AttackTimes
	_missile.effectId = _tMissile.EffectId

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		_missile.tower = gBattleRecord:GetBattleUnit(_tMissile.TowerUnitId)
	end)
end

classend()