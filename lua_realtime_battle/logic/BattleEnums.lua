-- 唯一随机类型
Global.ErrorCode = {
    SUCCESS = 0,
    OK = 0,       -- 目标

    FRAME_INVALID = 1001,               -- 序列帧无效
    FRAME_PLAYERINVALID = 1002,         -- 序列帧玩家无效

    UPGRADE_FULLLEVEL = 1011,           -- 升级满级
    UPGRADE_POINTNOTENOUGH = 1012,      -- 升级点数不足

    ROLL_POINTNOTENOUGH = 1021,         -- 抽卡点数不足
    ROLL_FULLGRID = 1022,               -- 抽卡无空格
    ROLL_TOWERRESINVALID = 1023,        -- 抽卡塔无效

    MERGE_TOWERINVALID = 1031,          -- 合并塔无效
    MERGE_TYPENOTMATCH = 1032,          -- 合并塔类型不一致
    MERGE_TYPENOTEXIST = 1033,          -- 合并塔类型不存在
    MERGE_TOWERRESINVALID = 1034,       -- 合并塔无效

    HEROTALENT_TYPENOTMATCH = 1041,     -- 英雄天赋类型不一致
    HEROTALENT_NOTREADY = 1042,         -- 英雄天赋冷却中
}
export('ErrorCode', ErrorCode)

-- 战斗缓冲行为类型
Global.BattleFrameActionType = {
    ALL = 0,
    ADDTOWER = 1,    	-- 添加塔
    REMOVETOWER = 2,    -- 移除塔
    EXCHANGETOWER = 3,  -- 交换塔
    UPGRADETOWER = 4,	-- 升级塔
    MAX = 5,
}
export('BattleFrameActionType', BattleFrameActionType)

-- 唯一随机类型
Global.UniqueRandType = {
    ALL = 0,
    TARGET = 1,    -- 目标
    MAGIC = 2,    -- 魔法
    MAX = 3,
}
export('UniqueRandType', UniqueRandType)

-- 游戏命令类型
Global.GBCommandType = {
    ALL = 0,
    ADDPLAYER = 1,    -- 添加玩家
    ADDTOWER = 2,    -- 添加塔
    REMOVETOWER = 3,    -- 移除塔
    ADDMONSTER = 4,    -- 添加怪物
    REMOVEMONSTER = 5,    -- 移除怪物
    MONSTERHP = 6,    -- 怪物血量
    MONSTERMOVE = 7,    -- 怪物移动
    ADDCOLLIDER = 8,    -- 添加碰撞
    REMOVECOLLIDER = 9,    -- 移除碰撞
    POINT = 10,    -- 点数更新
    BATTLEEND = 11,    -- 战斗结束
    FIRE = 12,    -- 发射子弹
    UPGRADE = 13, -- 升级
    STAT = 16,    -- 统计
    GRIDUPDATE = 17,
    EXCHANGETOWER = 18,    -- 交换塔
    TIMESCALE = 19,    -- 播放速度
    PENDINGTOWER = 20,    -- 塔缓冲结束
    FRAMECHASING = 21,    -- 追帧
    SNAPSHOT = 22,  -- 快照
    EFFECT = 23, -- 特效添加移除
    BUFFER = 24, -- 状态添加移除
    HEROTALENTCD = 25, -- 英雄天赋CD
    ROUNDSTART = 26, -- 回合开始
    UNITEVENT = 27, -- 单位事件
    PLAYERHP = 28, -- 玩家血量
    PERIOD = 29, -- 战斗阶段
    DAMAGE = 30, -- 伤害
    FLAG = 31, -- 标记
    GUIDE = 32, -- 引导
    PLAYERPARAM = 33, -- 玩家参数
    EMOJI = 34, -- 表情
    MAX = 35,
}
export('GBCommandType', GBCommandType)

-- 单位合成类型
Global.BattleTowerMergeType = {
    ALL = 0,
    MERGE = 1,      -- 合成
    EXCHANGE = 2,   -- 交换
    COPY = 3,       -- 复制
    FIX = 4,        -- 营养
    REBUILD = 5,    -- 重构
    MAX = 5,
}
export('BattleTowerMergeType', BattleTowerMergeType)

-- 单位合成类型
Global.BattleCoopRoundType = {
    ALL = 0,
    NORMAL = 1,     -- 常规
    SPECIAL = 2,    -- 特殊，精英
    BOSS = 3,       -- 魔王
    MAX = 5,
}
export('BattleCoopRoundType', BattleCoopRoundType)

-- 战斗伤害类型
Global.BattleDamageType = {
    ALL = 0,
    NORMAL = 1,     -- 普通
    CRITICAL = 2,   -- 暴击
    POISON = 3,     -- 毒
    POINT = 4,      -- SP
    HEAL = 5,       -- 回血
    TDAMAGE = 6,    -- 触发伤害
    MAX = 7,
}
export('BattleDamageType', BattleDamageType)