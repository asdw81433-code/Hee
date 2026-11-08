using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;

namespace NeonBay
{
    public enum Archetype { Civilian, Grunt, Gunner, Shotgunner, Bruiser, Sniper, Netrunner, Heavy, Boss, Officer, Vendor }
    public enum NPCState { Idle, Walk, Suspicious, Combat, Search, Flee, Cower, Stunned, Dead }

    /// <summary>
    /// One class drives civilians, vendors, gang members, police and bosses. Behaviour is chosen by archetype
    /// and hostility. Movement uses a NavMeshAgent when the streamed NavMesh is available, otherwise simple steering.
    /// </summary>
    public class NPC : MonoBehaviour
    {
        public string npcId;
        public string shopId;
        public string displayName = "Citizen";
        public string groupId;
        public FactionId faction = FactionId.Civilian;
        public Archetype archetype = Archetype.Civilian;
        public int level = 1;
        public bool forcedHostile;
        public bool stationary;
        public bool essential;
        public bool talkable;
        public Vector3 home;
        public float homeRadius = 10f;

        public NPCState state = NPCState.Idle;
        public HumanoidRig rig;
        public Damageable dmg;
        public NavMeshAgent agent;
        public WeaponDef weaponDef;
        public float detection;   // 0..1 awareness of the player
        public Damageable target;
        public bool revealed => revealTimer > 0f;
        public bool Aware => state == NPCState.Combat || state == NPCState.Search || detection > 0.6f;
        public bool IsHostileToPlayer => forcedHostile || Factions.HostileToPlayer(faction);

        // sidewalk walking for civilians
        public int bx = -1, bz = -1;
        public float loopT;
        public int loopDir = 1;

        Vector3 lastKnown;
        float thinkTimer, moveTimer, stateTimer, fireCd, burstLeft, reloadTimer, stunTimer, blindTimer, crippleTimer, revealTimer, bleedLeft, bleedRate;
        float meleeT = -1f;
        int ammo;
        Vector3 moveTarget;
        bool hasMoveTarget;
        float speed;
        float lostSightTime;
        float hackChargeT = -1f;
        float grenadeTimer = 8f;
        float idleTimer;
        Vector3 velocity;
        Vector3 lastPos;
        float coverTimer;
        public float sightRange = 38f;
        static readonly List<NPC> all = new List<NPC>();
        public static IReadOnlyList<NPC> All => all;

        public float PreferredRange => archetype switch
        {
            Archetype.Bruiser => 1.6f,
            Archetype.Shotgunner => 7f,
            Archetype.Sniper => 45f,
            Archetype.Gunner => 22f,
            Archetype.Netrunner => 24f,
            Archetype.Heavy => 16f,
            Archetype.Boss => 12f,
            _ => 15f
        };

        bool Melee => weaponDef == null || weaponDef.IsMelee || archetype == Archetype.Bruiser;

        void OnEnable() { all.Add(this); GameEvents.Noise += OnNoise; }
        void OnDisable() { all.Remove(this); GameEvents.Noise -= OnNoise; }

        public void Setup()
        {
            dmg = GetComponent<Damageable>();
            dmg.faction = faction;
            dmg.Damaged += OnDamaged;
            dmg.Died += OnDied;
            dmg.invulnerable = essential;
            if (weaponDef != null) { ammo = weaponDef.mag > 0 ? weaponDef.mag : 999; rig.AttachWeapon(weaponDef); }
            home = transform.position;
            lastPos = transform.position;
            state = archetype == Archetype.Civilian && bx >= 0 ? NPCState.Walk : NPCState.Idle;
            thinkTimer = Random.Range(0f, 0.3f);
        }

        void TryAttachAgent()
        {
            if (agent != null || stationary || bx >= 0 && state == NPCState.Walk) return;
            if (NavMesh.SamplePosition(transform.position, out var hit, 2.5f, NavMesh.AllAreas))
            {
                transform.position = hit.position;
                agent = gameObject.AddComponent<NavMeshAgent>();
                agent.radius = 0.35f; agent.height = 1.8f;
                agent.speed = 3.5f; agent.acceleration = 14f; agent.angularSpeed = 540f;
                agent.stoppingDistance = 0.6f;
                agent.autoBraking = true;
                agent.obstacleAvoidanceType = ObstacleAvoidanceType.LowQualityObstacleAvoidance;
                agent.updateRotation = false;
            }
        }

        // ------------------------------------------------------------------ update
        void Update()
        {
            if (state == NPCState.Dead) return;
            float dt = Time.deltaTime;
            if (dt <= 0f) return;
            if (stunTimer > 0) stunTimer -= dt;
            if (blindTimer > 0) blindTimer -= dt;
            if (crippleTimer > 0) crippleTimer -= dt;
            if (revealTimer > 0) revealTimer -= dt;
            if (bleedLeft > 0)
            {
                float d = Mathf.Min(bleedLeft, bleedRate * dt);
                bleedLeft -= d;
                dmg.ApplyDamage(new DamageInfo { amount = d, type = DamageType.Melee, point = transform.position + Vector3.up, source = Game.Player != null ? Game.Player.gameObject : null, fromPlayer = true });
                if (state == NPCState.Dead) return;
            }

            thinkTimer -= dt;
            if (thinkTimer <= 0f)
            {
                thinkTimer = 0.2f;
                Think(0.2f);
            }
            Act(dt);

            velocity = (transform.position - lastPos) / dt;
            lastPos = transform.position;
            bool aiming = state == NPCState.Combat && !Melee && stunTimer <= 0f;
            rig.Animate(velocity.Flat().magnitude, aiming, false, dt, state == NPCState.Cower || stunTimer > 0f, meleeT >= 0f, meleeT);
            if (Game.HasPlayer && (Game.PlayerPos - transform.position).sqrMagnitude < 64f && state != NPCState.Combat && state != NPCState.Flee)
                rig.LookAt(Game.Cam.transform.position);
        }

        void Think(float dt)
        {
            if (stunTimer > 0f) { state = state == NPCState.Dead ? state : NPCState.Stunned; return; }
            if (state == NPCState.Stunned) state = target != null ? NPCState.Combat : NPCState.Idle;
            if (archetype == Archetype.Civilian || archetype == Archetype.Vendor) { ThinkCivilian(dt); return; }

            // perception
            var player = Game.HasPlayer ? Game.Stats.dmg : null;
            bool seesPlayer = false;
            if (player != null && !player.isDead && blindTimer <= 0f)
            {
                var eye = rig.HeadPos;
                var ppos = Game.Cam.transform.position - Vector3.up * 0.15f;
                float dist = Vector3.Distance(eye, ppos);
                float range = sightRange * (Game.Player.Crouching ? 0.65f : 1f) * (Game.Env != null ? Mathf.Lerp(1f, 0.75f, Game.Env.NightFactor) : 1f);
                var to = (ppos - eye).normalized;
                bool inCone = Vector3.Dot(transform.forward, to.Flat().normalized) > 0.25f || dist < 3f || state == NPCState.Combat;
                if (dist < range && inCone && Util.LineOfSight(eye, ppos))
                {
                    seesPlayer = true;
                    if (IsHostileToPlayer)
                    {
                        float rate = ((1f - dist / range) * 3f + 0.4f) * Game.Stats.DetectionMult * (Game.Player.Noise * 0.5f + 0.75f);
                        if (state == NPCState.Search) rate *= 2.5f;
                        detection = Mathf.Min(1f, detection + rate * dt);
                        if (detection >= 1f) EngageTarget(player);
                        else if (detection > 0.35f && state != NPCState.Combat) { state = NPCState.Suspicious; lastKnown = ppos; }
                    }
                }
            }
            if (!seesPlayer && state != NPCState.Combat) detection = Mathf.Max(0f, detection - dt * 0.15f);

            // other hostile NPCs (gang wars, police shootouts)
            if (target == null || target.isDead)
            {
                target = null;
                foreach (var n in all)
                {
                    if (n == this || n.state == NPCState.Dead || !Factions.Hostile(faction, n.faction) || n.archetype == Archetype.Vendor) continue;
                    if (n.faction == FactionId.Civilian) continue;
                    if ((n.transform.position - transform.position).sqrMagnitude > 35f * 35f) continue;
                    if (!Util.LineOfSight(rig.HeadPos, n.rig.HeadPos)) continue;
                    EngageTarget(n.dmg);
                    break;
                }
            }

            if (target != null)
            {
                bool isPlayer = target == player;
                var tp = isPlayer ? Game.Cam.transform.position : target.transform.position + Vector3.up * 1.4f;
                bool los = (!isPlayer || seesPlayer || Util.LineOfSight(rig.HeadPos, tp)) && blindTimer <= 0f;
                if (los) { lastKnown = tp; lostSightTime = 0f; }
                else lostSightTime += dt;
                if (lostSightTime > 7f) { state = NPCState.Search; stateTimer = 12f; target = null; hasMoveTarget = false; SetDest(lastKnown, 3.5f); }
                if (target != null && target.isDead) { target = null; state = NPCState.Search; stateTimer = 5f; }
            }

            // morale
            if (state == NPCState.Combat && dmg.Fraction < 0.2f && archetype == Archetype.Grunt && faction != FactionId.Helix && Random.value < 0.02f)
            {
                state = NPCState.Flee; stateTimer = 8f;
            }
        }

        void ThinkCivilian(float dt)
        {
            if (state == NPCState.Flee || state == NPCState.Cower)
            {
                stateTimer -= dt;
                if (stateTimer <= 0f) state = bx >= 0 ? NPCState.Walk : NPCState.Idle;
            }
        }

        public void EngageTarget(Damageable t)
        {
            if (t == null || state == NPCState.Dead) return;
            if (archetype == Archetype.Civilian || archetype == Archetype.Vendor) { Panic(t.transform.position); return; }
            bool wasCalm = state != NPCState.Combat;
            target = t;
            state = NPCState.Combat;
            detection = 1f;
            lastKnown = t.transform.position + Vector3.up * 1.4f;
            if (wasCalm)
            {
                fireCd = Random.Range(0.4f, 0.9f) / Mathf.Max(0.5f, Game.EnemyAccuracyMult);
                moveTimer = 0f;
                if (t == Game.Stats?.dmg && !string.IsNullOrEmpty(groupId)) Spawner.AlertGroup(groupId, t);
                if (Random.value < 0.4f) Game.UI?.Bark(this, Barks.Combat(faction));
            }
        }

        public void Panic(Vector3 from)
        {
            if (state == NPCState.Dead || archetype == Archetype.Vendor && essential) { if (state != NPCState.Dead) { state = NPCState.Cower; stateTimer = 8f; } return; }
            if ((from - transform.position).sqrMagnitude < 25f || Random.value < 0.25f) { state = NPCState.Cower; stateTimer = Random.Range(5f, 9f); }
            else
            {
                state = NPCState.Flee; stateTimer = Random.Range(8f, 14f);
                var away = (transform.position - from).Flat();
                if (bx >= 0)
                {
                    var next = Game.City.SidewalkPoint(bx, bz, loopT + 0.01f);
                    loopDir = Vector3.Dot(next - transform.position, away) >= 0 ? 1 : -1;
                }
                else SetDest(transform.position + away.normalized * 20f, 6f);
            }
            if (Random.value < 0.3f) Game.UI?.Bark(this, Barks.Panic());
        }

        void Act(float dt)
        {
            if (stunTimer > 0f) { Stop(); return; }
            switch (state)
            {
                case NPCState.Walk: SidewalkWalk(dt, 1.4f); break;
                case NPCState.Flee:
                    if (bx >= 0) SidewalkWalk(dt, 5.2f);
                    else MoveTick(dt);
                    break;
                case NPCState.Cower: Stop(); break;
                case NPCState.Idle: Idle(dt); break;
                case NPCState.Suspicious:
                    Stop();
                    FaceTowards(lastKnown, dt * 3f);
                    if (detection < 0.2f) state = NPCState.Idle;
                    break;
                case NPCState.Search:
                    stateTimer -= dt;
                    MoveTick(dt);
                    if (!hasMoveTarget || ArrivedAt(moveTarget, 1.5f))
                    {
                        FaceTowards(transform.position + Quaternion.Euler(0, Time.time * 60f, 0) * Vector3.forward, dt * 2f);
                        if (stateTimer <= 0f) { state = NPCState.Idle; SetDest(home, 2f); }
                    }
                    break;
                case NPCState.Combat: Combat(dt); break;
            }
        }

        void Idle(float dt)
        {
            if (stationary)
            {
                if (Game.HasPlayer && (Game.PlayerPos - transform.position).sqrMagnitude < 36f) FaceTowards(Game.PlayerPos, dt * 3f);
                return;
            }
            MoveTick(dt);
            idleTimer -= dt;
            if (idleTimer <= 0f)
            {
                idleTimer = Random.Range(3f, 9f);
                var r = Random.insideUnitCircle * homeRadius;
                SetDest(home + new Vector3(r.x, 0, r.y), 1.4f);
            }
        }

        void SidewalkWalk(float dt, float spd)
        {
            if (bx < 0) { Idle(dt); return; }
            if (state == NPCState.Walk)
            {
                idleTimer -= dt;
                if (idleTimer < -Random.Range(10f, 30f)) idleTimer = Random.Range(2f, 6f);
                if (idleTimer > 0f) { if (Random.value < 0.01f) FaceTowards(transform.position + Random.onUnitSphere, 1f); return; }
            }
            float per = Game.City.SidewalkPerimeter(bx, bz);
            float nextT = Mathf.Repeat(loopT + loopDir * spd * (crippleTimer > 0 ? 0.5f : 1f) * dt / per, 1f);
            var p = Game.City.SidewalkPoint(bx, bz, nextT) + Vector3.up * 0.15f;
            var d = (p - transform.position).Flat();
            if (d.sqrMagnitude > 0.000001f)
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(d), dt * 8f);
            // stop for anyone directly ahead
            if (state == NPCState.Walk && Physics.SphereCast(transform.position + Vector3.up, 0.3f, transform.forward, out var hit, 1.2f, Layers.ActorAndPlayerMask, QueryTriggerInteraction.Ignore) && hit.collider.transform.root != transform.root)
                return;
            loopT = nextT;
            transform.position = p;
        }

        void Combat(float dt)
        {
            if (target == null) { state = NPCState.Search; stateTimer = 8f; return; }
            bool isPlayer = target == Game.Stats?.dmg;
            var tpos = isPlayer ? Game.PlayerPos : target.transform.position;
            var aimPoint = isPlayer ? Game.Cam.transform.position - Vector3.up * 0.25f : target.transform.position + Vector3.up * 1.3f;
            float dist = Vector3.Distance(transform.position, tpos);
            bool los = lostSightTime <= 0.01f;
            FaceTowards(los ? aimPoint : lastKnown, dt * 8f);

            // movement decisions
            moveTimer -= dt;
            if (!stationary && moveTimer <= 0f)
            {
                moveTimer = Random.Range(1.6f, 3.4f);
                if (Melee) SetDest(tpos, 5.5f);
                else
                {
                    float pref = PreferredRange;
                    var dest = PickTacticalSpot(tpos, aimPoint, pref);
                    SetDest(dest, dist > pref * 1.5f ? 4.5f : 3.2f);
                }
            }
            if (Melee && !stationary && dist > 1.4f) { SetDest(tpos, 5.5f * (crippleTimer > 0 ? 0.5f : 1f)); }
            MoveTick(dt);

            // attacks
            if (meleeT >= 0f)
            {
                meleeT += dt / 0.6f;
                if (meleeT > 0.5f && meleeT - dt / 0.6f <= 0.5f && dist < 2.2f)
                {
                    float dmgAmt = (archetype == Archetype.Bruiser ? 28f : 16f) * LevelMult;
                    target.ApplyDamage(new DamageInfo { amount = dmgAmt, type = DamageType.Melee, point = target.transform.position + Vector3.up, direction = transform.forward, source = gameObject });
                    Game.Audio?.Play3D("punch", target.transform.position, 0.9f);
                    if (isPlayer)
                    {
                        Game.Player.Shake(0.25f);
                        CameraFX.KickFrom(Game.Cam, transform.forward, archetype == Archetype.Bruiser ? 7f : 4f);
                        CameraFX.Flash(new Color(0.6f, 0f, 0f), 0.25f);
                        CameraFX.Chroma(0.3f);
                        if (archetype == Archetype.Bruiser || archetype == Archetype.Boss) CameraFX.HitStop(0.05f);
                    }
                }
                if (meleeT >= 1f) meleeT = -1f;
                return;
            }
            fireCd -= dt;
            if (Melee)
            {
                if (dist < 1.9f && fireCd <= 0f) { meleeT = 0f; fireCd = archetype == Archetype.Bruiser ? 1.3f : 1f; Game.Audio?.Play3D("swing", transform.position, 0.7f); }
                return;
            }
            if (archetype == Archetype.Netrunner && isPlayer && los) { NetrunnerHack(dt); }
            if (reloadTimer > 0f) { reloadTimer -= dt; if (reloadTimer <= 0f) ammo = weaponDef.mag; return; }
            if (los && dist < weaponDef.range * 1.15f && fireCd <= 0f)
            {
                if (burstLeft <= 0) burstLeft = archetype == Archetype.Heavy ? Random.Range(6, 12) : weaponDef.auto ? Random.Range(3, 7) : Random.Range(1, 3);
                Shoot(aimPoint, dist, isPlayer);
                burstLeft--;
                fireCd = burstLeft > 0 ? 1f / weaponDef.fireRate : Random.Range(0.8f, 1.8f) * (archetype == Archetype.Sniper ? 2.2f : 1f);
                ammo--;
                if (ammo <= 0) { reloadTimer = weaponDef.reload * 1.2f; burstLeft = 0; }
            }
            // grenades against campers
            grenadeTimer -= dt;
            if (!los && grenadeTimer <= 0f && (archetype == Archetype.Grunt || archetype == Archetype.Heavy || archetype == Archetype.Officer) && dist < 30f)
            {
                grenadeTimer = Random.Range(10f, 18f);
                if (Random.value < 0.45f)
                {
                    var from = rig.HeadPos + transform.forward * 0.5f;
                    var v = BallisticVelocity(from, lastKnown, 1.1f);
                    Grenade.Throw(from, v, faction == FactionId.Helix && Random.value < 0.3f, gameObject);
                    Game.UI?.Bark(this, "Grenade out!");
                }
            }
        }

        float LevelMult => 1f + (level - 1) * 0.09f;

        void Shoot(Vector3 aimPoint, float dist, bool isPlayer)
        {
            var muzzle = rig.MuzzlePos;
            float acc = archetype switch { Archetype.Sniper => 0.85f, Archetype.Boss => 0.6f, Archetype.Heavy => 0.38f, Archetype.Gunner => 0.5f, _ => 0.42f };
            acc *= Game.EnemyAccuracyMult * (1f - Mathf.Clamp01(dist / weaponDef.range) * 0.5f);
            if (crippleTimer > 0f) acc *= 0.4f;
            if (isPlayer)
            {
                float pv = Game.Player.Velocity.Flat().magnitude;
                acc *= Mathf.Lerp(1f, 0.55f, pv / 8f);
                if (Game.Player.Crouching) acc *= 0.85f;
                if (Game.Stats.HasBuff("camo")) acc *= 0.25f;
                if (Game.Player.InVehicle) acc *= 0.7f;
            }
            for (int p = 0; p < weaponDef.pellets; p++)
            {
                bool hit = Random.value < acc / Mathf.Max(1f, weaponDef.pellets * 0.35f);
                Vector3 end = aimPoint;
                if (hit)
                {
                    end = aimPoint + Random.insideUnitSphere * 0.15f;
                    if (!Util.LineOfSight(muzzle, end)) hit = false;
                }
                if (hit)
                {
                    float d = weaponDef.damage * LevelMult * 0.55f;
                    target.ApplyDamage(new DamageInfo { amount = d, type = weaponDef.damageType, point = end, direction = (end - muzzle).normalized, source = gameObject });
                }
                else
                {
                    var miss = aimPoint + Random.insideUnitSphere * Mathf.Lerp(0.8f, 2.5f, dist / weaponDef.range);
                    var dir = (miss - muzzle).normalized;
                    end = muzzle + dir * weaponDef.range;
                    if (Physics.Raycast(muzzle, dir, out var rh, weaponDef.range, Layers.WorldMask, QueryTriggerInteraction.Ignore))
                    {
                        end = rh.point;
                        Game.Fx?.Impact(rh.point, rh.normal, 0);
                    }
                    if (isPlayer && Vector3.Distance(Game.Cam.transform.position, end) < 4f) Game.UI?.NearMiss();
                }
                if (p < 2) Game.Fx?.Tracer(muzzle, end, new Color(1f, 0.6f, 0.3f));
            }
            Game.Fx?.MuzzleFlash(muzzle, transform.forward, weaponDef.accent);
            Game.Audio?.Play3D(weaponDef.sound == "sniper" || weaponDef.sound == "shotgun" || weaponDef.sound == "revolver" ? weaponDef.sound : "enemy_shot", muzzle, 0.9f, Random.Range(0.9f, 1.1f), 4f, 180f);
        }

        void NetrunnerHack(float dt)
        {
            if (hackChargeT < 0f)
            {
                if (Random.value < 0.01f) { hackChargeT = 0f; Game.UI?.IncomingHack(this, 0f); Game.Audio?.Play2D("hack_start", 0.6f); }
                return;
            }
            hackChargeT += dt / 3.5f;
            Game.UI?.IncomingHack(this, hackChargeT);
            if (hackChargeT >= 1f)
            {
                hackChargeT = -1f;
                Game.Stats.dmg.ApplyDamage(new DamageInfo { amount = 22f * LevelMult, type = DamageType.Hack, point = Game.PlayerPos, source = gameObject });
                Game.Stats.UseRam(1f);
                Game.UI?.Glitch(0.8f);
                Game.Audio?.Play2D("glitch");
            }
        }

        public bool HackInProgress => hackChargeT >= 0f;
        public float HackProgress => hackChargeT;

        static Vector3 BallisticVelocity(Vector3 from, Vector3 to, float time)
        {
            var g = Physics.gravity;
            return (to - from - 0.5f * g * time * time) / time;
        }

        Vector3 PickTacticalSpot(Vector3 tpos, Vector3 aimPoint, float pref)
        {
            var best = transform.position;
            float bestScore = float.MinValue;
            var from = (transform.position - tpos).Flat();
            if (from.sqrMagnitude < 0.01f) from = Vector3.forward;
            float baseAng = Mathf.Atan2(from.z, from.x);
            for (int i = 0; i < 6; i++)
            {
                float a = baseAng + Random.Range(-1.1f, 1.1f);
                float r = pref * Random.Range(0.75f, 1.25f);
                var cand = tpos + new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * r;
                if (NavMesh.SamplePosition(cand, out var hit, 3f, NavMesh.AllAreas)) cand = hit.position;
                else if (agent != null) continue;
                bool standLos = Util.LineOfSight(cand + Vector3.up * 1.6f, aimPoint);
                bool crouchBlocked = !Util.LineOfSight(cand + Vector3.up * 0.8f, aimPoint);
                float score = (standLos ? 2f : -1f) + (crouchBlocked ? 1.5f : 0f) - Mathf.Abs(Vector3.Distance(cand, tpos) - pref) * 0.1f - Vector3.Distance(cand, transform.position) * 0.05f;
                if (score > bestScore) { bestScore = score; best = cand; }
            }
            return best;
        }

        // ------------------------------------------------------------------ movement
        void SetDest(Vector3 p, float spd)
        {
            moveTarget = p; hasMoveTarget = true; speed = spd * (crippleTimer > 0 ? 0.5f : 1f);
            TryAttachAgent();
            if (agent != null && agent.isOnNavMesh)
            {
                agent.speed = speed;
                agent.SetDestination(p);
            }
        }

        void Stop()
        {
            hasMoveTarget = false;
            if (agent != null && agent.isOnNavMesh) agent.ResetPath();
        }

        bool ArrivedAt(Vector3 p, float r) => (transform.position - p).Flat().sqrMagnitude < r * r;

        void MoveTick(float dt)
        {
            if (!hasMoveTarget || stationary) return;
            if (agent != null)
            {
                if (!agent.isOnNavMesh)
                {
                    // the local navmesh moved away from us: try to re-snap, otherwise drop back to steering
                    if (NavMesh.SamplePosition(transform.position, out var h, 3f, NavMesh.AllAreas)) agent.Warp(h.position);
                    else { Destroy(agent); agent = null; }
                    return;
                }
                if (state != NPCState.Combat && agent.velocity.sqrMagnitude > 0.1f)
                    transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(agent.velocity.Flat().normalized), dt * 8f);
                if (!agent.pathPending && agent.remainingDistance < 0.7f) hasMoveTarget = false;
                return;
            }
            var d = (moveTarget - transform.position).Flat();
            if (d.magnitude < 0.6f) { hasMoveTarget = false; return; }
            var dir = d.normalized;
            // basic obstacle avoidance
            if (Physics.SphereCast(transform.position + Vector3.up * 0.9f, 0.35f, dir, out var hit, 1.5f, Layers.WorldMask, QueryTriggerInteraction.Ignore))
                dir = Vector3.Cross(Vector3.up, hit.normal).normalized * (Vector3.Dot(Vector3.Cross(Vector3.up, hit.normal), dir) >= 0 ? 1 : -1);
            var np = transform.position + dir * speed * dt;
            if (Physics.Raycast(np + Vector3.up * 1.5f, Vector3.down, out var g, 3f, Layers.WorldMask, QueryTriggerInteraction.Ignore)) np.y = g.point.y;
            transform.position = np;
            if (state != NPCState.Combat) transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(dir), dt * 8f);
        }

        void FaceTowards(Vector3 p, float k)
        {
            var d = (p - transform.position).Flat();
            if (d.sqrMagnitude < 0.01f) return;
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(d), Mathf.Clamp01(k));
        }

        // ------------------------------------------------------------------ reactions
        void OnNoise(Vector3 pos, float radius, GameObject src)
        {
            if (state == NPCState.Dead || src == gameObject) return;
            float d2 = (pos - transform.position).sqrMagnitude;
            if (d2 > radius * radius) return;
            bool fromPlayer = Game.Player != null && src == Game.Player.gameObject;
            if (archetype == Archetype.Civilian || archetype == Archetype.Vendor)
            {
                if (radius > 25f && state != NPCState.Cower && state != NPCState.Flee) Panic(pos);
                return;
            }
            if (state == NPCState.Combat) return;
            if (fromPlayer && IsHostileToPlayer)
            {
                lastKnown = pos;
                if (radius > 25f && d2 < 30f * 30f) EngageTarget(Game.Stats.dmg);
                else { state = NPCState.Search; stateTimer = 12f; SetDest(pos, 3.5f); detection = Mathf.Max(detection, 0.5f); }
            }
        }

        void OnDamaged(DamageInfo info)
        {
            ReactToHit(info);
            if (info.source == null) return;
            var src = info.source.GetComponent<Damageable>();
            bool fromPlayer = info.fromPlayer || (Game.Player != null && info.source == Game.Player.gameObject);
            if (fromPlayer)
            {
                if (faction == FactionId.Civilian || faction == FactionId.Police)
                    GameEvents.RaiseCrime(CrimeType.Assault, transform.position);
                else Factions.Provoke(faction);
                if (src == null) src = Game.Stats?.dmg;
            }
            Game.UI?.ShowEnemyHealth(this);
            if (archetype == Archetype.Civilian || archetype == Archetype.Vendor) { Panic(info.source.transform.position); return; }
            if (src != null && !src.isDead) EngageTarget(src);
        }

        void OnDied(DamageInfo info)
        {
            state = NPCState.Dead;
            hackChargeT = -1f;
            if (agent != null) Destroy(agent);
            var force = info.direction.normalized * (8f + info.force * 2f) + Vector3.up * 2f;
            if (info.type == DamageType.Explosive) force = info.direction.normalized * 40f + Vector3.up * 25f;
            if (info.type == DamageType.Vehicle) force = info.direction * 30f + Vector3.up * 12f;
            rig.Ragdoll(force, info.point);
            bool byPlayer = info.fromPlayer || (Game.Player != null && info.source == Game.Player.gameObject);
            if (byPlayer)
            {
                if (faction == FactionId.Civilian || faction == FactionId.Police) GameEvents.RaiseCrime(CrimeType.Murder, transform.position);
                if (archetype != Archetype.Civilian && archetype != Archetype.Vendor)
                {
                    int xp = Mathf.RoundToInt((archetype == Archetype.Boss ? 250 : archetype == Archetype.Heavy ? 70 : 35) * (1f + level * 0.12f));
                    if (info.stealth) xp = Mathf.RoundToInt(xp * 1.3f);
                    Game.Stats?.AddXP(xp);
                    Game.Stats?.OnKill(this, info);
                    Loot.RollEnemy(this);
                    if (faction != FactionId.Police) Game.Stats?.AddCred(archetype == Archetype.Boss ? 15 : 1);
                }
                Factions.AddRep(faction, -2);
            }
            GameEvents.RaiseNpcKilled(this, info);
            foreach (var n in all)
                if (n != this && (n.transform.position - transform.position).sqrMagnitude < 400f && (n.archetype == Archetype.Civilian)) n.Panic(transform.position);
            Destroy(gameObject, 0.05f);
        }

        /// <summary>Body language for a hit: the head snaps, the face winces, skin bruises, cuts and bullet wounds bleed.</summary>
        void ReactToHit(DamageInfo info)
        {
            if (rig == null || info.amount < 3f || dmg.isDead && state == NPCState.Dead) return;
            var dir = info.direction.sqrMagnitude > 0.001f ? info.direction.normalized : -transform.forward;
            bool head = info.headshot || info.point.y > rig.head.position.y + 0.04f;
            float power = Mathf.Clamp(info.amount / (info.type == DamageType.Melee ? 22f : 35f), 0.25f, 1.5f);
            rig.React(dir, info.point, power, head, !head);
            if (Game.Settings != null && !Game.Settings.gore) return;
            var inj = rig.injury;
            if (inj == null || rig.FarFromCamera) return;
            if (info.type == DamageType.Melee)
            {
                if (head) inj.Register(inj.HeadZoneAt(info.point), Mathf.Clamp01(info.amount / 40f), 0.25f);
                else inj.Register(inj.BodyZoneAt(info.point), Mathf.Clamp01(info.amount / 50f));
                if (head) Game.Fx?.Sweat(rig.HeadPos, dir, 10);
            }
            else if (info.type == DamageType.Ballistic && !dmg.isRobotic)
            {
                var bone = rig.NearestBone(info.point);
                inj.Wound(info.point, -dir, bone, 0.035f + power * 0.03f);
                if (bone == rig.thighL || bone == rig.thighR || bone == rig.kneeL || bone == rig.kneeR) Cripple(4f);
            }
        }

        // ------------------------------------------------------------------ status effects from hacks / weapons
        public void Stun(float t) { stunTimer = Mathf.Max(stunTimer, t); }
        public void Blind(float t) { blindTimer = Mathf.Max(blindTimer, t); detection = 0f; }
        public void Cripple(float t) { crippleTimer = Mathf.Max(crippleTimer, t); }
        public void Reveal(float t) { revealTimer = Mathf.Max(revealTimer, t); }
        public void ApplyBleed(float total) { bleedLeft += total; bleedRate = Mathf.Max(bleedRate, total / 4f); }
        public void Distract(Vector3 p) { if (state != NPCState.Combat) { state = NPCState.Search; stateTimer = 8f; SetDest(p, 2.5f); } }
        public bool Unaware => state != NPCState.Combat && detection < 0.6f;

        /// <summary>Silent takedown from behind.</summary>
        public void Takedown(bool lethal)
        {
            var info = new DamageInfo { amount = 99999f, type = DamageType.Melee, point = transform.position + Vector3.up, direction = transform.forward, source = Game.Player.gameObject, fromPlayer = true, stealth = true, force = 1f };
            dmg.invulnerable = false;
            dmg.ApplyDamage(info);
        }

        public bool CanBeTakenDown(Transform player)
        {
            if (state == NPCState.Dead || essential || archetype == Archetype.Boss) return false;
            var toPlayer = (player.position - transform.position).Flat().normalized;
            return Unaware && Vector3.Dot(transform.forward, toPlayer) < -0.2f;
        }
    }

    public class TalkInteractable : Interactable
    {
        public NPC npc;
        public override string Prompt => "Talk to " + (npc != null ? npc.displayName : "");
        public override bool CanInteract => npc != null && npc.state != NPCState.Dead && npc.state != NPCState.Combat;
        public override void Interact()
        {
            if (npc == null) return;
            Game.Dialogue?.TalkTo(npc);
        }
    }

    public static class Barks
    {
        static readonly string[] jackal = { "Chrome or die!", "Fresh meat!", "Light 'em up!", "You picked the wrong block, choom!" };
        static readonly string[] lotus = { "Madame sends her regards.", "Nothing personal.", "Clean this up." };
        static readonly string[] helix = { "Hostile engaged.", "Containment protocol.", "Asset is armed - lethal force authorised." };
        static readonly string[] raiders = { "Strip 'em for parts!", "The Scar eats tonight!", "Hahaha! Run!" };
        static readonly string[] police = { "NBPD! Drop it!", "Suspect is armed!", "Requesting backup, Precinct 12!" };
        static readonly string[] panic = { "Run!", "Somebody call the NBPD!", "Oh no, no, no...", "Don't shoot! I got kids!", "Get down!" };
        public static string Combat(FactionId f) => f switch
        {
            FactionId.Jackals => jackal[Random.Range(0, jackal.Length)],
            FactionId.Lotus => lotus[Random.Range(0, lotus.Length)],
            FactionId.Helix => helix[Random.Range(0, helix.Length)],
            FactionId.Raiders => raiders[Random.Range(0, raiders.Length)],
            FactionId.Police => police[Random.Range(0, police.Length)],
            _ => "Hey!"
        };
        public static string Panic() => panic[Random.Range(0, panic.Length)];
    }
}
