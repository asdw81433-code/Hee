using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum PunchType { Jab, Cross, LeadHook, RearHook, LeadUpper, RearUpper }
    public enum PunchKind { Straight, Hook, Uppercut }
    public enum FightStyle { OutBoxer, Swarmer, Slugger, Counter, Brawler }
    public enum HitResult { Miss, Slipped, Parried, Blocked, Clean }

    public class PunchDef
    {
        public PunchType type;
        public string name, code;
        public bool lead;
        public PunchKind kind;
        public float windup, extend, recover, damage, stamina, reach, twist;
        public float Total => windup + extend + recover;
    }

    public class FighterStats
    {
        public float power = 50, speed = 50, engine = 50, chin = 50, defense = 50, footwork = 50, heart = 50;
        public float Overall => (power + speed + engine + chin + defense + footwork + heart) / 7f;
        public FighterStats Clone() => (FighterStats)MemberwiseClone();
    }

    public class FighterProfile
    {
        public string id, name, nickname, bio;
        public int wins, losses, kos, draws;
        public FightStyle style;
        public bool southpaw;
        public FighterStats stats = new FighterStats();
        public Appearance look;
        public int heightCm = 180, reachCm = 183, weightKg = 79;
        public int purse = 500, rounds = 3;
        public string Record => wins + "-" + losses + (draws > 0 ? "-" + draws : "") + " (" + kos + " KO)";
        public string FullName => string.IsNullOrEmpty(nickname) ? name : name.Split(' ')[0] + " \"" + nickname + "\" " + (name.Contains(" ") ? name.Substring(name.IndexOf(' ') + 1) : "");
    }

    public class RoundStats
    {
        public int thrown, landed, jabsThrown, jabsLanded, powerThrown, powerLanded, bodyLanded, headLanded, blocked, evaded, knockdowns, counters;
        public float damage, centerTime, pressureTime;
        public void Add(RoundStats o)
        {
            thrown += o.thrown; landed += o.landed; jabsThrown += o.jabsThrown; jabsLanded += o.jabsLanded;
            powerThrown += o.powerThrown; powerLanded += o.powerLanded; bodyLanded += o.bodyLanded; headLanded += o.headLanded;
            blocked += o.blocked; evaded += o.evaded; knockdowns += o.knockdowns; counters += o.counters;
            damage += o.damage; centerTime += o.centerTime; pressureTime += o.pressureTime;
        }
        public static string Pct(int l, int t) => t <= 0 ? "0%" : Mathf.RoundToInt(100f * l / t) + "%";
    }

    /// <summary>Global boxing data: punch table, colours, the Pit roster, the player's career and training.</summary>
    public static class Boxing
    {
        public static BoxingMatch Match;
        public static PitArena Arena;

        public static readonly Color[] TrunkColors =
        {
            new Color(0.72f, 0.05f, 0.1f), new Color(0.06f, 0.18f, 0.6f), new Color(0.05f, 0.05f, 0.06f), new Color(0.92f, 0.92f, 0.94f),
            new Color(0.85f, 0.62f, 0.1f), new Color(0.65f, 0.08f, 0.55f), new Color(0.05f, 0.6f, 0.65f), new Color(0.12f, 0.45f, 0.15f)
        };
        public static readonly string[] TrunkNames = { "Blood Red", "Royal Blue", "Midnight", "Ivory", "Gold", "Neon Orchid", "Cyan Static", "Jungle" };
        public static readonly Color[] GloveColors =
        {
            new Color(0.75f, 0.04f, 0.06f), new Color(0.06f, 0.12f, 0.55f), new Color(0.06f, 0.06f, 0.07f), new Color(0.9f, 0.9f, 0.9f),
            new Color(0.9f, 0.68f, 0.1f), new Color(0.9f, 0.1f, 0.6f), new Color(0.1f, 0.85f, 0.9f)
        };
        public static readonly string[] GloveNames = { "Red", "Blue", "Black", "White", "Gold", "Magenta", "Cyan" };

        public static readonly PunchDef[] Punches =
        {
            new PunchDef { type = PunchType.Jab, name = "Jab", code = "1", lead = true, kind = PunchKind.Straight, windup = 0.05f, extend = 0.1f, recover = 0.15f, damage = 4.2f, stamina = 2.4f, reach = 0.84f, twist = 12f },
            new PunchDef { type = PunchType.Cross, name = "Cross", code = "2", lead = false, kind = PunchKind.Straight, windup = 0.09f, extend = 0.13f, recover = 0.22f, damage = 9.5f, stamina = 5.2f, reach = 0.88f, twist = 40f },
            new PunchDef { type = PunchType.LeadHook, name = "Lead Hook", code = "3", lead = true, kind = PunchKind.Hook, windup = 0.11f, extend = 0.13f, recover = 0.25f, damage = 10.5f, stamina = 6f, reach = 0.64f, twist = 34f },
            new PunchDef { type = PunchType.RearHook, name = "Rear Hook", code = "4", lead = false, kind = PunchKind.Hook, windup = 0.14f, extend = 0.14f, recover = 0.28f, damage = 12.5f, stamina = 7f, reach = 0.62f, twist = 38f },
            new PunchDef { type = PunchType.LeadUpper, name = "Lead Uppercut", code = "5", lead = true, kind = PunchKind.Uppercut, windup = 0.12f, extend = 0.12f, recover = 0.25f, damage = 10.5f, stamina = 6f, reach = 0.58f, twist = 18f },
            new PunchDef { type = PunchType.RearUpper, name = "Rear Uppercut", code = "6", lead = false, kind = PunchKind.Uppercut, windup = 0.15f, extend = 0.13f, recover = 0.28f, damage = 13.5f, stamina = 7.5f, reach = 0.58f, twist = 30f },
        };

        public static PunchDef Get(PunchType t) => Punches[(int)t];

        public static string StyleName(FightStyle s) => s switch
        {
            FightStyle.OutBoxer => "Out-Boxer", FightStyle.Swarmer => "Swarmer", FightStyle.Slugger => "Slugger", FightStyle.Counter => "Counter-Puncher", _ => "Brawler"
        };

        public static string StyleDesc(FightStyle s) => s switch
        {
            FightStyle.OutBoxer => "Lives behind the jab, circles away and wins rounds on the cards.",
            FightStyle.Swarmer => "Walks you down behind a high guard and digs to the body.",
            FightStyle.Slugger => "Slow feet, heavy hands. One clean shot can end the night.",
            FightStyle.Counter => "Waits for you to miss, then makes you pay double.",
            _ => "Wild, chrome-plated and fearless. Throws everything."
        };

        // ------------------------------------------------------------------ roster
        static List<FighterProfile> roster;
        public static List<FighterProfile> Roster { get { if (roster == null) roster = BuildRoster(); return roster; } }

        static Appearance Look(int skin, int hair, int hairCol, int beard, float bulk, float muscle, int trunks, int gloves, Color accent, bool female = false, float height = 1f, float jaw = 0.5f)
        {
            var hc = Palette.HairColors[hairCol];
            return new Appearance
            {
                skin = Palette.SkinTones[skin], chromeSkin = skin == Palette.SkinTones.Length - 1, hair = hair, hairColor = hc, beard = beard, beardColor = hc * 0.85f,
                bulk = bulk, muscle = muscle, trunks = TrunkColors[trunks], gloves = GloveColors[gloves], accent = accent, female = female, height = height, jaw = jaw,
                outfit = 1, eyes = new Color(0.25f, 0.18f, 0.1f), brows = 0
            };
        }

        static List<FighterProfile> BuildRoster()
        {
            var l = new List<FighterProfile>();
            FighterProfile F(string id, string name, string nick, FightStyle st, bool sp, int w, int lo, int ko, Appearance look, int h, int reach, int kg, int purse, int rounds, string bio,
                float pow, float spd, float eng, float chin, float def, float foot, float heart)
            {
                var p = new FighterProfile { id = id, name = name, nickname = nick, style = st, southpaw = sp, wins = w, losses = lo, kos = ko, look = look, heightCm = h, reachCm = reach, weightKg = kg, purse = purse, rounds = rounds, bio = bio };
                p.stats = new FighterStats { power = pow, speed = spd, engine = eng, chin = chin, defense = def, footwork = foot, heart = heart };
                l.Add(p);
                return p;
            }
            F("nico", "Nico Ruiz", "Neon", FightStyle.OutBoxer, false, 4, 3, 1, Look(2, 3, 0, 1, 0.92f, 0.45f, 6, 6, Palette.Cyan, false, 0.99f, 0.3f), 178, 182, 72, 450, 3,
                "A Neon Strip bouncer who thinks the jab is a personality. Busy, light-footed, glass jaw.", 38, 62, 55, 35, 52, 64, 45);
            var brick = F("brick", "Sammy Kowalski", "Brick", FightStyle.Slugger, false, 9, 6, 8, Look(0, 1, 2, 5, 1.32f, 0.3f, 2, 2, Palette.Orange, false, 1.02f, 1f), 183, 180, 98, 700, 3,
                "Dock worker. Hits like a falling container and moves like one too.", 72, 30, 45, 70, 30, 28, 65);
            brick.look.noseWidth = 1.25f; brick.look.brows = 1;
            F("fang", "Lee Fang", "Twin Fang", FightStyle.Swarmer, true, 12, 4, 7, Look(1, 5, 4, 0, 1.0f, 0.75f, 5, 5, Palette.Magenta, false, 0.97f, 0.4f), 174, 175, 70, 1000, 4,
                "Southpaw pressure fighter. Her brother is the other Fang. Neither of them backs up.", 55, 66, 70, 55, 50, 58, 70).look.tattoo = true;
            F("dara", "Dara Okafor", "Static", FightStyle.Counter, false, 15, 2, 6, Look(5, 8, 0, 3, 1.02f, 0.8f, 1, 1, Palette.Blue, false, 1.03f, 0.6f), 186, 193, 80, 1500, 4,
                "Former Helix security. Patient, precise and impossible to hit clean.", 56, 70, 62, 60, 78, 66, 60);
            F("crane", "Mikhail Volkov", "The Crane", FightStyle.OutBoxer, false, 18, 3, 9, Look(0, 4, 3, 8, 1.05f, 0.6f, 3, 3, Palette.White, false, 1.08f, 0.8f), 196, 206, 86, 2100, 5,
                "Seven feet of reach and a Russian accent from a holo-drama. Jab, jab, jab, goodnight.", 60, 58, 68, 58, 66, 70, 58);
            F("lupe", "Lupe Santos", "Lowtown Lightning", FightStyle.Swarmer, false, 21, 1, 14, Look(3, 12, 1, 0, 0.95f, 0.85f, 4, 4, Palette.Yellow, true, 0.95f, 0.35f), 168, 170, 63, 2800, 5,
                "Fastest hands in Lowtown. Grew up dodging Jackal patrols, now she dodges everything.", 58, 85, 78, 58, 68, 80, 75);
            var benny = F("benny", "Benny Castellano", "Chrome Jaw", FightStyle.Brawler, false, 25, 5, 21, Look(1, 6, 0, 6, 1.22f, 0.55f, 0, 0, Palette.Red, false, 1.01f, 1f), 181, 185, 92, 3800, 6,
                "Had his jaw replaced with titanium after his first loss. Has not been dropped since.", 76, 50, 60, 92, 40, 45, 80);
            benny.look.brows = 3; benny.look.chromeArm = false;
            var polly = F("polly", "Polly Marchetti", "IRON POLLY", FightStyle.Brawler, false, 41, 0, 38, Look(4, 7, 0, 0, 1.25f, 0.95f, 2, 4, Palette.Red, true, 1.04f, 0.7f), 180, 188, 84, 6000, 6,
                "Undefeated queen of the Pit. Reinforced titanium shins, a chrome right arm and zero mercy.", 88, 66, 80, 85, 62, 60, 95);
            polly.look.chromeArm = true; polly.look.tattoo = true; polly.look.eyes = Palette.Red;
            return l;
        }

        public static FighterProfile Fighter(string id) => Roster.Find(f => f.id == id);

        // ------------------------------------------------------------------ the player as a fighter
        public static readonly string[] TrainKeys = { "box_pow", "box_spd", "box_eng", "box_chin", "box_def", "box_foot" };
        public static readonly string[] TrainNames = { "Power (heavy bag)", "Hand Speed (speed bag)", "Engine (roadwork)", "Chin (neck work)", "Defense (slip rope)", "Footwork (ladder drills)" };
        public static int TrainLevel(int i) => Flags.Get(TrainKeys[i]);
        public static int TrainCost(int i) => 250 + TrainLevel(i) * 220;
        public const int TrainMax = 10;

        public static FighterProfile PlayerFighter()
        {
            var cp = Game.Profile ?? new CharacterProfile();
            var look = Appearance.FromProfile(cp);
            look.outfit = 1;
            look.helmet = false; look.mask = false; look.visor = false;
            int body = cp.attributes != null && cp.attributes.Length > 0 ? cp.attributes[0] : 3;
            int reflex = cp.attributes != null && cp.attributes.Length > 1 ? cp.attributes[1] : 3;
            int cool = cp.attributes != null && cp.attributes.Length > 4 ? cp.attributes[4] : 3;
            if (Game.Stats != null) { body = Game.Stats.Attr(Attr.Body); reflex = Game.Stats.Attr(Attr.Reflex); cool = Game.Stats.Attr(Attr.Cool); }
            var st = new FighterStats
            {
                power = 40 + body * 3 + TrainLevel(0) * 4 + (Game.Stats != null && Game.Stats.HasCyber("piston_fists") ? 10 : 0),
                speed = 40 + reflex * 3 + TrainLevel(1) * 4,
                engine = 42 + body * 2 + TrainLevel(2) * 4,
                chin = 40 + body * 2.5f + TrainLevel(3) * 4 + (Game.Stats != null && Game.Stats.HasCyber("titan_bones") ? 10 : 0),
                defense = 40 + reflex * 2.5f + TrainLevel(4) * 4,
                footwork = 40 + reflex * 2.5f + TrainLevel(5) * 4 + (Game.Stats != null && Game.Stats.HasCyber("pneumatic_calves") ? 6 : 0),
                heart = 45 + cool * 4,
            };
            return new FighterProfile
            {
                id = "player", name = cp.name, nickname = string.IsNullOrEmpty(cp.nickname) ? "" : cp.nickname, style = FightStyle.OutBoxer, southpaw = cp.southpaw,
                wins = Flags.Get("box_w"), losses = Flags.Get("box_l"), kos = Flags.Get("box_ko"), draws = Flags.Get("box_d"),
                look = look, stats = st, heightCm = Mathf.RoundToInt(176 * cp.height), reachCm = Mathf.RoundToInt(180 * cp.height), weightKg = cp.frame == 0 ? 70 : cp.frame == 1 ? 79 : 92
            };
        }

        /// <summary>0..8: how many of the roster the player has climbed past.</summary>
        public static int Rank => Mathf.Clamp(Flags.Get("box_rank"), 0, Roster.Count);
        public static bool IsChampion => Rank >= Roster.Count;
        public static FighterProfile NextOpponent => IsChampion ? Roster[Roster.Count - 1] : Roster[Rank];

        public static void RecordResult(FighterProfile opp, bool won, bool draw, bool ko)
        {
            if (draw) Flags.Add("box_d", 1);
            else if (won)
            {
                Flags.Add("box_w", 1); Flags.Add("ring_wins", 1);
                if (ko) Flags.Add("box_ko", 1);
                int idx = Roster.IndexOf(opp);
                if (idx >= 0 && idx == Rank) Flags.SetVar("box_rank", Rank + 1);
                opp.losses++;
            }
            else { Flags.Add("box_l", 1); opp.wins++; if (ko) opp.kos++; }
        }

        // ------------------------------------------------------------------ player injuries persist between fights
        public static InjuryRecord PlayerInjuries = new InjuryRecord();
        public static float PlayerInjuryHealTimer;

        public static void HealPlayerInjuries(float amount)
        {
            var r = PlayerInjuries;
            for (int i = 0; i < r.swell.Length; i++) { r.swell[i] = Mathf.Max(0, r.swell[i] - amount); r.bruise[i] = Mathf.Max(0, r.bruise[i] - amount * 0.7f); r.cut[i] = Mathf.Max(0, r.cut[i] - amount * 1.3f); }
            r.concussion = Mathf.Max(0, r.concussion - amount * 0.6f); r.bodyTrauma = Mathf.Max(0, r.bodyTrauma - amount);
        }

        public static void SaveInjuries()
        {
            var r = PlayerInjuries;
            for (int i = 0; i < r.swell.Length; i++)
            {
                Flags.SetVar("inj_s" + i, Mathf.RoundToInt(r.swell[i] * 1000)); Flags.SetVar("inj_b" + i, Mathf.RoundToInt(r.bruise[i] * 1000)); Flags.SetVar("inj_c" + i, Mathf.RoundToInt(r.cut[i] * 1000));
            }
            Flags.SetVar("inj_con", Mathf.RoundToInt(r.concussion * 1000)); Flags.SetVar("inj_body", Mathf.RoundToInt(r.bodyTrauma * 1000));
        }

        public static void LoadInjuries()
        {
            var r = new InjuryRecord();
            for (int i = 0; i < r.swell.Length; i++) { r.swell[i] = Flags.Get("inj_s" + i) / 1000f; r.bruise[i] = Flags.Get("inj_b" + i) / 1000f; r.cut[i] = Flags.Get("inj_c" + i) / 1000f; }
            r.concussion = Flags.Get("inj_con") / 1000f; r.bodyTrauma = Flags.Get("inj_body") / 1000f;
            PlayerInjuries = r;
        }
    }
}
