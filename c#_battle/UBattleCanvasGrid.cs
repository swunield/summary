using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleCanvasGrid : MonoBehaviour
{
    [SerializeField]
    private GameObject _objGrid;
    public GameObject objGrid
    {
        get
        {
            return _objGrid;
        }
    }

    [SerializeField]
    private GameObject _objDrager;
    public GameObject objDrager
    {
        get
        {
            return _objDrager;
        }
    }

    [SerializeField]
    private UIDragEvent _dragEvent;
    public UIDragEvent dragEvent
    {
        get
        {
            return _dragEvent;
        }
    }

    [SerializeField]
    private GameObject _objTower;
    public GameObject objTower
    {
        get
        {
            return _objTower;
        }
    }

    private bool _isDragTowerInit = false;

    private void Awake()
    {
        if (_objTower != null)
        {
            BindDragTower(_objTower);
        }
    }

    public void BindDragTower(GameObject objTower)
    {
        if (objTower == null || _dragEvent == null)
        {
            return;
        }

        _dragEvent.followerTransform = objTower.transform;

        InitDragTower();
    }

    public void InitDragTower()
    {
        if (_isDragTowerInit)
        {
            return;
        }

        if (_dragEvent == null)
        {
            return;
        }

        _dragEvent.AddUIEventListener(UIEventType.OnDragBegin, () => {
            if (_dragEvent.followerTransform == null)
            {
                return;
            }
            var uContainer = _dragEvent.followerTransform.GetComponent<UBattleTowerContainer>();
            uContainer?.MoveSortingLayerToTop();
        }, true);

        _dragEvent.AddUIEventListener(UIEventType.OnDragEnd, () => {
            if (_dragEvent.followerTransform == null)
            {
                return;
            }
            var uContainer = _dragEvent.followerTransform.GetComponent<UBattleTowerContainer>();
            uContainer?.RestoreSortingLayer();
        }, true);

        _isDragTowerInit = true;
    }

    public void Restore()
    {
        _dragEvent?.Restore();
    }
}
