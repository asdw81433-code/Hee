using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Random street encounters that make the open world feel alive and dangerous.</summary>
    public class WorldEvents : MonoBehaviour
    {
        public enum Kind { None, Shakedown, GangWar, Burnout, SupplyDrop, PoliceRaid }
        public Kind active = Kind.None;
        public Vector3 site;
        public string Label { get; private set; }
        float timer = 70f;
        float life;
        int eventId;
        string Group => "evt" + eventId + "_a";
        string Group2 => "evt" + eventId + "_b";
        GameObject crate;

        void Start() { Game.Events = this; }

        void Update()
        {
            if (!Game.IsPlaying || !Game.HasPlayer) return;
            float dt = Time.deltaTime;
            if (active == Kind.None)
            {
                timer -= dt;
                if (timer <= 0f) { timer = Random.Range(80f, 160f); TryStart(); }
                return;
            }
            life += dt;
            bool far = (Game.PlayerPos - site).sqrMagnitude > 320f * 320f;
            bool done = false;
            switch (active)
            {
                case Kind.Shakedown:
                case Kind.Burnout:
                    if (Spawner.Alive(Group) == 0) { done = true; Reward(); }
                    break;
                case Kind.GangWar:
                case Kind.PoliceRaid:
                    if (Spawner.Alive(Group) == 0 || Spawner.Alive(Group2) == 0) done = true;
                    break;
                case Kind.SupplyDrop:
                    if (crate == null || crate.GetComponent<LootCrate>().opened) done = true;
                    break;
            }
            if (done || far || life > 420f) End(!done);
        }

        void TryStart()
        {
            if (Game.Player.InVehicle && Random.value < 0.5f) return;
            if (Game.PlayerPos.y < -20f || Game.PlayerPos.y > 60f) return;
            if (Game.Activities != null && (Game.Activities.RaceActive || Game.Activities.FightActive)) return;
            foreach (var q in Game.Quests.Active) if (q.kind == QuestKind.Main && q.Step != null && q.Step.objectives.Exists(o => o.type == ObjType.Kill || o.type == ObjType.Survive)) return;
            var dir = Random.insideUnitSphere.Flat().normalized;
            var p = Game.PlayerPos + dir * Random.Range(70f, 150f);
            if (!Game.City.InCity(p)) return;
            var road = Game.City.NearestRoadPoint(p, out var rd);
            site = Spawner.FreeSpot(road + Vector3.Cross(rd, Vector3.up) * 9f, 4f);
            var d = Game.City.DistrictAt(site);
            int lvl = Mathf.Max(1, Game.Stats.Level + Random.Range(-1, 2));
            float roll = Random.value;
            var gang = d == District.Lowtown ? FactionId.Jackals : d == District.NeonStrip || d == District.Docks ? FactionId.Lotus : d == District.Scar ? FactionId.Raiders : FactionId.Jackals;
            life = 0f;
            eventId++;
            if (roll < 0.35f)
            {
                active = Kind.Shakedown;
                Spawner.Squad(Group, gang, site, 4f, Random.Range(2, 4), lvl, true, Archetype.Grunt, Archetype.Bruiser, Archetype.Grunt);
                var victim = Spawner.Spawn(Archetype.Civilian, FactionId.Civilian, site + Vector3.right * 1.5f, 0, 1);
                victim.state = NPCState.Cower; victim.Panic(site);
                Label = Factions.Name(gang) + " shakedown";
                Game.UI?.Notify("Crime in progress nearby: " + Label, Palette.Orange);
            }
            else if (roll < 0.6f && d != District.Spire)
            {
                active = Kind.GangWar;
                var rival = gang == FactionId.Jackals ? FactionId.Lotus : FactionId.Jackals;
                if (gang == FactionId.Raiders) rival = FactionId.Police;
                Spawner.Squad(Group, gang, site + Vector3.left * 9f, 5f, Random.Range(3, 5), lvl, false, Archetype.Grunt, Archetype.Gunner, Archetype.Shotgunner);
                Spawner.Squad(Group2, rival, site + Vector3.right * 9f, 5f, Random.Range(3, 5), lvl, false, Archetype.Grunt, Archetype.Gunner, Archetype.Bruiser);
                Label = Factions.Name(gang) + " vs " + Factions.Name(rival);
                Game.UI?.Notify("Gunfire reported: " + Label, Palette.Red);
            }
            else if (roll < 0.72f && Game.Stats.Level >= 3)
            {
                active = Kind.Burnout;
                var look = Appearance.Random(FactionId.Raiders, new Rng(Random.Range(0, 9999)));
                look.chromeSkin = true; look.skin = Palette.SkinTones[Palette.SkinTones.Length - 1]; look.mask = true; look.bulk = 1.35f;
                var b = Spawner.Spawn(Archetype.Boss, FactionId.Raiders, site, 0, lvl + 3, Group, true, Random.value < 0.5f ? "monoblade" : "hornet", "BURNOUT", look);
                b.dmg.Init(1400f + lvl * 120f, 70f);
                b.dmg.isRobotic = true;
                b.sightRange = 60f;
                Label = "BURNOUT sighting";
                Game.UI?.Banner("NBPD ALERT", "A Burnout is rampaging in " + CityData.DistrictName(d) + ". Bounty posted.", Palette.Red);
            }
            else if (roll < 0.86f)
            {
                active = Kind.SupplyDrop;
                crate = new GameObject("SupplyDrop") { layer = Layers.World };
                crate.transform.position = site + Vector3.up * 0.1f;
                var col = crate.AddComponent<BoxCollider>(); col.size = new Vector3(1.4f, 1f, 1f); col.center = new Vector3(0, 0.5f, 0);
                var lc = crate.AddComponent<LootCrate>(); lc.tier = 2; lc.prompt = "Open Helix supply drop";
                Util.Primitive(PrimitiveType.Cube, "Body", crate.transform, new Vector3(0, 0.45f, 0), new Vector3(1.4f, 0.9f, 1f), Mats.Cached("dropbody", () => Mats.Emissive(new Color(0.85f, 0.85f, 0.9f), Palette.Cyan * 0.8f)));
                var lid = Util.Primitive(PrimitiveType.Cube, "Lid", crate.transform, new Vector3(0, 0.95f, 0), new Vector3(1.42f, 0.1f, 1.02f), Mats.Cached("droplid", () => Mats.Lit(new Color(0.2f, 0.2f, 0.22f))));
                var light = crate.AddComponent<Light>(); light.type = LightType.Point; light.color = Palette.Cyan; light.range = 12f; light.intensity = 3f;
                Drone.Spawn(FactionId.Helix, site + Vector3.up * 14f, lvl, Group);
                Drone.Spawn(FactionId.Helix, site + Vector3.up * 16f + Vector3.right * 6f, lvl, Group);
                Label = "Helix supply drop";
                Game.UI?.Notify("A Helix supply pod crashed nearby", Palette.Cyan);
                Game.Fx?.Explosion(site, 3f);
            }
            else
            {
                active = Kind.PoliceRaid;
                Spawner.Squad(Group, FactionId.Police, site + Vector3.left * 10f, 4f, 3, lvl, false, Archetype.Officer);
                Spawner.Squad(Group2, gang == FactionId.Lotus ? FactionId.Jackals : gang, site + Vector3.right * 10f, 5f, 4, lvl, false, Archetype.Grunt, Archetype.Gunner);
                Label = "NBPD raid";
                Game.UI?.Notify("NBPD raid in progress", Palette.Blue);
            }
        }

        void Reward()
        {
            int lvl = Game.Stats.Level;
            if (active == Kind.Burnout)
            {
                Game.Stats.AddMoney(1500 + lvl * 150); Game.Stats.AddXP(500); Game.Stats.AddCred(15);
                Pickup.Spawn(site, null, 0, 0, Loot.RandomWeapon(lvl + 5, 3));
                Game.UI?.Banner("BURNOUT NEUTRALISED", "NBPD bounty paid: " + Util.Credits(1500 + lvl * 150), Palette.Yellow);
            }
            else
            {
                Game.Stats.AddMoney(150 + lvl * 30); Game.Stats.AddXP(120); Game.Stats.AddCred(4);
                Game.UI?.Notify("Crime stopped. The locals won't forget it.", Palette.Green);
            }
        }

        void End(bool despawn)
        {
            if (despawn) Spawner.DespawnGroups("evt" + eventId + "_");
            else Spawner.Forget("evt" + eventId + "_");
            if (crate != null && despawn) Destroy(crate);
            crate = null;
            active = Kind.None;
            Label = null;
        }

        public void ClearAll() { End(true); timer = 90f; }
    }
}
