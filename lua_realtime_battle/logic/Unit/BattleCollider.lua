---
--- class BattleCollider
-- @classmod BattleCollider
-- 战斗碰撞
class('BattleCollider', BattleUnit)

local table_insert = table.insert
local BattleTriggerParam_New = BattleTriggerParam.New

local TSCollider = gModel.TSCollider

---Constructor
function BattleCollider:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.COLLIDER

	self.colliderId = 0				-- 实例Id
	self.colliderRes = false		-- 配置
	self.triggerTimeInterval = 0	-- 触发时间间隔
	self.maxCollisionTimes = 0		-- 最大碰撞次数

	self.owner = false				-- 所有者，{ unitId, player }	

	self.position = 0				-- 当前位置

	self.enterMonsterList = {}		-- 进入过的怪物列表
	self.collisionTimes = 0			-- 碰撞次数
	self.birthTime = 0				-- 生成时间
	self.duration = 0				-- 持续时间
	self.triggerTimeMap = {}		-- 触发时间

	self.node = false 				-- 链表节点
end

function BattleCollider:Serialize( ... )
	local tCollider = TSCollider:new{}
	tCollider.Id = self.colliderId
	tCollider.ResId = self.colliderRes.id
	tCollider.Position = self.position
	tCollider.OwnerId = self.owner.unitId
	tCollider.OwnerPlayerId = self.owner.player.unitId
	tCollider.Unit = self.super:Serialize()
	tCollider.CollisionTimes = self.collisionTimes ~= 0 and self.collisionTimes or nil
	tCollider.BirthTime = self.birthTime
	tCollider.Duration = self.duration ~= 0 and self.duration or nil
	for monsterUnitId, monster in pairs(self.enterMonsterList) do
		if not tCollider.EnterMonsterList then
			tCollider.EnterMonsterList = {}
		end
		table_insert(tCollider.EnterMonsterList, monsterUnitId)
	end
	for monsterUnitId, time in pairs(self.triggerTimeMap) do
		local monster = gBattleRecord:GetBattleUnit(monsterUnitId)
		if monster then
			if not tCollider.TriggerTimeMap then
				tCollider.TriggerTimeMap = {}
			end
			tCollider.TriggerTimeMap[monsterUnitId] = time
		end
	end
	return tCollider
end

function BattleCollider:DeSerialize( _tCollider, _player, ... )
	if not _tCollider or not _player then
		return
	end
	self:Init(GameResMgr.GetBattleColliderRes(_tCollider.ResId), _tCollider.Id, nil, _player, _tCollider.Position)
	self.super:DeSerialize(_tCollider.Unit)
	self.owner.unitId = _tCollider.OwnerId
	self.collisionTimes = _tCollider.CollisionTimes or 0
	self.birthTime = _tCollider.BirthTime
	self.duration = _tCollider.Duration or 0
	if _tCollider.TriggerTimeMap then
		for monsterUnitId, time in pairs(_tCollider.TriggerTimeMap) do
			self.triggerTimeMap[monsterUnitId] = time
		end
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		self.owner.player = gBattleRecord:GetBattleUnit(_tCollider.OwnerPlayerId)
		self:RegisterTalentList(self.colliderRes.talentList, self.owner)

		local enterMonsterList = _tCollider.EnterMonsterList
		if enterMonsterList then
			for i = 1, #enterMonsterList do
				local monster = gBattleRecord:GetBattleUnit(enterMonsterList[i])
				if monster then
					self.enterMonsterList[monster.unitId] = monster
				end
			end
		end
		-- 通知前端添加碰撞
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDCOLLIDER, self.player.playerId, self.colliderId)
	end)
end

function BattleCollider:Destroy( ... )
	-- 进入的怪物通知离开
	for _, monster in pairs(self.enterMonsterList) do
		if not monster:HasUnitFlag(BattleUnitFlag.DEATH) then
			-- 触发离开碰撞
			local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
			gBattleTrigger:FireTrigger(BattleTriggerType.LEAVECOLLISION, triggerParam)
		end
	end
	self.enterMonsterList = {}

	-- 父类销毁
	self.super:Destroy()
end

function BattleCollider:Init( _colliderRes, _colliderId, _owner, _player, _position, ... )
	if not _colliderRes then
		return false
	end

	self.colliderId = _colliderId
	self.owner = _owner or {}
	self.player = _player
	self.unit = self
	self.unitId = self:GenerateUnitId(self.colliderId)
	self.colliderRes = _colliderRes
	self.position = _position
	self.birthTime = gBattleTime + BattleConstants.BATTLE_COLLIDER_DELAY_TIME
	self.triggerTimeInterval = self.colliderRes.timeInterval
	self.maxCollisionTimes = self.colliderRes.collisionTimes
	self.duration = BattleFormula.GetValue(self.colliderRes.duration, self)

	-- 注册天赋
	if _owner then
		self:RegisterTalentList(_colliderRes.talentList, _owner)
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
	if self.duration ~= 0 and gBattleTime - self.birthTime >= self.duration then
		self.player:RemoveCollider(self.colliderId)
		return
	end

	local position = self.position
	local halfRange = self.colliderRes.range * 0.5

	-- 遍历怪物，判断是否碰撞
	local monsterList = self.player.monsterList
	local monster = false
	local monsterUnitId = false
	local monsterTime = 0
	local enterMonsters = {}
	for i = 1, #monsterList do
		-- 达到最大碰撞次数，直接销毁
		if self.maxCollisionTimes > 0 and self.collisionTimes >= self.maxCollisionTimes then
			self.player:RemoveCollider(self.colliderId)
			break
		end

		monster = monsterList[i]
		if not monster.isDie then
			monsterUnitId = monster.unitId
			if monster.position < position - halfRange then
				-- 后面的怪物都不需要遍历了
				break
			end

			if monster.position <= position + halfRange then
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
						local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
						gBattleTrigger:FireTrigger(BattleTriggerType.COLLISIONINTERVAL, triggerParam)
					end
					self.triggerTimeMap[monsterUnitId] = monsterTime
				else
					-- 进入碰撞
					enterMonsters[monsterUnitId] = monster
					if not self.enterMonsterList[monsterUnitId] then
						self.enterMonsterList[monsterUnitId] = monster
						self.collisionTimes = self.collisionTimes + 1

						-- 触发进入碰撞
						local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
						gBattleTrigger:FireTrigger(BattleTriggerType.ENTERCOLLISION, triggerParam)

						-- 达到最大碰撞次数，直接销毁
						if self.maxCollisionTimes > 0 and self.collisionTimes >= self.maxCollisionTimes then
							self.player:RemoveCollider(self.colliderId)
							break
						end
					end
				end
			end
		end
	end

	-- 检查离开碰撞的怪物
	for _, monster in pairs(self.enterMonsterList) do
		if not enterMonsters[monster.unitId] then
			-- 触发离开碰撞
			local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
			gBattleTrigger:FireTrigger(BattleTriggerType.LEAVECOLLISION, triggerParam)
		end
	end
	self.enterMonsterList = enterMonsters
end

function BattleCollider:GetGrade( ... )
	if self.owner.player then
		return self.owner.player:GetTowerGrade(self.colliderRes.towerId)
	end
	return 0
end

function BattleCollider:GetLevel( ... )
	local towerRes = GameResMgr.GetBattleTowerRes(self.colliderRes.towerId)
	return towerRes and towerRes.level or 0
end

classend()