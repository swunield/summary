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
using Game.Model.Log;
using Game.Model.Stat;
using Game.Utils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Game.Service
{
    /// <summary>
    /// 房间服务
    /// </summary>
    public class RoomService : ThreadContext
    {
        private static ILogger Logger = LoggerManager.Load<RoomService>();

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

        // 战斗快照启用时间，5秒
        private static readonly int BATTLE_SNAPSHOT_MIN_TIME = 5000;

        // 房间刷新间隔
        private static readonly long ROOM_UPDATE_INTERVAL = ConfigConstants.BATTLE_FRAME_TIME;

        // 战斗开始延迟
        private static readonly long BATTLE_BEGIN_DELAY = 3000;

        // 房间刷新间隔计时
        private long _roomUpdateTime = 0;

        // 房间时间
        private long _roomTime = 0;

        // 对应匹配服务器配置
        private MatchServerConfig _matchServerConfig = null;
        private int _areaId = 0;

        // 所有房间
        private Dictionary<int, Room> _roomMap = new Dictionary<int, Room>();
        // 用户房间记录
        private Dictionary<int, Room> _userRoomMap = new Dictionary<int, Room>();

        // 实时统计
        private RTRoom _rtRoom = new RTRoom();

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

            //开始结算服务
            RoomSettleService.TryStart();

            // 启动线程
            this.StartThreadContext();

            // 开始统计
            StartStat();
        }

        private void Update(long delta, long time)
        {
            // 实时统计
            var commit = _rtRoom.TryCommitStart(time);

            // 线程更新
            this.ThreadContextUpdate(false);

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

            // 实时统计
            _rtRoom.TryCommitEnd(time, commit);
        }

        // 单个房间更新
        private void UpdateRoom(Room room, long delta, long time)
        {
            if (room == null) return;

            switch (room.State)
            {
                // 空闲
                case RoomState.Idle:
                    return;
                // 战斗中
                case RoomState.Battle:
                    UpdateBattle(room, delta, time);
                    break;
                // 暂停
                case RoomState.Pause:
                    room.UnPause(delta);
                    return;
                // 准备
                case RoomState.Prepare:
                    {
                        var ready = true;
                        foreach (var user in room.Users)
                        {
                            //跳过机器人
                            if (user.IsRobot) continue;
                            //玩家准备就绪
                            if (user.IsConnected)
                            {
                                //就绪超时, 强制开始
                                if ((GetTime() >= (user.ConnectTime + ROOM_USER_WAITING_TIME_MAX)))
                                {
                                    ready = true;
                                    break;
                                }
                            }
                            else
                            {
                                ready = false;
                            }
                        }
                        if (ready)
                        {
                            room.BattleStartTime = DateTime.UtcNow;
                            room.State = RoomState.Battle;
                            room.UpdateTime = GetTime();
                            // 延迟1秒开始战斗
                            room.Record.BattleTime = -BATTLE_BEGIN_DELAY;

                            Logger.LogInformation($"Room[{room.RoomId}] Ready");
                        }
                        //房间准备超时
                        else if (time >= (room.PrepareTime + ROOM_WAITING_TIME_MAX))
                        {
                            //通知匹配服房间准备超时
                            var roomSettleData = new RoomSettleData(room, true);
                            _ = MatchService.R2M_NotifySettleResult(_matchServerConfig.ServerId, roomSettleData);
                            CloseRoom(room);
                        }
                    }
                    break;
            }
        }

        // 单场战斗刷新
        private void UpdateBattle(Room room, long delta, long time)
        {
            if (room == null || room.State != RoomState.Battle)
            {
                return;
            }

            //房间是否进入结算
            if (RoomSettleService.SettleRoom(room, time)) return;

            var record = room.Record;

            record.BattleTime += delta;
            if (record.BattleTime < 0)
            {
                // 战斗缓冲中
                return;
            }

            if (record.BattleTime == 0)
            {
                room.BattleFrame = 0;
                room.PendFrame = room.FramePackageLength - ConfigConstants.BATTLE_SERVER_LEAD_FRAME_COUNT;
                record.FrameCount = 0;
                // 广播通知玩家战斗开始
                BroadcastRoomBattleFramePackage(room);
                Logger.LogDebug($"[Room-{room.RoomId}][Battle Begin][Broadcast To Users Battle[{record.BattleId}]]");
                return;
            }

            // 帧数+1
            room.BattleFrame++;
            room.PendFrame++;

            // 给玩家广播战斗包
            if (room.PendFrame == room.FramePackageLength)
            {
                record.FrameCount = room.BattleFrame;
                room.LastPackageBattleFrame = room.BattleFrame;
                room.PendFrame = 0;
                BroadcastRoomBattleFramePackage(room);
            }
        }

        private bool InitRoom()
        {
            var config = ConfigService.MatchConfig.Value;
            _matchServerConfig = config.GetMatchServerConfigByRoomServerId(Host.ServerId, out int areaId);
            if (_matchServerConfig == null)
            {
                Logger.LogError($"[Room][Init Room][Failed][Match Server Config Is Invalid [{Host.ServerId}]]");
                return false;
            }

            _areaId = areaId;

            var allRoomIds = GetRoomServerAllRoomId(_matchServerConfig, Host.ServerId);
            if (allRoomIds == null)
            {
                Logger.LogError($"[Room][Init Room][Failed][Empty Room Id List [{Host.ServerId}]]");
                return false;
            }

            // 初始化所有房间
            foreach (var roomId in allRoomIds)
            {
                var room = new Room(roomId);
                _roomMap.Add(roomId, room);
            }

            Logger.LogDebug($"[Room][Init Room][Success][Server[{Host.ServerId}] RoomCount[{_roomMap.Count}]]");

            return true;
        }

        /// <summary>
        /// 准备房间 - 远程
        /// </summary>
        [Rpc(RetryTimes = 1)]
        public static async Task<ResultWithError<RoomPrepareInfo>> M2R_PrepareRoom(int serverId, int roomId, List<MatchUser> users, bool isManual = false)
        {
            return await RpcProxy.RunAsync(typeof(RoomService), serverId, RpcProxy.BuildArgs(serverId, roomId, users, isManual),
                async () => await INSTANCE.PostAsync(() => INSTANCE.PrepareRoom(roomId, users, isManual))
            );
        }

        /// <summary>
        /// 准备房间 - 本地
        /// </summary>
        public ResultWithError<RoomPrepareInfo> PrepareRoom(int roomId, List<MatchUser> users, bool isManual = false)
        {
            var result = new ResultWithError<RoomPrepareInfo>();
            if (users == null || users.Count == 0)
            {
                Logger.LogError($"[Room-{roomId}][Prepare Room][Failed][Users is Empty [{users?.Count}]]");
                result.Code = ErrorCode.InvalidRoomUser;
                return result;
            }
            //房间未找到
            var room = GetRoom(roomId);
            if (room == null)
            {
                Logger.LogError($"[Room-{roomId}][Prepare Room][Failed][Room Not Found]");
                result.Code = ErrorCode.RoomNotFound;
                return result;
            }
            //房间未空闲
            if (room.State != RoomState.Idle)
            {
                Logger.LogError($"[Room-{roomId}][Prepare Room][Failed][Room Is Busy]");
                result.Code = ErrorCode.RoomBusy;
                return result;
            }
            //房间准备
            room.Prepare(_areaId, GetTime(), users, isManual);

            // 记录玩家房间
            foreach (var user in users)
            {
                _userRoomMap[user.UserId] = room;
            }

            //返回准备信息
            result.Data = room.PrepareInfo;

            Logger.LogDebug($"[Room-{roomId}][Prepare Room][Success][Users[{users[0].UserId} - {users[1].UserId}]]");

            return result;
        }

        // 房间服，关闭房间
        public void CloseRoom(Room room)
        {
            if (room == null)
            {
                return;
            }

            // 移除房间记录
            foreach (var u in room.Users)
            {
                if (_userRoomMap.ContainsKey(u.UserId)) _userRoomMap.Remove(u.UserId);
            }

            room.Close();
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

            roomUser.ConnectTime = -GetTime();
            Logger.LogDebug($"[Room][Room User Disconnected][Success][Room[{room.RoomId}] User[{userId}]]");
        }

        // 广播房间战斗帧包，只有真人对战才需要广播
        public void BroadcastRoomBattleFramePackage(Room room)
        {
            if (room == null)
            {
                return;
            }

            var pendingList = new List<TBattleFrameDetail>(room.PendingList);
            room.PendingList.Clear();
            
            var package = new BroadcastBattleFramePackageDefinition(room.Record.FrameCount, pendingList.Count == 0 ? null : pendingList);
            for (int i = 0; i < room.Users.Count; i++)
            {
                var user = room.Users[i];
                if (user.IsConnected && !user.IsSnapshoting && user.ReportResult == null)
                {
                    BroadcastService.BroadcastAsync(room.Users[i].UserId, package);
                }
            }
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
            if (roomUser.ReportResult != null)
            {
                return ErrorCode.AllreadySendBattleResult;
            }

            // 回合上报
            if (frameType == BattleFrameType.REPORT.ToInt())
            {
                if (room.Record.BattleType == BattleType.COOP.ToInt())
                {
                    if (roomUser.CoopReport == null)
                    {
                        roomUser.CoopReport = new RoomUserCoopReport();
                    }
                    roomUser.CoopReport.FrameCount = room.Record.IsRealTime ? room.BattleFrame : frameCount;
                    roomUser.CoopReport.RoundNum = param1.ToInt();
                }
                return ErrorCode.Success;
            }

            var frame = new TBattleFrame()
            {
                FrameCount = room.Record.IsRealTime ? room.BattleFrame : frameCount,
                FrameType = frameType,
                Param1 = param1,
                Param2 = param2,
                Point = point,
                FrameId = frameId,
            };
            if (room.Record.IsRealTime && (room.PendFrame == 0 || room.State == RoomState.Pause))
            {
                frame.FrameCount = room.BattleFrame + 1;
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
                room.PendingList.Add(frameDetail);

                // 非投降帧，将帧数提前至帧包开始
                if (frameType != BattleFrameType.SURRENDER.ToInt())
                {
                    frameDetail.Frame.FrameCount = room.LastPackageBattleFrame + 1;
                }

                // 立即广播
                room.PendFrame = room.FramePackageLength - 1;
            }

            // 插入战斗记录
            room.Record.AddBattleFrame(userId, frame);

            // 记录操作时间
            room.UpdateTime = GetTime();

            return ErrorCode.Success;
        }

        // 玩家通知战斗结束
        public async Task<ErrorCode> OnPlayerBattleEnd(int userId, int winPlayerId, int roundNum, int frameCount, string battleId, bool isPoorNet)
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
            if (roomUser.ReportResult != null)
            {
                return ErrorCode.AllreadySendBattleResult;
            }

            room.UpdateTime = GetTime();

            //保存用户上报的结果，并记录时间，超过1秒未接收到其他玩家上报结果的话，尝试结算
            roomUser.ReportResult = new TBattleResult(winPlayerId, frameCount, roundNum, isPoorNet);
            roomUser.ReportTime = GetTime();

            //Logger.LogDebug($"User[{userId}]: Report room[{room.RoomId}]win[{winPlayerId}]round[{roundNum}]");
            Logger.LogDebug($"房间[{room.RoomId}]玩家[{userId}]上报战斗结果 -> 胜者Id[{winPlayerId}]回合[{roundNum}]");
            return ErrorCode.Success;
        }

        //战斗快照
        public ResultWithError<bool> TryRequestSnapShot(Room room, RoomUser user)
        {
            var result = new ResultWithError<bool>
            {
                Data = false,
                Code = ErrorCode.Success
            };

            // 非实时战斗，或者，战斗持续时间低于5秒不启用快照
            if (!room.Record.IsRealTime || room.BattleFrame <= BATTLE_SNAPSHOT_MIN_TIME / ConfigConstants.BATTLE_FRAME_TIME)
            {
                return result;
            }

            // 玩家重连，战斗暂停3秒，并从对方玩家获取快照
            var opponentUser = room.Users.FirstOrDefault(u => u.UserId != user.UserId);
            if (opponentUser == null)
            {
                // 找不到对手
                //result.Code = ErrorCode.InvalidRoomUser;
                return result;
            }
            if (opponentUser.IsDisconnected)
            {
                // TODO, 机器人或者对手也掉线，需要从哪里获取快照，等待磊哥实现
                // 两个玩家都掉线了，强制结束战斗
                // ExecBattleEnd(room, BattleEndReason.TwoDisconnect);
                //result.Code = ErrorCode.DataNotFound;
                Logger.LogDebug($"User[{user.UserId}]: Opponent[{opponentUser.UserId}] is disconnected too.");
                return result;
            }

            // 标记房间上次操作时间
            room.UpdateTime = GetTime();
            // 标记等待快照
            user.IsSnapshoting = true;
            // 广播给对手，请求快照
            _ = BroadcastService.BroadcastAsync(opponentUser.UserId, new BroadcastRequestSnapshotDefinition(new TEmpty()));

            result.Data = true;
            return result;
        }

        public async Task<bool> SendSnapShot(Room room, RoomUser user, TSSnapShot tSnapShot)
        {
            if (!room.Record.IsRealTime)
            {
                room.Record.SnapShot = tSnapShot;
                return true;
            }

            // 房间战斗暂停3秒
            room.Pause(ConfigConstants.BATTLE_SNAPSHOT_PAUSE_TIME);

            // 标记快照发送
            user.IsSnapshoting = false;

            // 广播玩家战斗信息，带快照
            var record = room.Record;
            record.SnapShot = tSnapShot;
            await BroadcastService.BroadcastAsync(user.UserId, new BroadcastBattleRecordDefinition(record));
            room.Record.SnapShot = null;

            return true;
        }

        public bool ResumeBattle(Room room)
        {
            if (room.State != RoomState.Pause)
            {
                return false;
            }
            room.PauseDuration = 0;
            room.State = RoomState.Battle;

            return true;
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

        public ErrorCode TryGetRoom(int roomId, int userId, string token, string battleId, out Room room, out RoomUser roomUser)
        {
            roomUser = null;
            room = RoomService.INSTANCE.GetRoom(roomId);
            if (room == null)
            {
                Logger.LogError($"[Room][Connect Room][Room[{roomId}] Not Found]");
                return ErrorCode.RoomNotFound;
            }
            roomUser = room.GetRoomUser(userId);
            if (roomUser == null || room.Record.BattleId != battleId)
            {
                Logger.LogError($"[Room][Connect Room][Room[{roomId}] User[{userId}] Battle[{battleId}] Token[{token}] Is Invalid]");
                return ErrorCode.InvalidRoomUser;
            }
            if (string.IsNullOrEmpty(roomUser.Token))
            {
                Logger.LogError($"[Room][Connect Room][Room[{roomId}] Can't get token for User[{userId}]]");
                return ErrorCode.DataNotFound;
            }
            if (token != roomUser.Token)
            {
                Logger.LogError($"[Room][Connect Room][Room[{roomId}] Invalid token for User[{userId}]. Require:[{roomUser.Token}] Actual:[{token}]]");
                return ErrorCode.InvalidToken;
            }
            return ErrorCode.Success;
        }

        public Room GetRoom(int roomId)
        {
            if (!_roomMap.ContainsKey(roomId))
            {
                return null;
            }
            return _roomMap[roomId];
        }

        public Room GetRoomByUserId(int userId)
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

            RoomService.INSTANCE.Post(() =>
            {
                RoomService.INSTANCE.OnRoomUserDisconnected(userId);
            });
        }

        // 开始统计
        public void StartStat()
        {
            _rtRoom.ServerId = Host.ServerId;
            _rtRoom.SetCommitListener(() => {
                _rtRoom.Clear();
                foreach (var item in _roomMap)
                {
                    var room = item.Value;
                    switch (room.State)
                    {
                        // 空闲
                        case RoomState.Idle:
                            {
                                continue;
                            }
                        // 战斗中
                        case RoomState.Battle:
                        // 暂停
                        case RoomState.Pause:
                            {
                                _rtRoom.BusyCount += 1;
                                _rtRoom.BattleCount += 1;
                            }
                            break;
                        // 准备
                        case RoomState.Prepare:
                            {
                                _rtRoom.BusyCount += 1;
                            }
                            break;
                    }
                    _rtRoom.CountMap[room.Record.BattleType] += 1;
                    if (room.Record.IsRealTime)
                    {
                        _rtRoom.PlayerCount += 2;
                        _rtRoom.PlayerCountMap[room.Record.BattleType] += 2;
                        _rtRoom.RTCountMap[room.Record.BattleType] += 1;
                    }
                    else
                    {
                        _rtRoom.PlayerCount += 1;
                        _rtRoom.PlayerCountMap[room.Record.BattleType] += 1;
                    }
                }
            });
        }
    }
}