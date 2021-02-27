---
--- class BattleLogic
-- @classmod BattleLogic
class('BattleLogic')

local math_floor = math.floor

---Constructor
function BattleLogic:ctor( _isLocal, ... )
	self.playerList = {}
	self.waveNum = 0			-- 波数
	self.roundNum = 0			-- 回合数
	self.roundStartWaveNum = 0	-- 当前回合起始波数
	self.roundStartTime = 0		-- 当前回合开始时间
	self.roundDuration = 0		-- 当前回合持续时间
	self.battleRes = false 		-- 战斗配置
	self.monsterHP = 0			-- 怪物血量，公式用
	self.isLocal = _isLocal or false -- 是否本地
end

function BattleLogic:Serialize( _tLogic, ... )
	_tLogic.RoundNum = self.roundNum
	_tLogic.WaveNum = self.waveNum
	_tLogic.RoundStartWaveNum = self.roundStartWaveNum
	_tLogic.RoundStartTime = self.roundStartTime
end

function BattleLogic:DeSerialize( _tLogic, ... )
	if not _tLogic then
		return
	end
	self.roundNum = _tLogic.RoundNum
	self.waveNum = _tLogic.WaveNum
	self.roundStartWaveNum = _tLogic.RoundStartWaveNum
	self.roundStartTime = _tLogic.RoundStartTime
end

function BattleLogic:Finalize( ... )
	-- body
end

function BattleLogic:Initialize( _battleType, ... )
	self.battleRes = GameResMgr.GetBattleRes(_battleType)
end

function BattleLogic:Update( _deltaTime, ... )
	-- body
end

function BattleLogic:OnBattleBegin()
	self.playerList = gBattleRecord.playerList
end

function BattleLogic:CheckBattleEnd( ... )
	return false
end

function BattleLogic:OnMonsterLeave( _monster, _leaveFlags, ... )
end

function BattleLogic:GetMonsterResId( _monsterType, _index, ... )
	if _monsterType <= MonsterType.ALL or _monsterType > MonsterType.BOSS then
		return 0
	end
	if _monsterType == MonsterType.BOSS then
		return self.battleRes.bossIdList[_index or 1]
	end
	return self.battleRes.monsterList[_monsterType]
end

function BattleLogic:GetMonsterWaveCount( _monsterType, ... )
	if _monsterType <= MonsterType.ALL or _monsterType >= MonsterType.BOSS then
		return 0
	end
	return self.battleRes.monsterWaveCount[_monsterType]
end

function BattleLogic:GetRoundData( _round, ... )
	local roundList = self.battleRes.roundList
	local round = _round > #roundList and #roundList or _round
	return roundList[round]
end

function BattleLogic:RefreshMonsterHP( ... )
	local monsterId = self:GetMonsterResId(MonsterType.NORMAL)
	local normalMonsterRes = GameResMgr.GetBattleMonsterRes(monsterId)
	local monsterHPScale = normalMonsterRes.hpScale / Constants.PERCENT_MAX
	self.monsterHP = math_floor(BattleFormula.GetValue(normalMonsterRes.hpId) * monsterHPScale)
end

classend()