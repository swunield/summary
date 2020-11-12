using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameQueueTask : MonoBehaviour
{
    private System.Action _onCancelAllDoneCallBack = null;

    private AsyncAction _lastAction = null;
    private int _taskQueueExecTimes = 0;
    private bool _isWaiting = false;
    private bool _isCancel = false;
    private bool _isCancelAll = false;
    private bool _isRunning = false;

    // 队列执行最大次数
    [FieldLabel("队列执行最大次数")]
    [SerializeField]
    private int _maxQueueExecTimes = 0;
    public int maxQueueExecTimes
    {
        get { return _maxQueueExecTimes; }
        set { _maxQueueExecTimes = value; }
    }

    private class QueueTask
    {
        public Func<float>[] taskActionList;
        public int bindID;
    }

    private AsyncAction _curAsyncAction = null;
    private IEnumerator _lastTaskEnumerator;
    private List<QueueTask> _inactiveTaskList = new List<QueueTask>();

    // 队列执行次数是否超限
    public bool isQueueExecOverTimes
    {
        get { return _maxQueueExecTimes != 0 && _taskQueueExecTimes >= _maxQueueExecTimes; }
    }

    private void OnDestroy()
    {
        _onCancelAllDoneCallBack = null;
    }

    public void Clear()
    {
        _taskQueueExecTimes = 0;
        _lastTaskEnumerator = null;
        _lastAction = null;
        _inactiveTaskList.Clear();
        _isWaiting = false;
        _isCancel = false;
        _isCancelAll = false;
        _isRunning = false;
        _curAsyncAction = null;
    }

    public bool IsRunning()
    {
        return _isRunning;
    }

    public void Wait()
    {
        _isWaiting = true;
    }

    public void Pulse()
    {
        _isWaiting = false;
    }

    public void Cancel()
    {
        _isCancel = true;
        _isWaiting = false;
    }

    public void CancelAll()
    {
        _isCancelAll = true;
        _isWaiting = false;
    }

    public void CancelAll(System.Action onCancelDone)
    {
        if (_lastAction == null)
        {
            if (onCancelDone != null)
            {
                onCancelDone();
            }
            return;
        }

        _onCancelAllDoneCallBack = onCancelDone;
        CancelAll();
    }

    public bool ExecTask(Func<float> taskAction1, int bindID = 0)
    {
        return ExecTask(taskAction1, null, null, null, bindID);
    }

    public bool ExecTask(Func<float> taskAction1, Func<float> taskAction2, int bindID = 0)
    {
        return ExecTask(taskAction1, taskAction2, null, null, bindID);
    }

    public bool ExecTask(Func<float> taskAction1, Func<float> taskAction2, Func<float> taskAction3, int bindID = 0)
    {
        return ExecTask(taskAction1, taskAction2, taskAction3, null, bindID);
    }

    public bool ExecTask(Func<float> taskAction1, Func<float> taskAction2, Func<float> taskAction3, Func<float> taskAction4, int bindID = 0)
    {
        var taskActionList = new List<Func<float>>();
        if (taskAction1 != null)
        {
            taskActionList.Add(taskAction1);
        }
        if (taskAction2 != null)
        {
            taskActionList.Add(taskAction2);
        }
        if (taskAction3 != null)
        {
            taskActionList.Add(taskAction3);
        }
        if (taskAction4 != null)
        {
            taskActionList.Add(taskAction4);
        }
        return ExecTask(taskActionList.ToArray(), bindID);
    }

    public bool ExecTask(Func<float>[] taskActionList, int bindID = 0)
    {
        if (_maxQueueExecTimes != 0 && _taskQueueExecTimes >= _maxQueueExecTimes)
        {
            return false;
        }

        if (!this.gameObject.activeSelf || !this.gameObject.activeInHierarchy)
        {
            _inactiveTaskList.Add(new QueueTask() { taskActionList = taskActionList, bindID = bindID });
            return true;
        }

        CheckSameBindID(bindID);

        AsyncAction action = new AsyncAction();
        action.bindID = bindID;
        action.action = () =>
        {
            _curAsyncAction = action;
            _lastTaskEnumerator = _ExecTask(taskActionList, () =>
            {
                if (action.nextAction == null || _isCancelAll)
                {
                    var isCancelAll = _isCancelAll;
                    _taskQueueExecTimes += 1;
                    _lastTaskEnumerator = null;
                    _lastAction = null;
                    _inactiveTaskList.Clear();
                    _isWaiting = false;
                    _isCancel = false;
                    _isCancelAll = false;
                    _isRunning = false;
                    _curAsyncAction = null;

                    if (isCancelAll && _onCancelAllDoneCallBack != null)
                    {
                        _onCancelAllDoneCallBack();
                        _onCancelAllDoneCallBack = null;
                    }

                    return;
                }
                action.Complete(null);
            });
            StartCoroutine(_lastTaskEnumerator);
        };

        if (_lastAction == null)
        {
            action.Action();
        }
        else
        {
            _lastAction.nextAction = action;
            _lastAction.OnCompleted((_action) =>
            {
                _action.NextAction();
            });
        }

        _lastAction = action;
        _isRunning = true;

        return true;
    }

    private IEnumerator _ExecTask(Func<float>[] taskActionList, Action onDone)
    {
        for (int i = 0; i < taskActionList.Length; i++)
        {
            // 重置状态
            _isWaiting = false;

            if (_isCancel || _isCancelAll)
            {
                if (onDone != null)
                {
                    onDone();
                }
                yield break;
            }

            var result = taskActionList[i]();

            var isWaiting = _isWaiting;
            while (_isWaiting)
            {
                yield return null;
            }
            if (_isCancel || _isCancelAll)
            {
                if (onDone != null)
                {
                    onDone();
                }
                yield break;
            }

            if (!isWaiting)
            {
                if (result < 0)
                {
                    if (onDone != null)
                    {
                        onDone();
                    }
                    yield break;
                }
                else if (result == 0)
                {
                    yield return null;
                }
                else
                {
                    yield return new WaitForSeconds(result);
                }
            }
        }

        if (onDone != null)
        {
            onDone();
        }
    }

    private void OnEnable()
    {
        if (_lastTaskEnumerator != null)
        {
            StartCoroutine(_lastTaskEnumerator);
        }
        if (_inactiveTaskList.Count != 0)
        {
            var count = _inactiveTaskList.Count;
            for (int i = 0; i < count; i++)
            {
                ExecTask(_inactiveTaskList[i].taskActionList, _inactiveTaskList[i].bindID);
            }
            _inactiveTaskList.Clear();
        }
    }

    public void CheckSameBindID(int bindID)
    {
        if (bindID == 0 || _curAsyncAction == null)
        {
            return;
        }

        var action = _curAsyncAction;
        while (action != null && action.nextAction != null)
        {
            if (action.nextAction.bindID == bindID)
            {
                if (_lastAction == action.nextAction)
                {
                    _lastAction = action;
                }
                action.nextAction = action.nextAction.nextAction;
            }
            else
            {
                action = action.nextAction;
            }
        }
    }
}
