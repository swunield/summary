---
--- class BattleBuffer
-- @classmod BattleBuffer
-- 英雄状态
class('BattleBuffer')

---Constructor
function BattleBuffer:ctor( ... )
	self.bufferId = 0					-- 状态ID
	self.bufferRes = false				-- 状态配置
	self.battleUnit = false				-- 携带者
	self.unitType = false 				-- 携带者单位类型
	self.ownerUnit = false				-- 所有者单价
	self.ownerPlayer = false 			-- 所有者玩家
	self.layerList = {}					-- 状态层列表
	self.isDestroy = false				-- 是否销毁
	self.haloCounter = false 			-- 光环计时器
	self.haloIntervalIndex = 0			-- 光环间隔索引
	self.haloInterval = 0				-- 光环间隔
	self.haloIntervalCount = 0			-- 光环间隔数量
	self.haloTalentCount = 0			-- 光环行为数量
	self.duration = 0					-- 持续时间

	self.totalPoison = 0				-- 中毒伤害
	self.poisonInverval = 0				-- 中毒间隔
	self.poisonCounter = 0				-- 中毒计时器

	self.totalExtPoint = 0				-- 额外SP
	self.extPointInterval = 0			-- 额外SP间隔
	self.extPointCounter = 0			-- 额外SP计时器

	self.bindBufferId = 0				-- 关联BufferId
end

function BattleBuffer:Destroy( ... )
	gBattleManager:AddBattleLog(string.format('RemoveBuffer Time[%d] Buffer[%d] Unit[%s] Owner[%s]', gBattleTime, self.bufferRes.id, self.battleUnit.unitId, self.ownerPlayer.unitId))

	-- 移除所有Buff数值
	for i = 1, #self.layerList do
		local bufferValueList = self.layerList[i].valueList
		local valueNum = #bufferValueList
		for n = 1, valueNum do
			local bufferValue = bufferValueList[n]
			self:RemoveBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
		end
	end
	self.layerList = {}

	-- 触发移除Buffer
	local triggerParam = BattleTriggerParam(self.battleUnit, nil, nil, -self.bufferRes.id)
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam)

	-- 移除临时天赋触发器
	self.battleUnit:UnRegisterTalent(self.bufferRes.talentId)

	-- 解绑状态
	self.isDestroy = true
end

-- 状态初始化
function BattleBuffer:Init( _bufferResId, _battleUnit, _ownerUnit, ... )
	self.bufferRes = GameResMgr.GetBattleBufferRes(_bufferResId)
	if not self.bufferRes then
		return false
	end

	-- 检查类型和值List数量是否一致
	local valueNum = #self.bufferRes.valueList
	if valueNum ~= #self.bufferRes.valueTypeList then
		return false
	end
	
	self.battleUnit = _battleUnit
	self.ownerUnit = _ownerUnit
	self.ownerPlayer = _ownerUnit.player
	self.unitType = _battleUnit.unitType
	self.bufferId = gBattleManager:GenerateBufferId()
	self.duration = BattleFormula.GetValue(self.bufferRes.duration, self.ownerUnit, self.battleUnit)

	if self.unitType == BattleUnitType.GRID then
		return true
	end

	-- 注册临时天赋
	if self.bufferRes.talentId ~= 0 then
		self.battleUnit:RegisterTalent(self.bufferRes.talentId, self.ownerUnit)
	end

	-- 触发添加Buffer
	local triggerParam = BattleTriggerParam(self.battleUnit, nil, nil, self.bufferRes.id)
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam)

	-- 光环，初始化光环计时器
	if #self.bufferRes.haloIntervalList > 0 then
		self.haloCounter = 0
		self.haloIntervalIndex = 1
		self.haloTalentCount = #self.bufferRes.haloTalentList
		self.haloIntervalCount = #self.bufferRes.haloIntervalList
		self.haloInterval = self.bufferRes.haloIntervalList[self.haloIntervalIndex]
	end

	gBattleManager:AddBattleLog(string.format('AddBuffer Time[%d] Buffer[%d] Unit[%s] Owner[%s] Magic[%d]', gBattleTime, _bufferResId, _battleUnit.unitId, _ownerUnit.unitId, _magicRes and _magicRes.id or 0))

	return true
end

function BattleBuffer:Update( _deltaTime, ... )
	if self.unitType ~= BattleUnitType.GRID then
		-- 光环
		if self.haloCounter then
			self.haloCounter = self.haloCounter + _deltaTime
			if self.haloCounter >= self.haloInterval then
				-- 执行光环行为
				local talentId = self.bufferRes.haloTalentList[self.haloIntervalIndex % self.haloTalentCount + 1]
				local talentRes = GameResMgr.GetTalentRes(talentId)
				if talentRes then
					for i = 1, #talentRes.actionList do
						local actionId = talentRes.actionList[i]
						local triggerParam = BattleTriggerParam(self.battleUnit, nil, nil, nil)
						gBattleTrigger:FireAction(actionId, self.battleUnit, self.ownerUnit, triggerParam)
					end
				end

				-- 光环计时
				self.haloCounter = self.haloCounter - self.haloInterval
				self.haloIntervalIndex = self.haloIntervalIndex + 1
				if self.haloIntervalIndex > self.haloIntervalCount then
					self.haloIntervalIndex = 1
				end
				self.haloInterval = self.bufferRes.haloIntervalList[self.haloIntervalIndex]
			end	
		end

		-- 间隔触发
		self:UpdatePoison(_deltaTime)
		self:UpdateExtPoint(_deltaTime)
	end

	-- 状态生命周期
	if self.duration == 0 then
		-- 永久Buffer
		return
	end
	local layerCount = #self.layerList
	for i = layerCount, 1, -1 do
		local layer = self.layerList[i]
		if gBattleTime - layer.time >= self.duration then
			self:RemoveBufferLayer(i)
		end
	end
	if #self.layerList == 0 then
		-- 移除状态
		self.battleUnit:RemoveBuffer(self)
	end
end

-- 状态叠加
function BattleBuffer:AddBufferLayer( _ownerUnit, _useBetterLayer, _isInit, ... )
	if not _isInit then
		-- 持续时间叠加
		if self.bufferRes.overlapType == BufferOverlapType.DURATION then
			self.duration = self.duration + BattleFormula.GetValue(self.bufferRes.duration, self.ownerUnit, self.battleUnit)
			return
		end
	end

	-- 解析状态数据
	local bufferValueList = self:ParseBufferValue(_ownerUnit)
	local useBetterLayer = NilDefault(_useBetterLayer, true)

	-- 到达最大叠加层数，直接移除最上一层
	local maxLayerCount = self.bufferRes.maxLayerCount
	if maxLayerCount ~= 0 and #self.layerList == maxLayerCount then
		if self.duration == 0 and useBetterLayer then
			-- 永久Buffer的话，保留值大的层
			for i = 1, #self.layerList do
				local layer = self.layerList[i]
				if layer:IsTargetBetter(bufferValueList) then
					self:RemoveBufferLayer(i)
					break
				end
			end
			if #self.layerList == maxLayerCount then
				return
			end
		else
			self:RemoveBufferLayer(1)
		end
	end
	
	-- 插入状态层
	local layer = BattleBufferLayer(gBattleTime, _ownerUnit)
	layer.valueList = bufferValueList
	table_insert(self.layerList, layer)
	
	-- 状态层数据生效
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:AddBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end
end

-- 解析状态数据
function BattleBuffer:ParseBufferValue( _ownerUnit, ... )
	local bufferValueList = {}
	if self.unitType == BattleUnitType.GRID then
		return bufferValueList
	end
	local valueNum = #self.bufferRes.valueList
	local bufferType = self.bufferRes.bufferType
	local formulaId = 0
	for i = 1, valueNum do
		local bufferValue = {}
		bufferValue.type = self.bufferRes.valueTypeList[i]
		bufferValue.branch = NilDefault(self.bufferRes.valueBranchList[i], 1)
		formulaId = self.bufferRes.valueList[i]
		bufferValue.value = BattleFormula.GetValue(math.abs(formulaId), _ownerUnit, self.battleUnit)
		if formulaId < 0 then
			bufferValue.value = bufferValue.value * -1
		end
		table_insert(bufferValueList, bufferValue)
	end
	return bufferValueList
end

-- 移除顶层叠加
function BattleBuffer:RemoveBufferLayer( _layerIndex, _ownerUnit )
	local layerIndex = NilDefault(_layerIndex, 1)
	if layerIndex == 0 and _ownerUnit then
		for i = 1, #self.layerList do
			if self.layerList[i].ownerUnit.unitId == _ownerUnit.unitId then
				layerIndex = i
				break
			end
		end
	end
	if layerIndex <= 0 or #self.layerList < layerIndex then
		return
	end
	
	-- 移除状态层数值
	local bufferValueList = self.layerList[layerIndex].valueList
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:RemoveBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end
	
	-- 移除状态层
	table_remove(self.layerList, layerIndex)
end

local BufferValueSwitcher = 
{
	-- 临时SP
	[AttriType.TEMPPOINT] = function( self, _value, _isAdd, ... )
		self.battleUnit.player:AddPoint(_isAdd and _value or -_value)
	end,
	-- 中毒
	[AttriType.POISON] = function( self, _value, _isAdd, ... )
		self.totalPoison = self.totalPoison + (_isAdd and _value or -_value)
		if self.totalPoison == 0 then
			self.poisonInverval = 0
			self.poisonCounter = 0
		end
	end,
	-- 中毒间隔
	[AttriType.TIPOISON] = function( self, _value, _isAdd, ... )
		if _isAdd then
			self.poisonInverval = _value
		end
	end,
	-- 额外SP
	[AttriType.EXTPOINT] = function( self, _value, _isAdd, ... )
		self.totalExtPoint = self.totalExtPoint + (_isAdd and _value or -_value)
		if self.totalExtPoint == 0 then
			self.extPointInterval = 0
			self.extPointCounter = 0
		end
	end,
	-- 额外SP间隔
	[AttriType.TIEXTPOINT] = function( self, _value, _isAdd, ... )
		if _isAdd then
			self.extPointInterval = _value
		end
	end
}

-- 添加状态数据
function BattleBuffer:AddBufferValue( _type, _branch, _value )
	local newValue, oldValue = self.battleUnit:UpdateCarryAttribute(_type, _branch, _value)
	-- 部分属性需要额外处理
	local switcher = BufferValueSwitcher[_type]
	if switcher then
		switcher(self, _value, true)
	end

	-- 眩晕、沉默等状态，新增
	if newValue > 0 and oldValue == 0 then
		if _type >= AttriType.STATE_MIN and _type <= AttriType.STATE_MAX then
			local realFlag = BattleUnitFlag.STATE_MIN + _type - AttriType.STATE_MIN
			self.battleUnit:AddUnitFlag(realFlag)
		end
	end
end

-- 移除状态数据
function BattleBuffer:RemoveBufferValue( _type, _branch, _value, ... )
	local newValue, oldValue = self.battleUnit:UpdateCarryAttribute(_type, _branch, _value, false)

	-- 部分属性需要额外处理
	local switcher = BufferValueSwitcher[_type]
	if switcher then
		switcher(self, _value, false)
	end

	-- 眩晕、沉默等状态，清空
	if newValue == 0 and oldValue > 0 then
		if _type >= AttriType.STATE_MIN and _type <= AttriType.STATE_MAX then
			local realFlag = BattleUnitFlag.STATE_MIN + _type - AttriType.STATE_MIN
			self.battleUnit:ClearUnitFlag(realFlag)
		end
	end
end

-- 中毒
function BattleBuffer:UpdatePoison( _deltaTime, ... )
	if self.totalPoison == 0 then
		return
	end
	self.poisonCounter = self.poisonCounter + _deltaTime
	if self.poisonCounter < self.poisonInverval then
		return
	end
	self.poisonCounter = self.poisonCounter - self.poisonInverval
	self.battleUnit:OnAttackDamage(self.ownerPlayer, self.totalPoison)
end

-- 额外SP
function BattleBuffer:UpdateExtPoint( _deltaTime, ... )
	if self.totalExtPoint == 0 then
		return
	end
	self.extPointCounter = self.extPointCounter + _deltaTime
	if self.extPointCounter < self.extPointInterval then
		return
	end
	self.extPointCounter = self.extPointCounter - self.extPointInterval
	self.battleUnit.player:AddPoint(self.totalExtPoint)
end

function BattleBuffer:GetLayerCount( ... )
	return #self.layerList
end

classend()