---
--- class GBGrid
-- @classmod GBGrid
class('GBGrid', GBUnit)

---Constructor
function GBGrid:ctor( ... )
	self.super = Super()

	self.grid = false
end

function GBGrid:Destroy( ... )
	-- 父类销毁
	self.super:Destroy()
end

function GBGrid:Init( _gbPlayer, _gridIndex, _uBattleGrid, ... )
	self.uBattleUnit = _uBattleGrid
	self.grid = _gbPlayer.player:GetGrid(_gridIndex)
	self.battleUnit = self.grid
	self.gbUnit = self
	self.gbPlayer = _gbPlayer
end

function GBGrid:UpdateBuffer( _bufferList, _bufferIndexMap, ... )

end

classend()