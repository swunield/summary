---
--- class BattleManager
-- @classmod BattleManager‘
-- 战斗管理器，包括英雄、回合、行动管理等
class('BattleManager')

-- 车轮战战斗类型
local WheelBattleList = {
	BattleType.SHILIAN,
	BattleType.YUANZHENG,
	BattleType.PATA,
}

-- 九宫格战斗类型
local NineFieldBattleList = {
	BattleType.SOCIALBOSS,
}

---Constructor
function BattleManager:ctor( ... )
	self.heroList = {}					-- 战斗英雄列表
	self.campHeroList = {}				-- 战斗阵营英雄列表，只包存存活英雄，且按位置排序
	self.campGhostHeroList = {}			-- 战斗阵营鬼魂列表
	self.campHaloHeroList = {} 			-- 战斗阵营光环英雄列表，英雄和队伍一一对应，同阵营切换队伍时，需要销毁上一个光环英雄（单队开场）
	self.campPetHeroList = {}			-- 战斗阵营宠物英雄列表，英雄和队伍一一对应，同阵营切换队伍时，需要销毁上一个宠物英雄（单队开场)
	self.campTalentHeroList = {}		-- 战斗阵营天赋英雄列表，英雄和阵营一一对应，整场战斗只在入场时创建（全局）
	self.campFetterHeroList = {}		-- 战斗阵营羁绊英雄列表，英雄和队伍一一对应，同阵营切换队伍时，需要销毁上一个羁绊英雄（单队开场）
	self.heroIdGenerator = 0			-- 英雄ID生成器
	self.bufferIdGenerator = 0			-- 状态ID生成器
	self.roundNum = 0					-- 战斗回合数
	self.roundActionOrder = {}			-- 战斗回合行动顺序，战斗开场确定
	self.roundActionList = {}			-- 战斗回合行动队列
	self.extraActionList = {}			-- 战斗额外行动队列
	self.allBattleResult = {}
	self.realActionHero = false			-- 真实行动英雄
	self.lastActionHero = false			-- 最后一个行动的英雄
	self.jumpBattle = false				-- 跳过战斗

	self.battleId = ''					-- 战斗Id
	self.battleType = BattleType.ALL 	-- 战斗类型
	self.battleParam = ''				-- 战斗参数
	self.maxRound = Constants.BT_roundMax -- 最大回合数
	self.battleFieldType = BattleFieldType.SIX -- 战场类型
	self.battleFieldRes = false			-- 战场配置
	self.isWheelBattle = false 			-- 是否车轮战(2 全胜1 车轮0 田忌)
	self.isPvpBattle = false			-- 是否PVP战斗
	self.battleCampData = false 		-- 战场阵营数据
	self.campTeamIndex = {}				-- 战场阵营队伍索引

	self.battleResult = BattleResult()	-- 战斗结果
	self.curSingleResult = false 		-- 当前单场战斗结果
	self.isRecord = false				-- 是否战斗记录
	self.isVideo = false				-- 是否录像

	self.specialBattleData = {}			-- 特殊战斗数据
	self.isRoundEndTriggered = false 	-- 回合结束是否触发

	self.campDieLoseHeroList = {}		-- 阵营死亡即失败英雄列表

	self.isClientMode = false 			-- 是否客户端模式
	self.isLogEnable = false			-- 是否保存Log
end

-- 初始化
function BattleManager:Initialize( _battleEnterData, _isLogEnable, ... )
	if not _battleEnterData then
		return
	end

	-- 日志相关
	self.isLogEnable = NilDefault(_isLogEnable, BattleMain.LogEnable)
	self.battleId = _battleEnterData.battleId
	self:AddBattleLog('log_reset', true)

	-- 阵营英雄列表、阵营统计列表
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		self.campHeroList[i] = {}
		self.campGhostHeroList[i] = {}
		self.campDieLoseHeroList[i] = false
		self.battleResult.campTeamStat[i] = BattleCampTeamStat()
		self.battleResult.campWinStat[i] = 0
		self.campTeamIndex[i] = 1
		self.campHaloHeroList[i] = false
		self.campPetHeroList[i] = false
		self.campTalentHeroList[i] = false
		self.campFetterHeroList[i] = false
	end

	-- 阵营数据
	self.battleCampData = _battleEnterData.campData
	self.battleType = _battleEnterData.battleType
	self.battleParam = _battleEnterData.battleParam
	self.battleFieldRes = GameResMgr.GetBattleFieldRes(self.battleType)
	if not self.battleFieldRes then
		return
	end

	self.battleFieldType = self.battleFieldRes.fieldType
	self.isWheelBattle = self.battleFieldRes.isWheelBattle
	self.isPvpBattle = self.battleFieldRes.isPvpBattle ~= 0
end

-- 初始战斗
function BattleManager:InitBattleTeam( _camp, _notifyAddAllHero, ... )
	local campData = self.battleCampData[_camp]
	if not campData then
		return false
	end

	local notifyAddAllHero = NilDefault(_notifyAddAllHero, true)

	local teamIndex = self.campTeamIndex[_camp]
	if teamIndex > #campData.teamList then
		if notifyAddAllHero then
			-- 通知表现层添加英雄
			self:NotifyGBCommandAddAllHero()
			-- 重置回合数
			self.roundNum = 0
		end

		-- 校验战斗是否结束
		self:CheckBattleEnd()

		return false
	end

	local teamStat = BattleTeamStat()
	table.insert(self.battleResult.campTeamStat[_camp].teamStat, teamStat)

	local team = campData.teamList[teamIndex]
	
	-- 添加羁绊英雄
	self:AddBattleCampFetterHero(_camp, NilDefault(team.heroList, {}))

	-- 队伍光环
	self:AddBattleTeamHaloHero(_camp, team.haloId)

	-- 队伍宠物
	-- team.pet = {
	-- 	petId = 1,
	-- 	heroId = 240051,
	-- 	level = 1,
	-- 	talentList = {}
	-- }
	self:AddBattleTeamPetHero(_camp, team.pet)

	-- 添加阵营英雄
	local heroList = team.heroList
	local heroNum = #heroList
	local allHeroInvalid = true
	for index = 1, heroNum do
		if self:AddBattleHero(heroList[index], _camp, nil, 0, 0, false, false) then
			allHeroInvalid = false
		end
	end

	-- 当前队已全部死亡，尝试初始化下一队
	if allHeroInvalid then
		if self.isWheelBattle == 1 then
			self.campTeamIndex[_camp] = self.campTeamIndex[_camp] + 1
			self.campDieLoseHeroList[_camp] = false
			return self:InitBattleTeam(_camp, _notifyAddAllHero)
		end
	end

	if notifyAddAllHero then
		-- 通知表现层添加英雄
		self:NotifyGBCommandAddAllHero()
		-- 重置回合数
		self.roundNum = 0
	end

	-- 通知表现层刷新队伍索引
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.TEAM, _camp, teamIndex, #campData.teamList)

	return true
end

-- 添加阵营天赋英雄
function BattleManager:InitBattleCampTalent( ... )
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		local campData = self.battleCampData[i]
		if not campData then
			return
		end

		self:AddBattleCampTalentHero(i, campData.extraTalents)
	end
end

function BattleManager:AddBattleCampTalentHero( _camp, _talents, ... )
	if self.campTalentHeroList[_camp] or not _talents or #_talents == 0 then
		return
	end

	local heroData = gameres.BattleHeroData()
	heroData.typeId = Constants.BT_emptyHeroId
	heroData.battlePos = 1

	local battleHero = self:AddBattleHero(heroData, _camp, _talents, 0, 0, true, false)
	if not battleHero then
		return
	end

	self.campTalentHeroList[_camp] = battleHero

	self:AddBattleLog(string.format('AddBattleCampTalentHero Camp[%d] Team[%d] Talent[%s]', _camp, battleHero.teamIndex, gameutils.JSON:encode(_talents)))
end

function BattleManager:AddBattleCampFetterHero( _camp, _heroList, ... )
	-- 先销毁当前的光环英雄
	if self.campFetterHeroList[_camp] then
		self.campFetterHeroList[_camp]:Destroy()
		self.campFetterHeroList[_camp] = false
	end

	local heroData = gameres.BattleHeroData()
	heroData.typeId = Constants.BT_emptyHeroId
	heroData.battlePos = 1

	-- 计算职业羁绊
	local heroTemplateIdList = {}
	for i=1,#_heroList do
		table.insert(heroTemplateIdList, _heroList[i].typeId)
	end
	local _,_,talentList = GameFormula.CaculateMajorCombo(heroTemplateIdList)

	if not talentList or #talentList == 0 then return end

	local battleHero = self:AddBattleHero(heroData, _camp, talentList, 0, 0, false, false)
	if not battleHero then
		return
	end

	self.campFetterHeroList[_camp] = battleHero

	self:AddBattleLog(string.format('AddBattleCampFetterHero Camp[%d] Team[%d] Talent[%s]', _camp, battleHero.teamIndex, gameutils.JSON:encode(talentList)))
end

-- 添加队伍光环英雄
function BattleManager:AddBattleTeamHaloHero( _camp, _haloId, ... )
	-- 先销毁当前的光环英雄
	if self.campHaloHeroList[_camp] then
		self.campHaloHeroList[_camp]:Destroy()
		self.campHaloHeroList[_camp] = false
	end

	local haloRes = GameResMgr.GetHaloRes(_haloId)
	if not haloRes then
		return
	end

	local heroData = gameres.BattleHeroData()
	heroData.typeId = haloRes.heroId
	heroData.battlePos = 20

	local battleHero = self:AddBattleHero(heroData, _camp, nil, haloRes.level, 0, false, false)
	if not battleHero then
		return
	end

	self.campHaloHeroList[_camp] = battleHero

	self:AddBattleLog(string.format('AddBattleTeamHaloHero Camp[%d] Team[%d] Halo[%d]', _camp, battleHero.teamIndex, _haloId))
end

-- 添加队伍宠物英雄
function BattleManager:AddBattleTeamPetHero( _camp, _pet, ... )
	-- 先销毁当前的宠物英雄
	self:RemoveBattleCampPetHero(_camp)

	if not _pet or not _pet.petId or _pet.petId == 0 then
		return
	end

	local heroData = gameres.BattleHeroData()
	heroData.typeId = _pet.heroId
	heroData.level = _pet.level
	heroData.battlePos = 30

	local battleHero = self:AddBattleHero(heroData, _camp, _pet.talentList, 0, _pet.level, false, false)
	if not battleHero then
		return
	end

	self.campPetHeroList[_camp] = battleHero

	self:AddBattleLog(string.format('AddBattleTeamPetHero Camp[%d] Team[%d] Hero[%d] Level[%d]', _camp, battleHero.teamIndex, _pet.heroId, _pet.level))
end

function BattleManager:RemoveBattleCampPetHero( _camp, ... )
	if not self.campPetHeroList[_camp] then
		return
	end

	local hero = self.campPetHeroList[_camp]
	-- 通知战场移除英雄
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVEHERO, hero.heroId)
	-- 销毁英雄实例
	hero:Destroy()
	-- 清除列表
	self.campPetHeroList[_camp] = false
end

function BattleManager:AddBattleGhostHero( _battleHero )
	if not _battleHero then
		return
	end
	table.insert(self.campGhostHeroList[_battleHero.heroCamp], _battleHero)
end

function BattleManager:RemoveBattleCampGhostHero( _camp, ... )
	if #self.campGhostHeroList[_camp] == 0 then
		return
	end

	local campGhostHeroList = self.campGhostHeroList[_camp]
	local campGhostHeroNum = #campGhostHeroList
	for i = campGhostHeroNum, 1, -1 do
		local hero = campGhostHeroList[i]
		-- 通知战场移除英雄
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVEHERO, hero.heroId)
		-- 销毁英雄实例
		hero:Destroy()
	end
	self.campGhostHeroList[_camp] = {}
end

-- 添加英雄
function BattleManager:AddBattleHero( heroData, heroCamp, _extraHeroTalents, _haloLevel, _petLevel, _isTalenHero, _sendGBCommand, ... )
	if not heroData or not heroData.typeId or heroData.typeId == 0 or heroData.hpPercent == 0 then
		return false
	end
	
	local heroId = self:GenerateHeroId()
	local battleHero = BattleHero(heroId)
	if not battleHero:InitHero(heroData, heroCamp, _extraHeroTalents, _haloLevel, _petLevel, _isTalenHero) then
		return false
	end

	if not _extraHeroTalents and (not _haloLevel or _haloLevel == 0) and (not _petLevel or _petLevel == 0) then
		-- 添加到英雄列表和阵营英雄列表
		self.heroList[heroId] = battleHero
		table.insert(self.campHeroList[heroCamp], battleHero)

		-- 添加到死亡即失败英雄列表
		if self.battleFieldRes.raceLose ~= RaceType.ALL and battleHero.heroRes.race == self.battleFieldRes.raceLose then
			if not self.campDieLoseHeroList[heroCamp] then
				self.campDieLoseHeroList[heroCamp] = {}
			end
			table.insert(self.campDieLoseHeroList[heroCamp], battleHero)
		end

		-- 添加到统计
		local teamIndex = self.campTeamIndex[heroCamp]
		table.insert(self.battleResult.campTeamStat[heroCamp].teamStat[teamIndex].battleHeroList, battleHero.heroId)
		
		-- 通知表现层添加英雄
		local sendGBCommand = NilDefault(_sendGBCommand, true)
		if sendGBCommand then
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDHERO, heroId)
		end
	end

	return battleHero
end

-- 通知表现层添加所有英雄
function BattleManager:NotifyGBCommandAddAllHero( ... )
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			-- 通知表现层添加英雄
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDHERO, haloHero.heroId)
		end
		local petHero = self.campPetHeroList[i]
		if petHero then
			-- 通知表现层添加英雄
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDHERO, petHero.heroId)
		end
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			-- 通知表现层添加英雄
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.ADDHERO, heroList[n].heroId)
		end
	end
end

-- 初始化英雄数据
function BattleManager:InitAllHeroData( ... )
	-- 预初始化英雄
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		-- 天赋英雄
		local talentHero = self.campTalentHeroList[i]
		if talentHero then
			talentHero:PreInitHero()
		end
		-- 羁绊英雄
		local fetterHero = self.campFetterHeroList[i]
		if fetterHero then
			fetterHero:PreInitHero()
		end
		-- 光环英雄
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			haloHero:PreInitHero()
		end
		-- 宠物英雄
		local petHero = self.campPetHeroList[i]
		if petHero then
			petHero:PreInitHero()
		end
		-- 阵营英雄
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			heroList[n]:PreInitHero()
		end
	end

	-- 初始化英雄
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		-- 天赋英雄
		local talentHero = self.campTalentHeroList[i]
		if talentHero then
			talentHero:InitHeroData()
		end
		-- 羁绊英雄
		local fetterHero = self.campFetterHeroList[i]
		if fetterHero then
			fetterHero:InitHeroData()
		end
		-- 光环英雄
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			haloHero:InitHeroData()
		end
		-- 宠物英雄
		local petHero = self.campPetHeroList[i]
		if petHero then
			petHero:InitHeroData()
		end
		-- 阵营英雄
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			heroList[n]:InitHeroData()
		end
	end

	-- 打印Log
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			local battleHero = heroList[n]
			gBattleManager:AddBattleLog(string.format('InitHero ID[%d] Camp[%d] Team[%d] ResId[%d] Pos[%s] Level[%d] JieJi[%d] HP[%.0f] Attack[%.0f] Defence[%.0f] Speed[%.0f]', battleHero.heroId, battleHero.heroCamp, battleHero.teamIndex, battleHero.heroRes.heroId, battleHero.heroPosRes.id, battleHero.heroData.level, battleHero.heroData.jieLevel, battleHero.heroData.maxHP, battleHero:GetAttack(), battleHero:GetDefence(), battleHero.heroData.speed))
		end
	end
end

-- 检查是否所有英雄都准备好
function BattleManager:CheckAllHeroReady( ... )
	local hasLoadingHero = false
	local isPetReady = true
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			if haloHero.loadingState == 0 then
				return 0
			end
			if haloHero.loadingState == 1 then
				hasLoadingHero = true
			end
		end
		local petHero = self.campPetHeroList[i]
		if petHero then
			if petHero.loadingState == 0 then
				return 0
			end
			if petHero.loadingState == 1 then
				hasLoadingHero = true
			end
			if petHero.loadingState ~= 2 then
				isPetReady = false
			end
		end
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			if heroList[n].loadingState == 0 then
				return 0
			end
			if heroList[n].loadingState == 1 then
				hasLoadingHero = true
			end
		end
	end
	return hasLoadingHero and 1 or (isPetReady and 2 or 3)
end

-- 所有英雄
function BattleManager:GetBattleHeroList( ... )
	return self.heroList
end

-- 通过ID拿到英雄
function BattleManager:GetBattleHero( heroId, ... )
	local battleHero = self.heroList[heroId]
	if battleHero then
		return battleHero
	end

	for i = BattleCampType.CAMP_A, BattleCampType.MAX -1 do
		local haloHero = self.campHaloHeroList[i]
		if haloHero and haloHero.heroId == heroId then
			return haloHero
		end
		local petHero = self.campPetHeroList[i]
		if petHero and petHero.heroId == heroId then
			return petHero
		end
	end

	return false
end

-- 阵营指定位置英雄
function BattleManager:GetCampPosHero( battleCamp, posId, ... )
	local heroList = self.campHeroList[battleCamp]
	if not heroList or #heroList == 0 then
		return false
	end
	
	local heroNum = #heroList
	for i = 1, heroNum do
		if heroList[i].heroPosRes.posId == posId then
			return heroList[i]
		end
	end
	
	return false
end

-- 阵营指定站位英雄
function BattleManager:GetCampPosTypeHero( battleCamp, posType, _count, ... )
	local heroList = self.campHeroList[battleCamp]
	if not heroList or #heroList == 0 then
		return false
	end

	local posTypeHeroList = {}
	for i = 1, #heroList do
		if heroList[i].heroPosRes.posType == posType then
			table.insert(posTypeHeroList, heroList[i])
		end
	end

	local count = NilDefault(_count, 0)
	local heroNum = #posTypeHeroList
	if heroNum <= count or count == 0 then
		return posTypeHeroList
	end

	local targetHeroes = {}
	gBattleRandNum:ClearUniqueRecord(UniqueRandType.BATTLETARGET)
	for i = 1, count do
		local index = gBattleRandNum:NextUniqueInt(UniqueRandType.BATTLETARGET, heroNum)
		table.insert(targetHeroes, posTypeHeroList[index])
	end
	return targetHeroes
end

-- 阵营英雄列表
function BattleManager:GetCampHeroList( battleCamp, ... )
	return self.campHeroList[battleCamp]
end

-- 阵营英雄列表按位置排序
function BattleManager:SortCampHeroList( battleCamp, ... )
	if battleCamp == nil then
		battleCamp = BattleCampType.ALL
	end
	
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		if battleCamp == BattleCampType.ALL or i == battleCamp then
			table.sort(self.campHeroList[i], function(leftHero, rightHero)
				return leftHero.heroPosRes.posId < rightHero.heroPosRes.posId
			end)
		end
	end
end

-- 阵营列表移除英雄
function BattleManager:RemoveCampHero( battleHero, ... )
	-- 英雄死亡或者鬼魂状态从阵营列表移除
	if not battleHero:HasHeroFlag(BattleHeroFlag.DEATH) and not battleHero:HasHeroFlag(BattleHeroFlag.GHOST) then
		return
	end
	
	-- 从列表中移除
	local campHeroList = self.campHeroList[battleHero.heroCamp]
	local campHeroNum = #campHeroList
	for i = campHeroNum, 1, -1 do
		if campHeroList[i].heroId == battleHero.heroId then
			table.remove(campHeroList, i)
			break
		end
	end

	local campDieLoseHeroList = self.campDieLoseHeroList[battleHero.heroCamp]
	if campDieLoseHeroList then
		for i = #campDieLoseHeroList, 1, -1 do
			if campDieLoseHeroList[i].heroId == battleHero.heroId then
				table.remove(campDieLoseHeroList, i)
				break
			end
		end
	end
end

-- 尝试寻找合体英雄
function BattleManager:TryFindComboHero( _battleHero, ... )
	if not _battleHero then
		return {}, false
	end
	local comboRes, isMainHero = GameResMgr.GetBattleComboResByHeroRes(_battleHero.heroRes)
	if not comboRes or not isMainHero then
		return {}, false
	end

	local comboSubHeroList = {}
	local comboSubHeroIdList = comboRes.subHeroList
	local campHeroList = self.campHeroList[_battleHero.heroCamp]
	local campHeroNum = #campHeroList
	for i = 1, #comboSubHeroIdList do
		local subHeroResId = comboSubHeroIdList[i]
		local subHeroId = -1
		for n = 1, campHeroNum do
			if campHeroList[n].heroRes.baseHeroId == subHeroResId and campHeroList[n]:CanAction() then
				subHeroId = campHeroList[n].heroId
		end
		end
		if subHeroId == -1 then
			return {}, false
		end
		table.insert(comboSubHeroList, subHeroId)
	end

	return comboSubHeroList, comboRes
end

-- 校验战斗是否结束
function BattleManager:CheckBattleEnd( ... )
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		if #self.campHeroList[i] == 0 then
			self:OnBattleEnd(BattleTarget.GetTargetCamp(i, BattleTargetType.ENEMY))
			return true
		end
		if self.campDieLoseHeroList[i] and #self.campDieLoseHeroList[i] == 0 then
			self:OnBattleEnd(BattleTarget.GetTargetCamp(i, BattleTargetType.ENEMY))
			return true
		end
	end
	return false
end

-- 生成英雄ID
function BattleManager:GenerateHeroId()
	self.heroIdGenerator = self.heroIdGenerator + 1
	return self.heroIdGenerator
end

-- 生成状态ID
function BattleManager:GenerateBufferId()
	self.bufferIdGenerator = self.bufferIdGenerator + 1
	return self.bufferIdGenerator
end

-- 开始战斗
function BattleManager:BeginBattle( ... )
	-- 所有单位数据初始化
	self:InitAllHeroData()

	-- 单场战斗统计
	self.curSingleResult = BattleSingleResult()
	table.insert(self.battleResult.singleResultList, self.curSingleResult)
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		self.curSingleResult.campStat[i] = BattleTeamStat()
		local campHeroList = self.campHeroList[i]
		for n = 1, #campHeroList do
			table.insert(self.curSingleResult.campStat[i].battleHeroList, campHeroList[n].heroId)
		end
	end

	-- 校验战斗有效
	if not self:CheckBattleValid() then
		return
	end

	-- 阵营英雄按位置排序
	self:SortCampHeroList()
	-- 开始回合
	self:NextRoundAction()
end

-- 校验战斗有效
function BattleManager:CheckBattleValid( ... )
	-- 校验是否有空阵营
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		if #self.campHeroList[i] == 0 then
			self:OnBattleEnd(BattleTarget.GetTargetCamp(i, BattleTargetType.ENEMY))
			return false
		end
	end

	return true
end

-- 战斗结束
function BattleManager:OnBattleEnd( _winCamp, _isMaxRound, ... )
	-- 单队战斗结束
	self:OnSingleBattleEnd(_winCamp, _isMaxRound)
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.SINGLEBATTLEEND)

	local isBattleEnd = false
	-- 判定是否提前结束战斗 - 根据胜利场次
	if self.battleFieldRes.battleEndWinTimes > 0 then
		for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
			if self.battleResult.campWinStat[i] >= self.battleFieldRes.battleEndWinTimes then
				isBattleEnd = true
				break
			end
		end
	end
	-- -- 英灵塔战斗失败一场直接结束
	-- if self.battleFieldRes.id == BattleType.SOULTOWER then
	-- 	if self.battleResult.campWinStat[BattleCampType.CAMP_B] >= self.battleFieldRes.battleEndLoseTimes then
	-- 		isBattleEnd = true
	-- 	end
	-- end
	-- 常规校验
	if not isBattleEnd then
		for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
			if _winCamp ~= i then
				if self.campTeamIndex[i] >= #self.battleCampData[i].teamList then
					isBattleEnd = true
					break
				end
			end
		end
	end

	-- 战斗结束
	if isBattleEnd then
		-- 战斗日志结束
		self:AddBattleLog('log_end', true)
		-- 最终战斗结果
		self.battleResult.finalWinCamp = _winCamp
		self.battleResult.finalRandNum = gBattleRandNum:NextInt()
		self.battleResult.roundNum = self.roundNum

		-- 通知表现层战斗结束
		BattleMain.INSTANCE():SendGBCommand(GBCommandType.BATTLEEND)
		return
	end

	-- 重置战斗数据
	self.roundActionList = {}
	self.extraActionList = {}
	self.roundActionOrder = {}
	self.realActionHero = false
	self.lastActionHero = false

	if self.isWheelBattle == 1 then
		-- 进攻方死亡
		local loseCamp = BattleTarget.GetTargetCamp(_winCamp, BattleTargetType.ENEMY)
		local loseCampHeroList = self.campHeroList[loseCamp]
		local loseCampHeroNum = #loseCampHeroList
		for i = loseCampHeroNum, 1, -1 do
			local hero = loseCampHeroList[i]
			-- 通知战场移除英雄
			BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVEHERO, hero.heroId)
			-- 销毁英雄实例
			hero:Destroy()
		end

		-- 移除失败方的鬼魂
		self:RemoveBattleCampGhostHero(loseCamp)

		-- 清除胜利方英雄身上的状态
		local winCampHeroList = self.campHeroList[_winCamp]
		local winCampHeroNum = #winCampHeroList
		for n = winCampHeroNum, 1, -1 do
			local hero = winCampHeroList[n]
			hero:ClearBufferOnBattleEnd()
		end

		-- 车轮战
		local _loseCamp = BattleTarget.GetTargetCamp(_winCamp, BattleTargetType.ENEMY)
		self.campTeamIndex[_loseCamp] = self.campTeamIndex[_loseCamp] + 1
		self.campDieLoseHeroList[_loseCamp] = false
		-- 失败阵营初始化下一队
		self:InitBattleTeam(_loseCamp, true)
	else
		-- 常规战斗，先移除存活队伍
		for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
			local campHeroList = self.campHeroList[i]
			local campHeroNum = #campHeroList
			for n = campHeroNum, 1, -1 do
				local hero = campHeroList[n]
				-- 通知战场移除英雄
				BattleMain.INSTANCE():SendGBCommand(GBCommandType.REMOVEHERO, hero.heroId)
				-- 销毁英雄实例
				hero:Destroy()
			end
		end

		-- 移除双方的鬼魂
		self:RemoveBattleCampGhostHero(BattleCampType.CAMP_A)
		self:RemoveBattleCampGhostHero(BattleCampType.CAMP_B)

		-- 接着两队队伍索引都+1，并创建
		for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
			self.campTeamIndex[i] = self.campTeamIndex[i] + 1
			self.campDieLoseHeroList[i] = false
			self:InitBattleTeam(i, i == BattleCampType.CAMP_B)
		end
	end

	-- 服务器模式下，开始下一场战斗
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.BEGINBATTLE)
end

-- 当场战斗结束
function BattleManager:OnSingleBattleEnd( _winCamp, _isMaxRound, ... )
	-- 单场战斗结束
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		-- 天赋英雄
		local talentHero = self.campTalentHeroList[i]
		if talentHero then
			local triggerParam = TriggerParam(nil, nil, talentHero)
			gBattleTrigger:FireTrigger(BattleTriggerType.BATTLEEND, triggerParam, true)
		end
		-- 羁绊英雄
		local fetterHero = self.campFetterHeroList[i]
		if fetterHero then
			local triggerParam = TriggerParam(nil, nil, fetterHero)
			gBattleTrigger:FireTrigger(BattleTriggerType.BATTLEEND, triggerParam, true)
		end
		-- 光环英雄
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			local triggerParam = TriggerParam(nil, nil, haloHero)
			gBattleTrigger:FireTrigger(BattleTriggerType.BATTLEEND, triggerParam, true)
		end
		-- 宠物英雄
		local petHero = self.campPetHeroList[i]
		if petHero then
			local triggerParam = TriggerParam(nil, nil, petHero)
			gBattleTrigger:FireTrigger(BattleTriggerType.BATTLEEND, triggerParam, true)
		end
		-- 阵营英雄
		local heroList = self.campHeroList[i]
		for n = 1, #heroList do
			local triggerParam = TriggerParam(nil, nil, heroList[n])
			gBattleTrigger:FireTrigger(BattleTriggerType.BATTLEEND, triggerParam, true)
		end
	end

	-- 单场战斗统计
	local singleResult = self.battleResult.singleResultList[#self.battleResult.singleResultList]
	if singleResult then
		-- 日志
		-- singleResult.battleLog = table.concat(singleResult.battleLogList)
		-- 胜利方
		singleResult.winCamp = _winCamp
		-- 胜利方胜利场次+1
		self.battleResult.campWinStat[_winCamp] = self.battleResult.campWinStat[_winCamp] + 1
		-- 15轮
		if _isMaxRound then
			singleResult.maxRound = true
		else
			singleResult.maxRound = false
		end
		-- 记录最终战斗随机数
		singleResult.finalRandNum = gBattleRandNum:NextInt()
		-- 统计阵营英雄血量和总输出
		for i = BattleCampType.ALL + 1, BattleCampType.MAX - 1 do
			local campStat = singleResult.campStat[i]
			campStat.totalDamage = 0
			campStat.hpPercentMap = {}
			for n = 1, #campStat.battleHeroList do
				local battleHero = self:GetBattleHero(campStat.battleHeroList[n])
				campStat.hpPercentMap[battleHero.tHeroData.battlePos] = ToInt(battleHero:HasHeroFlag(BattleHeroFlag.GHOST) and 0 or battleHero.heroData.curHPPercent)
				campStat.totalDamage = ToInt(campStat.totalDamage + battleHero.totalAttackDamage)
			end
		end
		self:AddBattleLog('Battle End WinCamp[' .. singleResult.winCamp .. '] RandNum[' .. singleResult.finalRandNum .. ']')
	end

	-- 阵营统计
	for i = BattleCampType.ALL + 1, BattleCampType.MAX - 1 do
		local teamIndex = self.campTeamIndex[i]
		local teamStat = self.battleResult.campTeamStat[i].teamStat[teamIndex]
		if teamStat then
			teamStat.hpPercentMap = {}
			for n = 1, #teamStat.battleHeroList do
				local battleHero = self:GetBattleHero(teamStat.battleHeroList[n])
				teamStat.hpPercentMap[battleHero.tHeroData.battlePos] = ToInt(battleHero:HasHeroFlag(BattleHeroFlag.GHOST) and 0 or battleHero.heroData.curHPPercent)
				teamStat.totalDamage = ToInt(teamStat.totalDamage + battleHero.totalAttackDamage)
			end
		end
	end
end

-- 战斗是否结束
function BattleManager:IsBattleEnd( ... )
	return self.curSingleResult.winCamp ~= 0
end

-- 初始化回合行动初始队列顺序
function BattleManager:RefreshRoundActionOrder( ... )
	self.roundActionOrder = {}
	
	-- 遍历英雄列表插入到行动队列
	for k,v in pairs(self.heroList) do
		local battleHero = v
		if v.teamIndex == self.campTeamIndex[v.heroCamp] then
			table.insert(self.roundActionOrder, battleHero)
		end
	end
	
	table.sort(self.roundActionOrder, function(leftHero, rightHero)
		-- 速度大的优先出手
		local leftSpeed = leftHero:GetSpeed()
		local rightSpeed = rightHero:GetSpeed()
		if leftSpeed ~= rightSpeed then
			return leftSpeed > rightSpeed
		end

		-- 同等速度，位置ID小的优先(即越靠前靠下的优先)
		if leftHero.heroPosRes.posId ~= rightHero.heroPosRes.posId then
			return leftHero.heroPosRes.posId < rightHero.heroPosRes.posId
		end
		
		-- 同等速度，同等位置，英雄随机数小的优先
		return leftHero.randNum < rightHero.randNum		
	end)

	-- 最后一个行动的英雄
	self.lastActionHero = self.roundActionOrder[#self.roundActionOrder]
end

-- 开始下一回合
function BattleManager:NextRound( ... )
	-- 只有回合行动队列为空，才可以开始新的回合
	if #self.roundActionList ~= 0 or #self.extraActionList ~= 0 then
		return true, false
	end

	-- 回合结束
	if not self.isRoundEndTriggered then
		self.isRoundEndTriggered = true
		for k,v in ipairs(self.roundActionOrder) do
			-- 触发回合结束
			local triggerParam = TriggerParam(nil, nil, v, nil, nil, nil, nil, self.roundNum)
			gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDEND, triggerParam, true)
		end

		-- 天赋英雄触发回合结束
		for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
			-- 天赋英雄
			local talentHero = self.campTalentHeroList[i]
			if talentHero then
				local triggerParam = TriggerParam(nil, nil, talentHero, nil, nil, nil, nil, self.roundNum)
				gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDEND, triggerParam, true)
			end
			-- 羁绊英雄
			local fetterHero = self.campFetterHeroList[i]
			if fetterHero then
				local triggerParam = TriggerParam(nil, nil, fetterHero, nil, nil, nil, nil, self.roundNum)
				gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDEND, triggerParam, true)
			end
			-- 光环英雄
			local haloHero = self.campHaloHeroList[i]
			if haloHero then
				local triggerParam = TriggerParam(nil, nil, haloHero, nil, nil, nil, nil, self.roundNum)
				gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDEND, triggerParam, true)
			end
			-- 宠物英雄
			local petHero = self.campPetHeroList[i]
			if petHero and self.roundNum > 0 then
				local triggerParam = TriggerParam(nil, nil, petHero, nil, nil, nil, nil, self.roundNum)
				gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDEND, triggerParam, true)
			end
		end

		if #self.roundActionList ~= 0 or #self.extraActionList ~= 0 then
			return true, false
		end
	end

	-- 回合数加1
	self.roundNum = self.roundNum + 1
	self.isRoundEndTriggered = false
	
	-- 到达最大回合数，直接判定防守方成功
	if self.roundNum > self.maxRound then
		-- 战斗结束
		self:OnBattleEnd(self.battleFieldRes.roundMaxLose == 0 and BattleCampType.CAMP_A or BattleCampType.CAMP_B, true)
		return false, false
	end
	
	-- 通知表现层回合数加1
	BattleMain.INSTANCE():SendGBCommand(GBCommandType.ROUND, self.roundNum)
	BattleSpecialLogic.OnBattleRoundChange(self.roundNum)

	-- 刷新行动队列顺序
	self:RefreshRoundActionOrder()

	-- 天赋英雄触发回合开始
	for i = BattleCampType.CAMP_A, BattleCampType.MAX - 1 do
		-- 天赋英雄
		local talentHero = self.campTalentHeroList[i]
		if talentHero then
			local triggerParam = TriggerParam(nil, nil, talentHero, nil, nil, nil, nil, self.roundNum)
			gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDSTART, triggerParam, true)
		end
		-- 羁绊英雄
		local fetterHero = self.campFetterHeroList[i]
		if fetterHero then
			local triggerParam = TriggerParam(nil, nil, fetterHero, nil, nil, nil, nil, self.roundNum)
			gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDSTART, triggerParam, true)
		end
		-- 光环英雄
		local haloHero = self.campHaloHeroList[i]
		if haloHero then
			local triggerParam = TriggerParam(nil, nil, haloHero, nil, nil, nil, nil, self.roundNum)
			gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDSTART, triggerParam, true)
		end
		-- 宠物英雄
		local petHero = self.campPetHeroList[i]
		if petHero then
			local triggerParam = TriggerParam(nil, nil, petHero, nil, nil, nil, nil, self.roundNum)
			gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDSTART, triggerParam, true)
		end
	end

	-- 遍历英雄列表插入到行动队列
	local actionLog = 'Round[' .. self.roundNum .. ']'
	for k,v in ipairs(self.roundActionOrder) do
		local battleHero = v
		local battleAction = BattleAction(battleHero)
		table.insert(self.roundActionList, battleAction)

		-- 触发回合开始
		local triggerParam = TriggerParam(nil, nil, battleHero, nil, nil, nil, nil, self.roundNum)
		gBattleTrigger:FireTrigger(BattleTriggerType.ROUNDSTART, triggerParam, true)

		actionLog = actionLog .. string.format(" [%d-%d-%d]", battleHero.heroId, battleHero.heroRes.heroId, battleHero.heroPosRes.posId)
	end
	
	self:AddBattleLog(actionLog)

	return true, true
end

-- 开始回合下一次行动
function BattleManager:NextRoundAction( ... )
	-- 校验战斗是否结束
	if self:CheckBattleEnd() then
		return
	end

	if #self.roundActionList == 0 then
		-- 先插入额外行动队列
		if #self.extraActionList ~= 0 then
			for i = #self.extraActionList, 1, -1 do
				table.insert(self.roundActionList, 1, self.extraActionList[i])
			end
			self.extraActionList = {}
		end
	end

	-- 检查开始下一回合
	local isRoundValid, isNewRound = self:NextRound()
	if not isRoundValid then
		return
	end

	-- 先插入额外行动队列
	if #self.extraActionList ~= 0 then
		for i = #self.extraActionList, 1, -1 do
			table.insert(self.roundActionList, 1, self.extraActionList[i])
		end
		self.extraActionList = {}
	end

	-- 新回合
	if isNewRound then
		-- 其他英雄行动
		for i = BattleCampType.MAX - 1, BattleCampType.CAMP_A, -1 do
			-- 天赋英雄
			local talentHero = self.campTalentHeroList[i]
			if talentHero then
				table.insert(self.roundActionList, 1, BattleAction(talentHero))
			end
			-- 光环英雄
			local haloHero = self.campHaloHeroList[i]
			if haloHero then
				table.insert(self.roundActionList, 1, BattleAction(haloHero))
			end
			-- 宠物英雄
			local petHero = self.campPetHeroList[i]
			if petHero then
				table.insert(self.roundActionList, 1, BattleAction(petHero))
			end
		end
	end

	-- 宠物英雄若满怒，立即行动
	for i = 1, BattleCampType.MAX - 1 do
		-- 宠物英雄
		local petHero = self.campPetHeroList[i]
		if petHero and petHero:IsHeroFuryFull() then
			table.insert(self.roundActionList, 1, BattleAction(petHero, false))
			break
		end
	end
	
	-- 从行动队列中取出下一次行动
	Global.gBattleAction = self.roundActionList[1]
	if not Global.gBattleAction then
		return
	end
	
	-- 从行动队列移除
	table.remove(self.roundActionList, 1)
	
	-- 英雄开始行动
	gBattleAction:ActionBegin()
end

-- 回合数
function BattleManager:GetRoundNum()
	return self.roundNum
end

-- 追加行动，可指定目标和普攻ID
function BattleManager:AddExtraAction( _battleHero, _actionAttackId, _targetHeroes, ... )
	-- 行动队列插入新行动
	local battleAction = BattleAction(_battleHero, false)
	battleAction:ForceSkillAndTarget(_actionAttackId, _targetHeroes)
	if gBattleAction.comboRes and gBattleAction.comboRes.skillId == _actionAttackId then
		battleAction.comboHeroIdList = gBattleAction.comboHeroIdList
		battleAction.comboRes = gBattleAction.comboRes
	end
	table.insert(self.extraActionList, battleAction)
	
	self:AddBattleLog(string.format('AddExtraAction Hero[%d-->%d] AttackId[%s]', _battleHero.heroId, _targetHeroes[1] and _targetHeroes[1].heroId or 0, _actionAttackId))
end

-- 全体属性加成 计算获得，不走AttrValueRes表
function BattleManager:GetAttriAddition( _camp, _attrType, ... )
	local campData = self.battleCampData[_camp]
	return NilDefault(campData.attriAdditions[_attrType], 0)
end
-- 全体属性加成 走AttrValueRes表
function BattleManager:GetExtraAttrs( _camp )
	local campData = self.battleCampData[_camp]
	return NilDefault(campData.extraAttrs, {})
end

-- 是否PVP战斗
function BattleManager:IsPVPBattle( ... )
	return self.isPvpBattle
end

-- 刷新所有英雄的行动怒气
function BattleManager:RefreshAllHeroActionFury( ... )
	for heroId, battleHero in pairs(self.heroList) do
		if battleHero.teamIndex == self.campTeamIndex[battleHero.heroCamp] then
			battleHero:RefreshActionFury()
		end
	end
end

-- 添加战斗日志
function BattleManager:AddBattleLog( _log, _isSignal, ... )
	-- 打印日志
	if not _isSignal then
		_log = string.format('[BattleLog] %s', _log) 
		print(_log, ...)
	end

	if self.isLogEnable then
		if _isSignal then
			log(self.battleId, _log)
		else
			log(self.battleId, _log .. '\n')
		end
	end
	
	-- 记录到结果日志中
	-- _log = _log .. '\n'
	-- if self.curSingleResult then
	-- 	table.insert(self.curSingleResult.battleLogList, _log)
	-- end
end

classend()