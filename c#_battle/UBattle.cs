using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattle : MonoBehaviour
{
    private static UBattle _instance = null;
    public static UBattle INSTANCE { get { return _instance; } }
    public static GameLoop LOOPER { get { return _instance?.looper; } }

    [SerializeField]
    private List<UBattlePlayer> _playerList = new List<UBattlePlayer>();
    public List<UBattlePlayer> playerList { get { return _playerList; } set { _playerList = value; } }

    [SerializeField]
    private GameLoop _looper = null;
    public GameLoop looper { get { return _looper; } set { _looper = value; } }

    private List<UBattleUnit> _sortUnitList = new List<UBattleUnit>();

    public UBattlePlayer GetUBattlePlayer(int index)
    {
        if (index < 0 || index >= _playerList.Count)
        {
            return null;
        }
        return _playerList[index];
    }

    public void Init(Func<int, int, int> loopCallBack)
    {
        _instance = this;
        looper.Reset();
        looper.SetLoopCallBack(loopCallBack);
    }

    public void Destroy()
    {
        looper.Reset();
        looper.SetLoopCallBack(null);
        _sortUnitList.Clear();
        _instance = null;
    }

    public void AddSortUnit(UBattleUnit unit)
    {
        _sortUnitList.Add(unit);
    }

    public void RemoveSortUnit(UBattleUnit unit)
    {
        for (int i = 0; i < _sortUnitList.Count; i++)
        {
            if (unit.unitId == _sortUnitList[i].unitId)
            {
                _sortUnitList.RemoveAt(i);
                break;
            }
        }
    }

    public void RemoveAllSortUnit()
    {
        _sortUnitList.Clear();
    }

    public void RestoreCanvasGrid()
    {
        for (int i = 0; i < _playerList.Count; i++)
        {
            _playerList[i].RestoreCanvasGrid();
        }
    }

    public void RestoreGrid()
    {
        for (int i = 0; i < _playerList.Count; i++)
        {
            _playerList[i].RestoreGrid();
        }
    }

    private void LateUpdate()
    {
        var count = _sortUnitList.Count;
        if (count == 0)
        {
            return;
        }
        _sortUnitList.Sort(UBattleUnit.PositionComparer);
        for (int i = 0; i < count; i++)
        {
            _sortUnitList[i].Sort(i);
        }
    }
}
