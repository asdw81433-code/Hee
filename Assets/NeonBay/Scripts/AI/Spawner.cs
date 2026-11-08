using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Creates NPCs and keeps track of named groups for missions and events.</summary>
    public static class Spawner
    {
        static readonly Dictionary<string, List<NPC>> groups = new Dictionary<string, List<NPC>>();
        static readonly Dictionary<string, NPC> byId = new Dictionary<string, NPC>();
        static Rng rng = new Rng(4242);

        static readonly Dictionary<FactionId, string[]> names = new Dictionary<FactionId, string[]>
        {
            { FactionId.Jackals, new[] { "Jackal Runner", "Jackal Bruiser", "Jackal Wirehead", "Jackal Slasher" } },
            { FactionId.Lotus, new[] { "Lotus Enforcer", "Lotus Soldier", "Lotus Cleaner" } },
            { FactionId.Helix, new[] { "Helix Operator", "Helix Sentinel", "Helix Specialist" } },
            { FactionId.Raiders, new[] { "Scar Raider", "Scar Butcher", "Scar Howler" } },
            { FactionId.Police, new[] { "NBPD Officer", "NBPD Sergeant", "NBPD Riot Unit" } },
            { FactionId.Saints, new[] { "Static Saint", "Saint Netrunner" } },
        };
        static readonly string[] civNames = { "Citizen", "Commuter", "Night-shift Worker", "Street Kid", "Office Drone", "Delivery Rider", "Tourist", "Street Preacher", "Line Cook", "Gig Worker" };

        public static NPC Spawn(Archetype a, FactionId f, Vector3 pos, float yaw, int level, string group = null, bool hostile = false, string weapon = null, string name = null, Appearance look = null)
        {
            var go = new GameObject("NPC_" + f + "_" + a) { layer = Layers.Actors };
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0, yaw, 0));
            var rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = true; rb.useGravity = false;
            var dmg = go.AddComponent<Damageable>();
            var npc = go.AddComponent<NPC>();
            npc.archetype = a; npc.faction = f; npc.level = Mathf.Max(1, level); npc.groupId = group; npc.forcedHostile = hostile;
            look ??= Appearance.Random(f, rng);
            if (a == Archetype.Heavy || a == Archetype.Bruiser) look.bulk = Mathf.Max(look.bulk, 1.3f);
            if (a == Archetype.Boss) { look.bulk = Mathf.Max(look.bulk, 1.2f); look.height = Mathf.Max(look.height, 1.06f); }
            npc.rig = HumanoidRig.Build(go.transform, look, dmg, true);
            float hp; float armor = 0;
            switch (a)
            {
                case Archetype.Civilian: hp = 40; break;
                case Archetype.Vendor: hp = 100; break;
                case Archetype.Grunt: hp = 90; break;
                case Archetype.Gunner: hp = 110; armor = 10; break;
                case Archetype.Shotgunner: hp = 125; armor = 10; break;
                case Archetype.Bruiser: hp = 230; armor = 20; break;
                case Archetype.Sniper: hp = 80; break;
                case Archetype.Netrunner: hp = 85; break;
                case Archetype.Heavy: hp = 380; armor = 60; break;
                case Archetype.Boss: hp = 950; armor = 50; break;
                default: hp = 130; armor = 30; break;
            }
            if (f == FactionId.Helix) armor += 20;
            dmg.Init(hp * (1f + (npc.level - 1) * 0.12f), armor);
            dmg.isRobotic = look.chromeSkin;
            if (weapon == null)
            {
                switch (a)
                {
                    case Archetype.Grunt: weapon = rng.Chance(0.5f) ? "kite9" : "hornet"; break;
                    case Archetype.Gunner: weapon = rng.Chance(0.75f) ? "longwire" : "volt"; break;
                    case Archetype.Shotgunner: weapon = "mauler"; break;
                    case Archetype.Bruiser: weapon = rng.Chance(0.5f) ? "rebar" : "fists"; break;
                    case Archetype.Sniper: weapon = "hush"; break;
                    case Archetype.Netrunner: weapon = "kite9"; break;
                    case Archetype.Heavy: weapon = "longwire"; break;
                    case Archetype.Boss: weapon = rng.Pick("thunderhead", "longwire", "mauler"); break;
                    case Archetype.Officer: weapon = rng.Pick("kite9", "kite9", "longwire", "mauler"); break;
                }
            }
            npc.weaponDef = Weapons.Get(weapon);
            npc.displayName = name ?? (a == Archetype.Civilian ? rng.Pick(civNames) : names.TryGetValue(f, out var nl) ? rng.Pick(nl) : "Stranger");
            if (a == Archetype.Netrunner) npc.displayName = Factions.Name(f) + " Netrunner";
            if (a == Archetype.Heavy) npc.displayName = Factions.Name(f) + " Heavy";
            if (a == Archetype.Sniper) npc.displayName = Factions.Name(f) + " Sniper";
            npc.Setup();
            if (!string.IsNullOrEmpty(group))
            {
                if (!groups.TryGetValue(group, out var l)) { l = new List<NPC>(); groups[group] = l; }
                l.Add(npc);
            }
            return npc;
        }

        public static List<NPC> Squad(string group, FactionId f, Vector3 center, float radius, int count, int level, bool hostile, params Archetype[] mix)
        {
            var list = new List<NPC>();
            for (int i = 0; i < count; i++)
            {
                var a = mix != null && mix.Length > 0 ? mix[i % mix.Length] : Archetype.Grunt;
                var p = FreeSpot(center, radius);
                var npc = Spawn(a, f, p, rng.Range(0f, 360f), level + rng.Range(-1, 2), group, hostile);
                npc.homeRadius = Mathf.Max(4f, radius * 0.6f);
                list.Add(npc);
            }
            return list;
        }

        public static NPC Civilian(int bx, int bz, float t)
        {
            var p = Game.City.SidewalkPoint(bx, bz, t) + Vector3.up * 0.15f;
            var npc = Spawn(Archetype.Civilian, FactionId.Civilian, p, 0, 1);
            npc.bx = bx; npc.bz = bz; npc.loopT = t; npc.loopDir = rng.Chance(0.5f) ? 1 : -1;
            npc.state = NPCState.Walk;
            return npc;
        }

        public static NPC Vendor(VendorSpot spot)
        {
            var r = new Rng(spot.look + 17);
            var look = Appearance.Random(FactionId.Civilian, r);
            if (spot.npcId == "mamasol") { look.hair = 9; look.female = true; look.beard = 0; look.hairColor = new Color(0.85f, 0.85f, 0.88f); look.jacket = new Color(0.45f, 0.1f, 0.15f); look.accent = Palette.Magenta; look.height = 0.92f; }
            if (spot.npcId == "clinic") { look.jacket = new Color(0.85f, 0.88f, 0.9f); look.visor = true; look.accent = Palette.Cyan; }
            var npc = Spawn(Archetype.Vendor, FactionId.Civilian, spot.pos + Vector3.up * 0.0f, Quaternion.LookRotation(spot.facing).eulerAngles.y, 3, null, false, "fists", spot.name, look);
            npc.npcId = spot.npcId ?? "vendor_" + spot.shopId;
            npc.shopId = spot.shopId;
            npc.stationary = true;
            npc.essential = true;
            npc.dmg.invulnerable = true;
            npc.talkable = true;
            AddTalk(npc);
            if (!string.IsNullOrEmpty(spot.npcId)) byId[spot.npcId] = npc;
            return npc;
        }

        public static NPC Story(string id, string name, FactionId f, Vector3 pos, Vector3 facing, Appearance look = null, Archetype a = Archetype.Vendor, string weapon = "fists")
        {
            if (byId.TryGetValue(id, out var existing) && existing != null) return existing;
            var npc = Spawn(a, f, pos, facing.sqrMagnitude > 0.01f ? Quaternion.LookRotation(facing).eulerAngles.y : 0, 8, null, false, weapon, name, look);
            npc.npcId = id;
            npc.stationary = true;
            npc.essential = true;
            npc.dmg.invulnerable = true;
            npc.talkable = true;
            AddTalk(npc);
            byId[id] = npc;
            return npc;
        }

        static void AddTalk(NPC npc)
        {
            var t = npc.gameObject.AddComponent<TalkInteractable>();
            t.npc = npc;
            t.id = npc.npcId;
            t.range = 3f;
        }

        public static NPC FindById(string id) => id != null && byId.TryGetValue(id, out var n) && n != null ? n : null;

        public static void Remove(string id)
        {
            if (byId.TryGetValue(id, out var n) && n != null) Object.Destroy(n.gameObject);
            byId.Remove(id);
        }

        public static void AlertGroup(string group, Damageable target)
        {
            if (!groups.TryGetValue(group, out var l)) return;
            foreach (var n in l) if (n != null && n.state != NPCState.Dead && n.state != NPCState.Combat) n.EngageTarget(target);
        }

        public static int Alive(string group)
        {
            if (!groups.TryGetValue(group, out var l)) return 0;
            int c = 0;
            foreach (var n in l) if (n != null && n.state != NPCState.Dead) c++;
            return c;
        }

        public static List<NPC> Group(string group) => groups.TryGetValue(group, out var l) ? l : new List<NPC>();

        public static void DespawnGroups(string prefix)
        {
            var remove = new List<string>();
            foreach (var kv in groups)
            {
                if (!kv.Key.StartsWith(prefix)) continue;
                foreach (var n in kv.Value) if (n != null && n.state != NPCState.Dead) Object.Destroy(n.gameObject);
                remove.Add(kv.Key);
            }
            foreach (var k in remove) groups.Remove(k);
        }

        /// <summary>Stops tracking groups without removing their NPCs (they despawn naturally).</summary>
        public static void Forget(string prefix)
        {
            var remove = new List<string>();
            foreach (var k in groups.Keys) if (k.StartsWith(prefix)) remove.Add(k);
            foreach (var k in remove) groups.Remove(k);
        }

        public static void ClearAll()
        {
            foreach (var n in new List<NPC>(NPC.All)) if (n != null) Object.Destroy(n.gameObject);
            groups.Clear();
            byId.Clear();
        }

        /// <summary>Finds a walkable spot near center that isn't inside a building.</summary>
        public static Vector3 FreeSpot(Vector3 center, float radius)
        {
            for (int i = 0; i < 20; i++)
            {
                var off = rng.InsideCircle() * radius;
                var p = center + new Vector3(off.x, 0, off.y);
                if (!Physics.Raycast(p + Vector3.up * 6f, Vector3.down, out var hit, 12f, Layers.WorldMask, QueryTriggerInteraction.Ignore)) continue;
                if (hit.point.y > center.y + 2.5f) continue; // landed on a roof/crate
                var g = hit.point;
                if (Physics.CheckCapsule(g + Vector3.up * 0.5f, g + Vector3.up * 1.6f, 0.4f, Layers.ShootMask, QueryTriggerInteraction.Ignore)) continue;
                return g;
            }
            return center;
        }
    }
}
