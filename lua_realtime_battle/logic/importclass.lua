-- 此Plugin会被后端调用
-- 不能添加跟Unity引擎相关的代码

-- 引用类集合
use 'Model/BattleCommon'
use 'Model/BattleStat'
use 'Model/BattleResult'
use 'Unit/BattleUnit'
use 'Unit/BattleTower'
use 'Unit/BattleMonster'
use 'Unit/BattleGrid'
use 'Unit/BattleCollider'
use 'Unit/BattlePlayer'
use 'Record/BattleFrame'
use 'Record/BattlePlayerFrame'
use 'Record/BattleRecord'
use 'Logic/BattleLogic'
use 'Logic/BattlePkLogic'
use 'Logic/BattleCoopLogic'
use 'Buffer/BattleBuffer'
use 'Buffer/BattleBufferLayer'
use 'Trigger/BattleTrigger'
use 'Trigger/BattleTriggerAction'
use 'Trigger/BattleTriggerParam'

use 'BattleConstants'
use 'BattleFormula'
use 'BattleTarget'

use 'BattleMain'
use 'BattleManager'

-- 性能优化
Global.table_insert = table.insert
Global.table_remove = table.remove
Global.table_sort = table.sort
Global.table_concat = table.concat

-- 全局定义
Global.gameutils = plugins.gameutils
Global.gameres = plugins.gameres

-- print开关
Global.print = function( ... ) end
Global.log = function( ... ) end

Global.gBattleRandNum = nil				-- 战斗随机数
Global.gBattleManager = nil				-- 战斗管理器
Global.gBattleRecord = nil				-- 战斗记录器
Global.gBattleLogic = nil				-- 战斗逻辑
Global.gBattleTrigger = nil				-- 战斗触发器
Global.gBattleTimer = nil				-- 战斗计时器
Global.gBattleTime = nil				-- 战斗当前时间
Global.gBattleFrameCount = nil			-- 战斗当前帧
Global.gBattleResult = nil				-- 战斗结果

-- 战斗版本号
Global.BattleVersion = 1
