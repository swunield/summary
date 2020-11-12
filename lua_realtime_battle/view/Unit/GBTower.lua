---
--- class GBTower
-- @classmod GBTower
class('GBTower', GBUnit)

---Constructor
function GBTower:ctor( ... )
	self.super = Super()

	self.tower = false 				-- 战斗逻辑塔
	self.towerRes = false 			-- 塔配置
	self.gunCount = 0				-- 炮数量
	self.posIndex = 0				-- 塔位置
	self.objTop = false				-- 顶层节点
	self.objBottom = false 			-- 底层节点

	self.gunList = {}				-- 发射源

	self.pendingId = 0				-- 缓冲Id
end

function GBTower:Destroy( ... )
	if self.uBattleUnit then
		UIUtils.ReleasePoolContainer(self.uBattleUnit)
		UIUtils.SetObjectActive(self.uBattleUnit, false)
	end

	-- warn('GBTower Destroy', self.posIndex, self.tower and self.tower.towerId or 0, gamebattle.gBattleManager and gamebattle.gBattleManager:GetBattleFrameCount() or 0)

	-- 父类销毁
	self.super:Destroy()
end

function GBTower:Init( _towerRes, _gunCount, _posIndex, _uBattleTower, _gbPlayer, _tower, ... )
	if not _towerRes or not _uBattleTower or not _gbPlayer then
		return false
	end

	self.tower = NilDefault(_tower, false)
	self.unit = self.tower
	self.towerRes = _towerRes
	self.gunCount = _gunCount
	self.posIndex = _posIndex
	self.uBattleUnit = _uBattleTower
	self.gameObject = self.uBattleUnit.gameObject
	self.transform = self.uBattleUnit.transform
	self.objTop = self.uBattleUnit.objTop
	self.objBottom = self.uBattleUnit.objBottom
	self.gbPlayer = _gbPlayer

	UIUtils.SetObjectActive(self.uBattleUnit, true)
	UIUtils.RefreshPoolContainer(self.uBattleUnit, 'battle/tower', 1, 'tower')

	UIUtils.SetChildText(self.uBattleUnit, 'tower/txt', string.format('%s%d', self.towerRes.name, self.gunCount))
	local color = NilDefault(BattleConstants.BATTLE_TOWER_COLOR_LIST[_towerRes.name], { 0 , 0, 0 })
	UIUtils.SetChildColor(self.uBattleUnit, 'tower/frm', Color(color[1] / 255, color[2] / 255, color[3] / 255, 1))

	if self.tower then
		self.uBattleUnit.unitId = self.tower.unitId
		-- 添加到单位列表
		gGBField.allGBUnits[_tower.unitId] = self
	end

	-- warn('GBTower Init', _posIndex, self.tower and self.tower.towerId or 0, self.gunCount, gamebattle.gBattleManager:GetBattleFrameCount())

	return true
end

function GBTower:Update( _deltaTime, ... )
end

function GBTower:OnPendingOver( _tower, ... )
	if not _tower then
		return
	end
	
	-- 重新初始化一次，同逻辑塔关联
	self:Init(_tower.towerRes, _tower.gunCount, _tower.posIndex, self.uBattleUnit, self.gbPlayer, _tower)
end

function GBTower:CanMerge( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.posIndex == self.posIndex then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	if self:CanExchange(_targetTower) then
		return true, BattleTowerMergeType.EXCHANGE
	end
	if self:CanCopy(_targetTower) then
		return true, BattleTowerMergeType.COPY
	end
	if self:CanFix(_targetTower) then
		return true, BattleTowerMergeType.FIX
	end
	if _targetTower.towerRes.id ~= self.towerRes.id and self.towerRes.birthFlag ~= BattleUnitFlag.FIT and _targetTower.towerRes.birthFlag ~= BattleUnitFlag.FIT then
		return false
	end
	return true, BattleTowerMergeType.MERGE
end

-- 是否可以交换
function GBTower:CanExchange( _targetTower,  ... )
	if not _targetTower then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
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
	if _targetTower.gunCount ~= self.gunCount then
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
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.FIX
end

-- 发射子弹
function GBTower:FireMissile( _gunIndex, _missile, _fireInterval, ... )
	if not self.gunList[_gunIndex] then
		self.gunList[_gunIndex] = {}
	end
	local gbTargetUnit = gGBField:GetGBUnit(_missile.monsterUnitId)
	if not gbTargetUnit then
		return
	end

	local gun = self.gunList[_gunIndex]
	gun.missile = _missile
	gun.fireInterval = _fireInterval
	gun.nextFireTime = gGBField.gbTime + _fireInterval
	gGBField:AddGBEffect(nil, self.gbPlayer, _missile.effectId, self, gbTargetUnit, function( _isHit, ... )

	end)
end

classend()