---
--- class GBField
-- @classmod GBField
GBField = xclass('GBField')

local table_insert = table.insert
local table_remove = table.remove

---Constructor
function GBField:ctor( ... )
	self.playerId = 0				-- 自己玩家Id
	self.battleType = 0				-- 战斗类型
	self.fieldType = 0				-- 战场类型
	self.battleRes = false			-- 战斗配置
	self.looper = false 			-- 战斗主循环
	self.uBattle = false 			-- 战场组件

	self.gbPlayerList = {}			-- 玩家列表
	self.allGBUnits = {}			-- 单位Map

	self.pressTowerIndex = 0		-- 正在拖动塔

	self.effectIdGenerator = 0
	self.gbEffectList = {}			-- 特效列表
	self.gbSingleEffectMap = {}		-- 单体特效Map

	self.gbTime = 0					-- 显示层时间
	self.isFrameChasing = false		-- 是否正在追帧

	self.isTowersDirty = false		-- 塔列表是否变化
end

function GBField:Finalize( ... )
	-- 销毁特效
	for i = 1, #self.gbEffectList do
		local gbEffect = self.gbEffectList[i]
		if gbEffect then
			gbEffect:Destroy(true)
		end
	end
	-- 销毁玩家
	for i = 1, #self.gbPlayerList do
		self.gbPlayerList[i]:Destroy()
	end
	-- 销毁战场
	if self.uBattle then
		self.uBattle:Destroy()
	end
	self.uBattle = nil
end

function GBField:Initialize( _playerId, _battleType, _uBattle, ... )
	if not _uBattle then
		return
	end

	-- 玩家自己的Id
	self.playerId = _playerId
	self.battleType = _battleType
	self.battleRes = GameResMgr.GetBattleRes(_battleType)
	self.fieldType = self.battleRes.fieldType
	self.uBattle = _uBattle
	self.looper = _uBattle.looper

	-- 特效结束回调
	LUBattleEffect.OnEffectEndCallBack = function( _effectId, _isHit, ... )
		local gbEffect = gGBField:GetGBEffect(_effectId)
		if gbEffect then
			gbEffect:OnEffectEnd(_isHit)
		end
	end 
end

function GBField:Update( _deltaTime, _time, ... )
	-- 时间
	self.gbTime = _time
	-- 逻辑时间
	if not gamebattle.gBattleFreezing then
		local battleTime = gamebattle.gBattleTime
		for i = 1, #self.gbPlayerList do
			self.gbPlayerList[i]:Update(_deltaTime, battleTime)
		end
	end
	if self.isTowersDirty then
		self.isTowersDirty = false
		if self.pressTowerIndex ~= 0 then
			UIUtils.RefreshUIPage('battle', 'RefreshTowerPress')
		end
	end
end

function GBField:IsPlayerSelf( _playerId, ... )
	return self.playerId == _playerId
end

function GBField:AddGBPlayer( _playerId, ... )
	local index = self:IsPlayerSelf(_playerId) and 0 or 1
	local uBattlePlayer = self.uBattle:GetUBattlePlayer(index)
	if not uBattlePlayer then
		return false
	end

	local gbPlayer = GBPlayer()
	if not gbPlayer:Init(_playerId, uBattlePlayer) then
		return false
	end

	table_insert(self.gbPlayerList, gbPlayer)
	self.allGBUnits[gbPlayer.battleUnit.unitId] = gbPlayer
	return true
end

function GBField:GetGBPlayer( _playerId, ... )
	local playerCount = #self.gbPlayerList
	for i = 1, playerCount do
		local gbPlayer = self.gbPlayerList[i]
		if gbPlayer.playerId == _playerId then
			return gbPlayer
		end
	end
	return false
end

function GBField:AddGBTower( _playerId, _towerRes, _star, _posIndex, _tower, _addType, _pendingId, _hasExtraStar, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false, 0
	end
	local gbTower, pendingId = gbPlayer:AddGBTower(_towerRes, _star, _posIndex, _tower, _addType, _pendingId, _hasExtraStar)
	if not gbTower then
		return false, 0
	end
	if gbTower.battleUnit then
		self.allGBUnits[gbTower.battleUnit.unitId] = gbTower
	end
	self.isTowersDirty = true
	return gbTower, pendingId
end

function GBField:RemoveGBTower( _playerId, _posIndex, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local result, unitId = gbPlayer:RemoveGBTower(_posIndex)
	if result and unitId then
		self.allGBUnits[unitId] = nil
	end
	self.isTowersDirty = true
	return result
end

function GBField:ExchangeGBTower( _playerId, _dragIndex, _targetIndex, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local result = gbPlayer:ExchangeGBTower(_dragIndex, _targetIndex)
	return result
end

function GBField:GetGBTower( _playerId, _towerId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:GetGBTower(_towerId)
end

function GBField:OnTowerPendingOver( _playerId, _tower, _pendingId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:OnTowerPendingOver(_tower, _pendingId)
end

function GBField:AddGBMonster( _playerId, _monsterId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local gbMonster = gbPlayer:AddGBMonster(_monsterId)
	if not gbMonster then
		return false
	end
	self.allGBUnits[gbMonster.battleUnit.unitId] = gbMonster
	return gbMonster
end

function GBField:RemoveGBMonster( _playerId, _monsterId, _leaveFlags, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local result, unitId = gbPlayer:RemoveGBMonster(_monsterId, _leaveFlags)
	if result then
		self.allGBUnits[unitId] = nil
	end
	return result
end

function GBField:GetGBMonster( _playerId, _monsterId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:GetGBMonster(_monsterId)
end

function GBField:UpdateMonsterHP( _playerId, _monsterId, _damage, _damageType, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:UpdateGBMonsterHP(_monsterId, _damage, _damageType)
end

function GBField:UpdatePlayerHP( _playerId, _curHP, _maxHP, _isInit, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	UIUtils.RefreshUIPage('battle', 'UpdatePlayerHP', { playerId = _playerId, curHP = _curHP, maxHP = _maxHP, isInit = _isInit })
end

function GBField:MonsterMove( _playerId, _monsterId, _position, _speed, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:GBMonsterMove(_monsterId, _position, _speed)
end

function GBField:AddGBCollider( _playerId, _colliderId, _ownerUnitId, _pendingFrameCount, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local gbCollider = gbPlayer:AddGBCollider(_colliderId, _ownerUnitId, _pendingFrameCount)
	if not gbCollider then
		return false
	end
	self.allGBUnits[gbCollider.battleUnit.unitId] = gbCollider
	return gbCollider
end

function GBField:RemoveGBCollider( _playerId, _colliderId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local result, unitId = gbPlayer:RemoveGBCollider(_colliderId)
	if result then
		self.allGBUnits[unitId] = nil
	end
	return result
end

function GBField:GetGBCollider( _playerId, _colliderId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:GetGBCollider(_colliderId)
end

function GBField:GetGBUnit( _unitId, ... )
	return self.allGBUnits[_unitId] or false
end

function GBField:GenerateEffectId( ... )
	self.effectIdGenerator = self.effectIdGenerator + 1
	return self.effectIdGenerator
end

function GBField:AddGBEffect( _playerId, _gbPlayer, _resId, _gbUnit, _gbTargetUnit, _duration, _eventName, _endCallback, ... )
	local gbPlayer = _gbPlayer or self:GetGBPlayer(_playerId) 
	if not gbPlayer then
		return false
	end
	local effectRes = GameResMgr.GetBattleEffectRes(_resId)
	if not effectRes then
		return false
	end
	local singleKey = ''
	if _gbUnit and effectRes.effectType == EffectType.SINGLE and effectRes.targetType == EffectTargetType.TARGET then
		singleKey = _gbUnit.unitId .. '-' .. effectRes.id
		if self.gbSingleEffectMap[singleKey] then
			self.gbSingleEffectMap[singleKey]:Restart()
			return self.gbSingleEffectMap[singleKey]
		end
	end
	local effectId = self:GenerateEffectId()
	local gbEffect = GBEffect(effectId)
	if not gbEffect:Init(effectRes, _gbUnit, _gbTargetUnit, _duration, _eventName, _endCallback) then
		return false
	end
	table_insert(self.gbEffectList, gbEffect)
	if gbEffect.singleKey then
		self.gbSingleEffectMap[gbEffect.singleKey] = gbEffect
	end
	return gbEffect
end

function GBField:RemoveGBEffect( _effectId, _stopEffect, ... )
	for i = #self.gbEffectList, 1, -1 do
		if self.gbEffectList[i].effectId == _effectId then
			local gbEffect = self.gbEffectList[i]
			if self.gbSingleEffectMap[gbEffect.singleKey] then
				self.gbSingleEffectMap[gbEffect.singleKey] = nil
			end
			table_remove(self.gbEffectList, i)
			gbEffect:Destroy(_stopEffect)
			break
		end
	end
end

function GBField:GetGBEffect( _effectId, ... )
	if _effectId == 0 then
		return false
	end
	for i = 1, #self.gbEffectList do
		local gbEffect = self.gbEffectList[i]
		if gbEffect.effectId == _effectId then
			return gbEffect
		end
	end
	return false
end

function GBField:FireMissile( _unitId, _missile, ... )
	local gbTower = self:GetGBUnit(_unitId)
	if not gbTower then
		return
	end
	gbTower:FireMissile(_missile)
end

function GBField:UpdateTowerTimeScale( _unitId, _timeScale, ... )
	local gbTower = self:GetGBUnit(_unitId)
	if not gbTower then
		return
	end
	gbTower:UpdateTimeScale(_timeScale)
end

function GBField:UpdateStat( ... )
	UIUtils.RefreshUIPage('battle', 'Stat')
end

function GBField:UpdateGrid(_playerId, _gridIndex, _bufferList)
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return
	end
	gbPlayer:UpdateGrid(_gridIndex, _bufferList)
end

-- 追帧优化
-- 暴力追帧期间，单位缓存不创建关联预制体，子弹、瞬时特效不创建，永久特效缓存不创建关联预制体，
-- 暴力追帧结束，缓存单位创建关联预制体，缓存永久特效创建关联预制体
function GBField:SetFrameChasing( _isChasing, ... )
	local isChasing = _isChasing or  false
	if self.isFrameChasing == isChasing then
		return
	end
	self.isFrameChasing = isChasing

	-- 追帧结束
	if not isChasing then
		for i = 1, #self.gbPlayerList do
			self.gbPlayerList[i]:OnFrameChasingOver()
		end
		for i = 1, #self.gbEffectList do
			self.gbEffectList[i]:OnFrameChasingOver()
		end
	end
end

function GBField:UpgradeTower( _playerId, _poolIndex, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return
	end
	gbPlayer:UpgradeTower(_poolIndex)
end

function GBField:OnGBUnitBufferChange( _isAdd, _unitId, _bufferRes, ... )
	local gbUnit = self:GetGBUnit(_unitId)
	if not gbUnit then
		return
	end
	gbUnit:OnBufferChange(_isAdd, _bufferRes)
end

function GBField:OnGBUnitFlagChange( _unitId, _unitFlag, _isAdd, ... )
	local gbUnit = self:GetGBUnit(_unitId)
	if not gbUnit then
		return
	end
	gbUnit:OnUnitFlagChange(_unitFlag, _isAdd)
end

function GBField:FireUnitEvent( _unitId, _eventName,  _eventParam, ... )
	local gbUnit = self:GetGBUnit(_unitId)
	if not gbUnit then
		return
	end
	gbUnit:FireUnitEvent(_eventName, _eventParam)
end

function GBField:ShowDamage( _unitId, _damage, _damageType, ... )
	local gbUnit = self:GetGBUnit(_unitId)
	if not gbUnit then
		return
	end
	gbUnit:ShowDamage(gbUnit, _damage, _damageType)
end

function GBField:Pause( _isPause, ... )
	local isPause = NilDefault(_isPause, true)
	self.looper.isLoopEnable = not isPause
end