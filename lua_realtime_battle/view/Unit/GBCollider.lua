---
--- class GBCollider
-- @classmod GBCollider
class('GBCollider', GBUnit)

---Constructor
function GBCollider:ctor( ... )
	self.super = Super()

	self.collider = false		-- 战斗逻辑碰撞体
end

function GBCollider:Destroy( ... )
	if self.uBattleUnit then
		self.uBattleUnit:Stop(true)
	end

	-- 父类销毁
	self.super:Destroy()
end

function GBCollider:Init( _collider, _gbPlayer, ... )
	if not _collider or not _gbPlayer then
		return false
	end

	self.collider = _collider
	self.battleUnit = self.collider
	self.gbUnit = self
	self.gbPlayer = _gbPlayer

	self:CheckFrameChasing('Init', function( ... )
		local objCollider = GameObjectPool.INSTANCE:Request(self.collider.colliderRes.prefabName, 'animation/other/prefabs/tower/', true)
		if not objCollider then
			return false
		end

		self.uBattleUnit = UIUtils.GetObjectComponent(objCollider, 'UBattleCollider')
		self.gameObject = objCollider.gameObject
		self.transform = objCollider.transform
		self.uBattleUnit.unitId = self.collider.unitId
		-- 放入战场
		GOUtils.SetParent(self.gameObject, self.gbPlayer.objMonsterRoad, false, -1, -1, -1, string.format('collider_%d', self.collider.colliderId))
	end)

	-- 初始化位置
	self:SetPosition(self.collider.position)

	return true
end

function GBCollider:SetPosition( _position, ... )
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
	local posX = startPoint.x + (endPoint.x - startPoint.x) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	local posY = startPoint.y + (endPoint.y - startPoint.y) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	self:CheckFrameChasing('SetPosition', function( ... )
		self.uBattleUnit:SetPosition(posX, posY, 1)
	end)
end

classend()