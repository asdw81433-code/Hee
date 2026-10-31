using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum FacadeStyle { Glass, Office, Residential, Slum, Industrial, Ruin, Shopfront }

    public class FacadeTex
    {
        public Texture2D albedo, emission;
        public Vector2 tileMeters; // world size covered by one texture repeat
    }

    /// <summary>All textures in the game are generated procedurally at load time.</summary>
    public static class Tex
    {
        // ---------------------------------------------------------------- noise
        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 2147483647);
                h = (h ^ (h >> 13)) * 1274126177u;
                h ^= h >> 16;
                return (h & 0xFFFFFF) / 16777215f;
            }
        }

        public static float ValueNoise(float x, float y, int seed)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
            float a = Hash(xi, yi, seed), b = Hash(xi + 1, yi, seed), c = Hash(xi, yi + 1, seed), d = Hash(xi + 1, yi + 1, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
        }

        /// <summary>Tileable fBm: wraps at 'period' cells so textures repeat seamlessly.</summary>
        public static float TileNoise(float x, float y, int period, int seed, int octaves = 4)
        {
            float sum = 0, amp = 0.5f, norm = 0;
            int p = period;
            for (int o = 0; o < octaves; o++)
            {
                int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
                float xf = x - xi, yf = y - yi;
                float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
                int x0 = ((xi % p) + p) % p, y0 = ((yi % p) + p) % p, x1 = (x0 + 1) % p, y1 = (y0 + 1) % p;
                float a = Hash(x0, y0, seed + o), b = Hash(x1, y0, seed + o), c = Hash(x0, y1, seed + o), d = Hash(x1, y1, seed + o);
                sum += amp * Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
                norm += amp;
                amp *= 0.5f; x *= 2; y *= 2; p *= 2;
            }
            return sum / norm;
        }

        // ---------------------------------------------------------------- helpers
        public static Texture2D New(int w, int h, bool linear = false, bool mips = true, TextureWrapMode wrap = TextureWrapMode.Repeat)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, mips, linear)
            {
                wrapMode = wrap,
                filterMode = FilterMode.Trilinear,
                anisoLevel = 8
            };
            return t;
        }

        static Texture2D Finish(Texture2D t, Color32[] px, string name)
        {
            t.name = name;
            t.SetPixels32(px);
            t.Apply(true, true);
            return t;
        }

        static Color32 C(Color c) => (Color32)c;
        static Color32 C(float r, float g, float b, float a = 1f) => new Color32((byte)(Mathf.Clamp01(r) * 255), (byte)(Mathf.Clamp01(g) * 255), (byte)(Mathf.Clamp01(b) * 255), (byte)(Mathf.Clamp01(a) * 255));

        static void FillRect(Color32[] px, int w, int x0, int y0, int rw, int rh, Color32 c)
        {
            int h = px.Length / w;
            for (int y = Mathf.Max(0, y0); y < Mathf.Min(h, y0 + rh); y++)
                for (int x = Mathf.Max(0, x0); x < Mathf.Min(w, x0 + rw); x++)
                    px[y * w + x] = c;
        }

        static readonly Dictionary<string, Texture2D> cache = new Dictionary<string, Texture2D>();
        static Texture2D Get(string key, System.Func<Texture2D> make)
        {
            if (!cache.TryGetValue(key, out var t) || t == null) { t = make(); cache[key] = t; }
            return t;
        }

        // ---------------------------------------------------------------- simple sprites
        public static Texture2D Glow => Get("glow", () =>
        {
            int s = 64; var px = new Color32[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float a = Mathf.Clamp01(1 - d); a = a * a * (0.6f + 0.4f * a);
                px[y * s + x] = C(1, 1, 1, a);
            }
            return Finish(New(s, s, false, true, TextureWrapMode.Clamp), px, "Glow");
        });

        public static Texture2D Streak => Get("streak", () =>
        {
            int w = 8, h = 64; var px = new Color32[w * h];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            {
                float fx = 1 - Mathf.Abs((x + 0.5f) / w * 2 - 1);
                float fy = Mathf.Sin((y + 0.5f) / h * Mathf.PI);
                px[y * w + x] = C(1, 1, 1, fx * fy);
            }
            return Finish(New(w, h, false, true, TextureWrapMode.Clamp), px, "Streak");
        });

        public static Texture2D Smoke => Get("smoke", () =>
        {
            int s = 64; var px = new Color32[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float n = ValueNoise(x * 0.15f, y * 0.15f, 7) * 0.6f + ValueNoise(x * 0.3f, y * 0.3f, 9) * 0.4f;
                float a = Mathf.Clamp01(1 - d) * Mathf.Clamp01(n * 1.4f - 0.1f);
                px[y * s + x] = C(1, 1, 1, a);
            }
            return Finish(New(s, s, false, true, TextureWrapMode.Clamp), px, "Smoke");
        });

        public static Texture2D Ring => Get("ring", () =>
        {
            int s = 64; var px = new Color32[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float a = Mathf.Clamp01(1 - Mathf.Abs(d - 0.75f) * 8f);
                px[y * s + x] = C(1, 1, 1, a);
            }
            return Finish(New(s, s, false, true, TextureWrapMode.Clamp), px, "Ring");
        });

        public static Texture2D BulletHole => Get("hole", () =>
        {
            int s = 32; var px = new Color32[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float n = ValueNoise(x * 0.5f, y * 0.5f, 3);
                float core = d < 0.18f ? 1f : 0f;
                float scorch = Mathf.Clamp01(1 - d * 1.3f) * (0.5f + 0.5f * n);
                float a = Mathf.Max(core, scorch * 0.8f);
                float v = core > 0 ? 0.02f : 0.08f;
                px[y * s + x] = C(v, v, v, a);
            }
            return Finish(New(s, s, false, true, TextureWrapMode.Clamp), px, "BulletHole");
        });

        public static Texture2D Splat => Get("splat", () =>
        {
            int s = 64; var px = new Color32[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float n = ValueNoise(x * 0.18f, y * 0.18f, 11);
                float a = Mathf.Clamp01((1 - d) * 2.2f - (1 - n) * 1.2f);
                px[y * s + x] = C(1, 1, 1, a);
            }
            return Finish(New(s, s, false, true, TextureWrapMode.Clamp), px, "Splat");
        });

        public static Texture2D Scanlines => Get("scan", () =>
        {
            int w = 4, h = 64; var px = new Color32[w * h];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            {
                float a = (y % 4 < 2) ? 0.9f : 0.35f;
                a *= 0.7f + 0.3f * Mathf.Sin(y / (float)h * Mathf.PI * 2);
                px[y * w + x] = C(1, 1, 1, a);
            }
            return Finish(New(w, h), px, "Scanlines");
        });

        public static Texture2D Solid(Color c) => Get("solid" + ColorUtility.ToHtmlStringRGBA(c), () =>
        {
            var px = new Color32[16];
            for (int i = 0; i < 16; i++) px[i] = C(c);
            return Finish(New(4, 4, false, false), px, "Solid");
        });

        // ---------------------------------------------------------------- surfaces
        /// <summary>Converts a height field to a tangent-space normal map in the DXT5nm-compatible layout.</summary>
        public static Texture2D NormalFromHeight(float[] h, int w, int hh, float strength, string name)
        {
            var px = new Color32[w * hh];
            for (int y = 0; y < hh; y++) for (int x = 0; x < w; x++)
            {
                float l = h[y * w + (x - 1 + w) % w], r = h[y * w + (x + 1) % w];
                float d = h[((y - 1 + hh) % hh) * w + x], u = h[((y + 1) % hh) * w + x];
                var n = new Vector3((l - r) * strength, (d - u) * strength, 1f).normalized;
                byte nx = (byte)((n.x * 0.5f + 0.5f) * 255), ny = (byte)((n.y * 0.5f + 0.5f) * 255);
                px[y * w + x] = new Color32(255, ny, ny, nx);
            }
            return Finish(New(w, hh, true), px, name);
        }

        public class Surface { public Texture2D albedo, normal, gloss; public Vector2 tileMeters; }

        static readonly Dictionary<string, Surface> surfaces = new Dictionary<string, Surface>();

        public static Surface Road => GetSurface("road", () => MakeRoad(false));
        public static Surface Intersection => GetSurface("isect", () => MakeRoad(true));
        public static Surface Sidewalk => GetSurface("sidewalk", MakeSidewalk);
        public static Surface Concrete => GetSurface("concrete", () => MakeConcrete(0.42f, 5, "Concrete"));
        public static Surface Dirt => GetSurface("dirt", MakeDirt);
        public static Surface Metal => GetSurface("metal", MakeMetal);
        public static Surface Ribbed => GetSurface("ribbed", MakeRibbed);

        static Surface GetSurface(string key, System.Func<Surface> make)
        {
            if (!surfaces.TryGetValue(key, out var s)) { s = make(); surfaces[key] = s; }
            return s;
        }

        static Surface MakeRoad(bool intersection)
        {
            int w = 128, h = intersection ? 128 : 112;
            var px = new Color32[w * h]; var gl = new Color32[w * h]; var hf = new float[w * h];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            {
                float n = TileNoise(x / 8f, y / 8f, 16, 21);
                float grit = Hash(x, y, 5);
                float v = 0.11f + n * 0.06f + grit * 0.035f;
                float puddle = TileNoise(x / 32f, y / 32f, 4, 77, 3);
                float wet = Mathf.SmoothStep(0, 1, (puddle - 0.52f) * 6f);
                float u = (x + 0.5f) / w;
                bool paint = false; Color paintCol = Color.white;
                if (!intersection)
                {
                    float meters = (y + 0.5f) / h * 12f;
                    if (u < 0.035f && u > 0.015f || u > 0.965f && u < 0.985f) paint = true;
                    if (Mathf.Abs(u - 0.488f) < 0.01f || Mathf.Abs(u - 0.512f) < 0.01f) { paint = true; paintCol = new Color(0.95f, 0.75f, 0.2f); }
                    if ((Mathf.Abs(u - 0.25f) < 0.008f || Mathf.Abs(u - 0.75f) < 0.008f) && (meters % 6f) < 3f) paint = true;
                }
                else
                {
                    float vv = (y + 0.5f) / h;
                    float edge = Mathf.Min(Mathf.Min(u, 1 - u), Mathf.Min(vv, 1 - vv));
                    bool nearEdgeU = (u < 0.16f || u > 0.84f) && vv > 0.16f && vv < 0.84f;
                    bool nearEdgeV = (vv < 0.16f || vv > 0.84f) && u > 0.16f && u < 0.84f;
                    if (nearEdgeU && ((int)(vv * 14) % 2 == 0)) paint = true;
                    if (nearEdgeV && ((int)(u * 14) % 2 == 0)) paint = true;
                    if (edge < 0.01f) paint = false;
                }
                if (paint)
                {
                    float wear = TileNoise(x / 4f, y / 4f, 32, 99, 2);
                    float k = wear > 0.35f ? 0.85f : 0.4f;
                    v = 0; px[y * w + x] = C(Color.Lerp(new Color(0.12f, 0.12f, 0.12f), paintCol * 0.8f, k));
                }
                else px[y * w + x] = C(v, v, v * 1.05f);
                hf[y * w + x] = n * 0.6f + grit * 0.4f - wet * 0.5f;
                float gloss = Mathf.Lerp(0.35f, 1f, wet);
                gl[y * w + x] = C(0f, 0f, 0f, gloss);
            }
            return new Surface
            {
                albedo = Finish(New(w, h), px, intersection ? "Intersection" : "Road"),
                normal = NormalFromHeight(hf, w, h, 2.5f, "RoadN"),
                gloss = Finish(New(w, h, true), gl, "RoadGloss"),
                tileMeters = intersection ? new Vector2(14, 14) : new Vector2(14, 12)
            };
        }

        static Surface MakeSidewalk()
        {
            int s = 128; var px = new Color32[s * s]; var gl = new Color32[s * s]; var hf = new float[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                bool seam = x % 32 == 0 || y % 32 == 0;
                int tx = x / 32, ty = y / 32;
                float tile = Hash(tx, ty, 13) * 0.06f;
                float n = TileNoise(x / 8f, y / 8f, 16, 31);
                float stain = TileNoise(x / 24f, y / 24f, 5, 41, 3);
                float v = 0.34f + tile + n * 0.08f - Mathf.Clamp01(stain - 0.55f) * 0.4f;
                if (seam) v *= 0.55f;
                px[y * s + x] = C(v, v * 0.98f, v * 0.95f);
                hf[y * s + x] = seam ? 0f : 0.5f + n * 0.3f;
                float wet = Mathf.Clamp01((stain - 0.5f) * 4f);
                gl[y * s + x] = C(0, 0, 0, Mathf.Lerp(0.3f, 0.9f, wet));
            }
            return new Surface
            {
                albedo = Finish(New(s, s), px, "Sidewalk"),
                normal = NormalFromHeight(hf, s, s, 3f, "SidewalkN"),
                gloss = Finish(New(s, s, true), gl, "SidewalkGloss"),
                tileMeters = new Vector2(4, 4)
            };
        }

        static Surface MakeConcrete(float baseV, int seed, string name)
        {
            int s = 128; var px = new Color32[s * s]; var hf = new float[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float n = TileNoise(x / 6f, y / 6f, 21, seed);
                float big = TileNoise(x / 32f, y / 32f, 4, seed + 3, 3);
                float streak = TileNoise(x / 3f, y / 40f, 42, seed + 9, 2);
                float v = baseV + (n - 0.5f) * 0.12f + (big - 0.5f) * 0.15f - Mathf.Clamp01(streak - 0.6f) * 0.3f;
                px[y * s + x] = C(v, v, v * 0.97f);
                hf[y * s + x] = n;
            }
            return new Surface
            {
                albedo = Finish(New(s, s), px, name),
                normal = NormalFromHeight(hf, s, s, 1.5f, name + "N"),
                tileMeters = new Vector2(6, 6)
            };
        }

        static Surface MakeDirt()
        {
            int s = 128; var px = new Color32[s * s]; var hf = new float[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float n = TileNoise(x / 5f, y / 5f, 25, 51);
                float big = TileNoise(x / 20f, y / 20f, 6, 53, 3);
                var c = Color.Lerp(new Color(0.32f, 0.26f, 0.19f), new Color(0.48f, 0.4f, 0.3f), n * 0.6f + big * 0.4f);
                px[y * s + x] = C(c);
                hf[y * s + x] = n * 0.7f + big * 0.3f;
            }
            return new Surface { albedo = Finish(New(s, s), px, "Dirt"), normal = NormalFromHeight(hf, s, s, 2.5f, "DirtN"), tileMeters = new Vector2(8, 8) };
        }

        static Surface MakeMetal()
        {
            int s = 128; var px = new Color32[s * s]; var hf = new float[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                bool seam = x % 64 < 2 || y % 64 < 2;
                bool rivet = ((x % 64) - 6) * ((x % 64) - 6) + ((y % 64) - 6) * ((y % 64) - 6) < 5;
                float n = TileNoise(x / 4f, y / 32f, 32, 61, 3);
                float v = 0.5f + (n - 0.5f) * 0.15f;
                if (seam) v *= 0.4f;
                if (rivet) v = 0.7f;
                px[y * s + x] = C(v, v, v);
                hf[y * s + x] = seam ? 0 : rivet ? 1 : 0.5f;
            }
            return new Surface { albedo = Finish(New(s, s), px, "Metal"), normal = NormalFromHeight(hf, s, s, 2f, "MetalN"), tileMeters = new Vector2(3, 3) };
        }

        static Surface MakeRibbed()
        {
            int s = 128; var px = new Color32[s * s]; var hf = new float[s * s];
            for (int y = 0; y < s; y++) for (int x = 0; x < s; x++)
            {
                float rib = Mathf.Sin(x / (float)s * Mathf.PI * 2 * 16);
                float rust = TileNoise(x / 10f, y / 16f, 13, 71, 4);
                float v = 0.62f + rib * 0.08f;
                var c = Color.Lerp(new Color(v, v, v), new Color(0.45f, 0.22f, 0.1f), Mathf.Clamp01((rust - 0.55f) * 3f));
                px[y * s + x] = C(c);
                hf[y * s + x] = rib * 0.5f + 0.5f;
            }
            return new Surface { albedo = Finish(New(s, s), px, "Ribbed"), normal = NormalFromHeight(hf, s, s, 4f, "RibbedN"), tileMeters = new Vector2(2.5f, 2.5f) };
        }

        // ---------------------------------------------------------------- facades
        static readonly Dictionary<string, FacadeTex> facades = new Dictionary<string, FacadeTex>();

        public static FacadeTex Facade(FacadeStyle style, int variant)
        {
            string key = style + "_" + variant;
            if (facades.TryGetValue(key, out var f)) return f;
            f = MakeFacade(style, variant);
            facades[key] = f;
            return f;
        }

        static FacadeTex MakeFacade(FacadeStyle style, int variant)
        {
            int w = 256, h = 256;
            var al = new Color32[w * h];
            var em = new Color32[w * h];
            int seed = (int)style * 101 + variant * 17 + 3;
            int cols = 4, rows = 4;
            Vector2 tile = new Vector2(12f, 14f);
            if (style == FacadeStyle.Glass) { cols = 6; rows = 6; tile = new Vector2(12f, 21f); }
            if (style == FacadeStyle.Residential) { cols = 4; rows = 4; tile = new Vector2(12f, 13f); }
            if (style == FacadeStyle.Slum) { cols = 3; rows = 3; tile = new Vector2(9f, 9f); }
            if (style == FacadeStyle.Industrial) { cols = 2; rows = 1; tile = new Vector2(10f, 10f); }
            if (style == FacadeStyle.Shopfront) { cols = 2; rows = 1; tile = new Vector2(10f, 4.5f); h = 128; al = new Color32[w * h]; em = new Color32[w * h]; }
            int cw = w / cols, ch = h / rows;

            var warm = new[] { new Color(1f, 0.75f, 0.45f), new Color(1f, 0.85f, 0.6f), new Color(0.6f, 0.85f, 1f), new Color(1f, 0.4f, 0.7f), new Color(0.5f, 1f, 0.9f), new Color(0.9f, 0.9f, 1f) };

            for (int cy = 0; cy < rows; cy++)
                for (int cx = 0; cx < cols; cx++)
                {
                    float lit = Hash(cx, cy, seed);
                    var lc = warm[(int)(Hash(cx, cy, seed + 1) * warm.Length) % warm.Length];
                    float bright = 0.5f + Hash(cx, cy, seed + 2) * 0.5f;
                    float blinds = Hash(cx, cy, seed + 5);
                    for (int py = 0; py < ch; py++)
                        for (int pxl = 0; pxl < cw; pxl++)
                        {
                            int x = cx * cw + pxl, y = cy * ch + py;
                            float fx = (pxl + 0.5f) / cw, fy = (py + 0.5f) / ch;
                            float noise = TileNoise(x / 16f, y / 16f, 16, seed + 7);
                            float grime = TileNoise(x / 4f, y / 48f, 64, seed + 9, 2);
                            Color a; Color e = Color.black;
                            switch (style)
                            {
                                case FacadeStyle.Glass:
                                    {
                                        bool mullion = fx < 0.06f || fx > 0.94f;
                                        bool spandrel = fy < 0.18f;
                                        if (mullion) a = new Color(0.55f, 0.58f, 0.62f);
                                        else if (spandrel) a = new Color(0.12f, 0.14f, 0.17f);
                                        else
                                        {
                                            float grad = 0.18f + fy * 0.12f + noise * 0.05f;
                                            a = new Color(grad * 0.6f, grad * 0.8f, grad);
                                            if (lit < 0.38f)
                                            {
                                                float stripe = blinds > 0.5f && (py % 6 < 2) ? 0.4f : 1f;
                                                e = lc * bright * stripe * (0.65f + 0.35f * fy);
                                            }
                                        }
                                        break;
                                    }
                                case FacadeStyle.Office:
                                    {
                                        bool win = fx > 0.18f && fx < 0.82f && fy > 0.25f && fy < 0.85f;
                                        float c = 0.55f + noise * 0.15f - Mathf.Clamp01(grime - 0.62f) * 0.5f;
                                        a = new Color(c, c, c * 0.98f);
                                        if (win)
                                        {
                                            a = new Color(0.08f, 0.1f, 0.12f);
                                            if (lit < 0.45f) e = lc * bright * (fx > 0.49f && fx < 0.51f ? 0.2f : 1f);
                                        }
                                        else if (fy < 0.12f) a *= 0.7f;
                                        break;
                                    }
                                case FacadeStyle.Residential:
                                    {
                                        bool win = fx > 0.22f && fx < 0.78f && fy > 0.35f && fy < 0.82f;
                                        bool ac = fx > 0.6f && fx < 0.86f && fy > 0.12f && fy < 0.3f && Hash(cx, cy, seed + 8) > 0.45f;
                                        bool balcony = fy > 0.28f && fy < 0.35f && Hash(cx, cy, seed + 11) > 0.5f;
                                        float c = 0.8f + noise * 0.12f - Mathf.Clamp01(grime - 0.5f) * 0.9f;
                                        a = new Color(c, c * 0.97f, c * 0.92f);
                                        if (win)
                                        {
                                            a = new Color(0.07f, 0.07f, 0.09f);
                                            if (lit < 0.5f)
                                            {
                                                float curtain = (fx < 0.35f || fx > 0.65f) ? 0.55f : 1f;
                                                e = lc * bright * curtain;
                                            }
                                        }
                                        if (ac) a = new Color(0.55f, 0.56f, 0.57f) * (pxl % 4 == 0 ? 0.6f : 1f);
                                        if (balcony) a = new Color(0.25f, 0.25f, 0.27f);
                                        break;
                                    }
                                case FacadeStyle.Slum:
                                    {
                                        float patchHue = Hash(cx * 3 + (int)(fy * 2), cy * 7 + (int)(fx * 2), seed + 12);
                                        var pc = Color.HSVToRGB(patchHue, 0.35f, 0.55f);
                                        float rib = Mathf.Sin(x * 0.8f) * 0.08f;
                                        float rust = Mathf.Clamp01((grime - 0.45f) * 2.5f);
                                        a = Color.Lerp(pc + new Color(rib, rib, rib), new Color(0.35f, 0.17f, 0.08f), rust);
                                        bool win = fx > 0.3f && fx < 0.7f && fy > 0.4f && fy < 0.75f && Hash(cx, cy, seed + 13) > 0.35f;
                                        if (win)
                                        {
                                            a = new Color(0.05f, 0.05f, 0.05f);
                                            if (lit < 0.55f) e = Color.Lerp(new Color(1f, 0.55f, 0.2f), lc, 0.3f) * bright;
                                        }
                                        break;
                                    }
                                case FacadeStyle.Industrial:
                                    {
                                        float rib = Mathf.Sin(fx * Mathf.PI * 2 * 12) * 0.07f;
                                        float c = 0.5f + rib + noise * 0.1f - Mathf.Clamp01(grime - 0.55f) * 0.6f;
                                        a = new Color(c, c * 0.98f, c * 0.94f);
                                        bool strip = fy > 0.78f && fy < 0.9f;
                                        if (strip)
                                        {
                                            a = new Color(0.1f, 0.11f, 0.12f);
                                            if (lit < 0.6f) e = new Color(0.9f, 0.85f, 0.6f) * 0.5f;
                                        }
                                        break;
                                    }
                                case FacadeStyle.Ruin:
                                    {
                                        float c = 0.38f + noise * 0.15f;
                                        float burn = Mathf.Clamp01((TileNoise(x / 20f, y / 20f, 12, seed + 14, 3) - 0.5f) * 3f);
                                        a = Color.Lerp(new Color(c, c * 0.96f, c * 0.9f), new Color(0.05f, 0.04f, 0.04f), burn);
                                        bool win = fx > 0.2f && fx < 0.8f && fy > 0.3f && fy < 0.85f;
                                        if (win)
                                        {
                                            a = new Color(0.02f, 0.02f, 0.02f);
                                            if (lit < 0.08f) e = new Color(1f, 0.35f, 0.05f) * (0.6f + 0.4f * noise);
                                        }
                                        break;
                                    }
                                default: // Shopfront
                                    {
                                        bool glass = fx > 0.06f && fx < 0.94f && fy > 0.08f && fy < 0.78f;
                                        bool shutter = glass && fy > 0.78f - Hash(cx, 0, seed + 15) * 0.5f;
                                        float c = 0.3f + noise * 0.1f;
                                        a = new Color(c, c, c);
                                        if (glass)
                                        {
                                            a = new Color(0.05f, 0.06f, 0.07f);
                                            e = Color.Lerp(lc, Color.white, 0.4f) * (0.7f + 0.3f * Mathf.Sin(fx * 30f) * Mathf.Sin(fy * 20f)) * 1.2f;
                                        }
                                        if (shutter)
                                        {
                                            float rib = (py % 6 < 3) ? 0.45f : 0.35f;
                                            a = new Color(rib, rib, rib * 1.05f);
                                            e = Color.black;
                                        }
                                        if (fy > 0.82f) { a = new Color(0.08f, 0.08f, 0.09f); }
                                        break;
                                    }
                            }
                            al[y * w + x] = C(a);
                            em[y * w + x] = C(e);
                        }
                }
            return new FacadeTex
            {
                albedo = Finish(New(w, h), al, style + "A" + variant),
                emission = Finish(New(w, h), em, style + "E" + variant),
                tileMeters = tile
            };
        }

        // ---------------------------------------------------------------- pixel font
        static readonly Dictionary<char, string> font = new Dictionary<char, string>
        {
            {'A',"01110,10001,10001,11111,10001,10001,10001"},{'B',"11110,10001,10001,11110,10001,10001,11110"},
            {'C',"01110,10001,10000,10000,10000,10001,01110"},{'D',"11110,10001,10001,10001,10001,10001,11110"},
            {'E',"11111,10000,10000,11110,10000,10000,11111"},{'F',"11111,10000,10000,11110,10000,10000,10000"},
            {'G',"01110,10001,10000,10111,10001,10001,01111"},{'H',"10001,10001,10001,11111,10001,10001,10001"},
            {'I',"01110,00100,00100,00100,00100,00100,01110"},{'J',"00111,00010,00010,00010,00010,10010,01100"},
            {'K',"10001,10010,10100,11000,10100,10010,10001"},{'L',"10000,10000,10000,10000,10000,10000,11111"},
            {'M',"10001,11011,10101,10101,10001,10001,10001"},{'N',"10001,10001,11001,10101,10011,10001,10001"},
            {'O',"01110,10001,10001,10001,10001,10001,01110"},{'P',"11110,10001,10001,11110,10000,10000,10000"},
            {'Q',"01110,10001,10001,10001,10101,10010,01101"},{'R',"11110,10001,10001,11110,10100,10010,10001"},
            {'S',"01111,10000,10000,01110,00001,00001,11110"},{'T',"11111,00100,00100,00100,00100,00100,00100"},
            {'U',"10001,10001,10001,10001,10001,10001,01110"},{'V',"10001,10001,10001,10001,10001,01010,00100"},
            {'W',"10001,10001,10001,10101,10101,10101,01010"},{'X',"10001,10001,01010,00100,01010,10001,10001"},
            {'Y',"10001,10001,01010,00100,00100,00100,00100"},{'Z',"11111,00001,00010,00100,01000,10000,11111"},
            {'0',"01110,10001,10011,10101,11001,10001,01110"},{'1',"00100,01100,00100,00100,00100,00100,01110"},
            {'2',"01110,10001,00001,00010,00100,01000,11111"},{'3',"11111,00010,00100,00010,00001,10001,01110"},
            {'4',"00010,00110,01010,10010,11111,00010,00010"},{'5',"11111,10000,11110,00001,00001,10001,01110"},
            {'6',"00110,01000,10000,11110,10001,10001,01110"},{'7',"11111,00001,00010,00100,01000,01000,01000"},
            {'8',"01110,10001,10001,01110,10001,10001,01110"},{'9',"01110,10001,10001,01111,00001,00010,01100"},
            {'-',"00000,00000,00000,11111,00000,00000,00000"},{'.',"00000,00000,00000,00000,00000,01100,01100"},
            {'!',"00100,00100,00100,00100,00100,00000,00100"},{'?',"01110,10001,00001,00010,00100,00000,00100"},
            {':',"00000,01100,01100,00000,01100,01100,00000"},{'/',"00001,00010,00010,00100,01000,01000,10000"},
            {'+',"00000,00100,00100,11111,00100,00100,00000"},{'&',"01100,10010,10100,01000,10101,10010,01101"},
            {'\'',"00100,00100,01000,00000,00000,00000,00000"},{'%',"11000,11001,00010,00100,01000,10011,00011"},
            {'*',"00000,00100,10101,01110,10101,00100,00000"},{'#',"01010,01010,11111,01010,11111,01010,01010"},
            {'$',"00100,01111,10100,01110,00101,11110,00100"},{' ',"00000,00000,00000,00000,00000,00000,00000"},
        };

        static bool GlyphPixel(char ch, int gx, int gy)
        {
            if (!font.TryGetValue(char.ToUpperInvariant(ch), out var g)) return false;
            // gy = 0 is the TOP row
            int idx = gy * 6 + gx;
            return idx < g.Length && g[idx] == '1';
        }

        /// <summary>Draws text in the pixel font into a float mask (1 = lit). y grows upward in the texture.</summary>
        static void DrawText(float[] mask, int w, int h, int x0, int y0, string text, int scale)
        {
            int cx = x0;
            foreach (var ch in text)
            {
                for (int gy = 0; gy < 7; gy++)
                    for (int gx = 0; gx < 5; gx++)
                    {
                        if (!GlyphPixel(ch, gx, gy)) continue;
                        for (int sy = 0; sy < scale; sy++)
                            for (int sx = 0; sx < scale; sx++)
                            {
                                int x = cx + gx * scale + sx;
                                int y = y0 + (6 - gy) * scale + sy;
                                if (x >= 0 && x < w && y >= 0 && y < h) mask[y * w + x] = 1f;
                            }
                    }
                cx += 6 * scale;
            }
        }

        static void DrawPseudoGlyphs(float[] mask, int w, int h, int x0, int y0, int cw, int ch, int count, int seed, bool vertical)
        {
            var rng = new Rng(seed);
            int gs = Mathf.Min(cw, ch);
            for (int i = 0; i < count; i++)
            {
                int gx = vertical ? x0 : x0 + i * (gs + gs / 4);
                int gy = vertical ? y0 + i * (gs + gs / 4) : y0;
                int strokes = rng.Range(3, 7);
                int t = Mathf.Max(1, gs / 9);
                for (int s = 0; s < strokes; s++)
                {
                    int kind = rng.Range(0, 4);
                    int a = rng.Range(0, gs), b = rng.Range(0, gs), len = rng.Range(gs / 3, gs);
                    for (int k = 0; k < len; k++)
                        for (int tt = 0; tt < t; tt++)
                        {
                            int x, y;
                            switch (kind)
                            {
                                case 0: x = gx + Mathf.Min(gs - 1, k); y = gy + a + tt; break;
                                case 1: x = gx + a + tt; y = gy + Mathf.Min(gs - 1, k); break;
                                case 2:
                                    {
                                        float ang = k / (float)len * Mathf.PI * 2;
                                        float r = gs * 0.22f;
                                        x = gx + (int)(gs * 0.5f + Mathf.Cos(ang) * r) + tt; y = gy + (int)(b * 0.5f + Mathf.Sin(ang) * r);
                                        break;
                                    }
                                default: x = gx + Mathf.Min(gs - 1, k) + tt; y = gy + Mathf.Min(gs - 1, k * b / Mathf.Max(1, gs)); break;
                            }
                            if (x >= 0 && x < w && y >= 0 && y < h) mask[y * w + x] = 1f;
                        }
                }
            }
        }

        static float[] Blur(float[] src, int w, int h, int radius)
        {
            var tmp = new float[src.Length];
            var dst = new float[src.Length];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float s = 0; int n = 0;
                    for (int k = -radius; k <= radius; k++) { int xx = x + k; if (xx < 0 || xx >= w) continue; s += src[y * w + xx]; n++; }
                    tmp[y * w + x] = s / n;
                }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float s = 0; int n = 0;
                    for (int k = -radius; k <= radius; k++) { int yy = y + k; if (yy < 0 || yy >= h) continue; s += tmp[yy * w + x]; n++; }
                    dst[y * w + x] = s / n;
                }
            return dst;
        }

        // ---------------------------------------------------------------- sign atlas
        public const int SignCols = 8, SignRows = 16;
        static Texture2D signAtlas;
        public static readonly string[] SignWords =
        {
            "DINER","BAR","HOTEL","GUNS","CLINIC","BURGERS","KARAOKE","PAWN","24H","CHROME","IMPLANTS","DATA",
            "NET CAFE","TACOS","PIZZA","HOT DOGS","BBQ","DRINK","OPEN","LOTUS","HELIX","NEON","PHARMACY",
            "BOXING","FIGHT NIGHT","ARCADE","VR LOUNGE","BANK","TAXI","METRO","PARKING","CYBER","TECH","REPAIR",
            "SUSHI","DONUTS","COFFEE","LIQUOR","CASINO","MOTEL","LUCKY","GOLD","WE BUY GOLD","BAIL BONDS","CHECK CASHING","LIBERTY",
            "NEON BAY","2089","NO EXIT","DANGER","5TH AVE","GUMBO","CRAB SHACK","BEER","CAFE","OPTICS","WIRE","SYNTH",
            "DREAMS","RIDE","TATTOO","ROBOT","SPA","PARTS","BOWLING","LAUNDROMAT","JESUS SAVES","PSYCHIC","TAROT","CHAPEL",
            "LIVE MUSIC","JAZZ","BLUES","SOUL FOOD","RECORDS","COMICS","BARBER","NAILS","GYM","NO VACANCY","VACANCY","OYSTERS",
            "SURF SHOP","BAIT & TACKLE","LOANS","SLOTS","LOTTO","ATM","VALET","INN","DANCE","CLUB","COCKTAILS","WINE",
            "CUBAN","RAMEN","NOODLES","BAKERY","DELI","ICE COLD","EAT","CASH","PIERCING","VIDEO","TOYS","PETS"
        };
        static readonly Color[] signColors = { Palette.Magenta, Palette.Cyan, Palette.Yellow, Palette.Orange, Palette.Red, Palette.Green, Palette.Purple, Palette.Blue, Palette.White };

        public static Texture2D SignAtlas
        {
            get
            {
                if (signAtlas != null) return signAtlas;
                int cw = 128, ch = 64, w = cw * SignCols, h = ch * SignRows;
                var px = new Color32[w * h];
                for (int i = 0; i < px.Length; i++) px[i] = new Color32(3, 3, 5, 255);
                var cellMask = new float[cw * ch];
                for (int cell = 0; cell < SignCols * SignRows; cell++)
                {
                    System.Array.Clear(cellMask, 0, cellMask.Length);
                    var rng = new Rng(9000 + cell);
                    var col = signColors[cell % signColors.Length];
                    var col2 = signColors[(cell * 7 + 3) % signColors.Length];
                    bool frame = rng.Chance(0.6f);
                    if (cell < SignWords.Length)
                    {
                        string word = SignWords[cell];
                        int scale = Mathf.Clamp(118 / Mathf.Max(1, word.Length * 6), 1, 4);
                        int tw = word.Length * 6 * scale - scale, th = 7 * scale;
                        DrawText(cellMask, cw, ch, (cw - tw) / 2, (ch - th) / 2, word, scale);
                    }
                    else
                    {
                        int count = rng.Range(2, 5);
                        int gs = Mathf.Min(40, 110 / count - 6);
                        int total = count * (gs + gs / 4) - gs / 4;
                        DrawPseudoGlyphs(cellMask, cw, ch, (cw - total) / 2, (ch - gs) / 2, gs, gs, count, cell * 31, false);
                    }
                    if (frame)
                    {
                        for (int x = 3; x < cw - 3; x++) { cellMask[3 * cw + x] = 0.8f; cellMask[(ch - 4) * cw + x] = 0.8f; }
                        for (int y = 3; y < ch - 3; y++) { cellMask[y * cw + 3] = 0.8f; cellMask[y * cw + cw - 4] = 0.8f; }
                    }
                    var glow = Blur(cellMask, cw, ch, 3);
                    int ox = (cell % SignCols) * cw, oy = (cell / SignCols) * ch;
                    for (int y = 0; y < ch; y++)
                        for (int x = 0; x < cw; x++)
                        {
                            float core = cellMask[y * cw + x];
                            float g = glow[y * cw + x];
                            bool isFrame = frame && (x == 3 || y == 3 || x == cw - 4 || y == ch - 4);
                            var c = isFrame ? col2 : col;
                            var o = Color.Lerp(new Color(0.012f, 0.012f, 0.02f), c * 0.55f, Mathf.Clamp01(g * 1.6f));
                            if (core > 0) o = Color.Lerp(c, Color.white, 0.35f);
                            px[(oy + y) * w + ox + x] = C(o);
                        }
                }
                signAtlas = Finish(New(w, h, false, true, TextureWrapMode.Clamp), px, "SignAtlas");
                return signAtlas;
            }
        }

        public static Rect SignUV(int index)
        {
            index = ((index % (SignCols * SignRows)) + SignCols * SignRows) % (SignCols * SignRows);
            float cw = 1f / SignCols, ch = 1f / SignRows;
            int cx = index % SignCols, cy = index / SignCols;
            const float pad = 0.002f;
            return new Rect(cx * cw + pad, cy * ch + pad, cw - pad * 2, ch - pad * 2);
        }

        public static int SignIndexForWord(string word)
        {
            for (int i = 0; i < SignWords.Length; i++) if (SignWords[i] == word) return i;
            return 0;
        }

        // ---------------------------------------------------------------- vertical blade signs (classic stacked-letter neon)
        public static readonly string[] VerticalWords = { "HOTEL", "BAR", "MOTEL", "DINER", "PAWN", "OPEN", "CLUB", "GUNS", "TATTOO", "LIQUOR", "CASINO", "ARCADE", "BURGER", "PIZZA", "DANCE", "RADIO", "DONUTS", "BOXING", "LOTUS", "NEON", "JAZZ", "LOANS", "CHROME", "DRINKS" };
        public const int VertCols = 24;
        static Texture2D vertAtlas;

        public static Texture2D VerticalAtlas
        {
            get
            {
                if (vertAtlas != null) return vertAtlas;
                int cw = 32, ch = 256, w = cw * VertCols, h = ch;
                var px = new Color32[w * h];
                for (int i = 0; i < px.Length; i++) px[i] = new Color32(3, 3, 5, 255);
                var mask = new float[cw * ch];
                for (int cell = 0; cell < VertCols; cell++)
                {
                    System.Array.Clear(mask, 0, mask.Length);
                    string word = VerticalWords[cell % VerticalWords.Length];
                    int scale = 4, step = Mathf.Min(34, (ch - 16) / Mathf.Max(1, word.Length));
                    int total = step * word.Length;
                    int top = ch - (ch - total) / 2;
                    for (int k = 0; k < word.Length; k++)
                        DrawText(mask, cw, ch, (cw - 5 * scale) / 2, top - (k + 1) * step + (step - 7 * scale) / 2, word[k].ToString(), scale);
                    for (int y = 2; y < ch - 2; y++) { mask[y * cw + 2] = 0.8f; mask[y * cw + cw - 3] = 0.8f; }
                    for (int x = 2; x < cw - 2; x++) { mask[2 * cw + x] = 0.8f; mask[(ch - 3) * cw + x] = 0.8f; }
                    var glow = Blur(mask, cw, ch, 3);
                    var col = signColors[(cell * 5 + 1) % signColors.Length];
                    var frameCol = signColors[(cell * 3 + 4) % signColors.Length];
                    for (int y = 0; y < ch; y++)
                        for (int x = 0; x < cw; x++)
                        {
                            float core = mask[y * cw + x];
                            bool frame = x == 2 || x == cw - 3 || y == 2 || y == ch - 3;
                            var c = frame ? frameCol : col;
                            var o = Color.Lerp(new Color(0.012f, 0.012f, 0.02f), c * 0.55f, Mathf.Clamp01(glow[y * cw + x] * 1.6f));
                            if (core > 0) o = Color.Lerp(c, Color.white, 0.35f);
                            px[y * w + cell * cw + x] = C(o);
                        }
                }
                vertAtlas = Finish(New(w, h, false, true, TextureWrapMode.Clamp), px, "VerticalSignAtlas");
                return vertAtlas;
            }
        }

        public static Rect VerticalUV(int index)
        {
            index = ((index % VertCols) + VertCols) % VertCols;
            float cw = 1f / VertCols;
            return new Rect(index * cw + 0.001f, 0.002f, cw - 0.002f, 0.996f);
        }

        // ---------------------------------------------------------------- billboard ads
        public static readonly string[,] Ads =
        {
            { "HELIX DYNAMICS", "LIVE FOREVER" }, { "VOLT COLA", "FEEL THE SHOCK" },
            { "CHROME IS LOVE", "CLINIC 24H" }, { "LOTUS CLUB", "NIGHTS NEVER END" },
            { "BAY METRO", "FASTER THAN FATE" }, { "SYNAPSE+", "UPGRADE YOUR MIND" },
            { "NBPD", "SERVE . PROTECT . COMPLY" }, { "NEON BURGER", "2089 CALORIES" },
        };
        static Texture2D adAtlas;

        public static Texture2D AdAtlas
        {
            get
            {
                if (adAtlas != null) return adAtlas;
                int cw = 256, ch = 128, cols = 2, rows = 4, w = cw * cols, h = ch * rows;
                var px = new Color32[w * h];
                var mask = new float[cw * ch];
                var mask2 = new float[cw * ch];
                for (int i = 0; i < cols * rows; i++)
                {
                    System.Array.Clear(mask, 0, mask.Length);
                    System.Array.Clear(mask2, 0, mask2.Length);
                    string l1 = Ads[i, 0], l2 = Ads[i, 1];
                    int s1 = Mathf.Clamp(240 / (l1.Length * 6), 1, 5), s2 = Mathf.Clamp(240 / (l2.Length * 6), 1, 2);
                    DrawText(mask, cw, ch, (cw - l1.Length * 6 * s1) / 2, ch / 2 + 2, l1, s1);
                    DrawText(mask2, cw, ch, (cw - l2.Length * 6 * s2) / 2, ch / 2 - 22, l2, s2);
                    var c1 = signColors[(i * 3) % signColors.Length];
                    var c2 = signColors[(i * 3 + 4) % signColors.Length];
                    var glow = Blur(mask, cw, ch, 4);
                    int ox = (i % cols) * cw, oy = (i / cols) * ch;
                    for (int y = 0; y < ch; y++)
                        for (int x = 0; x < cw; x++)
                        {
                            float fy = y / (float)ch, fx = x / (float)cw;
                            var bg = Color.Lerp(c2 * 0.18f, c1 * 0.08f, fy);
                            float circle = Mathf.Abs(new Vector2(fx - 0.85f, fy - 0.7f).magnitude - 0.12f) < 0.01f ? 1f : 0f;
                            var o = bg + c1 * glow[y * cw + x] * 0.8f + c2 * circle;
                            if (mask[y * cw + x] > 0) o = Color.Lerp(c1, Color.white, 0.5f);
                            if (mask2[y * cw + x] > 0) o = Color.white * 0.9f;
                            if (y % 3 == 0) o *= 0.85f;
                            px[(oy + y) * w + ox + x] = C(o);
                        }
                }
                adAtlas = Finish(New(w, h, false, true, TextureWrapMode.Clamp), px, "AdAtlas");
                return adAtlas;
            }
        }

        public static Rect AdUV(int index)
        {
            index = ((index % 8) + 8) % 8;
            return new Rect((index % 2) * 0.5f + 0.002f, (index / 2) * 0.25f + 0.002f, 0.496f, 0.246f);
        }

        // ---------------------------------------------------------------- misc
        public static Texture2D Graffiti(int seed)
        {
            return Get("graf" + seed, () =>
            {
                int w = 128, h = 64;
                var mask = new float[w * h];
                DrawPseudoGlyphs(mask, w, h, 8, 10, 40, 40, 3, seed, false);
                var g = Blur(mask, w, h, 2);
                var col = signColors[seed % signColors.Length];
                var px = new Color32[w * h];
                for (int i = 0; i < px.Length; i++)
                {
                    float a = Mathf.Clamp01(mask[i] + g[i] * 1.5f);
                    px[i] = C(col.r, col.g, col.b, a);
                }
                return Finish(New(w, h, false, true, TextureWrapMode.Clamp), px, "Graffiti");
            });
        }
    }
}
