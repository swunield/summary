using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameObjectPool : MonoBehaviour
{
    private static GameObjectPool _instance;
    public static GameObjectPool INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = GameObject.FindObjectOfType<GameObjectPool>();
                if (_instance != null)
                {
                    _instance.gameObject.SetActive(false);
                }
            }
            if (_instance == null)
            {
                _instance = new GameObject("GameObjectPool").AddComponent<GameObjectPool>();
                _instance.gameObject.SetActive(false);
            }
            return _instance;
        }
    }

    public static void Destroy()
    {
        if (_instance != null)
        {
            GameObject.DestroyImmediate(_instance.gameObject);
        }
        _instance = null;
    }

    public static void ReleaseAll(string prefabName)
    {
        if (_instance != null)
        {
            _instance.ReleasePoolAll(prefabName);
        }
    }

    public static void ReleaseObject(GameObject obj)
    {
        if (_instance != null)
        {
            _instance.Release(obj);
        }
    }

    public static void Clear(string prefabName)
    {
        if (_instance == null)
        {
            return;
        }
        if (string.IsNullOrEmpty(prefabName))
        {
            _instance.ClearAll();
            return;
        }
        _instance.ClearPool(prefabName);
    }

    [FieldLabel("预制体目录")]
    public string prefabFolder = "ui/other/prefabs/";

    private Dictionary<string, FTPool<PoolGameObject>> _poolMap = new Dictionary<string, FTPool<PoolGameObject>>();
    private Dictionary<string, Transform> _poolTransformMap = new Dictionary<string, Transform>();
    private Dictionary<string, Action<PoolGameObject>> _resetActionMap = new Dictionary<string, Action<PoolGameObject>>();

    private void Awake()
    {
        _instance = this;
        GameObject.DontDestroyOnLoad(this);
    }

    private void OnDestroy()
    {
        ClearAll();
        _instance = null;
    }

    public void Initialize()
    {

    }

    public void ClearAll()
    {
        foreach (var key in _poolMap.Keys)
        {
            var pool = _poolMap[key];
            if (pool != null)
            {
                pool.Destroy();
            }
        }
        _poolMap.Clear();
        _resetActionMap.Clear();
    }

    public void ClearPool(string prefabName)
    {
        if (string.IsNullOrEmpty(prefabName))
        {
            ClearAll();
            return;
        }
        if (_poolMap.ContainsKey(prefabName))
        {
            _poolMap[prefabName].Destroy();
            _poolMap.Remove(prefabName);
        }
        if (_resetActionMap.ContainsKey(prefabName))
        {
            _resetActionMap.Remove(prefabName);
        }
    }

    public void ReleaseAll()
    {
        foreach (var key in _poolMap.Keys)
        {
            var pool = _poolMap[key];
            if (pool != null)
            {
                pool.ReleaseAll();
            }
        }
    }

    public FTPool<PoolGameObject> GetPool(string prefabName)
    {
        if (!_poolMap.ContainsKey(prefabName))
        {
            return null;
        }
        return _poolMap[prefabName];
    }

    public void PreRequest(string prefabName, int count)
    {
        var objList = new List<GameObject>();
        for (int i = 0; i < count; i++)
        {
            objList.Add(Request(prefabName, true).gameObject);
        }
        foreach (var obj in objList)
        {
            Release(obj);
        }
    }

    public PoolGameObject Request(string prefabName)
    {
        return Request(prefabName, false);
    }

    public PoolGameObject Request(string prefabName, bool forceAdd)
    {
        if (!LuaManager.GameRunning)
        {
            return null;
        }

        prefabName = prefabName.Replace(prefabFolder, "").Replace(".prefab", "");

        if (!this._poolMap.ContainsKey(prefabName) && !forceAdd)
        {
            return null;
        }

        if (!this._poolMap.ContainsKey(prefabName))
        {
            this._poolMap.Add(prefabName, new FTPool<PoolGameObject>().SetNewItemListener(() =>
            {
                var obj = GameObject.Instantiate<GameObject>(GameResLoader.INSTANCE.LoadRes(prefabFolder + prefabName + ".prefab", typeof(GameObject)) as GameObject, this.transform);
                var poolObj = obj.GetComponent<PoolGameObject>();
                if (poolObj == null)
                {
                    poolObj = obj.AddComponent<PoolGameObject>();
                }
                poolObj.prefabName = prefabName;
                return poolObj;
            }).SetFreeItemListener((PoolGameObject poolObj) =>
            {
                var poolTransform = this._poolTransformMap[poolObj.prefabName];
                if (poolTransform != null)
                {
                    if (poolObj.poolContainer != null)
                    {
                        poolObj.poolContainer.RomovePoolObject(poolObj);
                    }

                    poolObj.FireFreeEvent();
                    poolObj.transform.SetParent(poolTransform, false);
                    poolObj.poolContainer = null;
                }
            }).SetBusyItemListener((PoolGameObject poolObj) =>
            {
                poolObj.FireBusyEvent();
                ResetPoolGameObject(poolObj);
            }).SetDestroyItemListener((PoolGameObject poolObj) =>
            {
                if (poolObj != null)
                {
                    GameObject.Destroy(poolObj.gameObject);
                }
            }));
        }

        if (!_poolTransformMap.ContainsKey(prefabName))
        {
            var poolTransform = new GameObject(prefabName).transform;
            poolTransform.SetParent(this.transform);
            this._poolTransformMap.Add(prefabName, poolTransform);
        }

        var item = this._poolMap[prefabName].Request();
        return item;
    }

    public void Release(GameObject obj)
    {
        if (obj == null)
        {
            return;
        }
        var poolObj = obj.GetComponent<PoolGameObject>();
        if (poolObj == null)
        {
            return;
        }
        if (!this._poolMap.ContainsKey(poolObj.prefabName))
        {
            return;
        }
        this._poolMap[poolObj.prefabName].Release(poolObj);
    }

    public void ReleasePoolAll(string prefabName)
    {
        if (!this._poolMap.ContainsKey(prefabName))
        {
            return;
        }
        this._poolMap[prefabName].ReleaseAll();
    }

    public void RegisterResetListener(string prefabName, Action<PoolGameObject> listener)
    {
        if (string.IsNullOrEmpty(prefabName) || listener == null)
        {
            return;
        }
        _resetActionMap[prefabName] = listener;
    }

    public void ResetPoolGameObject(PoolGameObject poolObj)
    {
        if (poolObj == null)
        {
            return;
        }
        if (!_resetActionMap.ContainsKey(poolObj.prefabName))
        {
            return;
        }
        var resetAction = _resetActionMap[poolObj.prefabName];
        if (resetAction != null)
        {
            resetAction(poolObj);
        }
    }

    public bool IsSamePrefab(PoolGameObject poolObj, string checkPrefabName)
    {
        if (poolObj == null)
        {
            return false;
        }
        checkPrefabName = checkPrefabName.Replace(prefabFolder, "").Replace(".prefab", "");
        return checkPrefabName == poolObj.prefabName;
    }
}
