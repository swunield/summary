using UnityEditor;
using UnityEngine;

[CanEditMultipleObjects]
[CustomEditor(typeof(UICameraCanvas))]
public class UICameraCanvasEditor : UICameraSortingEditor
{
    protected SerializedProperty _canvas;
    protected SerializedProperty _canvasScaler;

    protected override void OnEnable()
    {
        base.OnEnable();

        _canvas = serializedObject.FindProperty("_canvas");
        _canvasScaler = serializedObject.FindProperty("_canvasScaler");
    }

    public override void OnInspectorGUI()
    {
        EditorGUILayout.PropertyField(_canvas, new GUIContent("Canvas"));
        EditorGUILayout.PropertyField(_canvasScaler, new GUIContent("Canvas Scaler"));

        base.OnInspectorGUI();
    }
}
