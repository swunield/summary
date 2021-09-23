using System;
using System.Collections;
using System.Collections.Generic;
using UAnimation;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleLine : UBattleEffect
{
    [SerializeField]
    private float _originLength = 1.0f;

    [SerializeField]
    private float _originDuration = 0.0f;

    [SerializeField]
    private ParticleSystem _lineParticle = null;
    public ParticleSystem lineParticle { get { return _lineParticle; } }

    [SerializeField]
    private Animation _lineAnimation = null;
    public Animation lineAnimation { get { return _lineAnimation; } }

    private Vector3 _localScale;
    private bool _isDirty = false;

    public override void LoopUpdate(int msDelta, int msTime, float sDelta, float sTime)
    {
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
        if (flyTime >= _duration)
        {
            OnEffectEnd(true);
            return;
        }

        _isDirty = false;
        if (_startUnit != null && _startUnit.unitId == _startUnitId && _startUnit.gameObject.activeInHierarchy)
        {
            if (_startUnit.isTopLayer)
            {
                this.MoveSortingLayerToTop();
            }
            
            if (_transStart.position != _startPosition)
            {
                _startPosition = _transStart.position;
                _transform.position = _startPosition;
                _isDirty = true;
            }
        }

        var endPosition = GetEndPosition();
        if (endPosition != _endPosition)
        {
            _endPosition = endPosition;
            _isDirty = true;
        }

        if (_isDirty)
        {
            AutoRotate();
            RefreshScale();
        }
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

        _localScale = _transform.localScale;
        RefreshScale();

        RefreshDuration();

        return true;
    }

    protected void RefreshScale()
    {   
        _localScale.x = UGameTools.GetPosDistance(_startPosition, GetEndPosition()) / _originLength;
        _transform.localScale = _localScale;
    }

    protected void RefreshDuration()
    {
        if (lineParticle != null)
        {
            var mainModule = lineParticle.main;
            mainModule.simulationSpeed = (mainModule.duration * 1000) / _duration;
        }
        if (lineAnimation != null)
        {
            var speed = _originDuration / _duration;
            foreach (AnimationState state in lineAnimation)
            {
                state.speed = speed;
            }
        }
    }
}
