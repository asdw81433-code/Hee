using UnityEngine;

namespace NeonBay
{
    /// <summary>Studio scene + UI for building your character (identity, origin, attributes, appearance).</summary>
    public class CreatorStudio : MonoBehaviour
    {
        public RenderTexture rt;
        Camera cam;
        Transform turntable;
        HumanoidRig rig;
        string builtKey;
        public float spin = 200f;
        public bool zoomFace, boxerPreview;
        float zoomBlend;

        public static CreatorStudio Create()
        {
            var go = new GameObject("CreatorStudio");
            go.transform.position = new Vector3(0, -400f, 0);
            var s = go.AddComponent<CreatorStudio>();
            s.Build();
            return s;
        }

        void Build()
        {
            rt = new RenderTexture(560, 820, 24, RenderTextureFormat.DefaultHDR) { antiAliasing = 4 };
            var floorMat = Mats.Lit(new Color(0.05f, 0.05f, 0.07f), Tex.Metal.albedo, 0.8f, 0.6f, Tex.Metal.normal);
            var floor = Util.Primitive(PrimitiveType.Cylinder, "Floor", transform, new Vector3(0, -0.05f, 0), new Vector3(3f, 0.05f, 3f), floorMat);
            Util.Primitive(PrimitiveType.Cylinder, "Ring", transform, new Vector3(0, -0.02f, 0), new Vector3(3.1f, 0.03f, 3.1f), Mats.Unlit(Palette.Magenta * 2.5f));
            var back = Util.Primitive(PrimitiveType.Quad, "Backdrop", transform, new Vector3(0, 1.5f, 3f), new Vector3(10f, 6f, 1f), Mats.Unlit(new Color(0.03f, 0.04f, 0.08f), Tex.Scanlines));
            turntable = new GameObject("Turntable").transform;
            turntable.SetParent(transform, false);
            void L(Vector3 p, Color c, float i, float range)
            {
                var l = new GameObject("Light").AddComponent<Light>();
                l.transform.SetParent(transform, false);
                l.transform.localPosition = p;
                l.type = LightType.Point; l.color = c; l.intensity = i; l.range = range; l.shadows = LightShadows.None;
            }
            L(new Vector3(-1.6f, 2.2f, -1.4f), new Color(1f, 0.85f, 0.75f), 2.2f, 8f);
            L(new Vector3(1.8f, 1.6f, -0.6f), Palette.Cyan, 2.4f, 7f);
            L(new Vector3(0.5f, 2.6f, 1.6f), Palette.Magenta, 3f, 7f);
            var cg = new GameObject("StudioCam");
            cg.transform.SetParent(transform, false);
            cg.transform.localPosition = new Vector3(0, 1.15f, -3.4f);
            cg.transform.localRotation = Quaternion.Euler(4f, 0, 0);
            cam = cg.AddComponent<Camera>();
            cam.targetTexture = rt;
            cam.fieldOfView = 34f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.01f, 0.01f, 0.02f);
            cam.nearClipPlane = 0.1f; cam.farClipPlane = 20f;
            PostFX.SetupCamera(cam);
        }

        public void Show(CharacterProfile p)
        {
            string key = p.frame + "|" + p.skin + "|" + p.hairStyle + "|" + p.hairColor + "|" + p.eyeColor + "|" + p.accent + "|" + p.faceTattoo + "|" + p.height.ToString("0.00") + "|" + p.jacket + "|" + p.origin
                + "|" + p.beard + "|" + p.beardColor + "|" + p.brows + "|" + p.female + "|" + p.jaw.ToString("0.0") + "|" + p.muscle.ToString("0.00") + "|" + p.trunksColor + "|" + p.gloveColor + "|" + boxerPreview;
            if (key == builtKey) return;
            builtKey = key;
            if (rig != null) Destroy(rig.gameObject);
            var look = Appearance.FromProfile(p);
            if (boxerPreview) look.outfit = 1;
            rig = HumanoidRig.Build(turntable, look, null, false);
            rig.forceNear = true;
        }

        void Update()
        {
            if (turntable != null) turntable.localRotation = Quaternion.Euler(0, spin, 0);
            if (rig != null)
            {
                rig.Animate(0f, false, false, Time.unscaledDeltaTime);
                if (cam != null) rig.LookAt(cam.transform.position);
            }
            zoomBlend = Mathf.MoveTowards(zoomBlend, zoomFace ? 1f : 0f, Time.unscaledDeltaTime * 3f);
            if (cam != null)
            {
                float k = zoomBlend * zoomBlend * (3f - 2f * zoomBlend);
                float headY = rig != null && rig.head != null ? rig.head.position.y - transform.position.y + 0.13f : 1.72f;
                cam.transform.localPosition = Vector3.Lerp(new Vector3(0, 1.15f, -3.4f), new Vector3(0, headY, -0.95f), k);
                cam.transform.localRotation = Quaternion.Euler(Mathf.Lerp(4f, 0f, k), 0, 0);
                cam.fieldOfView = Mathf.Lerp(34f, 30f, k);
            }
        }

        void OnDestroy()
        {
            if (rt != null) rt.Release();
        }
    }

    public partial class UIManager
    {
        CharacterProfile draft;
        CreatorStudio studio;
        int creatorTab;
        static readonly Color[] jackets =
        {
            new Color(0.12f, 0.12f, 0.15f), new Color(0.5f, 0.08f, 0.12f), new Color(0.1f, 0.25f, 0.45f), new Color(0.75f, 0.75f, 0.78f),
            new Color(0.2f, 0.35f, 0.18f), new Color(0.55f, 0.35f, 0.1f), new Color(0.35f, 0.1f, 0.45f), new Color(0.05f, 0.05f, 0.05f)
        };
        const int CreatorPool = 7;

        public void BeginCreator()
        {
            draft = new CharacterProfile { name = "Vega", attributes = new[] { 3, 3, 3, 3, 3 }, appearanceVersion = 2, hairStyle = 4, beard = 1, muscle = 0.55f };
            if (studio == null) studio = CreatorStudio.Create();
            creatorTab = 0;
        }

        int PointsLeft()
        {
            int used = 0; foreach (var a in draft.attributes) used += a - 3;
            return CreatorPool - used;
        }

        void DrawCreator()
        {
            if (draft == null) BeginCreator();
            UISkin.Rect(new Rect(0, 0, W, H), new Color(0.01f, 0.01f, 0.02f, 0.94f));
            UISkin.Text(new Rect(60, 30, 900, 50), "CREATE YOUR CHARACTER", UISkin.header, UISkin.Accent);
            string[] tabs = { "IDENTITY", "ATTRIBUTES", "FACE & HAIR", "BODY & STYLE", "FIGHTER" };
            for (int i = 0; i < tabs.Length; i++)
                if (GUI.Button(new Rect(60 + i * 172, 90, 164, 44), tabs[i], creatorTab == i ? UISkin.tabSel : UISkin.tab)) creatorTab = i;
            if (studio != null) { studio.zoomFace = creatorTab == 2; studio.boxerPreview = creatorTab == 4; }

            // preview
            if (studio != null)
            {
                studio.Show(draft);
                var pr = new Rect(W - 640, 90, 560, 820);
                UISkin.Rect(new Rect(pr.x - 2, pr.y - 2, pr.width + 4, pr.height + 4), UISkin.Accent.WithAlpha(0.5f));
                GUI.DrawTexture(pr, studio.rt, ScaleMode.ScaleAndCrop, false);
                var e = Event.current;
                if (e.type == EventType.MouseDrag && pr.Contains(e.mousePosition)) { studio.spin -= e.delta.x * 0.6f; e.Use(); }
                UISkin.Text(new Rect(pr.x, pr.yMax + 6, pr.width, 24), "drag to rotate", UISkin.center, UISkin.Dim);
            }

            var area = new Rect(60, 150, W - 780, H - 260);
            GUILayout.BeginArea(area);
            switch (creatorTab)
            {
                case 0:
                    GUILayout.Label("NAME", UISkin.glow);
                    GUI.SetNextControlName("name");
                    draft.name = GUILayout.TextField(draft.name, 18, UISkin.field, GUILayout.Height(44), GUILayout.Width(420));
                    InputHub.Typing = GUI.GetNameOfFocusedControl() == "name";
                    GUILayout.Space(14);
                    GUILayout.Label("ORIGIN", UISkin.glow);
                    foreach (Origin o in System.Enum.GetValues(typeof(Origin)))
                    {
                        if (GUILayout.Button("<b>" + CharacterProfile.OriginName(o).ToUpperInvariant() + "</b>\n<size=14>" + CharacterProfile.OriginDesc(o) + "</size>", draft.origin == o ? UISkin.buttonSel : UISkin.button, GUILayout.Height(108)))
                            draft.origin = o;
                    }
                    GUILayout.Space(14);
                    GUILayout.Label("DIFFICULTY", UISkin.glow);
                    GUILayout.BeginHorizontal();
                    string[] dn = { "STORY", "NORMAL", "HARD", "BRUTAL" };
                    for (int i = 0; i < 4; i++) if (GUILayout.Button(dn[i], draft.difficulty == i ? UISkin.tabSel : UISkin.tab, GUILayout.Height(40), GUILayout.Width(150))) draft.difficulty = i;
                    GUILayout.EndHorizontal();
                    break;
                case 1:
                    GUILayout.Label("Distribute " + CreatorPool + " points. Points left: <color=#ffd633>" + PointsLeft() + "</color>   (max 6 at creation, 15 later)", UISkin.label);
                    GUILayout.Space(10);
                    string[] info =
                    {
                        "BODY - health, melee damage, intimidation checks.",
                        "REFLEX - movement, stamina, recoil, reload speed.",
                        "TECH - armor, better prices, grenades, vehicles, tech dialogue.",
                        "NEURAL - RAM, quickhack damage, breaching terminals.",
                        "COOL - critical hits, stealth, persuasion checks."
                    };
                    for (int i = 0; i < 5; i++)
                    {
                        GUILayout.BeginHorizontal(UISkin.box);
                        GUILayout.Label(info[i], UISkin.label, GUILayout.Width(area.width - 260));
                        GUI.enabled = draft.attributes[i] > 3;
                        if (GUILayout.Button("-", UISkin.tab, GUILayout.Width(50), GUILayout.Height(44))) draft.attributes[i]--;
                        GUI.enabled = true;
                        GUILayout.Label(draft.attributes[i].ToString(), UISkin.centerBig, GUILayout.Width(60), GUILayout.Height(44));
                        GUI.enabled = PointsLeft() > 0 && draft.attributes[i] < 6;
                        if (GUILayout.Button("+", UISkin.tab, GUILayout.Width(50), GUILayout.Height(44))) draft.attributes[i]++;
                        GUI.enabled = true;
                        GUILayout.EndHorizontal();
                    }
                    GUILayout.Label("Your origin adds +1 to one attribute when the game starts. Dialogue skill checks show up as [COOL 6], [TECH 5] etc.", UISkin.labelSmall);
                    break;
                case 2:
                    creatorScroll = GUILayout.BeginScrollView(creatorScroll, GUILayout.Width(area.width), GUILayout.Height(area.height));
                    Picker("HAIR", ref draft.hairStyle, BodyBuilder.HairStyles, BodyBuilder.HairName);
                    Picker("HAIR COLOR", ref draft.hairColor, Palette.HairColors.Length, HairColorName);
                    GUI.enabled = !draft.female;
                    Picker("FACIAL HAIR", ref draft.beard, BodyBuilder.BeardStyles, BodyBuilder.BeardName);
                    GUI.enabled = true;
                    int bc = draft.beardColor + 1;
                    Picker("BEARD COLOR", ref bc, Palette.HairColors.Length + 1, i => i == 0 ? "Match hair" : HairColorName(i - 1)); draft.beardColor = bc - 1;
                    Picker("EYEBROWS", ref draft.brows, BodyBuilder.BrowStyles, BodyBuilder.BrowName);
                    Slider("JAWLINE", ref draft.jaw, 0f, 1f, draft.jaw < 0.35f ? "Narrow" : draft.jaw < 0.7f ? "Average" : "Square");
                    int eye = System.Array.IndexOf(Palette.Neon, draft.eyeColor); if (eye < 0) eye = 0;
                    Picker("CYBER-OPTICS", ref eye, Palette.Neon.Length, i => "Glow " + (i + 1)); draft.eyeColor = Palette.Neon[eye];
                    GUILayout.BeginHorizontal();
                    GUILayout.Label("FACE TATTOO", UISkin.label, GUILayout.Width(200));
                    if (GUILayout.Button(draft.faceTattoo ? "GLOWING" : "NONE", draft.faceTattoo ? UISkin.tabSel : UISkin.tab, GUILayout.Width(200), GUILayout.Height(38))) draft.faceTattoo = !draft.faceTattoo;
                    GUILayout.EndHorizontal();
                    GUILayout.Space(8);
                    GUILayout.Label("The camera zooms in on your face while this tab is open. Drag the preview to turn your head.", UISkin.labelSmall);
                    GUILayout.EndScrollView();
                    break;
                case 3:
                    GUILayout.BeginHorizontal();
                    GUILayout.Label("BODY TYPE", UISkin.label, GUILayout.Width(200));
                    if (GUILayout.Button("MASCULINE", !draft.female ? UISkin.tabSel : UISkin.tab, GUILayout.Width(150), GUILayout.Height(38))) draft.female = false;
                    if (GUILayout.Button("FEMININE", draft.female ? UISkin.tabSel : UISkin.tab, GUILayout.Width(150), GUILayout.Height(38))) { draft.female = true; draft.beard = 0; }
                    GUILayout.EndHorizontal();
                    GUILayout.Space(4);
                    Picker("FRAME", ref draft.frame, 3, i => CharacterProfile.FrameName(i));
                    Slider("MUSCLE DEFINITION", ref draft.muscle, 0f, 1f, draft.muscle < 0.3f ? "Soft" : draft.muscle < 0.65f ? "Athletic" : "Shredded");
                    Picker("SKIN", ref draft.skin, Palette.SkinTones.Length, i => i == Palette.SkinTones.Length - 1 ? "Full Chrome" : "Tone " + (i + 1));
                    int acc = System.Array.IndexOf(Palette.Neon, draft.accent); if (acc < 0) acc = 1;
                    Picker("NEON ACCENTS", ref acc, Palette.Neon.Length, i => "Glow " + (i + 1)); draft.accent = Palette.Neon[acc];
                    int jk = System.Array.IndexOf(jackets, draft.jacket); if (jk < 0) jk = 0;
                    Picker("JACKET", ref jk, jackets.Length, i => "Style " + (i + 1)); draft.jacket = jackets[jk];
                    GUILayout.BeginHorizontal();
                    GUILayout.Label("HEIGHT", UISkin.label, GUILayout.Width(200));
                    draft.height = GUILayout.HorizontalSlider(draft.height, 0.92f, 1.08f, GUILayout.Width(300));
                    GUILayout.Label(Mathf.RoundToInt(178 * draft.height) + " cm", UISkin.labelSmall, GUILayout.Width(90));
                    GUILayout.EndHorizontal();
                    break;
                case 4:
                    GUILayout.Label("Your persona in THE PIT, Neon Bay's underground boxing ring.", UISkin.labelSmall);
                    GUILayout.Space(6);
                    GUILayout.Label("RING NAME (nickname)", UISkin.glow);
                    GUI.SetNextControlName("nick");
                    draft.nickname = GUILayout.TextField(draft.nickname ?? "", 18, UISkin.field, GUILayout.Height(44), GUILayout.Width(420));
                    InputHub.Typing = GUI.GetNameOfFocusedControl() == "nick" || GUI.GetNameOfFocusedControl() == "name";
                    GUILayout.Space(8);
                    GUILayout.BeginHorizontal();
                    GUILayout.Label("STANCE", UISkin.label, GUILayout.Width(200));
                    if (GUILayout.Button("ORTHODOX", !draft.southpaw ? UISkin.tabSel : UISkin.tab, GUILayout.Width(150), GUILayout.Height(38))) draft.southpaw = false;
                    if (GUILayout.Button("SOUTHPAW", draft.southpaw ? UISkin.tabSel : UISkin.tab, GUILayout.Width(150), GUILayout.Height(38))) draft.southpaw = true;
                    GUILayout.EndHorizontal();
                    GUILayout.Space(4);
                    Picker("TRUNKS", ref draft.trunksColor, Boxing.TrunkColors.Length, i => Boxing.TrunkNames[i]);
                    Picker("GLOVES", ref draft.gloveColor, Boxing.GloveColors.Length, i => Boxing.GloveNames[i]);
                    GUILayout.Space(8);
                    GUILayout.Label("BODY feeds your power and chin, REFLEX your hand speed, defense and footwork, COOL your heart. Train with Coach Ma Ruiz in the Pit to improve further.", UISkin.labelSmall);
                    break;
            }
            GUILayout.EndArea();

            if (UISkin.Button(new Rect(60, H - 90, 220, 54), "BACK")) { InputHub.Typing = false; DestroyStudio(); Game.Manager.SetState(GameState.MainMenu); }
            bool ready = !string.IsNullOrWhiteSpace(draft.name);
            GUI.enabled = ready;
            if (UISkin.Button(new Rect(300, H - 90, 380, 54), "BEGIN IN NEON BAY  >>"))
            {
                InputHub.Typing = false;
                draft.name = draft.name.Trim();
                var p = draft;
                DestroyStudio();
                Game.Manager.StartNewGame(p);
            }
            GUI.enabled = true;
            if (PointsLeft() > 0) UISkin.Text(new Rect(700, H - 80, 600, 30), "You still have " + PointsLeft() + " attribute points to spend.", UISkin.labelSmall, UISkin.Warn);
        }

        Vector2 creatorScroll;
        static string HairColorName(int i) => i switch { 0 => "Black", 1 => "Brown", 2 => "Blonde", 3 => "Silver", 4 => "Neon Magenta", 5 => "Neon Cyan", 6 => "Red", 7 => "Toxic Green", _ => "Violet" };

        void Slider(string label, ref float value, float min, float max, string text)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, UISkin.label, GUILayout.Width(200));
            value = GUILayout.HorizontalSlider(value, min, max, GUILayout.Width(300));
            GUILayout.Label(text, UISkin.labelSmall, GUILayout.Width(120));
            GUILayout.EndHorizontal();
            GUILayout.Space(6);
        }

        void DestroyStudio()
        {
            if (studio != null) Destroy(studio.gameObject);
            studio = null;
        }

        void Picker(string label, ref int value, int count, System.Func<int, string> name)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, UISkin.label, GUILayout.Width(200));
            if (GUILayout.Button("<", UISkin.tab, GUILayout.Width(48), GUILayout.Height(38))) value = (value - 1 + count) % count;
            GUILayout.Label(name(value), UISkin.center, GUILayout.Width(200), GUILayout.Height(38));
            if (GUILayout.Button(">", UISkin.tab, GUILayout.Width(48), GUILayout.Height(38))) value = (value + 1) % count;
            GUILayout.EndHorizontal();
            GUILayout.Space(4);
        }
    }
}
