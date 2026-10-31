using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Landmarks, mission sites, interiors and interactive props.</summary>
    public partial class CityGenerator
    {
        public readonly List<DataShard> shards = new List<DataShard>();
        public float helixRoofHeight;

        void AddLoc(string id, string name, Vector3 pos, LocType type, District d, float radius = 10f, bool show = false)
        {
            city.locations[id] = new Location { id = id, name = name, pos = pos, type = type, district = d, radius = radius, showOnMap = show };
        }

        void BuildSpecial(Block b, Chunk c)
        {
            var r = new Rng(city.seed * 13 + b.bx * 101 + b.bz * 37);
            switch (b.special)
            {
                case "helix_tower": HelixTower(b, c, r); break;
                case "lotus_club": LotusClub(b, c, r); break;
                case "saints_hideout": SaintsDen(b, c, r); break;
                case "fight_ring": FightRing(b, c, r); break;
                case "relay_1": case "relay_2": case "relay_3": Relay(b, c, r, b.special); break;
                case "jackal_den": JackalDen(b, c, r); break;
                case "scar_camp": RaiderCamp(b, c, r); break;
                case "night_market": BuildNightMarket(b, c, r); break;
                case "spire_plaza": BuildPlaza(b, c, r); break;
                default: BuildSpireBlock(b, c, r); break;
            }
        }

        // ------------------------------------------------------------------ Helix Spire HQ
        void HelixTower(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            var ctr = new Vector3(s.center.x, 0, s.center.y);
            float H = 340f;
            helixRoofHeight = H;
            var pod = Shrink(s, 2f);
            Building(c, new Vector3(pod.xMin, Kerb, pod.yMin), new Vector3(pod.xMax, Kerb + 4.5f, pod.yMax), M.shopfronts[0], new Vector2(10, 4.65f), true, r);
            Building(c, new Vector3(pod.xMin, Kerb + 4.5f, pod.yMin), new Vector3(pod.xMax, 18f, pod.yMax), M.facades[FacadeStyle.Office][0], M.FacadeTile(FacadeStyle.Office), true, r);
            var foot = new Rect(ctr.x - 22, ctr.z - 22, 44, 44);
            var glass = M.facades[FacadeStyle.Glass][0];
            var neon = M.Neon(Palette.Cyan, 4f);
            float y = 18f;
            float[] tiers = { 140f, 250f, H };
            foreach (var top in tiers)
            {
                var mn = new Vector3(foot.xMin, y, foot.yMin); var mx = new Vector3(foot.xMax, top, foot.yMax);
                Building(c, mn, mx, glass, M.FacadeTile(FacadeStyle.Glass), true, r);
                LedEdges(c, mn, mx, neon, 0.5f);
                c.staticMB.Box(new Vector3(foot.xMin - 0.4f, top - 1f, foot.yMin - 0.4f), new Vector3(foot.xMax + 0.4f, top, foot.yMax + 0.4f), neon, null, Vector2.one);
                y = top;
                if (top < H) foot = Shrink(foot, 3f);
            }
            // vertical HELIX sign on the south face
            c.staticMB.Panel(M.signs, new Vector3(ctr.x, 200f, foot.yMin - 3.2f), Vector3.back, 30f, 15f, Tex.SignUV(Tex.SignIndexForWord("HELIX")));
            c.staticMB.Panel(M.ads, new Vector3(ctr.x, 60f, foot.yMin - 6.2f), Vector3.back, 40f, 20f, Tex.AdUV(0));

            // Roof arena
            var roof = new Vector3(ctr.x, H, ctr.z);
            float half = foot.width * 0.5f;
            foreach (var (a, e) in new[]
            {
                (new Vector3(-half, 0, -half), new Vector3(half, 1.3f, -half + 0.5f)), (new Vector3(-half, 0, half - 0.5f), new Vector3(half, 1.3f, half)),
                (new Vector3(-half, 0, -half), new Vector3(-half + 0.5f, 1.3f, half)), (new Vector3(half - 0.5f, 0, -half), new Vector3(half, 1.3f, half))
            })
                Building(c, roof + a, roof + e, M.metalDark, Vector2.one * 2f, true, r);
            c.staticMB.Cylinder(M.lotConcrete, roof + new Vector3(6, 0, 6), 7f, 0.15f, 24);
            c.staticMB.Cylinder(M.Neon(Palette.Yellow, 3f), roof + new Vector3(6, 0.01f, 6), 6.3f, 0.16f, 24, false);
            for (int i = 0; i < 8; i++)
            {
                var p = roof + new Vector3(r.Range(-half + 3, half - 3), 0, r.Range(-half + 3, half - 3));
                if ((p - (roof + new Vector3(6, 0, 6))).sqrMagnitude < 64f) continue;
                Crate(c, p, r, true);
            }
            // uplink dish
            var dish = roof + new Vector3(-10, 0, -10);
            c.staticMB.Box(dish + new Vector3(-1, 0, -1), dish + new Vector3(1, 6, 1), M.metal, M.metal, Vector2.one);
            c.staticMB.Cylinder(M.white, dish + Vector3.up * 6f, 4f, 0.6f, 16);
            c.staticMB.SimpleBox(dish + Vector3.up * 7.5f, Vector3.one * 0.8f, M.Neon(Palette.Red, 5f));
            c.AddCollider(dish + new Vector3(-1, 0, -1), dish + new Vector3(1, 6, 1));
            var term = PropFactory.TerminalAt(c, dish + new Vector3(3, 0, 0), Vector3.right, M, "helix_uplink", 3);
            AddLoc("helix_roof", "Helix Spire Roof", roof + Vector3.up * 0.2f, LocType.Mission, District.Spire, 25f);
            AddLoc("helix_uplink", "Helix Uplink", dish + new Vector3(3, 0, 0), LocType.Mission, District.Spire, 4f);
            c.lights.Add(new LightAnchor { pos = roof + Vector3.up * 6f, color = Palette.Cyan, range = 40f, intensity = 2.5f });
            c.lights.Add(new LightAnchor { pos = dish + Vector3.up * 8f, color = Palette.Red, range = 20f, intensity = 2f, flicker = true });

            // elevator: lobby <-> roof
            var lobby = new Vector3(ctr.x, Kerb, pod.yMin - 1.4f);
            AddLoc("helix_lobby", "Helix Lobby", lobby, LocType.Mission, District.Spire, 6f);
            var up = Interactable.Create<Teleporter>("HelixElevator", c.detailGo.transform, lobby, new Vector3(2.2f, 2.6f, 0.8f), Vector3.back);
            up.prompt = "Elevator to Roof (Floor 88)";
            up.requiredFlag = "helix_access";
            up.lockedText = "Elevator locked - Helix clearance required";
            up.target = roof + new Vector3(0, 0.3f, half - 5f);
            up.targetYaw = 180f;
            up.id = "helix_elevator";
            c.detailMB.SimpleBox(lobby + Vector3.up * 1.4f + Vector3.forward * 0.45f, new Vector3(2.6f, 2.9f, 0.1f), M.chrome);
            c.detailMB.SimpleBox(lobby + Vector3.up * 3.05f + Vector3.forward * 0.4f, new Vector3(2.6f, 0.15f, 0.12f), neon);
            var down = Interactable.Create<Teleporter>("HelixElevatorDown", c.root.transform, roof + new Vector3(0, 0, half - 1.2f), new Vector3(2.2f, 2.6f, 0.8f), Vector3.back);
            down.prompt = "Elevator to Lobby";
            down.target = lobby + Vector3.back * 2.5f;
            down.targetYaw = 180f;
            c.staticMB.SimpleBox(roof + new Vector3(0, 1.4f, half - 0.9f), new Vector3(3f, 2.9f, 0.6f), M.chrome);
        }

        // ------------------------------------------------------------------ Lotus Club
        void LotusClub(Block b, Chunk c, Rng r)
        {
            var s = b.build;
            var resTile = M.FacadeTile(FacadeStyle.Residential);
            Building(c, new Vector3(s.xMin, Kerb, s.yMax - 16), new Vector3(s.xMax, 42f, s.yMax), M.facades[FacadeStyle.Residential][3], resTile, true, r);
            Building(c, new Vector3(s.xMin, Kerb, s.yMin + 10), new Vector3(s.xMin + 14, 34f, s.yMax - 16), M.Facade(FacadeStyle.Residential, r), resTile, true, r);
            Building(c, new Vector3(s.xMax - 14, Kerb, s.yMin + 10), new Vector3(s.xMax, 30f, s.yMax - 16), M.Facade(FacadeStyle.Residential, r), resTile, true, r);
            // giant LOTUS sign facing the street
            c.staticMB.Panel(M.signs, new Vector3(s.center.x, 30f, s.yMax - 16.2f), Vector3.back, 22f, 11f, Tex.SignUV(Tex.SignIndexForWord("LOTUS")));
            // dance floor
            var floorMin = new Vector3(s.xMin + 18, Kerb + 0.02f, s.yMin + 18);
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 6; j++)
                {
                    var col = Palette.Neon[(i + j * 3) % Palette.Neon.Length];
                    var p = floorMin + new Vector3(i * 3f, 0, j * 3f);
                    c.detailMB.Floor(M.Neon(col, 1.2f), p.x + 0.1f, p.z + 0.1f, p.x + 2.9f, p.z + 2.9f, Kerb + 0.03f, new Vector2(3, 3));
                }
            // stage + screen
            var stage = new Vector3(s.center.x, Kerb, s.yMax - 21f);
            Building(c, stage + new Vector3(-9, 0, -3), stage + new Vector3(9, 1.2f, 3), M.metalDark, Vector2.one * 2, true, r);
            c.detailMB.Panel(M.ads, stage + new Vector3(0, 7, 2.6f), Vector3.back, 16f, 8f, Tex.AdUV(3));
            c.detailMB.SimpleBox(stage + new Vector3(0, 1.8f, 0), new Vector3(3f, 1.2f, 1.2f), M.Neon(Palette.Magenta, 3f));
            // bar counter
            var bar = new Vector3(s.xMax - 18, Kerb, s.center.y);
            Building(c, bar + new Vector3(-1, 0, -8), bar + new Vector3(1, 1.1f, 8), M.black, Vector2.one, true, r);
            c.detailMB.SimpleBox(bar + new Vector3(0, 1.12f, 0), new Vector3(2.1f, 0.05f, 16.1f), M.Neon(Palette.Cyan, 2f));
            // VIP booth
            var vip = new Vector3(s.xMin + 18, Kerb, s.yMax - 22);
            Building(c, vip + new Vector3(-4, 0, -3), vip + new Vector3(4, 0.6f, 3), M.wood, Vector2.one, true, r);
            c.detailMB.SimpleBox(vip + new Vector3(0, 1.0f, 2.5f), new Vector3(7f, 0.8f, 0.8f), Lit(new Color(0.5f, 0.05f, 0.1f)));
            AddLoc("lotus_vip", "Lotus VIP Booth", vip + Vector3.up * 0.6f, LocType.Mission, District.NeonStrip, 6f);
            AddLoc("lotus_floor", "Lotus Dance Floor", floorMin + new Vector3(12, 0, 9), LocType.Mission, District.NeonStrip, 18f);
            for (int i = 0; i < 6; i++)
                c.lights.Add(new LightAnchor { pos = floorMin + new Vector3(i * 4.5f, 6f, 9f), color = Palette.Neon[i % Palette.Neon.Length], range = 16f, intensity = 3f, flicker = i % 2 == 0 });
            vendors.Add(new VendorSpot { pos = bar + new Vector3(1.8f, 0, 0), facing = Vector3.left, shopId = "bar", name = "Bartender Kai", npcId = "bartender_lotus", look = 7 });
        }

        Material Lit(Color c) => Mats.Cached("lit" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Lit(c, null, 0.3f));

        // ------------------------------------------------------------------ hollow warehouse helper
        Rect HollowWarehouse(Chunk c, Rng r, Vector3 ctr, float w, float d, float h, float doorW, out Vector3 door)
        {
            var mat = M.Facade(FacadeStyle.Industrial, r);
            var tile = M.FacadeTile(FacadeStyle.Industrial);
            float t = 0.6f;
            float x0 = ctr.x - w * 0.5f, x1 = ctr.x + w * 0.5f, z0 = ctr.z - d * 0.5f, z1 = ctr.z + d * 0.5f;
            // south wall with a door gap
            float dl = ctr.x - doorW * 0.5f, dr = ctr.x + doorW * 0.5f;
            Building(c, new Vector3(x0, Kerb, z0), new Vector3(dl, h, z0 + t), mat, tile, true, r);
            Building(c, new Vector3(dr, Kerb, z0), new Vector3(x1, h, z0 + t), mat, tile, true, r);
            Building(c, new Vector3(dl, 5f, z0), new Vector3(dr, h, z0 + t), mat, tile, true, r);
            Building(c, new Vector3(x0, Kerb, z1 - t), new Vector3(x1, h, z1), mat, tile, true, r);
            Building(c, new Vector3(x0, Kerb, z0), new Vector3(x0 + t, h, z1), mat, tile, true, r);
            Building(c, new Vector3(x1 - t, Kerb, z0), new Vector3(x1, h, z1), mat, tile, true, r);
            // roof (underside visible from inside)
            c.staticMB.Box(new Vector3(x0, h, z0), new Vector3(x1, h + 0.4f, z1), M.ribbed, M.roof, Vector2.one * 3, M.metalDark);
            c.AddCollider(new Vector3(x0, h, z0), new Vector3(x1, h + 0.4f, z1));
            c.staticMB.Floor(M.lotConcrete, x0, z0, x1, z1, Kerb + 0.01f, Tex.Concrete.tileMeters);
            door = new Vector3(ctr.x, Kerb, z0 - 1f);
            return new Rect(x0 + t, z0 + t, w - 2 * t, d - 2 * t);
        }

        // ------------------------------------------------------------------ Static Saints den
        void SaintsDen(Block b, Chunk c, Rng r)
        {
            var ctr = new Vector3(b.build.center.x, 0, b.build.center.y);
            var inside = HollowWarehouse(c, r, ctr, 52, 38, 12, 4f, out var door);
            // server racks
            for (int i = 0; i < 6; i++)
            {
                var p = new Vector3(inside.xMin + 6 + i * 6.5f, Kerb, inside.yMax - 4);
                Building(c, p + new Vector3(-1, 0, -0.6f), p + new Vector3(1, 2.4f, 0.6f), M.black, Vector2.one, true, r);
                for (int k = 0; k < 5; k++)
                    c.detailMB.SimpleBox(p + new Vector3(0, 0.4f + k * 0.42f, -0.62f), new Vector3(1.7f, 0.05f, 0.02f), M.Neon(k % 2 == 0 ? Palette.Cyan : Palette.Green, 3f));
            }
            // desks with screens
            for (int i = 0; i < 4; i++)
            {
                var p = new Vector3(inside.xMin + 8 + i * 9f, Kerb, inside.center.y);
                Building(c, p + new Vector3(-1.5f, 0, -0.6f), p + new Vector3(1.5f, 0.8f, 0.6f), M.metalDark, Vector2.one, true, r);
                c.detailMB.Panel(M.screen, p + new Vector3(0, 1.3f, 0.3f), Vector3.back, 1.4f, 0.8f, new Rect(0, 0, 1, 1));
            }
            // the core
            var core = new Vector3(inside.center.x, Kerb, inside.yMin + 8);
            c.staticMB.Cylinder(M.Neon(Palette.Cyan, 2.5f), core, 1.2f, 4f, 12);
            c.AddCollider(core + new Vector3(-1.2f, 0, -1.2f), core + new Vector3(1.2f, 4, 1.2f));
            c.lights.Add(new LightAnchor { pos = core + Vector3.up * 2f, color = Palette.Cyan, range = 20f, intensity = 3f });
            c.lights.Add(new LightAnchor { pos = new Vector3(inside.center.x, 8f, inside.yMax - 6), color = Palette.Green, range = 22f, intensity = 2f });
            c.detailMB.Panel(M.signs, door + new Vector3(0, 6.5f, 0.3f), Vector3.back, 5f, 1.4f, Tex.SignUV(Tex.SignIndexForWord("DATA")));
            AddLoc("saints_inside", "Static Saints Den", new Vector3(inside.center.x, Kerb, inside.center.y), LocType.Mission, District.Docks, 18f);
            AddLoc("saints_door", "Den Entrance", door, LocType.Mission, District.Docks, 5f);
            AddLoc("saints_core", "Saints Core", core + Vector3.back * 2f, LocType.Mission, District.Docks, 4f);
        }

        // ------------------------------------------------------------------ The Pit
        void FightRing(Block b, Chunk c, Rng r)
        {
            var ctr = new Vector3(b.build.center.x, 0, b.build.center.y);
            var inside = HollowWarehouse(c, r, ctr, 46, 46, 14, 5f, out var door);
            var ring = new Vector3(inside.center.x, Kerb, inside.center.y + 2);
            float hs = 5f;
            Building(c, ring + new Vector3(-hs, 0, -hs), ring + new Vector3(hs, 0.8f, hs), M.fabric, Vector2.one * 2, true, r);
            var rope = M.Neon(Palette.Red, 3f);
            foreach (var corner in new[] { new Vector3(-hs, 0, -hs), new Vector3(hs, 0, -hs), new Vector3(hs, 0, hs), new Vector3(-hs, 0, hs) })
                c.staticMB.Box(ring + corner + new Vector3(-0.15f, 0.8f, -0.15f), ring + corner + new Vector3(0.15f, 2.3f, 0.15f), M.metal, M.metal, Vector2.one);
            for (int k = 0; k < 3; k++)
            {
                float y = 1.2f + k * 0.4f;
                c.detailMB.SimpleBox(ring + new Vector3(0, y, -hs), new Vector3(hs * 2, 0.05f, 0.05f), rope);
                c.detailMB.SimpleBox(ring + new Vector3(0, y, hs), new Vector3(hs * 2, 0.05f, 0.05f), rope);
                c.detailMB.SimpleBox(ring + new Vector3(-hs, y, 0), new Vector3(0.05f, 0.05f, hs * 2), rope);
                c.detailMB.SimpleBox(ring + new Vector3(hs, y, 0), new Vector3(0.05f, 0.05f, hs * 2), rope);
            }
            // invisible ring walls so fighters stay in
            c.AddCollider(ring + new Vector3(-hs, 0.8f, -hs - 0.1f), ring + new Vector3(hs, 3f, -hs));
            c.AddCollider(ring + new Vector3(-hs, 0.8f, hs), ring + new Vector3(hs, 3f, hs + 0.1f));
            c.AddCollider(ring + new Vector3(-hs - 0.1f, 0.8f, -hs), ring + new Vector3(-hs, 3f, hs));
            c.AddCollider(ring + new Vector3(hs, 0.8f, -hs), ring + new Vector3(hs + 0.1f, 3f, hs));
            // bleachers
            for (int k = 0; k < 4; k++)
            {
                Building(c, new Vector3(inside.xMin + 1, Kerb, inside.yMax - 3 - k * 1.2f), new Vector3(inside.xMax - 1, Kerb + 0.5f + k * 0.5f, inside.yMax - 2 - k * 1.2f), M.wood, Vector2.one, true, r);
            }
            for (int i = 0; i < 4; i++)
                c.lights.Add(new LightAnchor { pos = ring + new Vector3(i < 2 ? -6 : 6, 9f, i % 2 == 0 ? -6 : 6), color = new Color(1f, 0.9f, 0.8f), range = 18f, intensity = 2.5f });
            c.detailMB.Panel(M.signs, door + new Vector3(0, 7f, 0.3f), Vector3.back, 5f, 1.4f, Tex.SignUV(Tex.SignIndexForWord("BOXING")));
            AddLoc("ring_center", "The Pit - Ring", ring + Vector3.up * 0.8f, LocType.FightRing, District.Docks, 5f);
            AddLoc("ring_spawn", "Ring corner", ring + new Vector3(-3.5f, 0.85f, -3.5f), LocType.FightRing, District.Docks, 2f);
            vendors.Add(new VendorSpot { pos = new Vector3(inside.xMin + 4, Kerb, inside.yMin + 4), facing = Vector3.forward, shopId = "ring", name = "Promoter Chaz", npcId = "ring_master", look = 11 });
        }

        // ------------------------------------------------------------------ comms relays
        void Relay(Block b, Chunk c, Rng r, string id)
        {
            var s = b.build;
            ContainerYard(c, r, new Rect(s.xMin + 2, s.yMin + 2, s.width - 4, s.height * 0.35f));
            ContainerYard(c, r, new Rect(s.xMin + 2, s.yMax - s.height * 0.3f, s.width - 4, s.height * 0.3f - 2));
            var ctr = new Vector3(s.center.x, Kerb, s.center.y);
            float h = 38f;
            foreach (var o in new[] { new Vector3(-2, 0, -2), new Vector3(2, 0, -2), new Vector3(2, 0, 2), new Vector3(-2, 0, 2) })
                Building(c, ctr + o + new Vector3(-0.25f, 0, -0.25f), ctr + o + new Vector3(0.25f, h, 0.25f), M.metal, Vector2.one, true, r);
            for (float y = 4; y < h; y += 5f) c.staticMB.Box(ctr + new Vector3(-2.2f, y, -2.2f), ctr + new Vector3(2.2f, y + 0.25f, 2.2f), M.metal, M.metal, Vector2.one);
            c.staticMB.Cylinder(M.white, ctr + Vector3.up * h, 3f, 0.5f, 12);
            c.staticMB.SimpleBox(ctr + Vector3.up * (h + 1.5f), Vector3.one, M.blinkRed);
            for (int i = 0; i < 10; i++)
                Crate(c, ctr + new Vector3(r.Range(-18f, 18f), 0, r.Range(-12f, 12f)), r, true);
            var termPos = ctr + new Vector3(0, 0, -3.5f);
            PropFactory.TerminalAt(c, termPos, Vector3.back, M, id, 1);
            AddLoc(id + "_terminal", "Relay Terminal", termPos, LocType.Mission, District.Docks, 4f);
            c.lights.Add(new LightAnchor { pos = ctr + Vector3.up * 6f, color = Palette.Sodium, range = 25f, intensity = 2.4f });
        }

        void Crate(Chunk c, Vector3 p, Rng r, bool collider)
        {
            var size = new Vector3(r.Range(1.2f, 2.4f), r.Range(0.9f, 1.4f), r.Range(1.2f, 2.4f));
            var rot = Quaternion.Euler(0, r.Range(0, 4) * 90f + r.Range(-10f, 10f), 0);
            var mat = r.Chance(0.5f) ? M.metalDark : M.containers[r.Range(0, M.containers.Length)];
            c.detailMB.SimpleBox(p + Vector3.up * size.y * 0.5f, size, mat, rot);
            c.detailMB.SimpleBox(p + Vector3.up * (size.y + 0.01f), new Vector3(size.x * 0.9f, 0.02f, 0.12f), M.hazard, rot);
            if (collider) c.AddRotatedCollider(p + Vector3.up * size.y * 0.5f, size, rot);
        }

        // ------------------------------------------------------------------ Jackal den & raider camp
        void ScrapWall(Chunk c, Rng r, Vector3 a, Vector3 b, float h)
        {
            var d = b - a; float len = d.magnitude; var dir = d / len;
            for (float t = 0; t < len; t += 4f)
            {
                var p = a + dir * (t + 2f);
                var rot = Quaternion.LookRotation(dir) * Quaternion.Euler(0, 0, r.Range(-4f, 4f));
                var size = new Vector3(0.3f, h + r.Range(-0.6f, 0.8f), 4.1f);
                c.detailMB.SimpleBox(p + Vector3.up * size.y * 0.5f, size, r.Chance(0.5f) ? M.rust : M.ribbed, rot);
                c.AddRotatedCollider(p + Vector3.up * size.y * 0.5f, size, rot);
            }
        }

        void JackalDen(Block b, Chunk c, Rng r)
        {
            var s = Shrink(b.build, 2f);
            float h = 3.2f;
            // walls with a gate on the north side
            ScrapWall(c, r, new Vector3(s.xMin, Kerb, s.yMin), new Vector3(s.xMax, Kerb, s.yMin), h);
            ScrapWall(c, r, new Vector3(s.xMin, Kerb, s.yMin), new Vector3(s.xMin, Kerb, s.yMax), h);
            ScrapWall(c, r, new Vector3(s.xMax, Kerb, s.yMin), new Vector3(s.xMax, Kerb, s.yMax), h);
            ScrapWall(c, r, new Vector3(s.xMin, Kerb, s.yMax), new Vector3(s.center.x - 4, Kerb, s.yMax), h);
            ScrapWall(c, r, new Vector3(s.center.x + 4, Kerb, s.yMax), new Vector3(s.xMax, Kerb, s.yMax), h);
            var tile = M.FacadeTile(FacadeStyle.Slum);
            for (int i = 0; i < 6; i++)
            {
                var size = new Vector3(r.Range(5f, 9f), r.Range(3f, 5f), r.Range(5f, 9f));
                var mn = new Vector3(r.Range(s.xMin + 3, s.xMax - size.x - 3), Kerb, r.Range(s.yMin + 3, s.yMax - size.z - 8));
                Building(c, mn, mn + size, M.Facade(FacadeStyle.Slum, r), tile, true, r);
            }
            for (int i = 0; i < 5; i++) AddFireBarrel(c, new Vector3(r.Range(s.xMin + 4, s.xMax - 4), Kerb, r.Range(s.yMin + 4, s.yMax - 4)));
            for (int i = 0; i < 12; i++) Crate(c, new Vector3(r.Range(s.xMin + 4, s.xMax - 4), Kerb, r.Range(s.yMin + 4, s.yMax - 4)), r, true);
            c.detailMB.Panel(M.signs, new Vector3(s.center.x, Kerb + 5f, s.yMax + 0.3f), Vector3.forward, 6f, 1.6f, Tex.SignUV(Tex.SignIndexForWord("CHROME")));
            AddLoc("jackal_gate", "Jackal Den Gate", new Vector3(s.center.x, Kerb, s.yMax + 3f), LocType.Mission, District.Lowtown, 6f);
        }

        void RaiderCamp(Block b, Chunk c, Rng r)
        {
            var s = Shrink(b.build, 4f);
            var ctr = new Vector3(s.center.x, Kerb, s.center.y);
            for (int i = 0; i < 14; i++)
            {
                float a = i / 14f * Mathf.PI * 2;
                var p = ctr + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * 30f;
                if (i % 7 == 3) continue; // entrances
                if (i % 2 == 0) Wreck(c, r, p);
                else ScrapWall(c, r, p, p + new Vector3(-Mathf.Sin(a), 0, Mathf.Cos(a)) * 10f, 3.5f);
            }
            // watch towers
            foreach (var o in new[] { new Vector3(-24, 0, -24), new Vector3(24, 0, 24) })
            {
                var p = ctr + o;
                foreach (var l in new[] { new Vector3(-1.5f, 0, -1.5f), new Vector3(1.5f, 0, -1.5f), new Vector3(1.5f, 0, 1.5f), new Vector3(-1.5f, 0, 1.5f) })
                    Building(c, p + l + new Vector3(-0.15f, 0, -0.15f), p + l + new Vector3(0.15f, 7f, 0.15f), M.rust, Vector2.one, true, r);
                Building(c, p + new Vector3(-2, 7, -2), p + new Vector3(2, 7.3f, 2), M.wood, Vector2.one, true, r);
                c.lights.Add(new LightAnchor { pos = p + Vector3.up * 8f, color = Palette.Orange, range = 14f, intensity = 2f, flicker = true });
            }
            // bonfire
            c.staticMB.Cylinder(M.black, ctr, 2f, 0.4f, 10);
            fireBarrels.Add(ctr + Vector3.up * 0.5f);
            fireBarrels.Add(ctr + new Vector3(0.6f, 0.5f, 0.3f));
            c.lights.Add(new LightAnchor { pos = ctr + Vector3.up * 2f, color = new Color(1f, 0.45f, 0.1f), range = 24f, intensity = 3.2f, flicker = true });
            for (int i = 0; i < 8; i++) Crate(c, ctr + new Vector3(r.Range(-20f, 20f), 0, r.Range(-20f, 20f)), r, true);
        }

        // ------------------------------------------------------------------ apartment interior (underground)
        public const float InteriorY = -60f;

        void BuildApartmentInterior()
        {
            var home = city.Loc("home");
            if (home == null) return;
            var o = new Vector3(home.pos.x, InteriorY, home.pos.z);
            var mb = new MeshBuilder();
            var go = new GameObject("Apartment");
            go.transform.SetParent(root, false);
            var colHolder = go;
            void Solid(Vector3 mn, Vector3 mx, Material m)
            {
                mb.Box(o + mn, o + mx, m, m, new Vector2(3, 3), m);
                var bc = colHolder.AddComponent<BoxCollider>();
                bc.center = o + (mn + mx) * 0.5f;
                bc.size = mx - mn;
            }
            float W = 10f, D = 7f, H = 3.2f;
            var wall = Mats.Lit(new Color(0.32f, 0.3f, 0.34f), Tex.Concrete.albedo, 0.2f);
            var floor = Mats.Lit(new Color(0.25f, 0.2f, 0.17f), Tex.Concrete.albedo, 0.5f);
            Solid(new Vector3(-W / 2, -0.3f, -D / 2), new Vector3(W / 2, 0, D / 2), floor);
            Solid(new Vector3(-W / 2, H, -D / 2), new Vector3(W / 2, H + 0.3f, D / 2), wall);
            Solid(new Vector3(-W / 2 - 0.3f, 0, -D / 2), new Vector3(-W / 2, H, D / 2), wall);
            Solid(new Vector3(W / 2, 0, -D / 2), new Vector3(W / 2 + 0.3f, H, D / 2), wall);
            Solid(new Vector3(-W / 2, 0, D / 2), new Vector3(W / 2, H, D / 2 + 0.3f), wall);
            Solid(new Vector3(-W / 2, 0, -D / 2 - 0.3f), new Vector3(W / 2, H, -D / 2), wall);
            // window "view" of the city
            var view = Mats.Unlit(Color.white * 1.3f, Tex.Facade(FacadeStyle.Glass, 1).emission);
            mb.Panel(view, o + new Vector3(0, 1.7f, D / 2 - 0.02f), Vector3.back, 6f, 2f, new Rect(0, 0, 2, 0.7f));
            mb.SimpleBox(o + new Vector3(0, 0.7f, D / 2 - 0.15f), new Vector3(6.2f, 0.12f, 0.3f), M.metalDark);
            // bed
            Solid(new Vector3(-W / 2 + 0.2f, 0, -0.5f), new Vector3(-W / 2 + 2.3f, 0.5f, 2.5f), M.metalDark);
            mb.SimpleBox(o + new Vector3(-W / 2 + 1.25f, 0.6f, 1f), new Vector3(2f, 0.2f, 2.9f), Mats.Lit(new Color(0.15f, 0.2f, 0.35f), null, 0.05f));
            mb.SimpleBox(o + new Vector3(-W / 2 + 0.25f, 0.55f, 1f), new Vector3(0.05f, 0.05f, 3f), M.Neon(Palette.Magenta, 3f));
            var bed = Interactable.Create<Bed>("Bed", go.transform, o + new Vector3(-W / 2 + 1.25f, 0f, 1f), new Vector3(2f, 0.9f, 2.9f), Vector3.right);
            bed.id = "apt_bed";
            // desk + terminal
            Solid(new Vector3(W / 2 - 2.5f, 0, D / 2 - 1.1f), new Vector3(W / 2 - 0.2f, 0.8f, D / 2 - 0.1f), M.metalDark);
            mb.Panel(M.screen, o + new Vector3(W / 2 - 1.35f, 1.3f, D / 2 - 0.35f), Vector3.back, 1.4f, 0.8f, new Rect(0, 0, 1, 1));
            var term = Interactable.Create<Terminal>("HomeTerminal", go.transform, o + new Vector3(W / 2 - 1.35f, 0, D / 2 - 0.6f), new Vector3(2f, 1.6f, 0.9f), Vector3.back);
            term.requireHack = false;
            term.id = "apt_terminal";
            term.readTitle = "INBOX // 3 unread";
            term.readText = Lore.HomeTerminal;
            // fridge, couch, neon strip
            Solid(new Vector3(W / 2 - 0.9f, 0, -D / 2 + 0.2f), new Vector3(W / 2 - 0.2f, 1.9f, -D / 2 + 1f), M.white);
            Solid(new Vector3(-1.5f, 0, -D / 2 + 0.2f), new Vector3(1.5f, 0.45f, -D / 2 + 1.1f), Mats.Lit(new Color(0.35f, 0.1f, 0.15f), null, 0.1f));
            mb.SimpleBox(o + new Vector3(0, H - 0.05f, 0), new Vector3(W - 0.4f, 0.04f, 0.08f), M.Neon(Palette.Cyan, 3f));
            // door back to the street
            mb.SimpleBox(o + new Vector3(0, 1.1f, -D / 2 + 0.05f), new Vector3(1.2f, 2.2f, 0.1f), M.chrome);
            var exit = Interactable.Create<Teleporter>("AptExit", go.transform, o + new Vector3(0, 0, -D / 2 + 0.4f), new Vector3(1.4f, 2.2f, 0.4f), Vector3.forward);
            exit.prompt = "Go outside";
            exit.target = home.pos + home.facing * 1.5f + Vector3.up * Kerb;
            exit.targetYaw = Quaternion.LookRotation(home.facing).eulerAngles.y;
            exit.id = "apt_exit";
            mb.BuildObject("Mesh", go.transform, true);

            var light = new GameObject("AptLight").AddComponent<Light>();
            light.transform.SetParent(go.transform, false);
            light.transform.position = o + new Vector3(0, H - 0.5f, 0);
            light.type = LightType.Point; light.range = 12f; light.intensity = 1.6f; light.color = new Color(0.9f, 0.6f, 1f);
            var light2 = new GameObject("AptLight2").AddComponent<Light>();
            light2.transform.SetParent(go.transform, false);
            light2.transform.position = o + new Vector3(0, 1.6f, D / 2 - 1f);
            light2.type = LightType.Point; light2.range = 7f; light2.intensity = 1.2f; light2.color = Palette.Cyan;

            AddLoc("apt_terminal", "Home Terminal", o + new Vector3(W / 2 - 1.35f, 0.05f, D / 2 - 0.6f), LocType.Home, District.Lowtown, 2f);
            AddLoc("apt_exit", "Apartment Exit", o + new Vector3(0, 0.05f, -D / 2 + 0.4f), LocType.Home, District.Lowtown, 2f);
            AddLoc("apt_bed", "Bed", o + new Vector3(-W / 2 + 1.25f, 0.05f, 1f), LocType.Home, District.Lowtown, 2f);
            AddLoc("apt_spawn", "Apartment", o + new Vector3(-W / 2 + 3f, 0.05f, 1f), LocType.Home, District.Lowtown, 3f);
            AddLoc("apt_door", "Apartment Door", o + new Vector3(0, 0.05f, -D / 2 + 1.4f), LocType.Home, District.Lowtown, 2f);

            // street door into the apartment
            var hc = ChunkFor(home.pos);
            var enter = Interactable.Create<Teleporter>("AptEnter", hc.detailGo.transform, home.pos - home.facing * 0.8f + Vector3.up * Kerb, new Vector3(2.2f, 2.6f, 0.5f), home.facing);
            enter.prompt = "Enter apartment";
            enter.target = o + new Vector3(0, 0.05f, -D / 2 + 1.4f);
            enter.targetYaw = 0f;
            enter.id = "apt_enter";
        }

        // ------------------------------------------------------------------ interactive props placed after blocks
        public void PlaceInteractivePoints()
        {
            foreach (var loc in city.locations.Values)
            {
                var c = ChunkFor(loc.pos);
                switch (loc.type)
                {
                    case LocType.Metro: PropFactory.MetroEntrance(c, loc, M); break;
                    case LocType.Race: PropFactory.RaceMarker(c, loc, M); break;
                    case LocType.BountyBoard: PropFactory.BountyBoardAt(c, loc, M); break;
                    case LocType.GunShop: case LocType.NetShop: case LocType.CarDealer: case LocType.Clinic: case LocType.Bar: case LocType.Fixer:
                        PropFactory.ShopFront(c, loc, M, this);
                        break;
                }
            }
            for (int i = 0; i < city.shardSpots.Count; i++)
            {
                var p = city.shardSpots[i];
                var c = ChunkFor(p);
                var go = new GameObject("DataShard_" + i) { layer = Layers.Triggers };
                go.transform.SetParent(c.detailGo.transform, false);
                go.transform.position = p;
                var col = go.AddComponent<SphereCollider>(); col.radius = 0.5f; col.isTrigger = true;
                var s = go.AddComponent<DataShard>();
                s.index = i;
                var vis = Util.Primitive(PrimitiveType.Cube, "Vis", go.transform, Vector3.zero, new Vector3(0.25f, 0.35f, 0.05f), M.Neon(Palette.Green, 3f));
                vis.layer = Layers.Triggers;
                var glow = Util.Primitive(PrimitiveType.Quad, "Glow", go.transform, Vector3.zero, Vector3.one * 1.2f, Mats.Cached("shardglow", () => Mats.Additive(Palette.Green.WithAlpha(0.5f), Tex.Glow)));
                glow.AddComponent<Billboard>();
                shards.Add(s);
            }
        }
    }
}
