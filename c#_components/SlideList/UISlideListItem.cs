using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;

[SLua.CustomLuaClass]
public class UISlideListItem : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
{
    [SerializeField]
    private UnityEvent _selectEvent = new UnityEvent();

    [SerializeField]
    private UnityEvent _unSelectEvent = new UnityEvent();

    [SerializeField]
    private UnityEvent _clickEvent = new UnityEvent();

    [SerializeField]
    private int _itemIndex = 0;
    public int itemIndex
    {
        get
        {
            return _itemIndex;
        }
        set
        {
            _itemIndex = value;
            this.gameObject.name = string.Format("item_{0}", value);
        }
    }

    private RectTransform _itemTranform;
    public RectTransform itemTransform { get { return _itemTranform; } }

    private UISlideList _slideList = null;
    public UISlideList slideList { get { return _slideList; } set { _slideList = value; } }

    private bool _isInit = false;
    public bool isInit { get { return _isInit; } set { _isInit = value; } }

    private float _size = 0.0f;
    public float size { get { return _size; } set { _size = value; } }

    private bool _isSelected = false;
    public bool isSelected
    {
        get
        {
            return _isSelected;
        }
        set
        {
            if (_isSelected && !value)
            {
                OnUnSelect();
            }
            else if (!_isSelected && value)
            {
                OnSelect();
            }

            _isSelected = value;
        }
    }

    private float _position = 0.0f;
    public float position
    {
        get
        {
            return _position;
        }
        set
        {
            _position = value;
            var localPosition = _itemTranform.localPosition;
            if (_slideList.isHorizontal)
            {
                localPosition.x = _position;
            }
            else
            {
                localPosition.y = _position;
            }
            _itemTranform.localPosition = localPosition;
        }
    }

    private void OnDestroy()
    {
        _selectEvent.RemoveAllListeners();
        _unSelectEvent.RemoveAllListeners();
        _clickEvent.RemoveAllListeners();
    }

    public void OnPointerDown(PointerEventData eventData)
    {
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        if (Mathf.Abs(eventData.pressPosition.x - eventData.position.x) < 5.0f && Mathf.Abs(eventData.pressPosition.y - eventData.position.y) < 5.0f)
        {
            OnClickItem();
        }
        else
        {
            _slideList.OnPointerUp(eventData);
        }
    }

    public void BindSlideList(UISlideList slideList)
    {
        _itemTranform = this.transform as RectTransform;
        _slideList = slideList;
        size = _slideList.isHorizontal ? _itemTranform.sizeDelta.x : _itemTranform.sizeDelta.y;
        _position = _slideList.isHorizontal ? _itemTranform.localPosition.x : _itemTranform.localPosition.y;
        OnUnSelect();
    }

    public void OnClickItem()
    {
        _clickEvent.Invoke();
    }

    public void SelectSelf()
    {
        _slideList.SelectItem(this.itemIndex, false);
    }

    private void OnSelect()
    {
        _selectEvent.Invoke();
        _slideList.OnItemSelect(this, this.itemIndex);
    }

    private void OnUnSelect()
    {
        _unSelectEvent.Invoke();
    }
}
