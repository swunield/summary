---
--- class BattleCoopLogic
-- @classmod BattleCoopLogic
BattleCoopLogic = xclass('BattleCoopLogic', BattleLogic)

local table_insert = table.insert
local math_floor = math.floor
local math_ceil = math.ceil

local TSLogic = gModel.TSLogic
local TSPendingMonster = gModel.TSPendingMonster

---Constructor
function BattleCoopLogic:ctor( _isLocal, ... )
	self.super.isLocal = _isLocal or false 	-- 是否本地
	self.isBossPeriod = false			-- 是否Boss阶段
	self.leftWaveNum = 0				-- 回合剩余波数
	self.isBattleEnd = false			-- 是否战斗结束

	self.roundList = {}					-- 回合数据
	self.curRound = false				-- 当前回合数据
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
	self:GenerateMonster(self.leftWaveNum, true)

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知客户端回合开始
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, 0, self.roundNum, nil, self.curRound.nextBossId, self.curRound.roundType)
	end)
end

function BattleCoopLogic:Initialize( _battleType, _battleResId, ... )
	self.super:Initialize(_battleType, _battleResId)

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
			self.roundList[specialRound] = { roundType = BattleCoopRoundType.SPECIAL, monsterOrderList = self.battleRes.specialMonsterOrderList, bossTimes = i }
		end
		self.roundList[curBossRound] = { roundType = BattleCoopRoundType.BOSS, bossId = self.battleRes.bossIdList[((i - 1) % #self.battleRes.bossIdList) + 1], bossTimes = i }
	end

	local bossTimes = 1
	for i = 1, maxRound do
		local round = self.roundList[i]
		if not round then
			round = { roundType = BattleCoopRoundType.NORMAL, monsterOrderList = self.battleRes.normalMonsterOrderList, bossTimes = bossTimes }
			self.roundList[i] = round
		elseif round.roundType == BattleCoopRoundType.BOSS then
			bossTimes = bossTimes + 1
		end
	end

	local nextBossId = 0
	for i = maxRound, 1, -1 do
		local round = self.roundList[i]
		if round.roundType == BattleCoopRoundType.BOSS then
			nextBossId = round.bossId
		end
		if nextBossId ~= 0 then
			round.nextBossId = nextBossId
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
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, 0, self.roundNum, nil, self.curRound.nextBossId, self.curRound.roundType)
end

-- 校验战斗是否结束
function BattleCoopLogic:CheckBattleEnd( ... )
	if self.isBattleEnd then
		return true
	end
	local isVideo = gBattleRecord.isVideo
	if isVideo and gBattleFrameCount >= gBattleRecord.frameCount then
		return true
	end
	return false
end

function BattleCoopLogic:GenerateMonster( _leftWaveNum, _isSnapShotPushing, ... )
	gBattleTimer:StopTask('GenerateMonster')

	local index = self.roundNum > #self.roundList and #self.roundList or self.roundNum
	local round = self.roundList[index]
	self.curRound = round
	if round.roundType ~= BattleCoopRoundType.BOSS then
		-- 普通出怪
		self.leftWaveNum = _leftWaveNum or #round.monsterOrderList
		gBattleTimer:RunTask('GenerateMonster', 500, 500, #round.monsterOrderList * 2, false, function( _index, ... )
			local playerIndex = (_index + 1) % 2 + 1
			if playerIndex == 1 then
				self.waveNum = (_index + 1) / 2 + self.roundStartWaveNum - 1
				self.leftWaveNum = self.leftWaveNum - 1

				-- 普通怪物血量
				self:RefreshMonsterHP()
			end
			-- warn('GenerateMonster', gBattleFrameCount, self.waveNum, _index, self.leftWaveNum, self.roundNum, self.roundStartWaveNum)
			-- 玩家轮流出怪物
			local monsterType = round.monsterOrderList[self.waveNum - self.roundStartWaveNum + 1]
			local monsterId = self:GetMonsterResId(monsterType)
			self.playerList[playerIndex]:AddMonster(monsterId)
		end)
	else
		-- Boss
		self.leftWaveNum = _leftWaveNum or 1
		if not _isSnapShotPushing then
			gBattleFreezing = true
		end
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PERIOD, 'OnBossEnter', round.bossId)
		gBattleTimer:RunTask('GenerateMonster', 1500, 500, 2, false, function( _index )
			if _index == 1 then
				gBattleFreezing = false
				self.isBossPeriod = true
				self.waveNum = self.roundStartWaveNum
				self.leftWaveNum = 0
				
				-- 普通怪物血量
				self:RefreshMonsterHP()
			end
			-- warn('GenerateMonster', self.waveNum, self.leftWaveNum, gBattleFrameCount)
			-- 玩家轮流出怪物
			local monsterId = round.bossId
			self.playerList[_index]:AddMonster(monsterId)
		end, false)
	end
end

function BattleCoopLogic:OnMonsterLeave( _monster, _leaveFlags, ... )
	local playerList = self.playerList
	local isKilled = _leaveFlags[BattleUnitLeaveType.DIE] == 1
	if isKilled then
		local point = _monster:GetPoint()
		local killScore = _monster.monsterRes.killScore
		for i = 1, #playerList do
			local player = playerList[i]
			player:AddPoint(point)
			player:AddParamValue(BattleParamType.KILLSCORE, killScore)
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
	for i = 1, #playerList do
		if playerList[i]:GetMonsterCount() ~= 0 then
			return
		end
	end
	-- 怪物全部死亡，下一阶段
	self:OnNextRoundStart()
end

function BattleCoopLogic:GetBossTimes( ... )
	return self.curRound.bossTimes
end