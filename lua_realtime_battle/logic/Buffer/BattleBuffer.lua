---
--- class BattleBuffer
-- @classmod BattleBuffer
-- 英雄状态
class('BattleBuffer')

local table_insert = table.insert
local table_remove = table.remove
local BattleTriggerParam_New = BattleTriggerParam.New

local TSBuffer = gModel.TSBuffer
local TSBufferHalo = gModel.TSBufferHalo
local TSPoison = gModel.TSBufferPoison
local TSExtPoint = gModel.TSBufferExtPoint

---Constructor
function BattleBuffer:ctor( ... )  
	self.bufferId = 0					-- 状态ID
	self.bufferRes = false				-- 状态配置
	self.battleUnit = false				-- 携带者
	self.unitType = false 				-- 携带者单位类型
	self.owner = {}						-- 所有者，{ unitId, player }
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

function BattleBuffer:Serialize( ... )
	local tBuffer = TSBuffer:new{}
	tBuffer.Id = self.bufferId
	tBuffer.ResId = self.bufferRes.id
	tBuffer.Duration = self.duration ~= 0 and self.duration or nil
	tBuffer.OwnerId = self.owner.unitId
	tBuffer.OwnerPlayerId = self.owner.player.unitId
	tBuffer.BindBufferId = self.bindBufferId ~= 0 and self.bindBufferId or nil
	local layerCount = #self.layerList
	if layerCount ~= 0 then
		tBuffer.LayerList = {}
		for i = 1, layerCount do
			table_insert(tBuffer.LayerList, self.layerList[i]:Serialize())
		end
	end
	if self.haloCounter then
		tBuffer.Halo = TSBufferHalo:new{}
		tBuffer.Halo.Counter = self.haloCounter
		tBuffer.Halo.IntervalIndex = self.haloIntervalIndex
	end
	if self.totalPoison ~= 0 then
		tBuffer.Poison = TSPoison:new{}
		tBuffer.Poison.Total = self.totalPoison
		tBuffer.Poison.Interval = self.poisonInverval
		tBuffer.Poison.Counter = self.poisonCounter
	end
	if self.totalExtPoint ~= 0 then
		tBuffer.ExtPoint = TSExtPoint:new{}
		tBuffer.ExtPoint.Total = self.totalExtPoint
		tBuffer.ExtPoint.Interval = self.extPointInterval
		tBuffer.ExtPoint.Counter = self.extPointCounter
	end
	return tBuffer
end

function BattleBuffer:DeSerialize( _tBuffer, _battleUnit, ... )
	if not _tBuffer or not _battleUnit then
		return
	end

	local layerList = self.layerList
	local bufferRes = false

	self.bufferId = _tBuffer.Id
	bufferRes = GameResMgr.GetBattleBufferRes(_tBuffer.ResId)
	self.bufferRes = bufferRes
	self.battleUnit = _battleUnit
	self.unitType = _battleUnit.unitType
	self.duration = _tBuffer.Duration or 0
	self.owner.unitId = _tBuffer.OwnerId
	self.bindBufferId = _tBuffer.BindBufferId or 0
	if _tBuffer.LayerList then
		for i = 1, #_tBuffer.LayerList do
			local layer = BattleBufferLayer(self)
			layer:DeSerialize(_tBuffer.LayerList[i])
			table_insert(layerList, layer)
		end
	end
	if _tBuffer.Halo then
		self.haloCounter = _tBuffer.Halo.Counter
		self.haloIntervalIndex = _tBuffer.Halo.IntervalIndex
		self.haloTalentCount = #bufferRes.haloTalentList
		self.haloIntervalCount = #bufferRes.haloIntervalList
		self.haloInterval = bufferRes.haloIntervalList[self.haloIntervalIndex]
	end
	if _tBuffer.Poison then
		self.totalPoison = _tBuffer.Poison.Total
		self.poisonInverval = _tBuffer.Poison.Interval
		self.poisonCounter = _tBuffer.Poison.Counter
	end
	if _tBuffer.ExtPoint then
		self.totalExtPoint = _tBuffer.ExtPoint.Total
		self.extPointInterval = _tBuffer.ExtPoint.Interval
		self.extPointCounter = _tBuffer.ExtPoint.Counter
	end

	gBattleManager:RegisterSnapShotPushEndEvent(function( ... )
		self.owner.player = gBattleRecord:GetBattleUnit(_tBuffer.OwnerPlayerId)

		-- 绑定升阶
		for i = 1, #layerList do
			local layer = layerList[i]
			layer.owner.player = self.owner.player
			if layer.bindGrade and self.owner.player then
				self.owner.player:BindGradeBufferLayer(bufferRes.towerId, layer)
			end
		end

		-- 注册临时天赋
		if self.unitType ~= BattleUnitType.GRID and bufferRes.talentId ~= 0 then
			self.battleUnit:RegisterTalent(bufferRes.talentId, self.owner)
		end

		-- 通知前端添加状态
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.BUFFER, true, self.battleUnit.unitId, bufferRes)
	end, 2)
end

function BattleBuffer:Destroy( ... )  
	-- gBattleManager:AddBattleLog(string.format('RemoveBuffer Time[%d] Buffer[%d] Unit[%s] Owner[%s]', gBattleTime, self.bufferRes.id, self.battleUnit.unitId, self.owner.player.unitId))
	if self.isDestroy then
		return
	end

	-- 通知前端移除状态
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.BUFFER, false, self.battleUnit.unitId, self.bufferRes)

	-- 移除所有Buff数值
	for i = 1, #self.layerList do
		self:RemoveBufferLayer(i, nil, true)
	end
	self.layerList = {}

	-- 触发移除Buffer
	local triggerParam = BattleTriggerParam_New(self.battleUnit, nil, nil, tostring(-self.bufferRes.id))
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam)

	-- 移除临时天赋触发器
	self.battleUnit:UnRegisterTalent(self.bufferRes.talentId)

	-- 解绑状态
	self.isDestroy = true
end

-- 状态初始化
function BattleBuffer:Init( _bufferResId, _battleUnit, _owner, ... )  
	local bufferRes = GameResMgr.GetBattleBufferRes(_bufferResId)
	if not bufferRes then
		self.isDestroy = true
		return false
	end

	-- 检查类型和值List数量是否一致
	local valueNum = #bufferRes.valueList
	if valueNum ~= #bufferRes.valueTypeList then
		self.isDestroy = true
		return false
	end
	self.isDestroy = false

	self.bufferRes = bufferRes
	self.battleUnit = _battleUnit
	self.owner = _owner
	self.unitType = _battleUnit.unitType
	self.bufferId = gBattleManager:GenerateBufferId()
	self.duration = BattleFormula.GetValue(bufferRes.duration, self, self.battleUnit)

	-- 通知前端添加状态
	local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.BUFFER, true, self.battleUnit.unitId, bufferRes)

	if self.unitType == BattleUnitType.GRID then
		return true
	end

	-- 注册临时天赋
	if bufferRes.talentId ~= 0 then
		self.battleUnit:RegisterTalent(bufferRes.talentId, _owner)
	end

	-- 触发添加Buffer
	local triggerParam = BattleTriggerParam_New(self.battleUnit, nil, nil, tostring(bufferRes.id))
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam)

	-- 光环，初始化光环计时器
	if #bufferRes.haloIntervalList > 0 then
		self.haloCounter = 0
		self.haloIntervalIndex = 1
		self.haloTalentCount = #bufferRes.haloTalentList
		self.haloIntervalCount = #bufferRes.haloIntervalList
		self.haloInterval = BattleFormula.GetValue(bufferRes.haloIntervalList[self.haloIntervalIndex], self, self.battleUnit)
	end

	-- gBattleManager:AddBattleLog(string.format('AddBuffer Time[%d] Buffer[%d] Unit[%s] Owner[%s]', gBattleTime, _bufferResId, _battleUnit.unitId, _owner.unitId))

	return true
end

function BattleBuffer:Update( _deltaTime, ... )  
	if self.unitType ~= BattleUnitType.GRID then
		-- 光环
		local haloCounter = self.haloCounter
		if haloCounter then
			haloCounter = haloCounter + _deltaTime
			local haloInterval = self.haloInterval
			if haloCounter >= haloInterval then
				-- 执行光环行为
				local haloIntervalIndex = self.haloIntervalIndex
				local talentId = self.bufferRes.haloTalentList[(haloIntervalIndex - 1) % self.haloTalentCount + 1]
				local talentRes = GameResMgr.GetTalentRes(talentId)
				if talentRes then
					for i = 1, #talentRes.actionList do
						local actionId = talentRes.actionList[i]
						local triggerParam = BattleTriggerParam_New(self.battleUnit, nil, nil, nil)
						gBattleTrigger:FireAction(actionId, self.battleUnit, self.owner, triggerParam)
					end
				end

				-- 光环计时
				haloCounter = haloCounter - haloInterval
				haloIntervalIndex = (haloIntervalIndex % self.haloIntervalCount) + 1
				self.haloInterval = BattleFormula.GetValue(self.bufferRes.haloIntervalList[haloIntervalIndex], self, self.battleUnit)
				self.haloIntervalIndex = haloIntervalIndex
			end
			self.haloCounter = haloCounter
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
	local layerList = self.layerList
	local layerCount = #layerList
	for i = layerCount, 1, -1 do
		local layer = layerList[i]
		if gBattleTime - layer.time >= self.duration then
			self:RemoveBufferLayer(i)
		end
	end
	if #layerList == 0 then
		-- 移除状态
		self.battleUnit:RemoveBuffer(self)
	end
end

-- 状态叠加
function BattleBuffer:AddBufferLayer( _owner, _useBetterLayer, _isInit, ... )  
	if not _isInit then
		-- 持续时间叠加
		if self.bufferRes.overlapType == BufferOverlapType.DURATION then
			self.duration = self.duration + BattleFormula.GetValue(self.bufferRes.duration, self, self.battleUnit)
			return
		end
	end

	-- 解析状态数据
	local bufferValueList, isLayerBindGrade = self:ParseBufferValue()
	local useBetterLayer = _useBetterLayer == nil and true or _useBetterLayer

	-- 到达最大叠加层数，直接移除最上一层
	local maxLayerCount = self.bufferRes.maxLayerCount
	local layerList = self.layerList
	if maxLayerCount ~= 0 and #layerList == maxLayerCount then
		if self.duration == 0 and useBetterLayer then
			-- 永久Buffer的话，保留值大的层
			for i = 1, #layerList do
				local layer = layerList[i]
				if layer:IsTargetBetter(bufferValueList) then
					self:RemoveBufferLayer(i)
					break
				end
			end
			if #layerList == maxLayerCount then
				return
			end
		else
			self:RemoveBufferLayer(1)
		end
	end
	
	-- 插入状态层
	local layer = BattleBufferLayer(self, gBattleTime, _owner, isLayerBindGrade)
	layer.valueList = bufferValueList
	table_insert(layerList, layer)
	
	-- 状态层数据生效
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:AddBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end

	-- 绑定升阶
	if isLayerBindGrade and self.owner.player then
		self.owner.player:BindGradeBufferLayer(self.bufferRes.towerId, layer)
	end
end

-- 移除顶层叠加
function BattleBuffer:RemoveBufferLayer( _layerIndex, _ownerId, _keepInList )  
	local layerIndex = _layerIndex or 1
	local layer = false
	local layerList = self.layerList
	if layerIndex ~= 0 then
		layer = layerList[layerIndex]
	elseif _ownerId then
		for i = 1, #layerList do
			local bufferLayer = layerList[i]
			if bufferLayer.owner.unitId == _ownerId then
				layerIndex = i
				layer = bufferLayer
				break
			end
		end
	end
	if not layer then
		return
	end
	
	-- 移除状态层数值
	local bufferValueList = layer.valueList
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:RemoveBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end
	
	-- 移除状态层
	local removeFromList = not _keepInList
	if removeFromList then
		table_remove(layerList, layerIndex)
	end

	-- 解绑升阶
	if layer.bindGrade and self.owner.player then
		self.owner.player:UnBindGradeBufferLayer(self.bufferRes.towerId, layer)
	end
end

function BattleBuffer:RefreshBufferLayer( _layer )
	if not _layer or not _layer.bindGrade then
		return
	end
	local bufferValueList = self:ParseBufferValue()
	for i = 1, #bufferValueList do
		local bufferValue = bufferValueList[i]
		self:AddBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end
	local oldBufferValueList = _layer.valueList
	for i = 1, #oldBufferValueList do
		local bufferValue = oldBufferValueList[i]				
		self:RemoveBufferValue(bufferValue.type, bufferValue.branch, bufferValue.value)
	end
	_layer.valueList = bufferValueList
end

-- 解析状态数据
function BattleBuffer:ParseBufferValue( ... )  
	local bufferValueList = {}
	if self.unitType == BattleUnitType.GRID then
		return bufferValueList, false
	end
	local bufferRes = self.bufferRes
	local valueNum = #bufferRes.valueList
	local bufferType = bufferRes.bufferType
	local isLayerBindGrade = false
	local formulaId = 0
	for i = 1, valueNum do
		local bufferValue = {}
		bufferValue.type = bufferRes.valueTypeList[i]
		bufferValue.branch = bufferRes.valueBranchList[i] or 1
		formulaId = bufferRes.valueList[i]
		local value, bindGrade = BattleFormula.GetValue(math.abs(formulaId), self, self.battleUnit)
		if formulaId < 0 then
			value = value * -1
		end
		bufferValue.value = value
		bufferValue.bindGrade = bindGrade
		if bindGrade then
			isLayerBindGrade = true
		end
		table_insert(bufferValueList, bufferValue)
	end
	return bufferValueList, isLayerBindGrade
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
	self.battleUnit:OnAttackDamage(self.owner.player, self.totalPoison, nil, nil, BattleDamageType.POISON)
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

function BattleBuffer:GetGrade( ... )
	if self.owner.player then
		return self.owner.player:GetTowerGrade(self.bufferRes.towerId)
	end
	return 0
end

function BattleBuffer:GetLevel( ... )
	local towerRes = GameResMgr.GetBattleTowerRes(self.bufferRes.towerId)
	return towerRes and towerRes.level or 0
end

classend()