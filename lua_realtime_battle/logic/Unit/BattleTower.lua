---
--- class BattleTower
-- @classmod BattleTower
-- 战斗塔
class('BattleTower', BattleUnit)

---Constructor
function BattleTower:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.TOWER

	self.towerId = 0						-- 实例id
	self.towerRes = false					-- 配置
	self.gunCount = 0						-- 炮数量

	self.posIndex = 0						-- 位置索引

	self.replaceTargetId = 0				-- 替代的目标Id

	self.gunList = {} 						-- 飞行道具发射源列表
	self.lastMonsterId = 0					-- 上一次攻击怪物Id
	self.sameMonsterAttackTimes = 0			-- 同一怪物攻击次数

	self.attackTimes = 0					-- 攻击次数
	self.extraAttackTimes = 0				-- 附属攻击次数

	self.curConnectCount = 0				-- 当前连接数量
	self.connectCount = -1					-- 运算时连接数量
end

function BattleTower:Destroy( _leaveType, ... )
	-- 父类销毁
	self.super:Destroy(_leaveType, ...)
end

function BattleTower:Init( _towerRes, _gunCount, _towerId, _posIndex, _player, ... )
	if not _towerRes then
		return false
	end

	self.towerId = _towerId
	self.player = _player
	self.unitId = self:GenerateUnitId(self.towerId)
	self.towerRes = _towerRes
	self.gunCount = _gunCount
	self.posIndex = _posIndex

	-- 属性基础值
	self.baseAttriList[AttriType.ATTACK] = BattleFormula.GetValue(self.towerRes.attack, self, nil)
	self.baseAttriList[AttriType.ATKSPEED] = BattleFormula.GetValue(self.towerRes.atkSpeed, self, nil)
	self.baseAttriList[AttriType.EXATKSPEED] = BattleFormula.GetValue(self.towerRes.extraAtkSpeed, self, nil)
	self.baseAttriList[AttriType.CRITICAL] = Constants.BATTLE_CRITICALRATE_INIT
	self.baseAttriList[AttriType.CRITICALSCALE] = Constants.BATTLE_CRITICALSCALE_INIT

	-- 注册天赋
	for i = 1, #_towerRes.talentList do
		self:RegisterTalent(_towerRes.talentList[i], self)
	end

	-- 父类初始化
	self.super:Init()

	-- 飞行道具发射源初始化
	self.gunList = self:InitGun()

	return true
end

-- 飞行道具发射源初始化
function BattleTower:InitGun( ... )
	local gunList = {}
	local interval = ToInt(self:GetAtkSpeed() / self.gunCount)
	local extraInterval = ToInt(self:GetExAtkSpeed() / self.gunCount)
	for i = 1, self.gunCount do
		table_insert(gunList, { 
			nextFireTime = gBattleTime + self:GetAtkSpeed(), 
			fireInterval = interval * (i - 1), 
			missileQueue = LQueue(16),
			nextExtraFireTime = extraInterval == 0 and 0 or (gBattleTime + self:GetExAtkSpeed()),
			extraFireInterval = extraInterval * (i - 1),
		})
	end
	return gunList
end

function BattleTower:Update( _deltaTime, ... )
	-- 父类更新
	self.super:Update(_deltaTime, ...)

	-- 发射子弹
	for i = 1, self.gunCount do
		local gun = self.gunList[i]
		-- 普攻
		if self.towerRes.attack ~= 0 then
			-- 发射
			if gBattleTime >= gun.nextFireTime + gun.fireInterval then
				-- 命中时间
				local hitTime = gun.nextFireTime + gun.fireInterval + BattleConstants.BATTLE_MISSILE_TIME
				-- 下次发射时间
				gun.nextFireTime = gun.nextFireTime + self:GetAtkSpeed()
				gun.fireInterval = ToInt(self:GetAtkSpeed() / self.gunCount) * (i - 1)
				if self:CanAttack() then
					-- 寻找目标，并确定命中时间
					local targetId = self:GetTargetId()
					local targets = BattleTarget.FindTarget(targetId, self)
					local monster = #targets > 0 and targets[1] or false
					if monster then
						-- 同一怪物攻击次数
						self.sameMonsterAttackTimes = self.lastMonsterId == monster.monsterId and self.sameMonsterAttackTimes + 1 or 1
						self.lastMonsterId = monster.monsterId
						-- 插入子弹
						local missile = {}
						missile.hitTime = hitTime
						missile.monsterId = monster.monsterId
						missile.monsterUnitId = monster.unitId
						missile.damage = self:GetAttack()
						missile.effectId = self.towerRes.atkEffectId
						self.attackTimes = self.attackTimes + 1
						missile.attackTimes = self.attackTimes
						gun.missileQueue:EnQueue(missile)

						-- 统计子弹	
						self.player.stat:AddMissile()

						-- 通知前端发射
						BattleMain.INSTANCE():SendGBCommand(GBCommandType.FIRE, self.unitId, i, missile, gun.nextFireTime - gBattleTime + gun.fireInterval)
					end
				end
			end
			-- 命中
			local firstMissile = gun.missileQueue:Peek()
			if firstMissile and gBattleTime >= firstMissile.hitTime then
				local targetMonster = self.player:GetMonster(firstMissile.monsterId)
				if targetMonster and self:CanAttack() then
					-- 触发攻击
					local triggerParam = BattleTriggerParam(self, self, { targetMonster }, i * 100000000 + firstMissile.attackTimes)
					gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
					-- 计算伤害
					local damage = firstMissile.damage + triggerParam.extraDamage
					damage = self:CalcDamage(damage, targetMonster, nil, nil, false)
					-- 怪物被击
					targetMonster:OnAttackDamage(self, damage)
				else
					-- 无效输出
					self.player.stat:AddMissMissile()
				end
				-- 移除子弹
				gun.missileQueue:DeQueue()
			end
		end
		-- 附属行为
		if gun.nextExtraFireTime ~= 0 and gBattleTime >= gun.nextExtraFireTime + gun.extraFireInterval then
			-- 触发附属行为
			self.extraAttackTimes = self.extraAttackTimes + 1
			local triggerParam = BattleTriggerParam(self, self, nil, i * 100000000 + self.extraAttackTimes)
			gBattleTrigger:FireTrigger(BattleTriggerType.EXATTACK, triggerParam)
			-- 下次发射时间
			gun.nextExtraFireTime = gun.nextExtraFireTime + self:GetExAtkSpeed()
			gun.extraFireInterval = ToInt(self:GetExAtkSpeed() / self.gunCount) * (i - 1)
		end
	end
end

function BattleTower:GetAttack( ... )
	return self:GetAttribute(AttriType.ATTACK)
end

function BattleTower:GetAtkSpeed( ... )
	return self:GetAttribute(AttriType.ATKSPEED)
end

function BattleTower:GetExAtkSpeed( ... )
	return self:GetAttribute(AttriType.EXATKSPEED)
end

function BattleTower:GetTargetId( ... )
	local targetId = self.towerRes.targetId
	if self:HasUnitFlag(BattleUnitFlag.LOCKRANDOM) then
		targetId = Constants.BATTLE_LOCKRANDOM_TARGET_ID
		return targetId
	end
	if self:HasUnitFlag(BattleUnitFlag.LOCKFIRST) then
		targetId = Constants.BATTLE_LOCKFIRST_TARGET_ID
		return targetId
	end
	if self.replaceTargetId ~= 0 then
		targetId = self.replaceTargetId
	end
	return targetId
end

function BattleTower:RefreshTowerConnect( _list, ... )
	self.connectCount = 0
	local nextToPosList = BattleConstants.BATTLE_TOWER_CROSS_MAP[self.posIndex]
	for i = 1, #nextToPosList do
		local nextToTower = self.player.towerList[nextToPosList[i]]
		if nextToTower and nextToTower:HasUnitFlag(BattleUnitFlag.CONNECT) and nextToTower.connectCount == -1 then
			nextToTower:RefreshTowerConnect(_list)
		end 
	end
	table_insert(_list, self)
end

function BattleTower:SetConnectCount( _count, ... )
	self.connectCount = _count
	if self.curConnectCount == self.connectCount then
		return
	end
	self.curConnectCount = self.connectCount
	-- 添加Buffer
	self:AddBuffer(Constants.BATTLE_CONNECT_BUFFER, self, false)
end

-- 是否可以合成
function BattleTower:CanMerge( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.towerId == self.towerId then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	if self:CanExchange(_targetTower) then
		return true, BattleTowerMergeType.EXCHANGE
	end
	if self:CanCopy(_targetTower) then
		return true, BattleTowerMergeType.COPY
	end
	if self:CanFix(_targetTower) then
		return true, BattleTowerMergeType.FIX
	end
	if _targetTower.towerRes.id ~= self.towerRes.id and not self:HasUnitFlag(BattleUnitFlag.FIT) and not _targetTower:HasUnitFlag(BattleUnitFlag.FIT) then
		return false
	end
	return true, BattleTowerMergeType.MERGE
end

-- 是否可以交换
function BattleTower:CanExchange( _targetTower,  ... )
	if not _targetTower then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self:HasUnitFlag(BattleUnitFlag.EXCHANGE)
end

-- 是否可以复制
function BattleTower:CanCopy( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self:HasUnitFlag(BattleUnitFlag.COPY)
end

-- 是否可以营养
function BattleTower:CanFix( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.gunCount ~= self.gunCount then
		return false
	end
	return self:HasUnitFlag(BattleUnitFlag.FIX)
end

-- 是否可以攻击
function BattleTower:CanAttack( ... )
	return not self:HasUnitFlag(BattleUnitFlag.SILENCE)
end

classend()