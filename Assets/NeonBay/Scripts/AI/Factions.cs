using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum FactionId { None, Player, Civilian, Jackals, Lotus, Helix, Raiders, Police, Saints }

    /// <summary>Who hates whom, plus the player's standing with each group.</summary>
    public static class Factions
    {
        static readonly Dictionary<FactionId, int> rep = new Dictionary<FactionId, int>();
        static readonly Dictionary<FactionId, float> provoked = new Dictionary<FactionId, float>();
        const float GrudgeSeconds = 150f;
        static bool IsProvoked(FactionId f) => provoked.TryGetValue(f, out var t) && Time.time - t < GrudgeSeconds;

        public static string Name(FactionId f) => f switch
        {
            FactionId.Jackals => "Chrome Jackals",
            FactionId.Lotus => "Wet Lotus Syndicate",
            FactionId.Helix => "Helix Security",
            FactionId.Raiders => "Scar Raiders",
            FactionId.Police => "NBPD",
            FactionId.Saints => "Static Saints",
            FactionId.Civilian => "Civilian",
            FactionId.Player => "You",
            _ => "Unknown"
        };

        public static Color Color(FactionId f) => f switch
        {
            FactionId.Jackals => Palette.Orange,
            FactionId.Lotus => Palette.Magenta,
            FactionId.Helix => Palette.White,
            FactionId.Raiders => Palette.Red,
            FactionId.Police => Palette.Blue,
            FactionId.Saints => Palette.Green,
            _ => new Color(0.8f, 0.8f, 0.8f)
        };

        /// <summary>Static rivalries between NPC groups.</summary>
        public static bool Hostile(FactionId a, FactionId b)
        {
            if (a == b || a == FactionId.None || b == FactionId.None) return false;
            if (a == FactionId.Player) return HostileToPlayer(b);
            if (b == FactionId.Player) return HostileToPlayer(a);
            if (a == FactionId.Civilian || b == FactionId.Civilian) return false;
            if (a == FactionId.Saints || b == FactionId.Saints) return (a == FactionId.Helix || b == FactionId.Helix);
            if (a == FactionId.Police || b == FactionId.Police) return a == FactionId.Raiders || b == FactionId.Raiders || a == FactionId.Jackals || b == FactionId.Jackals;
            if ((a == FactionId.Jackals && b == FactionId.Lotus) || (a == FactionId.Lotus && b == FactionId.Jackals)) return true;
            if (a == FactionId.Raiders || b == FactionId.Raiders) return true;
            return false;
        }

        public static bool HostileToPlayer(FactionId f)
        {
            if (f == FactionId.Police) return Game.Police != null && Game.Police.Heat > 0;
            if (f == FactionId.Raiders) return true;
            if (f == FactionId.Civilian || f == FactionId.Saints) return IsProvoked(f);
            return IsProvoked(f) || Rep(f) <= -50;
        }

        public static void Provoke(FactionId f)
        {
            if (f == FactionId.Civilian || f == FactionId.Player || f == FactionId.None || f == FactionId.Police) return;
            provoked[f] = Time.time;
        }

        public static void Calm(FactionId f) => provoked.Remove(f);
        public static void CalmAll() => provoked.Clear();

        public static int Rep(FactionId f) => rep.TryGetValue(f, out var v) ? v : 0;
        public static void AddRep(FactionId f, int d) => rep[f] = Mathf.Clamp(Rep(f) + d, -100, 100);

        public static List<StringIntPair> Save()
        {
            var l = new List<StringIntPair>();
            foreach (var kv in rep) l.Add(new StringIntPair { key = kv.Key.ToString(), value = kv.Value });
            return l;
        }

        public static void Load(List<StringIntPair> l)
        {
            rep.Clear(); provoked.Clear();
            if (l == null) return;
            foreach (var p in l)
                if (System.Enum.TryParse(p.key, out FactionId f)) rep[f] = p.value;
        }
    }
}
