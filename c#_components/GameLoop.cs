using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameLoop : MonoBehaviour
{
    protected static GameLoop _instance = null;
    public static GameLoop INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = GameObject.FindObjectOfType<GameLoop>();
            }
            if (_instance == null)
            {
                _instance = new GameObject("GameLoop").AddComponent<GameLoop>();
            }

            return _instance;
        }
    }

    [SerializeField]
    private float _timeScale = 1;
    public float timeScale { get { return _timeScale; } set { _timeScale = value; } }

    [SerializeField]
    private int _maxDeltaTime = 99999;
    public int maxDeltaTime { get { return _maxDeltaTime; } set { _maxDeltaTime = value; } }

    [SerializeField]
    private bool _isLoopEnable = false;
    public bool isLoopEnable { get { return _isLoopEnable; } set { _isLoopEnable = value; _isFixedLoopEnable = _isLoopEnable ? false : _isFixedLoopEnable; } }

    [SerializeField]
    private bool _isFixedLoopEnable = false;
    public bool isFixedLoopEnable { get { return _isFixedLoopEnable; } set { _isFixedLoopEnable = value; _isLoopEnable = _isFixedLoopEnable ? false : _isLoopEnable; } }

    private float _startTime = 0;
    public float startTime { get { return _startTime; } set { _startTime = value; } }

    private float _totalTimeDelta = 0;
    public float totalTimeDelta { get { return _totalTimeDelta; } set { _totalTimeDelta = value; } }

    private int _msTime = 0;
    public int msTime { get { return _msTime; } set { _msTime = value; } }

    private int _msFixedTime = 0;
    public int msFixedTime { get { return _msFixedTime; } set { _msFixedTime = value; } }

    private float _sTime = 0;
    public float sTime { get { return _sTime; } set { _sTime = value; } }

    private float _sFixedTime = 0;
    public float sFixedTime { get { return _sFixedTime; } set { _sFixedTime = value; } }

    private Action<int, int, float, float> _loopCallBack = null;
    private Action<int, int, float, float> _fixedLoopCallBack = null;

    private List<GameLoopChild> _childList = new List<GameLoopChild>();
    private List<GameLoopChild> _penddingChildList = new List<GameLoopChild>();

    public void SetLoopCallBack(Action<int, int, float, float> callBack)
    {
        _loopCallBack = callBack;
        isLoopEnable = _loopCallBack != null;
    }

    public void SetFixedLoopCallBack(Action<int, int, float, float> callBack)
    {
        _fixedLoopCallBack = callBack;
        isFixedLoopEnable = _fixedLoopCallBack != null;
    }

    public void Reset()
    {
        _sTime = 0;
        _msTime = 0;
        _sFixedTime = 0;
        _msFixedTime = 0;
    }

    public int GetMSTime()
    {
        return _isFixedLoopEnable ? _msFixedTime : _msTime;
    }

    public float GetSTime()
    {
        return _isFixedLoopEnable ? _sFixedTime : _sTime;
    }

    private void Awake()
    {
        _sTime = 0;
        _msTime = 0;
        _sFixedTime = 0;
        _msFixedTime = 0;
    }

    private void Update()
    {
        if (!_isLoopEnable || _timeScale <= 0)
        {
            return;
        }

        if (_startTime == 0)
        {
            _startTime = Time.realtimeSinceStartup;
            _totalTimeDelta = 0;
            return;
        }

        var sDelta = Time.realtimeSinceStartup - _startTime - _totalTimeDelta;
        var msDelta = (int)(sDelta * 1000);
        sDelta = msDelta * 0.001f;
        _totalTimeDelta += sDelta;

        msDelta = (int)(msDelta * _timeScale);
        if (msDelta > maxDeltaTime * _timeScale)
        {
            msDelta = (int)(maxDeltaTime * _timeScale);
        }
        sDelta = msDelta * 0.001f;
        _msTime += msDelta;
        _sTime += sDelta;

        _loopCallBack?.Invoke(msDelta, _msTime, sDelta, _sTime);

        var penddingChildCount = _penddingChildList.Count;
        for (int i = 0; i < penddingChildCount; i++)
        {
            _childList.Add(_penddingChildList[i]);
        }
        _penddingChildList.Clear();

        var childCount = _childList.Count;
        for (int i = childCount - 1; i >= 0; i--)
        {
            var child = _childList[i];
            if (child == null || child.IsRemove())
            {
                _childList.RemoveAt(i);
                continue;
            }
            if (child.gameObject.activeInHierarchy)
            {
                child.LoopUpdate(msDelta, _msTime, sDelta, _sTime);
            }
        }
    }

    private void FixedUpdate()
    {
        if (!_isFixedLoopEnable || _timeScale <= 0)
        {
            return;
        }

        var sDelta = Time.fixedDeltaTime * _timeScale;
        var msDelta = (int)(sDelta * 1000);
        if (msDelta > maxDeltaTime * _timeScale)
        {
            msDelta = (int)(maxDeltaTime * _timeScale);
        }
        _msFixedTime += msDelta;
        _fixedLoopCallBack?.Invoke(msDelta, _msFixedTime, sDelta, _sFixedTime);

        var penddingChildCount = _penddingChildList.Count;
        for (int i = 0; i < penddingChildCount; i++)
        {
            _childList.Add(_penddingChildList[i]);
        }
        _penddingChildList.Clear();

        var childCount = _childList.Count;
        for (int i = childCount - 1; i >= 0; i--)
        {
            var child = _childList[i];
            if (child == null || child.IsRemove())
            {
                _childList.RemoveAt(i);
                continue;
            }
            if (child.gameObject.activeInHierarchy)
            {
                child.LoopFixedUpdate(msDelta, _msFixedTime, sDelta, _sFixedTime);
            }
        }
    }

    public void BindLoopChild(GameLoopChild child)
    {
        _penddingChildList.Add(child);
    }
}
