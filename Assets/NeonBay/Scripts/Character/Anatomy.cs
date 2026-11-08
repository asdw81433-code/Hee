using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>One elliptical cross-section of a lofted body part. Front (+Z) and back (-Z) depths can differ.</summary>
    public struct Ring
    {
        public float y, rx, rzf, rzb, cx, cz;
        public Ring(float y, float rx, float rzf, float rzb, float cx = 0f, float cz = 0f)
        { this.y = y; this.rx = rx; this.rzf = rzf; this.rzb = rzb; this.cx = cx; this.cz = cz; }
        public Ring(float y, float r) : this(y, r, r, r) { }
        public Ring Grow(float d) => new Ring(y, rx + d, rzf + d, rzb + d, cx, cz);
        public Ring Scale(float kx, float kz) => new Ring(y, rx * kx, rzf * kz, rzb * kz, cx * kx, cz * kz);
    }

    /// <summary>A gaussian muscle (or hollow, when amp &lt; 0) on the surface of a profile.</summary>
    public struct Bump
    {
        public float y, ang, amp, sy, sa;
        public Bump(float y, float angDeg, float amp, float sy, float saDeg)
        { this.y = y; ang = angDeg * Mathf.Deg2Rad; this.amp = amp; this.sy = sy; sa = Mathf.Max(0.01f, saDeg * Mathf.Deg2Rad); }
    }

    /// <summary>
    /// A smooth organic surface defined by cross-section rings along Y (interpolated with Catmull-Rom) plus
    /// gaussian muscle bumps. Angles: 0 = +X (character's right), 90 = +Z (front), 270 = back.
    /// </summary>
    public class Profile
    {
        public readonly Ring[] rings;
        public readonly List<Bump> bumps = new List<Bump>();
        public float power = 2f;
        public float YMin => rings[0].y;
        public float YMax => rings[rings.Length - 1].y;

        public Profile(params Ring[] r) { rings = r; Array.Sort(rings, (a, b) => a.y.CompareTo(b.y)); }
        public Profile Bump(float y, float angDeg, float amp, float sy, float saDeg) { bumps.Add(new Bump(y, angDeg, amp, sy, saDeg)); return this; }
        public Profile Power(float p) { power = p; return this; }

        static float CR(float a, float b, float c, float d, float t)
            => 0.5f * ((2f * b) + (-a + c) * t + (2f * a - 5f * b + 4f * c - d) * t * t + (-a + 3f * b - 3f * c + d) * t * t * t);

        public Ring Sample(float y)
        {
            int n = rings.Length;
            if (n == 1 || y <= rings[0].y) return rings[0];
            if (y >= rings[n - 1].y) return rings[n - 1];
            int i = 0;
            while (i < n - 2 && y > rings[i + 1].y) i++;
            float t = (y - rings[i].y) / Mathf.Max(1e-5f, rings[i + 1].y - rings[i].y);
            var p0 = rings[Mathf.Max(0, i - 1)]; var p1 = rings[i]; var p2 = rings[i + 1]; var p3 = rings[Mathf.Min(n - 1, i + 2)];
            return new Ring(y,
                Mathf.Max(0.0008f, CR(p0.rx, p1.rx, p2.rx, p3.rx, t)),
                Mathf.Max(0.0008f, CR(p0.rzf, p1.rzf, p2.rzf, p3.rzf, t)),
                Mathf.Max(0.0008f, CR(p0.rzb, p1.rzb, p2.rzb, p3.rzb, t)),
                CR(p0.cx, p1.cx, p2.cx, p3.cx, t), CR(p0.cz, p1.cz, p2.cz, p3.cz, t));
        }

        float SE(float v) => power == 2f ? v : Mathf.Sign(v) * Mathf.Pow(Mathf.Abs(v), 2f / power);

        public float Displace(float y, float theta)
        {
            float d = 0f;
            for (int i = 0; i < bumps.Count; i++)
            {
                var b = bumps[i];
                float dy = (y - b.y) / b.sy;
                float da = Mathf.DeltaAngle(theta * Mathf.Rad2Deg, b.ang * Mathf.Rad2Deg) * Mathf.Deg2Rad / b.sa;
                float e = dy * dy + da * da;
                if (e < 9f) d += b.amp * Mathf.Exp(-e);
            }
            return d;
        }

        /// <summary>Surface point (no offset).</summary>
        public Vector3 Point(float y, float theta)
        {
            var r = Sample(y);
            float c = Mathf.Cos(theta), s = Mathf.Sin(theta);
            float x = r.rx * SE(c), z = SE(s) * (s >= 0f ? r.rzf : r.rzb);
            float len = Mathf.Sqrt(x * x + z * z);
            float dx = len > 1e-6f ? x / len : c, dz = len > 1e-6f ? z / len : s;
            float d = Displace(y, theta);
            return new Vector3(r.cx + x + dx * d, y, r.cz + z + dz * d);
        }

        /// <summary>Outward surface normal by finite differences.</summary>
        public Vector3 Normal(float y, float theta)
        {
            const float e = 0.004f, ea = 0.02f;
            float y0 = Mathf.Max(YMin, y - e), y1 = Mathf.Min(YMax, y + e);
            if (y1 - y0 < 1e-5f) { y0 = y - e; y1 = y + e; }
            var dy = Point(y1, theta) - Point(y0, theta);
            var da = Point(y, theta + ea) - Point(y, theta - ea);
            var n = Vector3.Cross(dy, da);
            if (n.sqrMagnitude < 1e-12f)
            {
                // at a pole the surface faces along the axis
                return y > (YMin + YMax) * 0.5f ? Vector3.up : Vector3.down;
            }
            n.Normalize();
            // near the top/bottom ring the cross product degenerates towards the axis; blend to keep it sane
            return n;
        }

        public Vector3 PointOffset(float y, float theta, float offset)
        {
            if (Mathf.Abs(offset) < 1e-7f) return Point(y, theta);
            return Point(y, theta) + Normal(y, theta) * offset;
        }
    }

    public delegate BoneWeight WeightFn(float y, float theta, Vector3 bonePos);

    /// <summary>Growable mesh with sub-meshes and optional bone weights.</summary>
    public class MeshData
    {
        public readonly List<Vector3> v = new List<Vector3>(2048);
        public readonly List<Vector3> n = new List<Vector3>(2048);
        public readonly List<Vector2> uv = new List<Vector2>(2048);
        public readonly List<Color> col = new List<Color>(2048);
        public readonly List<BoneWeight> w = new List<BoneWeight>(2048);
        public readonly List<List<int>> subs = new List<List<int>>();
        public bool skinned;

        public List<int> Sub(int i) { while (subs.Count <= i) subs.Add(new List<int>()); return subs[i]; }

        public int Add(Vector3 p, Vector3 nn, Vector2 u, BoneWeight bw, Color? c = null)
        {
            v.Add(p); n.Add(nn); uv.Add(u); w.Add(bw); col.Add(c ?? Color.white);
            return v.Count - 1;
        }

        public Mesh ToMesh(string name)
        {
            var m = new Mesh { name = name };
            if (v.Count > 65000) m.indexFormat = IndexFormat.UInt32;
            m.SetVertices(v);
            m.SetNormals(n);
            m.SetUVs(0, uv);
            m.SetColors(col);
            m.subMeshCount = Mathf.Max(1, subs.Count);
            for (int i = 0; i < subs.Count; i++) m.SetTriangles(subs[i], i, false);
            if (skinned) m.boneWeights = w.ToArray();
            m.RecalculateBounds();
            try { m.RecalculateTangents(); } catch (Exception) { }
            return m;
        }
    }

    /// <summary>Procedural geometry helpers for characters: lofts, thickness-field shells and ellipsoids.</summary>
    public static class Anatomy
    {
        public static BoneWeight Bone(int i) => new BoneWeight { boneIndex0 = i, weight0 = 1f };
        public static BoneWeight Blend(int a, int b, float tb)
        {
            tb = Mathf.Clamp01(tb);
            if (tb <= 0.001f) return Bone(a);
            if (tb >= 0.999f) return Bone(b);
            return new BoneWeight { boneIndex0 = a, weight0 = 1f - tb, boneIndex1 = b, weight1 = tb };
        }
        public static BoneWeight Blend3(int a, int b, int c, float wa, float wb, float wc)
        {
            float s = wa + wb + wc; if (s <= 0f) return Bone(a);
            return new BoneWeight { boneIndex0 = a, weight0 = wa / s, boneIndex1 = b, weight1 = wb / s, boneIndex2 = c, weight2 = wc / s };
        }

        public static float Smooth(float e0, float e1, float x)
        {
            float t = Mathf.Clamp01((x - e0) / (e1 - e0));
            return t * t * (3f - 2f * t);
        }

        /// <summary>
        /// Emits a (y, theta) grid over the profile into md. 'thickness' (optional) offsets the surface along its normal;
        /// cells whose four corners all have thickness below 'skip' are not emitted (used for hair, beards, patches).
        /// </summary>
        public static void Grid(MeshData md, int sub, Profile p, float y0, float y1, float a0Deg, float a1Deg, int rows, int cols,
            Matrix4x4 m, WeightFn weight, Func<float, float, float> thickness = null, float skip = -1f, float offset = 0f,
            float uScale = 1f, float vScale = 1f, Func<float, float, Color> color = null)
        {
            bool closed = Mathf.Abs(a1Deg - a0Deg) >= 359.9f;
            int baseIdx = md.v.Count;
            var pts = new Vector3[(rows + 1) * (cols + 1)];
            var th = new float[pts.Length];
            float a0 = a0Deg * Mathf.Deg2Rad, a1 = a1Deg * Mathf.Deg2Rad;
            for (int i = 0; i <= rows; i++)
            {
                float y = Mathf.Lerp(y0, y1, i / (float)rows);
                for (int j = 0; j <= cols; j++)
                {
                    float a = Mathf.Lerp(a0, a1, j / (float)cols);
                    float t = offset + (thickness != null ? thickness(y, a) : 0f);
                    th[i * (cols + 1) + j] = t - offset;
                    pts[i * (cols + 1) + j] = p.PointOffset(y, a, t);
                }
            }
            // normals from the displaced grid
            var nrm = new Vector3[pts.Length];
            for (int i = 0; i <= rows; i++)
                for (int j = 0; j <= cols; j++)
                {
                    int jl = j - 1, jr = j + 1;
                    if (closed) { if (jl < 0) jl = cols - 1; if (jr > cols) jr = 1; }
                    else { jl = Mathf.Max(0, jl); jr = Mathf.Min(cols, jr); }
                    int id = Mathf.Max(0, i - 1), iu = Mathf.Min(rows, i + 1);
                    var dy = pts[iu * (cols + 1) + j] - pts[id * (cols + 1) + j];
                    var da = pts[i * (cols + 1) + jr] - pts[i * (cols + 1) + jl];
                    var nn = Vector3.Cross(dy, da);
                    if (nn.sqrMagnitude < 1e-14f)
                    {
                        float y = Mathf.Lerp(y0, y1, i / (float)rows);
                        nn = p.Normal(y, Mathf.Lerp(a0, a1, j / (float)cols));
                    }
                    nrm[i * (cols + 1) + j] = nn.normalized;
                }
            for (int i = 0; i <= rows; i++)
            {
                float y = Mathf.Lerp(y0, y1, i / (float)rows);
                for (int j = 0; j <= cols; j++)
                {
                    float a = Mathf.Lerp(a0, a1, j / (float)cols);
                    int k = i * (cols + 1) + j;
                    var lp = pts[k];
                    var bw = weight != null ? weight(y, a, lp) : Bone(0);
                    md.Add(m.MultiplyPoint3x4(lp), m.MultiplyVector(nrm[k]).normalized,
                        new Vector2(j / (float)cols * uScale, (y - y0) * vScale), bw, color?.Invoke(y, a));
                }
            }
            var tris = md.Sub(sub);
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                {
                    int a = i * (cols + 1) + j, b = (i + 1) * (cols + 1) + j, c = (i + 1) * (cols + 1) + j + 1, d = i * (cols + 1) + j + 1;
                    if (skip >= 0f && th[a] < skip && th[b] < skip && th[c] < skip && th[d] < skip) continue;
                    tris.Add(baseIdx + a); tris.Add(baseIdx + b); tris.Add(baseIdx + c);
                    tris.Add(baseIdx + a); tris.Add(baseIdx + c); tris.Add(baseIdx + d);
                }
        }

        /// <summary>Full lofted tube around the profile (360 degrees).</summary>
        public static void Loft(MeshData md, int sub, Profile p, Matrix4x4 m, WeightFn weight, int rows, int cols = 16, float offset = 0f, float y0 = float.NaN, float y1 = float.NaN)
        {
            Grid(md, sub, p, float.IsNaN(y0) ? p.YMin : y0, float.IsNaN(y1) ? p.YMax : y1, 0f, 360f, rows, cols, m, weight, null, -1f, offset, 1f, 2f);
        }

        /// <summary>Ellipsoid centred at 'c' with radii 'r' (local to matrix m).</summary>
        public static void Ellipsoid(MeshData md, int sub, Vector3 c, Vector3 r, Matrix4x4 m, BoneWeight bw, int rows = 8, int cols = 12, Color? color = null)
        {
            int baseIdx = md.v.Count;
            for (int i = 0; i <= rows; i++)
            {
                float phi = Mathf.PI * i / rows - Mathf.PI * 0.5f;
                float cy = Mathf.Sin(phi), cr = Mathf.Cos(phi);
                for (int j = 0; j <= cols; j++)
                {
                    float a = Mathf.PI * 2f * j / cols;
                    var unit = new Vector3(Mathf.Cos(a) * cr, cy, Mathf.Sin(a) * cr);
                    var pnt = c + Vector3.Scale(unit, r);
                    var nn = new Vector3(unit.x / Mathf.Max(1e-4f, r.x), unit.y / Mathf.Max(1e-4f, r.y), unit.z / Mathf.Max(1e-4f, r.z)).normalized;
                    md.Add(m.MultiplyPoint3x4(pnt), m.MultiplyVector(nn).normalized, new Vector2(j / (float)cols, i / (float)rows), bw, color);
                }
            }
            var tris = md.Sub(sub);
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                {
                    int a = i * (cols + 1) + j, b = (i + 1) * (cols + 1) + j, cc = (i + 1) * (cols + 1) + j + 1, d = i * (cols + 1) + j + 1;
                    tris.Add(baseIdx + a); tris.Add(baseIdx + b); tris.Add(baseIdx + cc);
                    tris.Add(baseIdx + a); tris.Add(baseIdx + cc); tris.Add(baseIdx + d);
                }
        }

        /// <summary>A tapered tube following a list of points (hair strands, braids, laces).</summary>
        public static void Tube(MeshData md, int sub, IList<Vector3> path, IList<float> radius, Matrix4x4 m, BoneWeight bw, int sides = 6, float lumpy = 0f, int seed = 0)
        {
            int baseIdx = md.v.Count;
            int count = path.Count;
            Vector3 prevN = Vector3.zero;
            for (int i = 0; i < count; i++)
            {
                var fwd = (i < count - 1 ? path[i + 1] - path[i] : path[i] - path[i - 1]).normalized;
                if (i > 0 && i < count - 1) fwd = (path[i + 1] - path[i - 1]).normalized;
                var nAxis = i == 0 ? Vector3.Cross(fwd, Mathf.Abs(fwd.y) < 0.9f ? Vector3.up : Vector3.right).normalized : Vector3.ProjectOnPlane(prevN, fwd).normalized;
                if (nAxis.sqrMagnitude < 1e-6f) nAxis = Vector3.Cross(fwd, Vector3.right).normalized;
                prevN = nAxis;
                var bAxis = Vector3.Cross(fwd, nAxis);
                float r = radius[Mathf.Min(i, radius.Count - 1)];
                for (int s = 0; s <= sides; s++)
                {
                    float a = Mathf.PI * 2f * s / sides;
                    float lump = lumpy > 0f ? 1f + lumpy * (Mathf.Sin(i * 2.3f + seed) * 0.5f + Mathf.Sin(a * 3f + i) * 0.5f) : 1f;
                    var dir = nAxis * Mathf.Cos(a) + bAxis * Mathf.Sin(a);
                    md.Add(m.MultiplyPoint3x4(path[i] + dir * r * lump), m.MultiplyVector(dir).normalized, new Vector2(s / (float)sides, i / (float)Mathf.Max(1, count - 1)), bw);
                }
            }
            var tris = md.Sub(sub);
            for (int i = 0; i < count - 1; i++)
                for (int s = 0; s < sides; s++)
                {
                    int a = i * (sides + 1) + s, b = (i + 1) * (sides + 1) + s, c = (i + 1) * (sides + 1) + s + 1, d = i * (sides + 1) + s + 1;
                    // tube path runs along +fwd; wind so faces point outward
                    tris.Add(baseIdx + a); tris.Add(baseIdx + c); tris.Add(baseIdx + b);
                    tris.Add(baseIdx + a); tris.Add(baseIdx + d); tris.Add(baseIdx + c);
                }
            // tip cap
            int tip = md.Add(m.MultiplyPoint3x4(path[count - 1] + (path[count - 1] - path[Mathf.Max(0, count - 2)]).normalized * radius[radius.Count - 1] * 0.6f),
                m.MultiplyVector((path[count - 1] - path[Mathf.Max(0, count - 2)]).normalized), new Vector2(0.5f, 1f), bw);
            int last = (count - 1) * (sides + 1);
            for (int s = 0; s < sides; s++) { tris.Add(baseIdx + last + s); tris.Add(baseIdx + last + s + 1); tris.Add(tip); }
        }

        // -------------------------------------------------------------------- textures
        static Texture2D skinTex, skinNormal, hairTex, hairNormal, clothTex, clothNormal, leatherNormal;

        public static Texture2D SkinTex { get { if (skinTex == null) BuildSkin(); return skinTex; } }
        public static Texture2D SkinNormal { get { if (skinNormal == null) BuildSkin(); return skinNormal; } }
        public static Texture2D HairTex { get { if (hairTex == null) BuildHair(); return hairTex; } }
        public static Texture2D HairNormal { get { if (hairNormal == null) BuildHair(); return hairNormal; } }
        public static Texture2D ClothTex { get { if (clothTex == null) BuildCloth(); return clothTex; } }
        public static Texture2D ClothNormal { get { if (clothNormal == null) BuildCloth(); return clothNormal; } }
        public static Texture2D LeatherNormal { get { if (leatherNormal == null) BuildCloth(); return leatherNormal; } }

        static void BuildSkin()
        {
            int s = 128;
            var px = new Color32[s * s];
            var h = new float[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float blotch = Tex.TileNoise(x / 32f, y / 32f, 4, 501, 3);
                    float pore = Tex.TileNoise(x / 3f, y / 3f, 43, 502, 2);
                    float v = 0.9f + blotch * 0.12f - (pore > 0.72f ? 0.06f : 0f);
                    px[y * s + x] = new Color32((byte)(Mathf.Clamp01(v * 1.02f) * 255), (byte)(Mathf.Clamp01(v * 0.97f) * 255), (byte)(Mathf.Clamp01(v * 0.95f) * 255), 255);
                    h[y * s + x] = pore * 0.6f + blotch * 0.4f;
                }
            skinTex = Tex.New(s, s); skinTex.name = "Skin"; skinTex.SetPixels32(px); skinTex.Apply(true, true);
            skinNormal = Tex.NormalFromHeight(h, s, s, 1.4f, "SkinNormal");
        }

        static void BuildHair()
        {
            int w = 64, hh = 128;
            var px = new Color32[w * hh];
            var h = new float[w * hh];
            for (int y = 0; y < hh; y++)
                for (int x = 0; x < w; x++)
                {
                    float strand = Tex.TileNoise(x / 1.6f, y / 24f, 40, 601, 3);
                    float clump = Tex.TileNoise(x / 6f, y / 40f, 10, 602, 2);
                    float v = Mathf.Clamp01(0.55f + strand * 0.6f + clump * 0.2f - 0.25f);
                    byte b = (byte)(v * 255);
                    px[y * w + x] = new Color32(b, b, b, 255);
                    h[y * w + x] = strand;
                }
            hairTex = Tex.New(w, hh); hairTex.name = "Hair"; hairTex.SetPixels32(px); hairTex.Apply(true, true);
            hairNormal = Tex.NormalFromHeight(h, w, hh, 3f, "HairNormal");
        }

        static void BuildCloth()
        {
            int s = 64;
            var px = new Color32[s * s];
            var h = new float[s * s];
            var hl = new float[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float weave = (Mathf.Sin(x * Mathf.PI * 0.5f) * Mathf.Sin(y * Mathf.PI * 0.5f)) * 0.5f + 0.5f;
                    float n = Tex.TileNoise(x / 8f, y / 8f, 8, 701, 3);
                    float v = 0.82f + weave * 0.1f + n * 0.1f;
                    byte b = (byte)(Mathf.Clamp01(v) * 255);
                    px[y * s + x] = new Color32(b, b, b, 255);
                    h[y * s + x] = weave * 0.7f + n * 0.3f;
                    hl[y * s + x] = Tex.TileNoise(x / 4f, y / 4f, 16, 702, 3);
                }
            clothTex = Tex.New(s, s); clothTex.name = "Cloth"; clothTex.SetPixels32(px); clothTex.Apply(true, true);
            clothNormal = Tex.NormalFromHeight(h, s, s, 1.2f, "ClothNormal");
            leatherNormal = Tex.NormalFromHeight(hl, s, s, 0.8f, "LeatherNormal");
        }

        // -------------------------------------------------------------------- materials
        public static Material Skin(Color c, bool chrome)
        {
            string key = "anat_skin" + ColorUtility.ToHtmlStringRGB(c) + chrome;
            return Mats.Cached(key, () => chrome
                ? Mats.Lit(c, null, 0.88f, 0.9f, Tex.Metal.normal, 0.3f)
                : Mats.Lit(c, SkinTex, 0.42f, 0f, SkinNormal, 0.35f));
        }

        public static Material Hair(Color c) => Mats.Cached("anat_hair" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Lit(c, HairTex, 0.38f, 0f, HairNormal, 0.9f));
        public static Material Stubble(Color c) => Mats.Cached("anat_stub" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Transparent(new Color(c.r, c.g, c.b, 0.55f), HairTex, 0.15f));
        public static Material Cloth(Color c) => Mats.Cached("anat_cloth" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Lit(c, ClothTex, 0.22f, 0f, ClothNormal, 0.6f));
        public static Material Satin(Color c) => Mats.Cached("anat_satin" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Lit(c, null, 0.78f, 0.05f, ClothNormal, 0.2f));
        public static Material Leather(Color c) => Mats.Cached("anat_leather" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Lit(c, null, 0.62f, 0.02f, LeatherNormal, 0.5f));
        public static Material Glow(Color c) => Mats.Cached("anat_glow" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Unlit(c * 3f));
    }
}
