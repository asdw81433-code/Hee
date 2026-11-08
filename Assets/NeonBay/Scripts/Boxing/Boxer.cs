using UnityEngine;

namespace NeonBay
{
    public enum BoxerState { Intro, Fighting, Clinch, Down, GettingUp, KO, Corner, Celebrate, Dejected }

    /// <summary>
    /// One fighter in the ring: vitals (head/body health, stamina, fatigue), punch timeline with combos and power
    /// shots, guard / slip / duck / parry defence, footwork with planted feet and IK, procedural boxing animation,
    /// hit reactions, knockdowns into a real ragdoll and recovery.
    /// </summary>
    public class Boxer : MonoBehaviour
    {
        public FighterProfile profile;
        public bool isPlayer;
        public HumanoidRig rig;
        public Boxer opponent;
        public BoxingMatch match;
        public BoxerState state = BoxerState.Intro;
        public int corner; // 0 red, 1 blue

        // ----------------------------------------------------------- vitals
        public float headHP = 100f, headCap = 100f, bodyHP = 100f, stamina = 100f, staminaMax = 100f;
        public float recentHead, rockedT, openT, counterWindow, lastHitTime = -99f;
        public int kdRound, kdTotal;
        public RoundStats round = new RoundStats(), total = new RoundStats();
        public float hype;

        // ----------------------------------------------------------- commands (written by controller every frame)
        public Vector2 move;
        public Vector3 lean;        // x slip (-1..1), y duck (-1..0), z pull back (-1..0) or lean in (+)
        public int guard;           // 0 normal, 1 high, 2 low
        public bool wantClinch, wantTaunt;
        public Vector3? forcedTarget; // referee sends you to a corner
        float guardPressedT = 9f;
        int lastGuard;

        // ----------------------------------------------------------- punch
        PunchDef cur; bool curBody, curPower; float curT, curScale = 1f; bool impactDone; Vector3 curTargetLocal;
        PunchDef queued; bool qBody, qPower; float queuedAge;
        int combo; float lastPunchEnd = -9f; bool lastLead;
        public PunchDef Current => cur;
        public bool CurrentBody => curBody;
        public bool CurrentPower => curPower;
        public bool Punching => cur != null;
        float Windup => cur == null ? 0f : (cur.windup + (curPower ? 0.11f : 0f) + (curBody ? 0.03f : 0f)) * curScale;
        float Extend => cur == null ? 0f : cur.extend * curScale;
        float Recover => cur == null ? 0f : (cur.recover + (curPower ? 0.09f : 0f) + (whiffed ? 0.12f : 0f)) * curScale;
        public bool WindingUp => cur != null && curT < Windup;
        public float TimeToImpact => cur == null || impactDone ? 99f : Mathf.Max(0f, Windup + Extend - curT);
        public bool InRecovery => cur != null && impactDone;
        bool whiffed;

        // ----------------------------------------------------------- body motion
        Vector3 vel;
        float yaw;
        public Vector3 leanCur;
        float guardHi, guardLo, bounce, clock, tauntT, stateT;
        Vector3 footL, footR, fromL, fromR, toL, toR; float stepL = -1f, stepR = -1f;
        float liverT = -1f;
        bool feetInit;
        public bool OnRopes { get; private set; }
        public float RingCenterDist { get; private set; }
        MaterialPropertyBlock sweatMpb;
        float sweat;
        public float Danger => Mathf.Clamp01(1f - headHP / 45f) * 0.7f + Mathf.Clamp01(rockedT) * 0.3f;

        // ----------------------------------------------------------- derived stats
        FighterStats S => profile.stats;
        public float PowerFactor => 0.72f + S.power / 100f * 0.65f;
        public float SpeedFactor => 1.16f - S.speed / 100f * 0.32f;
        public float ChinFactor => (1.28f - S.chin / 100f * 0.55f) * (rig != null && rig.injury != null ? rig.injury.ChinFactor : 1f);
        public float StaminaFactor => Mathf.Lerp(0.5f, 1f, Mathf.Clamp01(stamina / 45f));
        public float Fatigue => Mathf.Clamp01(1f - stamina / 60f) * 0.7f + Mathf.Clamp01(1f - staminaMax / 100f) * 0.5f;
        public bool Rocked => rockedT > 0f;
        public bool CanAct => (state == BoxerState.Fighting) && openT <= 0f;
        public bool IsDown => state == BoxerState.Down || state == BoxerState.KO;
        public Vector3 HeadPoint => rig.head.TransformPoint(new Vector3(0, 0.12f, 0.06f));
        public Vector3 ChinPoint => rig.head.TransformPoint(new Vector3(0, 0.05f, 0.09f));
        public Vector3 BodyPoint(int side) => rig.chest.TransformPoint(new Vector3(0.08f * side, 0.02f, 0.13f));
        public int LeadSign => profile.southpaw ? 1 : -1;
        float StanceYaw => profile.southpaw ? -28f : 28f;

        public static Boxer Create(FighterProfile p, bool player, Vector3 pos, float yawDeg, float canvasY)
        {
            var go = new GameObject("Boxer_" + p.id);
            go.transform.SetPositionAndRotation(new Vector3(pos.x, canvasY, pos.z), Quaternion.Euler(0, yawDeg, 0));
            var b = go.AddComponent<Boxer>();
            b.profile = p; b.isPlayer = player; b.yaw = yawDeg;
            var look = p.look.Clone();
            look.outfit = 1;
            var krb = go.AddComponent<Rigidbody>();
            krb.isKinematic = true; krb.useGravity = false;
            var dmg = go.AddComponent<Damageable>();
            dmg.Init(9999f);
            dmg.invulnerable = true;
            b.rig = HumanoidRig.Build(go.transform, look, dmg, false, 0);
            if (b.rig.injury != null) b.rig.injury.canHeal = false;
            if (player && b.rig.injury != null) b.rig.injury.Load(Boxing.PlayerInjuries);
            b.staminaMax = Mathf.Lerp(92f, 108f, p.stats.engine / 100f);
            b.stamina = b.staminaMax;
            if (player && b.rig.injury != null)
            {
                // carrying damage into a fight hurts
                b.headCap = 100f - b.rig.injury.concussion * 35f; b.headHP = b.headCap;
                b.staminaMax -= b.rig.injury.bodyTrauma * 20f; b.stamina = b.staminaMax;
            }
            b.sweatMpb = new MaterialPropertyBlock();
            return b;
        }

        // ================================================================== commands
        public void QueuePunch(PunchType t, bool body, bool power)
        {
            var def = Boxing.Get(t);
            if (state != BoxerState.Fighting) return;
            if (cur == null && openT <= 0f) { StartPunch(def, body, power); return; }
            // buffer the next punch for combos
            queued = def; qBody = body; qPower = power; queuedAge = 0f;
        }

        void StartPunch(PunchDef def, bool body, bool power)
        {
            bool alternate = combo > 0 && def.lead != lastLead;
            bool chained = Time.time - lastPunchEnd < 0.32f;
            combo = chained ? combo + 1 : 1;
            cur = def; curBody = body; curPower = power; curT = 0f; impactDone = false; whiffed = false;
            float speed = SpeedFactor * (Rocked ? 1.25f : 1f) * Mathf.Lerp(1.3f, 1f, Mathf.Clamp01(stamina / 35f));
            if (chained && alternate) speed *= 0.82f;
            if (rig.injury != null) speed *= 1f + rig.injury.ArmDamage(def.lead == !profile.southpaw) * 0.2f;
            curScale = speed;
            float cost = def.stamina * (power ? 1.6f : 1f) * (body ? 1.1f : 1f);
            stamina = Mathf.Max(0f, stamina - cost);
            staminaMax = Mathf.Max(45f, staminaMax - cost * 0.035f);
            round.thrown++; total.thrown++;
            if (def.type == PunchType.Jab) { round.jabsThrown++; total.jabsThrown++; }
            else { round.powerThrown++; total.powerThrown++; }
            lastLead = def.lead;
            if (Game.Audio != null) Game.Audio.Play3D("whiff", HeadPoint, 0.25f + (power ? 0.2f : 0f), Random.Range(0.9f, 1.15f) * (power ? 0.85f : 1f), 2f, 25f);
        }

        /// <summary>Called by the match when this fighter's punch lands or misses.</summary>
        public void OnPunchResult(HitResult r)
        {
            if (r == HitResult.Miss || r == HitResult.Slipped)
            {
                whiffed = true;
                stamina = Mathf.Max(0f, stamina - (cur != null ? cur.stamina * 0.45f : 2f));
            }
            if (r == HitResult.Parried) openT = 0.42f;
            if (r == HitResult.Slipped) openT = Mathf.Max(openT, 0.18f);
        }

        // ================================================================== being hit
        public HitResult Evaluate(Boxer attacker, PunchDef def, bool body, out float mult)
        {
            mult = 1f;
            float slip = Mathf.Abs(leanCur.x), duck = -Mathf.Min(0f, leanCur.y), back = -Mathf.Min(0f, leanCur.z);
            if (!body)
            {
                switch (def.kind)
                {
                    case PunchKind.Straight:
                        if (slip > 0.55f || duck > 0.6f || back > 0.78f) return HitResult.Slipped;
                        break;
                    case PunchKind.Hook:
                        if (duck > 0.55f || back > 0.85f) return HitResult.Slipped;
                        if (slip > 0.5f) mult *= 1.15f; // slipped into the hook
                        break;
                    case PunchKind.Uppercut:
                        if (back > 0.6f || slip > 0.72f) return HitResult.Slipped;
                        if (duck > 0.4f) mult *= 1.3f; // ducked into the uppercut
                        break;
                }
                if (leanCur.z > 0.3f) mult *= 1.12f; // walking into it
            }
            else if (back > 0.9f && def.kind == PunchKind.Straight) return HitResult.Slipped;

            bool parryable = !body && def.kind != PunchKind.Uppercut;
            if (parryable && guard == 1 && guardPressedT < 0.16f && stamina > 6f) return HitResult.Parried;

            bool blocking = (guard == 1 && !body) || (guard == 2 && body);
            if (blocking)
            {
                float frac = body ? 0.22f : def.kind == PunchKind.Straight ? 0.12f : def.kind == PunchKind.Hook ? 0.28f : 0.6f;
                if (stamina < 8f) frac = Mathf.Min(1f, frac * 2.6f); // arms too heavy to hold the guard
                mult *= frac;
                return HitResult.Blocked;
            }
            if (!body && guard == 0 && def.kind == PunchKind.Straight && Random.value < 0.25f + S.defense / 400f) { mult *= 0.55f; return HitResult.Blocked; }
            if (body && guard == 1) mult *= 1.2f; // high guard leaves the body open
            if (InRecovery || WindingUp) { mult *= 1.15f; } // caught mid-punch
            return HitResult.Clean;
        }

        /// <summary>Apply a resolved hit. Returns true when it causes a knockdown.</summary>
        public bool TakeHit(Boxer attacker, PunchDef def, bool body, bool power, float damage, HitResult res, Vector3 point, Vector3 dir, bool counter)
        {
            lastHitTime = Time.time;
            float powerK = Mathf.Clamp(damage / 14f, 0.15f, 1.6f);
            if (res == HitResult.Blocked)
            {
                stamina = Mathf.Max(0f, stamina - def.stamina * 0.9f * (power ? 1.4f : 1f));
                if (!body) headHP -= damage * 0.5f;
                else bodyHP -= damage * 0.5f;
                rig.React(dir, point, powerK * 0.3f, !body, body);
                vel += dir.Flat().normalized * 0.4f * powerK;
                counterWindow = 0.3f;
                return false;
            }
            bool kd = false;
            float sev = Mathf.Clamp01(damage / 28f) * (counter ? 1.3f : 1f) * (power ? 1.2f : 1f);
            if (!body)
            {
                float d = damage * ChinFactor;
                headHP -= d;
                headCap = Mathf.Max(30f, headCap - d * 0.16f);
                recentHead += d;
                stamina = Mathf.Max(0f, stamina - d * 0.25f);
                float rockLine = Mathf.Lerp(14f, 24f, S.chin / 100f) / ChinFactor;
                if (recentHead > rockLine || headHP < 28f && d > 6f) Rock(Mathf.Lerp(1.6f, 3.6f, Mathf.Clamp01(recentHead / 50f)));
                // injuries
                if (rig.injury != null && (Game.Settings == null || Game.Settings.gore))
                {
                    int side = Vector3.Dot(dir, transform.right) > 0f ? -1 : 1; // punch travelling to my right lands on my left side
                    InjuryZone z;
                    switch (def.kind)
                    {
                        case PunchKind.Hook: z = Random.value < 0.5f ? (side < 0 ? InjuryZone.CheekL : InjuryZone.CheekR) : Random.value < 0.5f ? (side < 0 ? InjuryZone.BrowL : InjuryZone.BrowR) : (side < 0 ? InjuryZone.EyeL : InjuryZone.EyeR); break;
                        case PunchKind.Uppercut: z = Random.value < 0.6f ? InjuryZone.Chin : InjuryZone.Mouth; break;
                        default:
                            float r = Random.value;
                            z = r < 0.35f ? InjuryZone.Nose : r < 0.55f ? InjuryZone.Mouth : (attacker.profile.southpaw == (def.lead) ? InjuryZone.EyeR : InjuryZone.EyeL);
                            break;
                    }
                    rig.injury.Register(z, sev * 0.75f, def.kind == PunchKind.Hook ? 0.1f : 0.04f + (power ? 0.05f : 0f));
                }
                // knockdown rules: out of head health, or a flush counter on a hurt fighter
                if (headHP <= 0f) kd = true;
                else if (Rocked && (counter || power) && d > 6f && headHP < 50f && Random.value < 0.3f) kd = true;
                else if (counter && power && d > 9f && headHP < 40f && Random.value < 0.2f) kd = true;
                if (Game.Fx != null)
                {
                    Game.Fx.Sweat(rig.head.TransformPoint(new Vector3(0, 0.15f, 0)), dir, Mathf.RoundToInt(10 + powerK * 26 + sweat * 20));
                    if (rig.injury != null && (rig.injury.Bleeding || powerK > 1f)) Game.Fx.BloodSpray(point, dir, Mathf.RoundToInt(2 + powerK * 5));
                }
            }
            else
            {
                float d = damage * (rig.injury != null ? rig.injury.BodyFactor : 1f);
                bodyHP -= d;
                stamina = Mathf.Max(0f, stamina - d * 1.15f);
                staminaMax = Mathf.Max(40f, staminaMax - d * 0.22f);
                int side = Vector3.Dot(dir, transform.right) > 0f ? -1 : 1;
                bool liver = side > 0 && def.kind == PunchKind.Hook; // hook landing on my right side = the liver
                if (rig.injury != null) rig.injury.Register(liver ? InjuryZone.Liver : def.kind == PunchKind.Straight ? InjuryZone.Stomach : side < 0 ? InjuryZone.RibsL : InjuryZone.RibsR, sev);
                if (liver && bodyHP < 45f && d > 8f && Random.value < 0.55f) liverT = 0.55f; // delayed collapse
                if (bodyHP <= 0f) { liverT = 0.3f; bodyHP = 8f; }
            }
            rig.React(dir, point, powerK, !body, body);
            vel += dir.Flat().normalized * (0.6f + powerK * 0.9f);
            if (rig.face != null) { rig.face.pain = Mathf.Max(rig.face.pain, powerK * 0.6f); }
            return kd;
        }

        public void Rock(float t)
        {
            if (rockedT <= 0f && Game.Audio != null && isPlayer) Game.Audio.Play2D("tinnitus", 0.25f);
            rockedT = Mathf.Max(rockedT, t);
            if (cur != null && !impactDone) cur = null;
        }

        // ================================================================== knockdown / recovery
        public void KnockDown(Vector3 dir, Vector3 point, float power, bool ko)
        {
            cur = null; queued = null;
            state = ko ? BoxerState.KO : BoxerState.Down;
            kdRound++; kdTotal++;
            stateT = 0f;
            var impulse = (dir.Flat().normalized * (110f + power * 120f) + Vector3.up * (40f + power * 30f)) * (ko ? 1.25f : 1f);
            rig.Knockdown(impulse, point, ko ? 0.55f : 0.3f);
            if (rig.face != null) { rig.face.ko = ko; rig.face.daze = 1f; }
        }

        public void GetUp()
        {
            if (state != BoxerState.Down) return;
            rig.RecoverFromRagdoll(rig.transform, CanvasY, 1.1f);
            // the ragdoll recovery moved the rig root; bring the boxer root along
            var rp = rig.transform.position; var rr = rig.transform.rotation;
            transform.position = new Vector3(rp.x, CanvasY, rp.z);
            yaw = rr.eulerAngles.y;
            transform.rotation = Quaternion.Euler(0, yaw, 0);
            rig.transform.localPosition = Vector3.zero; rig.transform.localRotation = Quaternion.identity;
            state = BoxerState.GettingUp; stateT = 0f;
            feetInit = false;
            float heart = S.heart / 100f;
            headHP = Mathf.Max(headHP, Mathf.Lerp(28f, 55f, heart) * Mathf.Lerp(1f, 0.6f, (kdTotal - 1) / 3f));
            recentHead = 0f;
            stamina = Mathf.Max(stamina, staminaMax * 0.5f);
            rockedT = 0f;
            if (rig.face != null) rig.face.daze = 0.7f;
        }

        public float CanvasY => match != null ? match.CanvasY : transform.position.y;

        // ================================================================== per-frame
        public void Tick(float dt)
        {
            clock += dt; stateT += dt;
            guardPressedT += dt;
            if (guard == 1 && lastGuard != 1) guardPressedT = 0f;
            lastGuard = guard;
            openT -= dt; counterWindow -= dt;
            recentHead = Mathf.MoveTowards(recentHead, 0f, dt * 7f);
            if (rockedT > 0f) rockedT -= dt;
            hype = Mathf.MoveTowards(hype, 0f, dt * 0.05f);

            // delayed liver shot collapse
            if (liverT > 0f)
            {
                liverT -= dt;
                if (liverT <= 0f && state == BoxerState.Fighting) match?.LiverKnockdown(this);
            }

            if (state == BoxerState.Down || state == BoxerState.KO) return;

            // punch timeline
            if (cur != null)
            {
                curT += dt;
                if (!impactDone && curT >= Windup + Extend)
                {
                    impactDone = true;
                    match?.ResolvePunch(this, cur, curBody, curPower);
                }
                if (cur != null && curT >= Windup + Extend + Recover)
                {
                    cur = null; lastPunchEnd = Time.time;
                    if (queued != null && queuedAge < 0.4f && CanAct) { var q = queued; queued = null; StartPunch(q, qBody, qPower); }
                }
            }
            if (queued != null) { queuedAge += dt; if (queuedAge > 0.4f) queued = null; else if (cur == null && CanAct) { var q = queued; queued = null; StartPunch(q, qBody, qPower); } }

            // recovery of vitals
            bool active = state == BoxerState.Fighting || state == BoxerState.Clinch;
            if (active && cur == null)
            {
                float regen = (9f + S.engine / 100f * 8f) * (1f - (rig.injury != null ? rig.injury.bodyTrauma * 0.4f : 0f)) * (guard == 1 ? 0.6f : 1f) * (state == BoxerState.Clinch ? 1.6f : 1f);
                if (move.sqrMagnitude > 0.1f) regen *= 0.8f;
                stamina = Mathf.Min(staminaMax, stamina + regen * dt);
            }
            if (Time.time - lastHitTime > 3f) headHP = Mathf.Min(headCap, headHP + dt * 0.9f);
            bodyHP = Mathf.Min(100f, bodyHP + dt * 0.15f);

            // lean follows the command with a little lag (that's where timing matters)
            float leanSpeed = Mathf.Lerp(5f, 9f, S.defense / 100f) * (Rocked ? 0.5f : 1f) * Mathf.Lerp(0.7f, 1f, stamina / 100f);
            var leanCmd = state == BoxerState.Fighting ? lean : Vector3.zero;
            if (Punching) leanCmd *= 0.35f;
            leanCur = Vector3.MoveTowards(leanCur, leanCmd, dt * leanSpeed);
            if (Mathf.Abs(leanCur.x) > 0.3f || leanCur.y < -0.3f) stamina = Mathf.Max(0f, stamina - dt * 3f);

            Move(dt);

            // sweat sheen builds up over the fight
            sweat = Mathf.MoveTowards(sweat, Mathf.Clamp01((match != null ? match.Round - 1 : 0) * 0.2f + (1f - stamina / 100f) * 0.4f + 0.2f), dt * 0.05f);
            if (rig.bodyRenderer != null)
            {
                sweatMpb.Clear();
                sweatMpb.SetFloat("_Smoothness", 0.42f + sweat * 0.4f);
                rig.bodyRenderer.SetPropertyBlock(sweatMpb, 0);
            }
            if (rig.face != null)
            {
                rig.face.fatigue = Fatigue;
                rig.face.daze = Mathf.MoveTowards(rig.face.daze, Rocked ? 0.85f : 0f, dt * 0.8f);
                rig.face.anger = Punching && curPower ? 0.8f : 0.15f;
                if (opponent != null && opponent.rig != null) rig.LookAt(opponent.HeadPoint);
            }
        }

        void Move(float dt)
        {
            var pos = transform.position;
            Vector3 toOpp = opponent != null ? (opponent.transform.position - pos).Flat() : transform.forward;
            float dist = toOpp.magnitude;
            var fwd = dist > 0.01f ? toOpp / dist : transform.forward.Flat().normalized;
            var right = Vector3.Cross(Vector3.up, fwd);
            float foot = 0.85f + S.footwork / 100f * 0.35f;
            float speedK = foot * Mathf.Lerp(0.65f, 1f, Mathf.Clamp01(stamina / 40f)) * (Rocked ? 0.45f : 1f) * (cur != null ? 0.45f : 1f) * (guard == 1 ? 0.75f : 1f);
            if (rig.injury != null) speedK *= 1f - rig.injury.LegDamage * 0.3f;
            Vector3 wish;
            if (forcedTarget.HasValue)
            {
                var d = (forcedTarget.Value - pos).Flat();
                wish = d.magnitude > 0.15f ? d.normalized * 1.6f : Vector3.zero;
            }
            else if (state == BoxerState.Fighting || state == BoxerState.GettingUp && stateT > 1.2f)
            {
                var m = Vector2.ClampMagnitude(move, 1f);
                wish = right * m.x * 1.55f + fwd * m.y * (m.y > 0 ? 1.7f : 1.45f);
                wish *= speedK;
                // weight goes forward into straight punches
                if (cur != null && !impactDone && curT > Windup * 0.7f && cur.kind == PunchKind.Straight) wish += fwd * (cur.lead ? 0.7f : 1.2f);
            }
            else wish = Vector3.zero;
            if (Rocked) wish += new Vector3(Mathf.PerlinNoise(clock * 1.3f, 3f) - 0.5f, 0, Mathf.PerlinNoise(5f, clock * 1.1f) - 0.5f) * 1.1f;
            vel = Vector3.MoveTowards(vel, wish, dt * 11f);
            pos += vel * dt;
            // stay out of each other
            if (opponent != null && !opponent.IsDown)
            {
                var sep = (pos - opponent.transform.position).Flat();
                float min = state == BoxerState.Clinch ? 0.42f : 0.58f;
                if (sep.magnitude < min) pos += sep.normalized * (min - sep.magnitude) * 0.55f;
            }
            // ropes
            if (match != null && match.ring != null)
            {
                OnRopes = match.ring.Constrain(ref pos, ref vel, 0.3f);
                RingCenterDist = (pos - match.ring.Center).Flat().magnitude;
            }
            pos.y = CanvasY;
            transform.position = pos;
            // face the opponent
            if (forcedTarget.HasValue && (forcedTarget.Value - pos).Flat().magnitude > 0.3f) fwd = (forcedTarget.Value - pos).Flat().normalized;
            float want = Mathf.Atan2(fwd.x, fwd.z) * Mathf.Rad2Deg;
            float turn = (cur != null ? 300f : 620f) * (Rocked ? 0.5f : 1f);
            if (state == BoxerState.Corner) want = Mathf.Atan2(-transform.position.x + (match != null ? match.ring.Center.x : 0f), -transform.position.z + (match != null ? match.ring.Center.z : 0f)) * Mathf.Rad2Deg;
            yaw = Mathf.MoveTowardsAngle(yaw, want, turn * dt);
            transform.rotation = Quaternion.Euler(0, yaw, 0);
        }

        // ================================================================== animation
        static float Ease(float k) => 1f - (1f - k) * (1f - k) * (1f - k);
        static float Smooth(float k) { k = Mathf.Clamp01(k); return k * k * (3f - 2f * k); }
        static Vector3 Bezier(Vector3 a, Vector3 c, Vector3 b, float t) { float u = 1f - t; return u * u * a + 2f * u * t * c + t * t * b; }

        public void Pose(float dt)
        {
            if (rig == null || rig.ragdolled) return;
            if (state == BoxerState.Down || state == BoxerState.KO) return;
            rig.MarkPosed();
            float sc = rig.Scale;
            var root = transform;
            var fwd = root.forward; var right = root.right; var up = Vector3.up;
            int lead = LeadSign;          // -1 left lead (orthodox)
            float stanceYaw = StanceYaw;

            // --- punch progress
            float twist = 0f, dip = 0f, punchK = 0f, side = 0f;
            if (cur != null)
            {
                float w = Windup, e = Extend, r = Recover;
                float t = curT;
                float wind = t < w ? t / w : 0f;
                float ext = t < w ? 0f : t < w + e ? Ease((t - w) / e) : 1f - Smooth((t - w - e) / r);
                punchK = ext;
                float sign = cur.lead ? -lead : lead; // lead punches rotate the lead shoulder forward
                sign *= profile.southpaw ? -1f : 1f;
                twist = (cur.twist * ext - cur.twist * 0.25f * wind) * (cur.lead ? 1f : -1f) * (profile.southpaw ? -1f : 1f);
                if (curBody) dip = 0.6f * Mathf.Max(ext, wind);
                if (cur.kind == PunchKind.Uppercut) dip = Mathf.Max(dip, 0.4f * wind * (1f - ext) + 0.15f * ext);
                side = sign;
            }

            // --- stance, bounce, lean
            bool tired = stamina < 30f;
            float bounceAmp = (state == BoxerState.Intro || move.sqrMagnitude > 0.05f ? 1f : 0.6f) * (tired ? 0.3f : 1f) * (Rocked ? 0f : 1f);
            bounce += dt * Mathf.PI * 2f * (tired ? 1.3f : 1.9f);
            float bob = Mathf.Abs(Mathf.Sin(bounce)) * 0.016f * bounceAmp;
            var L = leanCur;
            float duck = -Mathf.Min(0f, L.y), back = -Mathf.Min(0f, L.z), fwdLean = Mathf.Max(0f, L.z);
            float wob = Rocked ? Mathf.Sin(clock * 2.3f) * 6f : 0f;
            float hipDrop = 0.075f + duck * 0.2f + dip * 0.1f + (state == BoxerState.GettingUp ? Mathf.Lerp(0.38f, 0f, Smooth(stateT / 1.5f)) : 0f) + (Rocked ? 0.04f : 0f);
            rig.hips.localPosition = new Vector3(L.x * 0.11f, 0.98f - hipDrop + bob, -0.02f - back * 0.06f + fwdLean * 0.04f);
            rig.hips.localRotation = Quaternion.Euler(4f + duck * 10f, stanceYaw * 0.8f + twist * 0.4f, -L.x * 5f + wob * 0.5f);
            rig.torso.localRotation = Quaternion.Euler(7f + duck * 24f + dip * 14f - back * 16f + fwdLean * 8f, twist * 0.25f - stanceYaw * 0.15f, -L.x * 13f + wob);
            rig.chest.localRotation = Quaternion.Euler(4f + duck * 8f - back * 7f + (tired ? 6f : 0f), twist * 0.35f - stanceYaw * 0.3f, -L.x * 9f);
            rig.neck.localRotation = Quaternion.Euler(12f - duck * 6f, 0, 0);
            rig.head.localRotation = Quaternion.Euler(-9f - duck * 10f, 0, 0);

            // --- feet
            UpdateFeet(dt, sc, fwd, right);
            var kneeHint = (fwd + right * lead * -0.2f).normalized;
            rig.LegIK(lead > 0, (lead > 0 ? footR : footL) + up * 0.062f * sc, kneeHint, Quaternion.Euler(0, stanceYaw * 0.55f, 0) * fwd);
            rig.LegIK(lead < 0, (lead < 0 ? footR : footL) + up * 0.062f * sc, (fwd + right * -lead * 0.3f).normalized, Quaternion.Euler(0, stanceYaw * 1.4f + (cur != null && !cur.lead ? -twist * 0.6f : 0f), 0) * fwd);
            // rear heel up
            var rearAnkle = lead < 0 ? rig.ankleR : rig.ankleL;
            rearAnkle.rotation *= Quaternion.Euler(14f, 0, 0);

            // --- arms
            var O = rig.chest.TransformPoint(new Vector3(0, 0.2f, 0.02f));
            float drop = Mathf.Clamp01(Fatigue * 0.7f + (Rocked ? 0.6f : 0f));
            guardHi = Mathf.MoveTowards(guardHi, guard == 1 ? 1f : 0f, dt * 12f);
            guardLo = Mathf.MoveTowards(guardLo, guard == 2 ? 1f : 0f, dt * 12f);
            Vector3 GuardPos(bool isLead)
            {
                float sx = isLead ? lead : -lead;
                Vector3 normal = isLead ? O + fwd * 0.25f * sc + right * sx * 0.07f * sc + up * 0.1f * sc : O + fwd * 0.13f * sc + right * sx * 0.1f * sc + up * 0.13f * sc;
                Vector3 high = O + fwd * (isLead ? 0.15f : 0.12f) * sc + right * sx * 0.065f * sc + up * 0.2f * sc;
                Vector3 low = O + fwd * (isLead ? 0.17f : 0.14f) * sc + right * sx * 0.09f * sc + up * (isLead ? -0.1f : -0.15f) * sc;
                var p = Vector3.Lerp(Vector3.Lerp(normal, high, guardHi), low, guardLo);
                p += up * (-0.15f * drop * sc) + fwd * (0.04f * drop * sc);
                if (state == BoxerState.Intro) p += (right * Mathf.Sin(clock * 3f + (isLead ? 0f : 2f)) * 0.03f + up * Mathf.Sin(clock * 4.3f + sx) * 0.02f) * sc;
                return p;
            }
            for (int k = 0; k < 2; k++)
            {
                bool isLead = k == 0;
                bool rightArm = isLead ? lead > 0 : lead < 0;
                float sx = rightArm ? 1f : -1f;
                var sh = rightArm ? rig.shoulderR : rig.shoulderL;
                var g = GuardPos(isLead);
                var elbowHint = sh.position - up * 0.35f * sc + right * sx * 0.12f * sc - fwd * 0.05f * sc;
                var backHand = (right * sx * 0.75f + fwd * 0.25f + up * 0.2f).normalized;
                Vector3 target = g;
                if (cur != null && cur.lead == isLead)
                {
                    float w = Windup, e = Extend, r = Recover, t = curT;
                    var contact = PunchContact(cur, curBody, sc);
                    var dirP = (contact - sh.position).normalized;
                    var wristAt = contact - dirP * 0.13f * sc;
                    // clamp to reach so a miss leaves the arm fully extended in the air
                    float maxR = 0.545f * sc;
                    if ((wristAt - sh.position).magnitude > maxR) wristAt = sh.position + (wristAt - sh.position).normalized * maxR;
                    Vector3 start = g, ctrl;
                    switch (cur.kind)
                    {
                        case PunchKind.Hook:
                            start = g + right * sx * 0.04f * sc;
                            ctrl = g + right * sx * 0.34f * sc + fwd * 0.12f * sc + up * (curBody ? -0.1f : 0.02f) * sc;
                            elbowHint = sh.position + right * sx * 0.4f * sc + up * 0.2f * sc;
                            backHand = Vector3.Slerp(backHand, up, punchK);
                            break;
                        case PunchKind.Uppercut:
                            start = g - up * 0.06f * sc;
                            ctrl = g - up * 0.22f * sc + fwd * 0.1f * sc + right * -sx * 0.03f * sc;
                            elbowHint = sh.position - up * 0.4f * sc + fwd * 0.1f * sc;
                            backHand = Vector3.Slerp(backHand, fwd, punchK);
                            break;
                        default:
                            ctrl = Vector3.Lerp(g, wristAt, 0.5f) + up * 0.03f * sc;
                            backHand = Vector3.Slerp(backHand, up, punchK * 0.85f);
                            break;
                    }
                    if (t < w) target = Vector3.Lerp(g, start - fwd * 0.035f * sc, Smooth(t / w));
                    else if (t < w + e) target = Bezier(start, ctrl, wristAt, Ease((t - w) / e));
                    else target = Vector3.Lerp(wristAt, g, Smooth((t - w - e) / r));
                }
                else if (state == BoxerState.Clinch && opponent != null)
                {
                    target = opponent.rig.chest.TransformPoint(new Vector3(0.2f * sx, 0.18f, -0.08f));
                    elbowHint = sh.position + right * sx * 0.3f * sc - up * 0.1f * sc;
                }
                else if (state == BoxerState.Celebrate)
                {
                    target = O + up * 0.62f * sc + right * sx * (0.24f + 0.04f * Mathf.Sin(clock * 6f)) * sc + fwd * 0.05f * sc;
                    elbowHint = sh.position + right * sx * 0.4f * sc;
                }
                else if (state == BoxerState.Dejected || tauntT > 0f)
                {
                    target = sh.position - up * 0.5f * sc + fwd * 0.08f * sc + right * sx * 0.04f * sc;
                }
                else if (state == BoxerState.Corner)
                {
                    target = O + right * sx * 0.58f * sc - fwd * 0.2f * sc + up * 0.02f * sc;
                    elbowHint = sh.position - up * 0.3f * sc;
                }
                rig.ArmIK(rightArm, target, elbowHint, backHand);
            }
            if (state == BoxerState.Celebrate) rig.hips.localPosition += Vector3.up * Mathf.Abs(Mathf.Sin(clock * 5f)) * 0.08f;
            if (tauntT > 0f) { tauntT -= dt; rig.head.localRotation *= Quaternion.Euler(-10f, Mathf.Sin(tauntT * 14f) * 15f, 0); rig.chest.localRotation *= Quaternion.Euler(-8f, 0, 0); }
        }

        public void Taunt() { if (cur == null && state == BoxerState.Fighting && tauntT <= 0f) { tauntT = 1.2f; hype = Mathf.Min(1f, hype + 0.25f); stamina = Mathf.Min(staminaMax, stamina + 6f); } }
        public bool Taunting => tauntT > 0f;

        /// <summary>World point the glove is aimed at (opponent head or body), slightly randomised per punch.</summary>
        Vector3 PunchContact(PunchDef def, bool body, float sc)
        {
            if (opponent == null || opponent.rig == null) return transform.position + transform.forward + Vector3.up * 1.5f;
            if (body)
            {
                // a hook from my left hand lands on the opponent's right side (the liver), and vice versa
                bool leftHand = def.lead ? !profile.southpaw : profile.southpaw;
                int side = def.kind == PunchKind.Hook ? (leftHand ? 1 : -1) : 0;
                return opponent.BodyPoint(side);
            }
            return def.kind == PunchKind.Uppercut ? opponent.ChinPoint : opponent.rig.head.TransformPoint(new Vector3(0, 0.12f, 0.1f));
        }

        void UpdateFeet(float dt, float sc, Vector3 fwd, Vector3 right)
        {
            int lead = LeadSign;
            Vector3 Offset(bool isLead) => isLead ? new Vector3(lead * 0.05f, 0, 0.25f) * sc : new Vector3(-lead * 0.16f, 0, -0.19f) * sc;
            var predict = vel * 0.16f;
            var dLead = transform.position + transform.rotation * Offset(true) + predict;
            var dRear = transform.position + transform.rotation * Offset(false) + predict;
            if (!feetInit) { footL = lead < 0 ? dLead : dRear; footR = lead < 0 ? dRear : dLead; feetInit = true; stepL = stepR = -1f; }
            dLead.y = dRear.y = CanvasY;
            // step lead first, rear follows (shuffle footwork)
            StepFoot(lead < 0, dLead, dt, sc);
            StepFoot(lead > 0, dRear, dt, sc);
        }

        void StepFoot(bool left, Vector3 desired, float dt, float sc)
        {
            ref Vector3 f = ref (left ? ref footL : ref footR);
            ref Vector3 from = ref (left ? ref fromL : ref fromR);
            ref Vector3 to = ref (left ? ref toL : ref toR);
            ref float st = ref (left ? ref stepL : ref stepR);
            float otherStep = left ? stepR : stepL;
            if (st >= 0f)
            {
                st += dt / 0.13f;
                float k = Mathf.Clamp01(st);
                f = Vector3.Lerp(from, to, Smooth(k)) + Vector3.up * Mathf.Sin(k * Mathf.PI) * 0.045f * sc;
                if (st >= 1f) { st = -1f; f = to; if (match != null && (Game.Cam.transform.position - f).sqrMagnitude < 400f) Game.Audio?.Play3D("step", f, 0.12f, Random.Range(0.8f, 1.1f), 1f, 15f); }
                return;
            }
            if (otherStep >= 0f && otherStep < 0.6f) return;
            if ((f - desired).Flat().magnitude > 0.1f * sc) { st = 0f; from = f; to = desired; }
            f.y = CanvasY;
        }
    }
}
