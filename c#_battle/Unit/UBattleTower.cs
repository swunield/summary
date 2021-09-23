using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[SLua.CustomLuaClass]
public class LUBattleTower
{
    public static void Fire(int unitId, int index, int targetUnitId, int eventNameId)
    {
        var tower = ObjectCache.GetComponent<UBattleTower>(unitId);
        if (tower == null)
        {
            return;
        }
        var targetUnit = ObjectCache.GetComponent<UBattleUnit>(targetUnitId);
        if (targetUnit == null)
        {
            return;
        }
        tower.Fire(index, targetUnit, GameStrings.Get(eventNameId));
    }

    public static void SetTimeScale(int unitId, float timeScale)
    {
        ObjectCache.GetComponent<UBattleTower>(unitId)?.SetTimeScale(timeScale);
    }

    public static void FireBaseEvent(int unitId, string eventName)
    {
        ObjectCache.GetComponent<UBattleTower>(unitId)?.FireBaseEvent(eventName);
    }
}

// 塔
[SLua.CustomLuaClass]
public class UBattleTower : UBattleUnit
{
    [SerializeField]
    private int _index = 0;
    private int index { get { return _index; } set { _index = value; } }

    [SerializeField]
    private int _towerId = 0;
    private int towerId { get { return _towerId; } set { _towerId = value; } }

    [SerializeField]
    private List<SpineHelper> _autoRotateSpineList = new List<SpineHelper>();

    [SerializeField]
    private List<SpineHelper> _timeScaleSpineList = new List<SpineHelper>();
    public List<SpineHelper> timeScaleSpineList { get { return _timeScaleSpineList; } }

    [SerializeField]
    private UBattleTowerBase _uTowerBase = null;
    public UBattleTowerBase uTowerBase { get { return _uTowerBase; } set { _uTowerBase = value; } }

    [SerializeField]
    private Transform _boneMissile = null;
    public Transform boneMissile { get { return _boneMissile; } set { _boneMissile = value; } }

    [SerializeField]
    private List<RendererMaterialItem> _materialItems = new List<RendererMaterialItem>();

    private UBattleGrid _battleGrid = null;
    public UBattleGrid battleGrid { get { return _battleGrid; } set { _battleGrid = value; } }

    public void ShowCover(bool isShow = true)
    {
        foreach(var item in _materialItems)
        {
            item.SetFloat("_CoverAlpha", isShow ? 0.58f : 0);
        }
    }

    public void SetGrey(float factor)
    {
        foreach (var item in _materialItems)
        {
            item.SetFloat("_Grey", factor);
        }
    }

    public void SetLevel(int level)
    {
        uTowerBase?.SetLevel(level);
    }
    
    public void SetTimeScale(float timeScale)
    {
        foreach (var spine in _timeScaleSpineList)
        {
            spine.SetTimeScale(timeScale);
        }
    }

    public void Fire(int index, UBattleUnit uUnit, string eventName)
    {
        _uTowerBase?.Fire(index);

        if (_autoRotateSpineList.Count == 0)
        {
            FireUnitEvent(eventName);
            return;
        }
        var startPos = GetBonePosition("center");
        var endPos = uUnit.GetBonePosition("body");
        var angle = UGameTools.GetPosAngle(startPos, endPos);
        for (int i = 0; i < _autoRotateSpineList.Count; i++)
        {
            var spine = _autoRotateSpineList[i];
            spine.UpdateDirectionByAngle(angle);
            if (i == 0)
            {
                _curDirectionAngle = spine.GetCurDirectionAngle();
                if (_boneMissile != null)
                {
                    _boneMissile.position = spine.GetBulletWorldPosition();
                }
            }
        }
        FireUnitEvent(eventName);
    }

    public void FirePlayerEvent(string eventName)
    {
        if (battleGrid != null)
        {
            battleGrid.battlePlayer?.FireUnitEvent(eventName);
        }
    }

    public void FireBaseEvent(string eventName)
    {
        uTowerBase?.uiEvent?.FireUIEvent(eventName);
    }
}
