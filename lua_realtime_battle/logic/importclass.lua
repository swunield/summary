-- 此Plugin会被后端调用
-- 不能添加跟Unity引擎相关的代码

Global.gModel = plugins.model

-- 引用类集合
use 'BattleEnums'
use 'BattleConstants'

require 'BattleMain'
require 'BattleManager'

require 'Model/BattleCommon'
require 'Model/BattleFlag'
require 'Model/BattleStat'
require 'Model/BattleResult'
require 'Model/BattleTimer'
require 'Trigger/BattleTriggerParam'
require 'Unit/BattleMissile'
require 'Trigger/BattleTriggerAction'
require 'Trigger/BattleTrigger'
require 'AI/BattlePlayerAI'
require 'Skill/BattleSkill'
require 'Skill/BattleSkill_Dice'
require 'Skill/BattleSkill_StarBall'
require 'Skill/BattleSkill_Kill'
require 'Unit/BattleUnit'
require 'Unit/BattleTower'
require 'Unit/BattleHero'
require 'Unit/BattleMonster'
require 'Unit/BattleGrid'
require 'Unit/BattleCollider'
require 'Unit/BattlePlayer'
require 'Record/BattleFrame'
require 'Record/BattlePlayerFrame'
require 'Record/BattleRecord'
require 'Logic/BattlePkDistance'
require 'Logic/BattleCoopDistance'
require 'Logic/BattleLogic'
require 'Logic/BattlePkLogic'
require 'Logic/BattleCoopLogic'
require 'Buffer/BattleBuffer'
require 'Buffer/BattleBufferLayer'

require 'BattleFormula'
require 'BattleTarget'

-- 全局定义
Global.gameutils = plugins.gameutils
Global.gameres = plugins.gameres
Global.PERF = function( ... ) end
Global.PERFEND = function( ... ) end
Global.Profiler_Begin = function( ... ) end
Global.Profiler_End = function( ... ) end

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
Global.gBattleType = nil				-- 战斗类型
Global.gBattleResult = nil				-- 战斗结果
Global.BattleMonsterDistance = nil		-- 战斗怪物距离

-- 性能优化
Global.G_SendGBCommand = nil
Global.gSnapShotPushing = nil			-- 快照推送中
Global.gBattleFinalizing = nil			-- 战斗销毁中
Global.gBattleFreezing = nil			-- 战斗冻结中

-- 战斗版本号
Global.BattleVersion = 8
