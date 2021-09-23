using Feelingtouch.Core.Cache;
using Feelingtouch.Core.Util;
using Game.Model.Config;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Game.Model
{
    /// <summary>
    /// 房间状态
    /// </summary>
    public enum RoomState
    {
        /// <summary>
        /// 空闲
        /// </summary>
        Idle = 0,
        /// <summary>
        /// 准备
        /// </summary>
        Prepare = 1,
        /// <summary>
        /// 战斗
        /// </summary>
        Battle = 2,
        /// <summary>
        /// 暂停
        /// </summary>
        Pause = 3,
        /// <summary>
        /// 结算
        /// </summary>
        Settle = 4,
    }

    /// <summary>
    /// 房间玩家Coop模式上报回合数
    /// </summary>
    public class RoomUserCoopReport
    {
        public int FrameCount { get; set; }
        public int RoundNum { get; set; }
    }

    /// <summary>
    /// 房间内玩家
    /// </summary>
    public class RoomUser
    {
        /// <summary>
        /// 玩家Id
        /// </summary>
        public int UserId { get; }
        /// <summary>
        /// 机器人的UserId=RobotProfile.UserId
        /// </summary>
        public int RobotUserId { get; }
        /// <summary>
        /// 机器人积分
        /// </summary>
        public int RobotScore { get; }
        /// <summary>
        /// 连接房间的时间[毫秒], 初始0 | 连接时等于正数 | 掉线时等于负数
        /// </summary>
        public long ConnectTime { get; set; }
        /// <summary>
        /// 身份令牌
        /// </summary>
        public string Token { get; }
        /// <summary>
        /// 上报结果
        /// </summary>
        public TBattleResult ReportResult { get; set; }
        /// <summary>
        /// 上报时间[毫秒]
        /// </summary>
        public long ReportTime { get; set; }
        /// <summary>
        /// 是否加载快照中
        /// </summary>
        public bool IsSnapshoting { get; set; }
        /// <summary>
        /// 协作模式回合上报
        /// </summary>
        public RoomUserCoopReport CoopReport { get; set; } = null;
        /// <summary>
        /// 是否在线
        /// </summary>
        public bool IsConnected => ConnectTime > 0;
        /// <summary>
        /// 掉线时间[毫秒]
        /// </summary>
        public long DisconnectTime => -ConnectTime;
        /// <summary>
        /// 是否掉线
        /// </summary>
        public bool IsDisconnected => ConnectTime < 0;
        /// <summary>
        /// 是否上报结果
        /// </summary>
        public bool IsReported => ReportResult != null;
        /// <summary>
        /// 是否机器人
        /// </summary>
        public bool IsRobot => RobotUserId > 0;

        public RoomUser(MatchUser user)
        {
            if (user == null) return;
            UserId = user.UserId;
            RobotUserId = user.RobotUserId;
            RobotScore = user.Score;
            ConnectTime = 0;
            Token = IsRobot ? string.Empty : RandomExtensions.Instance.RandomString(8);
            ReportResult = null;
            ReportTime = 0;
            IsSnapshoting = false;
            CoopReport = null;
        }
    }

    /// <summary>
    /// 房间数据
    /// </summary>
    public class Room
    {
        /// <summary>
        /// 房间Id
        /// </summary>
        public int RoomId { get; }
        /// <summary>
        /// 房间状态
        /// </summary>
        public RoomState State { get; set; }
        /// <summary>
        /// 玩家列表
        /// </summary>
        public List<RoomUser> Users { get; set; }
        /// <summary>
        /// 战斗记录
        /// </summary>
        public TBattleRecord Record { get; set; }
        /// <summary>
        /// 准备时间[毫秒]
        /// </summary>
        public long PrepareTime { get; set; }
        /// <summary>
        /// 更新时间[毫秒]
        /// </summary>
        public long UpdateTime { get; set; }
        /// <summary>
        /// 暂停时长[毫秒]
        /// </summary>
        public long PauseDuration { get; set; }
        /// <summary>
        /// 战斗帧数
        /// </summary>
        public int BattleFrame { get; set; }
        /// <summary>
        /// 上一次帧包帧数
        /// </summary>
        public int LastPackageBattleFrame { get; set; }
        /// <summary>
        /// 缓冲帧数
        /// </summary>
        public int PendFrame { get; set; }
        /// <summary>
        /// 帧包长度
        /// </summary>
        public int FramePackageLength { get; set; }
        /// <summary>
        /// 缓冲帧列表
        /// </summary>
        public List<TBattleFrameDetail> PendingList { get; set; }
        /// <summary>
        /// 全部玩家掉线时间[毫秒]
        /// </summary>
        public long AllDisconnectTime { get; set; }
        /// <summary>
        /// 是否玩家创建房间
        /// </summary>
        public bool IsManual { get; set; } = false;
        /// <summary>
        /// 战斗开始时间
        /// </summary>
        public DateTime BattleStartTime { get; set; }

        public Room(int roomId) => RoomId = roomId;

        /// <summary>
        /// 准备
        /// </summary>
        public void Prepare(int areaId, long prepareTime, List<MatchUser> matchUsers, bool isManual = false)
        {
            if (matchUsers == null || matchUsers.Count == 0) return;
            State = RoomState.Prepare;
            Users = matchUsers.Select(u => new RoomUser(u)).ToList();
            Record = new TBattleRecord(matchUsers, TBattleRecord.GenerateBattleId(areaId));
            PrepareTime = prepareTime;
            UpdateTime = prepareTime;
            PauseDuration = 0;
            BattleFrame = 0;
            PendFrame = 0;
            PendingList = new List<TBattleFrameDetail>();
            FramePackageLength = GetFramePackageLength(Record.IsRealTime);
            IsManual = isManual;
            BattleStartTime = DateTime.MinValue;
        }

        /// <summary>
        /// 暂停
        /// </summary>
        public void Pause(long duration)
        {
            State = RoomState.Pause;
            PauseDuration = duration;
        }

        /// <summary>
        /// 恢复暂停
        /// </summary>
        public void UnPause(long delta)
        {
            if (PauseDuration > delta)
            {
                PauseDuration -= delta;
            }
            else
            {
                State = RoomState.Battle;
            }
        }

        /// <summary>
        /// 关闭
        /// </summary>
        public void Close()
        {
            State = RoomState.Idle;
            Users = null;
            Record = null;
            PrepareTime = 0;
            UpdateTime = 0;
            PauseDuration = 0;
            BattleFrame = 0;
            PendFrame = 0;
            PendingList = null;
            BattleStartTime = DateTime.MinValue;
        }

        /// <summary>
        /// 房间玩家Coop模式定时上报的战斗结果
        /// </summary>
        public TBattleResult CoopReportResult => new TBattleResult(Users.OrderBy(u => u.CoopReport == null ? 0 : u.CoopReport.RoundNum).LastOrDefault()?.CoopReport);

        public int GetFramePackageLength(bool isRealTime)
        {
            return isRealTime ? ConfigConstants.BATTLE_FRAME_PACKAGE_LENGTH : ConfigConstants.BATTLE_ROBOT_FRAME_PACKAGE_LENGTH;
        }

        public RoomUser GetRoomUser(int userId)
        {
            return Users?.FirstOrDefault(user => (user != null && user.UserId == userId));
        }

        /// <summary>
        /// 准备信息
        /// </summary>
        public RoomPrepareInfo PrepareInfo => new RoomPrepareInfo(Record?.BattleId, Users?.Select(u => u.Token).ToList());
    }

    /// <summary>
    /// 房间准备信息
    /// </summary>
    public class RoomPrepareInfo
    {
        /// <summary>
        /// 战斗Id
        /// </summary>
        public string BattleId { get; set; } = string.Empty;
        /// <summary>
        /// 玩家令牌
        /// </summary>
        public List<string> Tokens { get; set; }

        public RoomPrepareInfo(string battleId, List<string> tokens)
        {
            BattleId = battleId;
            Tokens = tokens;
        }
    }

    /// <summary>
    /// 房间结算数据
    /// </summary>
    public class RoomSettleData
    {
        /// <summary>
        /// 房间Id
        /// </summary>
        public int RoomId { get; set; }
        /// <summary>
        /// TBattleRecord的上报结果
        /// </summary>
        public TBattleResult BattleResult { get; set; }
        /// <summary>
        /// 玩家1Id
        /// </summary>
        public int UserId1 { get; set; }
        /// <summary>
        /// 玩家1上报结果
        /// </summary>
        public TBattleResult UserResult1 { get; set; }
        /// <summary>
        /// 玩家2Id
        /// </summary>
        public int UserId2 { get; set; }
        /// <summary>
        /// 玩家2上报结果
        /// </summary>
        public TBattleResult UserResult2 { get; set; }
        /// <summary>
        /// 是否玩家创建房间
        /// </summary>
        public bool IsManual { get; set; } = false;
        /// <summary>
        /// 房间准备超时
        /// </summary>
        public bool PrepareOverTime { get; set; } = false;

        public RoomSettleData() { }
        public RoomSettleData(Room room, bool prepareOverTime = false)
        {
            if (room == null)
            {
                return;
            }
            RoomId = room.RoomId;
            BattleResult = room.Record?.BattleResult;
            UserId1 = room.Users[0].UserId;
            UserResult1 = room.Users[0].ReportResult;
            UserId2 = room.Users[1].UserId;
            UserResult2 = room.Users[1].ReportResult;
            IsManual = room.IsManual;
            PrepareOverTime = prepareOverTime;
        }
    }
}