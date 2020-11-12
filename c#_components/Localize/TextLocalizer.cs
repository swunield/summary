using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public class TextLocalizer : MonoBehaviour
{
    private static TextLocalizer _instance;
    public static TextLocalizer INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = new GameObject("TextLocalizer").AddComponent<TextLocalizer>();
            }
            return _instance;
        }
    }

    public static System.Func<string, string> OnLocalizeText;
    public static System.Action OnRefreshAllText;
    private Dictionary<UILocalizeText, string> _allLocalizerText = new Dictionary<UILocalizeText, string>();

    private int _languageType = 0;
    public int languageType { get { return _languageType; } }

    void Awake()
    {
        _instance = this;
        DontDestroyOnLoad(gameObject);
    }

    private void OnDestroy()
    {
        OnLocalizeText = null;
        OnRefreshAllText = null;
        _instance = null;
        _allLocalizerText.Clear();
    }

    public static void Initialize(int languageType)
    {
        if (_instance == null)
        {
            _instance = new GameObject("TextLocalizer").AddComponent<TextLocalizer>();
        }
        _instance._languageType = languageType;
    }

    public static int GetLanguageType()
    {
        if (_instance == null)
        {
            return 0;
        }
        return _instance.languageType;
    }

    public static void ExecLocalizeText(UILocalizeText uiText, string key)
    {
        if (_instance == null)
        {
            return;
        }
        if (OnLocalizeText != null && key.Length != 0 && uiText.languageType != _instance.languageType)
        {
            uiText.uiText.text = OnLocalizeText(key);
            uiText.languageType = _instance._languageType;
        }
    }

    public static void RefreshAllText(int languageType)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalRefreshAllText(languageType);
    }

    protected void InternalRefreshAllText(int languageType)
    {
        if (OnLocalizeText == null)
        {
            return;
        }

        _languageType = languageType;
        foreach (KeyValuePair<UILocalizeText, string> textInfo in _allLocalizerText)
        {
            ExecLocalizeText(textInfo.Key, textInfo.Value);
        }
        if (OnRefreshAllText != null)
        {
            OnRefreshAllText();
        }
    }

    public static void RegisterText(UILocalizeText uiText, string key)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalRegisterText(uiText, key);
    }

    public void InternalRegisterText(UILocalizeText uiText, string key)
    {
        _allLocalizerText[uiText] = key;
    }

    public static void UnRegisterText(UILocalizeText uiText)
    {
        if (_instance == null)
        {
            return;
        }
        _instance.InternalUnRegisterText(uiText);
    }

    protected void InternalUnRegisterText(UILocalizeText uiText)
    {
        _allLocalizerText.Remove(uiText);
    }
}
