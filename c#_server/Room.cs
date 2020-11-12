using System;
using System.Collections.Generic;
using System.Text;

namespace Game.Model
{
    public partial class TRoom
    {
        // 缓存帧
        public List<TBattleFrameDetail> PendingFrameList { get; set; }

        // 缓冲帧间隔记录
        public int PendingFrameCount { get; set; }

        public TRoomUser GetRoomUser(int userId)
        {
            if (Users == null)
            {
                return null;
            }

            for (int i = 0; i < Users.Count; i++)
            {
                if (Users[i].UserId == userId)
                {
                    return Users[i];
                }
            }
            return null;
        }

        // 真人玩家数量
        public int GetRealUserCount()
        {
            if (Users == null)
            {
                return 0;
            }

            var count = 0;
            for (int i = 0; i < Users.Count; i++)
            {
                if (Users[i].UserId > 0)
                {
                    count++;
                }
            }
            return count;
        }

        public int GetResultUserCount()
        {
            if (Users == null)
            {
                return 0;
            }

            var count = 0;
            for (int i = 0; i < Users.Count; i++)
            {
                if (Users[i].Result != null)
                {
                    count++;
                }
            }
            return count;
        }

        public bool IsAllUserSameResult()
        {
            if (Users == null)
            {
                return false;
            }

            TBattleResult result = null;
            for (int i = 0; i < Users.Count; i++)
            {
                if (result == null)
                {
                    result = Users[i].Result;
                    continue;
                }
                if (!result.IsSameResult(Users[i].Result))
                {
                    return false;
                }
            }
            return true;
        }
    }

    public class RoomOpen
    {
        public string BattleId { get; set; } = string.Empty;

        public List<string> RoomTokens { get; set; }
    }
}
