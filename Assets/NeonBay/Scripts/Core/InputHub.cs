using System;
using System.Collections.Generic;
using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
#endif

namespace NeonBay
{
    public enum Btn
    {
        Fire, Aim, Reload, Jump, Sprint, Crouch, Interact, Vehicle, Weapon1, Weapon2, Weapon3, Weapon4,
        Holster, Melee, Grenade, Ability, Scan, Map, Journal, Inventory, Skills, Pause, QuickSave, QuickLoad,
        Radio, CameraView, Horn, Lights, CallCar, Phone, Walk, Ability2
    }

    /// <summary>
    /// Works with either the legacy Input Manager or the new Input System package,
    /// whichever the project has enabled (Unity 6 templates default to the new one).
    /// </summary>
    public static class InputHub
    {
        static readonly Dictionary<Btn, KeyCode> binds = new Dictionary<Btn, KeyCode>
        {
            { Btn.Fire, KeyCode.Mouse0 }, { Btn.Aim, KeyCode.Mouse1 }, { Btn.Reload, KeyCode.R },
            { Btn.Jump, KeyCode.Space }, { Btn.Sprint, KeyCode.LeftShift }, { Btn.Crouch, KeyCode.C },
            { Btn.Interact, KeyCode.E }, { Btn.Vehicle, KeyCode.F }, { Btn.Weapon1, KeyCode.Alpha1 },
            { Btn.Weapon2, KeyCode.Alpha2 }, { Btn.Weapon3, KeyCode.Alpha3 }, { Btn.Weapon4, KeyCode.Alpha4 },
            { Btn.Holster, KeyCode.H }, { Btn.Melee, KeyCode.V }, { Btn.Grenade, KeyCode.G },
            { Btn.Ability, KeyCode.Q }, { Btn.Scan, KeyCode.Tab }, { Btn.Map, KeyCode.M },
            { Btn.Journal, KeyCode.J }, { Btn.Inventory, KeyCode.I }, { Btn.Skills, KeyCode.K },
            { Btn.Pause, KeyCode.Escape }, { Btn.QuickSave, KeyCode.F5 }, { Btn.QuickLoad, KeyCode.F9 },
            { Btn.Radio, KeyCode.N }, { Btn.CameraView, KeyCode.B }, { Btn.Horn, KeyCode.LeftAlt },
            { Btn.Lights, KeyCode.L }, { Btn.CallCar, KeyCode.T }, { Btn.Phone, KeyCode.P }, { Btn.Walk, KeyCode.LeftControl }, { Btn.Ability2, KeyCode.X }
        };

        public static KeyCode Binding(Btn b) => binds.TryGetValue(b, out var k) ? k : KeyCode.None;
        public static void Rebind(Btn b, KeyCode k) { binds[b] = k; }

        public static string Label(Btn b)
        {
            if (TouchActive && TouchControls.Labels.TryGetValue(b, out var touchName)) return touchName;
            var k = Binding(b);
            switch (k)
            {
                case KeyCode.Mouse0: return "LMB";
                case KeyCode.Mouse1: return "RMB";
                case KeyCode.Mouse2: return "MMB";
                case KeyCode.LeftShift: return "SHIFT";
                case KeyCode.LeftControl: return "CTRL";
                case KeyCode.LeftAlt: return "ALT";
                case KeyCode.Escape: return "ESC";
                default:
                    var s = k.ToString();
                    if (s.StartsWith("Alpha")) s = s.Substring(5);
                    return s.ToUpperInvariant();
            }
        }

        /// <summary>Set by UI while a text field has focus so gameplay keys are ignored.</summary>
        public static bool Typing;

        // ------------------------------------------------------------------ virtual input
        // The on-screen touch controls (TouchControls) press "virtual keys" here, so every system that reads
        // InputHub works on phones without knowing about touch at all.
        /// <summary>True while the on-screen touch controls are in charge (mouse emulation from touches is ignored).</summary>
        public static bool TouchActive;
        public static Vector2 VirtualMove, VirtualLook;
        static readonly HashSet<KeyCode> vHeld = new HashSet<KeyCode>();
        static readonly Dictionary<KeyCode, int> vDownFrame = new Dictionary<KeyCode, int>(), vUpFrame = new Dictionary<KeyCode, int>();
        static float vScroll; static int vScrollFrame = -1;

        public static void SetVirtual(KeyCode k, bool held)
        {
            if (k == KeyCode.None || vHeld.Contains(k) == held) return;
            if (held) { vHeld.Add(k); vDownFrame[k] = Time.frameCount; }
            else { vHeld.Remove(k); vUpFrame[k] = Time.frameCount; }
        }

        public static bool VirtualHeld(KeyCode k) => vHeld.Contains(k);

        static readonly List<KeyCode> releaseTmp = new List<KeyCode>();
        public static void ReleaseVirtual()
        {
            releaseTmp.Clear(); releaseTmp.AddRange(vHeld);
            foreach (var k in releaseTmp) SetVirtual(k, false);
            VirtualMove = Vector2.zero; VirtualLook = Vector2.zero;
        }

        public static void PushScroll(float s) { vScroll = s; vScrollFrame = Time.frameCount; }

        static bool Virtual(KeyCode k, int mode)
        {
            if (mode == 0) return vHeld.Contains(k);
            var d = mode == 1 ? vDownFrame : vUpFrame;
            return d.TryGetValue(k, out var f) && f == Time.frameCount;
        }

        public static bool Held(Btn b) => !Typing && KeyState(Binding(b), 0);
        public static bool Down(Btn b) => !Typing && KeyState(Binding(b), 1);
        public static bool Up(Btn b) => !Typing && KeyState(Binding(b), 2);
        public static bool KeyDown(KeyCode k) => !Typing && KeyState(k, 1);
        public static bool KeyHeld(KeyCode k) => !Typing && KeyState(k, 0);

        public static Vector2 Move
        {
            get
            {
                if (Typing) return Vector2.zero;
                float x = (KeyState(KeyCode.D, 0) ? 1 : 0) - (KeyState(KeyCode.A, 0) ? 1 : 0);
                float y = (KeyState(KeyCode.W, 0) ? 1 : 0) - (KeyState(KeyCode.S, 0) ? 1 : 0);
                var v = new Vector2(x, y) + VirtualMove;
                return v.sqrMagnitude > 1f ? v.normalized : v;
            }
        }

        /// <summary>Mouse delta in "legacy axis" units (roughly 0.1 per pixel).</summary>
        public static Vector2 Look => TouchActive ? VirtualLook : MouseLook + VirtualLook;

        static Vector2 MouseLook
        {
            get
            {
#if ENABLE_INPUT_SYSTEM
                var m = Mouse.current;
                if (m == null) return Vector2.zero;
                return m.delta.ReadValue() * 0.08f;
#else
                if (!legacyAxesOk) return Vector2.zero;
                try { return new Vector2(Input.GetAxisRaw("Mouse X"), Input.GetAxisRaw("Mouse Y")); }
                catch (ArgumentException) { legacyAxesOk = false; return Vector2.zero; }
#endif
            }
        }

        public static float Scroll
        {
            get
            {
                if (vScrollFrame == Time.frameCount) return vScroll;
#if ENABLE_INPUT_SYSTEM
                var m = Mouse.current;
                if (m == null) return 0f;
                float y = m.scroll.ReadValue().y;
                return Mathf.Abs(y) > 0.01f ? Mathf.Sign(y) : 0f;
#else
                return Input.mouseScrollDelta.y;
#endif
            }
        }

        public static Vector2 MousePosition
        {
            get
            {
#if ENABLE_INPUT_SYSTEM
                var m = Mouse.current;
                return m != null ? m.position.ReadValue() : Vector2.zero;
#else
                return Input.mousePosition;
#endif
            }
        }

#if !ENABLE_INPUT_SYSTEM
        static bool legacyAxesOk = true;
#endif

        // mode: 0 held, 1 pressed this frame, 2 released this frame
        static bool KeyState(KeyCode k, int mode)
        {
            if (k == KeyCode.None) return false;
            if (Virtual(k, mode)) return true;
            // phones report touches as mouse buttons; the touch overlay handles those itself
            if (TouchActive && k >= KeyCode.Mouse0 && k <= KeyCode.Mouse6) return false;
#if ENABLE_INPUT_SYSTEM
            ButtonControl c = Control(k);
            if (c == null) return false;
            return mode == 0 ? c.isPressed : mode == 1 ? c.wasPressedThisFrame : c.wasReleasedThisFrame;
#else
            return mode == 0 ? Input.GetKey(k) : mode == 1 ? Input.GetKeyDown(k) : Input.GetKeyUp(k);
#endif
        }

#if ENABLE_INPUT_SYSTEM
        static readonly Dictionary<KeyCode, Key> keyMap = new Dictionary<KeyCode, Key>();

        static ButtonControl Control(KeyCode k)
        {
            if (k >= KeyCode.Mouse0 && k <= KeyCode.Mouse6)
            {
                var m = Mouse.current;
                if (m == null) return null;
                switch (k)
                {
                    case KeyCode.Mouse0: return m.leftButton;
                    case KeyCode.Mouse1: return m.rightButton;
                    case KeyCode.Mouse2: return m.middleButton;
                    case KeyCode.Mouse3: return m.backButton;
                    case KeyCode.Mouse4: return m.forwardButton;
                    default: return null;
                }
            }
            var kb = Keyboard.current;
            if (kb == null) return null;
            if (!keyMap.TryGetValue(k, out var key))
            {
                key = Convert(k);
                keyMap[k] = key;
            }
            if (key == UnityEngine.InputSystem.Key.None) return null;
            return kb[key];
        }

        static Key Convert(KeyCode k)
        {
            switch (k)
            {
                case KeyCode.Return: return UnityEngine.InputSystem.Key.Enter;
                case KeyCode.LeftControl: return UnityEngine.InputSystem.Key.LeftCtrl;
                case KeyCode.RightControl: return UnityEngine.InputSystem.Key.RightCtrl;
                case KeyCode.BackQuote: return UnityEngine.InputSystem.Key.Backquote;
                case KeyCode.LeftAlt: return UnityEngine.InputSystem.Key.LeftAlt;
                case KeyCode.RightAlt: return UnityEngine.InputSystem.Key.RightAlt;
            }
            var name = k.ToString();
            if (name.StartsWith("Alpha")) name = "Digit" + name.Substring(5);
            else if (name.StartsWith("Keypad") && name.Length == 7 && char.IsDigit(name[6])) name = "Numpad" + name.Substring(6);
            if (Enum.TryParse(name, out Key result)) return result;
            return UnityEngine.InputSystem.Key.None;
        }
#endif
    }
}
