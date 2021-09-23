---
--- class BattlePage
-- @classmod BattlePage
class('BattlePage', PageBase)

local table_insert = table.insert
local math_floor = math.floor

---Constructor
function BattlePage:ctor( page, ... )
	self.super = Super(page, ...)

	self.objDragTower = false			-- 拖动的塔物件
	self.dragTowerIndex = 0				-- 拖动的塔索引
	self.dragOriginPos = false 			-- 拖动的塔初始位置
	self.allCoveredTowerMap = {}		-- 所有遮盖的塔

	self.myGBPlayer = false 			-- 玩家自己
	self.myTowerList = {}				-- 玩家塔列表
	self.enemyGBPlayer = false

	self.battleType = BattleType.PK
	self.isGuiding = false
	self.nextBossId = false
	self.myTowerBlockMap = {}

	self.battleRes = false				-- 战斗配置
end

function BattlePage:OnPageDestroy( ... )

end

function BattlePage:Init( ... )
	-- 自定义事件
	self.customEvents = {
		-- 投降
		['Surrender'] = function( ... )
			gGameDialog:ShowMessage(nil, GAMETEXT('AskSurrender'), nil, nil, function( ... )
				gGBMain:ExecSurrender()
			end)
			return true
		end,
		-- 抽卡
		['Roll'] = function( ... )
			local success = gGBMain:ExecRoll()
			if success then
				-- 抽卡引导
				if self.isGuiding and gGuideMgr:IsRollGuiding() then
					gGuideMgr:CheckCodeNextGuide(GuideManager.GPARAM_ROLL)
				end
			end
			return success
		end,
		-- 阻塞服务端指令
		['BlockServer'] = function( ... )
			return GBMain.BlockServerCommand(true)
		end,
		-- 解除阻塞服务端指令
		['UnBlockServer'] = function( ... )
			return GBMain.BlockServerCommand(false)
		end,
		-- 升级
		['Upgrade'] = function( _index, ... )
			return gGBMain:ExecUpgrade(tonumber(_index))
		end,
		-- 英雄天赋
		['ClickHero'] = function( ... )
			return gGBMain:ExecHeroTalent()
		end,
		['Clean'] = function( ... )
			GameObjectPool.AutoClean(false)
			gGameClient:StartGC()
		end,
		-- 回城
		['ClickHome'] = function( ... )
			-- 同房间服断开连接
			gGameNetMgr:DisConnect(NetSessionType.ROOM)
			gGameClient:JumpToScene('Home')
		end,
		-- 入场动画结束
		['BattleEnterComplete'] = function( ... )
			gGBMain:BeginBattle(BattleBeginFlag.ANIMATION)
		end,
		-- 表情
		['ClickEmoji'] = function( _index, ... )
			gGBMain:ExecEmoji(_index)
		end,
		-- 点击敌人队伍
		['ClickEnemyTeam'] = function( _index, ... )
			self:OnClickEnemyTeam(tonumber(_index))
		end,
		-- 点击Boss
		['ClickBoss'] = function( ... )
			self:OnClickBoss()
		end
	}
	-- 页面刷新事件
	self.refreshEvents = {
		['UpdatePoint'] = function( self, _data, ... )
			self:UpdatePoint(_data.point, _data.costPoint)
		end,
		['Upgrade'] = function( self, _data, ... )
			self:UpdateTowerGrade(_data.gbPlayer.player, _data.poolIndex)
		end,
		['RefreshHeroTalentCDTime'] = function( self, _data, ... )
			self:RefreshHeroTalentCDTime(_data.playerId, _data.pastTime, _data.leftTime)
		end,
		['RoundStart'] = function( self, _data, ... )
			self:OnRoundStart(_data.duration, _data.roundNum, _data.bossIndex, _data.nextBossId, _data.roundType)
		end,
		['UpdatePlayerHP'] = function( self, _data, ... )
			self:UpdatePlayerHP(_data.playerId, _data.curHP, _data.maxHP, _data.isInit)
		end,
		['OnBossEnter'] = function( self, _data, ... )
			self:OnBossEnter(_data.param1)
		end,
		['UnBlock'] = function( self, _data, ... )
			-- 引导战斗关闭屏蔽
			ObjectCache.SetActive(UIName.BattleBlock, false)
		end,
		['UpdatePlayerParam'] = function( self, _data,... )
			self:UpdatePlayerParam(_data.playerId, _data.paramType, _data.paramValue)
		end,
		['RandomBoss'] = function( self, ... )
			self:OnBossRandom(gamebattle.gBattleLogic.bossIndex)
		end,
		['UpdateTowerStar'] = function( self, _data, ... )
			self:UpdateTowerStar(_data.playerId, _data.poolIndex, _data.totalStar)
		end,
		['PlayerEmoji'] = function( self, _data, ... )
			self:OnPlayerEmoji(_data.playerId, _data.index)
		end,
		['RefreshTowerPress'] = function( self, _data, ... )
			self:RefreshTowerPress()
		end
	}
end

function BattlePage:OnGetUIGroup( _groupPath, ... )

end

function BattlePage:OnUIGroupInit( _groupPath, _luaUIGroup, ... )

end

function BattlePage:InitOBRegister( ... )

end

function BattlePage:OnShow( _data, ... )
	-- 关闭战斗匹配界面
	ObjectCache.HidePage(EncodeUIName(UIName.BattleMatch, 1), true)

	self.nextBossId = false
	self.objDragTower = false
	self.dragTowerIndex = 0
	self.dragOriginPos = false
	self.allCoveredTowerMap = {}

	self.myGBPlayer = false
	self.enemyGBPlayer = false

	-- 初始界面状态
	local battleRecord = gUIDataMgr.battleData:BuildBattleRecord()
	if battleRecord then
		UIUtils.SelectActionSelector(self, battleRecord.battleType == BattleType.COOP and 'OnShowCoop' or 'OnShowPk')
	end

	-- 初始化战斗
	self:InitBattle()

	UIUtils.SelectActionSelector(self, gamebattle.gBattleRecord.isLocal and 'OnShowLocal' or 'OnShowNotLocal')
	UIUtils.SelectActionSelector(self, gamebattle.gBattleRecord.isVideo and 'OnShowVideo' or 'OnShowNotVideo')
	UIUtils.SelectActionSelector(self, gamebattle.gBattleRecord.isRealTime and 'OnShowRealTime' or 'OnShowNotRealTime')

	-- 引导战斗开始屏蔽
	ObjectCache.SetActive(UIName.BattleBlock, self.isGuiding)
	if self.isGuiding then
		OCUtils.SetActive(UIName.BattleSurrender, 0, false)
	end

	if self.myGBPlayer and self.enemyGBPlayer then
		-- 刷新
		self:UpdateTowerGrade(self.myGBPlayer.player, nil, true)
		self:UpdateTowerGrade(self.enemyGBPlayer.player, nil, true)
		self:UpdateHeroTalent(self.myGBPlayer.player)
		self:UpdateHeroTalent(self.enemyGBPlayer.player)
		self:UpdateEnemyInfo(self.enemyGBPlayer.player)
	end
end

function BattlePage:OnHideBegin( ... )
	-- 销毁战斗
	self:DestroyBattle()

	self.objDragTower = false
	self.dragTowerIndex = 0
	self.dragOriginPos = false
	self.allCoveredTowerMap = {}

	self.myGBPlayer = false
	self.enemyGBPlayer = false
end

function BattlePage:OnHide( ... )
	if not GBMain.IsDestroyed() then
		-- 销毁战斗
		self:DestroyBattle()

		self.objDragTower = false
		self.dragTowerIndex = 0
		self.dragOriginPos = false
		self.allCoveredTowerMap = {}

		self.myGBPlayer = false
		self.enemyGBPlayer = false
	end
end

function BattlePage:InitBattle( ... )
	if gUIDataMgr.isFirstEnterHome then
		return
	end

	-- 战斗进场数据
	local battleRecord = gUIDataMgr.battleData:BuildBattleRecord()
	if not battleRecord then
		return
	end

	self.battleType = battleRecord.battleType
	self.isGuiding = battleRecord.battleId == 'guide'
	self.battleRes = GameResMgr.GetBattleRes(self.battleType)

	local uBattleField = ObjectCache.GetComponent(UIName.BattleField, 0, UBattleField)
	if not uBattleField then
		return
	end

	local uBattle = uBattleField:SwitchBattle(self.battleRes.fieldType - 1)
	local myPlayerId = battleRecord.isVideo and battleRecord.playerList[1].playerId or gUIDataMgr:GetUserId()
	GBMain.INSTANCE():Initialize(myPlayerId, battleRecord, uBattle)

	-- 注册格子事件
	local uMyPlayer = uBattle:GetUBattlePlayer(0)
	local allGrids = uMyPlayer.canvasGridList
	for i = 1, allGrids.Count do
		local towerIndex = i
		local objDrag = allGrids[i - 1].objDrager
		UIUtils.SetObjectPressCallBack(objDrag, nil, function( ... )
			self:OnTowerPressDown(towerIndex)
		end, function( ... )
			self:OnTowerPressUp(towerIndex)
		end)

		UIUtils.AddObjectDragEvent(objDrag, function( _pointEvent )
			self:OnTowerDragBegin(towerIndex, _pointEvent)
		end, nil, function( _pointEvent )
			self:OnTowerDragEnd(towerIndex, _pointEvent, objDrag)
		end)
	end

	-- 注册敌人格子点击事件
	local uEnemyPlayer = uBattle:GetUBattlePlayer(1)
	local allEnemyGrids = uEnemyPlayer.canvasGridList
	for i = 1, allEnemyGrids.Count do
		local towerIndex = i
		local objDrag = allEnemyGrids[i - 1].objDrager
		UIUtils.SetObjectPressCallBack(objDrag, nil, nil, function( ... )
			self:OnClickEnemyTower(towerIndex)
		end)
	end

	self.myGBPlayer = gGBMain:GetMyGBPlayer()
	self.enemyGBPlayer = gGBMain:GetEnemyGBPlayer()
	self:InitPlayerParam(self.myGBPlayer.player)
	self:InitPlayerParam(self.enemyGBPlayer.player)

	-- 本地模式or录像or引导or快照or已经开始
	if battleRecord.isLocal or battleRecord.isVideo or gGBMain.isGuiding or battleRecord.tSnapShot or battleRecord.frameCount > 0 then
		gGBMain:BeginBattle(BattleBeginFlag.LOGIC)
	end
	-- 非录像且已经开始或者有快照
	if not battleRecord.isVideo and (battleRecord.tSnapShot or battleRecord.frameCount > 0) then
		-- 不播动画
		gGBMain:BeginBattle(BattleBeginFlag.ANIMATION)
	else
		-- 播入场动画
		self:ShowBattleEnter()
	end
end

function BattlePage:DestroyBattle( ... )
	if not gUIDataMgr.isFirstEnterHome then
		-- 战斗销毁
		GBMain.Destroy()
	end
end

function BattlePage:RefreshTowerPress( ... )
	local myGBPlayer = self.myGBPlayer
	local coverdTowerMap = self.allCoveredTowerMap
	local pressGBTower = myGBPlayer:GetGBTowerByPos(gGBField.pressTowerIndex)
	if not pressGBTower then
		gGBField.pressTowerIndex = 0
		for i = 1, BattleConstants.BATTLE_MAX_TOWER do
			local gbGrid = myGBPlayer:GetGBGrid(i)
			if coverdTowerMap[i] then
				if coverdTowerMap[i] == 'ShowCover' then
					gbGrid:ShowCover(false, GameStringType.OnHideCover)
				else
					gbGrid:ShowCover(false, GameStringType.HideMergeMark)
				end
				coverdTowerMap[i] = nil
			end
		end
		return
	end
	local towerIndex = pressGBTower.posIndex
	for i = 1, BattleConstants.BATTLE_MAX_TOWER do
		local gbGrid = myGBPlayer:GetGBGrid(i)
		if i ~= towerIndex then
			local gbTower = myGBPlayer:GetGBTowerByPos(i)
			if gbTower then
				local canMerge, mergeType = pressGBTower:CanMerge(gbTower)
				if not canMerge then
					if coverdTowerMap[i] ~= 'ShowCover' then
						gbGrid:ShowCover(true, GameStringType.OnShowCover)
						coverdTowerMap[i] = 'ShowCover'
					end
				else
					local markKey = 'ShowMark_' .. mergeType
					if coverdTowerMap[i] ~= markKey then
						coverdTowerMap[i] = markKey
						gbGrid:ShowCover(false, GameStringType.MergeMark_Merge + mergeType - 1)
					end
				end
			else
				if coverdTowerMap[i] then
					if coverdTowerMap[i] == 'ShowCover' then
						gbGrid:ShowCover(false, GameStringType.OnHideCover)
					else
						gbGrid:ShowCover(false, GameStringType.HideMergeMark)
					end
					coverdTowerMap[i] = nil
				end
			end
		end
	end
end

function BattlePage:OnTowerPressDown( _towerIndex, ... )
	local pressGBTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not pressGBTower then
		return
	end

	gGBField.pressTowerIndex = _towerIndex
	self:RefreshTowerPress()
end

function BattlePage:OnTowerPressUp( _towerIndex, ... )
	gGBField.pressTowerIndex = 0
	self:RefreshTowerPress()
end

function BattlePage:OnTowerDragBegin( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if self.objDragTower and self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		return
	end

	self.dragTowerIndex = _towerIndex
	self.objDragTower = _pointEvent.pointerDrag

	if dragTower.tower then
		-- UIUtils.SetChildText(self, 'canvas/pnl_debug/txt_tower', string.format('Tower [%d] [%d] 攻击[%d] 攻速[%d] 暴击[%d] 暴倍[%d]', dragTower.tower.towerId, dragTower.tower.unitId, dragTower.tower:GetAttack(), dragTower.tower:GetAtkSpeed(), dragTower.tower:GetAttribute(AttriType.CRITICAL), dragTower.tower:GetAttribute(AttriType.CRITICALSCALE)))
		local bufferList = dragTower.tower.carryBufferList
		local time = math.random(1, 100)
		for i = 1, #bufferList do
			local buffer = bufferList[i]
			for n = 1, #buffer.layerList do
				local layer = buffer.layerList[n]
				print(string.format('[%d] BufferLayer', time), dragTower.posIndex, dragTower.tower.unitId, buffer.bufferId, buffer.bufferRes.id, gameutils.JSON:encode(layer.valueList), layer.owner.unitId or 0)
			end
		end
	end
end

function BattlePage:OnTowerDragEnd( _towerIndex, _pointEvent, _objDrag, ... )
	-- 禁止同时拖动多个
	if not self.objDragTower or self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		self.objDragTower = false
		return
	end

	-- 找到目标塔位置
	local dragEndIndex = self.myGBPlayer:GetGridIndexByPosition(self.objDragTower.transform.position)
	if dragEndIndex == 0 then
		self.objDragTower = false
		return
	end

	local dragEndTower = self.myGBPlayer:GetGBTowerByPos(dragEndIndex)
	if not dragEndTower or not dragTower:CanMerge(dragEndTower) then
		-- 不能合成，飞回原地
		self.objDragTower = false
		return
	end

	-- 直接放回原地
	self.objDragTower = false

	-- 执行合成
	if gGBMain:ExecMerge(self.dragTowerIndex, dragEndIndex) then
		-- 合成引导
		if self.isGuiding and gGuideMgr:IsMergeGuiding() then
			gGuideMgr:CheckCodeNextGuide(GuideManager.GPARAM_MERGE)
			GOUtils.IgnoreDragEndRecover(_objDrag.gameObject)
		end
	end
end

function BattlePage:UpdatePoint( _point, _costPoint, ... )
	ObjectCache.SetText(UIName.BattlePoint, _point, 0)
	ObjectCache.SetText(UIName.BattleCostPoint, _costPoint, 0)

	-- 刷新塔升级遮罩
	if self.myGBPlayer then
		local myPlayer = self.myGBPlayer.player
		for i = 1, 5 do
			local cost = myPlayer:GetTowerUpgradeCostByPoolIndex(i)
			local showBlock = cost == 0 or not myPlayer:IsPointEnough(cost)
			if self.myTowerBlockMap[i] ~= showBlock then
				-- ObjectCache.PlayTween(EncodeUIName(UIName.BattleTowerItem_1 + i - 1, 8), showBlock and 'Show' or 'Hide', false, 0)
				ObjectCache.SelectActionSelector(UIName.BattleTowerItem_1 + i - 1, 10, showBlock and 'Cover_Grey' or 'Normal')
				self.myTowerBlockMap[i] = showBlock
			end
		end
	end
end

function BattlePage:UpdateTowerGrade( _player, _poolIndex, _isInit, ... )
	if not _poolIndex then
		for i = 1, 5 do
			self:UpdateTowerGrade(_player, i, _isInit)
		end
		return
	end
	local towerResId = _player:GetTowerResIdByPoolIndex(_poolIndex)
	local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
	if not towerRes then
		return
	end
	local isMine = self:IsMyPlayer(_player.playerId)
	local grade = _player:GetTowerGrade(towerResId)
	local cost = _player:GetTowerUpgradeCostByPoolIndex(_poolIndex)
	local _, awakenIndex = _player:GetTowerAwaken(towerResId)
	local uiName = isMine and UIName.BattleTowerItem_1 or UIName.BattleEnemyTowerItem_1
	uiName = uiName + _poolIndex - 1
	if _isInit then
		ObjectCache.SetImage(EncodeUIName(uiName, 2), PainterMgr.GetPathOfTowerIcon(towerRes.iconName, true), '.png', '', false)
		ObjectCache.SetImage(EncodeUIName(uiName, 1), PainterMgr.GetPathOfTowerBagQualityFrame(towerRes.quality, true), '.png', '', false)
		ObjectCache.SetMultiColorItem(EncodeUIName(uiName, 3), nil, towerRes.quality - 1)
	end
	ObjectCache.SetText(EncodeUIName(uiName, 4), cost == 0 and 'MAX' or tostring(grade))
	ObjectCache.SetActive(EncodeUIName(uiName, 5), cost ~= 0)
	ObjectCache.SetActive(uiName, 6, awakenIndex ~= 0)
	if isMine then
		ObjectCache.SetText(EncodeUIName(uiName, 7), tostring(cost))
		ObjectCache.SetActive(EncodeUIName(uiName, 11), cost ~= 0)
		local showBlock = _isInit or cost == 0 or not _player:IsPointEnough(cost)
		if self.myTowerBlockMap[_poolIndex] ~= showBlock then
			-- ObjectCache.PlayTween(EncodeUIName(uiName, 8), showBlock and 'Show' or 'Hide', false, 0)
			ObjectCache.SelectActionSelector(uiName, 10, showBlock and 'Cover_Grey' or 'Normal')
			self.myTowerBlockMap[_poolIndex] = showBlock
		end
	end
end

function BattlePage:RefreshHeroTalentCDTime( _playerId, _pastTime, _leftTime, ... )
	local startPercent = _leftTime / (_pastTime + _leftTime)
	local isMine = self:IsMyPlayer(_playerId)
	local uiName = isMine and UIName.BattleHeroMine or UIName.BattleHeroEnemy
	OCUtils.ImageValueTo(uiName, 2, startPercent, 0, _leftTime * 0.001, nil, false, gGBField.looper)
	if isMine then
		local duration = _leftTime * 0.001
		OCUtils.TextValueTo(uiName, 4, duration, 0, duration, 'MS', 0, nil, true, gGBField.looper)
	end
end                         

function BattlePage:UpdateHeroTalent( _player )
	local hero = _player.hero
	if not hero.heroRes then
		return
	end
	local isMine = self:IsMyPlayer(_player.playerId)
	local uiName = isMine and UIName.BattleHeroMine or UIName.BattleHeroEnemy
	if isMine then
		local heroTalentType = hero:GetHeroTalentType()
		ObjectCache.SetSelectable(EncodeUIName(uiName, 3), heroTalentType == BattleHeroTalentType.MANUAL and 1 or 0)
	end
	ObjectCache.SetImage(EncodeUIName(uiName, 1), GameResMgr.GetGamePatchFullPath('ui', 'image/icon/hero/' .. hero.heroRes.iconName), '.png', '', false)
	ObjectCache.SetActive(EncodeUIName(uiName, 2), hero.heroTalentRes.talentType ~= BattleHeroTalentType.TRIGGER)
end

function BattlePage:UpdateEnemyInfo( _player, ... )
	OCUtils.SetText(UIName.BattleEnemyPlayer, 1, _player.playerName)
	local rankRes = GameResMgr.GetPKRankRes(_player.playerLevel)
	if rankRes then
		OCUtils.SetText(UIName.BattleEnemyPlayer, 2, 'Lv.' .. rankRes.id)
		OCUtils.SetImage(UIName.BattleEnemyPlayer, 3, PainterMgr.GetPathOfPKRankIcon(rankRes.level))
	end
end

function BattlePage:IsMyPlayer( _playerId, ... )
	return gGBMain:IsMyPlayer(_playerId)
end

function BattlePage:OnRoundStart( _duration, _roundNum, _bossIndex, _nextBossId, _roundType, ... )
	_duration = _duration * 0.001
	OCUtils.TextValueTo(UIName.BattleBoss, 3, _duration, 0, _duration, 'MS', 0, nil, true, gGBField.looper)
	OCUtils.SetText(UIName.BattleBoss, 4, tostring(_roundNum))

	-- PVP随机boss
	if _bossIndex and not gamebattle.gBattleRecord.tSnapShot and not self.isGuiding then
		self:OnBossRandom(_bossIndex)
	end

	-- PVE下一个Boss
	if _nextBossId and self.nextBossId ~= _nextBossId then
		self.nextBossId = _nextBossId
		local bossRes = GameResMgr.GetBattleMonsterRes(_nextBossId)
		if bossRes then
			OCUtils.SetCanvasGroup(UIName.BattleBoss, 2, 1, -1, -1, -1)
			OCUtils.SetActive(UIName.BattleBoss, 1, true)
			OCUtils.SetImage(UIName.BattleBoss, 1, 'image/battlescene/' .. bossRes.iconName)
		end
	end

	-- 回合提示
	if _roundNum > 0 then
		if _roundType ~= BattleCoopRoundType.BOSS then
			OCUtils.SelectActionSelector(UIName.BattleAnimation, 1, 'Show_Round_Play')
			OCUtils.SetText(UIName.BattleAnimation, 2, tostring(_roundNum))
		end
		-- 上报回合数
		if _roundNum > 1 then
			gGBMain:ExecReport()
		end
	end

	-- 关闭战斗进场动画
	OCUtils.SelectActionSelector(UIName.BattleAnimation, 1, 'Hide_Battle_Enter')
end

function BattlePage:UpdatePlayerHP( _playerId, _curHP, _maxHP, _isInit, ... )
	local isMine = self:IsMyPlayer(_playerId)
	local uiName = isMine and UIName.BattleHeartMine or UIName.BattleHeartEnemy
	if _isInit then
		ObjectCache.SelectActionSelector(uiName, 'Init_' .. _maxHP)
	end
	_curHP = _curHP < 0 and 0 or (_curHP > _maxHP and _maxHP or _curHP)
	ObjectCache.SelectActionSelector(uiName, 'Heart_' .. _curHP)
end

function BattlePage:OnBossEnter( _bossResId, ... )
	OCUtils.SelectActionSelector(UIName.BattleAnimation, 1, 'Battle_Boss_Play')
	local bossRes = GameResMgr.GetBattleMonsterRes(_bossResId)
	if bossRes then
		ObjectCache.SetImage(UIName.BattleBossHead, GameResMgr.GetGamePatchFullPath('ui', 'image/battlescene/' .. bossRes.headName), '.png', '', false)
	end
end

function BattlePage:ShowBattleEnter( ... )
	OCUtils.SelectActionSelector(UIName.BattleAnimation, 1, self.battleType == BattleType.COOP and 'Battle_Enter_Coop' or 'Battle_Enter_PK')
	ObjectCache.SetText(EncodeUIName(UIName.BattleEnter, 1), self.myGBPlayer.player.playerName)
	ObjectCache.SetText(EncodeUIName(UIName.BattleEnter, 2), self.enemyGBPlayer.player.playerName)
end

function BattlePage:OnBossRandom( _bossIndex )
	OCUtils.SelectActionSelector(UIName.BattleAnimation, 1, 'Choice_Boss_Play_' .. _bossIndex)
	local bossResId = gamebattle.gBattleLogic:GetMonsterResId(MonsterType.BOSS, _bossIndex)
	local bossRes = GameResMgr.GetBattleMonsterRes(bossResId)
	if bossRes then
		self.nextBossId = bossResId
		OCUtils.SetActive(UIName.BattleBoss, 1, true)
		OCUtils.SetImage(UIName.BattleBoss, 1, 'image/battlescene/' .. bossRes.iconName)
	end
end

function BattlePage:InitPlayerParam( _player, ... )
	local paramMap = _player.paramMap
	local isMine = self:IsMyPlayer(_player.playerId)

	-- 击杀
	local uiName = isMine and UIName.MyKillScore or UIName.EnemyKillScore
	local hasKillScore = paramMap[BattleParamType.KILLSCORE] ~= nil
	OCUtils.SetActive(uiName, 1, hasKillScore)
	if hasKillScore then
		OCUtils.SetText(uiName, 2, '0')
		OCUtils.SetText(uiName, 3, '0')
	end
end

local PlayerParamSwitcher = {
	-- 击杀
	[BattleParamType.KILLSCORE] = function( self, _playerId, _paramValue, ... )
		local isMine = self:IsMyPlayer(_playerId)
		local uiName = isMine and UIName.MyKillScore or UIName.EnemyKillScore
		OCUtils.SetText(uiName, 2, tostring(_paramValue))
		OCUtils.SetText(uiName, 3, tostring(math_floor(_paramValue / 100)))
	end,
	-- 连击Combo
	[BattleParamType.COMBO] = function( self, _playerId, _paramValue, ... )
		local gbPlayer = gGBField:GetGBPlayer(_playerId)
		if gbPlayer then
			gbPlayer:UpdateParam(BattleParamType.COMBO, _paramValue)
		end
	end
}

function BattlePage:UpdatePlayerParam( _playerId, _paramType, _paramValue, ... )
	-- warn('UpdatePlayerParam', _playerId, _paramType, _paramValue)
	local switcher = PlayerParamSwitcher[_paramType]
	if switcher then
		switcher(self, _playerId, _paramValue)
	end
end

function BattlePage:UpdateTowerStar( _playerId, _poolIndex, _totalStar, ... )
	local isMine = self:IsMyPlayer(_playerId)
	if isMine then
		OCUtils.SetText(UIName.BattleTowerItem_1 + _poolIndex - 1, 9, tostring(_totalStar))
	end
end

function BattlePage:OnPlayerEmoji( _playerId, _index, ... )
	local isMine = self:IsMyPlayer(_playerId)
	local emojiID = _index or 1
	OCUtils.RefreshPoolContainer(UIName.BattleEmoji, isMine and 1 or 2, 'battle/battle_emoji/battle_emoji_' .. emojiID, 'Assets/Game/ui/other/prefabs/')
end

function BattlePage:OnClickEnemyTeam( _index, ... )
	if _index == 0 then
		local heroId = self.enemyGBPlayer.player.hero.heroRes.id
		TipsBattleUnitPage.OpenPageByHero(heroId)
		return
	end
	local towerId = self.enemyGBPlayer.player:GetTowerResIdByPoolIndex(_index)
	TipsBattleUnitPage.OpenPageByTower(towerId)
end

function BattlePage:OnClickBoss( ... )
	TipsBattleUnitPage.OpenPageByBoss(self.nextBossId)
end

function BattlePage:OnClickEnemyTower( _index )
	local gbTower = self.enemyGBPlayer:GetGBTowerByPos(_index)
	if not gbTower then
		return
	end
	TipsBattleUnitPage.OpenPageByTower(gbTower.towerRes.id)
end

classend()