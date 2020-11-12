---
--- class BattleLogic
-- @classmod BattleLogic
class('BattleLogic')

---Constructor
function BattleLogic:ctor( ... )
	self.playerList = {}
	self.waveNum = 0			-- 波数
	self.roundNum = 0			-- 回合数
	self.roundStartWaveNum = 0	-- 当前回合起始波数
	self.roundStartTime = 0		-- 当前回合开始时间
	self.roundDuration = 0		-- 当前回合持续时间
	self.battleRes = false 		-- 战斗配置
	self.monsterHP = 0			-- 怪物血量，公式用
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

function BattleLogic:OnMonsterDie( _monster, ... )
	if not _monster or not _monster:HasUnitFlag(BattleUnitFlag.DEATH) then
		return false
	end
	return true
end

function BattleLogic:GetMonsterResId( _monsterType, ... )
	if _monsterType <= MonsterType.ALL or _monsterType > MonsterType.BOSS then
		return 0
	end
	if _monsterType == MonsterType.BOSS then
		return self.battleRes.bossIdList[1]
	end
	return self.battleRes.monsterList[_monsterType]
end

function BattleLogic:GetMonsterHPScale( _monsterType, ... )
	if _monsterType <= MonsterType.ALL or _monsterType >= MonsterType.BOSS then
		return 100
	end
	return self.battleRes.monsterHPScaleList[_monsterType]
end

function BattleLogic:GetMonsterWaveCount( _monsterType, ... )
	if _monsterType <= MonsterType.ALL or _monsterType >= MonsterType.BOSS then
		return 0
	end
	return self.battleRes.monsterWaveCount[_monsterType]
end

function BattleLogic:GetRoundData( _round, ... )
	local round = _round > #self.battleRes.roundList and #self.battleRes.roundList or _round
	return self.battleRes.roundList[round]
end

function BattleLogic:OnMagicSpell( _player, _magicData, ... )
end

classend()