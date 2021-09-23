using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.UI;
#if UNITY_EDITOR
using UnityEditor;
#endif

[ExecuteInEditMode]
[RequireComponent(typeof(Canvas))]
public class UICameraCanvas : UICameraSorting
{
    [SerializeField]
    private Canvas _canvas = null;
    public Canvas canvas
    {
        get
        {
            if (_canvas == null)
            {
                _canvas = GetComponent<Canvas>();
            }
            return _canvas;
        }
    }

    [SerializeField]
    private CanvasScaler _canvasScaler = null;
    public CanvasScaler canvasScaler
    {
        get
        {
            if (_canvasScaler == null)
            {
                _canvasScaler = GetComponent<CanvasScaler>();
            }
            return _canvasScaler;
        }
    }

    protected override void Awake()
    {
#if UNITY_EDITOR
        if (!EditorApplication.isPlaying)
        {
            this.gameObject.layer = LayerMask.NameToLayer("UI");
            canvas.renderMode = RenderMode.ScreenSpaceCamera;
            canvas.planeDistance = 200;
            canvas.pixelPerfect = false;
            if (canvas.sortingLayerName == "Default")
            {
                canvas.sortingLayerName = "UI";
            }
            if (canvasScaler != null)
            {
                canvasScaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
                canvasScaler.referenceResolution = new Vector2(1080, 1920);
                canvasScaler.screenMatchMode = CanvasScaler.ScreenMatchMode.Expand;
                var rectTransform = canvas.GetComponent<RectTransform>();
                rectTransform.sizeDelta = new Vector2(1080, 1920);
                rectTransform.localScale = new Vector3(1, 1, 1);
            }
        }
#endif
        base.Awake();
    }

    public override void UpdateSorting(int order)
    {
        canvas.sortingOrder = order;
        canvas.worldCamera = sortingGroup.uiCamera;
    }

#if UNITY_EDITOR
    public override void RefreshInEditor(int order, string layerName)
    {
        canvas.sortingOrder = order;
        canvas.sortingLayerName = layerName;
        base.RefreshInEditor(order, layerName);
    }
#endif
}
