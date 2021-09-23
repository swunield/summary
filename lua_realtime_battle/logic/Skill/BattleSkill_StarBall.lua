---
--- class BattleSkill_StarBall
-- @classmod BattleSkill_StarBall
-- 星级光球，改变目标塔类型，并把星级改为光球星级
BattleSkill_StarBall = xclass('BattleSkill_StarBall')

local math_floor = math.floor
local math_ceil = math.ceil

local TSSkill = gModel.TSSkill

---Constructor
function BattleSkill_StarBall:ctor( ... )
	self.targetUnitId = false
	self.hitFrame = 0
	self.value = 0
end

function BattleSkill_StarBall:Serialize( ... )
	if not gBattleRecord:GetBattleUnit(self.targetUnitId) then
		return false
	end
	local tSkill = TSSkill:new{}
	tSkill.Type = BattleSkillType.STARBALL
	tSkill.TargetUnitId = self.targetUnitId
	tSkill.HitFrame = self.hitFrame
	tSkill.Value = self.value
	return tSkill
end

function BattleSkill_StarBall:DeSerialize( _tSkill )
	if not _tSkill then
		return
	end
	self.targetUnitId = _tSkill.TargetUnitId
	self.hitFrame = _tSkill.HitFrame
	self.value = _tSkill.Value
end

function BattleSkill_StarBall:Destroy( ... )
	-- body
end

function BattleSkill_StarBall:Init( _battleUnit, _targetUnit, _delayTime, _param, _startPosIndex, _effectResId, ... )
	if not _targetUnit then
		return false
	end
	local targetGrid = _targetUnit.player:GetGrid(_targetUnit.posIndex)
	if not targetGrid then
		return false
	end
	self.targetUnitId = targetGrid.unitId
	self.hitFrame = gBattleFrameCount + _delayTime / Constants.BATTLE_FRAME_TIME
	self.value = self:CalcStar()
	-- 添加标记
	targetGrid:AddUnitFlag(BattleUnitFlag.STARBALLLOCK, 1)
	-- 播放筛子特效
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EFFECT, true, _battleUnit.player.playerId, _battleUnit.unitId, Constants.BATTLE_BALL_MISSILE_EFFECT, targetGrid.unitId, 2000, GameStringType.Ball_1 + self.value - 1)
	return true
end

function BattleSkill_StarBall:Update( _deltaTime )
	if gBattleFrameCount < self.hitFrame then
		return true
	end
	-- 技能命中时，目标不存在则不作用
	local targetGrid = gBattleRecord:GetBattleUnit(self.targetUnitId)
	if not targetGrid then
		return false
	end
	-- 移除标记
	targetGrid:ClearUnitFlag(BattleUnitFlag.STARBALLLOCK, 1)
	local targetTower = targetGrid.tower
	if not targetTower then
		return false
	end
	-- 改变类型和星级
	local player = targetTower.player
	local posIndex = targetTower.posIndex
	if posIndex ~= 0 then
		local star = math_ceil((self.value + targetTower.star) / 2)
		local towerResId = player:RandomTowerResId(gBattleRandNum, targetTower.towerRes.id)
		local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
		if towerRes then
			player:RemoveTowerByFrame(nil, posIndex, FLAGMAP(BattleUnitLeaveType.STARBALL))
			player:AddTowerByFrame(nil, towerRes, star, posIndex, false, BattleTowerAddType.STARBALL)
		end
	end
	return false
end

-- 最小值  1+向上取整(boss次数/3)
-- 最大值  2+boss出现次数(<=6)
function BattleSkill_StarBall:CalcStar( ... )
	local bossTimes = gBattleLogic:GetBossTimes()
	local minStar = 1 + math_ceil(bossTimes / 3)
	if minStar > 4 then
		minStar = 4
	end
	local maxStar = 2 + bossTimes
	if maxStar > 6 then
		maxStar = 6
	end
	return gBattleRandNum:NextInt(minStar, maxStar)
end