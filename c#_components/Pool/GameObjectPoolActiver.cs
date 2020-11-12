using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;
using UnityEngine.Profiling;

[SLua.CustomLuaClass]
public class GameObjectPoolActiver : MonoBehaviour
{
    public static void ReleasePoolChildren(GameObject obj)
    {
        if (!LuaManager.GameRunning)
        {
            return;
        }

        if (obj == null)
        {
            return;
        }

        var containerList = obj.GetComponentsInChildren<GameObjectPoolContainer>(true);
        foreach (var container in containerList)
        {
            container.ReleasePoolContainer();
        }
    }

    public static void SetActive(GameObject obj, bool active)
    {
        if (obj == null)
        {
            return;
        }

        if (active)
        {
            obj.SetActive(true);
            return;
        }

        GameObjectPoolActiver.ReleasePoolChildren(obj);
        obj.SetActive(false);
    }

    [SLua.DoNotToLua]
    public void SetActive(bool active)
    {
        GameObjectPoolActiver.SetActive(this.gameObject, active);
    }

    [SLua.DoNotToLua]
    public void ReleasePoolChildren()
    {
        
        GameObjectPoolActiver.ReleasePoolChildren(this.gameObject);
    }
}
