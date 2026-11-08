using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// The ring: four ropes per side simulated with verlet integration. Fighters (and knocked-out bodies) push the
    /// ropes, the ropes stretch, wobble and push back. Also owns the ring bounds used by the fighters.
    /// </summary>
    public class RingRopes : MonoBehaviour
    {
        public Vector3 Center { get; private set; }
        public float Half { get; private set; }   // rope line distance from the centre
        public float CanvasY => Center.y;
        public static readonly float[] Heights = { 0.46f, 0.78f, 1.1f, 1.42f };
        const int Points = 18;

        class Rope
        {
            public Vector3 a, b;
            public Vector3[] p = new Vector3[Points], prev = new Vector3[Points], rest = new Vector3[Points];
            public int level;
            public Vector3 outward;
            public float energy;
        }
        readonly List<Rope> ropes = new List<Rope>();
        struct Pusher { public Vector3 c; public float r, y0, y1; public Vector3 vel; }
        readonly List<Pusher> pushers = new List<Pusher>();
        Mesh mesh;
        readonly List<Vector3> verts = new List<Vector3>();
        readonly List<Vector3> norms = new List<Vector3>();
        const int Sides = 7;
        float rope_sfx_cd;

        public static RingRopes Build(Transform parent, Vector3 canvasCenter, float half)
        {
            var go = new GameObject("RingRopes");
            go.transform.SetParent(parent, false);
            var r = go.AddComponent<RingRopes>();
            r.Center = canvasCenter; r.Half = half;
            var corners = new[] { new Vector3(-half, 0, -half), new Vector3(half, 0, -half), new Vector3(half, 0, half), new Vector3(-half, 0, half) };
            var outs = new[] { Vector3.back, Vector3.right, Vector3.forward, Vector3.left };
            for (int s = 0; s < 4; s++)
                for (int lv = 0; lv < Heights.Length; lv++)
                {
                    var rope = new Rope { level = lv, outward = outs[s] };
                    rope.a = canvasCenter + corners[s] + Vector3.up * Heights[lv];
                    rope.b = canvasCenter + corners[(s + 1) % 4] + Vector3.up * Heights[lv];
                    for (int i = 0; i < Points; i++)
                    {
                        float t = i / (float)(Points - 1);
                        var pt = Vector3.Lerp(rope.a, rope.b, t) + Vector3.down * Mathf.Sin(t * Mathf.PI) * 0.025f;
                        rope.p[i] = rope.prev[i] = rope.rest[i] = pt;
                    }
                    r.ropes.Add(rope);
                }
            r.BuildMesh();
            r.BuildPads(corners);
            return r;
        }

        void BuildMesh()
        {
            mesh = new Mesh { name = "Ropes" };
            mesh.MarkDynamic();
            var uv = new List<Vector2>();
            var subs = new List<int>[Heights.Length];
            for (int i = 0; i < subs.Length; i++) subs[i] = new List<int>();
            foreach (var rope in ropes)
            {
                int baseIdx = verts.Count;
                for (int i = 0; i < Points; i++)
                    for (int s = 0; s <= Sides; s++) { verts.Add(Vector3.zero); norms.Add(Vector3.up); uv.Add(new Vector2(s / (float)Sides, i / (float)(Points - 1) * 8f)); }
                var tris = subs[rope.level];
                for (int i = 0; i < Points - 1; i++)
                    for (int s = 0; s < Sides; s++)
                    {
                        int a = baseIdx + i * (Sides + 1) + s, b = baseIdx + (i + 1) * (Sides + 1) + s, c = b + 1, d = a + 1;
                        tris.Add(a); tris.Add(c); tris.Add(b);
                        tris.Add(a); tris.Add(d); tris.Add(c);
                    }
            }
            UpdateVerts();
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uv);
            mesh.subMeshCount = subs.Length;
            for (int i = 0; i < subs.Length; i++) mesh.SetTriangles(subs[i], i);
            mesh.bounds = new Bounds(Center + Vector3.up, new Vector3(Half * 2.6f, 3f, Half * 2.6f));
            var go = new GameObject("RopeMesh");
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterials = new[]
            {
                Mats.Cached("rope_cyan", () => Mats.Emissive(new Color(0.05f, 0.3f, 0.35f), Palette.Cyan * 2.2f, null, null, 0.7f)),
                Mats.Cached("rope_white", () => Mats.Lit(new Color(0.92f, 0.92f, 0.95f), Anatomy.ClothTex, 0.55f)),
                Mats.Cached("rope_white", () => Mats.Lit(new Color(0.92f, 0.92f, 0.95f), Anatomy.ClothTex, 0.55f)),
                Mats.Cached("rope_red", () => Mats.Emissive(new Color(0.35f, 0.03f, 0.05f), Palette.Red * 2.4f, null, null, 0.7f)),
            };
            mr.shadowCastingMode = ShadowCastingMode.On;
        }

        void BuildPads(Vector3[] corners)
        {
            var red = Mats.Cached("pad_red", () => Mats.Lit(new Color(0.75f, 0.05f, 0.08f), null, 0.7f));
            var blue = Mats.Cached("pad_blue", () => Mats.Lit(new Color(0.06f, 0.14f, 0.65f), null, 0.7f));
            var white = Mats.Cached("pad_white", () => Mats.Lit(new Color(0.9f, 0.9f, 0.92f), null, 0.6f));
            for (int c = 0; c < 4; c++)
            {
                var m = c == 0 ? red : c == 2 ? blue : white;
                var inward = (-corners[c]).normalized;
                for (int lv = 1; lv < Heights.Length; lv++)
                {
                    var md = new MeshData();
                    Anatomy.Ellipsoid(md, 0, Vector3.zero, new Vector3(0.11f, 0.13f, 0.08f), Matrix4x4.identity, Anatomy.Bone(0), 6, 12);
                    var go = new GameObject("Pad");
                    go.transform.SetParent(transform, false);
                    go.transform.position = Center + corners[c] + inward * 0.12f + Vector3.up * Heights[lv];
                    go.transform.rotation = Quaternion.LookRotation(inward);
                    go.AddComponent<MeshFilter>().sharedMesh = md.ToMesh("Pad");
                    go.AddComponent<MeshRenderer>().sharedMaterial = m;
                }
                // neon strip down each post
                var strip = Util.Primitive(PrimitiveType.Cube, "PostNeon", transform, Vector3.zero, new Vector3(0.04f, 1.45f, 0.04f), c == 0 ? Anatomy.Glow(Palette.Red) : c == 2 ? Anatomy.Glow(Palette.Blue) : Anatomy.Glow(Palette.Magenta));
                strip.transform.position = Center + corners[c] + inward * 0.17f + Vector3.up * 0.75f;
            }
        }

        // ------------------------------------------------------------------ fighters
        public Vector3 CornerPos(int corner, float inset = 0.7f)
        {
            // 0 red (-,-), 1 blue (+,+), 2 neutral (+,-), 3 neutral (-,+)
            var d = corner == 0 ? new Vector3(-1, 0, -1) : corner == 1 ? new Vector3(1, 0, 1) : corner == 2 ? new Vector3(1, 0, -1) : new Vector3(-1, 0, 1);
            return Center + d * (Half - inset);
        }

        /// <summary>Keeps a fighter inside the ropes; returns true when leaning on them. Ropes push back like springs.</summary>
        public bool Constrain(ref Vector3 pos, ref Vector3 vel, float radius)
        {
            var l = pos - Center;
            bool onRopes = false;
            float soft = Half - radius - 0.05f, hard = Half - 0.16f;
            for (int axis = 0; axis < 2; axis++)
            {
                float v = axis == 0 ? l.x : l.z;
                float av = Mathf.Abs(v), sgn = Mathf.Sign(v);
                if (av > soft)
                {
                    onRopes = true;
                    float pen = av - soft;
                    float vv = axis == 0 ? vel.x : vel.z;
                    float push = -sgn * pen * 22f;
                    vv += push * Time.deltaTime * 10f;
                    if (sgn * vv > 0f && av > hard - 0.05f) vv = -vv * 0.45f; // bounce off the ropes
                    if (av > hard) { v = sgn * hard; }
                    if (axis == 0) { vel.x = vv; l.x = v; } else { vel.z = vv; l.z = v; }
                    if (Mathf.Abs(vv) > 1.2f && rope_sfx_cd <= 0f) { rope_sfx_cd = 0.4f; Game.Audio?.Play3D("rope", pos + Vector3.up, 0.6f, Random.Range(0.85f, 1.1f), 2f, 30f); }
                }
            }
            pos = Center + new Vector3(l.x, pos.y - Center.y, l.z);
            return onRopes;
        }

        public void AddPusher(Vector3 center, float radius, float yLow, float yHigh, Vector3 vel)
        {
            pushers.Add(new Pusher { c = center, r = radius, y0 = yLow, y1 = yHigh, vel = vel });
        }

        void LateUpdate()
        {
            float dt = Mathf.Min(Time.deltaTime, 1f / 30f);
            rope_sfx_cd -= Time.deltaTime;
            var cam = Game.Cam;
            bool near = cam != null && (cam.transform.position - Center).sqrMagnitude < 70f * 70f;
            // gather pushers: boxers, ragdolls, referee, the player in free roam
            if (Boxing.Match != null) Boxing.Match.CollectPushers(this);
            if (Game.HasPlayer && (Boxing.Match == null || !Boxing.Match.Running))
                AddPusher(Game.PlayerPos, 0.38f, Game.PlayerPos.y + 0.1f, Game.PlayerPos.y + 1.7f, Game.Player.Velocity);
            if (!near) { pushers.Clear(); return; }
            if (dt > 0f) Simulate(dt);
            pushers.Clear();
            UpdateVerts();
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
        }

        void Simulate(float dt)
        {
            var g = Vector3.down * 9.81f * dt * dt * 0.15f;
            foreach (var rope in ropes)
            {
                for (int i = 1; i < Points - 1; i++)
                {
                    var v = (rope.p[i] - rope.prev[i]) * 0.965f;
                    rope.prev[i] = rope.p[i];
                    rope.p[i] += v + g + (rope.rest[i] - rope.p[i]) * 0.06f;
                }
                float segLen = (rope.b - rope.a).magnitude / (Points - 1);
                for (int it = 0; it < 4; it++)
                {
                    for (int i = 0; i < Points - 1; i++)
                    {
                        var d = rope.p[i + 1] - rope.p[i];
                        float len = d.magnitude;
                        if (len < 1e-5f) continue;
                        float diff = (len - segLen) / len;
                        var corr = d * diff * 0.5f;
                        if (i > 0) rope.p[i] += corr;
                        if (i + 1 < Points - 1) rope.p[i + 1] -= corr;
                    }
                    // bodies push the rope outward
                    foreach (var ps in pushers)
                    {
                        for (int i = 1; i < Points - 1; i++)
                        {
                            var p = rope.p[i];
                            if (p.y < ps.y0 || p.y > ps.y1) continue;
                            var dx = new Vector2(p.x - ps.c.x, p.z - ps.c.z);
                            float dist = dx.magnitude;
                            if (dist >= ps.r || dist < 1e-4f) continue;
                            // only push towards outside of the ring
                            var dir = dx / dist;
                            var outward = new Vector2(rope.outward.x, rope.outward.z);
                            if (Vector2.Dot(dir, outward) < 0f) dir = outward;
                            var np = new Vector2(ps.c.x, ps.c.z) + dir * ps.r;
                            float moved = (np - new Vector2(p.x, p.z)).magnitude;
                            rope.p[i] = new Vector3(np.x, p.y, np.y);
                            rope.energy = Mathf.Min(1f, rope.energy + moved * 3f);
                            // ropes stretched by a falling body also sag downwards a little
                            rope.p[i] += Vector3.down * moved * 0.25f;
                        }
                    }
                }
                rope.energy = Mathf.MoveTowards(rope.energy, 0f, dt * 2f);
            }
        }

        void UpdateVerts()
        {
            int k = 0;
            foreach (var rope in ropes)
            {
                float r = rope.level == Heights.Length - 1 ? 0.032f : 0.026f;
                var prevN = Vector3.up;
                for (int i = 0; i < Points; i++)
                {
                    var fwd = (i < Points - 1 ? rope.p[i + 1] - rope.p[i] : rope.p[i] - rope.p[i - 1]).normalized;
                    var n = Vector3.ProjectOnPlane(prevN, fwd).normalized;
                    if (n.sqrMagnitude < 0.01f) n = Vector3.up;
                    prevN = n;
                    var bAx = Vector3.Cross(fwd, n);
                    for (int s = 0; s <= Sides; s++)
                    {
                        float a = Mathf.PI * 2f * s / Sides;
                        var dir = n * Mathf.Cos(a) + bAx * Mathf.Sin(a);
                        if (k < verts.Count) { verts[k] = rope.p[i] + dir * r; norms[k] = dir; }
                        else { verts.Add(rope.p[i] + dir * r); norms.Add(dir); }
                        k++;
                    }
                }
            }
        }

        /// <summary>Sends a jolt through the ropes nearest a point (a body slamming into them).</summary>
        public void Jolt(Vector3 point, Vector3 impulse)
        {
            foreach (var rope in ropes)
                for (int i = 1; i < Points - 1; i++)
                {
                    float d = (rope.p[i] - point).magnitude;
                    if (d < 1.4f) rope.prev[i] -= impulse * (1f - d / 1.4f) * 0.02f;
                }
        }
    }
}
