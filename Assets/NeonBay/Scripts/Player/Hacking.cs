using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public class QuickhackDef
    {
        public string id, name, desc;
        public int cost;
        public float upload;
        public int price;
    }

    /// <summary>The scanner (hold TAB): inspect targets, launch quickhacks on people/drones and breach devices.</summary>
    public class Hacking : MonoBehaviour
    {
        public static readonly List<QuickhackDef> All = new List<QuickhackDef>
        {
            new QuickhackDef { id = "ping", name = "Ping", desc = "Reveal every hostile within 40m for 15s.", cost = 1, upload = 0.4f, price = 0 },
            new QuickhackDef { id = "overload", name = "Overload", desc = "Electric burst: heavy damage, stuns briefly.", cost = 3, upload = 1.1f, price = 0 },
            new QuickhackDef { id = "blind", name = "Optic Burn", desc = "Target is blinded and loses track of you for 8s.", cost = 2, upload = 0.8f, price = 900 },
            new QuickhackDef { id = "cripple", name = "Cripple Motor", desc = "Halves movement and wrecks accuracy for 10s.", cost = 2, upload = 0.9f, price = 1100 },
            new QuickhackDef { id = "short", name = "Short Circuit", desc = "Fries chrome: massive damage to drones/cyborgs, stuns humans.", cost = 4, upload = 1.2f, price = 1800 },
            new QuickhackDef { id = "cascade", name = "Cascade", desc = "Damage that jumps to up to 3 nearby enemies.", cost = 5, upload = 1.5f, price = 3200 },
            new QuickhackDef { id = "distract", name = "Lure", desc = "Fake noise pulls the target (and friends) away.", cost = 1, upload = 0.5f, price = 600 },
        };
        public static QuickhackDef Get(string id) => All.Find(q => q.id == id);

        public bool Scanning { get; private set; }
        public Component scanTarget;   // NPC, Drone, Vehicle or Interactable
        public int selected;
        public float uploadProgress = -1f;
        public QuickhackDef uploading;
        Component uploadTarget;
        Terminal breachTerminal;
        public float breachProgress = -1f;
        public string lastResult;
        float pingTimer;

        public List<QuickhackDef> Available
        {
            get
            {
                var l = new List<QuickhackDef>();
                foreach (var q in All) if (Game.Stats != null && Game.Stats.quickhacks.Contains(q.id)) l.Add(q);
                return l;
            }
        }

        void Update()
        {
            if (Game.Stats == null) return;
            bool playing = Game.IsPlaying && !Game.Player.InVehicle && !(Boxing.Match != null && Boxing.Match.Running);
            bool want = playing && InputHub.Held(Btn.Scan);
            if (want != Scanning)
            {
                Scanning = want;
                if (Scanning) Game.Audio?.Play2D("scan", 0.5f);
                Game.Manager?.SetScanSlow(Scanning);
            }
            if (pingTimer > 0) pingTimer -= Time.unscaledDeltaTime;

            UpdateUpload();
            UpdateBreach();
            if (!Scanning) { scanTarget = null; return; }

            // pick the target under the crosshair (generous: spherecast)
            var cam = Game.Cam.transform;
            scanTarget = null;
            float range = Game.Stats.HasCyber("optics_mk1") || Game.Stats.HasCyber("optics_mk2") ? 70f : 45f;
            if (Physics.SphereCast(cam.position, 0.35f, cam.forward, out var hit, range, Layers.InteractMask, QueryTriggerInteraction.Collide))
            {
                var c = hit.collider;
                var npcHit = c.GetComponentInParent<NPC>();
                var droneHit = c.GetComponentInParent<Drone>();
                var vehHit = c.GetComponentInParent<Vehicle>();
                if (npcHit != null) scanTarget = npcHit;
                else if (droneHit != null) scanTarget = droneHit;
                else if (vehHit != null) scanTarget = vehHit;
                if (scanTarget == null)
                {
                    var ia = c.GetComponentInParent<Interactable>();
                    if (ia != null && ia.Hackable) scanTarget = ia;
                }
                if (scanTarget is NPC dead && dead.state == NPCState.Dead) scanTarget = null;
            }

            var avail = Available;
            if (avail.Count > 0)
            {
                float sc = InputHub.Scroll;
                if (sc > 0.01f) selected = (selected - 1 + avail.Count) % avail.Count;
                if (sc < -0.01f) selected = (selected + 1) % avail.Count;
                for (int i = 0; i < Mathf.Min(7, avail.Count); i++) if (InputHub.Down(Btn.Weapon1 + i) && i < 4) selected = i;
                selected = Mathf.Clamp(selected, 0, avail.Count - 1);
            }
            if (InputHub.Down(Btn.Fire) && uploadProgress < 0f)
            {
                if (scanTarget is Interactable dev && dev.Hackable) StartDeviceHack(dev);
                else if (scanTarget is Vehicle veh) StartVehicleHack(veh);
                else if (scanTarget != null && avail.Count > 0) StartQuickhack(avail[selected], scanTarget);
                else if (avail.Count > 0 && avail[selected].id == "ping") StartQuickhack(avail[selected], null);
            }
        }

        void StartQuickhack(QuickhackDef q, Component target)
        {
            if (!Game.Stats.UseRam(q.cost)) { Game.UI?.Notify("Not enough RAM", Palette.Red); Game.Audio?.Play2D("ui_error"); return; }
            uploading = q;
            uploadTarget = target;
            uploadProgress = 0f;
            Game.Audio?.Play2D("hack_start", 0.6f);
            if (!Game.Stats.HasPerk("ghost_signal") && target is NPC n && n.IsHostileToPlayer) n.detection = Mathf.Max(n.detection, 0.5f);
        }

        void StartDeviceHack(Interactable dev)
        {
            if (!Game.Stats.UseRam(dev.HackCost)) { Game.UI?.Notify("Not enough RAM", Palette.Red); Game.Audio?.Play2D("ui_error"); return; }
            uploading = new QuickhackDef { id = "device", name = dev.HackLabel, upload = 1.2f };
            uploadTarget = dev;
            uploadProgress = 0f;
            Game.Audio?.Play2D("hack_start", 0.6f);
        }

        void StartVehicleHack(Vehicle v)
        {
            if (!Game.Stats.UseRam(3)) { Game.UI?.Notify("Not enough RAM", Palette.Red); return; }
            uploading = new QuickhackDef { id = "vehicle", name = "Overheat engine", upload = 1.4f };
            uploadTarget = v;
            uploadProgress = 0f;
            Game.Audio?.Play2D("hack_start", 0.6f);
        }

        void UpdateUpload()
        {
            if (uploadProgress < 0f || uploading == null) return;
            if (uploadTarget == null && uploading.id != "ping") { uploadProgress = -1f; return; }
            uploadProgress += Time.unscaledDeltaTime / Mathf.Max(0.1f, uploading.upload * Game.Stats.UploadMult);
            if (uploadProgress < 1f) return;
            uploadProgress = -1f;
            Execute(uploading, uploadTarget);
            uploading = null;
        }

        void Execute(QuickhackDef q, Component target)
        {
            float mult = Game.Stats.HackMult * Game.PlayerDamageMult;
            Game.Audio?.Play2D("hack_done", 0.6f);
            Damageable d = target != null ? target.GetComponent<Damageable>() : null;
            var npc = target as NPC;
            var pos = target != null ? target.transform.position + Vector3.up : Game.PlayerPos;
            void Hurt(Damageable who, float amount, DamageType t)
            {
                if (who == null) return;
                who.ApplyDamage(new DamageInfo { amount = amount, type = t, point = who.transform.position + Vector3.up, direction = Vector3.up, source = gameObject, fromPlayer = true });
                Game.UI?.DamageNumber(who.transform.position + Vector3.up * 1.8f, amount, false, false);
            }
            switch (q.id)
            {
                case "ping":
                    pingTimer = 15f;
                    foreach (var n in NPC.All) if (n.IsHostileToPlayer && (n.transform.position - Game.PlayerPos).sqrMagnitude < 1600f) n.Reveal(15f);
                    Game.UI?.Notify("Ping: hostiles revealed", Palette.Cyan);
                    break;
                case "overload":
                    Hurt(d, 55f * mult, DamageType.Electric);
                    npc?.Stun(1.2f);
                    Game.Fx?.ElectricBurst(pos, 2f);
                    break;
                case "blind": npc?.Blind(8f); Game.Fx?.Burst(pos + Vector3.up * 0.6f, Palette.Red, 15); break;
                case "cripple": npc?.Cripple(10f); Game.Fx?.Burst(pos, Palette.Yellow, 15); break;
                case "short":
                    Hurt(d, (d != null && d.isRobotic ? 180f : 30f) * mult, DamageType.Electric);
                    npc?.Stun(3f);
                    Game.Fx?.ElectricBurst(pos, 3f);
                    break;
                case "cascade":
                    Hurt(d, 45f * mult, DamageType.Hack);
                    int jumps = 0;
                    foreach (var n in NPC.All)
                    {
                        if (jumps >= 3 || n == npc || n.state == NPCState.Dead || !n.IsHostileToPlayer) continue;
                        if ((n.transform.position - pos).sqrMagnitude > 15f * 15f) continue;
                        Hurt(n.dmg, 35f * mult, DamageType.Hack);
                        Game.Fx?.Tracer(pos, n.transform.position + Vector3.up, Palette.Purple);
                        jumps++;
                    }
                    Game.Fx?.ElectricBurst(pos, 2f);
                    break;
                case "distract":
                    foreach (var n in NPC.All) if ((n.transform.position - pos).sqrMagnitude < 12f * 12f) n.Distract(pos);
                    break;
                case "device":
                    if (target is Interactable dev) dev.OnHacked();
                    Game.Stats.AddXP(20);
                    break;
                case "vehicle":
                    if (target is Vehicle v) v.dmg.ApplyDamage(new DamageInfo { amount = v.dmg.maxHealth * 0.8f, type = DamageType.Hack, point = v.transform.position, source = gameObject, fromPlayer = true });
                    break;
            }
            if (npc != null && npc.state != NPCState.Dead && !Game.Stats.HasPerk("ghost_signal") && npc.IsHostileToPlayer) npc.EngageTarget(Game.Stats.dmg);
            if (npc != null && !npc.IsHostileToPlayer && q.id != "ping") Factions.Provoke(npc.faction);
            if (npc != null && npc.faction == FactionId.Civilian && (q.id == "overload" || q.id == "short" || q.id == "cascade")) GameEvents.RaiseCrime(CrimeType.Assault, pos);
        }

        // manual breach (no RAM) by standing at a terminal
        public void StartManualBreach(Terminal t)
        {
            breachTerminal = t;
            breachProgress = 0f;
            Game.Audio?.Play2D("hack_start", 0.6f);
        }

        void UpdateBreach()
        {
            if (breachTerminal == null) return;
            if (!Game.IsPlaying || (breachTerminal.transform.position - Game.PlayerPos).sqrMagnitude > 9f || breachTerminal.hacked)
            {
                if (!breachTerminal.hacked) Game.UI?.Notify("Breach interrupted", Palette.Red);
                breachTerminal = null; breachProgress = -1f; return;
            }
            float speed = 1f / (4.5f - Mathf.Min(3f, Game.Stats.Attr(Attr.Neural) * 0.25f));
            breachProgress += Time.deltaTime * speed;
            if (breachProgress >= 1f)
            {
                breachTerminal.OnHacked();
                Game.Stats.AddXP(40);
                breachTerminal = null; breachProgress = -1f;
            }
        }

        public bool Pinging => pingTimer > 0f;
    }
}
