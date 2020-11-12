---
--- class BattleMonster
-- @classmod BattleMonster
-- 战斗怪物
class('BattleMonster', BattleUnit)

---Constructor
function BattleMonster:ctor( ... )
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.MONSTER

	self.monsterId = 0				-- 实例Id
	self.monsterRes = false			-- 配置
	self.isMagicMonster = false		-- 是否魔法怪

	self.curHP = false				-- 当前血量
	self.position = 0				-- 当前位置

	self.node = false 				-- 链表节点
end

function BattleMonster:Destroy( _leaveType, ... )
	local leaveType = NilDefault(_leaveType, BattleUnitLeaveType.ALL)
	if leaveType ~= BattleUnitLeaveType.CLEAN then
		-- 玩家加点
		local point = ToInt(self:GetPoint())
		point = self.player:AddPoint(point, 1)
		self.player.stat:AddMonsterPoint(point)
	end

	-- 父类销毁
	self.super:Destroy(leaveType)
end

function BattleMonster:Init( _monsterRes, _monsterId, _player, _monsterHP, _isMagicMonster, ... )
	if not _monsterRes then
		return false
	end

	self.monsterId = _monsterId
	self.player = _player
	self.unitId = self:GenerateUnitId(self.monsterId)
	self.monsterRes = _monsterRes
	self.isMagicMonster = NilDefault(_isMagicMonster, false)

	-- 注册天赋
	for i = 1, #_monsterRes.talentList do
		self:RegisterTalent(_monsterRes.talentList[i], self)
	end

	self.player.stat:AddMonster()

	-- 父类初始化
	self.super:Init()

	-- 属性基础值
	local monsterHPScale = gBattleLogic:GetMonsterHPScale(self.monsterRes.type) / 100
	self.baseAttriList[AttriType.HP] = ToInt(BattleFormula.GetValue(self.monsterRes.hpId, self) * monsterHPScale)
	self.baseAttriList[AttriType.SPEED] = BattleFormula.GetValue(self.monsterRes.speedId, self)
	self.baseAttriList[AttriType.DEFENCE] = Constants.BATTLE_DEFENCE_INIT
	-- 掉落点数
	self.baseAttriList[AttriType.POINT] = BattleFormula.GetValue(self.monsterRes.pointId, self)

	self.curHP = _monsterHP and _monsterHP or self:GetMaxHP()

	return true
end

function BattleMonster:Update( _deltaTime, ... )
	-- 父类更新
	self.super:Update(_deltaTime, ...)

	-- 移动
	self:Move(self:GetSpeed())
end

function BattleMonster:GetMaxHP( ... )
	return self:GetAttribute(AttriType.HP)
end

function BattleMonster:GetSpeed( ... )
	return ToInt(self:GetAttribute(AttriType.SPEED) * 0.925)
end

function BattleMonster:GetDefence( ... )
	return self:GetAttribute(AttriType.DEFENCE)
end

function BattleMonster:GetPoint( ... )
	return self:GetAttribute(AttriType.POINT)
end

function BattleMonster:Move( _speed, ... )
	-- 死亡不移动
	if self:HasUnitFlag(BattleUnitFlag.DEATH) then
		return
	end
	-- 眩晕不移动
	if self:HasUnitFlag(BattleUnitFlag.DIZZY) then
		-- 通知前端更新怪物位置
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.MONSTERMOVE, self.player.playerId, self.monsterId, self.position, 0)
		return
	end
	-- 更新位置
	self:SetPosition(self.position + _speed, _speed)
end

-- _speed -1瞬移
function BattleMonster:SetPosition( _position, _speed, ... )
	self.position = _position
	if self.position > BattleConstants.BATTLE_ROAD_LENGTH then
		-- 走了一圈
		-- self.position = self.position - BattleConstants.BATTLE_ROAD_LENGTH
		-- 移除怪物
		local subHP = self.monsterRes.type == MonsterType.BOSS and 2 or 1
		self.player:RemoveMonster(self.monsterId, BattleUnitLeaveType.END, subHP)
		-- 通知战斗逻辑
		gBattleLogic:OnMonsterDie(self)
		return
		-- 普通、精英、忍者怪走满一圈会分裂
		-- local monsterHP = self.curHP
		-- if self.monsterRes.type < MonsterType.BOSS then
		-- 	gBattleTimer:RunTask(string.format('MonsterClone_%s', self.unitId), 200, 0, 0, function( ... )
		-- 		local monsterId = self.monsterRes.id
		-- 		self.player:AddMonster(monsterId, monsterHP)
		-- 	end)
		-- end
	end
	-- 通知前端更新怪物位置
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.MONSTERMOVE, self.player.playerId, self.monsterId, self.position, _speed)
end

-- isRealDamage 真实伤害 无视护甲\免伤
function BattleMonster:OnAttackDamage( _attackerUnit, _damage, _isRealDamage, ... )
	-- 触发被击
	local triggerParam = BattleTriggerParam(self, _attackerUnit, { _attackerUnit }, _damage)
	gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKED, triggerParam)

	_damage = _damage > self.curHP and self.curHP or _damage
	self.curHP = self.curHP - _damage

	self.player.stat:AddDamage(_damage)

	gBattleManager:AddBattleLog(string.format('Monster Attacked Frame[%d] Monster[%s] Attacker[%s] Damage[%d] HP[%d]', gBattleFrameCount, self.unitId, _attackerUnit.unitId, _damage, self.curHP))

	-- 校验怪物死亡
	if self.curHP <= 0 then
		self.curHP = 0
		self:OnMonsterDie()
	end

	-- 通知前端更新怪物血量
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.MONSTERHP, self.player.playerId, self.monsterId)
end

function BattleMonster:OnMonsterDie( _attackerUnit, ... )
	if self:HasUnitFlag(BattleUnitFlag.DEATH) then
		return
	end

	if self.curHP > 0 then
		return
	end

	self.player.stat:AddKillMonster()

	-- 触发死亡
	local triggerParam = BattleTriggerParam(self, _attackerUnit, { _attackerUnit }, nil)
	gBattleTrigger:FireTrigger(BattleTriggerType.DEATH, triggerParam)

	-- 触发击杀
	triggerParam = BattleTriggerParam(_attackerUnit, _attackerUnit, nil, nil)
	gBattleTrigger:FireTrigger(BattleTriggerType.KILL, triggerParam)

	-- 怪物死亡
	self.player:RemoveMonster(self.monsterId)

	-- 通知战斗逻辑
	gBattleLogic:OnMonsterDie(self, true)
end

function BattleMonster:Clone( _monster, ... )
	if not _monster then
		return
	end

	self.curHP = _monster.curHP
end

classend()