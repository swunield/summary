---
--- class GBTower
-- @classmod GBTower
class('GBTower', GBUnit)

---Constructor
function GBTower:ctor( ... )
	self.super = Super()

	self.uBattleGrid = false

	self.tower = false 				-- 战斗逻辑塔
	self.towerRes = false 			-- 塔配置
	self.star = 0				-- 炮数量
	self.posIndex = 0				-- 塔位置

	self.pendingId = 0				-- 缓冲Id
end

function GBTower:Destroy( ... )
	if self.uBattleGrid and self.uBattleUnit then
		self.uBattleGrid:UnBindTower('OnTowerLeave')
	end

	-- 父类销毁
	self.super:Destroy()
end

local TowerAddEvents = 
{
	[BattleTowerAddType.ALL] = 'OnTowerBorn',
	[BattleTowerAddType.GROWUP] = 'OnTowerGrowUp',
	[BattleTowerAddType.MERGE] = 'OnTowerMerge',
	[BattleTowerAddType.REPRODUCE] = 'OnTowerFanyan',
	[BattleTowerAddType.ROLL] = 'OnTowerBorn',
	[BattleTowerAddType.FIX] = 'OnTowerFix',
	[BattleTowerAddType.COPY] = 'OnTowerCopy',
	[BattleTowerAddType.STARUP] = 'OnTowerMerge',
	[BattleTowerAddType.STARDOWN] = 'OnTowerMerge',
	[BattleTowerAddType.EXCHANGE] = 'OnTowerExchange',
}

function GBTower:Init( _towerRes, _star, _posIndex, _uBattleGrid, _gbPlayer, _tower, _addType, _isPendingOver, ... )
	if not _towerRes or not _uBattleGrid or not _gbPlayer then
		return false
	end

	self.tower = _tower or false
	self.battleUnit = self.tower
	self.gbUnit = self
	if not _isPendingOver then
		self.towerRes = _towerRes
		self.star = _star
		self.posIndex = _posIndex
		self.uBattleGrid = _uBattleGrid
		self.gbPlayer = _gbPlayer
	end

	self:CheckFrameChasing('Init', function( ... )
		if not _isPendingOver then
			local addType = _addType or BattleTowerAddType.ALL
			self.uBattleUnit = self.uBattleGrid:BindTower('animation/other/prefabs/tower/' .. _towerRes.prefabName, TowerAddEvents[addType])
			self.uBattleUnit:BindGameLoop(gGBField.looper)
			self.uBattleUnit:SetLevel(_star)
			self.gameObject = self.uBattleUnit.gameObject
			self.transform = self.uBattleUnit.transform
		end
		if self.tower then
			self.uBattleGrid.unitId = self.tower.unitId
			self.uBattleUnit.unitId = self.tower.unitId
			-- 添加到单位列表
			gGBField.allGBUnits[_tower.unitId] = self
		end
	end)

	return true
end

function GBTower:Update( _deltaTime, ... )
end

function GBTower:OnPendingOver( _tower, ... )
	if not _tower then
		return
	end
	
	-- 重新初始化一次，同逻辑塔关联
	self:Init(_tower.towerRes, _tower.star, _tower.posIndex, self.uBattleGrid, self.gbPlayer, _tower, true)
end

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
	local mergeUnitFlag = 0
	if self.towerRes.birthFlag == BattleUnitFlag.REPRODUCE or _targetTower.towerRes.birthFlag == BattleUnitFlag.REPRODUCE then
		mergeUnitFlag = BattleUnitFlag.REPRODUCE
	elseif self.towerRes.birthFlag == BattleUnitFlag.SUMMON or _targetTower.towerRes.birthFlag == BattleUnitFlag.SUMMON then
		mergeUnitFlag = BattleUnitFlag.SUMMON
	end
	return true, BattleTowerMergeType.MERGE, mergeUnitFlag
end

-- 是否可以交换
function GBTower:CanExchange( _targetTower,  ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.EXCHANGE
end

-- 是否可以复制
function GBTower:CanCopy( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.COPY
end

-- 是否可以营养
function GBTower:CanFix( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	-- 已满级
	if self.star == Constants.BATTLE_MAX_STAR then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.FIX
end

-- 发射子弹
function GBTower:FireMissile( _missile, ... )
	if not self.uBattleUnit then
		return
	end
	local gbTargetUnit = gGBField:GetGBUnit(_missile.targetUnitId)
	if not gbTargetUnit or not gbTargetUnit.uBattleUnit then
		return
	end

	-- 自动转向
	self.uBattleUnit:Fire(_missile.starIndex, gbTargetUnit.uBattleUnit, 'OnFire')
	-- 添加特效
	local duration = (_missile.hitFrame - gamebattle.gBattleFrameCount) * Constants.BATTLE_FRAME_TIME
	gGBField:AddGBEffect(nil, self.gbPlayer, _missile.effectId, self, gbTargetUnit, duration, function( _isHit, ... )

	end)
end

function GBTower:ShowCover( _isShow, _eventName, ... )
	if not self.uBattleUnit then
		return
	end
	local isShow = NilDefault(_isShow, true)
	self.uBattleGrid:ShowCover(isShow, _eventName)
end

function GBTower:UpdateTimeScale( _timeScale, ... )
	self:CheckFrameChasing('UpdateTimeScale', function( ... )
		if not self.uBattleUnit then
			return
		end
		self.uBattleUnit:SetTimeScale(_timeScale)
	end)
end

function GBTower:OnTowerUpgrade( ... )
	self.uBattleGrid:FireUnitEvent('OnTowerLevelUp')
end

classend()