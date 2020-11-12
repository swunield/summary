using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Profiling;

[SLua.CustomLuaClass]
public class GamePerf : MonoBehaviour
{
    public static bool SHOW_LOG = false;
    public static bool PERF_OPEN = true;

    protected static GamePerf _instance = null;
    public static GamePerf INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = GameObject.FindObjectOfType<GamePerf>();
            }
            if (_instance == null)
            {
                _instance = new GameObject("GamePerf").AddComponent<GamePerf>();
            }

            return _instance;
        }
    }

    public class GamePerfStat
    {
        public string key;
        public string parentKey;
        public int totalTimes;
        public double totalCostTime;
        public double lastCostTime;
        public List<double> recordList;
        public List<string> childList;
        public int statLevel;

        private string _realKey;
        public string realKey
        {
            get
            {
                if (string.IsNullOrEmpty(_realKey))
                {
                    _realKey = (string.IsNullOrEmpty(parentKey) ? "" : (parentKey + "_")) + key;
                }

                return _realKey;
            }
        }
    }

    class GamePerfingData
    {
        public string key;
        public string parentKey;
        public float beginTime;

        private string _realKey;
        public string realKey
        {
            get
            {
                if (string.IsNullOrEmpty(_realKey))
                {
                    _realKey = (string.IsNullOrEmpty(parentKey) ? "" : (parentKey + "_")) + key;
                }

                return _realKey;
            }
        }
    }

    private Dictionary<string, GamePerfStat> _allPerfStatList = new Dictionary<string, GamePerfStat>();
    private Stack<GamePerfingData> _perfingList = new Stack<GamePerfingData>();
    private Action _onStatRefresh = null;

    public static void Begin(string key)
    {
        Begin(key, null, false);
    }

    public static void Begin(string key, GameObject obj, bool ignoreParent = false)
    {
        if (obj == null)
        {
            GamePerf.INSTANCE.BeginPerf(key, ignoreParent);
        }
        else
        {
            var switcher = obj.GetComponent<GamePerfSwitcher>();
            if (switcher != null && switcher.isOpen)
            {
                if (switcher.isSingle)
                {
                    key += ("_" + obj.name);
                }

                GamePerf.INSTANCE.BeginPerf(key, ignoreParent);
            }
        }
    }

    public static void End()
    {
        GamePerf.INSTANCE.EndPerf(SHOW_LOG);
    }

    public static void End(bool showLog)
    {
        GamePerf.INSTANCE.EndPerf(showLog);
    }

    public static void Clear(string key = "")
    {
        GamePerf.INSTANCE.ClearPerf(key);
    }

    public static GamePerfStat[] GetPerfList(string keyFilter = "")
    {
        return GamePerf.INSTANCE.GetPerfStatList(keyFilter);
    }

    public static void SetPerfListener(Action onRefresh)
    {
        GamePerf.INSTANCE.SetPerfStatListener(onRefresh);
    }

    private void Awake()
    {
        _instance = this;
        GameObject.DontDestroyOnLoad(this.gameObject);
    }

    private void OnDestroy()
    {
        _instance = null;
        this._onStatRefresh = null;
    }

    private void BeginPerf(string key, bool ignoreParent = false)
    {
        if (!PERF_OPEN)
        {
            return;
        }

        if (string.IsNullOrEmpty(key))
        {
            FTDebug.LogError("[GamePerf] Perf Lose Key");
            return;
        }

        var parentKey = "";
        if (_perfingList.Count != 0 && !ignoreParent)
        {
            parentKey = _perfingList.First().realKey;
        }

        var perfing = new GamePerfingData()
        {
            key = key,
            parentKey = parentKey,
            beginTime = 0,
        };

        if (!_allPerfStatList.ContainsKey(perfing.realKey))
        {
            var perfStat = new GamePerfStat()
            {
                key = key,
                parentKey = parentKey,
                totalTimes = 0,
                totalCostTime = 0,
                lastCostTime = 0,
                recordList = new List<double>(),
                childList = new List<string>(),
                statLevel = 0,
            };
            _allPerfStatList.Add(perfing.realKey, perfStat);

            if (_allPerfStatList.Keys.Contains(parentKey))
            {
                var parentPerf = _allPerfStatList[parentKey];
                parentPerf.childList.Add(perfing.realKey);
                perfStat.statLevel = parentPerf.statLevel + 1;
            }
        }

        _perfingList.Push(perfing);
        perfing.beginTime = Time.realtimeSinceStartup * 1000;
    }

    private void EndPerf(bool showLog = false)
    {
        if (_perfingList.Count == 0)
        {
            return;
        }

        var nowTime = Time.realtimeSinceStartup * 1000;
        var perfing = _perfingList.Pop();

        if (!_allPerfStatList.ContainsKey(perfing.realKey))
        {
            return;
        }

        var perfStat = _allPerfStatList[perfing.realKey];
        perfStat.lastCostTime = Math.Round(nowTime - perfing.beginTime, 1);
        perfStat.recordList.Add(perfStat.lastCostTime);
        perfStat.totalTimes++;
        perfStat.totalCostTime += perfStat.lastCostTime;

        if (showLog)
        {
            FTDebug.LogWarning(string.Format("Key[{0}] RealKey[{1}] CostTime[{2}] TotalCostTime[{3}] TotalTimes[{4}] AverageTime[{5}] BeginTime[{6}] EndTime[{7}]", perfing.key, perfing.realKey,
                perfStat.lastCostTime, perfStat.totalCostTime, perfStat.totalTimes, Math.Round(perfStat.totalCostTime / perfStat.totalTimes, 1), perfing.beginTime, nowTime), "PERF");
        }

        if (this._onStatRefresh != null)
        {
            this._onStatRefresh();
        }
    }

    private void ClearPerf(string key = "")
    {
        if (string.IsNullOrEmpty(key))
        {
            _allPerfStatList.Clear();
            return;
        }

        foreach (var statKey in _allPerfStatList.Keys.ToArray())
        {
            if (statKey == key)
            {
                _allPerfStatList.Remove(key);
            }
        }
    }

    private GamePerfStat[] GetPerfStatList(string keyFilter = "")
    {
        if (string.IsNullOrEmpty(keyFilter))
        {
            return _allPerfStatList.Values.ToArray();
        }

        return _allPerfStatList.Values.Where(stat => stat.key.Contains(keyFilter)).ToArray();
    }

    private void SetPerfStatListener(Action onStatRefresh)
    {
        this._onStatRefresh = onStatRefresh;
    }
}
