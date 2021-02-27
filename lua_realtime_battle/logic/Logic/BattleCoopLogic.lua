---
--- class BattleCoopLogic
-- @classmod BattleCoopLogic
class('BattleCoopLogic', BattleLogic)

local table_insert = table.insert
local math_floor = math.floor
local math_ceil = math.ceil

local TSLogic = gModel.TSLogic
local TSPendingMonster = gModel.TSPendingMonster

---Constructor
function BattleCoopLogic:ctor( _isLocal, ... )
	self.super = Super(_isLocal, ...)
	self.isBossPeriod = false			-- 是否Boss阶段
	self.leftWaveNum = 0				-- 回合剩余波数
	self.isBattleEnd = false			-- 是否战斗结束

	self.roundList = {}					-- 回合数据
end

function BattleCoopLogic:Serialize( ... )
	local tLogic = TSLogic:new{}
	self.super:Serialize(tLogic)
	tLogic.BossPeriod = self.isBossPeriod and 1 or nil
	tLogic.LeftWaveNum = self.leftWaveNum ~= 0 and self.leftWaveNum or nil 
	return tLogic
end

function BattleCoopLogic:DeSerialize( _tLogic, ... )
	if not _tLogic then
		return
	end
	self.super:DeSerialize(_tLogic)
	self.isBossPeriod = _tLogic.BossPeriod == 1
	self.leftWaveNum = _tLogic.LeftWaveNum or 0

	self:RefreshMonsterHP()
	self:GenerateMonster(self.leftWaveNum)

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知客户端回合开始
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, 0, self.roundNum)
	end)
end

function BattleCoopLogic:Initialize( _battleType, ... )
	self.super:Initialize(_battleType)

	-- 怪物路径
	BattleConstants.BATTLE_ROAD_LENGTH = BattleConstants.BATTLE_COOP_ROAD_LENGTH
	BattleConstants.BATTLE_ROAD_UNIT_LENGTH = BattleConstants.BATTLE_COOP_ROAD_UNIT_LENGTH

	-- 距离数值表
	Global.BattleMonsterDistance = {}
	for gridIndex, distanceList in pairs(BattleCoopDistance) do
		local monsterDistanceList = {}
		BattleMonsterDistance[gridIndex] = monsterDistanceList
		for i = 1, #distanceList do
			table_insert(monsterDistanceList, math_ceil(distanceList[i] / Constants.BATTLE_FRAME_TIME))
		end
	end

	-- 初始化回合数据
	self:InitRound()
end

function BattleCoopLogic:Update( _deltaTime, ... )
end

function BattleCoopLogic:InitRound( ... )
	local bossRoundList = self.battleRes.bossRound
	local maxRound = bossRoundList[#bossRoundList]
	for i = 1, #bossRoundList do
		local preBossRound = i == 1 and 0 or bossRoundList[i - 1]
		local curBossRound = bossRoundList[i]
		if curBossRound - preBossRound > 1 then
			local specialRound = math_ceil((curBossRound + preBossRound) / 2)
			self.roundList[specialRound] = { roundType = BattleCoopRoundType.SPECIAL, monsterOrderList = self.battleRes.specialMonsterOrderList }
		end
		self.roundList[curBossRound] = { roundType = BattleCoopRoundType.BOSS, bossId = self.battleRes.bossIdList[((i - 1) % #self.battleRes.bossIdList) + 1] }
	end
	for i = 1, maxRound do
		local round = self.roundList[i]
		if not round then
			round = { roundType = BattleCoopRoundType.NORMAL, monsterOrderList = self.battleRes.normalMonsterOrderList }
			self.roundList[i] = round
		end
	end
end

function BattleCoopLogic:OnBattleBegin( ... )
	self.super:OnBattleBegin()

	self.roundNum = 0
	self.waveNum = 0
	self:OnNextRoundStart()
end

-- 下一回合开始
function BattleCoopLogic:OnNextRoundStart( ... )
	self.isBossPeriod = false
	self.roundNum = self.roundNum + 1
	self.roundStartWaveNum = self.waveNum + 1
	self.roundStartTime = gBattleTime
	self:GenerateMonster()

	-- gBattleManager:AddBattleLog(string.format('RoundStart Round[%d] Frame[%d]', self.roundNum, gBattleFrameCount))
	-- warn('OnNextRoundStart', gBattleFrameCount, self.roundNum, self.roundStartWaveNum, self.roundStartTime)
	-- 通知客户端回合开始
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, 0, self.roundNum)
end

-- 校验战斗是否结束
function BattleCoopLogic:CheckBattleEnd( ... )
	return self.isBattleEnd
end

function BattleCoopLogic:GenerateMonster( _leftWaveNum, ... )
	gBattleTimer:StopTask('GenerateMonster')

	local index = self.roundNum > #self.roundList and #self.roundList or self.roundNum
	local round = self.roundList[index]
	if round.roundType ~= BattleCoopRoundType.BOSS then
		-- 普通出怪
		self.leftWaveNum = _leftWaveNum or #round.monsterOrderList
		gBattleTimer:RunTask('GenerateMonster', 200, 1000, #round.monsterOrderList, false, function( _index, ... )
			self.waveNum = _index + self.roundStartWaveNum - 1
			self.leftWaveNum = self.leftWaveNum - 1
			-- warn('GenerateMonster', gBattleFrameCount, self.waveNum, _index, self.leftWaveNum, self.roundNum, self.roundStartWaveNum)
			local monsterType = round.monsterOrderList[_index]
			local monsterId = self:GetMonsterResId(monsterType)

			-- 双方各出一个怪物
			for i = 1, #self.playerList do
				self.playerList[i]:AddMonster(monsterId)
			end

			-- 普通怪物血量
			self:RefreshMonsterHP()
		end)
	else
		-- Boss
		self.leftWaveNum = _leftWaveNum or 1
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PERIOD, 'OnBossEnter', round.bossId)
		gBattleTimer:RunTask('GenerateMonster', 1200, 0, 0, function( ... )
			self.isBossPeriod = true
			self.waveNum = self.roundStartWaveNum
			self.leftWaveNum = 0
			-- warn('GenerateMonster', self.waveNum, self.leftWaveNum, gBattleFrameCount)
			local monsterId = round.bossId

			-- 双方各出一个怪物
			for i = 1, #self.playerList do
				self.playerList[i]:AddMonster(monsterId)
			end

			-- 普通怪物血量
			self:RefreshMonsterHP()
		end, false)
	end
end

function BattleCoopLogic:OnMonsterLeave( _monster, _leaveFlags, ... )
	local needPoint = _leaveFlags[BattleUnitLeaveType.DIE] == 1
	if needPoint then
		local point = _monster:GetPoint()
		for i = 1, #self.playerList do
			self.playerList[i]:AddPoint(point)
		end
	end
	-- 漏怪，战斗结束
	if _leaveFlags[BattleUnitLeaveType.END] == 1 and not self.isLocal then
		gBattleResult:SetRoundNum(self.roundNum)
		self.isBattleEnd = true
	end
	-- 回合判定
	if self.leftWaveNum ~= 0 then
		return
	end
	for i = 1, #self.playerList do
		if self.playerList[i]:GetMonsterCount() ~= 0 then
			return
		end
	end
	-- 怪物全部死亡，下一阶段
	self:OnNextRoundStart()
end

classend()