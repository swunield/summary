---
--- class BattleRecord
-- @classmod BattleRecord
class('BattleRecord')

local FRAME_QUEUE_CAPACITY = 64

---Constructor
function BattleRecord:ctor( ... )
	-- 序列化数据
	self.battleVersion = false									-- 版本号
	self.battleSeed = false 									-- 种子
	self.battleId = false 										-- 战斗id
	self.battleType = false 									-- 战斗类型
	self.isRealTime = false 									-- 是否即时战斗
	self.playerList = {}										-- 战斗玩家列表，BattlePlayer

	-- 可序列化可运行时数据
	self.frameCount = 0											-- 即时战斗帧数
	self.battleResult = false 									-- 战斗结果

	-- 运行时数据
	self.allUnits = {}											-- 所有单位Map，只用于快速查找，UnitId全局唯一，UnitId -- BattleUnit
end

function BattleRecord:Load( _tRecord, ... )
	if not _tRecord then
		return
	end

	self.battleVersion = _tRecord.BattleVersion
	self.battleSeed = _tRecord.BattleSeed
	self.battleId = _tRecord.BattleId
	self.battleType = _tRecord.BattleType
	self.isRealTime = _tRecord.IsRealTime
	self.frameCount = _tRecord.FrameCount
	-- 战斗结束
	self.battleResult = BattleResult()
	if _tRecord.BattleResult then
		self.battleResult:Load(_tRecord.BattleResult)
	end
	-- 玩家
	self.playerList = {}
	for i = 1, #_tRecord.PlayerList do
		local player = BattlePlayer()
		player:Load(_tRecord.PlayerList[i])
		table_insert(self.playerList, player)
	end
end

function BattleRecord:Finalize( ... )
	for i = 1, #self.playerList do
		self:RemoveBattleUnit(self.playerList[i].unitId)
		self.playerList[i]:Destroy()
		self.playerList[i] = false
	end
	self.playerList = {}
	self.allUnits = {}

	self.battleResult = false
	Global.gBattleResult = nil
end

function BattleRecord:Initialize( ... )
	if not self.battleResult then
		self.battleResult = BattleResult()
	end
	Global.gBattleResult = self.battleResult

	-- 初始化玩家
	for i = 1, #self.playerList do
		self.playerList[i]:Init(i)
		self:AddBattleUnit(self.playerList[i].unitId, self.playerList[i])
	end
end

function BattleRecord:Update( _deltaTime, ... )
	-- 更新玩家
	for i = 1, #self.playerList do
		self.playerList[i]:Update(_deltaTime)
	end
end

function BattleRecord:GetRealTimeFrameCount()
	return self.isRealTime and self.frameCount or BattleConstants.BATTLE_MAX_FRAME
end

function BattleRecord:GetNextFrameCount( ... )
	local nextFrame = BattleConstants.BATTLE_MAX_FRAME
	local nextFramePlayer = false
	for i = 1, #self.playerList do
		local player = self.playerList[i]
		local nextPlayerFrame = player:GetNextFrameCount()
		if nextPlayerFrame ~= 0 and nextPlayerFrame < nextFrame then
			nextFrame = nextPlayerFrame
			nextFramePlayer = player
		end
	end
	return nextFrame, nextFramePlayer
end

function BattleRecord:GetNextFrame( _moveToNext, ... )
	local nextFrame = BattleConstants.BATTLE_MAX_FRAME
	local nexFramePlayer = false
	for i = 1, #self.playerList do
		local player = self.playerList[i]
		local nextPlayerFrame = player:GetNextFrameCount()
		if nextPlayerFrame ~= 0 and nextPlayerFrame < nextFrame then
			nextFrame = nextPlayerFrame
			nexFramePlayer = player
		end
	end
	if not nextFramePlayer then
		return false
	end
	return nextFramePlayer:GetNextFrame(_moveToNext)
end

function BattleRecord:AddBattleFrame( _playerId, _frame, _frameType, _param1, _param2, _point, ... )
	local player = self:GetBattlePlayer(_playerId)
	if not player then
		return
	end
	player:AddBattleFrame(_frame, _frameType, _param1, _param2, _point)
end

function BattleRecord:GetBattlePlayer( _playerId, _enemy, ... )
	for i = 1, #self.playerList do
		local player = self.playerList[i]
		if (not _enemy and player.playerId == _playerId) or (_enemy and player.playerId ~= _playerId) then
			return player
		end
	end
	return false
end

function BattleRecord:GetAllPlayers( ... )
	return self.playerList
end

function BattleRecord:AddBattleUnit( _unitId, _battleUnit, ... )
	self.allUnits[_unitId] = _battleUnit
end

function BattleRecord:RemoveBattleUnit( _unitId, ... )
	self.allUnits[_unitId] = nil
end

function BattleRecord:GetBattleUnit( _unitId, ... )
	return NilDefault(self.allUnits[_unitId], false)
end

-- 投降
function BattleRecord:ExecSurrender( _playerId, _frame, _player, _isLogic, ... )
	if not _player then
		_player = self:GetBattlePlayer(_playerId)
	end
	if not _player then
		return false, -1
	end
	return _player:ExecSurrender(_frame, self.isRealTime, _isLogic)
end

-- _needPending 是否需要缓冲，实时对战时，玩家抽卡可以不用等待后端返回，直接随机出塔放下，并且记录缓冲帧
--  			 待接收到后端操作帧，跟缓冲帧校验，并移除
function BattleRecord:ExecRoll( _playerId, _frame, _player, _isLogic, ... )
	if not _player then
		_player = self:GetBattlePlayer(_playerId)
	end
	if not _player then
		return false, -1
	end
	return _player:ExecRoll(_frame, self.isRealTime, _isLogic)
end

function BattleRecord:ExecMerge( _playerId, _frame, _player, _isLogic, ... )
	if not _player then
		_player = self:GetBattlePlayer(_playerId)
	end
	if not _player then
		return false, -1
	end
	return _player:ExecMerge(_frame, self.isRealTime, _isLogic)
end

function BattleRecord:ExecMagic( _playerId, _frame, _player, _isLogic, ... )
	if not _player then
		_player = self:GetBattlePlayer(_playerId)
	end
	if not _player then
		return false, -1
	end
	return _player:ExecMagic(_frame, self.isRealTime, _isLogic)
end

classend()
export('BattleRecord', BattleRecord)