using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Spawns lane-following traffic and parked cars around the player, and summons owned vehicles.</summary>
    public class TrafficSystem : MonoBehaviour
    {
        public int trafficTarget = 22;
        public int parkedTarget = 10;
        readonly List<Vehicle> traffic = new List<Vehicle>();
        readonly List<Vehicle> parked = new List<Vehicle>();
        public readonly List<string> owned = new List<string>();
        Vehicle summoned;
        float timer;
        static readonly VehicleType[] trafficTypes = { VehicleType.Sedan, VehicleType.Sedan, VehicleType.Taxi, VehicleType.Taxi, VehicleType.Trike, VehicleType.Trike, VehicleType.Van, VehicleType.Muscle, VehicleType.Sports, VehicleType.Police };

        void Start() { Game.Traffic = this; }

        void Update()
        {
            if (!Game.HasPlayer || Game.City == null) return;
            timer -= Time.deltaTime;
            if (timer > 0f) return;
            timer = 0.5f;
            var p = Game.PlayerPos;
            if (p.y < -20f) return; // inside an interior
            traffic.RemoveAll(v => v == null);
            parked.RemoveAll(v => v == null);

            for (int i = traffic.Count - 1; i >= 0; i--)
            {
                var v = traffic[i];
                if (v.mode == VehicleMode.Player) { traffic.RemoveAt(i); continue; }
                if ((v.transform.position - p).sqrMagnitude > 330f * 330f) { Destroy(v.gameObject); traffic.RemoveAt(i); }
            }
            for (int i = parked.Count - 1; i >= 0; i--)
            {
                var v = parked[i];
                if (v.mode == VehicleMode.Player) { parked.RemoveAt(i); continue; }
                if ((v.transform.position - p).sqrMagnitude > 260f * 260f) { Destroy(v.gameObject); parked.RemoveAt(i); }
            }
            int want = Game.Env != null && Game.Env.NightFactor > 0.5f ? trafficTarget - 4 : trafficTarget;
            if (traffic.Count < want) SpawnTraffic(p);
            if (parked.Count < parkedTarget) SpawnParked(p);
        }

        bool Visible(Vector3 pos)
        {
            var cam = Game.Cam;
            if (cam == null) return false;
            var vp = cam.WorldToViewportPoint(pos);
            return vp.z > 0 && vp.x > -0.1f && vp.x < 1.1f && vp.y > -0.1f && vp.y < 1.1f && vp.z < 140f;
        }

        void SpawnTraffic(Vector3 p)
        {
            for (int attempt = 0; attempt < 6; attempt++)
            {
                int ix = Mathf.Clamp(Mathf.RoundToInt(p.x / CityData.Cell) + Random.Range(-3, 4), 0, CityData.Grid);
                int iz = Mathf.Clamp(Mathf.RoundToInt(p.z / CityData.Cell) + Random.Range(-3, 4), 0, CityData.Grid);
                var at = Game.City.Intersection(ix, iz);
                float d = (at - p).Flat().magnitude;
                if (d < 90f || d > 300f || Visible(at)) continue;
                int dir = Random.Range(0, 4);
                var dv = dir == 0 ? Vector3.right : dir == 1 ? Vector3.forward : dir == 2 ? Vector3.left : Vector3.back;
                int nx = ix + Mathf.RoundToInt(dv.x), nz = iz + Mathf.RoundToInt(dv.z);
                if (nx < 0 || nz < 0 || nx > CityData.Grid || nz > CityData.Grid) continue;
                var right = Vector3.Cross(Vector3.up, dv);
                var pos = at + dv * (CityData.RoadW * 0.5f + 2f) + right * 1.75f + Vector3.up * 0.02f;
                if (Physics.CheckBox(pos + Vector3.up, new Vector3(1.2f, 0.8f, 3f), Quaternion.LookRotation(dv), Layers.ActorAndPlayerMask)) continue;
                var type = trafficTypes[Random.Range(0, trafficTypes.Length)];
                if (Game.City.DistrictAt(at) == District.Scar && Random.value < 0.6f) continue; // sparse traffic in the Scar
                var v = Vehicle.Create(type, pos, Quaternion.LookRotation(dv), VehicleMode.Traffic);
                v.InitTraffic(ix, iz, dir, Random.Range(10f, 15f));
                traffic.Add(v);
                return;
            }
        }

        void SpawnParked(Vector3 p)
        {
            for (int attempt = 0; attempt < 6; attempt++)
            {
                var guess = p + new Vector3(Random.Range(-160f, 160f), 0, Random.Range(-160f, 160f));
                var road = Game.City.NearestRoadPoint(guess, out var dir);
                if (!Game.City.InCity(road) || (road - p).sqrMagnitude < 50f * 50f || Visible(road)) continue;
                // keep away from intersections
                float along = Vector3.Dot(road, dir) % CityData.Cell;
                if (along < 14f || along > CityData.Cell - 14f) continue;
                var side = Vector3.Cross(Vector3.up, dir) * (Random.value < 0.5f ? 1 : -1);
                var pos = road + side * 5.6f + Vector3.up * 0.02f;
                var face = Vector3.Dot(side, Vector3.Cross(Vector3.up, dir)) > 0 ? dir : -dir;
                if (Physics.CheckBox(pos + Vector3.up, new Vector3(1.2f, 0.8f, 3f), Quaternion.LookRotation(face), Layers.ActorAndPlayerMask)) continue;
                var type = trafficTypes[Random.Range(0, trafficTypes.Length - 1)];
                var v = Vehicle.Create(type, pos, Quaternion.LookRotation(face), VehicleMode.Parked);
                parked.Add(v);
                return;
            }
        }

        public void Own(string vehicleType)
        {
            if (!owned.Contains(vehicleType)) owned.Add(vehicleType);
        }

        public bool Summon(string vehicleType)
        {
            if (!owned.Contains(vehicleType) || !System.Enum.TryParse(vehicleType, out VehicleType t)) return false;
            var p = Game.PlayerPos;
            if (p.y < -20f) { Game.UI?.Notify("No signal underground", Palette.Red); return false; }
            if (summoned != null && summoned.mode != VehicleMode.Player) Destroy(summoned.gameObject);
            var road = Game.City.NearestRoadPoint(p + Game.Cam.transform.forward.Flat().normalized * 15f, out var dir);
            var pos = road + Vector3.Cross(Vector3.up, dir) * 5.6f + Vector3.up * 0.6f;
            summoned = Vehicle.Create(t, pos, Quaternion.LookRotation(dir), VehicleMode.Abandoned);
            summoned.ownedId = vehicleType;
            Game.UI?.Notify(Vehicle.TypeName(t) + " delivered nearby (autopilot)", Palette.Cyan);
            Game.UI?.SetWaypoint(pos, Vehicle.TypeName(t));
            return true;
        }

        public void ClearAll()
        {
            foreach (var v in traffic) if (v != null) Destroy(v.gameObject);
            foreach (var v in parked) if (v != null) Destroy(v.gameObject);
            if (summoned != null) Destroy(summoned.gameObject);
            traffic.Clear(); parked.Clear();
        }
    }
}
