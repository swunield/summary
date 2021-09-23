using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[SLua.CustomLuaClass]
public class LUBattleCollider
{
    public static int Create(int unitId, int prefabNameId, int prefabFolderId, int objParentId, float posX, float posY, float zFactor, int direction, float logicPosition, int ownerUnitId, float pendingTime)
    {
        var objParent = ObjectCache.GetComponent<CacheObject>(objParentId);
        if (objParent == null)
        {
            return 0;
        }
        var ownerUnit = ObjectCache.GetComponent<UBattleUnit>(ownerUnitId);
        if (ownerUnit == null)
        {
            return 0;
        }

        var prefabName = GameStrings.Get(prefabNameId);
        var prefabFolder = GameStrings.Get(prefabFolderId);
        var uCollider = GameObjectPool.INSTANCE.RequestComponent<UBattleCollider>(prefabName, prefabFolder, true);
        return Init(uCollider, objParent.transform, unitId, posX, posY, zFactor, direction, logicPosition, ownerUnit, pendingTime);
    }

    private static int Init(UBattleCollider uCollider, Transform transParent, int unitId, float posX, float posY, float zFactor, int direction, float logicPosition, UBattleUnit uOwnerUnit, float pendingTime)
    {
        uCollider = LUBattleUnit.Init(uCollider, unitId, false);
        if (uCollider == null)
        {
            return 0;
        }
        uCollider.transform.SetParent(transParent, false);
        uCollider.SetPosition(posX, posY, zFactor, direction, logicPosition);
        if (!uCollider.FireMissile(uOwnerUnit, pendingTime))
        {
            uCollider.Begin();
        }
        return unitId;
    }
}


public class UBattleCollider : UBattleUnit
{
    [SerializeField]
    private GameObjectPoolContainer _effectContainer = null;

    public bool FireMissile(UBattleUnit uOwnerUnit, float pendingTime)
    {
        if (_effectContainer == null || uOwnerUnit == null || pendingTime <= 0)
        {
            return false;
        }
        _effectContainer.Request();
        if (_effectContainer.poolObjectList.Count == 0)
        {
            return false;
        }
        var objMissile = _effectContainer.poolObjectList[0];
        var missileEffect = objMissile?.GetComponent<UBattleEffect>();
        if (missileEffect == null)
        {
            return false;
        }
        missileEffect.Fire(uOwnerUnit, _effectContainer.transform.position, pendingTime, null);
        return true;
    }
}
