using UnityEngine;

namespace NeonBay
{
    /// <summary>Fight HUD, tale of the tape, corner, knockdown count, results / scorecards and the Pit career menu.</summary>
    public partial class UIManager
    {
        float redHeadLag = 100f, blueHeadLag = 100f;
        bool showBoxControls = true;
        int pitTab;
        int exhibitionPick = -1;

        static readonly Color HeadCol = new Color(0.95f, 0.2f, 0.25f);
        static readonly Color BodyCol = new Color(1f, 0.6f, 0.2f);
        static readonly Color StamCol = new Color(1f, 0.86f, 0.2f);

        public void DrawBoxingHUD()
        {
            var m = Boxing.Match;
            if (m == null || m.Red == null || m.Blue == null) return;
            if (InputHub.Down(NeonBay.Btn.Holster)) showBoxControls = !showBoxControls;
            float dt = Time.unscaledDeltaTime;
            redHeadLag = Mathf.MoveTowards(redHeadLag, Mathf.Max(0f, m.Red.headHP), dt * 18f);
            blueHeadLag = Mathf.MoveTowards(blueHeadLag, Mathf.Max(0f, m.Blue.headHP), dt * 18f);
            if (redHeadLag < m.Red.headHP) redHeadLag = m.Red.headHP;
            if (blueHeadLag < m.Blue.headHP) blueHeadLag = m.Blue.headHP;

            // ---- screen effects: flash, rocked tunnel, swollen eyes
            if (CameraFX.FlashAmount > 0.01f) UISkin.Rect(new Rect(0, 0, W, H), CameraFX.FlashColor.WithAlpha(CameraFX.FlashAmount * 0.35f));
            var inj = m.Red.rig != null ? m.Red.rig.injury : null;
            if (inj != null && m.phase != MatchPhase.Corner)
            {
                SwollenSide(inj.EyeClosure(true), false);
                SwollenSide(inj.EyeClosure(false), true);
            }
            if (m.Red.Rocked && !PostFX.Available) UISkin.Rect(new Rect(0, 0, W, H), new Color(0.5f, 0f, 0f, 0.12f + Mathf.Sin(Time.time * 6f) * 0.05f));

            bool cinematic = m.phase == MatchPhase.Replay || m.phase == MatchPhase.KOSequence || m.phase == MatchPhase.Intro;
            if (cinematic)
            {
                UISkin.Rect(new Rect(0, 0, W, 110), Color.black);
                UISkin.Rect(new Rect(0, H - 110, W, 110), Color.black);
            }
            if (m.phase == MatchPhase.Replay)
            {
                UISkin.Text(new Rect(60, 34, 600, 50), "INSTANT REPLAY", UISkin.header, Palette.Red);
                var old = GUI.color; GUI.color = new Color(1, 1, 1, 0.06f);
                GUI.DrawTextureWithTexCoords(new Rect(0, 0, W, H), Tex.Scanlines, new Rect(0, 0, 1, H / 6f));
                GUI.color = old;
                UISkin.Text(new Rect(W - 460, H - 80, 420, 40), (TouchControls.Active ? "" : "[SPACE] skip"), UISkin.right, UISkin.Dim);
            }

            if (m.phase == MatchPhase.Intro) { DrawTaleOfTape(m); return; }
            if (m.phase == MatchPhase.Result) { DrawFightResult(m); return; }

            if (!cinematic)
            {
                FighterPanel(m.Red, new Rect(40, 26, 640, 110), false, redHeadLag);
                FighterPanel(m.Blue, new Rect(W - 680, 26, 640, 110), true, blueHeadLag);
                // round / clock
                var cr = new Rect(W * 0.5f - 120, 22, 240, 96);
                UISkin.Rect(cr, new Color(0.02f, 0.02f, 0.04f, 0.82f));
                UISkin.Frame(cr, Palette.Red * 0.9f, 2);
                UISkin.Text(new Rect(cr.x, cr.y + 6, cr.width, 24), "ROUND " + Mathf.Max(1, m.Round) + " / " + m.Rounds, UISkin.center, UISkin.Dim);
                var clockCol = m.clock < 10f && m.phase == MatchPhase.Fight ? Color.Lerp(Palette.Red, Color.white, Mathf.PingPong(Time.time * 3f, 1f)) : Color.white;
                UISkin.Text(new Rect(cr.x, cr.y + 30, cr.width, 56), m.ClockLeft, UISkin.title, clockCol);
            }

            // world popups
            foreach (var p in m.popups)
            {
                if (!WorldToGui(p.pos, out var g)) continue;
                float a = Mathf.Clamp01(p.t * 2f);
                float s = Mathf.Lerp(1.4f, 1f, Mathf.Clamp01((1.1f - p.t) * 6f)) * p.size;
                var st = new GUIStyle(UISkin.centerBig) { fontSize = Mathf.RoundToInt(30 * s) };
                UISkin.Text(new Rect(g.x - 260, g.y - 30, 520, 60), p.text, st, p.color.WithAlpha(a));
            }
            // referee
            if (m.referee != null && m.referee.shoutT > 0f && m.referee.rig != null && WorldToGui(m.referee.rig.HeadPos + Vector3.up * 0.35f, out var rg))
                UISkin.Text(new Rect(rg.x - 200, rg.y - 20, 400, 40), "\"" + m.referee.shout + "\"", UISkin.centerBig, Color.white);
            // commentary
            if (m.commentaryT > 0f && !string.IsNullOrEmpty(m.commentary))
            {
                var r = new Rect(W * 0.5f - 520, TouchControls.Active ? 150 : H - 210, 1040, 46);
                UISkin.Rect(r, new Color(0, 0, 0, 0.55f * Mathf.Clamp01(m.commentaryT)));
                UISkin.Text(r, "<color=#ffd633>MIC MALONE:</color>  " + m.commentary, UISkin.center, Color.white.WithAlpha(Mathf.Clamp01(m.commentaryT)));
            }

            if (m.phase == MatchPhase.Knockdown) DrawCount(m);
            if (m.phase == MatchPhase.Corner) DrawCorner(m);
            if (m.phase == MatchPhase.Fight && showBoxControls && !TouchControls.Active) DrawBoxControls();
        }

        void SwollenSide(float closure, bool right)
        {
            if (closure < 0.05f) return;
            float w = W * 0.45f * closure;
            const int steps = 12;
            float sw = w / steps;
            for (int i = 0; i < steps; i++)
            {
                float k = i / (float)steps;
                float x = right ? W - (i + 1) * sw : i * sw;
                UISkin.Rect(new Rect(x, 0, sw + 1, H), new Color(0.04f, 0f, 0.02f, closure * 0.95f * (1f - k) * (1f - k)));
            }
        }

        void FighterPanel(Boxer b, Rect r, bool mirror, float headLag)
        {
            UISkin.Rect(new Rect(r.x - 10, r.y - 6, r.width + 20, r.height + 12), new Color(0.01f, 0.01f, 0.03f, 0.62f));
            var accent = b.corner == 0 ? Palette.Red : Palette.Blue;
            UISkin.Rect(new Rect(mirror ? r.xMax + 4 : r.x - 10, r.y - 6, 6, r.height + 12), accent);
            var nameSt = mirror ? new GUIStyle(UISkin.header) { alignment = TextAnchor.MiddleRight } : UISkin.header;
            UISkin.Text(new Rect(r.x, r.y, r.width, 32), b.profile.name.ToUpperInvariant() + (string.IsNullOrEmpty(b.profile.nickname) ? "" : "  <size=17><color=#ffd633>\"" + b.profile.nickname + "\"</color></size>"), nameSt, Color.white);
            UISkin.Text(new Rect(r.x, r.y + 30, r.width, 20), b.profile.Record + "   " + Boxing.StyleName(b.profile.style) + (b.profile.southpaw ? "  SOUTHPAW" : ""), mirror ? new GUIStyle(UISkin.tiny) { alignment = TextAnchor.MiddleRight } : UISkin.tiny, UISkin.Dim);
            Bar(new Rect(r.x, r.y + 54, r.width, 18), Mathf.Max(0f, b.headHP) / 100f, headLag / 100f, b.headCap / 100f, HeadCol, mirror, b.Rocked);
            Bar(new Rect(r.x + (mirror ? r.width * 0.25f : 0f), r.y + 76, r.width * 0.75f, 8), Mathf.Max(0f, b.bodyHP) / 100f, -1f, 1f, BodyCol, mirror, false);
            Bar(new Rect(r.x, r.y + 90, r.width, 10), b.stamina / 110f, -1f, b.staminaMax / 110f, StamCol, mirror, b.stamina < 20f);
            var lbl = mirror ? new GUIStyle(UISkin.tiny) { alignment = TextAnchor.MiddleRight } : UISkin.tiny;
            var flags = (b.Rocked ? "<color=#ff3344>ROCKED</color>  " : "") + (b.rig.injury != null && b.rig.injury.MaxCut > 0.3f ? "<color=#ff5566>CUT</color>  " : "") + (b.stamina < 20f ? "<color=#ffd633>GASSED</color>" : "");
            UISkin.Text(new Rect(r.x, r.y + 100, r.width, 18), flags, lbl, Color.white);
        }

        void Bar(Rect r, float frac, float lag, float cap, Color c, bool mirror, bool pulse)
        {
            UISkin.Rect(r, new Color(0, 0, 0, 0.7f));
            frac = Mathf.Clamp01(frac); cap = Mathf.Clamp01(cap);
            Rect Seg(float a, float b) => mirror ? new Rect(r.xMax - r.width * b, r.y, r.width * (b - a), r.height) : new Rect(r.x + r.width * a, r.y, r.width * (b - a), r.height);
            if (cap < 1f) UISkin.Rect(Seg(cap, 1f), new Color(0.25f, 0.05f, 0.05f, 0.85f)); // lost permanently this fight
            if (lag > frac) UISkin.Rect(Seg(frac, Mathf.Clamp01(lag)), new Color(1f, 1f, 1f, 0.75f));
            var col = pulse ? Color.Lerp(c, Color.white, Mathf.PingPong(Time.unscaledTime * 4f, 1f) * 0.5f) : c;
            UISkin.Rect(Seg(0f, frac), col);
            var hl = Seg(0f, frac);
            UISkin.Rect(new Rect(hl.x, hl.y, hl.width, hl.height * 0.35f), Color.white.WithAlpha(0.18f));
            for (float x = 0.1f; x < 1f; x += 0.1f) UISkin.Rect(new Rect(r.x + r.width * x, r.y, 1, r.height), new Color(0, 0, 0, 0.4f));
        }

        void DrawBoxControls()
        {
            var r = new Rect(W * 0.5f - 640, H - 62, 1280, 40);
            UISkin.Rect(r, new Color(0, 0, 0, 0.45f));
            UISkin.Text(r, "<color=#19f2ff>LMB</color> Jab   <color=#19f2ff>RMB</color> Cross   <color=#19f2ff>Q/E</color> Hooks   <color=#19f2ff>Z/X</color> Uppercuts   <color=#19f2ff>+CTRL</color> Body   <color=#19f2ff>+SHIFT</color> Power   <color=#19f2ff>SPACE</color> Block (tap = parry)   <color=#19f2ff>MOUSE</color> Slip/Duck/Lean   <color=#19f2ff>C</color> Duck   <color=#19f2ff>F</color> Clinch   <color=#19f2ff>V</color> Taunt   <color=#19f2ff>B</color> Camera   <color=#8899aa>[H] hide</color>", new GUIStyle(UISkin.labelSmall) { alignment = TextAnchor.MiddleCenter, fontSize = 14 }, Color.white);
        }

        void DrawCount(BoxingMatch m)
        {
            if (m.downed == null)
            {
                UISkin.Text(new Rect(0, H * 0.3f, W, 80), "HE'S UP!", UISkin.title, Palette.Yellow);
                return;
            }
            float pulse = 1f + Mathf.Clamp01(1f - (Time.time % 1f) * 3f) * 0.25f;
            var st = new GUIStyle(UISkin.title) { fontSize = Mathf.RoundToInt(150 * pulse) };
            UISkin.Text(new Rect(0, H * 0.22f, W, 200), m.count > 0 ? m.count.ToString() : "", st, m.count >= 8 ? Palette.Red : Color.white);
            UISkin.Text(new Rect(0, H * 0.22f + 190, W, 40), m.downed.isPlayer ? (TouchControls.Active ? "GET UP! Tap when the marker is in the zone" : "GET UP! Press SPACE when the marker is in the zone") : m.downed.profile.name.ToUpperInvariant() + " IS DOWN", UISkin.centerBig, Color.white);
            if (m.downed.isPlayer && m.count >= 1)
            {
                var bar = new Rect(W * 0.5f - 360, H * 0.62f, 720, 34);
                UISkin.Rect(bar, new Color(0, 0, 0, 0.75f));
                float z = m.getUpZone;
                UISkin.Rect(new Rect(bar.x + bar.width * (0.5f - z * 0.5f), bar.y, bar.width * z, bar.height), new Color(0.2f, 1f, 0.45f, 0.55f));
                UISkin.Rect(new Rect(bar.x + bar.width * m.getUpMarker - 4, bar.y - 8, 8, bar.height + 16), Color.white);
                UISkin.Frame(bar, Palette.Cyan, 2);
                UISkin.Bar(new Rect(bar.x, bar.yMax + 18, bar.width, 12), m.getUpMeter, Palette.Yellow, new Color(0, 0, 0, 0.7f));
                UISkin.Text(new Rect(bar.x, bar.yMax + 34, bar.width, 24), "WILL TO CONTINUE", UISkin.tiny, UISkin.Dim);
                // the world swims while you're down
                UISkin.Rect(new Rect(0, 0, W, H), new Color(0.05f, 0f, 0f, 0.25f + Mathf.Sin(Time.time * 2f) * 0.08f));
            }
        }

        void DrawCorner(BoxingMatch m)
        {
            var r = new Rect(W - 700, 160, 640, 760);
            GUI.Box(r, GUIContent.none, UISkin.panel);
            UISkin.Text(new Rect(r.x + 24, r.y + 16, r.width - 48, 34), "CORNER  //  AFTER ROUND " + m.Round, UISkin.header, UISkin.Accent);
            float y = r.y + 64;
            void Row(string label, string a, string b)
            {
                UISkin.Text(new Rect(r.x + 24, y, 220, 24), label, UISkin.labelSmall, UISkin.Dim);
                UISkin.Text(new Rect(r.x + 250, y, 150, 24), a, UISkin.label, Palette.Red * 1.2f);
                UISkin.Text(new Rect(r.x + 420, y, 150, 24), b, UISkin.label, new Color(0.4f, 0.6f, 1f));
                y += 28;
            }
            Row("", m.Red.profile.name.Split(' ')[0].ToUpperInvariant(), m.Blue.profile.name.Split(' ')[0].ToUpperInvariant());
            Row("Punches landed", m.Red.round.landed + " / " + m.Red.round.thrown, m.Blue.round.landed + " / " + m.Blue.round.thrown);
            Row("Power punches", m.Red.round.powerLanded.ToString(), m.Blue.round.powerLanded.ToString());
            Row("Body shots", m.Red.round.bodyLanded.ToString(), m.Blue.round.bodyLanded.ToString());
            Row("Evaded / blocked", m.Red.round.evaded + " / " + m.Red.round.blocked, m.Blue.round.evaded + " / " + m.Blue.round.blocked);
            y += 8;
            var inj = m.Red.rig.injury;
            if (inj != null)
            {
                UISkin.Text(new Rect(r.x + 24, y, r.width - 48, 24), "DAMAGE REPORT", UISkin.tiny, UISkin.Dim); y += 22;
                InjBar(r, ref y, "Cut", inj.MaxCut, Palette.Red);
                InjBar(r, ref y, "Left eye swelling", inj.EyeClosure(true) * 0.7f + inj.swell[(int)InjuryZone.EyeL] * 0.3f, new Color(0.6f, 0.3f, 0.6f));
                InjBar(r, ref y, "Right eye swelling", inj.EyeClosure(false) * 0.7f + inj.swell[(int)InjuryZone.EyeR] * 0.3f, new Color(0.6f, 0.3f, 0.6f));
                InjBar(r, ref y, "Concussion", inj.concussion, Palette.Yellow);
                InjBar(r, ref y, "Ribs / body", Mathf.Max(inj.RibDamage, inj.bodyTrauma), BodyCol);
            }
            y += 6;
            UISkin.Text(new Rect(r.x + 24, y, r.width - 48, 60), "<color=#ffd633>COACH:</color> \"" + m.cornerAdvice + "\"", UISkin.label, Color.white);
            y += 70;
            for (int i = 0; i < m.cornerOptions.Length; i++)
            {
                if (UISkin.Button(new Rect(r.x + 24 + (i % 2) * 300, y + (i / 2) * 58, 290, 50), m.cornerOptions[i], m.cornerChoice == i)) m.ChooseCorner(i);
            }
            y += 124;
            UISkin.Bar(new Rect(r.x + 24, y, r.width - 48, 6), 1f - m.phaseT / 14f, Palette.Cyan, new Color(0, 0, 0, 0.6f));
            UISkin.Text(new Rect(r.x + 24, y + 10, r.width - 48, 22), m.cornerChoice >= 0 ? "Seconds out..." : (TouchControls.Active ? "Pick one before the bell" : "Pick one before the bell (1-4)"), UISkin.tiny, UISkin.Dim);
            for (int i = 0; i < 4; i++) if (InputHub.KeyDown(KeyCode.Alpha1 + i)) m.ChooseCorner(i);
        }

        void InjBar(Rect r, ref float y, string label, float v, Color c)
        {
            UISkin.Text(new Rect(r.x + 24, y, 220, 20), label, UISkin.tiny, Color.white);
            UISkin.Bar(new Rect(r.x + 250, y + 6, r.width - 280, 8), Mathf.Clamp01(v), c, new Color(0, 0, 0, 0.6f));
            y += 22;
        }

        void DrawTaleOfTape(BoxingMatch m)
        {
            var r = new Rect(W * 0.5f - 640, H * 0.5f - 300, 1280, 600);
            UISkin.Rect(r, new Color(0.01f, 0.01f, 0.03f, 0.82f));
            UISkin.Frame(r, Palette.Red, 2);
            UISkin.Text(new Rect(r.x, r.y + 18, r.width, 50), "TALE OF THE TAPE", UISkin.title, Palette.Yellow);
            UISkin.Text(new Rect(r.x, r.y + 76, r.width, 24), "THE PIT  //  " + m.Rounds + " ROUNDS  //  NEON BAY UNDERGROUND", UISkin.center, UISkin.Dim);
            var a = m.Red.profile; var b = m.Blue.profile;
            float y = r.y + 120;
            var L = new GUIStyle(UISkin.labelBig) { alignment = TextAnchor.MiddleRight };
            var R = new GUIStyle(UISkin.labelBig) { alignment = TextAnchor.MiddleLeft };
            var C = new GUIStyle(UISkin.labelSmall) { alignment = TextAnchor.MiddleCenter };
            UISkin.Text(new Rect(r.x + 40, y, 480, 40), a.name.ToUpperInvariant(), new GUIStyle(UISkin.header) { alignment = TextAnchor.MiddleRight, fontSize = 32 }, Palette.Red * 1.3f);
            UISkin.Text(new Rect(r.xMax - 520, y, 480, 40), b.name.ToUpperInvariant(), new GUIStyle(UISkin.header) { fontSize = 32 }, new Color(0.45f, 0.65f, 1f));
            UISkin.Text(new Rect(r.x + 560, y, 160, 40), "VS", UISkin.centerBig, Color.white);
            y += 46;
            void Line(string label, string va, string vb)
            {
                UISkin.Text(new Rect(r.x + 40, y, 480, 28), va, L, Color.white);
                UISkin.Text(new Rect(r.x + 540, y, 200, 28), label, C, UISkin.Dim);
                UISkin.Text(new Rect(r.xMax - 520, y, 480, 28), vb, R, Color.white);
                y += 30;
            }
            Line("NICKNAME", string.IsNullOrEmpty(a.nickname) ? "-" : "\"" + a.nickname + "\"", string.IsNullOrEmpty(b.nickname) ? "-" : "\"" + b.nickname + "\"");
            Line("RECORD", a.Record, b.Record);
            Line("STYLE", Boxing.StyleName(a.style), Boxing.StyleName(b.style));
            Line("STANCE", a.southpaw ? "Southpaw" : "Orthodox", b.southpaw ? "Southpaw" : "Orthodox");
            Line("HEIGHT / REACH", a.heightCm + " / " + a.reachCm + " cm", b.heightCm + " / " + b.reachCm + " cm");
            Line("WEIGHT", a.weightKg + " kg", b.weightKg + " kg");
            y += 8;
            string[] names = { "POWER", "SPEED", "ENGINE", "CHIN", "DEFENSE", "FOOTWORK", "HEART" };
            float[] va2 = { a.stats.power, a.stats.speed, a.stats.engine, a.stats.chin, a.stats.defense, a.stats.footwork, a.stats.heart };
            float[] vb2 = { b.stats.power, b.stats.speed, b.stats.engine, b.stats.chin, b.stats.defense, b.stats.footwork, b.stats.heart };
            for (int i = 0; i < names.Length; i++)
            {
                float fa = Mathf.Clamp01(va2[i] / 100f), fb = Mathf.Clamp01(vb2[i] / 100f);
                UISkin.Rect(new Rect(r.x + 120, y + 6, 400, 10), new Color(0, 0, 0, 0.6f));
                UISkin.Rect(new Rect(r.x + 520 - 400 * fa, y + 6, 400 * fa, 10), Palette.Red);
                UISkin.Text(new Rect(r.x + 540, y, 200, 22), names[i], C, UISkin.Dim);
                UISkin.Rect(new Rect(r.xMax - 520, y + 6, 400, 10), new Color(0, 0, 0, 0.6f));
                UISkin.Rect(new Rect(r.xMax - 520, y + 6, 400 * fb, 10), Palette.Blue);
                y += 24;
            }
            UISkin.Text(new Rect(r.x, r.yMax - 46, r.width, 30), "\"" + b.bio + "\"", UISkin.center, UISkin.Dim);
            UISkin.Text(new Rect(r.x, r.yMax + 20, r.width, 30), (TouchControls.Active ? "Tap TOUCH GLOVES" : "[SPACE] Touch gloves"), UISkin.centerBig, Color.Lerp(Color.white, Palette.Yellow, Mathf.PingPong(Time.unscaledTime, 1f)));
        }

        void DrawFightResult(BoxingMatch m)
        {
            var r = new Rect(W * 0.5f - 700, H * 0.5f - 380, 1400, 760);
            UISkin.Rect(new Rect(0, 0, W, H), new Color(0, 0, 0, 0.35f));
            GUI.Box(r, GUIContent.none, UISkin.panel);
            var winCol = m.draw ? Color.white : m.winner == m.Red ? Palette.Yellow : Palette.Red;
            UISkin.Text(new Rect(r.x, r.y + 20, r.width, 70), m.resultTitle, UISkin.title, winCol);
            UISkin.Text(new Rect(r.x, r.y + 92, r.width, 30), m.resultMethod, UISkin.centerBig, Color.white);
            // scorecards
            float y = r.y + 150;
            UISkin.Text(new Rect(r.x + 40, y, 600, 26), "OFFICIAL SCORECARDS", UISkin.tiny, UISkin.Dim);
            y += 28;
            foreach (var j in m.judges)
            {
                string rounds = "";
                for (int i = 0; i < j.red.Count; i++) rounds += j.red[i] + "-" + j.blue[i] + "  ";
                UISkin.Text(new Rect(r.x + 40, y, 260, 26), j.name, UISkin.label, Color.white);
                UISkin.Text(new Rect(r.x + 300, y, 140, 26), j.Red + " - " + j.Blue, UISkin.labelBig, j.Red > j.Blue ? Palette.Red * 1.3f : j.Blue > j.Red ? new Color(0.45f, 0.65f, 1f) : Color.white);
                UISkin.Text(new Rect(r.x + 450, y + 2, 260, 26), rounds, UISkin.tiny, UISkin.Dim);
                y += 30;
            }
            if (m.judges.Count > 0 && m.judges[0].red.Count == 0) UISkin.Text(new Rect(r.x + 40, y, 600, 26), "(the fight never went to the cards)", UISkin.tiny, UISkin.Dim);
            // compubox
            float x0 = r.x + 760; y = r.y + 150;
            UISkin.Text(new Rect(x0, y, 600, 26), "PUNCH STATS", UISkin.tiny, UISkin.Dim);
            y += 28;
            var a = m.Red.total; var b = m.Blue.total;
            void Stat(string label, string va, string vb)
            {
                UISkin.Text(new Rect(x0, y, 220, 26), label, UISkin.labelSmall, UISkin.Dim);
                UISkin.Text(new Rect(x0 + 230, y, 180, 26), va, UISkin.label, Palette.Red * 1.3f);
                UISkin.Text(new Rect(x0 + 420, y, 180, 26), vb, UISkin.label, new Color(0.45f, 0.65f, 1f));
                y += 28;
            }
            Stat("", m.Red.profile.name.Split(' ')[0], m.Blue.profile.name.Split(' ')[0]);
            Stat("Total punches", a.landed + "/" + a.thrown + " " + RoundStats.Pct(a.landed, a.thrown), b.landed + "/" + b.thrown + " " + RoundStats.Pct(b.landed, b.thrown));
            Stat("Jabs", a.jabsLanded + "/" + a.jabsThrown, b.jabsLanded + "/" + b.jabsThrown);
            Stat("Power punches", a.powerLanded + "/" + a.powerThrown, b.powerLanded + "/" + b.powerThrown);
            Stat("Body / head", a.bodyLanded + " / " + a.headLanded, b.bodyLanded + " / " + b.headLanded);
            Stat("Counters", a.counters.ToString(), b.counters.ToString());
            Stat("Knockdowns", a.knockdowns.ToString(), b.knockdowns.ToString());
            Stat("Evaded / blocked", a.evaded + " / " + a.blocked, b.evaded + " / " + b.blocked);
            // rewards
            y = r.yMax - 190;
            UISkin.Rect(new Rect(r.x + 40, y, r.width - 80, 1), UISkin.Accent * 0.5f);
            UISkin.Text(new Rect(r.x + 40, y + 14, 900, 30), "PURSE  " + Util.Credits(m.purse) + "     XP  +" + m.xp + "     CAREER  " + Flags.Get("box_w") + "-" + Flags.Get("box_l") + (Flags.Get("box_d") > 0 ? "-" + Flags.Get("box_d") : "") + "  (" + Flags.Get("box_ko") + " KO)     PIT RANK  " + (Boxing.IsChampion ? "CHAMPION" : "#" + (Boxing.Roster.Count - Boxing.Rank + 1)), UISkin.labelBig, Color.white);
            var inj = m.Red.rig.injury;
            if (inj != null && inj.FaceDamage > 0.15f) UISkin.Text(new Rect(r.x + 40, y + 52, 1000, 26), "Your face will carry this one for a while. Rest, or let Doc Reyes stitch you up.", UISkin.labelSmall, Palette.Orange);
            if (UISkin.Button(new Rect(r.xMax - 300, r.yMax - 90, 260, 60), "LEAVE THE RING") || InputHub.KeyDown(KeyCode.Return)) m.Close();
        }

        // ================================================================== the Pit menu (Promoter Chaz)
        public void OpenPit() { pitTab = 0; exhibitionPick = -1; OpenModal(Modal.Pit); }

        void DrawPit()
        {
            var area = Window(1260, 760, "THE PIT  //  PROMOTER CHAZ");
            string[] tabs = { "FIGHT CARD", "TRAINING", "MEDICAL" };
            for (int i = 0; i < tabs.Length; i++)
                if (GUI.Button(new Rect(area.x + i * 210, area.y, 200, 40), tabs[i], pitTab == i ? UISkin.tabSel : UISkin.tab)) pitTab = i;
            var body = new Rect(area.x, area.y + 54, area.width, area.height - 54);
            UISkin.Text(new Rect(area.xMax - 560, area.y + 6, 560, 30), "RECORD " + Flags.Get("box_w") + "-" + Flags.Get("box_l") + "  (" + Flags.Get("box_ko") + " KO)   " + Util.Credits(Game.Stats.Money), UISkin.right, Color.white);
            if (pitTab == 0) PitCard(body);
            else if (pitTab == 1) PitTraining(body);
            else PitMedical(body);
        }

        void PitCard(Rect r)
        {
            var roster = Boxing.Roster;
            float y = r.y;
            UISkin.Text(new Rect(r.x, y, 560, 24), "RANKINGS", UISkin.tiny, UISkin.Dim);
            y += 26;
            for (int i = roster.Count - 1; i >= 0; i--)
            {
                var f = roster[i];
                bool beaten = i < Boxing.Rank;
                bool next = i == Boxing.Rank;
                var row = new Rect(r.x, y, 560, 52);
                UISkin.Rect(row, next ? new Color(0.3f, 0.05f, 0.08f, 0.7f) : new Color(0, 0, 0, 0.35f));
                if (exhibitionPick == i) UISkin.Frame(row, Palette.Cyan, 2);
                UISkin.Text(new Rect(row.x + 10, row.y + 4, 60, 44), i == roster.Count - 1 ? "C" : "#" + (roster.Count - i), UISkin.centerBig, i == roster.Count - 1 ? Palette.Yellow : Color.white);
                UISkin.Text(new Rect(row.x + 76, row.y + 4, 360, 26), f.FullName, UISkin.label, beaten ? UISkin.Dim : Color.white);
                UISkin.Text(new Rect(row.x + 76, row.y + 28, 360, 20), f.Record + "  " + Boxing.StyleName(f.style) + (f.southpaw ? "  southpaw" : ""), UISkin.tiny, UISkin.Dim);
                UISkin.Text(new Rect(row.x + 430, row.y + 12, 120, 26), beaten ? "<color=#40ff70>BEATEN</color>" : next ? "<color=#ffd633>NEXT</color>" : "", UISkin.right, Color.white);
                if (beaten && GUI.Button(row, GUIContent.none, GUIStyle.none)) exhibitionPick = exhibitionPick == i ? -1 : i;
                y += 56;
            }
            // next fight card
            var opp = exhibitionPick >= 0 ? roster[exhibitionPick] : Boxing.NextOpponent;
            var card = new Rect(r.x + 600, r.y, r.width - 600, r.height);
            GUI.Box(card, GUIContent.none, UISkin.panelDark);
            float cy = card.y + 16;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 24), exhibitionPick >= 0 ? "EXHIBITION REMATCH" : Boxing.IsChampion ? "TITLE DEFENCE" : "NEXT FIGHT", UISkin.tiny, Palette.Yellow);
            cy += 26;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 40), opp.FullName, UISkin.header, Color.white);
            cy += 44;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 70), opp.bio, UISkin.label, UISkin.Dim);
            cy += 76;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 24), Boxing.StyleName(opp.style) + ": " + Boxing.StyleDesc(opp.style), UISkin.labelSmall, Color.white);
            cy += 34;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 24), "Record " + opp.Record + "    " + opp.heightCm + " cm    reach " + opp.reachCm + " cm    " + opp.weightKg + " kg", UISkin.labelSmall, Color.white);
            cy += 30;
            UISkin.Text(new Rect(card.x + 20, cy, card.width - 40, 24), opp.rounds + " rounds    Purse " + Util.Credits(opp.purse) + (exhibitionPick >= 0 ? " (exhibition)" : ""), UISkin.labelSmall, Palette.Green);
            cy += 40;
            var me = Boxing.PlayerFighter();
            string[] names = { "Power", "Speed", "Engine", "Chin", "Defense", "Footwork", "Heart" };
            float[] a = { me.stats.power, me.stats.speed, me.stats.engine, me.stats.chin, me.stats.defense, me.stats.footwork, me.stats.heart };
            float[] b = { opp.stats.power, opp.stats.speed, opp.stats.engine, opp.stats.chin, opp.stats.defense, opp.stats.footwork, opp.stats.heart };
            UISkin.Text(new Rect(card.x + 20, cy, 300, 20), "YOU  vs  " + opp.name.Split(' ')[0].ToUpperInvariant(), UISkin.tiny, UISkin.Dim);
            cy += 22;
            for (int i = 0; i < names.Length; i++)
            {
                UISkin.Text(new Rect(card.x + 20, cy, 120, 20), names[i], UISkin.tiny, Color.white);
                UISkin.Bar(new Rect(card.x + 140, cy + 3, 220, 6), a[i] / 100f, Palette.Cyan, new Color(0, 0, 0, 0.6f));
                UISkin.Bar(new Rect(card.x + 380, cy + 3, 220, 6), b[i] / 100f, Palette.Red, new Color(0, 0, 0, 0.6f));
                cy += 20;
            }
            if (Boxing.PlayerInjuries.Any && Boxing.PlayerInjuries.concussion + Boxing.PlayerInjuries.swell[0] + Boxing.PlayerInjuries.swell[1] > 0.3f)
                UISkin.Text(new Rect(card.x + 20, card.yMax - 120, card.width - 40, 40), "You're still hurt from your last fight - you'll start this one damaged.", UISkin.labelSmall, Palette.Orange);
            if (UISkin.Button(new Rect(card.x + 20, card.yMax - 74, card.width - 40, 56), "FIGHT  (walk to the ring)"))
            {
                CloseModal();
                Game.Activities.StartBoxingMatch(opp);
            }
        }

        void PitTraining(Rect r)
        {
            UISkin.Text(new Rect(r.x, r.y, r.width, 50), "Coach Ma Ruiz runs your camp. Every session costs money and sweat. Gains are permanent.", UISkin.label, UISkin.Dim);
            float y = r.y + 60;
            for (int i = 0; i < Boxing.TrainKeys.Length; i++)
            {
                int lv = Boxing.TrainLevel(i);
                var row = new Rect(r.x, y, r.width, 70);
                GUI.Box(row, GUIContent.none, UISkin.box);
                UISkin.Text(new Rect(row.x + 16, row.y + 8, 500, 28), Boxing.TrainNames[i], UISkin.labelBig, Color.white);
                for (int k = 0; k < Boxing.TrainMax; k++) UISkin.Rect(new Rect(row.x + 16 + k * 34, row.y + 44, 28, 12), k < lv ? Palette.Cyan : new Color(0, 0, 0, 0.5f));
                bool maxed = lv >= Boxing.TrainMax;
                int cost = Boxing.TrainCost(i);
                if (!maxed && UISkin.Button(new Rect(row.xMax - 240, row.y + 12, 220, 46), "TRAIN  " + Util.Credits(cost)))
                {
                    if (Game.Stats.Spend(cost))
                    {
                        Flags.Add(Boxing.TrainKeys[i], 1);
                        Game.Env?.SkipHours(2f);
                        Fade(0.8f);
                        Notify(Boxing.TrainNames[i].Split('(')[0].Trim() + " improved!", Palette.Green);
                        Game.Audio?.Play2D("levelup", 0.5f);
                    }
                    else Notify("Not enough cash", Palette.Red);
                }
                if (maxed) UISkin.Text(new Rect(row.xMax - 240, row.y + 20, 220, 30), "MAXED", UISkin.right, Palette.Yellow);
                y += 78;
            }
        }

        void PitMedical(Rect r)
        {
            var inj = Boxing.PlayerInjuries;
            UISkin.Text(new Rect(r.x, r.y, r.width, 50), "The Pit's cutman, Old Tomas, can patch you up. Wounds also heal by themselves over time and when you sleep.", UISkin.label, UISkin.Dim);
            float y = r.y + 70;
            void Line(string label, float v)
            {
                UISkin.Text(new Rect(r.x, y, 320, 26), label, UISkin.label, Color.white);
                UISkin.Bar(new Rect(r.x + 330, y + 8, 500, 10), Mathf.Clamp01(v), v > 0.5f ? Palette.Red : Palette.Orange, new Color(0, 0, 0, 0.6f));
                y += 34;
            }
            float cuts = 0, swell = 0;
            for (int i = 0; i < inj.cut.Length; i++) { cuts = Mathf.Max(cuts, inj.cut[i]); swell = Mathf.Max(swell, inj.swell[i]); }
            Line("Cuts", cuts);
            Line("Swelling", swell);
            Line("Concussion", inj.concussion);
            Line("Body trauma", inj.bodyTrauma);
            y += 20;
            int cost = Mathf.RoundToInt(120 + (cuts + swell + inj.concussion + inj.bodyTrauma) * 400);
            if (!inj.Any) UISkin.Text(new Rect(r.x, y, 600, 30), "You're fight-ready.", UISkin.labelBig, Palette.Green);
            else if (UISkin.Button(new Rect(r.x, y, 360, 56), "PATCH ME UP  " + Util.Credits(cost)))
            {
                if (Game.Stats.Spend(cost)) { Boxing.PlayerInjuries = new InjuryRecord(); Notify("Stitched, iced and ready to bleed again.", Palette.Green); Game.Audio?.Play2D("quest_done", 0.5f); }
                else Notify("Not enough cash", Palette.Red);
            }
        }
    }
}
