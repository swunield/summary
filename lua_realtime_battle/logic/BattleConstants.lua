Global.BattleConstants = {
	-- 战斗最大帧数
	BATTLE_MAX_FRAME = 9999999,
	-- 怪物路径长度
	BATTLE_ROAD_LENGTH = 250000,
	-- 怪物路径单位长度
	BATTLE_ROAD_UNIT_LENGTH = 2500,
	-- 怪物路径长度
	BATTLE_PK_ROAD_LENGTH = 250000,
	-- 怪物路径单位长度
	BATTLE_PK_ROAD_UNIT_LENGTH = 2500,
	-- 怪物路径长度
	BATTLE_COOP_ROAD_LENGTH = 195000,
	-- 怪物路径单位长度
	BATTLE_COOP_ROAD_UNIT_LENGTH = 1950,
	-- 怪物路径拐点
	BATTLE_COOP_CORNER = 88892,
	-- 战场塔数量
	BATTLE_MAX_TOWER = 15,
	-- 战斗飞行道具飞行时长
	BATTLE_MISSILE_TIME = 200,
	-- 塔十字站位表
	BATTLE_TOWER_CROSS_MAP = {
		{ 2, 6 },
		{ 1, 3, 7 },
		{ 2, 4, 8 },
		{ 3, 5, 9 },
		{ 4, 10 },
		{ 1, 7, 11 },
		{ 2, 6, 8, 12 },
		{ 3, 7, 9, 13 },
		{ 4, 8, 10, 14 },
		{ 5, 9, 15 },
		{ 6, 12 },
		{ 7, 11, 13 },
		{ 8, 12, 14 },
		{ 9, 13, 15 },
		{ 10, 14 }
	},
	-- 玩家总血量
	BATTLE_PLAYER_TOTAL_HP = 3,
	-- 塔颜色
	BATTLE_TOWER_COLOR_LIST = {
		['火'] = { 200, 12, 0 },
		['电'] = {0, 0, 0},
		['风'] = { 0, 207, 148 },
		['毒'] = {0, 0, 0},
		['冰'] = { 0, 146, 207 },
		['幸运'] = { 208, 52, 245 },
		['强攻'] = { 0, 63, 26 },
		['禁锢'] = { 0, 15, 245 },
		['疯狂'] = { 0, 0, 0 },
	},
	-- 格子状态颜色
	BATTLE_BUFFER_COLOR_LIST = {
		[1] = { 200, 12, 0 },
		[2] = { 0, 207, 148 },
		[3] = { 0, 146, 207 },
		[4] = { 208, 52, 245 },
		[5] = { 0, 15, 245 },
		[6] = { 0, 63, 26 },
		[7] = { 200, 12, 0 },
		[8] = { 0, 207, 148 },
		[9] = { 0, 146, 207 },
		[10] = { 208, 52, 245 },
		[11] = { 0, 15, 245 },
		[12] = { 0, 63, 26 },
		[13] = { 200, 12, 0 },
		[14] = { 0, 207, 148 },
		[15] = { 0, 146, 207 },
		[16] = { 208, 52, 245 },
		[17] = { 0, 15, 245 },
		[18] = { 0, 63, 26 },
		[19] = { 200, 12, 0 },
		[20] = { 0, 207, 148 },
		[21] = { 0, 146, 207 },
		[22] = { 208, 52, 245 },
		[23] = { 0, 15, 245 },
		[24] = { 0, 63, 26 },
	},
	-- 属性百分比限制
	BATTLE_ATTRIBUTE_LIMIT = {
		-- HP
		[AttriType.HP] = {
		},
		--  ATTACK
		[AttriType.ATTACK] = {

		},
		-- DEFENCE
		[AttriType.DEFENCE] = {
		},
		-- ATKSPEED
		[AttriType.ATKSPEED] = {
			min = 280,
			max = 5000,
		},
		-- SPEED
		[AttriType.SPEED] = {
			min = 0,
			max = 40000,
		},
		-- POINT
		[AttriType.POINT] = {
		},
		-- EXATKSPEED
		[AttriType.EXATKSPEED] = {
			min = 175,
			max = 5000000,
		},
		-- SPEEDPERCENT
		[AttriType.SPEEDPERCENT] = {
			min = 0.45,
			max = 2,
		},
	},
	-- 战斗参数默认值
	BATTLE_PARAM_DEFAULT = {
		-- 上一个怪物
		[BattleParamType.LASTMONSTER] = { 
			value = 0,
			unitType = BattleUnitType.TOWER
		},	
		-- 同一怪物攻击次数
		[BattleParamType.SAMEMONSTERATTACKTIMES] = {
		 	value = 0,
			unitType = BattleUnitType.TOWER 
		},	
		-- 总攻击次数
		[BattleParamType.ATTACKTIMES] = {
		 	value = 0,
			unitType = BattleUnitType.TOWER 
		},	
		-- 总额外攻击次数
		[BattleParamType.EXTRAATTACKTIMES] = {
		 	value = 0,
			unitType = BattleUnitType.TOWER 
		},	
		-- 当前连接数量
		[BattleParamType.CURCONNECTCOUNT] = {
			value = 0,
			unitType = BattleUnitType.TOWER 
		},	
		-- 总连接数量
		[BattleParamType.CONNECTCOUNT] = { 
			value = -1,
			unitType = BattleUnitType.TOWER 
		},
		-- 总击杀数
		[BattleParamType.KILLSCORE] = {
			value = 0,
			unitType = BattleUnitType.PLAYER,
			notifyParam = true,
		},
		-- 太阳个数
		[BattleParamType.SUNCOUNT] = {
			value = 0,
			unitType = BattleUnitType.PLAYER,
			triggerType = BattleTriggerType.TRIGGERSTATE,
			towerBaseId = 1033,
			hitValues = {
				[1] = 2,
				[4] = 2,
				[7] = 2
			}
		},
		-- Combo
		[BattleParamType.COMBO] = {
			value = 0,
			unitType = BattleUnitType.PLAYER,
			notifyParam = true,
		}
	}
}
export('BattleConstants', BattleConstants)