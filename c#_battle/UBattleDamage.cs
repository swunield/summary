using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.UI;

[SLua.CustomLuaClass]
public class UBattleDamage : MonoBehaviour
{
    [SerializeField]
    private Text _txtDamage = null;
    public Text txtDamage { get { return _txtDamage; } set { _txtDamage = value; } }
}
