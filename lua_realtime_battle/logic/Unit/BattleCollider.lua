---
--- class BattleCollider
-- @classmod BattleCollider
-- 战斗碰撞
BattleCollider = xclass('BattleCollider', BattleUnit)

local table_insert = table.insert
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy

local TSCollider = gModel.TSCollider
local TS2Int = gModel.TS2Int

---Constructor
function BattleCollider:ctor( ... )
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
	self.pendingFrameCount = 0		-- 缓冲帧数

	self.node = false 				-- 链表节点
end

function BattleCollider:Serialize( ... )
	local tCollider = TSCollider:new{}
	tCollider.Id = self.colliderId
	tCollider.ResId = self.colliderRes.id
	tCollider.Position = self.position
	tCollider.OwnerId = self.owner.unitId
	tCollider.OwnerPlayerId = self.owner.player.unitId
	tCollider.CollisionTimes = self.collisionTimes ~= 0 and self.collisionTimes or nil
	tCollider.BirthTime = self.birthTime
	tCollider.Duration = self.duration ~= 0 and self.duration or nil
	tCollider.PendingFrameCount = self.pendingFrameCount ~= 0 and self.pendingFrameCount or nil
	tCollider.Unit = self.super:Serialize()
	for monsterUnitId, monster in pairs(self.enterMonsterList) do
		if not tCollider.EnterMonsterList then
			tCollider.EnterMonsterList = {}
		end
		table_insert(tCollider.EnterMonsterList, monsterUnitId)
	end
	for monsterUnitId, time in pairs(self.triggerTimeMap) do
		local monster = gBattleRecord:GetBattleUnit(monsterUnitId)
		if monster then
			if not tCollider.TriggerTimeList then
				tCollider.TriggerTimeList = {}
			end
			local tValue = TS2Int:new{}
			tValue.Arg0 = monsterUnitId
			tValue.Arg1 = time
			table_insert(tCollider.TriggerTimeList, tValue)
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
	self.pendingFrameCount = _tCollider.PendingFrameCount or 0
	if _tCollider.TriggerTimeList then
		for i = 1, #_tCollider.TriggerTimeList do
			local tValue = _tCollider.TriggerTimeList[i]
			self.triggerTimeMap[tValue.Arg0] = tValue.Arg1
		end
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		local owner = gBattleRecord:GetBattleUnit(_tCollider.OwnerId)
		if owner then
			self.owner = owner
		else
			self.owner.player = gBattleRecord:GetBattleUnit(_tCollider.OwnerPlayerId)
		end

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
		if not HasBattleFlag(monster.unitFlag, BattleUnitFlag.DEATH) then
			-- 触发离开碰撞
			local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
			gBattleTrigger:FireTrigger(BattleTriggerType.LEAVECOLLISION, triggerParam)
			BattleTriggerParam_Destroy(triggerParam)
		end
	end
	self.enterMonsterList = {}

	-- 父类销毁
	self.super:Destroy()
end

function BattleCollider:Init( _colliderRes, _colliderId, _owner, _player, _position, _pendingFrameCount, ... )
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
	self.birthTime = gBattleTime
	self.triggerTimeInterval = self.colliderRes.timeInterval
	self.maxCollisionTimes = self.colliderRes.collisionTimes
	self.duration = BattleFormula.GetValue(self.colliderRes.duration, self)
	self.pendingFrameCount = _pendingFrameCount or 0

	-- 注册天赋
	if _owner then
		self:RegisterTalentList(_colliderRes.talentList, _owner)
	end

	-- 父类初始化
	self.super:Init(true)

	return true
end

function BattleCollider:Enter( ... )
	if self.pendingFrameCount ~= 0 then
		return
	end

	self.birthTime = gBattleTime

	-- 父类进入
	self.super:Enter(...)
end

function BattleCollider:Update( _deltaTime, ... )
	-- 缓冲期间
	if self.pendingFrameCount ~= 0 then
		self.pendingFrameCount = self.pendingFrameCount - 1
		if self.pendingFrameCount == 0 then
			-- 缓冲结束，进入战斗
			self:Enter()
		end
		return
	end

	-- 更新状态
	local carryBufferList = self.carryBufferList
	local bufferCount = #carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end

	-- 判断是否死亡
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.DEATH) then
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
	local triggerTimeInterval = self.triggerTimeInterval
	local maxCollisionTimes = self.maxCollisionTimes
	local triggerTimeMap = self.triggerTimeMap
	for i = 1, #monsterList do
		-- 达到最大碰撞次数，直接销毁
		if maxCollisionTimes > 0 and self.collisionTimes >= maxCollisionTimes then
			self.player:RemoveCollider(self.colliderId)
			break
		end

		monster = monsterList[i]
		if monster:IsValid() then
			monsterUnitId = monster.unitId
			if monster.position < position - halfRange then
				-- 后面的怪物都不需要遍历了
				break
			end

			if monster.position <= position + halfRange then
				if triggerTimeInterval > 0 then
					-- 间隔碰撞
					monsterTime = triggerTimeMap[monsterUnitId]
					if not monsterTime then
						monsterTime = 0
					else
						monsterTime = monsterTime + _deltaTime
					end
					if monsterTime == 0 or monsterTime >= triggerTimeInterval then
						if monsterTime ~= 0 then
							monsterTime = monsterTime - triggerTimeInterval
						end
						-- 触发间隔碰撞
						local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
						gBattleTrigger:FireTrigger(BattleTriggerType.COLLISIONINTERVAL, triggerParam)
						BattleTriggerParam_Destroy(triggerParam)
					end
					triggerTimeMap[monsterUnitId] = monsterTime
				else
					-- 进入碰撞
					enterMonsters[monsterUnitId] = monster
					if not self.enterMonsterList[monsterUnitId] then
						self.enterMonsterList[monsterUnitId] = monster
						self.collisionTimes = self.collisionTimes + 1

						-- 触发进入碰撞
						local triggerParam = BattleTriggerParam_New(self, self, { monster }, nil)
						gBattleTrigger:FireTrigger(BattleTriggerType.ENTERCOLLISION, triggerParam)
						BattleTriggerParam_Destroy(triggerParam)

						-- 达到最大碰撞次数，直接销毁
						if maxCollisionTimes > 0 and self.collisionTimes >= maxCollisionTimes then
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
			BattleTriggerParam_Destroy(triggerParam)
		end
	end
	self.enterMonsterList = enterMonsters
end

function BattleCollider:GetGrade( ... )
	local player = self.owner.player
	if player then
		return player:GetTowerGradeByBaseId(self.colliderRes.towerId)
	end
	return 0
end

function BattleCollider:GetLevel( ... )
	local player = self.owner.player
	if player then
		return player:GetTowerLevelByBaseId(self.colliderRes.towerId)
	end
	return 0
end

function BattleCollider:IsValid( ... )
	return self.pendingFrameCount == 0
end