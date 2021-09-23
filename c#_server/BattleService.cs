using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.ScriptEngine.Lua;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Game.Model;
using Game.Model.Config;
using Game.Pattern;
using Game.Utils;
using Microsoft.EntityFrameworkCore.Internal;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Game.Service
{
    interface IBattleSimulator
    {
        int BattleVersion { get; }
        TBattleResult Simulate(TBattleRecord record);
    }

    class BattleSimulator : IBattleSimulator
    {
        long _battleTimes = 0;
        LuaSvr _luaSvr;
        LuaTable _battleEntry;
        int _battleVersion = 0;
        int _reInitCount = 1000;

        public int BattleVersion => _battleVersion;
        public readonly AsyncLock Lock = new AsyncLock();

        public BattleSimulator(int reInitCount = 1000)
        {
            LuaState.hasfileDelegate = HasFile;
            LuaState.loaderDelegate = FileLoader;

            _reInitCount = reInitCount;
            InitState();
        }

        public void InitState()
        {
            try
            {
                //释放之前的luastate
                if (_luaSvr != null)
                {
                    _luaSvr.luaState.Dispose();
                }

                _luaSvr = new LuaSvr();
                _luaSvr.init((i) => { }, () =>
                {
                    Logger.LogInformation($"SLua server init done. L:{_luaSvr.luaState.L.ToInt64()}");
                }, LuaSvrFlag.LSF_3RDDLL);

                _luaSvr.start("Lua/LuaEnv/class.lua");
                _luaSvr.start("Lua/LuaEnv/xclass.lua");
                _luaSvr.start("Lua/LuaEnv/plugin.lua");
                _luaSvr.start("Lua/model/main.lua");
                _luaSvr.start("Lua/gameutils/main.lua");
                _luaSvr.start("Lua/gameres/main.lua");
                _luaSvr.start("Lua/gamebattle/main.lua");

                _battleEntry = _luaSvr.luaState.doFile("Lua/BattleEntry.lua") as LuaTable;

                //获取lua版本
                if (!int.TryParse(_battleEntry.invoke("version").ToString(), out _battleVersion))
                {
                    _battleVersion = 0;
                }

                if (_battleEntry == null)
                {
                    Logger.LogError("Init lua battle entry failed.");
                    throw new Exception("Init lua battle entry failed.");
                }
            }
            catch (Exception e)
            {
                Logger.LogError(e, "Init lua battle simulator failed.");
                throw e;
            }
        }

        public TBattleResult Simulate(TBattleRecord record)
        {
            LuaTable table;
            try
            {
                var times = Interlocked.Increment(ref _battleTimes);
                if (times >= _reInitCount && times % _reInitCount == 0)
                {
                    InitState();
                    Logger.LogDebug("Reinit Lua State");
                }

                Stopwatch watch = new Stopwatch();
                watch.Start();

                //Logger.LogWarning("Simulate Battle [" + record.ToJson() + "]");
                table = _battleEntry.invoke("entry", record.ToLua(), false) as LuaTable;

                var result = new TBattleResult()
                {
                    WinPlayerId = table["winPlayerId"].ToInt(),
                    FrameCount = table["frameCount"].ToInt(),
                    RoundNum = table["roundNum"].ToInt(),
                };

                watch.Stop();
                Logger.LogDebug($"Battle Simulate BattleId[{record.BattleId}] FrameCount[{record.FrameCount}] Result[{result.ToJson()}] Finish. Time cost [{watch.ElapsedMilliseconds}]ms");

                return result;
            }
            catch (Exception e)
            {
                Logger.LogError(e, "Simulate lua battle failed.");

                InitState();

                _ = BattleService.ReportBattleException(Host.ServerId, record.PlayerList[0].PlayerId, BattleVersion, record.ToLua());
            }

            return null;
        }

        static string FixFileName(string filename)
        {
            if (filename.StartsWith("file://") || filename.StartsWith("plug://"))
            {
                filename = filename.Substring(7);
                filename = filename.Replace('.', '/');
                filename = string.Format("Lua/{0}{1}", filename, filename.EndsWith(".lua") || filename.EndsWith(".txt") ? "" : ".lua");
            }

            return filename;
        }

        static byte[] FileLoader(string filename)
        {
            filename = FixFileName(filename);

            if (File.Exists(filename))
            {
                return File.ReadAllBytes(filename);
            }
            else
            {
                return null;
            }
        }

        static bool HasFile(string filename)
        {
            filename = FixFileName(filename);
            return File.Exists(filename);
        }
    }

    class AsyncBattleConsumer : AbstractConsumer<TBattleRecord, TBattleResult>
    {
        IBattleSimulator _simulator;

        public AsyncBattleConsumer(IBattleSimulator simulator)
        {
            _simulator = simulator;
        }

        protected override TBattleResult DoWork(TBattleRecord input)
        {
            var watch = new Stopwatch();
            watch.Start();
            var result = _simulator.Simulate(input);
            watch.Stop();

            var frameCount = result == null ? 0 : result.FrameCount;
            Logger.LogWarning($"Simulate Battle [{input.BattleId}] Frame [{frameCount}] Cost Time [{watch.ElapsedMilliseconds} ms]");
            return result;
        }
    }

    public class BattleService
    {
        private static ILogger Logger = LoggerManager.Load<BattleService>();

        private static AsyncProducer<TBattleRecord, TBattleResult> ASYNC_PRODUCER;

        public static int BATTLE_VERSION { get; private set; } = 0;

        public static void Start(int consumerCount = 2)
        {
            if (!(Host.Role.HasRole(ServerRole.Room) || (Host.Role.HasRole(ServerRole.Match))))
            {
                return;
            }

            var consumers = new List<AsyncBattleConsumer>();
            for (int i = 0; i < consumerCount; i++)
            {
                var simulator = new BattleSimulator(100);
                BATTLE_VERSION = simulator.BattleVersion;

                consumers.Add(new AsyncBattleConsumer(simulator));
            }

            ASYNC_PRODUCER = new AsyncProducer<TBattleRecord, TBattleResult>(consumers);
        }

        public static int GenerateSeed()
        {
            return RandomExtensions.Instance.Next(1048576);
        }

        public static async Task<TBattleResult> SimulateBattle(TBattleRecord record) => await AsyncSimulateBattle(record);

        private static async Task<TBattleResult> AsyncSimulateBattle(TBattleRecord record)
        {
            return await ASYNC_PRODUCER.Enqueue(record);
        }

        [Rpc]
        public static async Task ReportBattleException(int serverId, int attackerId, int version, string battleEnterDataOfLua)
        {
            await RpcProxy.RunAsync(typeof(BattleService), 10000, RpcProxy.BuildArgs(serverId, attackerId, version, battleEnterDataOfLua), () =>
            {
            });
        }

        #region 战斗结算
        /// <summary>
        /// 战斗结算
        /// </summary>
        public static ErrorCode Settle(int userId, string battleId, TBattleResult result, bool isManual, out TBattleSettle settle, int playerId)
        {
            settle = null;
            if (result == null)
            {
                return ErrorCode.Success;
            }
            settle = new TBattleSettle()
            {
                BattleType = result.BattleType,
                IsMyWin = userId == (result == null ? 0 : result.WinPlayerId),
                BonusOutput = null,
                Round = result == null ? 1 : result.SettleRound,
                Success = result != null,
                BattleId = battleId,
                IsManual = isManual,
            };
            //结算失败, 没有战斗结果
            if (!settle.Success) return ErrorCode.Success;
            //根据战斗类型结算
            var err = ErrorCode.Success;
            switch ((BattleType)result.BattleType)
            {
                //挑战
                case BattleType.PK:
                    err = SettleUserPK(userId, settle);
                    if (err != ErrorCode.Success) return err;
                    break;
                //合作
                case BattleType.COOP:
                    err = SettleUserCoop(userId, settle);
                    if (err != ErrorCode.Success) return err;
                    break;
                //随机竞技场
                case BattleType.PKRANDOM:
                    err = SettleUserPKRandom(userId, settle, playerId);
                    if (err != ErrorCode.Success) return err;
                    break;
                default:
                    Logger.LogError($"User[{userId}]: Unknown battleType[{result.BattleType}] to settle");
                    return ErrorCode.InvalidParameter;
            }
            return ErrorCode.Success;
        }
        /// <summary>
        /// 玩家战斗结算 - 挑战模式
        /// </summary>
        private static ErrorCode SettleUserPK(int userId, TBattleSettle settle)
        {
            if (settle == null)
            {
                Logger.LogError($"User[{userId}]: SettleUserPk Para TBattleSettle settle is null");
                return ErrorCode.FuncParameterIsNull;
            }
            //玩家创建房间的战斗不结算
            if (settle.IsManual) return ErrorCode.Success;

            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"User[{userId}]: TUserProfile.Cache.FindKey({userId}) == null");
                return ErrorCode.DataNotFound;
            }
            //顺序敏感
            //触发任务 - 完成任意战斗
            TaskCenterService.Update(userId, ConditionType.BATTLE, TaskOpType.Add, 1);
            //胜利
            if (settle.IsMyWin)
            {
                //触发任务 - 完成PVP战斗胜利
                TaskCenterService.Update(userId, ConditionType.PKWIN, TaskOpType.Add, 1);
                //战斗前广告加成
                bool beforeAD = UserService.CheckBattleExtraBonus(userId, settle.BattleType, true);
                if (beforeAD)
                {
                    settle.ExtraBonusFlag = 1;
                }
                //更新挑战档案
                ProfileService.UpdatePKBattle(profile, settle.IsMyWin, beforeAD, out int addScore, out int addGold);
                //创建结算奖励
                var bonusList = new TBonusList();
                //金币奖励
                var err = bonusList.AddItem(userId, ConfigConstants.COIN_ITEMID, addGold);
                if (err != ErrorCode.Success) return err;
                //添加奖励
                err = ItemService.AddBonus(userId, bonusList, AssetReason.BattleSettlePK);
                if (err != ErrorCode.Success) return err;
                //返回奖励
                settle.BonusOutput = new TBonusOutput() { BonusList = bonusList, };

                //创建预存战斗后胜利看广告的奖励
                var afterADBonusList = new TBonusList(userId, bonusList);
                err = afterADBonusList.AddItem(userId, ConfigConstants.SCORE_ITEMID, addScore);
                if (err != ErrorCode.Success) return err;
                //返回战斗后胜利看广告的奖励倍数
                bonusList.ExtraFactor = ExtraBonusService.TrySaveExtraBonus(userId, ExtraBonusType.PKWINBONUS, afterADBonusList);
            }
            //失败
            else
            {
                //更新挑战档案
                ProfileService.UpdatePKBattle(profile, settle.IsMyWin, false, out int addScore, out int addGold);
                settle.ExtraBonusFlag = ExtraBonusService.TrySaveExtraBonus(userId, ExtraBonusType.PKLOSECHEST, null) > 0 ? 2 : 0;
            }
            TUserProfile.Cache.AddOrUpdate(profile);
            return ErrorCode.Success;
        }
        /// <summary>
        /// 玩家战斗结算 - 合作模式
        /// </summary>
        private static ErrorCode SettleUserCoop(int userId, TBattleSettle settle)
        {
            if (settle == null)
            {
                Logger.LogError($"User[{userId}]: SettleUserCoop Para TBattleSettle settle is null");
                return ErrorCode.FuncParameterIsNull;
            }
            var battleRes = BattleResConfig.Cache.FindKey((int)BattleType.COOP);
            if (battleRes == null)
            {
                Logger.LogError($"User[{userId}]: BattleResConfig.Cache.FindKey({(int)BattleType.COOP}) == null");
                return ErrorCode.DataNotFound;
            }
            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"User[{userId}]: TUserProfile.Cache.FindKey({userId}) == null");
                return ErrorCode.DataNotFound;
            }
            //顺序敏感
            //触发任务 - 完成任意战斗
            TaskCenterService.Update(userId, ConditionType.BATTLE, TaskOpType.Add, 1);
            //触发任务 - 完成PVE战斗
            TaskCenterService.Update(userId, ConditionType.PVE, TaskOpType.Add, 1);
            //触发任务 - 完成PVE回合数
            TaskCenterService.Update(userId, ConditionType.STAGE, TaskOpType.Equal, settle.Round);
            //更新合作档案
            ProfileService.UpdateCoopBattle(profile, settle.Round);
            TUserProfile.Cache.AddOrUpdate(profile);
            //回合数大于0时结算奖励
            if (settle.Round > 0)
            {
                //触发任务 - 累计PVE回合数
                TaskCenterService.Update(userId, ConditionType.STAGEADD, TaskOpType.Add, settle.Round);
                //战斗前广告加成
                var beforeAD = UserService.CheckBattleExtraBonus(userId, settle.BattleType, true);
                if (beforeAD)
                {
                    settle.ExtraBonusFlag = 1;
                }
                //合作奖励列表
                var coopBonusList = new TBonusList();
                //宝箱碎片=基础奖励 + 战前广告加成
                var err = GetCoopRewardCount(userId, settle.Round, battleRes.rewardChestCountList, beforeAD, out int shardCount, out int adsCount, out int extraCount);
                if (err != ErrorCode.Success) return err;
                // 基础
                err = coopBonusList.AddItem(userId, ConfigConstants.COOP_CHESTSHARD_ITEMID, shardCount);
                if (err != ErrorCode.Success) return err;
                // 广告
                err = coopBonusList.AddItem(userId, ConfigConstants.COOP_CHESTSHARD_ITEMID, adsCount);
                if (err != ErrorCode.Success) return err;
                // 活动or状态
                err = coopBonusList.AddItem(userId, ConfigConstants.COOP_CHESTSHARD_ITEMID, extraCount);
                if (err != ErrorCode.Success) return err;
                //添加奖励
                err = ItemService.AddBonus(userId, coopBonusList, AssetReason.BattleSettleCoop);
                if (err != ErrorCode.Success) return err;
                //返回奖励
                settle.BonusOutput = new TBonusOutput() { BonusList = coopBonusList, };
            }
            return ErrorCode.Success;
        }
        /// <summary>
        /// 获取合作模式的奖励数量
        /// </summary>
        private static ErrorCode GetCoopRewardCount(int userId, int round, List<int> rewardCounts, bool beforeAD, out int count, out int adsCount, out int extraCount)
        {
            count = 0;
            adsCount = 0;
            extraCount = 0;
            if (rewardCounts == null)
            {
                Logger.LogError($"User[{userId}]: rewardCounts == null");
                return ErrorCode.FuncParameterIsNull;
            }
            else if (rewardCounts.Count < 2)
            {
                Logger.LogError($"User[{userId}]: rewardCounts.Count[{rewardCounts.Count}] < 2");
                return ErrorCode.InvalidParameter;
            }
            //回合数无效
            else if (round <= 0)
            {
                Logger.LogError($"User[{userId}]: round[{round}] <= 0");
                return ErrorCode.Success;
            }

            //查询获得
            var baseCount = 0;
            if (round <= rewardCounts.Count)
            {
                baseCount = rewardCounts[round - 1];
            }
            //计算获得 = 最终关奖励 + (最终关奖励 - 最终关前一关奖励)
            else
            {
                baseCount = rewardCounts[rewardCounts.Count - 1];
                baseCount += (rewardCounts[rewardCounts.Count - 1] - rewardCounts[rewardCounts.Count - 2]);
            }
            count = baseCount;
            //活动加成BUFF - 增加基础收益
            var activityRes = ConfigService.ActivityResOfCOOPBUFF.Value;
            if (activityRes != null)
            {
                var nowTime = DateTime.UtcNow.ToSecondsSinceEpoch();
                if ((nowTime >= activityRes.startTime) && (nowTime <= activityRes.endTime))
                {
                    extraCount += (int)Math.Ceiling(baseCount * (activityRes.valueList[0] * Constants.PercentScale));
                }
                Logger.LogDebug($"ActivityResOfCOOPBUFF User[{userId}] Value[{activityRes.valueList[0]}] Count[{count}]");
            }
            //状态加成
            if (UserService.GetUserState(userId, UserStateType.COOPPROFITS, out int stateValue))
            {
                extraCount += (int)Math.Ceiling(baseCount * (stateValue * Constants.PercentScale));
            }
            Logger.LogDebug($"Coop Profits User[{userId}] State[{stateValue}] Count[{count}] Base[{baseCount}]");
            //战斗前广告加成
            if (beforeAD)
            {
                adsCount = (int)Math.Ceiling(baseCount * (ConfigConstants.ADS_COOP_BONUS * Constants.PercentScale));
            }
            return ErrorCode.Success;
        }
        /// <summary>
        /// 玩家战斗结算 - 随机竞技场
        /// </summary>
        private static ErrorCode SettleUserPKRandom(int userId, TBattleSettle settle, int playerId)
        {
            if (settle == null)
            {
                Logger.LogError($"User[{userId}]: SettleUserPk Para TBattleSettle settle is null");
                return ErrorCode.FuncParameterIsNull;
            }
            return ArenaRandomLogicService.Settle(userId, settle.IsMyWin, playerId);
        }
        #endregion
    }
}