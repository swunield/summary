---
--- class BattleFrame
-- @classmod BattleFrame
class('BattleFrame')

local table_insert = table.insert

---Constructor
function BattleFrame:ctor( ... )
	-- 序列化数据
	self.frameCount = false 			-- 帧数
	self.frameType = false				-- 帧类型，抽卡、选卡、塔合成、释放魔法、发表情、投降
	self.param1 = false					-- 选卡(索引)、塔合成(塔1索引)、释放魔法(魔法索引)、发表情(表情Id)
	self.param2 = false 				-- 塔合成(塔2索引)
	self.param3 = false 				-- 塔合成(当前塔等级，只用于客户端本地)
	self.point = false 					-- 当前点数

	-- 可序列化可运行时数据
	self.frameId = false				-- 帧Id

	-- 运行时数据
	self.actionList = {} 				-- 行为列表，加塔/删塔/改变等级
end

function BattleFrame:Load( _tBattleFrame, ... )
	if not _tBattleFrame then
		return
	end

	self.frameCount = _tBattleFrame.FrameCount or 0
	self.frameType = _tBattleFrame.FrameType
	self.param1 = _tBattleFrame.Param1 or false
	self.param2 = _tBattleFrame.Param2 or false
	self.param3 = false
	self.point = _tBattleFrame.Point or false
	self.frameId = _tBattleFrame.FrameId or false
	self.actionList = {}
end

local FrameActionSwitcher = {
	[BattleFrameActionType.ADDTOWER] = function( self, _player, _towerRes, _star, _posIndex, _pendingId, ... )
		-- 添加逻辑塔
		local tower = _player:AddTower(_towerRes, _star, _posIndex, self.frameType == BattleFrameType.ROLL)
		local _ = G_SendGBCommand and G_SendGBCommand(GBCommandType.PENDINGTOWER, _player.playerId, tower, _pendingId)
	end,
	[BattleFrameActionType.REMOVETOWER] = function( self, _player, _posIndex, _leaveFlags, ... )
		-- 移除塔
		_player:RemoveTower(_posIndex, _leaveFlags)
	end,
	[BattleFrameActionType.EXCHANGETOWER] = function( self, _player, _dragIndex, _targetIndex, ... )
		-- 交换塔
		_player:ExchangeTower(_dragIndex, _targetIndex)
	end,
	[BattleFrameActionType.UPGRADETOWER] = function( self, _player, _towerPoolIndex, ... )
		-- 升级塔
		_player:UpgradeTower(_towerPoolIndex)
	end
}

function BattleFrame:AddFrameAction( _actionType, _player, _param1, _param2, _param3, _param4, ... )
	if not _player then
		return
	end
	local frameAction = {
		actionType = _actionType,
		player = _player,
		param1 = _param1 or false,
		param2 = _param2 or false,
		param3 = _param3 or false,
		param4 = _param4 or false
	}
	table_insert(self.actionList, frameAction)
end

function BattleFrame:OnPendingOver( ... )
	if #self.actionList == 0 then
		return
	end
	for i = 1, #self.actionList do
		local action = self.actionList[i]
		local switcher = FrameActionSwitcher[action.actionType]
		if switcher then
			switcher(self, action.player, action.param1, action.param2, action.param3, action.param4)
		end
	end
end

classend()
export('BattleFrame', BattleFrame)