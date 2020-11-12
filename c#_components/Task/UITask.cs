using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

public class UITask : MonoBehaviour
{
    [SerializeField]
    private float _duration = 0.0f;
    public float duration { get { return _duration; } set { _duration = value; } }

    [SerializeField]
    private bool _skipTask = false;
    public bool skipTask { get { return _skipTask; } set { _skipTask = value; } }

    [SerializeField]
    private GameObject _relativeObject = null;
    public GameObject relativeObject { get { return _relativeObject; } set { _relativeObject = value; } }

    [SerializeField]
    private UnityEvent _taskEvent;
    private System.Action _taskCallBack;

    private float _taskResult = 0;

    private void OnDestroy()
    {
       if (_taskEvent != null)
        {
            _taskEvent.RemoveAllListeners();
        }
        _taskCallBack = null;
        _relativeObject = null;
    }

    public float ExecTask()
    {
        if (_skipTask || (relativeObject != null && (!relativeObject.activeSelf || !relativeObject.activeInHierarchy)))
        {
            return 0;
        }

        _taskResult = _duration;
        if (_taskEvent != null)
        {
            _taskEvent.Invoke();
        }
        if (_taskCallBack != null)
        {
            _taskCallBack();
        }
        return _taskResult;
    }

    public void SetTaskCallBack(System.Action callBack)
    {
        this._taskCallBack = callBack;
    }

    public void Cancel()
    {
        this._taskResult = -1;
    }
}
