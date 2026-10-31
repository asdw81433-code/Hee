using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum GameState { Boot, Loading, MainMenu, CharacterCreation, Intro, Playing, Paused, Dialogue, Shop, Dead, Ending }
    public enum Difficulty { Story, Normal, Hard, Brutal }
    public enum CrimeType { Assault, Murder, Theft, Hacking, Vandalism }

    /// <summary>
    /// The project only uses Unity's built-in layers so it works in a fresh project
    /// without editing the TagManager.
    /// </summary>
    public static class Layers
    {
        public const int World = 0;     // "Default"      - static city geometry
        public const int Actors = 1;    // "TransparentFX" - NPCs, vehicles, drones, ragdolls
        public const int Player = 2;    // "Ignore Raycast" - the player capsule
        public const int Triggers = 4;  // "Water"        - trigger volumes / pickups
        public const int WorldMask = 1 << World;
        public const int ShootMask = (1 << World) | (1 << Actors);
        public const int SightMask = 1 << World;
        public const int InteractMask = (1 << World) | (1 << Actors) | (1 << Triggers);
        public const int PlayerMask = 1 << Player;
        public const int ActorAndPlayerMask = (1 << Actors) | (1 << Player);
    }

    public static class Game
    {
        public static GameManager Manager;
        public static CityData City;
        public static Settings Settings;
        public static AudioManager Audio;
        public static MusicSystem Music;
        public static UIManager UI;
        public static WorldEnvironment Env;
        public static Effects Fx;
        public static QuestSystem Quests;
        public static DialogueSystem Dialogue;
        public static PoliceSystem Police;
        public static TrafficSystem Traffic;
        public static CrowdSystem Crowd;
        public static WorldEvents Events;
        public static ChunkStreamer Chunks;
        public static Activities Activities;
        public static CharacterProfile Profile;

        // Player pieces (set when the player is spawned)
        public static PlayerController Player;
        public static PlayerStats Stats;
        public static Inventory Inventory;
        public static WeaponController Weapons;
        public static Hacking Hacking;
        public static PlayerInteractor Interactor;

        public static Difficulty Difficulty = Difficulty.Normal;
        public static float PlayTime;

        public static bool IsPlaying => Manager != null && Manager.State == GameState.Playing;
        public static bool HasPlayer => Player != null && Player.gameObject.activeInHierarchy;

        public static Vector3 PlayerPos => Player != null ? Player.transform.position : Vector3.zero;
        public static Camera Cam => Player != null ? Player.Cam : Camera.main;
        public static Vector3 ViewPos
        {
            get
            {
                var c = Cam;
                return c != null ? c.transform.position : Vector3.zero;
            }
        }

        public static float EnemyDamageMult => Difficulty switch
        {
            Difficulty.Story => 0.45f,
            Difficulty.Normal => 1f,
            Difficulty.Hard => 1.4f,
            _ => 1.9f
        };

        public static float PlayerDamageMult => Difficulty switch
        {
            Difficulty.Story => 1.5f,
            Difficulty.Normal => 1f,
            Difficulty.Hard => 0.85f,
            _ => 0.7f
        };

        public static float EnemyAccuracyMult => Difficulty switch
        {
            Difficulty.Story => 0.6f,
            Difficulty.Normal => 1f,
            Difficulty.Hard => 1.2f,
            _ => 1.4f
        };
    }

    /// <summary>Global gameplay events used to decouple systems (quests, AI, police, UI).</summary>
    public static class GameEvents
    {
        public static event Action<NPC, DamageInfo> NpcKilled;
        public static event Action<Vector3, float, GameObject> Noise;
        public static event Action<CrimeType, Vector3> Crime;
        public static event Action<string> Interacted;
        public static event Action<string> DialogueEnded;
        public static event Action<string> HackCompleted;
        public static event Action<string, int> ItemAdded;
        public static event Action<int> LevelUp;
        public static event Action<string> FlagSet;

        public static void RaiseNpcKilled(NPC npc, DamageInfo info) => NpcKilled?.Invoke(npc, info);
        public static void RaiseNoise(Vector3 pos, float radius, GameObject src) => Noise?.Invoke(pos, radius, src);
        public static void RaiseCrime(CrimeType type, Vector3 pos) => Crime?.Invoke(type, pos);
        public static void RaiseInteracted(string id) { if (!string.IsNullOrEmpty(id)) Interacted?.Invoke(id); }
        public static void RaiseDialogueEnded(string id) => DialogueEnded?.Invoke(id);
        public static void RaiseHackCompleted(string id) { if (!string.IsNullOrEmpty(id)) HackCompleted?.Invoke(id); }
        public static void RaiseItemAdded(string id, int count) => ItemAdded?.Invoke(id, count);
        public static void RaiseLevelUp(int level) => LevelUp?.Invoke(level);
        public static void RaiseFlagSet(string flag) => FlagSet?.Invoke(flag);

        public static void ClearAll()
        {
            NpcKilled = null; Noise = null; Crime = null; Interacted = null; DialogueEnded = null;
            HackCompleted = null; ItemAdded = null; LevelUp = null; FlagSet = null;
        }
    }

    /// <summary>Story/world flags and integer variables, persisted in saves.</summary>
    public static class Flags
    {
        static readonly HashSet<string> set = new HashSet<string>();
        static readonly Dictionary<string, int> vars = new Dictionary<string, int>();

        public static bool Has(string f) => set.Contains(f);
        public static void Set(string f)
        {
            if (set.Add(f)) GameEvents.RaiseFlagSet(f);
        }
        public static void Clear(string f) => set.Remove(f);
        public static int Get(string k) => vars.TryGetValue(k, out var v) ? v : 0;
        public static void SetVar(string k, int v) => vars[k] = v;
        public static void Add(string k, int d) => vars[k] = Get(k) + d;

        public static List<string> AllFlags() => new List<string>(set);
        public static List<StringIntPair> AllVars()
        {
            var l = new List<StringIntPair>();
            foreach (var kv in vars) l.Add(new StringIntPair { key = kv.Key, value = kv.Value });
            return l;
        }
        public static void Load(List<string> flags, List<StringIntPair> v)
        {
            set.Clear(); vars.Clear();
            if (flags != null) foreach (var f in flags) set.Add(f);
            if (v != null) foreach (var p in v) vars[p.key] = p.value;
        }
        public static void Reset() { set.Clear(); vars.Clear(); }
    }

    [Serializable]
    public class StringIntPair { public string key; public int value; }
}
