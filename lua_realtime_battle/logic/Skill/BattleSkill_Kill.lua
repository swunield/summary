---
--- class BattleSkill_Kill
-- @classmod BattleSkill_Kill
-- 星级光球，改变目标塔类型，并把星级改为光球星级
BattleSkill_Kill = xclass('BattleSkill_Kill')

local math_floor = math.floor
local math_ceil = math.ceil

local TSSkill = gModel.TSSkill

---Constructor
function BattleSkill_Kill:ctor( ... )
	self.targetUnitId = false
	self.hitFrame = 0
	self.value = 0
end

function BattleSkill_Kill:Serialize( ... )
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

function BattleSkill_Kill:DeSerialize( _tSkill )
	if not _tSkill then
		return
	end
	self.targetUnitId = _tSkill.TargetUnitId
	self.hitFrame = _tSkill.HitFrame
	self.value = _tSkill.Value
end

function BattleSkill_Kill:Destroy( ... )
	-- body
end

function BattleSkill_Kill:Init( _battleUnit, _targetUnit, _delayTime, _param, _startPosIndex, _effectResId, ... )
	if not _targetUnit then
		return false
	end
	local targetGrid = _targetUnit.player:GetGrid(_targetUnit.posIndex)
	if not targetGrid then
		return false
	end
	local startGrid = _battleUnit.player:GetGrid(_startPosIndex)
	if not startGrid then
		return false
	end
	self.targetUnitId = targetGrid.unitId
	self.hitFrame = gBattleFrameCount + _delayTime / Constants.BATTLE_FRAME_TIME
	self.value = tonumber(_param)
	-- 添加标记
	targetGrid:AddUnitFlag(self.value < 0 and BattleUnitFlag.ANSHALOCK_1 or BattleUnitFlag.ANSHALOCK_2, 1)
	-- 播放筛子特效
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EFFECT, true, _battleUnit.player.playerId, startGrid.unitId, _effectResId, targetGrid.unitId, _delayTime)
	return true
end

function BattleSkill_Kill:Update( _deltaTime )
	if gBattleFrameCount < self.hitFrame then
		return true
	end
	-- 技能命中时，目标不存在则不作用
	local targetGrid = gBattleRecord:GetBattleUnit(self.targetUnitId)
	if not targetGrid then
		return false
	end
	-- 移除标记
	targetGrid:ClearUnitFlag(self.value < 0 and BattleUnitFlag.ANSHALOCK_1 or BattleUnitFlag.ANSHALOCK_2, 1)
	local targetTower = targetGrid.tower
	if not targetTower then
		return false
	end
	-- 改变星级
	local curStar = targetTower.star
	if curStar == Constants.BATTLE_MAX_STAR and self.value > 0 then
		-- 满星塔加星，不执行
		return false
	end

	local player = targetTower.player
	local posIndex = targetTower.posIndex
	if posIndex ~= 0 then
		-- 移除当前塔
		player:RemoveTowerByFrame(nil, posIndex, FLAGMAP(BattleUnitLeaveType.KILLED))
		-- 添加新塔
		local nextStar = curStar + self.value
		nextStar = nextStar > Constants.BATTLE_MAX_STAR and Constants.BATTLE_MAX_STAR or nextStar
		if nextStar > 0 then
			player:AddTowerByFrame(nil, targetTower.towerRes, nextStar, posIndex, false, BattleTowerAddType.KILLED)
		end
	end
 
	return false
end