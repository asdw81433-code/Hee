using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public class AudioManager : MonoBehaviour
    {
        readonly Dictionary<string, List<AudioClip>> clips = new Dictionary<string, List<AudioClip>>();
        readonly List<AudioSource> pool3D = new List<AudioSource>();
        readonly List<AudioSource> pool2D = new List<AudioSource>();
        readonly List<AudioSource> loops = new List<AudioSource>();
        int next3D, next2D;
        public float SfxVolume => Game.Settings != null ? Game.Settings.sfxVolume : 1f;

        public void Init()
        {
            Game.Audio = this;
            Synth.BuildAll(this);
            for (int i = 0; i < 40; i++) pool3D.Add(MakeSource("3D_" + i, true));
            for (int i = 0; i < 14; i++) pool2D.Add(MakeSource("2D_" + i, false));
        }

        AudioSource MakeSource(string name, bool spatial)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var s = go.AddComponent<AudioSource>();
            s.playOnAwake = false;
            s.spatialBlend = spatial ? 1f : 0f;
            s.rolloffMode = AudioRolloffMode.Logarithmic;
            s.dopplerLevel = 0f;
            s.minDistance = 2f;
            s.maxDistance = 120f;
            return s;
        }

        public void Register(string name, AudioClip clip)
        {
            if (!clips.TryGetValue(name, out var l)) { l = new List<AudioClip>(); clips[name] = l; }
            l.Add(clip);
        }

        public AudioClip Clip(string name)
        {
            if (name == null || !clips.TryGetValue(name, out var l) || l.Count == 0) return null;
            return l[Random.Range(0, l.Count)];
        }

        public AudioSource Play2D(string name, float volume = 1f, float pitch = 1f)
        {
            var c = Clip(name);
            if (c == null) return null;
            var s = pool2D[next2D];
            next2D = (next2D + 1) % pool2D.Count;
            s.clip = c;
            s.volume = volume * SfxVolume;
            s.pitch = pitch * (Time.timeScale < 0.9f && Time.timeScale > 0.01f ? Mathf.Lerp(0.7f, 1f, Time.timeScale) : 1f);
            s.loop = false;
            s.Play();
            return s;
        }

        public AudioSource Play3D(string name, Vector3 pos, float volume = 1f, float pitch = 1f, float minDist = 2f, float maxDist = 120f)
        {
            var c = Clip(name);
            if (c == null) return null;
            var cam = Game.Cam;
            if (cam != null && (cam.transform.position - pos).sqrMagnitude > maxDist * maxDist * 1.2f) return null;
            // pick a free source, otherwise steal the oldest
            AudioSource s = null;
            for (int i = 0; i < pool3D.Count; i++)
            {
                var cand = pool3D[(next3D + i) % pool3D.Count];
                if (!cand.isPlaying) { s = cand; next3D = (next3D + i + 1) % pool3D.Count; break; }
            }
            if (s == null) { s = pool3D[next3D]; next3D = (next3D + 1) % pool3D.Count; }
            s.transform.position = pos;
            s.clip = c;
            s.volume = volume * SfxVolume;
            s.pitch = pitch * (Time.timeScale < 0.9f && Time.timeScale > 0.01f ? Mathf.Lerp(0.6f, 1f, Time.timeScale) : 1f);
            s.minDistance = minDist;
            s.maxDistance = maxDist;
            s.loop = false;
            s.Play();
            return s;
        }

        /// <summary>Plays a 3D sound with a slight random pitch, typical for repeated effects.</summary>
        public AudioSource PlayVar(string name, Vector3 pos, float volume = 1f, float maxDist = 120f)
            => Play3D(name, pos, volume, Random.Range(0.92f, 1.08f), 2f, maxDist);

        public AudioSource Loop2D(string name, float volume)
        {
            var s = MakeSource("Loop_" + name, false);
            s.clip = Clip(name);
            s.loop = true;
            s.volume = volume;
            if (s.clip != null) s.Play();
            loops.Add(s);
            return s;
        }

        public AudioSource AttachLoop(GameObject go, string name, float volume, float minDist, float maxDist)
        {
            var s = go.AddComponent<AudioSource>();
            s.clip = Clip(name);
            s.loop = true;
            s.spatialBlend = 1f;
            s.volume = volume * SfxVolume;
            s.minDistance = minDist;
            s.maxDistance = maxDist;
            s.rolloffMode = AudioRolloffMode.Logarithmic;
            s.dopplerLevel = 0f;
            s.playOnAwake = false;
            if (s.clip != null) { s.time = Random.Range(0f, s.clip.length * 0.9f); s.Play(); }
            return s;
        }

        /// <summary>Pause or resume every pooled sound (used by the pause menu).</summary>
        public void PauseAll(bool paused)
        {
            foreach (var s in pool3D) { if (paused) s.Pause(); else s.UnPause(); }
        }
    }
}
