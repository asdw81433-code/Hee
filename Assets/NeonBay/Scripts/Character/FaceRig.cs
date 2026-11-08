using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// Facial animation: eyeballs that track, blinking lids, brows, and a sprung jaw. Expressions come from
    /// pain / fatigue / daze / anger values and from impact reactions, so a punched face actually reacts.
    /// </summary>
    public class FaceRig : MonoBehaviour
    {
        HumanoidRig rig;
        Transform eyeL, eyeR, lidUL, lidUR, lidLL, lidLR, browL, browR;
        Vector3 browRestL, browRestR;
        Quaternion browRotL = Quaternion.identity, browRotR = Quaternion.identity;

        // inputs (set by the owner every frame or left to decay)
        public float fatigue, pain, daze, anger, talk;
        public bool ko, asleep;
        public Vector3? lookTarget;
        public float eyeClosureL, eyeClosureR; // from swelling

        // state
        float blinkT = -1f, nextBlink;
        float jaw, jawVel, jawImpulseHold;
        float squint, squintTarget, squintHold;
        float browUp, browFurrow, browInner;
        Vector2 saccade, saccadeTarget; float saccadeTimer;
        Vector2 eyeAim;
        float breathe;
        float surprise;

        public static FaceRig Build(HumanoidRig rig, Appearance a, int lod)
        {
            var f = rig.gameObject.AddComponent<FaceRig>();
            f.rig = rig;
            var head = rig.head;
            var white = Mats.Cached("anat_eyewhite", () => Mats.Lit(new Color(0.93f, 0.9f, 0.86f), null, 0.92f));
            var iris = Mats.Cached("anat_iris" + ColorUtility.ToHtmlStringRGB(a.eyes), () => Mats.Unlit(a.eyes * 1.35f));
            var pupil = Mats.Cached("anat_pupil", () => Mats.Lit(new Color(0.01f, 0.01f, 0.012f), null, 0.95f));
            var skin = Anatomy.Skin(a.skin, a.chromeSkin);
            var lash = Anatomy.Hair(a.beardColor * 0.5f);
            var browMat = Anatomy.Hair(a.beardColor);

            var c = BodyBuilder.EyeCenter;
            if (!a.visor || a.helmet)
            {
                f.eyeR = MakeEye(head, new Vector3(c.x, c.y, c.z), white, iris, pupil, lod);
                f.eyeL = MakeEye(head, new Vector3(-c.x, c.y, c.z), white, iris, pupil, lod);
            }
            f.lidUR = MakeLid(head, new Vector3(c.x, c.y, c.z), true, skin, lash, lod);
            f.lidUL = MakeLid(head, new Vector3(-c.x, c.y, c.z), true, skin, lash, lod);
            f.lidLR = MakeLid(head, new Vector3(c.x, c.y, c.z), false, skin, null, lod);
            f.lidLL = MakeLid(head, new Vector3(-c.x, c.y, c.z), false, skin, null, lod);
            if (a.brows < 4 && !a.helmet)
            {
                var hp = BodyBuilder.HeadProfile(a.jaw, a.female);
                f.browR = MakeBrow(head, hp, 1, a.brows, a.female, browMat, out f.browRestR);
                f.browL = MakeBrow(head, hp, -1, a.brows, a.female, browMat, out f.browRestL);
            }
            f.nextBlink = Random.Range(0.5f, 4f);
            return f;
        }

        static Transform MakeEye(Transform head, Vector3 center, Material white, Material iris, Material pupil, int lod)
        {
            var root = new GameObject("Eye").transform;
            root.SetParent(head, false);
            root.localPosition = center;
            var r = BodyBuilder.EyeRadius;
            AddEllipsoid(root, Vector3.zero, new Vector3(r, r, r), white, lod == 0 ? 10 : 6);
            AddEllipsoid(root, new Vector3(0, 0, r * 0.8f), new Vector3(r * 0.5f, r * 0.5f, r * 0.24f), iris, 8);
            AddEllipsoid(root, new Vector3(0, 0, r * 0.93f), new Vector3(r * 0.22f, r * 0.22f, r * 0.09f), pupil, 6);
            return root;
        }

        static void AddEllipsoid(Transform parent, Vector3 c, Vector3 r, Material m, int res)
        {
            var md = new MeshData();
            Anatomy.Ellipsoid(md, 0, c, r, Matrix4x4.identity, Anatomy.Bone(0), res / 2 + 2, res);
            var go = new GameObject("E");
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = Cached("ell" + c + r + res, md);
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = m;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            go.layer = Layers.Actors;
        }

        static readonly Dictionary<string, Mesh> cache = new Dictionary<string, Mesh>();
        static Mesh Cached(string key, MeshData md)
        {
            if (!cache.TryGetValue(key, out var m) || m == null) { m = md.ToMesh(key); cache[key] = m; }
            return m;
        }

        /// <summary>A spherical lid cap around the eye. Upper lids cover the top half, lower lids the bottom.</summary>
        static Transform MakeLid(Transform head, Vector3 center, bool upper, Material skin, Material lash, int lod)
        {
            var root = new GameObject(upper ? "LidU" : "LidL").transform;
            root.SetParent(head, false);
            root.localPosition = center;
            string key = "lid" + upper + lod;
            if (!cache.TryGetValue(key, out var mesh) || mesh == null)
            {
                var md = new MeshData();
                float r = BodyBuilder.EyeRadius * 1.13f;
                int rows = lod == 0 ? 6 : 3, cols = lod == 0 ? 14 : 8;
                int baseIdx = 0;
                for (int i = 0; i <= rows; i++)
                {
                    float phi = (upper ? 1f : -1f) * Mathf.PI * 0.5f * (1f - i / (float)rows);
                    float cy = Mathf.Sin(phi), cr = Mathf.Cos(phi);
                    for (int j = 0; j <= cols; j++)
                    {
                        float a = Mathf.PI * 2f * j / cols;
                        var u = new Vector3(Mathf.Cos(a) * cr, cy, Mathf.Sin(a) * cr);
                        // thicken the lid margin a little
                        float k = i == rows ? 1.04f : 1f;
                        md.Add(u * r * k, u, new Vector2(j / (float)cols, i / (float)rows), Anatomy.Bone(0));
                    }
                }
                var tris = md.Sub(0);
                for (int i = 0; i < rows; i++)
                    for (int j = 0; j < cols; j++)
                    {
                        int a0 = baseIdx + i * (cols + 1) + j, b0 = baseIdx + (i + 1) * (cols + 1) + j, c0 = b0 + 1, d0 = a0 + 1;
                        if (upper) { tris.Add(a0); tris.Add(c0); tris.Add(b0); tris.Add(a0); tris.Add(d0); tris.Add(c0); }
                        else { tris.Add(a0); tris.Add(b0); tris.Add(c0); tris.Add(a0); tris.Add(c0); tris.Add(d0); }
                    }
                mesh = md.ToMesh(key);
                cache[key] = mesh;
            }
            var go = new GameObject("Lid");
            go.transform.SetParent(root, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = skin;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            go.layer = Layers.Actors;
            if (upper && lash != null && lod == 0)
            {
                string lk = "lash";
                if (!cache.TryGetValue(lk, out var lm) || lm == null)
                {
                    var md = new MeshData();
                    var path = new List<Vector3>(); var rad = new List<float>();
                    float r = BodyBuilder.EyeRadius * 1.16f;
                    for (int i = 0; i <= 10; i++)
                    {
                        float a = Mathf.Lerp(15f, 165f, i / 10f) * Mathf.Deg2Rad;
                        path.Add(new Vector3(Mathf.Cos(a) * r, 0.0004f, Mathf.Sin(a) * r));
                        rad.Add(0.0011f * Mathf.Sin(a));
                    }
                    Anatomy.Tube(md, 0, path, rad, Matrix4x4.identity, Anatomy.Bone(0), 4);
                    lm = md.ToMesh(lk); cache[lk] = lm;
                }
                var l = new GameObject("Lash");
                l.transform.SetParent(root, false);
                l.AddComponent<MeshFilter>().sharedMesh = lm;
                var lr = l.AddComponent<MeshRenderer>();
                lr.sharedMaterial = lash;
                lr.shadowCastingMode = ShadowCastingMode.Off;
                l.layer = Layers.Actors;
            }
            return root;
        }

        static Transform MakeBrow(Transform head, Profile hp, int side, int style, bool fem, Material mat, out Vector3 rest)
        {
            float centerA = side > 0 ? 66f : 114f;
            float half = 17f;
            float y0 = 0.181f;
            var pivot = hp.PointOffset(y0, centerA * Mathf.Deg2Rad, 0f);
            rest = pivot;
            var root = new GameObject(side > 0 ? "BrowR" : "BrowL").transform;
            root.SetParent(head, false);
            root.localPosition = pivot;
            string key = "brow" + side + style + fem + hp.GetHashCode();
            if (!cache.TryGetValue(key, out var mesh) || mesh == null)
            {
                var md = new MeshData();
                float thick = style == 1 ? 0.0042f : style == 2 || fem ? 0.0022f : 0.003f;
                float width = style == 1 ? 0.0055f : style == 2 || fem ? 0.0028f : 0.0042f;
                float arch = style == 2 || fem ? 0.006f : 0.0025f;
                var m = Matrix4x4.Translate(-pivot);
                Anatomy.Grid(md, 0, hp, y0 - 0.012f, y0 + 0.014f, centerA - half, centerA + half, 8, 14, m, (y, t, p) => Anatomy.Bone(0), (y, th) =>
                {
                    float u = (th * Mathf.Rad2Deg - centerA) / half;              // -1..1 across the brow
                    float inner = side > 0 ? Mathf.Clamp01(u * 0.5f + 0.5f) : Mathf.Clamp01(-u * 0.5f + 0.5f); // 1 at the nose end
                    float cy = y0 + arch * (1f - u * u) - 0.002f * (1f - inner);
                    float w = width * Mathf.Lerp(0.6f, 1.25f, inner);
                    float k = (y - cy) / w;
                    float along = Mathf.Clamp01((1f - Mathf.Abs(u)) * 4f);
                    float t = thick * Mathf.Exp(-k * k) * along;
                    if (style == 3 && Mathf.Abs(u - 0.1f * side) < 0.12f) t = 0f; // scar gap
                    return t;
                }, 0.0005f, 0.0005f);
                mesh = md.ToMesh(key);
                cache[key] = mesh;
            }
            var go = new GameObject("BrowMesh");
            go.transform.SetParent(root, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            go.layer = Layers.Actors;
            return root;
        }

        // ================================================================== reactions
        /// <summary>Impact reaction. dirLocal is the punch direction in head space, power 0..1.5.</summary>
        public void Hit(Vector3 dirLocal, float power, bool body)
        {
            power = Mathf.Clamp(power, 0f, 1.6f);
            if (body)
            {
                jawVel += 4f * power;           // gasp
                squintTarget = Mathf.Max(squintTarget, 0.6f + 0.4f * power); squintHold = 0.5f + power * 0.6f;
                browInner = Mathf.Max(browInner, 0.8f * power);
                pain = Mathf.Max(pain, 0.6f * power);
                return;
            }
            // head shot: the jaw gets knocked open, eyes slam shut, brows jump
            jawVel += 9f * power + 2f;
            jawImpulseHold = 0.08f + 0.1f * power;
            blinkT = 0f;
            squintTarget = 1f; squintHold = 0.25f + 0.35f * power;
            browUp = Mathf.Max(browUp, 0.6f * power);
            surprise = Mathf.Max(surprise, power);
            pain = Mathf.Max(pain, 0.4f * power);
            // eyes get thrown opposite the punch
            saccade += new Vector2(-dirLocal.x, dirLocal.y) * 18f * power;
        }

        public void Blink() { if (blinkT < 0f) blinkT = 0f; }

        public void Tick(float dt)
        {
            if (rig == null || rig.ragdolled && !ko) return;
            float t = Time.time;
            // --- decay inputs
            pain = Mathf.MoveTowards(pain, 0f, dt * 0.35f);
            surprise = Mathf.MoveTowards(surprise, 0f, dt * 2.5f);
            squintHold -= dt;
            if (squintHold <= 0f) squintTarget = Mathf.MoveTowards(squintTarget, 0f, dt * 2f);
            squint = Mathf.MoveTowards(squint, Mathf.Max(squintTarget, pain * 0.5f, anger * 0.3f), dt * 14f);
            browUp = Mathf.MoveTowards(browUp, 0f, dt * 1.6f);
            browInner = Mathf.MoveTowards(browInner, pain * 0.8f, dt * 2f);
            browFurrow = Mathf.MoveTowards(browFurrow, Mathf.Max(anger, pain * 0.5f), dt * 3f);

            // --- blink
            if (!ko && !asleep)
            {
                nextBlink -= dt;
                if (nextBlink <= 0f && blinkT < 0f) { blinkT = 0f; nextBlink = Random.Range(1.8f, 5.5f) * (daze > 0.3f ? 0.5f : 1f); if (Random.value < 0.15f) nextBlink = 0.25f; }
            }
            float blink = 0f;
            if (blinkT >= 0f)
            {
                blinkT += dt / 0.16f;
                blink = Mathf.Sin(Mathf.Clamp01(blinkT) * Mathf.PI);
                if (blinkT >= 1f) blinkT = -1f;
            }

            // --- jaw spring
            float jawTarget = Mathf.Max(talk * (0.35f + 0.25f * Mathf.Sin(t * 13f)), fatigue * (0.25f + 0.25f * (Mathf.Sin(t * (2.5f + fatigue * 2f)) * 0.5f + 0.5f)));
            if (ko) jawTarget = 0.85f;
            else if (daze > 0.2f) jawTarget = Mathf.Max(jawTarget, 0.3f * daze);
            if (anger > 0.6f) jawTarget *= 0.3f;
            jawImpulseHold -= dt;
            float k = 140f, damp = 13f;
            jawVel += ((jawTarget - jaw) * k - jawVel * damp) * dt;
            jaw += jawVel * dt;
            jaw = Mathf.Clamp(jaw, -0.05f, 1.15f);
            if (rig.jaw != null) rig.jaw.localRotation = Quaternion.Euler(jaw * 21f, 0, 0);

            // --- eyes
            saccadeTimer -= dt;
            if (saccadeTimer <= 0f)
            {
                saccadeTimer = Random.Range(0.4f, 2.2f);
                saccadeTarget = Random.insideUnitCircle * (daze > 0.3f ? 14f : 4f);
            }
            saccade = Vector2.Lerp(saccade, saccadeTarget, 1f - Mathf.Exp(-(daze > 0.3f ? 3f : 25f) * dt));
            Vector2 aim = Vector2.zero;
            if (lookTarget.HasValue && rig.head != null)
            {
                var local = rig.head.InverseTransformPoint(lookTarget.Value) - BodyBuilder.EyeCenter;
                aim = new Vector2(Mathf.Clamp(Mathf.Atan2(local.x, local.z) * Mathf.Rad2Deg, -32f, 32f), Mathf.Clamp(Mathf.Atan2(local.y, new Vector2(local.x, local.z).magnitude) * Mathf.Rad2Deg, -25f, 25f));
            }
            eyeAim = Vector2.Lerp(eyeAim, aim, 1f - Mathf.Exp(-18f * dt));
            var e = eyeAim + saccade;
            float roll = ko ? -28f : daze * -6f;
            if (eyeR != null) eyeR.localRotation = Quaternion.Euler(-e.y + roll, e.x + (daze > 0.4f ? 4f : 0f), 0);
            if (eyeL != null) eyeL.localRotation = Quaternion.Euler(-e.y + roll, e.x - (daze > 0.4f ? 5f : 0f), 0);

            // --- lids: open -48 .. closed +74 (upper); lower lid 26 open .. -8 squeezed
            float baseClose = ko ? 0.62f : asleep ? 1f : Mathf.Clamp01(fatigue * 0.25f + daze * 0.35f + squint * 0.45f - surprise * 0.25f);
            float lookDown = Mathf.Clamp01(-e.y / 25f) * 0.25f;
            float closeR = Mathf.Max(Mathf.Max(baseClose + lookDown, blink), eyeClosureR);
            float closeL = Mathf.Max(Mathf.Max(baseClose + lookDown, blink), eyeClosureL);
            if (lidUR != null) lidUR.localRotation = Quaternion.Euler(Mathf.Lerp(-48f, 74f, Mathf.Clamp01(closeR)) - e.y * 0.4f, e.x * 0.15f, 0);
            if (lidUL != null) lidUL.localRotation = Quaternion.Euler(Mathf.Lerp(-48f, 74f, Mathf.Clamp01(closeL)) - e.y * 0.4f, e.x * 0.15f, 0);
            float lower = Mathf.Lerp(26f, -8f, Mathf.Clamp01(squint * 0.8f + eyeClosureR * 0.5f));
            if (lidLR != null) lidLR.localRotation = Quaternion.Euler(lower, 0, 0);
            lower = Mathf.Lerp(26f, -8f, Mathf.Clamp01(squint * 0.8f + eyeClosureL * 0.5f));
            if (lidLL != null) lidLL.localRotation = Quaternion.Euler(lower, 0, 0);

            // --- brows
            float up = browUp * 0.006f + surprise * 0.004f - browFurrow * 0.004f + daze * 0.002f;
            if (browR != null)
            {
                browR.localPosition = browRestR + new Vector3(-browFurrow * 0.0025f, up + browInner * 0.002f, 0);
                browR.localRotation = Quaternion.Euler(0, 0, browInner * 9f - browFurrow * 11f);
            }
            if (browL != null)
            {
                browL.localPosition = browRestL + new Vector3(browFurrow * 0.0025f, up + browInner * 0.002f, 0);
                browL.localRotation = Quaternion.Euler(0, 0, -browInner * 9f + browFurrow * 11f);
            }
        }
    }
}
