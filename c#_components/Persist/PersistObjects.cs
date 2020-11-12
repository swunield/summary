using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PersistObjects
{
    private static Dictionary<string, GameObject> persistMap = new Dictionary<string, GameObject>();

    public static GameObject AddPersist(string key, GameObject obj, bool forceAdd = true)
    {
        bool keyExist = persistMap.ContainsKey(key);
        if (obj == null)
        {
            if (keyExist)
            {
                return persistMap[key];
            }
            return null;
        }

        if (keyExist && !forceAdd)
        {
            if (obj != null)
            {
                GameObject.DestroyImmediate(obj);
            }
            return persistMap[key];
        }

        if (keyExist)
        {
            var objOld = persistMap[key];
            persistMap.Remove(key);
            if (objOld != null)
            {
                GameObject.DestroyImmediate(objOld);
            }
        }

        obj.name = key;
        GameObject.DontDestroyOnLoad(obj);
        persistMap.Add(key, obj);

        return obj;
    }

    public static void RemovePersist(string key)
    {
        bool keyExist = persistMap.ContainsKey(key);
        if (!keyExist)
        {
            return;
        }

        var obj = persistMap[key];
        persistMap.Remove(key);
        if (obj != null)
        {
            GameObject.DestroyImmediate(obj);
        }
    }

    public static void RemovePersist(string key, GameObject dstObj, bool needDestroy = true)
    {
        bool keyExist = persistMap.ContainsKey(key);
        if (!keyExist)
        {
            return;
        }

        var obj = persistMap[key];
        if (obj != dstObj)
        {
            return;
        }

        persistMap.Remove(key);
        if (obj != null && needDestroy)
        {
            GameObject.DestroyImmediate(obj);
        }
    }

    public static bool IsPersistKeyExist(string key)
    {
        return persistMap.ContainsKey(key);
    }

    public static GameObject GetPersist(string key)
    {
        bool keyExist = persistMap.ContainsKey(key);
        if (!keyExist)
        {
            return null;
        }
        return persistMap[key];
    }
}
