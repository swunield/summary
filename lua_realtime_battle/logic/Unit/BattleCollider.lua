---
--- class BattleCollider
-- @classmod BattleCollider
-- 战斗碰撞
class('BattleCollider', BattleUnit)

---Constructor
function BattleCollider:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.COLLIDER

	self.colliderId = 0				-- 实例Id
	self.colliderRes = false		-- 配置
	self.triggerTimeInterval = 0	-- 触发时间间隔
	self.maxCollisionTimes = 0		-- 最大碰撞次数

	self.ownerUnit = false			-- 所有者单位
	self.ownerPlayer = false		-- 所有者玩家

	self.position = 0				-- 当前位置

	self.enterMonsterList = {}		-- 进入过的怪物列表
	self.collisionTimes = 0			-- 碰撞次数
	self.birthTime = 0				-- 生成时间

	self.node = false 				-- 链表节点

	self.triggerTimeMap = {}		-- 触发时间
end

function BattleCollider:Destroy( ... )
	-- 进入的怪物通知离开
	for _, monster in pairs(self.enterMonsterList) do
		if not monster:HasUnitFlag(BattleUnitFlag.DEATH) then
			-- 触发离开碰撞
			local triggerParam = BattleTriggerParam(self, self, { monster }, nil)
			gBattleTrigger:FireTrigger(BattleTriggerType.LEAVECOLLISION, triggerParam)
		end
	end
	self.enterMonsterList = {}

	-- 父类销毁
	self.super:Destroy()
end

function BattleCollider:Init( _colliderRes, _colliderId, _ownerUnit, _player, _position, ... )
	if not _colliderRes then
		return false
	end

	self.colliderId = _colliderId
	self.ownerUnit = _ownerUnit
	self.ownerPlayer = _ownerUnit.player
	self.player = _player
	self.unitId = self:GenerateUnitId(self.colliderId)
	self.colliderRes = _colliderRes
	self.position = _position
	self.birthTime = gBattleTime + BattleConstants.BATTLE_COLLIDER_DELAY_TIME
	self.triggerTimeInterval = self.colliderRes.timeInterval
	self.maxCollisionTimes = self.colliderRes.collisionTimes

	-- 注册天赋
	for i = 1, #_colliderRes.talentList do
		self:RegisterTalent(_colliderRes.talentList[i], _ownerUnit)
	end

	-- 父类初始化
	self.super:Init()

	return true
end

function BattleCollider:Update( _deltaTime, ... )
	-- 父类更新
	self.super:Update(_deltaTime, ...)

	-- 判断是否死亡
	if self:HasUnitFlag(BattleUnitFlag.DEATH) then
		self.player:RemoveCollider(self.colliderId)
		return
	end

	-- 还没生效
	if gBattleTime < self.birthTime then
		return
	end

	-- 碰撞体生命周期
	local duration = self.colliderRes.duration
	if duration ~= 0 and gBattleTime - self.birthTime >= duration then
		self.player:RemoveCollider(self.colliderId)
		return
	end

	-- 遍历怪物，判断是否碰撞
	local monsterNode = self.player.monsterList.first
	local monster = false
	local monsterUnitId = false
	local monsterTime = 0
	local enterMonsters = {}
	while monsterNode do
		-- 达到最大碰撞次数，直接销毁
		if self.maxCollisionTimes > 0 and self.collisionTimes >= self.maxCollisionTimes then
			self.player:RemoveCollider(self.colliderId)
			break
		end

		monster = monsterNode.value
		monsterUnitId = monster.unitId
		if monster.position < self.position - self.colliderRes.range * 0.5 then
			-- 后面的怪物都不需要遍历了
			break
		end

		if monster.position <= self.position + self.colliderRes.range * 0.5 then
			if self.triggerTimeInterval > 0 then
				-- 间隔碰撞
				monsterTime = self.triggerTimeMap[monsterUnitId]
				if not monsterTime then
					monsterTime = 0
				else
					monsterTime = monsterTime + _deltaTime
				end
				if monsterTime == 0 or monsterTime >= self.triggerTimeInterval then
					if monsterTime ~= 0 then
						monsterTime = monsterTime - self.triggerTimeInterval
					end
					-- 触发间隔碰撞
					local triggerParam = BattleTriggerParam(self, self, { monster }, nil)
					gBattleTrigger:FireTrigger(BattleTriggerType.COLLISIONINTERVAL, triggerParam)
				end
				self.triggerTimeMap[monsterUnitId] = monsterTime
			else
				-- 碰撞进入离开
				enterMonsters[monsterUnitId] = monster
				if not self.enterMonsterList[monsterUnitId] then
					self.enterMonsterList[monsterUnitId] = monster
					self.collisionTimes = self.collisionTimes + 1

					-- 触发进入碰撞
					local triggerParam = BattleTriggerParam(self, self, { monster }, nil)
					gBattleTrigger:FireTrigger(BattleTriggerType.ENTERCOLLISION, triggerParam)

					-- 达到最大碰撞次数，直接销毁
					if self.maxCollisionTimes > 0 and self.collisionTimes >= self.maxCollisionTimes then
						self.player:RemoveCollider(self.colliderId)
						break
					end
				end
			end
		end
		monsterNode = monsterNode.next
	end

	-- 检查离开碰撞的怪物
	for _, monster in pairs(self.enterMonsterList) do
		if not enterMonsters[monster.unitId] then
			-- 触发离开碰撞
			local triggerParam = BattleTriggerParam(self, self, { monster }, nil)
			gBattleTrigger:FireTrigger(BattleTriggerType.LEAVECOLLISION, triggerParam)
		end
	end
	self.enterMonsterList = enterMonsters
end

classend()