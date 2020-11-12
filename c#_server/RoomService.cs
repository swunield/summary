using Feelingtouch.Core;
using Feelingtouch.Core.Codec.Json;
using Feelingtouch.Core.Config;
using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Feelingtouch.Core.Util.Thread;
using Game.Config;
using Game.Model;
using Game.Model.Config;
using Game.Utils;
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;

namespace Game.Service
{
    public class RoomService : ThreadContext
    {
        private static RoomService _instance = null;
        public static RoomService INSTANCE
        {
            get
            {
                if (_instance == null)
                {
                    _instance = new RoomService();
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
                    _timer = new FixedTimer(OnTimerCallback, "RoomService", 0, ConfigConstants.BATTLE_FRAME_TIME, true);
                }
                return _timer;
            }
        }

        private static void OnTimerCallback(object state, long delta, long time)
        {
            RoomService.INSTANCE.Update(delta, time);
        }

        // 房间最大等待时间，1分钟
        private static readonly long ROOM_WAITING_TIME_MAX = 1 * 60 * 1000;

        // 房间有用户连入后最大等待时间，10秒
        private static readonly long ROOM_USER_WAITING_TIME_MAX = 10 * 1000;

        // 战斗无操作等待时间，3分钟
        private static readonly long BATTLE_NO_OPERATION_WAITING_TIME_MAX = 3 * 60 * 1000;

        // 战斗结算等待时间，1秒
        private static readonly long BATTLE_SETTLE_WAITING_TIME_MAX = 1000;

        // 房间刷新间隔
        private static readonly long ROOM_UPDATE_INTERVAL = ConfigConstants.BATTLE_FRAME_TIME;

        // 房间刷新间隔计时
        private long _roomUpdateTime = 0;

        // 房间时间
        private long _roomTime = 0;

        // 对应匹配服务器配置
        private MatchServerConfig _matchServerConfig = null;

        // 所有房间
        private Dictionary<int, TRoom> _roomMap = new Dictionary<int, TRoom>();
        // 用户房间记录
        private Dictionary<int, TRoom> _userRoomMap = new Dictionary<int, TRoom>();

        public static void TryStart()
        {
            if (!Host.Role.HasRole(ServerRole.Room))
            {
                return;
            }

            RoomService.INSTANCE.Start();
        }

        private void Start()
        {
            // 启动计时器
            timer.Start();
            _roomTime = GetTime();

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

            // 房间更新
            _roomUpdateTime += delta;
            while (_roomUpdateTime >= ROOM_UPDATE_INTERVAL)
            {
                _roomUpdateTime -= ROOM_UPDATE_INTERVAL;
                _roomTime += ROOM_UPDATE_INTERVAL;

                foreach (var item in _roomMap)
                {
                    var room = item.Value;
                    UpdateRoom(room, ROOM_UPDATE_INTERVAL, _roomTime);
                }
            }
        }

        // 单个房间更新
        private void UpdateRoom(TRoom room, long delta, long time)
        {
            if (room == null)
            {
                return;
            }

            switch (room.RoomState)
            {
                // 空闲中
                case TRoomState.Idle:
                    {
                        return;
                    }
                    break;
                // 等待玩家连入
                case TRoomState.Waiting:
                    {
                        int readyCount = 0;
                        long readyTime = 0;
                        for (int i = 0; i < room.Users.Count; i++)
                        {
                            if (room.Users[i].ReadyTime != 0)
                            {
                                readyCount++;
                                readyTime = room.Users[i].ReadyTime;
                            }
                        }
                        if (readyCount == 0 && time - room.OpenRoomTime >= ROOM_WAITING_TIME_MAX)
                        {
                            // 开房1分钟后，一直无玩家进入，关闭房间
                            CloseRoom(room);
                            break;
                        }
                        if (readyCount == room.GetRealUserCount())
                        {
                            // 玩家全部进入
                            OnRoomAllUserReady(room);
                            break;
                        }
                        if (GetTime() - readyTime >= ROOM_USER_WAITING_TIME_MAX)
                        {
                            // 部分玩家连入，等待10秒后，强制开始战斗
                            OnRoomAllUserReady(room);
                        }
                    }
                    break;
                // 战斗中
                case TRoomState.Battleing:
                    {
                        UpdateBattle(room, delta, time);
                    }
                    break;
            }
        }

        // 单场战斗刷新
        private void UpdateBattle(TRoom room, long delta, long time)
        {
            if (room == null || room.RoomState != TRoomState.Battleing)
            {
                return;
            }

            // 结算校验
            CheckBattleEnd(room, time);        
            
            if (room.RoomState != TRoomState.Battleing)
            {
                return;
            }

            // 校验战斗是否无操作超时
            if (time - room.LastOperationTime >= BATTLE_NO_OPERATION_WAITING_TIME_MAX)
            {
                CheckBattleEnd(room, time, true);
                return;
            }

            var record = room.Record;

            record.BattleTime += delta;
            if (record.BattleTime < 0)
            {
                // 战斗缓冲中
                return;
            }

            if (record.BattleTime == 0)
            {
                room.PendingFrameCount = ConfigConstants.BATTLE_FRAME_PACKAGE_LENGTH - ConfigConstants.BATTLE_SERVER_LEAD_FRAME_COUNT;
                record.FrameCount = 0;

                // 广播通知玩家战斗开始
                BroadcastRoomBattleFramePackage(room);
                Logger.LogInformation($"[Room][Battle Begin][Broadcast To Users Room[{room.RoomId}] Battle[{record.BattleId}]]");
                return;
            }

            record.FrameCount++;
            room.PendingFrameCount++;

            // 给玩家广播战斗包
            if (room.PendingFrameCount == ConfigConstants.BATTLE_FRAME_PACKAGE_LENGTH)
            {
                room.PendingFrameCount = 0;
                BroadcastRoomBattleFramePackage(room);
            }
        }

        private bool InitRoom()
        {
            var config = ConfigManager.LoadConfig<MatchConfig>();
            _matchServerConfig = config.GetMatchServerConfigByRoomId(Host.ServerId);
            if (_matchServerConfig == null)
            {
                Logger.LogError($"[Room][Room Init Failed][Can not find MatchServerConfig [{Host.ServerId}]]");
                return false;
            }

            var allRoomIds = GetRoomServerAllRoomId(_matchServerConfig, Host.ServerId);
            if (allRoomIds == null)
            {
                Logger.LogError($"[Room][Room Init Failed][Empty Room Ids [{Host.ServerId}]]");
                return false;
            }

            // 初始化所有房间
            foreach (var roomId in allRoomIds)
            {
                var room = new TRoom()
                {
                    RoomId = roomId,
                    RoomState = TRoomState.Idle,
                    Users = null,
                    Record = null,
                    PendingFrameList = null,
                    PendingFrameCount = 0,
                };

                _roomMap.Add(roomId, room);
            }

            Logger.LogInformation($"[Room][Room Init Success][Server[{Host.ServerId}] Count[{_roomMap.Count}]]");

            return true;
        }

        // 房间服，开设房间
        public ResultWithError<RoomOpen> OpenRoom(int roomId, int battleType, MatchUser user1, MatchUser user2)
        {
            var result = new ResultWithError<RoomOpen>();
            if (user1 == null || user2 == null)
            {
                result.Code = ErrorCode.InvalidRoomUser;
                return result;
            }

            var room = GetRoom(roomId);
            if (room == null)
            {
                // 房间未找到
                Logger.LogWarning($"[Room][Open Room Failed][Room Not Found Room[{roomId}]] Server[{Host.ServerId}]");
                result.Code = ErrorCode.RoomNotFound;
                return result;
            }
            if (room.RoomState != TRoomState.Idle)
            {
                // 房间占用中
                Logger.LogWarning($"[Room][Open Room Failed][Room Busy Room[{roomId}]] Server[{Host.ServerId}]");
                result.Code = ErrorCode.RoomBusy;
                return result;
            }

            var battleId = Guid.NewGuid().ToString("N");

            // 等待玩家连接
            room.RoomState = TRoomState.Waiting;
            room.OpenRoomTime = GetTime();
            room.LastOperationTime = 0;

            // 保存玩家
            room.Users = new List<TRoomUser>();
            room.Users.Add(new TRoomUser() { UserId = user1.UserId, ReadyTime = 0, Token = RandomExtensions.Instance.RandomString(8), Result = null, ResultTime = 0 });
            room.Users.Add(new TRoomUser() { UserId = user2.UserId, ReadyTime = 0, Token = RandomExtensions.Instance.RandomString(8), Result = null, ResultTime = 0 });

            // 战斗信息
            room.Record = new TBattleRecord()
            {
                BattleId = battleId,
                BattleVersion = 1,
                BattleSeed = BattleService.GenerateSeed(),
                BattleType = battleType,
                PlayerList = new List<TBattlePlayer>(),
                FrameCount = -1,
                IsRealTime = true,
                BattleResult = null,
            };
            room.Record.PlayerList.Add(new TBattlePlayer()
            {
                PlayerId = user1.UserId,
                PlayerName = user1.UserName,
                PlayerLevel = user1.UserLevel,
                ServerId = user1.ServerId,
                PlayerSeed = BattleService.GenerateSeed(),
                TowerPool = user1.TowerSet.TowerPool,
                Hero = user1.Hero,
                PlayerFrame = new TBattlePlayerFrame() { FrameList = new List<TBattleFrame>() },
            });
            room.Record.PlayerList.Add(new TBattlePlayer()
            {
                PlayerId = user2.UserId,
                PlayerName = user2.UserName,
                PlayerLevel = user2.UserLevel,
                ServerId = user2.ServerId,
                PlayerSeed = BattleService.GenerateSeed(),
                TowerPool = user2.TowerSet.TowerPool,
                Hero = user2.Hero,
                PlayerFrame = new TBattlePlayerFrame() { FrameList = new List<TBattleFrame>() },
            });

            // 战斗帧缓存
            room.PendingFrameList = new List<TBattleFrameDetail>();
            room.PendingFrameCount = 0;

            // 记录玩家房间
            _userRoomMap[user1.UserId] = room;
            _userRoomMap[user2.UserId] = room;

            result.Data = new RoomOpen()
            {
                BattleId = battleId,
                RoomTokens = new List<string>() { room.Users[0].Token, room.Users[1].Token },
            };

            Logger.LogInformation($"[Room][Open Room Success][Room[{roomId}] BattleType[{battleType}] User1[{user1.UserId}] User2[{user2.UserId}]]");

            return result;
        }

        // 房间服，关闭房间
        public void CloseRoom(TRoom room)
        {
            if (room == null)
            {
                return;
            }

            // 通知匹配服战斗结果
            var player1 = room.Record.PlayerList[0];
            var player2 = room.Record.PlayerList[1];
            var winPlayerId = room.Record.BattleResult == null ? 0 : room.Record.BattleResult.WinPlayerId;
            _ = R2M_NotifyBattleResult(_matchServerConfig.ServerId, room.RoomId, winPlayerId, player1.PlayerId, player1.ServerId, player2.PlayerId, player2.ServerId);

            // 移除房间记录
            for (int i = 0; i < room.Users.Count; i++)
            {
                var userId = room.Users[i].UserId;
                if (_userRoomMap.ContainsKey(userId))
                {
                    _userRoomMap.Remove(userId);
                }
            }

            room.RoomState = TRoomState.Idle;
            room.OpenRoomTime = 0;
            room.Users = null;
            room.Record = null;
            room.PendingFrameList = null;
            room.LastOperationTime = 0;
        }

        // 玩家都准备好
        public void OnRoomAllUserReady(TRoom room)
        {
            if (room == null)
            {
                return;
            }

            room.RoomState = TRoomState.Battleing;
            room.LastOperationTime = GetTime();
            // 延迟1秒开始战斗
            room.Record.BattleTime = -ConfigConstants.BATTLE_FPS * ROOM_UPDATE_INTERVAL;

            Logger.LogInformation($"[Room][Room Ready][Room[{room.RoomId}]]");
        }

        // 玩家断开连接
        public void OnRoomUserDisconnected(int userId)
        {
            var room = GetRoomByUserId(userId);
            if (room == null)
            {
                return;
            }

            var roomUser = room.GetRoomUser(userId);
            if (roomUser == null)
            {
                return;
            }

            roomUser.ReadyTime = 0;

            Logger.LogInformation($"[Room][Room User Disconnected][Room[{room.RoomId}] User[{userId}]]");
        }

        // 广播房间战斗帧包，只有真人对战才需要广播
        public void BroadcastRoomBattleFramePackage(TRoom room)
        {
            if (room == null || !room.Record.IsRealTime)
            {
                return;
            }

            var package = new BroadcastBattleFramePackageDefinition(room.Record.FrameCount, room.PendingFrameList.Count == 0 ? null : room.PendingFrameList);
            for (int i = 0; i < room.Users.Count; i++)
            {
                if (room.Users[i].ReadyTime != 0 && room.Users[i].Result == null)
                {
                    BroadcastService.BroadcastAsync(room.Users[i].UserId, package);
                }
            }
            room.PendingFrameList.Clear();
        }

        // 执行战斗操作
        public ErrorCode ExecBattleOperation(int userId, int frameCount, int frameType, string param1, string param2, int point, int frameId)
        {
            var room = GetRoomByUserId(userId);
            if (room == null)
            {
                return ErrorCode.RoomNotFound;
            }

            var roomUser = room.GetRoomUser(userId);
            if (roomUser == null)
            {
                return ErrorCode.InvalidRoomUser;
            }

            // 已上报战斗结果，无法继续上传战斗帧
            if (roomUser.Result != null)
            {
                return ErrorCode.AllreadySendBattleResult;
            }

            var frame = new TBattleFrame()
            {
                FrameCount = room.Record.IsRealTime ? room.Record.FrameCount : frameCount,
                FrameType = frameType,
                Param1 = param1,
                Param2 = param2,
                Point = point,
                FrameId = frameId,
            };
            if (room.Record.IsRealTime && room.PendingFrameCount == 0)
            {
                frame.FrameCount = room.Record.FrameCount + 1;
            }
            if (frame.FrameCount <= 0)
            {
                frame.FrameCount = 1;
            }

            // 真人PK，插入缓存队列
            if (room.Record.IsRealTime)
            {
                var frameDetail = new TBattleFrameDetail()
                {
                    PlayerId = userId,
                    Frame = frame,
                };
                room.PendingFrameList.Add(frameDetail);

                // 投降帧，立即广播
                if (frameType == (int)BattleFrameType.SURRENDER)
                {
                    room.PendingFrameCount = ConfigConstants.BATTLE_FRAME_PACKAGE_LENGTH - 1;
                }
            }

            // 插入战斗记录
            room.Record.AddBattleFrame(userId, frame);

            // 记录操作时间
            room.LastOperationTime = GetTime();

            return ErrorCode.Success;
        }

        // 玩家通知战斗结束
        public async Task<ErrorCode> OnPlayerBattleEnd(int userId, int winPlayerId, int frameCount, string battleId)
        {
            var room = GetRoomByUserId(userId);
            if (room == null)
            {
                // 房间不存在了，有可能已经结算完了
                var battleRecord = TBattleRecord.Cache.FindKey(battleId);
                if (battleRecord != null && battleRecord.BattleResult != null)
                {
                    return ErrorCode.Success;
                }

                // 找不到战斗，参数错误
                return ErrorCode.InvalidParameter;
            }

            var roomUser = room.GetRoomUser(userId);
            if (roomUser == null)
            {
                return ErrorCode.InvalidRoomUser;
            }
            if (roomUser.Result != null)
            {
                return ErrorCode.AllreadySendBattleResult;
            }

            room.LastOperationTime = GetTime();

            if (room.Record.IsRealTime)
            {
                // 真人PK，保存用户上报的结果，并记录时间，超过1秒未接收到其他玩家上报结果的话，尝试结算
                roomUser.Result = new TBattleResult()
                {
                    WinPlayerId = winPlayerId,
                    FrameCount = frameCount,
                };
                roomUser.ResultTime = GetTime();
            }
            else
            {
                // 机器人，直接结算
                room.Record.BattleResult = await BattleService.SimulateBattle(room.Record);
                // 战斗结算
                ExecBattleEnd(room, BattleEndReason.NoRealTime);
            }

            return ErrorCode.Success;
        }

        // 非真人PK，无需校验战斗结束，战斗结束以玩家上报战斗结束协议为准
        public async void CheckBattleEnd(TRoom room, long time, bool forceEnd = false)
        {
            if (room == null || room.Record.IsSimulating || !room.Record.IsRealTime)
            {
                return;
            }

            var resultCount = 0;
            var resultOverTimeCount = 0;
            TRoomUser overTimeUser = null;
            int overTimeUserIndex = 0;
            for (int i = 0; i < room.Users.Count; i++)
            {
                var roomUser = room.Users[i];
                if (roomUser.Result != null)
                {
                    resultCount++;
                }
                if (roomUser.ResultTime != 0 && time - roomUser.ResultTime >= BATTLE_SETTLE_WAITING_TIME_MAX)
                {
                    resultOverTimeCount++;
                    overTimeUser = roomUser;
                    overTimeUserIndex = i;
                }
            }
            // 玩家都上报了结果，对比Result看是否一致，若一致，直接结算，若不一致，需要模拟一次战斗，以模拟结果为准
            if (resultCount == room.Users.Count)
            {
                // 结果一致
                if (room.IsAllUserSameResult())
                {
                    room.Record.BattleResult = room.Users[0].Result;
                    // 战斗结算
                    ExecBattleEnd(room, BattleEndReason.TwoSameResult);

                    return;
                }

                // 结果不一致，模拟战斗
                room.Record.IsSimulating = true;
                room.Record.BattleResult = await BattleService.SimulateBattle(room.Record);
                // 战斗结算
                ExecBattleEnd(room, BattleEndReason.TwoDiffResult);

                return;
            }
            if (resultOverTimeCount == 1)
            {
                // 结果超时，尝试结算
                room.Record.MaxFrameCount = overTimeUser.Result.FrameCount;
                room.Record.IsSimulating = true;
                var result = await BattleService.SimulateBattle(room.Record);
                if (result.IsSameResult(overTimeUser.Result))
                {
                    room.Record.BattleResult = result;
                    // 战斗结算
                    ExecBattleEnd(room, BattleEndReason.OneSameResult);

                    return;
                }
                // 结算结果跟玩家上报不一致，玩家作弊，直接判定另个玩家胜利
                room.Record.BattleResult = new TBattleResult()
                {
                    WinPlayerId = room.Users[(overTimeUserIndex + 1) % room.Users.Count].UserId,
                    FrameCount = overTimeUser.Result.FrameCount,
                };
                // 战斗结算
                ExecBattleEnd(room, BattleEndReason.OneDiffResult);

                return;
            }
            if (forceEnd)
            {
                room.Record.IsSimulating = true;
                room.Record.BattleResult = await BattleService.SimulateBattle(room.Record);
                // 战斗结算
                ExecBattleEnd(room, BattleEndReason.NoOpOverTime);

                return;
            }
        }

        // 战斗结算
        public void ExecBattleEnd(TRoom room, BattleEndReason reason)
        {
            if (room == null)
            {
                return;
            }

            Logger.LogInformation($"[Room][Battle End][ Room[{room.RoomId}] EndReason[{reason.ToString()}] Result[{room.Record.BattleResult.SerializeJson().ToFormatSafeString()}]]");

            // 保存战斗录像
            room.Record.EndReason = reason;
            TBattleRecord.Cache.AddOrUpdate(room.Record);

            // 关闭房间，并通知匹配服战斗结果
            CloseRoom(room);
        }

        public static int GetRoomServerId(MatchServerConfig config, int roomId)
        {
            if (config == null || config.RoomServers.Length == 0)
            {
                return 0;
            }

            int index = (roomId - 1) % config.RoomServers.Length;
            int roomServerId = config.RoomServers[index];
            return roomServerId;
        }

        public static List<int> GetRoomServerAllRoomId(MatchServerConfig config, int roomServerId)
        {
            if (config == null || config.RoomServers.Length == 0)
            {
                return null;
            }

            var index = -1;
            for (int i = 0; i < config.RoomServers.Length; i++)
            {
                if (config.RoomServers[i] == roomServerId)
                {
                    index = i;
                    break;
                }
            }
            if (index == -1)
            {
                return null;
            }

            var allRooms = new List<int>();
            for (int i = 0; i < config.RoomCount; i++)
            {
                var roomId = i + 1;
                var serverId = GetRoomServerId(config, roomId);
                if (serverId == roomServerId)
                {
                    allRooms.Add(roomId);
                }
            }
            return allRooms;
        }

        public TRoom GetRoom(int roomId)
        {
            if (!_roomMap.ContainsKey(roomId))
            {
                return null;
            }
            return _roomMap[roomId];
        }

        public TRoom GetRoomByUserId(int userId)
        {
            if (!_userRoomMap.ContainsKey(userId))
            {
                return null;
            }
            return _userRoomMap[userId];
        }

        public long GetTime()
        {
            return timer.Time;
        }

        // 房间服，玩家断开连接
        public static void R_OnServerDisconnected(int userId)
        {
            // 只处理逻辑服
            if (userId == 0 || !Host.Role.HasRole(ServerRole.Room))
            {
                return;
            }

            RoomService.INSTANCE.Post(() => {
                RoomService.INSTANCE.OnRoomUserDisconnected(userId);
            });
        }

        [Rpc]
        // 房间服--->匹配服，通知匹配服战斗结果，标记房间空闲
        public static async Task<ErrorCode> R2M_NotifyBattleResult(int matchServerId, int roomId, int winPlayerId, int playerId1, int serverId1, int playerId2, int serverId2)
        {
            return await RpcProxy.RunAsync(typeof(RoomService), matchServerId, RpcProxy.BuildArgs(matchServerId, roomId, winPlayerId, playerId1, serverId1, playerId2, serverId2), async () =>
            {
                return await MatchService.INSTANCE.PostAsync(() =>
                {
                    MatchService.INSTANCE.NotifyBattleResult(roomId, winPlayerId, playerId1, serverId1, playerId2, serverId2);
                    return ErrorCode.Success;
                });
            });
        }
    }
}
