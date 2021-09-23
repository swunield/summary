---
--- class GBMonster
-- @classmod GBMonster
GBMonster = xclass('GBMonster', GBUnit)

local os_time = os.time
local os_clock = os.time
local math_random = math.random

local CreateBattleMonster = LUBattleMonster.Create
local UpdateBattleMonster = LUBattleMonster.UpdateMonster
local UpdateBattleMonsterHP = LUBattleMonster.UpdateHP
local SetBattleMonsterTimeScale = LUBattleMonster.SetTimeScale
local SetBattleMonsterPosition = LUBattleMonster.SetPosition
local EndBattleUnit = LUBattleUnit.End
local DestroyBattleUnit = LUBattleUnit.Destroy
local OnUnitTeleport = LUBattleUnit.OnUnitTeleport
local PlaySound = AudioManager.PlaySound

---Constructor
function GBMonster:ctor( ... )
	self.monster = false 				-- 战斗逻辑怪物

	self.position = 0 					-- 显示层位置
	self.speed = 0 						-- 显示层速度，每秒
	self.logicSpeed = 0					-- 逻辑速度，每帧

	self.hpPercent = -1					-- 血量百分比
	self.timeScale = -1					-- 时间系数
	self.baseSpeed = 0					-- 基础速度
end

function GBMonster:Destroy( _leaveFlags, ... )
	if _leaveFlags and _leaveFlags[BattleUnitLeaveType.DIE] == 1 then
		-- 随机播死亡音效
		self:PlayDieAudio()
		if self.unitId ~= 0 then
			EndBattleUnit(self.unitId, GameStringType.OnMonsterDie)
		end
	else
		if self.unitId ~= 0 then
			EndBattleUnit(self.unitId, GameStringType.OnMonsterLeave)
		end
	end

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
	self.unitId = self.monster.unitId
	self.baseSpeed = self.monster.baseAttriList[AttriType.SPEED] / Constants.BATTLE_FPS

	self:CheckFrameChasing('Init', function( ... )
		self.unitId = CreateBattleMonster(self.monster.unitId, self.monster.monsterRes.prefabName, GameStringType.MonsterPath, self.gbPlayer.objMonsterRoadId)
	end)

	-- 初始化血量
	self:UpdateHP(true)
	-- 初始化位置
	self:SetPosition(self.monster.position)

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
	if not curHP or not maxHP or (_isInit and curHP == maxHP) then
		return
	end
	self.hpPercent = curHP / maxHP
end

function GBMonster:Move( _position, _speed, ... )
	if _speed == 0 then
		if self.speed ~= 0 then
			self.timeScale = 0
		end
		self.speed = 0
		self.logicSpeed = 0
		return
	end
	-- 瞬移,强制设置位置
	if _speed == -1 then
		-- 原地播放瞬移特效
		gGBField:AddGBEffect(nil, self.gbPlayer, Constants.BATTLE_TELEPORT_EFFECT, self)
		self:SetPosition(_position)
		OnUnitTeleport(self.unitId)
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

	if self.logicSpeed ~= _speed then
		self.logicSpeed = _speed
		self.timeScale = _speed / self.baseSpeed
	end
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
	-- 向上向左时前面怪物层级低，向下向右时前面怪物层级高
	local zOrderFactor = ((endPoint.x < startPoint.x) or (endPoint.y > startPoint.y)) and -1 or 1
	local posX = startPoint.x + (endPoint.x - startPoint.x) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	local posY = startPoint.y + (endPoint.y - startPoint.y) * (_position - startPoint.z) / (endPoint.z - startPoint.z)
	local direction = startPoint.w
	self.position = _position
	self:CheckFrameChasing('UpdateMonster', function( ... )
		UpdateBattleMonster(self.unitId, posX, posY, zOrderFactor, direction, _position, self.hpPercent, self.timeScale)
		self.hpPercent = -1
		self.timeScale = -1
	end)
end

---- 播放死亡音效
local osTime      = 0    -- 系统时间
local dieTime     = 0    -- 下次播放时间
local dieInterval = 0.5  -- 最小播放间隔
local dieMinIndex = 1    -- 最小播放索引
local dieMaxIndex = 10    -- 最大播放索引
local dieIndexes  = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }  -- 播放索引列表
function GBMonster:PlayDieAudio( ... )
	if self.monster.monsterRes.type ~= MonsterType.NORMAL then
		return
	end
	osTime = os_time()
	if osTime < dieTime then
		return
	end
	-- local sounName ='AU_10200_monster_die_' .. math_random(dieMinIndex, dieMaxIndex)
	-- warn(sounName)
	PlaySound('AU_10100_monster_die_' .. dieIndexes[math_random(dieMinIndex, dieMaxIndex)])
	dieTime = osTime + dieInterval
end