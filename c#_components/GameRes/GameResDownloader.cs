using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

public enum GameResDownloadState
{
    WAITING = 0,            // 等待中
    DOWNLOADING,            // 下载中
    SUCCESS,                // 下载完成
    FAILED,                 // 下载失败
    STOP,                   // 停止下载
    PAUSE,                  // 暂停下载
    CANCEL,                 // 取消下载
}

public class GameResDownloadTask
{
    public int taskId { get; set; } = 0;
    public string bundleName { get; set; } = "";
    public string[] urls { get; set; }
    public string hash { get; set; } = "";
    public int totalSize { get; set; } = 0;
    public int timeOut { get; set; } = 10;
    public GameResDownloadState state { get; set; } = GameResDownloadState.WAITING;
    public Action<int, float, int, int> onDownloadState { get; set; }
}

[SLua.CustomLuaClass]
public class GameResDownloader : MonoBehaviour
{
    private static Dictionary<string, GameResDownloader> _downloaderMap = new Dictionary<string, GameResDownloader>();
    public static GameResDownloader GetOrCreateDownloader(string name)
    {
        if (_downloaderMap.ContainsKey(name))
        {
            return _downloaderMap[name];
        }

        var downloader = new GameObject("GameResDownloader_" + name).AddComponent<GameResDownloader>();
        _downloaderMap[name] = downloader;
        return downloader;
    }

    public static void Destroy(string name)
    {
        if (!_downloaderMap.ContainsKey(name))
        {
            return;
        }

        var downloader = _downloaderMap[name];
        _downloaderMap.Remove(name);

        GameObject.Destroy(downloader.gameObject);
    }

    private List<GameResDownloadTask> _taskList = new List<GameResDownloadTask>();
    private int _taskIdGenerator = 1;
    private GameWebRequest _curWebRequest = null;
    private GameResDownloadTask _curTask = null;

    private void Awake()
    {
        GameObject.DontDestroyOnLoad(this);
    }

    private void OnDestroy()
    {
        CancelAll();
    }

    private void Start()
    {

    }

    // onDownloadState 0下载完成 1下载失败 2下载中
    public int Start(string bundleName, string[] urls, string hash, int totalSize, Action<int, float, int, int> onDownloadState, int timeOut = 10, bool isImmediatelyStart = true)
    {
        var task = new GameResDownloadTask()
        {
            taskId = _taskIdGenerator++,
            bundleName = bundleName,
            hash = hash,
            urls = urls,
            totalSize = totalSize,
            onDownloadState = onDownloadState,
            timeOut = timeOut,
            state = GameResDownloadState.WAITING,
        };

        if (isImmediatelyStart || _taskList.Count == 0)
        {
            _taskList.Insert(0, task);
            StopAllCoroutines();
            if (_curTask != null)
            {
                _curTask.state = GameResDownloadState.WAITING;
                _curTask = null;
            }
            if (_curWebRequest != null)
            {
                GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
                _curWebRequest = null;
            }
            StartCoroutine(_DownloadAsync(task));
        }
        else
        {
            _taskList.Add(task);
        }

        return task.taskId;
    }

    public void UnBindTask(int taskId)
    {
        for (int i = 0; i < _taskList.Count; i++)
        {
            if (_taskList[i].taskId == taskId)
            {
                _taskList[i].onDownloadState = null;
                break;
            }
        }
    }

    public bool CancelTask(int taskId)
    {
        for (int i = 0; i < _taskList.Count; i++)
        {
            if (_taskList[i].taskId == taskId)
            {
                if (_taskList[i].state == GameResDownloadState.WAITING)
                {
                    _taskList.RemoveAt(i);
                    return true;
                }
                if (_taskList[i].state == GameResDownloadState.DOWNLOADING)
                {
                    StopAllCoroutines();
                    if (_curWebRequest != null)
                    {
                        GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
                        _curWebRequest = null;
                    }
                    _taskList[i].state = GameResDownloadState.CANCEL;
                    OnDownloadFinish(_taskList[i]);
                    return true;
                }
                _taskList[i].onDownloadState = null;
            }
        }
        return false;
    }

    public bool CancelTask(string bundleName)
    {
        for (int i = 0; i < _taskList.Count; i++)
        {
            if (_taskList[i].bundleName == bundleName)
            {
                if (_taskList[i].state == GameResDownloadState.WAITING)
                {
                    _taskList.RemoveAt(i);
                    return true;
                }
                if (_taskList[i].state == GameResDownloadState.DOWNLOADING)
                {
                    StopAllCoroutines();
                    if (_curWebRequest != null)
                    {
                        GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
                        _curWebRequest = null;
                    }
                    _taskList[i].state = GameResDownloadState.CANCEL;
                    OnDownloadFinish(_taskList[i]);
                    return true;
                }
                _taskList[i].onDownloadState = null;
            }
        }
        return false;
    }

    public GameResDownloadTask GetTask(int taskId)
    {
        foreach (var task in _taskList)
        {
            if (task.taskId == taskId)
            {
                return task;
            }
        }
        return null;
    }

    public void CancelAll()
    {
        for (int i = 0; i < _taskList.Count; i++)
        {
            _taskList[i].onDownloadState = null;
        }
        _taskList.Clear();
        StopAllCoroutines();
        if (_curWebRequest != null)
        {
            GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
            _curWebRequest = null;
        }
        _curTask = null;
    }

    private IEnumerator _DownloadAsync(GameResDownloadTask task)
    {
        _curTask = task;
        var realHash = Hash128.Parse(task.hash);
        task.state = GameResDownloadState.DOWNLOADING;

#if UNITY_ANDROID && !UNITY_EDITOR
        Caching.compressionEnabled = !task.bundleName.Contains("video");
#endif

        bool success = false;
        foreach (string url in task.urls)
        {
            float checkTimeOutTime = Time.time;
            float progress = 0;

            FTDebug.Log(string.Format("Download {0} From {1} Size[{2}]", task.bundleName, url, task.totalSize));

            _curWebRequest = GameWebRequest.SendAssetBundleWebRequest(url, realHash, true);
            if (task.onDownloadState != null)
            {
                task.onDownloadState((int)GameResDownloadState.DOWNLOADING, 0, 0, _taskList.Count);
            }
            while (_curWebRequest != null && !_curWebRequest.request.isDone)
            {
                if (!string.IsNullOrEmpty(_curWebRequest.request.error))
                {
                    break;
                }
                var _progress = _curWebRequest.request.downloadProgress;
                if (task.timeOut != 0)
                {
                    if (progress != _progress)
                    {
                        checkTimeOutTime = Time.time;
                    }
                    else if (Time.time - checkTimeOutTime >= task.timeOut)
                    {
                        break;
                    }
                }
                if (progress != _progress && task.onDownloadState != null)
                {
                    task.onDownloadState((int)GameResDownloadState.DOWNLOADING, _progress, (int)(_progress * task.totalSize), _taskList.Count);
                }
                progress = _progress;
                yield return null;
            }

            FTDebug.LogWarning(string.Format("Download Result {0} From {1} Error[{2}] {3}", task.bundleName, url, _curWebRequest.request.error, _curWebRequest.request.isDone));
            if (!string.IsNullOrEmpty(_curWebRequest.request.error) || !_curWebRequest.request.isDone)
            {
                FTDebug.LogWarning(string.Format("Failed To Download {0} From {1} Error[{2}]", task.bundleName, url, _curWebRequest.request.error));
                GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
                _curWebRequest = null;
                continue;
            }

            FTDebug.Log(string.Format("Download Success {0} From {1} Size[{2}]", task.bundleName, url, task.totalSize));

            GameWebRequest.DestroyAssetBundleWebRequest(_curWebRequest);
            _curWebRequest = null;
            success = true;
            break;
        }

#if UNITY_ANDROID && !UNITY_EDITOR
        if (!Caching.compressionEnabled)
        {
            Caching.compressionEnabled = true;
        }
#endif

        task.state = success ? GameResDownloadState.SUCCESS : GameResDownloadState.FAILED;
        OnDownloadFinish(task);
    }

    private void OnDownloadFinish(GameResDownloadTask task)
    {
        _curTask = null;
        if (task.onDownloadState != null)
        {
            task.onDownloadState((int)task.state, 1.0f, task.totalSize, _taskList.Count);
        }
        for (int i = 0; i < _taskList.Count; i++)
        {
            if (_taskList[i].taskId == task.taskId)
            {
                _taskList.RemoveAt(i);
                break;
            }
        }
        if (_taskList.Count > 0 && _taskList[0].state == GameResDownloadState.WAITING)
        {
            StartCoroutine(_DownloadAsync(_taskList[0]));
        }
    }
}
