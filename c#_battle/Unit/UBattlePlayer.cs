using System.Collections;
using System.Collections.Generic;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

[SLua.CustomLuaClass]
public class LUBattlePlayer
{
    public static void SetBattleField(int unitId, string prefabName, string prefabFolder)
    {
        ObjectCache.GetComponent<UBattlePlayer>(unitId)?.SetBattleField(prefabName, prefabFolder);
    }

    public static void ShowDamage(int unitId, int targetUnitId, int damage, int prefabNameId, int prefabFolderId, int boneNameId)
    {
        var player = ObjectCache.GetComponent<UBattlePlayer>(unitId);
        if (player == null)
        {
            return;
        }
        var targetUnit = ObjectCache.GetComponent<UBattleUnit>(targetUnitId);
        if (targetUnit == null)
        {
            return;
        }
        player.ShowDamage(targetUnit, damage, prefabNameId, prefabFolderId, boneNameId);
    }

    public static int GetGridIndexByPosition(int unitId, Vector3 position)
    {
        var player = ObjectCache.GetComponent<UBattlePlayer>(unitId);
        if (player == null)
        {
            return 0;
        }
        return player.GetGridIndexByPosition(position);
    }
}

[ExecuteInEditMode]
[SLua.CustomLuaClass]
public class UBattlePlayer : UBattleUnit
{
    [SerializeField]
    private bool _isPlayerSelf = false;

    [SerializeField]
    private int _playerId = 0;
    public int playerId { get { return _playerId; } set { _playerId = value; } }

    [SerializeField]
    private GameObjectPoolContainer _fieldContaner = null;
    public GameObjectPoolContainer fieldContainer { get { return _fieldContaner; } }

    [SerializeField]
    private List<UBattleCanvasGrid> _canvasGridList = new List<UBattleCanvasGrid>();
    public List<UBattleCanvasGrid> canvasGridList { get { return _canvasGridList; } set { _canvasGridList = value; } }

    [SerializeField]
    private List<UBattleTower> _towerList = new List<UBattleTower>();
    public List<UBattleTower> towerList { get { return _towerList; } set { _towerList = value; } }

    [SerializeField]
    private List<CacheObject> _gridList = new List<CacheObject>();
    public List<CacheObject> gridList { get { return _gridList; } set { _gridList = value; } } 

    [SerializeField]
    private List<Vector4> _monsterPathPointList = new List<Vector4>();
    public List<Vector4> monsterPathPointList { get { return _monsterPathPointList; } set { _monsterPathPointList = value; } }

    [SerializeField]
    private CacheObject _objMonsterRoad = null;
    public GameObject objMonsterRoad { get { return _objMonsterRoad.cacheObject.gameObject; } }
    public int objMonsterRoadId { get { return _objMonsterRoad.cacheObject.cacheId; } }

    [SerializeField]
    private GameObject _objTopCanvas = null;
    public GameObject objTopCanvas { get { return _objTopCanvas; } set { _objTopCanvas = value; } }

    [SerializeField]
    private GameObjectPool _damagePool;
    public GameObjectPool damagePool
    {
        get
        {
            if (_damagePool == null)
            {
                _damagePool = GameObjectPool.INSTANCE;
            }
            return _damagePool;
        }
        set
        {
            _damagePool = value;
        }
    }

    private List<UBattleMonster> _monsterList = new List<UBattleMonster>();

    protected override void Awake()
    {
        base.Awake();

        if (_isPlayerSelf)
        {
            // 己方节点绑定拖拽
            for (int i = 0; i < canvasGridList.Count; i++)
            {
                var canvasGrid = canvasGridList[i];
                var grid = gridList[i].cacheObject.GetComponent<UBattleGrid>();
                canvasGrid.BindDragTower(grid.towerContainer.gameObject);
            }
        }
    }

    public UBattleTower GetUBattleTower(int index)
    {
        if (index < 0 || index >= _towerList.Count)
        {
            return null;
        }
        return _towerList[index];
    }

    public UBattleGrid GetUBattleGrid(int index)
    {
        if (index < 0 || index >= _gridList.Count)
        {
            return null;
        }
        return _gridList[index].cacheObject.GetComponent<UBattleGrid>();
    }

    public int GetUBattleGridId(int index)
    {
        if (index < 0 || index >= _gridList.Count)
        {
            return 0;
        }
        return _gridList[index].cacheObject.cacheId;
    }

    public int GetGridIndexByPosition(Vector3 position)
    {
        for (int i = 0; i < _canvasGridList.Count; i++)
        {
            var gridTransform = _canvasGridList[i].objGrid.transform as RectTransform;
            var localPosition = gridTransform.InverseTransformPoint(position);
            if (gridTransform.rect.Contains(localPosition))
            {
                return i;
            }
        }
        return -1;
    }

    public void ShowDamage(UBattleUnit unit, int damage, int prefabNameId, int prefabFolderId, int boneNameId)
    {
        var prefabName = GameStrings.Get(prefabNameId);
        var prefabFolder = GameStrings.Get(prefabFolderId);
        var uDamage = damagePool.RequestComponent<UBattleDamage>(prefabName, prefabFolder, true, this.objTopCanvas.transform);
        if (uDamage == null)
        {
            return;
        }
        using (zstring.Block())
        {
            uDamage.txtDamage.text = zstring.Format("{0}", damage).Intern();
        }
        var boneName = GameStrings.Get(boneNameId);
        boneName = string.IsNullOrEmpty(boneName) ? "head" : boneName;
        uDamage.transform.position = unit.GetBonePosition(boneName);
    }

    public void SetBattleField(string prefabName, string prefabFolder)
    {
        fieldContainer?.RefreshPoolContainer(prefabName, prefabFolder);
    }

    public void RestoreCanvasGrid()
    {
        var count = _canvasGridList.Count;
        for (int i = 0; i < count; i++)
        {
            _canvasGridList[i].Restore();
        }
    }

    public void RestoreGrid()
    {
        var count = _gridList.Count;
        for (int i = 0; i < count; i++)
        {
            _gridList[i].GetComponent<UBattleGrid>().Restore();
        }
    }

#if UNITY_EDITOR
    private void OnDrawGizmos()
    {
        for (int i = 0; i < monsterPathPointList.Count - 1; i++)
        {
            var start = monsterPathPointList[i];
            var end = monsterPathPointList[i + 1];
            Gizmos.DrawLine(start, end);
            Handles.Label((start + end) * 0.5f, Mathf.Sqrt(Mathf.Pow(start.x - end.x, 2) + Mathf.Pow(start.y - end.y, 2)).ToString());
        }
    }
#endif
}
