---
--- class BattleBuffer
-- @classmod BattleBuffer
-- 英雄状态
class('BattleBuffer')

---Constructor
function BattleBuffer:ctor( ... )
	self.bufferId = 0				-- 状态ID
	self.bufferRes = false			-- 状态配置
	self.ownerHero = false			-- 所有者，状态释放者
	self.battleHero = false			-- 携带者
	self.roundList = {}				-- 状态添加回合列表
	self.roundValueList = {}		-- 状态回合数据列表
	self.totalLXDamage = 0			-- 总流血伤害
	self.totalZSDamage = 0			-- 总灼烧伤害
	self.totalHealHP = 0			-- 总回血量
	self.isDestroy = false			-- 是否销毁
	self.isActionEnd = false		-- 是否行动结束移除
	self.totalShield = 0 			-- 护盾
	self.totalZDDamage = 0 			-- 中毒伤害
end

function BattleBuffer:Destroy( _param, _fireTrigger, ... )
	local fireTrigger = NilDefault(_fireTrigger, true)

	-- 英雄状态移除
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFER, self.battleHero.heroId, self.bufferRes.id, false, false)

	-- 触发护盾破裂，驱散或净化不触发，_param 2驱散或净化
	if self.bufferRes.bufferType == BufferType.SHIELD then
		local breakType = NilDefault(_param, 0)
		if fireTrigger then
			local triggerParam = TriggerParam(nil, nil, self.battleHero, nil, nil, nil, nil, nil, self.totalShield)
			gBattleTrigger:FireTrigger(breakType + BattleTriggerType.SHIELDBREAK, triggerParam, true)
		end

		self.battleHero:UpdateShield(0)
	end

	-- 如果当前Buffer是嘲讽的话，需要清除携带英雄上的嘲讽数据
	if #self.bufferRes.valueTypeList == 1 and self.bufferRes.valueTypeList[1] == AttriType.CHAOFENG then
		self.battleHero.cxBufferId = 0
		self.battleHero.cxHeroId = 0
	end

	-- 移除所有Buff数值
	for i = 1, #self.roundValueList do
		local bufferValueList = self.roundValueList[i]
		local valueNum = #bufferValueList
		for n = 1, valueNum do
			local bufferValue = bufferValueList[n]
			self:RemoveBufferValue(bufferValue.type, bufferValue.value)
		end
	end
	self.roundValueList = {}
	self.roundList = {}

	-- 触发移除Buffer
	if fireTrigger then
		local triggerParam = TriggerParam(nil, nil, self.battleHero, self.ownerHero, { self.ownerHero }, nil, nil, tostring(-ToInt(self.bufferRes.id)))
		gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam, true)
	end

	-- 移除临时天赋触发器
	self.battleHero:UnRegisterHeroTalent(self.bufferRes.talentId)

	-- 解绑状态
	self.isDestroy = true
	self.ownerHero:UnbindActionBuffer(self)
end

-- 状态初始化
function BattleBuffer:Init( bufferResId, _ownerHero, _battleHero, _actionHero, _isActionEnd, ... )
	self.bufferRes = GameResMgr.GetBufferRes(bufferResId)
	if not self.bufferRes then
		return false
	end

	-- 检查类型和值List数量是否一致
	local valueNum = #self.bufferRes.valueList
	if valueNum ~= #self.bufferRes.valueTypeList then
		return false
	end
	
	self.ownerHero = _ownerHero
	self.battleHero = _battleHero
	self.bufferId = gBattleManager:GenerateBufferId()
	self.isActionEnd = NilDefault(_isActionEnd, false)
	if not self.isActionEnd and self.bufferRes.actionType == BufferActionType.END then
		self.isActionEnd = true
	end

	-- 当前行动单位绑定状态
	local actionHero = FalseDefault(_actionHero, gBattleManager.lastActionHero)
	if actionHero then
		actionHero:BindActionBuffer(self)
	else
		_ownerHero:BindActionBuffer(self)
	end

	-- 注册临时天赋
	if self.bufferRes.talentId ~= 0 then
		self.battleHero:RegisterHeroTalent(self.bufferRes.talentId, self.ownerHero)
	end

	-- 触发添加Buffer
	local triggerParam = TriggerParam(nil, nil, self.battleHero, self.ownerHero, { self.ownerHero }, nil, nil, self.bufferRes.id)
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFER, triggerParam, true)

	-- 英雄状态添加
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFER, self.battleHero.heroId, self.bufferRes.id, true, false)
	
	return true
end

-- 状态叠加
function BattleBuffer:OverLapBuffer( _triggerTargetHeroes, ... )
	local curRoundNum = self.ownerHero:GetActionRoundNum()
	
	-- 解析状态数据
	local bufferValueList = self:ParseBufferValue(_triggerTargetHeroes)
	if #bufferValueList == 0 then
		return
	end

	local maxOverLap = self.bufferRes.maxOverLap
	-- 印记类状态，到达最大叠加层数后，不再层叠
	if self.bufferRes.bufferType == BufferType.YINJI and maxOverLap ~= 0 and #self.roundList == maxOverLap then
		return
	end
	
	-- 到达最大叠加层数，直接移除最上一层
	if maxOverLap ~= 0 and #self.roundList == maxOverLap then
		self:RemoveBufferLap(1)
	end
	
	-- 插入行动回合数
	table.insert(self.roundList, curRoundNum)
	-- 插入回合数据
	table.insert(self.roundValueList, bufferValueList)
	
	-- 回合数据生效
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:AddBufferValue(bufferValue.type, bufferValue.value)
	end

	-- 英雄状态添加
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFER, self.battleHero.heroId, self.bufferRes.id, false, true)
end

-- 解析状态数据
function BattleBuffer:ParseBufferValue( _triggerTargetHeroes, ... )
	local bufferValueList = {}
	local valueNum = #self.bufferRes.valueList
	local bufferType = self.bufferRes.bufferType
	for i = 1, valueNum do
		local bufferValue = {}
		bufferValue.type = self.bufferRes.valueTypeList[i]
		if bufferType == BufferType.STEAL then
			-- 偷取属性，计算所有行动目标的属性和
			if bufferValue.type >= AttriType.HPPERCENT and bufferValue.type <= AttriType.SPEEDPERCENT then
				bufferValue.type = bufferValue.type - AttriType.SPEED
			end
			bufferValue.value = 0
			local targetHeroes = NilDefault(_triggerTargetHeroes, gBattleAction:GetCurTargetHeroes())
			local targetNum = #targetHeroes
			local stealPercent = ToInt(self.bufferRes.valueList[i]) * s_PercentScale
			for i = 1, targetNum do
				-- 负面状态抗性
				local ignoreNegativePer = 1 - targetHeroes[i]:GetAttribute(AttriType.IGNORENEGATIVE) * s_PercentScale
				ignoreNegativePer = ignoreNegativePer < 0 and 0 or ignoreNegativePer
				
				bufferValue.value = bufferValue.value + targetHeroes[i]:GetAttribute(bufferValue.type) * stealPercent * ignoreNegativePer
			end
		elseif bufferValue.type == AttriType.LIUXUE or bufferValue.type == AttriType.ZHUOSHAO or bufferValue.type == AttriType.SHIELD or bufferValue.type == AttriType.ZHONGDU then
			local result = Split(self.bufferRes.valueList[i], '|')
			local damageScale = result[1] and ToInt(result[1]) or s_PercentMax
			local damageType = result[2] and ToInt(result[2]) or BattleDamageType.ALL
			local damageFlag = result[3] and ToInt(result[3]) or 0
			local isMustHit = damageFlag % 10 == 1
			local isIgnoreDefence = ToInt(damageFlag * 0.1) % 10 == 1
			local isMustCritical = ToInt(damageFlag * 0.01) % 10 == 1
			
			-- 流血、灼烧、护盾，必中不暴击
			bufferValue.value = self.ownerHero:CalcAttackDamage(self.battleHero, SkillType.TALENT, nil, damageType, damageScale, true, false, isIgnoreDefence)
		elseif bufferValue.type == AttriType.HUIXUE then
			local result = Split(self.bufferRes.valueList[i], '|')
			local damageScale = result[1] and ToInt(result[1]) or s_PercentMax
			local damageType = result[2] and ToInt(result[2]) or BattleDamageType.ALL
			local damageFlag = result[3] and ToInt(result[3]) or 0

			-- 回血
			bufferValue.value = self.ownerHero:CalcHealHP(self.battleHero, damageScale, damageType, SkillType.TALENT)
		elseif bufferValue.type == AttriType.SHANGHAIYINJI or bufferValue.type == AttriType.BAOJIYINJI then
			-- 伤害、暴击印记，需要按百分比计算普攻伤害数值，必中不暴击
			bufferValue.value = self.ownerHero:CalcAttackDamage(self.battleHero, SkillType.TALENT, nil, BattleDamageType.ALL, ToInt(self.bufferRes.valueList[i]), true, false, false, true)

			-- 负面状态抗性
			local ignoreNegativePer = 1 - self.battleHero:GetAttribute(AttriType.IGNORENEGATIVE) * s_PercentScale
			ignoreNegativePer = ignoreNegativePer < 0 and 0 or ignoreNegativePer
			bufferValue.value = bufferValue.value * ignoreNegativePer
		elseif bufferValue.type == AttriType.CHAOFENG then
			-- 嘲讽
			self.battleHero.cxBufferId = self.bufferId
			self.battleHero.cxHeroId = self.ownerHero.heroId
			bufferValue.value = 1
		else
			-- 普通属性，默认配置值
			bufferValue.value = ToInt(self.bufferRes.valueList[i])

			-- 负面状态抗性
			if self.bufferRes.pnType == BufferPNType.NEGATIVE or self.bufferRes.pnType == BufferPNType.NEGATIVE_NODIS then
				local ignoreNegativePer = 1 - self.battleHero:GetAttribute(AttriType.IGNORENEGATIVE) * s_PercentScale
				ignoreNegativePer = ignoreNegativePer < 0 and 0 or ignoreNegativePer
				bufferValue.value = bufferValue.value * ignoreNegativePer
			end
		end
		bufferValue.value = ToInt(bufferValue.value)
		table.insert(bufferValueList, bufferValue)
	end
	return bufferValueList
end

-- 移除顶层叠加
function BattleBuffer:RemoveBufferLap( lapIndex )
	if #self.roundList < lapIndex then
		return
	end
	
	-- 移除顶层叠加数据
	local bufferValueList = self.roundValueList[lapIndex]
	local valueNum = #bufferValueList
	for i = 1, valueNum do
		local bufferValue = bufferValueList[i]
		self:RemoveBufferValue(bufferValue.type, bufferValue.value)
	end
	
	-- 移除顶层行动回合数和数据
	table.remove(self.roundList, lapIndex)
	table.remove(self.roundValueList, lapIndex)
end

-- 状态增加一次回合行动
function BattleBuffer:ExecRoundAction( _isActionEnd )
	if self.isDestroy == true then
		return
	end

	local isActionEnd = NilDefault(_isActionEnd, false)

	if not isActionEnd then
		-- 先处理回血
		if self.totalHealHP > 0 then
			self.battleHero:HealHP(self.totalHealHP, self.ownerHero)
			-- 回血音效
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFERSOUND, AttriType.HUIXUE)
		end

		-- 接着处理流血伤害
		if self.totalLXDamage > 0 then
			self.battleHero:OnAttackDamage(self.ownerHero, SkillType.TALENT, nil, self.totalLXDamage)
			-- 流血音效
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFERSOUND, AttriType.LIUXUE)
		end

		-- 接着处理灼烧伤害
		if self.totalZSDamage > 0 then
			self.battleHero:OnAttackDamage(self.ownerHero, SkillType.TALENT, nil, self.totalZSDamage)
			-- 灼烧音效
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFERSOUND, AttriType.ZHUOSHAO)
		end

		-- 接着处理中毒伤害
		if self.totalZDDamage > 0 then
			self.battleHero:OnAttackDamage(self.ownerHero, SkillType.TALENT, nil, self.totalZDDamage)
			-- 中毒音效
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFERSOUND, AttriType.ZHONGDU)
		end
	end

	-- 触发状态回合行动
	local triggerParam = TriggerParam(SkillType.TALENT, nil, self.battleHero, self.ownerHero, { self.ownerHero }, 0, 0, self.bufferRes.id)
	gBattleTrigger:FireTrigger(BattleTriggerType.BUFFERROUNDACTION, triggerParam, true)

	if self.isActionEnd == isActionEnd then
		-- 检查状态是否有过期叠层，有的话移除
		local durRound = self.bufferRes.durRound
		local lapNum = #self.roundList
		local curRoundNum = self.ownerHero:GetActionRoundNum()
		for i = lapNum, 1, -1 do
			if curRoundNum >= self.roundList[i] + durRound then
				self:RemoveBufferLap(i)
			end
		end

		-- 检查是否状态层是否全部移除，是的话销毁状态
		if #self.roundList == 0 then
			-- 销毁状态
			self.battleHero:RemoveBuffer(self)
		end
	end
end

-- 添加状态数据
function BattleBuffer:AddBufferValue( _type, _value )
	local newValue, oldValue = self.battleHero.heroData:UpdateCarryAttribute(_type, _value)

	-- 眩晕、流血等状态，新增
	if newValue > 0 and oldValue == 0 then
		if _type >= AttriType.STATE_MIN and _type <= AttriType.STATE_MAX then
			local realFlag = BattleHeroFlag.STATE_MIN + _type - AttriType.STATE_MIN
			self.battleHero:AddHeroFlag(realFlag)

			if _type <= AttriType.CHENMO then
				-- 眩晕、冰冻、石化、沉默，添加状态时播放声音
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.BUFFERSOUND, _type)
			end
		end
	end
	
	if _type == AttriType.LIUXUE then
		-- 统计流血总伤害
		self.totalLXDamage = self.totalLXDamage + _value
	elseif _type == AttriType.HUIXUE then
		-- 统计回血
		self.totalHealHP = self.totalHealHP + _value
	elseif _type == AttriType.ZHUOSHAO then
		-- 统计灼烧伤害
		self.totalZSDamage = self.totalZSDamage + _value
	elseif _type == AttriType.ZHONGDU then
		-- 统计中毒伤害
		self.totalZDDamage = self.totalZDDamage + _value
	elseif _type == AttriType.SHIELD then
		-- 护盾
		self.totalShield = _value
		self.battleHero:UpdateShield(_value)
	end
end

-- 移除状态数据
function BattleBuffer:RemoveBufferValue( _type, _value, ... )
	local needRemove = NilDefault(_remove, true)
	local newValue, oldValue = self.battleHero.heroData:UpdateCarryAttribute(_type, _value, false)

	-- 眩晕、流血等状态，清空
	if newValue == 0 and oldValue > 0 then
		if _type >= AttriType.STATE_MIN and _type <= AttriType.STATE_MAX then
			local realFlag = BattleHeroFlag.STATE_MIN + _type - AttriType.STATE_MIN
			self.battleHero:ClearHeroFlag(realFlag)
		end
	end
	
	if _type == AttriType.LIUXUE then
		-- 统计流血总伤害
		self.totalLXDamage = self.totalLXDamage - _value
	elseif _type == AttriType.HUIXUE then
		-- 统计回血	
		self.totalHealHP = self.totalHealHP - _value
	elseif _type == AttriType.ZHUOSHAO then
		-- 统计灼烧
		self.totalZSDamage = self.totalZSDamage - _value
	elseif _type == AttriType.ZHONGDU then
		-- 统计中毒
		self.totalZDDamage = self.totalZDDamage - _value
	end
end

classend()