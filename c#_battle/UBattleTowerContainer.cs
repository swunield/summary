using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleTowerContainer : MonoBehaviour
{
    [SerializeField]
    private UBattleGrid _battleGrid;
    public UBattleGrid battleGrid { get { return _battleGrid; } }

    private UBattleTower _tower;
    public UBattleTower tower { get { return _tower; } set { _tower = value; } }

    public void BindTower(GameObject objTower, bool force = false)
    {
        if (objTower == null) 
        {
            return;
        }

        var uTower = objTower.GetComponent<UBattleTower>();
        BindTower(uTower, force);
    }

    public void BindTower(UBattleTower uTower, bool force = false)
    {
        if ((!force && tower != null) || uTower == null)
        {
            return;
        }

        tower = uTower;
        tower.battleGrid = battleGrid;
        uTower.transform.SetParent(this.transform, false);
    }

    public void UnBindTower()
    {
        if (tower == null)
        {
            return;
        }

        GameObjectPool.ReleaseObject(tower.gameObject);
        tower.battleGrid = null;
        tower = null;
    }

    public UBattleTower BindTower(int prefabNameId, int prefabFolderId, bool forceBind)
    {
        var prefabName = GameStrings.Get(prefabNameId);
        var prefabFolder = GameStrings.Get(prefabFolderId);
        return BindTower(prefabName, prefabFolder, forceBind);
    }

    public UBattleTower BindTower(string prefabName, string prefabFolder)
    {
        return BindTower(prefabName, prefabFolder, false);
    }

    public UBattleTower BindTower(string prefabName, string prefabFolder, bool forceBind)
    {
        if (tower != null)
        {
            if (!forceBind)
            {
                return tower;
            }
            else
            {
                UnBindTower();
            }
        }

        var uTower = GameObjectPool.INSTANCE.RequestComponent<UBattleTower>(prefabName, prefabFolder, true);
        uTower = LUBattleUnit.Init(uTower, 0);
        if (uTower == null)
        {
            return null;
        }
        BindTower(uTower);
        return uTower;
    }

    public void ShowCover(bool isShow)
    {
        tower?.ShowCover(isShow);
    }

    public void SetGrey(float factor)
    {
        tower?.SetGrey(factor);
    }

    public void MoveSortingLayerToTop()
    {
        tower?.MoveSortingLayerToTop();
    }

    public void RestoreSortingLayer()
    {
        tower?.RestoreSortingLayer();
    }

    public void FireTowerEvent(string eventName)
    {
        tower?.FireUnitEvent(eventName);
    }

    public void Restore()
    {
        UnBindTower();
    }
}
