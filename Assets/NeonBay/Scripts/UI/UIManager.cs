using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum Modal { None, Shop, Gigs, Sleep, Metro, Garage, Lore }

    /// <summary>All UI is immediate-mode (IMGUI) drawn in code at a 1080p virtual resolution.</summary>
    public partial class UIManager : MonoBehaviour
    {
        public float scale = 1f;
        public float W => Screen.width / scale;
        public float H => Screen.height / scale;
        public Modal modal = Modal.None;
        public int modalClosedFrame = -1;

        class Note { public string text; public Color color; public float t; }
        readonly List<Note> notes = new List<Note>();
        string bannerTitle, bannerSub; Color bannerColor; float bannerT;
        class Sub { public string speaker, text; public float time; public Color color; }
        readonly Queue<Sub> subs = new Queue<Sub>();
        Sub currentSub; float subT;
        string hint; float hintT;
        float fadeT, fadeDur;
        public float glitch;
        float hurtFlash, nearMiss;
        class Popup { public Vector3 pos; public string text; public Color color; public float t; }
        readonly List<Popup> popups = new List<Popup>();
        class BarkInfo { public NPC npc; public string text; public float t; }
        readonly List<BarkInfo> barks = new List<BarkInfo>();
        readonly Dictionary<NPC, float> enemyBars = new Dictionary<NPC, float>();
        NPC hackingNpc; float hackProg; float hackSeen;
        float timerLeft = -1f; string timerLabel;
        public Vector3? waypoint; public string waypointLabel;
        float xpPopT; int xpPopAmount;
        float lastHealth = -1f;
        float fpsT, fps; int fpsFrames;

        void Awake()
        {
            Game.UI = this;
            UISkin.Build();
        }

        // ================================================================== public API used by gameplay
        public void Notify(string text, Color c)
        {
            notes.Add(new Note { text = text, color = c, t = 5f });
            if (notes.Count > 7) notes.RemoveAt(0);
        }

        public void Banner(string title, string sub, Color c)
        {
            bannerTitle = title; bannerSub = sub; bannerColor = c; bannerT = 4.5f;
        }

        public void Subtitle(string speaker, string text, float seconds, Color c)
        {
            if (Game.Settings != null && !Game.Settings.subtitles && speaker != "JUNE") return;
            subs.Enqueue(new Sub { speaker = speaker, text = text, time = seconds, color = c });
        }

        public void Hint(string text) { hint = text; hintT = 9f; }
        public void XpPopup(int amount) { xpPopAmount = xpPopT > 0 ? xpPopAmount + amount : amount; xpPopT = 2.2f; }

        public void DamageNumber(Vector3 pos, float amount, bool crit, bool head)
        {
            popups.Add(new Popup { pos = pos + Random.insideUnitSphere * 0.2f, text = Mathf.RoundToInt(amount).ToString() + (crit ? "!" : ""), color = head ? Palette.Yellow : crit ? Palette.Orange : Color.white, t = 1f });
            if (popups.Count > 30) popups.RemoveAt(0);
        }

        public void ShowEnemyHealth(NPC npc) { if (npc != null) enemyBars[npc] = 4f; }

        public void Bark(NPC npc, string text)
        {
            if (npc == null || string.IsNullOrEmpty(text)) return;
            barks.RemoveAll(b => b.npc == npc);
            barks.Add(new BarkInfo { npc = npc, text = text, t = 3.2f });
        }

        public void NearMiss() { nearMiss = 0.3f; }
        public void IncomingHack(NPC npc, float progress) { hackingNpc = npc; hackProg = progress; hackSeen = 0.3f; }
        public void Glitch(float amount) { glitch = Mathf.Max(glitch, amount); }
        public void Fade(float seconds) { fadeDur = seconds; fadeT = seconds; }
        public void StartTimer(float seconds, string label) { timerLeft = seconds; timerLabel = label; }
        public void StopTimer() { timerLeft = -1f; }
        public void SetWaypoint(Vector3 p, string label) { waypoint = p; waypointLabel = label; }
        public void ClearWaypoint() { waypoint = null; }

        // ================================================================== frame update
        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            for (int i = notes.Count - 1; i >= 0; i--) { notes[i].t -= dt; if (notes[i].t <= 0) notes.RemoveAt(i); }
            bannerT -= dt; hintT -= dt; xpPopT -= dt;
            if (fadeT > 0) fadeT -= dt;
            glitch = Mathf.MoveTowards(glitch, 0f, dt * 0.8f);
            hurtFlash = Mathf.MoveTowards(hurtFlash, 0f, dt * 1.5f);
            nearMiss = Mathf.MoveTowards(nearMiss, 0f, dt);
            hackSeen -= dt;
            if (timerLeft > 0 && Game.IsPlaying) timerLeft -= Time.deltaTime;
            if (currentSub == null && subs.Count > 0) { currentSub = subs.Dequeue(); subT = currentSub.time; }
            if (currentSub != null && Game.Manager != null && Game.Manager.State != GameState.Paused) { subT -= dt; if (subT <= 0) currentSub = null; }
            for (int i = popups.Count - 1; i >= 0; i--) { popups[i].t -= dt; popups[i].pos += Vector3.up * dt * 0.8f; if (popups[i].t <= 0) popups.RemoveAt(i); }
            for (int i = barks.Count - 1; i >= 0; i--) { barks[i].t -= dt; if (barks[i].t <= 0 || barks[i].npc == null) barks.RemoveAt(i); }
            var keys = new List<NPC>(enemyBars.Keys);
            foreach (var k in keys) { if (k == null || k.state == NPCState.Dead) { enemyBars.Remove(k); continue; } enemyBars[k] -= dt; if (enemyBars[k] <= 0) enemyBars.Remove(k); }

            if (Game.Stats != null && Game.Stats.dmg != null)
            {
                float h = Game.Stats.dmg.health;
                if (lastHealth >= 0 && h < lastHealth - 0.5f) { hurtFlash = Mathf.Clamp01(hurtFlash + (lastHealth - h) / 40f); Game.Player?.Shake(Mathf.Clamp01((lastHealth - h) / 80f)); }
                lastHealth = h;
            }
            // post-processing feedback (drunk / glitch / chrono)
            if (PostFX.Available && Game.Stats != null)
            {
                bool drunk = Game.Stats.HasBuff("drunk");
                float g = glitch + (drunk ? 0.4f + Mathf.Sin(Time.time * 1.3f) * 0.2f : 0f);
                PostFX.SetChromatic(0.08f + g * 0.6f + (Game.Manager.SlowMotion ? 0.4f : 0f));
                PostFX.SetLensDistortion(drunk ? Mathf.Sin(Time.time * 0.9f) * 0.25f : Game.Manager.SlowMotion ? -0.25f : glitch > 0.3f ? -glitch * 0.3f : 0f);
                float low = Game.Stats.dmg.Fraction < 0.3f ? (0.3f - Game.Stats.dmg.Fraction) * 1.4f : 0f;
                PostFX.SetVignette(0.32f + low + hurtFlash * 0.3f, Color.Lerp(Color.black, new Color(0.6f, 0f, 0f), Mathf.Clamp01(low * 2f + hurtFlash)));
            }

            fpsFrames++; fpsT += dt;
            if (fpsT > 0.5f) { fps = fpsFrames / fpsT; fpsFrames = 0; fpsT = 0; }

            HandleModalKeys();
        }

        void HandleModalKeys()
        {
            if (modal != Modal.None && (InputHub.KeyDown(KeyCode.Escape) || InputHub.KeyDown(KeyCode.Tab)))
            {
                if (modal == Modal.Lore) CloseLore(); else CloseModal();
            }
        }

        public void OpenModal(Modal m)
        {
            modal = m;
            scroll = Vector2.zero;
            Game.Manager?.SetState(GameState.Shop);
            Game.Audio?.Play2D("ui_open", 0.5f);
        }

        public void CloseModal()
        {
            modal = Modal.None;
            modalClosedFrame = Time.frameCount;
            if (Game.Manager != null && Game.Manager.State == GameState.Shop) Game.Manager.SetState(GameState.Playing);
        }

        Vector2 scroll;

        // ================================================================== OnGUI router
        void OnGUI()
        {
            if (Game.Manager == null) return;
            float uiScale = Game.Settings != null ? Game.Settings.uiScale : 1f;
            scale = Mathf.Max(0.4f, Screen.height / 1080f * uiScale);
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(scale, scale, 1f));
            GUI.depth = 0;

            switch (Game.Manager.State)
            {
                case GameState.Boot:
                case GameState.Loading: DrawLoading(); break;
                case GameState.MainMenu: DrawMainMenu(); break;
                case GameState.CharacterCreation: DrawCreator(); break;
                case GameState.Intro: DrawIntro(); break;
                case GameState.Playing: DrawHUD(); break;
                case GameState.Paused: DrawPause(); break;
                case GameState.Dialogue: DrawDialogue(); break;
                case GameState.Shop: DrawHUD(true); DrawModal(); break;
                case GameState.Dead: DrawHUD(true); DrawDeath(); break;
                case GameState.Ending: DrawEnding(); break;
            }
            DrawNotifications();
            DrawBanner();
            if (fadeT > 0f) UISkin.Rect(new Rect(0, 0, W, H), new Color(0, 0, 0, Mathf.Clamp01(fadeT / Mathf.Max(0.01f, fadeDur)) * 1.2f));
            if (glitch > 0.05f) DrawGlitch();
            if (Game.Settings != null && Game.Settings.showFps) UISkin.Text(new Rect(W - 120, H - 30, 110, 24), Mathf.RoundToInt(fps) + " FPS", UISkin.tiny, Color.white);
        }

        void DrawModal()
        {
            switch (modal)
            {
                case Modal.Shop: DrawShop(); break;
                case Modal.Gigs: DrawGigs(); break;
                case Modal.Sleep: DrawSleep(); break;
                case Modal.Metro: DrawMetro(); break;
                case Modal.Garage: DrawGarage(); break;
                case Modal.Lore: DrawLore(); break;
            }
        }

        void DrawNotifications()
        {
            if (Game.Manager.State == GameState.MainMenu || Game.Manager.State == GameState.Loading) return;
            float y = H * 0.42f;
            foreach (var n in notes)
            {
                float a = Mathf.Clamp01(n.t * 2f);
                var r = new Rect(24, y, 520, 30);
                UISkin.Rect(new Rect(r.x, r.y, 4, r.height), n.color.WithAlpha(a));
                UISkin.Rect(new Rect(r.x + 4, r.y, r.width, r.height), new Color(0, 0, 0, 0.45f * a));
                UISkin.Text(new Rect(r.x + 14, r.y + 4, r.width - 20, r.height), n.text, UISkin.labelSmall, new Color(1, 1, 1, a));
                y += 34;
            }
        }

        void DrawBanner()
        {
            if (bannerT <= 0 || string.IsNullOrEmpty(bannerTitle)) return;
            float a = Mathf.Clamp01(bannerT) * Mathf.Clamp01((4.5f - bannerT) * 4f);
            var r = new Rect(W * 0.5f - 420, H * 0.18f, 840, 96);
            UISkin.Rect(r, new Color(0, 0, 0, 0.55f * a));
            UISkin.Rect(new Rect(r.x, r.y, r.width, 2), bannerColor.WithAlpha(a));
            UISkin.Rect(new Rect(r.x, r.yMax - 2, r.width, 2), bannerColor.WithAlpha(a));
            UISkin.Text(new Rect(r.x, r.y + 8, r.width, 44), bannerTitle, UISkin.centerBig, bannerColor.WithAlpha(a));
            UISkin.Text(new Rect(r.x, r.y + 52, r.width, 36), bannerSub, UISkin.center, new Color(1, 1, 1, a));
        }

        void DrawGlitch()
        {
            int n = Mathf.RoundToInt(glitch * 14f);
            for (int i = 0; i < n; i++)
            {
                float y = Random.Range(0f, H), h = Random.Range(2f, 26f);
                var c = Random.value < 0.5f ? Palette.Cyan : Palette.Magenta;
                UISkin.Rect(new Rect(Random.Range(-100f, W * 0.5f), y, Random.Range(W * 0.2f, W), h), c.WithAlpha(Random.Range(0.05f, 0.25f) * glitch));
            }
        }

        public bool LoreOpen => modal == Modal.Lore;

        // world -> GUI coordinates (null if behind the camera)
        public bool WorldToGui(Vector3 world, out Vector2 gui)
        {
            gui = Vector2.zero;
            var cam = Game.Cam;
            if (cam == null) return false;
            var sp = cam.WorldToScreenPoint(world);
            if (sp.z <= 0.05f) return false;
            gui = new Vector2(sp.x / scale, (Screen.height - sp.y) / scale);
            return true;
        }
    }
}
