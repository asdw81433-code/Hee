using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// Everything alive around the Pit's ring: the dynamic ropes, turnbuckles, overhead light rig, the canvas logo,
    /// a crowd that cheers, jumps and gasps with the fight, and the arena's crowd noise.
    /// </summary>
    public class PitArena : MonoBehaviour
    {
        public RingRopes ring;
        public Vector3 center;   // canvas centre
        public float floorY;
        public float half = 4.88f;
        class Fan { public HumanoidRig rig; public Vector3 pos; public float yaw, phase, excite, jump; public int mood; }
        readonly List<Fan> fans = new List<Fan>();
        bool crowdBuilt;
        float crowdRetry;
        AudioSource crowdLoop;
        float hype, hypeTarget;
        float oohCd, cheerCd;
        Light keyA, keyB;

        public static PitArena Create(Vector3 canvasCenter)
        {
            var go = new GameObject("PitArena");
            var a = go.AddComponent<PitArena>();
            a.center = canvasCenter;
            a.floorY = canvasCenter.y - 0.8f;
            a.Build();
            Boxing.Arena = a;
            return a;
        }

        void Build()
        {
            ring = RingRopes.Build(transform, center, half);
            // overhead truss with neon and two hard key lights that make faces and sweat read
            var trussMat = Mats.Cached("truss", () => Mats.Lit(new Color(0.12f, 0.12f, 0.13f), Tex.Metal.albedo, 0.6f, 0.8f, Tex.Metal.normal));
            float th = 5.2f;
            for (int s = 0; s < 4; s++)
            {
                bool x = s % 2 == 0;
                float o = (s < 2 ? -1 : 1) * (half + 0.6f);
                var bar = Util.Primitive(PrimitiveType.Cube, "Truss", transform, Vector3.zero, x ? new Vector3((half + 0.6f) * 2f, 0.18f, 0.18f) : new Vector3(0.18f, 0.18f, (half + 0.6f) * 2f), trussMat);
                bar.transform.position = center + (x ? new Vector3(0, th, o) : new Vector3(o, th, 0));
                var neon = Util.Primitive(PrimitiveType.Cube, "TrussNeon", transform, Vector3.zero, x ? new Vector3((half + 0.6f) * 2f, 0.05f, 0.05f) : new Vector3(0.05f, 0.05f, (half + 0.6f) * 2f), Anatomy.Glow(s % 2 == 0 ? Palette.Magenta : Palette.Cyan));
                neon.transform.position = bar.transform.position + Vector3.down * 0.13f;
            }
            keyA = MakeSpot(center + new Vector3(-2.5f, th - 0.2f, -2.5f), new Color(1f, 0.93f, 0.85f), true);
            keyB = MakeSpot(center + new Vector3(2.5f, th - 0.2f, 2.5f), new Color(0.85f, 0.9f, 1f), false);
            // canvas logo (neon bay sign art) and ring apron skirt glow
            var logo = Util.Primitive(PrimitiveType.Quad, "CanvasLogo", transform, Vector3.zero, new Vector3(4.2f, 1.2f, 1f), Mats.Cached("canvaslogo", () => Mats.Additive(new Color(1f, 1f, 1f, 1f) * 0.9f, Tex.SignAtlas)));
            logo.transform.position = center + Vector3.up * 0.006f;
            logo.transform.rotation = Quaternion.Euler(90f, 0, 0);
            var mf = logo.GetComponent<MeshFilter>();
            var m = Instantiate(mf.sharedMesh);
            var uv = Tex.SignUV(Tex.SignIndexForWord("BOXING"));
            m.uv = new[] { new Vector2(uv.xMin, uv.yMin), new Vector2(uv.xMax, uv.yMin), new Vector2(uv.xMin, uv.yMax), new Vector2(uv.xMax, uv.yMax) };
            mf.sharedMesh = m;
            for (int s = 0; s < 4; s++)
            {
                var skirt = Util.Primitive(PrimitiveType.Cube, "ApronGlow", transform, Vector3.zero, s % 2 == 0 ? new Vector3(half * 2f + 0.4f, 0.04f, 0.04f) : new Vector3(0.04f, 0.04f, half * 2f + 0.4f), Anatomy.Glow(Palette.Red));
                float o = (s < 2 ? -1 : 1) * (half + 0.22f);
                skirt.transform.position = center + (s % 2 == 0 ? new Vector3(0, -0.05f, o) : new Vector3(o, -0.05f, 0));
            }
            crowdLoop = Game.Audio != null ? Game.Audio.AttachLoop(gameObject, "crowd_loop", 0.0f, 6f, 70f) : null;
            if (crowdLoop != null) crowdLoop.transform.position = center;
        }

        Light MakeSpot(Vector3 pos, Color c, bool shadows)
        {
            var go = new GameObject("RingKey");
            go.transform.SetParent(transform, false);
            go.transform.position = pos;
            go.transform.rotation = Quaternion.LookRotation((center + Vector3.up * 1.2f - pos).normalized);
            var l = go.AddComponent<Light>();
            l.type = LightType.Spot; l.color = c; l.intensity = 9f; l.range = 14f; l.spotAngle = 70f; l.innerSpotAngle = 35f;
            l.shadows = shadows ? LightShadows.Soft : LightShadows.None;
            l.shadowStrength = 0.85f;
            return l;
        }

        // ------------------------------------------------------------------ crowd
        void BuildCrowd()
        {
            crowdBuilt = true;
            var rng = new Rng(777);
            int n = Game.Settings != null && Game.Settings.quality <= 1 ? 22 : 40;
            for (int i = 0; i < n * 3 && fans.Count < n; i++)
            {
                float ang = rng.Range(0f, Mathf.PI * 2f);
                float dist = rng.Range(half + 1.6f, half + 5.5f);
                var p = center + new Vector3(Mathf.Cos(ang) * dist, 0, Mathf.Sin(ang) * dist);
                if (!Physics.Raycast(new Vector3(p.x, center.y + 2.5f, p.z), Vector3.down, out var hit, 6f, Layers.WorldMask, QueryTriggerInteraction.Ignore)) continue;
                if (hit.point.y > center.y - 0.3f) continue; // that's the ring or a prop
                bool tooClose = false;
                foreach (var f in fans) if ((f.pos - hit.point).sqrMagnitude < 0.8f * 0.8f) { tooClose = true; break; }
                if (tooClose) continue;
                var look = Appearance.Random(rng.Chance(0.2f) ? rng.Pick(FactionId.Jackals, FactionId.Lotus, FactionId.Raiders) : FactionId.Civilian, rng);
                look.helmet = false;
                var holder = new GameObject("Fan");
                holder.transform.SetParent(transform, false);
                holder.transform.position = hit.point;
                var toRing = (center - hit.point).Flat().normalized;
                float yaw = Mathf.Atan2(toRing.x, toRing.z) * Mathf.Rad2Deg;
                holder.transform.rotation = Quaternion.Euler(0, yaw, 0);
                var rig = HumanoidRig.Build(holder.transform, look, null, false, 2);
                fans.Add(new Fan { rig = rig, pos = hit.point, yaw = yaw, phase = rng.Range(0f, 10f), mood = rng.Range(0, 3) });
            }
        }

        void DestroyCrowd()
        {
            foreach (var f in fans) if (f.rig != null) Destroy(f.rig.transform.parent.gameObject);
            fans.Clear();
            crowdBuilt = false;
        }

        /// <summary>Crowd reaction: 0.2 = good shot, 0.6 = big shot, 1 = knockdown.</summary>
        public void Excite(float amount)
        {
            hypeTarget = Mathf.Clamp01(hypeTarget + amount);
            foreach (var f in fans) { f.excite = Mathf.Max(f.excite, amount * Random.Range(0.6f, 1.2f)); if (amount > 0.5f && Random.value < 0.6f) f.jump = Random.Range(0.4f, 0.9f); }
            if (Game.Audio == null) return;
            if (amount >= 0.8f && cheerCd <= 0f) { cheerCd = 1.5f; Game.Audio.Play3D("crowd_cheer", center + Vector3.up * 2f, 1f, Random.Range(0.92f, 1.05f), 8f, 90f); }
            else if (amount >= 0.35f && oohCd <= 0f) { oohCd = 0.7f; Game.Audio.Play3D("crowd_ooh", center + Vector3.up * 2f, 0.8f, Random.Range(0.9f, 1.1f), 8f, 80f); }
        }

        void Update()
        {
            float dt = Time.deltaTime;
            oohCd -= dt; cheerCd -= dt;
            var cam = Game.Cam;
            float dCam = cam != null ? (cam.transform.position - center).magnitude : 999f;
            bool fight = Boxing.Match != null && Boxing.Match.Running;
            crowdRetry -= dt;
            if (dCam < 45f && !crowdBuilt && Game.IsPlaying && crowdRetry <= 0f)
            {
                BuildCrowd();
                if (fans.Count < 6) { DestroyCrowd(); crowdRetry = 4f; } // floor not streamed in yet
            }
            else if (dCam > 70f && crowdBuilt && !fight) DestroyCrowd();
            hypeTarget = Mathf.MoveTowards(hypeTarget, fight ? 0.35f : 0.1f, dt * 0.08f);
            hype = Mathf.MoveTowards(hype, hypeTarget, dt * 0.8f);
            if (crowdLoop != null)
            {
                crowdLoop.volume = (Game.Audio != null ? Game.Audio.SfxVolume : 1f) * Mathf.Lerp(0.18f, 0.9f, hype) * (fight ? 1f : 0.5f);
                crowdLoop.pitch = Mathf.Lerp(0.95f, 1.08f, hype);
            }
            if (keyA != null) { keyA.enabled = dCam < 60f; keyB.enabled = dCam < 60f; }
            if (!crowdBuilt || fans.Count == 0) return;
            // the crowd watches the action
            Vector3 focus = center + Vector3.up * 1.4f;
            if (fight && Boxing.Match.Red != null && Boxing.Match.Blue != null)
                focus = (Boxing.Match.Red.rig.hips.position + Boxing.Match.Blue.rig.hips.position) * 0.5f + Vector3.up * 0.4f;
            float t = Time.time;
            foreach (var f in fans)
            {
                if (f.rig == null) continue;
                f.excite = Mathf.MoveTowards(f.excite, hype * 0.5f, dt * 0.4f);
                float ex = f.excite;
                f.jump = Mathf.MoveTowards(f.jump, 0f, dt * 0.5f);
                f.rig.Animate(0f, false, false, dt);
                // bounce, raise fists, shake arms
                float bounce = Mathf.Abs(Mathf.Sin(t * 7f + f.phase)) * 0.12f * f.jump + Mathf.Abs(Mathf.Sin(t * 3f + f.phase)) * 0.02f * ex;
                f.rig.hips.localPosition += Vector3.up * bounce;
                if (ex > 0.35f || f.jump > 0f)
                {
                    float arms = Mathf.Clamp01((ex - 0.3f) * 2f + f.jump);
                    float pump = Mathf.Sin(t * 8f + f.phase) * 20f;
                    if (f.mood == 0)
                    {
                        f.rig.shoulderL.localRotation = Quaternion.Slerp(f.rig.shoulderL.localRotation, Quaternion.Euler(-160f + pump, 0, -15f), arms);
                        f.rig.shoulderR.localRotation = Quaternion.Slerp(f.rig.shoulderR.localRotation, Quaternion.Euler(-160f - pump, 0, 15f), arms);
                        f.rig.elbowL.localRotation = Quaternion.Slerp(f.rig.elbowL.localRotation, Quaternion.Euler(-30f, 0, 0), arms);
                        f.rig.elbowR.localRotation = Quaternion.Slerp(f.rig.elbowR.localRotation, Quaternion.Euler(-30f, 0, 0), arms);
                    }
                    else if (f.mood == 1)
                    {
                        f.rig.shoulderR.localRotation = Quaternion.Slerp(f.rig.shoulderR.localRotation, Quaternion.Euler(-150f + pump * 1.5f, 0, 10f), arms);
                        f.rig.elbowR.localRotation = Quaternion.Slerp(f.rig.elbowR.localRotation, Quaternion.Euler(-60f, 0, 0), arms);
                    }
                    else
                    {
                        float clap = Mathf.Abs(Mathf.Sin(t * 9f + f.phase));
                        f.rig.shoulderL.localRotation = Quaternion.Slerp(f.rig.shoulderL.localRotation, Quaternion.Euler(-70f, 30f - clap * 10f, 0), arms);
                        f.rig.shoulderR.localRotation = Quaternion.Slerp(f.rig.shoulderR.localRotation, Quaternion.Euler(-70f, -30f + clap * 10f, 0), arms);
                        f.rig.elbowL.localRotation = Quaternion.Slerp(f.rig.elbowL.localRotation, Quaternion.Euler(-70f, 0, 0), arms);
                        f.rig.elbowR.localRotation = Quaternion.Slerp(f.rig.elbowR.localRotation, Quaternion.Euler(-70f, 0, 0), arms);
                    }
                }
                f.rig.LookAt(focus);
            }
        }
    }
}
