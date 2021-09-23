using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleTowerBase : MonoBehaviour
{
    [SerializeField]
    private List<UIEvent> _pointList = new List<UIEvent>();

    [SerializeField]
    private RendererLayoutGroup _normalPointLayoutGroup;

    [SerializeField]
    private int _maxLevel = 7;

    [SerializeField]
    private UIEvent _uiEvent = null;
    public UIEvent uiEvent
    {
        get
        {
            if (_uiEvent == null)
            {
                _uiEvent = GetComponent<UIEvent>();
            }
            return _uiEvent;
        }
    }

    private int _curLevel = 0;
    private List<MultiColorItem> _pointColorList = new List<MultiColorItem>();

    private void Awake()
    {
        for (int i = 0; i < _pointList.Count; i ++)
        {
            var colorItem = _pointList[i].GetComponent<MultiColorItem>();
            _pointColorList.Add(colorItem);
        }
    }

    public void SetLevel(int level)
    {
        if (_curLevel == level)
        {
            return;
        }
        _curLevel = level;

        _normalPointLayoutGroup?.gameObject.SetActive(_curLevel < _maxLevel);
        if (_maxLevel == _pointList.Count)
        {
            _pointList[_maxLevel - 1]?.gameObject.SetActive(_curLevel == _maxLevel);
        }
        if (_curLevel < _maxLevel)
        {
            _normalPointLayoutGroup.Layout(_curLevel);
            for (int i = 0; i < _curLevel; i++)
            {
                _pointColorList[i]?.SwitchColor(level - 1);
            }
        }
    }

    public void Fire(int index)
    {
        if (_curLevel == _maxLevel && _curLevel <= _pointList.Count)
        {
            _pointList[_curLevel - 1]?.FireUIEvent("Fire");
            return;
        }
        if (index > _pointList.Count)
        {
            return;
        }
        _pointList[index - 1]?.FireUIEvent("Fire");
    }
}
