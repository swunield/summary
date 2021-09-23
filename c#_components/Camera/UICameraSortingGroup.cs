using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public class UICameraSortingGroup : MonoBehaviour
{
    [SerializeField]
    private int _sortingOrderMax = 10;
    public int sortingOrderMax { get { return _sortingOrderMax; } set { _sortingOrderMax = value; } }

    [SerializeField]
    private Camera _uiCamera = null;
    public Camera uiCamera { get { return _uiCamera; } set { _uiCamera = value; } }

    private int _baseSortingOrder = 0;
    public int baseSortingOrder { get { return _baseSortingOrder; } set { _baseSortingOrder = value; } }

    private List<UICameraSorting> _sortingList = new List<UICameraSorting>();

    public void UpdateGroup(int baseOrder, Camera camera)
    {
        if (baseSortingOrder == baseOrder && camera == uiCamera)
        {
            return;
        }
        baseSortingOrder = baseOrder;
        uiCamera = camera;
        
        // 刷新现有Sorting
        for (int i = 0; i < _sortingList.Count; i++)
        {
            var sorting = _sortingList[i];
            sorting.UpdateSorting(sorting.GetRealSortingOrder());
        }
    }

    public void Bind(UICameraSorting sorting)
    {
        _sortingList.Add(sorting);
    }

    public void UnBind(UICameraSorting sorting)
    {
        for (int i = 0; i < _sortingList.Count; i++)
        {
            if (_sortingList[i] == sorting)
            {
                _sortingList.RemoveAt(i);
                break;
            }
        }
    }
}
