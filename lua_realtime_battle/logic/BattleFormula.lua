---
--- class BattleFormula
-- @classmod BattleFormula
class('BattleFormula')

---Constructor
function BattleFormula:ctor( ... )
end

function BattleFormula.CalcMagicQuality( _point, ... )
	for i = #Constants.BATTLE_MAGIC_QUALITY_POINT_LIST, 1, -1 do
		if _point >= Constants.BATTLE_MAGIC_QUALITY_POINT_LIST[i] then
			return i - 1
		end
	end
	return 0
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
	[BattleFormulaType.LEVEL] = function( _base, _param, _battleUnit, ... )
		return _base + _param * _battleUnit.gunCount
	end,
	[BattleFormulaType.COOP_MONSTERHP] = function( _base, _param, _battleUnit, ... )
		local wheelCount = ToInt((gBattleLogic.roundNum - 1) / 10) + 1
		local roundStart = (1 + LMath.AccumulateAdd(1, gBattleLogic.roundNum - 1)) * _base
		local roundStepStart = LMath.AccumulateAdd(0, wheelCount - 1) * 10 * _param
		local roundStep = roundStepStart + (gBattleLogic.roundNum % 10) * wheelCount * _param
		return roundStart + (gBattleLogic.waveNum - gBattleLogic.roundStartWaveNum + 1) * roundStep
	end,
	[BattleFormulaType.PK_MONSTERHP] = function( _base, _param, _battleUnit, ... )
		local roundNum = gBattleLogic.roundNum > _param and _param or gBattleLogic.roundNum
		local formulaId = _base + roundNum
		return GetValue(formulaId, _battleUnit)
	end,
	[BattleFormulaType.PK_MONSTERHP_REAL] = function( _base, _param, _battleUnit, ... )
		return _base + _param * (gBattleLogic.waveNum - gBattleLogic.roundStartWaveNum)
	end,
	-- 随机
	[BattleFormulaType.RANDOM] = function( _base, _param, _battleUnit, ... )
		return _base + gBattleRandNum:NextInt(_param)
	end,
	-- 当前SP
	[BattleFormulaType.CURRENTSP] = function( _base, _param, _battleUnit, ... )
		return _base + ToInt(_battleUnit.player.point * _param / Constants.PERCENT_MAX)
	end,
	-- 同怪物攻击次数
	[BattleFormulaType.ATTACKTIMES] = function( _base, _param, _battleUnit, ... )
		return _base + _battleUnit.sameMonsterAttackTimes * _param
	end,
	-- 塔阶数
	[BattleFormulaType.GUN] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return _base + _battleUnit.gunCount * _param
	end,
	-- 目标塔阶数
	[BattleFormulaType.TARGETGUN] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return _base + _targetUnit.gunCount * _param
	end,
	-- 塔阶数+品质
	[BattleFormulaType.GUNQUALITY] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return _base * _battleUnit.gunCount + 0 * _param
	end,
	-- 品质
	[BattleFormulaType.QUALITY] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return _base + 0 * _param
	end,
	-- 怪物数量
	[BattleFormulaType.MONSTERCOUNT] = function( _base, _param, _battleUnit, _targetUnit, ... )
		local monsterCount = _battleUnit.player:GetMonsterCount()
		return ToInt(_base + monsterCount * _param / Constants.PERCENT_MAX)
	end,
	-- 怪物数量+品质
	[BattleFormulaType.MONSTERCOUNTQUALITY] = function( _base, _param, _battleUnit, _targetUnit, ... )
		local monsterCount = _battleUnit.player:GetMonsterCount()
		return ToInt((_base + 0 * _param) * monsterCount / Constants.PERCENT_MAX)
	end,
	-- PK Boss血量
	[BattleFormulaType.PK_BOSSHP] = function( _base, _param, _battleUnit, _targetUnit, ... )
		local baseHp = NilDefault(Constants.BATTLE_PK_BOSS_HP[gBattleLogic.roundNum], Constants.BATTLE_PK_BOSS_HP[#Constants.BATTLE_PK_BOSS_HP])
		local totalMonsterHP = gBattleLogic:GetTotalMonsterHP(_battleUnit.player)
		return baseHp + ToInt(totalMonsterHP * 0.5)
	end,
	-- 怪物血量百分比
	[BattleFormulaType.MONSTERHPPER] = function( _base, _param, _battleUnit, _targetUnit, ... )
		return ToInt(_base + _param * gBattleLogic.monsterHP / Constants.PERCENT_MAX)
	end,
	-- 伤害衰减
	[BattleFormulaType.DAMAGEATTENUATION] = function( _base, _param, _battleUnit, _targetUnit, _index, ... )
		local attenuationFormulaId = _base
		local damage = GetValue(_param, _battleUnit, _targetUnit)
		if _param == 0 then
			damage = _battleUnit:GetAttack()
		end
		return GetValue(attenuationFormulaId, _battleUnit, _targetUnit, _index, damage)
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
		return ToInt(_damage * percent / Constants.PERCENT_MAX)
	end,
	-- 回合+魔法使用次数
	[BattleFormulaType.ROUNDTIMES] = function( _base, _param, _battleUnit, _targetUnit, _index, _damage, ... )
		return gBattleLogic.roundNum * (_base + _param * _battleUnit.player.magicSpellTimes)
	end,
	-- 连接
	[BattleFormulaType.CONNECT] = function( _base, _param, _battleUnit, _targetUnit, _index, _damage, ... )
		if _targetUnit.curConnectCount <= 1 then
			return 0
		end
		return _base + _param * (_targetUnit.curConnectCount - 1)
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