---
--- class BattleResult
-- @classmod BattleResult
class('BattleResult')

---Constructor
function BattleResult:ctor( ... )
	self.winPlayerId = 0 			-- 胜利玩家Id
	self.frameCount = 0 			-- 最后一帧
	self.roundNum = 0				-- 回合数 
end

function BattleResult:SetWinPlayerId( _playerId, ... )
	self.winPlayerId = _playerId
end

function BattleResult:SetFrameCount( _frameCount, ... )
	self.frameCount = _frameCount
end

function BattleResult:SetRoundNum( _roundNum, ... )
	self.roundNum = _roundNum
end

classend()