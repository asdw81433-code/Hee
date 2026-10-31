using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public struct LightAnchor
    {
        public Vector3 pos;
        public Color color;
        public float range, intensity;
        public bool flicker;
        public bool nightOnly;
    }

    public class Chunk
    {
        public int cx, cz;
        public Vector3 center;
        public GameObject root, staticGo, detailGo, collidersGo;
        public readonly MeshBuilder staticMB = new MeshBuilder();
        public readonly MeshBuilder detailMB = new MeshBuilder();
        public readonly List<LightAnchor> lights = new List<LightAnchor>();
        public readonly List<GameObject> detailObjects = new List<GameObject>();
        public bool detailVisible = true;

        public void AddCollider(Vector3 min, Vector3 max)
        {
            var c = collidersGo.AddComponent<BoxCollider>();
            c.center = (min + max) * 0.5f - collidersGo.transform.position;
            c.size = new Vector3(Mathf.Abs(max.x - min.x), Mathf.Abs(max.y - min.y), Mathf.Abs(max.z - min.z));
        }

        public void AddRotatedCollider(Vector3 center, Vector3 size, Quaternion rot)
        {
            var go = new GameObject("col");
            go.transform.SetParent(collidersGo.transform, false);
            go.transform.position = center;
            go.transform.rotation = rot;
            var c = go.AddComponent<BoxCollider>();
            c.size = size;
        }
    }

    /// <summary>
    /// Shows prop/detail meshes only near the camera and drives a small pool of real point lights
    /// that follow the nearest light anchors (neon signs, street lamps, fires).
    /// </summary>
    public class ChunkStreamer : MonoBehaviour
    {
        public const float ChunkSize = 200f;
        public static float Origin => -CityData.WallMargin - 30f;
        public int count;
        public Chunk[,] chunks;
        public float detailDistance = 380f;
        public int poolSize = 28;

        readonly List<Light> pool = new List<Light>();
        readonly List<LightAnchor> candidates = new List<LightAnchor>(512);
        readonly List<float> candidateDist = new List<float>(512);
        readonly int[] assigned = new int[64];
        float timer;
        public float nightFactor = 1f; // set by environment

        public void Init(Chunk[,] chunks, int count)
        {
            this.chunks = chunks;
            this.count = count;
            for (int i = 0; i < poolSize; i++)
            {
                var go = new GameObject("PoolLight" + i);
                go.transform.SetParent(transform, false);
                var l = go.AddComponent<Light>();
                l.type = LightType.Point;
                l.shadows = LightShadows.None;
                l.renderMode = LightRenderMode.ForcePixel;
                l.enabled = false;
                pool.Add(l);
            }
        }

        public static Vector2Int ChunkIndex(Vector3 p)
        {
            return new Vector2Int(Mathf.FloorToInt((p.x - Origin) / ChunkSize), Mathf.FloorToInt((p.z - Origin) / ChunkSize));
        }

        public Chunk ChunkAt(Vector3 p)
        {
            if (chunks == null) return null;
            var i = ChunkIndex(p);
            if (i.x < 0 || i.y < 0 || i.x >= count || i.y >= count) return null;
            return chunks[i.x, i.y];
        }

        void Update()
        {
            if (chunks == null) return;
            var cam = Game.Cam;
            if (cam == null) return;
            var p = cam.transform.position;

            timer -= Time.unscaledDeltaTime;
            if (timer <= 0f)
            {
                timer = 0.3f;
                float d2 = detailDistance * detailDistance;
                for (int x = 0; x < count; x++)
                    for (int z = 0; z < count; z++)
                    {
                        var c = chunks[x, z];
                        if (c == null || c.detailGo == null) continue;
                        bool vis = (c.center - p).Flat().sqrMagnitude < d2;
                        if (vis != c.detailVisible)
                        {
                            c.detailVisible = vis;
                            c.detailGo.SetActive(vis);
                        }
                    }
                AssignLights(p);
            }
            // flicker
            float t = Time.time;
            for (int i = 0; i < pool.Count; i++)
            {
                var l = pool[i];
                if (!l.enabled) continue;
                int idx = assigned[i];
                if (idx < 0 || idx >= candidates.Count) continue;
                var a = candidates[idx];
                float k = a.nightOnly ? nightFactor : 1f;
                if (a.flicker)
                {
                    float n = Mathf.PerlinNoise(t * 9f, a.pos.x * 0.37f);
                    k *= n > 0.25f ? 1f : 0.15f;
                }
                l.intensity = a.intensity * k;
            }
        }

        void AssignLights(Vector3 p)
        {
            candidates.Clear();
            candidateDist.Clear();
            var ci = ChunkIndex(p);
            for (int x = ci.x - 1; x <= ci.x + 1; x++)
                for (int z = ci.y - 1; z <= ci.y + 1; z++)
                {
                    if (x < 0 || z < 0 || x >= count || z >= count) continue;
                    var c = chunks[x, z];
                    if (c == null) continue;
                    foreach (var a in c.lights)
                    {
                        float d = (a.pos - p).sqrMagnitude;
                        if (d > 160f * 160f) continue;
                        candidates.Add(a);
                        candidateDist.Add(d / (a.range * a.range));
                    }
                }
            // pick nearest N (partial selection)
            int n = Mathf.Min(pool.Count, candidates.Count);
            var used = new bool[candidates.Count];
            for (int i = 0; i < pool.Count; i++)
            {
                if (i >= n) { pool[i].enabled = false; assigned[i] = -1; continue; }
                int best = -1; float bd = float.MaxValue;
                for (int j = 0; j < candidates.Count; j++)
                {
                    if (used[j]) continue;
                    if (candidateDist[j] < bd) { bd = candidateDist[j]; best = j; }
                }
                used[best] = true;
                assigned[i] = best;
                var a = candidates[best];
                var l = pool[i];
                l.transform.position = a.pos;
                l.color = a.color;
                l.range = a.range;
                l.intensity = a.intensity;
                l.enabled = !(a.nightOnly && nightFactor < 0.05f);
            }
        }
    }
}
