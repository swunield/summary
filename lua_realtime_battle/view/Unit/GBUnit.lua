---
--- class GBUnit
-- @classmod GBUnit
class('GBUnit')

---Constructor
function GBUnit:ctor( ... )
	self.gameObject = false 				-- 单位物件
	self.transform = false 					-- 单位Transform
	self.uBattleUnit = false				-- 单位组件
	self.gbPlayer = false 					-- 玩家
	self.unit = false 						-- BattleUnit，逻辑单位
end

function GBUnit:Destroy( ... )
	-- 销毁当前类声明的变量，尤其是与UnityObject之间的引用
	self:ClearContent()
end

function GBUnit:Init( ... )
	-- body
end

classend()