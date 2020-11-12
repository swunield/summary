-- 属性列表
class('AttributeList')

function AttributeList:ctor( ... )
	self.valueList = {}
end

function AttributeList:UpdateAttribute( _attrType, _value, _add, ... )
	local baseType = _attrType % 100
	if baseType <= AttriType.ALL or baseType >= AttriType.MAX then
		return 0, 0
	end
	
	local isAdd = NilDefault(_add, true)
	if not self.valueList[_attrType] then
		self.valueList[_attrType] = 0
	end
	
	local oldValue = self.valueList[_attrType]
	
	if isAdd then
		self.valueList[_attrType] = self.valueList[_attrType] + _value
	else
		self.valueList[_attrType] = self.valueList[_attrType] - _value
	end
	
	return self.valueList[_attrType], oldValue
end

function AttributeList:GetAttribute( _attrType, ... )
	if not self.valueList[_attrType] then
		return 0
	end
	return self.valueList[_attrType]
end

classend()


-- 英雄数据
class('HeroData')
	
function HeroData:ctor( ... )
	self.camp = 0							-- 阵营
	self.baseHP = 0							-- 基础血量
	self.baseAttack = 0						-- 基础攻击
	self.baseDefence = 0					-- 基础防御
	self.baseSpeed = 0						-- 基础速度
	
	self.level = 0							-- 等级
	self.jieLevel = 0						-- 阶级
	
	self.maxHP = 0							-- 最大血量
	self.curHP = 0							-- 当前血量
	self.curHPPercent = 0					-- 当前血量百分比
	self.speed = 0							-- 速度
	self.fury = 0							-- 怒气
	self.actionFury = 0 					-- 行动怒气

	self.heroFlag = Flag()					-- 英雄标记
	
	self.carryAttribute = AttributeList()	-- 英雄技能、状态、装备等属性列表
end

function HeroData:GetAttributeValue( _attrType )
	return self.carryAttribute:GetAttribute(_attrType) + gBattleManager:GetAttriAddition(self.camp, _attrType)
end

function HeroData:GetAttributePercent( _attrType )
	return self:GetAttributeValue(_attrType) * s_PercentScale
end

function HeroData:UpdateCarryAttribute( _attrType, _value, _add, ... )
	return self.carryAttribute:UpdateAttribute( _attrType, _value, _add, ...)
end

classend()


---
--- class BattleHero
-- @classmod BattleHero
-- 战斗英雄
class('BattleHero')

---Constructor
function BattleHero:ctor( _heroId, ... )
	self.heroId = _heroId			-- 英雄逻辑ID
	self.heroRes = false			-- 英雄配置数据
	self.heroPosRes = false			-- 英雄位置配置
	self.heroPos = { x = 0, y = 0, z = 0 }	-- 英雄位置
	self.heroCamp = false			-- 英雄阵营
	self.randNum = false			-- 英雄随机数，用于随机排序等
	self.teamIndex = 0				-- 英雄队伍索引
	
	self.attackId = false			-- 英雄普攻ID
	self.actionSkillId = false		-- 英雄行动技能ID
	self.extraHeroTalents = false 	-- 额外天赋，非上阵英雄才有，如光环、天赋英雄
	
	self.tHeroData = false			-- 后端传入英雄数据
	self.heroData = HeroData()		-- 英雄数据
	self.loadingState = 0			-- 英雄是否准备好,0默认 1下载中 2准备好
	self.isHeroInit = false 		-- 英雄数据是否初始化
	self.isHeroPreInit = false 		-- 英雄数据是否预初始化
	
	self.actionRoundNum = 0			-- 行动回合数
	self.carryBufferList = {}		-- 英雄携带状态列表
	self.actionBufferList = {}		-- 英雄行动相关状态列表
	
	self.totalAttackDamage = 0		-- 英雄总输出伤害
	self.totalHurtDamage = 0		-- 英雄总承受伤害
	self.totalHealHP = 0			-- 英雄总贡献回血

	self.curShield = 0 				-- 当前护盾值
	self.totalShield = 0 			-- 英雄护盾

	self.cxBufferId = 0 			-- 携带的嘲讽BufferID
	self.cxHeroId = 0 				-- 携带的嘲讽Buffer对应的英雄ID

	self.triggerFireRecord = {} 	-- 触发器触发记录，有些触发器是有触发次数限制的
	self.talentTriggerIdList = {} 	-- 已注册的天赋的触发器列表

	self.isHaloHero = false 		-- 是否光环英雄
	self.haloHeroActionTimes = 0 	-- 光环英雄行动次数

	self.isPetHero = false 			-- 是否宠物英雄
	self.petLevel = 0				-- 宠物等级

	self.isTalentHero = false 		-- 是否天赋英雄
end

function BattleHero:Destroy( ... )
	-- 移除所有携带状态
	self:RemoveAllBuffer()
	-- 增加死亡标记
	self:AddHeroFlag(BattleHeroFlag.DEATH)
	-- 从阵营列表中移除
	gBattleManager:RemoveCampHero(self)
	-- 移除触发器中英雄所有行为
	gBattleTrigger:UnRegisterHeroAllActions(self.heroId)
end

-- 初始化英雄
function BattleHero:InitHero( _heroData, _heroCamp, _extraHeroTalents, _haloLevel, _petLevel, _isTalentHero, ... )
	if not _heroData or self.tHeroData then
		return false
	end

	-- 英雄数据
	self.tHeroData = _heroData
	self.extraHeroTalents = NilDefault(_extraHeroTalents, false)
	self.isHaloHero = _haloLevel ~= nil and _haloLevel > 0
	self.isPetHero = _petLevel ~= nil and _petLevel > 0
	self.petLevel = _petLevel
	self.isTalentHero = NilDefault(_isTalentHero, false)

	self.heroRes = GameResMgr.GetHeroRes(self.tHeroData.typeId)
	if not self.heroRes then
		return false
	end

	self.heroCamp = _heroCamp
	self.heroPosRes = GameResMgr.GetBattlePosRes(self.tHeroData.battlePos, gBattleManager.battleFieldType)
	self.teamIndex = gBattleManager.campTeamIndex[self.heroCamp]
	
	-- 阵营A站位对调
	self.heroPos.x = self.heroPosRes.posX
	if self.heroCamp == BattleCampType.CAMP_A then
		self.heroPos.x = -self.heroPos.x
	end
	self.heroPos.y = self.heroPosRes.posY
	self.heroPos.z = self.heroPosRes.posZ

	-- 初始化普攻ID
	self.attackId = self.heroRes.attackId

	-- 优先设置前端显示相关
	self.heroData.camp = _heroCamp
	self.heroData.level = self.tHeroData.level
	self.heroData.jieLevel = self.tHeroData.jieLevel
	self.heroData.curHPPercent = self.tHeroData.hpPercent

	if self.isHaloHero then
		self.attackId = tostring(ToInt(self.heroRes.skillId) + (_haloLevel - 1) * 10)
	end

	return true
end

function BattleHero:PreInitHero( ... )
	if self.isHeroPreInit then
		-- 触发预入场
		local triggerParam = TriggerParam(nil, nil, self)
		gBattleTrigger:FireTrigger(BattleTriggerType.PREBATTLESTART, triggerParam, true)
	
		return
	end
	self.isHeroPreInit = true

	if self.extraHeroTalents then
		-- 非上阵英雄注册天赋
		for i = 1, #self.extraHeroTalents do
			self:RegisterHeroTalent(self.extraHeroTalents[i])
		end
	end

	-- 初始化装备
	self:InitHeroEquip(self.tHeroData.equipments)

	-- 初始化符石
	self:InitHeroStone(self.tHeroData.stones)

	-- 初始化圣物
	self:InitHeroAmulet(self.tHeroData) --amuletAttrTypes amuletAttrValues amuletSkills

	-- 初始化英灵殿等属性加成
	self:InitHeroExtraAttrs()

	-- 注册大招和天赋
	self:RegisterHeroActions()

	-- 触发预入场
	local triggerParam = TriggerParam(nil, nil, self)
	gBattleTrigger:FireTrigger(BattleTriggerType.PREBATTLESTART, triggerParam, true)
end

-- 初始化英雄数据
function BattleHero:InitHeroData( ... )
	if self.isHeroInit then
		-- 触发入场
		local triggerParam = TriggerParam(nil, nil, self)
		gBattleTrigger:FireTrigger(BattleTriggerType.BATTLESTART, triggerParam, true)

		return
	end
	self.isHeroInit = true

	-- 生成唯一随机数
	self.randNum = gBattleRandNum:NextUniqueInt(UniqueRandType.BATTLEHERO)

	-- 基础属性
	local baseAttrMap = GameFormula.CalcHeroBaseAttrMap(self.tHeroData.typeId, self.tHeroData.level, self.tHeroData.jieLevel, self.tHeroData.starRank)
	self.heroData.baseHP = baseAttrMap[AttriType.HP] or 0
	self.heroData.baseAttack = baseAttrMap[AttriType.ATTACK] or 0
	self.heroData.baseDefence = baseAttrMap[AttriType.DEFENCE] or 0
	self.heroData.baseSpeed = baseAttrMap[AttriType.SPEED] or 0
	self.heroData.level = self.tHeroData.level
	self.heroData.jieLevel = self.tHeroData.jieLevel
	self.heroData.fury = self.isPetHero and 0 or Constants.BT_furyInit

	-- 触发入场
	local triggerParam = TriggerParam(nil, nil, self)
	gBattleTrigger:FireTrigger(BattleTriggerType.BATTLESTART, triggerParam, true)
	
	-- 血量运算
	self.heroData.maxHP = self.heroData.maxHP == 0 and self:GetMaxHP() or self.heroData.maxHP
	self.heroData.curHP = self.heroData.maxHP * self.tHeroData.hpPercent * s_PercentScale
	self.heroData.curHPPercent = self.tHeroData.hpPercent
	if self.isHaloHero or self.isPetHero then
		self.heroData.maxHP = s_PercentMax
		self.heroData.curHP = s_PercentMax
		self.heroData.curHPPercent = s_PercentMax
	end
	
	-- 速度运算
	self.heroData.speed = self:GetSpeed()

	
	-- 更新怒气
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROFURY, self.heroId)
	-- 更新血量
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROHP, self.heroId)
	BattleSpecialLogic.OnHeroHPChange(self.heroId, self.heroData.curHPPercent)
end

-- 英雄最大血量
function BattleHero:GetMaxHP()
	if self.heroData.maxHP ~= 0 then
		return self.heroData.maxHP
	end
	local hpPer = self.heroData:GetAttributePercent(AttriType.HPPERCENT)
	hpPer = MinMaxValue(hpPer, Constants.BT_hpPerMin * s_PercentScale, Constants.BT_hpPerMax * s_PercentScale)
	return (self.heroData.baseHP + self.heroData:GetAttributeValue(AttriType.HP)) * (hpPer + 1)
end

-- 英雄攻击
function BattleHero:GetAttack()
	local attackPer = self.heroData:GetAttributePercent(AttriType.ATTACKPERCENT)
	local attackPerMax = self.heroCamp == BattleCampType.CAMP_B and gBattleManager.battleFieldRes.enemyAttackPerMax ~= 0 and gBattleManager.battleFieldRes.enemyAttackPerMax or Constants.BT_attackPerMax
	attackPer = MinMaxValue(attackPer, Constants.BT_attackPerMin * s_PercentScale, attackPerMax * s_PercentScale)
	local ghostScale = self:HasHeroFlag(BattleHeroFlag.GHOST) and self:GetHeroFlagValue(BattleHeroFlag.GHOST) * s_PercentScale or 1
	return (self.heroData.baseAttack + self.heroData:GetAttributeValue(AttriType.ATTACK)) * (attackPer + 1) * ghostScale
end

-- 英雄防御
function BattleHero:GetDefence()
	local defencePer = self.heroData:GetAttributePercent(AttriType.DEFENCEPERCENT)
	defencePer = MinMaxValue(defencePer, Constants.BT_defencePerMin * s_PercentScale, Constants.BT_defencePerMax * s_PercentScale)
	return (self.heroData.baseDefence + self.heroData:GetAttributeValue(AttriType.DEFENCE)) * (defencePer + 1)
end

-- 英雄速度
function BattleHero:GetSpeed( ... )
	local speedPer = self.heroData:GetAttributePercent(AttriType.SPEEDPERCENT)
	speedPer = MinMaxValue(speedPer, Constants.BT_speedPerMin * s_PercentScale, Constants.BT_speedPerMax * s_PercentScale)
	return (self.heroData.baseSpeed + self.heroData:GetAttributeValue(AttriType.SPEED)) * (speedPer + 1)
end

-- 怒气上限
function BattleHero:GetMaxFury( ... )
	local maxFury = self.heroData:GetAttributeValue(AttriType.NUQIMAX)
	return Constants.BT_furyMax + maxFury
end

local BaseAttriSwitcher = {
	-- 命中
	[AttriType.HITRATE] = function( _battleHero, ... )
		return _battleHero.heroRes.initHitRate
	end,
	-- 闪避
	[AttriType.DODGERATE] = function( _battleHero, ... )
		return _battleHero.heroRes.initDodgeRate
	end,
	-- 暴击
	[AttriType.CRITICALRATE] = function( _battleHero, ... )
		return _battleHero.heroRes.initCriticalRate
	end,
	-- 抗暴击
	[AttriType.IGNORECRITICAL] = function( _battleHero, ... )
		return _battleHero.heroRes.initIgnoreCritical
	end,
	-- 暴击背书
	[AttriType.CRITICALSCALE] = function( _battleHero, ... )
		return _battleHero.heroRes.initCriticalScale
	end,
}

-- 获取属性
function BattleHero:GetAttribute( attrType, targetHero, ... )
	if attrType == AttriType.ATTACK then
	return self:GetAttack()
	end
	if attrType == AttriType.DEFENCE then
		return self:GetDefence()
	end
	if attrType == AttriType.SPEED then
		return self:GetSpeed()
	end
	if attrType == AttriType.HP then
		return self.heroData.maxHP
	end

	-- HeroRes基础属性
	local baseAttribute = BaseAttriSwitcher[attrType] and BaseAttriSwitcher[attrType](self) or 0 

	-- 无目标直接返回
	if not targetHero then
		return self.heroData:GetAttributeValue(attrType) + baseAttribute
	end

	local targetMajor = targetHero.heroRes.major
	local targetRace = targetHero.heroRes.race
	
	local totalAttribute = baseAttribute
	-- 全体无筛选加成
	totalAttribute = totalAttribute + self.heroData:GetAttributeValue(attrType)
	-- 指定目标职业加成
	totalAttribute = totalAttribute + self.heroData:GetAttributeValue(attrType + targetMajor * 100)
	-- 指定目标种族加成
	totalAttribute = totalAttribute + self.heroData:GetAttributeValue(attrType + targetRace * 1000)
	-- 指定目标种族且职业加成
	totalAttribute = totalAttribute + self.heroData:GetAttributeValue(attrType + targetMajor * 100 + targetRace * 1000)
	
	return totalAttribute
end

-- 开始行动
function BattleHero:ActionBegin( _realAction, ... )
	-- 非追加行动、非反击
	if _realAction then
		-- 行动回合数+1
		self.actionRoundNum = self.actionRoundNum + 1
	end

	-- 触发开始行动
	local triggerParam = TriggerParam(nil, nil, self, nil, nil, nil, nil, self.actionRoundNum)
	gBattleTrigger:FireTrigger(BattleTriggerType.ACTIONBEGIN, triggerParam, true)	

	if _realAction then
		-- 通知拥有的所有Buffer执行一次回合行为
		self:NotifyAllActionBufferAction(false)
	end

	-- 校验战斗是否结束
	if gBattleManager:CheckBattleEnd() then
		return false
	end

	-- 校验战斗是否结束
	if gBattleManager:IsBattleEnd() then
		return false
	end

	-- 刷新所有英雄行动前怒气
	gBattleManager:RefreshAllHeroActionFury()

	-- 天赋英雄不可以行动
	if self.isTalentHero then
		return false
	end

	-- 光环英雄只能真实行动一次
	if self.isHaloHero and self.haloHeroActionTimes >= 1 then
		return false
	end

	-- 检查英雄是否可以行动
	if not self.isPetHero and not self:CanAction() then
		return false
	end

	-- 检查附属英雄是否可以行动
	if #gBattleAction.comboHeroIdList > 0 then
		for i = 1, #gBattleAction.comboHeroIdList do
			local comboHero = gBattleManager:GetBattleHero(gBattleAction.comboHeroIdList[i])
			if not comboHero or not comboHero:CanAction() then
				return false
			end
		end
	end
	
	-- 光环英雄(宠物)，直接放大招
	if self.isHaloHero then
		gBattleAction.skillId = self.attackId
		gBattleAction.comboHeroIdList = {}	
		gBattleAction.comboRes = false
		self.haloHeroActionTimes = self.haloHeroActionTimes + 1
	end

	-- 行动无指定技能ID，计算行动技能
	if gBattleAction.skillId == '0' then
		if self.cxHeroId ~= 0 then
			local cxHero = gBattleManager:GetBattleHero(self.cxHeroId)
			if not cxHero or cxHero:HasHeroFlag(BattleHeroFlag.DEATH) then
				-- 嘲讽英雄已死，移除嘲讽Buffer
				self:RemoveBufferById(self.cxBufferId)
			end
		end

		-- 检查是否怒气已满，满了且未禁魔的话释放大招，否则直接普攻，嘲讽状态只能普攻
		if self.heroData.fury == self:GetMaxFury() and (self.isPetHero or (not self:HasHeroFlag(BattleHeroFlag.CHENMO) and self.cxHeroId == 0)) then
			local comboHeroIdList, comboRes = gBattleManager:TryFindComboHero(self)
			if #comboHeroIdList ~= 0 then
				gBattleAction.skillId = comboRes.skillId
				gBattleAction.comboHeroIdList = comboHeroIdList
				gBattleAction.comboRes = comboRes
			else
				gBattleAction.skillId = self.heroRes.skillId
				gBattleAction.comboHeroIdList = {}
				gBattleAction.comboRes = false
			end

			-- 清空怒气
			self:AddHeroFury(-self:GetMaxFury())
		else
			gBattleAction.skillId = self.attackId
			gBattleAction.comboHeroIdList = {}	
			gBattleAction.comboRes = false
		end
	end

	-- 没有配技能
	local skillRes = GameResMgr.GetSkillRes(gBattleAction.skillId)
	if not skillRes then
		return false
	end

	-- 触发技能开始
	local triggerParam = TriggerParam(skillRes.skillType, skillRes.effectType, self, nil, nil, nil, nil, gBattleAction.skillId)
	gBattleTrigger:FireTrigger(BattleTriggerType.SKILLBEGIN, triggerParam, true)	
	
	return true
end

-- 行动结束
function BattleHero:ActionEnd( _realAction, ... )
	-- 触发行动结束
	local triggerParam = TriggerParam(gBattleAction:GetSkillType(), gBattleAction:GetSkillEffectType(), self, nil, nil, nil, nil, self.actionRoundNum)
	gBattleTrigger:FireTrigger(BattleTriggerType.ACTIONEND, triggerParam, true)
	if _realAction then
		-- 通知拥有的所有Buffer执行一次回合结束行为
		self:NotifyAllActionBufferAction(true)
	end
end

-- 获取行动回合数
function BattleHero:GetActionRoundNum( ... )
	return self.actionRoundNum
end

-- 英雄是否可以行动
function BattleHero:CanAction( ... )
	return not self:HasHeroFlag(BattleHeroFlag.DEATH) and not self:HasHeroFlag(BattleHeroFlag.XUANYUN) and not self:HasHeroFlag(BattleHeroFlag.BINGDONG) and not self:HasHeroFlag(BattleHeroFlag.SHIHUA)
end

-- 添加英雄标记
function BattleHero:AddHeroFlag( _heroFlag, _flagValue, ... )
	-- 初次增加英雄标记，有些需要增加特效
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDHEROFLAG, self.heroId, _heroFlag)
	
	if _heroFlag == BattleHeroFlag.TARGETLOCKED then
		-- 目标锁定需要先清空
		self:ClearHeroFlag(_heroFlag)
	end

	-- 初次添加标记，需要尝试添加附加状态
	if not self:HasHeroFlag(_heroFlag) then
		local extraBufferId = 100000 + _heroFlag * 1000 + 11
		self:AddBuffer(extraBufferId, self)
	end

	self.heroData.heroFlag:AddFlag(_heroFlag, _flagValue)

	if _heroFlag == BattleHeroFlag.GHOST then
		-- 鬼魂单位需要从阵营移除，不计入存活、不计入目标
		gBattleManager:RemoveCampHero(self)
		-- 加入鬼魂列表
		gBattleManager:AddBattleGhostHero(self)
		-- 净化负面状态
		self:JingHuaBuffer(BufferPNType.NEGATIVE)
		-- 强制满血
		self:HealHP(self.heroData.maxHP, self)
	end
end

-- 移除英雄标记
function BattleHero:ClearHeroFlag( _heroFlag, ... )
	-- 初次移除英雄标记，有些需要移除特效
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.CLEARHEROFLAG, self.heroId, _heroFlag)

	self.heroData.heroFlag:ClearFlag(_heroFlag)

	-- 移除标记，需要尝试移除附加状态
	if not self:HasHeroFlag(_heroFlag) then
		local extraBufferId = 100000 + _heroFlag * 1000 + 11
		self:RemoveBufferByTypeId(extraBufferId, self)
	end
end

-- 英雄是否有标记
function BattleHero:HasHeroFlag( _heroFlag )
	return self.heroData.heroFlag:HasFlag(_heroFlag)
end

-- 英雄标记数值
function BattleHero:GetHeroFlagValue( _heroFlag, ... )
	return self.heroData.heroFlag:GetFlagValue(_heroFlag)
end

-- 英雄触发技能，包含普攻、大招、合体技
function BattleHero:ExecSkill( ... )
	local damageCount = gBattleAction:GetDamageCount()
	for i = 1, damageCount do
		self:ExecSkillHit(i)
	end
end

-- 英雄技能触发伤害逻辑
function BattleHero:ExecSkillHit( _hitIndex, ... )
	-- 处理技能命中
	gBattleAction:ExecSkillHit()
	-- 没有目标，预处理下一次伤害
	if #gBattleAction:GetCurTargetHeroes() == 0 then
		gBattleAction:PreExecSkillHit(_hitIndex and _hitIndex + 1 or nil)
		return
	end

	-- 触发英雄技能
	local skillEffectType = gBattleAction:GetSkillEffectType()
	local triggerParam = TriggerParam(gBattleAction:GetSkillType(), skillEffectType, self)
	gBattleTrigger:FireTrigger(BattleTriggerType.SKILL, triggerParam)
	
	-- 遍历所有目标触发伤害逻辑
	local targetHeroes = gBattleAction:GetCurTargetHeroes()
	local targetHeroNum = #targetHeroes
	local hitTargetHeroes = {}
	for i = 1, targetHeroNum do
		gBattleAction.curTargetHero = targetHeroes[i]
		local isHitted = false
		if skillEffectType == SkillEffectType.HEAL then
			-- 治疗类
			isHitted = self:HealTarget(targetHeroes[i].heroId, gBattleAction:GetSkillType(), skillEffectType, gBattleAction:GetCurDamageType(), gBattleAction:GetCurDamageScale())
		elseif skillEffectType == SkillEffectType.BUFFER then
			-- 状态类
			isHitted = self:BufferTarget(targetHeroes[i].heroId, gBattleAction:GetSkillType(), skillEffectType, gBattleAction:GetCurDamageScale())
		else
			-- 伤害类
			isHitted = self:AttackTarget(targetHeroes[i].heroId, gBattleAction:GetSkillType(), skillEffectType, gBattleAction:GetCurDamageType(), gBattleAction:GetCurDamageScale(), gBattleAction:IsCurDamageMustHit(), gBattleAction:IsCurDamageMustCritical(), gBattleAction:IsCurDamageIgnoreDefence())
		end
		if isHitted then
			table.insert(hitTargetHeroes, targetHeroes[i])
		end
	end

	-- 真实队列行动，命中增加怒气
	if #hitTargetHeroes > 0 and not gBattleAction.normalAttackFuryed and gBattleAction.actionHero.heroId == self.heroId and gBattleAction.realAction == true and gBattleAction.skillRes.skillType == SkillType.NORMAL then
		self:AddHeroFury(Constants.BT_furyNormalAttack)
		gBattleAction.normalAttackFuryed = true
	end

	-- 触发大招或者普攻结束
	triggerParam = TriggerParam(gBattleAction:GetSkillType(), skillEffectType, self, self, targetHeroes)
	gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKEND, triggerParam)
	triggerParam = TriggerParam(gBattleAction:GetSkillType(), skillEffectType, self, self, hitTargetHeroes)
	gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKHITEND, triggerParam)

	-- 预处理下一次伤害
	gBattleAction:PreExecSkillHit(_hitIndex and _hitIndex + 1 or nil)
end

-- 治疗目标
function BattleHero:HealTarget( targetId, _skillType, _skillEffectType, _healType, _healScale )
	local targetHero = gBattleManager:GetBattleHero(targetId)
	if not targetHero or targetHero:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	local skillType = NilDefault(_skillType, SkillType.NORMAL)
	local extraHealScale = 0

	if gBattleAction.realAction then
		-- 真实行动普攻触发治疗命中
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
		extraHealScale = extraHealScale + triggerParam.damageScale
	else
		-- 追加治疗触发命中
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.EXTRAATTACK, triggerParam)
		extraHealScale = extraHealScale + triggerParam.damageScale
	end

	local healScale = NilDefault(_healScale, s_PercentMax)
	local healHP = self:CalcHealHP(targetHero, healScale + extraHealScale, _healType, skillType)

	gBattleManager:AddBattleLog(string.format('HealTarget SkillType[%d] [%d-->%d] Heal[%.1f]', _skillType, self.heroId, targetId, healHP))

	-- 治疗目标
	targetHero:HealHP(healHP, self, skillType, _skillEffectType)

	return true
end

-- 给目标加状态
function BattleHero:BufferTarget( targetId, _skillType, _skillEffectType, _bufferResId, ... )
	local targetHero = gBattleManager:GetBattleHero(targetId)
	if not targetHero or targetHero:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	local skillType = NilDefault(_skillType, SkillType.NORMAL)

	if gBattleAction.realAction then
		-- 真实行动普攻触发状态命中
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
	else
		-- 追加状态触发命中
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.EXTRAATTACK, triggerParam)
	end

	gBattleManager:AddBattleLog(string.format('BufferTarget SkillType[%d] [%d-->%d] Buffer[%.1f]', _skillType, self.heroId, targetId, _bufferResId))

	-- 给目标加状态
	targetHero:AddBuffer(_bufferResId, self, nil, nil, skillType, _skillEffectType)

	return true
end

-- 攻击目标
function BattleHero:AttackTarget( targetId, _skillType, _skillEffectType, _damageType, _damageScale, _mustHit, _mustCritical, _ignoreDefence, ... )
	local targetHero = gBattleManager:GetBattleHero(targetId)
	if not targetHero or targetHero:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	-- 计算伤害
	local attackDamage, criticalScale, attackHit = self:CalcAttackDamage(targetHero, _skillType, _skillEffectType, _damageType, _damageScale, _mustHit, _mustCritical, _ignoreDefence)

	gBattleManager:AddBattleLog(string.format('AttackTarget SkillType[%d] [%d-->%d] Hit[%s] Damage[%.1f] Critical[%.1f]', _skillType, self.heroId, targetId, tostring(attackHit), attackDamage, criticalScale))
	
	if not attackHit then
		-- 未命中直接返回，Miss跳字
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.TIAOZI, TiaoZiType.MISS, targetHero.heroId)
		return false
	end

	local isTargetHeroReBirth = targetHero:HasHeroFlag(BattleHeroFlag.REBIRTH)

	-- 目标单位受到攻击
	attackDamage = targetHero:OnAttackDamage(self, _skillType, _skillEffectType, attackDamage, criticalScale ~= 1)
	
	if attackDamage > 0 then
		local xixuePer = self.heroData:GetAttributeValue(AttriType.XIXUE)
		if xixuePer > 0 then
			local healHP = attackDamage * (xixuePer * s_PercentScale)
			self:HealHP(healHP, self, SkillType.TALENT, _skillEffectType, true)
		end
	end

	return true
end

-- 受到攻击
function BattleHero:OnAttackDamage( attackerHero, _skillType, _skillEffectType, attackDamage, _isCriticalDamage, _killTriggerType, _ignoreShield, ... )
	if self.isPetHero or attackDamage <= 0 or self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return 0
	end
	
	local skillType = NilDefault(_skillType, SkillType.TALENT)
	if skillType ~= SkillType.TALENT then
		-- 触发被击，普攻、大招触发
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, attackerHero, { attackerHero }, attackDamage, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKED, triggerParam)
		attackDamage = attackDamage + triggerParam.extraDamage
		
		-- 播放受击动作
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.ACTION, self.heroId, HeroActionType.ATTACKED)
	end

	-- 最大减血
	local maxSubHPPer = self:GetAttribute(AttriType.MAXSUBHPPER)
	maxSubHPPer = maxSubHPPer == 0 and s_PercentMax or maxSubHPPer
	maxSubHPPer = maxSubHPPer < Constants.BT_heroSubHpPerMin and Constants.BT_heroSubHpPerMin or maxSubHPPer
	-- BOSS最大减血，不设上限
	local maxBossSubHPPer = self:GetAttribute(AttriType.MAXBOSSSUBHPPER)
	maxBossSubHPPer = maxBossSubHPPer == 0 and s_PercentMax or maxBossSubHPPer
	maxBossSubHPPer = maxBossSubHPPer < Constants.BT_bossSubHpPerMin and Constants.BT_bossSubHpPerMin or maxBossSubHPPer
	maxSubHPPer = math.min(maxSubHPPer, maxBossSubHPPer)
	if maxSubHPPer > 0 and maxSubHPPer < s_PercentMax then
		local maxSubHP = self.heroData.maxHP * (maxSubHPPer * s_PercentScale)
		attackDamage = attackDamage > maxSubHP and maxSubHP or attackDamage
	end
	
	-- 计算掉血，优先护盾
	local ignoreShield = NilDefault(_ignoreShield, false)
	if not ignoreShield and self.curShield > 0 then
		-- 攻击英雄增加贡献值
		attackerHero:AddAttackDamage(attackDamage)
		-- 受击英雄增加贡献值
		self:AddHurtDamage(attackDamage)

		self.curShield = self.curShield - attackDamage
		-- 护盾破裂，移除状态
		if self.curShield <= 0 then
			self:RemoveBufferByBufferType(BufferType.SHIELD, 0)
			self.curShield = 0
			self.totalShield = 0
		end
	else
		-- 受到致死伤害
		if attackDamage >= self.heroData.curHP then
			local triggerParam = TriggerParam(skillType, _skillEffectType, self, attackerHero, { attackerHero }, attackDamage)
			gBattleTrigger:FireTrigger(BattleTriggerType.DEATHATTACKED, triggerParam)
			attackDamage = attackDamage + triggerParam.extraDamage
		end

		-- 攻击英雄增加贡献值
		attackerHero:AddAttackDamage(attackDamage)
		-- 受击英雄增加贡献值
		self:AddHurtDamage(attackDamage)

		self.heroData.curHP = self.heroData.curHP - attackDamage
		self.heroData.curHPPercent = self.heroData.curHP * s_PercentMax / self.heroData.maxHP
	end

	gBattleManager:AddBattleLog(string.format('OnAttackDamage SkillType[%d] [%d<--%d] RealDamage[%.1f] HP[%.1f]', _skillType, self.heroId, attackerHero.heroId, attackDamage, self.heroData.curHP))
	
	if _skillType == SkillType.TALENT then
		-- 流血跳字
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.TIAOZI, TiaoZiType.LIUXUE, self.heroId, -attackDamage)
	elseif _isCriticalDamage then
		-- 暴击跳字
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.TIAOZI, TiaoZiType.BAOJI, self.heroId, -attackDamage)
	else
		-- 普通跳字
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.TIAOZI, TiaoZiType.NORMAL, self.heroId, -attackDamage)
	end

	if skillType ~= SkillType.TALENT then
		-- 触发被击结束，扣血后
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, attackerHero, { attackerHero }, attackDamage, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKEDEND, triggerParam)
	end

	-- 触发血量降低
	local triggerParam = TriggerParam(skillType, _skillEffectType, self, attackerHero, { attackerHero }, attackDamage, self.heroData.curHP)
	gBattleTrigger:FireTrigger(BattleTriggerType.SUBHP, triggerParam)
	
	-- 受击增加怒气，冰冻时受击不增加
	if _skillType ~= SkillType.TALENT and not self:HasHeroFlag(BattleHeroFlag.BINGDONG) then
		self:AddHeroFury(Constants.BT_furyBeAttacked)
	end

	if ToInt(self.heroData.curHPPercent) <= 0 then
		-- 英雄死亡
		self.heroData.curHP = 0
		self.heroData.curHPPercent = 0
		self:OnHeroDie(skillType, _skillEffectType, attackerHero)
	end

	if self.heroData.curHP == 0 then
		-- 击杀
		if _killTriggerType ~= nil then
			local triggerParam = TriggerParam(skillType, _skillEffectType, attackerHero, attackerHero, { self })
			gBattleTrigger:FireTrigger(_killTriggerType, triggerParam)
		end
	end
	
	-- 更新血量
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROHP, self.heroId)
	BattleSpecialLogic.OnHeroHPChange(self.heroId, self.heroData.curHPPercent)

	return attackDamage
end

-- 计算攻击基础伤害
function BattleHero:CalcAttackDamage( targetHero, _skillType, _skillEffectType, _damageType, _damageScale, _mustHit, _mustCritical, _ignoreDefence, _ignoreCritical, ... )
	local criticalScale = 1
	local attackDamage = 0
	local attackHit = self:CalcAttackHit(targetHero, _mustHit)
	local skillType = NilDefault(_skillType, SkillType.TALENT)
	local extraDamageScale = 0
	
	-- 攻击未命中，触发攻击闪避
	if not attackHit then
		if skillType ~= SkillType.TALENT then
			-- 自己触发未命中
			local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
			gBattleTrigger:FireTrigger(BattleTriggerType.DODGEATTACK, triggerParam)
			-- 被击单位触发闪避，普攻、大招都触发
			local triggerParam = TriggerParam(skillType, _skillEffectType, targetHero, self, { self })
			gBattleTrigger:FireTrigger(BattleTriggerType.DODGEATTACKED, triggerParam)
		end
		
		return attackDamage, criticalScale, attackHit
	end

	if gBattleAction then
		if gBattleAction.realAction then
			-- 真实行动普攻触发攻击命中
			local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
			gBattleTrigger:FireTrigger(BattleTriggerType.ATTACK, triggerParam)
			extraDamageScale = extraDamageScale + triggerParam.damageScale
			attackDamage = attackDamage + triggerParam.extraDamage
		else
			-- 追加攻击触发命中
			local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.EXTRAATTACK, triggerParam)
			extraDamageScale = extraDamageScale + triggerParam.damageScale
			attackDamage = attackDamage + triggerParam.extraDamage
		end
	end

	-- 计算攻击暴击倍数，1为不暴击
	criticalScale = self:CalcAttackCriticalScale(targetHero, _mustCritical, _ignoreCritical)
	if criticalScale ~= 1 and skillType ~= SkillType.TALENT then
		-- 自己触发暴击，普攻触发
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, self, { targetHero })
		gBattleTrigger:FireTrigger(BattleTriggerType.CRITATTACK, triggerParam)
		extraDamageScale = extraDamageScale + triggerParam.damageScale
		attackDamage = attackDamage + triggerParam.extraDamage

		-- 被击单位触发被暴击，普攻、暴击都触发
		triggerParam = TriggerParam(skillType, _skillEffectType, targetHero, self, { self })
		gBattleTrigger:FireTrigger(BattleTriggerType.CRITATTACKED, triggerParam)
	end
	
	-- 技能加伤
	local skillDamageScale = s_PercentMax
	if skillType >= SkillType.SPELL then
		skillDamageScale = skillDamageScale + self:GetAttribute(AttriType.SKILLDAMAGE)
		-- 大招伤害提升标记
		if self:HasHeroFlag(BattleHeroFlag.SPELLSCALE) then
			skillDamageScale = skillDamageScale + self:GetHeroFlagValue(BattleHeroFlag.SPELLSCALE)
			self:ClearHeroFlag(BattleHeroFlag.SPELLSCALE)
		end
		skillDamageScale = skillDamageScale > Constants.BT_extraSkillDmgMax and Constants.BT_extraSkillDmgMax or skillDamageScale
		skillDamageScale = skillDamageScale < Constants.BT_extraSkillDmgMin and Constants.BT_extraSkillDmgMin or skillDamageScale
	end
	skillDamageScale = skillDamageScale * s_PercentScale

	-- 无视护甲标记
	local ignoreDefenceFlagScale = self:GetHeroFlagValue(BattleHeroFlag.IGNOREDEFENCE)
	self:ClearHeroFlag(BattleHeroFlag.IGNOREDEFENCE)

	-- 命中增伤
	local hitExtraDamageScale = 1
	local hitRate = self:GetAttribute(AttriType.HITRATE, targetHero)
	local dodgeRate = targetHero:GetAttribute(AttriType.DODGERATE)
	if hitRate > dodgeRate then
		hitExtraDamageScale = 1 + (hitRate * s_PercentScale - dodgeRate * s_PercentScale) * Constants.BT_mingZhongExtraDmg * s_PercentScale
	end

	-- 守方格挡
	local gdRate = targetHero:GetAttribute(AttriType.GEDANG)
	local gdDamageScale = 1
	if gBattleRandNum:NextInt(s_PercentMax) <= gdRate then
		gdDamageScale = 1 - Constants.BT_geDang * s_PercentScale
		-- 目标触发格挡
		local triggerParam = TriggerParam(skillType, _skillEffectType, targetHero, self, { self })
		gBattleTrigger:FireTrigger(BattleTriggerType.GEDANG, triggerParam)
	end

	-- PVP韧性
	local rxDamageScale = 1
	if gBattleManager:IsPVPBattle() then
		rxDamageScale = 1 - targetHero:GetAttribute(AttriType.RENXING) * s_PercentScale
	end

	-- 攻方加伤
	local plusDamageScale = (s_PercentMax + self:GetAttribute(AttriType.PLUSDAMAGE, targetHero)) * s_PercentScale
	
	-- 守方减伤
	local ignoreSkillDamageScale = skillType >= SkillType.SPELL and targetHero:GetAttribute(AttriType.IGNORESKILLDAMAGE) or 0 
	local ignoreDamageScale = s_PercentMax - targetHero:GetAttribute(AttriType.IGNOREDAMAGE, self) - ignoreSkillDamageScale
	ignoreDamageScale = (ignoreDamageScale < Constants.BT_ignoreDamageMin and Constants.BT_ignoreDamageMin or ignoreDamageScale)
	ignoreDamageScale = ignoreDamageScale * s_PercentScale

	-- 伤害倍数
	local damageScale = NilDefault(_damageScale, s_PercentMax) * s_PercentScale + extraDamageScale * s_PercentScale

	-- 护甲相关，无视护甲、真实伤害
	local ignoreDefence = NilDefault(_ignoreDefence, false)
	local ignoreDefenceScale = 1 - (self:GetAttribute(AttriType.IGNOREDEFENCE) + ignoreDefenceFlagScale) * s_PercentScale
	ignoreDefenceScale = ignoreDefenceScale < 0 and 0 or ignoreDefenceScale
	local defenceScale = ignoreDefence == true and 1 or (Constants.BT_fangYuXiShu / (Constants.BT_fangYuXiShu + targetHero:GetDefence() * ignoreDefenceScale))
	
	-- 计算基础伤害，伤害 * 伤害倍数 * 守方减伤 * 攻方加伤 * 护甲系数 * 命中增伤 * 格挡减伤 * 韧性减伤 * 暴击倍数 * 技能额外伤害
	local baseDamage = self:CalcBaseDamage(targetHero, _damageType)
	attackDamage = attackDamage + baseDamage * damageScale * ignoreDamageScale * plusDamageScale * defenceScale * hitExtraDamageScale * gdDamageScale * rxDamageScale * criticalScale * skillDamageScale
	
	return attackDamage, criticalScale, attackHit
end

-- 基础伤害公式枚举
local BaseDamageSwicher = 
{
	-- 自身攻击
	[BattleDamageType.ALL] = function( _battleHero, _targetHero )
		return _battleHero:GetAttack()
	end,
	-- 自身剩余血量%*自己攻击
	[BattleDamageType.CURHPPERATK] = function( _battleHero, _targetHero )
		return _battleHero:GetAttack() * _battleHero.heroData.curHPPercent
	end,
	-- 自身损失血量%*自己攻击
	[BattleDamageType.LOSEHPPERATK] = function( _battleHero, _targetHero )
		return _battleHero:GetAttack() * (1 - _battleHero.heroData.curHPPercent)
	end,
	-- 自身剩余血量
	[BattleDamageType.CURHP] = function( _battleHero, _targetHero )
		return _battleHero.heroData.curHP
	end,
	-- 自身最大血量
	[BattleDamageType.MAXHP] = function( _battleHero, _targetHero )
		return _battleHero.heroData.maxHP
	end,
	-- 目标攻击
	[BattleDamageType.TARGETATK] = function( _battleHero, _targetHero )
		return _targetHero:GetAttack()
	end,
	-- 目标剩余血量%*自己攻击
	[BattleDamageType.TARGETCURHPPERATK] = function( _battleHero, _targetHero )
		return _battleHero:GetAttack() * _targetHero.heroData.curHPPercent * s_PercentScale
	end,
	-- 目标损失血量%*自己攻击
	[BattleDamageType.TARGETLOSEHPPERATK] = function( _battleHero, _targetHero )
		return _battleHero:GetAttack() * (s_PercentMax - _targetHero.heroData.curHPPercent) * s_PercentScale
	end,
	-- 目标剩余血量
	[BattleDamageType.TARGETCURHP] = function( _battleHero, _targetHero )
		return _targetHero.heroData.curHP
	end,
	-- 目标最大血量
	[BattleDamageType.TARGETMAXHP] = function( _battleHero, _targetHero )
		return _targetHero.heroData.maxHP
	end,
}

-- 基础伤害公式
function BattleHero:CalcBaseDamage( _targetHero, _damageType )
	local damageType = NilDefault(_damageType, BattleDamageType.ALL)

	local damageCalculator = NilDefault(BaseDamageSwicher[damageType], BaseDamageSwicher[BattleDamageType.ALL])
	return damageCalculator(self, _targetHero)
end

-- 计算攻击命中
function BattleHero:CalcAttackHit( targetHero, _mustHit )
	-- 必中时不计算命中
	local mustHit = NilDefault(_mustHit, false)
	if mustHit then
		return true
	end

	-- 必中标记
	if self:HasHeroFlag(BattleHeroFlag.MUSTHIT) then
		self:ClearHeroFlag(BattleHeroFlag.MUSTHIT)
		return true
	end

	-- 目标眩晕冰冻石化时无法闪避
	if targetHero:HasHeroFlag(BattleHeroFlag.BINGDONG) or targetHero:HasHeroFlag(BattleHeroFlag.XUANYUN) or targetHero:HasHeroFlag(BattleHeroFlag.SHIHUA) then
		return true
	end
	
	-- 命中率 = ( 10000 - 守方.闪避 + 攻方.命中 ) * ( 1 - 攻方.偏移 / 10000 )
	local hitRate = (s_PercentMax - targetHero:GetAttribute(AttriType.DODGERATE) + self:GetAttribute(AttriType.HITRATE, targetHero)) * (1 - self:GetAttribute(AttriType.PIANYI, targetHeroes) * s_PercentScale)
	if hitRate < Constants.BT_mingZhongMin then
		hitRate = Constants.BT_mingZhongMin
	elseif hitRate > Constants.BT_mingZhongMax then
		hitRate = Constants.BT_mingZhongMax
	end
	return gBattleRandNum:NextInt(s_PercentMax) <= hitRate
end

-- 计算攻击暴击
function BattleHero:CalcAttackCriticalScale( targetHero, _mustCritical, _ignoreCritical )
	-- 忽略暴击
	local ignoreCritical = NilDefault(_ignoreCritical,  false)
	if ignoreCritical then
		return 1
	end
	
	-- 暴击概率 = ( 10000 + 攻方.暴击 - 守方.暴抗 ) 
	local criticalRate = self:GetAttribute(AttriType.CRITICALRATE, targetHero) - targetHero:GetAttribute(AttriType.IGNORECRITICAL)
	if criticalRate < Constants.BT_baoJiMin then
		criticalRate = Constants.BT_baoJiMin
	elseif criticalRate > Constants.BT_baoJiMax then
		criticalRate = Constants.BT_baoJiMax
	end
	
	-- 必然暴击
	local mustCritical = NilDefault(_mustCritical, false)

	-- 必然暴击标记
	local hasMustCriticalFlag = self:HasHeroFlag(BattleHeroFlag.MUSTCRITICAL)
	self:ClearHeroFlag(BattleHeroFlag.MUSTCRITICAL)

	-- 不暴击
	if not mustCritical and not hasMustCriticalFlag and gBattleRandNum:NextInt(s_PercentMax) > criticalRate then
		return 1
	end
	
	-- 暴击倍数 = 常量表.暴倍下限 + 攻方.暴倍 - 守方.暴抗 * 暴抗减暴倍系数 / 10000
	local criticalScale = Constants.BT_baoBeiMin + self:GetAttribute(AttriType.CRITICALSCALE) - targetHero:GetAttribute(AttriType.IGNORECRITICAL) * Constants.BT_ignoreCriticalScale * s_PercentScale
	if criticalScale > Constants.BT_baoBeiMax then
		criticalScale = Constants.BT_baoBeiMax
	elseif criticalScale < Constants.BT_baoBeiMin then
		criticalRate = Constants.BT_baoBeiMin
	end
	return criticalScale * s_PercentScale
end

-- 灼烧伤害
function BattleHero:CalcZhuoShaoDamage( targetHero, value, ... )
	local plusDamageScale = (s_PercentMax + self:GetAttribute(AttriType.PLUSDAMAGE, targetHero)) * s_PercentScale
	local ignoreDamageScale = (s_PercentMax - targetHero:GetAttribute(AttriType.IGNOREDAMAGE)) * s_PercentScale
	local zsScale = value * s_PercentScale

	return targetHero.heroData.maxHP * zsScale * plusDamageScale * ignoreDamageScale
end

-- 回复血量
function BattleHero:HealHP( _healHP, _healerHero, _skillType, _skillEffectType, _isXiXue, ... )
	if self.isPetHero or self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	local skillType = NilDefault(_skillType, SkillType.TALENT)
	if skillType ~= SkillType.TALENT then
		-- 触发被治疗，普攻、大招触发
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, _healerHero, { _healerHero }, _healHP, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKED, triggerParam)
		_healHP = _healHP + triggerParam.extraDamage
	else
		-- 触发治疗命中，加血前，被动或者状态回血
		local triggerParam = TriggerParam(skillType, _skillEffectType, _healerHero, _healerHero, { self })
		gBattleTrigger:FireTrigger(BattleTriggerType.HEALHP, triggerParam, true)
	end

	if self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	local isXiXue = NilDefault(_isXiXue, false)

	-- 计算被治疗提升效果
	local beHealHPPer =  self:GetAttribute(AttriType.BEHEALPER) + s_PercentMax
	beHealHPPer = beHealHPPer < Constants.BT_behealPerMin and Constants.BT_behealPerMin or beHealHPPer
	beHealHPPer = beHealHPPer > Constants.BT_behealPerMax and Constants.BT_behealPerMax or beHealHPPer
	beHealHPPer = beHealHPPer * s_PercentScale

	local healHP = _healHP * (isXiXue and 1 or beHealHPPer)
	
	-- 回血输出英雄增加贡献值
	_healerHero:AddHealHP(healHP)

	-- 计算回血
	self.heroData.curHP = self.heroData.curHP + healHP
	if self.heroData.curHP > self.heroData.maxHP then
		self.heroData.curHP = self.heroData.maxHP
	end
	self.heroData.curHPPercent = self.heroData.curHP * s_PercentMax / self.heroData.maxHP
	
	gBattleManager:AddBattleLog(string.format('HealHP [%d<--%d] HealHP[%.1f] HP[%.1f]', self.heroId, _healerHero.heroId, healHP, self.heroData.curHP))
	
	-- 回血跳字
	if not self:HasHeroFlag(BattleHeroFlag.GHOST) then
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.TIAOZI, TiaoZiType.HUIXUE, self.heroId, healHP)
	else
		self.heroData.curHP = 1
		self.heroData.curHPPercent = 1
	end

	if skillType ~= SkillType.TALENT then
		-- 触发治疗结束，加血后
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, _healerHero, { _healerHero }, healHP, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKEDEND, triggerParam)
	else
		-- 触发治疗命中，加血后，被动或者状态回血
		local triggerParam = TriggerParam(skillType, _skillEffectType, _healerHero, _healerHero, { self })
		gBattleTrigger:FireTrigger(BattleTriggerType.HEALHPEND, triggerParam, true)
	end

	-- 更新血量
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROHP, self.heroId)	
	
	return true
end

-- 计算回血数值
function BattleHero:CalcHealHP( _targetHero, _healPercent, _healType, _skillType )
	-- 大招加血加成
	local skillType = NilDefault(_skillType, SkillType.TALENT)
	local skillScale = s_PercentMax
	if skillType >= SkillType.SPELL then
		skillScale = s_PercentMax + self:GetAttribute(AttriType.SKILLDAMAGE)
		-- 大招伤害提升标记
		if self:HasHeroFlag(BattleHeroFlag.SPELLSCALE) then
			skillScale = skillScale + self:GetHeroFlagValue(BattleHeroFlag.SPELLSCALE)
			self:ClearHeroFlag(BattleHeroFlag.SPELLSCALE)
		end
		skillScale = skillScale > Constants.BT_extraSkillDmgMax and Constants.BT_extraSkillDmgMax or skillScale
		skillScale = skillScale < Constants.BT_extraSkillDmgMin and Constants.BT_extraSkillDmgMin or skillScale
	end
	skillScale = skillScale * s_PercentScale

	local healPercent = NilDefault(_healPercent, s_PercentMax) * s_PercentScale

	-- 计算治疗提升效果
	local healHPPer = self:GetAttribute(AttriType.HEALPER) + s_PercentMax
	healHPPer = healHPPer < Constants.BT_healPerMin and Constants.BT_healPerMin or healHPPer
	healHPPer = healHPPer > Constants.BT_healPerMax and Constants.BT_healPerMax or healHPPer
	healHPPer = healHPPer * s_PercentScale

	local healType = NilDefault(_healType, BattleDamageType.ALL)
	local damageCalculator = NilDefault(BaseDamageSwicher[healType], BaseDamageSwicher[BattleDamageType.ALL])
	return damageCalculator(self, _targetHero) * healPercent * skillScale * healHPPer
end

-- 英雄死亡
function BattleHero:OnHeroDie( _skillType, _skillEffectType, _attackerHero, ... )
	if self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return
	end

	-- 触发英雄死亡
	local triggerParam = TriggerParam(_skillType, _skillEffectType, self, _attackerHero, { _attackerHero })
	gBattleTrigger:FireTrigger(BattleTriggerType.DEATH, triggerParam, true)

	-- 复活啦~~
	if self.heroData.curHP > 0 then
		return
	end

	-- 增加死亡标记
	self:AddHeroFlag(BattleHeroFlag.DEATH)

	-- 触发英雄死亡结束
	local triggerParam = TriggerParam(_skillType, _skillEffectType, self, _attackerHero, { _attackerHero })
	gBattleTrigger:FireTrigger(BattleTriggerType.DEATHEND, triggerParam, true)

	-- 销毁实例
	self:Destroy()
	
	-- 播放死亡动作
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ACTION, self.heroId, HeroActionType.DEATH)
end

-- 英雄怒气
function BattleHero:AddHeroFury( _addFury, ... )
	if _addFury == 0 then
		return
	end

	-- 禁魔不能增加怒气
	if _addFury > 0 and self:HasHeroFlag(BattleHeroFlag.JINMO) then
		return
	end

	self.heroData.fury = self.heroData.fury + _addFury
	if self.heroData.fury > self:GetMaxFury() then
		self.heroData.fury = self:GetMaxFury()
	elseif self.heroData.fury < 0 then
		self.heroData.fury = 0
	end
	-- 更新怒气
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROFURY, self.heroId)	
end

-- 英雄怒气是否已满
function BattleHero:IsHeroFuryFull( ... )
	return self.heroData.fury == self:GetMaxFury()
end

-- 初始化装备
function BattleHero:InitHeroEquip( _equipList, ... )
	local valueList = GameFormula.GetAttrIdListByEquip(_equipList)

	local valueNum = #valueList
	for i = 1, valueNum do
		self:AddAttrValue(valueList[i], 1)
	end
end

-- 初始化符石
function BattleHero:InitHeroStone( _stoneList, ... )
	local valueList, talentList = GameFormula.GetAttrIdListAndTalentIdListByStone(_stoneList)

	local valueNum = #valueList
	for i = 1, valueNum do
		self:AddAttrValue(valueList[i], 1)
	end

	local talentNum = #talentList
	for i = 1, talentNum do
		self:RegisterHeroTalent(talentList[i])
	end
end

function BattleHero:InitHeroAmulet( _heroData )
	-- 添加属性
	if _heroData.amuletAttrTypes and _heroData.amuletAttrValues then
		local attrNum = #_heroData.amuletAttrTypes
		for i=1,attrNum do
			local realType = _heroData.amuletAttrTypes[i]
			local realValue = _heroData.amuletAttrValues[i]
			self.heroData:UpdateCarryAttribute(realType, realValue, true)
		end
	end

	-- 添加天赋
	if _heroData.amuletSkills then
		local talentList = _heroData.amuletSkills -- 实际上是天赋
		local talentNum = #talentList
		for i = 1, talentNum do
			self:RegisterHeroTalent(talentList[i])
		end
	end
end

function BattleHero:InitHeroExtraAttrs( ... )
	local valueList = gBattleManager:GetExtraAttrs(self.heroCamp)
	local valueNum = #valueList
	for i = 1, valueNum do
		self:AddAttrValue(valueList[i], 1)
	end
end

-- 注册行为
function BattleHero:RegisterHeroActions()
	if self.heroRes then
		-- 注册大招天赋
		local skillId = self.isHaloHero and self.attackId or self.heroRes.skillId
		local skillRes = GameResMgr.GetSkillRes(skillId)
		if skillRes then
			self:RegisterHeroTalent(skillRes.talentId)
		end

		-- 注册合体技天赋
		local comboRes, isMainHero = GameResMgr.GetBattleComboResByHeroRes(self.heroRes)
		if comboRes and isMainHero then
			local comboSkillId = comboRes.skillId
			local comboSkillRes = GameResMgr.GetSkillRes(comboSkillId)
			if comboSkillRes then
				self:RegisterHeroTalent(comboSkillRes.talentId)
			end
		end
		
		-- 注册天赋行为
		local talentNum = #self.heroRes.talentIdList
		for i = 1, talentNum do
			-- 只处理已解锁天赋
			local unlockJieLevel = self.isPetHero and 0 or self.heroRes.talentUnlockJieJi[i]
			if unlockJieLevel <= self.heroData.jieLevel then
				local talentId = self.heroRes.talentIdList[i]
				if self.isPetHero then
					talentId = tostring(ToInt(talentId) + self.petLevel * 100)
				end
				self:RegisterHeroTalent(talentId)
			end
		end
	end

	-- 注册额外天赋
	for i = 1, #self.tHeroData.extraTalents do
		self:RegisterHeroTalent(self.tHeroData.extraTalents[i])
	end
end

-- 注册天赋行为
function BattleHero:RegisterHeroTalent( _talentId, _ownerHero, ... )
	if self.talentTriggerIdList[_talentId] or _talentId == '0' then
		return {}
	end

	local triggerIdList = {}
	local talentRes = GameResMgr.GetTalentRes(_talentId)
	if not talentRes then
		return {}
	end

	local actionNum = #talentRes.actionIdList
	for n = 1, actionNum do
		local triggerId = gBattleTrigger:RegisterAction(talentRes.actionIdList[n], self, _ownerHero)
		table.insert(triggerIdList, triggerId)
	end

	self.talentTriggerIdList[_talentId] = triggerIdList
	return triggerIdList
end

-- 移除天赋注册行为
function BattleHero:UnRegisterHeroTalent( _talentId, ... )
	if not self.talentTriggerIdList[_talentId] then
		return
	end

	local triggerIdList = self.talentTriggerIdList[_talentId]
	for i = 1, #triggerIdList do
		gBattleTrigger:UnRegisterActionTrigger(triggerIdList[i])
	end
	self.talentTriggerIdList[_talentId] = nil
end

-- 校验部分状态免疫
function BattleHero:CheckBufferIgnore( _bufferRes, ... )
	if not _bufferRes then
		return false
	end

	if #_bufferRes.valueTypeList ~= 1 then
		return false
	end

	local valueType = _bufferRes.valueTypeList[1]
	if valueType < AttriType.STATE_MIN or valueType > AttriType.STATE_MAX then
		return false
	end

	local ignoreRate = self:GetAttribute(valueType + AttriType.STATE_MAX - AttriType.STATE_MIN)
	if ignoreRate > 0 and gBattleRandNum:NextInt(s_PercentMax) < ignoreRate then
		return true
	end

	return false
end

-- 增加状态
function BattleHero:AddBuffer( bufferResId, ownerHero, isActionEnd, _triggerTargetHeroes, _skillType, _skillEffectType, ... )
	if self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end
	
	local bufferRes = GameResMgr.GetBufferRes(bufferResId)
	if not bufferRes then
		return false
	end

	local skillType = NilDefault(_skillType, SkillType.TALENT)
	if skillType ~= SkillType.TALENT then
		-- 触发被加状态，普攻、大招触发
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, ownerHero, { ownerHero }, 0, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKED, triggerParam)
	end

	if self:HasHeroFlag(BattleHeroFlag.DEATH) then
		return false
	end

	-- 控制类Buff概率免疫
	if bufferRes.bufferType == BufferType.CONTROL then
		local ignoreControlRate = self:GetAttribute(AttriType.IGNORECONTROL)
		if ignoreControlRate > 0 and gBattleRandNum:NextInt(s_PercentMax) < ignoreControlRate then
			return false
		end
	end

	-- 新加护盾需要先移除当前护盾
	if bufferRes.bufferType == BufferType.SHIELD then
		self:RemoveBufferByBufferType(BufferType.SHIELD, 1)
	end

	-- 眩晕、石化、流血、沉默、冰冻免疫校验
	if self:CheckBufferIgnore(bufferRes) then
		return false
	end

	-- 如果增加嘲讽的话，需要先移除英雄身上当前的嘲讽状态
	if #bufferRes.valueTypeList == 1 and bufferRes.valueTypeList[1] == AttriType.CHAOFENG and self.cxBufferId ~= 0 then
		self:RemoveBufferById(self.cxBufferId)
	end
	
	-- 有同ID同所有者的Buffer的话，直接叠加
	local bufferNum = #self.carryBufferList
	for i = 1, bufferNum do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == bufferResId and buffer.ownerHero.heroId == ownerHero.heroId then
			buffer:OverLapBuffer(_triggerTargetHeroes)
			return true
		end
	end
	
	-- 添加新Buffer实例
	local buffer = BattleBuffer()
	if not buffer:Init(bufferResId, ownerHero, self, gBattleManager.realActionHero, isActionEnd) then
		return false
	end
	
	buffer:OverLapBuffer(_triggerTargetHeroes)
	table.insert(self.carryBufferList, buffer)

	if skillType ~= SkillType.TALENT then
		-- 触发加状态结束，加状态后
		local triggerParam = TriggerParam(skillType, _skillEffectType, self, ownerHero, { ownerHero }, 0, self.heroData.curHP)
		gBattleTrigger:FireTrigger(BattleTriggerType.ATTACKEDEND, triggerParam)
	end

	return true
end

-- 销毁状态
function BattleHero:RemoveBuffer( _buffer, _param, _fireTrigger )
	if not _buffer then
		return
	end

	-- 从状态列表中移除
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _buffer.bufferId then
			table.remove(self.carryBufferList, i)
			break
		end
	end

	-- 销毁状态
	_buffer:Destroy(_param, _fireTrigger)
end

-- 是否携带状态
function BattleHero:HasBuffer( _bufferResId, ... )
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferResId then
			return true
		end
	end
	return false
end

-- 驱散Buffer，指定Buffer数值类型
function BattleHero:QuSanBuffer( _targetAttrType, ... )
	if not _targetAttrType then
		return
	end

	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		local valueTypeList = buffer.bufferRes.valueTypeList
		if #valueTypeList == 1 and valueTypeList[1] == _targetAttrType then
			local oldNum = #self.carryBufferList
			self:RemoveBuffer(buffer, 2)
			-- 有可能这次移除会触发移除多个buffer
			if oldNum ~= #self.carryBufferList + 1 then
				return self:QuSanBuffer(_targetAttrType)
			end
		end
	end
end

-- 净化Buffer，指定Buffer增益减益类型
function BattleHero:JingHuaBuffer( _targetPNType, _targetBufferType, _jhCount, ... )
	if not _targetPNType then
		return {}
	end

	local targetBufferType = NilDefault(_targetBufferType, BufferType.ALL)

	local jhBufferList = {}
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		local durRound = buffer.bufferRes.durRound
		local pnType = buffer.bufferRes.pnType
		local bufferType = buffer.bufferRes.bufferType
		if durRound < 888 and (pnType <= BufferPNType.NEGATIVE and (_targetPNType == BufferPNType.ALL or _targetPNType == pnType)) and (targetBufferType == BufferType.ALL or targetBufferType == bufferType) then
			table.insert(jhBufferList, { bufferId = buffer.bufferId, randNum = gBattleRandNum:NextInt(0, 1000000), bufferResId = buffer.bufferRes.id })
		end
	end

	-- 按随机数排序
	table.sort(jhBufferList, function( _leftBuffer, _rightBuffer )
		if _leftBuffer.randNum ~= _rightBuffer.randNum then
			return _leftBuffer.randNum < _rightBuffer.randNum
		end
		return _leftBuffer.bufferId < _rightBuffer.bufferId
	end)

	-- 随机移除指定数量状态
	local finalJhBufferList = {}
	local jhCount = NilDefault(_jhCount, 0)
	for i = 1, #jhBufferList do
		if jhCount ~= 0 and i > jhCount then
			break
		end
		table.insert(finalJhBufferList, jhBufferList[i].bufferResId)
		self:RemoveBufferById(jhBufferList[i].bufferId)
	end

	return finalJhBufferList
end

-- 销毁指定ID状态
function BattleHero:RemoveBufferByTypeId( _bufferTypeId )
	if not _bufferTypeId then
		return
	end

	-- 从状态列表中移除
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.id == _bufferTypeId then
			local oldNum = #self.carryBufferList
			self:RemoveBuffer(buffer)
			-- 有可能这次移除会触发移除多个buffer
			if oldNum ~= #self.carryBufferList + 1 then
				return self:RemoveBufferByTypeId(_bufferTypeId)
			end
		end
	end
end

-- 销毁指定ID状态
function BattleHero:RemoveBufferById( _bufferId )
	if not _bufferId then
		return
	end

	local targetBuffer = false
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferId == _bufferId then
			table.remove(self.carryBufferList, i)
			targetBuffer = buffer
			break
		end
	end

	self:RemoveBuffer(targetBuffer)
end

-- 销毁指定类型状态
function BattleHero:RemoveBufferByBufferType( _bufferType, _param, ... )
	if not _bufferType then
		return
	end

	-- 从状态列表中移除
	local bufferNum = #self.carryBufferList
	for i = bufferNum, 1, -1 do
		local buffer = self.carryBufferList[i]
		if buffer.bufferRes.bufferType == _bufferType then
			local oldNum = #self.carryBufferList
			self:RemoveBuffer(buffer, _param)
			-- 有可能这次移除会触发移除多个buffer
			if oldNum ~= #self.carryBufferList + 1 then
				return self:RemoveBufferByBufferType(_bufferType, _param)
			end
		end
	end
end

-- 多波战斗清除状态
function BattleHero:ClearBufferOnBattleEnd( ... )
	local count = #self.carryBufferList
	for i = count, 1, -1 do
		if self.carryBufferList[i].bufferRes.durRound ~= 999 then
			local oldNum = #self.carryBufferList
			self:RemoveBuffer(self.carryBufferList[i], nil, false)
			-- 有可能这次移除会触发移除多个buffer
			if oldNum ~= #self.carryBufferList + 1 then
				return self:ClearBufferOnBattleEnd()
			end
		end
	end
end

-- 销毁全部状态
function BattleHero:RemoveAllBuffer( ... )
	for i = #self.carryBufferList, 1, -1 do
		local oldNum = #self.carryBufferList
		self:RemoveBuffer(self.carryBufferList[i])
		-- 有可能这次移除会触发移除多个buffer
		if oldNum ~= #self.carryBufferList + 1 then
			return self:RemoveAllBuffer()
		end
	end
	self.carryBufferList = {}
end

-- 绑定状态
function BattleHero:BindActionBuffer( _buffer, ... )
	table.insert(self.actionBufferList, _buffer)
end

-- 解绑状态
function BattleHero:UnbindActionBuffer( _buffer, ... )
	-- if not _buffer then
	-- 	return
	-- end
	
	-- local bufferNum = #self.actionBufferList
	-- for i = bufferNum, 1, -1 do
	-- 	if self.actionBufferList[i].bufferId == _buffer.bufferId then
	-- 		table.remove(self.actionBufferList, i)
	-- 	end
	-- end
end

-- 通知行动相关的所有状态行动一次
function BattleHero:NotifyAllActionBufferAction( _isActionEnd, ... )
	local bufferNum = #self.actionBufferList
	if bufferNum == 0 then
		return
	end

	-- 检查可移除Buffer
	for i = bufferNum, 1, -1 do
		if self.actionBufferList[i].isDestroy == true then
			table.remove(self.actionBufferList, i)
		end
	end

	-- 拥有的Buffer执行一次回合行动
	bufferNum = #self.actionBufferList
	for i = bufferNum, 1, -1 do
		self.actionBufferList[i]:ExecRoundAction(_isActionEnd)
	end
end

-- 替换普攻
function BattleHero:ReplaceNormalAttack( _normalAttackId, ... )
	local skillRes = GameResMgr.GetSkillRes(_normalAttackId)
	if not skillRes then
		return
	end
	
	self.attackId = _normalAttackId
end

-- 偷取怒气
function BattleHero:StealFury( _targetHero, _furyNum, ... )
	-- 从目标偷取怒气
	local realFury = _targetHero:OnFuryStealed(_furyNum)
	-- 给自己加怒气
	self:AddHeroFury(realFury)
end

-- 被偷怒气
function BattleHero:OnFuryStealed( _furyNum, ...  )
	local realFury = _furyNum
	if self.heroData.fury < _furyNum then
		realFury = self.heroData.fury
	end
	
	-- 更新怒气
	self:AddHeroFury(-realFury)
	
	return realFury
end

-- 添加贡献值
function BattleHero:AddAttackDamage( _value, ... )
	self.totalAttackDamage = self.totalAttackDamage + _value
end

function BattleHero:AddHurtDamage( _value, ... )
	self.totalHurtDamage = self.totalHurtDamage + _value
end

function BattleHero:AddHealHP( _value, ... )
	self.totalHealHP = self.totalHealHP + _value
end

-- 英雄添加属性
-- xx属性打a种族b职业目标
-- ALL - xx
-- 目标种族所有职业 axx
-- 目标职业所有种族 b0xx
-- 目标种族目标职业 baxx
function BattleHero:AddAttrValue( attrValueResId, _attrLevel, ... )
	local attrValueRes = GameResMgr.GetAttrValueRes(attrValueResId)
	if not attrValueRes then
		return
	end
	
	-- 校验装备职业
	if attrValueRes.equipMajor ~= MajorType.ALL and attrValueRes.equipMajor ~= self.heroRes.major then
		return		
	end

	-- 校验装备种族
	if attrValueRes.equipRace ~= RaceType.ALL and attrValueRes.equipRace ~= self.heroRes.race then
		return
	end
	
	local realType = attrValueRes.attrType
	if attrValueRes.targetMajor ~= MajorType.ALL then
		realType = realType + attrValueRes.targetMajor * 100
	end
	if attrValueRes.targetRace ~= RaceType.ALL then
		realType = realType + attrValueRes.targetRace * 1000
	end
	
	local attrLevel = NilDefault(_attrLevel, 1)
	self.heroData:UpdateCarryAttribute(realType, attrValueRes.attrValue * attrLevel, true)
end

function BattleHero:IsTriggerFireOverTimes( _triggerRes, _triggerId )
	if not _triggerRes or _triggerRes.maxTriggerTimes == 0 then
		return false
	end

	local triggerKey = _triggerId .. '_' .._triggerRes.id
	if not self.triggerFireRecord[triggerKey] then
		self.triggerFireRecord[triggerKey] = 0
	end

	return self.triggerFireRecord[triggerKey] >= _triggerRes.maxTriggerTimes
end

function BattleHero:RecordTriggerFire( _triggerRes, _triggerId )
	if not _triggerRes or _triggerRes.maxTriggerTimes == 0 then
		return
	end

	local triggerKey = _triggerId .. '_' .._triggerRes.id
	if not self.triggerFireRecord[triggerKey] then
		self.triggerFireRecord[triggerKey] = 0
	end

	self.triggerFireRecord[triggerKey] = self.triggerFireRecord[triggerKey] + 1
end

function BattleHero:GetTriggerFireTimes( _triggerRes, _triggerId )
	if not _triggerRes or _triggerRes.maxTriggerTimes == 0 then
		return 0
	end

	local triggerKey = _triggerId .. '_' .._triggerRes.id
	return self.triggerFireRecord[triggerKey] and self.triggerFireRecord[triggerKey] or 0
end


function BattleHero:RefreshActionFury( ... )
	self.heroData.actionFury = self:HasHeroFlag(BattleHeroFlag.DEATH) and 0 or self.heroData.fury
end

function BattleHero:GetShowScale( ... )
	return self.heroRes.showScale * self.tHeroData.showScale * 0.01 * 1.1
end

function BattleHero:GetExtraShowScale( ... )
	return self.tHeroData.showScale * 0.01 * 1.1
end

function BattleHero:UpdateShield( _totalShield, ... )
	self.totalShield = NilDefault(_totalShield, 0)
	self.curShield = self.totalShield

	-- 更新血量
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.HEROHP, self.heroId)
end

function BattleHero:IsReady( ... )
	return self.loadingState == 2
end

classend()