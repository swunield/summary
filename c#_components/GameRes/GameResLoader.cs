using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;
using UnityEngine.Networking;

[SLua.CustomLuaClass]
public class GameResLoader : MonoBehaviour
{
    public class GameResAssetBundle
    {
        public string hash;
        public AssetBundle assetBundle;
    }

    private static GameResLoader _instance;
    public static GameResLoader INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = GameObject.FindObjectOfType<GameResLoader>();
                if (_instance == null)
                {
                    _instance = new GameObject("GameResLoader").AddComponent<GameResLoader>();
                }
                GameObject.DontDestroyOnLoad(_instance.gameObject);
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

    public static void Reset()
    {
        if (_instance != null)
        {
            _instance.UnLoadAllAssetBundles();
        }
    }

    void Awake()
    {
        _instance = this;
        GameObject.DontDestroyOnLoad(gameObject);
    }

    private void OnDestroy()
    {
        UnLoadAllAssetBundles();
        _instance = null;
    }

    public static Hash128 ParseHash(string hash)
    {
        return Hash128.Parse(hash);
    }

    public static bool IsVersionCached(string bundleName, string hash)
    {
        return Caching.IsVersionCached(bundleName, Hash128.Parse(hash));
    }

    [SerializeField]
    private GameResLoadMode _loadMode;
    public static GameResLoadMode loadMode
    {
        set
        {
            INSTANCE._loadMode = value;
        }
    }

    public static GameResLoadMode actualLoadMode
    {
        get
        {
#if UNITY_EDITOR
            return INSTANCE._loadMode;
#else
			return GameResLoadMode.Release;
#endif
        }
    }

    [SerializeField]
    public string defaultResFolder = "Assets/Game";

    [SerializeField]
    public string defaultOutputFolder = "Assets/Output";

    // 所有AssetBundle
    private Dictionary<string, Dictionary<string, GameResAssetBundle>> _allAssetBundleMap = new Dictionary<string, Dictionary<string, GameResAssetBundle>>();

    public void LoadManifest(string manifestName, string hash, string[] urls, bool isLoadFromPackage, System.Action<bool, string[]> onLoadDone)
    {
        LoadManifest(manifestName, hash, urls, isLoadFromPackage, onLoadDone, GameResLoadMode.None);
    }

    public void LoadManifest(string manifestName, string hash, string[] urls, bool isLoadFromPackage, System.Action<bool, string[]> onLoadDone, GameResLoadMode resLoadMode)
    {
        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
#if UNITY_EDITOR
        if (resLoadMode == GameResLoadMode.Direct || resLoadMode == GameResLoadMode.None)
        {
            onLoadDone(true, null);
            return;
        }
#endif

        LoadAssetBundle(manifestName, manifestName, hash, urls, isLoadFromPackage, (result) =>
        {
            if (!result)
            {
                UnLoadAssetBundle(manifestName, manifestName);
                onLoadDone(false, null);
                return;
            }

            var manifestBundle = GetAssetBundle(manifestName, manifestName);
            if (manifestBundle == null)
            {
                UnLoadAssetBundle(manifestName, manifestName);
                onLoadDone(false, null);
                return;
            }

            var manifest = manifestBundle.LoadAsset("assetbundlemanifest", typeof(AssetBundleManifest)) as AssetBundleManifest;
            if (manifest == null)
            {
                UnLoadAssetBundle(manifestName, manifestName);
                onLoadDone(false, null);
                return;
            }

            var allAssetBundles = manifest.GetAllAssetBundles();
            UnLoadAssetBundle(manifestName, manifestName);

            onLoadDone(true, allAssetBundles);
        }, resLoadMode);
    }

    public void LoadAssetBundle(string bundleName, string manifestName, string hash, string[] urls, bool isLoadFromPackage, System.Action<bool> onLoadDone)
    {
        LoadAssetBundle(bundleName, manifestName, hash, urls, isLoadFromPackage, onLoadDone, GameResLoadMode.None);
    }

    public void LoadAssetBundle(string bundleName, string manifestName, string hash, string[] urls, bool isLoadFromPackage, System.Action<bool> onLoadDone, GameResLoadMode resLoadMode)
    {
        if (string.IsNullOrEmpty(hash))
        {
            onLoadDone(false);
            return;
        }
        if (hash == GetAssetBundleHash(bundleName, manifestName))
        {
            // 已加载相同Hash的，无需再加载
            onLoadDone(true);
            return;
        }

        // 已加载不同Hash的，先卸载
        UnLoadAssetBundle(bundleName, manifestName);

        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            _allAssetBundleMap.Add(manifestName, new Dictionary<string, GameResAssetBundle>());
        }
        var bundleGroupMap = _allAssetBundleMap[manifestName];

        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
        switch (resLoadMode)
        {
#if UNITY_EDITOR
            case GameResLoadMode.None:
            case GameResLoadMode.Direct:
                {
                    // 无需加载AssetBundle，直接通过AssetDatabase加载
                    onLoadDone(true);
                    return;
                }
                break;
            case GameResLoadMode.LocalSimulation:
                {
                    // 从Output中加载
                    var buildTarget = UnityEditor.EditorUserBuildSettings.activeBuildTarget.ToString();
                    var project = Application.dataPath.Substring(0, Application.dataPath.Length - "Assets".Length);
                    var fullPath = string.Format(project + defaultOutputFolder + "/{0}/{1}/{2}", manifestName, buildTarget, bundleName);
                    if (File.Exists(fullPath))
                    {
                        StartCoroutine(LoadAssetBundleFromFile(bundleGroupMap, bundleName, manifestName, hash, fullPath, onLoadDone));
                        return;
                    }
                }
                break;
#endif
            case GameResLoadMode.Release:
                {
                    if (isLoadFromPackage)
                    {
                        // 从包体加载
                        var fullPath = Application.streamingAssetsPath + "/" + bundleName;
                        StartCoroutine(LoadAssetBundleFromFile(bundleGroupMap, bundleName, manifestName, hash, fullPath, onLoadDone));
                        return;
                    }
                    else
                    {
                        // 从Cache中加载
                        StartCoroutine(LoadAssetBundleFromCache(bundleGroupMap, bundleName, manifestName, hash, urls, onLoadDone));
                        return;
                    }
                }
                break;
        }

        onLoadDone(IsAssetBundleLoaded(bundleName, manifestName));
    }

    private IEnumerator LoadAssetBundleFromCache(Dictionary<string, GameResAssetBundle> bundleGroupMap, string bundleName, string manifestName, string hash, string[] urls, System.Action<bool> onLoadDone)
    {
        var realHash = Hash128.Parse(hash);

        bool success = false;
        foreach (string url in urls)
        {
            float checkTimeOutTime = Time.time;
            float progress = 0;

            var webRequest = GameWebRequest.SendAssetBundleWebRequest(url, realHash, true);
            while (!webRequest.request.isDone)
            {
                if (!string.IsNullOrEmpty(webRequest.request.error))
                {
                    break;
                }
                if (progress != webRequest.request.downloadProgress)
                {
                    checkTimeOutTime = Time.time;
                }
                else if (Time.time - checkTimeOutTime >= 5)
                {
                    break;
                }
                yield return null;
            }

            if (!string.IsNullOrEmpty(webRequest.request.error) || !webRequest.request.isDone)
            {
                FTDebug.LogWarning(string.Format("Failed To LoadAssetBundleFromCache Name[{0}] From[{1}] Error[{2}]", bundleName, url, webRequest.request.error));
                GameWebRequest.DestroyAssetBundleWebRequest(webRequest);
                Caching.ClearCachedVersion(bundleName, realHash);
                continue;
            }

            AssetBundle assetBundle = null;
            try
            {
                assetBundle = DownloadHandlerAssetBundle.GetContent(webRequest.request);
                if (assetBundle == null)
                {
                    FTDebug.LogWarning(string.Format("Failed To LoadAssetBundleFromCache Name[{0}] From[{1}] Error[AssetBundle is Null]", bundleName, url));
                    GameWebRequest.DestroyAssetBundleWebRequest(webRequest);
                    Caching.ClearCachedVersion(bundleName, realHash);
                    continue;
                }
            }
            catch (System.Exception e)
            {
                FTDebug.LogWarning(string.Format("Failed To LoadAssetBundleFromCache Name[{0}] From[{1}] Error[{2}]", bundleName, url, e.Message));
                GameWebRequest.DestroyAssetBundleWebRequest(webRequest);
                Caching.ClearCachedVersion(bundleName, realHash);
                continue;
            }

            if (bundleGroupMap.ContainsKey(bundleName) && bundleGroupMap[bundleName].hash != hash)
            {
                UnLoadAssetBundle(bundleName, manifestName);
            }

            if (!bundleGroupMap.ContainsKey(bundleName))
            {
                bundleGroupMap.Add(bundleName, new GameResAssetBundle()
                {
                    hash = hash,
                    assetBundle = assetBundle,
                });
            }

            GameWebRequest.DestroyAssetBundleWebRequest(webRequest);
            success = true;
            FTDebug.Log(string.Format("LoadAssetBundleFromCache Name[{0}] From[{1}]", bundleName, url));

            // 清除除当前使用的
            Caching.ClearOtherCachedVersions(bundleName, realHash);

            break;
        }

        onLoadDone(success);
    }

    private IEnumerator LoadAssetBundleFromFile(Dictionary<string, GameResAssetBundle> bundleGroupMap, string bundleName, string manifestName, string hash, string fullPath, System.Action<bool> onLoadDone)
    {
        var realHash = Hash128.Parse(hash);

        var req = AssetBundle.LoadFromFileAsync(fullPath);
        while (!req.isDone)
        {
            yield return null;
        }

        if (req.assetBundle == null)
        {
            onLoadDone(false);
            yield break;
        }

        if (bundleGroupMap.ContainsKey(bundleName) && bundleGroupMap[bundleName].hash != hash)
        {
            UnLoadAssetBundle(bundleName, manifestName);
        }

        if (!bundleGroupMap.ContainsKey(bundleName))
        {
            bundleGroupMap.Add(bundleName, new GameResAssetBundle()
            {
                hash = hash,
                assetBundle = req.assetBundle,
            });
        }

        // 清除缓存中除当前使用的
        Caching.ClearOtherCachedVersions(bundleName, realHash);

        onLoadDone(true);

        FTDebug.LogWarning(string.Format("LoadAssetBundleFromFile Name[{0}] Path[{1}]", bundleName, fullPath));
    }

    public void UnLoadAssetBundle(string bundleName, string manifestName, bool unloadAll = true)
    {
        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            return;
        }
        var bundleGroupMap = _allAssetBundleMap[manifestName];
        if (!bundleGroupMap.ContainsKey(bundleName))
        {
            return;
        }
        bundleGroupMap[bundleName].assetBundle.Unload(unloadAll);
        bundleGroupMap.Remove(bundleName);

        FTDebug.LogWarning(string.Format("UnLoadAssetBundle Name[{0}] UnLoadAll[{1}]", bundleName, unloadAll));
    }

    public void UnLoadAssetBundleGroup(string manifestName)
    {
        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            return;
        }
        var bundleGroupMap = _allAssetBundleMap[manifestName];
        foreach (var bundleName in bundleGroupMap.Keys)
        {
            bundleGroupMap[bundleName].assetBundle.Unload(true);
            FTDebug.LogWarning(string.Format("UnLoadAssetBundleGroup ManifestName[{0}] BundleName[{1}]", manifestName, bundleName));
        }
        bundleGroupMap.Clear();
    }

    public void UnLoadAllAssetBundles()
    {
        foreach (var manifestName in _allAssetBundleMap.Keys)
        {
            UnLoadAssetBundleGroup(manifestName);
        }
        _allAssetBundleMap.Clear();
    }

    public Object LoadRes(string fullPath, System.Type type)
    {
        return LoadRes(fullPath, type, GameResLoadMode.None);
    }

    public Object LoadRes(string fullPath, System.Type type, GameResLoadMode resLoadMode)
    {
        if (!fullPath.Contains(INSTANCE.defaultResFolder) && !fullPath.Contains("Assets/"))
        {
            fullPath = string.Format("{0}/{1}", INSTANCE.defaultResFolder, fullPath);
        }

        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
#if UNITY_EDITOR
        if (resLoadMode == GameResLoadMode.Direct || resLoadMode == GameResLoadMode.None)
        {
            return UnityEditor.AssetDatabase.LoadAssetAtPath(fullPath, type);
        }
#endif
        var bundle = GetResAssetBundle(fullPath);
        if (bundle == null)
        {
            return null;
        }

        return bundle.LoadAsset(fullPath, type);
    }

    public T LoadRes<T>(string fullPath, GameResLoadMode resLoadMode) where T : Object
    {
        return LoadRes(fullPath, typeof(T), resLoadMode) as T;
    }

    public T LoadRes<T>(string fullPath) where T : Object
    {
        return LoadRes(fullPath, typeof(T)) as T;
    }

    public void LoadResAsync(string fullPath, System.Type type, System.Action<Object> onLoadDone)
    {
        LoadResAsync(fullPath, type, onLoadDone, GameResLoadMode.None);
    }

    public void LoadResAsync(string fullPath, System.Type type, System.Action<Object> onLoadDone, GameResLoadMode resLoadMode)
    {
        if (!fullPath.Contains(INSTANCE.defaultResFolder) && !fullPath.Contains("Assets/"))
        {
            fullPath = string.Format("{0}/{1}", INSTANCE.defaultResFolder, fullPath);
        }

        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
#if UNITY_EDITOR
        if (resLoadMode == GameResLoadMode.Direct || resLoadMode == GameResLoadMode.None)
        {
            onLoadDone(LoadRes(fullPath, type));
            return;
        }
#endif
        var bundle = GetResAssetBundle(fullPath);
        if (bundle == null)
        {
            onLoadDone(null);
            return;
        }

        StartCoroutine(_LoadResAsync(bundle, fullPath, type, onLoadDone));
    }

    private IEnumerator _LoadResAsync(AssetBundle bundle, string fullPath, System.Type type, System.Action<Object> onLoadDone)
    {
        if (bundle == null)
        {
            onLoadDone(null);
            yield break;
        }

        var req = bundle.LoadAssetAsync(fullPath, type);
        yield return req;

        onLoadDone(req.asset);
    }

    public AssetBundle GetResAssetBundle(string resFullPath, string manifestName = "", string bundleName = "")
    {
        if (!resFullPath.Contains(INSTANCE.defaultResFolder) && !resFullPath.Contains("Assets/"))
        {
            resFullPath = string.Format("{0}/{1}", INSTANCE.defaultResFolder, resFullPath);
        }
        foreach (var manifest in _allAssetBundleMap.Keys)
        {
            if (!string.IsNullOrEmpty(manifestName) && manifestName != manifest)
            {
                continue;
            }

            var bundleGroupMap = _allAssetBundleMap[manifest];
            foreach (var bundle in bundleGroupMap.Values)
            {
                if (!string.IsNullOrEmpty(bundleName) && bundleName != bundle.assetBundle.name)
                {
                    continue;
                }

                if (bundle.assetBundle.Contains(resFullPath))
                {
                    return bundle.assetBundle;
                }
            }
        }
        return null;
    }

    public GameResAssetBundle GetGameResAssetBundle(string bundleName, string manifestName)
    {
        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            return null;
        }
        var bundleGroupMap = _allAssetBundleMap[manifestName];
        if (!bundleGroupMap.ContainsKey(bundleName))
        {
            return null;
        }
        return bundleGroupMap[bundleName];
    }

    public AssetBundle GetAssetBundle(string bundleName, string manifestName)
    {
        var gameResAssetBundle = GetGameResAssetBundle(bundleName, manifestName);
        if (gameResAssetBundle == null)
        {
            return null;
        }
        return gameResAssetBundle.assetBundle;
    }

    public string GetAssetBundleHash(string bundleName, string manifestName)
    {
        var gameResAssetBundle = GetGameResAssetBundle(bundleName, manifestName);
        if (gameResAssetBundle == null)
        {
            return null;
        }
        return gameResAssetBundle.hash;
    }

    public void LoadGroupAllAssets(string manifestName)
    {
        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            return;
        }
        var bundleGroupMap = _allAssetBundleMap[manifestName];
        foreach (var bundle in bundleGroupMap.Values)
        {
            bundle.assetBundle.LoadAllAssets();
        }
    }

    public bool IsAssetBundleLoaded(string bundleName, string manifestName)
    {
        return GetAssetBundle(bundleName, manifestName) != null;
    }

    public string[] GetGroupAllBundleNames(string manifestName)
    {
        if (!_allAssetBundleMap.ContainsKey(manifestName))
        {
            return null;
        }

        return _allAssetBundleMap[manifestName].Keys.ToArray();
    }

    public bool ContainsRes(string res, string manifestName = "", string bundleName = "")
    {
        return GetResAssetBundle(res, manifestName, bundleName) != null;
    }

    public void LoadResourcesAysnc(string resName, System.Action<Object> onLoadDone)
    {
        StartCoroutine(this._LoadResourcesAsync(resName, onLoadDone));
    }

    private IEnumerator _LoadResourcesAsync(string resName, System.Action<Object> onLoadDone)
    {
        var request = Resources.LoadAsync(resName);
        while (!request.isDone)
        {
            yield return null;
        }
        if (onLoadDone != null)
        {
            onLoadDone(request.asset);
        }
    }

    public Coroutine CoroutineLoadManifestBundles(string manifestName, string manifestHash, string[] manifestUrls, Dictionary<string, string> resHashes, Dictionary<string, List<string>> resUrls, System.Action onLoadDone = null, GameResLoadMode resLoadMode = GameResLoadMode.None)
    {
        return StartCoroutine(_LoadManifestBundles(manifestName, manifestHash, manifestUrls, resHashes, resUrls, onLoadDone, resLoadMode));
    }

    private IEnumerator _LoadManifestBundles(string manifestName, string manifestHash, string[] manifestUrls, Dictionary<string, string> resHashes, Dictionary<string, List<string>> resUrls, System.Action onLoadDone = null, GameResLoadMode resLoadMode = GameResLoadMode.None)
    {
        bool isLoadDone = false;
        LoadManifestBundles(manifestName, manifestHash, manifestUrls, resHashes, resUrls, (result) =>
        {
            if (onLoadDone != null)
            {
                onLoadDone();
            }
            isLoadDone = true;
        });
        while (!isLoadDone)
        {
            yield return null;
        }
    }

    public void LoadManifestBundles(string manifestName, string manifestHash, string[] manifestUrls, Dictionary<string, string> resHashes, Dictionary<string, List<string>> resUrls, System.Action<bool> onLoadDone = null, GameResLoadMode resLoadMode = GameResLoadMode.None)
    {
        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
        if (resLoadMode == GameResLoadMode.Direct)
        {
            if (onLoadDone != null)
            {
                onLoadDone(true);
            }
            return;
        }

        manifestHash = string.IsNullOrEmpty(manifestHash) ? GameBundleSetting.INSTANCE.GetBundleHash(manifestName, manifestName) : manifestHash;
        manifestUrls = (manifestUrls == null || manifestUrls.Length == 0) ? new string[] { manifestName } : manifestUrls;
        GameResLoader.INSTANCE.LoadManifest(manifestName, manifestHash, manifestUrls, GameBundleSetting.INSTANCE.IsBundleSameHash(manifestHash, manifestName, manifestName),
            (result, bundleNames) =>
            {
                if (!result || bundleNames == null)
                {
                    if (onLoadDone != null)
                    {
                        onLoadDone(result);
                    }
                    return;
                }

                var bundleList = bundleNames.ToList<string>();
                LoadBundles(manifestName, bundleList, resUrls, resHashes, (_result) =>
                {
                    if (!_result)
                    {
                        if (onLoadDone != null)
                        {
                            onLoadDone(false);
                        }
                        return;
                    }

                    if (onLoadDone != null)
                    {
                        onLoadDone(true);
                    }
                });
            },
        resLoadMode);
    }

    public void LoadBundles(string manifestName, List<string> bundleList, Dictionary<string, List<string>> resUrls, Dictionary<string, string> resHashes, System.Action<bool> onLoadDone = null, GameResLoadMode resLoadMode = GameResLoadMode.None)
    {
        resLoadMode = resLoadMode == GameResLoadMode.None ? actualLoadMode : resLoadMode;
        if (resLoadMode == GameResLoadMode.Direct)
        {
            if (onLoadDone != null)
            {
                onLoadDone(true);
            }
            return;
        }

        if (bundleList.Count == 0)
        {
            if (onLoadDone != null)
            {
                onLoadDone(true);
            }
            return;
        }

        var bundleName = bundleList[0];
        bundleList.RemoveAt(0);

        var hash = (resHashes != null && resHashes.ContainsKey(bundleName)) ? resHashes[bundleName] : GameBundleSetting.INSTANCE.GetBundleHash(bundleName, manifestName);
        var urls = (resUrls != null && resUrls.ContainsKey(bundleName)) ? resUrls[bundleName].ToArray() : new string[] { bundleName };
        GameResLoader.INSTANCE.LoadAssetBundle(bundleName, manifestName, hash, urls, GameBundleSetting.INSTANCE.IsBundleSameHash(hash, bundleName, manifestName),
            (result) =>
            {
                if (!result)
                {
                    if (onLoadDone != null)
                    {
                        onLoadDone(false);
                    }
                    return;
                }
                LoadBundles(manifestName, bundleList, resUrls, resHashes, onLoadDone, resLoadMode);
            },
        resLoadMode);
    }
}
