using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum WeaponClass { Fists, Melee, Pistol, Revolver, SMG, Shotgun, Rifle, Sniper, Tech }
    public enum AmmoType { None, Light, Rifle, Shells, Heavy }
    public enum Rarity { Common, Uncommon, Rare, Epic, Legendary }

    public class WeaponDef
    {
        public string id, name, desc;
        public WeaponClass cls;
        public AmmoType ammo;
        public DamageType damageType = DamageType.Ballistic;
        public float damage;
        public int pellets = 1;
        public float fireRate;      // shots per second
        public bool auto;
        public int mag;
        public float reload;
        public float spread, adsSpread;   // degrees
        public float range;
        public float recoil;        // degrees of camera kick per shot
        public float adsFov = 55f;
        public string sound;
        public int price;
        public Color accent = Palette.Cyan;
        public float meleeRange = 2.2f;
        public bool bleed;
        public bool scoped;
        public Vector3 size = new Vector3(0.06f, 0.12f, 0.35f);   // model dimensions
        public bool IsMelee => cls == WeaponClass.Melee || cls == WeaponClass.Fists;
    }

    public static class Weapons
    {
        static readonly Dictionary<string, WeaponDef> defs = new Dictionary<string, WeaponDef>();
        public static IEnumerable<WeaponDef> All => defs.Values;

        static Weapons()
        {
            Add(new WeaponDef { id = "fists", name = "Bare Fists", desc = "Knuckles and bad intentions. Scales with BODY.", cls = WeaponClass.Fists, damage = 16, fireRate = 2.4f, meleeRange = 2f, sound = "punch", price = 0, accent = Palette.Orange });
            Add(new WeaponDef { id = "rebar", name = "Rebar Club", desc = "A length of rebar wrapped in tape. Brutal and honest.", cls = WeaponClass.Melee, damage = 34, fireRate = 1.5f, meleeRange = 2.4f, sound = "swing", price = 250, accent = Palette.Orange, size = new Vector3(0.05f, 0.05f, 0.9f) });
            Add(new WeaponDef { id = "monoblade", name = "Mono-Katana", desc = "Monomolecular edge. Causes bleeding.", cls = WeaponClass.Melee, damage = 58, fireRate = 1.7f, meleeRange = 2.6f, sound = "slash", bleed = true, price = 2200, accent = Palette.Cyan, size = new Vector3(0.03f, 0.06f, 1.0f) });
            Add(new WeaponDef { id = "kite9", name = "Kite-9 Pistol", desc = "Reliable street sidearm. Fast follow-up shots.", cls = WeaponClass.Pistol, ammo = AmmoType.Light, damage = 24, fireRate = 4.5f, mag = 12, reload = 1.35f, spread = 1.6f, adsSpread = 0.35f, range = 75, recoil = 1.6f, sound = "pistol", price = 450, accent = Palette.Cyan, size = new Vector3(0.05f, 0.13f, 0.26f) });
            Add(new WeaponDef { id = "thunderhead", name = "Thunderhead Revolver", desc = "Hand cannon. Six chances to be right.", cls = WeaponClass.Revolver, ammo = AmmoType.Heavy, damage = 72, fireRate = 1.6f, mag = 6, reload = 2.3f, spread = 1.3f, adsSpread = 0.15f, range = 110, recoil = 6f, sound = "revolver", price = 1600, accent = Palette.Yellow, size = new Vector3(0.06f, 0.14f, 0.34f) });
            Add(new WeaponDef { id = "hornet", name = "Hornet SMG", desc = "Sprays a swarm of lead. Great up close.", cls = WeaponClass.SMG, ammo = AmmoType.Light, damage = 13, fireRate = 13f, auto = true, mag = 36, reload = 1.8f, spread = 3.2f, adsSpread = 1.4f, range = 45, recoil = 0.85f, sound = "smg", price = 1300, accent = Palette.Magenta, size = new Vector3(0.06f, 0.14f, 0.42f) });
            Add(new WeaponDef { id = "mauler", name = "Mauler Shotgun", desc = "Nine pellets of conflict resolution.", cls = WeaponClass.Shotgun, ammo = AmmoType.Shells, damage = 12, pellets = 9, fireRate = 1.2f, mag = 6, reload = 2.8f, spread = 6.5f, adsSpread = 4.5f, range = 24, recoil = 9f, sound = "shotgun", price = 1500, accent = Palette.Red, size = new Vector3(0.07f, 0.13f, 0.75f) });
            Add(new WeaponDef { id = "longwire", name = "Longwire AR", desc = "Military surplus assault rifle. Versatile.", cls = WeaponClass.Rifle, ammo = AmmoType.Rifle, damage = 26, fireRate = 9.5f, auto = true, mag = 30, reload = 2.1f, spread = 1.9f, adsSpread = 0.45f, range = 150, recoil = 1.25f, sound = "rifle", price = 2600, accent = Palette.Green, size = new Vector3(0.06f, 0.15f, 0.8f) });
            Add(new WeaponDef { id = "volt", name = "Volt Carbine", desc = "Tech rifle firing charged slugs. Double damage to drones and chrome.", cls = WeaponClass.Tech, ammo = AmmoType.Rifle, damageType = DamageType.Electric, damage = 23, fireRate = 6f, auto = true, mag = 24, reload = 2f, spread = 1.4f, adsSpread = 0.35f, range = 120, recoil = 1.1f, sound = "smg", price = 3400, accent = Palette.Blue, size = new Vector3(0.07f, 0.16f, 0.7f) });
            Add(new WeaponDef { id = "hush", name = "Hush-1 Sniper", desc = "Bolt-action precision rifle with a 6x optic.", cls = WeaponClass.Sniper, ammo = AmmoType.Heavy, damage = 150, fireRate = 0.8f, mag = 5, reload = 3f, spread = 5f, adsSpread = 0.03f, range = 450, recoil = 10f, adsFov = 18f, scoped = true, sound = "sniper", price = 4500, accent = Palette.Purple, size = new Vector3(0.06f, 0.14f, 1.1f) });
        }

        static void Add(WeaponDef d) => defs[d.id] = d;
        public static WeaponDef Get(string id) => id != null && defs.TryGetValue(id, out var d) ? d : null;

        public static string AmmoItem(AmmoType t) => t switch
        {
            AmmoType.Light => "ammo_light",
            AmmoType.Rifle => "ammo_rifle",
            AmmoType.Shells => "ammo_shells",
            AmmoType.Heavy => "ammo_heavy",
            _ => null
        };

        public static Color RarityColor(int tier) => tier switch
        {
            0 => new Color(0.85f, 0.85f, 0.85f),
            1 => new Color(0.3f, 1f, 0.4f),
            2 => new Color(0.25f, 0.6f, 1f),
            3 => new Color(0.75f, 0.3f, 1f),
            _ => new Color(1f, 0.65f, 0.1f)
        };

        public static string RarityName(int tier) => ((Rarity)Mathf.Clamp(tier, 0, 4)).ToString();
    }

    [Serializable]
    public class WeaponInstance
    {
        public string defId;
        public int tier;
        public int mod;
        public int ammoInMag;
        public string uid;

        public WeaponInstance() { }
        public WeaponInstance(string def, int tier = 0)
        {
            defId = def; this.tier = Mathf.Clamp(tier, 0, 4);
            uid = Guid.NewGuid().ToString("N").Substring(0, 10);
            var d = Def;
            ammoInMag = d != null ? d.mag : 0;
        }

        public WeaponDef Def => Weapons.Get(defId);
        public float DamageMult => 1f + tier * 0.15f + mod * 0.08f;
        public string DisplayName => (Def?.name ?? defId) + (mod > 0 ? " +" + mod : "");
        public Color RarityColor => Weapons.RarityColor(tier);
        public int SellValue => Mathf.RoundToInt((Def?.price ?? 50) * 0.3f * (1 + tier * 0.5f) * (1 + mod * 0.2f));
        public int UpgradeCost => Mathf.RoundToInt((Def?.price ?? 200) * 0.25f * (mod + 1));
        public int UpgradeScrap => 4 + mod * 3;
    }
}
