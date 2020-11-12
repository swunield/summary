using System;
using System.Collections;
using System.Collections.Generic;

[SLua.CustomLuaClass]
public class FTRandom
{
    private const int DEFAULT_RANDOM_SEED = 6365;
    private const uint RANDOM_INT_MAX = 0x7FFFFFFFu;
    private const uint RANDOM_CONST = 0x000041A7u;
    private const uint RANDOM_Q = RANDOM_INT_MAX / RANDOM_CONST;
    private const uint RANDOM_R = RANDOM_INT_MAX % RANDOM_CONST;

    private int _seed;
    private uint _poolNum;
    private uint _count;
    private Dictionary<int, Dictionary<int, int>> _uniqueResultRecord = new Dictionary<int, Dictionary<int, int>>();

    public static FTRandom Create(int seed = 0)
    {
        var random = new FTRandom();
        random.Initialize(seed);
        return random;
    }

    public FTRandom()
    {
        _seed = DEFAULT_RANDOM_SEED;
        _poolNum = 0;
        _count = 0;
    }

    public void Initialize(int seed = 0)
    {
        _seed = seed == 0 ? DEFAULT_RANDOM_SEED : seed;
        _poolNum = (uint)_seed;
        _count = 0;
    }

    public int NextInt()
    {
        uint high = _poolNum / RANDOM_Q;
        uint low = _poolNum - high * RANDOM_Q;

        _poolNum = (RANDOM_CONST * low) - (RANDOM_R * high);
        if (_poolNum == 0)
        {
            _poolNum = DEFAULT_RANDOM_SEED;
        }

        int result = (int)_poolNum;
        if (result < 0)
        {
            result = -result;
        }
        _count++;

        return result;
    }

    public int NextInt(int min, int max)
    {
        if (min == 0 && max == 0)
        {
            return NextInt();
        }

        if (min == max)
        {
            return min;
        }

        if (min > max)
        {
            var temp = 0;
            temp = max;
            max = min;
            min = temp;
        }

        int result = NextInt();
        return min + result % (max - min);
    }

    public float NextFloat(float min, float max)
    {
        if (min == max)
        {
            return min;
        }

        if (min > max)
        {
            var temp = 0.0f;
            temp = max;
            max = min;
            min = temp;
        }

        int result = NextInt();
        return min + (max - min) * ((float)result / (float)(RANDOM_INT_MAX + 1));
    }

    public int NextUniqueInt(int tag, int min = 0, int max = 0)
    {
        var result = NextInt(min, max);
        if (_uniqueResultRecord.ContainsKey(tag) && _uniqueResultRecord[tag].ContainsKey(result))
        {
            return NextUniqueInt(tag, min, max);
        }

        if (!_uniqueResultRecord.ContainsKey(tag))
        {
            _uniqueResultRecord[tag] = new Dictionary<int, int>();
        }
        _uniqueResultRecord[tag][result] = 1;

        return result;
    }

    public void ClearUniqueRecord(int tag = -1)
    {
        if (tag == -1)
        {
            _uniqueResultRecord.Clear();
            return;
        }

        if (!_uniqueResultRecord.ContainsKey(tag))
        {
            return;
        }
        _uniqueResultRecord[tag].Clear();
    }

    public int[] MultiNextInt(int count = 10)
    {
        var resultList = new List<int>();
        for (int i = 0; i < count; i++)
        {
            resultList.Add(NextInt());
        }
        return resultList.ToArray();
    }

    public int[] MultiNextUniqueInt(int tag, int count = 10, int min = 0, int max = 0)
    {
        var resultList = new List<int>();
        for (int i = 0; i < count; i++)
        {
            resultList.Add(NextUniqueInt(tag, min, max));
        }
        return resultList.ToArray();
    }

    public uint GetPoolNum()
    {
        return _poolNum;
    }

    public uint GetCount()
    {
        return _count;
    }

    public void Sync(uint poolNum, uint count)
    {
        _poolNum = poolNum;
        _count = count;
    }

    public int Compare(FTRandom random)
    {
        if (random._seed != _seed)
        {
            return -1;
        }
        if (random._poolNum == _poolNum && random._count == _count)
        {
            return 0;
        }
        return Math.Abs((int)random._count - (int)(_count));
    }
}
