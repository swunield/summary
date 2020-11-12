using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using UAnimation;

[SLua.CustomLuaClass]
public class UISlideList : UIDragBehaviour, IPointerDownHandler, IPointerUpHandler
{
    [FieldLabel("容器")]
    [SerializeField]
    private RectTransform _content;
    public RectTransform content { get { return _content; } set { _content = value; } }

    [FieldLabel("标记模板索引")]
    [SerializeField]
    private int _selectTemplateIndex = 0;
    public int selectTemplateIndex { get { return _selectTemplateIndex; } set { _selectTemplateIndex = value; } }

    [FieldLabel("水平滚动")]
    [SerializeField]
    private bool _isHorizontal = true;
    public bool isHorizontal { get { return _isHorizontal; } }

    [FieldLabel("循环")]
    [SerializeField]
    private bool _isLoop = false;

    [FieldLabel("滑动时间")]
    [SerializeField]
    private float _runningDuration = 0.5f;
    public float runningDuration { get { return _runningDuration; } set { _runningDuration = value; } }

    [FieldLabel("轮播间隔")]
    [SerializeField]
    private float _autoPlayInterval = 0.0f;
    public float autoPlayInterval { get { return _autoPlayInterval; } set { _autoPlayInterval = value; } }

    [SerializeField]
    private EaseFuncSelector _easeFunc = null;
    private EaseFunction preferEaseFunc
    {
        get
        {
            if (_easeFunc == null || !_easeFunc.hasFunc)
            {
                return EaseFunc.EaseInOutCubic;
            }
            return _easeFunc.func;
        }
    }

    [SerializeField]
    private List<float> _slideScaleList = new List<float>();
    public List<float> slideScaleList { get { return _slideScaleList; } }

    [SerializeField]
    private bool _isDrag = false;
    public bool isDrag { get { return _isDrag; } set { _isDrag = value; } }

    [SerializeField]
    private float _dragDistance = 50.0f;
    public float dragDistance { get { return _dragDistance; } set { _dragDistance = value; } }

    private int _totalItemCount = 0;
    public int totalItemCount { get { return _totalItemCount; } }

    private List<UISlideListItem> _itemList = new List<UISlideListItem>();

    private System.Action<UISlideListItem, string, int, bool> _onItemInit;
    private System.Action<UISlideListItem, int, bool> _onItemRefresh;
    private System.Action<UISlideListItem, int> _onItemSelect;
    private System.Action<UISlideListItem, int> _onItemUnSelect;

    private float _startPosition = 0.0f;
    private float _itemSize = 0.0f;
    private float _spacing = 0.0f;
    private int _curSelectItemIndex = 0;
    private int _curSelectTemplateIndex = 0;
    private int _emptyCount = 0;

    private float _runningInterval = 0.0f;
    private float _runningIntervalOffset = 0.0f;
    private float _runningStartTime = 0.0f;
    private float _runningTime = 0.0f;
    private int _runningBeginSelectItemIndex = 0;
    private int _runningTargetSelectItemIndex = 0;

    private float _lastAutoPlayTime = 0.0f;
    private int _autoPlayLockStatus = 0;

    void Awake()
    {
    }

    void OnDestroy()
    {
        _onItemInit = null;
        _onItemRefresh = null;
        _onItemSelect = null;
        _onItemUnSelect = null;
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        if (_autoPlayLockStatus == 0)
        {
            _autoPlayLockStatus = 2;
        }
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        if (_autoPlayLockStatus == 2)
        {
            _autoPlayLockStatus = 0;
            _lastAutoPlayTime = Time.realtimeSinceStartup;
        }

        if (isDrag)
        {
            return;
        }

        if (isHorizontal)
        {
            if (Mathf.Abs(eventData.position.x - eventData.pressPosition.x) > 5.0f)
            {
                SelectItem(_curSelectItemIndex + (eventData.position.x > eventData.pressPosition.x ? -1 : 1), false);
            }
        }
        else
        {
            if (Mathf.Abs(eventData.position.y - eventData.pressPosition.y) > 5.0f)
            {
                SelectItem(_curSelectItemIndex + (eventData.position.y > eventData.pressPosition.y ? -1 : 1), false);
            }
        }
    }

    public override void OnBeginDrag(PointerEventData eventData)
    {
        if (_autoPlayLockStatus == 0)
        {
            _autoPlayLockStatus = 1;
        }
    }

    public override void OnEndDrag(PointerEventData eventData)
    {
        if (_autoPlayLockStatus == 1)
        {
            _autoPlayLockStatus = 0;
            _lastAutoPlayTime = Time.realtimeSinceStartup;
        }

        if (!isDrag)
        {
            return;
        }

        if (isHorizontal)
        {
            if (Mathf.Abs(content.anchoredPosition.x) > dragDistance)
            {
                var offset = content.anchoredPosition.x / (_itemSize + _spacing);
                if (SelectItem(_curSelectItemIndex + (eventData.position.x > eventData.pressPosition.x ? -1 : 1), false, false, 0, false, -offset))
                {
                    var pos = content.anchoredPosition;
                    pos.x = 0;
                    content.anchoredPosition = pos;
                }
            }
        }
        else
        {
            if (Mathf.Abs(content.anchoredPosition.y) > dragDistance)
            {
                var offset = content.anchoredPosition.y / (_itemSize + _spacing);
                if (SelectItem(_curSelectItemIndex + (eventData.position.y > eventData.pressPosition.y ? -1 : 1), false, false, 0, false, -offset))
                {
                    var pos = content.anchoredPosition;
                    pos.y = 0;
                    content.anchoredPosition = pos;
                }
            }
        }
    }

    public bool IsRunning()
    {
        return _runningStartTime != 0;
    }

    public void Init(System.Action<UISlideListItem, string, int, bool> onItemInit, System.Action<UISlideListItem, int, bool> onItemRefresh, System.Action<UISlideListItem, int> onItemSelect, System.Action<UISlideListItem, int> onItemUnSelect)
    {
        _onItemInit = onItemInit;
        _onItemRefresh = onItemRefresh;
        _onItemSelect = onItemSelect;
        _onItemUnSelect = onItemUnSelect;

        InitOriginParams();
    }

    public void SetListItemCount(int count, int selectItemIndex = 0, bool isDirect = true)
    {
        _totalItemCount = count;
        if (_totalItemCount <= 0)
        {
            selectItemIndex = 0;
            _totalItemCount = 0;
        }
        else
        {
            if (selectItemIndex < 0 || selectItemIndex >= _totalItemCount)
            {
                selectItemIndex = _curSelectItemIndex;
                selectItemIndex = (selectItemIndex >= 0 && selectItemIndex < _totalItemCount) ? selectItemIndex : 0;
            }
        }

        SelectItem(selectItemIndex, isDirect);
    }

    public void OnItemSelect(UISlideListItem item, int itemIndex)
    {
        if (_onItemSelect != null)
        {
            _onItemSelect(item, itemIndex);
        }
    }

    public void OnItemUnSelect(UISlideListItem item, int itemIndex)
    {
        if (_onItemUnSelect != null)
        {
            _onItemUnSelect(item, itemIndex);
        }
    }

    public void SelectItem(int selectItemIndex)
    {
        SelectItem(selectItemIndex, true);
    }

    public void RunToItem(int selectItemIndex)
    {
        SelectItem(selectItemIndex, false);
    }

    public bool SelectItem(int selectItemIndex, bool isDirect, bool isRunning = false, float singleInterval = 0.0f, bool forceSelect = false, float intervalOffset = 0.0f)
    {
        if (_isLoop)
        {
            return LoopSelectItem(selectItemIndex, isDirect, isRunning, singleInterval, forceSelect, intervalOffset);
        }

        selectItemIndex = selectItemIndex < 0 ? _curSelectItemIndex : selectItemIndex;
        selectItemIndex = selectItemIndex >= _totalItemCount ? _totalItemCount - 1 : selectItemIndex;
        if (_totalItemCount == 0 || selectItemIndex < 0)
        {
            selectItemIndex = 0;
        }

        if (isDirect)
        {
            var interval = selectItemIndex - _curSelectItemIndex;
            var startItemIndex = _itemList[0].itemIndex;
            var lastEmptyCount = _emptyCount;

            if (selectItemIndex < (_curSelectTemplateIndex - _emptyCount))
            {
                _emptyCount = selectItemIndex - (_curSelectTemplateIndex - _emptyCount);
            }
            else if (selectItemIndex > (_totalItemCount - (_itemList.Count - (_curSelectTemplateIndex - _emptyCount))))
            {
                _emptyCount = selectItemIndex - (_totalItemCount - (_itemList.Count - (_curSelectTemplateIndex - _emptyCount)));
            }
            else
            {
                _emptyCount = 0;
            }
            startItemIndex += (interval + lastEmptyCount - _emptyCount);

            if (!isRunning)
            {
                _runningStartTime = 0;
            }
            else if (interval != 0 && _emptyCount == 0 && lastEmptyCount == 0)
            {
                for (int i = 0; i < Mathf.Abs(interval); i++)
                {
                    if (interval < 0)
                    {
                        var item = _itemList[_itemList.Count - 1];
                        _itemList.RemoveAt(_itemList.Count - 1);
                        _itemList.Insert(0, item);
                    }
                    else
                    {
                        var item = _itemList[0];
                        _itemList.RemoveAt(0);
                        _itemList.Add(item);
                    }
                }
            }

            for (int i = 0; i < _itemList.Count; i++)
            {
                var item = _itemList[i];
                var itemIndex = startItemIndex + i;
                if (itemIndex == selectItemIndex)
                {
                    _curSelectTemplateIndex = i;
                }

                if (!item.isInit && _onItemInit != null)
                {
                    item.isInit = true;
                    _onItemInit(item, "", itemIndex, false);
                }
                if (_onItemRefresh != null && (!isRunning || selectItemIndex != _curSelectItemIndex))
                {
                    _onItemRefresh(item, itemIndex, false);
                }
                item.position = _startPosition + (i - _emptyCount - singleInterval) * (_itemSize + _spacing);
                item.itemIndex = itemIndex;
                if (itemIndex == selectItemIndex && item.isSelected && forceSelect)
                {
                    OnItemSelect(item, itemIndex);
                }
                item.isSelected = itemIndex == selectItemIndex;
            }
            UpdateSlideItemScale(singleInterval);
            _curSelectItemIndex = selectItemIndex;
            _lastAutoPlayTime = Time.realtimeSinceStartup;
            return true;
        }

        if (_runningStartTime != 0 || _curSelectItemIndex == selectItemIndex)
        {
            return false;
        }

        _runningStartTime = Time.realtimeSinceStartup;
        _runningInterval = selectItemIndex - _curSelectItemIndex;
        if (_runningInterval != 0)
        {
            _runningStartTime -= intervalOffset * _runningDuration / _runningInterval;
        }
        _runningInterval -= intervalOffset;
        _runningIntervalOffset = intervalOffset;
        _runningTargetSelectItemIndex = selectItemIndex;
        _runningBeginSelectItemIndex = _curSelectItemIndex;
        _lastAutoPlayTime = Time.realtimeSinceStartup;
        return true;
    }

    public bool LoopSelectItem(int selectItemIndex, bool isDirect = false, bool isRunning = false, float singleInterval = 0.0f, bool forceSelect = false, float intervalOffset = 0.0f)
    {
        selectItemIndex = FixLoopItemIndex(selectItemIndex);
        if (selectItemIndex < 0 || selectItemIndex >= _totalItemCount)
        {
            return false;
        }

        if (isDirect)
        {
            if (!isRunning)
            {
                _runningStartTime = 0;
            }
            else
            {
                var interval = selectItemIndex - _curSelectItemIndex;
                if (interval != 0)
                {
                    if (Mathf.Abs(interval) > Mathf.Abs(_totalItemCount - Mathf.Abs(interval)))
                    {
                        interval = interval < 0 ? _totalItemCount + interval : interval - _totalItemCount;
                    }
                    for (int i = 0; i < Mathf.Abs(interval); i++)
                    {
                        if (interval < 0)
                        {
                            var item = _itemList[_itemList.Count - 1];
                            _itemList.RemoveAt(_itemList.Count - 1);
                            _itemList.Insert(0, item);
                        }
                        else
                        {
                            var item = _itemList[0];
                            _itemList.RemoveAt(0);
                            _itemList.Add(item);
                        }
                    }
                }
            }

            selectItemIndex = FixLoopItemIndex(selectItemIndex);
            for (int i = 0; i < _itemList.Count; i++)
            {
                var item = _itemList[i];
                var itemIndex = FixLoopItemIndex(i - _curSelectTemplateIndex + selectItemIndex);
                if (itemIndex == selectItemIndex)
                {
                    _curSelectTemplateIndex = i;
                }

                if (!item.isInit && _onItemInit != null)
                {
                    item.isInit = true;
                    _onItemInit(item, "", itemIndex, false);
                }
                if (_onItemRefresh != null && (!isRunning || selectItemIndex != _curSelectItemIndex))
                {
                    _onItemRefresh(item, itemIndex, false);
                }

                item.position = _startPosition + (i - singleInterval) * (_itemSize + _spacing);
                item.itemIndex = itemIndex;
                if (itemIndex == selectItemIndex && item.isSelected && forceSelect)
                {
                    OnItemSelect(item, itemIndex);
                }
                item.isSelected = itemIndex == selectItemIndex;
            }
            UpdateSlideItemScale(singleInterval);
            _curSelectItemIndex = selectItemIndex;
            _lastAutoPlayTime = Time.realtimeSinceStartup;
            return true;
        }

        if (_runningStartTime != 0 || _curSelectItemIndex == selectItemIndex)
        {
            return false;
        }

        _runningStartTime = Time.realtimeSinceStartup;
        _runningInterval = selectItemIndex - _curSelectItemIndex;
        if (Mathf.Abs(_runningInterval) > Mathf.Abs(_totalItemCount - Mathf.Abs(_runningInterval)))
        {
            _runningInterval = _runningInterval < 0 ? _totalItemCount + _runningInterval : _runningInterval - _totalItemCount;
        }
        if (_runningInterval != 0)
        {
            _runningStartTime -= intervalOffset * _runningDuration / _runningInterval;
        }
        _runningInterval -= intervalOffset;
        _runningIntervalOffset = intervalOffset;
        _runningTargetSelectItemIndex = selectItemIndex;
        _runningBeginSelectItemIndex = _curSelectItemIndex;
        _lastAutoPlayTime = Time.realtimeSinceStartup;
        return true;
    }

    private void InitOriginParams()
    {
        var itemCount = content.childCount;
        for (int i = 0; i < itemCount; i++)
        {
            var transItem = content.GetChild(i) as RectTransform;
            var item = transItem.gameObject.GetComponent<UISlideListItem>();
            if (item == null)
            {
                item = transItem.gameObject.AddComponent<UISlideListItem>();
            }

            // 锚点格式固定
            if (_isHorizontal)
            {
                transItem.anchorMax = new Vector2(transItem.anchorMin.x, transItem.anchorMax.y);
            }
            else
            {
                transItem.anchorMax = new Vector2(transItem.anchorMax.x, transItem.anchorMin.y);
            }

            item.itemIndex = i;
            item.BindSlideList(this);
            _itemList.Add(item);
            if (i == 0)
            {
                _itemSize = _isHorizontal ? transItem.sizeDelta.x : transItem.sizeDelta.y;
                _startPosition = _isHorizontal ? transItem.localPosition.x : transItem.localPosition.y;
            }
        }
        _curSelectItemIndex = _selectTemplateIndex;
        _curSelectTemplateIndex = _selectTemplateIndex;
        _emptyCount = 0;
        _totalItemCount = _itemList.Count;

        var layoutContent = content.GetComponent<HorizontalOrVerticalLayoutGroup>();
        if (layoutContent != null)
        {
            _spacing = layoutContent.spacing;
            layoutContent.enabled = false;
        }
    }

    private void Update()
    {
        UpdateAutoPlay();
        UpdateRunning();
    }

    private void UpdateAutoPlay()
    {
        if (_autoPlayLockStatus != 0 || _autoPlayInterval == 0.0f)
        {
            return;
        }
        if (Time.realtimeSinceStartup - _lastAutoPlayTime < _autoPlayInterval)
        {
            return;
        }

        var index = _curSelectItemIndex + 1;
        if (index >= _totalItemCount)
        {
            index = 0;
        }
        SelectItem(index, false, false);
    }

    private void UpdateRunning()
    {
        if (_runningStartTime == 0)
        {
            return;
        }

        _runningTime = Time.realtimeSinceStartup - _runningStartTime;
        if (_runningTime >= _runningDuration)
        {
            _runningStartTime = 0.0f;
            _runningTime = 0.0f;
            _runningInterval = 0;
            _runningIntervalOffset = 0;
            SelectItem(_runningTargetSelectItemIndex, true, true, 0);
            _runningTargetSelectItemIndex = 0;
            _runningBeginSelectItemIndex = 0;
            return;
        }

        OnRunning();
    }

    private void OnRunning()
    {
        if (_isLoop)
        {
            OnLoopRunning();
            return;
        }

        var interval = _runningInterval * preferEaseFunc(_runningTime / _runningDuration) + _runningIntervalOffset;
        var intervalIndex = (int)interval;
        var singleInterval = interval % 1;
        var selectItemIndex = _runningBeginSelectItemIndex + intervalIndex;
        if (singleInterval > 0.5f)
        {
            selectItemIndex++;
            singleInterval--;
        }
        else if (singleInterval < -0.5f)
        {
            selectItemIndex--;
            singleInterval++;
        }
        SelectItem(selectItemIndex, true, true, singleInterval);
    }

    private void OnLoopRunning()
    {
        var interval = _runningInterval * preferEaseFunc(_runningTime / _runningDuration) + _runningIntervalOffset;
        var intervalIndex = (int)interval;
        var singleInterval = interval % 1;
        var selectItemIndex = _runningBeginSelectItemIndex + intervalIndex;
        if (singleInterval > 0.5f)
        {
            selectItemIndex++;
            singleInterval--;
        }
        else if (singleInterval < -0.5f)
        {
            selectItemIndex--;
            singleInterval++;
        }
        selectItemIndex = FixLoopItemIndex(selectItemIndex);
        SelectItem(selectItemIndex, true, true, singleInterval);
    }

    private int FixLoopItemIndex(int itemIndex)
    {
        if (itemIndex < 0)
        {
            itemIndex += _totalItemCount;
        }
        else if (itemIndex >= _totalItemCount)
        {
            itemIndex -= _totalItemCount;
        }
        else
        {
            return itemIndex;
        }
        return FixLoopItemIndex(itemIndex);
    }

    private void UpdateSlideItemScale(float singleInterval = 0.0f)
    {
        if (_slideScaleList.Count == 0)
        {
            return;
        }

        for (int i = 0; i < _itemList.Count; i++)
        {
            var interval = singleInterval;
            var index = i;
            var scaleIndex = Mathf.Abs(index - _curSelectTemplateIndex);
            var scale = scaleIndex >= _slideScaleList.Count ? _slideScaleList[_slideScaleList.Count - 1] : _slideScaleList[scaleIndex];
            if (_runningInterval != 0 && interval != 0.0f)
            {
                index = _runningInterval * interval > 0 ? i : (interval < 0 ? i + 1 : i - 1);
                scaleIndex = Mathf.Abs(index - _curSelectTemplateIndex);
                scale = scaleIndex >= _slideScaleList.Count ? _slideScaleList[_slideScaleList.Count - 1] : _slideScaleList[scaleIndex];

                var nextIndex = _runningInterval * interval < 0 ? i : (interval < 0 ? i + 1 : i - 1);
                var nextScaleIndex = Mathf.Abs(nextIndex - _curSelectTemplateIndex);
                var nextScale = nextScaleIndex >= _slideScaleList.Count ? _slideScaleList[_slideScaleList.Count - 1] : _slideScaleList[nextScaleIndex];

                interval = _runningInterval * interval > 0 ? interval : (interval > 0 ? interval - 1 : interval + 1);
                scale = scale + (nextScale - scale) * Mathf.Abs(interval);
            }

            _itemList[i].itemTransform.localScale = new Vector3(scale, scale);
        }
    }
}
