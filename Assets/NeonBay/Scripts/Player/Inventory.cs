using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum ItemKind { Consumable, Ammo, Grenade, Component, Junk, Quest }

    public class ItemDef
    {
        public string id, name, desc;
        public ItemKind kind;
        public int price;
        public int maxStack = 999;
        public float heal, healOverTime, ram, stamina;
        public string buff;
        public float buffTime;
    }

    public static class Items
    {
        static readonly Dictionary<string, ItemDef> defs = new Dictionary<string, ItemDef>();
        public static IEnumerable<ItemDef> All => defs.Values;

        static Items()
        {
            Add(new ItemDef { id = "medkit", name = "MedInjector", desc = "Restores 60% health instantly.", kind = ItemKind.Consumable, price = 120, heal = 0.6f });
            Add(new ItemDef { id = "stim", name = "Overdrive Stim", desc = "+25% speed, infinite stamina for 20s.", kind = ItemKind.Consumable, price = 160, buff = "stim", buffTime = 20f });
            Add(new ItemDef { id = "ram_shot", name = "RAM Shot", desc = "Restores 4 RAM.", kind = ItemKind.Consumable, price = 110, ram = 4 });
            Add(new ItemDef { id = "noodle_cup", name = "Instant Noodles", desc = "Heals 25 over 10 seconds.", kind = ItemKind.Consumable, price = 15, healOverTime = 25 });
            Add(new ItemDef { id = "street_food", name = "Chili Dog", desc = "Synth-beef dog with all the fixings. Heals 45 over 10s.", kind = ItemKind.Consumable, price = 30, healOverTime = 45 });
            Add(new ItemDef { id = "gumbo", name = "Gator Gumbo", desc = "Spicy enough to wake the dead. Heals 70 over 10s, +stamina regen.", kind = ItemKind.Consumable, price = 55, healOverTime = 70, buff = "spice", buffTime = 60f });
            Add(new ItemDef { id = "volt_cola", name = "Volt Cola", desc = "Restores stamina, +50% stamina regen for 30s.", kind = ItemKind.Consumable, price = 15, stamina = 100, buff = "volt", buffTime = 30f });
            Add(new ItemDef { id = "synth_beer", name = "Liberty Lager", desc = "+15 armor, blurry vision for 40s.", kind = ItemKind.Consumable, price = 20, buff = "drunk", buffTime = 40f });
            Add(new ItemDef { id = "ammo_light", name = "Light Ammo", desc = "Pistols and SMGs.", kind = ItemKind.Ammo, price = 2 });
            Add(new ItemDef { id = "ammo_rifle", name = "Rifle Ammo", desc = "Assault rifles and tech carbines.", kind = ItemKind.Ammo, price = 3 });
            Add(new ItemDef { id = "ammo_shells", name = "Shotgun Shells", desc = "Buckshot.", kind = ItemKind.Ammo, price = 5 });
            Add(new ItemDef { id = "ammo_heavy", name = "Heavy Rounds", desc = "Revolvers and sniper rifles.", kind = ItemKind.Ammo, price = 8 });
            Add(new ItemDef { id = "frag", name = "Frag Grenade", desc = "Throw with G. 7m blast radius.", kind = ItemKind.Grenade, price = 130, maxStack = 6 });
            Add(new ItemDef { id = "emp", name = "EMP Grenade", desc = "Stuns chrome, fries drones and cameras.", kind = ItemKind.Grenade, price = 160, maxStack = 6 });
            Add(new ItemDef { id = "scrap", name = "Tech Scrap", desc = "Used to upgrade weapons at a gunsmith.", kind = ItemKind.Component, price = 14 });
            Add(new ItemDef { id = "data_chip", name = "Corrupted Data Chip", desc = "Some fence will pay for it.", kind = ItemKind.Junk, price = 45 });
            Add(new ItemDef { id = "gold_watch", name = "Gold Watch", desc = "Real gold. Probably.", kind = ItemKind.Junk, price = 140 });
            Add(new ItemDef { id = "optic", name = "Broken Cyber-Optic", desc = "Still has resale value.", kind = ItemKind.Junk, price = 90 });
            Add(new ItemDef { id = "amulet", name = "Silver Saint Medal", desc = "Old St. Christopher medal. Collectors love these.", kind = ItemKind.Junk, price = 220 });
            Add(new ItemDef { id = "lotus_chip", name = "LOTUS Prototype Chip", desc = "Something is alive in there.", kind = ItemKind.Quest, price = 0, maxStack = 1 });
            Add(new ItemDef { id = "package", name = "Sealed Package", desc = "Don't open it. Don't ask.", kind = ItemKind.Quest, price = 0 });
            Add(new ItemDef { id = "relay_key", name = "Relay Access Key", desc = "Decrypted convoy routing data.", kind = ItemKind.Quest, price = 0 });
        }

        static void Add(ItemDef d) => defs[d.id] = d;
        public static ItemDef Get(string id) => id != null && defs.TryGetValue(id, out var d) ? d : null;
    }

    public class Inventory : MonoBehaviour
    {
        readonly Dictionary<string, int> items = new Dictionary<string, int>();
        public readonly List<WeaponInstance> weapons = new List<WeaponInstance>();
        public readonly WeaponInstance[] slots = new WeaponInstance[4];
        public event Action Changed;

        public int Count(string id) => id != null && items.TryGetValue(id, out var n) ? n : 0;
        public bool Has(string id, int n = 1) => Count(id) >= n;
        public IEnumerable<KeyValuePair<string, int>> AllItems => items;

        public void Add(string id, int n = 1, bool notify = true)
        {
            if (string.IsNullOrEmpty(id) || n <= 0) return;
            var def = Items.Get(id);
            int max = def != null ? def.maxStack : 999;
            items[id] = Mathf.Min(max, Count(id) + n);
            if (notify) Game.UI?.Notify("+" + n + " " + (def != null ? def.name : id), Palette.Cyan);
            GameEvents.RaiseItemAdded(id, n);
            Changed?.Invoke();
        }

        public bool Remove(string id, int n = 1)
        {
            if (Count(id) < n) return false;
            items[id] = Count(id) - n;
            if (items[id] <= 0) items.Remove(id);
            Changed?.Invoke();
            return true;
        }

        public int Ammo(AmmoType t) => Count(Weapons.AmmoItem(t));
        public int TakeAmmo(AmmoType t, int wanted)
        {
            var id = Weapons.AmmoItem(t);
            int got = Mathf.Min(wanted, Count(id));
            if (got > 0) Remove(id, got);
            return got;
        }

        public void AddWeapon(WeaponInstance w, bool autoEquip)
        {
            if (w == null || w.Def == null) return;
            weapons.Add(w);
            Game.UI?.Notify("Acquired " + w.DisplayName + " [" + Weapons.RarityName(w.tier) + "]", w.RarityColor);
            if (autoEquip)
            {
                for (int i = 0; i < slots.Length; i++)
                    if (slots[i] == null) { slots[i] = w; break; }
            }
            Changed?.Invoke();
        }

        public void RemoveWeapon(WeaponInstance w)
        {
            weapons.Remove(w);
            for (int i = 0; i < slots.Length; i++) if (slots[i] == w) slots[i] = null;
            Changed?.Invoke();
        }

        public void Equip(WeaponInstance w, int slot)
        {
            if (slot < 0 || slot >= slots.Length) return;
            for (int i = 0; i < slots.Length; i++) if (slots[i] == w) slots[i] = null;
            slots[slot] = w;
            Game.Weapons?.OnLoadoutChanged();
            Changed?.Invoke();
        }

        public bool Use(string id)
        {
            var def = Items.Get(id);
            if (def == null || def.kind != ItemKind.Consumable || !Has(id)) return false;
            var s = Game.Stats;
            if (s == null) return false;
            Remove(id);
            if (def.heal > 0) s.HealFraction(def.heal);
            if (def.healOverTime > 0) s.AddRegen(def.healOverTime, 10f);
            if (def.ram > 0) s.RestoreRam(def.ram);
            if (def.stamina > 0) s.stamina = s.MaxStamina;
            if (!string.IsNullOrEmpty(def.buff)) s.AddBuff(def.buff, def.buffTime);
            Game.Audio?.Play2D(def.id == "volt_cola" || def.id == "synth_beer" ? "vend" : "pickup", 0.7f);
            Game.UI?.Notify("Used " + def.name, Palette.Green);
            return true;
        }

        public void Clear()
        {
            items.Clear(); weapons.Clear();
            for (int i = 0; i < slots.Length; i++) slots[i] = null;
        }

        public void SaveTo(SaveData d)
        {
            d.items.Clear();
            foreach (var kv in items) d.items.Add(new ItemStack { id = kv.Key, count = kv.Value });
            d.weapons.Clear();
            foreach (var w in weapons) d.weapons.Add(new WeaponSave { defId = w.defId, tier = w.tier, mod = w.mod, ammoInMag = w.ammoInMag, uid = w.uid });
            d.equipped.Clear();
            foreach (var s in slots) d.equipped.Add(s != null ? s.uid : "");
        }

        public void LoadFrom(SaveData d)
        {
            Clear();
            foreach (var it in d.items) items[it.id] = it.count;
            foreach (var ws in d.weapons)
                weapons.Add(new WeaponInstance { defId = ws.defId, tier = ws.tier, mod = ws.mod, ammoInMag = ws.ammoInMag, uid = ws.uid });
            for (int i = 0; i < slots.Length && i < d.equipped.Count; i++)
                slots[i] = weapons.Find(w => w.uid == d.equipped[i]);
            Changed?.Invoke();
        }
    }

    public static class Loot
    {
        public static WeaponInstance RandomWeapon(int level, int minTier = 0)
        {
            var pool = new[] { "kite9", "kite9", "hornet", "mauler", "longwire", "thunderhead", "rebar", "monoblade", "volt", "hush" };
            int maxIdx = Mathf.Clamp(4 + level / 2, 4, pool.Length);
            var id = pool[UnityEngine.Random.Range(0, maxIdx)];
            float roll = UnityEngine.Random.value + level * 0.02f;
            int tier = roll > 1.05f ? 4 : roll > 0.92f ? 3 : roll > 0.75f ? 2 : roll > 0.45f ? 1 : 0;
            return new WeaponInstance(id, Mathf.Max(minTier, tier));
        }

        public static void RollEnemy(NPC npc)
        {
            var pos = npc.transform.position;
            int lvl = npc.level;
            bool scav = Game.Stats != null && Game.Stats.HasPerk("scavenger");
            Pickup.Spawn(pos + Offset(), null, 0, UnityEngine.Random.Range(10, 40) + lvl * 6);
            if (npc.weaponDef != null && npc.weaponDef.ammo != AmmoType.None)
                Pickup.Spawn(pos + Offset(), Weapons.AmmoItem(npc.weaponDef.ammo), UnityEngine.Random.Range(6, 20) * (scav ? 2 : 1));
            float wChance = npc.archetype == Archetype.Boss ? 1f : 0.12f + (scav ? 0.1f : 0f);
            if (UnityEngine.Random.value < wChance)
                Pickup.Spawn(pos + Offset(), null, 0, 0, npc.weaponDef != null ? new WeaponInstance(npc.weaponDef.id, npc.archetype == Archetype.Boss ? 3 : UnityEngine.Random.Range(0, 3)) : RandomWeapon(lvl));
            if (UnityEngine.Random.value < 0.35f) Pickup.Spawn(pos + Offset(), "scrap", UnityEngine.Random.Range(1, 4));
            if (UnityEngine.Random.value < 0.12f) Pickup.Spawn(pos + Offset(), UnityEngine.Random.value < 0.5f ? "medkit" : "data_chip", 1);
            if (UnityEngine.Random.value < 0.06f) Pickup.Spawn(pos + Offset(), "frag", 1);
        }

        public static void RollCrate(int tier, Vector3 pos)
        {
            int lvl = Game.Stats != null ? Game.Stats.Level : 1;
            Pickup.Spawn(pos + Offset() + Vector3.up * 0.5f, null, 0, UnityEngine.Random.Range(40, 120) * (tier + 1));
            Pickup.Spawn(pos + Offset() + Vector3.up * 0.5f, "scrap", UnityEngine.Random.Range(2, 6) + tier);
            var ammo = new[] { "ammo_light", "ammo_rifle", "ammo_shells", "ammo_heavy" };
            Pickup.Spawn(pos + Offset() + Vector3.up * 0.5f, ammo[UnityEngine.Random.Range(0, ammo.Length)], UnityEngine.Random.Range(10, 30));
            if (UnityEngine.Random.value < 0.3f + tier * 0.2f) Pickup.Spawn(pos + Offset() + Vector3.up * 0.5f, null, 0, 0, RandomWeapon(lvl + tier * 2, Mathf.Min(tier, 3)));
            var junk = new[] { "gold_watch", "optic", "amulet", "data_chip", "medkit", "ram_shot", "stim" };
            Pickup.Spawn(pos + Offset() + Vector3.up * 0.5f, junk[UnityEngine.Random.Range(0, junk.Length)], 1);
        }

        static Vector3 Offset() => new Vector3(UnityEngine.Random.Range(-0.8f, 0.8f), 0.1f, UnityEngine.Random.Range(-0.8f, 0.8f));
    }
}
