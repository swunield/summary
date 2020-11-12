---
--- class BattleUnit
-- @classmod BattleUnit
-- 战斗单位，塔、怪物、碰撞等
class('BattleUnit')

---Constructor
function BattleUnit:ctor( ... )
	self.unitType = false							-- 单位类型
	self.unitId = false 							-- 单位Id，类型+玩家Id+实例Id

	self.carryAttribute = AttributeList()			-- 属性列表
	self.carryAttriDirtyFlag = Flag()				-- 属性脏数据标记
	self.attriList = {}								-- 属性值列表
	self.baseAttriList = {}							-- 属性基础值列表

	self.unitFlag = Flag()							-- 单位标记
	self.carryBufferList = {}						-- 单位携带状态列表

	self.player = false 							-- 玩家
end

function BattleUnit:Destroy( _leaveType, ... )
	-- 触发离场
	local leaveType = NilDefault(_leaveType, BattleUnitLeaveType.ALL)
	local triggerParam = BattleTriggerParam(self, nil, nil, leaveType)
	gBattleTrigger:FireTrigger(BattleTriggerType.LEAVE, triggerParam)
	-- 注销所有触发器
	gBattleTrigger:UnRegisterUnitAllActions(self)
	-- 移除所有携带状态
	self:RemoveAllBuffer()
	-- 增加死亡标记
	self:AddUnitFlag(BattleUnitFlag.DEATH)
end

function BattleUnit:Init( ... )
	-- 触发进场
	local triggerParam = BattleTriggerParam(self, nil, nil, nil)
	gBattleTrigger:FireTrigger(BattleTriggerType.ENTER, triggerParam)
end

function BattleUnit:Update( _deltaTime, ... )
	-- 更新状态
	local bufferCount = #self.carryBufferList
	for i = bufferCount, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer then
			buffer:Update(_deltaTime)
		end
	end
end

function BattleUnit:GenerateUnitId( _instanceId, ... )
	if not self.unitType or not self.player then
		return false
	end
	return string.format('%d_%d_%d', self.unitType, self.player.playerId, _instanceId)
end

function BattleUnit:GetAttribute( _attriType )
	if _attriType < AttriType.BASEMAX then
		if self.attriList[_attriType] and not self:IsAttriDirty(_attriType) then
			return self.attriList[_attriType]
		end

		local percentType = _attriType + AttriType.BASEMAX
		local percent = self:GetAttributePercent(percentType)
		local percentLimit = BattleConstants.BATTLE_ATTRIBUTE_LIMIT[percentType]
		local percentMin = percentLimit and percentLimit.min or false
		local percentMax = percentLimit and percentLimit.max or false
		if percentMin and percent < percentMin then
			percent = percentMin
		end
		if percentMax and percent > percentMax then
			percent = percentMax
		end
		
		local baseAttri = NilDefault(self.baseAttriList[_attriType], 0)
		local attriValue = 0
		if _attriType == AttriType.ATKSPEED or _attriType == AttriType.EXATKSPEED then
			attriValue = ToInt((baseAttri + self:GetAttributeValue(_attriType)) / percent)
		else
			attriValue = ToInt((baseAttri + self:GetAttributeValue(_attriType)) * percent)
		end
		local valueLimit = BattleConstants.BATTLE_ATTRIBUTE_LIMIT[_attriType]
		local valueMin = valueLimit and valueLimit.min or false
		local valueMax = valueLimit and valueLimit.max or false
		if valueMin and attriValue < valueMin then
			attriValue = valueMin
		end
		if valueMax and attriValue > valueMax then
			attriValue = valueMax
		end
		
		self:ClearAttriDirtyFlag(_attriType)
		self.attriList[_attriType] = attriValue
		return attriValue
	end
	local baseAttri = NilDefault(self.baseAttriList[_attriType], 0)
	return baseAttri + self:GetAttributeValue(_attriType)
end

function BattleUnit:GetAttributeValue( _attriType )
	return self.carryAttribute:GetAttribute(_attriType)
end

function BattleUnit:GetAttributePercent( _attriType )
	if _attriType <= AttriType.BASEMAX then
		return 0
	end
	return self.carryAttribute:GetAttribute(_attriType, nil, true)
end

function BattleUnit:UpdateBaseAttribute( _attriType, _value, ... )
	if _attriType > AttriType.BASEMAX then
		return
	end
	local baseAttri = NilDefault(self.baseAttriList[_attriType], 0)
	if baseAttri ~= _value then
		self:AddAttriDirtyFlag(_attriType)
	end
	self.baseAttriList[_attriType] = _value
end

function BattleUnit:UpdateCarryAttribute( _attriType, _branch, _value, _add, ... )
	local value, oldValue = self.carryAttribute:UpdateAttribute( _attriType, _branch, _value, _add, ...)
	if value ~= oldValue then
		local dirtyAttriType = (_attriType < AttriType.BASEMAX or _attriType > AttriType.BASEPERCENTMAX) and _attriType or _attriType - AttriType.BASEMAX
		self:AddAttriDirtyFlag(dirtyAttriType)
	end
	return value, oldValue
end

function BattleUnit:AddAttriDirtyFlag( _attriType )
	_attriType = (_attriType < AttriType.BASEMAX or _attriType > AttriType.BASEPERCENTMAX) and _attriType or _attriType - AttriType.BASEMAX
	self.carryAttriDirtyFlag:AddFlag(_attriType)
end

function BattleUnit:ClearAttriDirtyFlag( _attriType )
	_attriType = (_attriType < AttriType.BASEMAX or _attriType > AttriType.BASEPERCENTMAX) and _attriType or _attriType - AttriType.BASEMAX
	self.carryAttriDirtyFlag:ClearFlag(_attriType)
end

function BattleUnit:IsAttriDirty( _attriType )
	_attriType = (_attriType < AttriType.BASEMAX or _attriType > AttriType.BASEPERCENTMAX) and _attriType or _attriType - AttriType.BASEMAX 
	return self.carryAttriDirtyFlag:HasFlag(_attriType)
end

function BattleUnit:AddBuffer( _bufferResId, _ownerUnit, _useBetterLayer, ... )
	if self:HasUnitFlag(BattleUnitFlag.DEATH) then
		return false
	end
	local bufferRes = GameResMgr.GetBattleBufferRes(_bufferResId)
	if not bufferRes then
		return false
	end
	local bufferOverlapType = bufferRes.overlapType
	if bufferOverlapType ~= BufferOverlapType.SINGLE then
		local bufferCount = #self.carryBufferList
		-- 同ID的Buffer直接叠加
		for i = 1, bufferCount do
			local buffer = self.carryBufferList[i]
			if buffer.bufferRes.id == _bufferResId and buffer.ownerPlayer.unitId == _ownerUnit.player.unitId then
				-- 添加层数
				buffer:AddBufferLayer(_ownerUnit, _useBetterLayer)
				-- Buffer添加
				self:OnBufferAdd(buffer)
				return buffer
			end
		end
	end
	-- 添加新Buffer实例
	local buffer = BattleBuffer()
	if not buffer:Init(_bufferResId, self, _ownerUnit) then
		return false
	end
	-- 添加层数
	buffer:AddBufferLayer(_ownerUnit, _useBetterLayer, true)
	-- 插入列表
	table_insert(self.carryBufferList, buffer)
	-- Buffer添加
	self:OnBufferAdd(buffer)
	return buffer
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

function BattleUnit:RemoveBufferByResId( _bufferResId, _ownerUnit, _isRemoveAll, ... )
	local isRemoveAll = NilDefault(_isRemoveAll, true)
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId and _ownerUnit.player.unitId == buffer.ownerPlayer.unitId then
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

function BattleUnit:RemoveBufferLayer( _bufferResId, _ownerUnit, _layerCount, ... )
	if _layerCount == 0 then
		self:RemoveBufferByResId(_bufferResId, _ownerUnit, false)
		return
	end

	local layerCount = NilDefault(_layerCount, 1)
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId and _ownerUnit.player.unitId == buffer.ownerPlayer.unitId then
			for i = 1, layerCount do
				-- 层数减1
				buffer:RemoveBufferLayer(0, _ownerUnit)
			end
			-- Buffer层数移除
			self:OnBufferLayerRemove(buffer, layerCount)
			break
		end
	end
end

function BattleUnit:RemoveBufferLayerByBufferId( _bufferId, _layerCount, ... )
	if not _bufferId or _bufferId == 0 then
		return
	end
	if _layerCount == 0 then
		self:RemoveBufferByBufferId(_bufferId)
		return
	end
	local layerCount = NilDefault(_layerCount, 1)
	for i = #self.carryBufferList, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _bufferId then
			for i = 1, layerCount do
				-- 层数减1
				buffer:RemoveBufferLayer(0, _ownerUnit)
			end
			-- Buffer层数移除
			self:OnBufferLayerRemove(buffer, layerCount)
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


function BattleUnit:OnBufferAdd( _buffer, ... )
end

function BattleUnit:OnBufferRemove( _buffer, ... )
end

function BattleUnit:OnBufferLayerRemove( _buffer, _layerCount, ... )
end

function BattleUnit:OnAllBufferRemove( ... )
end

function BattleUnit:AddUnitFlag( _unitFlag, _flagValue, ... )
	if _unitFlag == BattleUnitFlag.DIZZY then
		-- 已经被晕过了，不能再晕了
		if self:HasUnitFlag(BattleUnitFlag.DIZZYED) then
			return
		end
		-- 眩晕标记
		self:AddBuffer(Constants.BATTLE_DIZZYED_BUFFER, self)
	end

	self.unitFlag:AddFlag(_unitFlag, _flagValue)
end

function BattleUnit:ClearUnitFlag( _unitFlag, ... )
	self.unitFlag:ClearFlag(_unitFlag)
end

function BattleUnit:HasUnitFlag( _unitFlag, ... )
	return self.unitFlag:HasFlag(_unitFlag)
end

function BattleUnit:GetUnitFlagValue( _unitFlag, ... )
	return self.unitFlag:GetFlagValue(_unitFlag)
end

function BattleUnit:RegisterTalent( _talentId, _ownerUnit, ... )
	local talentRes = GameResMgr.GetTalentRes(_talentId)
	if not talentRes then
		return
	end
	local actionCount = #talentRes.actionList
	for i = 1, actionCount do
		local actionId = talentRes.actionList[i]
		gBattleTrigger:RegisterAction(actionId, self, _ownerUnit)
	end
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
	local ignoreSeckill = NilDefault(_ignoreSeckill, false)
	local damage = _damage
	local defenceScale = 1
	if _targetMonster then
		-- 秒杀判定
		if not ignoreSeckill and not _targetMonster:HasUnitFlag(BattleUnitFlag.SECKILLED) then
			local seckillRate = NilDefault(_seckillRate, self:GetAttribute(AttriType.SECKILL))
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
	local ignoreCritical = NilDefault(_ignoreCritical, true)
	if not ignoreCritical then
		local criticalRate = self:GetAttribute(AttriType.CRITICAL)
		if criticalRate > 0 and gBattleRandNum:NextInt(s_PercentMax) <= criticalRate then
			criticalScale = self:GetAttribute(AttriType.CRITICALSCALE) * s_PercentScale
		end
	end
	-- 加伤
	local plusDamageScale = 1 + self:GetAttribute(AttriType.PLUSDAMAGE) * s_PercentScale
	-- 最终伤害
	damage = ToInt(damage * criticalScale * plusDamageScale * defenceScale)
	return damage, criticalScale > 1
end

classend()