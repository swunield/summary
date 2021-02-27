---
--- class GBPlayer
-- @classmod GBPlayer
class('GBPlayer', GBUnit)

---Constructor
function GBPlayer:ctor( ... )
	self.super = Super()

	self.playerId = 0					-- 玩家Id
	self.player = false 				-- 玩家
	self.objMonsterRoad = false 		-- 怪物路径物件
	self.objTopRoad = false				-- 怪物路径顶层
	self.objBottomRoad = false			-- 怪物路径底层
	self.objTop	 = false				-- 顶层节点
	self.objBottom = false 				-- 底层节点
	self.monsterPath = {}				-- 怪物路径，LVector3列表

	self.gbGridList = {}				-- 格子列表
	self.gbTowerList = {}				-- 塔列表
	self.gbMonsterList = {}				-- 怪物列表
	self.gbColliderList = {}			-- 碰撞列表

	self.gridBufferIndexMap = {}		-- 格子状态索引Map
	self.nextBufferIndex = 1			-- 下一个状态索引

	self.pendingGBTowerList = {}			-- 缓冲Tower
	self.nextPendingTowerId = 0			-- 下一个缓冲TowerId
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

	-- 父类销毁
	self.super:Destroy()
end

function GBPlayer:Init( _playerId, _uBattlePlayer, ... )
	if not _uBattlePlayer then
		return false
	end

	self.playerId = _playerId
	self.player = gamebattle.gBattleRecord:GetBattlePlayer(_playerId)
	if not self.player then
		return false
	end

	-- 物件
	self.uBattleUnit = _uBattlePlayer
	self.uBattleUnit.unitId = self.player.unitId
	self.objMonsterRoad = _uBattlePlayer.objMonsterRoad
	self.objTop = _uBattlePlayer.objTop
	self.objBottom = _uBattlePlayer.objBottom

	self.battleUnit = self.player
	self.gbUnit = self
	self.gbPlayer = self

	-- 怪物行进路径
	local path = _uBattlePlayer.monsterPathPointList
	local pointCount = path.Count
	for i = 1, pointCount do
		local point = path[i - 1]
		local lPoint = LVector3(point.x, point.y, point.z * BattleConstants.BATTLE_ROAD_LENGTH / Constants.PERCENT_MAX)
		warn(i, lPoint.x, lPoint.y, lPoint.z)
		table.insert(self.monsterPath, lPoint)
	end

	-- 初始化格子列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbGrid = GBGrid()
		local uBattleGrid = _uBattlePlayer:GetUBattleGrid(i - 1)
		gbGrid:Init(self, i, uBattleGrid)
		self.gbGridList[i] = gbGrid
	end

	-- 初始化塔列表
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		self.gbTowerList[i] = false
	end

	return true
end

function GBPlayer:Update( _deltaTime, ... )
	-- 塔
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbTower = self.gbTowerList[i]
		if gbTower then
			gbTower:Update(_deltaTime)
		end
	end

	-- 怪物
	local monsterCount = #self.gbMonsterList
	for i = monsterCount, 1, -1 do
		local gbMonster = self.gbMonsterList[i]
		if gbMonster then
			gbMonster:Update(_deltaTime)
		end
	end
end

function GBPlayer:AddGBTower( _towerRes, _star, _posIndex, _tower, _addType, _pendingId, ... )
	if not _towerRes then
		return false, 0
	end

	local uBattleGrid = self.uBattleUnit:GetUBattleGrid(_posIndex - 1)
	if not uBattleGrid then
		return false, 0
	end

	local gbTower = GBTower()
	if not gbTower:Init(_towerRes, _star, _posIndex, uBattleGrid, self, _tower, _addType) then
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
	return gbTower, gbTower.pendingId
end

function GBPlayer:RemoveGBTower( _posIndex, ... )
	local gbTower = self:GetGBTowerByPos(_posIndex)
	if not gbTower then
		return false, false
	end

	local unitId = gbTower.battleUnit and gbTower.battleUnit.unitId or false
	-- 从列表移除
	self.gbTowerList[gbTower.posIndex] = false
	-- 缓冲移除
	if gbTower.pendingId and gbTower.pendingId ~= 0 then
		self.pendingGBTowerList[gbTower.pendingId] = nil
	end
	-- 销毁
	gbTower:Destroy()

	return true, unitId
end

function GBPlayer:ExchangeGBTower( _dragIndex, _targetIndex, ... )
	local gbDragTower = self:GetGBTowerByPos(_dragIndex)
	local gbTargetTower = self:GetGBTowerByPos(_targetIndex)
	if not gbDragTower or not gbTargetTower then
		return false
	end
	local dragTowerRes = gbDragTower.towerRes
	local targetTowerRes = gbTargetTower.towerRes
	local dragTowerStar = gbDragTower.star
	local targetTowerStar = gbTargetTower.star
	local dragTowerPendingId = gbDragTower.pendingId
	local targetTowerPendingId = gbTargetTower.pendingId

	local dragTower = gbDragTower.tower
	local targetTower = gbTargetTower.tower	
	-- 移除塔
	gGBField:RemoveGBTower(self.playerId, _dragIndex)
	gGBField:RemoveGBTower(self.playerId, _targetIndex)
	-- 添加塔
	gGBField:AddGBTower(self.playerId, dragTowerRes, dragTowerStar, _targetIndex, dragTower, BattleTowerAddType.EXCHANGE, dragTowerPendingId)
	gGBField:AddGBTower(self.playerId, targetTowerRes, targetTowerStar, _dragIndex, targetTower, BattleTowerAddType.EXCHANGE, targetTowerPendingId)
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
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbTower = self.gbTowerList[i]
		if gbTower and gbTower.tower and gbTower.tower.towerId == _towerId then
			return gbTower
		end
	end
	return false
end

function GBPlayer:GetGBTowerByPos( _posIndex, ... )
	return self.gbTowerList[_posIndex]
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

	table.insert(self.gbMonsterList, gbMonster)
	return gbMonster
end

function GBPlayer:RemoveGBMonster( _monsterId, ... )
	local gbMonster, index = self:GetGBMonster(_monsterId)
	if not gbMonster then
		return false, false
	end

	local unitId = gbMonster.battleUnit.unitId
	-- 从列表移除
	table.remove(self.gbMonsterList, index)
	-- 销毁
	gbMonster:Destroy()

	return true, unitId
end

function GBPlayer:GetGBMonster( _monsterId, ... )
	local count = #self.gbMonsterList
	for i = 1, count do
		local gbMonster = self.gbMonsterList[i]
		if gbMonster and gbMonster.monster and gbMonster.monster.monsterId == _monsterId then
			return gbMonster, i
		end
	end
	return false, 0
end

-- 伤害跳字预制体
local DamagePrefabMap = { 'battle/tiaozi_putong', 'battle/tiaozi_baoji', 'battle/tiaozi_zhongdu', 'battle/tiaozi_sp' }
function GBPlayer:UpdateGBMonsterHP( _monsterId, _damage, _damageType, ... )
	local gbMonster = self:GetGBMonster(_monsterId)
	if not gbMonster then
		return false
	end
	-- 更新血量
	gbMonster:UpdateHP()
	-- 跳字
	if gbMonster.uBattleUnit and not gbMonster:HasSameDamage(_damage, _damageType) then
		self.uBattleUnit:ShowDamage(gbMonster.uBattleUnit, _damage, DamagePrefabMap[_damageType], nil, nil)
	end
	return true
end

function GBPlayer:ShowDamage( _gbUnit, _damage, _damageType, ... )
	if _gbUnit == self then
		return
	end
	local uBattleUnit = _gbUnit.uBattleUnit
	if uBattleUnit and not _gbUnit:HasSameDamage(_damage, _damageType) then
		self.uBattleUnit:ShowDamage(uBattleUnit, _damage, DamagePrefabMap[_damageType], nil, nil)
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

function GBPlayer:AddGBCollider( _colliderId, ... )
	local collider = self.player:GetCollider(_colliderId)
	if not collider then
		return false
	end

	local gbCollider = GBCollider()
	if not gbCollider:Init(collider, self) then
		return false
	end

	table.insert(self.gbColliderList, gbCollider)
	return gbCollider
end

function GBPlayer:RemoveGBCollider( _colliderId, ... )
	local gbCollider, index = self:GetGBCollider(_colliderId)
	if not gbCollider then
		return false, false
	end

	local unitId = gbCollider.battleUnit.unitId
	-- 从列表移除
	table.remove(self.gbColliderList, index)
	-- 销毁
	gbCollider:Destroy()

	return true, unitId
end

function GBPlayer:GetGBCollider( _colliderId, ... )
	local count = #self.gbColliderList
	for i = 1, count do
		local gbCollider = self.gbColliderList[i]
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
	return self.uBattleUnit:GetGridIndexByPosition(_position) + 1
end

function GBPlayer:OnFrameChasingOver( ... )
	for i = 1, #self.gbTowerList do
		local gbTower = self.gbTowerList[i]
		if gbTower then
			gbTower:OnFrameChasingOver()
		end
	end
	for i = 1, #self.gbMonsterList do
		local gbMonster = self.gbMonsterList[i]
		if gbMonster then
			gbMonster:OnFrameChasingOver()
		end
	end
end

function GBPlayer:UpgradeTower( _poolIndex, ... )
	local towerResId = self.player:GetTowerResIdByPoolIndex(_poolIndex)
	if not towerResId then
		return
	end
	-- 刷新UI
	UIUtils.RefreshUIPage('battle', 'Upgrade', { gbPlayer = self, pooIndex = _poolIndex })
	-- 同类型塔播放升级特效
	for i = 1, #self.gbTowerList do
		local gbTower = self.gbTowerList[i]
		if gbTower and gbTower.towerRes.id == towerResId then
			-- 升级
			gbTower:OnTowerUpgrade()
		end
	end
end

classend()