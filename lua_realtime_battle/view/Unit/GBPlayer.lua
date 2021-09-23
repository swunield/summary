---
--- class GBPlayer
-- @classmod GBPlayer
GBPlayer = xclass('GBPlayer', GBUnit)

local os_clock = os.time
local table_insert = table.insert
local table_remove = table.remove

local SetBattlePlayerField = LUBattlePlayer.SetBattleField
local ShowBattlePlayerDamage = LUBattlePlayer.ShowDamage
local GetGridIndexByPosition = LUBattlePlayer.GetGridIndexByPosition
local SetBattleUnitId = LUBattleUnit.SetUnitId

---Constructor
function GBPlayer:ctor( ... )
	self.playerId = 0					-- 玩家Id
	self.player = false 				-- 玩家
	self.objTopId = 0
	self.objBottomId = 0
	self.objMonsterRoadId = 0

	self.monsterPath = {}				-- 怪物路径，LVector3列表

	self.gbGridList = {}				-- 格子列表
	self.gbTowerList = {}				-- 塔列表
	self.gbMonsterList = {}				-- 怪物列表
	self.gbColliderList = {}			-- 碰撞列表

	self.gridBufferIndexMap = {}		-- 格子状态索引Map
	self.nextBufferIndex = 1			-- 下一个状态索引

	self.pendingGBTowerList = {}		-- 缓冲Tower
	self.nextPendingTowerId = 0			-- 下一个缓冲TowerId

	self.hsCount = 0					-- 火山数量
	self.isHSShowing = false			-- 火山是否显示
	
	self.towerStarMap = {}				-- 塔总星级统计
	self.isTowerStarDirty = false		
end

function GBPlayer:Destroy( ... )
	-- 销毁塔
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbTower = self.gbTowerList[i]
		if gbTower then
			gbTower:Destroy()
		end
	end

	-- 销毁怪物
	for i = 1, #self.gbMonsterList do
		local gbMonster = self.gbMonsterList[i]
		if gbMonster then
			gbMonster:Destroy()
		end
	end

	-- 销毁碰撞
	for i = 1, #self.gbColliderList do
		local gbCollider = self.gbColliderList[i]
		if gbCollider then
			gbCollider:Destroy()
		end
	end

	-- 移出缓存
	SetBattleUnitId(self.unitId, 0)

	-- 父类销毁
	self.super:Destroy()
end

function GBPlayer:Init( _playerId, _uBattlePlayer, ... )
	if not _uBattlePlayer then
		return false
	end

	self.playerId = _playerId
	local player = gamebattle.gBattleRecord:GetBattlePlayer(_playerId)
	if not player then
		return false
	end

	-- 物件
	self.player = player
	_uBattlePlayer.unitId = player.unitId
	self.unitId = player.unitId
	self.objTopId = _uBattlePlayer.objTopId
	self.objBottomId = _uBattlePlayer.objBottomId
	self.objMonsterRoadId = _uBattlePlayer.objMonsterRoadId

	self.battleUnit = player
	self.gbUnit = self
	self.gbPlayer = self

	-- 怪物行进路径
	local path = _uBattlePlayer.monsterPathPointList
	local pointCount = path.Count
	for i = 1, pointCount do
		local point = path[i - 1]
		local lPoint = { x = point.x, y = point.y, z = point.z * BattleConstants.BATTLE_ROAD_LENGTH / Constants.PERCENT_MAX, w = point.w }
		-- print(i, lPoint.x, lPoint.y, lPoint.z, lPoint.w)
		table_insert(self.monsterPath, lPoint)
	end

	-- 初始化格子列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbGrid = GBGrid()
		local gridId = _uBattlePlayer:GetUBattleGridId(i - 1)
		gbGrid:Init(self, i, gridId)
		self.gbGridList[i] = gbGrid
		gGBField.allGBUnits[gbGrid.grid.unitId] = gbGrid
	end

	-- 初始化塔列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		self.gbTowerList[i] = false
	end

	-- 初始化塔点数
	for i = 1, #player.towerPool do
		local towerResId = player.towerPool[i]
		self.towerStarMap[towerResId] = { poolIndex = i, totalStar = 0, nextTotalStar = 0, playerId = self.playerId }
	end

	-- 刷新战场背景
	local fieldId = player.fieldId
	fieldId = fieldId == 0 and 1001 or fieldId
	local isSelfPlayer = gGBField:IsPlayerSelf(self.playerId)
	SetBattlePlayerField(self.unitId, string.format('field/%d/%d_BattleField_%d_%d', fieldId, fieldId, gGBField.battleRes.fieldType, isSelfPlayer and 2 or 1), 'animation/other/prefabs/')

	return true
end

function GBPlayer:Update( _deltaTime, _battleTime, ... )
	-- 塔
	local gbTowerList = self.gbTowerList
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbTower = gbTowerList[i]
		if gbTower then
			gbTower:Update(_deltaTime, _battleTime)
		end
	end

	-- 怪物
	local gbMonsterList = self.gbMonsterList
	local monsterCount = #gbMonsterList
	for i = monsterCount, 1, -1 do
		local gbMonster = gbMonsterList[i]
		if gbMonster then
			gbMonster:Update(_deltaTime)
		end
	end

	-- 火山
	if self.isHSShowing ~= (self.hsCount > 0) then
		self.isHSShowing = self.hsCount > 0
		self:FireUnitEvent(self.isHSShowing and 'OnHuoShanShow' or 'OnHuoShanHide')
	end

	-- 刷新塔总星级
	if self.isTowerStarDirty then
		self.isTowerStarDirty = false
		for towerResId, towerStar in pairs(self.towerStarMap) do
			if towerStar.totalStar ~= towerStar.nextTotalStar then
				towerStar.totalStar = towerStar.nextTotalStar
				RefreshUIPage('battle', 'UpdateTowerStar', towerStar)
			end
		end
	end
end

function GBPlayer:AddGBTower( _towerRes, _star, _posIndex, _tower, _addType, _pendingId, _hasExtraStar, ... )
	if not _towerRes then
		return false, 0
	end

	local gbGrid = self.gbGridList[_posIndex]
	if not gbGrid then
		return false, 0
	end

	local gbTower = GBTower()
	if not gbTower:Init(_towerRes, _star, _posIndex, gbGrid, self, _tower, _addType, nil, _hasExtraStar) then
		return false, 0
	end
	-- 缓冲加入
	if not gbTower.tower then
		if _pendingId and _pendingId ~= 0 then
			gbTower.pendingId = _pendingId
		else
			self.nextPendingTowerId = self.nextPendingTowerId + 1
			gbTower.pendingId = self.nextPendingTowerId
		end
		self.pendingGBTowerList[gbTower.pendingId] = gbTower
	end
	self.gbTowerList[_posIndex] = gbTower
	-- 更新总星数
	self:AddGBTowerStar(_towerRes.id, _star)
	-- 火山
	if _towerRes.birthFlag == BattleUnitFlag.HUOSHAN then
		self:OnHuoShanChange(true)
	end
	return gbTower, gbTower.pendingId
end

function GBPlayer:RemoveGBTower( _posIndex, ... )
	local gbTower = self:GetGBTowerByPos(_posIndex)
	if not gbTower then
		return false, false
	end
	local towerRes = gbTower.towerRes
	local unitId = gbTower.battleUnit and gbTower.battleUnit.unitId or false
	-- 从列表移除
	self.gbTowerList[gbTower.posIndex] = false
	-- 缓冲移除
	if gbTower.pendingId and gbTower.pendingId ~= 0 then
		self.pendingGBTowerList[gbTower.pendingId] = nil
	end
	-- 更新总星数
	self:AddGBTowerStar(towerRes.id, -gbTower.star)
	-- 销毁
	gbTower:Destroy()
	-- 火山
	if towerRes.birthFlag == BattleUnitFlag.HUOSHAN then
		self:OnHuoShanChange(false)
	end
	return true, unitId
end

function GBPlayer:ExchangeGBTower( _dragIndex, _targetIndex, ... )
	local gbDragTower = self:GetGBTowerByPos(_dragIndex)
	local gbTargetTower = self:GetGBTowerByPos(_targetIndex)
	if not gbDragTower or not gbTargetTower then
		return false
	end

	local dragTower = gbDragTower.tower
	local targetTower = gbTargetTower.tower	
	local dragGrid = gbDragTower.gbGrid
	local targetGrid = gbTargetTower.gbGrid

	gbDragTower:Exchange(targetGrid, _targetIndex)
	gbTargetTower:Exchange(dragGrid, _dragIndex)
	self.gbTowerList[_targetIndex] = gbDragTower
	self.gbTowerList[_dragIndex] = gbTargetTower

	gGBField.isTowersDirty = true
end

function GBPlayer:OnTowerPendingOver( _tower, _pendingId, ... )
	local gbTower = self.pendingGBTowerList[_pendingId]
	if not _tower or not gbTower or gbTower.posIndex ~= _tower.posIndex then
		return
	end
	-- 缓冲结束
	gbTower:OnPendingOver(_tower)
	if gbTower.tower and gbTower.pendingId then
		self.pendingGBTowerList[gbTower.pendingId] = nil
		gbTower.pendingId = 0
	end
end

function GBPlayer:GetGBTower( _towerId, ... )
	local gbTowerList = self.gbTowerList
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbTower = gbTowerList[i]
		if gbTower and gbTower.tower and gbTower.tower.towerId == _towerId then
			return gbTower
		end
	end
	return false
end

function GBPlayer:GetGBTowerByPos( _posIndex, ... )
	return self.gbTowerList[_posIndex]
end

function GBPlayer:GetGBGrid( _posIndex, ... )
	return self.gbGridList[_posIndex]
end

function GBPlayer:AddGBMonster( _monsterId, ... )
	local monster = self.player:GetMonster(_monsterId)
	if not monster then
		return false
	end

	local gbMonster = GBMonster()
	if not gbMonster:Init(monster, self) then
		return false
	end

	table_insert(self.gbMonsterList, gbMonster)
	return gbMonster
end

function GBPlayer:RemoveGBMonster( _monsterId, _leaveFlags, ... )
	local gbMonster, index = self:GetGBMonster(_monsterId)
	if not gbMonster then
		return false, false
	end

	local unitId = gbMonster.battleUnit.unitId
	-- 从列表移除
	table_remove(self.gbMonsterList, index)
	-- 销毁
	gbMonster:Destroy(_leaveFlags)

	return true, unitId
end

function GBPlayer:GetGBMonster( _monsterId, ... )
	local gbMonsterList = self.gbMonsterList
	local count = #gbMonsterList
	for i = 1, count do
		local gbMonster = gbMonsterList[i]
		if gbMonster and gbMonster.monster and gbMonster.monster.monsterId == _monsterId then
			return gbMonster, i
		end
	end
	return false, 0
end

-- 伤害跳字预制体
local DamagePrefabMap = { GameStringType.TZPuTong, GameStringType.TZBaoJi, GameStringType.TZDu, GameStringType.TZPoint, GameStringType.TZHeal, GameStringType.TZTDamage }
function GBPlayer:UpdateGBMonsterHP( _monsterId, _damage, _damageType, ... )
	local gbMonster = self:GetGBMonster(_monsterId)
	if not gbMonster then
		return false
	end
	-- 更新血量
	gbMonster:UpdateHP()
	-- 跳字
	local targetUnitId = gbMonster.unitId
	if targetUnitId ~= 0 and not gbMonster:HasSameDamage(_damage, _damageType) then
		ShowBattlePlayerDamage(self.unitId, targetUnitId, _damage > 0 and _damage or -_damage, DamagePrefabMap[_damageType], 0, 0)
	end
	return true
end

function GBPlayer:ShowDamage( _gbUnit, _damage, _damageType, ... )
	if _gbUnit == self then
		return
	end
	local targetUnitId = _gbUnit.unitId
	if targetUnitId ~= 0 and not _gbUnit:HasSameDamage(_damage, _damageType) then
		ShowBattlePlayerDamage(self.unitId, targetUnitId, _damage, DamagePrefabMap[_damageType], 0, 0)
	end
end

function GBPlayer:GBMonsterMove( _monsterId, _position, _speed, ... )
	local gbMonster = self:GetGBMonster(_monsterId)
	if not gbMonster then
		return false
	end
	gbMonster:Move(_position, _speed)
	return true
end

function GBPlayer:AddGBCollider( _colliderId, _ownerUnitId, _pendingFrameCount, ... )
	local collider = self.player:GetCollider(_colliderId)
	if not collider then
		return false
	end

	local gbCollider = GBCollider()
	if not gbCollider:Init(collider, self, _ownerUnitId, _pendingFrameCount) then
		return false
	end

	table_insert(self.gbColliderList, gbCollider)
	return gbCollider
end

function GBPlayer:RemoveGBCollider( _colliderId, ... )
	local gbCollider, index = self:GetGBCollider(_colliderId)
	if not gbCollider then
		return false, false
	end

	local unitId = gbCollider.battleUnit.unitId
	-- 从列表移除
	table_remove(self.gbColliderList, index)
	-- 销毁
	gbCollider:Destroy()

	return true, unitId
end

function GBPlayer:GetGBCollider( _colliderId, ... )
	local gbColliderList = self.gbColliderList
	local count = #gbColliderList
	for i = 1, count do
		local gbCollider = gbColliderList[i]
		if gbCollider and gbCollider.collider and gbCollider.collider.colliderId == _colliderId then
			return gbCollider, i
		end
	end
	return false, 0
end

function GBPlayer:UpdateGrid( _gridIndex, _bufferList, ... )
	local gbGrid = self.gbGridList[_gridIndex]
	if not gbGrid then
		return
	end

	for bufferResId, v in pairs(_bufferList) do
		if not self.gridBufferIndexMap[bufferResId] then
			self.gridBufferIndexMap[bufferResId] = self.nextBufferIndex
			self.nextBufferIndex = self.nextBufferIndex + 1
		end
	end

	gbGrid:UpdateBuffer(_bufferList, self.gridBufferIndexMap)
end

function GBPlayer:GetGridIndexByPosition( _position, ... )
	return GetGridIndexByPosition(self.unitId, _position) + 1
end

function GBPlayer:OnFrameChasingOver( ... )
	local gbTowerList = self.gbTowerList
	for i = 1, #gbTowerList do
		local gbTower = gbTowerList[i]
		if gbTower then
			gbTower:OnFrameChasingOver()
		end
	end
	local gbMonsterList = self.gbMonsterList
	for i = 1, #gbMonsterList do
		local gbMonster = gbMonsterList[i]
		if gbMonster then
			gbMonster:OnFrameChasingOver()
		end
	end
end

function GBPlayer:UpgradeTower( _poolIndex, ... )
	-- 刷新UI
	UIUtils.RefreshUIPage('battle', 'Upgrade', { gbPlayer = self, poolIndex = _poolIndex })
	local towerResId = self.player:GetTowerResIdByPoolIndex(_poolIndex)
	if not towerResId then
		return
	end
	-- 同类型塔播放升级特效
	local gbTowerList = self.gbTowerList
	for i = 1, #gbTowerList do
		local gbTower = gbTowerList[i]
		if gbTower and gbTower.towerRes.id == towerResId then
			-- 升级
			gbTower:OnTowerUpgrade()
		end
	end
end

function GBPlayer:OnHuoShanChange( _isAdd, ... )
	self.hsCount = self.hsCount + (_isAdd and 1 or -1)
end

function GBPlayer:AddGBTowerStar( _towerResId, _star )
	local towerStar = self.towerStarMap[_towerResId]
	towerStar.nextTotalStar = towerStar.nextTotalStar + _star
	self.isTowerStarDirty = true
end

function GBPlayer:UpdateParam( _paramType, _paramValue, ... )
	local gbTowerList = self.gbTowerList
	for i = 1, #gbTowerList do
		local gbTower = gbTowerList[i]
		if gbTower and gbTower.towerRes.paramList[1] == _paramType then
			gbTower:UpdateParam(_paramType, _paramValue)
		end
	end
end