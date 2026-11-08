using System.Collections;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace NeonBay
{
    /// <summary>Boots every system, generates the city, and owns the high-level game flow (menu, new game, save/load, death, endings).</summary>
    public class GameManager : MonoBehaviour
    {
        public const int CitySeed = 2089;
        public GameState State { get; private set; } = GameState.Boot;
        public float LoadProgress { get; private set; }
        public string LoadStatus { get; private set; } = "Booting";
        public bool SlowMotion { get; private set; }
        bool scanSlow;
        public Camera menuCam;
        float menuT;
        public string endingTitle, endingText;
        public CityGenerator generator;
        float autosaveTimer = 300f;
        float musicCheck;

        // ------------------------------------------------------------------ bootstrap
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void AutoBoot()
        {
            if (Util.FindAny<GameManager>() != null) return;
            if (Util.FindAny<NeonBayBoot>() == null)
            {
                // Only take over scenes that are meant for the game (or Unity's empty template scenes).
                var name = SceneManager.GetActiveScene().name;
                if (name != "NeonBay" && name != "SampleScene" && name != "Untitled" && !string.IsNullOrEmpty(name)) return;
            }
            new GameObject("NeonBay").AddComponent<GameManager>();
        }

        void Awake()
        {
            if (Game.Manager != null && Game.Manager != this) { Destroy(gameObject); return; }
            Game.Manager = this;
            DontDestroyOnLoad(gameObject);
            Application.targetFrameRate = Application.isMobilePlatform ? 60 : 144;
            if (Application.isMobilePlatform)
            {
                Screen.sleepTimeout = SleepTimeout.NeverSleep;
                Screen.autorotateToPortrait = false; Screen.autorotateToPortraitUpsideDown = false;
                Screen.autorotateToLandscapeLeft = true; Screen.autorotateToLandscapeRight = true;
                Screen.orientation = ScreenOrientation.AutoRotation;
            }
            Game.Settings = Settings.Load();
            gameObject.AddComponent<TouchControls>();
        }

        IEnumerator Start()
        {
            SetState(GameState.Loading);
            // Remove template cameras / lights / listeners so they don't fight with ours
            foreach (var c in Util.FindAll<Camera>()) if (c.gameObject.scene.IsValid() && c.transform.root != transform) c.gameObject.SetActive(false);
            foreach (var l in Util.FindAll<AudioListener>()) if (l.transform.root != transform) l.enabled = false;

            Mats.Init();
            var menuGo = new GameObject("MenuCamera") { tag = "MainCamera" };
            menuGo.transform.SetParent(transform, false);
            menuCam = menuGo.AddComponent<Camera>();
            menuCam.farClipPlane = 2500f; menuCam.nearClipPlane = 0.3f; menuCam.fieldOfView = 60f; menuCam.allowHDR = true;
            menuGo.AddComponent<AudioListener>();
            menuCam.clearFlags = CameraClearFlags.Skybox;
            menuGo.transform.position = new Vector3(900, 300, -200);

            gameObject.AddComponent<UIManager>();
            Status(0.01f, "Synthesizing audio");
            yield return null;
            var audio = new GameObject("Audio").AddComponent<AudioManager>();
            audio.transform.SetParent(transform, false);
            audio.Init();
            var music = new GameObject("Music");
            music.transform.SetParent(transform, false);
            music.AddComponent<AudioSource>();
            music.AddComponent<MusicSystem>();
            Game.Music.intensityTarget = 0.35f;

            PostFX.Init(gameObject);
            PostFX.SetupCamera(menuCam);

            Game.City = new CityData(CitySeed);
            generator = new CityGenerator(Game.City);
            yield return generator.Generate(transform, (p, s) => Status(0.03f + p * 0.82f, s));

            Status(0.86f, "Booting street-level systems");
            yield return null;
            var fx = new GameObject("Effects").AddComponent<Effects>();
            fx.transform.SetParent(transform, false);
            fx.Init();
            var chunks = gameObject.AddComponent<ChunkStreamer>();
            chunks.Init(generator.chunks, generator.chunkCount);
            Game.Chunks = chunks;
            var env = new GameObject("Environment").AddComponent<WorldEnvironment>();
            env.transform.SetParent(transform, false);
            env.Init(generator);
            gameObject.AddComponent<NavMeshStreamer>();
            gameObject.AddComponent<QuestSystem>();
            gameObject.AddComponent<DialogueSystem>();
            gameObject.AddComponent<PoliceSystem>();
            gameObject.AddComponent<TrafficSystem>();
            var crowd = gameObject.AddComponent<CrowdSystem>();
            crowd.Init(generator.vendors);
            gameObject.AddComponent<WorldEvents>();
            gameObject.AddComponent<Activities>();
            Story.Register();
            Status(0.9f, "Mapping the city");
            Physics.SyncTransforms();
            yield return Game.UI.BuildMap(generator);
            Status(1f, "Ready");
            Game.Settings.Apply();
            yield return null;
            SetState(GameState.MainMenu);
        }

        void Status(float p, string s) { LoadProgress = p; LoadStatus = s; }

        // ------------------------------------------------------------------ state
        public void SetState(GameState s)
        {
            State = s;
            bool cursorFree = s != GameState.Playing;
            Cursor.lockState = cursorFree ? CursorLockMode.None : CursorLockMode.Locked;
            Cursor.visible = cursorFree;
            ApplyTimeScale();
            if (s != GameState.Playing) InputHub.Typing = false;
            Game.Audio?.PauseAll(s == GameState.Paused);
        }

        void ApplyTimeScale()
        {
            float ts = 1f;
            if (State == GameState.Paused || State == GameState.Dialogue || State == GameState.Shop || State == GameState.CharacterCreation || State == GameState.Dead || State == GameState.Ending || State == GameState.Intro) ts = 0f;
            else if (SlowMotion) ts = 0.3f;
            else if (scanSlow) ts = 0.35f;
            baseTimeScale = ts;
            ts *= ts > 0f ? CameraFX.TimeScale : 1f;
            Time.timeScale = ts;
            Time.fixedDeltaTime = 0.02f * Mathf.Max(0.05f, ts);
        }
        float baseTimeScale = 1f;

        public void SetSlowMotion(bool on) { SlowMotion = on; ApplyTimeScale(); }
        public void SetScanSlow(bool on) { scanSlow = on; ApplyTimeScale(); }

        void Update()
        {
            CameraFX.Tick(Time.unscaledDeltaTime);
            if (baseTimeScale > 0f)
            {
                float want = baseTimeScale * CameraFX.TimeScale;
                if (!Mathf.Approximately(Time.timeScale, want)) { Time.timeScale = want; Time.fixedDeltaTime = 0.02f * Mathf.Max(0.05f, want); }
            }
            if (State == GameState.MainMenu || State == GameState.CharacterCreation && Game.Player == null || State == GameState.Loading)
                UpdateMenuCamera();

            if (State == GameState.Playing || State == GameState.Paused)
            {
                if (InputHub.KeyDown(KeyCode.Escape) && Time.frameCount != Game.UI.modalClosedFrame)
                {
                    if (State == GameState.Playing) OpenPause(0); else SetState(GameState.Playing);
                }
            }
            if (State == GameState.Playing)
            {
                Game.PlayTime += Time.unscaledDeltaTime;
                if (InputHub.Down(Btn.Map)) OpenPause(4);
                if (InputHub.Down(Btn.Journal)) OpenPause(3);
                if (InputHub.Down(Btn.Inventory)) OpenPause(1);
                if (InputHub.Down(Btn.Skills)) OpenPause(0);
                if (InputHub.Down(Btn.QuickSave)) { if (SaveTo(SaveSystem.Quick)) Game.UI.Notify("Quicksaved", Palette.Green); }
                if (InputHub.Down(Btn.QuickLoad) && SaveSystem.Exists(SaveSystem.Quick)) LoadFrom(SaveSystem.Quick);
                autosaveTimer -= Time.unscaledDeltaTime;
                if (autosaveTimer <= 0f) { autosaveTimer = 300f; if (!InCombat()) AutoSave(); }
            }
            UpdateMusic();
        }

        public void OpenPause(int tab)
        {
            Game.UI.pauseTab = tab;
            SetState(GameState.Paused);
            Game.Audio?.Play2D("ui_open", 0.5f);
        }

        void UpdateMenuCamera()
        {
            if (menuCam == null || Game.City == null) return;
            menuT += Time.unscaledDeltaTime * 0.025f;
            var c = Game.City.Center;
            float r = 520f;
            var pos = c + new Vector3(Mathf.Cos(menuT) * r, 140f + Mathf.Sin(menuT * 0.7f) * 50f, Mathf.Sin(menuT) * r);
            menuCam.transform.position = pos;
            var helix = Game.City.Loc("helix_tower");
            var look = (helix != null ? helix.pos : c) + Vector3.up * 120f;
            menuCam.transform.rotation = Quaternion.LookRotation(look - pos);
        }

        bool InCombat()
        {
            if (!Game.HasPlayer) return false;
            foreach (var n in NPC.All)
                if (n != null && n.state == NPCState.Combat && n.target == Game.Stats.dmg && (n.transform.position - Game.PlayerPos).sqrMagnitude < 80f * 80f) return true;
            return Game.Police != null && Game.Police.Heat > 0;
        }

        void UpdateMusic()
        {
            var m = Game.Music;
            if (m == null) return;
            musicCheck -= Time.unscaledDeltaTime;
            if (musicCheck > 0f) return;
            musicCheck = 0.5f;
            if (State == GameState.MainMenu || State == GameState.Loading || State == GameState.CharacterCreation) { m.intensityTarget = 0.35f; return; }
            if (Game.Player != null && Game.Player.InVehicle && m.station != 0) { m.intensityTarget = 0.7f; return; }
            bool combat = InCombat();
            float night = Game.Env != null ? Game.Env.NightFactor : 0.5f;
            m.intensityTarget = combat ? 1f : Game.Activities != null && (Game.Activities.RaceActive || Game.Activities.FightActive) ? 0.85f : Mathf.Lerp(0.15f, 0.3f, night);
        }

        // ------------------------------------------------------------------ new game / player
        public void BeginCharacterCreation()
        {
            SetState(GameState.CharacterCreation);
            Game.UI.BeginCreator();
        }

        public void StartNewGame(CharacterProfile profile)
        {
            ResetWorld();
            Game.Profile = profile;
            profile.Migrate();
            Game.Difficulty = (Difficulty)Mathf.Clamp(profile.difficulty, 0, 3);
            Game.PlayTime = 0f;
            var spawn = Game.City.Loc("apt_spawn");
            SpawnPlayer(profile, spawn.pos + Vector3.up * 0.1f, 90f);
            var stats = Game.Stats;
            switch (profile.origin)
            {
                case Origin.GutterKid: stats.attributes[(int)Attr.Cool]++; stats.Money = 300; stats.StreetCred = 10; break;
                case Origin.CorpWashout: stats.attributes[(int)Attr.Neural]++; stats.Money = 1800; stats.Install(CyberwareDB.Get("deck_mk1")); break;
                default: stats.attributes[(int)Attr.Body]++; stats.Money = 500; Game.Traffic.Own("Muscle"); break;
            }
            stats.Recalc(true);
            Game.Weapons.GiveStarter(profile.origin);
            Game.Env.timeOfDay = 21.4f; Game.Env.day = 1;
            Game.Env.SetWeather(Weather.Rain, true);
            Story.StartNewGame();
            Story.SpawnPersistentNpcs();
            Game.Activities.RestoreWorldState();
            SetState(GameState.Intro);
            Game.UI.BeginIntro(profile);
        }

        public void FinishIntro()
        {
            SetState(GameState.Playing);
            Game.UI.Banner("NEON BAY", "2089  //  " + Util.TimeString(Game.Env.timeOfDay) + "  //  " + Game.Env.WeatherName, Palette.Cyan);
            AutoSave();
        }

        void SpawnPlayer(CharacterProfile profile, Vector3 pos, float yaw)
        {
            if (Game.Player != null) Destroy(Game.Player.gameObject);
            var pc = PlayerController.Create(profile, pos, yaw);
            Game.Player = pc;
            Game.Stats = pc.GetComponent<PlayerStats>();
            Game.Inventory = pc.GetComponent<Inventory>();
            Game.Weapons = pc.GetComponent<WeaponController>();
            Game.Hacking = pc.GetComponent<Hacking>();
            Game.Interactor = pc.GetComponent<PlayerInteractor>();
            Game.Stats.Init(profile);
            Game.Stats.dmg.Died += OnPlayerDied;
            if (menuCam != null) menuCam.gameObject.SetActive(false);
            Game.Settings.Apply();
        }

        void ResetWorld()
        {
            if (Boxing.Match != null) Boxing.Match.Abort();
            Boxing.PlayerInjuries = new InjuryRecord();
            CameraFX.Clear();
            Spawner.ClearAll();
            Game.Traffic?.ClearAll();
            Game.Crowd?.ClearAll();
            Game.Police?.ClearAll();
            Game.Events?.ClearAll();
            Flags.Reset();
            Factions.Load(null);
            if (Game.Traffic != null) Game.Traffic.owned.Clear();
            foreach (var p in Util.FindAll<Pickup>()) Destroy(p.gameObject);
            foreach (var g in Util.FindAll<Grenade>()) Destroy(g.gameObject);
            foreach (var v in Util.FindAll<Vehicle>()) Destroy(v.gameObject);
            foreach (var q in Util.FindAll<QuestObject>()) if (q.transform.parent == null) Destroy(q.gameObject);
            foreach (var l in Game.City.locations.Values) l.discovered = false;
            SetSlowMotion(false);
            Story.ResetQuests();
        }

        // ------------------------------------------------------------------ death
        void OnPlayerDied(DamageInfo info)
        {
            if (Game.Player.InVehicle) Game.Player.ExitVehicle(true);
            Game.Stats.ClearBuffs();
            Game.Audio?.Play2D("flatline", 0.6f);
            SetState(GameState.Dead);
        }

        public void RespawnAtClinic()
        {
            var clinic = Game.City.Loc("clinic");
            Game.Stats.dmg.Revive(0.6f);
            int fee = Mathf.RoundToInt(Game.Stats.Money * 0.1f);
            Game.Stats.Money -= fee;
            Game.Police.ClearAll();
            Game.Player.Teleport(clinic.pos + clinic.facing * 2.5f + Vector3.up * 0.2f, Quaternion.LookRotation(clinic.facing).eulerAngles.y);
            Game.Quests.RestartActive();
            Game.Env.SkipHours(6f);
            SetState(GameState.Playing);
            Game.UI.Banner("TRAUMA RECOVERY", "Doc Reyes patched you up.  -" + Util.Credits(fee), Palette.Cyan);
        }

        public void RescueToStreet()
        {
            var p = Game.City.LanePoint(Game.PlayerPos, out _, 1);
            Game.Player.Teleport(Spawner.FreeSpot(p + Vector3.up * 0.2f, 6f) + Vector3.up * 0.2f, Game.Player.Yaw);
        }

        public void ShowEnding(string title, string text)
        {
            endingTitle = title;
            endingText = text;
            Flags.Set("game_complete");
            SetState(GameState.Ending);
            Game.Audio?.Play2D("quest_done");
            AutoSave();
        }

        // ------------------------------------------------------------------ saving
        public void AutoSave()
        {
            if (Game.Player == null || State == GameState.Dead) return;
            if (Game.Player.transform.position.y < -20f && !Flags.Has("allow_interior_save")) { /* interior saves are fine too */ }
            SaveTo(SaveSystem.Auto);
        }

        public bool SaveTo(string slot)
        {
            if (Game.Player == null || Game.Stats.dmg.isDead) return false;
            if (Boxing.Match != null && Boxing.Match.Running) return false;
            Boxing.SaveInjuries();
            var d = new SaveData
            {
                seed = CitySeed,
                difficulty = (int)Game.Difficulty,
                playTime = Game.PlayTime,
                profile = Game.Profile,
                position = Game.Player.InVehicle ? Game.Player.vehicle.FindExitPoint() : Game.PlayerPos,
                yaw = Game.Player.Yaw,
                timeOfDay = Game.Env.timeOfDay,
                day = Game.Env.day,
                weather = (int)Game.Env.weather,
            };
            Game.Stats.SaveTo(d);
            Game.Inventory.SaveTo(d);
            Game.Quests.SaveTo(d);
            d.flags = Flags.AllFlags();
            d.vars = Flags.AllVars();
            d.reputation = Factions.Save();
            d.ownedVehicles = new System.Collections.Generic.List<string>(Game.Traffic.owned);
            foreach (var l in Game.City.locations.Values) if (l.discovered) d.discovered.Add(l.id);
            bool ok = SaveSystem.Write(slot, d);
            if (ok && slot == SaveSystem.Auto) Game.UI?.Notify("Autosaved", new Color(0.6f, 0.7f, 0.8f));
            return ok;
        }

        public void LoadFrom(string slot)
        {
            var d = SaveSystem.Peek(slot);
            if (d == null) { Game.UI?.Notify("Save could not be loaded", Palette.Red); return; }
            StartCoroutine(LoadRoutine(d));
        }

        IEnumerator LoadRoutine(SaveData d)
        {
            Game.UI?.Fade(1f);
            ResetWorld();
            yield return null;
            Game.Profile = d.profile ?? new CharacterProfile();
            Game.Profile.Migrate();
            Game.Difficulty = (Difficulty)d.difficulty;
            Game.PlayTime = d.playTime;
            SpawnPlayer(Game.Profile, d.position + Vector3.up * 0.2f, d.yaw);
            Flags.Load(d.flags, d.vars);
            Boxing.LoadInjuries();
            Factions.Load(d.reputation);
            Game.Stats.LoadFrom(d);
            Game.Inventory.LoadFrom(d);
            foreach (var v in d.ownedVehicles) Game.Traffic.Own(v);
            foreach (var id in d.discovered) { var l = Game.City.Loc(id); if (l != null) l.discovered = true; }
            Game.Env.timeOfDay = d.timeOfDay; Game.Env.day = Mathf.Max(1, d.day);
            Game.Env.SetWeather((Weather)d.weather, true);
            Game.Activities.RestoreWorldState();
            Story.SpawnPersistentNpcs();
            yield return null;
            Game.Quests.LoadFrom(d);
            SetState(GameState.Playing);
            Game.UI?.Banner("NEON BAY", "Welcome back, " + Game.Profile.name, Palette.Cyan);
        }

        public void QuitToMenu()
        {
            ResetWorld();
            if (Game.Player != null) Destroy(Game.Player.gameObject);
            Game.Player = null; Game.Stats = null; Game.Inventory = null; Game.Weapons = null; Game.Hacking = null; Game.Interactor = null;
            if (menuCam != null) menuCam.gameObject.SetActive(true);
            Game.Music?.SetStation(0);
            SetState(GameState.MainMenu);
        }
    }

    /// <summary>Optional marker: add to any scene to make the game boot there.</summary>
    public class NeonBayBoot : MonoBehaviour { }
}
