using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class UICameraSorting : MonoBehaviour
{
    public enum SortingMode
    { 
        Relative,       // 相对
        Absolute,       // 绝对
    }

    public enum GroupBindMode
    {
        Awake,          
        Enable,
        Manual,
    }

    [SerializeField]
    private SortingMode _sortingMode = SortingMode.Relative;
    public SortingMode sortingMode { get { return _sortingMode; } }

    [SerializeField]
    private GroupBindMode _bindMode = GroupBindMode.Awake;
    public GroupBindMode bindMode { get { return _bindMode; } }

    [SerializeField]
    protected string _sortingLayerName = "UI";
    public string sortingLayerName { get { return _sortingLayerName; } set { _sortingLayerName = value; } }

    [SerializeField]
    protected int _sortingOrder = 0;
    public int sortingOrder { get { return _sortingOrder; } set { _sortingOrder = value; } }

    protected UICameraSortingGroup _sortingGroup = null;
    public UICameraSortingGroup sortingGroup { get { return _sortingGroup; } }

    protected virtual void Awake()
    {
        if (bindMode == GroupBindMode.Awake)
        {
            BindGroup();
        }
    }

    protected void OnDestroy()
    {
        if (bindMode == GroupBindMode.Awake)
        {
            UnBindGroup();
        }
    }

    protected void OnEnable()
    {
        if (bindMode == GroupBindMode.Enable)
        {
            BindGroup();
        }
    }

    protected void OnDisable()
    {
        if (bindMode == GroupBindMode.Enable)
        {
            UnBindGroup();
        }
    }

    public virtual void UpdateSorting(int order)
    {
    }

    public void BindGroup()
    {
        BindGroup(GetComponentInParent<UICameraSortingGroup>());
    }

    public void BindGroup(UICameraSortingGroup sortingGroup)
    {
        if (sortingGroup == null || _sortingGroup == sortingGroup)
        {
            return;
        }
        if (_sortingGroup != null)
        {
            UnBindGroup();
        }
        _sortingGroup = sortingGroup;
        _sortingGroup.Bind(this);
        UpdateSorting(GetRealSortingOrder());
    }

    public void UnBindGroup()
    {
        if (_sortingGroup != null)
        {
            _sortingGroup.UnBind(this);
        }
        _sortingGroup = null;
    }

    public void BindAllChildGroup(Transform parent)
    {
        var sortingGroup = GetComponentInParent<UICameraSortingGroup>();
        var sortings = parent.GetComponentsInChildren<UICameraSorting>();
        var count = sortings.Length;
        for (int i = 0; i < count; i++)
        {
            sortings[i].BindGroup(sortingGroup);
        }
    }

    public void UnBindAllChildGroup(Transform parent)
    {
        var sortings = parent.GetComponentsInChildren<UICameraSorting>();
        var count = sortings.Length;
        for (int i = 0; i < count; i++)
        {
            sortings[i].UnBindGroup();
        }
    }

    public int GetRealSortingOrder()
    {
        switch(_sortingMode)
        {
            case SortingMode.Absolute:
                {
                    return sortingOrder;
                }
            default:
                {
                    return _sortingGroup.baseSortingOrder + sortingOrder;
                }
        }
    }

#if UNITY_EDITOR
    public virtual void RefreshInEditor(int order, string layerName)
    {
        _sortingOrder = order;
        _sortingLayerName = layerName;
    }
#endif
}
