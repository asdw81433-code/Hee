using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// A real-time generative synth (runs on the audio thread). Provides the adaptive score
    /// (calm exploration <-> combat) and several in-car radio stations.
    /// </summary>
    [RequireComponent(typeof(AudioSource))]
    public class MusicSystem : MonoBehaviour
    {
        public static readonly string[] StationNames = { "Score", "NEON FM 89.0 (synthwave)", "RUST RADIO (industrial)", "LOTUS LOUNGE (chill)", "BAYOU BASS (phonk)" };

        struct Style
        {
            public float bpm;
            public int root;          // MIDI note
            public int[] progression; // scale degrees for each bar
            public float swing;
            public float bassCut, padLevel, arpLevel, leadLevel, drive;
            public int kickPattern, hatDensity;
        }

        static readonly int[] Minor = { 0, 2, 3, 5, 7, 8, 10 };

        static readonly Style[] styles =
        {
            new Style { bpm = 92, root = 45, progression = new[] { 0, 5, 2, 6 }, swing = 0f, bassCut = 600, padLevel = 0.35f, arpLevel = 0.18f, leadLevel = 0f, drive = 1.2f, kickPattern = 0, hatDensity = 2 },
            new Style { bpm = 104, root = 45, progression = new[] { 0, 5, 3, 6 }, swing = 0f, bassCut = 1200, padLevel = 0.3f, arpLevel = 0.25f, leadLevel = 0.18f, drive = 1.4f, kickPattern = 1, hatDensity = 2 },
            new Style { bpm = 128, root = 40, progression = new[] { 0, 0, 5, 6 }, swing = 0f, bassCut = 2000, padLevel = 0.12f, arpLevel = 0.2f, leadLevel = 0.1f, drive = 3f, kickPattern = 1, hatDensity = 4 },
            new Style { bpm = 80, root = 50, progression = new[] { 0, 3, 5, 4 }, swing = 0.18f, bassCut = 500, padLevel = 0.4f, arpLevel = 0.15f, leadLevel = 0.12f, drive = 1f, kickPattern = 2, hatDensity = 2 },
            new Style { bpm = 140, root = 43, progression = new[] { 0, 5, 6, 4 }, swing = 0.1f, bassCut = 300, padLevel = 0.15f, arpLevel = 0.2f, leadLevel = 0.15f, drive = 2.4f, kickPattern = 3, hatDensity = 4 },
        };

        // main thread -> audio thread
        public volatile int station;
        public float intensityTarget;
        public float volume = 0.5f;
        volatile float intensity;
        volatile float vol;
        volatile bool muted = true;

        double sampleRate = 48000;
        double time;
        int lastStep = -1;
        float bassPh, bassEnv, bassLp, bassFreq;
        readonly float[] padPh = new float[6];
        float padLp;
        float arpPh, arpEnv, arpFreq;
        float leadPh, leadEnv, leadFreq;
        float kickPh, kickEnv, snareEnv, hatEnv, hatLp;
        float[] delay;
        int delayPos;
        uint rnd = 7777;
        float currentStationMix = 1f;
        int playingStation;

        float Rand() { rnd ^= rnd << 13; rnd ^= rnd >> 17; rnd ^= rnd << 5; return (rnd & 0xFFFFFF) / 8388607.5f - 1f; }
        static float Mtof(float m) => 440f * Mathf.Pow(2f, (m - 69f) / 12f);

        void Awake()
        {
            Game.Music = this;
            sampleRate = AudioSettings.outputSampleRate;
            delay = new float[(int)sampleRate];
            var src = GetComponent<AudioSource>();
            // a silent looping clip keeps the source (and therefore OnAudioFilterRead) running
            var silent = AudioClip.Create("silence", 1024, 1, (int)sampleRate, false);
            src.clip = silent;
            src.loop = true;
            src.spatialBlend = 0f;
            src.playOnAwake = false;
            src.volume = 1f;
            src.Play();
        }

        void Update()
        {
            float target = Mathf.Clamp01(intensityTarget);
            intensity = Mathf.MoveTowards(intensity, target, Time.unscaledDeltaTime * (target > intensity ? 0.6f : 0.12f));
            float mv = Game.Settings != null ? Game.Settings.musicVolume : 0.5f;
            vol = Mathf.MoveTowards(vol, mv * volume, Time.unscaledDeltaTime * 0.5f);
            muted = vol < 0.001f;
        }

        public void SetStation(int s) { station = Mathf.Clamp(s, 0, styles.Length - 1); }

        void OnAudioFilterRead(float[] data, int channels)
        {
            if (muted) { System.Array.Clear(data, 0, data.Length); return; }
            int want = station;
            float inten = intensity;
            float v = vol;
            double dt = 1.0 / sampleRate;
            for (int i = 0; i < data.Length; i += channels)
            {
                // crossfade between stations through silence
                if (want != playingStation)
                {
                    currentStationMix -= (float)dt * 2f;
                    if (currentStationMix <= 0f) { playingStation = want; currentStationMix = 0f; time = 0; lastStep = -1; }
                }
                else if (currentStationMix < 1f) currentStationMix += (float)dt * 1.5f;

                var st = styles[playingStation];
                double beat = time * st.bpm / 60.0;
                int step = (int)(beat * 4.0);
                double stepFrac = beat * 4.0 - step;
                if (st.swing > 0 && (step & 1) == 1 && stepFrac < st.swing) step -= 1;
                if (step != lastStep) Trigger(st, step, inten);
                lastStep = step;

                float s = Render(st, inten, (float)dt);
                s *= v * currentStationMix;
                float l = s, r = s;
                // arp delay (stereo widened)
                float dly = delay[delayPos];
                l += dly * 0.35f; r += dly * 0.25f;
                for (int c = 0; c < channels; c++) data[i + c] = c == 0 ? l : c == 1 ? r : s;
                time += dt;
            }
        }

        int bar, chordRoot;
        float[] chord = new float[3];

        void Trigger(Style st, int step, float inten)
        {
            int inBar = step & 15;
            bar = (step >> 4) % st.progression.Length;
            int degree = st.progression[bar];
            chordRoot = st.root + Minor[degree % 7];
            chord[0] = chordRoot + 12; chord[1] = st.root + Minor[(degree + 2) % 7] + 12 + ((degree + 2) >= 7 ? 12 : 0); chord[2] = st.root + Minor[(degree + 4) % 7] + 12 + ((degree + 4) >= 7 ? 12 : 0);

            bool driving = inten > 0.45f || playingStation != 0;
            // bass
            bool bassHit = driving ? (inBar % 2 == 0) : (inBar % 8 == 0);
            if (bassHit)
            {
                bassFreq = Mtof(chordRoot + ((inBar % 8 == 6 && driving) ? 12 : 0));
                bassEnv = 1f;
            }
            // arp
            if (inBar % (driving ? 1 : 2) == 0)
            {
                int idx = (inBar / (driving ? 1 : 2)) % 4;
                int n = idx == 3 ? 1 : idx;
                arpFreq = Mtof(chord[n] + 12);
                arpEnv = 1f;
            }
            // lead melody (radio)
            if (st.leadLevel > 0 && inBar % 4 == 0 && Rand() > -0.2f)
            {
                int deg = (int)((Rand() * 0.5f + 0.5f) * 7);
                leadFreq = Mtof(st.root + 24 + Minor[deg % 7]);
                leadEnv = 1f;
            }
            // drums
            float drums = playingStation != 0 ? 1f : Mathf.Clamp01((inten - 0.25f) * 2f);
            if (drums > 0.05f)
            {
                bool kick = st.kickPattern switch
                {
                    0 => inBar == 0 || inBar == 8 || (inten > 0.7f && (inBar == 4 || inBar == 12)),
                    1 => inBar % 4 == 0,
                    2 => inBar == 0 || inBar == 7 || inBar == 10,
                    _ => inBar == 0 || inBar == 3 || inBar == 6 || inBar == 10 || inBar == 11
                };
                if (kick) { kickEnv = drums; kickPh = 0; }
                if (inBar == 4 || inBar == 12) snareEnv = drums * 0.8f;
                if (inBar % (st.hatDensity >= 4 ? 1 : 2) == 0) hatEnv = drums * (inBar % 4 == 2 ? 0.6f : 0.35f);
            }
        }

        float Render(Style st, float inten, float dt)
        {
            float sr = (float)sampleRate;
            float outS = 0;
            // bass: saw through a one-pole low pass
            bassPh += bassFreq / sr; if (bassPh > 1f) bassPh -= 1f;
            float saw = bassPh * 2f - 1f;
            float cut = st.bassCut * (0.6f + inten * 0.9f);
            float a = 1f - Mathf.Exp(-2f * Mathf.PI * cut / sr);
            bassLp += a * (saw - bassLp);
            bassEnv *= 1f - dt * 4f;
            outS += bassLp * bassEnv * 0.55f;

            // pad: two detuned saws per chord tone
            float pad = 0;
            for (int k = 0; k < 6; k++)
            {
                float f = Mtof(chord[k % 3] + (k >= 3 ? 0.08f : -0.08f));
                padPh[k] += f / sr; if (padPh[k] > 1f) padPh[k] -= 1f;
                pad += padPh[k] * 2f - 1f;
            }
            float pa = 1f - Mathf.Exp(-2f * Mathf.PI * (500f + inten * 900f) / sr);
            padLp += pa * (pad / 6f - padLp);
            outS += padLp * st.padLevel;

            // arp: pulse wave with short envelope, fed into the delay line
            arpPh += arpFreq / sr; if (arpPh > 1f) arpPh -= 1f;
            arpEnv *= 1f - dt * 9f;
            float arp = (arpPh < 0.35f ? 1f : -1f) * arpEnv * st.arpLevel * (0.5f + inten * 0.5f);
            outS += arp;
            int dlen = (int)(sr * 60f / st.bpm * 0.75f);
            if (dlen >= delay.Length) dlen = delay.Length - 1;
            int readPos = (delayPos - dlen + delay.Length) % delay.Length;
            delay[delayPos] = arp * 0.6f + delay[readPos] * 0.45f;
            delayPos = (delayPos + 1) % delay.Length;

            // lead: soft square
            leadPh += leadFreq / sr; if (leadPh > 1f) leadPh -= 1f;
            leadEnv *= 1f - dt * 2.5f;
            outS += Mathf.Sin(leadPh * Mathf.PI * 2f) * 0.6f * leadEnv * st.leadLevel + (leadPh < 0.5f ? 0.2f : -0.2f) * leadEnv * st.leadLevel;

            // kick
            kickEnv *= 1f - dt * 7f;
            float kf = 45f + 110f * kickEnv * kickEnv;
            kickPh += kf / sr;
            outS += Mathf.Sin(kickPh * Mathf.PI * 2f) * kickEnv * 0.9f;
            // snare
            snareEnv *= 1f - dt * 14f;
            outS += (Rand() * 0.7f + Mathf.Sin((float)time * 1130f) * 0.3f) * snareEnv * 0.35f;
            // hat (high-passed noise)
            hatEnv *= 1f - dt * 40f;
            float hn = Rand();
            hatLp += 0.3f * (hn - hatLp);
            outS += (hn - hatLp) * hatEnv * 0.25f;

            // gentle saturation
            float drive = st.drive * (0.8f + inten * 0.4f);
            return (float)System.Math.Tanh(outS * drive) * 0.5f;
        }
    }
}
