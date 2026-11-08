using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// On-screen controls for phones and tablets. Reads raw touches (legacy Input or the Input System, whichever
    /// is enabled), and turns them into InputHub virtual keys, a floating move stick and drag-to-look, so the rest
    /// of the game runs unchanged. The layout switches with context: on foot, driving, and an Undisputed-style
    /// boxing layout (punch pad, block, duck, latching BODY / POWER modifiers, swipe to slip) with GET UP / SKIP
    /// prompts. Menus stay IMGUI and are tapped directly.
    /// </summary>
    [DefaultExecutionOrder(-1000)]
    public class TouchControls : MonoBehaviour
    {
        public static TouchControls Instance;
        /// <summary>The overlay is drawn and in charge of input this frame.</summary>
        public static bool Active { get; private set; }

        /// <summary>Button names used in prompts ("[USE] Talk") while touch controls are active.</summary>
        public static readonly Dictionary<Btn, string> Labels = new Dictionary<Btn, string>
        {
            { Btn.Interact, "USE" }, { Btn.Vehicle, "CAR" }, { Btn.Jump, "JUMP" }, { Btn.Fire, "FIRE" }, { Btn.Aim, "AIM" },
            { Btn.Reload, "RELOAD" }, { Btn.Holster, "HOLSTER" }, { Btn.Grenade, "NADE" }, { Btn.Melee, "MELEE" },
            { Btn.Scan, "SCAN" }, { Btn.Map, "MAP" }, { Btn.Pause, "II" }, { Btn.CallCar, "CALL" }, { Btn.Skills, "MENU" },
        };

        /// <summary>The device has a touchscreen, so the settings menu offers the touch options.</summary>
        public static bool Supported
        {
            get
            {
                if (Application.isMobilePlatform) return true;
#if ENABLE_INPUT_SYSTEM
                if (UnityEngine.InputSystem.Touchscreen.current != null) return true;
#endif
#if ENABLE_LEGACY_INPUT_MANAGER
                try { return Input.touchSupported; } catch (System.InvalidOperationException) { }
#endif
                return false;
            }
        }

        public static bool Enabled
        {
            get
            {
                int mode = Game.Settings != null ? Game.Settings.touchControls : 0;
                return mode == 1 || mode == 0 && Application.isMobilePlatform;
            }
        }

        enum Ctx { None, OnFoot, Vehicle, Boxing, GetUp, Skip, Watch }
        enum Kind { Hold, Toggle, Latch, Scroll }
        enum Own { None, Stick, Look, Pad }

        class Pad
        {
            public string id, label;
            public KeyCode key;
            public Kind kind;
            public Vector2 c;      // centre, virtual 1080p units
            public float r;
            public Color col;
            public bool lookDrag;  // dragging a finger on it also turns the camera
            public bool punch;     // consumes BODY / POWER latches
            public bool on;        // toggle / latch state
            public bool spent;     // a held latch was used by a punch: switch off when released
            public bool dim;
            public int finger = -1;
            public int seenFrame;
        }

        class Finger { public Own own; public Pad pad; public Vector2 last; }

        struct Pt { public int id; public Vector2 pos; }

        readonly Dictionary<string, Pad> pads = new Dictionary<string, Pad>();
        readonly List<Pad> visible = new List<Pad>();
        readonly Dictionary<int, Finger> fingers = new Dictionary<int, Finger>();
        readonly List<Pt> pts = new List<Pt>();
        readonly HashSet<KeyCode> want = new HashSet<KeyCode>(), wanted = new HashSet<KeyCode>();
        readonly HashSet<int> alive = new HashSet<int>();
        readonly List<int> dead = new List<int>();
        Ctx ctx, lastCtx;
        Rect safe;          // safe area in virtual units (top-left origin)
        float W, H, u, px;  // virtual screen size, button scale, pixels per virtual unit
        int stickFinger = -1, lookFinger = -1;
        Vector2 stickCentre, stickKnob, stickHome;
        float stickR;
        Rect stickZone;
        bool clearLatches;
        static Texture2D disc, ring;
        GUIStyle labelStyle;

        static readonly Color Cyan = new Color(0.1f, 0.95f, 1f), Magenta = new Color(1f, 0.2f, 0.75f), Yellow = new Color(1f, 0.82f, 0.2f),
            Red = new Color(1f, 0.25f, 0.25f), White = new Color(0.9f, 0.95f, 1f), Green = new Color(0.3f, 1f, 0.5f);

        void Awake()
        {
            Instance = this;
            if (disc == null) { disc = MakeCircle(false); ring = MakeCircle(true); }
        }

        void OnDisable() { Active = false; InputHub.TouchActive = false; InputHub.ReleaseVirtual(); }

        // ================================================================== update
        void Update()
        {
            bool enabledNow = Enabled;
            InputHub.TouchActive = enabledNow;
            ctx = enabledNow ? Context() : Ctx.None;
            Active = ctx != Ctx.None;
            if (ctx != lastCtx)
            {
                foreach (var p in pads.Values) { p.on = false; p.finger = -1; }
                foreach (var f in fingers.Values) { f.own = Own.None; f.pad = null; }
                stickFinger = lookFinger = -1;
                lastCtx = ctx;
            }
            if (!enabledNow) { if (wanted.Count > 0 || InputHub.VirtualMove != Vector2.zero) Release(); return; }

            px = Screen.height / 1080f;
            if (px <= 0f) return;
            W = Screen.width / px; H = 1080f;
            var sa = Screen.safeArea;
            safe = new Rect(sa.x / px, (Screen.height - sa.yMax) / px, sa.width / px, sa.height / px);
            u = Mathf.Clamp(Game.Settings != null ? Game.Settings.touchSize : 1f, 0.6f, 1.6f);

            Layout();
            Gather();
            Track(ctx != Ctx.None);
            Apply();
        }

        Ctx Context()
        {
            var gm = Game.Manager;
            if (gm == null || gm.State != GameState.Playing) return Ctx.None;
            if (Game.UI != null && Game.UI.modal != Modal.None) return Ctx.None;
            var m = Boxing.Match;
            if (m != null)
            {
                switch (m.phase)
                {
                    case MatchPhase.Fight:
                    case MatchPhase.RoundStart: return Ctx.Boxing;
                    case MatchPhase.Intro:
                    case MatchPhase.Replay: return Ctx.Skip;
                    case MatchPhase.Knockdown: return m.Red != null && m.Red.state == BoxerState.Down ? Ctx.GetUp : Ctx.Watch;
                    case MatchPhase.Corner:
                    case MatchPhase.Result:
                    case MatchPhase.Done: return Ctx.None;
                    default: return Ctx.Watch;
                }
            }
            if (Game.Player == null) return Ctx.None;
            return Game.Player.InVehicle ? Ctx.Vehicle : Ctx.OnFoot;
        }

        // ================================================================== layout
        Vector2 BR(float x, float y) => new Vector2(safe.xMax + x * u, safe.yMax + y * u);
        Vector2 TL(float x, float y) => new Vector2(safe.x + x * u, safe.y + y * u);

        Pad Add(string id, string label, KeyCode key, Vector2 c, float r, Color col, Kind kind = Kind.Hold, bool lookDrag = false, bool punch = false)
        {
            if (!pads.TryGetValue(id, out var p)) { p = new Pad { id = id }; pads[id] = p; }
            p.label = label; p.key = key; p.c = c; p.r = r * u; p.col = col; p.kind = kind; p.lookDrag = lookDrag; p.punch = punch;
            p.dim = false;
            p.seenFrame = Time.frameCount;
            visible.Add(p);
            return p;
        }

        void Layout()
        {
            visible.Clear();
            bool stick = false;
            switch (ctx)
            {
                case Ctx.OnFoot:
                {
                    stick = true;
                    bool scanning = Game.Hacking != null && Game.Hacking.Scanning;
                    Add("fire", scanning ? "HACK" : "FIRE", KeyCode.Mouse0, BR(-245, -255), 84, scanning ? Cyan : Red, Kind.Hold, true);
                    Add("aim", "AIM", KeyCode.Mouse1, BR(-90, -265), 54, White, Kind.Toggle, true);
                    Add("jump", "JUMP", InputHub.Binding(Btn.Jump), BR(-105, -105), 62, Cyan);
                    Add("crouch", "CROUCH", InputHub.Binding(Btn.Crouch), BR(-262, -80), 48, White);
                    Add("reload", "RELOAD", InputHub.Binding(Btn.Reload), BR(-405, -185), 44, White);
                    Add("melee", "MELEE", InputHub.Binding(Btn.Melee), BR(-410, -320), 44, Magenta);
                    Add("nade", "NADE", InputHub.Binding(Btn.Grenade), BR(-90, -400), 44, Yellow);
                    Add("chrono", "CHRONO", InputHub.Binding(Btn.Ability), BR(-215, -415), 42, Cyan);
                    Add("camo", "CAMO", InputHub.Binding(Btn.Ability2), BR(-345, -445), 42, Cyan);
                    Add("scan", "SCAN", InputHub.Binding(Btn.Scan), BR(-90, -525), 42, Cyan, Kind.Toggle);
                    Add("wpn", scanning ? "NEXT" : "WEAPON", KeyCode.None, BR(-220, -540), 42, White, Kind.Scroll);
                    var prompt = Game.Interactor != null ? Game.Interactor.PromptText : null;
                    if (prompt != null && prompt.Contains("[" + Labels[Btn.Vehicle] + "]")) Add("car", "ENTER", InputHub.Binding(Btn.Vehicle), BR(-560, -300), 58, Green);
                    else if (prompt != null) Add("use", "USE", InputHub.Binding(Btn.Interact), BR(-560, -300), 58, Green);
                    TopRow(true);
                    break;
                }
                case Ctx.Vehicle:
                    stick = true;
                    Add("brake", "BRAKE", InputHub.Binding(Btn.Jump), BR(-120, -130), 72, Red);
                    Add("exit", "EXIT", InputHub.Binding(Btn.Vehicle), BR(-305, -105), 50, Green);
                    Add("horn", "HORN", InputHub.Binding(Btn.Horn), BR(-110, -310), 44, Yellow);
                    Add("vcam", "CAM", InputHub.Binding(Btn.CameraView), BR(-250, -275), 42, White);
                    Add("lights", "LIGHTS", InputHub.Binding(Btn.Lights), BR(-390, -250), 40, White);
                    Add("radio", "RADIO", InputHub.Binding(Btn.Radio), BR(-110, -440), 40, Magenta);
                    TopRow(false);
                    break;
                case Ctx.Boxing:
                {
                    stick = true;
                    // lead hand column / rear hand column, block under the right thumb
                    Add("jab", "JAB", KeyCode.Mouse0, BR(-430, -110), 56, Cyan, Kind.Hold, false, true);
                    Add("cross", "CROSS", KeyCode.Mouse1, BR(-282, -110), 56, Cyan, Kind.Hold, false, true);
                    Add("lhook", "L.HOOK", KeyCode.Q, BR(-430, -250), 54, Magenta, Kind.Hold, false, true);
                    Add("rhook", "R.HOOK", KeyCode.E, BR(-282, -250), 54, Magenta, Kind.Hold, false, true);
                    Add("lupper", "L.UPPER", KeyCode.Z, BR(-430, -390), 52, Yellow, Kind.Hold, false, true);
                    Add("rupper", "R.UPPER", KeyCode.X, BR(-282, -390), 52, Yellow, Kind.Hold, false, true);
                    Add("block", "BLOCK", InputHub.Binding(Btn.Jump), BR(-115, -125), 68, White);
                    Add("duck", "DUCK", KeyCode.C, BR(-110, -290), 46, White);
                    Add("body", "BODY", InputHub.Binding(Btn.Walk), BR(-110, -415), 44, Green, Kind.Latch);
                    Add("power", "POWER", InputHub.Binding(Btn.Sprint), BR(-150, -535), 44, Red, Kind.Latch);
                    Add("clinch", "CLINCH", InputHub.Binding(Btn.Vehicle), BR(-575, -120), 40, White);
                    Add("taunt", "TAUNT", InputHub.Binding(Btn.Melee), BR(-575, -245), 36, Magenta);
                    CentreRow();
                    break;
                }
                case Ctx.GetUp:
                    Add("getup", "GET\nUP!", InputHub.Binding(Btn.Jump), new Vector2(W * 0.5f, safe.yMax - 190 * u), 110, Yellow);
                    CentreRow();
                    break;
                case Ctx.Skip:
                    Add("skip", Boxing.Match != null && Boxing.Match.phase == MatchPhase.Intro ? "TOUCH\nGLOVES" : "SKIP", InputHub.Binding(Btn.Jump), BR(-130, -130), 78, Yellow);
                    CentreRow();
                    break;
                case Ctx.Watch:
                    CentreRow();
                    break;
            }

            // floating move stick: anywhere in the lower-left, ghost at its home spot
            stickR = 105f * u;
            stickHome = new Vector2(safe.x + 235f * u, safe.yMax - 230f * u);
            stickZone = stick ? new Rect(safe.x, safe.y + safe.height * 0.33f, W * 0.45f - safe.x, safe.height * 0.67f) : default;
            if (!stick) stickFinger = -1;

            // drop fingers whose pad disappeared (e.g. the USE prompt went away)
            foreach (var p in pads.Values)
                if (p.seenFrame != Time.frameCount && p.finger >= 0)
                {
                    if (fingers.TryGetValue(p.finger, out var f)) { f.own = Own.None; f.pad = null; }
                    p.finger = -1;
                }
        }

        void TopRow(bool onFoot)
        {
            // right of the minimap
            Add("pause", "II", KeyCode.Escape, TL(300, 62), 34, White);
            Add("map", "MAP", InputHub.Binding(Btn.Map), TL(380, 62), 34, White);
            if (onFoot)
            {
                Add("call", "CALL\nCAR", InputHub.Binding(Btn.CallCar), TL(460, 62), 34, White);
                Add("holster", "HOL-\nSTER", InputHub.Binding(Btn.Holster), TL(540, 62), 34, White);
            }
        }

        void CentreRow()
        {
            // under the round clock, between the fighter panels
            Add("bpause", "II", KeyCode.Escape, new Vector2(W * 0.5f + 175f, 64f), 32, White);
            Add("bcam", "CAM", InputHub.Binding(Btn.CameraView), new Vector2(W * 0.5f - 175f, 64f), 32, White);
        }

        // ================================================================== touches
        void Gather()
        {
            pts.Clear();
#if ENABLE_LEGACY_INPUT_MANAGER
            try
            {
                int n = Input.touchCount;
                for (int i = 0; i < n; i++)
                {
                    var t = Input.GetTouch(i);
                    if (t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled) continue;
                    pts.Add(new Pt { id = t.fingerId, pos = ToVirtual(t.position) });
                }
                return;
            }
            catch (System.InvalidOperationException) { pts.Clear(); }
#endif
#if ENABLE_INPUT_SYSTEM
            var ts = UnityEngine.InputSystem.Touchscreen.current;
            if (ts == null) return;
            foreach (var t in ts.touches)
            {
                if (!t.press.isPressed) continue;
                pts.Add(new Pt { id = t.touchId.ReadValue(), pos = ToVirtual(t.position.ReadValue()) });
            }
#endif
        }

        Vector2 ToVirtual(Vector2 screen) => new Vector2(screen.x / px, (Screen.height - screen.y) / px);

        void Track(bool interactive)
        {
            var look = Vector2.zero;
            alive.Clear();
            foreach (var t in pts)
            {
                alive.Add(t.id);
                if (!fingers.TryGetValue(t.id, out var f))
                {
                    f = new Finger { last = t.pos };
                    fingers[t.id] = f;
                    // a finger that lands while a menu is up (e.g. tapping RESUME) never becomes a control
                    if (interactive) Begin(t.id, f, t.pos); else f.own = Own.None;
                    continue;
                }
                var d = t.pos - f.last;
                f.last = t.pos;
                switch (f.own)
                {
                    case Own.Stick:
                        stickKnob = t.pos - stickCentre;
                        if (stickKnob.magnitude > stickR) { stickCentre = t.pos - stickKnob.normalized * stickR; stickKnob = t.pos - stickCentre; }
                        break;
                    case Own.Look:
                        look += d;
                        break;
                    case Own.Pad:
                        if (f.pad != null && f.pad.lookDrag) look += d;
                        break;
                }
            }
            dead.Clear();
            foreach (var kv in fingers) if (!alive.Contains(kv.Key)) dead.Add(kv.Key);
            foreach (var id in dead)
            {
                var f = fingers[id];
                if (f.own == Own.Pad && f.pad != null && f.pad.finger == id)
                {
                    f.pad.finger = -1;
                    if (f.pad.spent) { f.pad.on = false; f.pad.spent = false; }
                }
                if (id == stickFinger) { stickFinger = -1; stickKnob = Vector2.zero; }
                if (id == lookFinger) lookFinger = -1;
                fingers.Remove(id);
            }
            // virtual units -> mouse-delta units (roughly what a desktop mouse produces for the same turn)
            InputHub.VirtualLook = new Vector2(look.x, -look.y) * 0.075f;
        }

        void Begin(int id, Finger f, Vector2 pos)
        {
            // buttons first (slightly generous hit circles)
            Pad best = null; float bestD = float.MaxValue;
            foreach (var p in visible)
            {
                float dd = (pos - p.c).magnitude;
                if (dd < p.r * 1.18f && dd < bestD) { best = p; bestD = dd; }
            }
            if (best != null)
            {
                f.own = Own.Pad; f.pad = best;
                best.finger = id;
                switch (best.kind)
                {
                    case Kind.Toggle: best.on = !best.on; break;
                    case Kind.Latch: best.on = !best.on; best.spent = false; break;
                    case Kind.Scroll: InputHub.PushScroll(1f); break;
                }
                if (best.punch) clearLatches = true;
                return;
            }
            if (stickFinger < 0 && stickZone.width > 0f && stickZone.Contains(pos))
            {
                f.own = Own.Stick; stickFinger = id;
                // keep the whole ring on screen
                stickCentre = new Vector2(Mathf.Max(pos.x, safe.x + stickR + 10f), Mathf.Min(pos.y, safe.yMax - stickR - 10f));
                stickKnob = pos - stickCentre;
                return;
            }
            if (lookFinger < 0 && pos.x > W * 0.3f) { f.own = Own.Look; lookFinger = id; return; }
            f.own = Own.None;
        }

        // ================================================================== output
        void Apply()
        {
            want.Clear();
            bool latchClearNow = false;
            foreach (var p in visible)
            {
                if (p.key == KeyCode.None) continue;
                bool held = p.kind switch
                {
                    Kind.Toggle => p.on,
                    Kind.Latch => p.on || p.finger >= 0,
                    _ => p.finger >= 0,
                };
                if (held) want.Add(p.key);
            }
            if (clearLatches) { clearLatches = false; latchClearNow = true; }

            var move = stickFinger >= 0 ? stickKnob / Mathf.Max(1f, stickR) : Vector2.zero;
            move.y = -move.y; // screen down = walk back
            float mag = move.magnitude;
            if (mag < 0.12f) move = Vector2.zero;
            else move = move.normalized * Mathf.InverseLerp(0.12f, 1f, Mathf.Min(1f, mag));
            InputHub.VirtualMove = move;

            if (ctx == Ctx.OnFoot && stickFinger >= 0)
            {
                // push the stick all the way forward to sprint, ease off to walk
                if (mag > 0.92f && move.y > 0.55f) want.Add(InputHub.Binding(Btn.Sprint));
                else if (mag > 0.12f && mag < 0.45f) want.Add(InputHub.Binding(Btn.Walk));
            }

            foreach (var k in wanted) if (!want.Contains(k)) InputHub.SetVirtual(k, false);
            foreach (var k in want) InputHub.SetVirtual(k, true);
            wanted.Clear();
            foreach (var k in want) wanted.Add(k);

            // BODY / POWER latches apply to this frame's punch, then switch off
            if (latchClearNow)
                foreach (var p in visible)
                    if (p.kind == Kind.Latch) { if (p.finger < 0) p.on = false; else p.spent = true; }
        }

        void Release()
        {
            InputHub.ReleaseVirtual();
            wanted.Clear();
            fingers.Clear();
            stickFinger = lookFinger = -1;
            foreach (var p in pads.Values) { p.finger = -1; p.on = false; p.spent = false; }
        }

        // ================================================================== drawing
        void OnGUI()
        {
            if (!Active || Event.current.type != EventType.Repaint || px <= 0f) return;
            GUI.depth = -50;
            var oldM = GUI.matrix; var oldC = GUI.color;
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(px, px, 1f));
            if (labelStyle == null)
            {
                labelStyle = new GUIStyle(UISkin.label ?? GUI.skin.label) { alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold, wordWrap = false, richText = false };
                labelStyle.normal.textColor = Color.white;
            }

            if (stickZone.width > 0f)
            {
                bool live = stickFinger >= 0;
                var c = live ? stickCentre : stickHome;
                GUI.color = new Color(1f, 1f, 1f, live ? 0.22f : 0.1f);
                GUI.DrawTexture(Circle(c, stickR), disc);
                GUI.color = Cyan.WithAlpha(live ? 0.7f : 0.3f);
                GUI.DrawTexture(Circle(c, stickR), ring);
                var knob = c + (live ? Vector2.ClampMagnitude(stickKnob, stickR) : Vector2.zero);
                GUI.color = Cyan.WithAlpha(live ? 0.55f : 0.25f);
                GUI.DrawTexture(Circle(knob, stickR * 0.42f), disc);
            }

            foreach (var p in visible)
            {
                bool pressed = p.finger >= 0 || (p.kind == Kind.Toggle || p.kind == Kind.Latch) && p.on;
                float a = p.dim ? 0.18f : pressed ? 0.62f : 0.3f;
                float pulse = p.id == "getup" ? 1f + Mathf.Sin(Time.unscaledTime * 8f) * 0.04f : 1f;
                var rect = Circle(p.c, p.r * (pressed ? 0.94f : 1f) * pulse);
                GUI.color = new Color(p.col.r * 0.25f, p.col.g * 0.25f, p.col.b * 0.3f, a + 0.15f);
                GUI.DrawTexture(rect, disc);
                GUI.color = p.col.WithAlpha(pressed ? 0.95f : 0.6f);
                GUI.DrawTexture(rect, ring);
                labelStyle.fontSize = Mathf.RoundToInt(Mathf.Clamp(p.r * (p.label.Length > 5 ? 0.3f : 0.38f), 12f, 34f));
                GUI.color = pressed ? Color.white : new Color(1f, 1f, 1f, 0.85f);
                GUI.Label(rect, p.label, labelStyle);
            }
            GUI.matrix = oldM; GUI.color = oldC;
        }

        static Rect Circle(Vector2 c, float r) => new Rect(c.x - r, c.y - r, r * 2f, r * 2f);

        static Texture2D MakeCircle(bool outline)
        {
            const int S = 128;
            var t = new Texture2D(S, S, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color32[S * S];
            float R = S * 0.5f - 1.5f;
            for (int y = 0; y < S; y++)
                for (int x = 0; x < S; x++)
                {
                    float d = new Vector2(x + 0.5f - S * 0.5f, y + 0.5f - S * 0.5f).magnitude;
                    float a;
                    if (outline) a = Mathf.Clamp01(1f - Mathf.Abs(d - (R - 3f)) / 3f);
                    else a = Mathf.Clamp01(R - d) * Mathf.Lerp(0.75f, 1f, d / R);
                    px[y * S + x] = new Color32(255, 255, 255, (byte)(a * 255f));
                }
            t.SetPixels32(px);
            t.Apply(false, true);
            return t;
        }
    }
}
