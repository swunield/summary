using Feelingtouch.Core.Rpc;
using Feelingtouch.Core.Runtime;
using Feelingtouch.Core.ScriptEngine.Lua;
using Feelingtouch.Core.Util;
using Feelingtouch.Core.Util.Log;
using Game.Model;
using Game.Pattern;
using Game.Utils;
using Microsoft.EntityFrameworkCore.Internal;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Game.Service
{
    interface IBattleSimulator
    {
        int BattleVersion { get; }
        TBattleResult Simulate(TBattleRecord record);
    }

    class BattleSimulator : IBattleSimulator
    {
        long _battleTimes = 0;
        LuaSvr _luaSvr;
        LuaTable _battleEntry;
        int _battleVersion = 0;
        int _reInitCount = 1000;

        public int BattleVersion => _battleVersion;
        public readonly AsyncLock Lock = new AsyncLock();

        public BattleSimulator(int reInitCount = 1000)
        {
            LuaState.hasfileDelegate = HasFile;
            LuaState.loaderDelegate = FileLoader;

            _reInitCount = reInitCount;
            InitState();
        }

        public void InitState()
        {
            try
            {
                //释放之前的luastate
                if (_luaSvr != null)
                {
                    _luaSvr.luaState.Dispose();
                }

                _luaSvr = new LuaSvr();
                _luaSvr.init((i) => { }, () =>
                {
                    Logger.LogInformation($"SLua server init done. L:{_luaSvr.luaState.L.ToInt64()}");
                });

                _luaSvr.start("Lua/LuaEnv/class.lua");
                _luaSvr.start("Lua/LuaEnv/plugin.lua");
                _luaSvr.start("Lua/gameutils/main.lua");
                _luaSvr.start("Lua/gameres/main.lua");
                _luaSvr.start("Lua/gamebattle/main.lua");

                _battleEntry = _luaSvr.luaState.doFile("Lua/BattleEntry.lua") as LuaTable;

                //获取lua版本
                if (!int.TryParse(_battleEntry.invoke("version").ToString(), out _battleVersion))
                {
                    _battleVersion = 0;
                }

                if (_battleEntry == null)
                {
                    Logger.LogError("Init lua battle entry failed.");
                    throw new Exception("Init lua battle entry failed.");
                }
            }
            catch (Exception e)
            {
                Logger.LogError(e, "Init lua battle simulator failed.");
                throw e;
            }
        }

        public TBattleResult Simulate(TBattleRecord record)
        {
            LuaTable table;
            try
            {
                var times = Interlocked.Increment(ref _battleTimes);
                if (times >= _reInitCount && times % _reInitCount == 0)
                {
                    InitState();
                    Logger.LogDebug("Reinit Lua State");
                }

                Stopwatch watch = new Stopwatch();
                watch.Start();

                //Logger.LogWarning("Simulate Battle [" + record.ToLua().ToFormatSafeString() + "]");
                table = _battleEntry.invoke("entry", record.ToLua(), false) as LuaTable;

                var result = new TBattleResult()
                {
                    WinPlayerId = table["winPlayerId"].ToInt(),
                    FrameCount = table["frameCount"].ToInt(),
                };

                watch.Stop();
                Logger.LogDebug($"Battle Simulate BattleId[{record.BattleId}] FrameCount[{record.FrameCount}] Finish. Time cost [{watch.ElapsedMilliseconds}]ms");

                return result;
            }
            catch (Exception e)
            {
                Logger.LogError(e, "Simulate lua battle failed.");

                InitState();

                _ = BattleService.ReportBattleException(Host.ServerId, record.PlayerList[0].PlayerId, BattleVersion, record.ToLua());
            }

            return null;
        }

        static string FixFileName(string filename)
        {
            if (filename.StartsWith("file://") || filename.StartsWith("plug://"))
            {
                filename = filename.Substring(7);
                filename = filename.Replace('.', '/');
                filename = string.Format("Lua/{0}{1}", filename, filename.EndsWith(".lua") || filename.EndsWith(".txt") ? "" : ".lua");
            }

            return filename;
        }

        static byte[] FileLoader(string filename)
        {
            filename = FixFileName(filename);

            if (File.Exists(filename))
            {
                return File.ReadAllBytes(filename);
            }
            else
            {
                return null;
            }
        }

        static bool HasFile(string filename)
        {
            filename = FixFileName(filename);
            return File.Exists(filename);
        }
    }

    class AsyncBattleConsumer : AbstractConsumer<TBattleRecord, TBattleResult>
    {
        IBattleSimulator _simulator;

        public AsyncBattleConsumer(IBattleSimulator simulator)
        {
            _simulator = simulator;
        }

        protected override TBattleResult DoWork(TBattleRecord input)
        {
            return _simulator.Simulate(input);
        }
    }

    public class BattleService
    {
        private static AsyncProducer<TBattleRecord, TBattleResult> ASYNC_PRODUCER;

        public static int BATTLE_VERSION { get; private set; } = 0;

        public static void Start(int consumerCount = 2)
        {
            if (!Host.Role.HasRole(ServerRole.Room))
            {
                return;
            }

            var consumers = new List<AsyncBattleConsumer>();
            for (int i = 0; i < consumerCount; i++)
            {
                var simulator = new BattleSimulator(500);
                BATTLE_VERSION = simulator.BattleVersion;

                consumers.Add(new AsyncBattleConsumer(simulator));
            }

            ASYNC_PRODUCER = new AsyncProducer<TBattleRecord, TBattleResult>(consumers);
        }

        public static int GenerateSeed()
        {
            return RandomExtensions.Instance.Next(1048576);
        }

        public static async Task<TBattleResult> SimulateBattle(TBattleRecord record) => await AsyncSimulateBattle(record);

        private static async Task<TBattleResult> AsyncSimulateBattle(TBattleRecord record)
        {
            return await ASYNC_PRODUCER.Enqueue(record);
        }

        [Rpc]
        public static async Task ReportBattleException(int serverId, int attackerId, int version, string battleEnterDataOfLua)
        {
            await RpcProxy.RunAsync(typeof(BattleService), 10000, RpcProxy.BuildArgs(serverId, attackerId, version, battleEnterDataOfLua), () =>
            {
            });
        }
    }
}
