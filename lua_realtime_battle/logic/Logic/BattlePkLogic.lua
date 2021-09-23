---
--- class BattlePkLogic
-- @classmod BattlePkLogic
BattlePkLogic = xclass('BattlePkLogic', BattleLogic)

local table_insert = table.insert
local math_floor = math.floor
local math_ceil = math.ceil
local FLAGMAP = Utils.BuildFlagMap

local TSLogic = gModel.TSLogic
local TSPendingMonster = gModel.TSPendingMonster

---Constructor
function BattlePkLogic:ctor( _isLocal, ... )  
	self.super.isLocal = _isLocal or false 	-- 是否本地
	self.pendingMonsterData = {}
	self.isBossPeriod = false			-- 是否Boss阶段
	self.bossIndex = 0					-- 当前回合Boss索引
end

function BattlePkLogic:Serialize( ... )
	local tLogic = TSLogic:new{}
	self.super:Serialize(tLogic)
	tLogic.BossPeriod = self.isBossPeriod and 1 or nil
	tLogic.BossIndex = self.bossIndex
	for playerId, pendingData in pairs(self.pendingMonsterData) do
		if pendingData.monsterCount ~= 0 then
			if not tLogic.PendingMonster then
				tLogic.PendingMonster = {}
			end
			local tPending = TSPendingMonster:new{}
			tPending.PlayerId = playerId
			tPending.Count = pendingData.monsterCount
			tPending.LastTime = pendingData.lastMonsterTime
			table_insert(tLogic.PendingMonster, tPending)
		end 
	end
	return tLogic
end

function BattlePkLogic:DeSerialize( _tLogic, ... )
	if not _tLogic then
		return
	end
	self.super:DeSerialize(_tLogic)
	self.isBossPeriod = _tLogic.BossPeriod == 1
	self.bossIndex = _tLogic.BossIndex
	if _tLogic.PendingMonster then
		for i = 1, #_tLogic.PendingMonster do
			local tPending = _tLogic.PendingMonster[i]
			local pendingData = {}
			pendingData.monsterCount = tPending.Count
			pendingData.lastMonsterTime = tPending.LastTime
			self.pendingMonsterData[tPending.PlayerId] = pendingData
		end
	end

	self:RefreshMonsterHP()
	self:GenerateMonster(true)

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知客户端回合开始
		if not self.isBossPeriod then
			local bossTask = gBattleTimer:GetTask('GenerateBoss')
			if bossTask then
				local duration = bossTask.beginTime + bossTask.delayTime - bossTask.time
				duration = duration < 0 and 0 or duration
				local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, duration, 0)
			end
		end
	end)
end

function BattlePkLogic:Initialize( _battleType, _battleResId, ... )
	self.super:Initialize(_battleType, _battleResId)

	-- 怪物路径
	BattleConstants.BATTLE_ROAD_LENGTH = BattleConstants.BATTLE_PK_ROAD_LENGTH
	BattleConstants.BATTLE_ROAD_UNIT_LENGTH = BattleConstants.BATTLE_PK_ROAD_UNIT_LENGTH

	-- 距离数值表
	Global.BattleMonsterDistance = {}
	for gridIndex, distanceList in pairs(BattlePkDistance) do
		local monsterDistanceList = {}
		BattleMonsterDistance[gridIndex] = monsterDistanceList
		for i = 1, #distanceList do
			table_insert(monsterDistanceList, math_ceil(distanceList[i] / Constants.BATTLE_FRAME_TIME))
		end
	end
end

function BattlePkLogic:Update( _deltaTime, ... )  
	for i = 1, #self.playerList do
		local player = self.playerList[i]
		local pendingData = self.pendingMonsterData[player.playerId]
		if pendingData.monsterCount > 0 and gBattleTime - pendingData.lastMonsterTime >= 100 then
			local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
			player:AddMonster(normalMonsterId)
			pendingData.lastMonsterTime = gBattleTime
			pendingData.monsterCount = pendingData.monsterCount - 1
		end
	end
end

function BattlePkLogic:OnBattleBegin( ... )  
	self.super:OnBattleBegin()

	for i = 1, #self.playerList do
		self.pendingMonsterData[self.playerList[i].playerId] = {
			monsterCount = 0,
			lastMonsterTime = 0
		}
	end

	self.roundNum = 0
	self.waveNum = 0
	self:OnNextRoundStart()
end

-- boss随机跟上一个不重复的
function BattlePkLogic:RandomBoss( _lastBossIndex, ... )
	local index = gBattleRandNum:NextInt(#self.battleRes.bossIdList)
	if _lastBossIndex ~= 0 and _lastBossIndex == index then
		return self:RandomBoss(_lastBossIndex)
	end
	return index
end

-- 下一回合开始
function BattlePkLogic:OnNextRoundStart( ... )
	self.isBossPeriod = false
	self.roundNum = self.roundNum + 1
	self.roundStartWaveNum = self.waveNum + 1
	self.roundStartTime = gBattleTime
	self.bossIndex = self:RandomBoss(self.bossIndex)
	self:GenerateMonster()

	-- 通知客户端回合开始
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, 0, 0, self.bossIndex)
end

-- 校验战斗是否结束
function BattlePkLogic:CheckBattleEnd( ... )
	if self.isLocal then
		return false
	end
	local playerCount = #self.playerList
	for i = 1, playerCount do
		local player = self.playerList[i]
		local curHP = player.curHP
		if player.isSurrender or curHP <= 0 then
			local winPlayerId = self.playerList[i % playerCount + 1].playerId
			gBattleResult:SetWinPlayerId(winPlayerId)
			return true
		end
	end
	return false
end

function BattlePkLogic:GenerateMonster( _isSnapShotPushing, ... )
	if not _isSnapShotPushing then  
		gBattleFreezing = true
	end

	local roundDuration = self:GetRoundData(self.roundNum)
	self.roundDuration = roundDuration

	local delay = 3000
	for i = MonsterType.NORMAL, MonsterType.ELITE do
		local monsterType = i
		local monsterId = self:GetMonsterResId(monsterType)
		local monsterWaveCount = self:GetMonsterWaveCount(monsterType)
		local monsterInterval = math_floor(roundDuration / monsterWaveCount)
		local monsterGenerator = function( _index, ... )
			if _index == 0 then
				gBattleFreezing = false
			end
			if _index == monsterWaveCount or (monsterType ~= MonsterType.NORMAL and _index == 0) then
				return
			end
			if monsterType == MonsterType.NORMAL and _index == 0 then
				local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ROUNDSTART, roundDuration, 0)
			end
			-- 统计总波数
			if monsterType == MonsterType.NORMAL then
				self.waveNum = _index + self.roundStartWaveNum

				-- 普通怪物血量
				self:RefreshMonsterHP()
			end
			-- 双方各出一个怪物
			for i = 1, #self.playerList do
				self.playerList[i]:AddMonster(monsterId)
			end
			-- warn('GenerateNormalMonster', self.roundNum, self.roundStartWaveNum, monsterType, _index, self.waveNum, gBattleTime)
		end
		gBattleTimer:RunTask(string.format('GenerateMonster_%d', monsterType), delay, monsterInterval, monsterWaveCount, monsterGenerator, monsterGenerator)
	end

	-- 生成BOSS
	gBattleTimer:RunTask('GenerateBoss', delay + roundDuration, 2000, 1, function( ... )
		gBattleFreezing = true
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PERIOD, 'OnBossEnter', self:GetMonsterResId(MonsterType.BOSS, self.bossIndex))
	end, function( ... )
		-- 解除冻结
		gBattleFreezing = false
		-- 标记Boss阶段
		self.isBossPeriod = true
		-- 生成Boss
		for i = 1, #self.playerList do
			local player = self.playerList[i]
			-- 添加BOSS
			player:AddMonster(self:GetMonsterResId(MonsterType.BOSS, self.bossIndex))
			-- 清场所有怪物
			player:RemoveAllMonster(FLAGMAP(BattleUnitLeaveType.CLEAN), false)
			-- 重置怪物缓冲数据
			local pendingData = self.pendingMonsterData[player.playerId]
			pendingData.monsterCount = 0
			pendingData.lastMonsterTime = 0
		end
	end)
end

function BattlePkLogic:OnMonsterLeave( _monster, _leaveFlags, ... )
	-- 怪物非清场方式离场的话，给玩家加SP
	local needPoint = _leaveFlags[BattleUnitLeaveType.CLEAN] ~= 1
	local player = _monster.player
	if needPoint then
		player:AddPoint(_monster:GetPoint())
	end
	-- 怪物走到终点，扣血
	if _leaveFlags[BattleUnitLeaveType.END] == 1 then
		local subHP = _monster.monsterRes.type == MonsterType.BOSS and 2 or 1
		player.curHP = player.curHP - subHP

		-- 通知前端更新血量
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PLAYERHP, player.playerId, player.curHP, player.maxHP, false)
	end
	local isKilled = _leaveFlags[BattleUnitLeaveType.DIE] == 1
	if isKilled then
		-- 累积击杀
		player:AddParamValue(BattleParamType.KILLSCORE, _monster.monsterRes.killScore)
	end
	if self.isBossPeriod then
		for i = 1, #self.playerList do
			if self.playerList[i]:GetMonsterCount() ~= 0 then
				return
			end
		end
		-- 怪物全部死亡，下一阶段
		self:OnNextRoundStart()
	else
		if isKilled then
			-- 对手增加一个小怪
			local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
			local opponentPlayer = BattleTarget.GetTargetPlayer(player, BattlePlayerType.OPPONENT)
			if self.isLocal then
				opponentPlayer = player
			end
			local pendingData = self.pendingMonsterData[opponentPlayer.playerId]
			pendingData.monsterCount = pendingData.monsterCount + 1
		end
	end
end

function BattlePkLogic:GetTotalMonsterHP( _player, ... )  
	local totalHP = 0
	local pendingData = self.pendingMonsterData[_player.playerId]
	if pendingData.monsterCount > 0 then
		local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
		local normalMonsterRes = GameResMgr.GetBattleMonsterRes(normalMonsterId)
		local monsterHPScale = normalMonsterRes.hpScale / Constants.PERCENT_MAX
		local monsterHP = math_floor(BattleFormula.GetValue(normalMonsterRes.hpId) * monsterHPScale)
		totalHP = totalHP + monsterHP * pendingData.monsterCount
	end
	for i = 1, #_player.monsterList do
		local monster = _player.monsterList[i]
		if monster.monsterRes.type ~= MonsterType.BOSS then
			totalHP = totalHP + (monster.curHP or 0)
		end
	end
	return totalHP * 0.5
end

function BattlePkLogic:GetBossTimes( ... )
	return self.roundNum
end