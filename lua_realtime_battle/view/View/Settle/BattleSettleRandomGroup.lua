class('BattleSettleRandomGroup', GroupBase)  -- 战斗结算 - 随机竞技场

---- 构造
function BattleSettleRandomGroup:ctor( ... )
	self.super = Super(...)
end

---- 初始化
function BattleSettleRandomGroup:Init( ... )
	-- 自定义事件
	self.customEvents =
	{
		-- 点击双方胜负的确定按钮
		['ClickPnlOK'] = function ( ... )
			-- 返回主城
			UIUtils.HidePage('battle_settle')
			gGameClient:JumpToScene('Home')
			return false
		end,
	}
end

---- 更新
function BattleSettleRandomGroup:InternalUpdateGroup( ... )
	if not self.groupData then
		warn('not self.groupData')
		return false
	end
	self:UpdatePlayerView(UIUtils.GetChild(self, 'pnl/pnl_mine'), gGBMain:GetMyPlayer(), self.groupData.isMyWin)
	self:UpdatePlayerView(UIUtils.GetChild(self, 'pnl/pnl_enemy'), gGBMain:GetEnemyPlayer(), not self.groupData.isMyWin)
end

---- 更新选手视图
	-- @gameObject _pnl:          面板
	-- @table      _battlePlayer: BattlePlayer
	-- @bool       _win:          是否胜利
	-- @bool       _isMy:         是否我方
	-- @bool       _showPoint:    显示积分变化
function BattleSettleRandomGroup:UpdatePlayerView( _pnl, _battlePlayer, _win )
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

---- 未使用
function BattleSettleRandomGroup:OnGroupDestroy( ... )
end
function BattleSettleRandomGroup:InitOBRegister( ... )
end
function BattleSettleRandomGroup:OnShow( ... )
end
function BattleSettleRandomGroup:OnHide( ... )
end

classend()