using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

[SLua.CustomLuaClass]
public class PoolGameObject : FTPoolItem
{
    public string prefabName;
    public GameObjectPoolContainer poolContainer;

    [SerializeField]
    private UIEvents _uiEvents = new UIEvents();

    public void Release()
    {
        GameObjectPool.INSTANCE.Release(this.gameObject);
    }

    public void FireFreeEvent()
    {
        _uiEvents.InvokeEvent(UIEventType.OnFree);
    }

    public void FireBusyEvent()
    {
        _uiEvents.InvokeEvent(UIEventType.OnBusy);
    }
}
