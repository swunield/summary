using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class FTPoolItem : MonoBehaviour
{
    public int poolItemId = 0;
}

[SLua.CustomLuaClass]
public class FTPool<T> where T : FTPoolItem
{
    private Stack<T> _freeList = new Stack<T>();
    private Dictionary<int, T> _busyList = new Dictionary<int, T>();
    private int _busyCount = 0;

    private Func<T> _onNewItemListener = null;
    private Action<T> _onFreeItemListener = null;
    private Action<T> _onBusyItemListener = null;
    private Action<T> _onDestroyItemListener = null;

    private int _poolItemIdGenerator = 0;

    public FTPool()
    {

    }

    public void Destroy()
    {
        foreach (var item in _freeList)
        {
            if (this._onDestroyItemListener != null && item != null)
            {
                this._onDestroyItemListener(item);
            }
        }
        _freeList.Clear();

        foreach (var key in _busyList.Keys)
        {
            var item = _busyList[key];
            if (this._onDestroyItemListener != null && item != null)
            {
                this._onDestroyItemListener(item);
            }
        }
        _busyList.Clear();

        _busyCount = 0;

        this._onNewItemListener = null;
        this._onFreeItemListener = null;
        this._onBusyItemListener = null;
        this._onDestroyItemListener = null;
    }

    public FTPool<T> SetNewItemListener(Func<T> listener)
    {
        this._onNewItemListener = listener;
        return this;
    }

    public FTPool<T> SetFreeItemListener(Action<T> listener)
    {
        this._onFreeItemListener = listener;
        return this;
    }

    public FTPool<T> SetBusyItemListener(Action<T> listener)
    {
        this._onBusyItemListener = listener;
        return this;
    }

    public FTPool<T> SetDestroyItemListener(Action<T> listener)
    {
        this._onDestroyItemListener = listener;
        return this;
    }

    private T CreateNewItem()
    {
        var item = this._onNewItemListener();
        item.poolItemId = this._poolItemIdGenerator++;
        return item;
    }

    private void AddFreeItem(int addCount)
    {
        for (int i = 0; i < addCount; i++)
        {
            var item = CreateNewItem();
            this._freeList.Push(item);
            this._onFreeItemListener?.Invoke(item);
        }
    }

    private T GetFreeItem()
    {
        T freeItem = null;
        if (this._freeList.Count == 0)
        {
            freeItem = CreateNewItem();
        }
        else
        {
            freeItem = this._freeList.Pop();
        }

        this._busyList.Add(freeItem.poolItemId, freeItem);
        this._busyCount++;
        this._onBusyItemListener?.Invoke(freeItem);
        return freeItem;
    }

    private void FreeItem(T item)
    {
        if (item == null)
        {
            return;
        }
        if (!this._busyList.ContainsKey(item.poolItemId))
        {
            return;
        }
        this._busyList.Remove(item.poolItemId);
        this._busyCount--;
        this._freeList.Push(item);
        this._onFreeItemListener?.Invoke(item);
    }

    private void FreeAllItems()
    {
        int count = this._busyList.Keys.Count;
        for (int i = count - 1; i >=0; i--)
        {
            var key = this._busyList.Keys.ElementAt(i);
            var item = this._busyList[key];
            if (item != null)
            {
                this.FreeItem(item);
            }
        }
    }

    public T Request()
    {
        return this.GetFreeItem();
    }

    public void Release(T item)
    {
        this.FreeItem(item);
    }

    public void ReleaseAll()
    {
        this.FreeAllItems();
    }
}
