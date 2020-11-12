---
--- class BattleSpecialLogic
-- @classmod BattleSpecialLogic
class('BattleSpecialLogic')


-- 特殊战斗初始化
local SpecialBattleInitSwitcher = 
{
	-- 职业副本
	[BattleType.ZYFBBOSS] = function( ... )
		gBattleManager.specialBattleData.fbRes = GameResMgr.GetZYFubenRes(ToInt(gBattleManager.battleParam))
		if not gBattleManager.specialBattleData.fbRes then
			return false
		end

		local fbRes = gBattleManager.specialBattleData.fbRes

		-- boss血量Buffer列表
		gBattleManager.specialBattleData.bossBufferHPList = {}
		local index = 1
		for i = 1, 100 do
			if i >= fbRes.bufferHpList[index] then
				if i == fbRes.bufferHpList[index + 1] then
					index = index + 1
				end
				index = index > #fbRes.bufferHpList and #fbRes.bufferHpList or index
				table.insert(gBattleManager.specialBattleData.bossBufferHPList, { bossHPPer = (100 - i) * 100, bufferId = fbRes.hpBufferList[index] })
			end
		end

		-- boss回合Buffer列表
		gBattleManager.specialBattleData.bossBufferRoundList = {}
		gBattleManager.maxRound = fbRes.bufferRoundList[#fbRes.bufferRoundList]
		index = 1
		for i = 1, gBattleManager.maxRound do
			if i >= fbRes.bufferRoundList[index] then
				if i == fbRes.bufferRoundList[index + 1] then
					index = index + 1
				end
				index = index > #fbRes.bufferRoundList and #fbRes.bufferRoundList or index
				table.insert(gBattleManager.specialBattleData.bossBufferRoundList, { round = i, bufferId = fbRes.roundBufferList[index] })
			end
		end

		if gBattleManager.isClientMode then
			-- 客户端模式，boss血量宝箱列表
			gBattleManager.specialBattleData.bossRewardHPList = {}
			for i = 1, #fbRes.rewardHpList do
				table.insert(gBattleManager.specialBattleData.bossRewardHPList, { bossHPPer = 10000 - fbRes.rewardHpList[i], rewardLevel = fbRes.rewardLevelList[i], rewardIndex = i, lastBossHPPer = i == 1 and 10000 or (10000 - fbRes.rewardHpList[i - 1]) })
			end
		end

		-- boss
		gBattleManager.specialBattleData.bossHero = gBattleManager.campHeroList[BattleCampType.CAMP_B][1]
		gBattleManager.specialBattleData.bossHero.heroData.maxHP = fbRes.totalHp
		gBattleManager.specialBattleData.bossBufferLaps = 0

		return true
	end,
}

-- 特殊战斗逻辑事件
local SpecialBattleLogicSwitcher = 
{
	-- 职业副本，BOSS血量变化
	['ZYFB_BossHP'] = function( _heroId, _hpPercent, ... )
		if gBattleManager.specialBattleData.bossHero.heroId ~= _heroId then
			return
		end

		-- 掉血Buffer
		local bossHero = gBattleManager.specialBattleData.bossHero
		local bufferHPList = gBattleManager.specialBattleData.bossBufferHPList
		while (#bufferHPList >= 1 and _hpPercent <= bufferHPList[1].bossHPPer) do
			bossHero:AddBuffer(bufferHPList[1].bufferId, bossHero)
			gBattleManager.specialBattleData.bossBufferLaps = gBattleManager.specialBattleData.bossBufferLaps + 1
			table.remove(bufferHPList, 1)

			-- 通知表现层，职业副本BOSS叠加Buffer
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ZYFB_BUFFER, bossHero.heroId, gBattleManager.specialBattleData.bossBufferLaps)
		end

		if gBattleManager.isClientMode then
			-- 客户端模式，掉血奖励
			local dropRewardList = {}
			local rewardHPList = gBattleManager.specialBattleData.bossRewardHPList
			while (#rewardHPList > 1 and _hpPercent <= rewardHPList[1].bossHPPer) do
				table.insert(dropRewardList, { rewardIndex = rewardHPList[1].rewardIndex, rewardLevel = rewardHPList[1].rewardLevel, nextRewardLevel = #rewardHPList > 1 and rewardHPList[2].rewardLevel or rewardHPList[1].rewardLevel })
				table.remove(rewardHPList, 1)
			end

			local nextRewardLevel = rewardHPList[1].rewardLevel
			local nextPoint = ToInt((100 - rewardHPList[1].bossHPPer * 0.01) * bossHero.heroData.maxHP * 0.01)
			local curPoint = ToInt(bossHero.heroData.maxHP - bossHero.heroData.curHP)
			local lastPoint = ToInt((100 - rewardHPList[1].lastBossHPPer * 0.01) * bossHero.heroData.maxHP * 0.01)
			local gold = ToInt(curPoint * gBattleManager.specialBattleData.fbRes.goldFactor * s_PercentScale)
			local rewardIndex = rewardHPList[1].rewardIndex
			local totalReward = #gBattleManager.specialBattleData.fbRes.rewardHpList

			-- 通知表现层，职业副本刷新BOSS血量
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ZYFB_HP, bossHero.heroId, curPoint, nextPoint, lastPoint, nextRewardLevel, rewardIndex, dropRewardList, gold, totalReward)
		end
	end,
	-- 职业副本，回合变化
	['ZYFB_Round'] = function( _round, ... )
		-- 回合Buffer
		local bufferRoundList = gBattleManager.specialBattleData.bossBufferRoundList
		while (#bufferRoundList >= 1 and _round >= bufferRoundList[1].round) do
			local bossHero = gBattleManager.specialBattleData.bossHero
			bossHero:AddBuffer(bufferRoundList[1].bufferId, bossHero)
			gBattleManager.specialBattleData.bossBufferLaps = gBattleManager.specialBattleData.bossBufferLaps + 1
			table.remove(bufferRoundList, 1)

			-- 通知表现层，职业副本BOSS叠加Buffer
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ZYFB_BUFFER, bossHero.heroId, gBattleManager.specialBattleData.bossBufferLaps)
		end
	end
}

-- 特殊战斗逻辑初始化
function BattleSpecialLogic.InitSpecialBattle( ... )
	local initExcutor = SpecialBattleInitSwitcher[gBattleManager.battleType]
	if not initExcutor then
		return true
	end
	return initExcutor()
end

-- 特殊战斗逻辑事件
function BattleSpecialLogic.FireSpecialBattleLogic( _battleType, _logicName, _param1, _param2, ... )
	if _battleType ~= gBattleManager.battleType then
		return
	end

	local logicExcutor = SpecialBattleLogicSwitcher[_logicName]
	if not logicExcutor then
		return
	end
	logicExcutor( _param1, _param2, ...)
end

-- 英雄血量变化
function BattleSpecialLogic.OnHeroHPChange( _heroId, _hpPercent, ...  )
	-- 职业副本，BOSS血量变化
	FireSpecialBattleLogic(BattleType.ZYFBBOSS, 'ZYFB_BossHP', _heroId, _hpPercent)
end

-- 战斗回合变化
function BattleSpecialLogic.OnBattleRoundChange( _round )
	-- 职业副本，回合变化
	FireSpecialBattleLogic(BattleType.ZYFBBOSS, 'ZYFB_Round', _round)
end

classend()