---
--- class BattleHero
-- @classmod BattleHero
-- 战斗塔
class('BattleHero', BattleUnit)

local BattleTriggerParam_New = BattleTriggerParam.New

local TSHero = gModel.TSHero
local TSHeroTalent = gModel.TSHeroTalent

---Constructor
function BattleHero:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.HERO

	self.heroId = 0							-- 实例id
	self.heroRes = false					-- 配置
	self.heroTalentRes = false				-- 英雄特性
	self.talentRes = false					-- 天赋配置

	self.heroTalent = false					-- 英雄特性数据
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

function BattleHero:Load( _tHero, ... )
	if not _tHero then
		return
	end

	self.heroRes = GameResMgr.GetBattleHeroRes(_tHero.HeroId)
	self.heroTalentRes = GameResMgr.GetHeroTalentRes(self.heroRes.heroTalentId)
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

	-- 父类初始化
	self.super:Init()

	return true
end

function BattleHero:Update( _deltaTime, ... )
	if not self.heroRes then
		return
	end

	-- 父类更新
	self.super:Update(_deltaTime, ...)

	-- 自动攻击天赋
	self:TryExecHeroTalent(BattleHeroTalentType.AUTO)
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

	self.heroTalent.nextReadyTime = gBattleTime + _heroTalentRes.fireCD

	-- 通知前端刷新CD
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.HEROTALENTCD, self.player.playerId, 0, _heroTalentRes.fireCD)
end

function BattleHero:TryExecHeroTalent( _talentType, ... )
	if not self.heroRes then
		return ErrorCode.SUCCESS
	end
	if self.heroTalentRes.talentType ~= _talentType then
		return ErrorCode.HEROTALENT_TYPENOTMATCH
	end
	local heroTalent = self.heroTalent
	if gBattleTime < heroTalent.nextReadyTime then
		return ErrorCode.HEROTALENT_NOTREADY
	end

	local lastTime = _talentType == BattleHeroTalentType.MANUAL and gBattleTime or heroTalent.nextReadyTime
	heroTalent.nextReadyTime = lastTime + self.heroTalentRes.fireCD

	-- 触发行为
	local talentRes = self.talentRes
	for i = 1, #talentRes.actionList do
		local actionId = talentRes.actionList[i]
		local triggerParam = BattleTriggerParam_New(self, nil, nil, nil)
		gBattleTrigger:FireAction(actionId, self, self, triggerParam)
	end

	-- 通知前端刷新CD
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.HEROTALENTCD, self.player.playerId, gBattleTime - lastTime, heroTalent.nextReadyTime - gBattleTime)

	return ErrorCode.SUCCESS
end

function BattleHero:IsHeroTalentReady( ... )
	return not self.heroTalent or gBattleTime >= self.heroTalent.nextReadyTime
end

function BattleHero:GetHeroTalentType( ... )
	return self.heroTalentRes.talentType
end

classend()