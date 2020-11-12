---
--- class BattlePage
-- @classmod BattlePage
class('BattlePage', PageBase)

---Constructor
function BattlePage:ctor( page, ... )
	self.super = Super(page, ...)

	self.objDragTower = false			-- 拖动的塔物件
	self.dragTowerIndex = 0				-- 拖动的塔索引
	self.dragOriginPos = false 			-- 拖动的塔初始位置
	self.allCoveredTowerList = {}		-- 所有遮盖的塔
	self.isTowerFlying = false 			-- 塔是否正在飞

	self.myGBPlayer = false 			-- 玩家自己
	self.myTowerList = {}				-- 玩家塔列表
	self.enemyGBPlayer = false

	self.isMagicEnable = false 			-- 魔法禁用
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
		['ClickMagic'] = function( _index, ... )
			GBMain.INSTANCE():ExecMagic(ToInt(_index))
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
		end
	}

	UIUtils.AddChildClickCallBack(self, 'btn_home', function( ... )
		-- 同房间服断开连接
		gGameNetMgr:DisConnect(NetSessionType.ROOM)
		gGameClient:JumpToScene('Home')
	end)

	-- 己方塔注册拖动事件
	for i = 1, 15 do
		local towerIndex = i
		local childName = string.format('pnl_battle/pnl_field/pnl_mine/pnl_bg/pnl_tower/item_%d/pnl_tower/pnl_tower', i)
		local objTower = self:GetChild(childName)
		local tower = { towerIndex = towerIndex, objTower = objTower, objContainer = objTower.transform.parent.gameObject }
		table_insert(self.myTowerList, tower)

		UIUtils.SetObjectPressCallBack(objTower, nil, function( ... )
			self:OnTowerPressDown(towerIndex, objTower)
		end, function( ... )
			self:OnTowerPressUp(towerIndex, objTower)
		end)

		UIUtils.AddObjectDragEvent(objTower, function( _pointEvent )
			self:OnTowerDragBegin(towerIndex, _pointEvent)
		end, function( _pointEvent )
			self:OnTowerDraging(towerIndex, _pointEvent)
		end, function( _pointEvent )
			self:OnTowerDragEnd(towerIndex, _pointEvent)
		end)
	end
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
	self.isTowerFlying = false

	self.myGBPlayer = false
	self.enemyGBPlayer = false

	self.isMagicEnable = false

	-- 初始化战斗
	self:InitBattle()
end

function BattlePage:OnHide( ... )
	-- 销毁战斗
	self:DestroyBattle()

	self.objDragTower = false
	self.dragTowerIndex = 0
	self.dragOriginPos = false
	self.allCoveredTowerList = {}
	self.isTowerFlying = false

	self.myGBPlayer = false
	self.enemyGBPlayer = false
end

function BattlePage:OnPageRefresh( _key, _data, ... )
	if _key == 'Stat' then
		local player = self.myGBPlayer.player
		local stat = player.stat
		local firstMonsterSpeed = player.firstMonster and player.firstMonster:GetSpeed() or 0
		local firstMonsterDefence = player.firstMonster and player.firstMonster:GetDefence() or 0
		local statContent = string.format('   头部怪物 速度 %d  护甲 %d\n   子弹总计 %d  丢失子弹 %d  子弹丢失率 %.1f%%\n   伤害总计 %d  每秒伤害 %d\n   魔法次数 %d  魔法 %s\n   当前怪物 %d  总计怪物 %d  击杀怪物 %d  缓冲怪物 %d\n   当前SP %d  总计SP %d  怪物SP %d  抽卡SP %d  魔法SP %d\n   当前兵线 %d\n   当前血量 %d\n', 
								firstMonsterSpeed, firstMonsterDefence, stat.totalMissile, stat.totalMissMissile, stat.totalMissMissile * 100 / stat.totalMissile, stat.totalDamage, stat.damagePerSecond, 
								stat.totalMagicTimes, stat.magicList, stat.totalMonster, stat.totalMonster + stat.totalKillMonster, stat.totalKillMonster, stat.pendingMonsterCount,
								player.point, stat.totalPoint, stat.totalMonsterPoint, stat.totalRollPoint, stat.totalMagicPoint,
								player.firstMonster and player.firstMonster.position or 0, player.curHP)
		UIUtils.SetChildText(self, 'pnl_debug/pnl_self/txt', statContent)
		
		player = self.enemyGBPlayer.player
		stat = player.stat
		firstMonsterSpeed = player.firstMonster and player.firstMonster:GetSpeed() or 0
		firstMonsterDefence = player.firstMonster and player.firstMonster:GetDefence() or 0
		statContent = string.format('   当前血量 %d\n   当前兵线 %d\n   当前SP %d  总计SP %d  怪物SP %d  抽卡SP %d  魔法SP %d\n   当前怪物 %d  总计怪物 %d  击杀怪物 %d  缓冲怪物 %d\n   魔法次数 %d  魔法 %s\n   伤害总计 %d  每秒伤害 %d\n   子弹总计 %d  丢失子弹 %d  子弹丢失率 %.1f%%\n   头部怪物 速度 %d  护甲 %d', 
								player.curHP, player.firstMonster and player.firstMonster.position or 0, player.point, stat.totalPoint, stat.totalMonsterPoint, stat.totalRollPoint, stat.totalMagicPoint,
								stat.totalMonster, stat.totalMonster + stat.totalKillMonster, stat.totalKillMonster, stat.pendingMonsterCount, stat.totalMagicTimes, stat.magicList, 
								stat.totalDamage, stat.damagePerSecond, stat.totalMissile, stat.totalMissMissile, stat.totalMissMissile * 100 / stat.totalMissile, firstMonsterSpeed, firstMonsterDefence)
		UIUtils.SetChildText(self, 'pnl_debug/pnl_enemy/txt', statContent)
	elseif _key == 'UpdatePoint' then
		self:UpdatePoint(_data.point, _data.costPoint)
	elseif _key == 'AddMagic' then
		self:AddMagic(_data.magicIndex, _data.magicData)
	elseif _key == 'UpdateMagic' then
		self:UpdateMagic(_data.magicIndex, _data.magicData)
	elseif _key == 'ServerFrame' then
		UIUtils.SetChildText(self, 'pnl_debug/txt_info', string.format('T[%s] [%s] S[%d-%d-%d] [%d]', FormatTime(ToInt(gamebattle.gBattleTime / 1000)), FormatTime(ToInt((gamebattle.gBattleLogic.roundDuration - (gamebattle.gBattleTime - gamebattle.gBattleLogic.roundStartTime)) / 1000)), _data.ServerFrame, _data.LocalFrame, 
			_data.ServerFrame - _data.LocalFrame, gamebattle.gBattleManager.battleState))
	elseif _key == 'BeginMagicCD' then
		UIUtils.SelectActionSelector(self, 'BeginMagicCD_All')
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

	GBMain.INSTANCE():Initialize(gUIDataMgr:GetUserId(), battleRecord, UIUtils.GetChildComponent(self, 'pnl_battle/pnl_field', 'UBattle'))

	-- 单机模式
	if not battleRecord.isRealTime then
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
	UIUtils.SetChildText(self, 'pnl_battle/pnl_operation/pnl_up/pnl_info_l/pnl_point/txt', _point)
	UIUtils.SetChildText(self, 'pnl_battle/pnl_operation/pnl_up/pnl_chouka/btn_chouka/txt_cost', _costPoint)
	if not self.isMagicEnable and _costPoint ~= 10 then
		UIUtils.SelectActionSelector(self, 'BeginMagicCD_All')
		self.isMagicEnable = true
	end
end

function BattlePage:OnTowerPressDown( _towerIndex, _objTower, ... )
	local pressTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not pressTower then
		return
	end

	for i = 1, #self.myTowerList do
		local myTower = self.myTowerList[i]
		local tower = self.myGBPlayer:GetGBTowerByPos(myTower.towerIndex)
		if tower and i ~= _towerIndex and not pressTower:CanMerge(tower) then
			table_insert(self.allCoveredTowerList, myTower.objTower)
			UIUtils.SelectChildActionSelector(myTower.objTower, 'tower', 'FadeInCover')
		end
	end
end

function BattlePage:OnTowerPressUp( _towerIndex, _objTower, ... )
	for i = 1, #self.allCoveredTowerList do
		UIUtils.SelectChildActionSelector(self.allCoveredTowerList[i], 'tower', 'FadeOutCover')
	end
	self.allCoveredTowerList = {}
end

function BattlePage:OnTowerDragBegin( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if self.isTowerFlying or (self.objDragTower and self.objDragTower ~= _pointEvent.pointerDrag) then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		return
	end

	self.dragTowerIndex = _towerIndex
	self.objDragTower = _pointEvent.pointerDrag

	UIUtils.SetObjectParent(self.objDragTower, self, true)
	self.dragOriginPos = self.objDragTower.transform.localPosition

	UIUtils.SetObjectPosition(self.objDragTower, _pointEvent.position.x, _pointEvent.position.y)
	if dragTower.tower then
		UIUtils.SetChildText(self, 'pnl_debug/txt_tower', string.format('Tower [%d] [%s] 攻击[%d] 攻速[%d] 暴击[%d] 暴倍[%d]', dragTower.tower.towerId, dragTower.tower.unitId, dragTower.tower:GetAttack(), dragTower.tower:GetAtkSpeed(), dragTower.tower:GetAttribute(AttriType.CRITICAL), dragTower.tower:GetAttribute(AttriType.CRITICALSCALE)))
		local bufferList = dragTower.tower.carryBufferList
		for i = 1, #bufferList do
			local buffer = bufferList[i]
			for n = 1, #buffer.layerList do
				local layer = buffer.layerList[n]
				warn('BufferLayer', dragTower.posIndex, buffer.bufferRes.id, gameutils.JSON:encode(layer.valueList), layer.ownerUnit.posIndex and layer.ownerUnit.posIndex or 0)
			end
		end
	end
end

function BattlePage:OnTowerDraging( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if self.isTowerFlying or not self.objDragTower or self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	UIUtils.SetObjectPosition(self.objDragTower, _pointEvent.position.x, _pointEvent.position.y)
end

function BattlePage:OnTowerDragEnd( _towerIndex, _pointEvent, ... )
	-- 禁止同时拖动多个
	if self.isTowerFlying or not self.objDragTower or self.objDragTower ~= _pointEvent.pointerDrag then
		return
	end

	local dragTower = self.myGBPlayer:GetGBTowerByPos(_towerIndex)
	if not dragTower then
		UIUtils.SetObjectParent(self.objDragTower, self.myTowerList[_towerIndex].objContainer, false, 0, 0)
		self.objDragTower = false
		return
	end

	-- 找到目标塔位置
	local dragEndPosition = self.objDragTower.transform.position
	local dragEndIndex = self.dragTowerIndex
	for i = 1, #self.myTowerList do
		if i ~= self.dragTowerIndex then
			local towerTrans = self.myTowerList[i].objTower.transform
			local endPos = towerTrans:InverseTransformPoint(dragEndPosition)
			if towerTrans.rect:Contains(endPos) then
				dragEndIndex = i
				break
			end
		end
	end

	local dragEndTower = self.myGBPlayer:GetGBTowerByPos(dragEndIndex)
	if not dragEndTower or not dragTower:CanMerge(dragEndTower) then
		-- 不能合成，飞回原地
		self.isTowerFlying = true
		local curPosition = self.objDragTower.transform.localPosition
		GOUtils.TweenMoveTo(self.objDragTower, curPosition.x, curPosition.y, self.dragOriginPos.x, self.dragOriginPos.y, 0.1, 0, nil, true, function( ... )
			UIUtils.SetObjectParent(self.objDragTower, self.myTowerList[_towerIndex].objContainer, false, 0, 0)
			self.isTowerFlying = false
			self.objDragTower = false
		end)
		return
	end

	-- 直接放回原地
	UIUtils.SetObjectParent(self.objDragTower, self.myTowerList[_towerIndex].objContainer, false, 0, 0)
	self.objDragTower = false

	-- 执行合成
	GBMain.INSTANCE():ExecMerge(self.dragTowerIndex, dragEndIndex)
end

function BattlePage:AddMagic( _magicIndex, _magicData, ... )
	local magicId = _magicData.magicId
	local magicRes = self:UpdateMagic(_magicIndex, _magicData)
	if not magicRes then
		return
	end
end

function BattlePage:UpdateMagic( _magicIndex, _magicData, ... )
	local magicId = _magicData and _magicData.magicId or 0
	warn('UpdateMagic', _magicIndex, magicId)
	local magicRes = GameResMgr.GetMagicRes(magicId)
	if not magicRes then
		UIUtils.SetChildActive(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d', _magicIndex), false)
		return false
	end

	UIUtils.SetChildActive(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d', _magicIndex), true)
	UIUtils.SetChildText(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d/btn_magic/txt', _magicIndex), magicRes.name)
	UIUtils.SetChildText(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d/btn_magic/txt_cost', _magicIndex), _magicData.costPoint)
	UIUtils.SetChildActive(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d/img_block', _magicIndex), _magicData.index ~= _magicIndex)
	local color = NilDefault(BattleConstants.BATTLE_TOWER_COLOR_LIST[magicRes.name], {0, 0, 0})
	UIUtils.SetChildColor(self, string.format('pnl_battle/pnl_operation/pnl_magic/item_%d/btn_magic', _magicIndex), Color(color[1] / 255, color[2] / 255, color[3] / 255, 1))
	return magicRes
end

classend()