using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public class ObjectNameCache : ScriptableObject, ISerializationCallbackReceiver
{
    [SerializeField]
    private List<string> _objectNameList;

    private Dictionary<string, int> _objectNameMap = new Dictionary<string, int>();

    public void OnAfterDeserialize()
    {
        _objectNameMap.Clear();
        for (int i = 0; i < _objectNameList.Count; i++)
        {
            _objectNameMap[_objectNameList[i]] = i + 1;
        }
    }

    public void OnBeforeSerialize()
    {
    }

    public int GetId(string cacheName)
    {
        int id = 0;
        if (_objectNameMap.TryGetValue(cacheName, out id))
        {
            return id;
        }
        return 0;
    }
}
