using UnityEngine;

namespace NeonBay
{
    public partial class UIManager
    {
        void DrawHUD(bool minimal = false)
        {
            if (!Game.HasPlayer) return;
            var stats = Game.Stats;
            var pc = Game.Player;
            var wc = Game.Weapons;

            if (!minimal)
            {
                DrawWorldMarkers();
                DrawCrosshair(wc);
                if (wc != null && wc.ScopeActive)
                {
                    float s = H * 1.05f;
                    var sr = new Rect(W * 0.5f - s * 0.5f, H * 0.5f - s * 0.5f, s, s);
                    GUI.DrawTexture(sr, UISkin.scopeTex);
                    UISkin.Rect(new Rect(0, 0, sr.x + 1, H), Color.black);
                    UISkin.Rect(new Rect(sr.xMax - 1, 0, W - sr.xMax + 1, H), Color.black);
                    UISkin.Text(new Rect(W * 0.5f + 20, H * 0.5f + 20, 300, 24), "6x  //  " + RangeToCrosshair() , UISkin.mono, Palette.Red);
                }
            }

            // status overlays
            if (stats.HasBuff("camo")) UISkin.Rect(new Rect(0, 0, W, H), new Color(0.2f, 0.6f, 1f, 0.08f));
            if (Game.Manager.SlowMotion) UISkin.Rect(new Rect(0, 0, W, H), new Color(0.3f, 1f, 0.8f, 0.06f));
            if (Game.Hacking != null && Game.Hacking.Scanning) UISkin.Rect(new Rect(0, 0, W, H), new Color(0.1f, 0.9f, 1f, 0.07f));
            if (hurtFlash > 0.01f && !PostFX.Available)
            {
                var old = GUI.color; GUI.color = new Color(0.7f, 0f, 0f, hurtFlash * 0.7f);
                GUI.DrawTexture(new Rect(0, 0, W, H), UISkin.vignette);
                GUI.color = old;
            }

            // ---------------- bottom-left: vitals
            var bl = new Rect(30, H - 150, 420, 130);
            UISkin.Rect(new Rect(bl.x - 10, bl.y - 10, bl.width + 20, bl.height + 10), new Color(0, 0, 0, 0.35f));
            float hp = stats.dmg.health, mhp = stats.dmg.maxHealth;
            UISkin.Text(new Rect(bl.x, bl.y, 200, 22), "HEALTH", UISkin.tiny, UISkin.Dim);
            UISkin.Text(new Rect(bl.x + 220, bl.y, 200, 22), Mathf.CeilToInt(hp) + " / " + Mathf.CeilToInt(mhp), UISkin.right, Color.white);
            var hpCol = stats.dmg.Fraction < 0.3f ? Color.Lerp(Palette.Red, Color.white, Mathf.PingPong(Time.unscaledTime * 3f, 1f) * 0.4f) : new Color(0.2f, 1f, 0.75f);
            UISkin.Bar(new Rect(bl.x, bl.y + 22, 420, 14), hp / mhp, hpCol, new Color(0, 0, 0, 0.6f), true);
            UISkin.Text(new Rect(bl.x, bl.y + 42, 200, 20), "STAMINA", UISkin.tiny, UISkin.Dim);
            UISkin.Bar(new Rect(bl.x, bl.y + 60, 300, 6), stats.stamina / stats.MaxStamina, Palette.Yellow, new Color(0, 0, 0, 0.6f));
            UISkin.Text(new Rect(bl.x + 310, bl.y + 50, 110, 20), "ARMOR " + Mathf.RoundToInt(stats.ArmorValue), UISkin.tiny, Palette.Cyan);
            UISkin.Text(new Rect(bl.x, bl.y + 72, 80, 20), "RAM", UISkin.tiny, UISkin.Dim);
            for (int i = 0; i < stats.MaxRam; i++)
            {
                float fill = Mathf.Clamp01(stats.ram - i);
                var rr = new Rect(bl.x + 40 + i * 18, bl.y + 75, 14, 12);
                UISkin.Rect(rr, new Color(0, 0, 0, 0.6f));
                UISkin.Rect(new Rect(rr.x, rr.y, rr.width * fill, rr.height), Palette.Cyan);
            }
            UISkin.Text(new Rect(bl.x, bl.y + 94, 420, 22), "LV " + stats.Level + "   " + Util.Credits(stats.Money) + "   CRED " + stats.StreetCred + (stats.AttributePoints + stats.PerkPoints > 0 ? "   <color=#ffd633>[K] points to spend</color>" : ""), UISkin.labelSmall, Color.white);
            UISkin.Bar(new Rect(bl.x, bl.y + 118, 420, 3), stats.XP / (float)stats.XPToNext, Palette.Magenta, new Color(0, 0, 0, 0.5f));
            if (xpPopT > 0) UISkin.Text(new Rect(bl.x + 300, bl.y + 94, 120, 22), "+" + xpPopAmount + " XP", UISkin.right, Palette.Magenta.WithAlpha(Mathf.Clamp01(xpPopT)));

            // buffs
            float bx = bl.x;
            foreach (var b in new[] { "stim", "volt", "drunk", "spice", "chrono", "camo" })
            {
                if (!stats.HasBuff(b)) continue;
                UISkin.Text(new Rect(bx, bl.y - 34, 120, 22), b.ToUpperInvariant() + " " + Mathf.CeilToInt(stats.BuffTime(b)) + "s", UISkin.tiny, Palette.Green);
                bx += 100;
            }

            // ---------------- bottom-right: weapon / vehicle
            var br = new Rect(W - 450, H - 150, 420, 130);
            if (pc.InVehicle)
            {
                var v = pc.vehicle;
                UISkin.Text(new Rect(br.x, br.y + 10, 420, 60), Mathf.RoundToInt(v.SpeedKmh) + " <size=20>KM/H</size>", new GUIStyle(UISkin.title) { alignment = TextAnchor.MiddleRight, fontSize = 52 }, Color.white);
                UISkin.Text(new Rect(br.x, br.y + 70, 420, 22), Vehicle.TypeName(v.type), UISkin.right, UISkin.Dim);
                UISkin.Bar(new Rect(br.x + 220, br.y + 96, 200, 6), v.dmg.Fraction, v.dmg.Fraction < 0.3f ? Palette.Red : Palette.Cyan, new Color(0, 0, 0, 0.6f));
                if (Game.Music != null && Game.Music.station > 0) UISkin.Text(new Rect(br.x, br.y + 106, 420, 22), "♪ " + MusicSystem.StationNames[Game.Music.station], UISkin.right, Palette.Magenta);
            }
            else if (wc != null)
            {
                var w = wc.Current;
                var def = w?.Def;
                if (def != null)
                {
                    UISkin.Text(new Rect(br.x, br.y + 6, 420, 26), w.DisplayName, UISkin.right, w.RarityColor);
                    if (!def.IsMelee)
                    {
                        int reserve = Game.Inventory.Ammo(def.ammo);
                        UISkin.Text(new Rect(br.x, br.y + 30, 420, 60), w.ammoInMag + "<size=26> / " + reserve + "</size>", new GUIStyle(UISkin.title) { alignment = TextAnchor.MiddleRight, fontSize = 50 }, w.ammoInMag == 0 ? Palette.Red : Color.white);
                        if (wc.Reloading) UISkin.Text(new Rect(br.x, br.y + 88, 420, 22), "RELOADING", UISkin.right, Palette.Yellow);
                    }
                    else UISkin.Text(new Rect(br.x, br.y + 36, 420, 40), wc.Blocking ? "BLOCKING" : "MELEE", UISkin.right, UISkin.Dim);
                }
                else UISkin.Text(new Rect(br.x, br.y + 36, 420, 30), "HOLSTERED  [H]", UISkin.right, UISkin.Dim);
                string gren = "FRAG x" + Game.Inventory.Count("frag") + "   EMP x" + Game.Inventory.Count("emp");
                UISkin.Text(new Rect(br.x, br.y + 108, 420, 22), gren + "   [G]", UISkin.right, UISkin.Dim);
                string abil = "";
                if (stats.HasCyber("chronoweave")) abil += stats.chronoCooldown > 0 ? "CHRONO " + Mathf.CeilToInt(stats.chronoCooldown) + "s   " : "<color=#19f2ff>[Q] CHRONO</color>   ";
                if (stats.HasCyber("camo_mesh")) abil += stats.camoCooldown > 0 ? "CAMO " + Mathf.CeilToInt(stats.camoCooldown) + "s" : "<color=#19f2ff>[X] CAMO</color>";
                if (abil.Length > 0) UISkin.Text(new Rect(br.x, br.y - 20, 420, 22), abil, UISkin.right, UISkin.Dim);
                // slots
                for (int i = 0; i < 4; i++)
                {
                    var sw = Game.Inventory.slots[i];
                    var sr = new Rect(br.x + 30 + i * 98, br.y - 52, 92, 26);
                    UISkin.Rect(sr, i == wc.slot && !wc.Holstered ? new Color(1f, 0.15f, 0.7f, 0.35f) : new Color(0, 0, 0, 0.35f));
                    UISkin.Text(new Rect(sr.x + 6, sr.y + 3, sr.width - 8, sr.height), (i + 1) + " " + (sw != null ? Short(sw.Def.name) : "-"), UISkin.tiny, sw != null ? sw.RarityColor : UISkin.Dim);
                }
            }

            if (minimal) return;

            // ---------------- top-left: minimap & location
            var mm = new Rect(30, 30, 230, 230);
            DrawMinimap(mm);
            var district = Game.City.DistrictAt(Game.PlayerPos);
            UISkin.Text(new Rect(30, 266, 400, 24), Game.PlayerPos.y < -20f ? "INTERIOR" : CityData.DistrictName(district), UISkin.label, CityData.DistrictColor(district));
            UISkin.Text(new Rect(30, 290, 400, 22), Util.TimeString(Game.Env.timeOfDay) + "  DAY " + Game.Env.day + "  " + Game.Env.WeatherName, UISkin.labelSmall, UISkin.Dim);
            if (Game.Police != null && Game.Police.Heat > 0)
            {
                string stars = new string('★', Game.Police.Heat) + new string('☆', 5 - Game.Police.Heat);
                float pulse = Game.Police.Searching ? 0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 6f) : 1f;
                UISkin.Text(new Rect(30, 314, 400, 30), "NBPD " + stars, UISkin.labelBig, Color.Lerp(Palette.Red, Palette.Blue, Mathf.PingPong(Time.unscaledTime * 2f, 1f)).WithAlpha(pulse));
                if (Game.Police.Searching) UISkin.Bar(new Rect(30, 346, 230, 4), Game.Police.CoolProgress, Palette.Cyan, new Color(0, 0, 0, 0.6f));
            }
            if (Game.Events != null && Game.Events.active != WorldEvents.Kind.None)
                UISkin.Text(new Rect(30, 356, 400, 22), "◆ " + Game.Events.Label, UISkin.tiny, Palette.Orange);

            // ---------------- top-center: compass
            DrawCompass(new Rect(W * 0.5f - 360, 26, 720, 34));
            if (hintT > 0 && !string.IsNullOrEmpty(hint))
            {
                var hr = new Rect(W * 0.5f - 400, 74, 800, 54);
                UISkin.Rect(hr, new Color(0, 0, 0, 0.5f * Mathf.Clamp01(hintT)));
                UISkin.Text(new Rect(hr.x + 12, hr.y + 6, hr.width - 24, hr.height), hint, UISkin.center, new Color(1, 1, 1, Mathf.Clamp01(hintT)));
            }

            // ---------------- top-right: quest tracker
            DrawTracker(new Rect(W - 470, 30, 440, 300));

            // ---------------- center prompts
            var ia = Game.Interactor;
            if (ia != null && !string.IsNullOrEmpty(ia.PromptText))
            {
                var pr = new Rect(W * 0.5f - 300, H * 0.5f + 70, 600, 34);
                UISkin.Rect(pr, new Color(0, 0, 0, 0.55f));
                UISkin.Text(pr, ia.PromptText, UISkin.center, Color.white);
            }
            var hk = Game.Hacking;
            if (hk != null)
            {
                if (hk.Scanning) DrawScanner(hk);
                if (hk.uploadProgress >= 0f && hk.uploading != null) ProgressBar("UPLOADING: " + hk.uploading.name.ToUpperInvariant(), hk.uploadProgress, Palette.Cyan, H * 0.5f + 110);
                if (hk.breachProgress >= 0f) ProgressBar("BREACHING TERMINAL...", hk.breachProgress, Palette.Green, H * 0.5f + 110);
            }
            if (hackSeen > 0f && hackingNpc != null && hackingNpc.HackInProgress)
                ProgressBar("! INCOMING HACK: " + hackingNpc.displayName.ToUpperInvariant() + " - break line of sight !", hackProg, Palette.Red, H * 0.3f);

            // ---------------- activity HUDs
            var act = Game.Activities;
            if (act != null && act.RaceActive)
            {
                UISkin.Text(new Rect(W * 0.5f - 300, 96, 600, 40), Activities.Fmt(act.RaceTime) + "    CP " + act.RaceCheckpoint + "/" + act.RaceTotal, UISkin.centerBig, Palette.Yellow);
                if (act.Countdown > 0f) UISkin.Text(new Rect(0, H * 0.35f, W, 120), Mathf.CeilToInt(act.Countdown).ToString(), new GUIStyle(UISkin.title) { fontSize = 120 }, Palette.Yellow);
            }
            if (act != null && act.FightActive) UISkin.Text(new Rect(W * 0.5f - 300, 96, 600, 40), "THE PIT  -  ROUND " + Mathf.Max(1, act.FightRound) + " / 3", UISkin.centerBig, Palette.Red);
            if (timerLeft > 0f) UISkin.Text(new Rect(W * 0.5f - 300, 136, 600, 40), timerLabel + "  " + Activities.Fmt(timerLeft), UISkin.centerBig, timerLeft < 20f ? Palette.Red : Palette.Yellow);
            if (nearMiss > 0f) UISkin.Text(new Rect(W * 0.5f - 100, H * 0.5f - 80, 200, 24), "~ near miss ~", UISkin.center, new Color(1f, 0.8f, 0.6f, nearMiss * 2f));

            // ---------------- subtitles
            if (currentSub != null)
            {
                var sr = new Rect(W * 0.5f - 520, H - 210, 1040, 64);
                UISkin.Rect(sr, new Color(0, 0, 0, 0.5f));
                UISkin.Text(new Rect(sr.x + 16, sr.y + 6, sr.width - 32, 24), currentSub.speaker, UISkin.label, currentSub.color);
                UISkin.Text(new Rect(sr.x + 16, sr.y + 30, sr.width - 32, 34), currentSub.text, UISkin.label, Color.white);
            }
        }

        static string Short(string s) => s.Length > 11 ? s.Substring(0, 11) : s;

        string RangeToCrosshair()
        {
            var cam = Game.Cam.transform;
            return Physics.Raycast(cam.position, cam.forward, out var h, 600f, Layers.ShootMask, QueryTriggerInteraction.Ignore) ? Mathf.RoundToInt(h.distance) + "m" : "---";
        }

        void ProgressBar(string label, float p, Color c, float y)
        {
            var r = new Rect(W * 0.5f - 260, y, 520, 46);
            UISkin.Rect(r, new Color(0, 0, 0, 0.55f));
            UISkin.Text(new Rect(r.x, r.y + 2, r.width, 22), label, UISkin.center, c);
            UISkin.Bar(new Rect(r.x + 14, r.y + 28, r.width - 28, 8), p, c, new Color(0, 0, 0, 0.6f), true);
        }

        void DrawCrosshair(WeaponController wc)
        {
            if (wc == null || Game.Player.InVehicle || wc.ScopeActive) return;
            var c = new Vector2(W * 0.5f, H * 0.5f);
            var def = wc.CurrentDef;
            var col = new Color(1f, 1f, 1f, 0.85f);
            var hkTarget = Game.Hacking != null && Game.Hacking.Scanning;
            if (def == null || def.IsMelee || hkTarget)
            {
                UISkin.Rect(new Rect(c.x - 2, c.y - 2, 4, 4), hkTarget ? Palette.Cyan : col);
            }
            else
            {
                float fovK = Game.Cam.fieldOfView;
                float gap = 4f + Mathf.Tan(wc.SpreadNow * Mathf.Deg2Rad) / Mathf.Tan(fovK * 0.5f * Mathf.Deg2Rad) * H * 0.5f;
                float len = 9f;
                UISkin.Rect(new Rect(c.x - gap - len, c.y - 1, len, 2), col);
                UISkin.Rect(new Rect(c.x + gap, c.y - 1, len, 2), col);
                UISkin.Rect(new Rect(c.x - 1, c.y - gap - len, 2, len), col);
                UISkin.Rect(new Rect(c.x - 1, c.y + gap, 2, len), col);
                UISkin.Rect(new Rect(c.x - 1, c.y - 1, 2, 2), Palette.Cyan);
            }
            if (wc.HitMarker > 0f)
            {
                var hc = wc.HitMarkerKill ? Palette.Red : Color.white;
                hc.a = wc.HitMarker;
                var m = GUI.matrix;
                GUIUtility.RotateAroundPivot(45f, c);
                float s = 10f + (wc.HitMarkerKill ? 4f : 0f);
                UISkin.Rect(new Rect(c.x - s - 6, c.y - 1, s, 2), hc);
                UISkin.Rect(new Rect(c.x + 6, c.y - 1, s, 2), hc);
                UISkin.Rect(new Rect(c.x - 1, c.y - s - 6, 2, s), hc);
                UISkin.Rect(new Rect(c.x - 1, c.y + 6, 2, s), hc);
                GUI.matrix = m;
            }
        }

        void DrawCompass(Rect r)
        {
            UISkin.Rect(r, new Color(0, 0, 0, 0.35f));
            UISkin.Rect(new Rect(r.x, r.yMax - 1, r.width, 1), UISkin.Accent.WithAlpha(0.5f));
            float yaw = Game.Cam.transform.eulerAngles.y;
            float fov = 180f;
            string[] labels = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
            for (int i = 0; i < 8; i++)
            {
                float a = Mathf.DeltaAngle(yaw, i * 45f);
                if (Mathf.Abs(a) > fov * 0.5f) continue;
                float x = r.center.x + a / fov * r.width;
                UISkin.Text(new Rect(x - 20, r.y + 4, 40, 26), labels[i], UISkin.center, i % 2 == 0 ? Color.white : UISkin.Dim);
            }
            for (int d = 0; d < 360; d += 15)
            {
                float a = Mathf.DeltaAngle(yaw, d);
                if (Mathf.Abs(a) > fov * 0.5f || d % 45 == 0) continue;
                float x = r.center.x + a / fov * r.width;
                UISkin.Rect(new Rect(x, r.yMax - 8, 1, 6), UISkin.Dim);
            }
            void Mark(Vector3 p, Color c)
            {
                var to = p - Game.Cam.transform.position;
                float ang = Mathf.Atan2(to.x, to.z) * Mathf.Rad2Deg;
                float a = Mathf.Clamp(Mathf.DeltaAngle(yaw, ang), -fov * 0.5f, fov * 0.5f);
                UISkin.Diamond(new Vector2(r.center.x + a / fov * r.width, r.yMax + 6), 10f, c);
            }
            foreach (var m in QuestMarkers()) Mark(m, Palette.Yellow);
            if (waypoint.HasValue) Mark(waypoint.Value, Palette.Cyan);
            if (Game.Events != null && Game.Events.active != WorldEvents.Kind.None) Mark(Game.Events.site, Palette.Orange);
        }

        void DrawTracker(Rect r)
        {
            var q = Game.Quests?.tracked;
            if (q == null || q.status != QuestStatus.Active || q.Step == null) return;
            float y = r.y;
            UISkin.Text(new Rect(r.x, y, r.width, 26), q.title.ToUpperInvariant(), UISkin.label, q.kind == QuestKind.Main ? Palette.Yellow : Palette.Cyan);
            y += 28;
            foreach (var o in q.Step.objectives)
            {
                if (string.IsNullOrEmpty(o.text)) continue;
                string box = o.Done ? "<color=#4dff80>■</color> " : "<color=#19f2ff>□</color> ";
                string dist = "";
                var m = o.MarkerPos;
                if (m.HasValue && !o.Done && Game.HasPlayer) dist = "  <color=#8899aa>" + Mathf.RoundToInt(Vector3.Distance(Game.PlayerPos, m.Value)) + "m</color>";
                UISkin.Text(new Rect(r.x, y, r.width, 44), box + o.Display + dist, UISkin.labelSmall, o.Done ? UISkin.Dim : (o.optional ? new Color(0.75f, 0.8f, 0.85f) : Color.white));
                y += UISkin.labelSmall.CalcHeight(new GUIContent(box + o.Display + dist), r.width) + 4;
            }
        }

        void DrawWorldMarkers()
        {
            var cam = Game.Cam;
            // objective markers
            foreach (var p in QuestMarkers())
            {
                if (!WorldToGui(p, out var g)) continue;
                float d = Vector3.Distance(cam.transform.position, p);
                g.x = Mathf.Clamp(g.x, 40, W - 40); g.y = Mathf.Clamp(g.y, 60, H - 60);
                UISkin.Diamond(g, 16f, Palette.Yellow.WithAlpha(0.9f));
                UISkin.Text(new Rect(g.x - 60, g.y + 12, 120, 22), Mathf.RoundToInt(d) + "m", UISkin.center, Palette.Yellow);
            }
            if (waypoint.HasValue && WorldToGui(waypoint.Value + Vector3.up * 2f, out var wg))
            {
                float d = Vector3.Distance(cam.transform.position, waypoint.Value);
                if (d < 12f && waypointLabel == "Waypoint") ClearWaypoint();
                UISkin.Diamond(wg, 13f, Palette.Cyan);
                UISkin.Text(new Rect(wg.x - 80, wg.y + 10, 160, 22), (waypointLabel ?? "") + " " + Mathf.RoundToInt(d) + "m", UISkin.center, Palette.Cyan);
            }
            // NPC overlays
            foreach (var n in NPC.All)
            {
                if (n == null || n.state == NPCState.Dead) continue;
                var head = n.rig.HeadPos + Vector3.up * 0.45f;
                float d2 = (head - cam.transform.position).sqrMagnitude;
                if (d2 > 70f * 70f) continue;
                if (!WorldToGui(head, out var g)) continue;
                if (n.IsHostileToPlayer && n.state != NPCState.Combat && n.detection > 0.05f)
                {
                    var c = Color.Lerp(Palette.Yellow, Palette.Red, n.detection);
                    UISkin.Text(new Rect(g.x - 20, g.y - 30, 40, 30), n.detection > 0.6f ? "!" : "?", UISkin.centerBig, c);
                    UISkin.Bar(new Rect(g.x - 18, g.y, 36, 3), n.detection, c, new Color(0, 0, 0, 0.5f));
                }
                bool showBar = enemyBars.ContainsKey(n) || n.revealed || (Game.Hacking != null && Game.Hacking.scanTarget == n);
                if (showBar && d2 < 60f * 60f)
                {
                    UISkin.Text(new Rect(g.x - 90, g.y - 22, 180, 20), n.displayName + "  <color=#8899aa>LV" + n.level + "</color>", UISkin.center, n.IsHostileToPlayer ? Palette.Red : Color.white);
                    UISkin.Bar(new Rect(g.x - 50, g.y, 100, 5), n.dmg.Fraction, n.IsHostileToPlayer ? Palette.Red : Palette.Green, new Color(0, 0, 0, 0.6f));
                }
                if (n.revealed && !Util.LineOfSight(cam.transform.position, head))
                    UISkin.Frame(new Rect(g.x - 14, g.y + 4, 28, 60), Palette.Red.WithAlpha(0.8f), 2f);
            }
            foreach (var b in barks)
            {
                if (b.npc == null || !WorldToGui(b.npc.rig.HeadPos + Vector3.up * 0.7f, out var g)) continue;
                if ((b.npc.transform.position - cam.transform.position).sqrMagnitude > 40f * 40f) continue;
                var size = UISkin.labelSmall.CalcSize(new GUIContent(b.text));
                var br = new Rect(g.x - size.x * 0.5f - 8, g.y - 30, size.x + 16, 26);
                UISkin.Rect(br, new Color(0, 0, 0, 0.55f * Mathf.Clamp01(b.t)));
                UISkin.Text(new Rect(br.x + 8, br.y + 3, size.x + 4, 22), b.text, UISkin.labelSmall, new Color(1, 1, 1, Mathf.Clamp01(b.t)));
            }
            foreach (var p in popups)
            {
                if (!WorldToGui(p.pos, out var g)) continue;
                UISkin.Text(new Rect(g.x - 50, g.y - 12, 100, 24), p.text, UISkin.center, p.color.WithAlpha(Mathf.Clamp01(p.t * 2f)));
            }
        }

        void DrawScanner(Hacking hk)
        {
            var r = new Rect(W * 0.5f + 140, H * 0.5f - 160, 420, 330);
            var t = hk.scanTarget;
            UISkin.Text(new Rect(W * 0.5f - 200, H * 0.5f + 160, 400, 24), "SCANNER  //  scroll or 1-4 to pick, LMB to execute", UISkin.center, Palette.Cyan);
            if (t == null) return;
            GUI.Box(r, GUIContent.none, UISkin.panel);
            GUILayout.BeginArea(new Rect(r.x + 16, r.y + 12, r.width - 32, r.height - 24));
            if (t is NPC n)
            {
                GUILayout.Label(n.displayName.ToUpperInvariant(), UISkin.header);
                GUILayout.Label(Factions.Name(n.faction) + "   LEVEL " + n.level + "   " + n.archetype, UISkin.labelSmall);
                GUILayout.Label("HP " + Mathf.CeilToInt(n.dmg.health) + "/" + Mathf.CeilToInt(n.dmg.maxHealth) + "   ARMOR " + Mathf.RoundToInt(n.dmg.armor) + (n.dmg.isRobotic ? "   <color=#19f2ff>CHROME (weak to EMP)</color>" : ""), UISkin.labelSmall);
                GUILayout.Label(n.IsHostileToPlayer ? "<color=#ff3344>HOSTILE</color>" : "<color=#4dff80>NEUTRAL</color>" + (n.weaponDef != null ? "   ARMED: " + n.weaponDef.name : ""), UISkin.labelSmall);
            }
            else if (t is Drone dr) { GUILayout.Label("SECURITY DRONE", UISkin.header); GUILayout.Label(Factions.Name(dr.faction) + "  HP " + Mathf.CeilToInt(dr.dmg.health), UISkin.labelSmall); }
            else if (t is Vehicle v) { GUILayout.Label(Vehicle.TypeName(v.type).ToUpperInvariant(), UISkin.header); GUILayout.Label("LMB: Overheat engine (3 RAM)", UISkin.labelSmall); }
            else if (t is Interactable ia) { GUILayout.Label("DEVICE", UISkin.header); GUILayout.Label("LMB: " + ia.HackLabel + "  (" + ia.HackCost + " RAM)", UISkin.labelSmall); }
            GUILayout.Space(8);
            if (t is NPC || t is Drone)
            {
                var list = hk.Available;
                for (int i = 0; i < list.Count; i++)
                {
                    var q = list[i];
                    bool sel = i == hk.selected;
                    bool afford = Game.Stats.ram >= q.cost;
                    GUILayout.Label((sel ? "<color=#ff2bbf>▶ </color>" : "   ") + (i < 4 ? "[" + (i + 1) + "] " : "") + q.name + "  <color=#19f2ff>" + q.cost + " RAM</color>" + (afford ? "" : " <color=#ff3344>(low RAM)</color>"), sel ? UISkin.label : UISkin.labelSmall);
                    if (sel) GUILayout.Label("     " + q.desc, UISkin.tiny);
                }
            }
            GUILayout.EndArea();
        }
    }
}
