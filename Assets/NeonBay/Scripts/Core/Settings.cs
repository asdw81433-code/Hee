using UnityEngine;

namespace NeonBay
{
    /// <summary>Player options, persisted with PlayerPrefs.</summary>
    public class Settings
    {
        public float mouseSensitivity = 1f;
        public bool invertY;
        public float fov = 78f;
        public float masterVolume = 0.9f;
        public float musicVolume = 0.55f;
        public float sfxVolume = 0.9f;
        public int quality = -1;
        public bool postFx = true;
        public bool motionBlur = true;
        public bool headBob = true;
        public bool screenShake = true;
        public bool gore = true;
        public bool showFps;
        public float viewDistance = 1400f;
        public bool subtitles = true;
        public float uiScale = 1f;
        /// <summary>On-screen touch controls: 0 = auto (phones/tablets), 1 = always on, 2 = off.</summary>
        public int touchControls;
        public float touchSize = 1f;

        const string P = "nb_";

        public static Settings Load()
        {
            var s = new Settings
            {
                mouseSensitivity = PlayerPrefs.GetFloat(P + "sens", 1f),
                invertY = PlayerPrefs.GetInt(P + "invy", 0) == 1,
                fov = PlayerPrefs.GetFloat(P + "fov", 78f),
                masterVolume = PlayerPrefs.GetFloat(P + "vol", 0.9f),
                musicVolume = PlayerPrefs.GetFloat(P + "mus", 0.55f),
                sfxVolume = PlayerPrefs.GetFloat(P + "sfx", 0.9f),
                quality = PlayerPrefs.GetInt(P + "q", -1),
                postFx = PlayerPrefs.GetInt(P + "pfx", 1) == 1,
                motionBlur = PlayerPrefs.GetInt(P + "mb", 1) == 1,
                headBob = PlayerPrefs.GetInt(P + "bob", 1) == 1,
                screenShake = PlayerPrefs.GetInt(P + "shk", 1) == 1,
                gore = PlayerPrefs.GetInt(P + "gore", 1) == 1,
                showFps = PlayerPrefs.GetInt(P + "fps", 0) == 1,
                viewDistance = PlayerPrefs.GetFloat(P + "vd", 1400f),
                subtitles = PlayerPrefs.GetInt(P + "sub", 1) == 1,
                uiScale = PlayerPrefs.GetFloat(P + "ui", 1f),
                touchControls = PlayerPrefs.GetInt(P + "touch", 0),
                touchSize = PlayerPrefs.GetFloat(P + "tsize", 1f),
            };
            if (s.quality < 0) s.quality = QualitySettings.GetQualityLevel();
            if (Application.isMobilePlatform && !PlayerPrefs.HasKey(P + "vd"))
            {
                // first launch on a phone: shorter draw distance, no motion blur, slightly larger UI
                s.viewDistance = 750f;
                s.motionBlur = false;
                s.uiScale = 1.1f;
            }
            return s;
        }

        public void Save()
        {
            PlayerPrefs.SetFloat(P + "sens", mouseSensitivity);
            PlayerPrefs.SetInt(P + "invy", invertY ? 1 : 0);
            PlayerPrefs.SetFloat(P + "fov", fov);
            PlayerPrefs.SetFloat(P + "vol", masterVolume);
            PlayerPrefs.SetFloat(P + "mus", musicVolume);
            PlayerPrefs.SetFloat(P + "sfx", sfxVolume);
            PlayerPrefs.SetInt(P + "q", quality);
            PlayerPrefs.SetInt(P + "pfx", postFx ? 1 : 0);
            PlayerPrefs.SetInt(P + "mb", motionBlur ? 1 : 0);
            PlayerPrefs.SetInt(P + "bob", headBob ? 1 : 0);
            PlayerPrefs.SetInt(P + "shk", screenShake ? 1 : 0);
            PlayerPrefs.SetInt(P + "gore", gore ? 1 : 0);
            PlayerPrefs.SetInt(P + "fps", showFps ? 1 : 0);
            PlayerPrefs.SetFloat(P + "vd", viewDistance);
            PlayerPrefs.SetInt(P + "sub", subtitles ? 1 : 0);
            PlayerPrefs.SetFloat(P + "ui", uiScale);
            PlayerPrefs.SetInt(P + "touch", touchControls);
            PlayerPrefs.SetFloat(P + "tsize", touchSize);
            PlayerPrefs.Save();
        }

        public void Apply()
        {
            AudioListener.volume = masterVolume;
            int levels = QualitySettings.names.Length;
            if (levels > 0)
            {
                quality = Mathf.Clamp(quality, 0, levels - 1);
                if (QualitySettings.GetQualityLevel() != quality) QualitySettings.SetQualityLevel(quality, true);
            }
            PostFX.SetEnabled(postFx);
            PostFX.SetMotionBlur(motionBlur ? 0.25f : 0f);
            var cam = Game.Cam;
            if (cam != null) cam.farClipPlane = viewDistance;
            if (Application.isMobilePlatform) ApplyMobile();
        }

        /// <summary>Phone budget: lower render resolution, no MSAA, short shadows and a tighter prop/detail radius.</summary>
        void ApplyMobile()
        {
            if (Game.Chunks != null) Game.Chunks.detailDistance = Mathf.Clamp(viewDistance * 0.35f, 160f, 380f);
            var rp = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline;
            if (rp == null) return;
            var t = rp.GetType();
            void Set(string name, object value)
            {
                var prop = t.GetProperty(name);
                if (prop == null || !prop.CanWrite) return;
                try { prop.SetValue(rp, value); } catch (System.Exception) { }
            }
            Set("renderScale", viewDistance < 900f ? 0.75f : 0.85f);
            Set("msaaSampleCount", 1);
            Set("shadowDistance", Mathf.Clamp(viewDistance * 0.08f, 40f, 90f));
        }
    }
}
