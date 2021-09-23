class('BattleSettlePage', PageBase)  -- 战斗结算界面

---- 构造
function BattleSettlePage:ctor( page, ... )
	self.super = Super(page, ...)

	-- 视图
	self.pkGroup   = BattleSettlePKGroup()        -- 挑战视图
	self.coopGroup = BattleSettleCoopGroup()      -- 合作视图
	self.randomGroup = BattleSettleRandomGroup()  -- 随机竞技场视图

	-- 视图表
	self.groupMap =
	{
		['canvas/pnl_group/group_pvp/group_battle_settle_pvp'] = self.pkGroup,    -- 挑战视图
		['canvas/pnl_group/group_pve/group_battle_settle_pve'] = self.coopGroup,  -- 合作视图
		['canvas/pnl_group/group_jjc_suiji/group_battle_settle_jjc_suiji'] = self.randomGroup,  -- 随机竞技场视图
	}
end

---- 初始化
function BattleSettlePage:Init( ... )
end

---- 获取视图
function BattleSettlePage:OnGetUIGroup( _groupPath )
	return self.groupMap[_groupPath] or false
end

---- 显示
	-- @table _data: TBattleSettle
function BattleSettlePage:OnShow( _data, ... )
	if not _data then
		warn('not _data')
		return false
	end
	-- 挑战
	if _data.BattleType == BattleType.PK then
		local groupData =
		{
			isMyWin = _data.IsMyWin or false,
			isSuccess = _data.Success or false,
			isGuiding = _data.IsGuiding or false,
			isManual = _data.IsManual or false,
			watchBeforeAD = _data.ExtraBonusFlag == 1,
			afterADScale = (((_data.BonusOutput and _data.BonusOutput.BonusList) and _data.BonusOutput.BonusList.ExtraFactor or 0) % 1000) + 1,
		}
		-- 我方胜利或者结算失败都显示胜利
		local action = (groupData.isMyWin or (not groupData.isSuccess)) and 'Open_Group_Pvp_Win' or 'Open_Group_Pvp_Lose'
		UIUtils.SelectActionSelector(self, action)
		self.pkGroup:UpdateGroup(groupData)
	-- 合作
	elseif _data.BattleType == BattleType.COOP then
		local groupData =
		{
			round = _data.Round or 1,
			shardCounts = _data.BonusOutput.BonusList.Counts,
			isSuccess = _data.Success or false,
		}
		UIUtils.SelectActionSelector(self, 'Open_Group_Pve')
		self.coopGroup:UpdateGroup(groupData)
	-- 随机竞技场
	elseif _data.BattleType == BattleType.PKRANDOM then
		local groupData =
		{
			isMyWin = _data.IsMyWin or false,
			isSuccess = _data.Success or false,
		}
		-- 我方胜利或者结算失败都显示胜利
		local action = (groupData.isMyWin or (not groupData.isSuccess)) and 'Open_Group_Jjc_Suiji_Win' or 'Open_Group_Jjc_Suiji_Lose'
		UIUtils.SelectActionSelector(self, action)
		self.randomGroup:UpdateGroup(groupData)
	else
		warn('Unknwon BattleType', _data.BattleType)
	end
end

---- 事件
	---- 打开界面
		-- @table _tBattleSettle: TBattleSettle
	function OpenPage( _tBattleSettle )
		if not _tBattleSettle then
			warn('not _tBattleSettle')
			return false
		end
		UIUtils.ShowPage('battle_settle', 1, nil, _tBattleSettle)
	end

---- 未使用
function BattleSettlePage:OnPageDestroy( ... )
end
function BattleSettlePage:OnUIGroupInit( _groupPath, _luaUIGroup, ... )
end
function BattleSettlePage:InitOBRegister( ... )
end
function BattleSettlePage:OnHide( ... )
end
function BattleSettlePage:OnPageRefresh( _key, _data, ... )
end

classend()

Global.BattleSettlePage = BattleSettlePage