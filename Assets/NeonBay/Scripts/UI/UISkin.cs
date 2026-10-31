using UnityEngine;

namespace NeonBay
{
    /// <summary>Neon IMGUI skin generated in code (no assets): panels, buttons, bars and fonts.</summary>
    public static class UISkin
    {
        public static GUIStyle panel, panelDark, button, buttonSel, label, labelSmall, labelBig, title, header, center, centerBig, right, tiny, box, tab, tabSel, field, mono, glow;
        public static Texture2D white, panelTex, panelDarkTex, buttonTex, buttonHover, buttonActive, buttonSelTex, lineTex, vignette, scopeTex, gradTex, circleTex;
        public static Font font, fontBold, fontMono;
        static bool built;
        public static readonly Color Accent = new Color(0.1f, 0.95f, 1f);
        public static readonly Color Accent2 = new Color(1f, 0.15f, 0.7f);
        public static readonly Color TextColor = new Color(0.88f, 0.94f, 1f);
        public static readonly Color Dim = new Color(0.55f, 0.62f, 0.7f);
        public static readonly Color Warn = new Color(1f, 0.82f, 0.2f);

        static Texture2D Tex9(Color fill, Color border, int corner, bool cut)
        {
            int s = 32;
            var t = new Texture2D(s, s, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Point };
            var px = new Color[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    bool edge = x == 0 || y == 0 || x == s - 1 || y == s - 1;
                    bool cutCorner = cut && (x + (s - 1 - y)) < corner; // top-left cut
                    bool cutCorner2 = cut && ((s - 1 - x) + y) < corner; // bottom-right cut
                    if (cutCorner || cutCorner2) { px[y * s + x] = Color.clear; continue; }
                    bool diag = cut && ((x + (s - 1 - y)) == corner || ((s - 1 - x) + y) == corner);
                    var c = edge || diag ? border : fill;
                    // subtle scanline in the fill
                    if (!edge && !diag && y % 3 == 0) c = new Color(c.r * 1.08f, c.g * 1.08f, c.b * 1.08f, c.a);
                    px[y * s + x] = c;
                }
            t.SetPixels(px);
            t.Apply();
            return t;
        }

        static Texture2D Solid(Color c)
        {
            var t = new Texture2D(2, 2) { wrapMode = TextureWrapMode.Clamp };
            t.SetPixels(new[] { c, c, c, c });
            t.Apply();
            return t;
        }

        public static void Build()
        {
            if (built) return;
            built = true;
            white = Solid(Color.white);
            panelTex = Tex9(new Color(0.03f, 0.05f, 0.08f, 0.88f), new Color(0.1f, 0.85f, 1f, 0.9f), 6, true);
            panelDarkTex = Tex9(new Color(0.01f, 0.015f, 0.025f, 0.94f), new Color(0.1f, 0.5f, 0.6f, 0.7f), 0, false);
            buttonTex = Tex9(new Color(0.05f, 0.09f, 0.13f, 0.92f), new Color(0.1f, 0.6f, 0.75f, 0.9f), 4, true);
            buttonHover = Tex9(new Color(0.06f, 0.25f, 0.32f, 0.95f), new Color(0.2f, 1f, 1f, 1f), 4, true);
            buttonActive = Tex9(new Color(0.5f, 0.05f, 0.35f, 0.95f), new Color(1f, 0.3f, 0.8f, 1f), 4, true);
            buttonSelTex = Tex9(new Color(0.35f, 0.05f, 0.3f, 0.95f), new Color(1f, 0.25f, 0.8f, 1f), 4, true);
            lineTex = Solid(new Color(0.1f, 0.95f, 1f, 0.8f));

            int vs = 128;
            vignette = new Texture2D(vs, vs, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            scopeTex = new Texture2D(vs * 2, vs * 2, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            circleTex = new Texture2D(64, 64, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < vs; y++)
                for (int x = 0; x < vs; x++)
                {
                    float dx = x / (float)vs * 2 - 1, dy = y / (float)vs * 2 - 1;
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    vignette.SetPixel(x, y, new Color(1, 1, 1, Mathf.Clamp01((d - 0.55f) * 1.6f)));
                }
            vignette.Apply();
            for (int y = 0; y < vs * 2; y++)
                for (int x = 0; x < vs * 2; x++)
                {
                    float dx = x / (float)(vs * 2) * 2 - 1, dy = y / (float)(vs * 2) * 2 - 1;
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    float a = d > 0.92f ? 1f : d > 0.9f ? 0.6f : 0f;
                    if ((Mathf.Abs(dx) < 0.004f || Mathf.Abs(dy) < 0.004f) && d < 0.9f && d > 0.04f) a = 0.85f;
                    scopeTex.SetPixel(x, y, new Color(0, 0, 0, a));
                }
            scopeTex.Apply();
            for (int y = 0; y < 64; y++)
                for (int x = 0; x < 64; x++)
                {
                    float dx = x / 64f * 2 - 1, dy = y / 64f * 2 - 1;
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    circleTex.SetPixel(x, y, new Color(1, 1, 1, Mathf.Clamp01((1f - d) * 8f)));
                }
            circleTex.Apply();
            gradTex = new Texture2D(1, 64, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < 64; y++) gradTex.SetPixel(0, y, new Color(0, 0, 0, Mathf.Pow(y / 63f, 1.5f)));
            gradTex.Apply();

            var builtin = Util.LoadBuiltinFont();
            try { font = Font.CreateDynamicFontFromOSFont(new[] { "Bahnschrift", "Segoe UI", "Helvetica Neue", "DejaVu Sans", "Liberation Sans", "Arial", "Tahoma", "Leelawadee UI", "Noto Sans Thai" }, 18); } catch { font = builtin; }
            try { fontMono = Font.CreateDynamicFontFromOSFont(new[] { "Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "Tahoma" }, 16); } catch { fontMono = builtin; }
            if (font == null) font = builtin;
            if (fontMono == null) fontMono = font;
            fontBold = font;

            panel = new GUIStyle { normal = { background = panelTex }, border = new RectOffset(8, 8, 8, 8), padding = new RectOffset(16, 16, 14, 14) };
            panelDark = new GUIStyle(panel) { normal = { background = panelDarkTex }, border = new RectOffset(2, 2, 2, 2) };
            box = new GUIStyle(panelDark);
            label = new GUIStyle { font = font, fontSize = 18, wordWrap = true, richText = true, normal = { background = null, textColor = TextColor } };
            labelSmall = new GUIStyle(label) { fontSize = 15, normal = { textColor = Dim } };
            labelBig = new GUIStyle(label) { fontSize = 24 };
            tiny = new GUIStyle(label) { fontSize = 13, normal = { textColor = Dim } };
            title = new GUIStyle(label) { fontSize = 64, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter, normal = { textColor = Accent }, wordWrap = false };
            header = new GUIStyle(label) { fontSize = 26, fontStyle = FontStyle.Bold, normal = { textColor = Accent } };
            center = new GUIStyle(label) { alignment = TextAnchor.MiddleCenter };
            centerBig = new GUIStyle(label) { alignment = TextAnchor.MiddleCenter, fontSize = 30, fontStyle = FontStyle.Bold };
            right = new GUIStyle(label) { alignment = TextAnchor.MiddleRight };
            mono = new GUIStyle(label) { font = fontMono, fontSize = 16 };
            glow = new GUIStyle(label) { fontStyle = FontStyle.Bold, normal = { textColor = Accent2 } };
            button = new GUIStyle
            {
                font = font, fontSize = 18, alignment = TextAnchor.MiddleLeft, richText = true,
                padding = new RectOffset(16, 12, 6, 6), border = new RectOffset(6, 6, 6, 6),
                normal = { background = buttonTex, textColor = TextColor },
                hover = { background = buttonHover, textColor = Color.white },
                active = { background = buttonActive, textColor = Color.white },
                wordWrap = true
            };
            buttonSel = new GUIStyle(button) { normal = { background = buttonSelTex, textColor = Color.white } };
            tab = new GUIStyle(button) { alignment = TextAnchor.MiddleCenter, fontSize = 16 };
            tabSel = new GUIStyle(buttonSel) { alignment = TextAnchor.MiddleCenter, fontSize = 16 };
            field = new GUIStyle(button) { normal = { background = panelDarkTex, textColor = Color.white }, focused = { background = buttonHover, textColor = Color.white }, hover = { background = panelDarkTex, textColor = Color.white } };
        }

        // ----------------------------------------------------------- drawing helpers
        public static void Rect(Rect r, Color c)
        {
            var old = GUI.color; GUI.color = c;
            GUI.DrawTexture(r, white);
            GUI.color = old;
        }

        public static void Bar(Rect r, float frac, Color fill, Color back, bool segments = false)
        {
            Rect(r, back);
            Rect(new Rect(r.x, r.y, r.width * Mathf.Clamp01(frac), r.height), fill);
            if (segments)
                for (float x = r.x + 10; x < r.xMax; x += 10) Rect(new Rect(x, r.y, 1, r.height), new Color(0, 0, 0, 0.45f));
            Rect(new Rect(r.x, r.yMax, r.width, 1), fill * 0.6f);
        }

        public static void Text(Rect r, string s, GUIStyle st, Color c, bool shadow = true)
        {
            var old = st.normal.textColor;
            if (shadow)
            {
                st.normal.textColor = new Color(0, 0, 0, c.a * 0.8f);
                GUI.Label(new Rect(r.x + 2, r.y + 2, r.width, r.height), s, st);
            }
            st.normal.textColor = c;
            GUI.Label(r, s, st);
            st.normal.textColor = old;
        }

        public static bool Button(Rect r, string s, bool selected = false)
        {
            bool hover = r.Contains(Event.current.mousePosition);
            bool clicked = GUI.Button(r, s, selected ? buttonSel : button);
            if (clicked) Game.Audio?.Play2D("ui_confirm", 0.35f);
            return clicked;
        }

        public static void Frame(Rect r, Color c, float t = 1f)
        {
            Rect(new Rect(r.x, r.y, r.width, t), c);
            Rect(new Rect(r.x, r.yMax - t, r.width, t), c);
            Rect(new Rect(r.x, r.y, t, r.height), c);
            Rect(new Rect(r.xMax - t, r.y, t, r.height), c);
        }

        public static void Diamond(Vector2 c, float size, Color col)
        {
            var m = GUI.matrix;
            GUIUtility.RotateAroundPivot(45f, c);
            Rect(new Rect(c.x - size * 0.5f, c.y - size * 0.5f, size, size), col);
            GUI.matrix = m;
        }
    }
}
