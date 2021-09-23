using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public class LUBattleMonster
{
    public static int Create(int unitId, int prefabNameId, int prefabFolderId, int objParentId)
    {
        var objParent = ObjectCache.GetComponent<CacheObject>(objParentId);
        if (objParent == null)
        {
            return 0;
        }
        var prefabName = GameStrings.Get(prefabNameId);
        var prefabFolder = GameStrings.Get(prefabFolderId);
        var uMonster = GameObjectPool.INSTANCE.RequestComponent<UBattleMonster>(prefabName, prefabFolder, true, objParent.transform);
        uMonster = LUBattleUnit.Init(uMonster, unitId);
        if (uMonster == null)
        {
            return 0;
        }
        return unitId;
    }

    public static void UpdateMonster(int unitId, float x, float y, float zFactor, int direction, float logicPosition, float hpPercent, float timeScale)
    {
        var monster = ObjectCache.GetComponent<UBattleMonster>(unitId);
        if (monster == null)
        {
            return;
        }
        monster.SetPosition(x, y, zFactor, direction, logicPosition);
        if (hpPercent != -1)
        {
            monster.UpdateHP(hpPercent);
        }
        if (timeScale != -1)
        {
            monster.SetTimeScale(timeScale);
        }
    }

    public static void SetPosition(int unitId, float x, float y, float zFactor, int direction, float logicPosition)
    {
        var monster = ObjectCache.GetComponent<UBattleMonster>(unitId);
        if (monster == null)
        {
            return;
        }
        monster.SetPosition(x, y, zFactor, direction, logicPosition);
    }

    public static void UpdateHP(int unitId, float progress)
    {
        var monster = ObjectCache.GetComponent<UBattleMonster>(unitId);
        if (monster == null)
        {
            return;
        }
        monster.UpdateHP(progress);
    }

    public static void SetTimeScale(int unitId, float timeScale)
    {
        var monster = ObjectCache.GetComponent<UBattleMonster>(unitId);
        if (monster == null)
        {
            return;
        }
        monster.SetTimeScale(timeScale);
    }
}

public class UBattleMonster : UBattleUnit
{
    [SerializeField]
    private Canvas _canvas = null;

    [SerializeField]
    private Image _imgHP = null;

    [SerializeField]
    private List<SpineHelper> _autoRotateSpineList = new List<SpineHelper>();

    [SerializeField]
    private List<SpineHelper> _timeScaleSpineList = new List<SpineHelper>();

    [SerializeField]
    private CanvasGroup _canvasGroup = null;

    protected override void Awake()
    {
        base.Awake();

        if (_canvas != null)
        {
            _canvas.worldCamera = Camera.main;
            if (_canvasGroup == null)
            {
                _canvasGroup = _canvas.GetComponent<CanvasGroup>();
            }
        }
    }

    public override void SetPosition(float x, float y, float zFactor, int direction, float logicPosition)
    {
        base.SetPosition(x, y, zFactor, direction, logicPosition);

        for (int i = 0; i < _autoRotateSpineList.Count; i++)
        {
            var spine = _autoRotateSpineList[i];
            spine.UpdateDirection(direction);
        }
    }

    public void UpdateHP(float progress)
    {
        _canvasGroup.alpha = 1;
        _imgHP.fillAmount = progress;
    }

    public void ShowDamage(float damage, string prefabName, string prefabFolder, string boneName = "")
    {
        var uDamage = GameObjectPool.INSTANCE.RequestComponent<UBattleDamage>(prefabName, prefabFolder, true, _canvas.transform);
        if (uDamage == null)
        {
            return;
        }
        using (zstring.Block())
        {
            uDamage.txtDamage.text = zstring.Format("{0}", damage).Intern();
        }
        boneName = string.IsNullOrEmpty(boneName) ? "head" : boneName;
        uDamage.transform.position = GetBonePosition(boneName);
    }

    public void SetTimeScale(float timeScale)
    {
        for (int i = 0; i < _timeScaleSpineList.Count; i++)
        {
            _timeScaleSpineList[i]?.SetTimeScale(timeScale);
        }
    }
}
