using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

[CanEditMultipleObjects]
[CustomEditor(typeof(UICameraSorting))]
public class UICameraSortingEditor : Editor
{
    protected SerializedProperty _sortingMode;
    protected SerializedProperty _bindMode;
    protected SortingLayerProperty.SerializedSortingProperties sortingProperties;

    protected virtual void OnEnable()
    {
        _sortingMode = serializedObject.FindProperty("_sortingMode");
        _bindMode = serializedObject.FindProperty("_bindMode");

        var rendererSerializedObject = SortingLayerProperty.GetRenderersSerializedObject(serializedObject);
        sortingProperties = new SortingLayerProperty.SerializedSortingProperties(rendererSerializedObject);
    }

    public override void OnInspectorGUI()
    {
        EditorGUILayout.PropertyField(_sortingMode, new GUIContent("Sorting Mode"));
        EditorGUILayout.PropertyField(_bindMode, new GUIContent("Bind Mode"));

        if (SortingLayerProperty.SortingPropertyFields(sortingProperties, true))
        {
            var sortingOrder = sortingProperties.sortingOrder.intValue;
            var sortingLayerName = SortingLayer.IDToName(sortingProperties.sortingLayerID.intValue);
            foreach (var target in targets)
            {
                var item = target as UICameraSorting;
                item.RefreshInEditor(sortingOrder, sortingLayerName);
            }
        }

        serializedObject.ApplyModifiedProperties();
    }
}
