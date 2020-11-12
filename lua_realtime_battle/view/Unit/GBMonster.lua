---
--- class GBMonster
-- @classmod GBMonster
class('GBMonster', GBUnit)

---Constructor
function GBMonster:ctor( ... )
	self.super = Super()

	self.monster = false 				-- 战斗逻辑怪物
	self.objMonsterHP = false 			-- 怪物血量物件

	self.position = 0 					-- 显示层位置
	self.speed = 0 						-- 显示层速度，每秒
end

function GBMonster:Destroy( ... )
	self.uBattleUnit.unitId = ''

	if self.gameObject then
		GameObjectPool.ReleaseObject(self.gameObject)
	end

	-- 父类销毁
	self.super:Destroy()

	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBMonster:Init( _monster, _gbPlayer, ... )
	if not _monster or not _gbPlayer then
		return false
	end

	local objMonster = GameObjectPool.INSTANCE:Request('battle/battle_monster', true)
	if not objMonster then
		return false
	end

	self.uBattleUnit = UIUtils.GetObjectComponent(objMonster, 'UBattleMonster')
	self.gameObject = objMonster.gameObject
	self.transform = objMonster.transform
	self.objMonsterHP = UIUtils.GetChild(self.gameObject, 'txt')
	self.monster = _monster
	self.unit = self.monster
	self.gbPlayer = _gbPlayer
	self.uBattleUnit.unitId = self.monster.unitId

	-- 放入战场
	GOUtils.SetParent(self.gameObject, self.gbPlayer.objMonsterRoad, false, -1, -1, -1, string.format('monster_%d', self.monster.monsterId))
	-- 初始化位置
	self:SetPosition(self.monster.position)
	-- 初始化血量
	self:UpdateHP()
	-- 魔法怪
	if self.monster.isMagicMonster then
		UIUtils.SetChildColor(self.gameObject, 'frm', Color(1, 0, 1, 1))
	else
		UIUtils.SetChildColor(self.gameObject, 'frm', Color(1, 1, 1, 1))
	end

	return true
end

function GBMonster:Update( _deltaTime, ... )
	local moveDistance = _deltaTime * self.speed / 1000
	local position = self.position + moveDistance
	position = position > BattleConstants.BATTLE_ROAD_LENGTH and BattleConstants.BATTLE_ROAD_LENGTH or position
	self:SetPosition(position)
end

function GBMonster:UpdateHP( ... )
	GOUtils.SetText(self.objMonsterHP, tostring(self.monster.curHP))
end

function GBMonster:Move( _position, _speed, ... )
	if _speed == 0 then
		self.speed = 0
		return
	end
	-- 瞬移,强制设置位置
	if _speed == -1 then
		self:SetPosition(_position)
		return
	end

	-- 提前预测2秒后的位置，显示层预演
	local forcastTime = 2
	local targetPosition = _position + _speed * Constants.BATTLE_FPS * forcastTime
	-- if targetPosition > BattleConstants.BATTLE_ROAD_LENGTH then
	-- 	targetPosition = BattleConstants.BATTLE_ROAD_LENGTH
	-- end
	local distance = targetPosition - self.position
	self.speed = distance / forcastTime
end

function GBMonster:SetPosition( _position, ... )
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
	self.position = _position
end

classend()