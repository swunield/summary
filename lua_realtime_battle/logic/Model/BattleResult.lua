---
--- class BattleResult
-- @classmod BattleResult
class('BattleResult')

---Constructor
function BattleResult:ctor( ... )
	self.winPlayerId = false 			-- 胜利玩家Id
	self.frameCount = false 			-- 最后一帧
end

function BattleResult:SetWinPlayerId( _playerId, ... )
	self.winPlayerId = _playerId
end

function BattleResult:SetFrameCount( _frameCount, ... )
	self.frameCount = _frameCount
end

classend()