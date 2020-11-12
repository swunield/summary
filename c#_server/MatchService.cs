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
using Game.Utils;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Text;
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
        private ConcurrentQueue<int> _idleRoomList = new ConcurrentQueue<int>();

        // 占用房间
        private ConcurrentDictionary<int, int> _busyRoomMap = new ConcurrentDictionary<int, int>();

        // 匹配队列，线程安全
        private Dictionary<int, SortedLinkList<MatchUser>> _matchMap = new Dictionary<int, SortedLinkList<MatchUser>>();

        // 玩家匹配节点
        private Dictionary<int, LinkedListNode<MatchUser>> _matchNodeMap = new Dictionary<int, LinkedListNode<MatchUser>>();

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

            // 启动线程
            this.StartThreadContext();
        }

        private void Update(long delta, long time)
        {
            // 线程更新
            this.ThreadContextUpdate();

            // 每秒匹配一次
            _matchUpdateTime += delta;
            if (_matchUpdateTime >= MATCH_UPDATE_INTERVAL)
            {
                _matchUpdateTime -= MATCH_UPDATE_INTERVAL;

                // 执行匹配
                ExecuteMatch(time);
            }
        }

        private bool InitRoom()
        {
            var config = ConfigManager.LoadConfig<MatchConfig>();
            _matchServerConfig = config.GetMatchServerConfig(Host.ServerId);
            if (_matchServerConfig == null)
            {
                Logger.LogError($"[Match][Room Init][Can not find MatchServerConfig [{Host.ServerId}]]");
                return false;
            }

            var roomServerCount = _matchServerConfig.RoomServers.Length;
            for (int i = 0; i < _matchServerConfig.RoomCount; i++)
            {
                // 加入空闲队列
                var roomId = i + 1;
                _idleRoomList.Enqueue(roomId);
            }

            return true;
        }

        public bool HasIdleRoom()
        {
            return !_idleRoomList.IsEmpty;
        }

        public int GetIdleRoom()
        {
            int roomId = 0;
            if (_idleRoomList.TryDequeue(out roomId))
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

        public void FreeRoom(int roomId)
        {
            if (!_busyRoomMap.ContainsKey(roomId))
            {
                return;
            }

            int value = 0;
            if (_busyRoomMap.TryRemove(roomId, out value))
            {
                _idleRoomList.Enqueue(roomId);
            }
        }

        public int StartMatch(MatchUser matchUser)
        {
            if (matchUser == null || _matchNodeMap.ContainsKey(matchUser.UserId))
            {
                // 玩家在匹配队列中
                return -1;
            }

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

            Logger.LogVerbose($"[Match][Start Match][User[{userId}] Server[{serverId}] Battle[{battleType}] Score[{matchUser.Score}]]");

            return 0;
        }

        public bool CancelMatch(int userId, int battleType)
        {
            if (!_matchMap.ContainsKey(battleType))
            {
                return true;
            }
            if (!_matchNodeMap.ContainsKey(userId))
            {
                return true;
            }
            var node = _matchNodeMap[userId];
            var matchUser = node.Value;
            if (matchUser.BattleType != battleType)
            {
                return true;
            }

            // 从匹配队列移除
            var matchList = _matchMap[battleType];
            matchList.Remove(node);

            // 移除节点
            _matchNodeMap.Remove(userId);

            Logger.LogVerbose($"[Match][Cancel Match][User[{userId}] Battle[{battleType}] Score[{matchUser.Score}]]");

            return true;
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

                var battleType = item.Key;
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

                    var matchUser = node.Value;
                    if (node.Next != null && matchUser.IsSuitableOpponent(node.Next.Value, time))
                    {
                        var targetUser = node.Next.Value;

                        // 从匹配队列中移除
                        matchList.Remove(node.Next);
                        var nextNode = node.Next;
                        matchList.Remove(node);
                        node = nextNode;

                        // 移除匹配节点
                        if (_matchNodeMap.ContainsKey(matchUser.UserId))
                        {
                            _matchNodeMap.Remove(matchUser.UserId);
                        }
                        if (_matchNodeMap.ContainsKey(targetUser.UserId))
                        {
                            _matchNodeMap.Remove(targetUser.UserId);
                        }

                        _ = OnMatchSuccess(matchUser, targetUser);
                        continue;
                    }
                    node = node.Next;
                }
            }
        }

        // 匹配成功
        public async Task OnMatchSuccess(MatchUser user1, MatchUser user2)
        {
            // 没有空闲房间
            if (!HasIdleRoom())
            {
                Logger.LogWarning($"[Match][Match Failed][No Idle Room [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]");

                // 通知逻辑服匹配失败，没有空闲房间
                _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, false, string.Empty, (int)ErrorCode.NoIdleRoom, string.Empty, string.Empty);
                _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, false, string.Empty, (int)ErrorCode.NoIdleRoom, string.Empty, string.Empty);
                return;
            }

            // 分配房间，生成战斗Id
            var roomId = GetIdleRoom();
            var roomServerId = RoomService.GetRoomServerId(_matchServerConfig, roomId);
            var roomServerUrl = ConfigService.GetServerUrl(roomServerId);

            // 通知房间服房间用户信息
            var result = await M2R_OpenRoom(roomId, roomServerId, user1, user2);
            if (result == null)
            {
                Logger.LogWarning($"[Match][Match Failed][Room Server Invalid Room[{roomId}_{roomServerId}] [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]");

                // 通知逻辑服匹配失败，房间服务不可用
                _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, false, string.Empty, (int)ErrorCode.RoomServerInvalid, string.Empty, string.Empty);
                _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, false, string.Empty, (int)ErrorCode.RoomServerInvalid, string.Empty, string.Empty);
                return;
            }
            if (result.Code != ErrorCode.Success)
            {
                await OnMatchSuccess(user1, user2);
                return;
            }

            var battleId = result.Data.BattleId;
            var roomToken1 = result.Data.RoomTokens[0];
            var roomToken2 = result.Data.RoomTokens[1];

            Logger.LogInformation($"[Match][Match Success][Room[{roomId}] Battle[{battleId}] [{user1.UserId}_{user1.Score}] vs [{user2.UserId}_{user2.Score}]]");

            // 通知逻辑服匹配成功
            _ = M2L_NotifyMatchResult(user1.UserId, user1.ServerId, true, roomServerUrl, roomId, battleId, roomToken1);
            _ = M2L_NotifyMatchResult(user2.UserId, user2.ServerId, true, roomServerUrl, roomId, battleId, roomToken2);
        }

        // 通知战斗结果
        public void NotifyBattleResult(int roomId, int winPlayerId, int playerId1, int serverId1, int playerId2, int serverId2)
        {
            // 通知逻辑服战斗结果
            if (playerId1 > 0)
            {
                _ = M2L_NotifyBattleResult(playerId1, serverId1, winPlayerId);
            }
            if (playerId2 > 0)
            {
                _ = M2L_NotifyBattleResult(playerId2, serverId2, winPlayerId);
            }

            // 释放房间
            FreeRoom(roomId);
        }

        // 逻辑服，发起匹配
        public static async Task<ResultWithError<TStartMatchOutput>> L_StartMatch(int userId, int battleType, int areaId)
        {
            var result = new ResultWithError<TStartMatchOutput>()
            {
                Code = ErrorCode.Success,
                Data = new TStartMatchOutput()
            };

            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                result.Code = ErrorCode.InvalidParameter;
                return result;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match != null && match.MatchState != TMatchState.None)
            {
                // 已经在匹配了或战斗中
                result.Code = ErrorCode.AllreadyMatching + (int)match.MatchState - 1;
                return result;
            }

            var towerSet = CardService.GetBattleTowerSet(userId, battleType);
            if (towerSet == null)
            {
                // 找不到卡组数据
                result.Code = ErrorCode.DataNotFound;
                return result;
            }

            var currentHero = CardService.GetCurrentHero(userId, battleType);
            if (currentHero == null)
            {
                // 找不到卡组数据
                result.Code = ErrorCode.DataNotFound;
                return result;
            }

            var matchUser = new MatchUser()
            {
                UserId = userId,
                ServerId = user.ServerId,
                UserName = user.Name,
                UserLevel = user.UserLevel.Level,
                BattleType = battleType,
                Score = user.UserLevel.Exp,
                TowerSet = towerSet,
                Hero = TBattleHero.Build(userId, currentHero),
            };

            // 匹配服Id
            var matchServerId = GetMatchServerId(areaId);
            var matchStartResult = await L2M_StartMatch(matchUser, matchServerId);
            if (matchStartResult == null)
            {
                // 匹配服不可用
                result.Code = ErrorCode.MatchServerInvalid;
                return result;
            }
            result.Code = matchStartResult.Code;
            if (result.Code != ErrorCode.Success)
            {
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
            match.MatchState = TMatchState.Matching;
            match.MatchServerId = matchServerId;
            match.BattleType = battleType;
            match.RoomServerUrl = string.Empty;
            match.RoomId = 0;
            match.BattleId = string.Empty;
            match.RoomToken = string.Empty;
            TMatch.Cache.AddOrUpdate(match);

            result.Data.MatchServerId = matchServerId;
            result.Data.BattleType = battleType;
            result.Data.WaitTime = matchStartResult.Data.WaitTime;
            return result;
        }

        [Rpc]
        // 逻辑服--->匹配服，发起匹配
        public static async Task<ResultWithError<TStartMatchOutput>> L2M_StartMatch(MatchUser matchUser, int matchServerId)
        {
            if (matchUser == null || matchServerId == 0)
            {
                return null;
            }

            return await RpcProxy.RunAsync(typeof(MatchService), matchServerId, RpcProxy.BuildArgs(matchUser, matchServerId), async () =>
            {
                var result = new ResultWithError<TStartMatchOutput>()
                {
                    Data = new TStartMatchOutput()
                };

                // 加入匹配队列
                result.Data.WaitTime = await MatchService.INSTANCE.PostAsync<int>(() =>
                {
                    return MatchService.INSTANCE.StartMatch(matchUser);
                });

                return result;
            });
        }

        // 逻辑服，取消匹配
        public static async Task<ErrorCode> L_CancelMatch(int userId, int battleType, int matchServerId)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                return ErrorCode.InvalidParameter;
            }

            if (!IsMatchServer(matchServerId))
            {
                return ErrorCode.MatchServerInvalid;
            }

            var cancelResult = await L2M_CancelMatch(userId, battleType, matchServerId);
            if (cancelResult == null)
            {
                return ErrorCode.MatchServerInvalid;
            }
            if (cancelResult.Code != ErrorCode.Success)
            {
                return cancelResult.Code;
            }

            // 更新匹配状态
            var match = TMatch.Cache.FindKey(userId);
            if (match == null || match.MatchState != TMatchState.Matching)
            {
                // 当前未在匹配中，无法取消匹配
                return ErrorCode.NotMatching;
            }

            match.MatchState = TMatchState.None;
            match.MatchServerId = 0;
            TMatch.Cache.AddOrUpdate(match);

            return ErrorCode.Success;
        }

        [Rpc]
        // 逻辑服--->匹配服，取消匹配
        public static async Task<ResultWithError<int>> L2M_CancelMatch(int userId, int battleType, int matchServerId)
        {
            if (matchServerId == 0)
            {
                return null;
            }

            return await RpcProxy.RunAsync(typeof(MatchService), matchServerId, RpcProxy.BuildArgs(userId, battleType, matchServerId), async () =>
            {
                var result = new ResultWithError<int>();

                // 移除匹配队列
                var success = await MatchService.INSTANCE.PostAsync<bool>(() =>
                {
                    return MatchService.INSTANCE.CancelMatch(userId, battleType);
                });

                return result;
            });
        }

        // 逻辑服，通知匹配结果
        public static async Task<ErrorCode> L_NotifyMatchResult(int userId, bool isSuccess, string roomServerUrl, int roomId, string battleId, string roomToken)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                return ErrorCode.DataNotFound;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null)
            {
                return ErrorCode.DataNotFound;
            }

            if (isSuccess)
            {
                // 匹配成功
                match.MatchState = TMatchState.Battleing;
                match.RoomServerUrl = roomServerUrl;
                match.RoomId = roomId;
                match.BattleId = battleId;
                match.RoomToken = roomToken;
            }
            else
            {
                // 匹配失败，取消匹配
                match.MatchState = TMatchState.None;
            }
            TMatch.Cache.AddOrUpdate(match);

            // 广播给客户端匹配结果，匹配成功时客户端收到通知，直接连接房间服
            await BroadcastService.BroadcastAsync(userId, new BroadcastMatchResultDefinition(roomId, roomServerUrl, battleId, roomToken));

            return ErrorCode.Success;
        }

        [Rpc]
        // 匹配服--->逻辑服，通知匹配结果
        public static async Task<ResultWithError<int>> M2L_NotifyMatchResult(int userId, int serverId, bool isSuccess, string roomServerUrl, int roomId, string battleId, string roomToken)
        {
            return await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(userId, serverId, isSuccess, roomServerUrl, roomId, battleId, roomToken), async () =>
            {
                var result = new ResultWithError<int>();

                // 逻辑服，通知匹配结果
                result.Code = await L_NotifyMatchResult(userId, isSuccess, roomServerUrl, roomId, battleId, roomToken);

                return result;
            });
        }

        // 逻辑服，通知战斗结果
        public static async Task<ErrorCode> L_NotifyBattleResult(int userId, int winPlayerId)
        {
            var user = TUser.Cache.FindKey(userId);
            if (user == null)
            {
                return ErrorCode.DataNotFound;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null)
            {
                return ErrorCode.DataNotFound;
            }

            var battleType = match.BattleType;

            // 战斗结束
            match.MatchState = TMatchState.None;
            match.MatchServerId = 0;
            match.BattleType = 0;
            match.RoomServerUrl = string.Empty;
            match.RoomId = 0;
            match.BattleId = string.Empty;
            match.RoomToken = string.Empty;
            TMatch.Cache.AddOrUpdate(match);

            // 结算，winPlayerId等于0时房间异常关闭，未结算战斗
            if (winPlayerId != 0)
            {
                user = UserService.AddExp(userId, winPlayerId == userId ? 35 : -30);
            }

            // 广播给客户端匹配结果，匹配成功时客户端收到通知，直接连接房间服
            var settle = new TBattleSettle() { WinPlayerId = winPlayerId, UserLevel = user.UserLevel};
            await BroadcastService.BroadcastAsync(userId, new BroadcastBattleSettleDefinition(settle));

            return ErrorCode.Success;
        }

        [Rpc]
        // 匹配服--->房间服，通知房间服开设房间
        public static async Task<ResultWithError<RoomOpen>> M2R_OpenRoom(int roomId, int roomServerId, MatchUser user1, MatchUser user2)
        {
            return await RpcProxy.RunAsync(typeof(MatchService), roomServerId, RpcProxy.BuildArgs(roomId, roomServerId, user1, user2), async () =>
            {
                var result = new ResultWithError<RoomOpen>();

                // 房间服，开设房间
                result = await RoomService.INSTANCE.PostAsync<ResultWithError<RoomOpen>>(() =>
                {
                    return RoomService.INSTANCE.OpenRoom(roomId, user1.BattleType, user1, user2);
                });

                return result;
            });
        }

        [Rpc]
        // 匹配服--->逻辑服，通知战斗结果
        public static async Task<ResultWithError<int>> M2L_NotifyBattleResult(int userId, int serverId, int winPlayerId)
        {
            return await RpcProxy.RunAsync(typeof(MatchService), serverId, RpcProxy.BuildArgs(userId, serverId, winPlayerId), async () =>
            {
                var result = new ResultWithError<int>();

                // 逻辑服，通知匹配结果
                result.Code = await L_NotifyBattleResult(userId, winPlayerId);

                return result;
            });
        }

        // 玩家断开连接
        public static async void L_OnServerDisconnected(int userId)
        {
            // 只处理逻辑服
            if (userId == 0 || !Host.Role.HasRole(ServerRole.Logic))
            {
                return;
            }

            var match = TMatch.Cache.FindKey(userId);
            if (match == null || match.MatchState != TMatchState.Matching)
            {
                return;
            }

            // 匹配中的玩家，与服务器断开连接后，取消匹配
            await L_CancelMatch(userId, match.BattleType, match.MatchServerId);
        }

        public static int GetMatchServerId(int areaId)
        {
            var config = ConfigManager.LoadConfig<MatchConfig>();
            var matchServerConfig = config.GetMatchServerConfigByAreaId(areaId);
            if (matchServerConfig == null)
            {
                return 0;
            }
            return matchServerConfig.ServerId;
        }

        public static bool IsMatchServer(int matchServerId)
        {
            var config = ConfigManager.LoadConfig<MatchConfig>();
            var matchServerConfig = config.GetMatchServerConfig(matchServerId);
            return matchServerConfig != null;
        }
    }
}
