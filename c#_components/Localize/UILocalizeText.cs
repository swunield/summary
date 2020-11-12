using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
[RequireComponent(typeof(Text))]
public class UILocalizeText : MonoBehaviour
{
    [Tooltip("文本Key")]
    public string textKey;

    private Text _uiText;
    public Text uiText
    {
        get
        {
            if (_uiText == null)
            {
                _uiText = GetComponent<Text>();
            }
            return _uiText;
        }
    }

    private int _languageType = 0;
    public int languageType { get { return _languageType; } set { _languageType = value; } }

    // Use this for initialization
    void Start()
    {
        TextLocalizer.ExecLocalizeText(this, textKey);
    }

    private void OnEnable()
    {
        TextLocalizer.ExecLocalizeText(this, textKey);
        TextLocalizer.RegisterText(this, textKey);
    }

    private void OnDisable()
    {
        TextLocalizer.UnRegisterText(this);
    }

    private void OnDestroy()
    {
        TextLocalizer.UnRegisterText(this);
    }

#if UNITY_EDITOR
    void OnDrawGizmos()
    {
        Gizmos.color = Color.red;
        Gizmos.DrawSphere(transform.position, 15);
    }
#endif
}
