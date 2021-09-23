---
--- class BattleMonster
-- @classmod BattleMonster
-- 战斗怪物
BattleMonster = xclass('BattleMonster', BattleUnit)

local os_clock = os.clock
local math_floor = math.floor
local math_ceil = math.ceil
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy
local FLAGMAP = Utils.BuildFlagMap

local TSMonster = gModel.TSMonster

---Constructor
function BattleMonster:ctor( ... )  
	self.super.unitType = BattleUnitType.MONSTER

	self.monsterId = 0				-- 实例Id
	self.monsterRes = false			-- 配置

	self.maxHP = false				-- 最大血量
	self.curHP = false				-- 当前血量
	self.position = 0				-- 当前位置

	self.isDie = false				-- 是否死亡
	self.sortIndex = 0				-- 排序索引
	self.pendingFrameCount = 0		-- 缓冲帧数
end

function BattleMonster:Serialize( ... )
	local tMonster = TSMonster:new{}
	tMonster.Id = self.monsterId
	tMonster.ResId = self.monsterRes.id
	tMonster.CurHP = self.curHP or -1
	tMonster.Position = self.position
	tMonster.PendingFrameCount = self.pendingFrameCount ~= 0 and self.pendingFrameCount or nil
	tMonster.Unit = self.super:Serialize()
	return tMonster
end

function BattleMonster:DeSerialize( _tMonster, _player, ... )
	if not _tMonster or not _player then
		return
	end
	self:Init(GameResMgr.GetBattleMonsterRes(_tMonster.ResId), _tMonster.Id, _player, _tMonster.CurHP ~= -1 and _tMonster.CurHP or false)
	self.position = _tMonster.Position
	self.pendingFrameCount = _tMonster.PendingFrameCount or 0
	self.super:DeSerialize(_tMonster.Unit)

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		-- 通知前端添加怪物
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDMONSTER, self.player.playerId, self.monsterId)
	end)
end

function BattleMonster:Destroy( _leaveFlags, ... )  
	self.isDie = true
	
	local leaveFlags = _leaveFlags or FLAGMAP(BattleUnitLeaveType.DIE)
	gBattleLogic:OnMonsterLeave(self, leaveFlags)

	-- 父类销毁
	self.super:Destroy(leaveFlags)
end

function BattleMonster:Init( _monsterRes, _monsterId, _player, _monsterHP, _position, ... )  
	if not _monsterRes then
		return false  
	end

	self.monsterId = _monsterId
	self.player = _player
	self.unit = self
	self.unitId = self:GenerateUnitId(self.monsterId)
	self.monsterRes = _monsterRes

	-- 注册天赋
	self:RegisterTalentList(_monsterRes.talentList, self)

	-- 属性基础值
	local extraHP = 0
	if self.monsterRes.type == MonsterType.BOSS then
		extraHP = gBattleLogic:GetTotalMonsterHP(_player)
	end
	local monsterHPScale = self.monsterRes.hpScale / Constants.PERCENT_MAX
	self.baseAttriList[AttriType.HP] = math_floor(BattleFormula.GetValue(self.monsterRes.hpId, self) * monsterHPScale) + extraHP
	self.baseAttriList[AttriType.SPEED] = BattleFormula.GetValue(self.monsterRes.speedId, self)
	self.baseAttriList[AttriType.DEFENCE] = Constants.BATTLE_DEFENCE_INIT
	-- 掉落点数
	self.baseAttriList[AttriType.POINT] = BattleFormula.GetValue(self.monsterRes.pointId, self)

	self.pendingFrameCount = _monsterRes.pendingTime == 0 and 0 or math_ceil(_monsterRes.pendingTime / Constants.BATTLE_FRAME_TIME)

	if _position and _position > 0 then
		self:SetPosition(_position, 0)
	end

	-- 血量初始化
	self.maxHP = self:GetMaxHP()
	self.curHP = _monsterHP or false

	-- 父类初始化
	self.super:Init()

	return true
end

-- 进入战斗 
function BattleMonster:Enter( ... )
	if self.pendingFrameCount ~= 0 then
		return
	end

	-- 父类进入
	self.super:Enter(...)

	self.curHP = self.curHP or self.maxHP
end

T_MONSTER_UPDATE = 0
function BattleMonster:Update( _deltaTime, ... )
	if self.isDie then
		return
	end

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

	-- 移动
	-- local time = os_clock()
	local speed = self:GetSpeed()
	-- T_MONSTER_UPDATE = T_MONSTER_UPDATE + os_clock() - time
	self:Move(speed)
end

function BattleMonster:GetMaxHP( ... )
	return self:GetAttribute(AttriType.HP)
end

function BattleMonster:GetSpeed( ... )
	return self:GetAttribute(AttriType.SPEED)
end

function BattleMonster:GetDefence( ... )
	return self:GetAttribute(AttriType.DEFENCE)
end

function BattleMonster:GetPoint( ... )
	return math_floor(self:GetAttribute(AttriType.POINT))
end

function BattleMonster:Move( _speed, ... )
	-- 死亡不移动
	if self.isDie then
		return
	end
	-- 眩晕不移动
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.DIZZY) then
		-- 通知前端更新怪物位置
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.MONSTERMOVE, self.player.playerId, self.monsterId, self.position, 0)
		return
	end
	-- 更新位置
	self:SetPosition(self.position + _speed, _speed)
end

-- _speed -1瞬移
function BattleMonster:SetPosition( _position, _speed, ... )
	self.position = _position
	if _position > BattleConstants.BATTLE_ROAD_LENGTH then
		-- 移除怪物
		self.player:RemoveMonster(self.monsterId, FLAGMAP(BattleUnitLeaveType.END))
		return
	end
	-- 通知前端更新怪物位置
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.MONSTERMOVE, self.player.playerId, self.monsterId, _position, _speed)
end

-- isRealDamage 真实伤害 无视护甲\免伤
function BattleMonster:OnAttackDamage( _attackerUnit, _damage, _isRealDamage, _damageEffectId, _damageType, ... )  
	if self.pendingFrameCount ~= 0 then
		return
	end

	-- 触发被击
	local triggerParam = BattleTriggerParam_New(self, _attackerUnit, { _attackerUnit }, tostring(_damage))
	gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKED, triggerParam)
	BattleTriggerParam_Destroy(triggerParam)

	local curHP = self.curHP
	local maxHP = self.maxHP
	-- _damage = _damage * 100
	local damage = _damage > curHP and curHP or _damage
	curHP = curHP - damage
	curHP = curHP > maxHP and maxHP or curHP
	self.curHP = curHP

	-- gBattleManager:AddBattleLog(string.format('Monster Attacked Frame[%d] Monster[%d] Attacker[%d] Damage[%d] HP[%d]', gBattleFrameCount, self.unitId, _attackerUnit.unitId, _damage, self.curHP))

	if G_SendGBCommand then
		-- 通知前端播放特效
		if _damageEffectId then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.EFFECT, true, self.player.playerId, self.unitId, _damageEffectId)
		end
		-- 通知前端更新怪物血量
		local __ = G_SendGBCommand and G_SendGBCommand(GBCommandType.MONSTERHP, self.player.playerId, self.monsterId, _damage, _damageType or BattleDamageType.NORMAL)
	end

	-- 校验怪物死亡
	if curHP <= 0 then
		self.curHP = 0
		self:OnMonsterDie(_attackerUnit)
	end
end

function BattleMonster:OnMonsterDie( _attackerUnit, ... )  
	if self.isDie then
		return
	end

	-- 触发死亡
	local triggerParam = BattleTriggerParam_New(self, _attackerUnit, { _attackerUnit }, nil)
	gBattleTrigger:FireTrigger(BattleTriggerType.DEATH, triggerParam)
	BattleTriggerParam_Destroy(triggerParam)

	-- 触发击杀
	triggerParam = BattleTriggerParam_New(_attackerUnit, _attackerUnit, nil, nil)
	gBattleTrigger:FireTrigger(BattleTriggerType.KILL, triggerParam)
	BattleTriggerParam_Destroy(triggerParam)

	-- 怪物死亡
	self.player:RemoveMonster(self.monsterId, FLAGMAP(BattleUnitLeaveType.DIE))
end

function BattleMonster:Clone( _monster, ... )
	if not _monster then
		return
	end

	self.curHP = _monster.curHP
end

function BattleMonster:IsValid( ... )
	return not (self.isDie or self.pendingFrameCount ~= 0)
end

function BattleMonster:CanAttack( ... )
	return not (self.isDie or HasBattleFlag(self.unitFlag, BattleUnitFlag.DIZZY))
end

function BattleMonster:IsHaloValid( ... )
	return not HasBattleFlag(self.unitFlag, BattleUnitFlag.DIZZY)
end
