-- 此Plugin会被后端调用
-- 不能添加跟Unity引擎相关的代码

Global.gModel = plugins.model

-- 引用类集合
use 'BattleEnums'
use 'BattleConstants'

use 'BattleMain'
use 'BattleManager'

use 'Model/BattleCommon'
use 'Model/BattleFlag'
use 'Model/BattleStat'
use 'Model/BattleResult'
use 'Model/BattleTimer'
use 'Trigger/BattleTriggerParam'
use 'Trigger/BattleTriggerAction'
use 'Trigger/BattleTrigger'
use 'AI/BattlePlayerAI'
use 'Unit/BattleMissile'
use 'Unit/BattleUnit'
use 'Unit/BattleTower'
use 'Unit/BattleHero'
use 'Unit/BattleMonster'
use 'Unit/BattleGrid'
use 'Unit/BattleCollider'
use 'Unit/BattlePlayer'
use 'Record/BattleFrame'
use 'Record/BattlePlayerFrame'
use 'Record/BattleRecord'
use 'Logic/BattlePkDistance'
use 'Logic/BattleCoopDistance'
use 'Logic/BattleLogic'
use 'Logic/BattlePkLogic'
use 'Logic/BattleCoopLogic'
use 'Buffer/BattleBuffer'
use 'Buffer/BattleBufferLayer'

use 'BattleFormula'
use 'BattleTarget'

-- 全局定义
Global.gameutils = plugins.gameutils
Global.gameres = plugins.gameres
Global.PERF = function( ... ) end
Global.PERFEND = function( ... ) end

-- print开关
-- Global.print = function( ... ) end
-- Global.log = function( ... ) end

Global.gBattleRandNum = nil				-- 战斗随机数
Global.gBattleManager = nil				-- 战斗管理器
Global.gBattleRecord = nil				-- 战斗记录器
Global.gBattleLogic = nil				-- 战斗逻辑
Global.gBattleTrigger = nil				-- 战斗触发器
Global.gBattleTimer = nil				-- 战斗计时器
Global.gBattleTime = nil				-- 战斗当前时间
Global.gBattleFrameCount = nil			-- 战斗当前帧
Global.gBattleType = nil				-- 战斗类型
Global.gBattleResult = nil				-- 战斗结果
Global.BattleMonsterDistance = nil		-- 战斗怪物距离

-- 性能优化
Global.G_SendGBCommand = nil
Global.gSnapShotPushing = nil			-- 快照推送中
Global.gBattleFinalizing = nil			-- 战斗销毁中

-- 战斗版本号
Global.BattleVersion = 1
