using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>NBPD heat (0-5 stars). Witnessed crimes raise heat, police and drones respond, staying unseen cools it down.</summary>
    public class PoliceSystem : MonoBehaviour
    {
        public int Heat { get; private set; }
        public bool Searching { get; private set; }
        public float CoolProgress { get; private set; }
        float lastSeen;
        float spawnTimer;
        readonly List<NPC> units = new List<NPC>();
        readonly List<Drone> drones = new List<Drone>();
        AudioSource siren;
        public bool suppressed; // story moments can disable police

        void Start()
        {
            Game.Police = this;
            GameEvents.Crime += OnCrime;
            if (Game.Audio != null) siren = Game.Audio.Loop2D("siren", 0f);
        }

        void OnDestroy() { GameEvents.Crime -= OnCrime; }

        void OnCrime(CrimeType type, Vector3 pos)
        {
            if (suppressed || !Game.HasPlayer) return;
            bool witnessed = false;
            foreach (var n in NPC.All)
            {
                if (n == null || n.state == NPCState.Dead) continue;
                float d2 = (n.transform.position - pos).sqrMagnitude;
                if (n.faction == FactionId.Police && d2 < 60f * 60f) { witnessed = true; break; }
                if (n.faction == FactionId.Civilian && n.archetype == Archetype.Civilian && d2 < 25f * 25f && Util.LineOfSight(n.rig.HeadPos, pos + Vector3.up)) { witnessed = true; break; }
            }
            if (!witnessed) return;
            int add = type switch { CrimeType.Murder => 1, CrimeType.Assault => Heat == 0 ? 1 : 0, CrimeType.Theft => Heat == 0 ? 1 : 0, CrimeType.Hacking => Heat == 0 ? 1 : 0, _ => 0 };
            // killing officers escalates faster
            if (type == CrimeType.Murder && Heat >= 2) add = 1;
            if (add <= 0 && Heat > 0) { lastSeen = Time.time; return; }
            SetHeat(Mathf.Min(5, Heat + add));
            lastSeen = Time.time;
        }

        public void SetHeat(int h)
        {
            int old = Heat;
            Heat = Mathf.Clamp(h, 0, 5);
            if (Heat > old) { Game.UI?.Notify("NBPD HEAT " + new string('*', Heat), Palette.Red); spawnTimer = 0f; }
            if (Heat == 0 && old > 0)
            {
                Game.UI?.Notify("You lost the NBPD", Palette.Cyan);
                foreach (var u in units) if (u != null) { u.target = null; u.state = NPCState.Idle; }
                foreach (var d in drones) if (d != null) d.Leave();
            }
        }

        void Update()
        {
            units.RemoveAll(u => u == null || u.state == NPCState.Dead);
            drones.RemoveAll(d => d == null);
            if (siren != null) siren.volume = Heat > 0 ? Mathf.Lerp(siren.volume, 0.12f + Heat * 0.03f, Time.deltaTime) * (Game.Audio != null ? Game.Audio.SfxVolume : 1f) : Mathf.MoveTowards(siren.volume, 0f, Time.deltaTime * 0.2f);
            if (Heat <= 0 || !Game.HasPlayer || !Game.IsPlaying) { Searching = false; return; }

            bool seen = false;
            foreach (var u in units) if (u.state == NPCState.Combat && u.target == Game.Stats.dmg && u.detection >= 1f && Util.LineOfSight(u.rig.HeadPos, Game.Cam.transform.position)) { seen = true; break; }
            foreach (var d in drones) if (d.SeesPlayer) { seen = true; break; }
            if (seen) lastSeen = Time.time;
            float coolTime = (10f + Heat * 4f) * (Game.Stats.HasPerk("vanish") ? 0.5f : 1f);
            float since = Time.time - lastSeen;
            Searching = since > 3f;
            CoolProgress = Mathf.Clamp01(since / coolTime);
            if (since > coolTime) { SetHeat(Heat - 1); lastSeen = Time.time; }

            spawnTimer -= Time.deltaTime;
            if (spawnTimer <= 0f)
            {
                spawnTimer = 6f;
                int wantUnits = Heat switch { 1 => 2, 2 => 4, 3 => 5, 4 => 7, _ => 9 };
                int wantDrones = Heat switch { 1 => 0, 2 => 0, 3 => 1, 4 => 2, _ => 3 };
                if (units.Count < wantUnits) SpawnUnits(Mathf.Min(3, wantUnits - units.Count));
                if (drones.Count < wantDrones) drones.Add(Drone.Spawn(FactionId.Police, Game.PlayerPos + Random.insideUnitSphere.Flat().normalized * 60f + Vector3.up * 25f, Heat));
                // despawn units that fell far behind
                foreach (var u in units)
                    if (u != null && (u.transform.position - Game.PlayerPos).sqrMagnitude > 220f * 220f) Destroy(u.gameObject);
            }
        }

        void SpawnUnits(int n)
        {
            var player = Game.PlayerPos;
            var cam = Game.Cam.transform;
            for (int attempt = 0; attempt < 8 && n > 0; attempt++)
            {
                var dir = Random.insideUnitSphere.Flat().normalized;
                if (Vector3.Dot(dir, cam.forward.Flat().normalized) > 0.5f) dir = -dir; // prefer behind the player
                var p = Game.City.NearestRoadPoint(player + dir * Random.Range(55f, 85f), out _);
                if (player.y < -20f) p = player + dir * 20f; // interiors: spawn at the door
                p = Spawner.FreeSpot(p, 4f);
                var a = Heat >= 4 && Random.value < 0.3f ? Archetype.Heavy : Archetype.Officer;
                int lvl = Mathf.Max(Game.Stats.Level, 2 + Heat * 2);
                var u = Spawner.Spawn(a, FactionId.Police, p, 0, lvl, "police", false);
                u.sightRange = 55f;
                u.EngageTarget(Game.Stats.dmg);
                units.Add(u);
                n--;
            }
        }

        public void ClearAll()
        {
            Heat = 0;
            foreach (var u in units) if (u != null) Destroy(u.gameObject);
            foreach (var d in drones) if (d != null) Destroy(d.gameObject);
            units.Clear(); drones.Clear();
        }
    }

    /// <summary>Hovering security drone used by NBPD and Helix. Robotic: weak to EMP and electric damage.</summary>
    public class Drone : MonoBehaviour
    {
        public FactionId faction;
        public Damageable dmg;
        public int level = 1;
        public string groupId;
        Rigidbody rb;
        float fireCd = 2f;
        bool leaving;
        Transform rotor;
        public bool SeesPlayer { get; private set; }
        AudioSource hum;
        Vector3 orbit;

        public static Drone Spawn(FactionId f, Vector3 pos, int level, string group = null)
        {
            var go = new GameObject("Drone_" + f) { layer = Layers.Actors };
            go.transform.position = pos;
            var body = Util.Primitive(PrimitiveType.Cube, "Body", go.transform, Vector3.zero, new Vector3(0.9f, 0.3f, 0.9f), Mats.Cached("drone", () => Mats.Lit(new Color(0.1f, 0.1f, 0.12f), Tex.Metal.albedo, 0.7f, 0.8f)), true);
            body.layer = Layers.Actors;
            var eye = Util.Primitive(PrimitiveType.Sphere, "Eye", go.transform, new Vector3(0, -0.15f, 0.3f), Vector3.one * 0.25f, Mats.Cached("droneeye" + f, () => Mats.Unlit((f == FactionId.Police ? Palette.Red : Palette.Cyan) * 4f)));
            var ring = Util.Primitive(PrimitiveType.Cylinder, "Rotor", go.transform, new Vector3(0, 0.2f, 0), new Vector3(1.4f, 0.02f, 1.4f), Mats.Cached("dronering", () => Mats.Additive(new Color(0.6f, 0.8f, 1f, 0.3f), Tex.Ring)));
            var d = go.AddComponent<Drone>();
            d.faction = f; d.level = level; d.groupId = group;
            d.rotor = ring.transform;
            d.dmg = go.AddComponent<Damageable>();
            d.dmg.Init(90f + level * 12f, 20f);
            d.dmg.faction = f;
            d.dmg.isRobotic = true;
            d.dmg.Died += d.OnDied;
            d.dmg.Damaged += info => { if (info.fromPlayer && f != FactionId.Police) Factions.Provoke(f); };
            var hb = body.AddComponent<Hitbox>(); hb.owner = d.dmg;
            d.rb = go.AddComponent<Rigidbody>();
            d.rb.useGravity = false;
            Util.SetDrag(d.rb, 2f, 4f);
            d.rb.mass = 20f;
            d.hum = Game.Audio?.AttachLoop(go, "drone", 0.5f, 3f, 60f);
            d.orbit = Random.insideUnitSphere.Flat().normalized;
            return d;
        }

        public void Leave() { leaving = true; }

        void FixedUpdate()
        {
            if (dmg.isDead || !Game.HasPlayer) return;
            var player = Game.PlayerPos + Vector3.up * 1.5f;
            if (leaving)
            {
                rb.AddForce(Vector3.up * 30f, ForceMode.Acceleration);
                if (transform.position.y > 150f) Destroy(gameObject);
                return;
            }
            orbit = Quaternion.Euler(0, 20f * Time.fixedDeltaTime, 0) * orbit;
            var desired = player + orbit * 12f + Vector3.up * 6f;
            var force = (desired - transform.position) * 3f - Util.GetVelocity(rb) * 1.5f;
            rb.AddForce(Vector3.ClampMagnitude(force, 30f), ForceMode.Acceleration);
            var look = player - transform.position;
            if (look.sqrMagnitude > 0.1f) rb.MoveRotation(Quaternion.Slerp(rb.rotation, Quaternion.LookRotation(look), Time.fixedDeltaTime * 4f));
        }

        void Update()
        {
            if (rotor != null) rotor.Rotate(Vector3.up, 1080f * Time.deltaTime, Space.Self);
            if (dmg.isDead || leaving || !Game.HasPlayer || !Game.IsPlaying) return;
            bool hostile = faction == FactionId.Police ? Game.Police != null && Game.Police.Heat > 0 : Factions.HostileToPlayer(faction) || !string.IsNullOrEmpty(groupId);
            var eye = transform.position;
            var target = Game.Cam.transform.position;
            float dist = Vector3.Distance(eye, target);
            SeesPlayer = dist < 60f && Util.LineOfSight(eye, target);
            if (!hostile || !SeesPlayer) return;
            fireCd -= Time.deltaTime;
            if (fireCd <= 0f)
            {
                fireCd = Random.Range(0.25f, 0.4f);
                bool hit = Random.value < 0.3f * Game.EnemyAccuracyMult * (Game.Stats.HasBuff("camo") ? 0.2f : 1f);
                var end = hit ? target - Vector3.up * 0.3f : target + Random.insideUnitSphere * 2f;
                if (hit) Game.Stats.dmg.ApplyDamage(new DamageInfo { amount = 6f + level * 1.5f, type = DamageType.Ballistic, point = end, direction = (end - eye).normalized, source = gameObject });
                Game.Fx?.Tracer(eye, end, Palette.Red);
                Game.Audio?.Play3D("smg", eye, 0.6f, 1.4f, 3f, 120f);
            }
        }

        void OnDied(DamageInfo info)
        {
            rb.useGravity = true;
            Util.SetDrag(rb, 0.2f, 0.5f);
            rb.AddTorque(Random.insideUnitSphere * 50f, ForceMode.Impulse);
            if (hum != null) hum.Stop();
            Game.Fx?.ElectricBurst(transform.position, 3f);
            if (info.fromPlayer)
            {
                Game.Stats?.AddXP(45 + level * 5);
                if (faction == FactionId.Police) GameEvents.RaiseCrime(CrimeType.Vandalism, transform.position);
                Pickup.Spawn(transform.position, "scrap", Random.Range(2, 5));
            }
            Destroy(gameObject, 6f);
        }

        void OnCollisionEnter(Collision c)
        {
            if (dmg.isDead && c.relativeVelocity.magnitude > 4f)
            {
                Game.Fx?.Explosion(transform.position, 3f);
                Effects.Blast(transform.position, 3f, 30f, gameObject, false, false);
                Destroy(gameObject);
            }
        }
    }
}
