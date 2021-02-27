class('BattleSettlePage', PageBase)  -- 战斗结算界面n

---- 构造
function BattleSettlePage:ctor( page, ... )
	self.super = Super(page, ...)
end

---- 初始化
function BattleSettlePage:Init( ... )
	-- 自定义事件
	self:RegisterEvents()
end

---- 显示
	-- @table _data: TBattleSettle
function BattleSettlePage:OnShow( _data, ... )
	-- 战斗类型
	local battleTypeText = false
	-- 战斗结果
	local battlResultText = _data.IsMyWin and '胜利' or '失败'
	-- 玩家积分
	local addScore = 0
	-- 金币数量
	local addCoin = 0
	-- 宝箱碎片
	local addChest = 0
	-- 连胜积分
	local streakScore = 0
	-- 挑战
	if _data.BattleType == BattleType.PK then
		battleTypeText = '挑战'
		addScore = _data.IsMyWin and 30 or -20
		addCoin = _data.IsMyWin and 35 or 0
		if gUIDataMgr.profileData.tUserProfile and gUIDataMgr.profileData.tUserProfile.TPKProfile then
			local winStreak = gUIDataMgr.profileData.tUserProfile.TPKProfile.WinStreak
			if winStreak > 1 then
				streakScore = (tPKProfile.WinStreak - 1) * 5
			end
		end
	-- 合作
	elseif _data.BattleType == BattleType.COOP then
		battleTypeText = '合作'
		local bonusList = _data.BonusOutput and _data.BonusOutput.BonusList or false
		if bonusList then
			for index = 1, #bonusList.Ids do
				-- 宝箱碎片
				if bonusList.Ids[index] == Constants.COOP_CHEST_ITEMID then
					addChest = bonusList.Counts[index]
				-- 金币
				elseif bonusList.Ids[index] == Constants.COIN_ITEMID then
					addCoin = bonusList.Counts[index]
				end
			end
		end
	else
		battleTypeText = '未知'
		warn('Unknown BattleType', _data.BattleType)
	end
	UIUtils.SetChildText(self, 'pnl/txt_result',
		'战斗类型 ' .. battleTypeText
		.. '\n战斗结果 ' .. battlResultText
		.. '\n玩家积分 ' .. ((addScore >= 0) and '+' or '') .. addScore
		.. '\n连胜积分 ' .. streakScore
		.. '\n金币数量 +' .. addCoin
		.. '\n宝箱碎片 +' .. addChest)
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
	---- 注册事件
	function BattleSettlePage:RegisterEvents( ... )
		self.customEvents =
		{
			-- 返回主城
			['ClickOK'] = function( ... )
				gGameClient:JumpToScene('Home')
				return false
			end,
		}
	end

---- 未使用
function BattleSettlePage:OnPageDestroy( ... )
end
function BattleSettlePage:OnGetUIGroup( _groupPath, ... )
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