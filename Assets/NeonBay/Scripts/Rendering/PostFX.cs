using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// URP post-processing set up through reflection so the scripts compile (and simply skip
    /// post effects) in a project that doesn't have URP installed.
    /// </summary>
    public static class PostFX
    {
        const string URPNs = "UnityEngine.Rendering.Universal.";
        static Component volume;
        static ScriptableObject profile;
        static readonly Dictionary<string, object> comps = new Dictionary<string, object>();
        static bool enabled = true;
        public static bool Available => volume != null;

        static Type FindType(string fullName)
        {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                var t = asm.GetType(fullName, false);
                if (t != null) return t;
            }
            return null;
        }

        public static void Init(GameObject host)
        {
            if (!Mats.URP) return;
            try
            {
                var volumeType = FindType("UnityEngine.Rendering.Volume");
                var profileType = FindType("UnityEngine.Rendering.VolumeProfile");
                if (volumeType == null || profileType == null) return;

                // Disable any volumes already in the scene (template sample scenes ship one).
                foreach (var v in UnityEngine.Object.FindObjectsByType(volumeType, FindObjectsSortMode.None))
                    if (v is Behaviour b) b.enabled = false;

                volume = host.AddComponent(volumeType);
                profile = ScriptableObject.CreateInstance(profileType);
                profile.name = "NeonBayProfile";
                Set(volume, "isGlobal", true);
                Set(volume, "priority", 100f);
                Set(volume, "sharedProfile", profile);

                var add = profileType.GetMethod("Add", new[] { typeof(Type), typeof(bool) });
                foreach (var n in new[] { "Tonemapping", "Bloom", "ColorAdjustments", "Vignette", "ChromaticAberration", "FilmGrain", "MotionBlur", "WhiteBalance", "SplitToning", "LensDistortion" })
                {
                    var t = FindType(URPNs + n);
                    if (t == null || add == null) continue;
                    comps[n] = add.Invoke(profile, new object[] { t, false });
                }

                Param("Tonemapping", "mode", "ACES");
                Param("Bloom", "threshold", 0.95f);
                Param("Bloom", "intensity", 1.1f);
                Param("Bloom", "scatter", 0.72f);
                Param("Bloom", "highQualityFiltering", true);
                Param("ColorAdjustments", "postExposure", 0.15f);
                Param("ColorAdjustments", "contrast", 18f);
                Param("ColorAdjustments", "saturation", 8f);
                Param("Vignette", "intensity", 0.32f);
                Param("Vignette", "smoothness", 0.45f);
                Param("ChromaticAberration", "intensity", 0.08f);
                Param("FilmGrain", "type", "Thin2");
                Param("FilmGrain", "intensity", 0.18f);
                Param("MotionBlur", "intensity", 0.25f);
                Param("SplitToning", "shadows", new Color(0.35f, 0.45f, 0.75f));
                Param("SplitToning", "highlights", new Color(0.95f, 0.55f, 0.75f));
                Param("SplitToning", "balance", -15f);
                Param("LensDistortion", "intensity", 0f);
            }
            catch (Exception e)
            {
                Debug.LogWarning("[NeonBay] Post processing unavailable: " + e.Message);
                volume = null;
            }
        }

        public static void SetupCamera(Camera cam)
        {
            if (!Mats.URP || cam == null) return;
            try
            {
                var t = FindType(URPNs + "UniversalAdditionalCameraData");
                if (t == null) return;
                var data = cam.GetComponent(t);
                if (data == null) data = cam.gameObject.AddComponent(t);
                Set(data, "renderPostProcessing", true);
                Set(data, "dithering", true);
                Set(data, "stopNaN", true);
                var aaType = FindType(URPNs + "AntialiasingMode");
                if (aaType != null) Set(data, "antialiasing", Enum.Parse(aaType, "SubpixelMorphologicalAntiAliasing"));
            }
            catch (Exception e)
            {
                Debug.LogWarning("[NeonBay] Camera post setup failed: " + e.Message);
            }
        }

        public static void SetEnabled(bool on)
        {
            enabled = on;
            if (volume is Behaviour b) b.enabled = on;
        }

        public static void SetBloom(float intensity, float threshold = -1f)
        {
            Param("Bloom", "intensity", intensity);
            if (threshold >= 0) Param("Bloom", "threshold", threshold);
        }

        public static void SetGrade(float exposure, float contrast, float saturation, Color filter)
        {
            Param("ColorAdjustments", "postExposure", exposure);
            Param("ColorAdjustments", "contrast", contrast);
            Param("ColorAdjustments", "saturation", saturation);
            Param("ColorAdjustments", "colorFilter", filter);
        }

        public static void SetWhiteBalance(float temperature, float tint)
        {
            Param("WhiteBalance", "temperature", temperature);
            Param("WhiteBalance", "tint", tint);
        }

        public static void SetVignette(float intensity, Color color)
        {
            Param("Vignette", "intensity", intensity);
            Param("Vignette", "color", color);
        }

        public static void SetChromatic(float v) => Param("ChromaticAberration", "intensity", Mathf.Clamp01(v));
        public static void SetLensDistortion(float v) => Param("LensDistortion", "intensity", Mathf.Clamp(v, -1f, 1f));
        public static void SetMotionBlur(float v) => Param("MotionBlur", "intensity", Mathf.Clamp01(v));
        public static void SetGrain(float v) => Param("FilmGrain", "intensity", Mathf.Clamp01(v));

        // ------------------------------------------------------------ reflection helpers
        static void Param(string comp, string field, object value)
        {
            if (volume == null) return;
            if (!comps.TryGetValue(comp, out var c) || c == null) return;
            try
            {
                var f = c.GetType().GetField(field, BindingFlags.Public | BindingFlags.Instance);
                if (f == null) return;
                var p = f.GetValue(c);
                if (p == null) return;
                var pt = p.GetType();
                pt.GetProperty("overrideState")?.SetValue(p, true);
                var valueProp = pt.GetProperty("value");
                if (valueProp == null) return;
                var target = valueProp.PropertyType;
                object v = value;
                if (value is string s && target.IsEnum) v = Enum.Parse(target, s);
                else if (value is float fl && target == typeof(int)) v = (int)fl;
                else if (value is Color col && target == typeof(Vector4)) v = (Vector4)col;
                valueProp.SetValue(p, v);
            }
            catch (Exception) { }
        }

        static void Set(object target, string member, object value)
        {
            if (target == null) return;
            var t = target.GetType();
            var p = t.GetProperty(member, BindingFlags.Public | BindingFlags.Instance);
            if (p != null && p.CanWrite) { p.SetValue(target, value); return; }
            var f = t.GetField(member, BindingFlags.Public | BindingFlags.Instance);
            if (f != null) f.SetValue(target, value);
        }
    }
}
