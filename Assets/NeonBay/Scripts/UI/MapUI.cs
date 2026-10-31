using System.Collections;
using UnityEngine;

namespace NeonBay
{
    public partial class UIManager
    {
        Texture2D mapTex, arrowTex;
        float mapMin, mapSize;
        float mapZoom = 1f;
        Vector2 mapPan;
        bool mapDragging;
        Vector2 dragStart, panStart;
        const int MapRes = 512;

        /// <summary>Renders a top-down map by ray-casting the generated city (height-shaded buildings, district tint, roads, water).</summary>
        public IEnumerator BuildMap(CityGenerator gen)
        {
            var city = Game.City;
            mapMin = -CityData.WallMargin - 10f;
            mapSize = city.Size + 2f * (CityData.WallMargin + 10f);
            mapTex = new Texture2D(MapRes, MapRes, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color32[MapRes * MapRes];
            float step = mapSize / MapRes;
            for (int y = 0; y < MapRes; y++)
            {
                for (int x = 0; x < MapRes; x++)
                {
                    var wp = new Vector3(mapMin + (x + 0.5f) * step, 0, mapMin + (y + 0.5f) * step);
                    Color c;
                    if (wp.x > city.Size + 20f && wp.x < city.Size + CityData.WallMargin) c = new Color(0.02f, 0.08f, 0.14f);
                    else if (!city.InCity(wp)) c = new Color(0.12f, 0.03f, 0.05f);
                    else
                    {
                        bool road = city.OnRoad(wp);
                        float h = 0f;
                        if (Physics.Raycast(wp + Vector3.up * 600f, Vector3.down, out var hit, 700f, Layers.WorldMask, QueryTriggerInteraction.Ignore)) h = hit.point.y;
                        var dc = CityData.DistrictColor(city.DistrictAt(wp));
                        if (road && h < 0.5f) c = new Color(0.1f, 0.11f, 0.13f);
                        else if (h < 0.5f) c = Color.Lerp(new Color(0.05f, 0.06f, 0.08f), dc, 0.12f);
                        else
                        {
                            float k = Mathf.Clamp01(h / 120f);
                            c = Color.Lerp(Color.Lerp(new Color(0.2f, 0.22f, 0.26f), dc, 0.25f), Color.Lerp(new Color(0.75f, 0.8f, 0.85f), dc, 0.3f), Mathf.Sqrt(k));
                        }
                    }
                    px[y * MapRes + x] = c;
                }
                if (y % 32 == 0) yield return null;
            }
            // building edges for crispness
            var outp = new Color32[px.Length];
            for (int y = 0; y < MapRes; y++)
                for (int x = 0; x < MapRes; x++)
                {
                    var c = px[y * MapRes + x];
                    int xr = Mathf.Min(MapRes - 1, x + 1), yu = Mathf.Min(MapRes - 1, y + 1);
                    var n1 = px[y * MapRes + xr]; var n2 = px[yu * MapRes + x];
                    int diff = Mathf.Abs(c.r - n1.r) + Mathf.Abs(c.r - n2.r);
                    if (diff > 40) c = new Color32((byte)Mathf.Min(255, c.r + 30), (byte)Mathf.Min(255, c.g + 40), (byte)Mathf.Min(255, c.b + 45), 255);
                    outp[y * MapRes + x] = c;
                }
            mapTex.SetPixels32(outp);
            mapTex.Apply();

            arrowTex = new Texture2D(32, 32, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear };
            for (int y = 0; y < 32; y++)
                for (int x = 0; x < 32; x++)
                {
                    float fx = (x - 15.5f) / 16f, fy = (y - 15.5f) / 16f;
                    // arrow pointing up (+y in texture = top on screen after GUI flip)
                    bool inside = fy > -0.8f && Mathf.Abs(fx) < (fy + 0.8f) * 0.55f && fy < 0.9f && !(fy < -0.2f && Mathf.Abs(fx) < 0.25f && fy < -0.35f);
                    arrowTex.SetPixel(x, y, inside ? Color.white : Color.clear);
                }
            arrowTex.Apply();
        }

        Vector2 WorldToMapUV(Vector3 p) => new Vector2((p.x - mapMin) / mapSize, (p.z - mapMin) / mapSize);

        static Color IconColor(LocType t) => t switch
        {
            LocType.Fixer => Palette.Magenta,
            LocType.GunShop => Palette.Red,
            LocType.Clinic => Palette.Cyan,
            LocType.NetShop => Palette.Green,
            LocType.CarDealer => Palette.Yellow,
            LocType.Bar => Palette.Orange,
            LocType.Metro => Palette.Blue,
            LocType.Race => Palette.Yellow,
            LocType.FightRing => Palette.Red,
            LocType.BountyBoard => Palette.Blue,
            LocType.Home => Palette.Green,
            LocType.Hideout => new Color(0.8f, 0.3f, 0.3f),
            _ => Palette.White
        };

        static string IconGlyph(LocType t) => t switch
        {
            LocType.Fixer => "F", LocType.GunShop => "G", LocType.Clinic => "+", LocType.NetShop => "N", LocType.CarDealer => "C",
            LocType.Bar => "B", LocType.Metro => "M", LocType.Race => "R", LocType.FightRing => "P", LocType.BountyBoard => "$",
            LocType.Home => "H", LocType.Hideout => "!", _ => "*"
        };

        void Icon(Vector2 c, Color col, string glyph, float size = 16f)
        {
            UISkin.Rect(new Rect(c.x - size * 0.5f - 1, c.y - size * 0.5f - 1, size + 2, size + 2), new Color(0, 0, 0, 0.8f));
            UISkin.Rect(new Rect(c.x - size * 0.5f, c.y - size * 0.5f, size, size), col * 0.85f);
            UISkin.Text(new Rect(c.x - size, c.y - size * 0.5f - 1, size * 2, size + 2), glyph, UISkin.tiny, Color.black, false);
        }

        // ------------------------------------------------------------------ minimap (north-up)
        void DrawMinimap(Rect r)
        {
            if (mapTex == null || !Game.HasPlayer) return;
            float range = Game.Player.InVehicle ? 360f : 230f;
            var p = Game.PlayerPos;
            bool inside = p.y < -20f;
            UISkin.Rect(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), new Color(0.1f, 0.9f, 1f, 0.6f));
            GUI.BeginGroup(r);
            var local = new Rect(0, 0, r.width, r.height);
            if (inside)
            {
                UISkin.Rect(local, new Color(0.02f, 0.03f, 0.05f, 0.95f));
                UISkin.Text(local, "NO SIGNAL\n(indoors)", UISkin.center, UISkin.Dim);
                GUI.EndGroup();
                return;
            }
            var uv = WorldToMapUV(p);
            float span = range * 2f / mapSize;
            GUI.DrawTextureWithTexCoords(local, mapTex, new Rect(uv.x - span * 0.5f, uv.y - span * 0.5f, span, span));
            UISkin.Rect(local, new Color(0, 0.02f, 0.05f, 0.25f));
            Vector2 ToMini(Vector3 w) => new Vector2((w.x - p.x) / (range * 2f) * r.width + r.width * 0.5f, -(w.z - p.z) / (range * 2f) * r.height + r.height * 0.5f);
            bool InMini(Vector2 v) => v.x > 4 && v.y > 4 && v.x < r.width - 4 && v.y < r.height - 4;

            foreach (var l in Game.City.locations.Values)
            {
                if (!l.showOnMap || l.type == LocType.Mission || l.type == LocType.Landmark) continue;
                var m = ToMini(l.pos);
                if (InMini(m)) Icon(m, IconColor(l.type), IconGlyph(l.type), 13f);
            }
            // NPC dots: hostiles in combat, revealed enemies, police
            foreach (var n in NPC.All)
            {
                if (n == null || n.state == NPCState.Dead) continue;
                bool show = n.state == NPCState.Combat || n.revealed || (n.IsHostileToPlayer && n.detection > 0.2f) || (Game.Hacking != null && Game.Hacking.Pinging && n.IsHostileToPlayer);
                if (!show) continue;
                var m = ToMini(n.transform.position);
                if (!InMini(m)) continue;
                var col = n.faction == FactionId.Police ? Palette.Blue : Palette.Red;
                UISkin.Rect(new Rect(m.x - 3, m.y - 3, 6, 6), col);
            }
            // quest marker
            foreach (var mp in QuestMarkers())
            {
                var m = ToMini(mp);
                m.x = Mathf.Clamp(m.x, 8, r.width - 8); m.y = Mathf.Clamp(m.y, 8, r.height - 8);
                UISkin.Diamond(m, 11f, Palette.Yellow);
            }
            if (waypoint.HasValue)
            {
                var m = ToMini(waypoint.Value);
                m.x = Mathf.Clamp(m.x, 8, r.width - 8); m.y = Mathf.Clamp(m.y, 8, r.height - 8);
                UISkin.Diamond(m, 10f, Palette.Cyan);
            }
            if (Game.Events != null && Game.Events.active != WorldEvents.Kind.None)
            {
                var m = ToMini(Game.Events.site);
                if (InMini(m)) UISkin.Diamond(m, 9f, Palette.Orange);
            }
            // player arrow
            var center = new Vector2(r.width * 0.5f, r.height * 0.5f);
            var matrix = GUI.matrix;
            float yaw = Game.Player.InVehicle ? Game.Player.vehicle.transform.eulerAngles.y : Game.Player.Yaw;
            GUIUtility.RotateAroundPivot(yaw, center);
            var old = GUI.color; GUI.color = Color.white;
            GUI.DrawTexture(new Rect(center.x - 9, center.y - 9, 18, 18), arrowTex);
            GUI.color = old;
            GUI.matrix = matrix;
            UISkin.Text(new Rect(4, 2, 30, 20), "N", UISkin.tiny, Palette.Cyan);
            GUI.EndGroup();
        }

        System.Collections.Generic.IEnumerable<Vector3> QuestMarkers()
        {
            var q = Game.Quests?.tracked;
            if (q == null || q.status != QuestStatus.Active || q.Step == null) yield break;
            foreach (var o in q.Step.objectives)
            {
                if (o.Done) continue;
                var m = o.MarkerPos;
                if (m.HasValue) yield return m.Value;
            }
        }

        // ------------------------------------------------------------------ full map (pause tab)
        void DrawFullMap(Rect area)
        {
            if (mapTex == null) return;
            var e = Event.current;
            float side = Mathf.Min(area.width - 260, area.height);
            var r = new Rect(area.x, area.y, side, side);
            // zoom & pan
            if (r.Contains(e.mousePosition))
            {
                if (e.type == EventType.ScrollWheel) { mapZoom = Mathf.Clamp(mapZoom * (e.delta.y > 0 ? 0.9f : 1.1f), 1f, 6f); e.Use(); }
                if (e.type == EventType.MouseDown && e.button == 1) { mapDragging = true; dragStart = e.mousePosition; panStart = mapPan; e.Use(); }
            }
            if (mapDragging && e.type == EventType.MouseDrag) { mapPan = panStart - (e.mousePosition - dragStart) / side / mapZoom; e.Use(); }
            if (e.type == EventType.MouseUp && e.button == 1) mapDragging = false;
            float span = 1f / mapZoom;
            var focus = Game.HasPlayer && Game.PlayerPos.y > -20f ? WorldToMapUV(Game.PlayerPos) : new Vector2(0.5f, 0.5f);
            var c = focus + new Vector2(mapPan.x, -mapPan.y);
            c.x = Mathf.Clamp(c.x, span * 0.5f, 1 - span * 0.5f); c.y = Mathf.Clamp(c.y, span * 0.5f, 1 - span * 0.5f);
            var uvRect = new Rect(c.x - span * 0.5f, c.y - span * 0.5f, span, span);
            UISkin.Rect(new Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), UISkin.Accent.WithAlpha(0.6f));
            GUI.DrawTextureWithTexCoords(r, mapTex, uvRect);
            Vector2 ToMap(Vector3 w)
            {
                var uv = WorldToMapUV(w);
                return new Vector2(r.x + (uv.x - uvRect.x) / uvRect.width * r.width, r.y + (1f - (uv.y - uvRect.y) / uvRect.height) * r.height);
            }
            Vector3 FromMap(Vector2 m)
            {
                float u = uvRect.x + (m.x - r.x) / r.width * uvRect.width;
                float v = uvRect.y + (1f - (m.y - r.y) / r.height) * uvRect.height;
                return new Vector3(mapMin + u * mapSize, 0, mapMin + v * mapSize);
            }
            bool In(Vector2 v) => r.Contains(v);

            // district labels
            if (mapZoom < 2.5f)
            {
                foreach (District d in System.Enum.GetValues(typeof(District)))
                {
                    Vector3 sum = Vector3.zero; int n = 0;
                    foreach (var b in Game.City.blocks) if (b.district == d) { sum += new Vector3(b.outer.center.x, 0, b.outer.center.y); n++; }
                    if (n == 0) continue;
                    var m = ToMap(sum / n);
                    UISkin.Text(new Rect(m.x - 120, m.y - 12, 240, 24), CityData.DistrictName(d), UISkin.center, CityData.DistrictColor(d).WithAlpha(0.8f));
                }
            }
            string hover = null;
            foreach (var l in Game.City.locations.Values)
            {
                if (!l.showOnMap) continue;
                if (l.type == LocType.Mission || l.type == LocType.Home && l.id != "home") continue;
                var m = ToMap(l.pos);
                if (!In(m)) continue;
                var col = IconColor(l.type);
                if (l.type == LocType.Metro && !l.discovered) col = col * 0.45f;
                Icon(m, col, IconGlyph(l.type), 18f);
                if (Vector2.Distance(e.mousePosition, m) < 12f) hover = l.name + (l.type == LocType.Metro ? (l.discovered ? "  (fast travel)" : "  (undiscovered)") : "");
            }
            foreach (var mp in QuestMarkers()) { var m = ToMap(mp); if (In(m)) UISkin.Diamond(m, 16f, Palette.Yellow); }
            if (waypoint.HasValue) { var m = ToMap(waypoint.Value); if (In(m)) UISkin.Diamond(m, 14f, Palette.Cyan); }
            if (Game.HasPlayer && Game.PlayerPos.y > -20f)
            {
                var m = ToMap(Game.PlayerPos);
                var matrix = GUI.matrix;
                GUIUtility.RotateAroundPivot(Game.Player.Yaw, m);
                GUI.DrawTexture(new Rect(m.x - 11, m.y - 11, 22, 22), arrowTex);
                GUI.matrix = matrix;
            }
            if (hover != null) UISkin.Text(new Rect(e.mousePosition.x + 16, e.mousePosition.y - 10, 420, 26), hover, UISkin.label, Color.white);
            if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(e.mousePosition))
            {
                var w = FromMap(e.mousePosition);
                SetWaypoint(w, "Waypoint");
                Game.Audio?.Play2D("ui_blip");
                e.Use();
            }

            // legend
            var lg = new Rect(r.xMax + 20, area.y, 240, area.height);
            GUILayout.BeginArea(lg);
            GUILayout.Label("LEGEND", UISkin.header);
            foreach (LocType t in new[] { LocType.Home, LocType.Fixer, LocType.GunShop, LocType.Clinic, LocType.NetShop, LocType.CarDealer, LocType.Bar, LocType.Metro, LocType.Race, LocType.FightRing, LocType.BountyBoard, LocType.Hideout })
            {
                var row = GUILayoutUtility.GetRect(220, 24);
                Icon(new Vector2(row.x + 10, row.y + 12), IconColor(t), IconGlyph(t), 16f);
                GUI.Label(new Rect(row.x + 26, row.y + 1, 200, 22), t.ToString(), UISkin.labelSmall);
            }
            GUILayout.Space(10);
            GUILayout.Label("<color=#ffd633>◆</color> Objective   <color=#19f2ff>◆</color> Waypoint", UISkin.labelSmall);
            GUILayout.Label("LMB: set waypoint\nRMB drag: pan\nWheel: zoom", UISkin.tiny);
            if (waypoint.HasValue && GUILayout.Button("Clear waypoint", UISkin.button)) ClearWaypoint();
            GUILayout.EndArea();
        }
    }
}
