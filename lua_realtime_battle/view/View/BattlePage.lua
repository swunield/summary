---
--- class BattlePage
-- @classmod BattlePage
class('BattlePage', PageBase)

local math_floor = math.floor

---Constructor
function BattlePage:ctor( page, ... )
	self.super = Super(page, ...)

	self.objDragTower = false			-- 拖动的塔物件
	self.dragTowerIndex = 0				-- 拖动的塔索引
	self.dragOriginPos = false 			-- 拖动的塔初始位置
	self.allCoveredTowerList = {}		-- 所有遮盖的塔

	self.myGBPlayer = false 			-- 玩家自己
	self.myTowerList = {}				-- 玩家塔列表
	self.enemyGBPlayer = false

	self.battleType = BattleType.PK
end

function BattlePage:OnPageDestroy( ... )

end

function BattlePage:Init( ... )
	-- 自定义事件
	self.customEvents = {
		-- 投降
		['Surrender'] = function( ... )
			GBMain.INSTANCE():ExecSurrender()
			return false
		end,
		-- 抽卡
		['Roll'] = function( ... )
			GBMain.INSTANCE():ExecRoll()
			return false
		end,
		-- 阻塞服务端指令
		['BlockServer'] = function( ... )
			GBMain.BlockServerCommand(true)
			return false
		end,
		-- 解除阻塞服务端指令
		['UnBlockServer'] = function( ... )
			GBMain.BlockServerCommand(false)
			return false
		end,
		-- 升级
		['Upgrade'] = function( _index, ... )
			GBMain.INSTANCE():ExecUpgrade(tonumber(_index))
			return false
		end,
		-- 英雄天赋
		['ClickHero'] = function( ... )
			GBMain.INSTANCE():ExecHeroTalent()
			return false
		end
	}

	UIUtils.AddChildClickCallBack(self, 'btn_home', function( ... )
		-- 同房间服断开连接
		gGameNetMgr:DisConnect(NetSessionType.ROOM)
		gGameClient:JumpToScene('Home')
	end)
end

function BattlePage:OnGetUIGroup( _groupPath, ... )

end

function BattlePage:OnUIGroupInit( _groupPath, _luaUIGroup, ... )

end

function BattlePage:InitOBRegister( ... )

end

function BattlePage:OnShow( _data, ... )
	self.objDragTower = false
	self.dragTowerIndex = 0
	self.dragOriginPos = false
	self.allCoveredTowerList = {}

	self.myGBPlayer = false
	self.enemyGBPlayer = false

	-- 初始化战斗
	self:InitBattle()

	-- 初始界面状态
	UIUtils.SelectActionSelector(self, self.battleType == BattleType.COOP and 'OnShowCoop' or 'OnShowPk')
	UIUtils.SelectActionSelector(self, gamebattle.gBattleRecord.isLocal and 'OnShowLocal' or 'OnShowNotLocal')
	UIUtils.SelectActionSelector(self, gamebattle.gBattleRecord.isRealTime and 'OnShowRealTime' or 'OnShowNotRealTime')

	-- 刷新
	self:UpdateTowerGrade(self.myGBPlayer.player)
	self:UpdateTowerGrade(self.enemyGBPlayer.player)
	self:UpdateHeroTalent(self.myGBPlayer.player)
	self:UpdateHeroTalent(self.enemyGBPlayer.player)
end

function BattlePage:OnHide( ... )
	-- 销毁战斗
	self:DestroyBattle()

	self.objDragTower = false
	self.dragTowerIndex = 0
	self.dragOriginPos = false
	self.allCoveredTowerList = {}

	self.myGBPlayer = false
	self.enemyGBPlayer = false
end

local PageRefreshSwitcher = {
	['UpdatePoint'] = function( self, _data, ... )
		self:UpdatePoint(_data.point, _data.costPoint)
	end,
	['ServerFrame'] = function( self, _data, ... )
		UIUtils.SetChildText(self, 'pnl_debug/txt_info', string.format('T[%s] [%s] S[%d-%d-%d] [%d]', FormatTime(math_floor(gamebattle.gBattleTime / 1000)), FormatTime(math_floor((gamebattle.gBattleLogic.roundDuration - (gamebattle.gBattleTime - gamebattle.gBattleLogic.roundStartTime)) / 1000)), _data.ServerFrame, _data.LocalFrame, 
			_data.ServerFrame - _data.LocalFrame, gamebattle.gBattleManager.battleState))
	end,
	['Upgrade'] = function( self, _data, ... )
		self:UpdateTowerGrade(_data.gbPlayer.player, _data.poolIndex)
	end,
	['RefreshHeroTalentCDTime'] = function( self, _data, ... )
		self:RefreshHeroTalentCDTime(_data.playerId, _data.pastTime, _data.leftTime)
	end,
	['RoundStart'] = function( self, _data, ... )
		self:OnRoundStart(_data.duration, _data.roundNum)
	end,
	['UpdatePlayerHP'] = function( self, _data, ... )
		self:UpdatePlayerHP(_data.playerId, _data.curHP, _data.maxHP, _data.isInit)
	end,
	['OnBossEnter'] = function( self, _data, ... )
		self:OnBossEnter(_data.param1)
	end
}

function BattlePage:OnPageRefresh( _key, _data, ... )
	local switcher = PageRefreshSwitcher[_key]
	if switcher then
		switcher(self, _data)
	end
end

function BattlePage:InitBattle( ... )
	if gUIDataMgr.isFirstEnterHome then
		return
	end

	-- 战斗进场数据
	local battleRecord = gUIDataMgr.battleData:BuildBattleRecord()
	if not battleRecord then
		return
	end

	self.battleType = battleRecord.battleType

	local uBattleField = GOUtils.GetComponentWithTag('BattleField', 'UBattleField', false)
	if not uBattleField then
		return
	end

	local uBattle = uBattleField:SwitchBattle(battleRecord.battleType - 1)
	GBMain.INSTANCE():Initialize(gUIDataMgr:GetUserId(), battleRecord, uBattle)

	-- 注册格子事件
	local uMyPlayer = uBattle:GetUBattlePlayer(0)
	local allGrids = uMyPlayer.canvasGridList
	for i = 1, allGrids.Count do
		local towerIndex = i
		local objDrag = allGrids[i - 1].objDrager
		UIUtils.SetObjectPressCallBack(objDrag, nil, function( ... )
			self:OnTowerPressDown(towerIndex)
		end, function( ... )
			self:OnTowerPressUp(towerIndex)
		end)

		UIUtils.AddObjectDragEvent(objDrag, function( _pointEvent )
			self:OnTowerDragBegin(towerIndex, _pointEvent)
		end, nil, function( _pointEvent )
			self:OnTowerDragEnd(towerIndex, _pointEvent)
		end)
	end

	-- 单机模式or快照
	if not battleRecord.isRealTime or battleRecord.tSnapShot then
		warn('BeginBattle')
		GBMain.INSTANCE():BeginBattle()
	end

	self.myGBPlayer = GBMain.INSTANCE():GetMyGBPlayer()
	self.enemyGBPlayer = GBMain.INSTANCE():GetEnemyGBPlayer()
end

function BattlePage:DestroyBattle( ... )
	if not gUIDataMgr.isFirstEnterHome then
		-- 战斗销毁
		GBMain.Destroy()
	end
end

function BattlePage:UpdatePoint( _point, _costPoint, ... )
	UIUtils.SetChildText(self, 'pnl_battle/pnl_operation/pnl_mine/pnl_lvl_num/txt', _point)
	UIUtils.SetChildText(self, 'pnl_battle/pnl_operation/pnl_mine/btn_ta_up/txt_cost', _costPoint)
end

function BattlePage:OnTowerPressDown( _towerIndex, ... )
	local pressGBTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not pressGBTower then
		return
	end

	for i = 1, 15 do
		local gbTower = self.myGBPlayer:GetGBTowerByPos(i)
		if gbTower and i ~= _towerIndex and not pressGBTower:CanMerge(gbTower) then
			table.insert(self.allCoveredTowerList, gbTower)
			gbTower:ShowCover(true, 'OnShowCover')
		end
	end
end

function BattlePage:OnTowerPressUp( _towerIndex, ... )
	for i = 1, #self.allCoveredTowerList do
		self.allCoveredTowerList[i]:ShowCover(false, 'OnHideCover')
	end
	self.allCoveredTowerList = {}
end

function BattlePage:OnTowerDragBegin( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if self.objDragTower and self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		return
	end

	self.dragTowerIndex = _towerIndex
	self.objDragTower = _pointEvent.pointerDrag

	if dragTower.tower then
		UIUtils.SetChildText(self, 'pnl_debug/txt_tower', string.format('Tower [%d] [%s] 攻击[%d] 攻速[%d] 暴击[%d] 暴倍[%d]', dragTower.tower.towerId, dragTower.tower.unitId, dragTower.tower:GetAttack(), dragTower.tower:GetAtkSpeed(), dragTower.tower:GetAttribute(AttriType.CRITICAL), dragTower.tower:GetAttribute(AttriType.CRITICALSCALE)))
		local bufferList = dragTower.tower.carryBufferList
		for i = 1, #bufferList do
			local buffer = bufferList[i]
			for n = 1, #buffer.layerList do
				local layer = buffer.layerList[n]
				warn('BufferLayer', dragTower.posIndex, buffer.bufferRes.id, gameutils.JSON:encode(layer.valueList), layer.owner.unitId or 0)
			end
		end
	end
end

function BattlePage:OnTowerDragEnd( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if not self.objDragTower or self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		self.objDragTower = false
		return
	end

	-- 找到目标塔位置
	local dragEndIndex = self.myGBPlayer:GetGridIndexByPosition(self.objDragTower.transform.position)
	if dragEndIndex == 0 then
		self.objDragTower = false
		return
	end

	local dragEndTower = self.myGBPlayer:GetGBTowerByPos(dragEndIndex)
	if not dragEndTower or not dragTower:CanMerge(dragEndTower) then
		-- 不能合成，飞回原地
		self.objDragTower = false
		return
	end

	-- 直接放回原地
	self.objDragTower = false

	-- 执行合成
	GBMain.INSTANCE():ExecMerge(self.dragTowerIndex, dragEndIndex)
end

function BattlePage:UpdateTowerGrade( _player, _poolIndex, ... )
	if not _poolIndex then
		for i = 1, 5 do
			self:UpdateTowerGrade(_player, i)
		end
		return
	end
	local towerResId = _player:GetTowerResIdByPoolIndex(_poolIndex)
	local towerRes = GameResMgr.GetBattleTowerRes(towerResId)
	if not towerRes then
		return
	end
	local isMine = self:IsMyPlayer(_player.playerId)
	local grade = _player:GetTowerGrade(towerResId)
	local cost = _player:GetTowerUpgradeCostByPoolIndex(_poolIndex)
	local path = isMine and 'pnl_battle/pnl_operation/pnl_mine/pnl_tower/item_' or 'pnl_battle/pnl_operation/pnl_enemy/pnl_tower/item_'
	UIUtils.SetChildImage(self, path .. _poolIndex .. '/btn_magic/pnl_icon/icon', PainterMgr.GetPathOfTowerIcon(towerRes.iconName))
	UIUtils.SetChildText(self, path .. _poolIndex .. '/btn_magic/pnl_lvl/txt_num', cost == 0 and 'MAX' or grade)
	UIUtils.SetChildActive(self, path .. _poolIndex .. '/btn_magic/pnl_lvl/txt', cost ~= 0)
	if isMine then
		UIUtils.SetChildText(self, path .. _poolIndex .. '/btn_magic/pnl_num/txt', cost)
		UIUtils.SetChildActive(self, path .. _poolIndex .. '/btn_magic/pnl_num', cost ~= 0)
	end
end

function BattlePage:RefreshHeroTalentCDTime( _playerId, _pastTime, _leftTime, ... )
	local startPercent = _leftTime / (_pastTime + _leftTime)
	local isMine = self:IsMyPlayer(_playerId)
	local iconPath = isMine and 'pnl_battle/pnl_operation/pnl_mine/pnl_hero/btn_hero/img_cd' or 'pnl_battle/pnl_operation/pnl_enemy/pnl_hero/btn_hero/img_cd'
	UIUtils.ImageValueTo(self:GetChild(iconPath), startPercent, 0, _leftTime * 0.001, nil, false, gGBField.looper)
end

function BattlePage:UpdateHeroTalent( _player )
	local hero = _player.hero
	if not hero.heroRes then
		return
	end
	local isMine = self:IsMyPlayer(_player.playerId)
	if isMine then
		local heroTalentType = hero:GetHeroTalentType()
		UIUtils.SetChildSelectable(self, 'pnl_battle/pnl_operation/pnl_mine/pnl_hero/btn_hero/btn', heroTalentType == BattleHeroTalentType.MANUAL)
	end

	local iconPath = isMine and 'pnl_battle/pnl_operation/pnl_mine/pnl_hero/btn_hero/icon' or 'pnl_battle/pnl_operation/pnl_enemy/pnl_hero/btn_hero/icon'
	UIUtils.SetChildImage(self,  iconPath, 'image/icon/hero/' .. hero.heroRes.iconName)
end

function BattlePage:IsMyPlayer( _playerId, ... )
	return GBMain.INSTANCE():IsMyPlayer(_playerId)
end

function BattlePage:OnRoundStart( _duration, _roundNum, ... )
	_duration = _duration * 0.001
	UIUtils.TextValueTo(self:GetChild('pnl_battle/pnl_operation/pnl_enemy/pnl_right_ui/pnl_time/txt'), _duration, 0, _duration, 'MS', nil, nil, nil, gGBField.looper)

	UIUtils.SetChildActive(self, 'pnl_battle/pnl_operation/pnl_enemy/pnl_right_ui/pnl_round', _roundNum > 0)
	UIUtils.SetChildText(self, 'pnl_battle/pnl_operation/pnl_enemy/pnl_right_ui/pnl_round/txt', _roundNum)

	-- 回合提示
	if _roundNum > 0 then
		UIUtils.SetChildText(self, 'pnl_animation/battle_round/pnl/txt_num', _roundNum)
		UIUtils.SelectChildActionSelector(self, 'pnl_animation/battle_round', 'Play')
	end
end

function BattlePage:UpdatePlayerHP( _playerId, _curHP, _maxHP, _isInit, ... )
	local isMine = self:IsMyPlayer(_playerId)
	local pnlHeartPath = isMine and 'pnl_battle/pnl_operation/pnl_mine/pnl_hero/pnl_heart' or 'pnl_battle/pnl_operation/pnl_enemy/pnl_hero/pnl_heart'
	if _isInit then
		UIUtils.SelectChildActionSelector(self, pnlHeartPath, 'Init_' .. _maxHP)
	end
	_curHP = _curHP < 0 and 0 or (_curHP > _maxHP or _maxHP and _curHP)
	UIUtils.SelectChildActionSelector(self, pnlHeartPath, 'Heart_' .. _curHP)
end

function BattlePage:OnBossEnter( _bossResId, ... )
	UIUtils.SelectChildActionSelector(self, 'pnl_animation/battle_boss', 'Play')
end

classend()