
using System.Collections.Generic;

public class LRUCache<K, T>
{
    private int _size;                              // 链表长度
    private int _capacity;                          // 缓存容量 
    private Dictionary<K, ListNode<T>> _dictCache;  // key +缓存数据
    private ListNode<T> _linkHead;

    public event System.Action<T, int> onElementRemove;

    public LRUCache(int capacity)
    {
        _linkHead = new ListNode<T>(default(K), default(T));
        _linkHead.Next = _linkHead.Prev = _linkHead;
        this._size = 0;
        this._capacity = capacity;
        this._dictCache = new Dictionary<K, ListNode<T>>();
    }

    public void Clear()
    {
        if (_linkHead.Next == _linkHead.Prev && _linkHead.Next == _linkHead)
        {
            return;
        }

        while (_linkHead.Prev != null)
        {
            RemoveLast();
        }
    }

    public int capacity
    {
        get
        {
            return _capacity;
        }
        set
        {
            _capacity = value;
        }
    }

    public Dictionary<K, ListNode<T>>.KeyCollection KeySet
    {
        get
        {
            return _dictCache.Keys;
        }
    }

    public bool ContainsKey(K key)
    {
        return _dictCache.ContainsKey(key);
    }

    public T Get(K key)
    {
        if (_dictCache.ContainsKey(key))
        {
            ListNode<T> n = _dictCache[key];
            MoveToHead(n);
            return n.Value;
        }
        else
        {
            return default(T);
        }
    }

    public void Set(K key, T value, int tryRemoveTimes = 0)
    {
        ListNode<T> n;
        if (_dictCache.ContainsKey(key))
        {
            n = _dictCache[key];
            n.Value = value;
            MoveToHead(n);
        }
        else
        {
            n = new ListNode<T>(key, value);
            AttachToHead(n);
            _size++;
            _dictCache.Add(key, n);
        }
        if (_size > _capacity && tryRemoveTimes < _capacity)
        {
            _size--;
            RemoveLast(tryRemoveTimes);// 如果更新节点后超出容量，删除最后一个
        }
    }

    public bool Remove(K key)
    {
        ListNode<T> n;
        if (_dictCache.ContainsKey(key))
        {
            n = _dictCache[key];
            RemoveFromList(n);
            _dictCache.Remove(key);
            if (onElementRemove != null)
            {
                onElementRemove(n.Value, 0);
            }
            return true;
        }
        return false;
    }

    public bool RemoveWithoutNotify(K key)
    {
        ListNode<T> n;
        if (_dictCache.ContainsKey(key))
        {
            n = _dictCache[key];
            RemoveFromList(n);
            _dictCache.Remove(key);
            return true;
        }
        return false;
    }

    // 移出链表最后一个节点
    private void RemoveLast(int tryRemoveTimes = 0)
    {
        ListNode<T> deNode = _linkHead.Prev;
        RemoveFromList(deNode);
        _dictCache.Remove(deNode.Key);
        if (onElementRemove != null)
        {
            onElementRemove(deNode.Value, tryRemoveTimes);
        }
    }

    // 将一个孤立节点放到头部
    private void AttachToHead(ListNode<T> n)
    {
        n.Prev = _linkHead;
        n.Next = _linkHead.Next;
        _linkHead.Next.Prev = n;
        _linkHead.Next = n;
    }

    // 将一个链表中的节点放到头部
    private void MoveToHead(ListNode<T> n)
    {
        RemoveFromList(n);
        AttachToHead(n);
    }

    private void RemoveFromList(ListNode<T> n)
    {
        //将该节点从链表删除
        n.Prev.Next = n.Next;
        n.Next.Prev = n.Prev;
    }

    public class ListNode<T>
    {
        public ListNode<T> Prev;
        public ListNode<T> Next;
        public T Value;
        public K Key;

        public ListNode(K key, T val)
        {
            Value = val;
            Key = key;
            this.Prev = null;
            this.Next = null;
        }
    }
}
