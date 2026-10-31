using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public class VendorSpot
    {
        public Vector3 pos;
        public Vector3 facing;
        public string shopId;
        public string name;
        public string npcId;
        public int look;
    }

    /// <summary>
    /// Procedurally builds Neon Bay: ground, roads, five districts of buildings, props, landmarks and interiors.
    /// Everything is combined into per-chunk meshes to keep draw calls low.
    /// </summary>
    public partial class CityGenerator
    {
        readonly CityData city;
        readonly Rng rng;
        public readonly CityMaterials M;
        public Transform root;
        public Chunk[,] chunks;
        public int chunkCount;
        public readonly List<VendorSpot> vendors = new List<VendorSpot>();
        public readonly List<Vector3> steamVents = new List<Vector3>();
        public readonly List<Vector3> fireBarrels = new List<Vector3>();
        public readonly List<Transform> holograms = new List<Transform>();
        public static CityGenerator Current;

        public CityGenerator(CityData city)
        {
            this.city = city;
            rng = new Rng(city.seed);
            M = new CityMaterials();
            Current = this;
        }

        Chunk ChunkFor(Vector3 p)
        {
            var i = ChunkStreamer.ChunkIndex(p);
            i.x = Mathf.Clamp(i.x, 0, chunkCount - 1);
            i.y = Mathf.Clamp(i.y, 0, chunkCount - 1);
            return chunks[i.x, i.y];
        }

        public IEnumerator Generate(Transform parent, Action<float, string> progress)
        {
            root = new GameObject("NeonBay_City").transform;
            root.SetParent(parent, false);
            float total = city.Size + 2 * (CityData.WallMargin + 30f);
            chunkCount = Mathf.CeilToInt(total / ChunkStreamer.ChunkSize);
            chunks = new Chunk[chunkCount, chunkCount];
            for (int x = 0; x < chunkCount; x++)
                for (int z = 0; z < chunkCount; z++)
                {
                    var c = new Chunk { cx = x, cz = z };
                    c.center = new Vector3(ChunkStreamer.Origin + (x + 0.5f) * ChunkStreamer.ChunkSize, 0, ChunkStreamer.Origin + (z + 0.5f) * ChunkStreamer.ChunkSize);
                    c.root = new GameObject($"Chunk_{x}_{z}");
                    c.root.transform.SetParent(root, false);
                    c.collidersGo = new GameObject("Colliders");
                    c.collidersGo.transform.SetParent(c.root.transform, false);
                    c.collidersGo.layer = Layers.World;
                    c.detailGo = new GameObject("Detail");
                    c.detailGo.transform.SetParent(c.root.transform, false);
                    chunks[x, z] = c;
                }

            progress?.Invoke(0.02f, "Pouring the foundations");
            yield return null;
            Safe(BuildGround, "ground");
            Safe(BuildRoads, "roads");
            progress?.Invoke(0.1f, "Paving the streets");
            yield return null;

            int done = 0, totalBlocks = CityData.Grid * CityData.Grid;
            for (int bx = 0; bx < CityData.Grid; bx++)
            {
                for (int bz = 0; bz < CityData.Grid; bz++)
                {
                    var blk = city.blocks[bx, bz];
                    Safe(() => BuildBlock(blk), "block " + bx + "," + bz);
                    done++;
                }
                progress?.Invoke(0.1f + 0.6f * done / totalBlocks, "Raising " + CityData.DistrictName(city.blocks[bx, Mathf.Min(bx, CityData.Grid - 1)].district));
                yield return null;
            }

            Safe(BuildStreetFurniture, "street furniture");
            progress?.Invoke(0.75f, "Wiring the neon");
            yield return null;
            Safe(BuildPerimeter, "perimeter");
            Safe(BuildMonorail, "monorail");
            Safe(BuildSkyline, "skyline");
            Safe(BuildApartmentInterior, "apartment");
            Safe(PlaceInteractivePoints, "interactive points");
            progress?.Invoke(0.82f, "Uploading the skyline");
            yield return null;

            // Combine everything
            int built = 0;
            foreach (var c in chunks)
            {
                c.staticGo = c.staticMB.BuildObject("Static", c.root.transform, true);
                var det = c.detailMB.BuildObject("DetailMesh", c.detailGo.transform, true);
                if (c.staticGo != null) c.staticGo.isStatic = true;
                c.staticMB.Clear(); c.detailMB.Clear();
                built++;
                if (built % 10 == 0)
                {
                    progress?.Invoke(0.82f + 0.15f * built / (chunkCount * chunkCount), "Compiling geometry");
                    yield return null;
                }
            }
            progress?.Invoke(1f, "Ready");
        }

        static void Safe(Action a, string what)
        {
            try { a(); }
            catch (Exception e) { Debug.LogError("[NeonBay] City generation step failed (" + what + "): " + e); }
        }

        // ------------------------------------------------------------------ ground & roads
        void BuildGround()
        {
            float m = CityData.WallMargin;
            var size = city.Size;
            // one big physics floor for the city (top at y = 0)
            var floor = new GameObject("CityFloor") { layer = Layers.World };
            floor.transform.SetParent(root, false);
            var bc = floor.AddComponent<BoxCollider>();
            bc.center = new Vector3(size * 0.5f, -1f, size * 0.5f);
            bc.size = new Vector3(size + m * 2, 2f, size + m * 2);

            // asphalt apron between the outer road and the megawall
            var tile = Tex.Concrete.tileMeters;
            void Apron(float x0, float z0, float x1, float z1)
            {
                var c = ChunkFor(new Vector3((x0 + x1) * 0.5f, 0, (z0 + z1) * 0.5f));
                // split into ~100m pieces so each lands in the right chunk
                for (float x = x0; x < x1; x += 100f)
                    for (float z = z0; z < z1; z += 100f)
                    {
                        float xe = Mathf.Min(x + 100f, x1), ze = Mathf.Min(z + 100f, z1);
                        ChunkFor(new Vector3((x + xe) * 0.5f, 0, (z + ze) * 0.5f)).staticMB.Floor(M.lotConcrete, x, z, xe, ze, 0.005f, tile);
                    }
            }
            float h = CityData.RoadW * 0.5f;
            Apron(-m, -m, size + m, -h);
            Apron(-m, size + h, size + m, size + m);
            Apron(-m, -h, -h, size + h);
            Apron(size + h, -h, size + m, size + h);
        }

        void BuildRoads()
        {
            float h = CityData.RoadW * 0.5f;
            var tile = Tex.Road.tileMeters;
            for (int i = 0; i <= CityData.Grid; i++)
                for (int j = 0; j <= CityData.Grid; j++)
                {
                    var p = city.Intersection(i, j);
                    var c = ChunkFor(p);
                    // intersection square
                    c.staticMB.FloorUV(M.isect,
                        new Vector3(p.x - h, 0.01f, p.z - h), new Vector3(p.x - h, 0.01f, p.z + h),
                        new Vector3(p.x + h, 0.01f, p.z + h), new Vector3(p.x + h, 0.01f, p.z - h), new Rect(0, 0, 1, 1));
                    // road towards +x
                    if (i < CityData.Grid)
                    {
                        float x0 = p.x + h, x1 = p.x + CityData.Cell - h;
                        var cc = ChunkFor(new Vector3((x0 + x1) * 0.5f, 0, p.z));
                        float len = x1 - x0;
                        // u spans the road width (along z), v runs along x
                        cc.staticMB.Quad(M.road,
                            new Vector3(x0, 0.01f, p.z + h), new Vector3(x1, 0.01f, p.z + h), new Vector3(x1, 0.01f, p.z - h), new Vector3(x0, 0.01f, p.z - h),
                            new Vector2(1, 0), new Vector2(1, len / tile.y), new Vector2(0, len / tile.y), new Vector2(0, 0));
                    }
                    if (j < CityData.Grid)
                    {
                        float z0 = p.z + h, z1 = p.z + CityData.Cell - h;
                        var cc = ChunkFor(new Vector3(p.x, 0, (z0 + z1) * 0.5f));
                        float len = z1 - z0;
                        cc.staticMB.Quad(M.road,
                            new Vector3(p.x - h, 0.01f, z0), new Vector3(p.x - h, 0.01f, z1), new Vector3(p.x + h, 0.01f, z1), new Vector3(p.x + h, 0.01f, z0),
                            new Vector2(0, 0), new Vector2(0, len / tile.y), new Vector2(1, len / tile.y), new Vector2(1, 0));
                    }
                }
        }

        // ------------------------------------------------------------------ blocks
        const float Kerb = 0.15f;

        void BuildBlock(Block b)
        {
            var c = ChunkFor(new Vector3(b.outer.center.x, 0, b.outer.center.y));
            var o = b.outer; var s = b.build;
            var swTile = Tex.Sidewalk.tileMeters;
            // sidewalk ring (raised kerb) + lot floor
            c.staticMB.Box(new Vector3(o.xMin, 0, o.yMin), new Vector3(o.xMax, Kerb, o.yMax), M.curb, null, new Vector2(4, 4));
            var lotMat = b.district == District.Scar ? M.lotDirt : b.district == District.Docks ? M.lotConcrete : M.lotConcrete;
            if (b.plaza) lotMat = M.sidewalk;
            // sidewalk strips
            c.staticMB.Floor(M.sidewalk, o.xMin, o.yMin, o.xMax, s.yMin, Kerb, swTile);
            c.staticMB.Floor(M.sidewalk, o.xMin, s.yMax, o.xMax, o.yMax, Kerb, swTile);
            c.staticMB.Floor(M.sidewalk, o.xMin, s.yMin, s.xMin, s.yMax, Kerb, swTile);
            c.staticMB.Floor(M.sidewalk, s.xMax, s.yMin, o.xMax, s.yMax, Kerb, swTile);
            c.staticMB.Floor(lotMat, s.xMin, s.yMin, s.xMax, s.yMax, Kerb, lotMat == M.sidewalk ? swTile : Tex.Concrete.tileMeters);
            c.AddCollider(new Vector3(o.xMin, 0, o.yMin), new Vector3(o.xMax, Kerb, o.yMax));

            if (!string.IsNullOrEmpty(b.special) && b.special != "home")
            {
                BuildSpecial(b, c);
                return;
            }

            var lr = new Rng(city.seed * 31 + b.bx * 1013 + b.bz * 7919);
            switch (b.district)
            {
                case District.Spire: BuildSpireBlock(b, c, lr); break;
                case District.NeonStrip: BuildDenseBlock(b, c, lr, 3, 12f, 62f, FacadeStyle.Residential, true); break;
                case District.Lowtown: BuildDenseBlock(b, c, lr, 4, 8f, 30f, FacadeStyle.Slum, true); break;
                case District.Docks: BuildDocksBlock(b, c, lr); break;
                default: BuildScarBlock(b, c, lr); break;
            }
            if (b.special == "home") MarkHome(b, c);
        }

        /// <summary>Adds a solid building volume: facade on the sides, roof on top, plus a collider.</summary>
        void Building(Chunk c, Vector3 min, Vector3 max, Material facade, Vector2 tile, bool collider = true, Rng r = null)
        {
            float uOff = r != null ? r.Range(0, 4) * 0.25f : 0f;
            c.staticMB.Box(min, max, facade, M.roof, tile, null, null, uOff);
            if (collider) c.AddCollider(min, max);
        }

        void LedEdges(Chunk c, Vector3 min, Vector3 max, Material neon, float t = 0.35f)
        {
            float x0 = min.x, x1 = max.x, z0 = min.z, z1 = max.z, y0 = min.y, y1 = max.y;
            c.staticMB.Box(new Vector3(x0 - t, y0, z0 - t), new Vector3(x0 + t * 0.2f, y1, z0 + t * 0.2f), neon, neon, Vector2.one);
            c.staticMB.Box(new Vector3(x1 - t * 0.2f, y0, z0 - t), new Vector3(x1 + t, y1, z0 + t * 0.2f), neon, neon, Vector2.one);
            c.staticMB.Box(new Vector3(x0 - t, y0, z1 - t * 0.2f), new Vector3(x0 + t * 0.2f, y1, z1 + t), neon, neon, Vector2.one);
            c.staticMB.Box(new Vector3(x1 - t * 0.2f, y0, z1 - t * 0.2f), new Vector3(x1 + t, y1, z1 + t), neon, neon, Vector2.one);
        }

        void BuildSpireBlock(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            if (b.plaza) { BuildPlaza(b, c, r); return; }
            int towers = r.Chance(0.55f) ? 1 : 2;
            var glassTile = M.FacadeTile(FacadeStyle.Glass);
            var offTile = M.FacadeTile(FacadeStyle.Office);
            for (int t = 0; t < towers; t++)
            {
                Rect foot;
                if (towers == 1) foot = Shrink(s, r.Range(2f, 8f));
                else foot = t == 0 ? new Rect(s.xMin, s.yMin, s.width * 0.48f, s.height) : new Rect(s.xMin + s.width * 0.52f, s.yMin, s.width * 0.48f, s.height);
                float podH = r.Range(8f, 16f);
                var shop = r.Pick(M.shopfronts);
                Building(c, new Vector3(foot.xMin, Kerb, foot.yMin), new Vector3(foot.xMax, Kerb + 4.5f, foot.yMax), shop, new Vector2(10, 4.65f), true, r);
                Building(c, new Vector3(foot.xMin, Kerb + 4.5f, foot.yMin), new Vector3(foot.xMax, podH, foot.yMax), M.Facade(FacadeStyle.Office, r), offTile, true, r);
                var shaft = Shrink(foot, r.Range(4f, 10f));
                float height = r.Range(110f, 300f) * (towers == 2 ? 0.7f : 1f);
                var glass = M.Facade(FacadeStyle.Glass, r);
                float y = podH;
                int tiers = r.Range(1, 4);
                var neon = M.Neon(r.Pick(Palette.SpireNeon), 3f);
                for (int k = 0; k < tiers; k++)
                {
                    float top = k == tiers - 1 ? height : y + (height - podH) / tiers;
                    var mn = new Vector3(shaft.xMin, y, shaft.yMin);
                    var mx = new Vector3(shaft.xMax, top, shaft.yMax);
                    Building(c, mn, mx, glass, glassTile, true, r);
                    if (r.Chance(0.7f)) LedEdges(c, mn, mx, neon);
                    // floor band light
                    c.staticMB.Box(new Vector3(shaft.xMin - 0.2f, top - 0.6f, shaft.yMin - 0.2f), new Vector3(shaft.xMax + 0.2f, top, shaft.yMax + 0.2f), neon, M.roof, Vector2.one);
                    y = top;
                    shaft = Shrink(shaft, r.Range(2f, 5f));
                    if (shaft.width < 10f) break;
                }
                // crown + antenna
                var ctr = new Vector3(shaft.center.x, y, shaft.center.y);
                c.staticMB.Box(ctr + new Vector3(-0.4f, 0, -0.4f), ctr + new Vector3(0.4f, r.Range(12f, 35f), 0.4f), M.metal, M.metal, Vector2.one);
                c.staticMB.SimpleBox(ctr + Vector3.up * 36f, Vector3.one * 1.2f, M.blinkRed);
                if (r.Chance(0.5f))
                {
                    // holo ad on the podium
                    var face = new Vector3(foot.center.x, podH + 10f, foot.yMin - 0.6f);
                    c.detailMB.Panel(M.ads, face, Vector3.back, Mathf.Min(24f, foot.width * 0.8f), 12f, Tex.AdUV(r.Range(0, 8)));
                }
                AddSign(c, r, new Vector3(foot.center.x, Kerb + 5.4f, foot.yMin - 0.25f), Vector3.back, 6f, 1.4f, r.Range(0, 128));
                c.lights.Add(new LightAnchor { pos = new Vector3(foot.center.x, 3f, foot.yMin - 2f), color = Palette.Cyan, range = 14f, intensity = 1.6f, nightOnly = true });
            }
        }

        void BuildDenseBlock(Block b, Chunk c, Rng r, int grid, float minH, float maxH, FacadeStyle upper, bool shops)
        {
            var s = b.build;
            if (b.plaza) { BuildNightMarket(b, c, r); return; }
            float lw = s.width / grid, lh = s.height / grid;
            var tile = M.FacadeTile(upper);
            bool slum = b.district == District.Lowtown;
            for (int gx = 0; gx < grid; gx++)
                for (int gz = 0; gz < grid; gz++)
                {
                    bool edge = gx == 0 || gz == 0 || gx == grid - 1 || gz == grid - 1;
                    var lot = new Rect(s.xMin + gx * lw, s.yMin + gz * lh, lw, lh);
                    // alleys between some lots
                    var foot = new Rect(lot.xMin + (gx > 0 ? 1.5f : 0f), lot.yMin + (gz > 0 ? 1.5f : 0f), lot.width - (gx > 0 ? 1.5f : 0f) - (gx < grid - 1 ? 1.5f : 0f), lot.height - (gz > 0 ? 1.5f : 0f) - (gz < grid - 1 ? 1.5f : 0f));
                    if (!edge && r.Chance(0.35f))
                    {
                        // courtyard: clutter, steam
                        if (r.Chance(0.5f)) steamVents.Add(new Vector3(foot.center.x, Kerb, foot.center.y));
                        if (slum && r.Chance(0.5f)) AddFireBarrel(c, new Vector3(foot.center.x + 2, Kerb, foot.center.y));
                        continue;
                    }
                    float h = Mathf.Lerp(minH, maxH, Mathf.Pow(r.Value, 1.6f));
                    if (b.district == District.NeonStrip && edge && r.Chance(0.15f)) h *= 1.6f;
                    var facade = upper == FacadeStyle.Slum && r.Chance(0.3f) ? M.Facade(FacadeStyle.Residential, r) : M.Facade(upper, r);
                    float y0 = Kerb;
                    if (shops && edge)
                    {
                        Building(c, new Vector3(foot.xMin, y0, foot.yMin), new Vector3(foot.xMax, y0 + 4.5f, foot.yMax), r.Pick(M.shopfronts), new Vector2(10, 4.65f), true, r);
                        y0 += 4.5f;
                    }
                    var top = new Vector3(foot.xMax, h, foot.yMax);
                    Building(c, new Vector3(foot.xMin, y0, foot.yMin), top, facade, tile, true, r);
                    // street-facing details
                    if (edge) DecorateFacades(b, c, r, foot, h, slum);
                    Rooftop(c, r, foot, h, slum);
                }
        }

        void DecorateFacades(Block b, Chunk c, Rng r, Rect foot, float h, bool slum)
        {
            var s = b.build;
            var sides = new List<int>();
            if (Mathf.Abs(foot.yMin - s.yMin) < 0.1f) sides.Add(0);
            if (Mathf.Abs(foot.xMax - s.xMax) < 0.1f) sides.Add(1);
            if (Mathf.Abs(foot.yMax - s.yMax) < 0.1f) sides.Add(2);
            if (Mathf.Abs(foot.xMin - s.xMin) < 0.1f) sides.Add(3);
            var palette = slum ? Palette.SlumNeon : Palette.MarketNeon;
            foreach (int side in sides)
            {
                GetFace(foot, side, out var a, out var bpt, out var n);
                float len = Vector3.Distance(a, bpt);
                var dir = (bpt - a).normalized;
                // awning over shopfront
                var awn = r.Pick(M.awnings);
                var mid = (a + bpt) * 0.5f;
                var awnCenter = mid + n * 1.1f + Vector3.up * (Kerb + 4.1f);
                var rot = Quaternion.LookRotation(n) * Quaternion.Euler(-18f, 0, 0);
                c.detailMB.SimpleBox(awnCenter, new Vector3(len * 0.9f, 0.08f, 2.4f), awn, rot);
                // horizontal shop sign
                AddSign(c, r, mid + n * 0.25f + Vector3.up * (Kerb + 5.3f), n, Mathf.Min(len * 0.7f, 7f), 1.3f, r.Range(0, 128));
                // vertical blade signs sticking out into the street
                int blades = Mathf.Clamp((int)(len / 8f), 1, 3);
                for (int i = 0; i < blades; i++)
                {
                    if (!r.Chance(slum ? 0.5f : 0.8f)) continue;
                    float t = (i + 0.5f) / blades;
                    float bh = r.Range(4f, Mathf.Min(14f, h - 8f));
                    if (bh < 3f) continue;
                    var bp = a + dir * (len * t) + n * 1.1f + Vector3.up * (Kerb + 6f + bh * 0.5f);
                    int idx = r.Range(0, Tex.VertCols);
                    float bw = Mathf.Clamp(bh / 6.5f, 0.7f, 1.8f);
                    c.detailMB.SimpleBox(bp, new Vector3(0.18f, bh + 0.3f, bw + 0.15f), M.metalDark, Quaternion.LookRotation(n));
                    c.detailMB.Panel(M.signsVertical, bp + dir * 0.1f, dir, bw, bh, Tex.VerticalUV(idx));
                    c.detailMB.Panel(M.signsVertical, bp - dir * 0.1f, -dir, bw, bh, Tex.VerticalUV(idx));
                    var col = r.Pick(palette);
                    c.lights.Add(new LightAnchor { pos = bp + n * 2f, color = col, range = 12f, intensity = 2.2f, flicker = r.Chance(0.15f), nightOnly = true });
                }
                // AC units and pipes on upper floors
                int acs = (int)(len * h / 60f);
                for (int i = 0; i < acs; i++)
                {
                    var ap = a + dir * r.Range(1f, len - 1f) + Vector3.up * r.Range(6f, h - 1.5f) + n * 0.35f;
                    c.detailMB.SimpleBox(ap, new Vector3(0.9f, 0.6f, 0.6f), M.white, Quaternion.LookRotation(n));
                }
                if (slum && r.Chance(0.6f))
                {
                    // graffiti glow
                    var gp = a + dir * r.Range(2f, Mathf.Max(2.1f, len - 2f)) + Vector3.up * (Kerb + 2.2f) + n * 0.04f;
                    var gm = Mats.Cached("graf" + (r.Range(0, 6)), () => Mats.Additive(Color.white * 1.4f, Tex.Graffiti(r.Range(0, 6))));
                    c.detailMB.Panel(gm, gp, n, 3.2f, 1.6f, new Rect(0, 0, 1, 1));
                }
                // vendor kiosks along market sidewalks
                if (b.district == District.NeonStrip && r.Chance(0.12f) || b.district == District.Lowtown && r.Chance(0.06f))
                {
                    var kp = mid + n * 1.6f + Vector3.up * Kerb;
                    vendors.Add(new VendorSpot { pos = kp, facing = n, shopId = "food", name = r.Pick("Rosa", "Big Mike", "Dee", "Uncle Ray", "Luz", "Benny", "Marisol"), look = r.Range(0, 99) });
                    StallVisual(c, kp, n, r);
                }
            }
        }

        void GetFace(Rect foot, int side, out Vector3 a, out Vector3 b, out Vector3 n)
        {
            switch (side)
            {
                case 0: a = new Vector3(foot.xMin, 0, foot.yMin); b = new Vector3(foot.xMax, 0, foot.yMin); n = Vector3.back; break;
                case 1: a = new Vector3(foot.xMax, 0, foot.yMin); b = new Vector3(foot.xMax, 0, foot.yMax); n = Vector3.right; break;
                case 2: a = new Vector3(foot.xMax, 0, foot.yMax); b = new Vector3(foot.xMin, 0, foot.yMax); n = Vector3.forward; break;
                default: a = new Vector3(foot.xMin, 0, foot.yMax); b = new Vector3(foot.xMin, 0, foot.yMin); n = Vector3.left; break;
            }
        }

        void Rooftop(Chunk c, Rng r, Rect foot, float h, bool slum)
        {
            int n = r.Range(1, 4);
            for (int i = 0; i < n; i++)
            {
                var p = new Vector3(r.Range(foot.xMin + 2, foot.xMax - 2), h, r.Range(foot.yMin + 2, foot.yMax - 2));
                int kind = r.Range(0, slum ? 4 : 3);
                switch (kind)
                {
                    case 0: c.staticMB.SimpleBox(p + Vector3.up * 0.8f, new Vector3(2.5f, 1.6f, 1.8f), M.metal); break;
                    case 1: c.staticMB.Cylinder(M.rust, p, 1.4f, 3f, 8); c.staticMB.Box(p + new Vector3(-0.1f, -0.01f, -0.1f), p + new Vector3(0.1f, 0.01f, 0.1f), M.metal, M.metal, Vector2.one); break;
                    case 2:
                        c.staticMB.Box(p + new Vector3(-0.15f, 0, -0.15f), p + new Vector3(0.15f, r.Range(4f, 9f), 0.15f), M.metalDark, M.metalDark, Vector2.one);
                        break;
                    default:
                        // stacked shack
                        var sm = M.Facade(FacadeStyle.Slum, r);
                        var size = new Vector3(r.Range(3f, 6f), r.Range(2.5f, 3.5f), r.Range(3f, 6f));
                        var mn = new Vector3(Mathf.Clamp(p.x - size.x * 0.5f, foot.xMin, foot.xMax - size.x), h, Mathf.Clamp(p.z - size.z * 0.5f, foot.yMin, foot.yMax - size.z));
                        Building(c, mn, mn + size, sm, M.FacadeTile(FacadeStyle.Slum), false, r);
                        break;
                }
            }
            if (!slum && r.Chance(0.25f) && foot.width > 12f)
            {
                // rooftop billboard on a frame
                var bp = new Vector3(foot.center.x, h + 7f, foot.center.y);
                bool alongX = r.Chance(0.5f);
                var nrm = alongX ? Vector3.back : Vector3.left;
                c.staticMB.Box(bp + new Vector3(-0.3f, -7f, -0.3f), bp + new Vector3(0.3f, -2f, 0.3f), M.metalDark, M.metalDark, Vector2.one);
                c.staticMB.Panel(M.ads, bp + nrm * 0.1f, nrm, 14f, 7f, Tex.AdUV(r.Range(0, 8)));
                c.staticMB.Panel(M.ads, bp - nrm * 0.1f, -nrm, 14f, 7f, Tex.AdUV(r.Range(0, 8)));
            }
        }

        void AddSign(Chunk c, Rng r, Vector3 center, Vector3 normal, float w, float h, int atlasIndex)
        {
            c.detailMB.Panel(M.signs, center, normal, w, h, Tex.SignUV(atlasIndex));
            c.detailMB.SimpleBox(center - normal * 0.12f, new Vector3(w + 0.3f, h + 0.3f, 0.2f), M.metalDark, Quaternion.LookRotation(normal));
        }

        void StallVisual(Chunk c, Vector3 p, Vector3 n, Rng r)
        {
            var rot = Quaternion.LookRotation(n);
            var right = rot * Vector3.right;
            c.detailMB.SimpleBox(p + Vector3.up * 0.5f, new Vector3(2.4f, 1f, 0.9f), M.metalDark, rot);
            c.detailMB.SimpleBox(p + Vector3.up * 1.02f, new Vector3(2.5f, 0.06f, 1f), M.chrome, rot);
            c.detailMB.SimpleBox(p + Vector3.up * 2.4f - n * 0.3f, new Vector3(2.8f, 0.06f, 1.8f), r.Pick(M.awnings), rot * Quaternion.Euler(-10f, 0, 0));
            for (int i = -1; i <= 1; i += 2)
                c.detailMB.SimpleBox(p + right * 1.3f * i + Vector3.up * 1.2f - n * 0.6f, new Vector3(0.08f, 2.4f, 0.08f), M.metalDark, rot);
            var lc = r.Pick(Palette.MarketNeon);
            c.detailMB.SimpleBox(p + Vector3.up * 2.2f + n * 0.4f, new Vector3(0.35f, 0.45f, 0.35f), M.Neon(lc, 3f), rot);
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 2.1f + n * 0.8f, color = lc, range = 7f, intensity = 2f });
            c.AddRotatedCollider(p + Vector3.up * 0.5f, new Vector3(2.4f, 1f, 0.9f), rot);
        }

        void AddFireBarrel(Chunk c, Vector3 p)
        {
            c.detailMB.Cylinder(M.rust, p, 0.35f, 0.95f, 8);
            c.AddCollider(p + new Vector3(-0.35f, 0, -0.35f), p + new Vector3(0.35f, 0.95f, 0.35f));
            fireBarrels.Add(p + Vector3.up * 0.95f);
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 1.6f, color = new Color(1f, 0.5f, 0.15f), range = 9f, intensity = 2.2f, flicker = true });
        }

        void BuildDocksBlock(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            var ind = M.FacadeTile(FacadeStyle.Industrial);
            if (r.Chance(0.6f))
            {
                // warehouse + small yard
                var foot = new Rect(s.xMin + 2, s.yMin + 2, s.width * r.Range(0.55f, 0.8f), s.height * r.Range(0.5f, 0.85f));
                float h = r.Range(10f, 18f);
                Building(c, new Vector3(foot.xMin, Kerb, foot.yMin), new Vector3(foot.xMax, h, foot.yMax), M.Facade(FacadeStyle.Industrial, r), ind, true, r);
                // loading doors + sodium lamps
                for (float x = foot.xMin + 6; x < foot.xMax - 4; x += 12f)
                {
                    c.detailMB.SimpleBox(new Vector3(x, Kerb + 2.5f, foot.yMin - 0.05f), new Vector3(5f, 5f, 0.1f), M.ribbed);
                    c.detailMB.SimpleBox(new Vector3(x, Kerb + 6.2f, foot.yMin - 0.4f), new Vector3(0.8f, 0.25f, 0.6f), M.lampSodium);
                    c.lights.Add(new LightAnchor { pos = new Vector3(x, Kerb + 5.5f, foot.yMin - 1.5f), color = Palette.Sodium, range = 14f, intensity = 2f, nightOnly = true });
                }
                ContainerYard(c, r, new Rect(foot.xMax + 3, s.yMin + 2, s.xMax - foot.xMax - 5, s.height - 4));
            }
            else
            {
                ContainerYard(c, r, Shrink(s, 2f));
                if (r.Chance(0.5f)) Crane(c, r, s);
            }
        }

        void ContainerYard(Chunk c, Rng r, Rect area)
        {
            if (area.width < 4 || area.height < 4) return;
            const float L = 12.2f, W = 2.45f, H = 2.6f;
            bool alongX = area.width > area.height;
            int rows = Mathf.FloorToInt((alongX ? area.height : area.width) / (W + 2.2f));
            int cols = Mathf.FloorToInt((alongX ? area.width : area.height) / (L + 1.5f));
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                {
                    if (r.Chance(0.25f)) continue;
                    int stack = r.Range(1, 5);
                    for (int k = 0; k < stack; k++)
                    {
                        Vector3 mn, mx;
                        if (alongX)
                        {
                            mn = new Vector3(area.xMin + j * (L + 1.5f), Kerb + k * H, area.yMin + i * (W + 2.2f));
                            mx = mn + new Vector3(L, H, W);
                        }
                        else
                        {
                            mn = new Vector3(area.xMin + i * (W + 2.2f), Kerb + k * H, area.yMin + j * (L + 1.5f));
                            mx = mn + new Vector3(W, H, L);
                        }
                        Building(c, mn, mx, r.Pick(M.containers), new Vector2(2.5f, 2.6f), true, r);
                    }
                }
        }

        void Crane(Chunk c, Rng r, Rect s)
        {
            float h = r.Range(28f, 40f);
            var a = new Vector3(s.xMin + 4, Kerb, s.center.y);
            var b = new Vector3(s.xMax - 4, Kerb, s.center.y);
            foreach (var p in new[] { a + Vector3.forward * 8, a - Vector3.forward * 8, b + Vector3.forward * 8, b - Vector3.forward * 8 })
                Building(c, p - new Vector3(0.8f, 0, 0.8f), p + new Vector3(0.8f, h, 0.8f), M.craneOrange, Vector2.one * 3, true, r);
            c.staticMB.Box(new Vector3(a.x - 2, h, a.z - 9), new Vector3(b.x + 2, h + 3, a.z + 9), M.craneOrange, M.craneOrange, Vector2.one * 3);
            c.staticMB.SimpleBox(new Vector3(a.x, h + 3.5f, a.z), Vector3.one, M.blinkRed);
            c.staticMB.SimpleBox(new Vector3(b.x, h + 3.5f, b.z), Vector3.one, M.blinkRed);
        }

        void BuildScarBlock(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            var tile = M.FacadeTile(FacadeStyle.Ruin);
            int n = r.Range(2, 5);
            for (int i = 0; i < n; i++)
            {
                float w = r.Range(12f, 26f), d = r.Range(12f, 26f);
                var mn = new Vector3(r.Range(s.xMin, s.xMax - w), Kerb, r.Range(s.yMin, s.yMax - d));
                float h = r.Range(8f, 45f);
                var fac = M.Facade(FacadeStyle.Ruin, r);
                // main hulk then a jagged broken top
                float solid = h * r.Range(0.5f, 0.8f);
                Building(c, mn, new Vector3(mn.x + w, solid, mn.z + d), fac, tile, true, r);
                int shards = r.Range(2, 5);
                for (int k = 0; k < shards; k++)
                {
                    float sw = r.Range(2f, w * 0.5f), sd = r.Range(2f, d * 0.5f);
                    var smn = new Vector3(r.Range(mn.x, mn.x + w - sw), solid, r.Range(mn.z, mn.z + d - sd));
                    Building(c, smn, smn + new Vector3(sw, r.Range(2f, h - solid + 1f), sd), fac, tile, true, r);
                }
                // rubble
                for (int k = 0; k < 6; k++)
                {
                    var rp = new Vector3(r.Range(mn.x - 3, mn.x + w + 3), Kerb + 0.3f, r.Range(mn.z - 3, mn.z + d + 3));
                    var size = new Vector3(r.Range(0.6f, 2.5f), r.Range(0.4f, 1.2f), r.Range(0.6f, 2.5f));
                    var rot = Quaternion.Euler(r.Range(-20f, 20f), r.Range(0f, 360f), r.Range(-20f, 20f));
                    c.detailMB.SimpleBox(rp, size, M.lotConcrete, rot);
                    if (size.x > 1.5f) c.AddRotatedCollider(rp, size, rot);
                }
            }
            for (int k = 0; k < 3; k++) if (r.Chance(0.5f)) AddFireBarrel(c, new Vector3(r.Range(s.xMin, s.xMax), Kerb, r.Range(s.yMin, s.yMax)));
            if (r.Chance(0.6f)) Wreck(c, r, new Vector3(r.Range(s.xMin + 3, s.xMax - 3), Kerb, r.Range(s.yMin + 3, s.yMax - 3)));
        }

        void Wreck(Chunk c, Rng r, Vector3 p)
        {
            var rot = Quaternion.Euler(r.Range(-8f, 8f), r.Range(0f, 360f), r.Range(-25f, 25f));
            var body = new Vector3(2f, 1f, 4.5f);
            c.detailMB.SimpleBox(p + Vector3.up * 0.7f, body, M.rust, rot);
            c.detailMB.SimpleBox(p + Vector3.up * 1.5f + rot * new Vector3(0, 0, -0.3f), new Vector3(1.8f, 0.7f, 2.2f), M.black, rot);
            c.AddRotatedCollider(p + Vector3.up * 0.8f, new Vector3(2f, 1.6f, 4.5f), rot);
        }

        void BuildPlaza(Block b, Chunk c, Rng r)
        {
            var ctr = new Vector3(b.outer.center.x, Kerb, b.outer.center.y);
            // fountain
            c.staticMB.Cylinder(M.lotConcrete, ctr, 9f, 0.7f, 24);
            c.staticMB.Cylinder(M.water, ctr + Vector3.up * 0.01f, 8.4f, 0.75f, 24, true);
            c.AddCollider(ctr + new Vector3(-8, 0, -8), ctr + new Vector3(8, 0.7f, 8));
            // giant hologram above the fountain
            var holo = new GameObject("PlazaHologram");
            holo.transform.SetParent(c.detailGo.transform, false);
            holo.transform.position = ctr + Vector3.up * 2f;
            var hm = new MeshBuilder();
            for (int i = 0; i < 6; i++)
                hm.Cylinder(M.holo, new Vector3(0, i * 3.2f, 0), 4.5f - i * 0.5f, 0.35f, 24, false);
            hm.SimpleBox(new Vector3(0, 10, 0), new Vector3(1.6f, 16f, 1.6f), M.holo);
            hm.BuildObject("Rings", holo.transform, false);
            holo.AddComponent<Spinner>().speed = 18f;
            holograms.Add(holo.transform);
            c.lights.Add(new LightAnchor { pos = ctr + Vector3.up * 8f, color = Palette.Cyan, range = 30f, intensity = 2.5f });
            // planters with synthetic trees + benches
            for (int i = 0; i < 8; i++)
            {
                float a = i / 8f * Mathf.PI * 2;
                var p = ctr + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * 22f;
                SynthTree(c, p, r);
                var bp = ctr + new Vector3(Mathf.Cos(a + 0.4f), 0, Mathf.Sin(a + 0.4f)) * 16f;
                var rot = Quaternion.LookRotation((ctr - bp).normalized);
                c.detailMB.SimpleBox(bp + Vector3.up * 0.45f, new Vector3(2.2f, 0.12f, 0.6f), M.wood, rot);
                c.detailMB.SimpleBox(bp + Vector3.up * 0.2f, new Vector3(2.0f, 0.4f, 0.4f), M.metalDark, rot);
            }
            // flanking low towers so the block isn't empty
            var s = b.build;
            Building(c, new Vector3(s.xMin, Kerb, s.yMin), new Vector3(s.xMin + 14, 40, s.yMin + 14), M.Facade(FacadeStyle.Glass, r), M.FacadeTile(FacadeStyle.Glass), true, r);
            Building(c, new Vector3(s.xMax - 14, Kerb, s.yMax - 14), new Vector3(s.xMax, 55, s.yMax), M.Facade(FacadeStyle.Glass, r), M.FacadeTile(FacadeStyle.Glass), true, r);
        }

        void SynthTree(Chunk c, Vector3 p, Rng r)
        {
            c.detailMB.Cylinder(M.lotConcrete, p, 1.6f, 0.6f, 10);
            c.detailMB.Cylinder(M.metalDark, p + Vector3.up * 0.6f, 0.18f, 3.2f, 6);
            var leaf = M.Neon(r.Chance(0.5f) ? Palette.Magenta : Palette.Cyan, 1.4f);
            for (int k = 0; k < 4; k++)
                c.detailMB.SimpleBox(p + Vector3.up * (3.3f + k * 0.35f), new Vector3(2.6f - k * 0.5f, 0.12f, 2.6f - k * 0.5f), leaf, Quaternion.Euler(0, k * 22f, 0));
            c.AddCollider(p + new Vector3(-1.6f, 0, -1.6f), p + new Vector3(1.6f, 0.6f, 1.6f));
        }

        void BuildNightMarket(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            // rows of stalls with lantern strings overhead
            for (float z = s.yMin + 8; z < s.yMax - 6; z += 12f)
            {
                for (float x = s.xMin + 6; x < s.xMax - 4; x += 5f)
                {
                    var p = new Vector3(x, Kerb, z);
                    var n = ((int)((z - s.yMin) / 12f) % 2 == 0) ? Vector3.forward : Vector3.back;
                    StallVisual(c, p, n, r);
                    if (r.Chance(0.3f))
                        vendors.Add(new VendorSpot { pos = p + n * 0.1f, facing = n, shopId = "food", name = r.Pick("Rosa", "Big Mike", "Dee", "Uncle Ray", "Luz", "Benny", "Marisol", "Joy"), look = r.Range(0, 99) });
                }
                // lantern string
                for (float x = s.xMin + 2; x < s.xMax - 2; x += 2.5f)
                {
                    var lp = new Vector3(x, Kerb + 4.6f + Mathf.Sin(x * 0.5f) * 0.2f, z + 6f);
                    c.detailMB.SimpleBox(lp, new Vector3(0.4f, 0.5f, 0.4f), M.Neon(r.Pick(Palette.MarketNeon), 3f));
                }
                c.detailMB.SimpleBox(new Vector3(s.center.x, Kerb + 4.9f, z + 6f), new Vector3(s.width - 4, 0.04f, 0.04f), M.cable);
                c.lights.Add(new LightAnchor { pos = new Vector3(s.center.x, Kerb + 4f, z + 6f), color = Palette.Orange, range = 22f, intensity = 2f });
            }
            // surrounding buildings on two sides
            Building(c, new Vector3(s.xMin, Kerb, s.yMax - 10), new Vector3(s.xMax, 28, s.yMax), M.Facade(FacadeStyle.Residential, r), M.FacadeTile(FacadeStyle.Residential), true, r);
        }

        void MarkHome(Block b, Chunk c)
        {
            var loc = city.Loc("home");
            if (loc == null) return;
            // glowing entrance frame
            var p = loc.pos + loc.facing * -0.3f + Vector3.up * Kerb;
            var right = Vector3.Cross(Vector3.up, loc.facing);
            c.detailMB.SimpleBox(p + Vector3.up * 1.3f - loc.facing * 0.6f, new Vector3(2.2f, 2.6f, 0.2f), M.metalDark, Quaternion.LookRotation(loc.facing));
            c.detailMB.SimpleBox(p + Vector3.up * 2.75f - loc.facing * 0.5f, new Vector3(2.6f, 0.12f, 0.12f), M.Neon(Palette.Green, 4f), Quaternion.LookRotation(loc.facing));
            c.detailMB.Panel(M.signs, p + Vector3.up * 3.4f - loc.facing * 0.45f, loc.facing, 3f, 1f, Tex.SignUV(Tex.SignIndexForWord("HOTEL")));
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 2.6f + loc.facing * 1f, color = Palette.Green, range = 8f, intensity = 2f });
        }

        static Rect Shrink(Rect r, float d) => new Rect(r.xMin + d, r.yMin + d, Mathf.Max(1f, r.width - d * 2), Mathf.Max(1f, r.height - d * 2));

        // ------------------------------------------------------------------ street furniture
        void BuildStreetFurniture()
        {
            var r = new Rng(city.seed + 77);
            for (int bx = 0; bx < CityData.Grid; bx++)
                for (int bz = 0; bz < CityData.Grid; bz++)
                {
                    var b = city.blocks[bx, bz];
                    var o = b.outer;
                    var c = ChunkFor(new Vector3(o.center.x, 0, o.center.y));
                    for (int side = 0; side < 4; side++)
                    {
                        GetFace(new Rect(o.xMin + 0.7f, o.yMin + 0.7f, o.width - 1.4f, o.height - 1.4f), side, out var a, out var e, out var n);
                        float len = Vector3.Distance(a, e);
                        var dir = (e - a).normalized;
                        if (b.district != District.Scar || r.Chance(0.3f))
                        {
                            for (float t = 10f; t < len - 8f; t += 30f)
                            {
                                var p = a + dir * t + Vector3.up * Kerb;
                                StreetLight(c, p, n, b.district, r);
                            }
                        }
                        // bins, benches, vending machines, ATMs, hydrants
                        for (float t = 18f; t < len - 12f; t += r.Range(14f, 26f))
                        {
                            var p = a + dir * t - n * 2.6f + Vector3.up * Kerb;
                            var rot = Quaternion.LookRotation(n);
                            float roll = r.Value;
                            if (b.district == District.Scar) continue;
                            if (roll < 0.35f)
                            {
                                c.detailMB.SimpleBox(p + Vector3.up * 0.5f + n * 2.0f, new Vector3(0.6f, 1f, 0.6f), M.metalDark, rot);
                            }
                            else if (roll < 0.5f && b.district != District.Docks)
                            {
                                PropFactory.VendingMachine(c, p - n * 0.6f, n, M, r);
                            }
                            else if (roll < 0.58f && (b.district == District.Spire || b.district == District.NeonStrip))
                            {
                                PropFactory.Atm(c, p - n * 0.6f, n, M);
                            }
                            else if (roll < 0.7f)
                            {
                                c.detailMB.SimpleBox(p + Vector3.up * 0.45f + n * 1.5f, new Vector3(2.0f, 0.1f, 0.6f), M.wood, rot);
                                c.detailMB.SimpleBox(p + Vector3.up * 0.2f + n * 1.5f, new Vector3(1.8f, 0.4f, 0.35f), M.metalDark, rot);
                            }
                            else if (roll < 0.8f && b.district == District.Lowtown)
                            {
                                // trash pile
                                for (int k = 0; k < 4; k++)
                                    c.detailMB.SimpleBox(p + n * 2.4f + new Vector3(r.Range(-0.8f, 0.8f), 0.25f, r.Range(-0.8f, 0.8f)), Vector3.one * r.Range(0.4f, 0.8f), M.black, Quaternion.Euler(0, r.Range(0, 90f), 0));
                            }
                        }
                    }
                    // overhead cables across the street (east and north of each block)
                    if ((b.district == District.Lowtown || b.district == District.NeonStrip) && bx < CityData.Grid - 1)
                    {
                        for (int k = 0; k < 3; k++)
                        {
                            float z = r.Range(o.yMin + 5, o.yMax - 5), y = r.Range(7f, 11f);
                            var p0 = new Vector3(o.xMax - 1, y, z); var p1 = new Vector3(o.xMax + CityData.RoadW + 1, y, z + r.Range(-4f, 4f));
                            Cable(c, p0, p1, b.district == District.NeonStrip && r.Chance(0.5f), r);
                        }
                    }
                }

            // food stall vendors and steam vents become live objects later (CrowdSystem / Environment)
        }

        void Cable(Chunk c, Vector3 p0, Vector3 p1, bool lanterns, Rng r)
        {
            const int seg = 4;
            Vector3 prev = p0;
            for (int i = 1; i <= seg; i++)
            {
                float t = i / (float)seg;
                var p = Vector3.Lerp(p0, p1, t) + Vector3.down * Mathf.Sin(t * Mathf.PI) * 0.9f;
                var mid = (prev + p) * 0.5f;
                var d = p - prev;
                c.detailMB.SimpleBox(mid, new Vector3(0.05f, 0.05f, d.magnitude), M.cable, Quaternion.LookRotation(d));
                if (lanterns) c.detailMB.SimpleBox(p + Vector3.down * 0.3f, new Vector3(0.35f, 0.45f, 0.35f), M.Neon(r.Pick(Palette.MarketNeon), 3f));
                prev = p;
            }
        }

        void StreetLight(Chunk c, Vector3 p, Vector3 n, District d, Rng r)
        {
            // n points from the block towards the road
            Material head; Color col; float h;
            switch (d)
            {
                case District.Spire: head = M.lampCool; col = new Color(0.8f, 0.9f, 1f); h = 9f; break;
                case District.Docks: head = M.lampSodium; col = Palette.Sodium; h = 11f; break;
                case District.NeonStrip: head = M.Neon(r.Pick(Palette.MarketNeon), 3f); col = Color.Lerp(new Color(1f, 0.8f, 0.6f), Palette.Magenta, 0.3f); h = 7f; break;
                case District.Lowtown: head = M.lampSodium; col = Palette.Sodium; h = 7f; break;
                default: head = M.lampWarm; col = new Color(1f, 0.7f, 0.4f); h = 7f; break;
            }
            c.detailMB.Cylinder(M.metalDark, p, 0.12f, h, 6, false);
            c.detailMB.SimpleBox(p + Vector3.up * h + n * 1.1f, new Vector3(0.15f, 0.15f, 2.3f), M.metalDark, Quaternion.LookRotation(n));
            var lamp = p + Vector3.up * (h - 0.15f) + n * 2.1f;
            c.detailMB.SimpleBox(lamp, new Vector3(0.5f, 0.15f, 0.9f), head, Quaternion.LookRotation(n));
            // soft volumetric cone (four additive quads)
            float top = 0.3f, bot = 2.6f;
            var down = lamp + Vector3.down * (h - 0.4f);
            var right = Vector3.Cross(Vector3.up, n).normalized;
            Vector3[] tc = { lamp + (n + right) * top, lamp + (n - right) * top, lamp + (-n - right) * top, lamp + (-n + right) * top };
            Vector3[] bc = { down + (n + right) * bot, down + (n - right) * bot, down + (-n - right) * bot, down + (-n + right) * bot };
            if (d != District.Scar)
            {
                for (int i = 0; i < 4; i++)
                {
                    int j = (i + 1) % 4;
                    c.detailMB.Quad(M.lightCone, bc[i], tc[i], tc[j], bc[j], new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0));
                    c.detailMB.Quad(M.lightCone, bc[j], tc[j], tc[i], bc[i], new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0));
                }
            }
            c.lights.Add(new LightAnchor { pos = lamp + Vector3.down * 0.6f, color = col, range = h * 2.6f, intensity = 2.4f, flicker = d == District.Lowtown && r.Chance(0.2f), nightOnly = true });
            c.AddCollider(p + new Vector3(-0.15f, 0, -0.15f), p + new Vector3(0.15f, h, 0.15f));
        }

        // ------------------------------------------------------------------ perimeter, skyline, monorail
        void BuildPerimeter()
        {
            float m = CityData.WallMargin, S = city.Size, H = 85f, T = 10f;
            var wallMat = M.megaWall;
            var tile = new Vector2(12, 12);
            void Wall(Vector3 mn, Vector3 mx)
            {
                // split long walls across chunks
                var size = mx - mn;
                int pieces = Mathf.CeilToInt(Mathf.Max(size.x, size.z) / 150f);
                for (int i = 0; i < pieces; i++)
                {
                    Vector3 a = mn, b = mx;
                    if (size.x > size.z) { a.x = mn.x + size.x * i / pieces; b.x = mn.x + size.x * (i + 1) / pieces; }
                    else { a.z = mn.z + size.z * i / pieces; b.z = mn.z + size.z * (i + 1) / pieces; }
                    var c = ChunkFor((a + b) * 0.5f);
                    Building(c, a, b, wallMat, tile, true);
                    // light strip near the top
                    c.staticMB.Box(new Vector3(a.x - 0.2f, H - 6, a.z - 0.2f), new Vector3(b.x + 0.2f, H - 5, b.z + 0.2f), M.Neon(Palette.Red, 3f), null, Vector2.one);
                }
            }
            Wall(new Vector3(-m - T, 0, -m - T), new Vector3(S + m + T, H, -m));
            Wall(new Vector3(-m - T, 0, S + m), new Vector3(S + m + T, H, S + m + T));
            Wall(new Vector3(-m - T, 0, -m), new Vector3(-m, H, S + m));
            Wall(new Vector3(S + m, 0, -m), new Vector3(S + m + T, H, S + m));

            // canal water between the docks and the east wall, with a railing
            float wx0 = S + 20f, wx1 = S + m;
            for (float z = -m; z < S + m; z += 100f)
            {
                var c = ChunkFor(new Vector3((wx0 + wx1) * 0.5f, 0, z + 50f));
                c.staticMB.Floor(M.water, wx0, z, wx1, Mathf.Min(z + 100f, S + m), 0.02f, new Vector2(20, 20));
                c.staticMB.Box(new Vector3(wx0 - 0.3f, 0, z), new Vector3(wx0, 1.1f, Mathf.Min(z + 100f, S + m)), M.metalDark, M.metalDark, Vector2.one);
                c.AddCollider(new Vector3(wx0 - 0.3f, 0, z), new Vector3(wx0, 1.4f, Mathf.Min(z + 100f, S + m)));
            }
        }

        void BuildSkyline()
        {
            // Unreachable silhouettes beyond the megawall make the city feel endless.
            var r = new Rng(city.seed + 999);
            var mb = new MeshBuilder();
            var center = city.Center;
            for (int i = 0; i < 90; i++)
            {
                float a = r.Range(0f, Mathf.PI * 2);
                float dist = city.Size * 0.5f + CityData.WallMargin + r.Range(120f, 700f);
                var p = center + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * dist;
                float w = r.Range(25f, 70f), h = r.Range(90f, 420f);
                var fac = M.Facade(r.Chance(0.5f) ? FacadeStyle.Glass : FacadeStyle.Office, r);
                mb.Box(p - new Vector3(w * 0.5f, 0, w * 0.5f), p + new Vector3(w * 0.5f, h, w * 0.5f), fac, M.roof, M.FacadeTile(FacadeStyle.Office));
                mb.SimpleBox(p + Vector3.up * (h + 2f), Vector3.one * 2f, M.blinkRed);
            }
            var go = mb.BuildObject("Skyline", root, false);
        }

        void BuildMonorail()
        {
            float z = 9 * CityData.Cell, y = 16f;
            for (float x = 0; x <= city.Size; x += 50f)
            {
                var c = ChunkFor(new Vector3(x, 0, z));
                if (Mathf.Abs(x % CityData.Cell) < 1f) continue; // keep intersections clear
                Building(c, new Vector3(x - 0.9f, 0, z + 9.2f), new Vector3(x + 0.9f, y, z + 11f), M.lotConcrete, new Vector2(4, 4));
            }
            for (float x = 0; x < city.Size; x += 100f)
            {
                var c = ChunkFor(new Vector3(x + 50, 0, z));
                c.staticMB.Box(new Vector3(x, y, z + 8.6f), new Vector3(x + 100f, y + 1.2f, z + 11.6f), M.lotConcrete, M.metalDark, new Vector2(4, 4));
                c.staticMB.Box(new Vector3(x, y - 0.2f, z + 8.5f), new Vector3(x + 100f, y, z + 11.7f), M.Neon(Palette.Cyan, 2.5f), null, Vector2.one);
            }
            var train = new GameObject("MonorailTrain");
            train.transform.SetParent(root, false);
            var mb = new MeshBuilder();
            for (int i = 0; i < 4; i++)
            {
                float x0 = i * 16.5f;
                mb.SimpleBox(new Vector3(x0 + 8f, 2f, 0), new Vector3(16f, 3.2f, 3.2f), M.white);
                mb.SimpleBox(new Vector3(x0 + 8f, 2.4f, 1.62f), new Vector3(14f, 1f, 0.05f), M.Neon(new Color(1f, 0.9f, 0.7f), 2.5f));
                mb.SimpleBox(new Vector3(x0 + 8f, 2.4f, -1.62f), new Vector3(14f, 1f, 0.05f), M.Neon(new Color(1f, 0.9f, 0.7f), 2.5f));
                mb.SimpleBox(new Vector3(x0 + 8f, 0.45f, 0), new Vector3(16f, 0.15f, 3.25f), M.Neon(Palette.Magenta, 3f));
            }
            mb.BuildObject("Cars", train.transform, true);
            var mr = train.AddComponent<Monorail>();
            mr.a = new Vector3(-80f, y + 1.2f, z + 10.1f);
            mr.b = new Vector3(city.Size + 10f, y + 1.2f, z + 10.1f);
        }
    }

    public class Spinner : MonoBehaviour
    {
        public float speed = 20f;
        public Vector3 axis = Vector3.up;
        void Update() => transform.Rotate(axis, speed * Time.deltaTime, Space.World);
    }

    public class Monorail : MonoBehaviour
    {
        public Vector3 a, b;
        public float speed = 22f;
        float t;
        int dir = 1;
        AudioSource src;

        void Start()
        {
            if (Game.Audio != null) src = Game.Audio.AttachLoop(gameObject, "train", 0.8f, 30f, 260f);
        }

        void Update()
        {
            float len = Vector3.Distance(a, b);
            t += dir * speed * Time.deltaTime / len;
            if (t > 1f) { t = 1f; dir = -1; }
            if (t < 0f) { t = 0f; dir = 1; }
            transform.position = Vector3.Lerp(a, b, t);
            transform.rotation = Quaternion.identity;
        }
    }
}
