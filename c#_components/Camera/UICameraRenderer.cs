using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(Renderer))]
public class UICameraRenderer : UICameraSorting
{
    [SerializeField]
    private Renderer _render = null;
    public Renderer render
    {
        get
        {
            if (_render == null)
            {
                _render = GetComponent<Renderer>();
            }
            return _render;
        }
    }

    protected override void Awake()
    {
#if UNITY_EDITOR
        this.gameObject.layer = LayerMask.NameToLayer("UI");
        if (render.sortingLayerName == "Default")
        {
            render.sortingLayerName = "UI";
        }
#endif
        base.Awake();
    }

    public override void UpdateSorting(int order)
    {
        render.sortingOrder = order;
    }

#if UNITY_EDITOR
    public override void RefreshInEditor(int order, string layerName)
    {
        render.sortingOrder = order;
        render.sortingLayerName = layerName;
        base.RefreshInEditor(order, layerName);
    }
#endif
}
