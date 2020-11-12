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

	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBGrid:Init( _gbPlayer, _gridIndex, _uBattleGrid, ... )
	self.uBattleUnit = _uBattleGrid
	self.gbPlayer = _gbPlayer
	self.grid = _gbPlayer.player:GetGrid(_gridIndex)
end

function GBGrid:UpdateBuffer( _bufferList, _bufferIndexMap, ... )
	self.uBattleUnit:HideAllBuffers()

	for i = 1, #_bufferList do
		local buffer = _bufferList[i]
		local gridFeature = buffer.bufferRes.gridFeature
		if gridFeature ~= '' then
			local count = buffer:GetLayerCount()
			local colors = Split(gridFeature, '|')
			self.uBattleUnit:SetBuffer(0, count, ToInt(colors[1]) / 255, ToInt(colors[2]) / 255, ToInt(colors[3]) / 255, 1)
			break
		end
	end
end

classend()