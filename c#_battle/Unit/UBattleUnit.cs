using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class LUBattleUnit
{
    public static T Init<T>(T unit, int unitId, bool autoBegin = true) where T : UBattleUnit
    {
        if (unit == null)
        {
            return null;
        }
        unit.unitId = unitId;
        unit.BindGameLoop(UBattle.LOOPER);
        if (autoBegin)
        {
            unit.Begin();
        }
        return unit;
    }

    public static void Destroy(int unitId)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.Destroy();
    }

    public static void End(int unitId, int eventNameId)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.End(GameStrings.Get(eventNameId));
    }

    public static void SetUnitId(int unitId, int newUnitId)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.SetUnitId(newUnitId);
    }

    public static void FireUnitEvent(int unitId, int eventNameId)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.FireUnitEvent(GameStrings.Get(eventNameId));
    }

    public static void FireUnitEvent(int unitId, string eventName)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.FireUnitEvent(eventName);
    }

    public static void OnUnitTeleport(int unitId)
    {
        ObjectCache.GetComponent<UBattleUnit>(unitId)?.OnTeleport();
    }
}

[SLua.CustomLuaClass]
[RequireComponent(typeof(PoolGameObject))]
[RequireComponent(typeof(UBones))]
public class UBattleUnit : USortingLayer
{
    public static Comparison<UBattleUnit> PositionComparer = ComparePosition;

    [SerializeField]
    private int _unitId = 0;
    public int unitId
    {
        get
        {
            return _unitId;
        }
        set
        {
            OnUnitIdChange(value);
            _unitId = value;
        } 
    }

    [SerializeField]
    private List<GameLoopChild> _loopChildList = new List<GameLoopChild>();

    [SerializeField]
    protected UIEvent _uiEvent = null;
    public UIEvent uiEvent
    {
        get
        {
            if (_uiEvent == null)
            {
                _uiEvent = GetComponent<UIEvent>();
            }
            return _uiEvent;
        }
    }

    [SerializeField]
    private CacheObject _objTop;
    public GameObject objTop { get { return _objTop.cacheObject.gameObject; } }
    public Transform transTop { get { return _objTop.cacheObject.transform; } }
    public int objTopId { get { return _objTop.cacheObject.cacheId; } }

    [SerializeField]
    private CacheObject _objBottom;
    public GameObject objBottom { get { return _objBottom.cacheObject.gameObject; } }
    public Transform transBottom { get { return _objBottom.cacheObject.transform; } }
    public int objBottomId { get { return _objBottom.cacheObject.cacheId; } }

    [SerializeField]
    protected bool _isAutoSort = false;

    [SerializeField]
    protected bool _isEndDestroy = false;

    protected float _curDirectionAngle = -1.0f;
    public float curDirectionAngle { get { return _curDirectionAngle; } }

    protected float _logicPosition = 0.0f;
    protected float _posZFactor = 1.0f;

    protected int _teleportFlag = -1;
    public int teleportFlag { get { return _teleportFlag; } set { _teleportFlag = value; } }

    private UBones _bones = null;
    private UBones bones
    {
        get
        {
            if (_bones == null)
            {
                _bones = GetComponent<UBones>();
            }
            return _bones;
        }
    }

    private Transform _transform;
    public new Transform transform
    {
        get
        {
            if (_transform == null)
            {
                _transform = this.gameObject.transform;
            }
            return _transform;
        }
    }

    protected virtual void Awake()
    {
        
    }

    protected virtual void OnDestroy()
    {
        unitId = 0;
    }

    protected virtual void OnUnitIdChange(int value)
    {
        if (value == 0 && _unitId != 0)
        {
            ObjectCache.UnRegist(_unitId, this);
        }
        else if (value != 0 && _unitId != value)
        {
            ObjectCache.UnRegist(_unitId, this);
            ObjectCache.Regist(value, this);
        }
    }

    public void FireUnitEvent(string name)
    {
        if (!string.IsNullOrEmpty(name))
        {
            uiEvent?.FireUIEvent(name);
        }
    }

    public void FireUnitEvent(SLua.LuaTable eventList)
    {
        if (eventList != null)
        {
            for (int i = 1; i <= eventList.length(); i++)
            {
                uiEvent?.FireUIEvent(eventList[i].ToString());
            }
        }
    }

    public Transform GetBoneTransform(BoneType type)
    {
        return bones?.GetBoneTransform(type);
    }

    public Transform GetBoneTransform(string boneName)
    {
        return bones?.GetBoneTransform(boneName);
    }

    public Vector3 GetBonePosition(BoneType type)
    {
        return bones == null ? this.transform.position : bones.GetBonePosition(type);
    }

    public Vector3 GetBonePosition(string boneName)
    {
        return bones == null ? this.transform.position : bones.GetBonePosition(boneName);
    }

    public void BindGameLoop(GameLoop looper)
    {
        foreach (var child in _loopChildList)
        {
            child.BindGameLoop(looper);
        }
    }

    public virtual void SetPosition(float x, float y, float zFactor, int direction, float logicPosition)
    {
        var position = transform.position;
        position.x = x;
        position.y = y;
        transform.position = position;

        _posZFactor = zFactor;
        _logicPosition = logicPosition;
    }

    public virtual void Sort(int sortIndex)
    {
        var localPosition = transform.localPosition;
        localPosition.z = _posZFactor * 100 * sortIndex;
        transform.localPosition = localPosition;
    }

    public void Begin()
    {
        _teleportFlag = -1;
        _uiEvent?.FireUIEvent(UIEventType.OnStart);
        if(_isAutoSort)
        {
            UBattle.INSTANCE?.AddSortUnit(this);
        }
    }

    public void End(string endEvent)
    {
        if (!string.IsNullOrEmpty(endEvent))
        {
            _uiEvent?.FireUIEvent(endEvent);
        }
        _uiEvent?.FireUIEvent(UIEventType.OnEnd);

        if (_isEndDestroy)
        {
            Destroy();
        }
    }

    public void Destroy()
    {
        _uiEvent?.FireUIEvent(UIEventType.OnDestroy);
        if (_isAutoSort)
        {
            UBattle.INSTANCE?.RemoveSortUnit(this);
        }
        unitId = 0;
    }

    public virtual void SetUnitId(int unitId)
    {
        this.unitId = unitId;
    }

    public static int ComparePosition(UBattleUnit leftUnit, UBattleUnit rightUnit)
    {
        var result = -leftUnit._logicPosition.CompareTo(rightUnit._logicPosition);
        if (result != 0)
        {
            return result;
        }
        return leftUnit.unitId.CompareTo(rightUnit.unitId);
    }

    public void OnTeleport()
    {
        _teleportFlag++;
    }
}
