using Feelingtouch.Core.Cache;
using Game.Model.Config;
using Game.Service;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Game.Model
{
    public enum BattleEndReason
    {
        None = 0,
        TwoSameResult,             // 玩家全部上报，且结果一致
        TwoDiffResult,             // 玩家全部上报，且结果不一致
        OneSameResult,             // 只有一个玩家上报，且结果一致
        OneDiffResult,             // 只有一个玩家上报，且结果不一致
        NoOpOverTime,              // 玩家全部无操作超时，强制结算
        NoRealTime,                // 非真人PK
    }

    public interface ILuaSerializable
    {
        string ToLua();
    }

    [EntityTable]
    public partial class TBattleRecord : BaseEntity, ILuaSerializable
    {
        public override string PrimaryKey => BattleId;

        public static DataEntityContainer<TBattleRecord> Cache => CachePool.GetContainer<TBattleRecord>();

        public BattleEndReason EndReason { get; set; } = BattleEndReason.None;

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

        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"BattleId='{BattleId}',");
            builder.Append($"BattleVersion={BattleVersion},");
            builder.Append($"BattleSeed={BattleSeed},");
            builder.Append($"BattleType={BattleType},");
            builder.Append($"IsRealTime={IsRealTime.ToString().ToLower()},");
            builder.Append($"FrameCount={FrameCount},");
            builder.Append($"PlayerList={{{string.Join(",", PlayerList.Select(player => player.ToLua()))}}}");
            builder.Append("}");
            return builder.ToString();
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

    public partial class TBattleHero : ILuaSerializable
    {
        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"HeroId={HeroId},");
            builder.Append($"ScrollPooi={{{string.Join(",", ScrollPooi.Select(scroll => scroll.ToString()))}}}");
            builder.Append("}");
            return builder.ToString();
        }

        public static TBattleHero Build(int userId, THero hero)
        {
            var heroId = ConfigService.GetHeroResIdByLevel(hero.Card.BaseId, hero.Card.Level);
            if (heroId == 0)
            {
                return null;
            }

            var scrollPackage = TUserScrollPackage.Cache.FindKey(userId);
            if (scrollPackage == null)
            {
                return null;
            }

            var battleHero = new TBattleHero()
            {
                HeroId = heroId,
            };
            for (int i = 0; i < hero.ScrollPool.Count; i++)
            {
                var scrollBaseId = hero.ScrollPool[i];
                battleHero.ScrollPooi.Add(scrollPackage.GetScrollResId(scrollBaseId));
            }
            return battleHero;
        }
    }

    public partial class TBattlePlayer : ILuaSerializable
    {
        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"PlayerId={PlayerId},");
            builder.Append($"PlayerSeed={PlayerSeed},");
            builder.Append($"ServerId={ServerId},");
            builder.Append($"PlayerName='{PlayerName}',");
            builder.Append($"PlayerLevel={PlayerLevel},");
            builder.Append($"TowerPool={{{string.Join(",", TowerPool.Select(tower => tower.ToString()))}}},");
            builder.Append($"Hero={Hero.ToLua()},");
            builder.Append($"PlayerFrame={PlayerFrame.ToLua()}");
            builder.Append("}");
            return builder.ToString();
        }
    }

    public partial class TBattlePlayerFrame : ILuaSerializable
    {
        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"FrameList={{{string.Join(",", FrameList.Select(frame => frame.ToLua()))}}}");
            builder.Append("}");
            return builder.ToString();
        }
    }

    public partial class TBattleFrame : ILuaSerializable
    {
        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"FrameCount={FrameCount},");
            builder.Append($"FrameType={FrameType},");
            builder.Append($"Param1='{Param1}',");
            builder.Append($"Param2='{Param2}',");
            builder.Append($"Point={Point},");
            builder.Append($"FrameId={FrameId}");
            builder.Append("}");
            return builder.ToString();
        }
    }

    public partial class TBattleResult : ILuaSerializable
    {
        public string ToLua()
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("{");
            builder.Append($"FrameCount={FrameCount},");
            builder.Append($"WinPlayerId={WinPlayerId}");
            builder.Append("}");
            return builder.ToString();
        }

        public bool IsSameResult(TBattleResult result)
        {
            return WinPlayerId == result.WinPlayerId;
        }
    }
}
