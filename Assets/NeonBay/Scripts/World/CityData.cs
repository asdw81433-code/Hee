using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum District { Spire, NeonStrip, Lowtown, Docks, Scar }

    public enum LocType
    {
        Home, Fixer, GunShop, Clinic, NetShop, CarDealer, Bar, Food, Metro, Mission, Race, FightRing,
        BountyBoard, Landmark, Hideout, Shard, Vendor
    }

    public class Location
    {
        public string id, name;
        public Vector3 pos;
        public Vector3 facing = Vector3.forward; // direction from the building towards the street
        public float radius = 15f;
        public District district;
        public LocType type;
        public bool discovered;
        public bool showOnMap = true;
        public int bx = -1, bz = -1;
    }

    public class Block
    {
        public int bx, bz;
        public District district;
        public Rect outer;   // block footprint between road edges (includes sidewalks)
        public Rect build;   // buildable area inside sidewalks
        public string special; // reserved for a story/activity structure
        public bool plaza;
    }

    /// <summary>Layout of Neon Bay: a grid of blocks split into five districts.</summary>
    public class CityData
    {
        public const int Grid = 18;
        public const float Cell = 100f;
        public const float RoadW = 14f;
        public const float SidewalkW = 4f;
        public const float WallMargin = 70f;

        public readonly int seed;
        public readonly Block[,] blocks = new Block[Grid, Grid];
        public readonly Dictionary<string, Location> locations = new Dictionary<string, Location>();
        public readonly List<Vector3> shardSpots = new List<Vector3>();
        public float Size => Grid * Cell;
        public Vector3 Center => new Vector3(Size * 0.5f, 0, Size * 0.5f);

        public CityData(int seed)
        {
            this.seed = seed;
            for (int x = 0; x < Grid; x++)
                for (int z = 0; z < Grid; z++)
                {
                    float x0 = x * Cell + RoadW * 0.5f, z0 = z * Cell + RoadW * 0.5f;
                    float s = Cell - RoadW;
                    blocks[x, z] = new Block
                    {
                        bx = x, bz = z,
                        district = ComputeDistrict(x, z),
                        outer = new Rect(x0, z0, s, s),
                        build = new Rect(x0 + SidewalkW, z0 + SidewalkW, s - SidewalkW * 2, s - SidewalkW * 2)
                    };
                }
            PlanLocations();
        }

        District ComputeDistrict(int bx, int bz)
        {
            float cx = (bx + 0.5f) / Grid, cz = (bz + 0.5f) / Grid;
            float n = (Tex.ValueNoise(bx * 0.45f, bz * 0.45f, seed) - 0.5f) * 0.12f;
            if (bx >= Grid - 3) return District.Docks;
            float dc = Vector2.Distance(new Vector2(cx, cz), new Vector2(0.48f, 0.56f)) + n;
            if (dc < 0.17f) return District.Spire;
            if (cz + n < 0.3f && cx > 0.5f) return District.Scar;
            if (cz + n < 0.46f && cx <= 0.52f) return District.Lowtown;
            return District.NeonStrip;
        }

        public static string DistrictName(District d)
        {
            switch (d)
            {
                case District.Spire: return "HELIX HEIGHTS";
                case District.NeonStrip: return "NEON STRIP";
                case District.Lowtown: return "LOWTOWN";
                case District.Docks: return "PORT MARROW";
                default: return "THE SCAR";
            }
        }

        public static Color DistrictColor(District d)
        {
            switch (d)
            {
                case District.Spire: return Palette.Cyan;
                case District.NeonStrip: return Palette.Magenta;
                case District.Lowtown: return Palette.Orange;
                case District.Docks: return Palette.Yellow;
                default: return Palette.Red;
            }
        }

        public bool InCity(Vector3 p) => p.x > -WallMargin && p.z > -WallMargin && p.x < Size + WallMargin && p.z < Size + WallMargin;

        public Block BlockAt(Vector3 p)
        {
            int bx = Mathf.FloorToInt(p.x / Cell), bz = Mathf.FloorToInt(p.z / Cell);
            if (bx < 0 || bz < 0 || bx >= Grid || bz >= Grid) return null;
            return blocks[bx, bz];
        }

        public District DistrictAt(Vector3 p)
        {
            int bx = Mathf.Clamp(Mathf.FloorToInt(p.x / Cell), 0, Grid - 1), bz = Mathf.Clamp(Mathf.FloorToInt(p.z / Cell), 0, Grid - 1);
            return blocks[bx, bz].district;
        }

        public Vector3 Intersection(int ix, int iz) => new Vector3(ix * Cell, 0, iz * Cell);

        public bool OnRoad(Vector3 p)
        {
            float mx = Mathf.Abs(p.x - Mathf.Round(p.x / Cell) * Cell);
            float mz = Mathf.Abs(p.z - Mathf.Round(p.z / Cell) * Cell);
            return (mx < RoadW * 0.5f || mz < RoadW * 0.5f) && InCity(p);
        }

        /// <summary>Nearest point on any road centre line; dir is the road direction.</summary>
        public Vector3 NearestRoadPoint(Vector3 p, out Vector3 dir)
        {
            float rx = Mathf.Clamp(Mathf.Round(p.x / Cell), 0, Grid) * Cell;
            float rz = Mathf.Clamp(Mathf.Round(p.z / Cell), 0, Grid) * Cell;
            float cx = Mathf.Clamp(p.x, 0, Size), cz = Mathf.Clamp(p.z, 0, Size);
            if (Mathf.Abs(p.x - rx) < Mathf.Abs(p.z - rz)) { dir = Vector3.forward; return new Vector3(rx, 0, cz); }
            dir = Vector3.right; return new Vector3(cx, 0, rz);
        }

        /// <summary>Point on a lane (right-hand traffic, US style) near p, facing along dir.</summary>
        public Vector3 LanePoint(Vector3 p, out Quaternion rot, int lane = 1)
        {
            var c = NearestRoadPoint(p, out var dir);
            var to = (p - c).Flat();
            var rightOfDir = Vector3.Cross(Vector3.up, dir);
            // p must end up on the right side of the travel direction (right-hand traffic)
            var travel = Vector3.Dot(to, rightOfDir) >= 0 ? dir : -dir;
            var l = Vector3.Cross(Vector3.up, travel);
            rot = Quaternion.LookRotation(travel);
            return c + l * (1.75f + lane * 3.5f);
        }

        /// <summary>Walking loop around a block, 2 m inside the kerb.</summary>
        public Vector3 SidewalkPoint(int bx, int bz, float t)
        {
            var r = blocks[bx, bz].outer;
            float inset = 2f;
            float x0 = r.xMin + inset, z0 = r.yMin + inset, x1 = r.xMax - inset, z1 = r.yMax - inset;
            float w = x1 - x0, h = z1 - z0, per = 2 * (w + h);
            float d = Mathf.Repeat(t, 1f) * per;
            if (d < w) return new Vector3(x0 + d, 0, z0);
            d -= w; if (d < h) return new Vector3(x1, 0, z0 + d);
            d -= h; if (d < w) return new Vector3(x1 - d, 0, z1);
            d -= w; return new Vector3(x0, 0, z1 - d);
        }

        public float SidewalkPerimeter(int bx, int bz)
        {
            var r = blocks[bx, bz].outer;
            return 2 * (r.width - 4f + r.height - 4f);
        }

        // ---------------------------------------------------------------- planning
        readonly HashSet<Vector2Int> reserved = new HashSet<Vector2Int>();

        Block FindBlock(District d, int nearX, int nearZ, bool reserve = true)
        {
            Block best = null; float bestD = float.MaxValue;
            for (int x = 0; x < Grid; x++)
                for (int z = 0; z < Grid; z++)
                {
                    var b = blocks[x, z];
                    if (b.district != d || reserved.Contains(new Vector2Int(x, z))) continue;
                    float dd = (x - nearX) * (x - nearX) + (z - nearZ) * (z - nearZ);
                    if (dd < bestD) { bestD = dd; best = b; }
                }
            if (best == null) best = blocks[Mathf.Clamp(nearX, 0, Grid - 1), Mathf.Clamp(nearZ, 0, Grid - 1)];
            if (reserve) reserved.Add(new Vector2Int(best.bx, best.bz));
            return best;
        }

        /// <summary>Location on the south sidewalk of a block (or another side) facing the street.</summary>
        Location AddFront(string id, string name, LocType type, Block b, int side = 0, float along = 0.5f, float radius = 12f)
        {
            var r = b.outer;
            Vector3 pos, facing;
            switch (side)
            {
                case 0: pos = new Vector3(Mathf.Lerp(r.xMin, r.xMax, along), 0, r.yMin + SidewalkW - 1.2f); facing = Vector3.back; break;
                case 1: pos = new Vector3(r.xMax - SidewalkW + 1.2f, 0, Mathf.Lerp(r.yMin, r.yMax, along)); facing = Vector3.right; break;
                case 2: pos = new Vector3(Mathf.Lerp(r.xMin, r.xMax, along), 0, r.yMax - SidewalkW + 1.2f); facing = Vector3.forward; break;
                default: pos = new Vector3(r.xMin + SidewalkW - 1.2f, 0, Mathf.Lerp(r.yMin, r.yMax, along)); facing = Vector3.left; break;
            }
            var loc = new Location { id = id, name = name, type = type, pos = pos, facing = facing, radius = radius, district = b.district, bx = b.bx, bz = b.bz };
            locations[id] = loc;
            return loc;
        }

        Location AddBlockCenter(string id, string name, LocType type, Block b, float radius)
        {
            var c = b.outer.center;
            var loc = new Location { id = id, name = name, type = type, pos = new Vector3(c.x, 0, c.y), radius = radius, district = b.district, bx = b.bx, bz = b.bz };
            locations[id] = loc;
            b.special = id;
            return loc;
        }

        void PlanLocations()
        {
            var rng = new Rng(seed + 404);

            // Signature structures that take a whole block
            AddBlockCenter("helix_tower", "Helix Spire HQ", LocType.Landmark, FindBlock(District.Spire, 8, 10), 45f);
            AddBlockCenter("lotus_club", "Lotus Club", LocType.Bar, FindBlock(District.NeonStrip, 10, 15), 40f);
            AddBlockCenter("saints_hideout", "Static Saints Den", LocType.Hideout, FindBlock(District.Docks, 15, 3), 35f);
            AddBlockCenter("fight_ring", "The Pit (Fight Ring)", LocType.FightRing, FindBlock(District.Docks, 16, 6), 30f);
            AddBlockCenter("relay_1", "Comms Relay A", LocType.Mission, FindBlock(District.Docks, 16, 9), 35f);
            AddBlockCenter("relay_2", "Comms Relay B", LocType.Mission, FindBlock(District.Docks, 15, 13), 35f);
            AddBlockCenter("relay_3", "Comms Relay C", LocType.Mission, FindBlock(District.Docks, 17, 16), 35f);
            AddBlockCenter("jackal_den", "Jackal Den", LocType.Hideout, FindBlock(District.Lowtown, 1, 2), 40f);
            AddBlockCenter("scar_camp", "Raider Camp", LocType.Hideout, FindBlock(District.Scar, 13, 1), 45f);
            AddBlockCenter("night_market", "Bayside Night Market", LocType.Landmark, FindBlock(District.NeonStrip, 4, 13), 40f).showOnMap = true;
            AddBlockCenter("spire_plaza", "Unity Plaza", LocType.Landmark, FindBlock(District.Spire, 10, 9), 40f);
            blocks[locations["spire_plaza"].bx, locations["spire_plaza"].bz].plaza = true;
            blocks[locations["night_market"].bx, locations["night_market"].bz].plaza = true;

            // Story / service points on sidewalks
            var homeB = FindBlock(District.Lowtown, 6, 6);
            AddFront("home", "Your Apartment (Mega-Block 7)", LocType.Home, homeB, 2, 0.4f, 8f);
            homeB.special = "home";
            var maeB = FindBlock(District.NeonStrip, 5, 9);
            AddFront("mamasol", "Mama Sol's Diner (Fixer)", LocType.Fixer, maeB, 0, 0.35f, 8f);
            AddFront("clinic", "Doc Reyes' Clinic", LocType.Clinic, maeB, 1, 0.6f, 8f);
            AddFront("gunshop_market", "Big Sam's Guns", LocType.GunShop, FindBlock(District.NeonStrip, 3, 11, false), 1, 0.5f, 8f);
            AddFront("netshop", "Pixie's Wetware", LocType.NetShop, FindBlock(District.NeonStrip, 7, 13, false), 0, 0.5f, 8f);
            AddFront("cardealer", "Uncle Tony's Motors", LocType.CarDealer, FindBlock(District.Docks, 16, 11, false), 3, 0.5f, 10f);
            AddFront("gunshop_docks", "Dockside Arms", LocType.GunShop, FindBlock(District.Docks, 15, 8, false), 3, 0.3f, 8f);
            AddFront("clinic_spire", "Helix MedCenter", LocType.Clinic, FindBlock(District.Spire, 7, 8, false), 0, 0.5f, 8f);
            AddFront("bar_rust", "The Rusty Lantern", LocType.Bar, FindBlock(District.Lowtown, 3, 4, false), 2, 0.5f, 8f);
            AddFront("police_hq", "NBPD Precinct 12 (Bounties)", LocType.BountyBoard, FindBlock(District.Spire, 6, 9, false), 3, 0.5f, 8f);
            AddFront("fixer_dutch", "Dutch's Garage (Fixer)", LocType.Fixer, FindBlock(District.Docks, 15, 10, false), 3, 0.7f, 8f);
            AddFront("fixer_kit", "Kit's Pawn (Fixer)", LocType.Fixer, FindBlock(District.Lowtown, 4, 2, false), 2, 0.3f, 8f);
            AddFront("market_square", "Neon Crossing", LocType.Mission, FindBlock(District.NeonStrip, 6, 11, false), 2, 0.5f, 25f).showOnMap = false;

            // Race starts are on roads
            locations["race_1"] = new Location { id = "race_1", name = "Street Race: Neon Sprint", type = LocType.Race, pos = new Vector3(4 * Cell, 0, 12 * Cell + 30), facing = Vector3.forward, radius = 8f, district = District.NeonStrip };
            locations["race_2"] = new Location { id = "race_2", name = "Street Race: Dockline", type = LocType.Race, pos = new Vector3(15 * Cell, 0, 5 * Cell + 30), facing = Vector3.forward, radius = 8f, district = District.Docks };
            locations["race_3"] = new Location { id = "race_3", name = "Street Race: Scar Run", type = LocType.Race, pos = new Vector3(11 * Cell + 30, 0, 2 * Cell), facing = Vector3.right, radius = 8f, district = District.Scar };
            locations["convoy"] = new Location { id = "convoy", name = "Convoy Route", type = LocType.Mission, pos = new Vector3(12 * Cell, 0, 3 * Cell + 50), facing = Vector3.forward, radius = 40f, district = District.Scar, showOnMap = false };

            // Metro stations - fast travel
            var metroBlocks = new[]
            {
                (District.Lowtown, 5, 4), (District.NeonStrip, 4, 14), (District.Spire, 9, 8),
                (District.Docks, 16, 4), (District.Scar, 11, 3), (District.NeonStrip, 12, 16), (District.Docks, 16, 15)
            };
            int mi = 1;
            foreach (var (d, x, z) in metroBlocks)
            {
                var b = FindBlock(d, x, z, false);
                var l = AddFront("metro_" + mi, "Metro: " + DistrictName(d) + " " + mi, LocType.Metro, b, (mi % 4), 0.15f, 6f);
                mi++;
            }

            // Food stalls are generated by the city builder; collectibles on sidewalks
            for (int i = 0; i < 20; i++)
            {
                int bx = rng.Range(0, Grid), bz = rng.Range(0, Grid);
                var p = SidewalkPoint(bx, bz, rng.Value);
                // nudge towards the building line so they sit in alcoves
                var c = blocks[bx, bz].outer.center;
                var toC = (new Vector3(c.x, 0, c.y) - p).normalized;
                shardSpots.Add(p + toC * 1.4f + Vector3.up * 0.9f);
            }
        }

        public Location Loc(string id) => locations.TryGetValue(id, out var l) ? l : null;
    }
}
