---
--- class GBField
-- @classmod GBField
class('GBField')

---Constructor
function GBField:ctor( ... )
	self.playerId = 0				-- 自己玩家Id
	self.looper = false 			-- 战斗朱循环
	self.uBattle = false 			-- 战场组件

	self.gbPlayerList = {}			-- 玩家列表
	self.allGBUnits = {}			-- 单位Map

	self.effectIdGenerator = 0
	self.gbEffectList = {}			-- 特效列表

	self.gbTime = 0					-- 显示层时间		
end

function GBField:Finalize( ... )
	if self.looper then
		-- 停止主循环
		GOUtils.SetLoopCallBack(self.looper.gameObject, nil)
		self.looper = false
	end
	-- 销毁特效
	for i = 1, #self.gbEffectList do
		local gbEffect = self.gbEffectList[i]
		if gbEffect then
			gbEffect:Destroy()
		end
	end
	-- 销毁玩家
	for i = 1, #self.gbPlayerList do
		self.gbPlayerList[i]:Destroy()
	end
	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBField:Initialize( _playerId, _uBattle, ... )
	if not _uBattle then
		return
	end

	-- 玩家自己的Id
	self.playerId = _playerId
	self.uBattle = _uBattle
	self.looper = _uBattle.looper

	-- 启动主循环
	GOUtils.ResetLoop(self.looper.gameObject)
	GOUtils.SetLoopCallBack(self.looper.gameObject, function( _delta, _time, ... )
		GBMain.INSTANCE():Update(_delta, _time)
	end)
end

function GBField:Update( _deltaTime, _time, ... )
	-- 时间
	self.gbTime = _time

	for i = 1, #self.gbPlayerList do
		self.gbPlayerList[i]:Update(_deltaTime)
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
	self.allGBUnits[gbPlayer.unit.unitId] = gbPlayer
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

function GBField:AddGBTower( _playerId, _towerRes, _gunCount, _posIndex, _tower, _pendingId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false, 0
	end
	local gbTower, pendingId = gbPlayer:AddGBTower(_towerRes, _gunCount, _posIndex, _tower, _pendingId)
	if not gbTower then
		return false, 0
	end
	if gbTower.unit then
		self.allGBUnits[gbTower.unit.unitId] = gbTower
	end
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
	self.allGBUnits[gbMonster.unit.unitId] = gbMonster
	return gbMonster
end

function GBField:RemoveGBMonster( _playerId, _monsterId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local result, unitId = gbPlayer:RemoveGBMonster(_monsterId)
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

function GBField:UpdateMonsterHP( _playerId, _monsterId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:UpdateGBMonsterHP(_monsterId)
end

function GBField:MonsterMove( _playerId, _monsterId, _position, _speed, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	return gbPlayer:GBMonsterMove(_monsterId, _position, _speed)
end

function GBField:AddGBCollider( _playerId, _colliderId, _ownerUnitId, ... )
	local gbPlayer = self:GetGBPlayer(_playerId)
	if not gbPlayer then
		return false
	end
	local gbCollider = gbPlayer:AddGBCollider(_colliderId, _ownerUnitId)
	if not gbCollider then
		return false
	end
	self.allGBUnits[gbCollider.unit.unitId] = gbCollider
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
	return NilDefault(self.allGBUnits[_unitId], false)
end

function GBField:GenerateEffectId( ... )
	self.effectIdGenerator = self.effectIdGenerator + 1
	return self.effectIdGenerator
end

function GBField:AddGBEffect( _playerId, _gbPlayer, _resId, _gbUnit, _gbTargetUnit, _endCallback, ... )
	local gbPlayer = NilDefault(_gbPlayer, self:GetGBPlayer(_playerId)) 
	if not gbPlayer then
		return false
	end
	local effectRes = GameResMgr.GetBattleEffectRes(_resId)
	if not effectRes then
		return false
	end
	local effectId = self:GenerateEffectId()
	local gbEffect = GBEffect(effectId)
	if not gbEffect:Init(effectRes, _gbUnit, _gbTargetUnit, _endCallback) then
		return false
	end
	table_insert(self.gbEffectList, gbEffect)
	return gbEffect
end

function GBField:RemoveGBEffect( _effectId, ... )
	for i = #self.gbEffectList, 1, -1 do
		if self.gbEffectList[i].effectId == _effectId then
			self.gbEffectList[i]:Destroy()
			table_remove(self.gbEffectList, i)
			break
		end
	end
end

function GBField:FireMissile( _unitId, _gunIndex, _missile, _nextFireTime, ... )
	local gbTower = self:GetGBUnit(_unitId)
	if not gbTower then
		return
	end
	gbTower:FireMissile(_gunIndex, _missile, _nextFireTime)
end

function GBField:AddMagic( _playerId, _magicIndex, _magicData, ... )
	if self.playerId ~= _playerId then
		return
	end
	UIUtils.RefreshUIPage('battle', 'AddMagic', { magicIndex = _magicIndex, magicData = _magicData } )
end

function GBField:UpdateMagic( _playerId, _magicIndex, _magicData, ... )
if self.playerId ~= _playerId then
		return
	end
	UIUtils.RefreshUIPage('battle', 'UpdateMagic', { magicIndex = _magicIndex, magicData = _magicData } )
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

classend()