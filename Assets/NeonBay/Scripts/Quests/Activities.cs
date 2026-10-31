using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public class GigOffer
    {
        public string spec, title, desc, fixer;
        public int reward, level;
    }

    public class BountyBoard : Interactable
    {
        public override string Prompt => "NBPD bounty board";
        public override void Interact() => Game.Activities?.OpenBounties();
    }

    /// <summary>Repeatable content: procedural gigs, bounties, street races, the fight ring and metro fast travel.</summary>
    public class Activities : MonoBehaviour
    {
        public int lastRadio = 1;

        void Awake()
        {
            Game.Activities = this;
        }

        void Start()
        {
            if (Game.Quests != null) Game.Quests.gigFactory = BuildGig;
        }

        // ================================================================== gigs
        static readonly Dictionary<string, District[]> fixerTurf = new Dictionary<string, District[]>
        {
            { "mamasol", new[] { District.NeonStrip, District.Lowtown, District.Spire } },
            { "fixer_dutch", new[] { District.Docks, District.Scar } },
            { "fixer_kit", new[] { District.Lowtown, District.Scar, District.NeonStrip } },
            { "police_hq", new[] { District.NeonStrip, District.Lowtown, District.Docks, District.Scar, District.Spire } },
        };

        static FactionId FactionFor(District d, Rng r) => d switch
        {
            District.NeonStrip => r.Chance(0.5f) ? FactionId.Lotus : FactionId.Jackals,
            District.Lowtown => FactionId.Jackals,
            District.Docks => FactionId.Lotus,
            District.Scar => FactionId.Raiders,
            _ => FactionId.Helix
        };

        static readonly string[] targetNames = { "Big Toon", "Silk Arun", "Mama Fang", "Wirejaw Ek", "The Accountant", "Nong Razor", "Captain Shin", "Ghostface Bee", "Dr. Kraisorn", "Twelve-Fingers Lek" };
        static readonly string[] items = { "a prototype optic", "a ledger of Lotus bribes", "a crate of military chrome", "a stolen spirit-house relic", "Helix payroll data", "a cargo of synth-insulin" };

        public List<GigOffer> Offers(string fixer)
        {
            var list = new List<GigOffer>();
            int day = Game.Env != null ? Game.Env.day : 1;
            int lvl = Game.Stats != null ? Game.Stats.Level : 1;
            bool bounty = fixer == "police_hq";
            for (int i = 0; i < 3; i++)
            {
                int seed = day * 1000 + (fixer.GetHashCode() & 0xFFF) * 7 + i * 131;
                int type = bounty ? 0 : new Rng(seed).Range(0, 4);
                var spec = $"{type}|{fixer}|{seed}|{lvl + new Rng(seed + 1).Range(0, 3)}";
                var q = Game.Quests.Get("gig_" + seed);
                if (q != null && q.status != QuestStatus.Inactive) continue;
                var tmp = Describe(spec);
                list.Add(tmp);
            }
            return list;
        }

        GigOffer Describe(string spec)
        {
            var p = spec.Split('|');
            int type = int.Parse(p[0]); string fixer = p[1]; int seed = int.Parse(p[2]); int lvl = int.Parse(p[3]);
            var r = new Rng(seed);
            var turf = fixerTurf.TryGetValue(fixer, out var t) ? t : new[] { District.NeonStrip };
            var d = r.Pick(turf);
            var fac = FactionFor(d, r);
            string target = r.Pick(targetNames);
            string item = r.Pick(items);
            int reward = 350 + lvl * 140 + type * 60;
            if (fixer == "police_hq") reward = Mathf.RoundToInt(reward * 1.5f);
            var o = new GigOffer { spec = spec, fixer = fixer, reward = reward, level = lvl };
            switch (type)
            {
                case 0:
                    o.title = (fixer == "police_hq" ? "WANTED: " : "Eliminate: ") + target;
                    o.desc = $"{target} ({Factions.Name(fac)}) is holed up in {CityData.DistrictName(d)} with bodyguards. Make them disappear.";
                    break;
                case 1:
                    o.title = "Retrieve " + item;
                    o.desc = $"The {Factions.Name(fac)} are sitting on {item} in {CityData.DistrictName(d)}. Bring it back.";
                    break;
                case 2:
                    o.title = "Sabotage: " + Factions.Name(fac) + " network";
                    o.desc = $"Breach a {Factions.Name(fac)} data terminal in {CityData.DistrictName(d)} and wipe their records.";
                    break;
                default:
                    o.title = "Courier run to " + CityData.DistrictName(d);
                    o.desc = "Pick up a package here and get it across the city before the client changes their mind. Timed.";
                    break;
            }
            return o;
        }

        public void OpenGigs(string fixer) => Game.UI?.OpenGigBoard(fixer, Offers(fixer));

        public void OpenBounties()
        {
            if (Game.Police != null && Game.Police.Heat > 0) { Game.UI?.Notify("The NBPD won't work with a wanted suspect", Palette.Red); return; }
            Game.UI?.OpenGigBoard("police_hq", Offers("police_hq"));
        }

        public void AcceptGig(GigOffer o)
        {
            foreach (var q in Game.Quests.Active)
                if (q.kind == QuestKind.Gig) { Game.UI?.Notify("Finish your current gig first", Palette.Red); return; }
            var quest = BuildGig(o.spec);
            Game.Quests.StartQuest(quest.id);
        }

        public Quest BuildGig(string spec)
        {
            var o = Describe(spec);
            var p = spec.Split('|');
            int type = int.Parse(p[0]); string fixer = p[1]; int seed = int.Parse(p[2]); int lvl = int.Parse(p[3]);
            var r = new Rng(seed);
            var turf = fixerTurf.TryGetValue(fixer, out var t) ? t : new[] { District.NeonStrip };
            var d = r.Pick(turf);
            var fac = FactionFor(d, r);
            string target = r.Pick(targetNames);
            r.Pick(items);
            // pick a street corner in that district
            Vector3 site = Game.City.Center;
            for (int i = 0; i < 40; i++)
            {
                int bx = r.Range(0, CityData.Grid), bz = r.Range(0, CityData.Grid);
                var b = Game.City.blocks[bx, bz];
                if (b.district != d || !string.IsNullOrEmpty(b.special)) continue;
                site = Game.City.SidewalkPoint(bx, bz, r.Value) + Vector3.up * 0.15f;
                break;
            }
            string id = "gig_" + seed;
            var q = Game.Quests.Get(id) ?? new Quest { id = id, title = o.title, giver = fixer, summary = o.desc, kind = QuestKind.Gig, money = o.reward, xp = 120 + lvl * 25, cred = 3 };
            q.spec = spec;
            q.steps.Clear();
            string group = "q_" + id + "_g";
            bool spawned = false;
            var s = q.AddStep("do", o.desc);
            void SpawnGuards(bool withBoss)
            {
                if (spawned) return;
                spawned = true;
                var mix = fac == FactionId.Raiders ? new[] { Archetype.Grunt, Archetype.Bruiser, Archetype.Shotgunner, Archetype.Gunner } : new[] { Archetype.Grunt, Archetype.Gunner, Archetype.Shotgunner, Archetype.Netrunner };
                Spawner.Squad(group, fac, site, 12f, 3 + lvl / 3, lvl, true, mix);
                if (withBoss) Spawner.Spawn(Archetype.Boss, fac, Spawner.FreeSpot(site, 4f), 0, lvl + 1, group, true, null, target);
            }
            switch (type)
            {
                case 0:
                    s.Obj(new Objective { text = "Eliminate " + target + " and the bodyguards", type = ObjType.Kill, target = group, count = 0, pos = site + Vector3.up * 2f });
                    s.enter = () => { spawned = false; SpawnGuards(true); };
                    break;
                case 1:
                    s.Obj(new Objective { text = "Find and take the goods", type = ObjType.Use, target = id + "_item", pos = site + Vector3.up });
                    s.enter = () =>
                    {
                        spawned = false;
                        var qo = Interactable.Create<QuestObject>("GigItem", null, Spawner.FreeSpot(site, 6f), new Vector3(0.8f, 0.7f, 0.8f), Vector3.forward, Layers.Triggers);
                        qo.id = id + "_item"; qo.prompt = "Take the goods";
                        qo.GetComponent<BoxCollider>().isTrigger = true;
                        Util.Primitive(PrimitiveType.Cube, "Crate", qo.transform, new Vector3(0, 0.35f, 0), new Vector3(0.8f, 0.6f, 0.6f), Mats.Cached("gigcrate", () => Mats.Emissive(new Color(0.2f, 0.2f, 0.22f), Palette.Yellow * 1.5f)));
                    };
                    s.update = dt => { if (!spawned && (Game.PlayerPos - site).sqrMagnitude < 150f * 150f) SpawnGuards(false); };
                    break;
                case 2:
                    s.Obj(new Objective { text = "Breach the data terminal", type = ObjType.Hack, target = id + "_term", pos = site + Vector3.up * 1.8f });
                    s.enter = () =>
                    {
                        spawned = false;
                        var tp = Spawner.FreeSpot(site, 5f);
                        var term = Interactable.Create<Terminal>("GigTerminal", null, tp, new Vector3(0.9f, 1.8f, 0.6f), Vector3.forward);
                        term.hackId = id + "_term"; term.id = term.hackId; term.cost = 2;
                        Util.Primitive(PrimitiveType.Cube, "Box", term.transform, new Vector3(0, 0.9f, 0), new Vector3(0.9f, 1.8f, 0.5f), Mats.Cached("gigterm", () => Mats.Emissive(new Color(0.1f, 0.1f, 0.12f), Palette.Green)));
                    };
                    s.update = dt => { if (!spawned && (Game.PlayerPos - site).sqrMagnitude < 150f * 150f) SpawnGuards(false); };
                    break;
                default:
                    {
                        float timer = 0f;
                        float dist = Vector3.Distance(Game.City.Loc(fixer)?.pos ?? Game.PlayerPos, site);
                        float limit = Mathf.Clamp(dist / 9f + 40f, 60f, 240f);
                        s.Obj(new Objective { text = "Deliver the package", type = ObjType.Reach, pos = site, radius = 6f, target = id });
                        s.enter = () => { timer = limit; Game.Inventory.Add("package", 1, false); Game.UI?.StartTimer(limit, "COURIER"); };
                        s.update = dt => timer -= dt;
                        s.fail = () => timer <= 0f;
                        s.exit = () => { Game.Inventory.Remove("package"); Game.UI?.StopTimer(); };
                        break;
                    }
            }
            Game.Quests.Register(q);
            return q;
        }

        // ================================================================== street races
        public bool RaceActive { get; private set; }
        public float RaceTime { get; private set; }
        public float Countdown { get; private set; }
        public int RaceCheckpoint { get; private set; }
        public int RaceTotal => checkpoints.Count;
        public string RaceName { get; private set; }
        string raceId;
        readonly List<Vector3> checkpoints = new List<Vector3>();
        GameObject marker;
        float gold, silver, bronze;

        public void StartRace(string id)
        {
            if (RaceActive || Game.Player == null) return;
            if (!Game.Player.InVehicle) { Game.UI?.Notify("You need a vehicle to race", Palette.Red); return; }
            var loc = Game.City.Loc(id);
            if (loc == null) return;
            raceId = id; RaceName = loc.name;
            checkpoints.Clear();
            var r = new Rng(id.GetHashCode());
            int ix = Mathf.Clamp(Mathf.RoundToInt(loc.pos.x / CityData.Cell), 0, CityData.Grid);
            int iz = Mathf.Clamp(Mathf.RoundToInt(loc.pos.z / CityData.Cell), 0, CityData.Grid);
            int lastDir = -1;
            float length = 0f; var prev = loc.pos;
            for (int i = 0; i < 12; i++)
            {
                for (int tries = 0; tries < 10; tries++)
                {
                    int dir = r.Range(0, 4);
                    if (lastDir >= 0 && dir == (lastDir + 2) % 4) continue;
                    int nx = ix + (dir == 0 ? 1 : dir == 2 ? -1 : 0), nz = iz + (dir == 1 ? 1 : dir == 3 ? -1 : 0);
                    if (nx < 1 || nz < 1 || nx > CityData.Grid - 1 || nz > CityData.Grid - 1) continue;
                    ix = nx; iz = nz; lastDir = dir;
                    break;
                }
                var cp = Game.City.Intersection(ix, iz);
                length += Vector3.Distance(prev, cp); prev = cp;
                checkpoints.Add(cp);
            }
            gold = length / 34f; silver = length / 28f; bronze = length / 22f;
            RaceCheckpoint = 0; RaceTime = 0f; Countdown = 3f; RaceActive = true;
            if (marker == null)
            {
                marker = new GameObject("RaceCheckpoint");
                var cyl = Util.Primitive(PrimitiveType.Cylinder, "Ring", marker.transform, new Vector3(0, 6f, 0), new Vector3(16f, 6f, 16f), Mats.Cached("racecp", () => Mats.Additive(new Color(1f, 0.85f, 0.1f, 0.25f) * 1.6f, Tex.Scanlines)));
                var l = marker.AddComponent<Light>(); l.type = LightType.Point; l.range = 25f; l.intensity = 3f; l.color = Palette.Yellow;
            }
            marker.SetActive(true);
            marker.transform.position = checkpoints[0];
            Game.UI?.SetWaypoint(checkpoints[0], "Checkpoint");
            Game.UI?.Banner("STREET RACE", RaceName + "   GOLD " + Fmt(gold) + "  SILVER " + Fmt(silver) + "  BRONZE " + Fmt(bronze), Palette.Yellow);
            Game.Audio?.Play2D("notify");
        }

        public static string Fmt(float t) => ((int)(t / 60)).ToString("0") + ":" + (t % 60f).ToString("00.00");
        public bool RaceLocked => RaceActive && Countdown > 0f;

        void UpdateRace(float dt)
        {
            if (!RaceActive) return;
            if (!Game.Player.InVehicle && Countdown <= 0f) { EndRace(false, "You left your vehicle"); return; }
            if (Countdown > 0f)
            {
                float before = Countdown;
                Countdown -= dt;
                if (Mathf.Ceil(before) != Mathf.Ceil(Countdown)) Game.Audio?.Play2D(Countdown <= 0f ? "ui_confirm" : "ui_blip", 0.8f);
                return;
            }
            RaceTime += dt;
            var cp = checkpoints[RaceCheckpoint];
            if ((Game.PlayerPos - cp).Flat().sqrMagnitude < 11f * 11f)
            {
                RaceCheckpoint++;
                Game.Audio?.Play2D("ui_confirm", 0.7f);
                if (RaceCheckpoint >= checkpoints.Count) { EndRace(true, null); return; }
                marker.transform.position = checkpoints[RaceCheckpoint];
                Game.UI?.SetWaypoint(checkpoints[RaceCheckpoint], "Checkpoint");
            }
            if (RaceTime > bronze * 2.5f) EndRace(false, "Too slow");
        }

        void EndRace(bool finished, string reason)
        {
            RaceActive = false;
            if (marker != null) marker.SetActive(false);
            Game.UI?.ClearWaypoint();
            if (!finished) { Game.UI?.Banner("RACE FAILED", reason, Palette.Red); return; }
            string medal; int money; int xp;
            if (RaceTime <= gold) { medal = "GOLD"; money = 1500; xp = 400; }
            else if (RaceTime <= silver) { medal = "SILVER"; money = 800; xp = 250; }
            else if (RaceTime <= bronze) { medal = "BRONZE"; money = 400; xp = 150; }
            else { medal = "FINISHED"; money = 120; xp = 60; }
            int bestMs = Flags.Get(raceId + "_best");
            int ms = Mathf.RoundToInt(RaceTime * 1000f);
            bool record = bestMs == 0 || ms < bestMs;
            if (record) Flags.SetVar(raceId + "_best", ms);
            Game.Stats.AddMoney(money); Game.Stats.AddXP(xp); Game.Stats.AddCred(medal == "GOLD" ? 8 : 3);
            Game.UI?.Banner(medal + (record ? "  NEW RECORD" : ""), RaceName + "  " + Fmt(RaceTime) + "   +" + Util.Credits(money), Palette.Yellow);
            Game.Audio?.Play2D("quest_done");
        }

        // ================================================================== fight ring
        public bool FightActive { get; private set; }
        public int FightRound { get; private set; }
        const string RingGroup = "ring_fighters";
        float roundDelay;

        public void StartFight()
        {
            if (FightActive || !Game.Stats.Spend(100)) return;
            FightActive = true;
            FightRound = 0;
            var spawn = Game.City.Loc("ring_spawn");
            Game.UI?.Fade(0.4f);
            Game.Player.Teleport(spawn.pos + Vector3.up * 0.1f, 45f);
            Game.Weapons.forceFists = true;
            Game.Police.suppressed = true;
            roundDelay = 2f;
            Game.UI?.Banner("THE PIT", "Three rounds. Fists only. Don't die.", Palette.Red);
        }

        void SpawnRound()
        {
            FightRound++;
            var c = Game.City.Loc("ring_center").pos;
            int lvl = Game.Stats.Level + FightRound - 1;
            if (FightRound == 1) Spawner.Spawn(Archetype.Bruiser, FactionId.None, c + new Vector3(2.5f, 0, 2.5f), 225f, lvl, RingGroup, true, "fists", "Sammy 'Brick' Kowalski");
            else if (FightRound == 2)
            {
                Spawner.Spawn(Archetype.Grunt, FactionId.None, c + new Vector3(2.5f, 0, 2.5f), 225f, lvl, RingGroup, true, "fists", "Twin Fang A");
                Spawner.Spawn(Archetype.Grunt, FactionId.None, c + new Vector3(-2.5f, 0, 2.5f), 135f, lvl, RingGroup, true, "fists", "Twin Fang B");
            }
            else
            {
                var look = Appearance.Random(FactionId.Raiders, new Rng(41));
                look.mask = false; look.hair = 4; look.chromeArm = true; look.bulk = 1.3f;
                Spawner.Spawn(Archetype.Boss, FactionId.None, c + new Vector3(2.5f, 0, 2.5f), 225f, lvl + 2, RingGroup, true, "fists", "IRON POLLY", look);
            }
            foreach (var n in Spawner.Group(RingGroup)) if (n != null && n.state != NPCState.Dead) n.EngageTarget(Game.Stats.dmg);
            Game.UI?.Banner("ROUND " + FightRound, FightRound == 3 ? "Champion: IRON POLLY" : "FIGHT!", Palette.Red);
            Game.Audio?.Play2D("ui_confirm");
        }

        void UpdateFight(float dt)
        {
            if (!FightActive) return;
            if (Game.Stats.dmg.Fraction < 0.1f) { EndFight(false); return; }
            if (roundDelay > 0f)
            {
                roundDelay -= dt;
                if (roundDelay <= 0f) SpawnRound();
                return;
            }
            if (Spawner.Alive(RingGroup) == 0)
            {
                if (FightRound >= 3) { EndFight(true); return; }
                roundDelay = 3f;
                Game.UI?.Notify("Round " + FightRound + " won!", Palette.Green);
            }
        }

        void EndFight(bool won)
        {
            FightActive = false;
            Spawner.DespawnGroups(RingGroup);
            Game.Weapons.forceFists = false;
            Game.Police.suppressed = false;
            if (won)
            {
                int purse = 1500 + Game.Stats.Level * 100;
                Game.Stats.AddMoney(purse); Game.Stats.AddXP(450); Game.Stats.AddCred(10);
                Flags.Add("ring_wins", 1);
                Game.UI?.Banner("CHAMPION", "The Pit roars your name.  +" + Util.Credits(purse), Palette.Yellow);
            }
            else
            {
                Game.Stats.dmg.health = Game.Stats.dmg.maxHealth * 0.3f;
                Game.UI?.Banner("KNOCKED OUT", "You wake up on the warehouse floor. Your pride hurts more.", Palette.Red);
                var spawn = Game.City.Loc("ring_spawn");
                Game.Player.Teleport(spawn.pos + new Vector3(-4f, 0, -6f), 0);
            }
        }

        // ================================================================== metro
        public void FastTravel(Location to)
        {
            if (to == null) return;
            if (Game.Police != null && Game.Police.Heat > 0) { Game.UI?.Notify("Metro is locked down while the NBPD is after you", Palette.Red); return; }
            if (RaceActive || FightActive) return;
            Game.UI?.Fade(1f);
            Game.Player.Teleport(to.pos + to.facing * 2f + Vector3.up * 0.2f, Quaternion.LookRotation(to.facing).eulerAngles.y);
            Game.Env?.SkipHours(0.4f);
            Game.Audio?.Play2D("train", 0.6f);
        }

        // ================================================================== misc
        public void RestoreWorldState()
        {
            var gen = CityGenerator.Current;
            if (gen != null)
                for (int i = 0; i < gen.shards.Count; i++) if (gen.shards[i] != null) gen.shards[i].gameObject.SetActive(!Flags.Has("shard_" + i));
        }

        public int ShardsFound
        {
            get { int n = 0; for (int i = 0; i < Lore.ShardCount; i++) if (Flags.Has("shard_" + i)) n++; return n; }
        }

        void Update()
        {
            if (!Game.IsPlaying || !Game.HasPlayer) return;
            float dt = Time.deltaTime;
            UpdateRace(dt);
            UpdateFight(dt);
        }
    }
}
