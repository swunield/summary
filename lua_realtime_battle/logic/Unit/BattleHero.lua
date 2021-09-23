---
--- class BattleHero
-- @classmod BattleHero
-- 战斗塔
BattleHero = xclass('BattleHero', BattleUnit)

local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy

local TSHero = gModel.TSHero
local TSHeroTalent = gModel.TSHeroTalent

---Constructor
function BattleHero:ctor( ... )
	self.super.unitType = BattleUnitType.HERO

	self.heroId = 0							-- 实例id
	self.heroRes = false					-- 配置
	self.heroTalentRes = false				-- 英雄特性
	self.talentRes = false					-- 天赋配置
	self.heroAIFactor = false				-- 英雄AI系数
	self.awakenTalentId = false				-- 觉醒天赋Id

	self.heroTalent = false					-- 英雄特性数据
	self.firstCD = false					-- 第一段CD
end

function BattleHero:Serialize( ... )
	local tHero = TSHero:new{}
	tHero.Unit = self.super:Serialize()
	if self.heroTalent then
		local tHeroTalent = TSHeroTalent:new{}
		tHeroTalent.NextReadyTime = self.heroTalent.nextReadyTime
		tHero.HeroTalent = tHeroTalent
	end
	return tHero
end

function BattleHero:DeSerialize( _tHero, ... )
	if not _tHero then
		return
	end
	if _tHero.HeroTalent then
		if not self.heroTalent then
			self.heroTalent = {}
		end
		self.heroTalent.nextReadyTime = _tHero.HeroTalent.NextReadyTime
	end
	self.super:DeSerialize(_tHero.Unit)

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		if self.heroTalent then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.HEROTALENTCD, self.player.playerId, gBattleTime - (self.heroTalent.nextReadyTime - self.heroTalentRes.fireCD), self.heroTalent.nextReadyTime - gBattleTime)
		end
	end)
end

function BattleHero:Load( _tHero, _heroAIFactor, ... )
	if not _tHero then
		return
	end

	local heroResId, awakenIndex, awakenLevel = DecodeAwaken(_tHero.HeroId)
	self.heroRes = GameResMgr.GetBattleHeroRes(heroResId)
	self.heroTalentRes = GameResMgr.GetHeroTalentRes(self.heroRes.heroTalentId)
	self.firstCD = _tHero.FirstCD or false
	-- 主动技能AI系数
	if self.heroTalentRes.talentType == BattleHeroTalentType.MANUAL then
		self.heroAIFactor = _heroAIFactor or false
	end
	-- 觉醒技能
	self.awakenTalentId = GameResMgr.GetAwakenTalentId(self.heroRes, awakenIndex, awakenLevel)
end

function BattleHero:Destroy( _leaveFlags, ... )
	-- 父类销毁
	self.super:Destroy(_leaveFlags, ...)	
end

function BattleHero:Init( _player, ... )
	if not self.heroRes then
		return false
	end

	self.player = _player
	self.heroId = _player:GenerateHeroId()
	self.player.maxHP = self.heroRes.hp
	self.player.curHP = self.heroRes.hp
	self.unit = self
	self.unitId = self:GenerateUnitId(self.heroId)

	-- 初始化英雄天赋
	self:InitHeroTalent(self.heroTalentRes)

	-- 初始化觉醒天赋
	self:RegisterTalent(self.awakenTalentId)

	-- 父类初始化
	self.super:Init(true)

	return true
end

function BattleHero:Update( _deltaTime, ... )
	if not self.heroRes then
		return
	end

	-- 更新状态
	local carryBufferList = self.carryBufferList
	local bufferCount = #carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end

	-- 自动攻击天赋
	self:TryExecHeroTalent(BattleHeroTalentType.AUTO)

	-- 英雄AI
	if self.heroAIFactor then
		self:TryExecHeroAI(self.heroAIFactor)
	end
end

function BattleHero:InitHeroTalent( _heroTalentRes, ... )
	-- 注册天赋
	self.talentRes = self:RegisterTalentList(_heroTalentRes.talentList, self)

	local talentType = _heroTalentRes.talentType
	if talentType == BattleHeroTalentType.TRIGGER then
		return
	end

	if not self.heroTalent then
		self.heroTalent = {}
	end

	local cdTime = self.firstCD or _heroTalentRes.fireCD
	self.heroTalent.nextReadyTime = gBattleTime + cdTime

	-- 通知前端刷新CD
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.HEROTALENTCD, self.player.playerId, _heroTalentRes.fireCD - cdTime, cdTime)
end

function BattleHero:TryExecHeroTalent( _talentType, ... )
	if not self.heroRes then
		return ErrorCode.SUCCESS
	end
	local heroTalentRes = self.heroTalentRes
	if heroTalentRes.talentType ~= _talentType then
		return ErrorCode.HEROTALENT_TYPENOTMATCH
	end
	local heroTalent = self.heroTalent
	if gBattleTime < heroTalent.nextReadyTime then
		return ErrorCode.HEROTALENT_NOTREADY
	end

	local lastTime = _talentType == BattleHeroTalentType.MANUAL and gBattleTime or heroTalent.nextReadyTime
	heroTalent.nextReadyTime = lastTime + heroTalentRes.fireCD

	-- 触发行为
	local talentRes = self.talentRes
	for i = 1, #talentRes.actionList do
		local actionId = talentRes.actionList[i]
		local triggerParam = BattleTriggerParam_New(self, nil, nil, nil)
		gBattleTrigger:FireAction(actionId, self, self, triggerParam)
		BattleTriggerParam_Destroy(triggerParam)
	end

	-- 通知前端刷新CD
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.HEROTALENTCD, self.player.playerId, gBattleTime - lastTime, heroTalent.nextReadyTime - gBattleTime, self.player.unitId, heroTalentRes.eventName)

	return ErrorCode.SUCCESS
end

function BattleHero:IsHeroTalentReady( ... )
	return not self.heroTalent or gBattleTime >= self.heroTalent.nextReadyTime
end

function BattleHero:GetHeroTalentType( ... )
	return self.heroTalentRes.talentType
end

function BattleHero:TryExecHeroAI( _heroAIFactor )
	-- 技能CD没好
	if not self:IsHeroTalentReady() then 
		return
	end
	local player = self.player
	if _heroAIFactor < 0 then
		-- 看对手怪物
		player = player.opponent
		_heroAIFactor = -_heroAIFactor
	end
	local monsterList = player.monsterList
	if #monsterList == 0 then
		return
	end
	local firstMonster = monsterList[1]
	if firstMonster.position * Constants.PERCENT_MAX / BattleConstants.BATTLE_ROAD_LENGTH < _heroAIFactor then
		return
	end
	-- 释放技能
	self:TryExecHeroTalent(BattleHeroTalentType.MANUAL)
end