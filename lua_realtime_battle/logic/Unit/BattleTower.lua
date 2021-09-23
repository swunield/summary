---
--- class BattleTower
-- @classmod BattleTower
-- 战斗塔
BattleTower = xclass('BattleTower', BattleUnit)

local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local math_ceil = math.ceil
local os_clock = os.clock
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy

local TSTower = gModel.TSTower
local TSStar = gModel.TSStar
local TS2Int = gModel.TS2Int
local TS3Int = gModel.TS3Int
local TS1Int1String = gModel.TS1Int1String

---Constructor
function BattleTower:ctor( ... )  
	self.super.unitType = BattleUnitType.TOWER

	self.towerId = 0						-- 实例id
	self.towerRes = false					-- 配置
	self.star = 0							-- 炮数量
	self.grade = 1							-- 阶级，战斗内等级
	self.level = 0							-- 等级，外部养成等级

	self.posIndex = 0						-- 位置索引

	self.replaceTargetId = 0				-- 替代的目标Id

	self.starList = {} 						-- 飞行道具发射源列表
	self.triggerFlagMap = {}				-- 触发器标记
	self.starAtkSpeed = 0
	self.starExtraSpeed = 0

	self.atkEffectId = 0					-- 攻击特效

	self.monsterDistanceList = false		-- 怪物距离数值表
	self.gradeBufferLayerList = {}			-- 升阶关联状态层
	self.hasNormalAttack = false
end

function BattleTower:Serialize( ... )
	local tTower = TSTower:new{}
	tTower.Id = self.towerId
	tTower.ResId = self.towerRes.id
	tTower.Star = self.star
	tTower.TargetResId = self.replaceTargetId ~= 0 and self.replaceTargetId or nil
	tTower.StarList = {}
	for i = 1, tTower.Star do
		local star = self.starList[i]
		local tStar = TSStar:new{}
		tStar.Speed = star.speed ~= 0 and star.speed or nil
		tStar.NextFireTime = star.nextFireTime ~= 0 and star.nextFireTime or nil
		tStar.FireInterval = star.fireInterval ~= 0 and star.fireInterval or nil
		tStar.ExtraSpeed = star.extraSpeed ~= 0 and star.extraSpeed or nil
		tStar.NextExtraFireTime = star.nextExtraFireTime ~= 0 and star.nextExtraFireTime or nil
		tStar.ExtraFireInterval = star.extraFireInterval ~= 0 and star.extraFireInterval or nil
		tStar.ExtraFreezeTime = star.extraFreezeTime ~= 0 and star.extraFreezeTime or nil
		table_insert(tTower.StarList, tStar)
	end
	tTower.StarAtkSpeed = self.starAtkSpeed
	tTower.StarExtraSpeed = self.starExtraSpeed
	for paramType, param in pairs(self.paramMap) do
		if not tTower.ParamList then
			tTower.ParamList = {}
		end
		local tValue = TS3Int:new{}
		tValue.Arg0 = paramType
		tValue.Arg1 = param.value
		tValue.Arg2 = param.nextValue ~= 0 and param.nextValue or nil
		table_insert(tTower.ParamList, tValue)
	end
	for triggerType, triggerValue in pairs(self.triggerFlagMap) do
		if not tTower.TriggerFlagList then
			tTower.TriggerFlagList = {}
		end
		local tValue = TS1Int1String:new{}
		tValue.Arg0 = triggerType
		tValue.Arg1 = triggerValue
		table_insert(tTower.TriggerFlagList, tValue)
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
			speed = tStar.Speed or 0,
			nextFireTime = tStar.NextFireTime or 0, 
			fireInterval = tStar.FireInterval or 0,
			extraSpeed = tStar.ExtraSpeed or 0, 
			nextExtraFireTime = tStar.NextExtraFireTime or 0,
			extraFireInterval = tStar.ExtraFireInterval or 0,
			extraFreezeTime = tStar.ExtraFreezeTime or 0,
		})
	end
	self.starAtkSpeed = _tTower.StarAtkSpeed
	self.starExtraSpeed = _tTower.StarExtraSpeed
	self.replaceTargetId = _tTower.TargetResId or 0
	if _tTower.ParamList then
		for i = 1, #_tTower.ParamList do
			local tValue = _tTower.ParamList[i]
			self.paramMap[tValue.Arg0].value = tValue.Arg1
			self.paramMap[tValue.Arg0].nextValue = tValue.Arg2
		end
	end
	if _tTower.TriggerFlagList then
		for i = 1, #_tTower.TriggerFlagList do
			local tValue = _tTower.TriggerFlagList[i]
			self.triggerFlagMap[tValue.Arg0] = tValue.Arg1
			-- 触发标记改变
			self:OnTriggerFlagChange(tValue.Arg0, tValue.Arg1)
		end
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.ADDTOWER, self.player.playerId, self.towerRes, self.star, self.posIndex, self)
		local connectParam = self.paramMap[BattleParamType.CONNECTCOUNT]
		if connectParam then
			local timeScale = connectParam.value <= 1 and 0 or (1 + (connectParam.value - 2) * 0.4)
			_ = G_SendGBCommand and G_SendGBCommand(GBCommandType.TIMESCALE, self.unitId, timeScale)
		end
		self:NotifyAllUnitFlag()
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
	self.atkEffectId = _towerRes.atkEffectIds[1] or 0

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
	self.hasNormalAttack = self.towerRes.attack ~= 0

	-- 注册天赋
	self:RegisterTalentList(_towerRes.talentList, self)

	-- 注册觉醒天赋
	local awakenTalentId = _player:GetTowerAwaken(_towerRes.id)
	self:RegisterTalent(awakenTalentId, self)

	-- 父类初始化
	self.super:Init()

	-- 飞行道具发射源初始化
	self.starList = self:InitStar()

	-- 初始化参数
	self:InitParam(self.towerRes.paramList)

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

	self.starAtkSpeed = self:GetAttribute(AttriType.ATKSPEED)
	self.starExtraSpeed = self:GetAttribute(AttriType.EXATKSPEED)

	local starList = {}
	local interval = math_floor(self.starAtkSpeed / self.star)
	local extraInterval = math_floor(self.starExtraSpeed / self.star)
	-- 7星禁用额外攻击
	if self.star == Constants.BATTLE_MAX_STAR and self.towerRes.birthFlag == BattleUnitFlag.GROWUP then
		extraInterval = 0
	end
	for i = 1, self.star do
		table_insert(starList, { 
			speed = self.starAtkSpeed,
			nextFireTime = gBattleTime, 
			fireInterval = interval * i, 
			extraSpeed = self.starExtraSpeed,
			nextExtraFireTime = extraInterval == 0 and 0 or gBattleTime,
			extraFireInterval = extraInterval * i,
			extraFreezeTime = 0,
		})
	end
	return starList
end

T_PERF = 0
function BattleTower:Update( _deltaTime, ... )
	-- 更新状态
	local carryBufferList = self.carryBufferList
	local bufferCount = #carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end

	local canAttack = not HasBattleFlag(self.unitFlag, BattleUnitFlag.SILENCE)
	local battleTime = gBattleTime
	local starCount = self.star
	local starList = self.starList
	local hasNormalAttack = self.hasNormalAttack

	-- 发射子弹
	for i = 1, starCount do
		local star = starList[i]
		-- 普攻
		if hasNormalAttack then
			-- 发射
			if battleTime >= star.nextFireTime + star.fireInterval then
				-- 下次发射时间
				if i == 1 then
					self.starAtkSpeed = self:GetAttribute(AttriType.ATKSPEED)
				end
				local atkSpeed = self.starAtkSpeed
				star.nextFireTime = star.nextFireTime + star.speed
				star.speed = atkSpeed
				star.fireInterval = math_floor(atkSpeed / starCount) * i
				local targets = false
				if canAttack then
					-- 寻找目标，并确定命中时间
					local targetId = self:GetTargetId()
					targets = BattleTarget.FindTarget(targetId, self)
					local monster = #targets > 0 and targets[1] or false
					if monster then
						-- 总攻击次数
						local attackTimes = 0
						local attackTimesParam = self.paramMap[BattleParamType.ATTACKTIMES]
						if attackTimesParam then
							attackTimesParam.value = attackTimesParam.value + 1
							attackTimes = attackTimesParam.value
						end
						-- 插入子弹
						local hitFrame = gBattleFrameCount + self:GetPositionDistance(monster.position)
						local damage = self:GetAttribute(AttriType.ATTACK)
						self.player:AddMissile(self, monster.unitId, damage, hitFrame, self.atkEffectId, i, attackTimes)
					end
				end
				self.curTargets = targets
			end
		end
		-- 附属行为
		if star.nextExtraFireTime ~= 0 then
			if not canAttack then
				star.extraFreezeTime = star.extraFreezeTime + _deltaTime
			elseif battleTime >= star.nextExtraFireTime + star.extraFireInterval + star.extraFreezeTime then
				-- 触发附属行为
				local extraAttackTimes = 0
				local lastStarExtraAttackTimes = 0
				local extraAttackTimesParam = self.paramMap[BattleParamType.EXTRAATTACKTIMES]
				if extraAttackTimesParam then
					extraAttackTimesParam.value = extraAttackTimesParam.value + 1
					extraAttackTimes = extraAttackTimesParam.value
					lastStarExtraAttackTimes = i == starCount and math_floor(extraAttackTimes / starCount) or 0
				end
				local triggerParam = BattleTriggerParam_New(self, self, nil, { starIndex = i, attackTimes = extraAttackTimes, isLastStar = i == starCount, lastStarAttackTimes = lastStarExtraAttackTimes })
				gBattleTrigger:FireTrigger(BattleTriggerType.EXATTACK, triggerParam)
				BattleTriggerParam_Destroy(triggerParam)
				-- 下次发射时间
				if i == 1 then
					self.starExtraSpeed = self:GetAttribute(AttriType.EXATKSPEED)
				end
				local exAtkSpeed = self.starExtraSpeed
				star.nextExtraFireTime = star.nextExtraFireTime + star.extraSpeed + star.extraFreezeTime
				star.extraSpeed = exAtkSpeed
				star.extraFireInterval = math_floor(exAtkSpeed / starCount) * i
				star.extraFreezeTime = 0
			end
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
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.LOCKRANDOM) then
		targetId = Constants.BATTLE_LOCKRANDOM_TARGET_ID
		return targetId
	end
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.LOCKFIRST) then
		targetId = Constants.BATTLE_LOCKFIRST_TARGET_ID
		return targetId
	end
	if self.replaceTargetId ~= 0 then
		targetId = self.replaceTargetId
	end
	return targetId
end

function BattleTower:RefreshTowerConnect( _list, ... )
	local connectParam = self.paramMap[BattleParamType.CONNECTCOUNT]
	if not connectParam then
		return
	end
	connectParam.value = 0
	local nextToPosList = BattleConstants.BATTLE_TOWER_CROSS_MAP[self.posIndex]
	for i = 1, #nextToPosList do
		local nextToTower = self.player.towerList[nextToPosList[i]]
		if nextToTower and HasBattleFlag(nextToTower.unitFlag, BattleUnitFlag.CONNECT) and nextToTower.paramMap[BattleParamType.CONNECTCOUNT].value == -1 then
			nextToTower:RefreshTowerConnect(_list)
		end 
	end
	table_insert(_list, self)
end

function BattleTower:SetConnectCount( _count, ... )
	local paramMap = self.paramMap
	local connectParam = paramMap[BattleParamType.CONNECTCOUNT]
	if not connectParam then
		return
	end
	local curConnectParam = paramMap[BattleParamType.CURCONNECTCOUNT]
	if not curConnectParam then
		return
	end
	connectParam.value = _count
	if curConnectParam.value == _count then
		return
	end
	curConnectParam.value = _count
	-- 添加Buffer
	self:AddBuffer((Constants.BATTLE_CONNECT_BUFFER + self.towerRes.level) * 10 + 1, self, false)
	-- 通知前端刷新速度
	local timeScale = _count <= 1 and 0 or (1 + (_count - 2) * 0.4)
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.TIMESCALE, self.unitId, timeScale)
end                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   

function BattleTower:GetConnectCount( ... )
	local connectParam = self.paramMap[BattleParamType.CONNECTCOUNT]
	return connectParam and connectParam.value or 0
end

function BattleTower:ResetConnectCount( ... )
	local connectParam = self.paramMap[BattleParamType.CONNECTCOUNT]
	if connectParam then
		connectParam.value = -1
	end
end

-- 是否可以合成
local MergeFlagMap = { 
	[BattleUnitFlag.REPRODUCE] = BattleUnitFlag.REPRODUCE, 
	[BattleUnitFlag.SUMMON] = BattleUnitFlag.SUMMON, 
	[BattleUnitFlag.COMBO] = BattleUnitFlag.COMBO,
	[BattleUnitFlag.KILL] = BattleUnitFlag.KILL,
	[BattleUnitFlag.HACKER] = BattleUnitFlag.HACKER
}
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
	if self:CanRebuild(_targetTower) then
		return true, BattleTowerMergeType.REBUILD, 0
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
	local mergeUnitFlag = MergeFlagMap[towerRes.birthFlag] or MergeFlagMap[targetTowerRes.birthFlag] or 0
	return true, BattleTowerMergeType.MERGE, mergeUnitFlag
end

-- 是否可以交换
function BattleTower:CanExchange( _targetTower,  ... )
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.EXCHANGE
end

-- 是否可以复制
function BattleTower:CanCopy( _targetTower, ... )
	if _targetTower.towerRes.id == self.towerRes.id then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.COPY
end

-- 是否可以营养
function BattleTower:CanFix( _targetTower, ... )
	if self.star == Constants.BATTLE_MAX_STAR then
		return false
	end
	return self.towerRes.birthFlag == BattleUnitFlag.FIX
end

-- 是否可以重构
function BattleTower:CanRebuild( _targetTower, ... )
	return HasBattleFlag(self.unitFlag, BattleUnitFlag.REBUILD)
end

-- 是否可以攻击
function BattleTower:CanAttack( ... )
	return not HasBattleFlag(self.unitFlag, BattleUnitFlag.SILENCE)
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

function BattleTower:FireTrigger( _isFlagTrigger, _triggerType, _triggerValue, _towerBaseId, ... )
	-- 没有天生触发器标识
	if _isFlagTrigger and _triggerType ~= self.towerRes.triggerFlag then
		return
	end
	if _towerBaseId and self.towerRes.baseId ~= _towerBaseId then
		return
	end
	-- 触发器值没变
	_triggerValue = tostring(_triggerValue)
	if self.triggerFlagMap[_triggerType] == _triggerValue then
		return
	end
	self.triggerFlagMap[_triggerType] = _triggerValue
	-- 触发标记改变
	self:OnTriggerFlagChange(_triggerType, _triggerValue)

	local triggerParam = BattleTriggerParam_New(self, nil, nil, _triggerValue)
	gBattleTrigger:FireTrigger(_triggerType, triggerParam, self)
	BattleTriggerParam_Destroy(triggerParam)
end

local TriggerFlagSwitcher = {
	[BattleTriggerType.TRIGGERSTATE] = function( self, _flag )
		local atkEffectIds = self.towerRes.atkEffectIds
		_flag = tonumber(_flag)
		self.atkEffectId = atkEffectIds[_flag] or atkEffectIds[1] or 0
	end
}

function BattleTower:OnTriggerFlagChange( _triggerType, _flag )
	local switcher = TriggerFlagSwitcher[_triggerType]
	if switcher then
		switcher(self, _flag)
	end
end

function BattleTower:GetPositionDistance( _position, ... )
	local distanceIndex = math_ceil(_position / BattleConstants.BATTLE_ROAD_UNIT_LENGTH)
	if distanceIndex == 0 then
		distanceIndex = 1
	end
	return self.monsterDistanceList[distanceIndex] or 15
end

function BattleTower:SetPosIndex( _posIndex, ... )
	self.posIndex = _posIndex
	-- 距离数值表
	self.monsterDistanceList = BattleMonsterDistance[_posIndex]
end

function BattleTower:RefreshSameMonsterAttackTimes( _monster, ... )
	local paramMap = self.paramMap
	local sameMonsterParam = paramMap[BattleParamType.SAMEMONSTERATTACKTIMES]
	if sameMonsterParam then
		local lastMonsterParam = paramMap[BattleParamType.LASTMONSTER]
		sameMonsterParam.value = lastMonsterParam.value == _monster.monsterId and sameMonsterParam.value + 1 or 1
		lastMonsterParam.value = _monster.monsterId
		return sameMonsterParam.value
	end
	return -1
end