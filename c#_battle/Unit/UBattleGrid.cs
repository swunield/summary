using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class LUBattleGrid
{
    public static int BindTower(int gridId, int prefabNameId, int prefabFolderId, int star, int eventNameId1 = 0, int eventNameId2 = 0)
    {
        var grid = ObjectCache.GetComponent<UBattleGrid>(gridId);
        if (grid == null)
        {
            return 0;
        }
        var tower = grid.BindTower(prefabNameId, prefabFolderId, GameStrings.Get(eventNameId1), GameStrings.Get(eventNameId2));
        if (tower == null)
        {
            return 0;
        }
        tower.SetLevel(star);
        tower.unitId = tower.GetInstanceID();
        return tower.unitId;
    }

    public static int BindTower(int gridId, int towerUnitId, bool force = false, int eventNameId1 = 0, int eventNameId2 = 0)
    {
        var grid = ObjectCache.GetComponent<UBattleGrid>(gridId);
        if (grid == null)
        {
            return 0;
        }
        var tower = ObjectCache.GetComponent<UBattleTower>(towerUnitId);
        if (tower == null)
        {
            return 0;
        }
        grid.BindTower(tower, force, GameStrings.Get(eventNameId1), GameStrings.Get(eventNameId2));
        return towerUnitId;
    }

    public static void UnBindTower(int gridId, int eventNameId)
    {
        ObjectCache.GetComponent<UBattleGrid>(gridId)?.UnBindTower(GameStrings.Get(eventNameId));
    }

    public static void FireUnitEvent(int gridId, int eventNameId)
    {
        ObjectCache.GetComponent<UBattleGrid>(gridId)?.FireUnitEvent(GameStrings.Get(eventNameId));
    }

    public static void ShowCover(int gridId, bool isShow, int eventNameId)
    {
        ObjectCache.GetComponent<UBattleGrid>(gridId)?.ShowCover(isShow, GameStrings.Get(eventNameId));
    }
}

[SLua.CustomLuaClass]
public class UBattleGrid : UBattleUnit
{
    [SerializeField]
    private int _index = 0;
    public int index { get { return _index; } set { _index = value; } }

    [SerializeField]
    private GameObject _objGrid;
    public GameObject objGrid { get { return _objGrid; } }

    [SerializeField]
    private UBattlePlayer _battlePlayer;
    public UBattlePlayer battlePlayer { get { return _battlePlayer; } }

    [SerializeField]
    private UBattleTowerContainer _towerContainer;
    public UBattleTowerContainer towerContainer { get { return _towerContainer; } }

    protected override void OnUnitIdChange(int value)
    {
    }

    protected override void Awake()
    {
        base.Awake();

        this.unitId = this.gameObject.GetInstanceID();
    }

    public UBattleTower BindTower(int prefabNameId, int prefabFolderId, string eventName1 = "", string eventName2 = "")
    {
        var uTower = towerContainer.BindTower(prefabNameId, prefabFolderId, false);
        if (uTower == null)
        {
            return null;
        }
        FireUnitEvent(eventName1);
        FireUnitEvent(eventName2);
        return uTower;
    }

    public void BindTower(UBattleTower uTower, bool force = false, string eventName1 = "", string eventName2 = "")
    {
        towerContainer.BindTower(uTower, force);
        FireUnitEvent(eventName1);
        FireUnitEvent(eventName2);
    }

    public void UnBindTower(string eventName = "OnTowerLeave")
    {
        FireUnitEvent(eventName);
        towerContainer.UnBindTower();
    }

    public void ShowCover(bool isShow)
    {
        ShowCover(isShow, "");
    }

    public void ShowCover(bool isShow, string eventName)
    {
        towerContainer.ShowCover(isShow);
        towerContainer.FireTowerEvent(eventName);
        FireUnitEvent(eventName);
    }

    public void SetGrey(float factor)
    {
        towerContainer?.SetGrey(factor);
    }

    public override void MoveSortingLayerToTop()
    {
        towerContainer?.MoveSortingLayerToTop();
    }

    public override void RestoreSortingLayer()
    {
        towerContainer?.RestoreSortingLayer();
    }

    public void FireTowerEvent(string eventName)
    {
        towerContainer.tower?.FireUnitEvent(eventName);
    }

    public void FireTowerEvent(SLua.LuaTable eventList)
    {
        towerContainer.tower?.FireUnitEvent(eventList);
    }

    public UBattleTower GetUBattleTower()
    {
        return towerContainer.tower;
    }

    public override void SetUnitId(int unitId)
    {
        if (towerContainer.tower != null)
        {
            towerContainer.tower.unitId = unitId;
        }
    }

    public void FirePlayerEvent(string name)
    {
        battlePlayer?.FireUnitEvent(name);
    }

    public void Restore()
    {
        towerContainer.Restore();
    }
}
