using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public class ImageLocalizer : MonoBehaviour
{
    private static ImageLocalizer _instance;
    public static ImageLocalizer INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = new GameObject("ImageLocalizer").AddComponent<ImageLocalizer>();
            }
            return _instance;
        }
    }

    public static System.Func<string, string, string, SLua.LuaTable> OnLocalizeImage;
    public static System.Action OnRefreshAllImage;
    private Dictionary<UILocalizeImage, string[]> _allLocalizerImage = new Dictionary<UILocalizeImage, string[]>();

    public int defaultLanguageType = 0;

    private int _languageType = 0;
    public int languageType { get { return _languageType; } }

    // Use this for initialization
    void Awake()
    {
        _instance = this;
        DontDestroyOnLoad(gameObject);
    }

    private void OnDestroy()
    {
        OnLocalizeImage = null;
        OnRefreshAllImage = null;
        _allLocalizerImage.Clear();
        _instance = null;
    }

    public static void Initialize(int languageType)
    {
        if (_instance == null)
        {
            _instance = new GameObject("ImageLocalizer").AddComponent<ImageLocalizer>();
        }
        _instance._languageType = languageType;
    }

    public static int GetDefaultLanguageType()
    {
        if (_instance == null)
        {
            return 0;
        }
        return _instance.defaultLanguageType;
    }

    public static int GetLanguageType()
    {
        if (_instance == null)
        {
            return 0;
        }
        return _instance.languageType;
    }

    public static void ExecLocalizeImage(UILocalizeImage image, string path, string pathExt, string folder = "")
    {
        if (_instance == null)
        {
            return;
        }
        if (OnLocalizeImage != null && path.Length != 0 && image.languageType != _instance.languageType)
        {
            var result = OnLocalizeImage(path, pathExt, folder);
            GOUtils.SetImage(image.gameObject, result[1].ToString(), pathExt, result[2].ToString());
            image.languageType = _instance._languageType;
        }
    }

    public static void RefreshAllImage(int languageType)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalRefreshAllImage(languageType);
    }

    protected void InternalRefreshAllImage(int languageType)
    {
        if (OnLocalizeImage == null)
        {
            return;
        }
        _languageType = languageType;
        foreach (KeyValuePair<UILocalizeImage, string[]> imageInfo in _allLocalizerImage)
        {
            ExecLocalizeImage(imageInfo.Key, imageInfo.Value[0], imageInfo.Value[1], imageInfo.Value[2]);
        }
        if (OnRefreshAllImage != null)
        {
            OnRefreshAllImage();
        }
    }

    public static void RegisterImage(UILocalizeImage uiImage, string path, string pathExt, string folder)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalRegisterImage(uiImage, path, pathExt, folder);
    }

    protected void InternalRegisterImage(UILocalizeImage uiImage, string path, string pathExt, string folder)
    {
        _allLocalizerImage[uiImage] = new string[] { path, pathExt, folder };
    }

    public static void UnRegisterImage(UILocalizeImage uiImage)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalUnRegisterImage(uiImage);
    }

    protected void InternalUnRegisterImage(UILocalizeImage uiImage)
    {
        _allLocalizerImage.Remove(uiImage);
    }
}
