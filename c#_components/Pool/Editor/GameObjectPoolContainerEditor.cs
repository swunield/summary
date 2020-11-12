using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(GameObjectPoolContainer))]
class GameObjectPoolContainerEditor : Editor
{
    private Object _prefab = null;
    private string _prefabName = "";
    private SerializedProperty _prefabNameProp = null;
    private string _lastPath = null;

    private void Awake()
    {
        _prefabNameProp = serializedObject.FindProperty("prefabName");
        _prefabName = _prefabNameProp.stringValue;
        _prefabName = _prefabName.Replace("ui/other/prefabs/", "").Replace(".prefab", "");
        if (!string.IsNullOrEmpty(_prefabName))
        {
            _prefab = AssetDatabase.LoadAssetAtPath("Assets/Game/ui/other/prefabs/" + _prefabName + ".prefab", typeof(Object));
        }
    }

    public override void OnInspectorGUI()
    {
        base.OnInspectorGUI();

        _prefab = EditorGUILayout.ObjectField("预制体", _prefab, typeof(GameObject), false);
        var path = AssetDatabase.GetAssetPath(_prefab);
        _lastPath = _lastPath == null ? path : _lastPath;
        if (_lastPath != path)
        {
            _lastPath = path;
            _prefabName = _lastPath.Replace("Assets/Game/ui/other/prefabs/", "").Replace(".prefab", "");
            _prefabNameProp.stringValue = _prefabName;
            serializedObject.ApplyModifiedProperties();
            Debug.LogWarning(_lastPath + " " + _prefabName);
        }
    }
}
