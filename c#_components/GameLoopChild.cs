using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[SLua.CustomLuaClass]
public abstract class GameLoopChild : MonoBehaviour
{
    [SerializeField]
    protected GameLoop _loop = null;
    public GameLoop loop { get { return _loop; } set { _loop = value; } }

    public void BindGameLoop(GameLoop loop)
    {
        _loop = loop;
        if (loop != null)
        {
            loop.BindLoopChild(this);
        }
    }

    public void UnBindGameLoop()
    {
        _loop = null;
    }

    public bool IsGameLoopBinded()
    {
        return _loop != null;
    }

    public bool IsRemove()
    {
        return _loop == null;
    }

    public int GetMSTime()
    {
        return _loop == null ? (int)(Time.realtimeSinceStartup * 1000) : _loop.GetMSTime();
    }

    public float GetSTime()
    {
        return _loop == null ? Time.realtimeSinceStartup : _loop.GetSTime();
    }

    public abstract void LoopUpdate(int msDelta, int msTime, float sDelta, float sTime);
    public abstract void LoopFixedUpdate(int msDelta, int msTime, float sDelta, float sTime);
}
