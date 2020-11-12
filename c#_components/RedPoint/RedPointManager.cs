using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class RedPointManager : MonoBehaviour
{
    private static RedPointManager _instance;
    public static RedPointManager INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = GameObject.FindObjectOfType<RedPointManager>();
            }
            if (_instance == null)
            {
                _instance = new GameObject("RedPointManager").AddComponent<RedPointManager>();
            }
            return _instance;
        }
    }

    class RedPointData
    {
        public string key;
        public bool result;
        public Dictionary<string, int> filterMap;
        public Func<object, bool> checkActiveFunc;
        public List<string> childKeyList;
        public List<string> parentKeyList;
    }

    private Dictionary<string, RedPointData> _redPointDataMap = new Dictionary<string, RedPointData>();
    private Dictionary<string, List<RedPointItem>> _redPointItemMap = new Dictionary<string, List<RedPointItem>>();
    private Dictionary<string, int> _checkKeyRecord = new Dictionary<string, int>();

    public static void Destroy()
    {
        if (_instance != null)
        {
            GameObject.DestroyImmediate(_instance.gameObject);
        }
        _instance = null;
    }

    public static void BindKey(string key, Func<object, bool> activeFunc, SLua.LuaTable parentKeyList = null, SLua.LuaTable filterList = null)
    {
        RedPointManager.INSTANCE.BindKey_Internal(key, activeFunc, parentKeyList, filterList);
    }

    public static void BindPointItem(GameObject obj, string key)
    {
        RedPointManager.INSTANCE.BindPointItem_Internal(obj, key, false);
    }

    public static void BindPointItem(GameObject obj, string key, bool forceBind)
    {
        RedPointManager.INSTANCE.BindPointItem_Internal(obj, key, forceBind);
    }

    public static void UnbindPointItem(GameObject obj)
    {
        var pointItem = obj.GetComponent<RedPointItem>();
        if (pointItem == null)
        {
            return;
        }
        UnbindPointItem(pointItem);
    }

    public static void UnbindPointItem(RedPointItem pointItem)
    {
        if (_instance == null)
        {
            return;
        }

        RedPointManager.INSTANCE.UnbindPointItem_Internal(pointItem);
    }

    public static void CheckAll()
    {
        RedPointManager.INSTANCE.CheckAll_Internal();
    }

    public static void Check(string key, string filter, object checkData, bool needCheckActive = true)
    {
        RedPointManager.INSTANCE.Check_Internal(key, filter, checkData, needCheckActive, true);
    }

    private void Awake()
    {
        _instance = this;
        GameObject.DontDestroyOnLoad(this);
    }

    private void OnDestroy()
    {
        foreach (var key in _redPointDataMap.Keys)
        {
            _redPointDataMap[key].checkActiveFunc = null;
        }
        _redPointDataMap.Clear();

        foreach (var key in _redPointItemMap.Keys)
        {
            _redPointItemMap[key].Clear();
        }
        _redPointItemMap.Clear();

        _instance = null;
    }

    private void BindKey_Internal(string key, Func<object, bool> activeFunc, SLua.LuaTable parentKeyList = null, SLua.LuaTable filterList = null)
    {
        if (string.IsNullOrEmpty(key))
        {
            return;
        }

        RedPointData pointData = null;
        if (_redPointDataMap.ContainsKey(key))
        {
            pointData = _redPointDataMap[key];
        }
        else
        {
            pointData = new RedPointData();
            pointData.key = key;
            pointData.result = false;
            pointData.filterMap = new Dictionary<string, int>();
            pointData.childKeyList = new List<string>();
            pointData.parentKeyList = new List<string>();
            _redPointDataMap.Add(key, pointData);
        }

        pointData.checkActiveFunc = activeFunc;
        if (filterList != null)
        {
            pointData.filterMap.Clear();
            for (int i = 0; i < filterList.length(); i++)
            {
                pointData.filterMap.Add(filterList[i + 1].ToString(), 1);
            }
        }
        if (parentKeyList != null)
        {
            pointData.parentKeyList.Clear();
            for (int i = 0; i < parentKeyList.length(); i++)
            {
                var parentKey = parentKeyList[i + 1].ToString();
                if (string.IsNullOrEmpty(parentKey))
                {
                    continue;
                }

                pointData.parentKeyList.Add(parentKey);
                BindChildKey(parentKey, key);
            }
        }
    }

    private void BindChildKey(string key, string childKey)
    {
        if (string.IsNullOrEmpty(key) || string.IsNullOrEmpty(childKey))
        {
            return;
        }

        RedPointData pointData = null;
        if (_redPointDataMap.ContainsKey(key))
        {
            pointData = _redPointDataMap[key];
        }
        else
        {
            pointData = new RedPointData();
            pointData.key = key;
            pointData.result = false;
            pointData.filterMap = new Dictionary<string, int>();
            pointData.childKeyList = new List<string>();
            pointData.parentKeyList = new List<string>();
            _redPointDataMap.Add(key, pointData);
        }

        for (int i = 0; i < pointData.childKeyList.Count; i++)
        {
            if (pointData.childKeyList[i] == childKey)
            {
                return;
            }
        }

        pointData.childKeyList.Add(childKey);
    }

    private void BindPointItem_Internal(GameObject obj, string key, bool forceBind = false)
    {
        if (string.IsNullOrEmpty(key) || obj == null)
        {
            return;
        }

        List<RedPointItem> itemList = null;
        if (_redPointItemMap.ContainsKey(key))
        {
            itemList = _redPointItemMap[key];
        }
        else
        {
            itemList = new List<RedPointItem>();
            _redPointItemMap.Add(key, itemList);
        }

        RedPointItem pointItem = obj.GetComponent<RedPointItem>();
        if (pointItem == null)
        {
            pointItem = obj.AddComponent<RedPointItem>();
        }
        if (!pointItem.isWarmed)
        {
            pointItem.key = key;
            pointItem.isBindPendding = true;
            return;
        }
        if (pointItem.isBind && !forceBind)
        {
            return;
        }
        if (forceBind && pointItem.isBind)
        {
            UnbindPointItem_Internal(pointItem);
        }

        pointItem.key = key;
        pointItem.isBind = true;
        itemList.Add(pointItem);
    }

    private void UnbindPointItem_Internal(RedPointItem pointItem)
    {
        if (pointItem == null || !pointItem.isBind)
        {
            return;
        }

        if (!_redPointItemMap.ContainsKey(pointItem.key))
        {
            return;
        }

        pointItem.isBind = false;
        var itemList = _redPointItemMap[pointItem.key];
        for (int i = 0; i < itemList.Count; i++)
        {
            if (itemList[i].GetInstanceID() == pointItem.GetInstanceID())
            {
                itemList.RemoveAt(i);
                break;
            }
        }
    }

    private void CheckAll_Internal()
    {
        _checkKeyRecord.Clear();

        foreach (var key in _redPointDataMap.Keys)
        {
            var pointData = _redPointDataMap[key];
            if (pointData.childKeyList.Count != 0)
            {
                continue;
            }
            Check_Internal(key, null, null);
        }
    }

    private void Check_Internal(string key, string filter, object checkData, bool needCheckActive = true, bool isEntry = false)
    {
        if (isEntry)
        {
            _checkKeyRecord.Clear();
        }

        if (!_redPointDataMap.ContainsKey(key))
        {
            RefreshPointItem(key);
            return;
        }

        var pointData = _redPointDataMap[key];

        if (pointData.filterMap.Count != 0 && !string.IsNullOrEmpty(filter) && !pointData.filterMap.ContainsKey(filter))
        {
            return;
        }

        if (_checkKeyRecord.ContainsKey(key))
        {
            return;
        }
        _checkKeyRecord.Add(key, 1);

        if (needCheckActive && pointData.checkActiveFunc != null)
        {
            pointData.result = pointData.checkActiveFunc(checkData);
        }

        if (pointData.childKeyList.Count != 0)
        {
            if (pointData.checkActiveFunc == null)
            {
                pointData.result = false;
            }

            for (int i = 0; i < pointData.childKeyList.Count; i++)
            {
                Check_Internal(pointData.childKeyList[i], null, null, true);
                pointData.result |= GetPointResult(pointData.childKeyList[i]);
            }
        }

        if (pointData.parentKeyList.Count != 0)
        {
            for (int i = 0; i < pointData.parentKeyList.Count; i++)
            {
                Check_Internal(pointData.parentKeyList[i], null, null, true);
            }
        }

        RefreshPointItem(key);
    }

    private void RefreshPointItem(string key)
    {
        if (!_redPointItemMap.ContainsKey(key))
        {
            return;
        }

        var result = GetPointResult(key);
        var itemList = _redPointItemMap[key];
        for (int i = 0; i < itemList.Count; i++)
        {
            itemList[i].gameObject.SetActive(result);
        }
    }

    public bool GetPointResult(string key)
    {
        if (!_redPointDataMap.ContainsKey(key))
        {
            return false;
        }

        return _redPointDataMap[key].result;
    }
}
