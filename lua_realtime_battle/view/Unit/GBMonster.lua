---
--- class GBMonster
-- @classmod GBMonster
class('GBMonster', GBUnit)

---Constructor
function GBMonster:ctor( ... )
	self.super = Super()

	self.monster = false 				-- 战斗逻辑怪物

	self.position = 0 					-- 显示层位置
	self.speed = 0 						-- 显示层速度，每秒
end

function GBMonster:Destroy( ... )
	self:FireUnitEvent('OnMonsterDie')

	-- 父类销毁
	self.super:Destroy()
end

function GBMonster:Init( _monster, _gbPlayer, ... )
	if not _monster or not _gbPlayer then
		return false
	end

	self.monster = _monster
	self.battleUnit = self.monster
	self.gbUnit = self
	self.gbPlayer = _gbPlayer

	self:CheckFrameChasing('Init', function( ... )
		local objMonster = GameObjectPool.INSTANCE:Request(self.monster.monsterRes.prefabName, 'animation/other/prefabs/monster/', true)
		if not objMonster then
			return false
		end

		self.uBattleUnit = UIUtils.GetObjectComponent(objMonster, 'UBattleMonster')
		self.gameObject = objMonster.gameObject
		self.transform = objMonster.transform
		self.uBattleUnit.unitId = self.monster.unitId
		-- 放入战场
		GOUtils.SetParent(self.gameObject, self.gbPlayer.objMonsterRoad, false, -1, -1, -1, string.format('monster_%d', self.monster.monsterId))
	end)

	-- 初始化位置
	self:SetPosition(self.monster.position)
	-- 初始化血量
	self:UpdateHP(true)

	return true
end

function GBMonster:Update( _deltaTime, ... )
	local moveDistance = _deltaTime * self.speed / 1000
	local position = self.position + moveDistance
	position = position > BattleConstants.BATTLE_ROAD_LENGTH and BattleConstants.BATTLE_ROAD_LENGTH or position
	self:SetPosition(position)
end

function GBMonster:UpdateHP( _isInit, ... )
	local curHP = self.monster.curHP
	local maxHP = self.monster.maxHP
	if _isInit and curHP == maxHP then
		return
	end
	self:CheckFrameChasing('UpdateHP', function( ... )
		self.uBattleUnit:UpdateHP(curHP / maxHP)
	end)
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
	self.position = _position
	self:CheckFrameChasing('SetPosition', function( ... )
		self.uBattleUnit:SetPosition(posX, posY, self.monster.sortIndex * 100)
	end)
end

classend()