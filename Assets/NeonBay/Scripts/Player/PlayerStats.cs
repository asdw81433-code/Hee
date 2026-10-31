using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum Origin { GutterKid, CorpWashout, BadlandsRunner }
    public enum Attr { Body, Reflex, Tech, Neural, Cool }

    [Serializable]
    public class CharacterProfile
    {
        public string name = "Nok";
        public Origin origin = Origin.GutterKid;
        public int frame;          // 0 lean, 1 athletic, 2 heavy
        public int skin = 2;
        public int hairStyle = 1;  // 0 shaved, 1 short, 2 mohawk, 3 long, 4 topknot
        public int hairColor;
        public Color eyeColor = Palette.Cyan;
        public Color cyberColor = Palette.Magenta;
        public bool faceTattoo = true;
        public float height = 1f;
        public Color jacket = new Color(0.12f, 0.12f, 0.15f);
        public Color accent = Palette.Magenta;
        public int difficulty = 1;
        public int[] attributes = { 3, 3, 3, 3, 3 };

        public static string OriginName(Origin o) => o switch
        {
            Origin.GutterKid => "Gutter Kid",
            Origin.CorpWashout => "Corp Washout",
            _ => "Badlands Runner"
        };

        public static string OriginDesc(Origin o) => o switch
        {
            Origin.GutterKid => "Born under the flooded overpasses of Lowtown. You know every gang, every shortcut and every lie the street tells.\n+1 COOL, starts with a Kite-9 pistol and a Rebar Club, gang contacts open unique dialogue.",
            Origin.CorpWashout => "Six years as a Helix Dynamics data analyst, until they scapegoated you for a breach. You know how the corps think - and how to hurt them.\n+1 NEURAL, $1,800, a Synapse Deck, corp dialogue options.",
            _ => "You grew up running salvage convoys through the Scar. Machines, engines and the open road are in your blood.\n+1 BODY, starts with your own car (the Rust Kestrel) and a Mauler shotgun."
        };

        public static string FrameName(int f) => f == 0 ? "Lean" : f == 1 ? "Athletic" : "Heavy";
        public static string HairName(int h) => h switch { 0 => "Shaved", 1 => "Short Crop", 2 => "Neon Mohawk", 3 => "Long", _ => "Top Knot" };
    }

    public class PerkDef
    {
        public string id, name, desc;
        public Attr attr;
        public int req;
    }

    public enum CyberSlot { Optics, Neural, Arms, Legs, Nervous, Skeleton, Skin }

    public class CyberwareDef
    {
        public string id, name, desc;
        public CyberSlot slot;
        public int price, level;
    }

    public static class Perks
    {
        public static readonly List<PerkDef> All = new List<PerkDef>
        {
            new PerkDef { id = "iron_knuckles", name = "Iron Knuckles", desc = "+40% melee damage.", attr = Attr.Body, req = 4 },
            new PerkDef { id = "thick_skin", name = "Thick Skin", desc = "+30 max health.", attr = Attr.Body, req = 5 },
            new PerkDef { id = "adrenal_rush", name = "Adrenal Rush", desc = "Melee kills restore 15% health.", attr = Attr.Body, req = 6 },
            new PerkDef { id = "rebar_spine", name = "Rebar Spine", desc = "-15% damage taken.", attr = Attr.Body, req = 8 },
            new PerkDef { id = "juggernaut", name = "Juggernaut", desc = "Sprinting into enemies knocks them down.", attr = Attr.Body, req = 10 },

            new PerkDef { id = "steady_hands", name = "Steady Hands", desc = "-25% weapon spread.", attr = Attr.Reflex, req = 4 },
            new PerkDef { id = "quick_draw", name = "Quick Draw", desc = "+30% reload and swap speed.", attr = Attr.Reflex, req = 5 },
            new PerkDef { id = "headhunter", name = "Headhunter", desc = "+35% headshot damage.", attr = Attr.Reflex, req = 6 },
            new PerkDef { id = "run_and_gun", name = "Run & Gun", desc = "No accuracy penalty while moving.", attr = Attr.Reflex, req = 8 },
            new PerkDef { id = "bullet_tempo", name = "Bullet Tempo", desc = "Kills grant +25% fire rate for 4s.", attr = Attr.Reflex, req = 10 },

            new PerkDef { id = "tinkerer", name = "Tinkerer", desc = "Shop prices -15%, upgrades cost less scrap.", attr = Attr.Tech, req = 4 },
            new PerkDef { id = "armor_weave", name = "Armor Weave", desc = "+25 armor.", attr = Attr.Tech, req = 5 },
            new PerkDef { id = "grenadier", name = "Grenadier", desc = "+40% explosion damage and radius.", attr = Attr.Tech, req = 6 },
            new PerkDef { id = "wheelman", name = "Wheelman", desc = "Vehicles are 30% tougher and faster.", attr = Attr.Tech, req = 7 },
            new PerkDef { id = "scavenger", name = "Scavenger", desc = "Enemies drop more ammo and weapons.", attr = Attr.Tech, req = 8 },

            new PerkDef { id = "overclock", name = "Overclock", desc = "+2 RAM.", attr = Attr.Neural, req = 4 },
            new PerkDef { id = "fast_uplink", name = "Fast Uplink", desc = "Quickhacks upload 35% faster.", attr = Attr.Neural, req = 5 },
            new PerkDef { id = "viral_code", name = "Viral Code", desc = "+35% quickhack damage.", attr = Attr.Neural, req = 6 },
            new PerkDef { id = "ram_recycler", name = "RAM Recycler", desc = "Kills restore 1 RAM.", attr = Attr.Neural, req = 7 },
            new PerkDef { id = "ghost_signal", name = "Ghost Signal", desc = "Quickhacks don't reveal your position.", attr = Attr.Neural, req = 9 },

            new PerkDef { id = "silent_steps", name = "Silent Steps", desc = "Enemies detect you 40% slower.", attr = Attr.Cool, req = 4 },
            new PerkDef { id = "assassin", name = "Assassin", desc = "+100% damage against unaware targets.", attr = Attr.Cool, req = 5 },
            new PerkDef { id = "cold_blood", name = "Cold Blood", desc = "+12% critical chance.", attr = Attr.Cool, req = 6 },
            new PerkDef { id = "smooth_talker", name = "Smooth Talker", desc = "+20% rewards from gigs and quests.", attr = Attr.Cool, req = 7 },
            new PerkDef { id = "vanish", name = "Vanish", desc = "Police heat fades twice as fast.", attr = Attr.Cool, req = 8 },
        };

        public static PerkDef Get(string id) => All.Find(p => p.id == id);
    }

    public static class CyberwareDB
    {
        public static readonly List<CyberwareDef> All = new List<CyberwareDef>
        {
            new CyberwareDef { id = "optics_mk1", name = "Vantablink Optics Mk.I", desc = "Scanner zoom, +5% critical chance.", slot = CyberSlot.Optics, price = 900, level = 1 },
            new CyberwareDef { id = "optics_mk2", name = "Vantablink Optics Mk.II", desc = "+12% critical chance, scanning reveals enemies through walls.", slot = CyberSlot.Optics, price = 3600, level = 6 },
            new CyberwareDef { id = "deck_mk1", name = "Synapse Deck Mk.I", desc = "+2 RAM, +10% quickhack damage.", slot = CyberSlot.Neural, price = 1200, level = 1 },
            new CyberwareDef { id = "deck_mk2", name = "Synapse Deck Mk.II", desc = "+5 RAM, +30% quickhack damage, faster RAM regen.", slot = CyberSlot.Neural, price = 4400, level = 7 },
            new CyberwareDef { id = "stabilizer_arms", name = "Gyro-Stabilizer Arms", desc = "-35% recoil, +20% reload speed.", slot = CyberSlot.Arms, price = 1900, level = 2 },
            new CyberwareDef { id = "piston_fists", name = "Piston Fists", desc = "+80% unarmed and melee damage, punches send people flying.", slot = CyberSlot.Arms, price = 2100, level = 3 },
            new CyberwareDef { id = "spring_legs", name = "Spring Legs", desc = "Enables a mid-air double jump.", slot = CyberSlot.Legs, price = 2300, level = 3 },
            new CyberwareDef { id = "pneumatic_calves", name = "Pneumatic Calves", desc = "+15% movement speed, -60% fall damage.", slot = CyberSlot.Legs, price = 1500, level = 1 },
            new CyberwareDef { id = "chronoweave", name = "Chronoweave Reflex Booster", desc = "[Q] Slow time to 30% for 5s. 35s cooldown.", slot = CyberSlot.Nervous, price = 4200, level = 5 },
            new CyberwareDef { id = "adrenal_pump", name = "Adrenal Pump", desc = "Regenerate health quickly while below 40%.", slot = CyberSlot.Nervous, price = 1700, level = 2 },
            new CyberwareDef { id = "titan_bones", name = "Titanium Bones", desc = "+60 max health.", slot = CyberSlot.Skeleton, price = 1800, level = 2 },
            new CyberwareDef { id = "subdermal", name = "Subdermal Plating", desc = "+40 armor.", slot = CyberSlot.Skin, price = 1500, level = 1 },
            new CyberwareDef { id = "camo_mesh", name = "Optical Camo Mesh", desc = "[X] Become nearly invisible for 7s. 45s cooldown.", slot = CyberSlot.Skin, price = 3900, level = 5 },
        };

        public static CyberwareDef Get(string id) => All.Find(c => c.id == id);
    }

    /// <summary>RPG state of the player: attributes, derived stats, level, perks, cyberware, money, buffs.</summary>
    public class PlayerStats : MonoBehaviour
    {
        public int[] attributes = { 3, 3, 3, 3, 3 };
        public int Level = 1;
        public int XP;
        public int PerkPoints;
        public int AttributePoints;
        public int Money;
        public int StreetCred;
        public readonly HashSet<string> perks = new HashSet<string>();
        public readonly List<string> cyberware = new List<string>();
        public readonly List<string> quickhacks = new List<string> { "ping", "overload" };

        public Damageable dmg;
        public float stamina = 100f;
        public float ram = 5f;
        readonly Dictionary<string, float> buffs = new Dictionary<string, float>();
        float regenPool, regenRate;
        public float chronoCooldown, camoCooldown;
        float killTempo;
        float heartbeatTimer;

        public int Attr(Attr a) => attributes[(int)a];
        public bool HasPerk(string id) => perks.Contains(id);
        public bool HasCyber(string id) => cyberware.Contains(id);
        public bool HasBuff(string id) => buffs.TryGetValue(id, out var t) && t > 0f;
        public float BuffTime(string id) => buffs.TryGetValue(id, out var t) ? t : 0f;

        // ----------------------------------------------------------- derived stats
        public float MaxHealth => 80f + Attr(NeonBay.Attr.Body) * 10f + Level * 5f + (HasPerk("thick_skin") ? 30 : 0) + (HasCyber("titan_bones") ? 60 : 0);
        public float ArmorValue => 5f + Level * 1.5f + (HasPerk("armor_weave") ? 25 : 0) + (HasCyber("subdermal") ? 40 : 0) + (HasBuff("drunk") ? 15 : 0);
        public float MaxStamina => 80f + Attr(NeonBay.Attr.Reflex) * 6f;
        public int MaxRam => 3 + Attr(NeonBay.Attr.Neural) + (HasPerk("overclock") ? 2 : 0) + (HasCyber("deck_mk1") ? 2 : 0) + (HasCyber("deck_mk2") ? 5 : 0);
        public float CritChance => 0.05f + Attr(NeonBay.Attr.Cool) * 0.015f + (HasPerk("cold_blood") ? 0.12f : 0) + (HasCyber("optics_mk1") ? 0.05f : 0) + (HasCyber("optics_mk2") ? 0.12f : 0);
        public float CritDamage => 0.5f + Attr(NeonBay.Attr.Cool) * 0.04f;
        public float MoveMult => 1f + Attr(NeonBay.Attr.Reflex) * 0.012f + (HasCyber("pneumatic_calves") ? 0.15f : 0) + (HasBuff("stim") ? 0.25f : 0);
        public float MeleeMult => (1f + Attr(NeonBay.Attr.Body) * 0.06f) * (HasPerk("iron_knuckles") ? 1.4f : 1f) * (HasCyber("piston_fists") ? 1.8f : 1f);
        public float HackMult => (1f + Attr(NeonBay.Attr.Neural) * 0.07f) * (HasPerk("viral_code") ? 1.35f : 1f) * (HasCyber("deck_mk1") ? 1.1f : 1f) * (HasCyber("deck_mk2") ? 1.3f : 1f);
        public float UploadMult => HasPerk("fast_uplink") ? 0.65f : 1f;
        public float ReloadMult => (HasPerk("quick_draw") ? 0.7f : 1f) * (HasCyber("stabilizer_arms") ? 0.8f : 1f) * (1f - Attr(NeonBay.Attr.Reflex) * 0.015f);
        public float RecoilMult => (HasCyber("stabilizer_arms") ? 0.65f : 1f) * (1f - Attr(NeonBay.Attr.Reflex) * 0.02f);
        public float SpreadMult => (HasPerk("steady_hands") ? 0.75f : 1f) * (1f - Attr(NeonBay.Attr.Reflex) * 0.02f);
        public float FireRateMult => killTempo > 0 ? 1.25f : 1f;
        public float DetectionMult => (HasPerk("silent_steps") ? 0.6f : 1f) * (1f - Attr(NeonBay.Attr.Cool) * 0.03f) * (HasBuff("camo") ? 0.08f : 1f);
        public float PriceMult => (HasPerk("tinkerer") ? 0.85f : 1f) * (1f - Mathf.Min(0.15f, StreetCred / 1000f));
        public float DamageTakenMult => HasPerk("rebar_spine") ? 0.85f : 1f;
        public float RewardMult => HasPerk("smooth_talker") ? 1.2f : 1f;
        public int XPToNext => Mathf.RoundToInt(120 + 85 * Mathf.Pow(Level, 1.35f));

        public void Init(CharacterProfile p)
        {
            attributes = (int[])p.attributes.Clone();
            dmg = GetComponent<Damageable>();
            Recalc(true);
        }

        public void Recalc(bool fill = false)
        {
            if (dmg == null) dmg = GetComponent<Damageable>();
            float frac = dmg.Fraction;
            dmg.maxHealth = MaxHealth;
            dmg.armor = ArmorValue;
            dmg.health = fill ? dmg.maxHealth : Mathf.Max(1f, frac * dmg.maxHealth);
            if (fill) { stamina = MaxStamina; ram = MaxRam; }
            ram = Mathf.Min(ram, MaxRam);
        }

        void Update()
        {
            float dt = Time.deltaTime;
            if (dmg == null || dmg.isDead) return;
            // buffs
            var keys = new List<string>(buffs.Keys);
            foreach (var k in keys)
            {
                buffs[k] -= k == "chrono" ? Time.unscaledDeltaTime : dt;
                if (buffs[k] <= 0f)
                {
                    buffs.Remove(k);
                    if (k == "chrono") Game.Manager?.SetSlowMotion(false);
                    if (k == "drunk") Recalc();
                }
            }
            if (chronoCooldown > 0) chronoCooldown -= Time.unscaledDeltaTime;
            if (camoCooldown > 0) camoCooldown -= dt;
            if (killTempo > 0) killTempo -= dt;

            // regeneration
            if (regenPool > 0f)
            {
                float h = Mathf.Min(regenPool, regenRate * dt);
                regenPool -= h; dmg.Heal(h);
            }
            if (HasCyber("adrenal_pump") && dmg.Fraction < 0.4f) dmg.Heal(6f * dt);
            if (Time.time - dmg.lastDamageTime > 6f && dmg.Fraction < 0.35f) dmg.Heal(1.5f * dt); // trauma auto-stabilise

            float ramRegen = (0.18f + Attr(NeonBay.Attr.Neural) * 0.02f) * (HasCyber("deck_mk2") ? 1.5f : 1f);
            ram = Mathf.Min(MaxRam, ram + ramRegen * dt);
            float stamRegen = 22f * (HasBuff("volt") ? 1.5f : 1f) * (HasBuff("spice") ? 1.25f : 1f);
            if (HasBuff("stim")) stamina = MaxStamina;
            stamina = Mathf.Min(MaxStamina, stamina + stamRegen * dt);

            if (dmg.Fraction < 0.25f)
            {
                heartbeatTimer -= dt;
                if (heartbeatTimer <= 0f) { heartbeatTimer = 0.9f; Game.Audio?.Play2D("heartbeat", 0.6f); }
            }
        }

        // ----------------------------------------------------------- money & xp
        public void AddMoney(int amount)
        {
            Money = Mathf.Max(0, Money + amount);
            if (amount > 0) Game.Audio?.Play2D("cash", 0.5f);
        }

        public bool Spend(int amount)
        {
            if (Money < amount) return false;
            Money -= amount;
            return true;
        }

        public void AddXP(int amount)
        {
            XP += amount;
            Game.UI?.XpPopup(amount);
            while (XP >= XPToNext)
            {
                XP -= XPToNext;
                Level++;
                PerkPoints++;
                AttributePoints++;
                Recalc();
                dmg.Heal(dmg.maxHealth);
                Game.Audio?.Play2D("levelup");
                Game.UI?.Banner("LEVEL " + Level, "+1 attribute point   +1 perk point   [K] to spend", Palette.Yellow);
                GameEvents.RaiseLevelUp(Level);
            }
        }

        public void AddCred(int amount)
        {
            StreetCred = Mathf.Clamp(StreetCred + amount, 0, 999);
        }

        public bool RaiseAttribute(Attr a)
        {
            if (AttributePoints <= 0 || attributes[(int)a] >= 15) return false;
            attributes[(int)a]++;
            AttributePoints--;
            Recalc();
            return true;
        }

        public bool CanBuyPerk(PerkDef p) => p != null && !HasPerk(p.id) && PerkPoints > 0 && Attr(p.attr) >= p.req;
        public bool BuyPerk(PerkDef p)
        {
            if (!CanBuyPerk(p)) return false;
            perks.Add(p.id);
            PerkPoints--;
            Recalc();
            return true;
        }

        public CyberwareDef InSlot(CyberSlot slot)
        {
            foreach (var id in cyberware) { var d = CyberwareDB.Get(id); if (d != null && d.slot == slot) return d; }
            return null;
        }

        public void Install(CyberwareDef d)
        {
            var old = InSlot(d.slot);
            if (old != null) cyberware.Remove(old.id);
            cyberware.Add(d.id);
            Recalc();
        }

        // ----------------------------------------------------------- consumables & combat hooks
        public void HealFraction(float f) => dmg.Heal(dmg.maxHealth * f);
        public void AddRegen(float amount, float duration) { regenPool += amount; regenRate = Mathf.Max(regenRate, amount / duration); }
        public void RestoreRam(float r) => ram = Mathf.Min(MaxRam, ram + r);
        public bool UseRam(float r) { if (ram < r) return false; ram -= r; return true; }
        public void AddBuff(string id, float t) { buffs[id] = Mathf.Max(BuffTime(id), t); if (id == "drunk") Recalc(); }
        public void ClearBuffs() { buffs.Clear(); Game.Manager?.SetSlowMotion(false); }

        public void OnKill(NPC npc, DamageInfo info)
        {
            if (HasPerk("ram_recycler")) RestoreRam(1);
            if (HasPerk("bullet_tempo")) killTempo = 4f;
            if (HasPerk("adrenal_rush") && info.type == DamageType.Melee) HealFraction(0.15f);
        }

        public bool TryChronoweave()
        {
            if (!HasCyber("chronoweave") || chronoCooldown > 0 || HasBuff("chrono")) return false;
            chronoCooldown = 35f;
            AddBuff("chrono", 5f);
            Game.Manager?.SetSlowMotion(true);
            Game.Audio?.Play2D("slowmo");
            return true;
        }

        public bool TryCamo()
        {
            if (!HasCyber("camo_mesh") || camoCooldown > 0) return false;
            camoCooldown = 45f;
            AddBuff("camo", 7f);
            Game.Audio?.Play2D("glitch", 0.6f);
            return true;
        }

        public void SaveTo(SaveData d)
        {
            d.level = Level; d.xp = XP; d.perkPoints = PerkPoints; d.attributePoints = AttributePoints;
            d.attributes = (int[])attributes.Clone();
            d.perks = new List<string>(perks);
            d.cyberware = new List<string>(cyberware);
            d.quickhacks = new List<string>(quickhacks);
            d.money = Money; d.streetCred = StreetCred;
            d.health = dmg != null ? dmg.health : MaxHealth;
        }

        public void LoadFrom(SaveData d)
        {
            Level = Mathf.Max(1, d.level); XP = d.xp; PerkPoints = d.perkPoints; AttributePoints = d.attributePoints;
            if (d.attributes != null && d.attributes.Length == 5) attributes = (int[])d.attributes.Clone();
            perks.Clear(); foreach (var p in d.perks) perks.Add(p);
            cyberware.Clear(); cyberware.AddRange(d.cyberware);
            quickhacks.Clear(); quickhacks.AddRange(d.quickhacks.Count > 0 ? d.quickhacks : new List<string> { "ping", "overload" });
            Money = d.money; StreetCred = d.streetCred;
            Recalc(true);
            if (d.health > 0) dmg.health = Mathf.Min(dmg.maxHealth, d.health);
        }
    }
}
