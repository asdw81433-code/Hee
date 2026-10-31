using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    public enum VehicleType { Sedan, Taxi, Muscle, Van, Sports, Police, Trike }
    public enum VehicleMode { Parked, Traffic, Player, Abandoned, Wreck }

    /// <summary>
    /// Raycast-suspension arcade car. Kinematic lane-following when it's traffic, full physics when the player drives
    /// (or after a crash). Also builds its own procedural model.
    /// </summary>
    public class Vehicle : MonoBehaviour
    {
        public VehicleType type;
        public VehicleMode mode;
        public Rigidbody rb;
        public Damageable dmg;
        public Transform seat;
        public string ownedId;
        public bool thirdPerson;
        public bool lightsOn = true;

        readonly List<Transform> wheelVis = new List<Transform>();
        readonly List<Vector3> wheelLocal = new List<Vector3>();
        readonly List<bool> wheelFront = new List<bool>();
        readonly List<float> wheelSusp = new List<float>();
        float wheelRadius = 0.36f, rest = 0.5f, stiffness = 8000f, damping = 2300f;
        float maxSpeed = 42f, engine = 9f, grip = 9f, maxSteer = 32f;
        float steer, throttle, wheelSpin;
        bool handbrake;
        int groundedWheels;
        AudioSource engineSrc, skidSrc;
        readonly List<Light> headlights = new List<Light>();
        Renderer lightBarRed, lightBarBlue;
        float burnTimer = -1f;
        float flippedTimer;
        Vector3 camVel;
        Vector3 boxSize;

        // traffic
        readonly Queue<Vector3> path = new Queue<Vector3>();
        int ix, iz, dir;
        float trafficSpeed;
        float blockedTime;
        public float cruise = 12f;
        public bool HasDriver => mode == VehicleMode.Traffic;
        public float SpeedKmh => (rb != null ? Util.GetVelocity(rb).magnitude : trafficSpeed) * 3.6f;
        static readonly Vector3[] Dirs = { Vector3.right, Vector3.forward, Vector3.left, Vector3.back };

        public static string TypeName(VehicleType t) => t switch
        {
            VehicleType.Sedan => "Makigai Sedan",
            VehicleType.Taxi => "Bay Cab",
            VehicleType.Muscle => "Rust Kestrel",
            VehicleType.Van => "Liberty Hauler",
            VehicleType.Sports => "Vega GT-R",
            VehicleType.Police => "NBPD Interceptor",
            _ => "Zip Trike 2089"
        };

        // ------------------------------------------------------------------ construction
        public static Vehicle Create(VehicleType type, Vector3 pos, Quaternion rot, VehicleMode mode, int paint = -1)
        {
            var go = new GameObject("Vehicle_" + type) { layer = Layers.Actors };
            go.transform.SetPositionAndRotation(pos, rot);
            var v = go.AddComponent<Vehicle>();
            v.type = type;
            v.Build(paint);
            v.rb = go.AddComponent<Rigidbody>();
            v.rb.mass = type == VehicleType.Trike ? 500f : type == VehicleType.Van ? 1900f : 1300f;
            v.rb.centerOfMass = new Vector3(0, -0.25f, 0.1f);
            v.rb.interpolation = RigidbodyInterpolation.Interpolate;
            v.rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;
            Util.SetDrag(v.rb, 0.05f, 2f);
            float massScale = v.rb.mass / 1300f;
            v.stiffness *= massScale; v.damping *= massScale;
            v.dmg = go.AddComponent<Damageable>();
            v.dmg.Init(type == VehicleType.Van ? 900f : type == VehicleType.Trike ? 350f : type == VehicleType.Police ? 800f : 600f, 30f);
            v.dmg.faction = FactionId.None;
            v.dmg.isRobotic = true;
            v.dmg.Died += v.OnDestroyed;
            v.dmg.Damaged += v.OnDamaged;
            v.engineSrc = Game.Audio?.AttachLoop(go, "engine", 0.25f, 3f, 60f);
            v.skidSrc = Game.Audio?.AttachLoop(go, "skid", 0f, 3f, 50f);
            v.SetMode(mode);
            return v;
        }

        void Build(int paint)
        {
            var M = CityGenerator.Current?.M;
            var rng = new Rng(GetInstanceID());
            Material body;
            if (M == null) body = Mats.Lit(Color.gray);
            else if (type == VehicleType.Taxi || type == VehicleType.Trike && rng.Chance(0.5f)) body = Mats.Cached("taxi", () => Mats.Lit(new Color(0.95f, 0.75f, 0.05f), null, 0.85f, 0.5f));
            else if (type == VehicleType.Police) body = Mats.Cached("policecar", () => Mats.Lit(new Color(0.05f, 0.08f, 0.2f), null, 0.88f, 0.6f));
            else body = paint >= 0 ? M.carPaints[paint % M.carPaints.Length] : rng.Pick(M.carPaints);
            var glass = Mats.Cached("carglass", () => Mats.Lit(new Color(0.02f, 0.025f, 0.035f), null, 0.97f, 0.7f));
            var dark = Mats.Cached("cardark", () => Mats.Lit(new Color(0.04f, 0.04f, 0.045f), null, 0.4f, 0.3f));
            var tire = Mats.Cached("tire", () => Mats.Lit(new Color(0.03f, 0.03f, 0.03f), null, 0.2f));
            var rim = Mats.Cached("rim", () => Mats.Lit(new Color(0.7f, 0.72f, 0.75f), null, 0.9f, 1f));
            var head = Mats.Cached("headlight", () => Mats.Unlit(new Color(1f, 0.95f, 0.85f) * 4f));
            var tail = Mats.Cached("taillight", () => Mats.Unlit(Palette.Red * 3.5f));
            var glow = Mats.Cached("under" + rng.Range(0, 6), () => Mats.Unlit(Palette.Neon[rng.Range(0, Palette.Neon.Length)] * 3f));

            float w = 1.9f, h = 0.7f, l = 4.5f, cabH = 0.6f, cabL = 2.3f, cabZ = -0.2f, y0 = 0.55f;
            switch (type)
            {
                case VehicleType.Muscle: w = 1.95f; h = 0.65f; l = 4.8f; cabH = 0.55f; cabL = 2f; cabZ = -0.5f; maxSpeed = 48f; engine = 11f; break;
                case VehicleType.Van: w = 2.1f; h = 1.5f; l = 5f; cabH = 0.5f; cabL = 1.6f; cabZ = 1.4f; maxSpeed = 34f; engine = 7f; grip = 7f; y0 = 0.6f; break;
                case VehicleType.Sports: w = 2f; h = 0.55f; l = 4.4f; cabH = 0.5f; cabL = 1.8f; cabZ = -0.6f; maxSpeed = 58f; engine = 14f; grip = 11f; y0 = 0.5f; break;
                case VehicleType.Police: maxSpeed = 52f; engine = 12f; grip = 10f; break;
                case VehicleType.Trike: w = 1.35f; h = 0.6f; l = 2.7f; cabH = 0f; maxSpeed = 30f; engine = 8f; grip = 8f; maxSteer = 38f; wheelRadius = 0.28f; break;
            }
            boxSize = new Vector3(w, h + cabH, l);
            var vis = new GameObject("Model").transform;
            vis.SetParent(transform, false);
            Box(vis, new Vector3(0, y0 + h * 0.5f, 0), new Vector3(w, h, l), body);
            Box(vis, new Vector3(0, y0 + 0.08f, 0), new Vector3(w * 0.98f, 0.16f, l * 0.98f), dark);
            if (cabH > 0)
            {
                Box(vis, new Vector3(0, y0 + h + cabH * 0.5f, cabZ), new Vector3(w * 0.88f, cabH, cabL), glass);
                Box(vis, new Vector3(0, y0 + h + cabH + 0.03f, cabZ), new Vector3(w * 0.86f, 0.06f, cabL * 0.85f), body);
            }
            else
            {
                // trike canopy
                Box(vis, new Vector3(0, y0 + h + 1.1f, -0.2f), new Vector3(w * 1.05f, 0.08f, l * 0.75f), body);
                foreach (var c in new[] { new Vector3(0.6f, 0, 0.9f), new Vector3(-0.6f, 0, 0.9f), new Vector3(0.6f, 0, -1.2f), new Vector3(-0.6f, 0, -1.2f) })
                    Box(vis, new Vector3(c.x, y0 + h + 0.55f, c.z), new Vector3(0.05f, 1.1f, 0.05f), dark);
                Box(vis, new Vector3(0, y0 + h + 1.05f, -0.2f), new Vector3(w * 1.06f, 0.03f, l * 0.76f), glow);
                Box(vis, new Vector3(0, y0 + h + 0.3f, -0.6f), new Vector3(w * 0.95f, 0.5f, 0.6f), dark);
            }
            // lights
            Box(vis, new Vector3(w * 0.33f, y0 + h * 0.6f, l * 0.5f + 0.01f), new Vector3(w * 0.22f, 0.1f, 0.03f), head);
            Box(vis, new Vector3(-w * 0.33f, y0 + h * 0.6f, l * 0.5f + 0.01f), new Vector3(w * 0.22f, 0.1f, 0.03f), head);
            Box(vis, new Vector3(0, y0 + h * 0.6f, -l * 0.5f - 0.01f), new Vector3(w * 0.85f, 0.08f, 0.03f), tail);
            Box(vis, new Vector3(0, y0 - 0.05f, 0), new Vector3(w * 0.9f, 0.03f, l * 0.85f), glow);
            if (type == VehicleType.Taxi)
            {
                var sign = Box(vis, new Vector3(0, y0 + h + cabH + 0.2f, cabZ), new Vector3(0.8f, 0.25f, 0.35f), Mats.Cached("taxisign", () => Mats.Unlit(new Color(1f, 0.85f, 0.3f) * 3f)));
            }
            if (type == VehicleType.Police)
            {
                lightBarRed = Box(vis, new Vector3(-0.3f, y0 + h + cabH + 0.1f, cabZ), new Vector3(0.5f, 0.12f, 0.25f), Mats.Unlit(Palette.Red * 5f)).GetComponent<Renderer>();
                lightBarBlue = Box(vis, new Vector3(0.3f, y0 + h + cabH + 0.1f, cabZ), new Vector3(0.5f, 0.12f, 0.25f), Mats.Unlit(Palette.Blue * 5f)).GetComponent<Renderer>();
                Box(vis, new Vector3(0, y0 + h * 0.5f, 0), new Vector3(w + 0.01f, 0.25f, l * 0.6f), Mats.Cached("policestripe", () => Mats.Lit(new Color(0.9f, 0.9f, 0.92f), null, 0.8f)));
            }

            // wheels
            float wx = w * 0.5f - 0.12f, wz = l * 0.5f - 0.8f;
            var wheelPos = type == VehicleType.Trike
                ? new[] { new Vector3(0, 0, l * 0.5f - 0.45f), new Vector3(-wx, 0, -wz + 0.2f), new Vector3(wx, 0, -wz + 0.2f) }
                : new[] { new Vector3(-wx, 0, wz), new Vector3(wx, 0, wz), new Vector3(-wx, 0, -wz), new Vector3(wx, 0, -wz) };
            for (int i = 0; i < wheelPos.Length; i++)
            {
                var wp = wheelPos[i] + Vector3.up * wheelRadius;
                var wt = new GameObject("Wheel" + i).transform;
                wt.SetParent(vis, false);
                wt.localPosition = wp;
                var tireGo = Util.Primitive(PrimitiveType.Cylinder, "Tire", wt, Vector3.zero, new Vector3(wheelRadius * 2f, 0.12f, wheelRadius * 2f), tire);
                tireGo.transform.localRotation = Quaternion.Euler(0, 0, 90);
                var rimGo = Util.Primitive(PrimitiveType.Cylinder, "Rim", wt, Vector3.zero, new Vector3(wheelRadius * 1.3f, 0.13f, wheelRadius * 1.3f), rim);
                rimGo.transform.localRotation = Quaternion.Euler(0, 0, 90);
                wheelVis.Add(wt);
                wheelLocal.Add(wp);
                wheelFront.Add(wheelPos[i].z > 0);
                wheelSusp.Add(0f);
            }
            foreach (var r in vis.GetComponentsInChildren<Renderer>()) r.shadowCastingMode = ShadowCastingMode.On;

            // collider
            var col = gameObject.AddComponent<BoxCollider>();
            col.size = new Vector3(w, h + cabH * 0.9f, l);
            col.center = new Vector3(0, y0 + (h + cabH) * 0.5f, 0);
            var hb = gameObject.AddComponent<Hitbox>();

            // seat (US cars are left-hand drive)
            var s = new GameObject("Seat").transform;
            s.SetParent(transform, false);
            s.localPosition = type == VehicleType.Trike ? new Vector3(0, y0 + 0.2f, 0.3f) : new Vector3(-w * 0.22f, y0 + 0.1f, cabZ + 0.1f);
            seat = s;
            Util.SetLayerRecursive(gameObject, Layers.Actors);
        }

        Transform Box(Transform parent, Vector3 pos, Vector3 size, Material m)
        {
            var go = Util.Primitive(PrimitiveType.Cube, "Part", parent, pos, size, m);
            return go.transform;
        }

        void Start()
        {
            var hb = GetComponent<Hitbox>();
            if (hb != null) hb.owner = dmg;
        }

        // ------------------------------------------------------------------ modes
        public void SetMode(VehicleMode m)
        {
            mode = m;
            bool kinematic = m == VehicleMode.Traffic || m == VehicleMode.Parked;
            rb.isKinematic = kinematic;
            rb.useGravity = !kinematic;
            if (!kinematic) Util.SetVelocity(rb, transform.forward * trafficSpeed);
            if (engineSrc != null) engineSrc.volume = (m == VehicleMode.Parked || m == VehicleMode.Wreck || m == VehicleMode.Abandoned) ? 0f : 0.25f * (Game.Audio != null ? Game.Audio.SfxVolume : 1f);
            if (m == VehicleMode.Player && headlights.Count == 0) MakeHeadlights();
            foreach (var l in headlights) l.enabled = m == VehicleMode.Player && lightsOn;
        }

        void MakeHeadlights()
        {
            for (int i = -1; i <= 1; i += 2)
            {
                var go = new GameObject("Headlight");
                go.transform.SetParent(transform, false);
                go.transform.localPosition = new Vector3(i * boxSize.x * 0.33f, 0.9f, boxSize.z * 0.5f + 0.2f);
                go.transform.localRotation = Quaternion.Euler(8f, 0, 0);
                var l = go.AddComponent<Light>();
                l.type = LightType.Spot; l.range = 45f; l.spotAngle = 60f; l.intensity = 2.2f; l.color = new Color(1f, 0.95f, 0.85f);
                l.shadows = LightShadows.None;
                headlights.Add(l);
            }
        }

        public void InitTraffic(int startX, int startZ, int direction, float speed)
        {
            ix = startX; iz = startZ; dir = direction; cruise = speed;
            trafficSpeed = speed * 0.6f;
            path.Clear();
            AppendSegment();
        }

        Vector3 Side(int d) => Vector3.Cross(Vector3.up, Dirs[d]); // right of travel (US traffic)
        const float LaneOff = 1.75f;

        bool ValidDir(int x, int z, int d)
        {
            var v = Dirs[d];
            int nx = x + Mathf.RoundToInt(v.x), nz = z + Mathf.RoundToInt(v.z);
            return nx >= 0 && nz >= 0 && nx <= CityData.Grid && nz <= CityData.Grid;
        }

        void AppendSegment()
        {
            var city = Game.City;
            var a = city.Intersection(ix, iz);
            var v = Dirs[dir];
            int nx = ix + Mathf.RoundToInt(v.x), nz = iz + Mathf.RoundToInt(v.z);
            var b = city.Intersection(nx, nz);
            float h = CityData.RoadW * 0.5f;
            var off = Side(dir) * LaneOff;
            path.Enqueue(a + v * (h + 1f) + off);
            path.Enqueue((a + b) * 0.5f + off);
            path.Enqueue(b - v * (h + 0.5f) + off);
            // choose the next direction (never a U-turn)
            var options = new List<int>();
            int straight = dir, left = (dir + 1) % 4, right = (dir + 3) % 4;
            foreach (var o in new[] { straight, straight, straight, left, right })
                if (ValidDir(nx, nz, o)) options.Add(o);
            int next = options.Count > 0 ? options[Random.Range(0, options.Count)] : (dir + 2) % 4;
            if (next != dir)
            {
                var offNext = Side(next) * LaneOff;
                var p0 = b - v * (h + 0.5f) + off;
                var p2 = b + Dirs[next] * (h + 1f) + offNext;
                var ctrl = b + off + offNext;
                for (int i = 1; i <= 3; i++)
                {
                    float t = i / 4f;
                    path.Enqueue((1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * ctrl + t * t * p2);
                }
            }
            ix = nx; iz = nz; dir = next;
        }

        // ------------------------------------------------------------------ player control
        public void EnterAsPlayer()
        {
            if (mode == VehicleMode.Wreck) return;
            if (mode == VehicleMode.Traffic)
            {
                // drag the driver out
                var p = transform.position - transform.right * (boxSize.x * 0.5f + 1f);
                var driver = Spawner.Spawn(Archetype.Civilian, FactionId.Civilian, p, 0, 1);
                driver.Panic(p + transform.right);
                GameEvents.RaiseCrime(CrimeType.Theft, transform.position);
            }
            else if (mode == VehicleMode.Parked && string.IsNullOrEmpty(ownedId)) GameEvents.RaiseCrime(CrimeType.Theft, transform.position);
            SetMode(VehicleMode.Player);
            Game.Player.EnterVehicle(this);
            Game.Audio?.Play3D("door", transform.position, 0.8f);
            if (Game.Music != null && Game.Music.station == 0) Game.Music.SetStation(Game.Activities != null ? Game.Activities.lastRadio : 1);
            Game.UI?.Notify(TypeName(type) + "   [N] radio  [B] camera  [L] lights  [F] exit", Palette.Cyan);
        }

        public void OnPlayerExit()
        {
            SetMode(dmg.isDead ? VehicleMode.Wreck : VehicleMode.Abandoned);
            if (Game.Activities != null && Game.Music != null) Game.Activities.lastRadio = Mathf.Max(1, Game.Music.station);
            Game.Music?.SetStation(0);
            thirdPerson = false;
            Game.Audio?.Play3D("door", transform.position, 0.8f);
        }

        public Vector3 FindExitPoint()
        {
            var side = -transform.right;
            var candidates = new[] { transform.position + side * (boxSize.x * 0.5f + 0.9f), transform.position - side * (boxSize.x * 0.5f + 0.9f), transform.position + transform.forward * (boxSize.z * 0.5f + 1.2f), transform.position - transform.forward * (boxSize.z * 0.5f + 1.2f), transform.position + Vector3.up * 3f };
            foreach (var c in candidates)
            {
                var p = c + Vector3.up * 0.3f;
                if (!Physics.CheckCapsule(p + Vector3.up * 0.4f, p + Vector3.up * 1.5f, 0.35f, Layers.ShootMask, QueryTriggerInteraction.Ignore))
                {
                    if (Physics.Raycast(p + Vector3.up, Vector3.down, out var g, 4f, Layers.WorldMask)) return g.point + Vector3.up * 0.05f;
                    return p;
                }
            }
            return transform.position + Vector3.up * 3f;
        }

        void Update()
        {
            // flashing police lights
            if (lightBarRed != null)
            {
                bool on = (Time.time * 4f) % 2f < 1f;
                lightBarRed.enabled = on; lightBarBlue.enabled = !on;
            }
            if (mode != VehicleMode.Player || Game.Player == null || Game.Player.vehicle != this) return;
            if (!Game.IsPlaying) { throttle = 0; steer = 0; return; }
            var mv = InputHub.Move;
            throttle = Game.Activities != null && Game.Activities.RaceLocked ? 0f : mv.y;
            steer = Mathf.MoveTowards(steer, mv.x, Time.deltaTime * 4f);
            handbrake = InputHub.Held(Btn.Jump);
            if (InputHub.Down(Btn.Vehicle)) { Game.Player.ExitVehicle(); return; }
            if (InputHub.Down(Btn.CameraView)) { thirdPerson = !thirdPerson; Game.Player.cameraOverride = thirdPerson; if (!thirdPerson) { Game.Cam.transform.localPosition = Vector3.zero; Game.Cam.transform.localRotation = Quaternion.identity; } }
            if (InputHub.Down(Btn.Lights)) { lightsOn = !lightsOn; foreach (var l in headlights) l.enabled = lightsOn; }
            if (InputHub.Down(Btn.Radio) && Game.Music != null)
            {
                int s = Game.Music.station + 1;
                if (s >= MusicSystem.StationNames.Length) s = 1;
                Game.Music.SetStation(s);
                Game.UI?.Notify("Radio: " + MusicSystem.StationNames[s], Palette.Magenta);
            }
            if (InputHub.Down(Btn.Horn)) { Game.Audio?.Play3D("horn", transform.position, 1f); GameEvents.RaiseNoise(transform.position, 15f, Game.Player.gameObject); }
            if (Mathf.Abs(Vector3.Dot(transform.up, Vector3.up)) < 0.35f && Util.GetVelocity(rb).magnitude < 2f)
            {
                flippedTimer += Time.deltaTime;
                if (flippedTimer > 2.5f) { flippedTimer = 0; transform.SetPositionAndRotation(transform.position + Vector3.up * 1.5f, Quaternion.Euler(0, transform.eulerAngles.y, 0)); Util.SetVelocity(rb, Vector3.zero); }
            }
            else flippedTimer = 0f;
        }

        void LateUpdate()
        {
            if (mode == VehicleMode.Player && thirdPerson && Game.Player != null && Game.Player.vehicle == this)
            {
                var cam = Game.Cam.transform;
                var vel = Util.GetVelocity(rb);
                var behind = transform.position - transform.forward * 7.5f + Vector3.up * 2.8f - vel * 0.05f;
                cam.position = Vector3.SmoothDamp(cam.position, behind, ref camVel, 0.12f);
                cam.rotation = Quaternion.Slerp(cam.rotation, Quaternion.LookRotation(transform.position + Vector3.up * 1.2f + transform.forward * 3f - cam.position), Time.deltaTime * 10f);
            }
            // spin wheels
            float spd = rb != null && !rb.isKinematic ? Vector3.Dot(Util.GetVelocity(rb), transform.forward) : trafficSpeed;
            wheelSpin += spd / Mathf.Max(0.1f, wheelRadius) * Mathf.Rad2Deg * Time.deltaTime;
            for (int i = 0; i < wheelVis.Count; i++)
            {
                float st = wheelFront[i] ? steer * maxSteer : 0f;
                wheelVis[i].localRotation = Quaternion.Euler(0, st, 0) * Quaternion.Euler(wheelSpin, 0, 0);
                wheelVis[i].localPosition = wheelLocal[i] + Vector3.up * (rb != null && !rb.isKinematic ? wheelSusp[i] : 0f);
            }
            if (engineSrc != null && mode != VehicleMode.Parked)
            {
                float k = Mathf.Clamp01(Mathf.Abs(spd) / maxSpeed);
                engineSrc.pitch = 0.55f + k * 1.5f + Mathf.Abs(throttle) * 0.15f;
            }
        }

        void FixedUpdate()
        {
            float dt = Time.fixedDeltaTime;
            if (mode == VehicleMode.Traffic) { TrafficTick(dt); return; }
            if (mode == VehicleMode.Parked) return;
            Simulate(dt);
            if (burnTimer >= 0f)
            {
                burnTimer -= dt;
                if (Random.value < 0.3f) Game.Fx?.Burst(transform.position + Vector3.up * 1.2f + transform.forward * boxSize.z * 0.35f, new Color(1f, 0.4f, 0.1f), 2);
                if (burnTimer < 0f) Explode();
            }
        }

        void Simulate(float dt)
        {
            bool playerDriving = mode == VehicleMode.Player;
            float thr = playerDriving ? throttle : 0f;
            float st = playerDriving ? steer : 0f;
            bool hb = playerDriving ? handbrake : mode == VehicleMode.Abandoned;
            var vel = Util.GetVelocity(rb);
            float fwdSpeed = Vector3.Dot(vel, transform.forward);
            float perkMult = Game.Stats != null && Game.Stats.HasPerk("wheelman") ? 1.15f : 1f;
            float vmax = maxSpeed * perkMult;
            float steerAngle = st * maxSteer * Mathf.Lerp(1f, 0.35f, Mathf.Abs(fwdSpeed) / vmax);
            groundedWheels = 0;
            float massPerWheel = rb.mass / wheelLocal.Count;
            float slip = 0f;
            for (int i = 0; i < wheelLocal.Count; i++)
            {
                var mount = transform.TransformPoint(wheelLocal[i] + Vector3.up * rest);
                if (!Physics.Raycast(mount, -transform.up, out var hit, rest + wheelRadius, Layers.WorldMask, QueryTriggerInteraction.Ignore)) { wheelSusp[i] = 0f; continue; }
                groundedWheels++;
                float dist = hit.distance - wheelRadius;
                float comp = Mathf.Clamp01(1f - dist / rest);
                wheelSusp[i] = Mathf.Clamp(rest - dist, 0f, rest);
                var pv = rb.GetPointVelocity(mount);
                float springVel = Vector3.Dot(pv, transform.up);
                float f = Mathf.Clamp(comp * stiffness - springVel * damping, 0f, stiffness * 3f);
                rb.AddForceAtPosition(transform.up * f, mount);

                var fwd = Quaternion.AngleAxis(wheelFront[i] ? steerAngle : 0f, transform.up) * transform.forward;
                var right = Vector3.Cross(transform.up, fwd);
                var cv = rb.GetPointVelocity(hit.point);
                float lat = Vector3.Dot(cv, right);
                float g = grip * (hb && !wheelFront[i] ? 0.18f : 1f);
                rb.AddForceAtPosition(-right * lat * g * massPerWheel, hit.point);
                slip = Mathf.Max(slip, Mathf.Abs(lat));

                bool driven = type == VehicleType.Trike ? !wheelFront[i] : true;
                if (driven && Mathf.Abs(thr) > 0.01f)
                {
                    bool braking = Mathf.Sign(thr) != Mathf.Sign(fwdSpeed) && Mathf.Abs(fwdSpeed) > 1f;
                    float a = braking ? 14f : engine * (thr > 0 ? 1f : 0.5f) * Mathf.Clamp01(1f - Mathf.Abs(fwdSpeed) / (thr > 0 ? vmax : vmax * 0.35f));
                    rb.AddForceAtPosition(fwd * Mathf.Sign(thr) * a * massPerWheel * perkMult, hit.point);
                }
                // rolling resistance & handbrake
                float roll = hb ? 3f : 0.25f;
                rb.AddForceAtPosition(-fwd * Vector3.Dot(cv, fwd) * roll * massPerWheel * 0.2f, hit.point);
            }
            if (groundedWheels > 0)
                rb.AddForce(-transform.up * vel.magnitude * rb.mass * 0.08f);
            else
                rb.AddTorque(transform.right * InputHub.Move.y * rb.mass * 0.4f * (playerDriving ? 1 : 0));
            if (skidSrc != null) skidSrc.volume = Mathf.Lerp(skidSrc.volume, groundedWheels > 0 && slip > 4f ? Mathf.Clamp01((slip - 4f) / 8f) * 0.6f * (Game.Audio != null ? Game.Audio.SfxVolume : 1f) : 0f, dt * 10f);
        }

        void TrafficTick(float dt)
        {
            if (path.Count < 4) AppendSegment();
            var target = path.Peek();
            var pos = rb.position;
            var to = (target - pos).Flat();
            if (to.magnitude < 2.5f) { path.Dequeue(); return; }
            float want = cruise;
            // look further ahead for turns
            float turn = Vector3.Angle(transform.forward, to);
            if (turn > 25f) want *= 0.45f;
            // obstacles ahead
            float look = 5f + trafficSpeed * 1.3f;
            if (Physics.BoxCast(pos + Vector3.up * 0.9f + transform.forward * (boxSize.z * 0.5f + 0.3f), new Vector3(boxSize.x * 0.45f, 0.5f, 0.2f), transform.forward, out var hit, transform.rotation, look, Layers.ActorAndPlayerMask, QueryTriggerInteraction.Ignore))
            {
                if (hit.collider.attachedRigidbody != rb)
                {
                    float d = hit.distance;
                    want = d < 3f ? 0f : Mathf.Min(want, d * 0.8f);
                    bool isPlayer = Game.Player != null && hit.collider.transform.root == Game.Player.transform.root;
                    if (want < 1f && isPlayer)
                    {
                        blockedTime += dt;
                        if (blockedTime > 2.5f) { blockedTime = -3f; Game.Audio?.Play3D("horn", pos, 0.8f); }
                    }
                }
            }
            else blockedTime = 0f;
            trafficSpeed = Mathf.MoveTowards(trafficSpeed, want, (want < trafficSpeed ? 14f : 4f) * dt);
            var dirN = to.normalized;
            var rot = Quaternion.RotateTowards(rb.rotation, Quaternion.LookRotation(dirN), (40f + trafficSpeed * 6f) * dt);
            var next = pos + rot * Vector3.forward * trafficSpeed * dt;
            next.y = 0.02f;
            rb.MovePosition(next);
            rb.MoveRotation(rot);
        }

        // ------------------------------------------------------------------ damage
        void OnCollisionEnter(Collision c)
        {
            float impact = c.relativeVelocity.magnitude;
            if (impact < 5f) return;
            bool playerCar = mode == VehicleMode.Player;
            var other = c.collider;
            var victim = Damageable.Resolve(other, out _, out _);
            if (victim != null && victim != dmg && !victim.isDead)
            {
                bool isNpc = victim.GetComponent<NPC>() != null;
                victim.ApplyDamage(new DamageInfo
                {
                    amount = impact * (isNpc ? 9f : 3f), type = DamageType.Vehicle, point = c.GetContact(0).point,
                    direction = Util.GetVelocity(rb).normalized, source = playerCar ? Game.Player.gameObject : gameObject, fromPlayer = playerCar, force = impact
                });
            }
            var otherCar = other.GetComponentInParent<Vehicle>();
            if (otherCar != null && otherCar.mode == VehicleMode.Traffic && impact > 7f) otherCar.SetMode(VehicleMode.Abandoned);
            if (impact > 7f)
            {
                float self = (impact - 6f) * 4f * (Game.Stats != null && playerCar && Game.Stats.HasPerk("wheelman") ? 0.7f : 1f);
                dmg.ApplyDamage(new DamageInfo { amount = self, type = DamageType.Vehicle, point = transform.position, direction = -c.relativeVelocity.normalized });
                Game.Audio?.Play3D("crash", c.GetContact(0).point, Mathf.Clamp01(impact / 20f));
                if (playerCar) Game.Player.Shake(Mathf.Clamp01(impact / 25f));
                Game.Fx?.Impact(c.GetContact(0).point, c.GetContact(0).normal, 2);
            }
            if (mode == VehicleMode.Traffic && impact > 6f) SetMode(VehicleMode.Abandoned);
        }

        void OnDamaged(DamageInfo info)
        {
            if (mode == VehicleMode.Traffic && info.fromPlayer) { SetMode(VehicleMode.Abandoned); }
            if (dmg.Fraction < 0.25f && burnTimer < 0f && !dmg.isDead && Random.value < 0.05f) burnTimer = 6f;
        }

        void OnDestroyed(DamageInfo info)
        {
            if (burnTimer < 0f) burnTimer = 3.5f;
        }

        void Explode()
        {
            burnTimer = -1f;
            Game.Fx?.Explosion(transform.position + Vector3.up, 7f);
            Effects.Blast(transform.position + Vector3.up, 7f, 160f, gameObject, false, false);
            if (Game.Player != null && Game.Player.vehicle == this)
            {
                Game.Player.ExitVehicle(true);
                Game.Stats?.dmg.ApplyDamage(new DamageInfo { amount = 80f, type = DamageType.Explosive, point = transform.position, source = gameObject });
            }
            var wreck = Mats.Cached("wreck", () => Mats.Lit(new Color(0.05f, 0.04f, 0.04f), Tex.Ribbed.albedo, 0.1f));
            foreach (var r in GetComponentsInChildren<Renderer>()) r.sharedMaterial = wreck;
            rb.AddForce(Vector3.up * rb.mass * 6f, ForceMode.Impulse);
            rb.AddTorque(Random.insideUnitSphere * rb.mass * 2f, ForceMode.Impulse);
            SetMode(VehicleMode.Wreck);
            if (engineSrc != null) engineSrc.volume = 0;
            Destroy(gameObject, 90f);
        }
    }
}
