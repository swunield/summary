using Feelingtouch.Core.Cache;
using Game.Model.Config;
using Game.Service;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace Game.Model
{
    public interface ILuaSerializable
    {
        string ToLua();
    }

    [EntityTable( StorageType = EntityTableStorageType.Memory | EntityTableStorageType.RemoteKv, StorageFinderType = typeof(BattleRecordStorageFinder))]
    public partial class TBattleRecord : BaseEntity
    {
        public override string PrimaryKey => BattleId;

        public static DataEntityContainer<TBattleRecord> Cache => CachePool.GetContainer<TBattleRecord>();

        public string Reason { get; set; }

        // 战斗时间
        [EntityField(MysqlIgnore = true)]
        public long BattleTime { get; set; } = 0;

        // 战斗状态
        [EntityField(MysqlIgnore = true)]
        public BattleState BattleState { get; set; } = BattleState.ALL;

        // 模拟战斗最大帧数
        [EntityField(MysqlIgnore = true)]
        public int MaxFrameCount { get; set; } = 0;

        // 是否模拟中
        [EntityField(MysqlIgnore = true)]
        public bool IsSimulating { get; set; } = false;

        public static string GenerateBattleId(int areaId)
        {
            return $"{areaId}.{Guid.NewGuid().ToString("N")}";
        }

        public static int ParseAreaIdFromBattleId(string battleId)
        {
            return int.Parse(Path.GetFileNameWithoutExtension(battleId));
        }

        public TBattleRecord(List<MatchUser> users, string battleId = null)
        {
            if (users == null || users.Count == 0) return;
            BattleId = string.IsNullOrEmpty(battleId) ? Guid.NewGuid().ToString("N") : battleId;
            BattleVersion = BattleService.BATTLE_VERSION;
            BattleSeed = BattleService.GenerateSeed();
            BattleType = users[0].BattleType;
            PlayerList = users.Select(u => new TBattlePlayer(u)).ToList();
            FrameCount = -1;
            IsRealTime = !users.Any(u => u.IsRobot);
            BattleResult = null;
            SnapShot = null;
        }

        public TBattlePlayer GetBattlePlayer(int playerId)
        {
            for (int i = 0; i < PlayerList.Count; i++)
            {
                if (PlayerList[i].PlayerId == playerId)
                {
                    return PlayerList[i];
                }
            }
            return null;
        }

        public bool AddBattleFrame(int playerId, TBattleFrame frame)
        {
            var player = GetBattlePlayer(playerId);
            if (player == null)
            {
                return false;
            }

            player.PlayerFrame.FrameList.Add(frame);
            return true;
        }
    }

    public partial class TBattleHero
    {
        public TBattleHero(int heroId)
        {
            HeroId = heroId;
        }
    }

    public partial class TBattlePlayer
    {
        public TBattlePlayer(MatchUser user)
        {
            if (user == null) return;
            PlayerId = user.UserId;
            PlayerName = user.UserName;
            PlayerLevel = user.CurLevel;
            ServerId = user.ServerId;
            PlayerSeed = BattleService.GenerateSeed();
            TowerPool = user.TowerPool;
            Hero = user.Hero;
            CriticalScale = user.CriticalScale;
            PlayerFrame = new TBattlePlayerFrame() { FrameList = new List<TBattleFrame>() };
            PlayerAI = user.PlayerAI;
            FieldId = user.FieldId;
        }
    }

    public partial class TBattleResult
    {
        public TBattleResult(int winPlayer, int frameCount, int round, bool isPoorNet)
        {
            WinPlayerId = winPlayer;
            FrameCount = frameCount;
            RoundNum = round;
            SettleRound = round;
            IsPoorNet = isPoorNet;
        }

        public TBattleResult(RoomUserCoopReport coopReport)
        {
            FrameCount = coopReport == null ? 0 : coopReport.FrameCount;
            RoundNum = coopReport == null ? 1 : coopReport.RoundNum;
            SettleRound = RoundNum;
        }
        public TBattleResult(TBattleResult result, bool isPoorNet = true)
        {
            if (result != null)
            {
                this.WinPlayerId = result.WinPlayerId;
                this.FrameCount = result.FrameCount;
                this.RoundNum = result.RoundNum;
                this.SettleRound = result.SettleRound;
            }
            IsPoorNet = isPoorNet;
        }

        public bool IsSameResult(TBattleResult result)
        {
            return WinPlayerId == result.WinPlayerId && RoundNum == result.RoundNum;
        }

        public void SetBattleType(int battleType)
        {
            BattleType = battleType;
        }
    }
}
