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
	if self.gameObject then
		GameObjectPool.ReleaseObject(self.gameObject)
	end

	-- 父类销毁
	self.super:Destroy()

	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBCollider:Init( _collider, _gbPlayer, ... )
	if not _collider or not _gbPlayer then
		return false
	end

	local objCollider = GameObjectPool.INSTANCE:Request('battle/battle_collider', true)
	if not objCollider then
		return false
	end

	self.uBattleUnit = UIUtils.GetObjectComponent(objCollider, 'UBattleCollider')
	self.gameObject = objCollider.gameObject
	self.transform = objCollider.transform
	self.collider = _collider
	self.unit = self.collider
	self.gbPlayer = _gbPlayer
	self.uBattleUnit.unitId = self.collider.unitId

	-- 放入战场
	local objParent = self.collider.colliderRes.zOrderType == EffectZOrderType.TOP and self.gbPlayer.objTopRoad or self.gbPlayer.objBottomRoad
	GOUtils.SetParent(self.gameObject, objParent, false, -1, -1, -1, string.format('monster_%d', self.collider.colliderId))
	-- 初始化位置
	self:SetPosition(self.collider.position)

	UIUtils.SetChildText(self, 'txt', self.collider.colliderRes.name)

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
	GOUtils.SetLocalPosition(self.gameObject, posX, posY, 1)
end

classend()