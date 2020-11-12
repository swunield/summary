---
--- class BattleMain
-- @classmod BattleMain
class('BattleMain')

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
	self.battleMananger = false 			-- 战斗管理器
	self.gameCommand = false				-- 游戏显示命令中心
end

function BattleMain:Finalize( ... )
	if self.battleMananger then
		self.battleMananger:Finalize()
	end
	self.battleMananger = false
	Global.gBattleManager = nil

	Global.gBattleRandNum = nil
end

function BattleMain:Initialize( _battleRecord, _gameCommand, ... )
	if not _battleRecord then
		return false
	end

	-- 连接游戏显示命令中心
	self.gameCommand = _gameCommand or false
	
	-- 初始化战斗随机数
	self.randNum = RandNum(_battleRecord.battleSeed)
	Global.gBattleRandNum = self.randNum

	-- 初始化战斗管理器
	self.battleMananger = BattleManager()
	self.battleMananger.isClientMode = _gameCommand and true or false
	Global.gBattleManager = self.battleMananger
	gBattleManager:Initialize(_battleRecord)

	-- 公式测试代码
	-- for i = 1, 200 do
	-- 	gBattleLogic.waveNum = i
	-- 	local round = gBattleLogic.roundNum
	-- 	gBattleLogic.roundNum = ToInt((i - 1) / 10) + 1
	-- 	if gBattleLogic.roundNum ~= round then
	-- 		gBattleLogic.roundStartWaveNum = gBattleLogic.waveNum
	-- 	end
	-- 	warn(i, BattleFormula.GetValue(200001, false))
	-- end
	
	return true
end

-- 战斗逻辑主循环
function BattleMain:Update( _deltaTime, ... )
	if not self.battleMananger then
		return
	end

	-- 管理器
	gBattleManager:Update(_deltaTime)
end

-- 向游戏中发送指令
function BattleMain:SendGBCommand( _cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ... )
	if self.gameCommand then
		return self.gameCommand:OnCommand(_cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ... )
	end
	return false
end

-- 战斗模拟入口，后端使用
function BattleMain:SimulateBattle( _battleRecord, ... )
	local battleRecordTable = String2Table(_battleRecord)
	if not battleRecordTable then
		return nil
	end
	
	-- 从Table中加载战斗数据
	local battleRecord = BattleRecord()
	battleRecord:Load(battleRecordTable)
	battleRecord.isRealTime = false
	
	-- 战斗模拟初始化
	self:Initialize(battleRecord)

	-- 战斗开始
	gBattleManager:BeginBattle()

	-- 驱动战斗帧
	while (gBattleManager.battleState ~= BattleState.END) do
		self:Update(Constants.BATTLE_FRAME_TIME)
	end
	
	-- 返回战斗结果
	return gBattleResult.instanceContent
end

classend()
export("BattleMain", BattleMain)