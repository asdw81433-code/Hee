using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    public enum InjuryZone { EyeL, EyeR, CheekL, CheekR, Nose, Mouth, BrowL, BrowR, Chin, RibsL, RibsR, Liver, Stomach, ArmL, ArmR, LegL, LegR }

    /// <summary>Serializable snapshot so the player's face carries the fight home.</summary>
    [Serializable]
    public class InjuryRecord
    {
        public float[] swell = new float[17], bruise = new float[17], cut = new float[17];
        public float concussion, bodyTrauma;
        public bool Any
        {
            get
            {
                if (concussion > 0.02f || bodyTrauma > 0.02f) return true;
                for (int i = 0; i < swell.Length; i++) if (swell[i] > 0.02f || bruise[i] > 0.02f || cut[i] > 0.02f) return true;
                return false;
            }
        }
    }

    /// <summary>
    /// Realistic damage on a character: swelling that closes eyes, bruises that darken, cuts that bleed down the face,
    /// a nose that bleeds, accumulating concussion and body trauma. Also exposes the gameplay penalties.
    /// </summary>
    public class InjuryState : MonoBehaviour
    {
        public const int Zones = 17;
        public readonly float[] swell = new float[Zones], bruise = new float[Zones], cut = new float[Zones];
        public float concussion;   // accumulated head trauma 0..1 (knockdowns come easier)
        public float bodyTrauma;   // accumulated body damage 0..1 (stamina drains)
        public float bleedTotal;   // how much blood has been lost (visual streaks)
        public bool canHeal = true;

        HumanoidRig rig;
        Profile head, trunk;
        Color skin;
        class Visual { public Transform t; public MeshRenderer r; public float baseScale; public bool patch; }
        readonly Visual[] swellVis = new Visual[Zones * 2];
        readonly Visual[] bruiseVis = new Visual[Zones];
        readonly Visual[] cutVis = new Visual[Zones];
        readonly Visual[] streakVis = new Visual[Zones];
        float dripTimer, stainTimer;
        MaterialPropertyBlock mpb;
        static readonly Color BruiseColor = new Color(0.32f, 0.1f, 0.2f);
        static readonly Color BloodColor = new Color(0.42f, 0.02f, 0.03f);

        public event Action<InjuryZone, float> Injured;

        public static InjuryState Attach(HumanoidRig rig, Appearance a)
        {
            var s = rig.gameObject.AddComponent<InjuryState>();
            s.rig = rig;
            s.head = BodyBuilder.HeadProfile(a.jaw, a.female);
            s.trunk = BodyBuilder.Trunk(BodyBuilder.Dims.Of(a), true);
            s.skin = a.skin;
            s.mpb = new MaterialPropertyBlock();
            return s;
        }

        // ------------------------------------------------------------------ zone geometry (head: y, angle; body: y, angle on the trunk)
        static readonly float[] zoneY = { 0.158f, 0.158f, 0.132f, 0.132f, 0.13f, 0.088f, 0.184f, 0.184f, 0.05f, 0.27f, 0.27f, 0.2f, 0.14f, 0f, 0f, 0f, 0f };
        static readonly float[] zoneA = { 113f, 67f, 138f, 42f, 90f, 90f, 118f, 62f, 90f, 140f, 40f, 45f, 90f, 0f, 0f, 0f, 0f };

        public static bool IsHead(InjuryZone z) => z <= InjuryZone.Chin;

        /// <summary>Finds the facial zone nearest to a world point on the head.</summary>
        public InjuryZone HeadZoneAt(Vector3 world)
        {
            if (rig == null || rig.head == null) return InjuryZone.Nose;
            var l = rig.head.InverseTransformPoint(world);
            float th = Mathf.Atan2(l.z, l.x) * Mathf.Rad2Deg;
            if (th < 0) th += 360f;
            float best = 1e9f; int bi = 4;
            for (int i = 0; i <= (int)InjuryZone.Chin; i++)
            {
                float dy = (l.y - zoneY[i]) / 0.03f, da = Mathf.DeltaAngle(th, zoneA[i]) / 30f;
                float d = dy * dy + da * da;
                if (d < best) { best = d; bi = i; }
            }
            return (InjuryZone)bi;
        }

        public InjuryZone BodyZoneAt(Vector3 world)
        {
            if (rig == null) return InjuryZone.Stomach;
            var l = rig.hips.InverseTransformPoint(world);
            if (l.y < 0.12f) return InjuryZone.Stomach;
            if (Mathf.Abs(l.x) < 0.05f) return InjuryZone.Stomach;
            if (l.y < 0.24f && l.x > 0f) return InjuryZone.Liver;
            return l.x > 0 ? InjuryZone.RibsR : InjuryZone.RibsL;
        }

        // ------------------------------------------------------------------ registering damage
        /// <summary>Adds damage to a zone. severity ~0..1 per hit (a clean power punch is ~0.35).</summary>
        public void Register(InjuryZone z, float severity, float cutChance = 0f)
        {
            int i = (int)z;
            severity = Mathf.Max(0f, severity);
            // diminishing returns, faces swell fast then plateau
            swell[i] = Mathf.Clamp01(swell[i] + severity * (1f - swell[i] * 0.55f) * (IsHead(z) ? 0.55f : 0.3f));
            bruise[i] = Mathf.Clamp01(bruise[i] + severity * 0.4f);
            if (IsHead(z))
            {
                concussion = Mathf.Clamp01(concussion + severity * 0.12f);
                bool cuttable = z == InjuryZone.BrowL || z == InjuryZone.BrowR || z == InjuryZone.CheekL || z == InjuryZone.CheekR || z == InjuryZone.Nose || z == InjuryZone.EyeL || z == InjuryZone.EyeR;
                if (cuttable && UnityEngine.Random.value < cutChance * (0.4f + swell[i]))
                {
                    var cz = z == InjuryZone.EyeL ? InjuryZone.BrowL : z == InjuryZone.EyeR ? InjuryZone.BrowR : z;
                    cut[(int)cz] = Mathf.Clamp01(cut[(int)cz] + 0.35f + severity * 0.4f);
                }
                // swelling spreads to the eye from cheek/brow blows
                if (z == InjuryZone.CheekL || z == InjuryZone.BrowL) swell[(int)InjuryZone.EyeL] = Mathf.Clamp01(swell[(int)InjuryZone.EyeL] + severity * 0.25f);
                if (z == InjuryZone.CheekR || z == InjuryZone.BrowR) swell[(int)InjuryZone.EyeR] = Mathf.Clamp01(swell[(int)InjuryZone.EyeR] + severity * 0.25f);
            }
            else bodyTrauma = Mathf.Clamp01(bodyTrauma + severity * (z == InjuryZone.Liver ? 0.22f : 0.12f));
            Injured?.Invoke(z, severity);
            Refresh(i);
        }

        /// <summary>Bullet / blade wound: a bleeding hole that sticks to the bone it hit.</summary>
        public void Wound(Vector3 point, Vector3 normal, Transform bone, float size = 0.05f)
        {
            if (bone == null) return;
            var q = Util.Primitive(PrimitiveType.Quad, "Wound", bone, Vector3.zero, Vector3.one * size, Mats.Cached("wound", () => Mats.Particle(new Color(0.35f, 0.01f, 0.02f, 0.95f), Tex.Splat, false)));
            q.transform.position = point + normal * 0.005f;
            q.transform.rotation = Quaternion.LookRotation(-normal) * Quaternion.Euler(0, 0, UnityEngine.Random.Range(0f, 360f));
            q.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            q.layer = Layers.Actors;
            bleedTotal += 0.1f;
            Game.Fx?.BloodSpray(point, normal, 6);
        }

        // ------------------------------------------------------------------ queries used by gameplay
        public float EyeClosure(bool left) => Mathf.Clamp01((swell[left ? 0 : 1] - 0.35f) * 1.4f);
        public float MaxCut { get { float m = 0; for (int i = 0; i < Zones; i++) m = Mathf.Max(m, cut[i]); return m; } }
        public float FaceDamage { get { float s = 0; for (int i = 0; i <= (int)InjuryZone.Chin; i++) s += swell[i] + cut[i] * 0.5f; return Mathf.Clamp01(s / 5f); } }
        public float RibDamage => Mathf.Max(swell[(int)InjuryZone.RibsL], swell[(int)InjuryZone.RibsR], swell[(int)InjuryZone.Liver] * 1.2f);
        public float LegDamage => Mathf.Max(swell[(int)InjuryZone.LegL], swell[(int)InjuryZone.LegR]);
        public float ArmDamage(bool left) => swell[left ? (int)InjuryZone.ArmL : (int)InjuryZone.ArmR];
        /// <summary>Multiplier on incoming head damage (concussed chins are made of glass).</summary>
        public float ChinFactor => 1f + concussion * 0.8f;
        public float BodyFactor => 1f + bodyTrauma * 0.6f + RibDamage * 0.3f;
        public bool Bleeding => MaxCut > 0.25f || swell[(int)InjuryZone.Nose] > 0.5f;

        /// <summary>Corner work between rounds: closes cuts and brings swelling down.</summary>
        public void Treat(float cutWork, float iceWork)
        {
            for (int i = 0; i < Zones; i++)
            {
                cut[i] = Mathf.Max(0f, cut[i] - cutWork);
                swell[i] = Mathf.Max(0f, swell[i] - iceWork * (IsHead((InjuryZone)i) ? 1f : 0.5f));
                Refresh(i);
            }
        }

        public void HealAll(float amount)
        {
            for (int i = 0; i < Zones; i++)
            {
                swell[i] = Mathf.Max(0f, swell[i] - amount);
                bruise[i] = Mathf.Max(0f, bruise[i] - amount * 0.6f);
                cut[i] = Mathf.Max(0f, cut[i] - amount * 1.2f);
                Refresh(i);
            }
            concussion = Mathf.Max(0f, concussion - amount * 0.5f);
            bodyTrauma = Mathf.Max(0f, bodyTrauma - amount);
            bleedTotal = Mathf.Max(0f, bleedTotal - amount * 2f);
            for (int i = 0; i < Zones; i++) RefreshStreak(i);
        }

        public InjuryRecord Save()
        {
            var r = new InjuryRecord { concussion = concussion, bodyTrauma = bodyTrauma };
            Array.Copy(swell, r.swell, Zones); Array.Copy(bruise, r.bruise, Zones); Array.Copy(cut, r.cut, Zones);
            return r;
        }

        public void Load(InjuryRecord r)
        {
            if (r == null) return;
            if (r.swell != null) Array.Copy(r.swell, swell, Mathf.Min(Zones, r.swell.Length));
            if (r.bruise != null) Array.Copy(r.bruise, bruise, Mathf.Min(Zones, r.bruise.Length));
            if (r.cut != null) Array.Copy(r.cut, cut, Mathf.Min(Zones, r.cut.Length));
            concussion = r.concussion; bodyTrauma = r.bodyTrauma;
            for (int i = 0; i < Zones; i++) Refresh(i);
        }

        // ------------------------------------------------------------------ visuals
        void Refresh(int i)
        {
            if (rig == null || rig.lod > 0) return;
            var z = (InjuryZone)i;
            if (z >= InjuryZone.ArmL) return;
            if (IsHead(z))
            {
                UpdateSwelling(i, 0);
                if (z == InjuryZone.EyeL || z == InjuryZone.EyeR) UpdateSwelling(i, 1);
                UpdatePatch(bruiseVis, i, bruise[i], 0.026f, 0.0013f, BruiseColor, 0.6f);
                UpdateCut(i);
            }
            else UpdatePatch(bruiseVis, i, bruise[i], 0.06f, 0.0015f, BruiseColor, 0.5f);
        }

        void UpdateSwelling(int i, int slot)
        {
            float s = swell[i];
            var key = i * 2 + slot;
            var v = swellVis[key];
            if (s < 0.04f) { if (v != null) v.t.gameObject.SetActive(false); return; }
            if (v == null)
            {
                var z = (InjuryZone)i;
                float y = zoneY[i], a = zoneA[i], r = 0.018f;
                switch (z)
                {
                    case InjuryZone.EyeL: case InjuryZone.EyeR:
                        bool right = z == InjuryZone.EyeR;
                        if (slot == 0) { y = 0.171f; a = right ? 58f : 122f; r = 0.017f; }
                        else { y = 0.146f; a = right ? 64f : 116f; r = 0.015f; }
                        break;
                    case InjuryZone.CheekL: case InjuryZone.CheekR: r = 0.024f; break;
                    case InjuryZone.Nose: y = 0.14f; r = 0.011f; break;
                    case InjuryZone.Mouth: y = 0.083f; r = 0.013f; break;
                    case InjuryZone.BrowL: case InjuryZone.BrowR: r = 0.014f; break;
                    case InjuryZone.Chin: y = 0.05f; r = 0.017f; break;
                }
                Transform parent = z == InjuryZone.Mouth || z == InjuryZone.Chin ? rig.jaw : rig.head;
                var p = head.Point(y, a * Mathf.Deg2Rad);
                var n = head.Normal(y, a * Mathf.Deg2Rad);
                var go = new GameObject("Swelling_" + z);
                go.transform.SetParent(parent, false);
                var local = parent == rig.jaw ? p - BodyBuilder.JawPivot : p;
                go.transform.localPosition = local - n * r * 0.25f;
                go.transform.localRotation = Quaternion.LookRotation(n, Vector3.up);
                var md = new MeshData();
                Anatomy.Ellipsoid(md, 0, Vector3.zero, new Vector3(r, r * 0.78f, r * 0.55f), Matrix4x4.identity, Anatomy.Bone(0), 6, 10);
                go.AddComponent<MeshFilter>().sharedMesh = md.ToMesh("Swell");
                var mr = go.AddComponent<MeshRenderer>();
                mr.sharedMaterial = Anatomy.Skin(skin, false);
                mr.shadowCastingMode = ShadowCastingMode.Off;
                go.layer = Layers.Actors;
                v = new Visual { t = go.transform, r = mr, baseScale = 1f };
                swellVis[key] = v;
            }
            v.t.gameObject.SetActive(true);
            float k = 0.35f + s * 0.95f;
            v.t.localScale = new Vector3(k, k, 0.25f + s * 1.4f);
            var col = Color.Lerp(skin, Color.Lerp(BruiseColor, new Color(0.55f, 0.15f, 0.18f), 0.4f), Mathf.Clamp01(bruise[i] * 0.55f + s * 0.25f));
            mpb.Clear();
            mpb.SetColor("_BaseColor", col); mpb.SetColor("_Color", col);
            v.r.SetPropertyBlock(mpb);
        }

        void UpdatePatch(Visual[] arr, int i, float amount, float size, float lift, Color c, float maxAlpha)
        {
            var v = arr[i];
            if (amount < 0.05f) { if (v != null) v.t.gameObject.SetActive(false); return; }
            if (v == null)
            {
                v = MakePatch(i, size, lift, false, "Bruise");
                if (v == null) return;
                arr[i] = v;
            }
            v.t.gameObject.SetActive(true);
            var col = new Color(c.r, c.g, c.b, Mathf.Clamp01(amount) * maxAlpha);
            mpb.Clear();
            mpb.SetColor("_BaseColor", col); mpb.SetColor("_Color", col);
            v.r.SetPropertyBlock(mpb);
        }

        void UpdateCut(int i)
        {
            float c = cut[i];
            if (c < 0.05f) { if (cutVis[i] != null) cutVis[i].t.gameObject.SetActive(false); return; }
            if (cutVis[i] == null) cutVis[i] = MakePatch(i, 0.012f, 0.0018f, true, "Cut");
            if (cutVis[i] == null) return;
            cutVis[i].t.gameObject.SetActive(true);
            var col = new Color(0.3f, 0.01f, 0.02f, Mathf.Clamp01(0.5f + c * 0.5f));
            mpb.Clear(); mpb.SetColor("_BaseColor", col); mpb.SetColor("_Color", col);
            cutVis[i].r.SetPropertyBlock(mpb);
        }

        void RefreshStreak(int i)
        {
            var v = streakVis[i];
            if (v == null) return;
            float amt = Mathf.Clamp01(bleedTotal * 0.5f) * Mathf.Clamp01(cut[i] * 2f + 0.3f);
            if (amt < 0.03f) { v.t.gameObject.SetActive(false); return; }
            v.t.gameObject.SetActive(true);
            var col = new Color(BloodColor.r, BloodColor.g, BloodColor.b, amt * 0.75f);
            mpb.Clear(); mpb.SetColor("_BaseColor", col); mpb.SetColor("_Color", col);
            v.r.SetPropertyBlock(mpb);
        }

        /// <summary>Thin shell patch lying on the face/trunk around a zone. gash = narrow horizontal slit.</summary>
        Visual MakePatch(int i, float size, float lift, bool gash, string name, bool streak = false)
        {
            var z = (InjuryZone)i;
            bool isHead = IsHead(z);
            var prof = isHead ? head : trunk;
            Transform parent = isHead ? (z == InjuryZone.Mouth || z == InjuryZone.Chin ? rig.jaw : rig.head) : rig.chest;
            if (parent == null) return null;
            float cy = zoneY[i], ca = zoneA[i] * Mathf.Deg2Rad;
            if (gash && (z == InjuryZone.BrowL || z == InjuryZone.BrowR)) cy = 0.19f;
            var offset = parent == rig.jaw ? BodyBuilder.JawPivot : parent == rig.chest ? new Vector3(0, 0.26f, 0) : Vector3.zero;
            float radius = isHead ? 0.095f : 0.2f;
            float halfA = size / radius;
            float halfY = gash ? size * 0.18f : size;
            float yLo = cy - halfY, yHi = cy + halfY;
            if (streak) { yLo = cy - 0.07f; yHi = cy - 0.002f; halfA = 0.006f / radius; }
            var md = new MeshData();
            var m = Matrix4x4.Translate(-offset);
            int seed = i * 31 + (gash ? 7 : 0);
            Anatomy.Grid(md, 0, prof, yLo, yHi, (ca - halfA) * Mathf.Rad2Deg, (ca + halfA) * Mathf.Rad2Deg, 6, 8, m, (y, t, p) => Anatomy.Bone(0), (y, th) =>
            {
                float u = (th - ca) / halfA, v = (y - (yLo + yHi) * 0.5f) / Mathf.Max(1e-4f, (yHi - yLo) * 0.5f);
                if (streak) { float wig = Mathf.Sin(v * 6f + seed) * 0.25f; u -= wig; }
                float d = u * u + v * v;
                float n = Mathf.PerlinNoise(u * 2f + seed, v * 2f) * 0.5f;
                return d + n * 0.3f < 1f ? lift : 0f;
            }, lift * 0.5f, 0.0003f);
            var go = new GameObject(name + "_" + z);
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = md.ToMesh(name);
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = Mats.Cached("inj_patch", () => Mats.Transparent(new Color(1, 1, 1, 0.5f), null, 0.6f));
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            go.layer = Layers.Actors;
            return new Visual { t = go.transform, r = mr, patch = true };
        }

        // ------------------------------------------------------------------ per frame: bleeding and healing
        void Update()
        {
            if (rig == null) return;
            float dt = Time.deltaTime;
            if (dt <= 0f) return;
            bool near = !rig.FarFromCamera;
            // bleeding
            float bleed = 0f;
            int worst = -1; float worstCut = 0f;
            for (int i = 0; i <= (int)InjuryZone.Chin; i++)
            {
                if (cut[i] > worstCut) { worstCut = cut[i]; worst = i; }
                bleed += cut[i];
            }
            float nose = swell[(int)InjuryZone.Nose];
            if (nose > 0.45f) bleed += (nose - 0.45f) * 1.2f;
            if (bleed > 0.05f && !rig.ragdolled)
            {
                bleedTotal = Mathf.Min(2f, bleedTotal + bleed * dt * 0.05f);
                dripTimer -= dt;
                if (dripTimer <= 0f && near && Game.Fx != null && rig.head != null)
                {
                    dripTimer = Mathf.Lerp(1.2f, 0.18f, Mathf.Clamp01(bleed));
                    Vector3 p;
                    if (worst >= 0 && worstCut > 0.1f && (nose < 0.45f || UnityEngine.Random.value < 0.5f))
                        p = rig.head.TransformPoint(head.Point(zoneY[worst] - 0.01f, zoneA[worst] * Mathf.Deg2Rad));
                    else
                        p = rig.head.TransformPoint(new Vector3(UnityEngine.Random.Range(-0.012f, 0.012f), 0.11f, 0.118f));
                    Game.Fx.BloodDrip(p, Vector3.down * 0.3f + UnityEngine.Random.insideUnitSphere * 0.15f);
                    if (worst >= 0 && worstCut > 0.2f && streakVis[worst] == null && rig.lod == 0) streakVis[worst] = MakePatch(worst, 0.01f, 0.0016f, false, "Streak", true);
                    for (int i = 0; i < Zones; i++) RefreshStreak(i);
                }
                stainTimer -= dt;
                if (stainTimer <= 0f && near)
                {
                    stainTimer = Mathf.Lerp(4f, 1.2f, Mathf.Clamp01(bleed));
                    if (Physics.Raycast(rig.head.position, Vector3.down, out var hit, 3f, Layers.WorldMask, QueryTriggerInteraction.Ignore))
                        Game.Fx?.BloodDecal(hit.point, hit.normal);
                }
            }
            // slow natural healing (much slower than a fight)
            if (canHeal)
            {
                float h = dt * 0.0035f;
                for (int i = 0; i < Zones; i++)
                {
                    if (swell[i] > 0f) { swell[i] = Mathf.Max(0f, swell[i] - h); }
                    if (cut[i] > 0f) cut[i] = Mathf.Max(0f, cut[i] - h * 1.5f);
                    if (bruise[i] > 0f) bruise[i] = Mathf.Max(0f, bruise[i] - h * 0.6f);
                }
                concussion = Mathf.Max(0f, concussion - h * 0.4f);
                bodyTrauma = Mathf.Max(0f, bodyTrauma - h);
                healRefresh -= dt;
                if (healRefresh <= 0f) { healRefresh = 2f; for (int i = 0; i < Zones; i++) Refresh(i); }
            }
        }
        float healRefresh;
    }
}
