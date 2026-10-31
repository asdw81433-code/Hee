using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Keeps the streets alive: pedestrians on sidewalks and vendors/fixers at their stalls near the player.</summary>
    public class CrowdSystem : MonoBehaviour
    {
        public int baseTarget = 34;
        readonly List<NPC> civilians = new List<NPC>();
        readonly Dictionary<VendorSpot, NPC> vendorNpcs = new Dictionary<VendorSpot, NPC>();
        List<VendorSpot> spots;
        float timer;
        public bool paused;

        public void Init(List<VendorSpot> vendorSpots)
        {
            spots = vendorSpots;
            Game.Crowd = this;
        }

        static float Density(District d) => d switch
        {
            District.NeonStrip => 1.4f,
            District.Spire => 1f,
            District.Lowtown => 1.1f,
            District.Docks => 0.35f,
            _ => 0.12f
        };

        void Update()
        {
            if (!Game.HasPlayer || Game.City == null || paused) return;
            timer -= Time.deltaTime;
            if (timer > 0f) return;
            timer = 0.4f;
            var p = Game.PlayerPos;
            bool inside = p.y < -20f;

            civilians.RemoveAll(c => c == null || c.state == NPCState.Dead);
            for (int i = civilians.Count - 1; i >= 0; i--)
                if ((civilians[i].transform.position - p).Flat().sqrMagnitude > 150f * 150f) { Destroy(civilians[i].gameObject); civilians.RemoveAt(i); }

            float dens = Density(Game.City.DistrictAt(p));
            float night = Game.Env != null ? Game.Env.NightFactor : 0.5f;
            int target = inside ? 0 : Mathf.RoundToInt(baseTarget * dens * Mathf.Lerp(1f, 0.8f, night) * (Game.Police != null && Game.Police.Heat >= 3 ? 0.5f : 1f));
            for (int k = 0; k < 2 && civilians.Count < target; k++) SpawnCivilian(p);

            // vendors and fixers
            if (spots != null)
            {
                foreach (var s in spots)
                {
                    vendorNpcs.TryGetValue(s, out var npc);
                    float d2 = (s.pos - p).sqrMagnitude;
                    if (npc == null && d2 < 110f * 110f && !inside)
                    {
                        vendorNpcs[s] = Spawner.Vendor(s);
                    }
                    else if (npc != null && d2 > 160f * 160f)
                    {
                        if (!string.IsNullOrEmpty(s.npcId)) Spawner.Remove(s.npcId);
                        else Destroy(npc.gameObject);
                        vendorNpcs.Remove(s);
                    }
                }
            }
        }

        void SpawnCivilian(Vector3 p)
        {
            var cam = Game.Cam;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                int bx = Mathf.Clamp(Mathf.FloorToInt(p.x / CityData.Cell) + Random.Range(-1, 2), 0, CityData.Grid - 1);
                int bz = Mathf.Clamp(Mathf.FloorToInt(p.z / CityData.Cell) + Random.Range(-1, 2), 0, CityData.Grid - 1);
                var b = Game.City.blocks[bx, bz];
                if (Random.value > Density(b.district) / 1.4f) continue;
                if (!string.IsNullOrEmpty(b.special) && b.special.StartsWith("relay")) continue;
                float t = Random.value;
                var pos = Game.City.SidewalkPoint(bx, bz, t);
                float d = (pos - p).Flat().magnitude;
                if (d < 30f || d > 130f) continue;
                if (cam != null)
                {
                    var vp = cam.WorldToViewportPoint(pos + Vector3.up);
                    if (vp.z > 0 && vp.z < 60f && vp.x > 0 && vp.x < 1 && vp.y > 0 && vp.y < 1) continue;
                }
                civilians.Add(Spawner.Civilian(bx, bz, t));
                return;
            }
        }

        public void ClearAll()
        {
            foreach (var c in civilians) if (c != null) Destroy(c.gameObject);
            civilians.Clear();
            foreach (var kv in vendorNpcs) if (kv.Value != null) Destroy(kv.Value.gameObject);
            vendorNpcs.Clear();
        }
    }
}
