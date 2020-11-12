using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameMultiAsyncRes : MonoBehaviour
{
    private static readonly string MULTI_ASYNC_DOWNLOADER = "MultiAsync";
    public static int TASK_TRY_TIMES = 3;

    private GameResDownloader _downloader = null;
    private List<GameAsyncResInfo> _allAsyncRes = new List<GameAsyncResInfo>();
    private Action<string, int, int, int, int, int, int> _onDownloadState = null;
    private bool _isDetail = false;

    private int _totalSize = 0;
    private int _downloadedSize = 0;
    private int _curDownloadIndex = 0;
    private int _totalCount = 0;
    private int _curTaskId = 0;
    private int _lastDownloadIndex = -1;

    private bool _isPaused = false;
    public bool isPaused
    {
        get
        {
            return _isPaused;
        }
        set
        {
            if (_isPaused && !value)
            {
                _isPaused = value;
                StartDownload(true);
            }
            else
            {
                _isPaused = value;
            }
        }
    }

    private void Start()
    {

    }

    private void OnDestroy()
    {
        Clear();
    }

    public void Clear()
    {
        _downloader = null;
        _onDownloadState = null;
        _allAsyncRes.Clear();

        _totalSize = 0;
        _downloadedSize = 0;
        _curDownloadIndex = 0;
        _lastDownloadIndex = -1;
        _totalCount = 0;
        _curTaskId = 0;
        _isPaused = false;
    }

    public bool Start(Action<string, int, int, int, int, int, int> onDownloadState, bool isDetail = false)
    {
        _onDownloadState = onDownloadState;
        _isDetail = isDetail;

        _allAsyncRes = GameAsyncRes.GetAll();
        if (_allAsyncRes.Count == 0)
        {
            OnDownloadState(null, GameResDownloadState.SUCCESS, 0, 0, 0, 0, 0);
            return true;
        }

        _downloader = GameResDownloader.GetOrCreateDownloader(MULTI_ASYNC_DOWNLOADER);
        if (_downloader == null)
        {
            OnDownloadState(null, GameResDownloadState.FAILED, 0, 0, 0, 0, 0);
            return false;
        }
        _downloader.CancelAll();

        _totalCount = _allAsyncRes.Count;
        _totalSize = _allAsyncRes.Sum(r => r.size);
        _downloadedSize = 0;
        _curDownloadIndex = 0;
        _lastDownloadIndex = -1;
        _curTaskId = 0;
        _isPaused = false;

        StartDownload();

        return true;
    }

    public void Pause()
    {
        isPaused = true;
    }

    public void Resume()
    {
        isPaused = false;
    }

    public void SetDownloadEvent(Action<string, int, int, int, int, int, int> onDownloadState, bool isDetail = false)
    {
        _onDownloadState = onDownloadState;
        _isDetail = isDetail;
        _lastDownloadIndex = -1;
    }

    private void StartDownload(bool isResume = false, int tryTimes = 0)
    {
        if (_isPaused)
        {
            return;
        }

        if (_curDownloadIndex >= _totalCount)
        {
            OnDownloadState(null, GameResDownloadState.SUCCESS, _totalCount, _totalCount, 0, _downloadedSize, _totalSize);
            return;
        }

        if (isResume)
        {
            _lastDownloadIndex = -1;
            // 暂停并不停止当前下载任务，只是不通知上层，若取消暂停，需看下当前任务是否完成，未完成的话不再开始新任务
            var curTask = _downloader.GetTask(_curTaskId);
            if (curTask != null && curTask.state < GameResDownloadState.SUCCESS)
            {
                return;
            }
        }

        var curRes = _allAsyncRes[_curDownloadIndex];
        OnDownloadState(curRes, GameResDownloadState.DOWNLOADING, _curDownloadIndex, _totalCount, 0, _downloadedSize, _totalSize);
        _curTaskId = _downloader.Start(curRes.bundleName, curRes.urls, curRes.hash, curRes.size, (state, progress, downloadSize, leftCount) =>
        {
            var eState = (GameResDownloadState)state;
            switch (eState)
            {
                case GameResDownloadState.SUCCESS:
                    {
                        GameResLoader.INSTANCE.LoadAssetBundle(curRes.bundleName, curRes.manifestName, curRes.hash, curRes.urls, false, (isSuccess) =>
                        {
                            if (isSuccess)
                            {
                                GameAsyncRes.OnAsyncResDownloadSuccess(curRes.bundleName);
                                OnDownloadState(curRes, (GameResDownloadState)state, _curDownloadIndex, _totalCount, downloadSize, _downloadedSize, _totalSize);
                            }

                            _downloadedSize += downloadSize;
                            _curDownloadIndex++;
                            StartDownload();
                        });
                    }
                    break;
                case GameResDownloadState.FAILED:
                    {
                        if (tryTimes < TASK_TRY_TIMES)
                        {
                            StartDownload(false, tryTimes++);
                            return;
                        }
                        OnDownloadState(curRes, GameResDownloadState.FAILED, _curDownloadIndex, _totalCount, downloadSize, _downloadedSize, _totalSize);
                    }
                    break;
                default:
                    {
                        OnDownloadState(curRes, (GameResDownloadState)state, _curDownloadIndex, _totalCount, downloadSize, _downloadedSize, _totalSize);
                    }
                    break;
            }
        }, 10, true);
    }

    private void OnDownloadState(GameAsyncResInfo resInfo, GameResDownloadState state, int curIndex, int totalCount, int curDownloadSize, int downloadedSize, int totalSize)
    {
        switch (state)
        {
            case GameResDownloadState.SUCCESS:
                {
                    if (curIndex >= totalCount)
                    {
                        if (_onDownloadState != null && !isPaused)
                        {
                            _onDownloadState(resInfo != null ? resInfo.bundleName : "", (int)GameResDownloadState.SUCCESS, curIndex, totalCount, curDownloadSize, downloadedSize, totalSize);
                        }

                        // 全部下载完成
                        Clear();
                    }
                }
                break;
            case GameResDownloadState.FAILED:
                {
                    if (_onDownloadState != null && !isPaused)
                    {
                        _onDownloadState(resInfo != null ? resInfo.bundleName : "", (int)GameResDownloadState.FAILED, curIndex, totalCount, curDownloadSize, downloadedSize, totalSize);
                    }
                }
                break;
            default:
                {
                    if (_onDownloadState != null && !isPaused)
                    {
                        if (_isDetail || _lastDownloadIndex != curIndex)
                        {
                            _onDownloadState(resInfo != null ? resInfo.bundleName : "", (int)GameResDownloadState.DOWNLOADING, curIndex, totalCount, curDownloadSize, downloadedSize, totalSize);
                            _lastDownloadIndex = curIndex;
                        }
                    }
                }
                break;
        }
    }
}
