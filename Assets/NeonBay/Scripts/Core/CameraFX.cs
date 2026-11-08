using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// Game-feel layer shared by every camera: trauma shake (perlin, squared falloff), directional kicks on a spring,
    /// FOV punches, hit-stop freeze frames, slow motion, colour flashes, concussion sway and blur.
    /// </summary>
    public static class CameraFX
    {
        static float trauma;
        static Vector3 kick, kickVel;
        static float fov, fovVel;
        static float hitStopT;
        static float slowT, slowScale = 1f, slowFade;
        static float flash; static Color flashColor = Color.white;
        static float dizzy, dizzyHold;
        static float chroma, lens, blur, blurHold;
        static float seed = 13.7f;

        public static float Trauma => trauma;
        public static float FlashAmount => flash;
        public static Color FlashColor => flashColor;
        public static float DizzyAmount => dizzy;
        public static float ChromaExtra => chroma + dizzy * 0.35f;
        public static float LensExtra => lens + Mathf.Sin(Time.unscaledTime * 1.7f) * dizzy * 0.22f;
        public static float BlurAmount => Mathf.Max(blur, dizzy * 0.45f);

        /// <summary>Additive trauma; perceived shake is trauma squared.</summary>
        public static void Shake(float amount) => trauma = Mathf.Clamp01(trauma + Mathf.Max(0f, amount));

        /// <summary>Snap the camera by euler degrees (pitch, yaw, roll); it springs back.</summary>
        public static void Kick(Vector3 eulerDeg) => kickVel += eulerDeg * 22f;

        /// <summary>Kick the camera away from a world-space hit direction.</summary>
        public static void KickFrom(Camera cam, Vector3 worldDir, float degrees)
        {
            if (cam == null) return;
            var l = cam.transform.InverseTransformDirection(worldDir.normalized);
            Kick(new Vector3(-l.y - Mathf.Abs(l.z) * 0.6f, l.x, -l.x * 0.8f) * degrees);
        }

        public static void FovPunch(float degrees) => fovVel += degrees * 18f;

        /// <summary>Freeze the action for a few frames to sell a heavy impact.</summary>
        public static void HitStop(float seconds)
        {
            if (Game.Settings != null && !Game.Settings.screenShake) return;
            hitStopT = Mathf.Max(hitStopT, seconds);
        }

        public static void SlowMo(float scale, float seconds) { slowScale = Mathf.Clamp(scale, 0.05f, 1f); slowT = seconds; slowFade = 0.35f; }
        public static void Flash(Color c, float amount) { flashColor = c; flash = Mathf.Clamp01(Mathf.Max(flash, amount)); }
        public static void Dizzy(float amount, float hold = 1f) { dizzy = Mathf.Clamp01(Mathf.Max(dizzy, amount)); dizzyHold = Mathf.Max(dizzyHold, hold); }
        public static void Chroma(float amount) => chroma = Mathf.Clamp01(Mathf.Max(chroma, amount));
        public static void Lens(float amount) => lens = Mathf.Clamp(lens + amount, -0.6f, 0.6f);
        public static void Blur(float amount, float hold) { blur = Mathf.Clamp01(Mathf.Max(blur, amount)); blurHold = Mathf.Max(blurHold, hold); }

        public static void Clear()
        {
            trauma = 0; kick = kickVel = Vector3.zero; fov = fovVel = 0; hitStopT = 0; slowT = 0; slowScale = 1; flash = 0; dizzy = 0; chroma = 0; lens = 0; blur = 0;
        }

        /// <summary>Multiplier applied on top of the game's base time scale.</summary>
        public static float TimeScale
        {
            get
            {
                if (hitStopT > 0f) return 0.03f;
                if (slowT > 0f) return slowScale;
                if (slowFade > 0f) return Mathf.Lerp(1f, slowScale, slowFade / 0.35f);
                return 1f;
            }
        }

        public static void Tick(float dt)
        {
            if (dt <= 0f) return;
            dt = Mathf.Min(dt, 0.1f);
            float shakeSetting = Game.Settings != null && !Game.Settings.screenShake ? 0.25f : 1f;
            trauma = Mathf.MoveTowards(trauma, 0f, dt * 1.35f);
            hitStopT -= dt;
            if (slowT > 0f) slowT -= dt; else if (slowFade > 0f) slowFade -= dt;
            kickVel += (-kick * 260f - kickVel * 22f) * dt;
            kick += kickVel * dt * shakeSetting;
            fovVel += (-fov * 200f - fovVel * 18f) * dt;
            fov += fovVel * dt;
            flash = Mathf.MoveTowards(flash, 0f, dt * 2.6f);
            dizzyHold -= dt;
            if (dizzyHold <= 0f) dizzy = Mathf.MoveTowards(dizzy, 0f, dt * 0.35f);
            chroma = Mathf.MoveTowards(chroma, 0f, dt * 2.2f);
            lens = Mathf.MoveTowards(lens, 0f, dt * 1.8f);
            blurHold -= dt;
            if (blurHold <= 0f) blur = Mathf.MoveTowards(blur, 0f, dt * 0.9f);
            seed += dt;
        }

        /// <summary>Rotation offset (degrees) to apply to a camera this frame.</summary>
        public static Vector3 RotationOffset
        {
            get
            {
                float shakeSetting = Game.Settings != null && !Game.Settings.screenShake ? 0.25f : 1f;
                float s = trauma * trauma * shakeSetting;
                float t = Time.unscaledTime * 24f;
                var shake = new Vector3(Mathf.PerlinNoise(t, 3.1f) - 0.5f, Mathf.PerlinNoise(5.3f, t) - 0.5f, Mathf.PerlinNoise(t, 7.7f) - 0.5f) * s * 9f;
                float dt2 = Time.unscaledTime;
                var sway = new Vector3(Mathf.Sin(dt2 * 1.3f) * 1.6f, Mathf.Sin(dt2 * 0.83f) * 2.4f, Mathf.Sin(dt2 * 1.1f) * 3.5f) * dizzy;
                return shake + kick + sway;
            }
        }

        public static Vector3 PositionOffset
        {
            get
            {
                float shakeSetting = Game.Settings != null && !Game.Settings.screenShake ? 0.25f : 1f;
                float s = trauma * trauma * shakeSetting;
                float t = Time.unscaledTime * 21f;
                return new Vector3(Mathf.PerlinNoise(t, 0.1f) - 0.5f, Mathf.PerlinNoise(0.3f, t) - 0.5f, 0f) * s * 0.22f;
            }
        }

        public static float FovOffset => fov;
    }
}
