---
--- class BattleSkill
-- @classmod BattleSkill
BattleSkill = xclass('BattleSkill')

---Constructor
function BattleSkill:ctor( ... )
end

local BattleSkillCreator = {
	[BattleSkillType.DICE] = function( ... )
		return BattleSkill_Dice()
	end,
	[BattleSkillType.STARBALL] = function( ... )
		return BattleSkill_StarBall()
	end,
	[BattleSkillType.KILL] = function( ... )
		return BattleSkill_Kill()
	end
}

function BattleSkill.Create( _skillType, ... )
	local creator = BattleSkillCreator[_skillType]
	if creator then
		return creator()
	end
	return false
end
