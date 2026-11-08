using UnityEngine;

namespace NeonBay
{
    /// <summary>Finds what the player is looking at and handles E (use / talk / takedown) and F (vehicles).</summary>
    public class PlayerInteractor : MonoBehaviour
    {
        public Interactable focus;
        public NPC takedownTarget;
        public Vehicle nearVehicle;
        public string PromptText { get; private set; }
        float takedownT = -1f;
        NPC takedownVictim;

        void Update()
        {
            focus = null; takedownTarget = null; nearVehicle = null; PromptText = null;
            if (!Game.IsPlaying || Game.Player == null) return;
            if (Boxing.Match != null && Boxing.Match.Running) return;
            var pc = Game.Player;
            if (pc.InVehicle) return;
            var cam = Game.Cam.transform;

            if (takedownT >= 0f)
            {
                takedownT += Time.deltaTime;
                if (takedownVictim != null) pc.LookAt(takedownVictim.rig.HeadPos, 10f);
                if (takedownT > 0.6f)
                {
                    if (takedownVictim != null && takedownVictim.state != NPCState.Dead)
                    {
                        takedownVictim.Takedown(true);
                        Game.Audio?.Play2D("punch", 1f, 0.8f);
                        Game.Stats.AddXP(30);
                    }
                    takedownT = -1f; takedownVictim = null;
                    pc.controlEnabled = true;
                }
                return;
            }

            if (Physics.Raycast(cam.position, cam.forward, out var hit, 3.6f, Layers.InteractMask, QueryTriggerInteraction.Collide))
            {
                var ia = hit.collider.GetComponentInParent<Interactable>();
                if (ia != null && hit.distance <= ia.range + 0.4f && ia.CanInteract) focus = ia;
                var npc = hit.collider.GetComponentInParent<NPC>();
                if (npc != null && hit.distance < 2.4f && npc.CanBeTakenDown(transform) && (npc.IsHostileToPlayer || npc.faction != FactionId.Civilian)) takedownTarget = npc;
            }
            if (takedownTarget != null)
            {
                PromptText = "[" + InputHub.Label(Btn.Interact) + "] Takedown " + takedownTarget.displayName;
                if (InputHub.Down(Btn.Interact))
                {
                    takedownVictim = takedownTarget;
                    takedownVictim.Stun(1.5f);
                    takedownT = 0f;
                    pc.controlEnabled = false;
                }
                return;
            }
            if (focus != null)
            {
                PromptText = "[" + InputHub.Label(Btn.Interact) + "] " + focus.Prompt;
                if (InputHub.Down(Btn.Interact)) { focus.Interact(); Game.Audio?.Play2D("ui_blip", 0.4f); }
            }

            // vehicles: nearest within reach
            float best = 16f;
            foreach (var c in Physics.OverlapSphere(transform.position + Vector3.up, 3.6f, 1 << Layers.Actors, QueryTriggerInteraction.Ignore))
            {
                var v = c.GetComponentInParent<Vehicle>();
                if (v == null || v.mode == VehicleMode.Wreck) continue;
                float d = (v.transform.position - transform.position).sqrMagnitude;
                if (d < best) { best = d; nearVehicle = v; }
            }
            if (nearVehicle != null)
            {
                string verb = nearVehicle.mode == VehicleMode.Traffic ? "Carjack" : !string.IsNullOrEmpty(nearVehicle.ownedId) ? "Drive" : nearVehicle.mode == VehicleMode.Parked ? "Steal" : "Drive";
                if (PromptText == null) PromptText = "[" + InputHub.Label(Btn.Vehicle) + "] " + verb + " " + Vehicle.TypeName(nearVehicle.type);
                if (InputHub.Down(Btn.Vehicle)) nearVehicle.EnterAsPlayer();
            }

            if (InputHub.Down(Btn.CallCar) && Game.Traffic != null)
            {
                if (Game.Traffic.owned.Count == 0) Game.UI?.Notify("You don't own a vehicle yet (Uncle Tony's Motors, Port Marrow Docks)", Palette.Yellow);
                else Game.UI?.OpenGarage();
            }
        }
    }
}
