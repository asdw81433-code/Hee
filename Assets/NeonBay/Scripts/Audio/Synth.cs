using System;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// Procedural sound design: every sound effect in the game is synthesized at load time,
    /// so the project needs no audio assets.
    /// </summary>
    public static class Synth
    {
        public const int SR = 44100;
        static uint seed = 12345;
        static float Noise() { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return (seed & 0xFFFFFF) / 8388607.5f - 1f; }
        static float Lp(float cutoff) => 1f - Mathf.Exp(-2f * Mathf.PI * cutoff / SR);
        const float TAU = Mathf.PI * 2f;

        static AudioClip Clip(string name, float[] data, bool normalize = true, float peak = 0.9f)
        {
            if (normalize)
            {
                float m = 0.0001f;
                for (int i = 0; i < data.Length; i++) m = Mathf.Max(m, Mathf.Abs(data[i]));
                float k = peak / m;
                for (int i = 0; i < data.Length; i++) data[i] *= k;
            }
            var c = AudioClip.Create(name, data.Length, 1, SR, false);
            c.SetData(data, 0);
            return c;
        }

        static void Echo(float[] d, float delaySec, float gain, int taps = 3)
        {
            int del = (int)(delaySec * SR);
            for (int t = 1; t <= taps; t++)
            {
                int dd = del * t; float g = Mathf.Pow(gain, t);
                for (int i = d.Length - 1; i >= dd; i--) d[i] += d[i - dd] * g;
            }
        }

        static float[] Loopable(float[] d, int fade)
        {
            int n = d.Length;
            fade = Mathf.Min(fade, n / 3);
            var o = new float[n - fade];
            for (int i = 0; i < o.Length; i++) o[i] = d[i];
            for (int i = 0; i < fade; i++)
            {
                float t = i / (float)fade;
                o[i] = d[i] * t + d[n - fade + i] * (1 - t);
            }
            return o;
        }

        // ------------------------------------------------------------------ recipes
        static float[] Gunshot(float len, float body, float crack, float decay, float lowpass, float echo, int s)
        {
            seed = (uint)(s * 7919 + 1);
            int n = (int)(len * SR); var d = new float[n];
            float lp = 0, a = Lp(lowpass), ph = 0;
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)SR;
                float nz = Noise();
                lp += a * (nz - lp);
                float env = Mathf.Exp(-t / decay);
                float crackEnv = Mathf.Exp(-t / 0.006f);
                float f = body * (1f + 2.5f * Mathf.Exp(-t / 0.015f));
                ph += TAU * f / SR;
                float bodyS = Mathf.Sin(ph) * Mathf.Exp(-t / (decay * 0.5f));
                float v = lp * env * 1.2f + nz * crackEnv * crack + bodyS * 0.9f;
                d[i] = (float)Math.Tanh(v * 2.2f);
            }
            Echo(d, echo, 0.28f, 3);
            return d;
        }

        static float[] Thud(float len, float freq, float decay, float noiseAmt, float lowpass, int s)
        {
            seed = (uint)(s * 31 + 7);
            int n = (int)(len * SR); var d = new float[n];
            float lp = 0, a = Lp(lowpass), ph = 0;
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)SR;
                lp += a * (Noise() - lp);
                ph += TAU * freq * (1 + Mathf.Exp(-t / 0.01f)) / SR;
                d[i] = (Mathf.Sin(ph) * 0.8f + lp * noiseAmt) * Mathf.Exp(-t / decay);
            }
            return d;
        }

        static float[] Tone(float len, float f0, float f1, float decay, int wave = 0, float attack = 0.003f)
        {
            int n = (int)(len * SR); var d = new float[n];
            float ph = 0;
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)SR;
                float f = Mathf.Lerp(f0, f1, t / len);
                ph += TAU * f / SR;
                float w = wave == 0 ? Mathf.Sin(ph) : wave == 1 ? Mathf.Sign(Mathf.Sin(ph)) * 0.6f : ((ph / TAU) % 1f) * 2f - 1f;
                float env = Mathf.Min(1f, t / attack) * Mathf.Exp(-t / decay);
                d[i] = w * env;
            }
            return d;
        }

        static float[] Seq(params float[][] parts)
        {
            int n = 0; foreach (var p in parts) n += p.Length;
            var d = new float[n]; int o = 0;
            foreach (var p in parts) { Array.Copy(p, 0, d, o, p.Length); o += p.Length; }
            return d;
        }

        static float[] Mix(float[] a, float[] b, float gb, int offset = 0)
        {
            var d = new float[Mathf.Max(a.Length, b.Length + offset)];
            for (int i = 0; i < a.Length; i++) d[i] += a[i];
            for (int i = 0; i < b.Length; i++) d[i + offset] += b[i] * gb;
            return d;
        }

        static float[] Whoosh(float len, float f0, float f1, int s, float q = 0.3f)
        {
            seed = (uint)(s * 13 + 3);
            int n = (int)(len * SR); var d = new float[n];
            float low = 0, band = 0;
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)len / SR;
                float f = Mathf.Lerp(f0, f1, t);
                float fc = 2f * Mathf.Sin(Mathf.PI * Mathf.Min(f, SR * 0.2f) / SR);
                float x = Noise();
                low += fc * band; float high = x - low - q * band; band += fc * high;
                d[i] = band * Mathf.Sin(Mathf.PI * t);
            }
            return d;
        }

        static float[] NoiseLoop(float len, float lowCut, float highCut, int s, float lfoHz = 0f, float lfoDepth = 0f)
        {
            seed = (uint)(s * 97 + 11);
            int n = (int)(len * SR); var d = new float[n];
            float lpA = 0, lpB = 0, aH = Lp(highCut), aL = Lp(lowCut);
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)SR;
                float x = Noise();
                lpA += aH * (x - lpA);
                lpB += aL * (lpA - lpB);
                float v = lpA - lpB;
                if (lfoHz > 0) v *= 1f - lfoDepth * (0.5f + 0.5f * Mathf.Sin(TAU * lfoHz * t));
                d[i] = v;
            }
            return Loopable(d, SR / 2);
        }

        static float[] Brown(float len, float lowpass, int s)
        {
            seed = (uint)(s * 53 + 17);
            int n = (int)(len * SR); var d = new float[n];
            float b = 0, lp = 0, a = Lp(lowpass);
            for (int i = 0; i < n; i++)
            {
                b = b * 0.995f + Noise() * 0.05f;
                lp += a * (b - lp);
                d[i] = lp;
            }
            return d;
        }

        // ------------------------------------------------------------------ build everything
        public static void BuildAll(AudioManager am)
        {
            // weapons
            am.Register("pistol", Clip("pistol", Gunshot(0.9f, 160f, 0.9f, 0.05f, 2600f, 0.21f, 1)));
            am.Register("pistol", Clip("pistol2", Gunshot(0.9f, 150f, 0.85f, 0.055f, 2400f, 0.19f, 2)));
            am.Register("smg", Clip("smg", Gunshot(0.6f, 190f, 0.7f, 0.035f, 3200f, 0.17f, 3)));
            am.Register("smg", Clip("smg2", Gunshot(0.6f, 200f, 0.75f, 0.03f, 3400f, 0.16f, 4)));
            am.Register("rifle", Clip("rifle", Gunshot(1.1f, 120f, 1.2f, 0.06f, 3800f, 0.24f, 5)));
            am.Register("rifle", Clip("rifle2", Gunshot(1.1f, 115f, 1.1f, 0.065f, 3600f, 0.26f, 6)));
            am.Register("shotgun", Clip("shotgun", Gunshot(1.4f, 80f, 1f, 0.12f, 1800f, 0.28f, 7)));
            am.Register("revolver", Clip("revolver", Gunshot(1.4f, 95f, 1.3f, 0.09f, 2200f, 0.3f, 8)));
            am.Register("sniper", Clip("sniper", Gunshot(2.2f, 70f, 1.6f, 0.11f, 4200f, 0.45f, 9)));
            am.Register("enemy_shot", Clip("eshot", Gunshot(0.8f, 140f, 0.8f, 0.05f, 2000f, 0.25f, 10)));
            am.Register("empty", Clip("empty", Tone(0.06f, 2400f, 1800f, 0.01f, 1)));
            am.Register("reload", Clip("reload", Mix(Thud(0.08f, 900f, 0.015f, 0.6f, 5000f, 11), Thud(0.1f, 600f, 0.02f, 0.5f, 4000f, 12), 0.8f, (int)(0.18f * SR))));
            am.Register("reload_end", Clip("reload_end", Mix(Thud(0.07f, 1200f, 0.012f, 0.7f, 6000f, 13), Thud(0.08f, 700f, 0.015f, 0.6f, 5000f, 14), 1f, (int)(0.09f * SR))));
            am.Register("swap", Clip("swap", Whoosh(0.18f, 800f, 2400f, 15)));

            // impacts
            am.Register("impact_concrete", Clip("ic", Thud(0.15f, 300f, 0.02f, 1.5f, 3000f, 16), true, 0.6f));
            am.Register("impact_concrete", Clip("ic2", Thud(0.15f, 260f, 0.025f, 1.6f, 2600f, 17), true, 0.6f));
            am.Register("impact_metal", Clip("im", Mix(Tone(0.35f, 2600f, 2500f, 0.08f), Tone(0.35f, 3900f, 3800f, 0.05f), 0.6f), true, 0.5f));
            am.Register("impact_flesh", Clip("if", Thud(0.18f, 110f, 0.04f, 0.8f, 600f, 18), true, 0.8f));
            am.Register("shield_hit", Clip("sh", Mix(Tone(0.3f, 1800f, 1400f, 0.06f), Thud(0.1f, 200f, 0.03f, 0.5f, 1500f, 19), 0.7f), true, 0.7f));
            am.Register("hitmarker", Clip("hm", Tone(0.05f, 3200f, 3000f, 0.015f), true, 0.35f));
            am.Register("headshot", Clip("hs", Mix(Tone(0.12f, 1500f, 2200f, 0.03f), Tone(0.12f, 3000f, 3300f, 0.02f), 0.7f), true, 0.5f));

            // explosions
            var boom = Brown(3f, 500f, 20);
            var crack = Gunshot(0.4f, 50f, 2f, 0.08f, 1500f, 0.01f, 21);
            for (int i = 0; i < boom.Length; i++) { float t = i / (float)SR; boom[i] = (float)Math.Tanh(boom[i] * 30f * Mathf.Exp(-t / 0.6f)); }
            am.Register("explosion", Clip("explosion", Mix(boom, crack, 0.8f)));
            am.Register("grenade_bounce", Clip("gb", Thud(0.08f, 700f, 0.015f, 0.4f, 4000f, 22), true, 0.5f));

            // movement
            for (int v = 0; v < 4; v++)
                am.Register("step", Clip("step" + v, Mix(Thud(0.12f, 80f + v * 12, 0.03f, 1.4f, 1100f + v * 150, 30 + v), Whoosh(0.05f, 3000f, 1500f, 40 + v, 0.6f), 0.3f), true, 0.45f));
            for (int v = 0; v < 3; v++)
                am.Register("step_wet", Clip("stepw" + v, Mix(Thud(0.12f, 80f, 0.03f, 1.2f, 1000f, 50 + v), NoiseLoop(0.2f, 1500f, 7000f, 60 + v), 0.5f), true, 0.45f));
            am.Register("land", Clip("land", Thud(0.25f, 70f, 0.06f, 1.5f, 900f, 70), true, 0.7f));
            am.Register("jump", Clip("jump", Whoosh(0.15f, 500f, 1500f, 71), true, 0.3f));
            am.Register("dash", Clip("dash", Whoosh(0.35f, 300f, 4000f, 72, 0.2f), true, 0.8f));
            am.Register("slide", Clip("slide", NoiseLoop(0.6f, 300f, 2500f, 73), true, 0.5f));

            // melee
            am.Register("swing", Clip("swing", Whoosh(0.25f, 400f, 2200f, 80), true, 0.6f));
            am.Register("punch", Clip("punch", Thud(0.16f, 90f, 0.035f, 1.2f, 800f, 81), true, 0.9f));
            am.Register("slash", Clip("slash", Mix(Whoosh(0.3f, 1500f, 6000f, 82, 0.15f), Tone(0.4f, 5200f, 5000f, 0.1f), 0.25f), true, 0.8f));

            // UI
            am.Register("ui_blip", Clip("ub", Tone(0.06f, 1200f, 1200f, 0.03f), true, 0.35f));
            am.Register("ui_hover", Clip("uh", Tone(0.03f, 2200f, 2200f, 0.012f), true, 0.15f));
            am.Register("ui_confirm", Clip("uc", Seq(Tone(0.07f, 880f, 880f, 0.04f), Tone(0.12f, 1320f, 1320f, 0.06f)), true, 0.4f));
            am.Register("ui_error", Clip("ue", Tone(0.2f, 140f, 120f, 0.12f, 1), true, 0.35f));
            am.Register("ui_open", Clip("uo", Tone(0.18f, 300f, 1200f, 0.12f, 2), true, 0.3f));
            am.Register("notify", Clip("nt", Seq(Tone(0.08f, 1046f, 1046f, 0.05f), Tone(0.15f, 1568f, 1568f, 0.08f)), true, 0.35f));
            am.Register("levelup", Clip("lu", Seq(Tone(0.12f, 523f, 523f, 0.1f, 2), Tone(0.12f, 659f, 659f, 0.1f, 2), Tone(0.12f, 784f, 784f, 0.1f, 2), Tone(0.5f, 1046f, 1046f, 0.35f, 2)), true, 0.5f));
            am.Register("quest_done", Clip("qd", Mix(Mix(Tone(1.2f, 440f, 440f, 0.6f, 2, 0.1f), Tone(1.2f, 554f, 554f, 0.6f, 2, 0.1f), 0.8f), Tone(1.2f, 659f, 659f, 0.6f, 2, 0.1f), 0.8f), true, 0.5f));
            am.Register("pickup", Clip("pk", Tone(0.12f, 700f, 1600f, 0.06f), true, 0.35f));
            am.Register("cash", Clip("cs", Seq(Tone(0.08f, 2093f, 2093f, 0.05f), Tone(0.25f, 2637f, 2637f, 0.1f)), true, 0.35f));
            var ring = new float[(int)(1.4f * SR)];
            for (int i = 0; i < ring.Length; i++) { float t = i / (float)SR; float on = (t % 0.7f) < 0.4f ? 1f : 0f; ring[i] = (Mathf.Sin(TAU * 440 * t) + Mathf.Sin(TAU * 480 * t)) * 0.5f * on * (0.5f + 0.5f * Mathf.Sign(Mathf.Sin(TAU * 20 * t))); }
            am.Register("phone", Clip("phone", ring, true, 0.3f));

            // hacking
            seed = 900;
            var glitch = new float[(int)(0.5f * SR)];
            float gf = 400; int hold = 0;
            for (int i = 0; i < glitch.Length; i++)
            {
                if (--hold <= 0) { hold = (int)(SR * (0.01f + (Noise() * 0.5f + 0.5f) * 0.04f)); gf = 200 + (Noise() * 0.5f + 0.5f) * 3000; }
                float t = i / (float)SR;
                glitch[i] = Mathf.Round(Mathf.Sign(Mathf.Sin(TAU * gf * t)) * 3f) / 3f * Mathf.Exp(-t / 0.3f);
            }
            am.Register("glitch", Clip("glitch", glitch, true, 0.4f));
            am.Register("scan", Clip("scan", Tone(0.45f, 400f, 2200f, 0.4f, 0, 0.05f), true, 0.3f));
            am.Register("hack_start", Clip("hs1", Seq(Tone(0.05f, 1800f, 1800f, 0.03f, 1), Tone(0.05f, 2400f, 2400f, 0.03f, 1), Tone(0.08f, 3000f, 3000f, 0.04f, 1)), true, 0.3f));
            am.Register("hack_done", Clip("hd", Mix(glitch, Tone(0.4f, 1200f, 300f, 0.2f, 2), 0.8f), true, 0.5f));
            am.Register("slowmo", Clip("sm", Mix(Tone(1.2f, 600f, 70f, 0.8f, 2, 0.02f), Whoosh(1.2f, 3000f, 200f, 91), 0.5f), true, 0.7f));

            // vehicles & world
            var eng = new float[SR];
            seed = 300;
            for (int i = 0; i < eng.Length; i++)
            {
                float t = i / (float)SR;
                float v = 0;
                for (int k = 1; k <= 10; k++) v += Mathf.Sin(TAU * 40f * k * t + k) / k * (k % 2 == 0 ? 1.4f : 0.8f);
                v *= 0.7f + 0.3f * Mathf.Sin(TAU * 20f * t);
                eng[i] = v;
            }
            am.Register("engine", Clip("engine", eng, true, 0.5f));
            am.Register("skid", Clip("skid", NoiseLoop(1.2f, 1200f, 4500f, 301, 8f, 0.4f), true, 0.5f));
            am.Register("horn", Clip("horn", Mix(Tone(0.6f, 350f, 350f, 2f, 1, 0.01f), Tone(0.6f, 440f, 440f, 2f, 1, 0.01f), 0.8f), true, 0.5f));
            am.Register("crash", Clip("crash", Mix(Thud(0.6f, 60f, 0.12f, 2f, 1200f, 302), Mix(Tone(0.8f, 1300f, 1250f, 0.25f), Tone(0.8f, 2100f, 2000f, 0.2f), 0.7f), 0.4f), true, 0.9f));
            am.Register("door", Clip("door", Mix(Whoosh(0.35f, 300f, 900f, 303), Thud(0.12f, 120f, 0.03f, 1f, 1000f, 304), 0.9f, (int)(0.3f * SR)), true, 0.6f));
            am.Register("vend", Clip("vend", Seq(Thud(0.15f, 140f, 0.04f, 1f, 1500f, 305), Thud(0.2f, 400f, 0.05f, 0.5f, 3000f, 306)), true, 0.6f));
            am.Register("crate", Clip("crate", Mix(Tone(0.4f, 200f, 120f, 0.2f, 2), Thud(0.15f, 150f, 0.04f, 1f, 1200f, 307), 1f, (int)(0.3f * SR)), true, 0.6f));

            // ambience loops
            var city = Brown(9f, 350f, 400);
            var traffic = NoiseLoop(9.5f, 200f, 1200f, 401, 0.25f, 0.8f);
            var cityL = new float[city.Length];
            for (int i = 0; i < city.Length; i++) { float t = i / (float)SR; cityL[i] = city[i] * 8f + (i < traffic.Length ? traffic[i] * 0.6f : 0) + Mathf.Sin(TAU * 50f * t) * 0.02f + Mathf.Sin(TAU * 100f * t) * 0.01f; }
            am.Register("amb_city", Clip("amb_city", Loopable(cityL, SR), true, 0.5f));
            var rain = NoiseLoop(7f, 500f, 7000f, 402);
            seed = 403;
            for (int i = 0; i < rain.Length; i++) if (Noise() > 0.9993f) for (int k = 0; k < 200 && i + k < rain.Length; k++) rain[i + k] += Mathf.Sin(k * 0.6f) * Mathf.Exp(-k / 40f) * 0.8f;
            am.Register("amb_rain", Clip("amb_rain", rain, true, 0.5f));
            am.Register("amb_wind", Clip("amb_wind", NoiseLoop(7f, 80f, 700f, 404, 0.43f, 0.7f), true, 0.5f));
            var siren = new float[2 * SR]; float sp = 0;
            for (int i = 0; i < siren.Length; i++) { float t = i / (float)SR; float f = 750f + 350f * Mathf.Sin(TAU * 0.5f * t); sp += TAU * f / SR; siren[i] = Mathf.Sin(sp) * 0.6f + Mathf.Sin(sp * 2f) * 0.2f; }
            am.Register("siren", Clip("siren", Loopable(siren, SR / 8), true, 0.5f));
            var train = NoiseLoop(4.5f, 40f, 600f, 405);
            for (int b = 0; b < 8; b++) { int o = (int)(b * 0.5f * SR); var clack = Thud(0.1f, 200f, 0.02f, 1f, 2000f, 406 + b); for (int k = 0; k < clack.Length && o + k < train.Length; k++) train[o + k] += clack[k] * 0.6f; }
            am.Register("train", Clip("train", train, true, 0.6f));
            var drone = new float[2 * SR];
            for (int i = 0; i < drone.Length; i++) { float t = i / (float)SR; drone[i] = (((180f * t) % 1f) * 2f - 1f) * 0.4f + (((183f * t) % 1f) * 2f - 1f) * 0.4f + Mathf.Sin(TAU * 90f * t) * 0.2f; }
            am.Register("drone", Clip("drone", Loopable(drone, SR / 10), true, 0.4f));
            var thunder = Brown(6f, 220f, 407);
            for (int i = 0; i < thunder.Length; i++) { float t = i / (float)SR; thunder[i] *= 30f * Mathf.Exp(-t / 1.8f) * (1f + 0.5f * Mathf.Sin(TAU * 1.3f * t)); thunder[i] = (float)Math.Tanh(thunder[i]); }
            am.Register("thunder", Clip("thunder", thunder, true, 0.9f));
            am.Register("heartbeat", Clip("heartbeat", Mix(Thud(0.2f, 55f, 0.05f, 0.1f, 300f, 408), Thud(0.2f, 50f, 0.06f, 0.1f, 300f, 409), 0.7f, (int)(0.25f * SR)), true, 0.7f));
            am.Register("hurt", Clip("hurt", Mix(Thud(0.25f, 70f, 0.06f, 1.3f, 700f, 410), Whoosh(0.15f, 2000f, 600f, 411), 0.4f), true, 0.8f));
            am.Register("flatline", Clip("flatline", Tone(2.5f, 1000f, 1000f, 50f, 0, 0.01f), true, 0.3f));
            BuildBoxing(am);
        }

        // ------------------------------------------------------------------ boxing
        static float[] Bell(float len, float f0, int s)
        {
            seed = (uint)(s * 71 + 5);
            int n = (int)(len * SR); var d = new float[n];
            float[] ratio = { 1f, 2.76f, 5.4f, 8.93f, 13.3f };
            float[] decay = { 1.5f, 0.85f, 0.45f, 0.25f, 0.12f };
            float[] amp = { 1f, 0.6f, 0.35f, 0.2f, 0.12f };
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)SR;
                float v = 0f;
                for (int k = 0; k < ratio.Length; k++) v += Mathf.Sin(TAU * f0 * ratio[k] * t + k) * amp[k] * Mathf.Exp(-t / decay[k]);
                v += Noise() * Mathf.Exp(-t / 0.004f) * 0.8f;
                v *= 1f + 0.08f * Mathf.Sin(TAU * 5.5f * t);
                d[i] = v;
            }
            return d;
        }

        static float[] Crowd(float len, int s, float excitement)
        {
            seed = (uint)(s * 131 + 9);
            int n = (int)(len * SR); var d = new float[n];
            // many murmuring voices: band-passed noise with slow random swells + a low room rumble
            var band = NoiseLoop(len + 0.6f, 250f, 2600f, s + 1);
            var low = Brown(len + 0.6f, 500f, s + 2);
            float swell = 0f, target = 0f; int hold = 0;
            for (int i = 0; i < n; i++)
            {
                if (--hold <= 0) { hold = (int)(SR * (0.2f + (Noise() * 0.5f + 0.5f) * 0.9f)); target = (Noise() * 0.5f + 0.5f); }
                swell += (target - swell) * 0.0004f;
                float t = i / (float)SR;
                float voices = band[i % band.Length] * (0.55f + swell * 0.6f * excitement);
                float chatter = Mathf.Sin(TAU * (180f + 40f * Mathf.Sin(TAU * 0.3f * t)) * t) * 0.02f * (Noise() > 0.3f ? 1f : 0f);
                d[i] = voices + low[i % low.Length] * 5f + chatter;
            }
            return Loopable(d, SR / 2);
        }

        static void BuildBoxing(AudioManager am)
        {
            am.Register("glove_head", Clip("gh1", Mix(Thud(0.28f, 92f, 0.05f, 1.9f, 2600f, 501), Thud(0.06f, 700f, 0.007f, 2.8f, 7000f, 502), 0.7f), true, 0.95f));
            am.Register("glove_head", Clip("gh2", Mix(Thud(0.3f, 84f, 0.055f, 2.1f, 2200f, 511), Thud(0.06f, 820f, 0.006f, 3f, 7600f, 512), 0.65f), true, 0.95f));
            am.Register("glove_heavy", Clip("ghh", Mix(Mix(Thud(0.45f, 62f, 0.09f, 2.4f, 1800f, 513), Thud(0.08f, 900f, 0.008f, 3f, 8000f, 514), 0.8f), Whoosh(0.2f, 1800f, 300f, 515), 0.25f), true, 1f));
            am.Register("glove_body", Clip("gb1", Mix(Thud(0.34f, 58f, 0.075f, 1.3f, 950f, 503), Thud(0.05f, 400f, 0.01f, 2f, 4000f, 504), 0.45f), true, 0.95f));
            am.Register("glove_body", Clip("gb2", Mix(Thud(0.36f, 52f, 0.08f, 1.4f, 900f, 516), Thud(0.05f, 360f, 0.01f, 2f, 3600f, 517), 0.45f), true, 0.95f));
            am.Register("glove_block", Clip("gbl", Mix(Thud(0.16f, 190f, 0.028f, 1.5f, 2600f, 505), Thud(0.08f, 120f, 0.03f, 0.6f, 900f, 506), 0.5f), true, 0.7f));
            am.Register("whiff", Clip("wf1", Whoosh(0.22f, 380f, 2700f, 507, 0.25f), true, 0.5f));
            am.Register("whiff", Clip("wf2", Whoosh(0.26f, 300f, 2300f, 508, 0.22f), true, 0.5f));
            var bell = Bell(1.9f, 1180f, 520);
            am.Register("bell", Clip("bell", bell, true, 0.85f));
            var b3 = Mix(Mix(bell, bell, 1f, (int)(0.32f * SR)), bell, 1f, (int)(0.64f * SR));
            am.Register("bell3", Clip("bell3", b3, true, 0.85f));
            am.Register("crowd_loop", Clip("crowd_loop", Crowd(8f, 530, 0.6f), true, 0.5f));
            var cheer = Crowd(3.2f, 540, 1f);
            for (int i = 0; i < cheer.Length; i++) { float t = i / (float)SR; cheer[i] *= Mathf.Min(1f, t / 0.25f) * Mathf.Exp(-Mathf.Max(0f, t - 0.6f) / 1.1f) * 2.2f; }
            seed = 541;
            for (int w = 0; w < 4; w++) { int o = (int)((0.2f + (Noise() * 0.5f + 0.5f) * 1.2f) * SR); var wh = Tone(0.5f, 2400f + w * 300f, 2900f + w * 200f, 0.3f, 0, 0.05f); for (int k = 0; k < wh.Length && o + k < cheer.Length; k++) cheer[o + k] += wh[k] * 0.12f; }
            am.Register("crowd_cheer", Clip("crowd_cheer", cheer, true, 0.8f));
            var ooh = new float[(int)(1.3f * SR)];
            seed = 545;
            float lp1 = 0f;
            for (int i = 0; i < ooh.Length; i++)
            {
                float t = i / (float)SR;
                lp1 += Lp(700f) * (Noise() - lp1);
                float voice = 0f; for (int v = 0; v < 6; v++) voice += Mathf.Sin(TAU * (150f + v * 23f - t * 30f) * t + v) * 0.12f;
                ooh[i] = (lp1 * 3f + voice) * Mathf.Min(1f, t / 0.08f) * Mathf.Exp(-t / 0.6f);
            }
            am.Register("crowd_ooh", Clip("crowd_ooh", ooh, true, 0.75f));
            am.Register("canvas", Clip("canvas", Mix(Thud(0.6f, 44f, 0.13f, 2.2f, 750f, 509), Thud(0.2f, 140f, 0.04f, 1.5f, 1600f, 510), 0.6f, (int)(0.07f * SR)), true, 1f));
            am.Register("rope", Clip("rope", Mix(Tone(0.5f, 96f, 88f, 0.22f, 2), Thud(0.12f, 160f, 0.03f, 0.8f, 1500f, 518), 0.6f), true, 0.6f));
            am.Register("count", Clip("count", Mix(Tone(0.09f, 880f, 860f, 0.05f, 1), Thud(0.08f, 300f, 0.02f, 0.5f, 3000f, 519), 0.4f), true, 0.45f));
            am.Register("tinnitus", Clip("tinnitus", Tone(2.6f, 4300f, 4150f, 1.3f, 0, 0.25f), true, 0.22f));
            am.Register("breath", Clip("breath", Mix(Whoosh(0.35f, 500f, 1400f, 520, 0.6f), Whoosh(0.4f, 1300f, 400f, 521, 0.6f), 0.8f, (int)(0.4f * SR)), true, 0.35f));
        }
    }
}
