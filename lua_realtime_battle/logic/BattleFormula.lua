---
--- class BattleFormula
-- @classmod BattleFormula
class('BattleFormula')

local math_floor = math.floor
local math_ceil = math.ceil
local LMath_AccumulateAdd = LMath.AccumulateAdd

---Constructor
function BattleFormula:ctor( ... )
end

local FormulaSwitcher = {
	[BattleFormulaType.ALL] = function( _base, _param, _battleUnit, ... )
		return _base
	end,
	[BattleFormulaType.WAVE] = function( _base, _param, _battleUnit, ... )
		return _base + _param * gBattleLogic.waveNum
	end,
	[BattleFormulaType.ROUND] = function( _base, _param, _battleUnit, ... )
		return _base + _param * gBattleLogic.roundNum
	end,
	[BattleFormulaType.COOP_ROUND] = function( _base, _param, _battleUnit, ... )
		return _base + _param * math_ceil((gBattleLogic.roundNum - 0.5) / 10)
	end,
	-- 塔星级
	[BattleFormulaType.STAR] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return GetValue(_base, _battleUnit, _targetUnit) + _battleUnit.star * _param
	end,
	-- 目标塔星级
	[BattleFormulaType.TARGETSTAR] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return GetValue(_base, _battleUnit, _targetUnit) + _targetUnit.star * _param
	end,
	-- 塔战斗阶数
	[BattleFormulaType.TOWERGRADE] = function( _base, _param, _battleUnit, ... )
		return GetValue(_base, _battleUnit) + _param * (_battleUnit:GetGrade() - 1), true
	end,
	-- 塔养成等级
	[BattleFormulaType.TOWERLEVEL] = function( _base, _param, _battleUnit, ... )
		return GetValue(_base, _battleUnit) + _param * _battleUnit:GetLevel()
	end,
	[BattleFormulaType.COOP_BOSSHP] = function( _base, _param, _battleUnit, ... )
		local roundNum = gBattleLogic.roundNum
		local offset = roundNum > _param and roundNum - _param or 0
		local formulaId = _base + roundNum - offset
		return GetValue(formulaId, _battleUnit, nil, offset)
	end,
	[BattleFormulaType.COOP_BOSSHP_REAL] = function( _base, _param, _battleUnit, _targetUnit, _offset, ... )
		return _base + _param * _offset
	end,
	[BattleFormulaType.COOP_MONSTERHP] = function( _base, _param, _battleUnit, ... )
		local roundNum = gBattleLogic.roundNum
		local offset = roundNum > _param and roundNum - _param or 0
		local formulaId = _base + roundNum - offset
		return GetValue(formulaId, _battleUnit, nil, offset)
	end,
	[BattleFormulaType.COOP_MONSTERHP_REAL] = function( _base, _param, _battleUnit, _targetUnit, _offset, ... )
		return _base + _param * (gBattleLogic.waveNum - gBattleLogic.roundStartWaveNum + 1 + _offset * 10)
	end,
	-- PK Boss血量
	[BattleFormulaType.PK_BOSSHP] = function( _base, _param, _battleUnit, _targetUnit, ... )
		local roundNum = gBattleLogic.roundNum
		local offset = roundNum > _param and roundNum - _param or 0
		local formulaId = _base + roundNum - offset
		return GetValue(formulaId, _battleUnit, nil, offset)
	end,
	-- PK Boss血量
	[BattleFormulaType.PK_BOSSHP_REAL] = function( _base, _param, _battleUnit, _targetUnit, _offset, ... )
		local totalMonsterHP = gBattleLogic:GetTotalMonsterHP(_battleUnit.player)
		return _base + _param * _offset + math_floor(totalMonsterHP * 0.5)
	end,
	[BattleFormulaType.PK_MONSTERHP] = function( _base, _param, _battleUnit, ... )
		local roundNum = gBattleLogic.roundNum
		local offset = roundNum > _param and roundNum - _param or 0
		local formulaId = _base + roundNum - offset
		return GetValue(formulaId, _battleUnit, nil, offset)
	end,
	[BattleFormulaType.PK_MONSTERHP_REAL] = function( _base, _param, _battleUnit, _targetUnit, _offset, ... )
		return _base + _param * (gBattleLogic.waveNum - gBattleLogic.roundStartWaveNum + _offset * 8)
	end,
	-- 随机
	[BattleFormulaType.RANDOM] = function( _base, _param, _battleUnit, ... )
		return _base + gBattleRandNum:NextInt(_param)
	end,
	-- 当前SP
	[BattleFormulaType.CURRENTSP] = function( _base, _param, _battleUnit, ... )
		return _base + math_floor(_battleUnit.player.point * _param / Constants.PERCENT_MAX)
	end,
	-- 同怪物攻击次数
	[BattleFormulaType.ATTACKTIMES] = function( _base, _param, _battleUnit, ... )
		local sameMonsterAttackTimes = _battleUnit.paramMap[BattleParamType.SAMEMONSTERATTACKTIMES] or 0
		return _base + sameMonsterAttackTimes * _param
	end,
	-- 怪物数量
	[BattleFormulaType.MONSTERCOUNT] = function( _base, _param, _battleUnit, _targetUnit, ... )
		local monsterCount = _battleUnit.player:GetMonsterCount()
		return math_floor(_base + monsterCount * _param / Constants.PERCENT_MAX)
	end,
	-- 怪物血量百分比
	[BattleFormulaType.MONSTERHPPER] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return math_floor((_base + _param * _targetUnit.maxHP / Constants.PERCENT_MAX) / (_targetUnit.monsterRes.hpScale / Constants.PERCENT_MAX))
	end,
	-- 伤害衰减
	[BattleFormulaType.DAMAGEATTENUATION] = function( _base, _param, _battleUnit, _targetUnit, _index, ... )
		local attenuationFormulaId = _base
		local damage, bindGrade = GetValue(_param, _battleUnit, _targetUnit)
		if _param == 0 then
			damage = _battleUnit:GetAttack()
		end
		return GetValue(attenuationFormulaId, _battleUnit, _targetUnit, _index, damage), bindGrade
	end,
	-- 衰减公式
	[BattleFormulaType.ATTENUATION] = function( _base, _param, _battleUnit, _targetUnit, _index, _damage, ... )
		local limit = _base
		local percent = Constants.PERCENT_MAX + _param * (_index - 1)
		if _param > 0 then
			percent = percent >= limit and limit or percent
		else
			percent = percent <= limit and limit or percent
		end
		return math_floor(_damage * percent / Constants.PERCENT_MAX)
	end,
	-- 连接
	[BattleFormulaType.CONNECT] = function( _base, _param, _battleUnit, _targetUnit, _index, _damage, ... )
		local curConnectCount = _targetUnit.paramMap[BattleParamType.CURCONNECTCOUNT]
		if not curConnectCount or curConnectCount <= 1 then
			return 0
		end
		return (GetValue(_base, _battleUnit, _targetUnit) + GetValue(_param, _battleUnit, _targetUnit)) * (curConnectCount - 1), true
	end
}

function BattleFormula.GetValue( _formulaId, _battleUnit, _targetUnit, _param1, _param2, ... )
	local formulaRes = GameResMgr.GetBattleFormulaRes(_formulaId)
	if not formulaRes then
		return _formulaId
	end
	local formula = FormulaSwitcher[formulaRes.formulaType]
	if not formula then
		return _base
	end
	return formula(formulaRes.base, formulaRes.param, _battleUnit, _targetUnit, _param1, _param2, ...)
end

classend()