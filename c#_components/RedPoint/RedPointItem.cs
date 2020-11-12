using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class RedPointItem : MonoBehaviour
{
    public string key = "";
    public bool isBind = false;
    public bool isWarmed = false;
    public bool isBindPendding = false;

    private void Start()
    {
        isWarmed = true;
        PenddingBind();
    }

    private void OnDestroy()
    {
        RedPointManager.UnbindPointItem(this);
    }

    private void PenddingBind()
    {
        if (!isBindPendding || !isWarmed)
        {
            return;
        }

        isBindPendding = false;
        RedPointManager.BindPointItem(this.gameObject, key);
        this.gameObject.SetActive(RedPointManager.INSTANCE.GetPointResult(key));
    }
}
