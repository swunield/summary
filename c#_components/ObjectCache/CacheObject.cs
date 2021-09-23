using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public partial class ObjectCache
{
    private static Dictionary<int, Component> AllCachedObjects = new Dictionary<int, Component>();
    private static ObjectNameCache _objectNameCache = null;

    public static void Initialize(string cachePath)
    {
        _objectNameCache = GameResLoader.INSTANCE.LoadRes<ObjectNameCache>(cachePath);
    }

    public static void Regist(int cacheId, Component component, bool force = false)
    {
        if (cacheId == 0 || component == null)
        {
            return;
        }
        if (AllCachedObjects.ContainsKey(cacheId))
        {
            if (!force)
            {
                return;
            }
            UnRegist(cacheId, null, true);
        }
        AllCachedObjects[cacheId] = component;
    }

    public static void UnRegist(int cacheId, Component component, bool force = false)
    {
        if (cacheId == 0)
        {
            return;
        }
        Component oldObject = null;
        if (!AllCachedObjects.TryGetValue(cacheId, out oldObject))
        {
            return;
        }
        if (!force && component != null && oldObject != null && oldObject != component)
        {
            return;
        }
        AllCachedObjects.Remove(cacheId);
    }

    public static Component GetComponent(int cacheId, bool needDecode = false)
    {
        int index = 0;
        if (needDecode)
        {
            cacheId = DecodeCacheId(cacheId, out index);
        }
        Component component = null;
        if (!AllCachedObjects.TryGetValue(cacheId, out component))
        {
            return null;
        }
        if (index != 0)
        {
            var cacheObject = component as CacheObject;
            if (cacheObject != null)
            {
                return cacheObject.GetComponent(index);
            }
        }
        return component;
    }

    public static T GetComponent<T>(int cacheId, bool needDecode = false) where T : Component
    {
        var component = GetComponent(cacheId, needDecode);
        return component as T;
    }

    public static Component GetComponent(int cacheId, System.Type type, bool needDecode = false)
    {
        var component = GetComponent(cacheId, needDecode);
        if (component != null && type.IsAssignableFrom(component.GetType()))
        {
            return (Component)System.Convert.ChangeType(component, type);
        }
        return null;
    }

    public static Component GetComponent(int cacheId, int index)
    {
        if (index == 0)
        {
            return GetComponent(cacheId);
        }
        var cacheObject = GetComponent<CacheObject>(cacheId);
        return cacheObject?.GetComponent<Component>(index);
    }

    public static T GetComponent<T>(int cacheId, int index) where T : Component
    {
        if (index == 0)
        {
            return GetComponent<T>(cacheId);
        }
        var cacheObject = GetComponent<CacheObject>(cacheId);
        return cacheObject?.GetComponent<T>(index);
    }

    public static Component GetComponent(int cacheId, int index, System.Type type)
    {
        var component = GetComponent(cacheId, index);
        if (component != null && type.IsAssignableFrom(component.GetType()))
        {
            return (Component)System.Convert.ChangeType(component, type);
        }
        return null;
    }

    public static GameObject GetGameObject(int cacheId, bool needDecode = false)
    {
        var component = GetComponent(cacheId, needDecode);
        return component != null ? component.gameObject : null;
    }

    public static GameObject GetGameObject(int cacheId, int index)
    {
        var component = GetComponent(cacheId, index);
        return component != null ? component.gameObject : null;
    }

    public static int GetId(string cacheName)
    {
        return _objectNameCache == null ? 0 : _objectNameCache.GetId(cacheName);
    }

    public static void Print()
    {
        foreach(var key in AllCachedObjects.Keys)
        {
            FTDebug.LogWarning($"CacheObject ID[{key}] Object[{AllCachedObjects[key].name}-{AllCachedObjects[key].GetInstanceID()}]");
        }
        FTDebug.LogWarning($"ObjectCache Count[{AllCachedObjects.Count}]");
    }
}

public class CacheObject : MonoBehaviour
{
    public enum CacheMode
    {
        Manual = 0,
        Awake = 1,
        Enable = 2,
    }

    [SerializeField]
    private CacheMode _cacheMode = CacheMode.Enable;

    [SerializeField]
    private bool _cacheSelf = true;

    [SerializeField]
    private List<CacheObjectItem> _cacheItems = new List<CacheObjectItem>();

    [SerializeField]
    private CacheObjectItem _cacheObject = new CacheObjectItem();
    public CacheObjectItem cacheObject { get { return _cacheObject; } }

    private int _cacheItemCount = 0;

    private void Awake()
    {
        _cacheItemCount = _cacheItems.Count;

        if (_cacheSelf && _cacheObject.component == null)
        {
            _cacheObject.component = this;
        }

        if (_cacheMode == CacheMode.Awake)
        {
            Regist();
        }
    }

    private void OnDestroy()
    {
        if (_cacheMode == CacheMode.Awake)
        {
            UnRegist();
        }
    }

    private void OnEnable()
    {
        if (_cacheMode == CacheMode.Enable)
        {
            Regist();
        }
    }

    private void OnDisable()
    {
        if (_cacheMode == CacheMode.Enable)
        {
            UnRegist();
        }
    }

    public void Regist()
    {
        for (int i = 0; i < _cacheItemCount; i++)
        {
            var item = _cacheItems[i];
            if (item.IsItemNeedRegist())
            {
                item.Regist();
            }
        }
        if (_cacheSelf)
        {
            cacheObject.Regist();
        }
    }
    
    public void UnRegist()
    {
        for (int i = 0; i < _cacheItemCount; i++)
        {
            _cacheItems[i].UnRegist();
        }
        if (_cacheSelf)
        {
            cacheObject.UnRegist();
        }
    }

    public Component GetComponent(int index = 0)
    {
        if (index <= 0 || index > _cacheItemCount)
        {
            return _cacheObject.component;
        }
        return _cacheItems[index - 1].component;
    }

    public T GetComponent<T>(int index = -1) where T : Component
    {
        if (index <= 0 || index > _cacheItemCount)
        {
            return _cacheObject.component as T;
        }
        return _cacheItems[index - 1].component as T;
    }
}

[System.Serializable]
public class CacheObjectItem
{
    private readonly static string GameObjectInsKey = "GameObject";

    [SerializeField]
    private Component _component;
    public Component component { get { return _component; } set { _component = value; } }

    [SerializeField]
    private string _cacheName = string.Empty;
    public string cacheName { get { return _cacheName; } set { _cacheName = value; } }

    [SerializeField]
    private int _cacheId = 0;
    public int cacheId
    {
        get
        {
            if (_cacheId == 0)
            {
                cacheId = GetDefaultCacheId();
            }
            else if (!_isRegisted)
            {
                Regist(_cacheId);
            }
            return _cacheId;
        }
        set
        {
            if (value == 0 && _cacheId != 0)
            {
                UnRegist();
            }
            else if (value != 0 && (_cacheId != value || !_isRegisted))
            {
                Regist(value);
            }
            _cacheId = value;
        }
    }

    private GameObject _gameObject = null;
    public GameObject gameObject
    {
        get
        {
            if (_gameObject == null)
            {
                _gameObject = component.gameObject;
            }
            return _gameObject;
        }
        set
        {
            _gameObject = value;
        }
    }

    private Transform _transform = null;
    public Transform transform
    {
        get
        {
            if (_transform == null)
            {
                _transform = gameObject.transform;
            }
            return _transform;
        }
    }

    private bool _isRegisted = false;

    public void Regist(int cacheId = -1)
    {
        if (_isRegisted && (_cacheId == cacheId || cacheId == -1))
        {
            return;
        }
        cacheId = cacheId == -1 ? _cacheId : cacheId;
        cacheId = cacheId == 0 ? GetDefaultCacheId() : cacheId;
        UnRegist();
        ObjectCache.Regist(cacheId, component);
        _cacheId = cacheId;
        _isRegisted = true;
    }

    public void UnRegist()
    {
        if (!_isRegisted)
        {
            return;
        }
        ObjectCache.UnRegist(_cacheId, component);
        if (!string.IsNullOrEmpty(_cacheName))
        {
            _cacheId = 0;
        }
        _isRegisted = false;
    }

    public T GetComponent<T>() where T : Component
    {
        return component as T;
    }

    public int GetDefaultCacheId()
    {
        if (GameObjectInsKey.Equals(_cacheName))
        {
            return component.gameObject.GetInstanceID();
        }
        var cacheId = ObjectCache.GetId(_cacheName);
        if (cacheId == 0)
        {
            cacheId = component.GetInstanceID();
        }
        return cacheId;
    }

    public int GetOriginCacheId()
    {
        return _cacheId;
    }

    public bool IsItemNeedRegist()
    {
        return _component != null && (!string.IsNullOrEmpty(_cacheName) || _cacheId != 0);
    }
}

