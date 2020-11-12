---
--- class BattleMain
-- @classmod BattleMain
class('BattleMain')

-- 日志开关
LogEnable = false

-- 战斗逻辑入口，战斗开始时实例化且战斗全程唯一，战斗结束时销毁
local s_instance;
function BattleMain.INSTANCE( ... )
	if not s_instance then
		s_instance = BattleMain()
	end
	return s_instance
end

function BattleMain.Destroy( ... )
	if s_instance then
		s_instance:Finalize()
		s_instance = nil
	end
end

---Constructor
function BattleMain:ctor( ... )
	self.randNum = false					-- 战斗随机数
	self.battleMananger = false				-- 战斗管理器
	self.battleTrigger = false				-- 战斗触发器
	self.gameCommand = false				-- 游戏显示命令中心
end

function BattleMain:Finalize( ... )
	Global.gBattleRandNum = nil
	Global.gBattleManager = nil
	Global.gBattleAction = nil
	Global.gBattleTrigger = nil
end

function BattleMain:Initialize( _battleEnterData, _gameCommand, _isLogEnable, ... )
	if not _battleEnterData then
		return false
	end
	
	-- 初始化战斗随机数
	self.randNum = RandNum(_battleEnterData.battleSeed)
	Global.gBattleRandNum = self.randNum
	
	-- 初始化战斗管理器
	self.battleMananger = BattleManager()
	Global.gBattleManager = self.battleMananger
	gBattleManager.isRecord = NilDefault(_battleEnterData.isRecord, false)
	gBattleManager.isVideo = NilDefault(_battleEnterData.isVideo, false)
	gBattleManager:Initialize(_battleEnterData, _isLogEnable)
	
	gBattleManager:AddBattleLog(string.format("Battle Begin Seed[%s] BattleId[%s] BattleType[%d] BattleParam[%s]", _battleEnterData.battleSeed, _battleEnterData.battleId, _battleEnterData.battleType, _battleEnterData.battleParam))	
	
	-- 初始化战斗触发器
	self.battleTrigger = BattleTrigger()
	Global.gBattleTrigger = self.battleTrigger
	
	-- 连接游戏显示命令中心
	self.gameCommand = _gameCommand or false
	gBattleManager.isClientMode = _gameCommand and true or false
	
	-- 初始化战斗
	gBattleManager:InitBattleCampTalent()
	gBattleManager:InitBattleTeam(BattleCampType.CAMP_A, false)
	gBattleManager:InitBattleTeam(BattleCampType.CAMP_B, true)

	-- 特殊战斗逻辑初始化
	BattleSpecialLogic.InitSpecialBattle()
	
	return true
end

-- 向游戏中发送指令
function BattleMain:SendGBCommand( cmdType, cmdData1, cmdData2, cmdData3, ... )
	if (not gBattleManager.jumpBattle or cmdType == GBCommandType.BATTLEEND) and self.gameCommand then
		self.gameCommand:OnCommand(cmdType, cmdData1, cmdData2, cmdData3, ... )
	else
		-- 服务端模式下，自动驱动行动
		if cmdType == GBCommandType.ACTION and cmdData3 then
			-- 遍历所有主行为目标触发伤害逻辑
			local actionHero = gBattleManager:GetBattleHero(cmdData1)
			if actionHero then
				actionHero:ExecSkill()
			end
			
			-- 下一个行动
			gBattleAction:ActionEnd()
		elseif cmdType == GBCommandType.BEGINBATTLE then
			gBattleManager:BeginBattle()
		end
	end
end

-- 战斗模拟入口，后端使用
function BattleMain:SimulateBattle( _battleEnterData, _isLogEnable, ... )
	local battleEnterTable = String2Table(_battleEnterData)
	if not battleEnterTable then
		return nil
	end
	
	-- 从Table中加载战斗数据
	local battleEnterData = gameres.BattleEnterData()
	battleEnterData:LoadData(battleEnterTable)
	
	-- 战斗模拟初始化
	self:Initialize(battleEnterData, nil, _isLogEnable)

	-- 战斗开始
	gBattleManager:BeginBattle()
	
	-- 返回战斗结果
	return gBattleManager.battleResult.instanceContent
end

-- 战斗模拟入口，前端使用
function BattleMain:SimulateBattle_Client( _battleEnterData, _isLogEnable, ... )
	-- 战斗输入数据
	local battleEnterData = _battleEnterData
	
	-- 战斗模拟初始化
	self:Initialize(battleEnterData, nil, _isLogEnable)

	-- 战斗开始
	gBattleManager:BeginBattle()
	
	-- 返回战斗结果
	return gBattleManager.battleResult.instanceContent
end

classend()
export("BattleMain", BattleMain)