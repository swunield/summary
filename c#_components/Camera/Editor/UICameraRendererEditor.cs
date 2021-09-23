using UnityEditor;
using UnityEngine;

[CanEditMultipleObjects]
[CustomEditor(typeof(UICameraRenderer))]
public class UICameraRendererEditor : UICameraSortingEditor
{
    protected SerializedProperty _render;
    protected SerializedProperty _canvasScaler;

    protected override void OnEnable()
    {
        base.OnEnable();

        _render = serializedObject.FindProperty("_render");
        _canvasScaler = serializedObject.FindProperty("_canvasScaler");
    }

    public override void OnInspectorGUI()
    {
        EditorGUILayout.PropertyField(_render, new GUIContent("Renderer"));
        base.OnInspectorGUI();
    }
}
