using System;
using System.Collections;
using System.Collections.Generic;
using UAnimation;
using UnityEngine;

[SLua.CustomLuaClass]
public class LUBattleEffect
{
    // 全局Effect结束回调
    public static Action<int, bool> OnEffectEndCallBack = null;

    public static UBattleEffect Get(int effectId)
    {
        return UBattleEffect.BattleEffectMap.ContainsKey(effectId) ? UBattleEffect.BattleEffectMap[effectId] : null;
    }

    public static UBattleEffect Create(int effectId, int prefabNameId, int prefabFolderId, int objParentId, bool isTop)
    {
        var parentUnit = ObjectCache.GetComponent<UBattleUnit>(objParentId);
        if (parentUnit == null)
        {
            return null;
        }
        var prefabName = GameStrings.Get(prefabNameId);
        var prefabFolder = GameStrings.Get(prefabFolderId);
        var parent = isTop ? parentUnit.transTop : parentUnit.transBottom;
        var uEffect = GameObjectPool.INSTANCE.RequestComponent<UBattleEffect>(prefabName, prefabFolder, true, parent);
        if (uEffect == null)
        {
            return null;
        }
        uEffect.effectId = effectId;
        return uEffect;
    }

    public static int Play(int effectId, int prefabNameId, int prefabFolderId, int objParentId, bool isTop, int unitId)
    {
        var uEffect = Create(effectId, prefabNameId, prefabFolderId, objParentId, isTop);
        if (uEffect == null)
        {
            return 0;
        }
        var battleUnit = ObjectCache.GetComponent<UBattleUnit>(unitId);
        if (battleUnit == null)
        {
            return 0;
        }
        uEffect.Play(battleUnit);
        return effectId;
    }

    public static int Fire(int effectId, int prefabNameId, int prefabFolderId, int objParentId, bool isTop, int startUnitId, int endUnitId, float duration, int easeNameId)
    {
        var uEffect = Create(effectId, prefabNameId, prefabFolderId, objParentId, isTop);
        if (uEffect == null)
        {
            return 0;
        }
        var startUnit = ObjectCache.GetComponent<UBattleUnit>(startUnitId);
        if (startUnit == null)
        {
            return 0;
        }
        var endUnit = ObjectCache.GetComponent<UBattleUnit>(endUnitId);
        if (endUnit == null)
        {
            return 0;
        }
        uEffect.Fire(startUnit, endUnit, duration, GameStrings.Get(easeNameId));
        return effectId;
    }

    public static void Stop(int effectId, bool isFinish)
    {
        var uEffect = Get(effectId);
        uEffect?.Stop(isFinish);
    }

    public static void Restart(int effectId)
    {
        var uEffect = Get(effectId);
        uEffect?.Restart();
    }

    public static void FireEvent(int effectId, int eventNameId)
    {
        var uEffect = Get(effectId);
        uEffect?.FireEvent(GameStrings.Get(eventNameId));
    }
}

[RequireComponent(typeof(PoolGameObject))]
[RequireComponent(typeof(USortingLayer))]
public class UBattleEffect : GameLoopChild
{
    // 全局Effect缓存
    public static Dictionary<int, UBattleEffect> BattleEffectMap = new Dictionary<int, UBattleEffect>();

    [SerializeField]
    protected int _effectId = 0;
    public int effectId
    {
        get
        {
            return _effectId;
        }
        set
        {
            if (value == 0 && _effectId != 0)
            {
                BattleEffectMap.Remove(_effectId);
            }
            else if (_effectId == 0 && value != 0)
            {
                BattleEffectMap[value] = this;
            }
            _effectId = value;
        }
    }

    [SerializeField]
    protected UIEvent _uiEvent;

    [SerializeField]
    protected float _duration = -1;

    [SerializeField]
    protected string _easeName = "";

    [SerializeField]
    protected string _targetBoneName = "";

    [SerializeField]
    protected bool _followTargetScale = false;

    [SerializeField]
    protected bool _autoRotate = false;

    [SerializeField]
    protected bool _isEndDestroy = true;

    [SerializeField]
    protected int _delayTime = 0;

    [SerializeField]
    protected USortingLayer _sortingLayer;
    public USortingLayer sortingLayer
    {
        get
        {
            if (_sortingLayer == null)
            {
                _sortingLayer = GetComponent<USortingLayer>();
            }
            return _sortingLayer;
        }
    }

    [SerializeField]
    private List<GameLoopChild> _loopChildList = new List<GameLoopChild>();

    protected Transform _transStart = null;
    protected UBattleUnit _startUnit = null;
    protected int _startUnitId = 0;
    protected Vector3 _startPosition;

    protected Transform _transEnd = null;
    protected UBattleUnit _endUnit = null;
    protected int _endUnitId = 0;
    protected Vector3 _endPosition;
    protected int _endTeleportFlag = -1;

    protected Transform _transform = null;

    protected float _startTime = 0;
    public float startTime { get { return _startTime; } set { _startTime = value < -1 ? GetMSTime() : value; } }

    protected EaseFunction _easeFunc = null;
    protected bool _isEnded = false;

    protected float _startAngle = -1.0f;
    protected float _endAngle = -1.0f;

    protected Transform _extraTransform;
    protected UIFollower _extraFollower;

    protected float _stayTime = 0;
    protected float _stayStartTime = 0;
    protected int _delayTimeCounter = 0;

    public override void LoopUpdate(int msDelta, int msTime, float sDelta, float sTime)
    {
    }

    public void Play(UBattleUnit battleUnit)
    {
        this.BindGameLoop(loop);

        _startUnit = battleUnit;
        _endUnit = battleUnit;
        _endTeleportFlag = _endUnit.teleportFlag;

        _transform = this.transform;
        var position = battleUnit.GetBonePosition(_targetBoneName);
        position.z = _transform.position.z;
        _transform.position = position;

        if (_followTargetScale)
        {
            _transform.localScale = battleUnit.transform.localScale;
        }

        _isEnded = false;
        _delayTimeCounter = _delayTime;

        this.OnEffectStart();
    }

    public void Stay()
    {
        if (_stayStartTime != 0)
        {
            return;
        }
        _stayStartTime = GetMSTime();
    }

    public void Forward()
    {
        if (_stayStartTime == 0)
        {
            return;
        }
        _stayTime += GetMSTime() - _stayStartTime;
        _stayStartTime = 0;
    }

    public void Restart()
    {
        _startTime = GetMSTime() + _delayTimeCounter;
        _delayTimeCounter = 0;
        OnEffectStart();
    }

    public void Stop(bool isFinish)
    {
        OnEffectEnd(isFinish);
    }

    public virtual void Fire(UBattleUnit startUnit, UBattleUnit endUnit, float duration, string easeName = null)
    {
        this.BindGameLoop();

        _transStart = startUnit.GetBoneTransform("missile");
        _startUnit = startUnit;
        _startUnitId = startUnit.unitId;
        _startPosition = _transStart.position;
        _startAngle = _startUnit.curDirectionAngle;

        _transEnd = string.IsNullOrEmpty(_targetBoneName) ? endUnit.GetBoneTransform("body") : endUnit.GetBoneTransform(_targetBoneName);
        _endUnit = endUnit;
        _endUnitId = _endUnit.unitId;
        _endTeleportFlag = _endUnit.teleportFlag;

        _duration = duration <= 0 ? _duration : duration;
        _startTime = GetMSTime();
        _easeName = string.IsNullOrEmpty(easeName) ? _easeName : easeName;
        _easeFunc = EaseFunc.GetFunction(easeName);

        _transform = this.transform;
        _transform.position = _startPosition;

        _isEnded = false;
        _delayTimeCounter = _delayTime;

        this.OnEffectStart();
    }

    public virtual void Fire(UBattleUnit startUnit, Vector3 endPosition, float duration, string easeName = null)
    {
        this.BindGameLoop();

        _transStart = startUnit.GetBoneTransform("missile");
        _startUnit = startUnit;
        _startUnitId = startUnit.unitId;
        _startPosition = _transStart.position;
        _startAngle = _startUnit.curDirectionAngle;

        _transEnd = null;
        _endUnit = null;
        _endUnitId = 0;
        _endPosition = endPosition;
        _endTeleportFlag = -1;

        _duration = duration <= 0 ? _duration : duration;
        _startTime = GetMSTime();
        _easeName = string.IsNullOrEmpty(easeName) ? _easeName : easeName;
        _easeFunc = EaseFunc.GetFunction(easeName);

        _transform = this.transform;
        _transform.position = _startPosition;

        _isEnded = false;
        _delayTimeCounter = _delayTime;

        this.OnEffectStart();
    }

    public virtual void Fire(GameObject objStart, UBattleUnit endUnit, float duration, string easeName = null)
    {
        this.BindGameLoop();

        _transStart = objStart.transform;
        _startUnit = null;
        _startUnitId = 0;
        _startPosition = _transStart.position;
        _startAngle = -1.0f;

        _transEnd = endUnit.transform;
        _endUnit = endUnit;
        _endUnitId = _endUnit.unitId;
        _endTeleportFlag = _endUnit.teleportFlag;

        _duration = duration <= 0 ? _duration : duration;
        _startTime = GetMSTime();
        _easeName = string.IsNullOrEmpty(easeName) ? _easeName : easeName;
        _easeFunc = EaseFunc.GetFunction(easeName);

        _transform = this.transform;
        _transform.position = _startPosition;

        _isEnded = false;
        _delayTimeCounter = _delayTime;

        this.OnEffectStart();
    }

    public virtual void Fire(GameObject objStart, Vector3 endPosition, float duration, string easeName = null)
    {
        this.BindGameLoop();

        _transStart = objStart.transform;
        _startUnit = null;
        _startUnitId = 0;
        _startPosition = _transStart.position;
        _startAngle = -1.0f;

        _transEnd = null;
        _endUnit = null;
        _endUnitId = 0;
        _endPosition = endPosition;
        _endTeleportFlag = -1;

        _duration = duration <= 0 ? _duration : duration;
        _startTime = GetMSTime();
        _easeName = string.IsNullOrEmpty(easeName) ? _easeName : easeName;
        _easeFunc = EaseFunc.GetFunction(easeName);

        _transform = this.transform;
        _transform.position = _startPosition;

        _isEnded = false;
        _delayTimeCounter = _delayTime;

        this.OnEffectStart();
    }

    protected void OnDisable()
    {
        this.TryUnBindGameLoop();
    }

    protected virtual bool OnEffectStart()
    {
        if (_delayTimeCounter > 0)
        {
            return false;
        }

        _stayStartTime = 0;
        _stayTime = 0;

        this.AutoRotate();

        FireEvent(UIEventType.OnStart);

        return true;
    }

    protected void OnEffectEnd(bool isFinish = true)
    {
        if (_isEnded)
        {
            return;
        }

        _isEnded = true;

        LUBattleEffect.OnEffectEndCallBack?.Invoke(effectId, isFinish);
        this.TryUnBindGameLoop();

        if (isFinish)
        {
            FireEvent(UIEventType.OnEndSuccess);
        }
        else
        {
            FireEvent(UIEventType.OnEndFailed);
        }
        FireEvent(UIEventType.OnEnd);

        if (_isEndDestroy)
        {
            FireEvent(UIEventType.OnDestroy);
        }

        effectId = 0;
    }

    protected float EaseValue(float time)
    {
        if (_easeFunc == null)
        {
            return time;
        }
        return _easeFunc(time);
    }

    protected Vector3 GetEndPosition()
    {
        return _transEnd != null ? _transEnd.position : _endPosition;
    }

    protected void AutoRotate(bool useCurrentPosition = false)
    {
        if (!_autoRotate)
        {
            _endAngle = _startAngle;
            return;
        }
        var startPos = useCurrentPosition ? _transform.position : _startPosition;
        var angle = UGameTools.GetPosAngle(_startPosition, GetEndPosition());
        if (_startAngle < 0)
        {
            _transform.localEulerAngles = new Vector3(0, 0, angle);
            _endAngle = _startAngle;
        }
        else
        {
            _transform.localEulerAngles = new Vector3(0, 0, _startAngle);
            _endAngle = angle;
            if (_endAngle - _startAngle > 180.0f)
            {
                _endAngle -= 360.0f;
            }
            else if (_startAngle - _endAngle > 180.0f)
            {
                _endAngle += 360.0f;
            }
        }
    }

    public void MoveSortingLayerToTop()
    {
        sortingLayer?.MoveSortingLayerToTop();
    }

    public void RestoreSortingLayer()
    {
        sortingLayer?.RestoreSortingLayer();
    }

    public void FollowStartUnit(bool isTop)
    {
        if (_startUnit == null)
        {
            return;
        }
        _transform.SetParent(isTop ? _startUnit.transTop : _startUnit.transBottom, false);
    }

    public void FollowEndUnit(bool isTop)
    {
        if (_endUnit == null)
        {
            return;
        }
        _transform.SetParent(isTop ? _endUnit.transTop : _endUnit.transBottom, false);
    }

    public void SetExtraTransform(Transform transform)
    {
        _extraTransform = transform;
    }

    public void SetExtraPositionBone(string boneName)
    {
        try
        {
            _extraTransform.position = _endUnit.GetBonePosition(boneName);
        }
        catch(Exception ex)
        {
            FTDebug.LogError($"SetExtraPositionBone Error {this.gameObject.name} {ex.Message} {ex.StackTrace}", true);
        }
    }

    public void SetExtraFollower(UIFollower follower)
    {
        _extraFollower = follower;
    }

    public void SetExtraFollowerBoneName(string boneName)
    {
        try
        {
            _extraFollower.target = _endUnit.GetBoneTransform(boneName);
        }
        catch (Exception ex)
        {
            FTDebug.LogError($"SetExtraFollowerBoneName Error {this.gameObject.name} {ex.Message} {ex.StackTrace}", true);
        }
    }

    public void PlayTween(string tweenName)
    {
        GOUtils.PlayTween(this.gameObject, tweenName, false, _duration == -1 ? 0 : _duration * 0.001f);
    }

    public void BindGameLoop()
    {
        base.BindGameLoop(UBattle.LOOPER);
        foreach (var child in _loopChildList)
        {
            child.BindGameLoop(UBattle.LOOPER);
        }
    }

    public override void TryUnBindGameLoop()
    {
        base.TryUnBindGameLoop();
        foreach (var child in _loopChildList)
        {
            child.TryUnBindGameLoop();
        }
    }

    public void RefreshStartTime()
    {
        _startTime = GetMSTime() + _delayTimeCounter;
        _delayTimeCounter = 0;
    }

    public void FireEvent(UIEventType type)
    {
        _uiEvent?.FireUIEvent(type);
    }

    public void FireEvent(string name)
    {
        _uiEvent?.FireUIEvent(name);
    }

    public void FireStartUnitEvent(string name)
    {
        _startUnit?.FireUnitEvent(name);
    }

    public void FireEndUnitEvent(string name)
    {
        _endUnit?.FireUnitEvent(name);
    }
}
