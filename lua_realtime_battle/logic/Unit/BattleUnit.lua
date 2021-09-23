---
--- class BattleUnit
-- @classmod BattleUnit
-- 战斗单位，塔、怪物、碰撞等
BattleUnit = xclass('BattleUnit')

local table_insert = table.insert
local table_remove = table.remove
local os_clock = os.clock
local math_floor = math.floor
local string_format = string.format
local BattleTriggerParam_New = BattleTriggerParam.New
local BattleTriggerParam_Destroy = BattleTriggerParam.Destroy
local FLAGMAP = Utils.BuildFlagMap

local TSUnit = gModel.TSUnit

---Constructor
function BattleUnit:ctor( ... )
	self.unitType = false							-- 单位类型
	self.unitId = 0 								-- 单位Id，类型+玩家Id+实例Id
	self.unit = false

	self.carryAttribute = AttributeList()			-- 属性列表
	self.attriList = {}								-- 属性值列表
	self.baseAttriList = {}							-- 属性基础值列表

	self.unitFlag = {}								-- 单位标记
	self.carryBufferList = {}						-- 单位携带状态列表

	self.paramMap = {}								-- 参数Map
	self.isParamDirty = false						-- 参数Map脏标记

	self.player = false 							-- 玩家
end

function BattleUnit:Serialize( ... )
	local tUnit = TSUnit:new{}
	tUnit.Flag = SerializeBattleFlag(self.unitFlag)
	if #self.carryBufferList > 0 then
		tUnit.BufferList = {}
		for i = 1, #self.carryBufferList do
			table_insert(tUnit.BufferList, self.carryBufferList[i]:Serialize())
		end
	end
	tUnit.AttributeList = self.carryAttribute:Serialize()
	return tUnit
end

function BattleUnit:DeSerialize( _tUnit, ... )
	if not _tUnit then
		return
	end
	DeSerializeBattleFlag(self.unitFlag, _tUnit.Flag)
	self.carryAttribute:DeSerialize(_tUnit.AttributeList)
	if _tUnit.BufferList then
		for i = 1, #_tUnit.BufferList do
			local buffer = BattleBuffer()
			buffer:DeSerialize(_tUnit.BufferList[i], self.unit)
			table_insert(self.carryBufferList, buffer)
		end
	end
end

function BattleUnit:Destroy( _leaveFlags, ... )
	-- 触发离场
	self:Leave(_leaveFlags)
	-- 注销所有触发器
	gBattleTrigger:UnRegisterUnitAllActions(self)
	-- 移除所有携带状态
	self:RemoveAllBuffer()
	-- 增加死亡标记
	self:AddUnitFlag(BattleUnitFlag.DEATH)
end

function BattleUnit:Init( _enter )
	-- 添加到全局单位Map
	gBattleRecord:AddBattleUnit(self.unitId, self.unit)

	-- 进入
	if _enter then
		self.unit:Enter()
	end
end

function BattleUnit:Enter( _enterType, ... )
	-- 触发进场
	local enterType = _enterType or BattleUnitEnterType.CREATE
	local triggerParam = BattleTriggerParam_New(self.unit, nil, nil, enterType)
	gBattleTrigger:FireTrigger(BattleTriggerType.ENTER, triggerParam)
	BattleTriggerParam_Destroy(triggerParam)
end

function BattleUnit:Leave( _leaveFlags, ... )
	-- 触发离场
	local leaveFlags = _leaveFlags or FLAGMAP(BattleUnitLeaveType.ALL)
	local triggerParam = BattleTriggerParam_New(self, nil, nil, _leaveFlags)
	gBattleTrigger:FireTrigger(BattleTriggerType.LEAVE, triggerParam)
	BattleTriggerParam_Destroy(triggerParam)
end

function BattleUnit:Update( _deltaTime, ... )
	-- 更新状态
	local carryBufferList = self.carryBufferList
	local bufferCount = #carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end
end

function BattleUnit:InitParam( _paramList )
	for i = 1, #_paramList do
		local paramType = _paramList[i]
		local default = BattleConstants.BATTLE_PARAM_DEFAULT[paramType]
		if default and default.unitType == self.unitType then
			if not self.paramMap[paramType] then
				self.paramMap[paramType] = { value = default.value, nextValue = default.value, default = default }
			end
		end
	end
end

function BattleUnit:GetParamValue( _paramType, ... )
	local param = self.paramMap[_paramType]
	return param and param.value or 0
end

function BattleUnit:GenerateUnitId( _instanceId, ... )
	if not self.unitType or not self.player then
		return 0
	end
	return self.player.playerIndex * 100000000 + self.unitType * 1000000 + _instanceId
end

T_ATTRI = 0
function BattleUnit:GetAttribute( _attriType )
	if _attriType < AttriType.BASEMAX then
		local attriCache = self.attriList[_attriType]
		if attriCache and not attriCache.dirty then
			return attriCache.value
		end

		local percentType = _attriType + AttriType.BASEMAX
		local percent = self:GetAttributePercent(percentType)
		
		local baseAttri = self.baseAttriList[_attriType] or 0
		local attriValue = 0
		if _attriType == AttriType.ATKSPEED or _attriType == AttriType.EXATKSPEED then
			attriValue = (baseAttri + self:GetAttributeValue(_attriType)) / percent
		elseif _attriType == AttriType.SPEED then
			local extraSpeed = self:GetAttributePercent(AttriType.EXTRASPEED)
			attriValue = (baseAttri + self:GetAttributeValue(_attriType)) * percent * extraSpeed
		else
			attriValue = (baseAttri + self:GetAttributeValue(_attriType)) * percent
		end
		local valueLimit = BattleConstants.BATTLE_ATTRIBUTE_LIMIT[_attriType]
		local valueMin = valueLimit and valueLimit.min or false
		local valueMax = valueLimit and valueLimit.max or false
		if attriValue ~= 0 and valueMin and attriValue < valueMin then
			attriValue = valueMin
		end
		if valueMax and attriValue > valueMax then
			attriValue = valueMax
		end
		if _attriType == AttriType.SPEED then
			attriValue = math_floor(attriValue / Constants.BATTLE_FPS)
		else
			attriValue = math_floor(attriValue)
		end
		if not attriCache then
			attriCache = {}
			self.attriList[_attriType] = attriCache
		end
		attriCache.dirty = false
		attriCache.value = attriValue
		return attriValue
	end
	local baseAttri = self.baseAttriList[_attriType] or 0
	return baseAttri + self:GetAttributeValue(_attriType)
end

function BattleUnit:GetAttributeValue( _attriType )
	return self.carryAttribute:GetAttribute(_attriType)
end

function BattleUnit:GetAttributePercent( _attriType )
	if _attriType <= AttriType.BASEMAX then
		return 0
	end
	local percent = self.carryAttribute:GetAttribute(_attriType, nil, true)
	local percentLimit = BattleConstants.BATTLE_ATTRIBUTE_LIMIT[_attriType]
	if percentLimit then
		local percentMin = percentLimit.min
		local percentMax = percentLimit.max
		if percentMin and percent < percentMin then
			percent = percentMin
		end
		if percentMax and percent > percentMax then
			percent = percentMax
		end
	end
	return percent
end

function BattleUnit:UpdateBaseAttribute( _attriType, _value, ... )
	if _attriType > AttriType.BASEMAX then
		return
	end
	local baseAttri = self.baseAttriList[_attriType] or 0
	if baseAttri ~= _value then
		local attriCache = self.attriList[_attriType]
		if attriCache then
			attriCache.dirty = true
		end
	end
	self.baseAttriList[_attriType] = _value
end

function BattleUnit:UpdateCarryAttribute( _attriType, _branch, _value, _add, ... )
	local value, oldValue = self.carryAttribute:UpdateAttribute( _attriType, _branch, _value, _add, ...)
	if value ~= oldValue then
		local dirtyAttriType = _attriType
		if _attriType == AttriType.EXTRASPEED then
			dirtyAttriType = AttriType.SPEED
		elseif _attriType >= AttriType.BASEMAX and _attriType <= AttriType.BASEPERCENTMAX then
			dirtyAttriType = _attriType - AttriType.BASEMAX
		end
		local attriCache = self.attriList[dirtyAttriType]
		if attriCache then
			attriCache.dirty = true
		end
	end
	return value, oldValue
end

function BattleUnit:AddBuffer( _bufferResId, _owner, _useBetterLayer, ... )
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.DEATH) then
		return false
	end
	local bufferRes = GameResMgr.GetBattleBufferRes(_bufferResId)
	if not bufferRes then
		return false
	end
	-- 可免疫属性校验
	if self:CheckAttributeIgnore(nil, bufferRes, bufferRes.bufferType == BufferType.CONTROL) then
		return false
	end
	local bufferOverlapType = bufferRes.overlapType
	if bufferOverlapType ~= BufferOverlapType.SINGLE then
		local bufferCount = #self.carryBufferList
		-- 同ID的Buffer直接叠加
		for i = 1, bufferCount do
			local buffer = self.carryBufferList[i]
			if buffer.bufferRes.id == _bufferResId and buffer.owner.player.unitId == _owner.player.unitId then
				-- 添加层数
				buffer:AddBufferLayer(_owner, _useBetterLayer)
				-- Buffer添加
				self:OnBufferAdd(buffer, _owner)
				return buffer
			end
		end
	end
	-- 添加新Buffer实例
	local buffer = BattleBuffer()
	if not buffer:Init(_bufferResId, self, _owner) then
		return false
	end
	-- 添加层数
	buffer:AddBufferLayer(_owner, _useBetterLayer, true)
	-- 插入列表
	table_insert(self.carryBufferList, buffer)
	-- Buffer添加
	self:OnBufferAdd(buffer, _owner)
	return buffer
end

-- 校验部分状态免疫
function BattleUnit:CheckAttributeIgnore( _attriType, _bufferRes, _isControl, ... )
	if not _bufferRes and not _attriType then
		return false
	end
	if _isControl then
		-- 控制类Buff概率免疫
		local ignoreControlRate = self:GetAttribute(AttriType.IGNORECONTROL)
		if ignoreControlRate > 0 and gBattleRandNum:NextInt(s_PercentMax) <= ignoreControlRate then
			return true
		end
	end
	local attriType = _attriType or _bufferRes.valueTypeList[1]
	if not attriType then
		return false
	end
	if attriType < AttriType.STATE_MIN or attriType > AttriType.STATE_IGNORE then
		return false
	end
	-- 已经被标记的时候，不再添加状态
	local attriFlag = BattleUnitFlag.STATE_MIN + attriType - AttriType.STATE_MIN
	if HasBattleFlag(self.unitFlag, attriFlag) then
		return true
	end
	local ignoreRate = self:GetAttribute(attriType + AttriType.IGNORE_MIN - AttriType.STATE_MIN)
	if ignoreRate > 0 and gBattleRandNum:NextInt(s_PercentMax) <= ignoreRate then
		return true
	end
	return false
end

function BattleUnit:GetBufferByResId( _bufferResId, ... )
	local bufferCount = #self.carryBufferList
	for i = 1, bufferCount do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId then
			return buffer
		end
	end
	return false
end

function BattleUnit:RemoveBuffer( _buffer, ... )
	if not _buffer then
		return
	end
	-- 从状态列表移除
	local bufferCount = #self.carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _buffer.bufferId then
			-- 移出列表
			table_remove(self.carryBufferList, i)
			break
		end
	end
	-- Buffer移除
	self:OnBufferRemove(_buffer)
	-- Buffer销毁
	_buffer:Destroy()
end

function BattleUnit:RemoveBufferByBufferId( _bufferId, ... )
	if not _bufferId or _bufferId == 0 then
		return
	end
	-- 从状态列表移除
	local bufferCount = #self.carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _bufferId then
			-- 移出列表
			table_remove(self.carryBufferList, i)
			-- Buffer移除
			self:OnBufferRemove(buffer)
			-- Buffer销毁
			buffer:Destroy()
			break
		end
	end
end

function BattleUnit:RemoveBufferByResId( _bufferResId, _owner, _isRemoveAll, ... )
	local isRemoveAll = _isRemoveAll == nil and true or _isRemoveAll
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId and _owner.player.unitId == buffer.owner.player.unitId then
			-- 移出列表
			table_remove(self.carryBufferList, i)
			-- Buffer移除
			self:OnBufferRemove(buffer)
			-- Buffer销毁
			buffer:Destroy()
			-- 是否全部移除
			if not isRemoveAll then
				break
			end
		end
	end
end

function BattleUnit:RemoveBufferLayer( _bufferResId, _owner, _layerCount, ... )
	if _layerCount == 0 then
		self:RemoveBufferByResId(_bufferResId, _owner, false)
		return
	end

	local layerCount = _layerCount or 1
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId and _owner.player.unitId == buffer.owner.player.unitId then
			-- Buffer层数移除
			self:OnBufferLayerRemove(buffer, _owner, layerCount)
			for i = 1, layerCount do
				-- 层数减1
				buffer:RemoveBufferLayer(_owner and 0 or 1, _owner, nil, true)
			end
			break
		end
	end
end

function BattleUnit:RemoveBufferLayerByBufferId( _bufferId, _owner, _layerCount, ... )
	if not _bufferId or _bufferId == 0 then
		return
	end
	if _layerCount == 0 then
		self:RemoveBufferByBufferId(_bufferId)
		return
	end
	local layerCount = _layerCount or 1
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _bufferId then
			-- Buffer层数移除
			self:OnBufferLayerRemove(buffer, _owner, layerCount)
			for i = 1, layerCount do
				-- 层数减1
				buffer:RemoveBufferLayer(_owner and 0 or 1, _owner, nil, true)
			end
			break
		end
	end
end

function BattleUnit:HasBuffer( _bufferResId, ... )
	local bufferCount = #self.carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId then
			return true
		end
	end
	return false
end

-- 销毁全部状态
function BattleUnit:RemoveAllBuffer( ... )
	local bufferCount = #self.carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer then
			-- 销毁状态
			buffer:Destroy()
		end
	end
	self.carryBufferList = {}
	-- 全部Buffer移除
	self:OnAllBufferRemove()
end


function BattleUnit:OnBufferAdd( _buffer, _owner,... )
end

function BattleUnit:OnBufferRemove( _buffer, ... )
end

function BattleUnit:OnBufferLayerRemove( _buffer, _owner, _layerCount, ... )
end

function BattleUnit:OnAllBufferRemove( ... )
end

T_FLAG = 0
function BattleUnit:AddUnitFlag( _flagType, _flagValue, ... )
	if _flagType == BattleUnitFlag.DIZZY then
		-- 已经被晕过了，不能再晕了
		if HasBattleFlag(self.unitFlag, BattleUnitFlag.DIZZYED) then
			return
		end
		-- 眩晕标记
		self:AddBuffer(Constants.BATTLE_DIZZYED_BUFFER, self)
	end
	if AddBattleFlag(self.unitFlag, _flagType, _flagValue) then
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FLAG, self.unitId, _flagType, true)
	end
end

function BattleUnit:ClearUnitFlag( _flagType, _flagValue, ... )
	if ClearBattleFlag(self.unitFlag, _flagType, _flagValue) then
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FLAG, self.unitId, _flagType, false)
	end
end

function BattleUnit:HasUnitFlag( _flagType, ... )
	return HasBattleFlag(self.unitFlag, _flagType)
end

function BattleUnit:NotifyAllUnitFlag( ... )
	for flagType, flagValue in pairs(self.unitFlag) do
		if flagValue ~= 0 then
			local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.FLAG, self.unitId, flagType, true)
		end
	end
end

function BattleUnit:RegisterTalentList( _talentList, _owner, ... )
	if not _talentList or #_talentList == 0 then
		return false
	end
	local battleType = gBattleType
	local talentId = _talentList[battleType]
	talentId = talentId and talentId or _talentList[1]
	return self:RegisterTalent(talentId, _owner)
end

function BattleUnit:RegisterTalent( _talentId, _owner, ... )
	local talentRes = GameResMgr.GetTalentRes(_talentId)
	if not talentRes then
		return false
	end
	local actionCount = #talentRes.actionList
	for i = 1, actionCount do
		local actionId = talentRes.actionList[i]
		gBattleTrigger:RegisterAction(actionId, self, _owner)
	end
	return talentRes
end

function BattleUnit:UnRegisterTalent( _talentId, ... )
	local talentRes = GameResMgr.GetTalentRes(_talentId)
	if not talentRes then
		return
	end
	local actionCount = #talentRes.actionList
	for i = 1, actionCount do
		local actionId = talentRes.actionList[i]
		gBattleTrigger:UnRegisterAction(actionId, self)
	end
end

function BattleUnit:CalcDamage( _damage, _targetMonster, _ignoreSeckill, _seckillRate, _ignoreCritical, ... )
	-- 被黑客
	if HasBattleFlag(self.unitFlag, BattleUnitFlag.HACKED) then
		local hackerFactor = self:GetAttribute(AttriType.HACKED)
		_damage = math_floor(-_damage * hackerFactor / Constants.PERCENT_MAX)
		return _damage, false
	end

	local ignoreSeckill = _ignoreSeckill or false
	local damage = _damage
	local defenceScale = 1
	if _targetMonster then
		-- 秒杀判定
		if not ignoreSeckill and not HasBattleFlag(_targetMonster.unitFlag, BattleUnitFlag.SECKILLED) then
			local seckillRate = _seckillRate or self:GetAttribute(AttriType.SECKILL)
			if seckillRate > 0 and gBattleRandNum:NextInt(s_PercentMax) <= seckillRate then
				damage = _targetMonster:GetMaxHP() * Constants.BATTLE_SECKILL_PERCENTS[_targetMonster.monsterRes.type] * s_PercentScale
				-- 秒杀标记
				self:AddBuffer(Constants.BATTLE_SECKILLED_BUFFER, self)
			end
		end
		-- 精英/Boss额外伤害
		if _targetMonster.monsterRes.type >= MonsterType.ELITE then
			local extraDamageScale = self:GetAttribute(AttriType.ELITEEXTRADAMAGE) * s_PercentScale
			if extraDamageScale ~= 0 then
				damage = damage * (1 + extraDamageScale)
			end
		end
		-- 护甲
		local defence = _targetMonster:GetDefence()
		defenceScale = 1 + (Constants.BATTLE_DEFENCE_INIT - defence) / Constants.BATTLE_DEFENCE_INIT
	end
	-- 暴击
	local criticalScale = 1
	local ignoreCritical = _ignoreCritical == nil and true or _ignoreCritical
	if not ignoreCritical then
		local criticalRate = self:GetAttribute(AttriType.CRITICAL)
		if criticalRate > 0 and gBattleRandNum:NextInt(s_PercentMax) <= criticalRate then
			criticalScale = self:GetAttribute(AttriType.CRITICALSCALE) * s_PercentScale
		end
	end
	-- 加伤
	local plusDamageScale = 1 + self:GetAttribute(AttriType.PLUSDAMAGE) * s_PercentScale
	-- 最终伤害
	damage = math_floor(damage * criticalScale * plusDamageScale * defenceScale)
	return damage, criticalScale > 1
end

function BattleUnit:IsValid( ... )
	return true
end

function BattleUnit:CanAttack( ... )
	return true
end

function BattleUnit:IsHaloValid( ... )
	return true
end

function BattleUnit:GetPositionDistance( _position, ... )
	return 15
end
