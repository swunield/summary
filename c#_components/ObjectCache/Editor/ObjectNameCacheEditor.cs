using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(ObjectNameCache))]
public class ObjectNameCacheEditor : Editor
{
    public override void OnInspectorGUI()
    {
        serializedObject.Update();
        SerializedProperty objectNameList = serializedObject.FindProperty("_objectNameList");
        SerializedProperty objectName;
        //---- [1]开始垂直布局 ----
        EditorGUILayout.BeginVertical();
        for (int index = 0; index < objectNameList.arraySize; index++)
        {
            objectName = objectNameList.GetArrayElementAtIndex(index);
            //---- [2]开始水平布局 ----
            EditorGUILayout.BeginHorizontal();
            //索引
            EditorGUILayout.LabelField((index + 1).ToString(), GUILayout.Width(30));
            //监听是否更改
            GUI.changed = false;
            //自定义命名
            objectName.stringValue = EditorGUILayout.TextField(objectName.stringValue);
            if (GUILayout.Button("X"))
            {
                FTDebug.LogWarning($"Delete {index} {objectNameList.GetArrayElementAtIndex(index).stringValue}");
                objectNameList.DeleteArrayElementAtIndex(index);
                serializedObject.ApplyModifiedProperties();
                AssetDatabase.SaveAssets();
                GUIUtility.ExitGUI();
            }
            EditorGUILayout.EndHorizontal();
            //---- [2]结束水平布局 ----
        }
        //新增按钮
        if (GUILayout.Button("新增", GUILayout.MaxHeight(30)))
        {
            objectNameList.InsertArrayElementAtIndex(objectNameList.arraySize);
            objectName = objectNameList.GetArrayElementAtIndex(objectNameList.arraySize - 1);
            objectName.stringValue = "";
            serializedObject.ApplyModifiedProperties();
            AssetDatabase.SaveAssets();
        }
        //新增按钮
        if (GUILayout.Button("导出", GUILayout.MaxHeight(40)))
        {
            // 去重
            CheckSameName(serializedObject, objectNameList);
            GenerateLuaFile(objectNameList);
        }
        //---- [2]开始水平布局 ----
        EditorGUILayout.Space();
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.EndHorizontal();
        //---- [2]结束水平布局 ----
        EditorGUILayout.HelpBox("每次新增组件名字后，需要重新生成Lua枚举文件", MessageType.Info);
        EditorGUILayout.EndVertical();
        //---- [1]结束垂直布局 ----
        serializedObject.ApplyModifiedProperties();
    }

    private void CheckSameName(SerializedObject serializedObject, SerializedProperty objectNameList)
    {
        var nameMap = new Dictionary<string, int>();
        var count = objectNameList.arraySize;
        for (int i = count - 1; i >= 0; i--)
        {
            var objectName = objectNameList.GetArrayElementAtIndex(i);
            if (string.IsNullOrEmpty(objectName.stringValue) || nameMap.ContainsKey(objectName.stringValue))
            {
                objectNameList.DeleteArrayElementAtIndex(i);
                continue;
            }
            nameMap.Add(objectName.stringValue, 1);
        }
        serializedObject.ApplyModifiedProperties();
        AssetDatabase.SaveAssets();
    }

    [MenuItem("Tools/UI Name")]
    public static void SelectUIName()
    {
        Selection.activeObject = AssetDatabase.LoadAssetAtPath<ObjectNameCache>("Assets/Game/ui/other/settings/ui_name.asset");
    }

    [MenuItem("Assets/ObjectCache/Create Object Name Cache")]
    public static void CreateObjectNameCache()
    {
        var selectObjects = Selection.GetFiltered(typeof(Object), SelectionMode.TopLevel | SelectionMode.Assets);
        if (selectObjects == null || selectObjects.Length == 0)
        {
            FTDebug.LogWarning($"CreateObjectNameCache - Cannot find select objects");
            return;
        }
        var objFolder = selectObjects.FirstOrDefault(obj => Directory.Exists(AssetDatabase.GetAssetPath(obj)));
        if (objFolder == null)
        {
            FTDebug.LogWarning($"CreateObjectNameCache - Cannot find select folder object");
            return;
        }
        AssetDatabase.CreateAsset(new ObjectNameCache(), AssetDatabase.GetAssetPath(objFolder) + "/NewObjectNameCache.asset");
    }

    private static void GenerateLuaFile(SerializedProperty objectNameList)
    {
        var builder = new StringBuilder();
        builder.Append("-- UI组件名字\r\n");
        builder.Append("Global.UIName = {\r\n");
        for (int i = 0; i < objectNameList.arraySize; i++)
        {
            var objectName = objectNameList.GetArrayElementAtIndex(i);
            if (string.IsNullOrEmpty(objectName.stringValue))
            {
                continue;
            }
            builder.Append($"\t{objectName.stringValue} = {i+1},\r\n");
        }
        builder.Append("}\r\n");
        builder.Append("export('UIName', UIName)");
        File.WriteAllText("Assets/LuaPlugins/gameres/res/UIName.lua", builder.ToString());
    }
}
