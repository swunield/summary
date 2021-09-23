using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

[SLua.CustomLuaClass]
public class UBattleField : MonoBehaviour
{
    [SerializeField]
    private int _fieldType = 0;
    public int fieldType { get { return _fieldType; } set { if (_fieldType == value) return; _fieldType = value; SwitchBattle(_fieldType); } }

    [SerializeField]
    private List<UBattle> _uBattleList = new List<UBattle>();

    public UBattle SwitchBattle(int fieldType)
    {
        if (fieldType < 0 || fieldType >= _uBattleList.Count)
        {
            return null;
        }
        for (int i = 0; i < _uBattleList.Count; i++)
        {
            _uBattleList[i].gameObject.SetActive(i == fieldType);
        }
        _fieldType = fieldType;
        return _uBattleList[fieldType];
    }

    public void RestoreCanvasGrid()
    {
        _uBattleList[_fieldType]?.RestoreCanvasGrid();
    }

    public void RestoreGrid()
    {
        _uBattleList[_fieldType]?.RestoreGrid();
    }
}
