using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;

namespace NeonBay
{
    /// <summary>
    /// Builds a NavMesh around the player at runtime (asynchronously) so AI can path through
    /// a city that only exists after procedural generation.
    /// </summary>
    public class NavMeshStreamer : MonoBehaviour
    {
        public Vector3 size = new Vector3(240f, 120f, 240f);
        public float rebuildDistance = 45f;
        NavMeshData data;
        NavMeshDataInstance instance;
        AsyncOperation op;
        Vector3 lastCenter = new Vector3(float.MaxValue, 0, 0);
        readonly List<NavMeshBuildSource> sources = new List<NavMeshBuildSource>();
        readonly List<NavMeshBuildMarkup> markups = new List<NavMeshBuildMarkup>();
        public bool Ready { get; private set; }
        public static NavMeshStreamer Instance;

        void Awake()
        {
            Instance = this;
            data = new NavMeshData();
            instance = NavMesh.AddNavMeshData(data);
        }

        void OnDestroy()
        {
            instance.Remove();
        }

        void Update()
        {
            if (!Game.HasPlayer) return;
            if (op != null && !op.isDone) return;
            if (op != null && op.isDone) { op = null; Ready = true; }
            var p = Game.PlayerPos;
            var center = Quantize(p);
            if ((center - lastCenter).sqrMagnitude < rebuildDistance * rebuildDistance && Mathf.Abs(p.y - lastCenter.y) < 30f) return;
            Rebuild(center);
        }

        public void ForceRebuild()
        {
            lastCenter = new Vector3(float.MaxValue, 0, 0);
        }

        Vector3 Quantize(Vector3 p)
        {
            float q = 15f;
            return new Vector3(Mathf.Round(p.x / q) * q, Mathf.Round(p.y / q) * q, Mathf.Round(p.z / q) * q);
        }

        void Rebuild(Vector3 center)
        {
            lastCenter = center;
            var bounds = new Bounds(center, size);
            sources.Clear();
            NavMeshBuilder.CollectSources(bounds, Layers.WorldMask, NavMeshCollectGeometry.PhysicsColliders, 0, markups, sources);
            var settings = NavMesh.GetSettingsByID(0);
            settings.agentRadius = 0.4f;
            settings.agentHeight = 1.8f;
            settings.agentClimb = 0.45f;
            settings.agentSlope = 40f;
            settings.overrideVoxelSize = true;
            settings.voxelSize = 0.2f;
            op = NavMeshBuilder.UpdateNavMeshDataAsync(data, settings, sources, new Bounds(Vector3.zero, size) { center = center });
        }
    }
}
