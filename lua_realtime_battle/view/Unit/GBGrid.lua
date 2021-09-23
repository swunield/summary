---
--- class GBGrid
-- @classmod GBGrid
GBGrid = xclass('GBGrid', GBUnit)

local FireBattleGridEvent = LUBattleGrid.FireUnitEvent
local ShowBattleGridCover = LUBattleGrid.ShowCover

---Constructor
function GBGrid:ctor( ... )
	self.grid = false
end

function GBGrid:Destroy( ... )
	-- 父类销毁
	self.super:Destroy()
end

function GBGrid:Init( _gbPlayer, _gridIndex, _gridId, ... )
	self.grid = _gbPlayer.player:GetGrid(_gridIndex)
	self.battleUnit = self.grid
	self.gbUnit = self
	self.gbPlayer = _gbPlayer
	self.unitId = _gridId
end

function GBGrid:UpdateBuffer( _bufferList, _bufferIndexMap, ... )

end

-- 状态变化
local UnitFlagChangeSwitcher = 
{
	-- 光球锁定
	[BattleUnitFlag.STARBALLLOCK] = function( self, _isAdd, ... )
		FireBattleGridEvent(self.unitId, _isAdd and GameStringType.OnTowerStarBallLock or GameStringType.OnTowerStarBallUnLock)
		return true
	end,
	-- 暗杀锁定
	[BattleUnitFlag.ANSHALOCK_1] = function( self, _isAdd, ... )
		FireBattleGridEvent(self.unitId, _isAdd and GameStringType.OnTowerAnShaLock_1 or GameStringType.OnTowerAnShaUnLock_1)
		return true
	end,
	[BattleUnitFlag.ANSHALOCK_2] = function( self, _isAdd, ... )
		FireBattleGridEvent(self.unitId, _isAdd and GameStringType.OnTowerAnShaLock_2 or GameStringType.OnTowerAnShaUnLock_2)
		return true
	end,
}

function GBGrid:OnUnitFlagChange( _unitFlag, _isAdd )
	local switcher = UnitFlagChangeSwitcher[_unitFlag]
	if switcher and switcher(self, _isAdd) then
		if _isAdd then
			self.unitFlagMap[_unitFlag] = 1
		else
			self.unitFlagMap[_unitFlag] = nil
		end
	end
end

function GBGrid:ShowCover( _isShow, _eventNameId, ... )
	if self.unitId == 0 then
		return
	end
	local isShow = NilDefault(_isShow, true)
	ShowBattleGridCover(self.unitId, isShow, _eventNameId)
end