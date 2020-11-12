---
--- class BattleSettlePage
-- @classmod BattleSettlePage
class('BattleSettlePage', PageBase)

---Constructor
function BattleSettlePage:ctor( page, ... )
	self.super = Super(page, ...)
end

function BattleSettlePage:OnPageDestroy( ... )

end

function BattleSettlePage:Init( ... )
	-- 自定义事件
	self.customEvents = {
		-- 返回主城
		['ClickOK'] = function( ... )
			self:OnClickOK()
			return false
		end,
	}
end

function BattleSettlePage:OnGetUIGroup( _groupPath, ... )

end

function BattleSettlePage:OnUIGroupInit( _groupPath, _luaUIGroup, ... )

end

function BattleSettlePage:InitOBRegister( ... )

end

function BattleSettlePage:OnShow( _data, ... )
	UIUtils.SetChildText(self, 'pnl/txt_result', string.format('%s [%d-->%d]', _data.WinPlayerId == gUIDataMgr:GetUserId() and '胜利 ' or '失败', _data.lastExp, _data.UserLevel.Exp))
end

function BattleSettlePage:OnHide( ... )

end

function BattleSettlePage:OnPageRefresh( _key, _data, ... )

end

function BattleSettlePage:OnClickOK( ... )
	gGameClient:JumpToScene('Home')
end

classend()