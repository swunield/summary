using Feelingtouch.Core;
using Feelingtouch.Core.Collections;
using Feelingtouch.Core.Config;
using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Feelingtouch.Core.Util.Thread;
using Game.Config;
using Game.Model;
using Game.Model.Config;
using Game.Model.Stat;
using Game.Utils;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Game.Service
{
    public class MatchService : ThreadContext
    {
        private static MatchService _instance = null;
        public static MatchService INSTANCE
        {
            get
            {
                if (_instance == null)
                {
                    _instance = new MatchService();
                }
                return _instance;
            }
        }

        private ITimer _timer = null;
        public ITimer timer
        {
            get
            {
                if (_timer == null)
                {
                    _timer = new FixedTimer(OnTimerCallback, "MatchService", 0, 50, true);
                }
                return _timer;
            }
        }

        private static void OnTimerCallback(object state, long delta, long time)
        {
            MatchService.INSTANCE.Update(delta, time);
        }

        // 匹配刷新间隔
        private static readonly long MATCH_UPDATE_INTERVAL = 1000;

        // 匹配间隔计时
        private long _matchUpdateTime = 0;

        // 服务器配置
        private MatchServerConfig _matchServerConfig = null;

        // 空闲房间列表
        private ConcurrentQueue<int> _idleRoomQ = new ConcurrentQueue<int>();

        // 占用房间
        private ConcurrentDictionary<int, int> _busyRoomMap = new ConcurrentDictionary<int, int>();

        // 匹配队列，线程安全
        private Dictionary<int, SortedLinkList<MatchUser>> _matchMap = new Dictionary<int, SortedLinkList<MatchUser>>();

        // 玩家匹配节点
        private Dictionary<int, LinkedListNode<MatchUser>> _matchNodeMap = new Dictionary<int, LinkedListNode<MatchUser>>();

        // 战斗中玩家
        private ConcurrentDictionary<int, MatchUser> _battlingUserMap = new ConcurrentDictionary<int, MatchUser>();

        // 开黑编码最长有效时间
        private static readonly int MAX_MATCH_CODE_TIME = 10 * 60 * 1000;

        // 开黑编码空闲队列
        private ConcurrentQueue<int> _idleMatchCodeQ = new ConcurrentQueue<int>();

        // 开黑等待玩家
        private ConcurrentDictionary<int, MatchUser> _busyMatchCodeMap = new ConcurrentDictionary<int, MatchUser>();

        // 实时数据统计
        private RTMatch _rtMatch = new RTMatch();
        private static int _playerSettleingCount = 0;

        public static void TryStart()
        {
            if (!Host.Role.HasRole(ServerRole.Match))
            {
                return;
            }

            MatchService.INSTANCE.Start();
        }

        private void Start()
        {
            // 启动计时器
            timer.Start();

            // 初始化房间
            if (!InitRoom())
            {
                return;
            }

            //开始机器人服务
            _ = RobotService.TryStart();

            // 启动线程
            this.StartThreadContext();

            // 实时统计
            StartStat();
        }

        public static void TryStop()
        {

        }

        private void Update(long delta, long time)
        {
            // 实时统计
            var commit = _rtMatch.TryCommitStart(time);

            // 线程更新
            this.ThreadContextUpdate(false);

            // 每秒匹配一次
            _matchUpdateTime += delta;
            if (_matchUpdateTime >= MATCH_UPDATE_INTERVAL)
            {
                _matchUpdateTime -= MATCH_UPDATE_INTERVAL;

                // 执行匹配
                ExecuteMatch(time);

                // 校验手动匹配是否超时
                CheckManualMatch(time);
            }

            // 实时上报
            _rtMatch.TryCommitEnd(time, commit);
        }

        private bool InitRoom()
        {
            var config = ConfigService.MatchConfig.Value;
            _matchServerConfig = config.GetMatchServerConfigByMatchServerId(Host.ServerId);
            if (_matchServerConfig == null)
            {
                Logger.LogError($"[Match][Room Init][Failed][Can not find MatchServerConfig [{Host.ServerId}]]");
                return false;
            }

            var roomServerCount = _matchServerConfig.RoomServers.Length;
            for (int i = 0; i < _matchServerConfig.RoomCount; i++)
            {
                // 加入空闲队列
                var roomId = i + 1;
                _idleRoomQ.Enqueue(roomId);
            }

            // 初始化房间创建编码
            InitMatchCode();

            return true;
        }

        public bool HasIdleRoom()
        {
            return !_idleRoomQ.IsEmpty;
        }

        public int GetIdleRoom()
        {
            int roomId = 0;
            if (_idleRoomQ.TryDequeue(out roomId))
            {
                if (_busyRoomMap.ContainsKey(roomId))
                {
                    return GetIdleRoom();
                }
                _busyRoomMap.TryAdd(roomId, 1);

                return roomId;
            }
            return 0;
        }

        public bool FreeRoom(int roomId)
        {
            int value = 0;
            if (_busyRoomMap.TryRemove(roomId, out value))
            {
                _idleRoomQ.Enqueue(roomId);
                return true;
            }
            return false;
        }

        private void InitMatchCode()
        {
            var allCodes = new List<int>();
            for (int i = 1000; i < 10000; i++)
            {
                allCodes.Add(i);
            }
            for (int i = 1000; i < 10000; i++)
            {
                var index = RandomExtensions.Instance.Next(allCodes.Count);
                _idleMatchCodeQ.Enqueue(allCodes[index]);
                allCodes.RemoveAt(index);
            }
        }

        public bool HasIdleMatchCode()
        {
            return !_idleMatchCodeQ.IsEmpty;
        }

        public int GetIdleMatchCode(MatchUser matchUser)
        {
            int matchCode = 0;
            if (_idleMatchCodeQ.TryDequeue(out matchCode))
            {
                if (_busyMatchCodeMap.ContainsKey(matchCode))
                {
                    return GetIdleMatchCode(matchUser);
                }
                _busyMatchCodeMap.TryAdd(matchCode, matchUser);
            }
            return matchCode;
        }

        public bool FreeMatchCode(int matchCode)
        {
            MatchUser matchUser = null;
            if (_busyMatchCodeMap.TryRemove(matchCode, out matchUser))
            {
                _idleMatchCodeQ.Enqueue(matchCode);
                return true;
            }
            return false;
        }

        public void CheckManualMatch(long time)
        {
            if (_busyMatchCodeMap.IsEmpty)
            {
                return;
            }
            foreach (var item in _busyMatchCodeMap)
            {
                var matchCode = item.Key;
                var matchUser = item.Value;
                if (matchUser == null || time - matchUser.StartTime >= MAX_MATCH_CODE_TIME)
                {
                    // 关闭房间
                    FreeMatchCode(matchCode);
                    // 通知逻辑服，房间超时
                    _ = M2L_NotifyMatchResult(matchUser.UserId, matchUser.ServerId, matchUser.BattleType, matchUser.IsRobot, false, string.Empty, (int)ErrorCode.ManualMatchOverTime, string.Empty, string.Empty);
                    break;
                }
            }
        }

        public ResultWithError<TStartMatchOutput> StartMatch(MatchUser matchUser, int battleVersion, bool isManual)
        {
            if (battleVersion != BattleService.BATTLE_VERSION)
            {
                // 战斗版本不一致
                Logger.LogError($"[Match][Start Match][Failed][BattleVersion is Invalid Client[{battleVersion}]] Server[{BattleService.BATTLE_VERSION}]");
                return new ResultWithError<TStartMatchOutput>()
                {
                    Code = ErrorCode.BattleVersionInvalid,
                    Data = new TStartMatchOutput(),
                };
            }

            if (isManual)
            {
                return StartManualMatch(matchUser);
            }

            if (matchUser == null)
            {
                Logger.LogError($"[Match][Start Match][Failed][MatchUser is Null]");
                return null;
            }

            if (_matchNodeMap.ContainsKey(matchUser.UserId))
            {
                // 玩家在匹配队列中
                Logger.LogError($"[Match-{matchUser.BattleType}][Start Match][Failed][User[{matchUser.UserId}] is Matching]");
                return null;
            }

            var result = new ResultWithError<TStartMatchOutput>()
            {
                Code = ErrorCode.Success,
                Data = new TStartMatchOutput(),
            };

            var battleType = matchUser.BattleType;
            var userId = matchUser.UserId;
            var serverId = matchUser.ServerId;

            if (!_matchMap.ContainsKey(battleType))
            {
                _matchMap.Add(battleType, new SortedLinkList<MatchUser>());
            }
            var matchList = _matchMap[battleType];

            // 加入匹配队列，并且保存节点
            matchUser.StartTime = timer.Time;
            _matchNodeMap[userId] = matchList.Add(matchUser);

            Logger.LogDebug($"[Match-{matchUser.BattleType}][Start Match][Success][User[{userId}] Server[{serverId}] Score[{matchUser.Score}]]");

            // 预估等待时间
            result.Data.WaitTime = 0;
            result.Data.BattleType = matchUser.BattleType;

            return result;
        }

        public ResultWithError<TStartMatchOutput> StartManualMatch(MatchUser matchUser)
        {
            if (matchUser == null)
            {
                Logger.LogError($"[Match][Start Match][Failed][[Manual-True] [MatchUser is Null]]");
                return null;
            }

            var result = new ResultWithError<TStartMatchOutput>()
            {
                Code = ErrorCode.Success,
                Data = new TStartMatchOutput(),
            };

            var matchCode = GetIdleMatchCode(matchUser);
            if (matchCode == 0)
            {
                Logger.LogError($"[Match-{matchUser.BattleType}][Start Match][Failed][[Manual-True] [User[{matchUser.UserId}] No Idle Match Code]]");

                result.Code = ErrorCode.ManualMatchFull;
                return result;
            }

            result.Data.MatchCode = matchCode;
            result.Data.BattleType = matchUser.BattleType;
            result.Data.WaitTime = MAX_MATCH_CODE_TIME;

            // 记录开始时间
            matchUser.StartTime = timer.Time;

            Logger.LogDebug($"[Match-{matchUser.BattleType}][Start Match][Success][[Manual-True-{matchCode}] [User[{matchUser.UserId}] Server[{matchUser.ServerId}] Battle[{matchUser.BattleType}] Score[{matchUser.Score}]]]");

            return result;
        }

        public bool CancelMatch(int userId, int battleType, int matchCode)
        {
            if (matchCode != 0)
            {
                return CancelManualMatch(userId, battleType, matchCode);
            }

            if (!_matchMap.ContainsKey(battleType))
            {
                Logger.LogError($"[Match-{battleType}][Cancel Match][Failed][User[{userId}] BattleType Invalid]");
                return true;
            }
            if (!_matchNodeMap.ContainsKey(userId))
            {
                Logger.LogError($"[Match-{battleType}][Cancel Match][Failed][User[{userId}] Is Not Matching]");
                return true;
            }
            var node = _matchNodeMap[userId];
            var matchUser = node.Value;
            if (matchUser.BattleType != battleType)
            {
                Logger.LogError($"[Match-{battleType}][Cancel Match][Failed][User[{userId}] Different BattleType[{battleType} - {matchUser.BattleType}]]");
                return true;
            }

            // 从匹配队列移除
            var matchList = _matchMap[battleType];
            matchList.Remove(node);

            // 移除节点
            _matchNodeMap.Remove(userId);

            Logger.LogDebug($"[Match-{battleType}][Cancel Match][Success][User[{userId}] Battle[{battleType}] Score[{matchUser.Score}]]");

            return true;
        }

        public bool CancelManualMatch(int userId, int battleType, int matchCode)
        {
            MatchUser matchUser = null;
            if (!_busyMatchCodeMap.TryGetValue(matchCode, out matchUser))
            {
                Logger.LogError($"[Match-{battleType}][Cancel Match][Failed][[Manual-True-{matchCode}] [User[{userId}] MatchCode InValid]]");
                return true;
            }
            if (matchUser.UserId != userId || matchUser.BattleType != battleType)
            {
                Logger.LogError($"[Match-{battleType}][Cancel Match][Failed][[Manual-True-{matchCode}] [User[{userId}] or BattleType Is Different MatchUser[{matchUser.UserId}] MatchType[{matchUser.BattleType}]]]");
                return true;
            }

            FreeMatchCode(matchCode);

            Logger.LogDebug($"[Match-{battleType}][Cancel Match][Success][[Manual-True-{matchCode}] [User[{userId}] Score[{matchUser.Score}]]]");

            return true;
        }

        public ErrorCode EnterManualMatch(MatchUser matchUser, int matchCode, int battleVersion)
        {
            if (battleVersion != BattleService.BATTLE_VERSION)
            {
                // 战斗版本不一致
                Logger.LogError($"[Match][Enter Match][Failed][BattleVersion is Invalid Client[{battleVersion}]] Server[{BattleService.BATTLE_VERSION}]");
                return ErrorCode.BattleVersionInvalid;
            }
            if (matchUser == null)
            {
                Logger.LogError($"[Match][Enter Match][Failed][MatchUser Is Null]");
                return ErrorCode.InvalidParameter;
            }
            MatchUser opponentUser = null;
            if (!_busyMatchCodeMap.TryGetValue(matchCode, out opponentUser))
            {
                Logger.LogError($"[Match][Enter Match][Failed][[Manual-True-{matchCode}] [MatchCode InValid]]");
                return ErrorCode.InvalidMatchCode;
            }
            if (opponentUser.BattleType != matchUser.BattleType || opponentUser.UserId == matchUser.UserId)
            {
                Logger.LogError($"[Match-{matchUser.BattleType}][Enter Match][Failed][[Manual-True-{matchCode}] [User or BattleType Different User[{matchUser.UserId} - {opponentUser.UserId}] Battle[{matchUser.BattleType} - {opponentUser.BattleType}]]]");
                return ErrorCode.InvalidMatchCode;
            }

            Logger.LogDebug($"[Match-{matchUser.BattleType}][Enter Match][Success][User[{matchUser.UserId}] Score[{matchUser.Score}]] MatchCode[{matchCode}]]");

            FreeMatchCode(matchCode);

            _ = OnMatchSuccess(opponentUser, matchUser, true);

            return ErrorCode.Success;
        }

        // 执行匹配
        public void ExecuteMatch(long time)
        {
            if (_matchMap.Count == 0)
            {
                return;
            }

            foreach (var item in _matchMap)
            {
                // 没有空闲房间，下一秒再尝试匹配
                if (!HasIdleRoom())
                {
                    break;
                }

                var battleType = (BattleType)item.Key;
                var matchList = item.Value;
                if (matchList.Count == 0)
                {
                    continue;
                }

                // 从前向后匹配，只对比后面有没有合适的对手
                var node = matchList.First;
                while (node != null)
                {
                    // 没有空闲房间，下一秒再尝试匹配
                    if (!HasIdleRoom())
                    {
                        break;
                    }

                    FindTargetUser(battleType, time, matchList, node, out MatchUser matchUser, out MatchUser targetUser);

                    if (targetUser != null)
                    {
                        // 匹配成功，本体从匹配队列移除
                        var nextNode = node.Next;
                        matchList.Remove(node);
                        node = nextNode;

                        // 移除匹配节点
                        if (_matchNodeMap.ContainsKey(matchUser.UserId))
                        {
                            _matchNodeMap.Remove(matchUser.UserId);
                        }
                        if (!targetUser.IsRobot && _matchNodeMap.ContainsKey(targetUser.UserId))
                        {
                            _matchNodeMap.Remove(targetUser.UserId);
                        }

                        var user1 = matchUser;
                        var user2 = targetUser;
                        if (targetUser.IsRobot)
                        {
                            var isTargetFirst = RandomExtensions.Instance.Next(100) > 50;
                            if (isTargetFirst)
                            {
                                user1 = targetUser;
                                user2 = matchUser;
                            }
                        }
                        _ = OnMatchSuccess(user1, user2);
                        continue;
                    }

                    node = node.Next;
                }
            }
        }

        private void FindTargetUser(BattleType battleType, long time, SortedLinkList<MatchUser> matchList, LinkedListNode<MatchUser> node, out MatchUser matchUser, out MatchUser targetUser)
        {

            switch (battleType)
            {
                case BattleType.PKRANDOM:
                    {
                        FindPkRandomTargetUser(battleType, time, matchList, node, out matchUser, out targetUser);
                    }
                    break;
                default:
                    {
                        matchUser = node.Value;
                        targetUser = null;
                        
                        if (matchUser.IsNewBie && battleType == BattleType.PK)
                        {
                            // PK新手阶段，只匹配机器人
                            if (time - matchUser.StartTime >= matchUser.MaxTime)
                            {
                                // 到达最大匹配时间，直接分配机器人
                                targetUser = RobotService.MatchRobot(matchUser, -1);
                            }
                        }
                        //按照策略
                        else if (matchUser.StrategyType == MatchStrategyType.ROBOT)
                        {
                            if (time - matchUser.StartTime >= matchUser.MaxTime)
                            {
                                targetUser = RobotService.MatchRobot(matchUser, matchUser.StrategyValue);
                            }
                        }
                        else
                        {
                            var nextNode = matchUser.GetSuitableOpponent(node.Next, time);
                            if (nextNode != null)
                            {
                                targetUser = nextNode.Value;

                                // 从匹配队列中移除
                                matchList.Remove(nextNode);
                            }
                            else if (time - matchUser.StartTime >= matchUser.MaxTime)
                            {
                                // 到达最大匹配时间，直接分配机器人
                                targetUser = RobotService.MatchRobot(matchUser, -1);
                            }
                        }
                    }
                    break;
            }
        }

        private void FindPkRandomTargetUser(BattleType battleType, long time, SortedLinkList<MatchUser> matchList, LinkedListNode<MatchUser> node, out MatchUser matchUser, out MatchUser targetUser)
        {
            matchUser = node.Value;
            targetUser = null;
            switch (matchUser.StrategyType)
            {
                //无策略
                case MatchStrategyType.NO:
                    //有下一个等待匹配玩家
                    var nextNode = node.Next;
                    if (nextNode != null)
                    {
                        //当前等待匹配玩家, 没有已对战选手
                        if ((matchUser.RecentPartners == null) || (matchUser.RecentPartners.Count == 0))
                        {
                            //直接匹配下一个玩家
                            targetUser = nextNode.Value;
                            matchList.Remove(nextNode);
                            return;
                        }
                        //当前等待匹配玩家, 有已对战选手
                        while (nextNode != null)
                        {
                            //未对战过下一个等待匹配玩家
                            if (!matchUser.RecentPartners.Contains(nextNode.Value.UserId))
                            {
                                //直接匹配下一个玩家
                                targetUser = nextNode.Value;
                                matchList.Remove(nextNode);
                                return;
                            }
                            nextNode = nextNode.Next;
                        }
                    }

                    //匹配超时 => 匹配机器人
                    if ((time - matchUser.StartTime) >= matchUser.MaxTime)
                    {
                        targetUser = RobotService.MatchRobot(matchUser);
                    }
                    break;
                //有策略
                default:
                    //匹配超时 => 匹配机器人
                    if ((time - matchUser.StartTime) >= matchUser.MaxTime)
                    {
                        targetUser = RobotService.MatchRobot(matchUser, matchUser.StrategyValue);
                    }
                    break;
            }
        }

        // 匹配成功
        public async Task OnMatchSuccess(MatchUser user1, MatchUser user2, bool isManual = false, int retryTimes = 0)
        {
            // 没有空闲房间
            if (!HasIdleRoom())
            {
                Logger.LogWarning($"[Match-{user1.BattleType}][OnMatchSuccess][Failed][No Idle Room [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]");

                // 通知逻辑服匹配失败，没有空闲房间
                _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, user1.BattleType, user1.IsRobot, false, string.Empty, (int)ErrorCode.NoIdleRoom, string.Empty, string.Empty);
                _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, user2.BattleType, user2.IsRobot, false, string.Empty, (int)ErrorCode.NoIdleRoom, string.Empty, string.Empty);
                return;
            }

            // 分配房间，生成战斗Id
            var roomId = GetIdleRoom();
            var roomServerId = RoomService.GetRoomServerId(_matchServerConfig, roomId);
            var roomServerUrl = ConfigService.GetServerUrl(roomServerId);

            Logger.LogDebug($"[Match-{user1.BattleType}][OnMatchSuccess][None][[Prepare Room [{roomId}_{roomServerId}] Retry[{retryTimes}]] [Users [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]]");

            // 通知房间服房间用户信息
            var result = await RoomService.M2R_PrepareRoom(roomServerId, roomId, new List<MatchUser>() { user1, user2 }, isManual);
            if (result == null || result.Code != ErrorCode.Success)
            {
                Logger.LogWarning($"[Match-{user1.BattleType}][OnMatchSuccess][Failed][[Room Server Error[{result?.Code}] Room[{roomId}_{roomServerId}] Retry[{retryTimes}]] [Users [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]]");

                // 释放房间
                FreeRoom(roomId);

                if (retryTimes >= 2)
                {
                    // 通知逻辑服匹配失败，没有空闲房间
                    _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, user1.BattleType, user1.IsRobot, false, string.Empty, (int)ErrorCode.RoomServerInvalid, string.Empty, string.Empty);
                    _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, user2.BattleType, user2.IsRobot, false, string.Empty, (int)ErrorCode.RoomServerInvalid, string.Empty, string.Empty);
                }
                else
                {
                    await Task.Delay(100);
                    await OnMatchSuccess(user1, user2, isManual, retryTimes + 1);
                }

                return;
            }

            // 暂存真实玩家数据
            SaveBattleingUser(user1);
            SaveBattleingUser(user2);

            var battleId = result.Data.BattleId;
            user1.BattleId = battleId;
            user2.BattleId = battleId;

            Logger.LogDebug($"[Match-{user1.BattleType}][OnMatchSuccess][Success][[Room[{roomId}_{roomServerId}] Retry[{retryTimes}] Battle[{battleId}] [Users [{user1.UserId}_{user1.Score}_{user1.MatchScore}] vs [{user2.UserId}_{user2.Score}_{user2.MatchScore}]]]");

            // 通知逻辑服匹配成功
            _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, user1.BattleType, user1.IsRobot, true, roomServerUrl, roomId, battleId, result.Data.Tokens[0]);
            _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, user2.BattleType, user2.IsRobot, true, roomServerUrl, roomId, battleId, result.Data.Tokens[1]);
        }

        public void SaveBattleingUser(MatchUser matchUser)
        {
            if (matchUser == null)
            {
                return;
            }
            _battlingUserMap.AddOrUpdate(matchUser.UserId, matchUser, (key, value) => matchUser);
        }

        public void RemoveBattleingUser(int userId)
        {
            _battlingUserMap.TryRemove(userId, out MatchUser matchUser);
        }

        public MatchUser GetBattlingUser(int userId)
        {
            _battlingUserMap.TryGetValue(userId, out MatchUser matchUser);
            return matchUser;
        }

        [Rpc]
        // 房间服--->匹配服，通知匹配服结算结果，标记房间空闲
        public static async Task R2M_NotifySettleResult(int serverId, RoomSettleData data)
        {
            if (serverId <= 0) return;
            await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(serverId, data),
                () => { INSTANCE.Post(() => INSTANCE.M_NotifyBattleResult(data)); }
            );
        }

        // 通知战斗结果
        public void M_NotifyBattleResult(RoomSettleData data)
        {
            try
            {
                if (!_battlingUserMap.TryGetValue(data.UserId1, out MatchUser user1))
                {
                    Logger.LogError($"Cannot find MatchUser[{data.UserId1}]");
                }
                if (!_battlingUserMap.TryGetValue(data.UserId2, out MatchUser user2))
                {
                    Logger.LogError($"Cannot find MatchUser[{data.UserId2}]");
                }

                var battleType = (int)BattleType.ALL;
                if (user1 != null)
                {
                    battleType = user1.BattleType;
                }
                else if (user2 != null)
                {
                    battleType = user2.BattleType;
                }

                var unusual1 = false;
                var unusual2 = false;
                TBattleResult result1 = null;
                TBattleResult result2 = null;
                TReocrdBattleItem battleItem = null;
                //房间准备未超时
                if (!data.PrepareOverTime)
                {
                    //对战记录
                    if (data.BattleResult != null)
                    {
                        //玩家1上报结果是否异常
                        unusual1 = (data.UserResult1 != null) && (!data.BattleResult.IsSameResult(data.UserResult1));
                        //玩家2上报结果是否异常
                        unusual2 = (data.UserResult2 != null) && (!data.BattleResult.IsSameResult(data.UserResult2));

                        result1 = new TBattleResult(data.BattleResult, data.UserResult1 == null ? true : data.UserResult1.IsPoorNet);
                        result2 = new TBattleResult(data.BattleResult, data.UserResult2 == null ? true : data.UserResult2.IsPoorNet);
                    }
                    else
                    {
                        result1 = data.UserResult1;
                        result2 = data.UserResult2;
                    }

                    if ((battleType == (int)BattleType.PK) || (battleType == (int)BattleType.COOP) || (battleType == (int)BattleType.PKRANDOM))
                    {
                        battleItem = (result1 == null && result2 == null) ? null : new TReocrdBattleItem(user1, result1, user2, result2);
                    }
                }
                var playerId1 = user1 == null ? 0 : user1.IsRobot ? -user1.RobotUserId : user1.UserId;
                var playerId2 = user2 == null ? 0 : user2.IsRobot ? -user2.RobotUserId : user2.UserId;
                //通知玩家1
                M_NotifyBattleResult(user1, result1, battleItem, data.IsManual, unusual1, data.PrepareOverTime, playerId2);
                //通知玩家2
                M_NotifyBattleResult(user2, result2, battleItem, data.IsManual, unusual2, data.PrepareOverTime, playerId1);
            }
            catch (Exception e)
            {
                Logger.LogError(e, $"NotifyBattleResult failed.");
            }
            finally
            {
                // 释放房间
                FreeRoom(data.RoomId);
                // 移除暂存玩家数据
                RemoveBattleingUser(data.UserId1);
                RemoveBattleingUser(data.UserId2);
            }
        }

        private void M_NotifyBattleResult(MatchUser user, TBattleResult result, TReocrdBattleItem battleItem, bool isManual, bool unusual, bool prepareOverTime, int playerId)
        {
            if (user == null) return;
            //机器人
            if (user.IsRobot)
            {
                //要求线程安全
                //[不结算]无战斗结果或者房间准备超时
                if (!(result == null || prepareOverTime))
                {
                    RobotService.BattleSettle(user, result);
                }
            }
            //真实玩家, 通知逻辑服战斗结果
            else
            {
                result?.SetBattleType(user.BattleType);
                _ = M2L_NotifyBattleResult(result, battleItem, user.UserId, user.BattleId, user.ServerId, isManual, unusual, prepareOverTime, playerId);
            }
        }

        public static bool L_TryStartMatch(int userId, int battleType, bool needConsume = false)
        {
            switch (battleType)
            {
                case (int)BattleType.COOP:
                    {
                        var battleInfo = UserService.TryGetUserBattleInfo(userId);
                        if (battleInfo == null)
                        {
                            return false;
                        }
                        if (battleInfo.LeftCoopTimes == 0)
                        {
                            return false;
                        }
                        if (needConsume)
                        {
                            battleInfo.LeftCoopTimes--;
                            TUserBattleInfo.Cache.AddOrUpdate(battleInfo);
                        }
                        return true;
                    }
                default:
                    {
                        return true;
                    }
            }
        }

        /// <summary>
        /// 逻辑服 - 创建或者更新匹配策略
        /// </summary>
        private static MatchStrategyItem L_CreateOrUpdateMatchStrategy(int userId, int battleType, out List<int> recentPartners)
        {
            recentPartners = null;

            //创建策略
            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"User[{userId}]: TUserProfile.Cache.FindKey({userId}) is null");
                return null;
            }
            var matchStrategy = UserMatchStrategy.Cache.FindKey(userId);
            if (matchStrategy == null)
            {
                var initPkRankRes = ConfigService.GetPkRankResConfig(profile.CurScore);
                if (initPkRankRes == null)
                {
                    Logger.LogError($"User[{userId}]: PKRankResConfig.Cache.FindKey({profile.CurScore}) is null");
                    return null;
                }
                matchStrategy = new UserMatchStrategy(userId, initPkRankRes.id);
                UserMatchStrategy.Cache.AddOrUpdate(matchStrategy);
            }
            //最近伙伴
            recentPartners = matchStrategy.RecentPartners?.ToList();
            //更新策略
            switch (battleType)
            {
                case (int)BattleType.COOP:
                    {
                        var strategyGroup = matchStrategy.COOP;
                        var pkRankRes = PKRankResConfig.Cache.FindKey(strategyGroup.Id);
                        if (pkRankRes == null)
                        {
                            Logger.LogError($"User[{userId}]: PKRankResConfig.Cache.FindKey({strategyGroup.Id}) is null");
                            return matchStrategy.GetStrategyItem();
                        }
                        //顺序敏感
                        //策略组降级
                        if (profile.CurScore < pkRankRes.triggerScore[0])
                        {
                            L_ResetMatchStrategy(userId, strategyGroup, strategyGroup.Id - 1);
                            UserMatchStrategy.Cache.AddOrUpdate(matchStrategy);
                        }
                        //策略组升级
                        else if (profile.CurScore > pkRankRes.triggerScore[1])
                        {
                            L_ResetMatchStrategy(userId, strategyGroup, strategyGroup.Id + 1);
                            UserMatchStrategy.Cache.AddOrUpdate(matchStrategy);
                        }
                        //策略组已空
                        else if (strategyGroup.IsEmpty)
                        {
                            L_ResetMatchStrategy(userId, strategyGroup, strategyGroup.Id);
                            UserMatchStrategy.Cache.AddOrUpdate(matchStrategy);
                        }
                        //返回当前策略
                        return matchStrategy.GetStrategyItem(strategyGroup.CurStrategy);
                    }
                    break;
                default:
                    {

                    }
                    break;
            }
            return matchStrategy.GetStrategyItem();
        }

        /// <summary>
        /// 逻辑服 - 重置匹配策略
        /// </summary>
        private static void L_ResetMatchStrategy(int userId, MatchStrategyGroup group, int strategyGroupId)
        {
            if (group == null)
            {
                Logger.LogError($"User[{userId}]: MatchStrategyGroup group is null");
                return;
            }
            strategyGroupId = ConfigService.CheckStrategyId(strategyGroupId);
            var pkRankRes = ConfigService.GetPkRankResConfigByStrategyId(strategyGroupId);
            if (pkRankRes == null)
            {
                Logger.LogError($"User[{userId}]: PKRankResConfig.Cache.FindKey({strategyGroupId}) is null");
                return;
            }
            //重置策略组Id
            group.Id = strategyGroupId;
            //清空策略
            group.ClearStrategy();
            //添加策略
            foreach (var strategyId in pkRankRes.MatchStrategyGroup)
            {
                var strategyRes = MatchStrategyResConfig.Cache.FindKey(strategyId);
                if (strategyRes == null)
                {
                    Logger.LogError($"User[{userId}]: MatchStrategyResConfig.Cache.FindKey({strategyId}) is null");
                    continue;
                }
                var hitIndex = RandomExtensions.Instance.RandomDrop(strategyRes.weightList);
                if (hitIndex < 0)
                {
                    Logger.LogError($"User[{userId}]: Match strategyId[{strategyId}] random hitIndex[{hitIndex}] < 0");
                    continue;
                }
                switch (strategyRes.matchStrategy)
                {
                    //无
                    case MatchStrategyType.NO:
                    //大腿
                    case MatchStrategyType.BIGMAN:
                        group.AddStrategy(strategyRes.matchStrategy, strategyRes.fakeScore, strategyRes.countList[hitIndex]);
                        break;
                    //机器人
                    case MatchStrategyType.ROBOT:
                        group.AddStrategy(strategyRes.matchStrategy, strategyRes.robotIdLIst[hitIndex], strategyRes.countList[hitIndex]);
                        break;
                }
            }
            //重置索引
            group.RandomIndex();
            Logger.LogDebug($"User[{userId}]: Random MatchStrategyIndex {group.Index}");
        }

        /// <summary>
        /// 逻辑服 - 结算匹配策略
        /// </summary>
        private static void L_SettleMatchStrategy(int userId, TBattleResult battleResult, int partnerId)
        {
            //暂时只有COOP匹配策略
            var matchStrategy = UserMatchStrategy.Cache.FindKey(userId);
            if (matchStrategy == null)
            {
                Logger.LogError($"User[{userId}]: UserMatchStrategy.Cache.FindKey({userId}) is null");
                return;
            }

            // 网络状况
            var isPoorNet = battleResult == null ? true : battleResult.IsPoorNet;
            bool isDirty = matchStrategy.UpdateNet(isPoorNet);
            if (isDirty)
            {
                Logger.LogDebug($"[Match][Settle Strategy][Success][User[{userId}] Net Change Times[{matchStrategy.PoorNetTimes}]]");
            }

            // 伙伴
            if (partnerId != 0)
            {
                matchStrategy.AddPartner(partnerId);
                isDirty = true;
            }

            if (battleResult != null)
            {
                switch (battleResult.BattleType)
                {
                    case (int)BattleType.COOP:
                        {
                            //下一个匹配策略
                            isDirty = matchStrategy.COOP.NextStrategy() || isDirty;
                            Logger.LogDebug($"User[{userId}]: Next MatchStrategyIndex {matchStrategy.COOP.Index}");
                        }
                        break;
                    default:
                        break;
                }
            }
            if (isDirty)
            {
                UserMatchStrategy.Cache.AddOrUpdate(matchStrategy);
            }
        }

        // 逻辑服，发起匹配
        public static async Task<ResultWithError<TStartMatchOutput>> L_StartMatch(int userId, int battleType, int areaId, int battleVersion, bool isManual = false)
        {
            var result = new ResultWithError<TStartMatchOutput>()
            {
                Code = ErrorCode.Success,
                Data = new TStartMatchOutput()
            };

            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Not Found]]");
                result.Code = ErrorCode.InvalidParameter;
                return result;
            }

            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Profile Not Found]]");
                result.Code = ErrorCode.InvalidParameter;
                return result;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match != null && match.MatchState != TMatchState.None)
            {
                // 已经在匹配了或战斗中
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] MatchState Invalid State[{match.MatchState}]]]");
                result.Code = ErrorCode.AllreadyBattleing + (int)match.MatchState - 1;
                return result;
            }

            if (!L_TryStartMatch(userId, battleType))
            {
                // 匹配次数不足
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Match Times is 0]]");
                result.Code = ErrorCode.MatchTimesZero;
                return result;
            }

            ErrorCode err;
            int heroResId;
            List<int> towerResIds;
            int critScale;
            int fieldId;
            List<int> recentPartners;
            MatchStrategyItem strategyItem;
            switch ((BattleType)battleType)
            {
                case BattleType.PKRANDOM:
                    critScale = ConfigConstants.RANDOMARENA_TOWER_CRITSCALE;
                    err = ArenaRandomLogicService.GetBattleTeamData(userId, out heroResId, out towerResIds, out fieldId, out recentPartners);
                    strategyItem = L_CreateOrUpdateMatchStrategy(userId, battleType, out _);
                    break;
                default:
                    err = CardService.GetBattleTeamData(userId, battleType,
                        out THero hero, out towerResIds, out critScale, out fieldId);
                    heroResId = hero == null ? 0 : hero.BattleHeroResId;
                    strategyItem = L_CreateOrUpdateMatchStrategy(userId, battleType, out recentPartners);
                    break;
            }

            if (err != ErrorCode.Success)
            {
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Battle Team Error[{err}]]]");
                result.Code = err;
                return result;
            }

            var matchUser = new MatchUser(battleType, fieldId, user.ServerId, userId, user.GetName(),
                profile.CurScore, heroResId, towerResIds, critScale, null, 0, strategyItem, recentPartners);

            // 匹配服Id
            var matchServerId = GetMatchServerId(areaId);
            var matchStartResult = await L2M_StartMatch(matchUser, matchServerId, battleVersion, isManual);
            if (matchStartResult == null)
            {
                // 匹配服不可用
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Match Server Invalid]]");
                result.Code = ErrorCode.MatchServerInvalid;
                return result;
            }
            result.Code = matchStartResult.Code;
            if (result.Code != ErrorCode.Success)
            {
                Logger.LogError($"[Match-{battleType}][Start Match][Failed][[Manual-{isManual}] [User[{userId}] Match Server Error[{result.Code}]]]");
                return result;
            }

            // 加入匹配队列成功，缓存匹配状态
            if (match == null)
            {
                match = new TMatch()
                {
                    UserId = userId,
                    MatchState = TMatchState.None,
                };
            }
            match.MatchState = isManual ? TMatchState.Manualing : TMatchState.Matching;
            match.MatchServerId = matchServerId;
            match.MatchCode = matchStartResult.Data.MatchCode;
            match.BattleType = battleType;
            match.RoomServerUrl = string.Empty;
            match.RoomId = 0;
            match.BattleId = string.Empty;
            match.RoomToken = string.Empty;
            TMatch.Cache.AddOrUpdate(match);

            result.Data = matchStartResult.Data;
            result.Data.MatchServerId = matchServerId;
            result.Data.WaitTime = matchUser.MaxTime;

            Logger.LogDebug($"[Match-{battleType}][Start Match][Success][[Manual-{isManual}-{match.MatchCode}] [User[{userId}] Match Start Strategy[{matchUser.StrategyType}_{matchUser.StrategyValue}] MaxTime[{matchUser.MaxTime}] MatchScore[{matchUser.MatchScore}]]]");

            return result;
        }

        [Rpc]
        // 逻辑服--->匹配服，发起匹配
        public static async Task<ResultWithError<TStartMatchOutput>> L2M_StartMatch(MatchUser matchUser, int matchServerId, int battleVersion, bool isManual)
        {
            if (matchUser == null || matchServerId == 0)
            {
                return null;
            }

            return await RpcProxy.RunAsync(typeof(MatchService), matchServerId, RpcProxy.BuildArgs(matchUser, matchServerId, battleVersion, isManual), async () =>
            {
                // 加入匹配队列
                return await MatchService.INSTANCE.PostAsync<ResultWithError<TStartMatchOutput>>(() =>
                {
                    return MatchService.INSTANCE.StartMatch(matchUser, battleVersion, isManual);
                });
            });
        }

        // 逻辑服，取消匹配
        public static async Task<ErrorCode> L_CancelMatch(int userId)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                Logger.LogError($"[Match][Cancel Match][Failed][User[{userId}] Not Found]");
                return ErrorCode.InvalidParameter;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null || match.MatchState < TMatchState.Matching)
            {
                Logger.LogError($"[Match][Cancel Match][Failed][User[{userId}] Is Not Matching]");

                // 当前未在匹配中，无法取消匹配
                return ErrorCode.NotMatching;
            }

            var matchServerId = match.MatchServerId;
            if (!IsMatchServer(matchServerId))
            {
                Logger.LogError($"[Match][Cancel Match][Failed][User[{userId}] MachServer[{matchServerId}] Is InValid]");
                return ErrorCode.MatchServerInvalid;
            }

            var cancelResult = await L2M_CancelMatch(userId, match.BattleType, matchServerId, match.MatchCode);
            if (cancelResult != null && cancelResult.Code != ErrorCode.Success)
            {
                Logger.LogError($"[Match][Cancel Match][Failed][User[{userId}] Cancel Error[{cancelResult?.Code}]]");
                return cancelResult.Code;
            }

            // 更新匹配状态
            match.MatchState = TMatchState.None;
            match.MatchServerId = 0;
            match.MatchCode = 0;
            TMatch.Cache.AddOrUpdate(match);

            Logger.LogDebug($"[Match][Cancel Match][Success][User[{userId}] Cancel Success]");

            return ErrorCode.Success;
        }

        [Rpc(RetryTimes = 2, RetryIntervals = new int[] { 200 })]
        // 逻辑服--->匹配服，取消匹配
        public static async Task<ResultWithError<int>> L2M_CancelMatch(int userId, int battleType, int matchServerId, int matchCode)
        {
            if (matchServerId == 0)
            {
                return null;
            }

            return await RpcProxy.RunAsync(typeof(MatchService), matchServerId, RpcProxy.BuildArgs(userId, battleType, matchServerId, matchCode), async () =>
            {
                var result = new ResultWithError<int>();

                // 移除匹配队列
                var success = await MatchService.INSTANCE.PostAsync<bool>(() =>
                {
                    return MatchService.INSTANCE.CancelMatch(userId, battleType, matchCode);
                });

                return result;
            });
        }


        // 逻辑服，进入手动匹配房间
        public static async Task<ErrorCode> L_EnterMatch(int userId, int battleType, int areaId, int matchCode, int battleVersion)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] Not Found]");
                return ErrorCode.InvalidParameter;
            }

            var profile = TUserProfile.Cache.FindKey(userId);
            if (profile == null)
            {
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] Profile Not Found]");
                return ErrorCode.InvalidParameter;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match != null && match.MatchState != TMatchState.None)
            {
                // 已经在匹配了或战斗中
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] MatchState[{match.MatchState}] Is InValid]");
                return ErrorCode.AllreadyBattleing + (int)match.MatchState - 1;
            }

            if (!L_TryStartMatch(userId, battleType))
            {
                // 匹配次数不足
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] Match Times is 0]");
                return ErrorCode.MatchTimesZero;
            }

            var errCode = CardService.GetBattleTeamData(userId, battleType,
                out THero hero, out List<int> towerResIds, out int critScale, out int fieldId);
            if (errCode != ErrorCode.Success)
            {
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] Battle Team Error[{errCode}]");
                return errCode;
            }

            var matchUser = new MatchUser(battleType, fieldId, user.ServerId, userId, user.GetName(),
                profile.CurScore, hero.BattleHeroResId, towerResIds, critScale, null);

            var matchServerId = GetMatchServerId(areaId);
            var enterResult = await L2M_EnterMatch(matchUser, matchServerId, matchCode, battleVersion);
            if (enterResult == null)
            {
                Logger.LogError($"[Match-{battleType}][Enter Match][Failed][User[{userId}] Match Server Invalid]");
                return ErrorCode.MatchServerInvalid;
            }

            Logger.LogDebug($"[Match-{battleType}][Enter Match][Success][User[{userId}] Result[{enterResult.Code}]]");
            return enterResult.Code;
        }

        [Rpc]
        // 逻辑服--->匹配服，进入手动匹配房间
        public static async Task<ResultWithError<int>> L2M_EnterMatch(MatchUser matchUser, int matchServerId, int matchCode, int battleVersion)
        {
            if (matchServerId == 0 || matchUser == null)
            {
                return null;
            }

            return await RpcProxy.RunAsync(typeof(MatchService), matchServerId, RpcProxy.BuildArgs(matchUser, matchServerId, matchCode, battleVersion), async () =>
            {
                var result = new ResultWithError<int>();

                // 移除匹配队列
                result.Code = await MatchService.INSTANCE.PostAsync<ErrorCode>(() =>
                {
                    return MatchService.INSTANCE.EnterManualMatch(matchUser, matchCode, battleVersion);
                });

                return result;
            });
        }


        // 逻辑服，通知匹配结果
        public static async Task<ErrorCode> L_NotifyMatchResult(int userId, int battleType, bool isSuccess, string roomServerUrl, int roomId, string battleId, string roomToken)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                Logger.LogError($"[Match-{battleType}][NotifyMatchResult][Failed][Result[{isSuccess}-{roomId}-{battleId}] User[{userId}] Not Found]");
                return ErrorCode.DataNotFound;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null)
            {
                match = new TMatch()
                {
                    UserId = userId,
                    MatchState = TMatchState.None,
                };
            }

            if (isSuccess)
            {
                // 消耗匹配次数
                L_TryStartMatch(userId, battleType, true);

                // 匹配成功
                match.BattleType = battleType;
                match.MatchState = TMatchState.Battleing;
                match.RoomServerUrl = roomServerUrl;
                match.RoomId = roomId;
                match.BattleId = battleId;
                match.RoomToken = roomToken;
                match.MatchCode = 0;
            }
            else
            {
                // 匹配失败，取消匹配
                match.MatchState = TMatchState.None;
                match.MatchCode = 0;
            }
            TMatch.Cache.AddOrUpdate(match);

            // 广播给客户端匹配结果，匹配成功时客户端收到通知，直接连接房间服
            await BroadcastService.BroadcastAsync(userId, new BroadcastMatchResultDefinition(battleType, roomId, roomServerUrl, battleId, roomToken));

            Logger.LogDebug($"[Match-{battleType}][NotifyMatchResult][Success][Result[{isSuccess}-{roomId}-{battleId}] User[{userId}] MatchState[{match.MatchState}]]");

            return ErrorCode.Success;
        }

        [Rpc]
        // 匹配服--->逻辑服，通知匹配结果
        public static async Task<ResultWithError<int>> M2L_NotifyMatchResult(int userId, int serverId, int battleType, bool isRobot, bool isSuccess, string roomServerUrl, int roomId, string battleId, string roomToken)
        {
            if (isRobot)
            {
                return null;
            }
            Logger.LogDebug($"[Match-{battleType}][NotifyMatchResult][None][Result[{isSuccess}-{roomId}-{battleId}] User[{userId}] Server[{serverId}]]");
            return await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(userId, serverId, battleType, isRobot, isSuccess, roomServerUrl, roomId, battleId, roomToken), async () =>
            {
                var result = new ResultWithError<int>();

                // 逻辑服，通知匹配结果
                result.Code = await L_NotifyMatchResult(userId, battleType, isSuccess, roomServerUrl, roomId, battleId, roomToken);

                return result;
            });
        }

        // 逻辑服，通知战斗结果
        public static async Task<ErrorCode> L_NotifyBattleResult(int userId, string battleId, TBattleResult battleResult, TReocrdBattleItem battleItem, bool isManual, bool unusual, bool prepareOverTime, int playerId)
        {
            if ((battleItem != null) && (!string.IsNullOrEmpty(battleItem.Id)))
            {
                //添加战斗记录
                var battleUser = TRecordBattleUser.Cache.FindKey(userId);
                if (battleUser != null)
                {
                    battleUser.Add(battleItem);
                    TRecordBattleUser.Cache.AddOrUpdate(battleUser);
                }
                //保存战斗记录
                TReocrdBattleItem.Cache.AddOrUpdate(battleItem);
            }

            //顺序敏感
            //战斗结算, 不能返给ErrorCode, 必须要成功关闭匹配
            BattleService.Settle(userId, battleId, battleResult, isManual, out TBattleSettle settle, playerId);

            //匹配策略结算
            L_SettleMatchStrategy(userId, battleResult, (isManual || battleItem == null) ? 0 : battleItem.GetPartnerId(userId));

            //榜单结算
            if (settle != null) _ = RankLogicService.Settle(userId, settle);

            //玩家上报的战斗结果与后端模拟结果不一致, 异常处理
            if (unusual)
            {
                //TODO ...
            }

            //广播房间准备超时
            if (prepareOverTime)
            {
                await BroadcastService.BroadcastAsync(userId, new BroadcastRoomPrepareOverTimeDefinition(new TEmpty()));
            }
            //广播战斗结算结果
            else if (settle != null)
            {
                await BroadcastService.BroadcastAsync(userId, new BroadcastBattleSettleDefinition(settle));
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null)
            {
                return ErrorCode.DataNotFound;
            }

            // 只能关闭同一场战斗匹配
            if (match.BattleId != battleId)
            {
                return ErrorCode.Success;
            }

            // 战斗结束
            match.MatchState = TMatchState.None;
            match.MatchServerId = 0;
            match.BattleType = 0;
            match.RoomServerUrl = string.Empty;
            match.RoomId = 0;
            match.BattleId = string.Empty;
            match.RoomToken = string.Empty;
            TMatch.Cache.AddOrUpdate(match);

            return ErrorCode.Success;
        }

        [Rpc(RetryTimes = 10, RetryIntervals = new int[] { 100, 300, 600, 1000, 10 * 1000, 30 * 1000, 60 * 1000, 10 * 60 * 1000, 15 * 60 * 1000, 30 * 60 * 1000 })]
        // 匹配服--->逻辑服，通知战斗结果
        public static async Task<ResultWithError<int>> M2L_NotifyBattleResult(TBattleResult battleResult, TReocrdBattleItem battleItem, int userId, string battleId, int serverId, bool isManual, bool unusual, bool prepareOverTime, int playerId)
        {
            Interlocked.Increment(ref _playerSettleingCount);
            var notifyResult = await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(battleResult, battleItem, userId, battleId, serverId, isManual, unusual, prepareOverTime, playerId), async () =>
            {
                var result = new ResultWithError<int>
                {
                    // 逻辑服，通知匹配结果
                    Code = await L_NotifyBattleResult(userId, battleId, battleResult, battleItem, isManual, unusual, prepareOverTime, playerId)
                };

                return result;
            });
            Interlocked.Decrement(ref _playerSettleingCount);
            return notifyResult;
        }

        [Rpc]
        public static async Task<ResultWithError<TBattleRecord>> L2M_LoadBattleRecord(int serverId, string battleId)
        {
            return await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(serverId, battleId), async () =>
            {
                var result = new ResultWithError<TBattleRecord>() { Code = ErrorCode.Success, Data = null };
                result.Data = TBattleRecord.Cache.FindKey(battleId);
                if (result.Data == null)
                {
                    result.Code = ErrorCode.DataNotFound;
                }
                return result;
            });
        }

        // 玩家断开连接
        public static async void L_OnServerDisconnected(int userId)
        {
            // 只处理逻辑服
            if (userId <= 0 || !Host.Role.HasRole(ServerRole.Logic))
            {
                return;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match != null && match.MatchState >= TMatchState.Matching)
            {
                // 匹配中的玩家，与服务器断开连接后，取消匹配
                await L_CancelMatch(userId);
            }
        }

        public static int GetMatchServerId(int areaId)
        {
            var config = ConfigService.MatchConfig.Value;
            var matchServerConfig = config.GetMatchServerConfigByAreaId(areaId);
            if (matchServerConfig == null)
            {
                return 0;
            }
            return matchServerConfig.ServerId;
        }

        public static bool IsMatchServer(int matchServerId)
        {
            var matchServerConfig = ConfigService.MatchConfig.Value?.GetMatchServerConfigByMatchServerId(matchServerId);
            return matchServerConfig != null;
        }

        // 实时统计
        public void StartStat()
        {
            _rtMatch.ServerId = Host.ServerId;
            _rtMatch.SetCommitListener(() =>
            {
                _rtMatch.RoomFreeCount = _idleRoomQ.Count;
                _rtMatch.RoomBusyCount = _busyRoomMap.Count;
                _rtMatch.RoomManualCount = _busyMatchCodeMap.Count;
                _rtMatch.PlayerMatchingCount = 0;
                for (int i = 1; i < (int)BattleType.MAX; i++)
                {
                    _rtMatch.PlayerMatchingMap[i] = 0;
                    _rtMatch.PlayerBattleingMap[i] = 0;
                }
                foreach (var battleType in _matchMap.Keys)
                {
                    var count = _matchMap[battleType].Count;
                    _rtMatch.PlayerMatchingMap[battleType] = count;
                    _rtMatch.PlayerMatchingCount += count;
                }
                _rtMatch.PlayerBattleingCount = 0;
                var battlingUsers = _battlingUserMap.Keys.ToList();
                foreach (var userId in battlingUsers)
                {
                    if (_battlingUserMap.TryGetValue(userId, out MatchUser matchUser))
                    {
                        if (matchUser != null && !matchUser.IsRobot)
                        {
                            var battleType = matchUser.BattleType;
                            _rtMatch.PlayerBattleingMap[battleType] += 1;
                            _rtMatch.PlayerBattleingCount += 1;
                        }
                    }
                }
                _rtMatch.PlayerSettleingCount = _playerSettleingCount;
            });
        }
    }
}