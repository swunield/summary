---
--- class GBCommand
-- @classmod GBCommand

class('GBCommand')

-- 游戏战斗显示命令中心，战斗开始时实例化且战斗全程唯一，战斗结束时销毁
local s_instance;
function GBCommand.INSTANCE( ... )
	if not s_instance then
		s_instance = GBCommand()
		s_instance:Initialize()
	end
	return s_instance
end

function GBCommand.Destroy( ... )
	if s_instance then
		s_instance:Finalize()
		s_instance = nil
	end
end

function GBCommand.SendGBCommand( cmdType, cmdData, ... )
	if s_instance then
		s_instance:OnCommand( cmdType, cmdData, ... )
	end
end

---Constructor
function GBCommand:ctor( ... )
end

-- 初始化战场
function GBCommand:Initialize( ... )
end

-- 销毁战场
function GBCommand:Finalize( ... )
end

local GBCommandSwitcher = {
	-- 添加玩家
	[GBCommandType.ADDPLAYER] = function( _playerId, ... )
		return gGBField:AddGBPlayer(_playerId)
	end,
	-- 添加塔
	[GBCommandType.ADDTOWER] = function( _playerId, _towerRes, _gunCount, _posIndex, ... )
		return gGBField:AddGBTower(_playerId, _towerRes, _gunCount, _posIndex)
	end,
	-- 移除塔
	[GBCommandType.REMOVETOWER] = function( _playerId, _posIndex, ... )
		return gGBField:RemoveGBTower(_playerId, _posIndex)
	end,
	-- 交换塔
	[GBCommandType.EXCHANGETOWER] = function( _playerId, _dragIndex, _targetIndex, ... )
		return gGBField:ExchangeGBTower(_playerId, _dragIndex, _targetIndex)
	end,
	-- 塔缓冲结束
	[GBCommandType.PENDINGTOWER] = function( _playerId, _tower, _pendingId, ... )
		return gGBField:OnTowerPendingOver(_playerId, _tower, _pendingId)
	end,
	-- 添加怪物
	[GBCommandType.ADDMONSTER] = function( _playerId, _monsterId, ... )
		return gGBField:AddGBMonster(_playerId, _monsterId)
	end,
	-- 移除怪物
	[GBCommandType.REMOVEMONSTER] = function( _playerId, _monsterId, ... )
		return gGBField:RemoveGBMonster(_playerId, _monsterId)
	end,
	-- 怪物血量
	[GBCommandType.MONSTERHP] = function( _playerId, _monsterId, ... )
		return gGBField:UpdateMonsterHP(_playerId, _monsterId)
	end,
	-- 怪物移动
	[GBCommandType.MONSTERMOVE] = function( _playerId, _monsterId, _position, _speed, ... )
		return gGBField:MonsterMove(_playerId, _monsterId, _position, _speed)
	end,
	-- 添加碰撞
	[GBCommandType.ADDCOLLIDER] = function( _playerId, _colliderId, _ownerUnitId, ... )
		return gGBField:AddGBCollider(_playerId, _colliderId, _ownerUnitId)
	end,
	-- 移除碰撞
	[GBCommandType.REMOVECOLLIDER] = function( _playerId, _colliderId, ... )
		return gGBField:RemoveGBCollider(_playerId, _colliderId)
	end,
	-- 点数更新
	[GBCommandType.POINT] = function( _playerId, _point, _costPoint, ... )
		return GBMain.INSTANCE():UpdatePoint(_playerId, _point, _costPoint)
	end,
	-- 战斗结束
	[GBCommandType.BATTLEEND] = function( _result, _battleId, ... )
		return GBMain.INSTANCE():OnLogicBattleEnd(_result, _battleId)
	end,
	-- 发射
	[GBCommandType.FIRE] = function( _unitId, _gunIndex, _missile, _fireInterval, ... )
		return gGBField:FireMissile(_unitId, _gunIndex, _missile, _fireInterval)
	end,
	-- 添加魔法到魔法槽
	[GBCommandType.MAGICADD] = function( _playerId, _magicIndex, _magicData, ... )
		return gGBField:AddMagic(_playerId, _magicIndex, _magicData)
	end,
	-- 魔法更新
	[GBCommandType.MAGICUPDATE] = function( _playerId, _magicIndex, _magicData, ... )
		return gGBField:UpdateMagic(_playerId, _magicIndex, _magicData)
	end,
	-- 统计
	[GBCommandType.STAT] = function( ... )
		return gGBField:UpdateStat()
	end,
	-- 格子更新
	[GBCommandType.GRIDUPDATE] = function( _playerId, _gridIndex, _bufferList, ... )
		return gGBField:UpdateGrid(_playerId, _gridIndex, _bufferList)
	end,
}

-- 处理战斗指令
function GBCommand:OnCommand( _cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ... )
	local cmdExcuter = GBCommandSwitcher[_cmdType]
	if cmdExcuter then
		return cmdExcuter(_cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ...)
	end
	return false
end

classend()