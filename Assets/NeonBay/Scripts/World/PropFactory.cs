using UnityEngine;

namespace NeonBay
{
    /// <summary>Interactive street props: visuals go into the chunk mesh, logic into a small collider object.</summary>
    public static class PropFactory
    {
        public static void VendingMachine(Chunk c, Vector3 p, Vector3 n, CityMaterials M, Rng r)
        {
            var rot = Quaternion.LookRotation(n);
            var col = r.Pick(Palette.Neon);
            c.detailMB.SimpleBox(p + Vector3.up * 1f, new Vector3(1.1f, 2f, 0.8f), M.metalDark, rot);
            c.detailMB.Panel(Mats.Cached("vend" + ColorUtility.ToHtmlStringRGB(col), () => Mats.Unlit(col * 1.8f, Tex.Scanlines)), p + Vector3.up * 1.25f + n * 0.41f, n, 0.95f, 1.3f, new Rect(0, 0, 1, 4));
            var v = Interactable.Create<VendingMachine>("Vending", c.detailGo.transform, p, new Vector3(1.1f, 2f, 0.8f), n);
            v.itemId = r.Pick("volt_cola", "noodle_cup", "synth_beer");
            v.price = v.itemId == "synth_beer" ? 20 : 15;
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 1.4f + n * 0.8f, color = col, range = 4.5f, intensity = 1.2f });
        }

        public static void Atm(Chunk c, Vector3 p, Vector3 n, CityMaterials M)
        {
            var rot = Quaternion.LookRotation(n);
            c.detailMB.SimpleBox(p + Vector3.up * 0.8f, new Vector3(0.8f, 1.6f, 0.6f), M.chrome, rot);
            c.detailMB.Panel(M.screen, p + Vector3.up * 1.2f + n * 0.31f, n, 0.5f, 0.35f, new Rect(0, 0, 1, 1));
            c.detailMB.Panel(M.signs, p + Vector3.up * 1.75f + n * 0.31f, n, 0.8f, 0.3f, Tex.SignUV(Tex.SignIndexForWord("BANK")));
            Interactable.Create<Atm>("ATM", c.detailGo.transform, p, new Vector3(0.8f, 1.6f, 0.6f), n);
        }

        public static Terminal TerminalAt(Chunk c, Vector3 p, Vector3 n, CityMaterials M, string hackId, int cost)
        {
            var rot = Quaternion.LookRotation(n);
            c.detailMB.SimpleBox(p + Vector3.up * 0.6f, new Vector3(0.9f, 1.2f, 0.5f), M.metalDark, rot);
            c.detailMB.Panel(M.screen, p + Vector3.up * 1.35f + n * 0.05f, n, 0.8f, 0.5f, new Rect(0, 0, 1, 1));
            c.detailMB.SimpleBox(p + Vector3.up * 1.7f, new Vector3(0.95f, 0.06f, 0.55f), M.Neon(Palette.Green, 3f), rot);
            var t = Interactable.Create<Terminal>("Terminal_" + hackId, c.root.transform, p, new Vector3(0.9f, 1.8f, 0.6f), n);
            t.hackId = hackId;
            t.id = hackId;
            t.cost = cost;
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 1.6f + n * 0.8f, color = Palette.Green, range = 5f, intensity = 1.5f });
            return t;
        }

        public static void MetroEntrance(Chunk c, Location loc, CityMaterials M)
        {
            var n = loc.facing;
            var rot = Quaternion.LookRotation(n);
            var right = Vector3.Cross(Vector3.up, n);
            var p = loc.pos + Vector3.up * 0.15f;
            // arch
            c.detailMB.SimpleBox(p + right * 1.6f + Vector3.up * 1.6f, new Vector3(0.25f, 3.2f, 0.25f), M.metalDark, rot);
            c.detailMB.SimpleBox(p - right * 1.6f + Vector3.up * 1.6f, new Vector3(0.25f, 3.2f, 0.25f), M.metalDark, rot);
            c.detailMB.SimpleBox(p + Vector3.up * 3.25f, new Vector3(3.5f, 0.3f, 0.4f), M.Neon(Palette.Cyan, 3.5f), rot);
            c.detailMB.Panel(M.signs, p + Vector3.up * 3.9f, n, 3f, 1f, Tex.SignUV(Tex.SignIndexForWord("METRO")));
            c.detailMB.Panel(M.signs, p + Vector3.up * 3.9f, -n, 3f, 1f, Tex.SignUV(Tex.SignIndexForWord("METRO")));
            var g = Interactable.Create<MetroGate>("Metro_" + loc.id, c.detailGo.transform, p, new Vector3(3f, 2.8f, 0.4f), n);
            g.location = loc;
            g.id = loc.id;
            // the collider is a trigger-like gate: make it not block walking
            g.GetComponent<BoxCollider>().isTrigger = true;
            g.gameObject.layer = Layers.Triggers;
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 3f + n, color = Palette.Cyan, range = 9f, intensity = 2f });
        }

        public static void RaceMarker(Chunk c, Location loc, CityMaterials M)
        {
            var p = loc.pos;
            c.detailMB.Cylinder(Mats.Cached("raceholo", () => Mats.Additive(new Color(1f, 0.85f, 0.1f, 0.35f) * 1.5f, Tex.Scanlines)), p, 3f, 6f, 20, false);
            var rs = Interactable.Create<RaceStart>("Race_" + loc.id, c.detailGo.transform, p, new Vector3(6f, 3f, 6f), loc.facing);
            rs.raceId = loc.id;
            rs.id = loc.id;
            rs.GetComponent<BoxCollider>().isTrigger = true;
            rs.gameObject.layer = Layers.Triggers;
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 3f, color = Palette.Yellow, range = 10f, intensity = 2f });
        }

        public static void BountyBoardAt(Chunk c, Location loc, CityMaterials M)
        {
            var n = loc.facing; var rot = Quaternion.LookRotation(n);
            var p = loc.pos + Vector3.up * 0.15f;
            c.detailMB.SimpleBox(p + Vector3.up * 1.2f, new Vector3(2.4f, 2.4f, 0.3f), M.metalDark, rot);
            c.detailMB.Panel(M.screen, p + Vector3.up * 1.3f + n * 0.16f, n, 2f, 1.6f, new Rect(0, 0, 1, 1));
            c.detailMB.Panel(M.signs, p + Vector3.up * 2.8f + n * 0.16f, n, 2.4f, 0.6f, Tex.SignUV(Tex.SignIndexForWord("DANGER")));
            var b = Interactable.Create<BountyBoard>("BountyBoard", c.detailGo.transform, p, new Vector3(2.4f, 2.4f, 0.4f), n);
            b.id = loc.id;
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 2f + n, color = Palette.Blue, range = 8f, intensity = 2f });
        }

        public static void ShopFront(Chunk c, Location loc, CityMaterials M, CityGenerator gen)
        {
            var n = loc.facing; var rot = Quaternion.LookRotation(n);
            var right = Vector3.Cross(Vector3.up, n);
            var p = loc.pos + Vector3.up * 0.15f;
            string word, shop, vendor; Color col;
            switch (loc.id)
            {
                case "gunshop_market": word = "GUNS"; shop = "guns"; vendor = "Big Sam"; col = Palette.Red; break;
                case "gunshop_docks": word = "GUNS"; shop = "guns"; vendor = "Ma Lynn"; col = Palette.Orange; break;
                case "netshop": word = "DATA"; shop = "net"; vendor = "Pixie"; col = Palette.Green; break;
                case "cardealer": word = "RIDE"; shop = "cars"; vendor = "Uncle Tony"; col = Palette.Yellow; break;
                case "clinic": word = "CLINIC"; shop = "clinic"; vendor = "Doc Reyes"; col = Palette.Cyan; break;
                case "clinic_spire": word = "IMPLANTS"; shop = "clinic"; vendor = "Dr. Hale"; col = Palette.White; break;
                case "bar_rust": word = "BAR"; shop = "bar"; vendor = "Yolanda"; col = Palette.Orange; break;
                case "mamasol": word = "DINER"; shop = "fixer"; vendor = "Mama Sol"; col = Palette.Magenta; break;
                case "fixer_dutch": word = "REPAIR"; shop = "fixer"; vendor = "Dutch"; col = Palette.Yellow; break;
                case "fixer_kit": word = "PAWN"; shop = "fixer"; vendor = "Kit Malone"; col = Palette.Purple; break;
                default: return;
            }
            // counter
            c.detailMB.SimpleBox(p + Vector3.up * 0.55f, new Vector3(3f, 1.1f, 0.8f), M.metalDark, rot);
            c.detailMB.SimpleBox(p + Vector3.up * 1.12f, new Vector3(3.1f, 0.06f, 0.9f), M.Neon(col, 2f), rot);
            c.AddRotatedCollider(p + Vector3.up * 0.55f, new Vector3(3f, 1.1f, 0.8f), rot);
            // canopy and sign
            c.detailMB.SimpleBox(p + Vector3.up * 3f - n * 0.4f, new Vector3(4f, 0.1f, 2.2f), M.metalDark, rot);
            c.detailMB.Panel(M.signs, p + Vector3.up * 3.6f + n * 0.4f, n, 3.6f, 1.1f, Tex.SignUV(Tex.SignIndexForWord(word)));
            c.detailMB.SimpleBox(p + Vector3.up * 2.92f + n * 0.6f, new Vector3(4f, 0.06f, 0.06f), M.Neon(col, 3.5f), rot);
            if (shop == "fixer")
            {
                // stools for the noodle bar look
                for (int i = -1; i <= 1; i++)
                    c.detailMB.Cylinder(M.chrome, p + n * 1f + right * i * 0.9f, 0.2f, 0.7f, 8);
            }
            c.lights.Add(new LightAnchor { pos = p + Vector3.up * 2.6f + n * 1.2f, color = col, range = 9f, intensity = 2.4f });
            gen.vendors.Add(new VendorSpot { pos = p - n * 0.75f, facing = n, shopId = shop, name = vendor, npcId = loc.id, look = loc.id.GetHashCode() & 0xFF });
        }
    }
}
