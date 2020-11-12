-- 此Plugin会被后端调用
-- 不能添加跟Unity引擎相关的代码

-- 引用类集合
use 'BattleMain'
use 'BattleManager'
use 'BattleHero'
use 'BattleAction'
use 'BattleTarget'
use 'BattleTrigger'
use 'BattleBuffer'
use 'BattleSpecialLogic'

-- 全局定义
Global.gameutils = plugins.gameutils
Global.gameres = plugins.gameres

-- print开关
Global.basePrint = print
Global.print = function( ... ) end

Global.gBattleRandNum = nil				-- 战斗随机数
Global.gBattleManager = nil				-- 战斗管理器
Global.gBattleAction = nil				-- 当前行动

-- 战斗版本号
Global.BattleVersion = 78
  