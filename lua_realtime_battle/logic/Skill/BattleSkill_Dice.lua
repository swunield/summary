---
--- class BattleSkill_Dice
-- @classmod BattleSkill_Dice
-- 骰子，星级低于骰子点数的所有塔改变类型
BattleSkill_Dice = xclass('BattleSkill_Dice')

local math_floor = math.floor
local math_ceil = math.ceil

local TSSkill = gModel.TSSkill

---Constructor
function BattleSkill_Dice:ctor( ... )
	self.battleUnit = false
	self.targetUnit = false
	self.hitFrame = 0
	self.value = 0
end

function BattleSkill_Dice:Serialize( ... )
	if not self.battleUnit:CanAttack() then
		return false
	end
	local tSkill = TSSkill:new{}
	tSkill.Type = BattleSkillType.DICE
	tSkill.UnitId = self.battleUnit.unitId
	tSkill.TargetUnitId = self.targetUnit.unitId
	tSkill.HitFrame = self.hitFrame
	tSkill.Value = self.value
	return tSkill
end

function BattleSkill_Dice:DeSerialize( _tSkill )
	if not _tSkill then
		return
	end
	self.hitFrame = _tSkill.HitFrame
	self.value = _tSkill.Value
	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		self.battleUnit = gBattleRecord:GetBattleUnit(_tSkill.UnitId)
		self.targetUnit = gBattleRecord:GetBattleUnit(_tSkill.TargetUnitId)
	end)
end

function BattleSkill_Dice:Destroy( ... )
	-- body
end

function BattleSkill_Dice:Init( _battleUnit, _targetUnit, _delayTime, _param, _startPosIndex, _effectResId, ... )
	if not _battleUnit or not _targetUnit then
		return false
	end
	self.battleUnit = _battleUnit
	self.targetUnit = _targetUnit.player
	self.hitFrame = gBattleFrameCount + _delayTime / Constants.BATTLE_FRAME_TIME
	self.value = self:CalcStar()

	-- 播放筛子特效
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EFFECT, true, _battleUnit.player.playerId, _battleUnit.unitId, Constants.BATTLE_DICE_MISSILE_EFFECT, _battleUnit.player.unitId, 500, GameStringType.Play_1 + self.value - 1)

	return true
end

function BattleSkill_Dice:Update( _deltaTime )
	if gBattleFrameCount < self.hitFrame then
		if not self.battleUnit:CanAttack() then
			return false
		end
		return true
	end
	-- 技能命中时，boss不能攻击则不作用
	if not self.battleUnit:CanAttack() then
		return false
	end
	local targetStar = self.value
	local player = self.targetUnit
	local towerList = player.towerList
	for i = 1, #towerList do
		local tower = towerList[i]
		if tower and tower.star <= targetStar then
			local posIndex = tower.posIndex
			local towerResId = player:RandomTowerResId(gBattleRandNum, tower.towerRes.id)
			local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
			if towerRes then
				-- 改变类型，保留星级
				local star = tower.star
				player:RemoveTowerByFrame(nil, posIndex, FLAGMAP(BattleUnitLeaveType.DICE))
				player:AddTowerByFrame(nil, towerRes, star, posIndex, false, BattleTowerAddType.DICE)
			end
		end
	end
	return false
end

-- 最小值  1+向上取整(boss次数/3)
-- 最大值  3+boss出现次数(<=6)
function BattleSkill_Dice:CalcStar( ... )
	local bossTimes = gBattleLogic:GetBossTimes()
	local minStar = 1 + math_ceil(bossTimes / 3)
	if minStar > 5 then
		minStar = 5
	end
	local maxStar = 3 + bossTimes
	if maxStar > 6 then
		maxStar = 6
	end
	return gBattleRandNum:NextInt(minStar, maxStar)
end