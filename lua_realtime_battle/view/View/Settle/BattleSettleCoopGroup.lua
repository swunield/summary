class('BattleSettleCoopGroup', GroupBase)  -- 战斗结算 - 挑战

---- 构造
function BattleSettleCoopGroup:ctor( ... )
	self.super = Super(...)
end

---- 初始化
function BattleSettleCoopGroup:Init( ... )
	self.customEvents =
	{
		-- 点击确定按钮
		['ClickOK'] = function ( ... )
			warn('ClickOK')
			-- 返回主城
			UIUtils.HidePage('battle_settle')
			gGameClient:JumpToScene('Home')
			return false
		end,
	}
end

---- 更新
function BattleSettleCoopGroup:InternalUpdateGroup( ... )
	local groupData = self.groupData
	if not groupData then
		warn('not self.groupData')
		return false
	end
	-- 回合数
	OCUtils.SetText(UIName.COOPSettleWin, 1, tostring(groupData.round))
	-- 宝箱碎片 - 基础奖励
	OCUtils.SetText(UIName.COOPSettleWin, 2, '+' .. (groupData.shardCounts[1] or 0))
	-- 宝箱碎片 - 战斗前广告奖励
	OCUtils.SetText(UIName.COOPSettleWin, 3, '+' .. (groupData.shardCounts[2] or 0))
	-- 宝箱碎片 - 额外奖励，活动or状态
	OCUtils.SetText(UIName.COOPSettleWin, 4, '+' .. (groupData.shardCounts[3] or 0))
	-- 我方
	self:UpdatePlayerView(UIUtils.GetChild(self, 'pnl/pnl_mine'), gGBMain:GetMyPlayer())
	-- 敌方
	self:UpdatePlayerView(UIUtils.GetChild(self, 'pnl/pnl_enemy'), gGBMain:GetEnemyPlayer())
	-- 触发新手任务 - 合作模式1次
	NewbieTaskPage.NewbieTaskDoneEvent(NewbieTaskType.COOP)
end

---- 更新选手视图
	-- @gameObject _pnl:          面板
	-- @table      _battlePlayer: BattlePlayer
function BattleSettleCoopGroup:UpdatePlayerView( _pnl, _battlePlayer )
	if not (_pnl and _battlePlayer) then
		warn('not (_pnl and _battlePlayer)', _pnl, _battlePlayer)
		return false
	end
	-- 玩家名
	UIUtils.SetChildText(_pnl, 'pnl_name/txt', _battlePlayer.playerName)
	-- 阵容
	local towerRes = false
	for index = 1, Constants.SET_TOWER_COUNT do
		towerRes = GameResMgr.GetBattleTowerRes(_battlePlayer.towerPool[index] or 0)
		if not towerRes then
			warn('not towerRes', _battlePlayer.towerPool[index] or 0)
			return false
		end
		TowerPainter.PaintSettle(UIUtils.GetChild(_pnl, 'pnl_tower/item_' .. index), towerRes)
	end
end

---- 未使用
function BattleSettleCoopGroup:OnGroupDestroy( ... )
end
function BattleSettleCoopGroup:InitOBRegister( ... )
end
function BattleSettleCoopGroup:OnShow( ... )
end
function BattleSettleCoopGroup:OnHide( ... )
end

classend()