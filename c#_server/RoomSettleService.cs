using Feelingtouch.Core.Cache;
using Feelingtouch.Core.Config;
using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Feelingtouch.Core.Util.Thread;
using Game.Config;
using Game.Model;
using Game.Model.Config;
using Game.Model.Log;
using Game.Utils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Game.Service
{
    /// <summary>
    /// 房间结算服务
    /// </summary>
    public class RoomSettleService
    {
        private static ILogger Logger = LoggerManager.Load<RoomSettleService>();

        /// <summary>
        /// 房间结算类型
        /// </summary>
        public enum RoomSettleType
        {
            None = 0,            //无
            ZeroReconnect = 11,  //收到0个玩家上报, 重连超时, 真人玩家全部掉线超过10秒
            ZeroOp = 12,         //收到0个玩家上报, 指令更新超时, 未收到指令超过300秒

            OneAI = 21,          //收到1个玩家上报, 未上报者是AI
            OneDisconnect = 22,  //收到1个玩家上报, 未上报者掉线
            OneOverTime = 23,    //收到1个玩家上报, 未上报者超过2秒未上报

            TwoSame = 31,        //收到2个玩家上报, 双方结果相同
            TwoDiff = 32,        //收到2个玩家上报, 双方结果不同
        }

        /// <summary>
        /// 战斗结算类型
        /// </summary>
        public enum BattleSettleType
        {
            None = 0,            //无
            PlayerRoom = 11,    //玩家房间
            BattleResult = 21,  //有战斗结果
            ReportResult = 22,  //无战斗结果, 有玩家上报结果
            TimerResult = 23,   //无战斗结果, 无玩家上报结果, 使用定时上报结果
            SimulateOK = 31,    //模拟战斗成功
            SimulateFail = 32,  //模拟战斗失败
        }

        /// <summary>
        /// 等待玩家重连的最大时间, 10秒
        /// </summary>
        private const int WaitReconnectMaxTime = 10 * 1000;
        /// <summary>
        /// 等待战斗指令超时的最大时间, 300秒
        /// </summary>
        private const int WaitOpMaxTime = 300 * 1000;
        /// <summary>
        /// 等待未上报者上报的最大时间, 2秒
        /// </summary>
        private const int WaitReportMaxTime = 2 * 1000;
        /// <summary>
        /// 等待房间结算的最大时间, 200秒
        /// </summary>
        private const int WaitRoomSettleMaxTime = 200 * 1000;
        /// <summary>
        /// 每回合最大帧数, 每回合最多10秒
        /// </summary>
        private static readonly int MaxFramePerRound = 10000 / ConfigConstants.BATTLE_FRAME_TIME;
        /// <summary>
        /// Coop模式, 房间结算较大回合, 50回合
        /// </summary>
        private const int RoomCoopBigRound = 50;

        /// <summary>
        /// COOP榜单允许发送上榜请求的最小回合数
        /// </summary>
        private static int COOPRankMinRound = ConfigConstants.COOP_RANKING_MIN;
        /// <summary>
        /// COOP榜单下次更新时间
        /// </summary>
        private static DateTime COOPRankNextUpdateTime = DateTime.MinValue;
        /// <summary>
        /// COOP榜单更新锁
        /// </summary>
        private static object COOPRankUpdateLock = new object();

        /// <summary>
        /// 匹配服务器Id
        /// </summary>
        private static Lazy<int> MatchServerId = new Lazy<int>(
            () =>
            {
                var config = ConfigService.MatchConfig.Value?.GetMatchServerConfigByRoomServerId(Host.ServerId, out int areaId);
                if (config == null)
                {
                    Logger.LogError($"Cannot find matchServerId by roomServerId[{Host.ServerId}");
                    return 0;
                }
                return config.ServerId;
            },
            LazyThreadSafetyMode.ExecutionAndPublication
        );

        /// <summary>
        /// 计时器
        /// </summary>
        private static ITimer Timer = null;

        /// <summary>
        /// 开始服务
        /// </summary>
        public static void TryStart()
        {
            //启动计时器
            Timer = (new AsyncTimer("RoomSettleService", 0, 10 * 60 * 1000))
                .InitializeCallback(
                    (object state, long delta, long time) => ConfigManager.ReloadConfig<BattleValidateConfig>()
                );
            Timer.Start();

            //60秒以后, 尝试重新加载COOP榜单已上榜的最小回合数
            _ = Task.Delay(60 * 1000).ContinueWith(TryReloadCOOPMinRound);
        }

        /// <summary>
        /// 尝试重新加载COOP榜单已上榜的最小回合数
        /// </summary>
        private static async Task TryReloadCOOPMinRound(object state)
        {
            lock (COOPRankUpdateLock)
            {
                //未到加载时间
                if (DateTime.UtcNow < COOPRankNextUpdateTime) return;
                //随机5-15分钟后再次加载
                COOPRankNextUpdateTime = DateTime.UtcNow.AddMinutes(RandomExtensions.Instance.Next(5, 15));
            }
            COOPRankMinRound = await RankCenterService.RemoteGetCOOPMinRound(Host.ServerId);
        }

        /// <summary>
        /// 房间结算
        /// </summary>
        public static bool SettleRoom(Room room, long time)
        {
            if (room == null || room.State != RoomState.Battle) return false;

            //玩家上报数量
            switch (room.Users.Count(user => user.IsReported))
            {
                //收到0个玩家上报
                case 0:
                    //真人玩家全部掉线超过10秒
                    if (room.Users.All(u => (!u.IsRobot) && u.IsDisconnected && (time >= (u.DisconnectTime + WaitReconnectMaxTime))))
                    {
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = null;
                        _ = SettleBattle(room, RoomSettleType.ZeroReconnect);
                        return true;
                    }
                    //超过300秒未收到更新指令
                    else if (time >= (room.UpdateTime + WaitOpMaxTime))
                    {
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = null;
                        _ = SettleBattle(room, RoomSettleType.ZeroOp);
                        return true;
                    }
                    return false;
                //收到1个玩家上报
                case 1:
                    var repoter = room.Users.FirstOrDefault(u => u.IsReported);
                    var unreporter = room.Users.FirstOrDefault(u => !u.IsReported);
                    //未上报者是AI, 验证等级1
                    if (unreporter.IsRobot)
                    {
                        //房间进入结算状态
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = repoter.ReportResult;
                        _ = SettleBattle(room, RoomSettleType.OneAI, 1);
                        return true;
                    }
                    //未上报者是玩家, 掉线, 验证等级2
                    else if (unreporter.IsDisconnected)
                    {
                        //房间进入结算状态
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = repoter.ReportResult;
                        _ = SettleBattle(room, RoomSettleType.OneDisconnect, 2);
                        return true;
                    }
                    //未上报者是玩家, 超过2秒未上报, 验证等级3
                    else if (time >= (repoter.ReportTime + WaitReportMaxTime))
                    {
                        //房间进入结算状态
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = repoter.ReportResult;
                        _ = SettleBattle(room, RoomSettleType.OneOverTime, 3);
                        return true;
                    }
                    return false;
                //收到2个玩家上报
                case 2:
                    //结果相同
                    if (room.Users[0].ReportResult.IsSameResult(room.Users[1].ReportResult))
                    {
                        //房间进入结算状态
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = room.Users[0].ReportResult;
                        _ = SettleBattle(room, RoomSettleType.TwoSame);
                    }
                    //结果不同, 验证等级4, 记录结果日志
                    else
                    {
                        //房间进入结算状态
                        room.State = RoomState.Settle;
                        room.Record.BattleResult = null;
                        _ = SettleBattle(room, RoomSettleType.TwoDiff, 4, true);
                    }
                    return true;
            }
            return false;
        }

        /// <summary>
        /// 战斗结算
        /// </summary>
        private static async Task SettleBattle(Room room, RoomSettleType type, int lv = 0, bool log = false)
        {
            if (room == null || room.State != RoomState.Settle) return;
            switch ((BattleType)room.Record.BattleType)
            {
                case BattleType.PK:
                case BattleType.PKRANDOM:
                    await SettlePK(room, type, lv, log);
                    break;
                case BattleType.COOP:
                    SettleCOOP(room, type, lv, log);
                    break;
            }
        }

        /// <summary>
        /// PK结算
        /// </summary>
        private static async Task SettlePK(Room room, RoomSettleType type, int lv = 0, bool log = false)
        {
            //---- 创建房间 ----
            //玩家创建房间, 不验证
            if (room.IsManual)
            {
                SettleResult(room, type, BattleSettleType.PlayerRoom, 0, log);
                return;
            }
            //---- 随机匹配 ----
            //随机匹配对手, 有战斗结果
            if (room.Record.BattleResult != null)
            {
                SettleResult(room, type, BattleSettleType.BattleResult, lv, log);
                return;
            }
            //随机匹配对手, 没有战斗结果, 模拟战斗
            room.Record.IsSimulating = true;
            room.Record.BattleResult = await BattleService.SimulateBattle(room.Record);
            //模拟成功, 不验证, 立即检查上报结果
            if (room.Record.BattleResult != null)
            {
                SettleResult(room, type, BattleSettleType.SimulateOK, 0, log);
            }
            //模拟失败, 不验证
            else
            {
                SettleResult(room, type, BattleSettleType.SimulateFail, 0, log);
            }
        }

        /// <summary>
        /// COOP结算
        /// </summary>
        private static void SettleCOOP(Room room, RoomSettleType type, int lv = 0, bool log = false)
        {
            var coopLv = lv;
            var coopLog = log;
            var battleSettleType = BattleSettleType.None;
            var round = 1;
            //有战斗结果
            if (room.Record.BattleResult != null)
            {
                battleSettleType = BattleSettleType.BattleResult;
                round = room.Record.BattleResult.RoundNum;
            }
            //无战斗结果, 所有玩家已上报结果
            else if (room.Users.All(u => u.IsReported))
            {
                battleSettleType = BattleSettleType.ReportResult;
                room.Record.BattleResult = null;
                round = room.Users.Max(u => u.ReportResult.RoundNum);
            }
            //无战斗结果, 有玩家未上报结果, 使用定时上报结果
            else
            {
                battleSettleType = BattleSettleType.TimerResult;
                room.Record.BattleResult = room.CoopReportResult;
                round = room.CoopReportResult.RoundNum;
            }

            //检查战斗结果的战斗回合
            var maxRound = (room.BattleFrame / MaxFramePerRound) + 1;
            var checkMaxRound = false;
            var checkBigRound = false;
            if (room.Record.BattleResult != null)
            {
                //战斗结果的战斗回合大于最大回合
                if (room.Record.BattleResult.RoundNum > maxRound)
                {
                    checkMaxRound = true;
                    //修正结算回合=最大回合, 记录结果日志
                    room.Record.BattleResult.SettleRound = maxRound;
                    coopLog = true;
                }
                //战斗结果的战斗回合大于50回合
                else if (room.Record.BattleResult.RoundNum > RoomCoopBigRound)
                {
                    checkBigRound = true;
                }
            }
            //检查玩家上报的战斗结果
            foreach (var u in room.Users)
            {
                if (u.IsReported)
                {
                    //玩家上报的战斗结果的战斗回合大于最大回合
                    if (u.ReportResult.RoundNum > maxRound)
                    {
                        checkMaxRound = true;
                        //修正结算回合=最大回合, 记录结果日志
                        u.ReportResult.SettleRound = maxRound;
                        coopLog = true;

                        Logger.LogError($"User[{u.UserId}]: ReportResult.RoundNum[{u.ReportResult.RoundNum}] > maxRound[{maxRound}]");
                    }
                    //玩家上报的战斗结果的战斗回合大于50回合
                    else if (u.ReportResult.RoundNum > RoomCoopBigRound)
                    {
                        checkBigRound = true;
                    }
                }
            }

            //战斗回合大于最大回合, 验证等级4
            if (checkMaxRound && (coopLv < 4))
            {
                coopLv = 4;
            }
            //战斗回合超过50, 验证等级2
            if (checkBigRound && (coopLv < 2))
            {
                coopLv = 2;
            }
            //回合数大于等于COOP榜单已上榜的最小回合数时, 强制验证, 验证成功后加入榜单
            SettleResult(room, type, battleSettleType, coopLv, coopLog, round >= COOPRankMinRound);
        }

        /// <summary>
        /// 结果结算
        /// </summary>
        private static void SettleResult(Room room, RoomSettleType roomSettleType, BattleSettleType battleResultType, int lv = 0, bool log = false, bool forceValidate = false)
        {
            if (room == null || room.State != RoomState.Settle) return;

            try
            {
                //顺序敏感
                //房间进入结算状态
                room.Record.Reason = $"{roomSettleType}|{battleResultType}";
                //保存战斗结果
                TBattleRecord.Cache.AddOrUpdate(room.Record);
                //记录战斗日志
                var robotUserId1 = room.Users != null && room.Users.Count > 0 ? room.Users[0].RobotUserId : 0;
                var robotUserId2 = room.Users != null && room.Users.Count > 1 ? room.Users[1].RobotUserId : 0;
                CachePool.GetContainer<BattleLog>().AddOrUpdate(new BattleLog(room.Record, robotUserId1, robotUserId2, room.BattleStartTime));
                //通知匹配服战斗结果
                _ = MatchService.R2M_NotifySettleResult(MatchServerId.Value, new RoomSettleData(room, false));
                //记录战斗结果日志
                if (log)
                {
                    CachePool.GetContainer<BattleResultLog>().AddOrUpdate(new BattleResultLog(room));
                }
                //通知验证服验证结果
                if (forceValidate || HitValidate(lv))
                {
                    _ = BattleValidateService.R2V_NotifyValidate(MatchServerId.Value, new BattleValidateData(room, lv, COOPRankMinRound));
                }
            }
            catch (Exception e)
            {
                Logger.LogError($"Exception SettleResult [{e.Message}] [{e.StackTrace}]");
            }
            finally
            {
                //尝试重新加载COOP榜单已上榜的最小回合数
                _ = TryReloadCOOPMinRound(null);
                //关闭房间
                RoomService.INSTANCE.CloseRoom(room);
            }
        }

        /// <summary>
        /// 战斗验证触发判定
        /// </summary>
        private static bool HitValidate(int lv)
        {
            if (lv <= 0)
            {
                return false;
            }
            var config = ConfigManager.LoadConfig<BattleValidateConfig>();
            if (config == null)
            {
                return true;
            }
            //百分比
            var percent = config.GetPercent(lv);
            if (percent <= 0)
            {
                return false;
            }
            else if (percent == 100)
            {
                return true;
            }
            else
            {
                return percent >= RandomExtensions.Instance.Next(percent, 101);
            }
        }
    }
}