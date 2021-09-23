---
--- class GBCollider
-- @classmod GBCollider
GBCollider = xclass('GBCollider', GBUnit)

local CreateBattleCollider = LUBattleCollider.Create
local EndBattleUnit = LUBattleUnit.End

---Constructor
function GBCollider:ctor( ... )
	self.collider = false		-- 战斗逻辑碰撞体
end

function GBCollider:Destroy( ... )
	if self.unitId ~= 0 then
		EndBattleUnit(self.unitId, GameStringType.OnEndSuccess)
	end

	-- 父类销毁
	self.super:Destroy()
end

function GBCollider:Init( _collider, _gbPlayer, _ownerUnitId, _pendingFrameCount, ... )
	if not _collider or not _gbPlayer then
		return false
	end

	self.collider = _collider
	self.battleUnit = self.collider
	self.gbUnit = self
	self.gbPlayer = _gbPlayer

	self:CheckFrameChasing('Init', function( ... )
		local prefabName = self.collider.colliderRes.prefabName
		local gbOwnerUnit = gGBField:GetGBUnit(_ownerUnitId)
		local pendingFrameCount = _pendingFrameCount or 0
		local pendingTime = pendingFrameCount * Constants.BATTLE_FRAME_TIME
		local logicPoistion = self.collider.position
		local posX, posY, zFactor, direction = self:GetPathPosition(logicPoistion)
		self.unitId = CreateBattleCollider(self.collider.unitId, prefabName, GameStringType.TowerPath, self.gbPlayer.objMonsterRoadId, posX, posY, zFactor, direction, logicPoistion, gbOwnerUnit and gbOwnerUnit.unitId or 0, pendingTime)
	end)

	return true
end

function GBCollider:GetPathPosition( _position )
	local startPoint = false
	local endPoint = false
	local path = self.gbPlayer.monsterPath
	local pointCount = #path
	for i = pointCount - 1, 1, -1 do
		local point = path[i]
		if _position >= point.z then
			startPoint = point
			endPoint = path[i + 1]
			break
		end
	end
	if not startPoint or not endPoint then
		return
	end
	local zOrderFactor = ((endPoint.x < startPoint.x) or (endPoint.y > startPoint.y)) and -1 or 1
	local posX = startPoint.x + (endPoint.x - startPoint.x) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	local posY = startPoint.y + (endPoint.y - startPoint.y) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	local direction = startPoint.w
	return posX, posY, zOrderFactor, direction
end