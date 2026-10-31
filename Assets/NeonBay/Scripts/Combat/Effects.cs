using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>Pooled visual effects: muzzle flashes, tracers, impacts, decals, explosions, bursts.</summary>
    public class Effects : MonoBehaviour
    {
        ParticleSystem sparks, blood, oil, smoke, burst, fire;
        readonly List<LineRenderer> tracers = new List<LineRenderer>();
        readonly List<float> tracerLife = new List<float>();
        int tracerIdx;
        readonly List<Transform> decals = new List<Transform>();
        int decalIdx;
        readonly List<Light> flashLights = new List<Light>();
        readonly List<float> flashLife = new List<float>();
        Material tracerMat, decalMat, flashMat;
        readonly List<Transform> flashes = new List<Transform>();
        readonly List<float> flashT = new List<float>();
        int flashIdx;

        public void Init()
        {
            Game.Fx = this;
            sparks = MakePs("Sparks", Mats.Particle(new Color(1f, 0.8f, 0.4f, 1f) * 2f, Tex.Streak, true), 0.25f, 9f, 0.04f, true, 1000);
            blood = MakePs("Blood", Mats.Particle(new Color(0.5f, 0.02f, 0.03f, 0.9f), Tex.Smoke, false), 0.45f, 3f, 0.25f, false, 400);
            oil = MakePs("Oil", Mats.Particle(new Color(0.2f, 0.9f, 1f, 0.9f) * 1.5f, Tex.Glow, true), 0.4f, 4f, 0.12f, true, 300);
            smoke = MakePs("Smoke", Mats.Particle(new Color(0.4f, 0.4f, 0.42f, 0.45f), Tex.Smoke, false), 2.2f, 1.2f, 1.6f, false, 300);
            burst = MakePs("Burst", Mats.Particle(Color.white * 2f, Tex.Glow, true), 0.6f, 5f, 0.12f, false, 500);
            fire = MakePs("Fireball", Mats.Particle(new Color(1f, 0.55f, 0.15f, 1f) * 2.5f, Tex.Smoke, true), 0.7f, 6f, 2.2f, false, 300);
            var grav = sparks.main; grav.gravityModifier = 1.2f;
            var bg = blood.main; bg.gravityModifier = 0.6f;
            var og = oil.main; og.gravityModifier = 0.8f;

            tracerMat = Mats.Additive(new Color(1f, 0.85f, 0.5f, 0.9f) * 2f, Tex.Glow);
            for (int i = 0; i < 24; i++)
            {
                var go = new GameObject("Tracer" + i);
                go.transform.SetParent(transform, false);
                var lr = go.AddComponent<LineRenderer>();
                lr.sharedMaterial = tracerMat;
                lr.positionCount = 2;
                lr.widthMultiplier = 0.035f;
                lr.shadowCastingMode = ShadowCastingMode.Off;
                lr.receiveShadows = false;
                lr.enabled = false;
                tracers.Add(lr); tracerLife.Add(0);
            }
            decalMat = Mats.Particle(Color.white, Tex.BulletHole, false);
            for (int i = 0; i < 80; i++)
            {
                var q = Util.Primitive(PrimitiveType.Quad, "Decal" + i, transform, Vector3.zero, Vector3.one * 0.14f, decalMat);
                q.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
                q.SetActive(false);
                decals.Add(q.transform);
            }
            flashMat = Mats.Additive(new Color(1f, 0.75f, 0.35f, 1f) * 3f, Tex.Glow);
            for (int i = 0; i < 12; i++)
            {
                var q = Util.Primitive(PrimitiveType.Quad, "Flash" + i, transform, Vector3.zero, Vector3.one * 0.5f, flashMat);
                q.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
                q.SetActive(false);
                flashes.Add(q.transform); flashT.Add(0);
            }
            for (int i = 0; i < 6; i++)
            {
                var l = new GameObject("FxLight" + i).AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.type = LightType.Point; l.shadows = LightShadows.None; l.enabled = false;
                flashLights.Add(l); flashLife.Add(0);
            }
        }

        ParticleSystem MakePs(string name, Material mat, float life, float speed, float size, bool stretch, int max)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = false;
            main.playOnAwake = false;
            main.startLifetime = new ParticleSystem.MinMaxCurve(life * 0.5f, life);
            main.startSpeed = new ParticleSystem.MinMaxCurve(speed * 0.3f, speed);
            main.startSize = new ParticleSystem.MinMaxCurve(size * 0.5f, size);
            main.maxParticles = max;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = ps.emission; em.rateOverTime = 0;
            var shape = ps.shape; shape.shapeType = ParticleSystemShapeType.Cone; shape.angle = 35f; shape.radius = 0.02f;
            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) }, new[] { new GradientAlphaKey(1, 0), new GradientAlphaKey(0, 1) });
            col.color = g;
            var r = ps.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = mat;
            r.renderMode = stretch ? ParticleSystemRenderMode.Stretch : ParticleSystemRenderMode.Billboard;
            if (stretch) { r.velocityScale = 0.04f; r.lengthScale = 1f; }
            r.shadowCastingMode = ShadowCastingMode.Off;
            return ps;
        }

        void Emit(ParticleSystem ps, Vector3 pos, Vector3 dir, int count)
        {
            ps.transform.position = pos;
            ps.transform.rotation = dir.sqrMagnitude > 0.001f ? Quaternion.LookRotation(dir) : Quaternion.identity;
            ps.Emit(count);
        }

        void Update()
        {
            float dt = Time.deltaTime;
            for (int i = 0; i < tracers.Count; i++)
            {
                if (!tracers[i].enabled) continue;
                tracerLife[i] -= dt;
                if (tracerLife[i] <= 0) tracers[i].enabled = false;
                else tracers[i].widthMultiplier = 0.035f * (tracerLife[i] / 0.05f);
            }
            for (int i = 0; i < flashLights.Count; i++)
            {
                if (!flashLights[i].enabled) continue;
                flashLife[i] -= dt;
                flashLights[i].intensity *= 0.85f;
                if (flashLife[i] <= 0) flashLights[i].enabled = false;
            }
            for (int i = 0; i < flashes.Count; i++)
            {
                if (!flashes[i].gameObject.activeSelf) continue;
                flashT[i] -= dt;
                if (flashT[i] <= 0) flashes[i].gameObject.SetActive(false);
            }
        }

        public void Tracer(Vector3 from, Vector3 to, Color c)
        {
            var lr = tracers[tracerIdx];
            tracerLife[tracerIdx] = 0.05f;
            tracerIdx = (tracerIdx + 1) % tracers.Count;
            lr.SetPosition(0, from + (to - from).normalized * 0.5f);
            lr.SetPosition(1, to);
            lr.startColor = Color.Lerp(Color.white, c, 0.5f);
            lr.endColor = Color.Lerp(Color.white, c, 0.5f).WithAlpha(0.3f);
            lr.enabled = true;
        }

        public void MuzzleFlash(Vector3 pos, Vector3 dir, Color c)
        {
            var f = flashes[flashIdx];
            flashT[flashIdx] = 0.035f;
            flashIdx = (flashIdx + 1) % flashes.Count;
            f.position = pos;
            var cam = Game.Cam;
            if (cam != null) f.rotation = Quaternion.LookRotation(pos - cam.transform.position) * Quaternion.Euler(0, 0, Random.Range(0, 360f));
            f.localScale = Vector3.one * Random.Range(0.35f, 0.6f);
            f.gameObject.SetActive(true);
            Emit(sparks, pos, dir, 3);
        }

        public void LightFlash(Vector3 pos, Color c, float intensity, float range, float time)
        {
            for (int i = 0; i < flashLights.Count; i++)
            {
                if (flashLights[i].enabled && i < flashLights.Count - 1) continue;
                var l = flashLights[i];
                l.transform.position = pos; l.color = c; l.intensity = intensity; l.range = range; l.enabled = true;
                flashLife[i] = time;
                return;
            }
        }

        /// <summary>surface: 0 world, 1 flesh, 2 chrome/robot</summary>
        public void Impact(Vector3 p, Vector3 n, int surface)
        {
            switch (surface)
            {
                case 1: Emit(blood, p, n, 8); break;
                case 2: Emit(oil, p, n, 10); Emit(sparks, p, n, 8); break;
                default:
                    Emit(sparks, p, n, 6);
                    Emit(smoke, p, n, 1);
                    Game.Audio?.PlayVar("impact_concrete", p, 0.5f, 40f);
                    break;
            }
            if (surface == 2) Game.Audio?.PlayVar("impact_metal", p, 0.6f, 40f);
            if (surface == 1) Game.Audio?.PlayVar("impact_flesh", p, 0.6f, 30f);
        }

        public void Decal(Vector3 p, Vector3 n, Transform parent)
        {
            var d = decals[decalIdx];
            decalIdx = (decalIdx + 1) % decals.Count;
            d.gameObject.SetActive(true);
            d.SetParent(transform, false);
            d.position = p + n * 0.01f;
            d.rotation = Quaternion.LookRotation(-n) * Quaternion.Euler(0, 0, Random.Range(0, 360f));
            d.localScale = Vector3.one * Random.Range(0.1f, 0.16f);
        }

        public void Burst(Vector3 p, Color c, int count)
        {
            var main = burst.main; main.startColor = c;
            Emit(burst, p, Vector3.up, count);
        }

        public void Explosion(Vector3 p, float radius)
        {
            var m = fire.main; m.startSize = new ParticleSystem.MinMaxCurve(radius * 0.3f, radius * 0.6f);
            var sh = fire.shape; sh.angle = 80f;
            Emit(fire, p, Vector3.up, 30);
            var sm = smoke.main; sm.startSize = new ParticleSystem.MinMaxCurve(radius * 0.4f, radius * 0.8f);
            Emit(smoke, p, Vector3.up, 16);
            sm.startSize = new ParticleSystem.MinMaxCurve(0.8f, 1.6f);
            Emit(sparks, p, Vector3.up, 60);
            LightFlash(p + Vector3.up, new Color(1f, 0.6f, 0.25f), 8f, radius * 4f, 0.4f);
            Game.Audio?.Play3D("explosion", p, 1f, Random.Range(0.9f, 1.05f), 6f, 300f);
            var cam = Game.Cam;
            if (cam != null && Game.Player != null)
            {
                float d = Vector3.Distance(cam.transform.position, p);
                Game.Player.Shake(Mathf.Clamp01(1.2f - d / (radius * 5f)));
            }
        }

        public void ElectricBurst(Vector3 p, float radius)
        {
            var main = burst.main; main.startColor = new Color(0.3f, 0.8f, 1f) * 2f;
            Emit(burst, p, Vector3.up, 60);
            Emit(oil, p, Vector3.up, 30);
            LightFlash(p + Vector3.up, Palette.Cyan, 6f, radius * 3f, 0.3f);
            Game.Audio?.Play3D("glitch", p, 1f, 0.7f, 5f, 120f);
        }

        /// <summary>Radial damage with line-of-sight falloff.</summary>
        public static void Blast(Vector3 p, float radius, float damage, GameObject source, bool emp, bool fromPlayer)
        {
            if (fromPlayer && Game.Stats != null && Game.Stats.HasPerk("grenadier")) { radius *= 1.4f; damage *= 1.4f; }
            var hits = Physics.OverlapSphere(p, radius, Layers.ShootMask | Layers.PlayerMask, QueryTriggerInteraction.Ignore);
            var done = new HashSet<Damageable>();
            foreach (var h in hits)
            {
                if (h.attachedRigidbody != null && !h.attachedRigidbody.isKinematic && !emp)
                    h.attachedRigidbody.AddExplosionForce(damage * 8f, p, radius, 1.5f, ForceMode.Impulse);
                var d = Damageable.Resolve(h, out _, out _);
                if (d == null || done.Contains(d)) continue;
                done.Add(d);
                var c = d.transform.position + Vector3.up;
                float dist = Vector3.Distance(c, p);
                if (!Util.LineOfSight(p + Vector3.up * 0.3f, c)) continue;
                float k = Mathf.Clamp01(1f - dist / radius);
                if (emp)
                {
                    d.ApplyDamage(new DamageInfo { amount = (d.isRobotic ? 120f : 15f) * (0.5f + k * 0.5f), type = DamageType.Electric, point = c, direction = (c - p).normalized, source = source, fromPlayer = fromPlayer });
                    var npc = d.GetComponent<NPC>();
                    if (npc != null) npc.Stun(4f);
                }
                else
                {
                    d.ApplyDamage(new DamageInfo { amount = damage * (0.25f + 0.75f * k), type = DamageType.Explosive, point = c, direction = (c - p).normalized, source = source, fromPlayer = fromPlayer, force = 25f * k });
                }
            }
            GameEvents.RaiseNoise(p, 90f, source);
        }
    }

    public class Grenade : MonoBehaviour
    {
        public bool emp;
        public GameObject owner;
        float fuse = 2.2f;
        bool fromPlayer;

        public static void Throw(Vector3 pos, Vector3 velocity, bool emp, GameObject owner)
        {
            var go = Util.Primitive(PrimitiveType.Sphere, emp ? "EMP" : "Frag", null, pos, Vector3.one * 0.14f,
                Mats.Cached(emp ? "empmat" : "fragmat", () => emp ? Mats.Unlit(Palette.Cyan * 3f) : Mats.Emissive(new Color(0.2f, 0.25f, 0.2f), Palette.Red * 2f)), true);
            go.layer = Layers.Actors;
            var rb = go.AddComponent<Rigidbody>();
            rb.mass = 0.4f;
            rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            Util.SetVelocity(rb, velocity);
            rb.angularVelocity = Random.insideUnitSphere * 10f;
            var g = go.AddComponent<Grenade>();
            g.emp = emp; g.owner = owner;
            g.fromPlayer = owner != null && owner.GetComponent<PlayerController>() != null;
            if (g.fromPlayer && Game.Player != null)
                foreach (var c in Game.Player.GetComponentsInChildren<Collider>()) Physics.IgnoreCollision(go.GetComponent<Collider>(), c);
        }

        void OnCollisionEnter(Collision c)
        {
            if (c.relativeVelocity.magnitude > 2f) Game.Audio?.Play3D("grenade_bounce", transform.position, 0.6f);
        }

        void Update()
        {
            fuse -= Time.deltaTime;
            if (fuse > 0f) return;
            var p = transform.position;
            if (emp) { Game.Fx?.ElectricBurst(p, 8f); Effects.Blast(p, 8f, 0f, owner, true, fromPlayer); }
            else { Game.Fx?.Explosion(p, 7f); Effects.Blast(p, 7f, 140f, owner, false, fromPlayer); }
            Destroy(gameObject);
        }
    }
}
