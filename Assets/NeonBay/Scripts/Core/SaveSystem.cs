using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace NeonBay
{
    [Serializable]
    public class ItemStack { public string id; public int count; }

    [Serializable]
    public class WeaponSave { public string defId; public int tier; public int mod; public int ammoInMag; public string uid; }

    [Serializable]
    public class QuestSave
    {
        public string id;
        public int status;
        public string step;
        public List<int> progress = new List<int>();
        public string gigSpec;
    }

    [Serializable]
    public class SaveData
    {
        public int version = 1;
        public string slotLabel;
        public string savedAt;
        public float playTime;
        public int seed;
        public int difficulty;

        public CharacterProfile profile;
        public int level;
        public int xp;
        public int perkPoints;
        public int attributePoints;
        public int[] attributes;
        public List<string> perks = new List<string>();
        public List<string> cyberware = new List<string>();
        public List<string> quickhacks = new List<string>();
        public int money;
        public int streetCred;
        public float health;

        public Vector3 position;
        public float yaw;

        public List<ItemStack> items = new List<ItemStack>();
        public List<WeaponSave> weapons = new List<WeaponSave>();
        public List<string> equipped = new List<string>();
        public List<StringIntPair> ammo = new List<StringIntPair>();

        public List<QuestSave> quests = new List<QuestSave>();
        public string trackedQuest;
        public List<string> flags = new List<string>();
        public List<StringIntPair> vars = new List<StringIntPair>();
        public List<StringIntPair> reputation = new List<StringIntPair>();
        public List<string> ownedVehicles = new List<string>();
        public List<string> discovered = new List<string>();

        public float timeOfDay;
        public int day;
        public int weather;
    }

    public static class SaveSystem
    {
        public const string Auto = "autosave";
        public const string Quick = "quicksave";
        public static readonly string[] Slots = { "slot1", "slot2", "slot3" };

        static string Dir => Path.Combine(Application.persistentDataPath, "saves");
        static string PathFor(string slot) => Path.Combine(Dir, slot + ".json");

        public static bool Exists(string slot) => File.Exists(PathFor(slot));

        public static string Describe(string slot)
        {
            var d = Peek(slot);
            if (d == null) return "-- EMPTY --";
            var name = d.profile != null ? d.profile.name : "?";
            return $"{name}  LV {d.level}  {Util.Credits(d.money)}  {TimeSpan.FromSeconds(d.playTime):hh\\:mm}  [{d.savedAt}]";
        }

        public static SaveData Peek(string slot)
        {
            try
            {
                var p = PathFor(slot);
                if (!File.Exists(p)) return null;
                return JsonUtility.FromJson<SaveData>(File.ReadAllText(p));
            }
            catch (Exception e)
            {
                Debug.LogWarning("[NeonBay] Could not read save " + slot + ": " + e.Message);
                return null;
            }
        }

        public static string MostRecent()
        {
            string best = null;
            DateTime bestTime = DateTime.MinValue;
            var all = new List<string>(Slots) { Auto, Quick };
            foreach (var s in all)
            {
                var p = PathFor(s);
                if (!File.Exists(p)) continue;
                var t = File.GetLastWriteTimeUtc(p);
                if (t > bestTime) { bestTime = t; best = s; }
            }
            return best;
        }

        public static bool Write(string slot, SaveData data)
        {
            try
            {
                Directory.CreateDirectory(Dir);
                data.slotLabel = slot;
                data.savedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
                var tmp = PathFor(slot) + ".tmp";
                File.WriteAllText(tmp, JsonUtility.ToJson(data, true));
                if (File.Exists(PathFor(slot))) File.Delete(PathFor(slot));
                File.Move(tmp, PathFor(slot));
                return true;
            }
            catch (Exception e)
            {
                Debug.LogError("[NeonBay] Save failed: " + e);
                return false;
            }
        }

        public static void Delete(string slot)
        {
            try { if (Exists(slot)) File.Delete(PathFor(slot)); } catch (Exception) { }
        }
    }
}
