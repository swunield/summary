using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class GameObjectPoolContainer : MonoBehaviour
{
    [FieldLabel("预制体路径")]
    public string prefabName = "";
    [FieldLabel("预制体数量")]
    public int count = 1;
    [FieldLabel("节点名字")]
    public string poolObjectName = "";
    [FieldLabel("强制命名Item")]
    public bool forceNameItem = false;
    [FieldLabel("运行时节点")]
    public List<PoolGameObject> poolObjectList = new List<PoolGameObject>();

    public Action<string, int> onPoolRefresh = null;

    private void OnDestroy()
    {
        onPoolRefresh = null;
    }

    public void RefreshPoolContainer(string prefabName, int count = 1, string objName = "0")
    {
        if (string.IsNullOrEmpty(prefabName))
        {
            return;
        }

        this.count = count;
        if (count > 0 && poolObjectList.Count == count)
        {
            if (GameObjectPool.INSTANCE.IsSamePrefab(poolObjectList[0], prefabName))
            {
                if (objName != "0" && objName != poolObjectName)
                {
                    poolObjectName = objName;
                    if (count == 1 && !forceNameItem)
                    {
                        poolObjectList[0].name = string.IsNullOrEmpty(poolObjectName) ? Path.GetFileName(prefabName) : poolObjectName;
                        OnPoolRefresh(prefabName, 0);
                    }
                    else
                    {
                        for (int i = 0; i < count; i++)
                        {
                            poolObjectList[i].name = string.IsNullOrEmpty(poolObjectName) ? string.Format("item_{0}", i + 1) : string.Format("{0}_{1}", poolObjectName, i + 1);
                            OnPoolRefresh(prefabName, i);
                        }
                    }
                }
                return;
            }
        }

        if (poolObjectList.Count != 0)
        {
            int objectCount = poolObjectList.Count;
            for (int i = objectCount - 1; i >= 0; i--)
            {
                GameObjectPool.INSTANCE.Release(poolObjectList[i].gameObject);
            }
            poolObjectList.Clear();
        }

        for (int i = 0; i < count; i++)
        {
            GamePerf.Begin("GOPC_Requset_" + prefabName);
            var poolObject = GameObjectPool.INSTANCE.Request(prefabName, true);
            GamePerf.End();
            poolObjectName = objName == "0" ? poolObjectName : objName;
            if (poolObject != null)
            {
                if (count == 1 && !forceNameItem)
                {
                    poolObject.name = string.IsNullOrEmpty(poolObjectName) ? Path.GetFileName(prefabName) : poolObjectName;
                }
                else
                {
                    poolObject.name = string.IsNullOrEmpty(poolObjectName) ? string.Format("item_{0}", i + 1) : string.Format("{0}_{1}", poolObjectName, i + 1);

                }
                GamePerf.Begin("GOPC_SetParent_" + prefabName);
                poolObject.transform.SetParent(this.transform, false);
                poolObject.poolContainer = this;
                OnPoolRefresh(prefabName, i);
                GamePerf.End();
                poolObjectList.Add(poolObject);
            }
        }
    }

    public void ReleasePoolContainer()
    {
        if (!LuaManager.GameRunning)
        {
            return;
        }

        if (poolObjectList.Count == 0)
        {
            return;
        }

        int count = poolObjectList.Count;
        for (int i = count - 1; i >= 0; i--)
        {
            GameObjectPool.INSTANCE.Release(poolObjectList[i].gameObject);
        }
        poolObjectList.Clear();
    }

    public void RomovePoolObject(PoolGameObject poolObject)
    {
        if (poolObject == null || poolObject.poolContainer != this)
        {
            return;
        }

        int count = poolObjectList.Count;
        for (int i = count - 1; i >= 0; i--)
        {
            if (poolObjectList[i] == poolObject)
            {
                poolObjectList.RemoveAt(i);
                break;
            }
        }
    }

    private void OnEnable()
    {
        if (!LuaManager.GameRunning)
        {
            return;
        }

        RefreshPoolContainer(prefabName, count);
    }

    private void OnPoolRefresh(string prefabName, int index)
    {
        if (onPoolRefresh != null)
        {
            onPoolRefresh(Path.GetFileNameWithoutExtension(prefabName), index);
        }
    }
}
