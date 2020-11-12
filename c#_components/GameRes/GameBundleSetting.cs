using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
#if UNITY_EDITOR
using UnityEditor;
#endif
using UnityEngine;

[SLua.CustomLuaClass]
[CreateAssetMenu(menuName = "Build/GameBundleSetting")]
public class GameBundleSetting : ScriptableObject, ISerializationCallbackReceiver
{
    private static GameBundleSetting _instance;
    public static GameBundleSetting INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = Resources.Load<GameBundleSetting>("bundleSetting");
            }
#if UNITY_EDITOR
            if (_instance == null)
            {
                _instance = GameBundleSetting.CreateInstance<GameBundleSetting>();
                var path = "Assets/Build/Resources/bundleSetting.asset";
                var dir = Path.GetDirectoryName(path);
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                UnityEditor.AssetDatabase.CreateAsset(_instance, path);
            }
#endif
            return _instance;
        }
    }

    [SerializeField]
    private GameAssetBundle[] bundles;

    private List<GameAssetBundle> bundleList = new List<GameAssetBundle>();

    private void OnDestroy()
    {
        _instance = null;
    }

    public void SetBundle(string bundleName, string manifestName, string hash, int size, bool isOnlyInPackage)
    {
        foreach (var bundle in bundleList)
        {
            if (bundle.bundleName == bundleName)
            {
                bundle.manifestName = manifestName;
                bundle.hash = hash;
                bundle.size = size;
                bundle.isOnlyInPackage = isOnlyInPackage;
#if UNITY_EDITOR
                EditorUtility.SetDirty(this);
#endif
                return;
            }
        }

        bundleList.Add(new GameAssetBundle() { bundleName = bundleName, manifestName = manifestName, hash = hash, size = size, isOnlyInPackage = isOnlyInPackage });
#if UNITY_EDITOR
        EditorUtility.SetDirty(this);
#endif
    }

    public string GetBundleHash(string bundleName, string manifestName = "")
    {
        foreach (var bundle in bundles)
        {
            if (bundle.bundleName == bundleName && (string.IsNullOrEmpty(manifestName) || manifestName == bundle.manifestName))
            {
                return bundle.hash;
            }
        }
        return "";
    }

    public GameAssetBundle GetBundle(string bundleName, string manifestName = "")
    {
        foreach (var bundle in bundles)
        {
            if (bundle.bundleName == bundleName && (string.IsNullOrEmpty(manifestName) || manifestName == bundle.manifestName))
            {
                return bundle;
            }
        }
        return null;
    }

    public bool IsBundleSameHash(string bundleHash, string bundleName, string manifestName = "")
    {
        return !string.IsNullOrEmpty(bundleHash) && GetBundleHash(bundleName, manifestName) == bundleHash;
    }

    public void RemoveBundle(string manifestName, string bundleName = "")
    {
        for (int i = bundleList.Count - 1; i >= 0; i--)
        {
            var bundle = bundleList[i];
            if (manifestName == bundle.manifestName && (string.IsNullOrEmpty(bundleName) || bundleName == bundle.bundleName))
            {
                bundleList.RemoveAt(i);
            }
        }
#if UNITY_EDITOR
        EditorUtility.SetDirty(this);
#endif
    }

    public GameAssetBundle[] GetAllPackageBundles()
    {
        return bundleList.ToArray();
    }

    public void OnAfterDeserialize()
    {
        bundleList.Clear();
        foreach (var bundle in bundles)
        {
            bundleList.Add(bundle);
        }
    }

    public void OnBeforeSerialize()
    {
        bundles = bundleList.ToArray();
    }
}

[Serializable]
public class GameAssetBundle
{
    public string bundleName;
    public string manifestName;
    public string hash;
    public int size;
    public bool isOnlyInPackage;
}
