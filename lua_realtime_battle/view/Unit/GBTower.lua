---
--- class GBTower
-- @classmod GBTower
GBTower = xclass('GBTower', GBUnit)

local math_ceil = math.ceil
local os_clock = os.time

local BindTower = LUBattleGrid.BindTower
local UnBindTower = LUBattleGrid.UnBindTower
local SetBattleUnitId = LUBattleUnit.SetUnitId
local FireBattleTower = LUBattleTower.Fire
local SetBattleTowerTimeScale = LUBattleTower.SetTimeScale
local FireBattleGridEvent = LUBattleGrid.FireUnitEvent
local FireTowerBaseEvent = false
pcall(function( ... )
	FireTowerBaseEvent = LUBattleTower.FireBaseEvent
	warn('FireTowerBaseEvent', FireTowerBaseEvent)
end)

---Constructor
function GBTower:ctor( ... )
	self.gbGrid = false

	self.tower = false 				-- 战斗逻辑塔
	self.towerRes = false 			-- 塔配置
	self.star = 0					-- 炮数量
	self.posIndex = 0				-- 塔位置

	self.objTopId = 0				-- TopObjId

	self.pendingId = 0				-- 缓冲Id
	self.updateExcutor = false 		-- 更新回调

	self.growStage = 0				-- 成长阶段
end

function GBTower:Destroy( ... )
	-- 父类销毁
	self.super:Destroy()

	if self.gbGrid.unitId ~= 0 and self.unitId ~= 0 then
		UnBindTower(self.gbGrid.unitId, GameStringType.OnTowerLeave)
	end
end

local TowerAddEvents = 
{
[BattleTowerAddType.ALL] = GameStringType.OnTowerBorn,
	[BattleTowerAddType.GROWUP] = GameStringType.OnTowerGrowUp,
	[BattleTowerAddType.MERGE] = GameStringType.OnTowerMerge,
	[BattleTowerAddType.REPRODUCE] = GameStringType.OnTowerFanyan,
	[BattleTowerAddType.ROLL] = GameStringType.OnTowerBorn,
	[BattleTowerAddType.FIX] = GameStringType.OnTowerFix,
	[BattleTowerAddType.COPY] = GameStringType.OnTowerCopy,
	[BattleTowerAddType.STARUP] = GameStringType.OnTowerMerge,
	[BattleTowerAddType.STARDOWN] = GameStringType.OnTowerMerge,
	[BattleTowerAddType.EXCHANGE] = GameStringType.OnTowerExchange,
	[BattleTowerAddType.STARBALL] = GameStringType.OnTowerBossStarBall,
	[BattleTowerAddType.DICE] = GameStringType.OnTowerBossDice,
	[BattleTowerAddType.REBUILD] = GameStringType.OnTowerRebuild,
	[BattleTowerAddType.KILLED] = GameStringType.Empty,
	[BattleTowerAddType.KILL] = GameStringType.OnTowerKill_1,
}

local TowerUpdateSwitcher = {
	-- 成长
	[1025] = function( self, _battleTime, ... )
		local tower = self.tower
		local lastStar = tower.starList[tower.star]
		local extraSpeed = tower.starExtraSpeed
		local curStage = math_ceil((_battleTime - lastStar.nextExtraFireTime - lastStar.extraFreezeTime) / (extraSpeed / 4))
		if self.growStage ~= curStage then
			self.growStage = curStage
			self:FireUnitEvent(GameStringType.GrowUp_1 + curStage - 1)
		end
	end
}

local GBTowerReConnectSwitcher = {
	-- 时钟
	[1038] = function( self )
		local bufferResId = self.towerRes.id * 10 + 1
		self:FireUnitEvent(GameStringType.SZPoint, { value = bufferResId }, true)
	end
}

function GBTower:Init( _towerRes, _star, _posIndex, _gbGrid, _gbPlayer, _tower, _addType, _isPendingOver, _hasExtraStar, ... )
	if not _towerRes or not _gbGrid or not _gbPlayer then
		return false
	end

	self.tower = _tower or false
	self.battleUnit = self.tower
	self.gbUnit = self
	if not _isPendingOver then
		self.towerRes = _towerRes
		self.star = _star
		self.posIndex = _posIndex
		self.gbGrid = _gbGrid
		self.gbPlayer = _gbPlayer
	end

	if _tower then
		-- 添加到单位列表
		gGBField.allGBUnits[_tower.unitId] = self
	end

	self:CheckFrameChasing('Init', function( ... )
		if not _isPendingOver or self.unitId == 0 then
			local addType = _addType or BattleTowerAddType.ALL
			local addEvent = addType == BattleTowerAddType.KILL and (GameStringType.OnTowerKill_1 + gGBField.fieldType - 1) or TowerAddEvents[addType] or GameStringType.OnTowerBorn
			self.unitId = BindTower(self.gbGrid.unitId, self.towerRes.prefabName, GameStringType.TowerPath, self.star, GameStringType.OnTowerEnter, _hasExtraStar and GameStringType.OnTowerExtraStar or addEvent)
			if _hasExtraStar and addType == BattleTowerAddType.KILL then
				FireBattleGridEvent(self.gbGrid.unitId, addEvent)
			end
			if _towerRes.birthFlag == BattleUnitFlag.COMBO then
				self.objTopId = ObjectCache.GetComponent(self.unitId, false).objTopId
				self:UpdateParam(BattleParamType.COMBO, self.gbPlayer.player:GetParamValue(BattleParamType.COMBO))
			end
			self:CheckAllUnitFlag()
			-- 觉醒
			local _, awakenIndex = _gbPlayer.player:GetTowerAwaken(_towerRes.id)
			self:SetAwaken(awakenIndex > 0)
		end
		if self.tower then
			self.updateExcutor = TowerUpdateSwitcher[self.tower.towerRes.baseId] or false
			SetBattleUnitId(self.unitId, self.tower.unitId)
			self.unitId = self.tower.unitId
			-- 断线重连
			if not _isPendingOver then
				local switcher = GBTowerReConnectSwitcher[_towerRes.baseId]
				if switcher then
					switcher(self)
				end
			end
		end
	end)

	return true
end

function GBTower:Update( _deltaTime, _battleTime, ... )
	local updateExcutor = self.updateExcutor
	if updateExcutor then
		updateExcutor(self, _battleTime)
	end
end

function GBTower:OnPendingOver( _tower, ... )
	if not _tower then
		return
	end
	
	-- 重新初始化一次，同逻辑塔关联
	self:Init(_tower.towerRes, _tower.star, _tower.posIndex, self.gbGrid, self.gbPlayer, _tower, nil, true)
end

function GBTower:Exchange( _gbGrid, _posIndex, ... )
	self.gbGrid = _gbGrid
	BindTower(_gbGrid.unitId, self.unitId, true, TowerAddEvents[BattleTowerAddType.EXCHANGE], 0)
	self.posIndex = _posIndex
end

local MergeFlagMap = { 
	[BattleUnitFlag.REPRODUCE] = BattleUnitFlag.REPRODUCE, 
	[BattleUnitFlag.SUMMON] = BattleUnitFlag.SUMMON, 
	[BattleUnitFlag.COMBO] = BattleUnitFlag.COMBO,  
	[BattleUnitFlag.KILL] = BattleUnitFlag.KILL,
	[BattleUnitFlag.HACKER] = BattleUnitFlag.HACKER
}
function GBTower:CanMerge( _targetTower, ... )
	if not _targetTower then
		return false, nil, 0
	end
	if _targetTower.posIndex == self.posIndex then
		return false, nil, 0
	end
	if _targetTower.star ~= self.star then
		return false, nil, 0
	end
	if self:CanExchange(_targetTower) then
		return true, BattleTowerMergeType.EXCHANGE, 0
	end
	if self:CanCopy(_targetTower) then
		return true, BattleTowerMergeType.COPY, 0
	end
	if self:CanRebuild(_targetTower) then
		return true, BattleTowerMergeType.REBUILD, 0
	end
	-- 已满级
	if self.star == Constants.BATTLE_MAX_STAR then
		return false, nil, 0
	end
	if self:CanFix(_targetTower) then
		return true, BattleTowerMergeType.FIX, 0
	end
	if _targetTower.towerRes.id ~= self.towerRes.id and self.towerRes.birthFlag ~= BattleUnitFlag.FIT and _targetTower.towerRes.birthFlag ~= BattleUnitFlag.FIT then
		return false, nil, 0
	end
	local mergeUnitFlag = MergeFlagMap[self.towerRes.birthFlag] or MergeFlagMap[_targetTower.towerRes.birthFlag] or 0
	return true, BattleTowerMergeType.MERGE, mergeUnitFlag
end

-- 是否可以交换
function GBTower:CanExchange( _targetTower,  ... )
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.EXCHANGE
end

-- 是否可以复制
function GBTower:CanCopy( _targetTower, ... )
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.COPY
end

-- 是否可以营养
function GBTower:CanFix( _targetTower, ... )
	-- 已满级
	if self.star == Constants.BATTLE_MAX_STAR then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.FIX
end

-- 是否可以重构
function GBTower:CanRebuild( _targetTower, ... )
	return gamebattle.HasBattleFlag(self.tower.unitFlag, BattleUnitFlag.REBUILD)
end

-- 发射子弹
function GBTower:FireMissile( _missile, ... )
	if self.unitId == 0 then
		return
	end
	local gbTargetUnit = gGBField:GetGBUnit(_missile.targetUnitId)
	if not gbTargetUnit or gbTargetUnit.unitId == 0 then
		return
	end

	-- 自动转向
	FireBattleTower(self.unitId, _missile.starIndex, gbTargetUnit.unitId, GameStringType.OnFire)
	-- 添加特效
	local duration = (_missile.hitFrame - gamebattle.gBattleFrameCount) * Constants.BATTLE_FRAME_TIME
	gGBField:AddGBEffect(nil, self.gbPlayer, _missile.effectId, self, gbTargetUnit, duration, nil, function( _isHit, ... )

	end)
end

function GBTower:SetGrey( _isGrey, ... )
	if self.unitId == 0 then
		return
	end
	local isGrey = NilDefault(_isGrey, true)
	FireBattleGridEvent(self.gbGrid.unitId, isGrey and GameStringType.OnShowGrey or GameStringType.OnHideGrey)
end

function GBTower:UpdateTimeScale( _timeScale, ... )
	self:CheckFrameChasing('UpdateTimeScale', function( ... )
		if self.unitId == 0 then
			return
		end
		SetBattleTowerTimeScale(self.unitId, _timeScale)
	end)
end

function GBTower:OnTowerUpgrade( ... )
	FireBattleGridEvent(self.gbGrid.unitId, GameStringType.OnTowerLevelUp)
end

-- 状态变化
local UnitFlagChangeSwitcher = 
{
	-- 禁锢
	[BattleUnitFlag.SILENCE] = function( self, _isAdd, ... )
		FireBattleGridEvent(self.gbGrid.unitId, _isAdd and GameStringType.OnSilenceAdd or GameStringType.OnSilenceRemove)
		return true
	end,
	-- 进阶
	[BattleUnitFlag.ADVANCE] = function( self, _isAdd,  ... )
		return self:FireUnitEvent(_isAdd and GameStringType.OnSkill or GameStringType.OnNormal)
	end,
	-- 重构
	[BattleUnitFlag.REBUILD] = function( ... )
		gGBField.isTowersDirty = true
	end
}

function GBTower:OnUnitFlagChange( _unitFlag, _isAdd )
	local switcher = UnitFlagChangeSwitcher[_unitFlag]
	if switcher then
		local result = switcher(self, _isAdd)
		if _isAdd then
			self.unitFlagMap[_unitFlag] = result and 1 or -1
		else
			self.unitFlagMap[_unitFlag] = not result and 0 or nil 
		end
	end
end

local ParamSwitcher = {
	-- 连击
	[BattleParamType.COMBO] = function( self, _paramValue, ... )
		OCUtils.SetText(self.objTopId, 1, string.format('%02d', _paramValue or 0))
	end
}

function GBTower:UpdateParam( _paramType, _paramValue, ... )
	local switcher = ParamSwitcher[_paramType]
	if switcher then
		switcher(self, _paramValue)
	end
end

function GBTower:SetAwaken( _isAwaken )
	if FireTowerBaseEvent then
		FireTowerBaseEvent(self.unitId, _isAwaken and 'OnAwaken' or 'OnNormal')
		return
	end
	local uBattleTower = ObjectCache.GetComponent(self.unitId, false)
	if not uBattleTower then
		return
	end
	local uTowerBase = uBattleTower.uTowerBase
	local uiBaseEvent = UIUtils.GetObjectComponent(uTowerBase, UIEvent)
	uiBaseEvent:FireUIEvent(_isAwaken and 'OnAwaken' or 'OnNormal')
end