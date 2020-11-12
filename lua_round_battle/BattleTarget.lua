---
--- class BattleTarget
-- @classmod BattleTarget
class('BattleTarget')

-- 普攻目标
local FindNormalTarget = function( _actionHero, _defaultTargets, ... )
	local targetHeroes = {}
	-- 普攻有目标列表时，直接返回
	if _defaultTargets and #_defaultTargets ~= 0 then
		local heroNum = #_defaultTargets
		for i = 1, heroNum do
			table.insert(targetHeroes, _defaultTargets[i])
		end
		return targetHeroes
	end
	
	if not _actionHero then
		return targetHeroes
	end
	
	local targetCamp = GetTargetCamp(_actionHero.heroCamp, BattleTargetType.ENEMY)
	local campHeroList = gBattleManager:GetCampHeroList(targetCamp)
	local campHeroNum = #campHeroList
	if campHeroNum == 0 then
		return targetHeroes
	end

	-- 直接返回第一个英雄
	table.insert(targetHeroes, campHeroList[1])
	return targetHeroes
end

-- 寻找目标入口
function BattleTarget.FindTargetHero( _targetId, _actionHero, _defaultTargets, _attackerHero, _triggerHero, ... )
	local targetHeroes = FindTargetHero_Internal(_targetId, _actionHero, _defaultTargets, _attackerHero, _triggerHero)
	local targetRes = GameResMgr.GetBattleTargetRes(_targetId)
	if not targetRes then
		return targetHeroes
	end
	if targetRes.targetType == BattleTargetType.EMPTY then
		return {}
	end

	if targetRes.specialLogic == BattleTargetLogicType.CHUANCI then
		-- 穿刺
		targetHeroes = FindChuanCiTarget(targetHeroes)
	elseif targetRes.specialLogic == BattleTargetLogicType.SAMEROW then
		-- 同排
		targetHeroes = FindSameRowTarget(targetHeroes)
	end

	return targetHeroes
end

function BattleTarget.FindTargetHero_Internal( _targetId, _actionHero, _defaultTargets, _attackerHero, _triggerHero, ... )
	if _targetId == '-1' then
		return {}
	end
	local targetRes = GameResMgr.GetBattleTargetRes(_targetId)
	if not targetRes then
		return FindNormalTarget(_actionHero, _defaultTargets)
	end
	if targetRes.targetType == BattleTargetType.EMPTY then
		return {}
	end
	
	local targetHeroes = {}
	if not _actionHero then
		return targetHeroes
	end
	
	-- 普攻及后二
	if targetRes.specialLogic == BattleTargetLogicType.TRIANGLE then
		return FindNormalTriangleTarget(_actionHero)
	end
	
	-- 目标类型，筛选一次目标
	local targetType = targetRes.targetType
	if targetType == BattleTargetType.SELF then
		-- 自己，不考虑其他参数，直接返回自己
		table.insert(targetHeroes, _actionHero)
		return targetHeroes
	elseif targetType == BattleTargetType.ATTACKER then
		-- 攻击者
		table.insert(targetHeroes, _attackerHero)
		return targetHeroes
	elseif targetType == BattleTargetType.TRIGGER then
		-- 触发者
		table.insert(targetHeroes, _triggerHero)
		return targetHeroes
	elseif targetType == BattleTargetType.ENEMYTARGETS then
		-- 行动目标，先把所有目标单位罗列出来，再计算其他参数
		local targetList = _defaultTargets
		if not targetList or #targetList == 0 then
			targetList = gBattleAction:GetCurTargetHeroes()
		end

		local heroNum = #targetList
		for i = 1, heroNum do
			if targetList[i].heroCamp ~= _actionHero.heroCamp then
				table.insert(targetHeroes, targetList[i])
			end
		end
	elseif targetType == BattleTargetType.TARGETS then
		-- 行动目标，先把所有目标单位罗列出来，再计算其他参数
		local targetList = _defaultTargets
		if not targetList or #targetList == 0 then
			targetList = gBattleAction:GetCurTargetHeroes()
		end
		
		local heroNum = #targetList
		for i = 1, heroNum do
			table.insert(targetHeroes, targetList[i])
		end
	elseif targetType == BattleTargetType.NORMALTARGET then
		targetHeroes = FindNormalTarget(_actionHero, _defaultTargets)
	else
		-- 敌我阵营，先把所有目标单位罗列出来，再计算其他参数
		local targetCamp = GetTargetCamp(_actionHero.heroCamp, targetType)
		local campHeroList = gBattleManager:GetCampHeroList(targetCamp)
		local heroNum = #campHeroList
		for i = 1, heroNum do
			if targetType ~= BattleTargetType.FRIENDNOTME or campHeroList[i].heroId ~= _actionHero.heroId then
				if not campHeroList[i]:HasHeroFlag(BattleHeroFlag.DEATH) then
					table.insert(targetHeroes, campHeroList[i])
				end
			end
		end
	end

	-- 过滤排除上次目标英雄
	FilterExceptLastTarget(targetRes.exceptLastTarget == 1, targetHeroes)

	-- 站位筛选
	FilterPosTarget(targetRes.posType, targetHeroes)
	
	-- 职业筛选
	FilterMajorTarget(targetRes.major, targetHeroes)

	-- 种族筛选
	FilterRaceTarget(targetRes.race, targetHeroes)
	
	-- 状态筛选
	FilterHeroFlagTarget(targetRes.heroFlag, targetHeroes)

	-- Buffer筛选
	FilterHeroBufferTarget(targetRes.heroBuffer, targetHeroes)
	
	-- 特殊逻辑
	FilterSpecialLogicTarget(targetRes.specialLogic, targetHeroes, targetRes.targetCount)
	
	-- 随机筛选
	FilterRandomTarget(targetRes.targetCount, targetHeroes)
	
	return targetHeroes
end

-- 目标阵营
function BattleTarget.GetTargetCamp( _selfCamp, _targetType )
	if _targetType ~= BattleTargetType.ENEMY then
		return _selfCamp
	end
	
	local targetCamp = _selfCamp + 1
	if targetCamp == BattleCampType.MAX then
		targetCamp = BattleCampType.CAMP_A
	end
	return targetCamp
end

-- 站位筛选
function BattleTarget.FilterPosTarget( _posType, targetHeroes, ... )
	local targetSwitcher = {
		-- 前排筛选
		[BattlePosType.FRONT] = function( targetHeroes, ... )
			FilterFrontTarget(targetHeroes)
		end,
		-- 后排筛选
		[BattlePosType.BACK] = function( targetHeroes, ... )
			FilterBackTarget(targetHeroes)
		end,
		-- 前中排筛选
		[BattlePosType.FANDM] = function( targetHeroes, ... )
			FilterFrontAndMiddleTarget(targetHeroes)
		end,
		-- 中后排筛选
		[BattlePosType.MANDB] = function( targetHeroes, ... )
			FilterMiddleAndBackTarget(targetHeroes)
		end,
		-- 中排筛选
		[BattlePosType.MIDDLE] = function( targetHeroes, ... )
			FilterMiddleTarget(targetHeroes)
		end
	}
	
	local targetFilter = targetSwitcher[_posType]
	if targetFilter then
		targetFilter(targetHeroes, ...)
	end
end

-- 前排筛选
function BattleTarget.FilterFrontTarget( targetHeroes, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	-- 找到最前排的位置类型
	local campHeroList = gBattleManager:GetCampHeroList(targetHeroes[1].heroCamp)
	local maxFrontPosType = BattlePosType.MAX
	for i = 1, #campHeroList do
		local battleHero = campHeroList[i]
		if battleHero.heroPosRes.posType < maxFrontPosType then
			maxFrontPosType = battleHero.heroPosRes.posType
		end
	end

	-- 移除非最前排位置的所有单位
	for i = heroNum, 1, -1 do
		if targetHeroes[i].heroPosRes.posType ~= maxFrontPosType then
			table.remove(targetHeroes, i)
		end
	end
end

-- 后排筛选
function BattleTarget.FilterBackTarget( targetHeroes, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	-- 找到最后排的位置类型
	local campHeroList = gBattleManager:GetCampHeroList(targetHeroes[1].heroCamp)
	local maxBackPosType = BattlePosType.ALL
	for i = 1, #campHeroList do
		local battleHero = campHeroList[i]
		if battleHero.heroPosRes.posType > maxBackPosType then
			maxBackPosType = battleHero.heroPosRes.posType
		end
	end

	-- 移除非最后排位置的所有单位
	for i = heroNum, 1, -1 do
		if targetHeroes[i].heroPosRes.posType ~= maxBackPosType then
			table.remove(targetHeroes, i)
		end
	end
end

-- 前中排筛选
function BattleTarget.FilterFrontAndMiddleTarget( targetHeroes, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	-- 找到所有排的位置类型
	local campHeroList = gBattleManager:GetCampHeroList(targetHeroes[1].heroCamp)
	local allPosTypeList = {}
	for i = 1, #campHeroList do
		local battleHero = campHeroList[i]
		if not allPosTypeList[battleHero.heroPosRes.posType] then
			allPosTypeList[battleHero.heroPosRes.posType] = 1
		end
	end

	-- 统计所有排的总数
	local totalPosCount = 0
	for k, v in pairs(allPosTypeList) do
		if v == 1 then
			totalPosCount = totalPosCount + 1
		end
	end

	if totalPosCount == 3 then
		-- 移除最后排位置的所有单位
		for i = heroNum, 1, -1 do
			if targetHeroes[i].heroPosRes.posType == BattlePosType.BACK then
				table.remove(targetHeroes, i)
			end
		end
	end
end

-- 中后排筛选
function BattleTarget.FilterMiddleAndBackTarget( targetHeroes, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	-- 找到所有排的位置类型
	local campHeroList = gBattleManager:GetCampHeroList(targetHeroes[1].heroCamp)
	local allPosTypeList = {}
	for i = 1, #campHeroList do
		local battleHero = campHeroList[i]
		if not allPosTypeList[battleHero.heroPosRes.posType] then
			allPosTypeList[battleHero.heroPosRes.posType] = 1
		end
	end

	-- 统计所有排的总数
	local totalPosCount = 0
	for k, v in pairs(allPosTypeList) do
		if v == 1 then
			totalPosCount = totalPosCount + 1
		end
	end

	if totalPosCount == 3 then
		-- 移除最前排位置的所有单位
		for i = heroNum, 1, -1 do
			if targetHeroes[i].heroPosRes.posType == BattlePosType.FRONT then
				table.remove(targetHeroes, i)
			end
		end
	end
end

-- 中排筛选
function BattleTarget.FilterMiddleTarget( targetHeroes, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	-- 找到所有排的位置类型
	local campHeroList = gBattleManager:GetCampHeroList(targetHeroes[1].heroCamp)
	local allPosTypeList = {}
	allPosTypeList[BattlePosType.FRONT] = 0
	allPosTypeList[BattlePosType.MIDDLE] = 0
	allPosTypeList[BattlePosType.BACK] = 0

	for i = 1, #campHeroList do
		local battleHero = campHeroList[i]
		if not allPosTypeList[battleHero.heroPosRes.posType] then
			allPosTypeList[battleHero.heroPosRes.posType] = 1
		end
	end

	-- 找到第二排类型
	local middlePosType = -3
	for i = 1, #allPosTypeList do
		if allPosTypeList[i] == 1 then
			middlePosType = middlePosType + 1
			if middlePosType == -1 then
				middlePosType = i
				break
			end
		end
	end

	-- 移除非中排位置的所有单位
	for i = heroNum, 1, -1 do
		if targetHeroes[i].heroPosRes.posType ~= middlePosType then
			table.remove(targetHeroes, i)
		end
	end
end

-- 职业筛选
function BattleTarget.FilterMajorTarget( _major, targetHeroes, ... )
	if _major == MajorType.ALL then
		return
	end
	
	local heroNum = #targetHeroes
	for i = heroNum, 1, -1 do
		if _major > 0 and targetHeroes[i].heroRes.major ~= _major then
			-- 移除非指定职业单位
			table.remove(targetHeroes, i)
		elseif _major < 0 and targetHeroes[i].heroRes.major == -_major then
			-- 移除指定职业单位
			table.remove(targetHeroes, i)
		end
	end
end

-- 种族筛选
function BattleTarget.FilterRaceTarget( _race, targetHeroes, ... )
	if _race == RaceType.ALL then
		return
	end
	
	
	local heroNum = #targetHeroes
	for i = heroNum, 1, -1 do
		if _race > 0 and targetHeroes[i].heroRes.race ~= _race then
			-- 移除非指定种族单位
			table.remove(targetHeroes, i)
		elseif _race < 0 and targetHeroes[i].heroRes.race == -_race then
			-- 移除指定种族单位
			table.remove(targetHeroes, i)
		end
	end
end

-- 状态筛选
function BattleTarget.FilterHeroFlagTarget( _heroFlag, targetHeroes, ... )
	if _heroFlag == BattleHeroFlag.ALL then
		return
	end
	
	local heroNum = #targetHeroes
	for i = heroNum, 1, -1 do
		if _heroFlag > 0 and not targetHeroes[i]:HasHeroFlag(_heroFlag) then
			-- 移除非指定状态单位
			table.remove(targetHeroes, i)
		elseif _heroFlag < 0 and targetHeroes[i]:HasHeroFlag(-_heroFlag) then
			-- 移除指定状态单位
			table.remove(targetHeroes, i)
		end
	end
end

-- Buffer筛选
function BattleTarget.FilterHeroBufferTarget( _heroBuffer, targetHeroes, ... )
	if _heroBuffer == 0 then
		return
	end
	
	local heroNum = #targetHeroes
	for i = heroNum, 1, -1 do
		if _heroBuffer > 0 and not targetHeroes[i]:HasBuffer(_heroBuffer) then
			-- 移除非指定状态单位
			table.remove(targetHeroes, i)
		elseif _heroBuffer < 0 and targetHeroes[i]:HasBuffer(-_heroBuffer) then
			-- 移除指定状态单位
			table.remove(targetHeroes, i)
		end
	end
end

-- 随机筛选
function BattleTarget.FilterRandomTarget( _targetCountList, targetHeroes, ... )
	if not _targetCountList or #_targetCountList == 0 then
		return
	end

	local randomCount = 0
	if #_targetCountList == 1 then
		randomCount = _targetCountList[1]
	else
		local index = gBattleRandNum:NextInt(1, #_targetCountList)
		randomCount = _targetCountList[index]
	end

	if randomCount == 0 then
		return
	end
	
	-- 目标英雄数量小于等于随机数量时，不再筛选
	local heroNum = #targetHeroes
	if heroNum == 0 or heroNum <= randomCount then
		return
	end
	
	-- 随机索引列表
	local randIndex = {}
	gBattleRandNum:ClearUniqueRecord(UniqueRandType.BATTLETARGET)
	for i = 1, randomCount do
		local index = gBattleRandNum:NextUniqueInt(UniqueRandType.BATTLETARGET, heroNum)
		randIndex[index] = 1
	end
	
	-- 移除非随机索引列表中的单位
	for i = heroNum, 1, -1 do
		if randIndex[i] ~= 1 then
			table.remove(targetHeroes, i)
		end
	end
end

-- 特殊逻辑筛选
function BattleTarget.FilterSpecialLogicTarget( _specialLogic, targetHeroes, _targetCountList, ... )
	if _specialLogic == BattleTargetLogicType.ALL then
		return
	end

	local specialSwitcher = {
		-- 血量最少筛选
		[BattleTargetLogicType.HPMIN] = function( targetHeroes, targetCount, ... )
			FilterMinHPTarget(targetHeroes, targetCount)
		end,
		-- 血量比例最少筛选
		[BattleTargetLogicType.HPPERMIN] = function( targetHeroes, targetCount, ... )
			FilterMinHPPerTarget(targetHeroes, targetCount)
		end,
		-- 怒气最少
		[BattleTargetLogicType.NQMIN] = function( targetHeroes, targetCount, ... )
			FilterMinFuryTarget(targetHeroes, targetCount)
		end,
		-- 怒气最多
		[BattleTargetLogicType.NQMAX] = function( targetHeroes, targetCount, ... )
			FilterMaxFuryTarget(targetHeroes, targetCount)
		end,
		-- 攻击最大
		[BattleTargetLogicType.ATTACKMAX] = function( targetHeroes, targetCount, ... )
			FilterMaxAttackTarget(targetHeroes, targetCount)
		end,
		-- 攻击最小
		[BattleTargetLogicType.ATTACKMIN] = function( targetHeroes, targetCount, ... )
			FilterMinAttackTarget(targetHeroes, targetCount)
		end,
	}

	local targetCount = 0
	if #_targetCountList == 0 then
		targetCount = 1
	elseif #_targetCountList == 1 then
		targetCount = _targetCountList[1]
	else
		local index = gBattleRandNum:NextInt(1, #_targetCountList)
		targetCount = _targetCountList[index]
	end
	targetCount = targetCount < 1 and 1 or targetCount
	
	local specialFilter = specialSwitcher[_specialLogic]
	if specialFilter then
		specialFilter(targetHeroes, targetCount, ...)
	end
end

-- 血量比例最少筛选
function BattleTarget.FilterMinHPPerTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	if heroNum <= targetCount then
		return
	end
	
	-- 按血量比例从低到高排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		if _heroLeft.heroData.curHPPercent ~= _heroRight.heroData.curHPPercent then
			return _heroLeft.heroData.curHPPercent < _heroRight.heroData.curHPPercent
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 血量最少筛选
function BattleTarget.FilterMinHPTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end

	if heroNum <= targetCount then
		return
	end
	
	-- 按血量从低到高排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		if _heroLeft.heroData.curHP ~= _heroRight.heroData.curHP then
			return _heroLeft.heroData.curHP < _heroRight.heroData.curHP
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 怒气最少筛选
function BattleTarget.FilterMinFuryTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	if heroNum <= targetCount then
		return
	end
	
	-- 按血量比例从低到高排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		if _heroLeft.heroData.actionFury ~= _heroRight.heroData.actionFury then
			return _heroLeft.heroData.actionFury < _heroRight.heroData.actionFury
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 怒气最多筛选
function BattleTarget.FilterMaxFuryTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	if heroNum <= targetCount then
		return
	end
	
	-- 按血量比例从高到低排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		if _heroLeft.heroData.actionFury ~= _heroRight.heroData.actionFury then
			return _heroLeft.heroData.actionFury > _heroRight.heroData.actionFury
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 攻击最高
function BattleTarget.FilterMaxAttackTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	if heroNum <= targetCount then
		return
	end
	
	-- 按攻击比例从高到低排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		local leftAttack = _heroLeft:GetAttack()
		local rightAttack = _heroRight:GetAttack()
		if leftAttack ~= rightAttack then
			return leftAttack > rightAttack
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 攻击最低
function BattleTarget.FilterMinAttackTarget( targetHeroes, targetCount, ... )
	local heroNum = #targetHeroes
	if heroNum == 0 then
		return
	end
	
	if heroNum <= targetCount then
		return
	end
	
	-- 按攻击比例从低到高排序
	table.sort(targetHeroes, function( _heroLeft, _heroRight )
		local leftAttack = _heroLeft:GetAttack()
		local rightAttack = _heroRight:GetAttack()
		if leftAttack ~= rightAttack then
			return leftAttack < rightAttack
		end
		return _heroLeft.heroId < _heroRight.heroId
	end)

	for i = #targetHeroes, 1, -1 do
		if i > targetCount then
			table.remove(targetHeroes, i)
		end
	end
end

-- 普攻及后二
function BattleTarget.FindNormalTriangleTarget( _actionHero, ... )
	local targetHeroes = {}
	if not _actionHero then
		return targetHeroes
	end
	
	local targetCamp = GetTargetCamp(_actionHero.heroCamp, BattleTargetType.ENEMY)
	local campHeroList = gBattleManager:GetCampHeroList(targetCamp)
	local campHeroNum = #campHeroList
	if campHeroNum == 0 then
		return targetHeroes
	end

	-- 添加普攻英雄
	local normalTarget = campHeroList[1]
	table.insert(targetHeroes, normalTarget)
	
	-- 后二，非后排才有
	if normalTarget.heroPosRes.posType ~= BattlePosType.BACK then
		for i = 1, 2 do
			local posId = normalTarget.heroPosRes.posId + i + normalTarget.heroPosRes.posType - 1
			local posHero = gBattleManager:GetCampPosHero(targetCamp, posId)
			if posHero then
				table.insert(targetHeroes, posHero)
			end
		end
	end
	
	return targetHeroes
end

-- 穿刺
function BattleTarget.FindChuanCiTarget( _targetHeroes, ... )
	if not _targetHeroes or #_targetHeroes == 0 then
		return _targetHeroes
	end

	-- 目标缓存，用于去重
	local targetHeroCache = {}
	for i = 1, #_targetHeroes do
		targetHeroCache[_targetHeroes[i].heroId] = _targetHeroes[i]
	end

	local targetCamp = _targetHeroes[1].heroCamp
	for i = 1, #_targetHeroes do
		local hero = _targetHeroes[i]
		if hero.heroPosRes.posType ~= BattlePosType.BACK then
			local heroes = gBattleManager:GetCampPosTypeHero(targetCamp, hero.heroPosRes.posType + 1, 1)
			if heroes and #heroes == 1 then
				local posHero = heroes[1]
				if posHero then
					targetHeroCache[posHero.heroId] = posHero
				end
			end
		end
	end

	_targetHeroes = {}
	for k, v in pairs(targetHeroCache) do
		table.insert(_targetHeroes, v)
	end
	
	-- 不同平台in pairs存在顺序不同的问题，所以需要重新排序
	table.sort(_targetHeroes, function( _heroLeft, _heroRight )
		return _heroLeft.heroId < _heroRight.heroId
	end)

	return _targetHeroes
end

-- 同排
function BattleTarget.FindSameRowTarget( _targetHeroes, ... )
	if not _targetHeroes or #_targetHeroes == 0 then
		return _targetHeroes
	end

	-- 目标缓存，用于去重
	local targetHeroCache = {}
	local targetRowCache = {}
	for i = 1, #_targetHeroes do
		targetHeroCache[_targetHeroes[i].heroId] = _targetHeroes[i]
		targetRowCache[_targetHeroes[i].heroPosRes.posType] = 1
	end

	local targetCampHeroList = gBattleManager:GetCampHeroList(_targetHeroes[1].heroCamp)
	for i = 1, #targetCampHeroList do
		local hero = targetCampHeroList[i]
		if targetRowCache[hero.heroPosRes.posType] == 1 then
			targetHeroCache[hero.heroId] = hero
		end
	end

	_targetHeroes = {}
	for k, v in pairs(targetHeroCache) do
		table.insert(_targetHeroes, v)
	end

	-- 不同平台in pairs存在顺序不同的问题，所以需要重新排序
	table.sort(_targetHeroes, function( _heroLeft, _heroRight )
		return _heroLeft.heroId < _heroRight.heroId
	end)

	return _targetHeroes
end

-- 过滤排除英雄
function BattleTarget.FilterExceptLastTarget( _isExceptLastTarget, _targetHeroes, ... )
	if not _isExceptLastTarget or not _targetHeroes or #_targetHeroes == 0 then
		return
	end

	local lastTargets = gBattleAction:GetLastTargetHeroes(true)
	if not lastTargets or #lastTargets == 0 then
		return
	end

	local exceptHeroIdMap = {}
	for i = 1, #lastTargets do
		exceptHeroIdMap[lastTargets[i].heroId] = 1
	end

	for i = #_targetHeroes, 1, -1 do
		if exceptHeroIdMap[_targetHeroes[i].heroId] == 1 then
			table.remove(_targetHeroes, i)
		end
	end
end

classend()