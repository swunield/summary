---
--- class BattleMain
-- @classmod BattleMain
BattleMain = xclass('BattleMain')

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

function BattleMain.SendGBCommand( _cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ... )
	return s_instance:SendCommand(_cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, ...)
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

	Global.G_SendGBCommand = nil
end

function BattleMain:Initialize( _battleRecord, _gameCommand, ... )  
	if not _battleRecord then
		return false
	end

	-- 连接游戏显示命令中心
	self.gameCommand = _gameCommand or false
	Global.G_SendGBCommand = _gameCommand and BattleMain.SendGBCommand or nil
	
	-- 初始化战斗随机数
	self.randNum = RandNum(_battleRecord.battleSeed)
	Global.gBattleRandNum = self.randNum

	-- 初始化战斗管理器
	self.battleMananger = BattleManager()
	self.battleMananger.isClientMode = _gameCommand and true or false
	Global.gBattleManager = self.battleMananger
	gBattleManager:Initialize(_battleRecord)

	return true
end

-- 战斗逻辑主循环
function BattleMain:Update( _deltaTime, ... )  
	if not gBattleManager then
		return 0
	end

	-- 管理器
	local realDeltaTime = gBattleManager:Update(_deltaTime)

	return realDeltaTime
end

-- 向游戏中发送指令
function BattleMain:SendCommand( _cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, _cmdData6, ... )
	if self.gameCommand then
		return self.gameCommand:OnCommand(_cmdType, _cmdData1, _cmdData2, _cmdData3, _cmdData4, _cmdData5, _cmdData6, ... )
	end
	return false
end

-- 战斗模拟入口，后端使用
function BattleMain:SimulateBattle( _battleRecordString, _tBattleRecord, _battleRecord, ... ) 
	local battleRecord = _battleRecord
	if not battleRecord then
		local battleRecordTable = _tBattleRecord or String2Table(_battleRecordString)
		if not battleRecordTable then
			return nil
		end
		
		-- 从Table中加载战斗数据
		battleRecord = BattleRecord()
		battleRecord:Load(battleRecordTable)
		battleRecord.isRealTime = false
	end
	-- 战斗模拟初始化
	self:Initialize(battleRecord)

	-- 战斗开始
	gBattleManager:BeginBattle()

	-- 驱动战斗帧
	local time = os.clock()
	while (gBattleManager.battleState ~= BattleState.END) do
		self:Update(Constants.BATTLE_FRAME_TIME)
	end
	warn('Battle Time', os.clock() - time)
	
	-- 返回战斗结果
	return gBattleResult.instanceContent
end

export('BattleMain', BattleMain)