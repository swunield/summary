using Feelingtouch.Core.Cache;
using Feelingtouch.Core.Config;
using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Feelingtouch.Core.Util.Thread;
using Game.Model;
using Game.Model.Config;
using Game.Utils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Game.Service
{
    /// <summary>
    /// 榜单服务 - 中心服
    /// </summary>
    public class RankCenterService
    {
        private static readonly ILogger Logger = LoggerManager.Load<RankCenterService>();
        /// <summary>
        /// PK榜单容量
        /// </summary>
        public const int PKRankCapacity = 200;
        /// <summary>
        /// PK榜单池
        /// </summary>
        private static RankPool<int, TRankPKItem> PKRankPool = null;
        /// <summary>
        /// COOP榜单容量
        /// </summary>
        public const int COOPRankCapacity = 100;
        /// <summary>
        /// COOP榜单池
        /// </summary>
        private static RankPool<string, TRankCOOPItem> COOPRankPool = null;
        /// <summary>
        /// 运行服务器Id
        /// </summary>
        public static Lazy<int> RunServerId = new Lazy<int>(
            () =>
            {
                var nodesConfig = ConfigManager.LoadConfig<NodesConfig>();
                if (nodesConfig == null)
                {
                    Logger.LogError($"Cannot load nodesConfig.");
                    return -1;
                }
                //查找第1个榜单服, 唯一
                var node = nodesConfig.Nodes.Values.FirstOrDefault(n => n.Role.HasRole(ServerRole.Rank));
                if (node == null)
                {
                    Logger.LogError($"Cannot rank serverId.");
                    return -1;
                }
                return node.ServerId;
            },
            LazyThreadSafetyMode.ExecutionAndPublication
        );
        
        /// <summary>
        /// 开始服务
        /// </summary>
        public static async Task Start()
        {
            //只在榜单服运行
            if (!Host.Role.HasRole(ServerRole.Rank))
            {
                Logger.LogDebug("Skip");
                return;
            }

            Logger.LogDebug("Start");

            PKRankPool = new RankPool<int, TRankPKItem>(PKRankCapacity, deleteIfFull: true);
            COOPRankPool = new RankPool<string, TRankCOOPItem>(COOPRankCapacity, deleteIfFull: true);

            //PK榜单
            await TRankPKItem.Cache.LoadAllEntitiesAsync();
            PKRankPool.Load(TRankPKItem.Cache, CheckPKItemAvailable, true);

            Logger.LogDebug($"Load TRankPKItem Count[{TRankPKItem.Cache.Entities.Count()}]");
            Logger.LogDebug($"Create PKRankPool Count[{PKRankPool.Count}]");
            var pkFirst = PKRankPool.First;
            if (pkFirst != null) Logger.LogDebug($"PKRankPool.First Score[{pkFirst.Score}]");
            var pkLast = PKRankPool.Last;
            if (pkLast != null) Logger.LogDebug($"PKRankPool.Last Score[{pkLast.Score}]");

            //COOP榜单
            await TRankCOOPItem.Cache.LoadAllEntitiesAsync();
            COOPRankPool.Load(TRankCOOPItem.Cache, CheckCOOPItemAvailable, true);

            Logger.LogDebug($"Load TRankCOOPItem Count[{TRankCOOPItem.Cache.Entities.Count()}]");
            Logger.LogDebug($"Create COOPRankPool Count[{COOPRankPool.Count}]");
            var coopFirst = COOPRankPool.First;
            if (coopFirst != null) Logger.LogDebug($"COOPRankPool.First Round[{coopFirst.Round}]");
            var coopLast = COOPRankPool.Last;
            if (coopLast != null) Logger.LogDebug($"COOPRankPool.Last Round[{coopLast.Round}]");
        }
        /// <summary>
        /// PK榜单条目是否有效
        /// </summary>
        private static bool CheckPKItemAvailable(TRankPKItem item) => item != null && item.Score >= ConfigConstants.PK_RANKING_MIN;
        /// <summary>
        /// COOP榜单条目是否有效
        /// </summary>
        private static bool CheckCOOPItemAvailable(TRankCOOPItem item) => item != null && item.Round >= ConfigConstants.COOP_RANKING_MIN;
        /// <summary>
        /// 获取PK榜单已上榜的最小分数
        /// </summary>
        private static int GetPKMinScore()
        {
            if (PKRankPool == null)
            {
                Logger.LogError("PKRankPool == null");
                return ConfigConstants.PK_RANKING_MIN;
            }
            //榜单未满时, 返回允许上榜的最低分
            if (!PKRankPool.Full)
            {
                return ConfigConstants.PK_RANKING_MIN;
            }
            //榜单已满时, 返回榜尾的分数
            var item = PKRankPool.Last;
            if (item == null)
            {
                Logger.LogError("Cannot get PKRankPool last item");
                return ConfigConstants.PK_RANKING_MIN;
            }
            return item.Score;
        }
        /// <summary>
        /// 获取COOP榜单已上榜的最小回合数
        /// </summary>
        private static int GetCOOPMinRound()
        {
            if (COOPRankPool == null)
            {
                Logger.LogError("COOPRankPool == null");
                return ConfigConstants.COOP_RANKING_MIN;
            }
            //榜单未满时, 返回允许上榜的最低回合数
            if (!COOPRankPool.Full)
            {
                return ConfigConstants.COOP_RANKING_MIN;
            }
            var item = COOPRankPool.Last;
            if (item == null)
            {
                Logger.LogError("Cannot get COOPRankPool last item");
                return ConfigConstants.COOP_RANKING_MIN;
            }
            return item.Round;
        }

        /// <summary>
        /// 加载榜单数据包
        /// </summary>
        [Rpc]
        public static async Task<TRankPack> RemoteLoadPack(int serverId)
        {
            if (serverId < 0) return null;
            if (RunServerId.Value < 0) return null;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId),
                () =>
                {
                    if (PKRankPool == null)
                    {
                        Logger.LogError("PKRankPool == null");
                        return null;
                    }
                    if (COOPRankPool == null)
                    {
                        Logger.LogError("COOPRankPool == null");
                        return null;
                    }
                    var pack = new TRankPack()
                    {
                        PKList = PKRankPool.GetRange(0, 99),
                        COOPList = COOPRankPool.GetRange(0, 99),
                    };
                    var pkCount = pack.PKList == null ? 0 : pack.PKList.Count;
                    var coopCount = pack.COOPList == null ? 0 : pack.COOPList.Count;
                    Logger.LogDebug($"[Success]ServerId[{serverId}] load RankPack pkCount[{pkCount}]coopCount[{coopCount}]");
                    return pack;
                }
            );
        }

        /// <summary>
        /// 获取PK榜单已上榜的最小分数
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteGetPKMinScore(int serverId)
        {
            if (RunServerId.Value < 0) return ConfigConstants.PK_RANKING_MIN;
            if (serverId < 0) return ConfigConstants.PK_RANKING_MIN;

            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId),
                () =>
                {
                    var score = GetPKMinScore();
                    Logger.LogDebug($"[Success]ServerId[{serverId}] get PKMinScore[{score}]");
                    return score;
                }
            );
        }
        /// <summary>
        /// 获取PK榜单排名
        /// </summary>
        public static async Task<int> RemoteGetPKRank(int serverId, int userId)
        {
            if (RunServerId.Value < 0) return -1;
            if (serverId < 0) return -1;
            if (userId == 0) return -1;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId),
                () =>
                {
                    if (PKRankPool == null)
                    {
                        Logger.LogError("PKRankPool == null");
                        return -1;
                    }
                    var rank = PKRankPool.GetRank(userId);
                    Logger.LogDebug($"[Success]ServerId[{serverId}] get PKRank UserId[{userId}]Rank[{rank}]");
                    return rank;
                }
            );
        }
        /// <summary>
        /// 删除PK榜单
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteDeletePKRankItem(int serverId, int userId)
        {
            if (RunServerId.Value < 0) return -1;
            if (userId == 0) return -1;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId, userId),
                () =>
                {
                    if (PKRankPool == null)
                    {
                        Logger.LogError("PKRankPool == null");
                        return -1;
                    }
                    var rank = PKRankPool.Remove(userId);
                    Logger.LogDebug($"[Success]ServerId[{serverId}] delete PKRankItem UserId[{userId}]Rank[{rank}]");
                    return rank;
                }
            );
        }
        /// <summary>
        /// 加入PK榜单
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteAddPKRankItem(int serverId, TRankPKItem item)
        {
            if (RunServerId.Value < 0) return -1;
            if (item == null) return -1;
            if (item.UserId == 0) return -1;

            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId, item),
                () =>
                {
                    if (PKRankPool == null)
                    {
                        Logger.LogError("PKRankPool == null");
                        return -1;
                    }
                    //低于允许上榜的最低分
                    if (item.Score < ConfigConstants.PK_RANKING_MIN)
                    {
                        //从榜单池中移除
                        var rank = PKRankPool.Remove(item.UserId);
                        //删除数据
                        TRankPKItem.Cache.TryDelete(item.UserId.ToString());
                        Logger.LogDebug($"[Fail]ServerId[{serverId}] add PKRankItem UserId[{item.UserId}]Score[{item.Score}]Rank[{rank}] < PK_RANKING_MIN");
                    }
                    //允许上榜
                    else
                    {
                        //加入成功, 保存数据
                        var rank = PKRankPool.Add(item);
                        if (rank > 0)
                        {
                            TRankPKItem.Cache.AddOrUpdate(item);
                        }
                        Logger.LogDebug($"[Success]ServerId[{serverId}] add PKRankItem UserId[{item.UserId}]Score[{item.Score}]Rank[{rank}]");
                    }
                    return GetPKMinScore();
                }
            );
        }

        /// <summary>
        /// 获取COOP榜单已上榜的最小回合数
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteGetCOOPMinRound(int serverId)
        {
            if (RunServerId.Value < 0) return ConfigConstants.COOP_RANKING_MIN;
            if (serverId < 0) return ConfigConstants.COOP_RANKING_MIN;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId),
                () =>
                {
                    var round = GetCOOPMinRound();
                    Logger.LogDebug($"[Success]ServerId[{serverId}] get COOPMinRound[{round}]");
                    return round;
                }
            );
        }
        /// <summary>
        /// 获取COOP榜单排名
        /// </summary>
        public static async Task<int> RemoteGetCOOPRank(int serverId, string key)
        {
            if (RunServerId.Value < 0) return -1;
            if (serverId < 0) return -1;
            if (string.IsNullOrEmpty(key)) return -1;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId),
                () =>
                {
                    if (COOPRankPool == null)
                    {
                        Logger.LogError("COOPRankPool == null");
                        return -1;
                    }
                    var rank = COOPRankPool.GetRank(key);
                    Logger.LogDebug($"[Success]ServerId[{serverId}] get COOPRank Key[{key}]Rank[{rank}]");
                    return rank;
                }
            );
        }
        /// <summary>
        /// 删除COOP榜单
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteDeleteCOOPRankItem(int serverId, string key)
        {
            if (RunServerId.Value < 0) return -1;
            if (serverId < 0) return -1;
            if (string.IsNullOrEmpty(key)) return -1;
            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId, key),
                () =>
                {
                    if (COOPRankPool == null)
                    {
                        Logger.LogError("COOPRankPool == null");
                        return -1;
                    }
                    var rank = COOPRankPool.Remove(key);
                    Logger.LogDebug($"[Success]ServerId[{serverId}] delete COOPRankItem Key[{key}]Rank[{rank}]");
                    return rank;
                }
            );
        }
        /// <summary>
        /// 加入COOP榜单
        /// </summary>
        [Rpc]
        public static async Task<int> RemoteAddCOOPRankItem(int serverId, TRankCOOPItem item, int robotScore1, int robotScore2)
        {
            if (RunServerId.Value < 0) return -1;
            if (item == null) return -1;
            if ((item.UserId1) == 0 && (item.UserId2 == 0)) return -1;

            return await RpcProxy.RunAsync(typeof(RankCenterService), RunServerId.Value, RpcProxy.BuildArgs(serverId, item, robotScore1, robotScore2),
                () =>
                {
                    if (COOPRankPool == null)
                    {
                        Logger.LogError("COOPRankPool == null");
                        return -1;
                    }
                    //低于允许上榜的最低回合数
                    if (item.Round < ConfigConstants.COOP_RANKING_MIN)
                    {
                        var key = item.PrimaryKey;
                        //从榜单池中移除
                        var rank = COOPRankPool.Remove(key);
                        //删除数据
                        TRankCOOPItem.Cache.TryDelete(key);
                        Logger.LogDebug($"[Fail]ServerId[{serverId}] add COOPRankItem Key[{key}]Round[{item.Round}]Rank[{rank}] < COOP_RANKING_MIN");
                    }
                    //允许上榜
                    else
                    {
                        var rank = COOPRankPool.Add(item);
                        //加入成功, 保存数据
                        if (rank > 0)
                        {
                            TRankCOOPItem.Cache.AddOrUpdate(item);
                        }
                        Logger.LogDebug($"[Success]ServerId[{serverId}] add COOPRankItem Key[{item.PrimaryKey}]Round[{item.Round}]Rank[{rank}]");
                        //机器人自动上榜PVP
                        if ((item.UserId1 < 0) && (robotScore1 >= ConfigConstants.PK_RANKING_MIN) && (!PKRankPool.ContainsKey(item.UserId1)))
                        {
                            var pkItem = new TRankPKItem(-1, item.UserId1, item.Name1, robotScore1, item.Team1.HeroBaseId, item.Team1.TowerPool, item.Team1.FieldId, DateTime.UtcNow.ToSecondsSinceEpoch());
                            PKRankPool.Add(pkItem);
                        }
                        if ((item.UserId2 < 0) && (robotScore2 >= ConfigConstants.PK_RANKING_MIN) && (!PKRankPool.ContainsKey(item.UserId2)))
                        {
                            var pkItem = new TRankPKItem(-1, item.UserId2, item.Name2, robotScore2, item.Team2.HeroBaseId, item.Team2.TowerPool, item.Team2.FieldId, DateTime.UtcNow.ToSecondsSinceEpoch());
                            PKRankPool.Add(pkItem);
                        }
                    }
                    return GetCOOPMinRound();
                }
            );
        }
    }

    /// <summary>
    /// 榜单服务 - 逻辑服
    /// </summary>
    public class RankLogicService
    {
        private static readonly ILogger Logger = LoggerManager.Load<RankLogicService>();
        /// <summary>
        /// 榜单下次加载时间
        /// </summary>
        private static DateTime RankNextLoadDateTime = DateTime.MinValue;
        /// <summary>
        /// 榜单下次加载时间戳
        /// </summary>
        private static int RankNextLoadTime = 0;
        /// <summary>
        /// 榜单加载锁
        /// </summary>
        private static readonly object RankLoadLock = new object();
        /// <summary>
        /// PK榜单池
        /// </summary>
        private static RankPool<int, TRankPKItem> PKRankPool = null;
        /// <summary>
        /// COOP榜单池
        /// </summary>
        private static RankPool<string, TRankCOOPItem> COOPRankPool = null;
        /// <summary>
        /// 开始服务
        /// </summary>
        public static async Task Start()
        {
            //只在逻辑服运行
            if (!Host.Role.HasRole(ServerRole.Logic))
            {
                Logger.LogDebug("Skip");
                return;
            }

            Logger.LogDebug("Start");

            //初始化PK榜单
            PKRankPool = new RankPool<int, TRankPKItem>(RankCenterService.PKRankCapacity, false);
            Logger.LogDebug($"Create PKRankPool");
            //初始化COOP榜单
            COOPRankPool = new RankPool<string, TRankCOOPItem>(RankCenterService.COOPRankCapacity, false);
            Logger.LogDebug($"Create COOPRankPool");

            //统一等待45秒后, 每个逻辑服依次间隔2秒, 尝试重新加载所有榜单
            await Task.Delay((45 + (Host.ServerId * 2)) * 1000).ContinueWith(TryReloadAllRank);
        }
        /// <summary>
        /// PK榜单条目是否有效
        /// </summary>
        private static bool CheckPKItemAvailable(TRankPKItem item) => item != null && item.Score >= ConfigConstants.PK_RANKING_MIN;
        /// <summary>
        /// COOP榜单条目是否有效
        /// </summary>
        private static bool CheckCOOPItemAvailable(TRankCOOPItem item) => item != null && item.Round >= ConfigConstants.COOP_RANKING_MIN;
        /// <summary>
        /// 尝试重新加载所有榜单
        /// </summary>
        public static async Task TryReloadAllRank(object state)
        {
            if (PKRankPool == null)
            {
                Logger.LogError("PKRankPool== null");
                return;
            }
            if (COOPRankPool == null)
            {
                Logger.LogError("COOPRankPool == null");
                return;
            }
            lock (RankLoadLock)
            {
                //未到加载时间
                if (DateTime.UtcNow < RankNextLoadDateTime) return;
                //更新下次加载时间
                //内网 1分钟 | 外网 10分钟
                var addMinutes = ConfigService.DevelopmentEnv.Value ? 1 : 10;
                RankNextLoadDateTime = DateTime.UtcNow.AddMinutes(addMinutes);
                RankNextLoadTime = RankNextLoadDateTime.ToSecondsSinceEpoch();
                Logger.LogDebug($"RankNextLoadTime[{RankNextLoadDateTime}]");
            }
            var pack = await RankCenterService.RemoteLoadPack(Host.ServerId);
            if (pack == null)
            {
                Logger.LogError("Fail to load rank pack from rank center server");
                return;
            }
            PKRankPool.ClearAndAdd(pack.PKList, CheckPKItemAvailable);
            COOPRankPool.ClearAndAdd(pack.COOPList, CheckCOOPItemAvailable);
            Logger.LogDebug($"Load PKRankPool Count[{PKRankPool.Count}]");
            Logger.LogDebug($"Load COOPRankPool Count[{COOPRankPool.Count}]");
        }
        /// <summary>
        /// 榜单结算
        /// </summary>
        public static async Task Settle(int userId, TBattleSettle settle)
        {
            //无结算
            if (settle == null) return;

            switch ((BattleType)settle.BattleType)
            {
                //PK
                case BattleType.PK:
                    await SettlePK(userId);
                    break;
            }

            //尝试重新加载所有榜单
            await TryReloadAllRank(null);
        }
        /// <summary>
        /// PK榜单结算
        /// </summary>
        private static async Task SettlePK(int userId)
        {
            //顺序敏感
            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"User[{userId}]: TUserProfile.Cache.FindKey({userId}) is null");
                return;
            }
            var curScore = profile.CurScore;
            //允许上榜
            if (curScore >= (ConfigConstants.PK_RANKING_MIN - 200))
            {
                //创建榜单条目
                var user = TUser.Cache.FindKey(userId);
                if (user == null)
                {
                    Logger.LogError($"User[{userId}]: TUser.Cache.FindKey({userId}) is null");
                    return;
                }
                var err = CardService.GetBattleTeamData(userId, (int)BattleType.PK,
                    out THero hero, out List<int> towerPool, out int _1, out int fieldId);
                if (err != ErrorCode.Success) return;
                var nowTime = DateTime.UtcNow.ToSecondsSinceEpoch();
                var item = new TRankPKItem(user.ServerId, userId, user.GetName(), curScore, hero.BattleHeroResId, towerPool, fieldId, nowTime);
                //发送榜单中心服, 请求上榜
                var rank = await RankCenterService.RemoteAddPKRankItem(Host.ServerId, item);
                Logger.LogDebug($"User[{userId}]: RemoteAddPKRankItem[{userId}]Score[{curScore}]Rank[{rank}]");
            }
        }
        /// <summary>
        /// 加载榜单数据包
        /// </summary>
        public static ErrorCode LoadPack(int userId, int battleType, int offset, int count, int time, TRankPack output)
        {
            if (output == null)
            {
                Logger.LogError($"User[{userId}]: Need TRankPack output");
                return ErrorCode.FuncParameterIsNull;
            }
            if (PKRankPool == null)
            {
                Logger.LogError("PKRankPool== null");
                return ErrorCode.DataNotFound;
            }
            if (COOPRankPool == null)
            {
                Logger.LogError("COOPRankPool == null");
                return ErrorCode.DataNotFound;
            }
            if (time != RankNextLoadTime)
            {
                switch ((BattleType)battleType)
                {
                    case BattleType.PK:
                        output.PKList = PKRankPool.GetRange(offset, count);
                        break;
                    case BattleType.COOP:
                        output.COOPList = COOPRankPool.GetRange(offset, count);
                        break;
                }
                output.Time = RankNextLoadTime;
            }

            //尝试重新加载所有榜单
            _ = TryReloadAllRank(null);

            return ErrorCode.Success;
        }

        //public int EstimateRank(int myValue, int minValue, int count, int total)
        //{
        //    //_topK 排行榜容量池
        //    //if (!_topK.Full) return -1;

        //    //var count = _topK.Count;
        //    //minValue=上榜最低分
        //    //count=排行榜内有多少人
        //    //total=人数总量
        //    float factorA = minValue / (1.0f / count - 1.0f / total);
        //    float factorB = factorA / total;
        //    float rank = factorA / (myValue + factorB);

        //    Logger.LogDebug($"FactorA:{factorA}, FactorB:{factorB}, Rank:{rank}, DefaultCount:{count}, Total:{total}");

        //    return (int)Math.Ceiling(rank) + 1;
        //}
    }
}