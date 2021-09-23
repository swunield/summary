class('BattleSettlePKGroup', GroupBase)  -- 战斗结算 - 挑战

---- 构造
function BattleSettlePKGroup:ctor( ... )
	self.super = Super(...)
	self.isMyWin      = false  -- 是否我方胜利
	self.isSuccess    = false  -- 是否结算成功
	self.isGuiding    = false  -- 是否引导战斗
	self.isManual     = false  -- 是否玩家创建房间
	self.myWinStreak  = false  -- 我方连胜次数
	self.afterADScale = false  -- 战斗后广告奖励加成倍数
	self.goldCounts   = false  -- 金币数量表
	self.scoreCounts  = false  -- 积分数量表
end

---- 初始化
function BattleSettlePKGroup:Init( ... )
	-- 自定义事件
	self.customEvents =
	{
		-- 点击双方胜负的确定按钮
		['ClickPnlOK'] = function ( ... )
			-- 是否显示详情面板
			local showTips = false
			-- 引导时不显示
			if self.isGuiding then
				showTips = false
			-- 玩家创建房间时不显示
			elseif self.isManual then
				showTips = false
			-- 战斗失败时不显示
			elseif not self.isMyWin then
				showTips = false
			-- 结算失败时不显示
			elseif not self.isSuccess then
				showTips = false
			else
				showTips = true
			end
			-- 显示详情面板
			if showTips then
				-- 顺序敏感
				-- 更新我方胜利结算视图
				self:UpdateMyWinView()
				-- 执行ACTION
				local action = (self.myWinStreak < 2) and 'Show_Pnl_2_Putong' or 'Show_Pnl_2_Liansheng'
				UIUtils.SelectActionSelector(self,  action)
			-- 不显示详情面板直接返回主城
			else
				UIUtils.HidePage('battle_settle')
				gGameClient:JumpToScene('Home')
			end
			return false
		end,
		-- 点击胜利结算的确定按钮
		['ClickSettleOK'] = function ( ... )
			-- 返回主城
			UIUtils.HidePage('battle_settle')
			gGameClient:JumpToScene('Home')
			return false
		end,
		-- 点击广告奖励
		['ClickRewardAds'] = function( ... )
			if not self.afterADScale then
				warn('invalid self.afterADScale')
			end
			GameAds.Request(ExtraBonusType.PKWINBONUS,
				function( _data )
					self.afterADScale = 1
					UIUtils.SelectActionSelector(self, 'Show_Lizi_Gold')
					UIUtils.SetChildActive(self, 'pnl_2/pnl_btn/btn_ads', false)
					self:ShowWinScoreAndGoldChange(
						self.scoreCounts.showAdd1, self.scoreCounts.showAdd2,
						self.goldCounts.showAdd1, self.goldCounts.showAdd2
					)
				end
			)
			return false
		end,
		-- 显示奖励数字动画
		['ShowTotalScore'] = function ( ... )
			self:ShowWinScoreAndGoldChange(0, self.scoreCounts.showAdd1, 0, self.goldCounts.showAdd1)
			return false
		end,
	}
end

---- 更新
function BattleSettlePKGroup:InternalUpdateGroup( ... )
	local groupData = self.groupData
	if not groupData then
		warn('not self.groupData')
		return false
	end
	self.isMyWin      = groupData.isMyWin or false
	self.isSuccess    = groupData.isSuccess or false
	self.isGuiding    = groupData.isGuiding or false
	self.isManual     = groupData.isManual or false
	self.myWinStreak  = gUIDataMgr.profileData:GetPKWinStreak()
	self.afterADScale = groupData.afterADScale or 1
	self.scoreCounts, self.goldCounts = self:CalcWinScoreAndGoldCounts(groupData.watchBeforeAD)
	-- 我方, 结算失败时强制显示我方胜利
	local myWin = self.isMyWin or (not self.isSuccess)
	local myPnl = UIUtils.GetChild(self, 'pnl_1/pnl_mine')
	self:UpdatePlayerView(myPnl, gGBMain:GetMyPlayer(), myWin)
	if not myWin then
		self:UpdateMyLoseView(myPnl)
	end
	-- 敌方, 结算失败时强制显示敌方失败
	local enemyWin = (not self.isMyWin) and self.isSuccess
	local enemyPnl = UIUtils.GetChild(self, 'pnl_1/pnl_enemy')
	self:UpdatePlayerView(enemyPnl, gGBMain:GetEnemyPlayer(), enemyWin)
	-- 非引导时
	if not self.isGuiding then
		-- 触发新手任务 - 对战1次
		NewbieTaskPage.NewbieTaskDoneEvent(NewbieTaskType.PKONCE)
		if myWin then
			-- 触发新手任务 - 对战胜利1次
			NewbieTaskPage.NewbieTaskDoneEvent(NewbieTaskType.PKWIN)
		end
	end
end

---- 计算胜利获得的积分和金币数量
	-- @bool _watchBeforeAD: 是否观看战斗前广告
function BattleSettlePKGroup:CalcWinScoreAndGoldCounts( _watchBeforeAD )
	-- 顺序敏感
	-- 连胜次数/连胜加成倍数
	local myWinStreak = self.myWinStreak > Constants.PK_MAX_WIN_STREAK and Constants.PK_MAX_WIN_STREAK or self.myWinStreak
	local winStreakScale = (myWinStreak > 1) and (myWinStreak - 1) or 0
	---- 积分 ----
	local scoreCounts =
	{
		baseAdd      = Constants.PK_SCORE_WIN_BASE,
		winStreakAdd = winStreakScale * Constants.PK_SCORE_WIN_STREAK,
		beforeADAdd  = _watchBeforeAD and Constants.ADS_PK_SCORE or 0,
		showAdd1     = 0,
		showAdd2     = 0,
	}
	---- 金币 ----
	local goldCounts =
	{
		baseAdd      = Constants.PK_COIN_WIN_BASE,
		winStreakAdd = winStreakScale * Constants.PK_COIN_WIN_STREAK,
		beforeADAdd  = _watchBeforeAD and Constants.ADS_PK_COIN or 0,
		showAdd1     = 0,
		showAdd2     = 0,
	}
	-- 胜利BUFF活动, 增加收益
	local buffScale = gUIDataMgr.taskData:BuffTaskPKWinScale() or 0
	if buffScale > 0 then
		scoreCounts.baseAdd = scoreCounts.baseAdd + math.ceil(scoreCounts.baseAdd * buffScale)
		scoreCounts.winStreakAdd = scoreCounts.winStreakAdd + math.ceil(scoreCounts.winStreakAdd * buffScale)
		scoreCounts.beforeADAdd = scoreCounts.beforeADAdd + math.ceil(scoreCounts.beforeADAdd * buffScale)

		goldCounts.baseAdd = goldCounts.baseAdd + math.ceil(goldCounts.baseAdd * buffScale)
		goldCounts.winStreakAdd = goldCounts.winStreakAdd + math.ceil(goldCounts.winStreakAdd * buffScale)
		goldCounts.beforeADAdd = goldCounts.beforeADAdd + math.ceil(goldCounts.beforeADAdd * buffScale)
	end
	-- 积分显示1 = 基础 + 连胜 + 战斗前广告
	scoreCounts.showAdd1 = scoreCounts.baseAdd + scoreCounts.winStreakAdd + scoreCounts.beforeADAdd
	-- 金币显示1 = 基础 + 连胜 + 战斗前广告
	goldCounts.showAdd1 = goldCounts.baseAdd + goldCounts.winStreakAdd + goldCounts.beforeADAdd
	
	-- 积分显示2 = 显示1 x 战斗后广告倍数
	scoreCounts.showAdd2 = scoreCounts.showAdd1 * (self.afterADScale or 1)
	-- 金币显示2 = 显示1 x 战斗后广告倍数
	goldCounts.showAdd2 = goldCounts.showAdd1 * (self.afterADScale or 1)

	return scoreCounts, goldCounts
end

---- 更新选手视图
	-- @gameObject _pnl:          面板
	-- @table      _battlePlayer: BattlePlayer
	-- @bool       _win:          是否胜利
	-- @bool       _isMy:         是否我方
	-- @bool       _showPoint:    显示积分变化
function BattleSettlePKGroup:UpdatePlayerView( _pnl, _battlePlayer, _win )
	if not (_pnl and _battlePlayer) then
		warn('not (_pnl and _battlePlayer)', _pnl, _battlePlayer)
		return false
	end
	-- 胜利 or 失败
	UIUtils.SetChildActive(_pnl, 'pnl_title/pnl_win', _win)
	UIUtils.SetChildActive(_pnl, 'pnl_title/pnl_lose', not _win)
	-- 玩家名
	UIUtils.SetChildText(_pnl, 'pnl_name/txt', _battlePlayer.playerName)
	-- 阵容
	if _battlePlayer.towerPool then
		local towerRes = false
		for index = 1, Constants.SET_TOWER_COUNT do
			towerRes = GameResMgr.GetBattleTowerRes(_battlePlayer.towerPool[index] or 0)
			if not towerRes then
				warn('not towerRes', _battlePlayer.towerPool[index] or 0)
				return false
			end
			TowerPainter.PaintSettle(UIUtils.GetChild(_pnl, 'pnl_tower/item_' .. index), towerRes)
		end
	else
		warn('not _battlePlayer.towerPool')
	end
end

---- 更新我方失败视图
	-- @gameObject _pnl: 面板
function BattleSettlePKGroup:UpdateMyLoseView( _pnl )
	if not _pnl then
		warn('not _pnl')
		return false
	end
	-- 玩家创建房间时不显示扣分
	UIUtils.SetChildActive(_pnl, 'pnl_title/pnl_lose/pnl_start', not self.isManual)
	if not self.isManual then
		-- 失败BUFF活动, 减少扣分
		local loseScore = -Constants.PK_SCORE_LOSE_BASE
		local protectScore = gUIDataMgr.taskData:BuffTaskPKLoseProtect() or 0
		if protectScore > 0 then
			loseScore = loseScore + protectScore
		end
		UIUtils.SetChildText(_pnl, 'pnl_title/pnl_lose/pnl_start/txt_num', loseScore)
	end
end

---- 更新我方胜利结算视图
function BattleSettlePKGroup:UpdateMyWinView( ... )
	-- 我方
	self:UpdatePlayerView(UIUtils.GetChild(self, 'pnl_2/pnl_mine'), gGBMain:GetMyPlayer(), true)
	-- 连胜次数
	local winStreakText = GAMETEXT('ui_winStreak', self.myWinStreak - 1)
	UIUtils.SetChildText(self, 'pnl_2/pnl_mine/pnl_title/pnl_win/txt_liansheng', winStreakText)
	-- 广告按钮
	local showAds = self.afterADScale > 1 and GameAds.CheckEnough(ExtraBonusType.PKWINBONUS) and self.scoreCounts.beforeADAdd == 0
	UIUtils.SetChildActive(self, 'pnl_2/pnl_btn/btn_ads', showAds)
	if showAds then
		UIUtils.SetChildText(self, 'pnl_2/pnl_btn/btn_ads/pnl_txt/txt_num', self.afterADScale)
	end
	---- 积分 ----
	-- 基础
	OCUtils.SetText(UIName.PKSettleWinScore, 1, '+' .. self.scoreCounts.baseAdd)
	-- 连胜
	OCUtils.SetText(UIName.PKSettleWinScore, 2, '+' .. self.scoreCounts.winStreakAdd)
	-- 广告
	OCUtils.SetText(UIName.PKSettleWinScore, 3, '+' .. self.scoreCounts.beforeADAdd)
	-- 总和
	OCUtils.SetText(UIName.PKSettleWinScore, 4, '+0')
	---- 金币 ----
	-- 基础
	OCUtils.SetText(UIName.PKSettleWinGold, 1, '+' .. self.goldCounts.baseAdd)
	-- 连胜
	OCUtils.SetText(UIName.PKSettleWinGold, 2, '+' .. self.goldCounts.winStreakAdd)
	-- 广告
	OCUtils.SetText(UIName.PKSettleWinGold, 3, '+' .. self.goldCounts.beforeADAdd)
	-- 总和
	OCUtils.SetText(UIName.PKSettleWinGold, 4, '+0')
end

---- 显示金币和积分总数变化
	-- @number _score1:   积分起始值
	-- @number _score2:   积分结束值
	-- @number _gold1:    金币起始值
	-- @number _gold2:    金币结束值
	-- @number _duration: 变化时长
function BattleSettlePKGroup:ShowWinScoreAndGoldChange( _score1, _score2, _gold1, _gold2, _duration )
	-- 积分累加总数
	OCUtils.TextValueTo(UIName.PKSettleWinScore, 5, _score1, _score2, _duration or 2, '+Number')
	-- 金币累加总数
	OCUtils.TextValueTo(UIName.PKSettleWinGold, 5, _gold1, _gold2, _duration or 2, '+Number')
end

---- 未使用
function BattleSettlePKGroup:OnGroupDestroy( ... )
end
function BattleSettlePKGroup:InitOBRegister( ... )
end
function BattleSettlePKGroup:OnShow( ... )
end
function BattleSettlePKGroup:OnHide( ... )
end

classend()