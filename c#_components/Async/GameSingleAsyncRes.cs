using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameSingleAsyncRes : MonoBehaviour
{
    private static readonly string SINGLE_ASYNC_DOWNLOADER = "SingleAsync";
    public static bool TASK_IMMEDIATELY_START = true;
    public static int TASK_TRY_TIMES = 3;

    private int _downloadTaskId = 0;
    private Action<int, float, int> _onDownloadState;
    private GameResDownloader _downloader = null;

    private Action<int, float, int> _downloadEvent;
    private bool _isDetailEvent = false;
    private int _lastEventState = -1;

    private bool _isWarm = false;

    private void Awake()
    {
        _isWarm = true;
    }

    private void Start()
    {
        
    }

    private void OnDestroy()
    {
        if (_downloadTaskId != 0 && _downloader != null)
        {
            _downloader.UnBindTask(_downloadTaskId);
        }
        _downloader = null;
        _downloadTaskId = 0;
        _onDownloadState = null;
        _downloadEvent = null;
        _lastEventState = -1;
    }

    public bool Start(string assetName, Action<int, float, int> onDownloadState, int tryTimes = 0)
    {
        if (!_isWarm)
        {
            this.gameObject.SetActive(true);
            this.gameObject.SetActive(false);
        }

        Stop();

        _onDownloadState = onDownloadState;
        var resInfo = GameAsyncRes.Get(assetName);
        if (resInfo == null)
        {
            OnDownloadState(null, GameResDownloadState.FAILED, 0, 0);
            return false;
        }

        _downloader = GameResDownloader.GetOrCreateDownloader(SINGLE_ASYNC_DOWNLOADER);
        if (_downloader == null)
        {
            OnDownloadState(resInfo, GameResDownloadState.FAILED, 0, 0);
            return false;
        }

        _downloadTaskId = _downloader.Start(resInfo.bundleName, resInfo.urls, resInfo.hash, resInfo.size, (state, progress, downloadSize, leftTaskCount) =>
        {
            switch(state)
            {
                case (int)GameResDownloadState.SUCCESS:
                    {
                        GameResLoader.INSTANCE.LoadAssetBundle(resInfo.bundleName, resInfo.manifestName, resInfo.hash, resInfo.urls, resInfo.loadSource == "Package", (isSuccess) =>
                        {
                            OnDownloadState(resInfo, isSuccess ? GameResDownloadState.SUCCESS : GameResDownloadState.FAILED, isSuccess ? 1 : 0, isSuccess ? resInfo.size : 0);
                        });
                    }
                    break;
                case (int)GameResDownloadState.FAILED:
                    {
                        if (tryTimes < TASK_TRY_TIMES)
                        {
                            Start(assetName, onDownloadState, tryTimes + 1);
                            return;
                        }

                        OnDownloadState(resInfo, GameResDownloadState.FAILED, 0, 0);
                    }
                    break;
                default:
                    {
                        OnDownloadState(resInfo, (GameResDownloadState)state, progress, downloadSize);
                    }
                    break;
            }
        }, 10, TASK_IMMEDIATELY_START);

        return true;
    }

    public void Stop()
    {
        if (_onDownloadState == null)
        {
            return;
        }

        if (_downloadTaskId != 0 && _downloader != null)
        {
            _downloader.UnBindTask(_downloadTaskId);
        }
        _downloader = null;
        _downloadTaskId = 0;
        _onDownloadState = null;

        if (_downloadEvent != null)
        {
            _downloadEvent((int)GameResDownloadState.STOP, 0, 0);
        }
        _lastEventState = -1;
    }

    public void SetDownloadEvent(Action<int, float, int> dlEvent, bool isDetail = false)
    {
        _downloadEvent = dlEvent;
        _isDetailEvent = isDetail;
        _lastEventState = -1;
    }

    private void OnDownloadState(GameAsyncResInfo resInfo, GameResDownloadState state, float progress, int downloadSize)
    {
        if (resInfo != null)
        {
            FTDebug.LogWarning($"SingleAsnycRes Download State [{resInfo.bundleName}] [{state}] [{progress}] [{downloadSize}]");
        }
        if (state == GameResDownloadState.SUCCESS && resInfo != null)
        {
            GameAsyncRes.OnAsyncResDownloadSuccess(resInfo.bundleName);
        }
        var iState = (int)state;
        if (_onDownloadState != null)
        {
            _onDownloadState(iState, progress, downloadSize);
        }
        if (_downloadEvent != null)
        {
            if (_isDetailEvent || iState >= (int)GameResDownloadState.SUCCESS || iState != _lastEventState)
            {
                _downloadEvent(iState, progress, downloadSize);
                _lastEventState = iState;
            }
        }
        if (state == GameResDownloadState.SUCCESS || state == GameResDownloadState.FAILED)
        {
            _onDownloadState = null;
        }
    }
}
