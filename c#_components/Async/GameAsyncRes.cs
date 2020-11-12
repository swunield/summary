using LitJson;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

public class GameAsyncResInfo
{
    public string bundleName { get; set; }
    public string manifestName { get; set; }
    public int size { get; set; }
    public string hash { get; set; }
    public string loadSource { get; set; }
    public string[] urls { get; set; }
}

[SLua.CustomLuaClass]
public class GameAsyncRes
{
    private static Dictionary<string, GameAsyncResInfo> _allAsyncResDict = new Dictionary<string, GameAsyncResInfo>();
    private static Dictionary<string, string> _allAsyncResBundleConfig = new Dictionary<string, string>();

    public static void Init(string jsonInfo)
    {
        _allAsyncResDict.Clear();
        var allAsyncResList = JsonMapper.ToObject<List<GameAsyncResInfo>>(jsonInfo);
        if (allAsyncResList != null)
        {
            foreach (var info in allAsyncResList)
            {
                _allAsyncResDict.Add(info.bundleName, info);
            }
        }
    }

    public static void InitBundleConfig(SLua.LuaTable luaConfig)
    {
        _allAsyncResBundleConfig.Clear();
        if (_allAsyncResDict.Count == 0)
        {
            return;
        }
        if (luaConfig == null)
        {
            return;
        }
        _allAsyncResBundleConfig = luaConfig.ToDictionary<string, string>();
    }

    public static GameAsyncResInfo Get(string assetName)
    {
        var bundleName = GetAsyncBundleName(assetName);
        if (string.IsNullOrEmpty(bundleName))
        {
            return null;
        }
        if (_allAsyncResDict.ContainsKey(bundleName))
        {
            return _allAsyncResDict[bundleName];
        }
        return null;
    }

    public static List<GameAsyncResInfo> GetAll()
    {
        return _allAsyncResDict.Values.ToList();
    }

    public static string GetAsyncBundleName(string assetName)
    {
        if (_allAsyncResDict.Count == 0)
        {
            return null;
        }
        if (!assetName.Contains(GameResLoader.INSTANCE.defaultResFolder) && !assetName.Contains("Assets/"))
        {
            assetName = string.Format("{0}/{1}", GameResLoader.INSTANCE.defaultResFolder, assetName);
        }
        if (_allAsyncResBundleConfig.ContainsKey(assetName))
        {
            return _allAsyncResBundleConfig[assetName];
        }
        return null;
    }

    public static bool IsAssetLoaded(string assetName)
    {
        var info = Get(assetName);
        if (info == null)
        {
            return true;
        }
        return GameResLoader.INSTANCE.IsAssetBundleLoaded(info.bundleName, info.manifestName);
    }

    public static bool IsAsyncEnable()
    {
        return _allAsyncResDict.Count != 0;
    }

    public static void OnAsyncResDownloadSuccess(string bundleName)
    {
        if (_allAsyncResDict.ContainsKey(bundleName))
        {
            _allAsyncResDict.Remove(bundleName);
        }
    }
}
