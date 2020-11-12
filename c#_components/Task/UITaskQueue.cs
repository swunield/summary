using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Events;

public class UITaskQueue : MonoBehaviour
{
    [SerializeField]
    private List<UITask> _uiTaskList = new List<UITask>();

    [SerializeField]
    private UnityEvent _completeEvent;
    private System.Action _completeCallBack;

    private GameQueueTask _taskQueue = null;
    public GameQueueTask taskQueue
    {
        get
        {
            if (_taskQueue == null)
            {
                _taskQueue = this.gameObject.GetComponent<GameQueueTask>();
                if (_taskQueue == null)
                {
                    _taskQueue = this.gameObject.AddComponent<GameQueueTask>();
                }
            }
            return _taskQueue;
        }
    }

    void Awake()
    {
        if (_uiTaskList.Count == 0)
        {
            _uiTaskList = this.gameObject.GetComponentsInChildren<UITask>(true).ToList();
        }
    }

    private void OnDestroy()
    {
        if (_completeEvent != null)
        {
            _completeEvent.RemoveAllListeners();
        }
        _completeCallBack = null;
    }

    public void Begin()
    {
        taskQueue.CancelAll(() => {
            taskQueue.Clear();

            var count = _uiTaskList.Count;
            if (count == 0)
            {
                return;
            }

            for (int i = 0; i < count; i++)
            {
                var task = _uiTaskList[i];
                taskQueue.ExecTask(() => { return task.ExecTask(); });
            }
            taskQueue.ExecTask(() => { OnTaskQueueComplete(); return 0; });
        });
    }

    private void OnTaskQueueComplete()
    {
        if (_completeEvent != null)
        {
            _completeEvent.Invoke();
        }
        if (_completeCallBack != null)
        {
            _completeCallBack();
        }
    }

    public void SetCompleteCallBack(System.Action callBack)
    {
        this._completeCallBack = callBack;
    }

    public void Wait()
    {
        taskQueue.Wait();
    }

    public void Pulse()
    {
        taskQueue.Pulse();
    }

    public void CancelAll()
    {
        taskQueue.CancelAll();
    }
}
