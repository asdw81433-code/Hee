using UnityEngine;

namespace NeonBay
{
    /// <summary>First-person movement and camera: walk, sprint, crouch, slide, jump, double jump, mantle, head bob, recoil, shake.</summary>
    [RequireComponent(typeof(CharacterController))]
    public class PlayerController : MonoBehaviour
    {
        public CharacterController cc;
        public Transform pivot;     // pitch
        public Transform shakeRoot; // bob / shake offsets
        public Camera Cam;
        public Vehicle vehicle;
        public bool InVehicle => vehicle != null;
        public bool cameraOverride;   // vehicle third-person camera etc.
        public bool controlEnabled = true;

        public Vector3 Velocity { get; private set; }
        public bool Grounded { get; private set; }
        public bool Crouching { get; private set; }
        public bool Sprinting { get; private set; }
        public bool Sliding { get; private set; }
        public float Noise { get; private set; }
        public float Yaw => yaw;

        const float StandHeight = 1.8f, CrouchHeight = 1.1f, Gravity = -24f;
        float yaw, pitch;
        float vy;
        Vector3 horiz;
        bool doubleJumpUsed;
        float slideTimer;
        float stepDist, bobPhase;
        float landDip;
        float fallSpeed;
        float eyeHeight = 1.65f;
        float recoilPitch, recoilYaw, kickVisual;
        float fovCurrent;
        public float fovOverride = -1f;
        public float sensitivityMult = 1f;
        bool mantling;
        Vector3 mantleFrom, mantleTo;
        float mantleT;

        public static PlayerController Create(CharacterProfile profile, Vector3 pos, float yaw)
        {
            var go = new GameObject("Player") { layer = Layers.Player, tag = "Player" };
            go.transform.position = pos;
            var cc = go.AddComponent<CharacterController>();
            cc.height = StandHeight; cc.radius = 0.35f; cc.center = new Vector3(0, StandHeight / 2f, 0);
            cc.stepOffset = 0.42f; cc.slopeLimit = 50f; cc.skinWidth = 0.04f; cc.minMoveDistance = 0f;
            var pc = go.AddComponent<PlayerController>();
            pc.cc = cc;
            var pivot = new GameObject("Pivot");
            pivot.transform.SetParent(go.transform, false);
            pivot.transform.localPosition = new Vector3(0, 1.65f, 0);
            pc.pivot = pivot.transform;
            var shake = new GameObject("Shake");
            shake.transform.SetParent(pivot.transform, false);
            pc.shakeRoot = shake.transform;
            var camGo = new GameObject("PlayerCamera") { tag = "MainCamera" };
            camGo.transform.SetParent(shake.transform, false);
            var cam = camGo.AddComponent<Camera>();
            cam.nearClipPlane = 0.03f;
            cam.farClipPlane = Game.Settings != null ? Game.Settings.viewDistance : 1400f;
            cam.fieldOfView = Game.Settings != null ? Game.Settings.fov : 78f;
            cam.allowHDR = true;
            camGo.AddComponent<AudioListener>();
            pc.Cam = cam;
            PostFX.SetupCamera(cam);

            var dmg = go.AddComponent<Damageable>();
            dmg.faction = FactionId.Player;
            go.AddComponent<PlayerStats>();
            go.AddComponent<Inventory>();
            go.AddComponent<WeaponController>();
            go.AddComponent<PlayerInteractor>();
            go.AddComponent<Hacking>();
            pc.yaw = yaw;
            pc.fovCurrent = cam.fieldOfView;
            return pc;
        }

        void Awake()
        {
            if (cc == null) cc = GetComponent<CharacterController>();
        }

        public void Teleport(Vector3 pos, float newYaw)
        {
            if (InVehicle) ExitVehicle(true);
            cc.enabled = false;
            transform.position = pos;
            cc.enabled = true;
            yaw = newYaw; pitch = 0; vy = 0; horiz = Vector3.zero; fallSpeed = 0;
            transform.rotation = Quaternion.Euler(0, yaw, 0);
            NavMeshStreamer.Instance?.ForceRebuild();
        }

        public void AddRecoil(float pitchDeg, float yawDeg)
        {
            recoilPitch += pitchDeg;
            recoilYaw += yawDeg;
            kickVisual += pitchDeg * 0.6f;
        }

        public void Shake(float amount) => CameraFX.Shake(amount);

        public void LookAt(Vector3 worldPoint, float speed)
        {
            var d = worldPoint - Cam.transform.position;
            if (d.sqrMagnitude < 0.01f) return;
            var rot = Quaternion.LookRotation(d);
            var e = rot.eulerAngles;
            float targetPitch = e.x > 180 ? e.x - 360 : e.x;
            yaw = Mathf.LerpAngle(yaw, e.y, Time.unscaledDeltaTime * speed);
            pitch = Mathf.Lerp(pitch, targetPitch, Time.unscaledDeltaTime * speed);
            ApplyRotation();
        }

        float Dt => Game.Manager != null && Game.Manager.SlowMotion ? Time.unscaledDeltaTime * 0.8f : Time.deltaTime;

        void Update()
        {
            if (Game.Manager == null) return;
            bool playing = Game.IsPlaying && controlEnabled;
            float dt = Dt;
            if (dt <= 0f) return;

            if (playing) Look();
            if (InVehicle) { UpdateCamera(dt); return; }
            if (!cc.enabled) { UpdateCamera(dt); return; }
            if (mantling) { UpdateMantle(dt); UpdateCamera(dt); return; }
            Move(dt, playing);
            UpdateCamera(dt);
        }

        void Look()
        {
            var s = Game.Settings;
            float sens = (s != null ? s.mouseSensitivity : 1f) * 2.2f * sensitivityMult;
            var l = InputHub.Look * sens;
            yaw += l.x;
            pitch -= l.y * (s != null && s.invertY ? -1 : 1);
            // recoil feeds into the actual aim
            pitch -= recoilPitch * 0.35f;
            recoilPitch = Mathf.Max(0f, recoilPitch - recoilPitch * 0.35f);
            yaw += recoilYaw * 0.5f;
            recoilYaw *= 0.5f;
            pitch = Mathf.Clamp(pitch, -86f, 86f);
            if (InVehicle && !cameraOverride)
            {
                float rel = Mathf.DeltaAngle(vehicle.transform.eulerAngles.y, yaw);
                rel = Mathf.Clamp(rel, -120f, 120f);
                yaw = vehicle.transform.eulerAngles.y + rel;
            }
            ApplyRotation();
        }

        void ApplyRotation()
        {
            if (InVehicle)
            {
                transform.localRotation = Quaternion.identity;
                pivot.rotation = Quaternion.Euler(pitch, yaw, 0);
            }
            else
            {
                transform.rotation = Quaternion.Euler(0, yaw, 0);
                pivot.localRotation = Quaternion.Euler(pitch, 0, 0);
            }
        }

        void Move(float dt, bool playing)
        {
            var stats = Game.Stats;
            var input = playing ? InputHub.Move : Vector2.zero;
            bool wantSprint = playing && InputHub.Held(Btn.Sprint) && input.y > 0.1f && !Crouching && (stats == null || stats.stamina > 1f);
            bool aiming = Game.Weapons != null && Game.Weapons.Aiming;
            if (aiming) wantSprint = false;

            // crouch / slide
            if (playing && InputHub.Down(Btn.Crouch))
            {
                if (Sprinting && Grounded && !Sliding)
                {
                    Sliding = true; slideTimer = 0.85f;
                    horiz = horiz.normalized * Mathf.Max(horiz.magnitude, 10.5f);
                    Game.Audio?.Play2D("slide", 0.6f);
                    Crouching = true;
                }
                else if (Crouching) TryStand();
                else Crouching = true;
            }
            if (Sliding)
            {
                slideTimer -= dt;
                if (slideTimer <= 0f || horiz.magnitude < 3f) Sliding = false;
            }

            float mult = stats != null ? stats.MoveMult : 1f;
            float speed = Crouching ? 2.4f : wantSprint ? 7.6f : (playing && InputHub.Held(Btn.Walk) ? 2.3f : 4.6f);
            speed *= mult;
            if (aiming) speed *= 0.6f;
            Sprinting = wantSprint && input.sqrMagnitude > 0.01f;
            if (Sprinting && stats != null && !stats.HasBuff("stim")) stats.stamina = Mathf.Max(0, stats.stamina - 11f * dt);

            var wish = (transform.forward * input.y + transform.right * input.x) * speed;
            if (Sliding)
            {
                horiz = Vector3.MoveTowards(horiz, Vector3.zero, 7f * dt);
            }
            else
            {
                float accel = Grounded ? (wish.sqrMagnitude > horiz.sqrMagnitude ? 14f : 11f) : 2.2f;
                horiz = Vector3.MoveTowards(horiz, wish, accel * speed * dt * (Grounded ? 1f : 0.6f) + (Grounded ? 0.5f : 0f));
            }

            // jump / double jump / mantle
            if (playing && InputHub.Down(Btn.Jump))
            {
                if (Crouching && !Sliding) TryStand();
                else if (TryStartMantle()) return;
                else if (Grounded)
                {
                    vy = Mathf.Sqrt(2f * -Gravity * 1.25f);
                    if (Sliding) { Sliding = false; horiz *= 1.08f; }
                    Crouching = false;
                    stats?.UseStamina(6f);
                    Game.Audio?.Play2D("jump", 0.4f);
                }
                else if (!doubleJumpUsed && stats != null && stats.HasCyber("spring_legs"))
                {
                    doubleJumpUsed = true;
                    vy = Mathf.Sqrt(2f * -Gravity * 1.6f);
                    horiz = Vector3.Lerp(horiz, wish, 0.6f);
                    Game.Audio?.Play2D("dash", 0.5f);
                    Game.Fx?.Burst(transform.position, Palette.Cyan, 12);
                }
            }

            vy += Gravity * dt;
            var motion = (horiz + Vector3.up * vy) * dt;
            bool wasGrounded = Grounded;
            var flags = cc.Move(motion);
            Grounded = (flags & CollisionFlags.Below) != 0 || cc.isGrounded;
            if ((flags & CollisionFlags.Above) != 0 && vy > 0) vy = 0;
            if (Grounded)
            {
                if (!wasGrounded) Land();
                vy = -2f;
                doubleJumpUsed = false;
            }
            else fallSpeed = Mathf.Min(fallSpeed, vy);

            // height (crouch)
            float targetH = Crouching ? CrouchHeight : StandHeight;
            if (!Mathf.Approximately(cc.height, targetH))
            {
                cc.height = Mathf.MoveTowards(cc.height, targetH, dt * 6f);
                cc.center = new Vector3(0, cc.height / 2f, 0);
            }
            eyeHeight = Mathf.MoveTowards(eyeHeight, Crouching ? 1.0f : 1.65f, dt * 5f);

            Velocity = cc.velocity;
            var flat = Velocity.Flat();
            if (Grounded && flat.magnitude > 0.5f)
            {
                stepDist += flat.magnitude * dt;
                bobPhase += flat.magnitude * dt * (Sprinting ? 1.6f : 1.9f);
                float stride = Sprinting ? 2.6f : Crouching ? 1.4f : 2.1f;
                if (stepDist > stride)
                {
                    stepDist = 0;
                    bool wet = Game.Env != null && Game.Env.wetness > 0.3f && transform.position.y > -20f;
                    if (!Crouching) Game.Audio?.Play2D(wet ? "step_wet" : "step", Sprinting ? 0.55f : 0.35f, Random.Range(0.9f, 1.1f));
                    Noise = Sprinting ? 1f : Crouching ? 0.05f : 0.45f;
                    if (Sprinting) GameEvents.RaiseNoise(transform.position, 9f, gameObject);
                }
            }
            else if (flat.magnitude < 0.3f) Noise = Mathf.MoveTowards(Noise, 0f, dt);

            // out of bounds safety
            if (transform.position.y < -150f) Game.Manager.RescueToStreet();
        }

        void Land()
        {
            float impact = -fallSpeed;
            fallSpeed = 0;
            if (impact > 6f)
            {
                landDip = Mathf.Clamp(impact * 0.012f, 0f, 0.25f);
                Game.Audio?.Play2D("land", Mathf.Clamp01(impact / 18f));
            }
            if (impact > 15f)
            {
                float dmg = (impact - 15f) * 7f;
                var stats = Game.Stats;
                if (stats != null && stats.HasCyber("pneumatic_calves")) dmg *= 0.4f;
                var d = GetComponent<Damageable>();
                d.ApplyDamage(new DamageInfo { amount = dmg, type = DamageType.Fall, point = transform.position, direction = Vector3.down });
                Shake(0.4f);
            }
        }

        void TryStand()
        {
            // make sure there's head room
            var p = transform.position;
            if (!Physics.CheckCapsule(p + Vector3.up * (cc.radius + 0.05f), p + Vector3.up * (StandHeight - cc.radius), cc.radius * 0.9f, Layers.ShootMask, QueryTriggerInteraction.Ignore))
            { Crouching = false; Sliding = false; }
        }

        bool TryStartMantle()
        {
            var p = transform.position;
            var fwd = transform.forward;
            if (!Physics.Raycast(p + Vector3.up * 1.0f, fwd, out var wall, 0.9f, Layers.ShootMask, QueryTriggerInteraction.Ignore)) return false;
            var probe = p + Vector3.up * 2.4f + fwd * (wall.distance + 0.45f);
            if (!Physics.Raycast(probe, Vector3.down, out var top, 2.0f, Layers.ShootMask, QueryTriggerInteraction.Ignore)) return false;
            float h = top.point.y - p.y;
            if (h < 0.55f || h > 2.25f || top.normal.y < 0.7f) return false;
            var dest = top.point + Vector3.up * 0.05f;
            if (Physics.CheckCapsule(dest + Vector3.up * (cc.radius + 0.1f), dest + Vector3.up * (CrouchHeight - cc.radius), cc.radius * 0.9f, Layers.ShootMask, QueryTriggerInteraction.Ignore)) return false;
            mantling = true; mantleT = 0; mantleFrom = p; mantleTo = dest;
            vy = 0; horiz = Vector3.zero;
            Game.Audio?.Play2D("jump", 0.5f, 0.8f);
            return true;
        }

        void UpdateMantle(float dt)
        {
            mantleT += dt / 0.38f;
            var mid = new Vector3(mantleFrom.x, mantleTo.y + 0.2f, mantleFrom.z);
            Vector3 pos = mantleT < 0.6f ? Vector3.Lerp(mantleFrom, mid, mantleT / 0.6f) : Vector3.Lerp(mid, mantleTo, (mantleT - 0.6f) / 0.4f);
            cc.enabled = false;
            transform.position = pos;
            cc.enabled = true;
            if (mantleT >= 1f) { mantling = false; Grounded = true; }
        }

        void UpdateCamera(float dt)
        {
            if (cameraOverride) return;
            var s = Game.Settings;
            // bob
            float amp = Grounded && !InVehicle ? Mathf.Clamp01(Velocity.Flat().magnitude / 7f) * (Sprinting ? 0.06f : 0.035f) : 0f;
            if (s != null && !s.headBob) amp = 0;
            var bob = new Vector3(Mathf.Cos(bobPhase * 0.5f * Mathf.PI) * amp * 0.6f, Mathf.Abs(Mathf.Sin(bobPhase * 0.5f * Mathf.PI)) * amp, 0f);
            landDip = Mathf.MoveTowards(landDip, 0f, dt * 0.9f);
            if (!InVehicle) pivot.localPosition = new Vector3(0, eyeHeight - landDip, 0);
            // trauma shake, kicks and concussion sway (shared CameraFX layer)
            var shakePos = CameraFX.PositionOffset;
            var shakeRot = CameraFX.RotationOffset;
            kickVisual = Mathf.MoveTowards(kickVisual, 0f, dt * 20f * Mathf.Max(1f, kickVisual));
            float roll = Sliding ? 4f : 0f;
            shakeRoot.localPosition = bob + shakePos;
            shakeRoot.localRotation = Quaternion.Euler(-kickVisual + shakeRot.x, shakeRot.y, shakeRot.z + roll);

            // fov
            float baseFov = s != null ? s.fov : 78f;
            float target = fovOverride > 0 ? fovOverride : baseFov + (Sprinting ? 7f : 0f) + (Sliding ? 9f : 0f);
            fovCurrent = Mathf.Lerp(fovCurrent, target, 1f - Mathf.Exp(-12f * Time.unscaledDeltaTime));
            Cam.fieldOfView = fovCurrent + CameraFX.FovOffset;
        }

        // ----------------------------------------------------------------- vehicles
        public void EnterVehicle(Vehicle v)
        {
            vehicle = v;
            cc.enabled = false;
            transform.SetParent(v.seat, false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
            pivot.localPosition = new Vector3(0, 0.75f, 0);
            Crouching = false; Sliding = false; Sprinting = false;
            Velocity = Vector3.zero;
            Game.Weapons?.Holster(true);
        }

        public void ExitVehicle(bool force = false)
        {
            if (vehicle == null) return;
            var v = vehicle;
            var exit = v.FindExitPoint();
            vehicle = null;
            cameraOverride = false;
            transform.SetParent(null, true);
            transform.position = exit;
            yaw = v.transform.eulerAngles.y;
            transform.rotation = Quaternion.Euler(0, yaw, 0);
            pivot.localPosition = new Vector3(0, 1.65f, 0);
            pivot.localRotation = Quaternion.Euler(pitch, 0, 0);
            shakeRoot.localPosition = Vector3.zero;
            Cam.transform.localPosition = Vector3.zero;
            Cam.transform.localRotation = Quaternion.identity;
            cc.enabled = true;
            v.OnPlayerExit();
            Game.Weapons?.Holster(false);
        }
    }

    public static class PlayerStatsExt
    {
        public static void UseStamina(this PlayerStats s, float amount)
        {
            if (s == null || s.HasBuff("stim")) return;
            s.stamina = Mathf.Max(0f, s.stamina - amount);
        }
    }
}
