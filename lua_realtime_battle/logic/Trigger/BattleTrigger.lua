---
--- class BattleTrigger
-- @classmod BattleTrigger
class('BattleTrigger')

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
function BattleTrigger:RegisterAction( _actionId, _battleUnit, _ownerUnit, ... )
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
		actionList = {}
		self.triggerMap[triggerKey] = actionList
	end
	-- 触发器行为
	local triggerId = self:GenerateTriggerId()
	local triggerAction = BattleTriggerAction(_battleUnit, _ownerUnit, actionRes, triggerRes, triggerId)
	table_insert(actionList, triggerAction)
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
	if not actionList or #actionList == 0 then
		return
	end
	local actionCount = #actionList
	for i = actionCount, 1, -1 do
		local action = actionList[i]
		if action and not action.isRemove and action.actionRes.id == _actionId and action.battleUnit.unitId == _battleUnit.unitId then
			action.isRemove = true
			break
		end
	end
end

-- 移除单位所有行为
function BattleTrigger:UnRegisterUnitAllActions( _battleUnit, ... )
	for k, actionList in pairs(self.triggerMap) do
		local actionCount = #actionList
		for i = actionCount, 1, -1 do
			local action = actionList[i]
			if action.battleUnit.unitId == _battleUnit.unitId then
				action.isRemove = true
			end
		end
	end
end

-- 触发行为
function BattleTrigger:FireTrigger( _triggerType, _triggerParam, ... )
	local triggerKey = _triggerType
	local actionList = self.triggerMap[triggerKey]
	if not actionList or #actionList == 0 then
		return
	end
	local actionCount = #actionList
	for i = 1, actionCount do
		local action = actionList[i]
		if action and not action.isRemove then
			action:FireTrigger(_triggerParam)
		end
	end
end

-- 触发行为，直接触发，光环or魔法
function BattleTrigger:FireAction( _actionId, _battleUnit, _ownerUnit, _triggerParam, ... )
	local actionRes = GameResMgr.GetBattleActionRes(_actionId)
	if not actionRes then
		return
	end
	local triggerRes = GameResMgr.GetBattleTriggerRes(actionRes.triggerId)
	local triggerAction = BattleTriggerAction(_battleUnit, _ownerUnit, actionRes, triggerRes)
	triggerAction:FireTrigger(_triggerParam)
end

-- 生成触发器ID
function BattleTrigger:GenerateTriggerId( ... )
	self.triggerIdGenerator = self.triggerIdGenerator + 1
	return self.triggerIdGenerator
end

classend()