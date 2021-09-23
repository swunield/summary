---
--- class BattleTrigger
-- @classmod BattleTrigger
BattleTrigger = xclass('BattleTrigger')

local os_clock = os.clock

local LMLinkList = plugins.gameutils.LMLinkList
local LMLinkNode = plugins.gameutils.LMLinkNode
local LMLinkList_New = LMLinkList.New
local LMLinkList_Add = LMLinkList.Add
local LMLinkList_AddNode = LMLinkList.AddNode
local LMLinkList_RemoveNode = LMLinkList.RemoveNode
local LMLinkList_Clear = LMLinkList.Clear
local LMLinkList_Find = LMLinkList.Find

---Constructor
function BattleTrigger:ctor( ... )  
	self.triggerMap = {}			-- 触发器Map，Key--BattleTriggerType  Value--ActionTrigger Array
	self.triggerIdGenerator = 0		-- 触发器Id生成器
end

function BattleTrigger:Finalize( ... )  
	-- body
end

function BattleTrigger:Initialize( ... )  
	-- body
end

-- 注册行为
function BattleTrigger:RegisterAction( _actionId, _battleUnit, _owner, ... )  
	local actionRes = GameResMgr.GetBattleActionRes(_actionId)
	if not actionRes then
		return 0
	end
	local triggerRes = GameResMgr.GetBattleTriggerRes(actionRes.triggerId)
	if not triggerRes then
		return 0
	end
	-- 注册触发器
	local triggerKey = triggerRes.triggerType
	local actionList = self.triggerMap[triggerKey]
	if actionList == nil then
		actionList = LMLinkList_New()
		self.triggerMap[triggerKey] = actionList
	end
	-- 触发器行为
	local triggerId = self:GenerateTriggerId()
	local triggerAction = BattleTriggerAction(_battleUnit, _owner, actionRes, triggerRes, triggerId)
	triggerAction.node = LMLinkList_Add(actionList, triggerAction)
	return triggerId
end

-- 移除行为
function BattleTrigger:UnRegisterAction( _actionId, _battleUnit, ... )
	local actionRes = GameResMgr.GetBattleActionRes(_actionId)
	if not actionRes then
		return
	end
	local triggerRes = GameResMgr.GetBattleTriggerRes(actionRes.triggerId)
	if not triggerRes then
		return
	end
	local triggerKey = triggerRes.triggerType
	local actionList = self.triggerMap[triggerKey]
	if not actionList or actionList.count == 0 then
		return
	end
	local actionNode = actionList.first
	while actionNode do
		local action = actionNode.value
		if action and action.actionRes.id == _actionId and action.battleUnit.unitId == _battleUnit.unitId then
			LMLinkList_RemoveNode(actionList, actionNode)
			break
		end
		actionNode = actionNode.next
	end
end

-- 移除单位所有行为
function BattleTrigger:UnRegisterUnitAllActions( _battleUnit, ... )
	for k, actionList in pairs(self.triggerMap) do
		local actionNode = actionList.first
		while actionNode do
			local action = actionNode.value
			if action and action.battleUnit.unitId == _battleUnit.unitId then
				actionNode = LMLinkList_RemoveNode(actionList, actionNode)
			else
				actionNode = actionNode.next
			end
		end
	end
end

-- 触发行为
T_TRIGGER = 0
function BattleTrigger:FireTrigger( _triggerType, _triggerParam, _battleUnit, ... )
	-- 序列化期间禁用
	if gSnapShotPushing or gBattleFinalizing then
		return
	end

	local triggerKey = _triggerType
	local actionList = self.triggerMap[triggerKey]
	if not actionList or actionList.count == 0 then
		return
	end
	local actionNode = actionList.first
	while actionNode do
		local action = actionNode.value
		if action and (not _battleUnit or _battleUnit == action.battleUnit) then
	-- local time = os_clock()
			action:FireTrigger(_triggerParam)
	-- T_TRIGGER = T_TRIGGER + os_clock() - time
		end
		actionNode = actionNode.next
	end
end

-- 触发行为，直接触发，光环or魔法
function BattleTrigger:FireAction( _actionId, _battleUnit, _owner, _triggerParam, ... )
	-- 序列化期间禁用
	if gSnapShotPushing or gBattleFinalizing then
		return
	end

	local actionRes = GameResMgr.GetBattleActionRes(_actionId)
	if not actionRes then
		return
	end
	local triggerRes = GameResMgr.GetBattleTriggerRes(actionRes.triggerId)
	local triggerAction = BattleTriggerAction(_battleUnit, _owner, actionRes, triggerRes)
	triggerAction:FireTrigger(_triggerParam)
end

-- 生成触发器ID
function BattleTrigger:GenerateTriggerId( ... )  
	self.triggerIdGenerator = self.triggerIdGenerator + 1
	return self.triggerIdGenerator
end