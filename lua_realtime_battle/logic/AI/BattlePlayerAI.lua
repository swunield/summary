---
--- class BattlePlayerAI
-- @classmod BattlePlayerAI
class('BattlePlayerAI')

local table_insert = table.insert

local TSPlayerAI = gModel.TSPlayerAI

---Constructor
function BattlePlayerAI:ctor( _tPlayerAI, ... )
	self.player = false						-- 玩家
	self.tPlayerAI = _tPlayerAI or false	-- AI策略
	self.towerMap = {}						-- 塔单星阶级价值表
	self.rollValue = 0						-- 抽卡价值
	self.rollOperation = false
	self.mergeOperationList = {}
	self.bestOperation = false				-- 最优操作
	self.bestFrame = false
	self.rollFactor = 1
	self.upgradeFactor = 1
	self.mergeFactor = 1

	self.firstRollTimes = 0					-- 初始roll次数
	self.nextFrameCount = 0					-- 下一次AI判定帧数
	self.mergeDirtyFlag = 0					-- 0不需刷新 1只刷新价值 2价值列表全部刷新
end

function BattlePlayerAI:Serialize( ... )
	local tPlayerAI = TSPlayerAI:new{}
	tPlayerAI.FirstRollTimes = self.firstRollTimes ~= 0 and self.firstRollTimes or nil
	tPlayerAI.NextFrameCount = self.nextFrameCount
	tPlayerAI.MergeDirtyFlag = self.mergeDirtyFlag ~= 0 and self.mergeDirtyFlag or nil
	return tPlayerAI
end

function BattlePlayerAI:DeSerialize( _tPlayerAI, ... )
	if not _tPlayerAI then
		return
	end
	self.firstRollTimes = _tPlayerAI.FirstRollTimes or 0
	self.nextFrameCount = _tPlayerAI.NextFrameCount
	self.mergeDirtyFlag = _tPlayerAI.MergeDirtyFlag or 0
end

function BattlePlayerAI:Init( _player, ... )
	self.player = _player or false
	-- 操作价值系数
	self.rollFactor = self.tPlayerAI.RollFactor / Constants.PERCENT_MAX
	self.upgradeFactor = self.tPlayerAI.UpgradeFactor / Constants.PERCENT_MAX
	self.mergeFactor = self.tPlayerAI.MergeFactor / Constants.PERCENT_MAX
	-- 初始化塔单星阶级价值表
	local towerPool = _player.towerPool
	for i = 1, #towerPool do
		local towerFactor = self.tPlayerAI.TowerFactors[i] / Constants.PERCENT_MAX
		local tower = { valueList = {}, poolIndex = i, curValue = 0, nextValue = 0, totalStar = 0, upgradeValueUp = 0, upgradeCost = 0, upgradeOperation = false }
		local towerResId = towerPool[i]
		self.towerMap[towerResId] = tower
		local towerAIRes = GameResMgr.GetBattleTowerAIRes(towerResId)
		for n = 1, #towerAIRes.valueList do
			tower.valueList[n] = towerAIRes.valueList[n] * towerFactor
		end
		tower.curValue = tower.valueList[1]
		tower.nextValue = tower.valueList[2]
		tower.upgradeCost = Constants.BATTLE_GRADE_COST[1]
		tower.upgradeOperation = { value = 0, priority = 0, frame = { FrameType = BattleFrameType.UPGRADE, Param1 = i }, isPointEnough = false }
	end
	-- 刷新Roll价值
	self:RefreshRollValue()
	-- 初始化Roll操作
	self.rollOperation = { value = 0, priority = 0, frame = { FrameType = BattleFrameType.ROLL }, isPointEnough = true }
	self.firstRollTimes = 4
	self.nextFrameCount = gBattleRandNum:NextInt(Constants.BATTLE_FPS / 2, Constants.BATTLE_FPS)
	-- 初始化最优帧
	self.bestFrame = BattleFrame()
end

function BattlePlayerAI:Update( ... )
	if self.nextFrameCount ~= gBattleFrameCount then
		return
	end

	-- 初始先Roll4次
	if self.firstRollTimes ~= 0 then
		self.bestOperation = self.rollOperation
		self.firstRollTimes = self.firstRollTimes - 1
	else
		self:BuildAllOperations()
	end

	self.nextFrameCount = gBattleFrameCount + (self.firstRollTimes ~= 0 and 20 or gBattleRandNum:NextInt(Constants.BATTLE_FPS / 2, Constants.BATTLE_FPS * 2))
	self:TryExecBestOperation()
end

function BattlePlayerAI:BuildAllOperations( ... )
	self.bestOperation = false

	local player = self.player
	local curPoint = player.point
	local rollCost = player.costPoint
	local frameCount = gBattleFrameCount
	local hasEmptyPos = player:HasEmptyPos()

	-- 合成
	if self.mergeDirtyFlag ~= 0 then
		self:RefreshMergeOperation()
		self.mergeDirtyFlag = 0
	end
	for i = 1, #self.mergeOperationList do
		-- warn('CheckBestOperation Merge', self.mergeOperationList[i].mergeFlag, self.mergeOperationList[i].value, self.mergeOperationList[i].towerList[1].posIndex, self.mergeOperationList[i].towerList[2].posIndex)
		self:CheckBestOperation(self.mergeOperationList[i])
	end
	if not hasEmptyPos and self.bestOperation then
		-- 格子满后，如果可合成的则直接合成
		-- 如果没有可合成的，则只能升阶了
		return
	end
	-- Roll和升阶取价值最高的操作
	local bestOtherOperation = false
	if hasEmptyPos then
		local rollOperation = self.rollOperation
		rollOperation.isPointEnough = curPoint >= rollCost 
		rollOperation.value = self.rollValue * (curPoint >= rollCost and rollCost or curPoint) / rollCost
		bestOtherOperation = rollOperation
	end	
	-- 升阶
	for towerResId, tower in pairs(self.towerMap) do
		local upgradeOperation = tower.upgradeOperation
		if upgradeOperation then
			local upgradeCost = tower.upgradeCost
			upgradeOperation.isPointEnough = curPoint >= upgradeCost
			upgradeOperation.value = tower.upgradeValueUp * (curPoint >= upgradeCost and upgradeCost or curPoint) / upgradeCost
			if not bestOtherOperation then
				bestOtherOperation = upgradeOperation
			elseif upgradeOperation.value > bestOtherOperation.value then
				bestOtherOperation = upgradeOperation
			end
		end
	end
	if bestOtherOperation then
		self:CheckBestOperation(bestOtherOperation)
	end
end

function BattlePlayerAI:CheckBestOperation( _operation, ... )
	if not _operation then
		return
	end
	local bestOperation = self.bestOperation
	if not bestOperation then
		self.bestOperation = _operation
		return
	end
	if _operation.priority > bestOperation.priority then
		self.bestOperation = _operation
		return
	end
	if _operation.priority < bestOperation.priority then
		return
	end
	if _operation.value > bestOperation.value then
		self.bestOperation = _operation
	end
end

function BattlePlayerAI:TryExecBestOperation( ... )
	local bestOperation = self.bestOperation
	if not bestOperation or not bestOperation.isPointEnough then
		return false
	end
	if bestOperation.priority < 0 and self.player:HasEmptyPos() then
		-- 有空格的情况下，低优先级操作不执行
		return false
	end
	local frame = bestOperation.frame
	if not frame then
		frame = { FrameType = BattleFrameType.MERGE, Param1 = bestOperation.towerList[1].posIndex, Param2 = bestOperation.towerList[2].posIndex }
	end
	-- warn('AI TryExecBestOperation', gBattleFrameCount, frame.FrameType, bestOperation.value, bestOperation.priority, self.rollValue, self.rollOperation.value)
	-- if frame.FrameType == BattleFrameType.MERGE then
	-- 	warn('AI Merge', bestOperation.star, self:GetTowerValue(bestOperation.towerList[1]), self:GetTowerValue(bestOperation.towerList[2]))
	-- end
	self.bestFrame:Load(frame)
	gBattleManager:ExecBattleFrame(nil, self.bestFrame, self.player)
	return true
end

function BattlePlayerAI:OnTowerUpgrade( _towerResId, _grade, ... )
	local tower = self.towerMap[_towerResId]
	if not tower or not tower.upgradeOperation then
		return
	end
	if _grade == Constants.BATTLE_MAX_GRADE then
		tower.upgradeOperation = false
		return
	end
	tower.curValue = tower.valueList[_grade]
	tower.nextValue = tower.valueList[_grade + 1]
	tower.upgradeCost = Constants.BATTLE_GRADE_COST[_grade]
	tower.upgradeValueUp = (tower.nextValue - tower.curValue) * self.upgradeFactor * tower.totalStar
	if self.mergeDirtyFlag == 0 then
		self.mergeDirtyFlag = 1
	end
end

function BattlePlayerAI:OnTowerEnter( _battleTower, ... )
	local tower = self.towerMap[_battleTower.towerRes.id]
	if not tower then
		return
	end
	tower.totalStar = tower.totalStar + _battleTower.star
	tower.upgradeValueUp = (tower.nextValue - tower.curValue) * tower.totalStar
	self.mergeDirtyFlag = 2
	if self.firstRollTimes == 0 and self.nextFrameCount - gBattleFrameCount < Constants.BATTLE_FPS then
		-- warn('Check Frame Count', self.nextFrameCount, gBattleFrameCount, gBattleFrameCount + Constants.BATTLE_FPS - self.nextFrameCount)
		self.nextFrameCount = gBattleFrameCount + Constants.BATTLE_FPS
	end
end

function BattlePlayerAI:OnTowerLeave( _battleTower, ... )
	local tower = self.towerMap[_battleTower.towerRes.id]
	if not tower then
		return
	end
	tower.totalStar = tower.totalStar - _battleTower.star
	tower.upgradeValueUp = (tower.nextValue - tower.curValue) * tower.totalStar
	self.mergeDirtyFlag = 2
	if self.firstRollTimes == 0 and self.nextFrameCount - gBattleFrameCount < Constants.BATTLE_FPS then
		-- warn('Check Frame Count', self.nextFrameCount, gBattleFrameCount, gBattleFrameCount + Constants.BATTLE_FPS - self.nextFrameCount)
		self.nextFrameCount = gBattleFrameCount + Constants.BATTLE_FPS
	end
end

function BattlePlayerAI:RefreshRollValue( ... )
	local totalValue = 0
	local count = 0
	for towerResId, tower in pairs(self.towerMap) do
		totalValue = totalValue + tower.curValue
		count = count + 1
	end
	self.rollValue = totalValue * self.rollFactor / count
end

function BattlePlayerAI:RefreshMergeOperation( ... )
	local hasEmptyPos = self.player:HasEmptyPos()
	if self.mergeDirtyFlag == 2 then
		self.mergeOperationList = {}
		-- 把所有塔，先按星级分组，再按塔类型分组
		local starTowerMap = {}
		local towerList = self.player.towerList
		for i = 1, #towerList do
			local battleTower = towerList[i]
			if battleTower then
				local star = battleTower.star
				local towerMap = starTowerMap[star]
				if not towerMap then
					towerMap = {}
					starTowerMap[star] = towerMap
				end
				local towerList = towerMap[battleTower.towerRes.id]
				if not towerList then
					towerList = {}
					towerMap[battleTower.towerRes.id] = towerList
				end
				table_insert(towerList, battleTower)
			end
		end
		for star, towerMap in pairs(starTowerMap) do
			local isNotMaxStar = star ~= Constants.BATTLE_MAX_STAR
			for towerResId, towerList in pairs(towerMap) do
				-- 普通合成，成长不可合成，7星不能普通合成
				local firstTower = towerList[1]
				local birthFlag = firstTower.towerRes.birthFlag
				if isNotMaxStar and birthFlag ~= BattleUnitFlag.GROWUP and #towerList >= 2 then
					local targetTower = towerList[2]
					local mergeFlag = (birthFlag == BattleUnitFlag.REPRODUCE or birthFlag == BattleUnitFlag.FIX) and birthFlag or 0
					local priority = GameResMgr.GetBattleTowerAIPriority(firstTower.towerRes.baseId, targetTower.towerRes.baseId)
					local mergeOperation = { value = 0, star = star + 1, priority = priority, towerList = { firstTower, targetTower }, mergeFlag = mergeFlag, isPointEnough = true }
					table_insert(self.mergeOperationList, mergeOperation)
				end
				-- 复制、营养、适应，7星只能复制
				-- 成长只能被复制，不能被营养、适应合成
				local isFit = birthFlag == BattleUnitFlag.FIT
				local isCopy = birthFlag == BattleUnitFlag.COPY
				local isFix = birthFlag == BattleUnitFlag.FIX
				if isCopy or (isNotMaxStar and (isFit or isFix)) then
					for targetTowerResId, targetTowerList in pairs(towerMap) do
						if targetTowerResId ~= towerResId then
							local targetTower = targetTowerList[1]
							local targetBirthFlag = targetTower.towerRes.birthFlag
							if isCopy or targetBirthFlag ~= BattleUnitFlag.GROWUP then
								local mergeFlag = (isFit and targetBirthFlag == BattleUnitFlag.REPRODUCE) and targetBirthFlag or birthFlag
								local priority = GameResMgr.GetBattleTowerAIPriority(firstTower.towerRes.baseId, targetTower.towerRes.baseId)
								local mergeOperation = { value = 0, star = star + 1, priority = priority, towerList = { firstTower, targetTower }, mergeFlag = mergeFlag, isPointEnough = true }
								table_insert(self.mergeOperationList, mergeOperation)
							end
						end
					end
				end
			end
		end
	end
	-- 计算操作价值
	local mergeFactor = self.mergeFactor
	for i = 1, #self.mergeOperationList do
		local opertaion = self.mergeOperationList[i]
		opertaion.value = self:GetMergeValue(opertaion.mergeFlag, opertaion.towerList, opertaion.star) * mergeFactor
	end
end

-- 合成价值
local MergeValueSwitcher = {
	-- 合成，生成下一星随机，消耗两个塔本体
	[BattleUnitFlag.ALL] = function( self, _towerList, _star, ... )
		return self.rollValue * _star - self:GetTowerValue(_towerList[1]) - self:GetTowerValue(_towerList[2])
	end,
	-- 复制，生成同星目标，消耗复制本体
	[BattleUnitFlag.COPY] = function( self, _towerList, _star, ... )
		return self:GetTowerValue(_towerList[2], 0) - self:GetTowerValue(_towerList[1])
	end,
	-- 营养，生成下一星目标，消耗两个塔本体
	[BattleUnitFlag.FIX] = function( self, _towerList, _star, ... )
		return self:GetTowerValue(_towerList[2], 1) - self:GetTowerValue(_towerList[1]) - self:GetTowerValue(_towerList[2])
	end,
	-- 繁衍，生成1星随机+下一星随机，消耗两个塔本体
	[BattleUnitFlag.REPRODUCE] = function( self, _towerList, _star, ... )
		return self.rollValue * (1 + _star) - self:GetTowerValue(_towerList[1]) - self:GetTowerValue(_towerList[2])
	end,
	-- 适应，生成下一星随机，消耗两个塔本体
	[BattleUnitFlag.FIT] = function( self, _towerList, _star, ... )
		return self.rollValue * _star - self:GetTowerValue(_towerList[1]) - self:GetTowerValue(_towerList[2])
	end,
}

function BattlePlayerAI:GetMergeValue( _mergeFlag, _towerList, _star, ... )
	local switcher = MergeValueSwitcher[_mergeFlag]
	if not switcher then
		switcher = MergeValueSwitcher[BattleUnitFlag.ALL]
	end
	return switcher(self, _towerList, _star)
end

function BattlePlayerAI:GetTowerValue( _battleTower, _extraStar, ... )
	local extraStar = _extraStar or 0
	local isCopy = _isCopy or false
	local towerResId = _battleTower.towerRes.id
	local star = _battleTower.star + extraStar
	local tower = self.towerMap[towerResId]
	local starValue = tower.curValue
	return starValue * star
end

classend()