---
--- class BattleTower
-- @classmod BattleTower
-- 战斗塔
class('BattleTower', BattleUnit)

local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local math_ceil = math.ceil
local os_clock = os.clock
local BattleTriggerParam_New = BattleTriggerParam.New

local TSTower = gModel.TSTower
local TSStar = gModel.TSStar

---Constructor
function BattleTower:ctor( ... )  
	self.super = Super( ...)
	self.super.unitType = BattleUnitType.TOWER

	self.towerId = 0						-- 实例id
	self.towerRes = false					-- 配置
	self.star = 0							-- 炮数量
	self.grade = 1							-- 阶级，战斗内等级
	self.level = 0							-- 等级，外部养成等级

	self.posIndex = 0						-- 位置索引

	self.replaceTargetId = 0				-- 替代的目标Id

	self.starList = {} 						-- 飞行道具发射源列表
	self.paramMap = {}						-- 参数列表
	self.triggerFlagMap = {}				-- 触发器标记

	self.monsterDistanceList = false		-- 怪物距离数值表
	self.gradeBufferLayerList = {}			-- 升阶关联状态层
end

function BattleTower:Serialize( ... )
	local tTower = TSTower:new{}
	tTower.Id = self.towerId
	tTower.ResId = self.towerRes.id
	tTower.Star = self.star
	tTower.TargetResId = self.replaceTargetId ~= 0 and self.replaceTargetId or nil
	tTower.StarList = {}
	for i = 1, #self.starList do
		local star = self.starList[i]
		local tStar = TSStar:new{}
		tStar.NextFireTime = star.nextFireTime ~= 0 and star.nextFireTime or nil
		tStar.NextExtraFireTime = star.nextExtraFireTime ~= 0 and star.nextExtraFireTime or nil
		tStar.FireInterval = star.fireInterval ~= 0 and star.fireInterval or nil
		tStar.ExtraFireInterval = star.extraFireInterval ~= 0 and star.extraFireInterval or nil
		table_insert(tTower.StarList, tStar)
	end
	for paramType, paramValue in pairs(self.paramMap) do
		if not tTower.ParamMap then
			tTower.ParamMap = {}
		end
		tTower.ParamMap[paramType] = paramValue
	end
	for triggerType, triggerValue in pairs(self.triggerFlagMap) do
		if not tTower.TriggerFlagMap then
			tTower.TriggerFlagMap = {}
		end
		tTower.TriggerFlagMap[triggerType] = triggerValue
	end
	tTower.Unit = self.super:Serialize()
	return tTower
end

function BattleTower:DeSerialize( _tTower, _player, _posIndex, ... )
	if not _tTower or not _player or not _posIndex then
		return
	end
	self:Init(GameResMgr.GetBattleTowerRes(_tTower.ResId), _tTower.Star, _tTower.Id, _posIndex, _player)
	self.super:DeSerialize(_tTower.Unit)
	self.starList = {}
	for i = 1, #_tTower.StarList do
		local tStar = _tTower.StarList[i]
		table_insert(self.starList, {
			nextFireTime = tStar.NextFireTime or 0, 
			fireInterval = tStar.FireInterval or 0, 
			nextExtraFireTime = tStar.NextExtraFireTime or 0,
			extraFireInterval = tStar.ExtraFireInterval or 0,
		})
	end
	self.replaceTargetId = _tTower.TargetResId or 0
	if _tTower.ParamMap then
		for paramType, paramValue in pairs(_tTower.ParamMap) do
			self.paramMap[paramType] = paramValue
		end
	end
	if _tTower.TriggerFlagMap then
		for triggerType, triggerValue in pairs(_tTower.TriggerFlagMap) do
			self.triggerFlagMap[triggerType] = triggerValue
		end
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDTOWER, self.player.playerId, self.towerRes, self.star, self.posIndex, self)
		local curConnectCount = self.paramMap[CURCONNECTCOUNT]
		if curConnectCount then
			local timeScale = curConnectCount <= 1 and 0 or (1 + (connectCount - 2) * 0.4)
			_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.TIMESCALE, self.unitId, timeScale)
		end
	end)
end

function BattleTower:Destroy( _leaveFlags, ... )  
	-- 父类销毁
	self.super:Destroy(_leaveFlags, ...)
end

function BattleTower:Init( _towerRes, _star, _towerId, _posIndex, _player, ... )  
	if not _towerRes then
		return false
	end

	self.towerId = _towerId
	self.player = _player
	self.unit = self
	self.unitId = self:GenerateUnitId(self.towerId)
	self.towerRes = _towerRes
	self.star = _star
	self.posIndex = _posIndex
	self.grade = _player:GetTowerGrade(_towerRes.id)
	self.level = _towerRes.level

	-- 初始标记
	if self.towerRes.birthFlag ~= 0 then
		self:AddUnitFlag(self.towerRes.birthFlag)
	end

	-- 属性基础值
	self.baseAttriList[AttriType.ATTACK] = BattleFormula.GetValue(self.towerRes.attack, self, nil) 
	self.baseAttriList[AttriType.ATKSPEED] = BattleFormula.GetValue(self.towerRes.atkSpeed, self, nil)
	self.baseAttriList[AttriType.EXATKSPEED] = BattleFormula.GetValue(self.towerRes.extraAtkSpeed, self, nil)
	self.baseAttriList[AttriType.CRITICAL] = Constants.BATTLE_CRITICALRATE_INIT
	self.baseAttriList[AttriType.CRITICALSCALE] = Constants.BATTLE_CRITICALSCALE_INIT + _player.criticalScale

	-- 注册天赋
	self:RegisterTalentList(_towerRes.talentList, self)

	-- 父类初始化
	self.super:Init()

	-- 飞行道具发射源初始化
	self.starList = self:InitStar()

	-- 初始化参数
	for i = 1, #self.towerRes.paramList do
		local paramType = self.towerRes.paramList[i]
		self.paramMap[paramType] = BattleConstants.BATTLE_PARAM_DEFAULT[paramType]
	end

	-- 距离数值表
	self.monsterDistanceList = BattleMonsterDistance[_posIndex]

	return true
end

-- 飞行道具发射源初始化
function BattleTower:InitStar( ... ) 
	-- 序列化期间禁用
	if gSnapShotPushing then
		return false
	end

	local starList = {}
	local interval = math_floor(self:GetAtkSpeed() / self.star)
	local extraInterval = math_floor(self:GetExAtkSpeed() / self.star)
	-- 7星禁用额外攻击
	if self.star == Constants.BATTLE_MAX_STAR and self.towerRes.birthFlag == BattleUnitFlag.GROWUP then
		extraInterval = 0
	end
	for i = 1, self.star do
		table_insert(starList, { 
			nextFireTime = gBattleTime + self:GetAtkSpeed(), 
			fireInterval = interval * (i - 1), 
			nextExtraFireTime = extraInterval == 0 and 0 or (gBattleTime + self:GetExAtkSpeed()),
			extraFireInterval = extraInterval * (i - 1),
		})
	end
	return starList
end

T_PERF = 0

function BattleTower:Update( _deltaTime, ... )
	-- 父类更新
	self.super:Update(_deltaTime, ...)

	-- 发射子弹
	for i = 1, self.star do
		local star = self.starList[i]
		-- 普攻
		-- local time = os_clock()
		-- T_PERF = T_PERF + os_clock() - time
		if self.towerRes.attack ~= 0 then
			-- 发射
			if gBattleTime >= star.nextFireTime + star.fireInterval then
				-- 下次发射时间
				local atkSpeed = self:GetAtkSpeed()
				star.nextFireTime = star.nextFireTime + atkSpeed
				star.fireInterval = math_floor(atkSpeed / self.star) * (i - 1)
				if self:CanAttack() then
					-- 寻找目标，并确定命中时间
					local targetId = self:GetTargetId()
					local targets = BattleTarget.FindTarget(targetId, self)
					local monster = #targets > 0 and targets[1] or false
					if monster then
						-- 同一怪物攻击次数
						local paramMap = self.paramMap
						local lastMonsterId = paramMap[BattleParamType.LASTMONSTER]
						if lastMonsterId then
							paramMap[BattleParamType.SAMEMONSTERATTACKTIMES] = lastMonsterId == monster.monsterId and paramMap[BattleParamType.SAMEMONSTERATTACKTIMES] + 1 or 1
							paramMap[BattleParamType.LASTMONSTER] = monster.monsterId
						end
						local attackTimes = paramMap[BattleParamType.ATTACKTIMES]
						if attackTimes then
							attackTimes = attackTimes + 1
							paramMap[BattleParamType.ATTACKTIMES] = attackTimes
						end
						attackTimes = attackTimes or 0
						-- 插入子弹
						local distanceIndex = math_ceil(monster.position / BattleConstants.BATTLE_ROAD_UNIT_LENGTH)
						if distanceIndex == 0 then
							distanceIndex = 1
						end
						local missileFrameCount = self.monsterDistanceList[distanceIndex]
						local hitFrame = gBattleFrameCount + missileFrameCount
						self.player:AddMissile(self, monster.unitId, self:GetAttack(), hitFrame, self.towerRes.atkEffectId, i, attackTimes)
					end
				end
			end
		end
		-- 附属行为
		if star.nextExtraFireTime ~= 0 and gBattleTime >= star.nextExtraFireTime + star.extraFireInterval then
			-- 触发附属行为
			local extraAttackTimes = self.paramMap[BattleParamType.EXTRAATTACKTIMES]
			if extraAttackTimes then
				extraAttackTimes = extraAttackTimes + 1
				self.paramMap[BattleParamType.EXTRAATTACKTIMES] = extraAttackTimes
			end
			extraAttackTimes = extraAttackTimes or 0
			local triggerParam = BattleTriggerParam_New(self, self, nil, { starIndex = i, attackTimes = extraAttackTimes })
			gBattleTrigger:FireTrigger(BattleTriggerType.EXATTACK, triggerParam)
			-- 下次发射时间
			local exAtkSpeed = self:GetExAtkSpeed()
			star.nextExtraFireTime = star.nextExtraFireTime + exAtkSpeed
			star.extraFireInterval = math_floor(exAtkSpeed / self.star) * (i - 1)
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
	if not self.paramMap[BattleParamType.CONNECTCOUNT] then
		return
	end
	self.paramMap[BattleParamType.CONNECTCOUNT] = 0
	local nextToPosList = BattleConstants.BATTLE_TOWER_CROSS_MAP[self.posIndex]
	for i = 1, #nextToPosList do
		local nextToTower = self.player.towerList[nextToPosList[i]]
		if nextToTower and nextToTower:HasUnitFlag(BattleUnitFlag.CONNECT) and nextToTower.paramMap[BattleParamType.CONNECTCOUNT] == -1 then
			nextToTower:RefreshTowerConnect(_list)
		end 
	end
	table_insert(_list, self)
end

function BattleTower:SetConnectCount( _count, ... )
	local paramMap = self.paramMap
	local connectCount = paramMap[BattleParamType.CONNECTCOUNT]
	if not connectCount then
		return
	end
	local curConnectCount = paramMap[BattleParamType.CURCONNECTCOUNT]
	if not curConnectCount then
		return
	end
	connectCount = _count
	paramMap[BattleParamType.CONNECTCOUNT] = connectCount
	if curConnectCount == connectCount then
		return
	end
	curConnectCount = connectCount
	paramMap[BattleParamType.CURCONNECTCOUNT] = curConnectCount
	-- 添加Buffer
	self:AddBuffer((Constants.BATTLE_CONNECT_BUFFER + self.towerRes.level) * 10 + 1, self, false)
	-- 通知前端刷新速度
	local timeScale = curConnectCount <= 1 and 0 or (1 + (connectCount - 2) * 0.4)
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.TIMESCALE, self.unitId, timeScale)
end                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   

function BattleTower:GetConnectCount( ... )
	return self.paramMap[BattleParamType.CONNECTCOUNT]
end

function BattleTower:ResetConnectCount( ... )
	if self.paramMap[BattleParamType.CONNECTCOUNT] then
		self.paramMap[BattleParamType.CONNECTCOUNT] = -1
	end
end

-- 是否可以合成
function BattleTower:CanMerge( _targetTower, ... )
	if not _targetTower then
		return false, nil, 0
	end
	if _targetTower.towerId == self.towerId then
		return false, nil, 0
	end
	if _targetTower.star ~= self.star then
		return false, nil, 0
	end
	if self:CanExchange(_targetTower) then
		return true, BattleTowerMergeType.EXCHANGE, 0
	end
	if self:CanCopy(_targetTower) then
		return true, BattleTowerMergeType.COPY, 0
	end
	-- 已满级
	if self.star == Constants.BATTLE_MAX_STAR then
		return false, nil, 0
	end
	if self:CanFix(_targetTower) then
		return true, BattleTowerMergeType.FIX, 0
	end
	local targetTowerRes = _targetTower.towerRes
	local towerRes = self.towerRes
	if targetTowerRes.id ~= towerRes.id and towerRes.birthFlag ~= BattleUnitFlag.FIT and targetTowerRes.birthFlag ~= BattleUnitFlag.FIT then
		return false, nil, 0
	end
	local mergeUnitFlag = 0
	if towerRes.birthFlag == BattleUnitFlag.REPRODUCE or targetTowerRes.birthFlag == BattleUnitFlag.REPRODUCE then
		-- 繁衍
		mergeUnitFlag = BattleUnitFlag.REPRODUCE
	elseif towerRes.birthFlag == BattleUnitFlag.SUMMON or targetTowerRes.birthFlag == BattleUnitFlag.SUMMON then
		-- 召唤
		mergeUnitFlag = BattleUnitFlag.SUMMON
	end
	return true, BattleTowerMergeType.MERGE, mergeUnitFlag
end

-- 是否可以交换
function BattleTower:CanExchange( _targetTower,  ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.EXCHANGE
end

-- 是否可以复制
function BattleTower:CanCopy( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.COPY
end

-- 是否可以营养
function BattleTower:CanFix( _targetTower, ... )
	if not _targetTower then
		return false
	end
	if _targetTower.star ~= self.star then
		return false
	end
	if self.star == Constants.BATTLE_MAX_STAR then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.FIX
end

-- 是否可以攻击
function BattleTower:CanAttack( ... )
	return not self:HasUnitFlag(BattleUnitFlag.SILENCE)
end

function BattleTower:OnUpgrade( _grade, ... )
	if self.grade == _grade then
		return
	end
	self.grade = _grade
	self:UpdateBaseAttribute(AttriType.ATTACK, BattleFormula.GetValue(self.towerRes.attack, self, nil))
	self:UpdateBaseAttribute(AttriType.ATKSPEED, BattleFormula.GetValue(self.towerRes.atkSpeed, self, nil))
	self:UpdateBaseAttribute(AttriType.EXATKSPEED, BattleFormula.GetValue(self.towerRes.extraAtkSpeed, self, nil))
end

function BattleTower:GetGrade( ... )
	return self.grade
end

function BattleTower:GetLevel( ... )
	return self.level
end

function BattleTower:FireTrigger( _isFlagTrigger, _triggerType, _triggerValue, ... )
	-- 没有天生触发器标识
	if _isFlagTrigger and _triggerType ~= self.towerRes.triggerFlag then
		return
	end
	-- 触发器值没变
	_triggerValue = tostring(_triggerValue)
	if self.triggerFlagMap[_triggerType] == _triggerValue then
		return
	end
	self.triggerFlagMap[_triggerType] = _triggerValue

	local triggerParam = BattleTriggerParam_New(self, nil, nil, _triggerValue)
	gBattleTrigger:FireTrigger(_triggerType, triggerParam, self)
end

classend()