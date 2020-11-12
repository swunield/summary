---
--- class BattleGrid
-- @classmod BattleGrid
class('BattleGrid', BattleUnit)

---Constructor
function BattleGrid:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.GRID

	self.gridIndex = 0				-- 格子索引
	self.tower = false				-- 关联Tower
end

function BattleGrid:Destroy( _leaveType, ... )
	self.carryBufferList = {}
	self.tower = false
end

function BattleGrid:Init( _gridIndex, _player, ... )
	self.gridIndex = _gridIndex
	self.player = _player
	self.unitId = self:GenerateUnitId(self.gridIndex)

	return true
end

function BattleGrid:OnTowerEnter( _tower, ... )
	if self.tower then
		self:OnTowerLeave(self.tower)
	end
	self.tower = _tower

	-- 格子持有的所有Buffer全部添加到塔
	for i = 1, #self.carryBufferList do
		local buffer = self.carryBufferList[i]
		for n = 1, #buffer.layerList do
			local layer = buffer.layerList[n]
			local towerBuffer = self.tower:AddBuffer(buffer.bufferRes.id, layer.ownerUnit)
			if towerBuffer then
				buffer.bindBufferId = towerBuffer.bufferId
			end
		end
	end
end

function BattleGrid:OnTowerLeave( _tower, ... )
	if not _tower or not self.tower or self.tower ~= _tower then
		return
	end

	-- 通过格子添加的Buffer全部移除
	for i = 1, #self.carryBufferList do
		local buffer = self.carryBufferList[i]
		self.tower:RemoveBufferByBufferId(buffer.bindBufferId)
		buffer.bindBufferId = 0
	end

	self.tower = false
end

function BattleGrid:OnBufferAdd( _buffer, ... )
	-- 已存在塔
	if self.tower then
		local towerBuffer = self.tower:AddBuffer(_buffer.bufferRes.id, _buffer.ownerUnit)
		if towerBuffer then
			_buffer.bindBufferId = towerBuffer.bufferId
		end
	end

	-- 通知前端刷新格子
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.GRIDUPDATE, self.player.playerId, self.gridIndex, self.carryBufferList)
end

function BattleGrid:OnBufferRemove( _buffer, ... )
	-- 已存在塔
	if self.tower then
		self.tower:RemoveBufferByBufferId(_buffer.bindBufferId)
		_buffer.bindBufferId = 0
	end

	-- 通知前端刷新格子
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.GRIDUPDATE, self.player.playerId, self.gridIndex, self.carryBufferList)
end

function BattleGrid:OnBufferLayerRemove( _buffer, _layerCount, ... )
	local layerCount = NilDefault(_layerCount, 1)
	-- 已存在塔
	if self.tower then
		self.tower:RemoveBufferLayerByBufferId(_buffer.bindBufferId, layerCount)
	end

	-- 通知前端刷新格子
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.GRIDUPDATE, self.player.playerId, self.gridIndex, self.carryBufferList)
end

function BattleGrid:OnAllBufferRemove( ... )
	-- 已存在塔
	if self.tower then
		self.tower:RemoveAllBuffer()
	end

	-- 通知前端刷新格子
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.GRIDUPDATE, self.player.playerId, self.gridIndex, self.carryBufferList)
end

classend()