using Spine.Unity;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public enum BoneType
{
    ROOT = 0,       // 脚下
    BODY,           // 身体
    HEAD,           // 头顶
    MISSILE,        // 子弹
    CENTER,         // 中心点
}

[SLua.CustomLuaClass]
public class UBones : MonoBehaviour
{
    private static string[] BoneNames = new string[] { "root", "body", "head", "missile", "center" }; 

    [SerializeField]
    private Transform _bonesRoot = null;

    private Dictionary<string, Transform> _bonesMap = new Dictionary<string, Transform>();

    private Transform _transform = null;

    private void Awake()
    {
        _transform = this.transform;
        InitBones();
    }

    protected void InitBones()
    {
        var transBones = _bonesRoot == null ? _transform.Find("bones") : _bonesRoot;
        if (transBones == null)
        {
            return;
        }
        _bonesMap.Clear();
        for (int i = 0; i < transBones.childCount; i++)
        {
            var transBone = transBones.GetChild(i);
            _bonesMap.Add(transBone.name, transBone);
        }
    }

    public Transform GetBoneTransform(BoneType type)
    {
        return GetBoneTransform(BoneNames[type.ToInt()]);
    }

    public Vector3 GetBonePosition(BoneType type)
    {
        return GetBonePosition(BoneNames[type.ToInt()]);
    }

    public Transform GetBoneTransform(string boneName)
    {
        Transform boneTransform = null;
        if (_bonesMap.TryGetValue(boneName, out boneTransform))
        {
            return boneTransform;
        }
        return _transform;
    }

    public Vector3 GetBonePosition(string boneName)
    {
        var transform = GetBoneTransform(boneName);
        return transform.position;
    }
}
