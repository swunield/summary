using Feelingtouch.Core.Cache;
using Feelingtouch.Core.Collections;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Game.Model.Config;
using Game.Service;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Game.Model
{
    // 逻辑服匹配状态缓存，用于恢复战斗
    [EntityTable(StorageType = EntityTableStorageType.Memory, KeepInterval = 2 * 60 * 60 * 1000)]
    public partial class TMatch : BaseEntity
    {
        public override string PrimaryKey => UserId.ToString();

        public static DataEntityContainer<TMatch> Cache => CachePool.GetContainer<TMatch>();
    }

    // 匹配队列元素
    public class MatchUser : ISortedLinkListValue
    {
        public string BattleId { get; set; }
        public int BattleType { get; set; }
        public int FieldId { get; set; }
        public int ServerId { get; set; }
        public int UserId { get; set; }
        public string UserName { get; set; }
        public int Score { get; set; }
        public int MatchScore { get; set; }
        public TBattleHero Hero { get; set; }
        public List<int> TowerPool { get; set; }
        public int CriticalScale { get; set; }
        public TBattlePlayerAI PlayerAI { get; set; }
        /// <summary>
        /// 机器人的UserId=RobotProfile.UserId
        /// </summary>
        public int RobotUserId { get; set; } = 0;
        public MatchStrategyItem Strategy { get; set; } = null;
        public List<int> RecentPartners { get; set; } = null;

        [JsonIgnore]
        public MatchStrategyType StrategyType => Strategy == null ? MatchStrategyType.ROBOT : Strategy.Type;
        [JsonIgnore]
        public int StrategyValue => Strategy == null ? -1 : Strategy.Value;
        [JsonIgnore]
        public bool IsRobot => RobotUserId > 0;

        public long StartTime { get; set; }
        public int MaxTime { get; set; } = 0;
        [JsonIgnore]
        public List<int> StepList => RankConfig.pkStepList;

        private PKRankResConfig _rankConfig = null;
        [JsonIgnore]
        public PKRankResConfig RankConfig
        {
            get
            {
                if (_rankConfig == null)
                {
                    _rankConfig = ConfigService.GetPkRankResConfig(MatchScore);
                }
                return _rankConfig;
            }
            set
            {
                _rankConfig = value;
            }
        }

        public MatchUser() { }
        public MatchUser(int battleType, int fieldId, int serverId, int userId, string name, int score, int heroId,
            List<int> towerPool, int criticalScale, TBattlePlayerAI aI, int robotUserId = 0, MatchStrategyItem strategy = null, List<int> recentPartners = null)
        {
            BattleId = string.Empty;
            BattleType = battleType;
            FieldId = fieldId;
            ServerId = serverId;
            UserId = userId;
            UserName = name;
            Score = score;
            MatchScore = strategy != null && strategy.Type == MatchStrategyType.BIGMAN ? strategy.Value : Score;
            StartTime = 0;
            Hero = new TBattleHero(heroId);
            TowerPool = new List<int>(towerPool);
            CriticalScale = criticalScale;
            PlayerAI = aI;
            RobotUserId = robotUserId;
            Strategy = strategy;
            RecentPartners = recentPartners == null ? null : new List<int>(recentPartners);
            MaxTime = GetMaxTime() * 1000;
        }
        /// <summary>
        /// 挑战段位
        /// </summary>
        [JsonIgnore]
        public int CurLevel => RankConfig.id;
        /// <summary>
        /// 比较排序
        /// </summary>
        public int Compare(ISortedLinkListValue v)
        {
            if (!(v is MatchUser m)) return -1;
            switch (m.BattleType)
            {
                case 3:
                    return (StartTime < m.StartTime) ? -1 : 0;
                default:
                    return (MatchScore < m.MatchScore) ? -1 : 0;
            }
        }
        /// <summary>
        /// 获取唯一Id, Id相同时表示对象相等
        /// </summary>
        public int GetUniqueId() => UserId;

        // 新手
        [JsonIgnore]
        public bool IsNewBie => MatchScore <= ConfigConstants.NEWBIE_SCORE_MAX;

        // 大佬
        [JsonIgnore]
        public bool IsMaster => MatchScore >= ConfigConstants.MASTER_SCORE_MIN;

        // 匹配分配是否符合
        public LinkedListNode<MatchUser> GetSuitableOpponent(LinkedListNode<MatchUser> nextNode, long time)
        {
            while (nextNode != null)
            {
                var nextUser = nextNode.Value;
                //下一个人需要抱大腿, 跳过
                if (nextUser.StrategyType == MatchStrategyType.BIGMAN)
                {
                    nextNode = nextNode.Next;
                    continue;
                }
                if (StrategyType == MatchStrategyType.BIGMAN && nextUser.StrategyType == MatchStrategyType.NO)
                {
                    // 大腿遇到高分真人直接命中
                    return nextNode;
                }
                if (nextUser.MatchScore <= GetMaxScore(time))
                {
                    return nextNode;
                }
                if (MatchScore >= nextUser.GetMinScore(time))
                {
                    return nextNode;
                }
                return null;
            }
            return null;
        }

        // 最大匹配时间
        public int GetMaxTime()
        {
            int maxTime = 0;
            switch((BattleType)BattleType)
            {
                case Config.BattleType.PK:
                    {
                        if (IsNewBie)
                        {
                            // 新手期直接匹配机器人，默认3秒随机
                            return RandomExtensions.Instance.Next(1, 3);
                        }
                        maxTime = RandomExtensions.Instance.Next(RankConfig.maxTimeList[0], RankConfig.maxTimeList[1]);
                    }
                    break;
                case Config.BattleType.PKRANDOM:
                    {
                        maxTime = RandomExtensions.Instance.Next(5, 20);
                    }
                    break;
                default:
                    {
                        maxTime = RandomExtensions.Instance.Next(RankConfig.maxTimeList[0], RankConfig.maxTimeList[1]);
                    }
                    break;
            }
            if (StrategyType == MatchStrategyType.ROBOT)
            {
                maxTime = maxTime * ConfigConstants.ROBOT_MATCH_TIME_FACTOR / Constants.PercentMax;
            }
            return maxTime;
        }

        public int GetMinScore(long time)
        {
            var waitingTime = (int)(time - StartTime);
            return MatchScore - (waitingTime * RankConfig.times / MaxTime + 1) * StepList[0];
        }

        public int GetMaxScore(long time)
        {
            var waitingTime = (int)(time - StartTime);
            return MatchScore + (waitingTime * RankConfig.times / MaxTime + 1) * StepList[1];
        }
    }

    /// <summary>
    /// 匹配策略
    /// </summary>
    public class MatchStrategyItem
    {
        /// <summary>
        /// 策略类型
        /// </summary>
        public MatchStrategyType Type { get; set; }
        /// <summary>
        /// 策略值
        /// </summary>
        public int Value { get; set; }

        public MatchStrategyItem() { }

        public MatchStrategyItem(MatchStrategyType type, int value)
        {
            Type = type;
            Value = value;
        }
    }

    /// <summary>
    /// 匹配策略组
    /// </summary>
    public class MatchStrategyGroup
    {
        /// <summary>
        /// 策略组Id = PkRankResId
        /// </summary>
        public int Id { get; set; }
        /// <summary>
        /// 索引
        /// </summary>
        public int Index { get; set; }
        /// <summary>
        /// 策略列表
        /// </summary>
        public List<MatchStrategyItem> Items { get; set; }
        /// <summary>
        /// 策略已空
        /// </summary>
        [JsonIgnore]
        public bool IsEmpty => Items == null || Items.Count == 0;
        /// <summary>
        /// 当前策略
        /// </summary>
        [JsonIgnore]
        public MatchStrategyItem CurStrategy => Items == null || Index < 0 || Index >= Items.Count ? null : Items[Index];
        /// <summary>
        /// 随机索引
        /// </summary>
        public void RandomIndex()
        {
            if (IsEmpty) return;
            Index = RandomExtensions.Instance.Next(0, Items.Count);
        }
        /// <summary>
        /// 下一个策略
        /// </summary>
        public bool NextStrategy()
        {
            if (CurStrategy == null)
            {
                return false;
            }
            Items.RemoveAt(Index);
            RandomIndex();
            return true;
        }
        /// <summary>
        /// 清空策略
        /// </summary>
        public void ClearStrategy()
        {
            if (IsEmpty) return;
            Items.Clear();
        }
        /// <summary>
        /// 添加策略
        /// </summary>
        public void AddStrategy(MatchStrategyType type, int value, int count)
        {
            if (count <= 0) return;
            if (Items == null) Items = new List<MatchStrategyItem>();
            for (int index = 0; index < count; index++)
            {
                Items.Add(new MatchStrategyItem(type, value));
            }
        }

        public MatchStrategyGroup() { }
        public MatchStrategyGroup(int id)
        {
            Id = id;
            Index = 0;
            Items = null;
        }
    }

    /// <summary>
    /// 玩家匹配策略
    /// </summary>
    [EntityTable(MySqlRoles = "Logic")]
    public class UserMatchStrategy : BaseEntity
    {
        /// <summary>
        /// 用户Id
        /// </summary>
        public int UserId { get; set; }
        /// <summary>
        /// 差网络计数
        /// </summary>
        public int PoorNetTimes { get; set; } = 1;
        /// <summary>
        /// COOP策略组
        /// </summary>
        public MatchStrategyGroup COOP { get; set; }
        /// <summary>
        /// 最近玩的伙伴，排重，最多记5个
        /// </summary>
        public Queue<int> RecentPartners { get; set; }

        [JsonIgnore]
        private MatchStrategyItem _default = new MatchStrategyItem(MatchStrategyType.NO, -1);

        public UserMatchStrategy() { }

        public UserMatchStrategy(int userId, int coopStrategyGroupId)
        {
            UserId = userId;
            PoorNetTimes = 1;
            COOP = new MatchStrategyGroup(coopStrategyGroupId);
            RecentPartners = new Queue<int>();
        }
        public MatchStrategyItem GetStrategyItem(MatchStrategyItem strategyItem = null)
        {
            if (strategyItem != null && strategyItem.Type > MatchStrategyType.NO)
            {
                return strategyItem;
            }

            _default.Type = PoorNetTimes > 0 ? MatchStrategyType.ROBOT : MatchStrategyType.NO;
            _default.Value = PoorNetTimes > 0 ? -1 : 0;
            return _default;
        }

        public bool UpdateNet(bool isPoorNet)
        {
            if (isPoorNet && PoorNetTimes <= 0)
            {
                PoorNetTimes++;
                return true;
            }
            if (!isPoorNet && PoorNetTimes >= 0)
            {
                PoorNetTimes--;
                return true;
            }
            return false;
        }

        public void AddPartner(int partnerId)
        {
            if (RecentPartners == null)
            {
                RecentPartners = new Queue<int>();
            }
            while (RecentPartners.Count >= 5)
            {
                RecentPartners.Dequeue();
            }
            RecentPartners.Enqueue(partnerId);
        }

        public override string PrimaryKey => UserId.ToString();
        public static DataEntityContainer<UserMatchStrategy> Cache => CachePool.GetContainer<UserMatchStrategy>();
    }
}