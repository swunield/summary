using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
[DisallowMultipleComponent]
public class USortingLayer : MonoBehaviour
{
    protected bool _isTopLayer = false;
    public bool isTopLayer { get { return _isTopLayer; } }

    public virtual void MoveSortingLayerToTop()
    {
        if (_isTopLayer)
        {
            return;
        }
        _isTopLayer = true;

        var items = this.gameObject.GetComponentsInChildren<SortingLayerItem>(true);
        foreach (var item in items)
        {
            item.MoveToTopLayer();
        }
    }

    public virtual void RestoreSortingLayer()
    {
        if (!_isTopLayer)
        {
            return;
        }
        _isTopLayer = false;

        var items = this.gameObject.GetComponentsInChildren<SortingLayerItem>(true);
        foreach (var item in items)
        {
            item.RestoreLayer();
        }
    }
}
