---
--- class BattleCoopLogic
-- @classmod BattleCoopLogic
class('BattleCoopLogic', BattleLogic)

---Constructor
function BattleCoopLogic:ctor( ... )
	self.super = Super(...)
	self.pendingMonsterData = {}
	self.isBossPeriod = false			-- 是否Boss阶段
end

function BattleCoopLogic:Update( _deltaTime, ... )
	self.super:Update(_deltaTime, ...)

	for i = 1, #self.playerList do
		local player = self.playerList[i]
		local pendingData = self.pendingMonsterData[player.playerId]
		if pendingData.monsterCount > 0 and gBattleTime - pendingData.lastMonsterTime >= 500 then
			local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
			player:AddMonster(normalMonsterId)
			pendingData.lastMonsterTime = gBattleTime
			pendingData.monsterCount = pendingData.monsterCount - 1
			player.stat:AddPendingMonster(false)
		end
	end
end

function BattleCoopLogic:OnBattleBegin( ... )
	self.super:OnBattleBegin()

	for i = 1, #self.playerList do
		self.pendingMonsterData[self.playerList[i].playerId] = {
			monsterCount = 0,
			lastMonsterTime = 0
		}
	end

	self.roundNum = 1
	self.roundStartWaveNum = 1
	self.roundStartTime = gBattleTime
	self:GenerateMonster()
end

-- 校验战斗是否结束
function BattleCoopLogic:CheckBattleEnd( ... )
	local playerCount = #self.playerList
	for i = 1, playerCount do
		local player = self.playerList[i]
		local curHP = player.curHP
		-- if player.isSurrender or curHP <= 0 then
		-- 	local winPlayerId = self.playerList[i % playerCount + 1].playerId
		-- 	gBattleResult:SetWinPlayerId(winPlayerId)

		-- 	gBattleManager:AddBattleLog(string.format('Battle End Frame[%d] WinPlayer[%d]', gBattleFrameCount, winPlayerId))
		-- 	gBattleManager:AddBattleLog('log_end', true)
		-- 	return true
		-- end
	end
	return false
end

function BattleCoopLogic:GenerateMonster( ... )
	-- 刷新魔法消耗
	if self.roundNum == 1 then
		for i = 1, #self.playerList do
			self.playerList[i]:GenerateCoopMagic(3, true)
		end
	end

	local roundDuration = self:GetRoundData(self.roundNum)
	self.roundDuration = roundDuration

	for i = MonsterType.NORMAL, MonsterType.ELITE do
		local monsterType = i
		local monsterId = self:GetMonsterResId(monsterType)
		local monsterWaveCount = self:GetMonsterWaveCount(monsterType)
		local monsterInterval = ToInt(roundDuration / monsterWaveCount)
		gBattleTimer:RunTask(string.format('GenerateMonster_%d', monsterType), 0, monsterInterval, monsterWaveCount, nil, function( _index, ... )
			if _index == monsterWaveCount or (monsterType ~= MonsterType.NORMAL and _index == 0) then
				return
			end
			-- 统计总波数
			if monsterType == MonsterType.NORMAL then
				self.waveNum = _index + self.roundStartWaveNum

				-- 普通怪物血量
				local normalMonsterRes = GameResMgr.GetBattleMonsterRes(monsterId)
				local monsterHPScale = gBattleLogic:GetMonsterHPScale(normalMonsterRes.type) / 100
				self.monsterHP = ToInt(BattleFormula.GetValue(normalMonsterRes.hpId) * monsterHPScale)
			end
			-- 双方各出一个怪物
			for i = 1, #self.playerList do
				self.playerList[i]:AddMonster(monsterId)
			end
			warn('GenerateNormalMonster', self.roundNum, self.roundStartWaveNum, monsterType, _index, self.waveNum, gBattleTime)
		end)
	end

	-- 随机魔法怪
	local magicMonsterCount = gBattleRandNum:NextInt(3, 6)
	local perPeriodTime = self.roundDuration / magicMonsterCount
	local delayTimeList = {}
	for i = 1, magicMonsterCount do
		table_insert(delayTimeList, perPeriodTime * (i - 1) + gBattleRandNum:NextInt(perPeriodTime))
	end	
	gBattleTimer:RunQueueTask('GenerateMagicMonster', delayTimeList, 0, 0, function( _index )
		local monsterType = gBattleRandNum:NextInt(MonsterType.ELITE)
		local monsterId = self:GetMonsterResId(monsterType)
		-- 双方各出一个魔法怪
		for i = 1, #self.playerList do
			self.playerList[i]:AddMonster(monsterId, nil, true)
		end
	end)

	-- 生成BOSS
	gBattleTimer:RunTask('GenerateBoss', roundDuration, 0, 0, function( ... )
		-- 标记Boss阶段
		self.isBossPeriod = true
		-- 生成Boss
		for i = 1, #self.playerList do
			local player = self.playerList[i]
			-- 添加BOSS
			player:AddMonster(self:GetMonsterResId(MonsterType.BOSS))
			-- 清场所有怪物
			player:RemoveAllMonster(BattleUnitLeaveType.CLEAN, false)
			-- 重置怪物缓冲数据
			local pendingData = self.pendingMonsterData[player.playerId]
			pendingData.monsterCount = 0
			pendingData.lastMonsterTime = 0
		end
	end)
end

function BattleCoopLogic:OnMonsterDie( _monster, _isKilled, ... )
	if not self.super:OnMonsterDie(_monster) then
		return false
	end

	if _isKilled and _monster.isMagicMonster then
		_monster.player:GenerateCoopMagic(1)
	end

	if self.isBossPeriod then
		for i = 1, #self.playerList do
			if self.playerList[i]:GetMonsterCount() ~= 0 then
				return true
			end
		end
		-- 怪物全部死亡，下一阶段
		self.isBossPeriod = false
		self.roundNum = self.roundNum + 1
		self.roundStartWaveNum = self.waveNum + 1
		self.roundStartTime = gBattleTime
		self:GenerateMonster()
	else
		if _isKilled then
			-- 对手增加一个小怪
			local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
			local player = BattleTarget.GetTargetPlayer(_monster.player, BattlePlayerType.OPPONENT)
			player = _monster.player
			local pendingData = self.pendingMonsterData[player.playerId]
			pendingData.monsterCount = pendingData.monsterCount + 1
			player.stat:AddPendingMonster(true)
		end
	end
	return true
end

function BattleCoopLogic:GetTotalMonsterHP( _player, ... )
	local totalHP = 0
	local pendingData = self.pendingMonsterData[_player.playerId]
	if pendingData.monsterCount > 0 then
		local normalMonsterId = self:GetMonsterResId(MonsterType.NORMAL)
		local normalMonsterRes = GameResMgr.GetBattleMonsterRes(normalMonsterId)
		local monsterHPScale = gBattleLogic:GetMonsterHPScale(normalMonsterRes.type) / 100
		local monsterHP = ToInt(BattleFormula.GetValue(normalMonsterRes.hpId) * monsterHPScale)
		totalHP = totalHP + monsterHP * pendingData.monsterCount
	end
	local monsterNode = _player.monsterList.first
	while monsterNode do
		local monster = monsterNode.value
		if monster.monsterRes.type ~= MonsterType.BOSS then
			totalHP = totalHP + monster.curHP
		end
		monsterNode = monsterNode.next
	end
	return totalHP
end

function BattleCoopLogic:OnMagicSpell( _player, _magicData, ... )
	_player:OnCoopMagicSpell(_magicData)
end

classend()