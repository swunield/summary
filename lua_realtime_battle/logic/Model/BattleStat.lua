---
--- class BattleStat
-- @classmod BattleStat
BattleStat = xclass('BattleStat')

---Constructor
function BattleStat:ctor( ... )
	self.totalDamage = 0				-- 伤害总计
	self.totalKillMonster = 0			-- 怪物总击杀数量
	self.totalMonster = 0				-- 当前怪物总数量
	self.totalPoint = 100				-- 总获得点数
	self.totalMonsterPoint = 0			-- 怪物击杀Point
	self.totalRollPoint = 0				-- 总Roll塔消耗点数
	self.totalMagicPoint = 0			-- 总魔法消耗点数
	self.totalMagicTimes = 0			-- 总魔法次数
	self.curDamagePerSecond = 0			-- 当前每秒伤害
	self.damagePerSecond = 0			-- 每秒伤害
	self.magicList = ''					-- 魔法使用列表
	self.totalMissile = 0				-- 子弹总计
	self.totalMissMissile = 0			-- 子弹丢失总计
	self.pendingMonsterCount = 0		-- 缓冲怪物数量
end

function BattleStat:AddDamage( _damage, ... )
	self.totalDamage = _damage + self.totalDamage
	self.curDamagePerSecond = self.curDamagePerSecond + _damage
end

function BattleStat:AddKillMonster( ... )
	self.totalKillMonster = self.totalKillMonster + 1
	self.totalMonster = self.totalMonster - 1
end

function BattleStat:AddMonster( ... )
	self.totalMonster = self.totalMonster + 1
end

function BattleStat:AddPoint( _point, ... )
	self.totalPoint = self.totalPoint + _point
end

function BattleStat:AddMonsterPoint( _point, ... )
	self.totalMonsterPoint = self.totalMonsterPoint + _point
end

function BattleStat:AddRollPoint( _point, ... )
	self.totalRollPoint = self.totalRollPoint + _point
end

function BattleStat:ResetSecondDamage( ... )
	self.damagePerSecond = self.curDamagePerSecond
	self.curDamagePerSecond = 0
end

function BattleStat:AddMissile( ... )
	self.totalMissile = self.totalMissile + 1
end

function BattleStat:AddMissMissile( ... )
	self.totalMissMissile = self.totalMissMissile + 1
end

function BattleStat:AddPendingMonster( _isAdd, ... )
	self.pendingMonsterCount = self.pendingMonsterCount + (_isAdd and 1 or -1)
end