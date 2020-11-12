using Feelingtouch.Core.Cache;
using Feelingtouch.Core.Collections;
using System;
using System.Collections.Generic;
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
    public class MatchUser : ISortedLinkListNode
    {
        public int UserId { get; set; }

        public TTowerSet TowerSet { get; set; }

        public TBattleHero Hero { get; set; }

        public int ServerId { get; set; }

        public string UserName { get; set; }

        public int UserLevel { get; set; }

        public int BattleType { get; set; }

        public int Score { get; set; }

        public long StartTime { get; set; }

        public int Compare(ISortedLinkListNode node)
        {
            var user = node as MatchUser;
            return Score == user.Score ? 0 : (Score > user.Score ? 1 : -1);
        }

        public bool IsSuitableOpponent(MatchUser user, long time)
        {
            // 随着等待时间放大匹配分差范围
            var waitTime = Math.Min(time - StartTime, time - user.StartTime);
            return Math.Abs(user.Score - Score) < 100 + 100 * waitTime / 1000;
        }
    }
}
