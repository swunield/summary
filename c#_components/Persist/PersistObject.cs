using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public class PersistObject : MonoBehaviour
{
    [SerializeField]
    private string _key = "";
    public string key
    {
        get
        {
            if (string.IsNullOrEmpty(_key))
            {
                _key = this.gameObject.name;
            }
            return _key;
        }
        set
        {
            _key = value;
        }
    }

    private void Awake()
    {
        PersistObjects.AddPersist(key, this.gameObject);
    }

    private void OnDestroy()
    {
        PersistObjects.RemovePersist(key, this.gameObject, false);
    }
}
