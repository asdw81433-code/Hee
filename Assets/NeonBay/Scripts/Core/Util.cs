using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Deterministic xorshift RNG so the city is identical on every machine and every load.</summary>
    public class Rng
    {
        uint state;

        public Rng(int seed)
        {
            state = (uint)seed * 2654435761u + 0x9E3779B9u;
            if (state == 0) state = 0xA341316Cu;
            for (int i = 0; i < 4; i++) Next();
        }

        public uint Next()
        {
            uint x = state;
            x ^= x << 13; x ^= x >> 17; x ^= x << 5;
            state = x;
            return x;
        }

        public float Value => (Next() & 0xFFFFFF) / 16777216f;
        public float Range(float min, float max) => min + (max - min) * Value;
        public int Range(int min, int maxExclusive) => maxExclusive <= min ? min : min + (int)(Next() % (uint)(maxExclusive - min));
        public bool Chance(float p) => Value < p;
        public T Pick<T>(IList<T> list) => list[Range(0, list.Count)];
        public T Pick<T>(params T[] items) => items[Range(0, items.Length)];
        public Vector2 InsideCircle() { float a = Range(0f, Mathf.PI * 2f), r = Mathf.Sqrt(Value); return new Vector2(Mathf.Cos(a) * r, Mathf.Sin(a) * r); }
        public Color ColorFrom(IList<Color> palette) => palette[Range(0, palette.Count)];
        public int WeightedIndex(IList<float> weights)
        {
            float total = 0; foreach (var w in weights) total += w;
            float r = Range(0f, total);
            for (int i = 0; i < weights.Count; i++) { r -= weights[i]; if (r <= 0) return i; }
            return weights.Count - 1;
        }
    }

    public static class Palette
    {
        public static readonly Color Cyan = new Color(0.1f, 0.95f, 1f);
        public static readonly Color Magenta = new Color(1f, 0.15f, 0.75f);
        public static readonly Color Yellow = new Color(1f, 0.85f, 0.15f);
        public static readonly Color Orange = new Color(1f, 0.45f, 0.08f);
        public static readonly Color Red = new Color(1f, 0.12f, 0.15f);
        public static readonly Color Green = new Color(0.25f, 1f, 0.45f);
        public static readonly Color Purple = new Color(0.55f, 0.2f, 1f);
        public static readonly Color Blue = new Color(0.15f, 0.45f, 1f);
        public static readonly Color White = new Color(0.95f, 0.97f, 1f);
        public static readonly Color Sodium = new Color(1f, 0.62f, 0.25f);

        public static readonly Color[] Neon = { Cyan, Magenta, Yellow, Orange, Red, Green, Purple, Blue };
        public static readonly Color[] MarketNeon = { Magenta, Red, Yellow, Orange, Cyan, Green };
        public static readonly Color[] SpireNeon = { Cyan, Blue, White, Purple };
        public static readonly Color[] SlumNeon = { Orange, Yellow, Green, Red, Magenta };

        public static readonly Color[] SkinTones =
        {
            new Color(0.96f, 0.80f, 0.69f), new Color(0.90f, 0.72f, 0.56f), new Color(0.80f, 0.60f, 0.43f),
            new Color(0.67f, 0.47f, 0.32f), new Color(0.52f, 0.35f, 0.23f), new Color(0.36f, 0.24f, 0.16f),
            new Color(0.25f, 0.17f, 0.12f), new Color(0.70f, 0.75f, 0.80f) // last one: full-chrome synth skin
        };

        public static readonly Color[] HairColors =
        {
            new Color(0.05f, 0.04f, 0.04f), new Color(0.25f, 0.15f, 0.08f), new Color(0.65f, 0.5f, 0.3f),
            new Color(0.9f, 0.9f, 0.92f), Magenta, Cyan, new Color(0.9f, 0.2f, 0.2f), Green, Purple
        };

        public static Color WithAlpha(this Color c, float a) { c.a = a; return c; }
        public static Color Scale(this Color c, float k) => new Color(c.r * k, c.g * k, c.b * k, c.a);
    }

    public static class Util
    {
        public static GameObject Make(string name, Transform parent = null, Vector3? localPos = null)
        {
            var go = new GameObject(name);
            if (parent != null) go.transform.SetParent(parent, false);
            if (localPos.HasValue) go.transform.localPosition = localPos.Value;
            return go;
        }

        public static GameObject Primitive(PrimitiveType type, string name, Transform parent, Vector3 localPos, Vector3 scale, Material mat, bool keepCollider = false)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            if (parent != null) go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            go.transform.localScale = scale;
            if (!keepCollider)
            {
                var col = go.GetComponent<Collider>();
                if (col != null) UnityEngine.Object.Destroy(col);
            }
            var r = go.GetComponent<MeshRenderer>();
            if (mat != null) r.sharedMaterial = mat;
            return go;
        }

        public static void SetLayerRecursive(GameObject go, int layer)
        {
            go.layer = layer;
            foreach (Transform t in go.transform) SetLayerRecursive(t.gameObject, layer);
        }

        public static float Damp(float current, float target, float lambda, float dt) => Mathf.Lerp(current, target, 1f - Mathf.Exp(-lambda * dt));
        public static Vector3 Damp(Vector3 current, Vector3 target, float lambda, float dt) => Vector3.Lerp(current, target, 1f - Mathf.Exp(-lambda * dt));

        public static Vector3 Flat(this Vector3 v) => new Vector3(v.x, 0f, v.z);

        public static string Credits(int amount) => "$" + amount.ToString("N0");

        public static string TimeString(float hours)
        {
            int h = Mathf.FloorToInt(hours) % 24;
            int m = Mathf.FloorToInt((hours - Mathf.Floor(hours)) * 60f);
            return h.ToString("00") + ":" + m.ToString("00");
        }

        public static T GetOrAdd<T>(this GameObject go) where T : Component
        {
            var c = go.GetComponent<T>();
            return c != null ? c : go.AddComponent<T>();
        }

        public static bool LineOfSight(Vector3 from, Vector3 to, Transform ignoreRoot = null)
        {
            var dir = to - from;
            float dist = dir.magnitude;
            if (dist < 0.01f) return true;
            return !Physics.Raycast(from, dir / dist, dist - 0.2f, Layers.SightMask, QueryTriggerInteraction.Ignore);
        }

        public static void SafeDestroy(UnityEngine.Object o)
        {
            if (o == null) return;
            if (Application.isPlaying) UnityEngine.Object.Destroy(o); else UnityEngine.Object.DestroyImmediate(o);
        }

        public static void Shuffle<T>(IList<T> list, Rng rng)
        {
            for (int i = list.Count - 1; i > 0; i--)
            {
                int j = rng.Range(0, i + 1);
                (list[i], list[j]) = (list[j], list[i]);
            }
        }

        public static Font LoadBuiltinFont()
        {
            Font f = null;
#if UNITY_2022_2_OR_NEWER
            try { f = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"); } catch (Exception) { }
#else
            try { f = Resources.GetBuiltinResource<Font>("Arial.ttf"); } catch (Exception) { }
#endif
            return f;
        }

        public static void SetVelocity(Rigidbody rb, Vector3 v)
        {
#if UNITY_6000_0_OR_NEWER
            rb.linearVelocity = v;
#else
            rb.velocity = v;
#endif
        }

        public static Vector3 GetVelocity(Rigidbody rb)
        {
#if UNITY_6000_0_OR_NEWER
            return rb.linearVelocity;
#else
            return rb.velocity;
#endif
        }

        public static void SetDrag(Rigidbody rb, float linear, float angular)
        {
#if UNITY_6000_0_OR_NEWER
            rb.linearDamping = linear;
            rb.angularDamping = angular;
#else
            rb.drag = linear;
            rb.angularDrag = angular;
#endif
        }

        public static T FindAny<T>() where T : UnityEngine.Object
        {
            return UnityEngine.Object.FindFirstObjectByType<T>();
        }

        public static T[] FindAll<T>() where T : UnityEngine.Object
        {
            return UnityEngine.Object.FindObjectsByType<T>(FindObjectsSortMode.None);
        }
    }

    /// <summary>Simple pool of GameObjects created by a factory function.</summary>
    public class GoPool
    {
        readonly Func<GameObject> factory;
        readonly List<GameObject> items = new List<GameObject>();
        int cursor;
        readonly int max;

        public GoPool(Func<GameObject> factory, int max) { this.factory = factory; this.max = max; }

        public GameObject Get()
        {
            for (int i = 0; i < items.Count; i++)
            {
                var go = items[(cursor + i) % items.Count];
                if (go != null && !go.activeSelf) { cursor = (cursor + i + 1) % items.Count; go.SetActive(true); return go; }
            }
            if (items.Count < max)
            {
                var go = factory();
                items.Add(go);
                go.SetActive(true);
                return go;
            }
            // recycle the oldest
            var r = items[cursor];
            cursor = (cursor + 1) % items.Count;
            r.SetActive(false);
            r.SetActive(true);
            return r;
        }
    }
}
