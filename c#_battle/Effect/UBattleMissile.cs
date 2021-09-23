using System;
using System.Collections;
using System.Collections.Generic;
using UAnimation;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleMissile : UBattleEffect
{
    [SerializeField]
    private float _maxParabolaHeight = 0;

    [SerializeField]
    private float _parabolaLimitFactor = 0.33f;

    [SerializeField]
    private EaseFuncSelector _parabolaEase = new EaseFuncSelector();

    [SerializeField]
    private bool _parabolaAutoRotate = false;

    [SerializeField]
    private bool _parbolaHalfTimeEase = true;

    private EaseFunction _parabolaEaseFunc = null;
    private Vector3 _parabolaOffset = Vector3.zero;

    public override void LoopUpdate(int msDelta, int msTime, float sDelta, float sTime)
    {
        if (_delayTimeCounter > 0)
        {
            _delayTimeCounter-=msDelta;
            if (_delayTimeCounter > 0)
            {
                return;
            }
            _startPosition = _transStart != null ? _transStart.position : _startPosition;
            OnEffectStart();
        }

        if (_isEnded || _stayStartTime != 0)
        {
            return;
        }
        var flyTime = msTime - _startTime - _stayTime;
        if (flyTime <= 0)
        {
            return;
        }
        if (_endUnit != null && _endUnit.unitId != _endUnitId)
        {
            OnEffectEnd(false);
            return;
        }
        var endPosition = GetEndPosition();
        if (flyTime >= _duration)
        {
            _transform.position = endPosition;
            OnEffectEnd(true);
            return;
        }

        var time = flyTime / _duration;
        var percent = EaseValue(time);
        var lastPosition = _transform.position;
        _transform.position = GetPosition(time, percent, _startPosition, endPosition);
        
        if (_parabolaAutoRotate)
        {
            if (time > 0)
            {
                _transform.localEulerAngles = new Vector3(0, 0, UGameTools.GetPosAngle(lastPosition, _transform.position));
            }
        }
        else
        {
            if (_startAngle != _endAngle)
            {
                _transform.localEulerAngles = new Vector3(0, 0, _startAngle + (_endAngle - _startAngle) * percent);
            }
            else if (_endTeleportFlag != -1 && _endUnit.teleportFlag != _endTeleportFlag)
            {
                _endTeleportFlag = _endUnit.teleportFlag;
                AutoRotate(true);
            }
        }
    }

    private Vector3 GetPosition(float time, float percent,  Vector3 startPosition, Vector3 endPosition)
    {
        var position = startPosition + (endPosition - startPosition) * percent;
        if (_parabolaOffset != Vector3.zero)
        {
            position += _parabolaOffset * ParabolaEaseValue(time);
            if (endPosition.x - startPosition.x > 0)
            {
                position.x = position.x < startPosition.x ? startPosition.x : position.x;
            }
            else
            {
                position.x = position.x > startPosition.x ? startPosition.x : position.x;
            }
        }
        return position;
    }

    protected override bool OnEffectStart()
    {
        if (!base.OnEffectStart())
        {
            return false;
        }

        if (_startUnit != null && _startUnit.isTopLayer)
        {
            this.MoveSortingLayerToTop();
        }
        else
        {
            this.RestoreSortingLayer();
        }

        this.OnParabolaStart();

        return true;
    }

    private void OnParabolaStart()
    {
        if (_maxParabolaHeight == 0)
        {
            _parabolaAutoRotate = false;
            _parabolaOffset = Vector3.zero;
            return;
        }
        _parabolaEaseFunc = _parabolaEase.hasFunc ? _parabolaEase.func : EaseFunc.GetFunction("EaseOutCubic");
        var endPosition = GetEndPosition();
        var parabolaHeight = _maxParabolaHeight;
        var distance = UGameTools.GetPosDistance(_startPosition, endPosition);
        if (endPosition.y > _startPosition.y)
        {
            var normalLineLength = Mathf.Abs((endPosition.x - _startPosition.x) * distance * 0.5f / (endPosition.y - _startPosition.y));
            if (normalLineLength <= _maxParabolaHeight)
            {
                parabolaHeight = normalLineLength * 0.5f;
            }
        }
        var heightLimit = distance * _parabolaLimitFactor;
        parabolaHeight = parabolaHeight > heightLimit ? heightLimit : parabolaHeight;
        if (endPosition.x - _startPosition.x > 0)
        {
            _parabolaOffset.x = (endPosition.y - _startPosition.y) * parabolaHeight * -1 / distance;
            _parabolaOffset.y = (endPosition.x - _startPosition.x) * parabolaHeight / distance;
        }
        else
        {
            _parabolaOffset.x = (endPosition.y - _startPosition.y) * parabolaHeight / distance;
            _parabolaOffset.y = (endPosition.x - _startPosition.x) * parabolaHeight * -1 / distance;
        }

        if (_parabolaAutoRotate)
        {
            var nextPosition = GetPosition(0.03f, EaseValue(0.03f), _startPosition, endPosition);
            _transform.localEulerAngles = new Vector3(0, 0, UGameTools.GetPosAngle(_startPosition, nextPosition));
        }
    }

    protected float ParabolaEaseValue(float time)
    {
        if (_parbolaHalfTimeEase)
        {
            time *= 2;
            if (_parabolaEaseFunc == null)
            {
                return time < 1 ? time : 2 - time;
            }
            return time < 1 ? _parabolaEaseFunc(time) : _parabolaEaseFunc(2 - time);
        }
        return _parabolaEaseFunc == null ? time : _parabolaEaseFunc(time);
    }
}
