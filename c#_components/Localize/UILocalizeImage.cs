using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public class UILocalizeImage : Image
{
    [SerializeField]
    private string _imagePath = "";
    public string imagePath { get { return _imagePath; } set { _imagePath = value; } }

    [SerializeField]
    private string _imageExt = ".png";
    public string imageExt { get { return _imageExt; } set { _imageExt = value; } }

    [SerializeField]
    private string _imageFolder = "";
    public string imageFolder { get { return _imageFolder; } set { _imageFolder = value; } }

    private int _languageType = 0;
    public int languageType { get { return _languageType; } set { _languageType = value; } }

    protected override void Start()
    {
        base.Start();

        _languageType = ImageLocalizer.GetDefaultLanguageType();
        ImageLocalizer.ExecLocalizeImage(this, _imagePath, _imageExt, _imageFolder);
    }

    protected override void OnEnable()
    {
        base.OnEnable();

        ImageLocalizer.ExecLocalizeImage(this, _imagePath, _imageExt, _imageFolder);
        ImageLocalizer.RegisterImage(this, _imagePath, _imageExt, _imageFolder);
    }

    protected override void OnDisable()
    {
        ImageLocalizer.UnRegisterImage(this);

        base.OnDisable();
    }

    protected override void OnDestroy()
    {
        ImageLocalizer.UnRegisterImage(this);

        base.OnDestroy();
    }
}
