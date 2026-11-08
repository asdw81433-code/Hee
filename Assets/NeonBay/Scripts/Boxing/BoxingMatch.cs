using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum MatchPhase { Intro, RoundStart, Fight, Knockdown, RoundEnd, Corner, KOSequence, Replay, Result, Done }

    /// <summary>
    /// Runs a full boxing match in the Pit: intro and tale of the tape, timed rounds, the referee and his count,
    /// three judges with their own scoring habits, the corner between rounds, KO slow motion and instant replay,
    /// the result and the career consequences.
    /// </summary>
    public class BoxingMatch : MonoBehaviour
    {
        public Boxer Red, Blue;          // red = the player's corner
        public Boxer Player => Red;
        public Boxer Opp => Blue;
        public RingRopes ring;
        public FighterProfile oppProfile;
        public MatchPhase phase;
        public int Round { get; private set; }
        public int Rounds { get; private set; }
        public float RoundLength { get; private set; } = 90f;
        public float clock;
        public float phaseT;
        public bool Running => phase != MatchPhase.Done;
        public float CanvasY => ring != null ? ring.CanvasY : 0f;
        public float PlayerDanger => Red != null ? Red.Danger : 0f;

        // count
        public Boxer downed;
        public int count;
        float countTick;
        int aiGetUpAt;
        public float getUpMeter, getUpMarker, getUpZone = 0.25f; public int getUpHits;
        float markerDir = 1f;

        // scoring
        public class Judge { public string name; public float wPower, wActivity, wDefense, wRing; public List<int> red = new List<int>(), blue = new List<int>(); public int Red => Sum(red); public int Blue => Sum(blue); static int Sum(List<int> l) { int s = 0; foreach (var x in l) s += x; return s; } }
        public readonly List<Judge> judges = new List<Judge>();
        public string resultTitle, resultMethod;
        public Boxer winner;
        public bool draw;
        public int purse, xp;

        // corner
        public string[] cornerOptions = { "WORK THE CUT", "ICE THE SWELLING", "CATCH YOUR BREATH", "GO FOR THE KO" };
        public int cornerChoice = -1;
        public string cornerAdvice;
        public float aggressionBuff;

        // presentation
        public class Popup { public string text; public Color color; public Vector3 pos; public float t; public float size; }
        public readonly List<Popup> popups = new List<Popup>();
        public string commentary; public float commentaryT;
        public bool broadcastCam;
        public RefereeBot referee;
        BoxerAI ai;
        BoxingCamera cam;
        Vector3 playerReturnPos;
        readonly ReplayBuffer replay = new ReplayBuffer();
        float koTime;
        GameObject stool0;
        float resumeT = -1f;

        public static BoxingMatch Begin(FighterProfile opponent)
        {
            if (Boxing.Match != null || Boxing.Arena == null || !Game.HasPlayer) return null;
            var go = new GameObject("BoxingMatch");
            var m = go.AddComponent<BoxingMatch>();
            m.oppProfile = opponent;
            m.Setup();
            Boxing.Match = m;
            return m;
        }

        void Setup()
        {
            ring = Boxing.Arena.ring;
            Rounds = Mathf.Max(3, oppProfile.rounds);
            RoundLength = 90f;
            var pf = Boxing.PlayerFighter();
            Red = Boxer.Create(pf, true, ring.CornerPos(0, 1.2f), 45f, CanvasY);
            Blue = Boxer.Create(oppProfile, false, ring.CornerPos(1, 1.2f), 225f, CanvasY);
            Red.opponent = Blue; Blue.opponent = Red;
            Red.match = this; Blue.match = this;
            Red.corner = 0; Blue.corner = 1;
            ai = new BoxerAI(Blue, Red);
            referee = RefereeBot.Create(this);
            // judges with different eyes for the sport
            judges.Add(new Judge { name = "Marisol Vega", wPower = 1.2f, wActivity = 0.8f, wDefense = 1f, wRing = 1f });
            judges.Add(new Judge { name = "Hank 'Two-Cards' Doyle", wPower = 1.6f, wActivity = 0.6f, wDefense = 0.5f, wRing = 0.8f });
            judges.Add(new Judge { name = "Dr. Anan Sirikul", wPower = 0.9f, wActivity = 1.3f, wDefense = 1.2f, wRing = 1.2f });
            // take the player out of first person
            var pc = Game.Player;
            playerReturnPos = ring.CornerPos(0, -1.6f);
            playerReturnPos.y = CanvasY - 0.75f;
            pc.Teleport(ring.CornerPos(0, -1.4f) + Vector3.down * 0.7f, 45f);
            pc.controlEnabled = false;
            pc.cameraOverride = true;
            pc.cc.enabled = false;
            Game.Weapons.forceFists = true;
            if (Game.Police != null) Game.Police.suppressed = true;
            cam = BoxingCamera.Attach(this, pc.Cam);
            Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false;
            SetPhase(MatchPhase.Intro);
            Game.Audio?.Play2D("crowd_cheer", 0.7f);
            Boxing.Arena?.Excite(0.6f);
            Say("MIC MALONE", "Laaadies and gentlemen... welcome to THE PIT! Tonight: " + Red.profile.FullName + " versus " + Blue.profile.FullName + "!");
        }

        void SetPhase(MatchPhase p)
        {
            phase = p; phaseT = 0f;
            bool menus = p == MatchPhase.Corner || p == MatchPhase.Result;
            Cursor.lockState = menus ? CursorLockMode.None : CursorLockMode.Locked;
            Cursor.visible = menus;
        }

        public void Say(string who, string line)
        {
            Game.UI?.Subtitle(who, line, 3.2f, Palette.Yellow);
        }

        public void Comment(string line) { commentary = line; commentaryT = 3.5f; }

        public void Pop(string text, Color c, Vector3 pos, float size = 1f)
        {
            popups.Add(new Popup { text = text, color = c, pos = pos, t = 1.1f, size = size });
            if (popups.Count > 12) popups.RemoveAt(0);
        }

        // ================================================================== update
        void Update()
        {
            if (!Game.IsPlaying) return;
            float dt = Time.deltaTime;
            if (dt <= 0f) return;
            phaseT += dt;
            commentaryT -= Time.unscaledDeltaTime;
            for (int i = popups.Count - 1; i >= 0; i--) { popups[i].t -= Time.unscaledDeltaTime; popups[i].pos += Vector3.up * Time.unscaledDeltaTime * 0.35f; if (popups[i].t <= 0f) popups.RemoveAt(i); }
            if (InputHub.Down(Btn.CameraView)) broadcastCam = !broadcastCam;

            switch (phase)
            {
                case MatchPhase.Intro:
                    Red.state = Blue.state = BoxerState.Intro;
                    if (phaseT > 7.5f || phaseT > 1f && (InputHub.Down(Btn.Jump) || InputHub.Down(Btn.Fire))) StartRound(1);
                    break;
                case MatchPhase.RoundStart:
                    if (phaseT > 1.6f) { SetPhase(MatchPhase.Fight); Red.state = Blue.state = BoxerState.Fighting; Game.Audio?.Play2D("bell", 0.9f); referee.Signal("FIGHT!"); }
                    break;
                case MatchPhase.Fight:
                    clock -= dt;
                    TickRingControl(dt);
                    if (clock <= 0f) EndRound();
                    break;
                case MatchPhase.Knockdown: TickCount(dt); break;
                case MatchPhase.RoundEnd:
                    if (phaseT > 2.6f) { SetPhase(MatchPhase.Corner); CornerBegin(); }
                    break;
                case MatchPhase.Corner:
                    if (phaseT > 14f || cornerChoice >= 0 && phaseT > 1f) CornerEnd();
                    break;
                case MatchPhase.KOSequence:
                    if (phaseT > 3.2f && replay.HasData) { SetPhase(MatchPhase.Replay); replay.BeginPlayback(); }
                    else if (phaseT > 3.2f) Finish();
                    break;
                case MatchPhase.Replay:
                    if (!replay.Playback(Time.unscaledDeltaTime, this) || phaseT > 1f && InputHub.Down(Btn.Jump)) { replay.EndPlayback(this); Finish(); }
                    break;
                case MatchPhase.Result:
                    break;
            }

            if (phase != MatchPhase.Replay)
            {
                if (phase == MatchPhase.Fight || phase == MatchPhase.Intro || phase == MatchPhase.RoundStart) { PlayerInput(); ai.Tick(dt); }
                else { ClearCommands(Red); if (phase != MatchPhase.Knockdown || downed != Blue) ClearCommands(Blue); }
                Red.Tick(dt); Blue.Tick(dt);
                Red.Pose(dt); Blue.Pose(dt);
                referee.Tick(dt);
            }
            if (phase == MatchPhase.Fight || phase == MatchPhase.Knockdown || phase == MatchPhase.KOSequence) replay.Record(Red, Blue);
        }

        void ClearCommands(Boxer b) { b.move = Vector2.zero; b.lean = Vector3.zero; b.guard = 0; }

        void TickRingControl(float dt)
        {
            // ring generalship: who holds the centre, who walks forward
            float r = Red.RingCenterDist, b = Blue.RingCenterDist;
            if (r < b - 0.4f) Red.round.centerTime += dt; else if (b < r - 0.4f) Blue.round.centerTime += dt;
            if (Red.move.y > 0.3f) Red.round.pressureTime += dt;
            if (Blue.move.y > 0.3f) Blue.round.pressureTime += dt;
            // clinch break
            if (Red.state == BoxerState.Clinch && phaseT > 0f)
            {
                clinchT -= dt;
                if (clinchT <= 0f) BreakClinch();
            }
        }
        float clinchT;

        // ================================================================== player controls
        Vector3 leanAcc;
        void PlayerInput()
        {
            var b = Red;
            if (b.state != BoxerState.Fighting && b.state != BoxerState.Intro) { ClearCommands(b); return; }
            b.move = InputHub.Move;
            var look = InputHub.Look * (Game.Settings != null ? Game.Settings.mouseSensitivity : 1f);
            leanAcc += new Vector3(look.x * 0.055f, 0f, 0f);
            if (look.y < 0f) leanAcc.y += look.y * 0.06f; else leanAcc.z -= look.y * 0.06f;
            leanAcc = Vector3.MoveTowards(leanAcc, Vector3.zero, Time.deltaTime * 2.6f);
            leanAcc = new Vector3(Mathf.Clamp(leanAcc.x, -1f, 1f), Mathf.Clamp(leanAcc.y, -1f, 0f), Mathf.Clamp(leanAcc.z, -1f, 0.5f));
            var lean = leanAcc;
            if (InputHub.KeyHeld(KeyCode.C)) lean.y = -1f;
            b.lean = lean;
            bool body = InputHub.Held(Btn.Walk);
            b.guard = InputHub.Held(Btn.Jump) ? (body ? 2 : 1) : 0;
            bool power = InputHub.Held(Btn.Sprint);
            if (b.state != BoxerState.Fighting) return;
            if (InputHub.Down(Btn.Fire)) b.QueuePunch(PunchType.Jab, body, power);
            if (InputHub.Down(Btn.Aim)) b.QueuePunch(PunchType.Cross, body, power);
            if (InputHub.KeyDown(KeyCode.Q)) b.QueuePunch(PunchType.LeadHook, body, power);
            if (InputHub.KeyDown(KeyCode.E)) b.QueuePunch(PunchType.RearHook, body, power);
            if (InputHub.KeyDown(KeyCode.Z)) b.QueuePunch(PunchType.LeadUpper, body, power);
            if (InputHub.KeyDown(KeyCode.X)) b.QueuePunch(PunchType.RearUpper, body, power);
            if (InputHub.Down(Btn.Vehicle)) TryClinch(Red);
            if (InputHub.Down(Btn.Melee)) { Red.Taunt(); if (Red.Taunting) { Boxing.Arena?.Excite(0.25f); Pop("SHOWBOAT!", Palette.Magenta, Red.HeadPoint + Vector3.up * 0.3f, 0.8f); } }
        }

        public void TryClinch(Boxer who)
        {
            var other = who.opponent;
            if (who.state != BoxerState.Fighting || other.state != BoxerState.Fighting) return;
            if ((who.transform.position - other.transform.position).Flat().magnitude > 0.95f) return;
            who.state = other.state = BoxerState.Clinch;
            clinchT = Random.Range(1.4f, 2.4f);
            Comment(who.profile.name.Split(' ')[0] + " ties him up!");
            Game.Audio?.Play3D("glove_block", who.HeadPoint, 0.7f);
        }

        void BreakClinch()
        {
            if (Red.state == BoxerState.Clinch) Red.state = BoxerState.Fighting;
            if (Blue.state == BoxerState.Clinch) Blue.state = BoxerState.Fighting;
            referee.Signal("BREAK!");
            var d = (Blue.transform.position - Red.transform.position).Flat().normalized;
            Red.transform.position -= d * 0.25f; Blue.transform.position += d * 0.25f;
        }

        // ================================================================== punches
        public void ResolvePunch(Boxer a, PunchDef def, bool body, bool power)
        {
            var d = a.opponent;
            if (d == null || d.IsDown || phase != MatchPhase.Fight) { a.OnPunchResult(HitResult.Miss); return; }
            var sh = def.lead == !a.profile.southpaw ? a.rig.shoulderL : a.rig.shoulderR;
            var target = body ? d.rig.chest.TransformPoint(new Vector3(0, 0.02f, 0.12f)) : def.kind == PunchKind.Uppercut ? d.ChinPoint : d.HeadPoint;
            float reach = def.reach * a.rig.Scale * (power ? 1.04f : 1f) + 0.06f;
            float dist = (target - sh.position).magnitude;
            var dir = (target - sh.position).normalized;
            bool inRange = dist <= reach && Vector3.Dot(a.transform.forward, (d.transform.position - a.transform.position).Flat().normalized) > 0.55f;
            if (d.state == BoxerState.Clinch) inRange = false;
            if (!inRange)
            {
                a.OnPunchResult(HitResult.Miss);
                if (a.isPlayer || d.isPlayer) Game.Audio?.Play3D("whiff", target, 0.35f);
                return;
            }
            var res = d.Evaluate(a, def, body, out float mult);
            bool counter = res == HitResult.Clean && (d.InRecovery || d.WindingUp || a.counterWindow > 0f);
            var round = a.round; var dr = d.round;
            if (res == HitResult.Slipped)
            {
                a.OnPunchResult(HitResult.Slipped);
                d.counterWindow = 0.6f;
                dr.evaded++; d.total.evaded++;
                Pop(d.leanCur.y < -0.4f ? "DUCKED" : "SLIPPED", new Color(0.6f, 0.9f, 1f), d.HeadPoint + Vector3.up * 0.25f, 0.7f);
                Game.Audio?.Play3D("whiff", target, 0.45f, 0.85f);
                if (d.isPlayer) CameraFX.Kick(new Vector3(0, d.leanCur.x * 2f, -d.leanCur.x * 3f));
                return;
            }
            if (res == HitResult.Parried)
            {
                a.OnPunchResult(HitResult.Parried);
                d.counterWindow = 0.7f;
                dr.evaded++; d.total.evaded++;
                Pop("PARRY!", Palette.Cyan, d.HeadPoint + Vector3.up * 0.25f, 1f);
                Game.Audio?.Play3D("glove_block", target, 0.9f, 1.25f);
                a.rig.React(-dir, target, 0.5f, false, false);
                if (d.isPlayer) CameraFX.HitStop(0.05f);
                return;
            }

            // damage
            float dmg = def.damage * a.PowerFactor * (power ? 1.45f : 1f) * a.StaminaFactor * mult * Random.Range(0.9f, 1.1f);
            if (counter) dmg *= 1.25f;
            if (a.isPlayer) dmg *= Mathf.Lerp(1f, Game.PlayerDamageMult, 0.5f) * (1f + aggressionBuff * 0.1f);
            else dmg *= Mathf.Lerp(1f, Game.EnemyDamageMult, 0.5f);
            if (d.isPlayer) dmg *= 1f + aggressionBuff * 0.12f;
            if (d.Rocked && !body) dmg *= 1.1f;
            var contact = target - dir * 0.04f;
            bool kd = d.TakeHit(a, def, body, power, dmg, res, contact, dir, counter);
            float pk = Mathf.Clamp(dmg / 14f, 0.1f, 1.6f);
            if (res == HitResult.Blocked)
            {
                a.OnPunchResult(HitResult.Blocked);
                dr.blocked++; d.total.blocked++;
                Game.Audio?.Play3D("glove_block", contact, 0.75f, Random.Range(0.9f, 1.1f));
                if (d.isPlayer) { CameraFX.Shake(0.06f + pk * 0.05f); CameraFX.KickFrom(cam != null ? cam.Cam : null, dir, 1f + pk); }
                return;
            }
            a.OnPunchResult(HitResult.Clean);
            round.landed++; a.total.landed++;
            if (def.type == PunchType.Jab) { round.jabsLanded++; a.total.jabsLanded++; } else { round.powerLanded++; a.total.powerLanded++; }
            if (body) { round.bodyLanded++; a.total.bodyLanded++; } else { round.headLanded++; a.total.headLanded++; }
            if (counter) { round.counters++; a.total.counters++; }
            round.damage += dmg; a.total.damage += dmg;
            a.hype = Mathf.Min(1f, a.hype + pk * 0.08f);

            // sound, crowd, camera
            Game.Audio?.Play3D(body ? "glove_body" : pk > 0.9f ? "glove_heavy" : "glove_head", contact, Mathf.Lerp(0.6f, 1f, pk), Random.Range(0.92f, 1.06f), 3f, 60f);
            if (pk > 0.75f || counter) Boxing.Arena?.Excite(counter ? 0.45f : 0.3f);
            if (counter) Pop("COUNTER!", Palette.Yellow, d.HeadPoint + Vector3.up * 0.3f, 1.1f);
            else if (power && pk > 0.8f) Pop("POWER SHOT", Palette.Orange, d.HeadPoint + Vector3.up * 0.3f, 0.95f);
            else if (body && pk > 0.6f) Pop("BODY!", new Color(1f, 0.6f, 0.3f), d.rig.chest.position + Vector3.up * 0.2f, 0.8f);
            if (d.Rocked && !kd && d.rockedT > 1.5f && Time.time - lastRockPop > 2f) { lastRockPop = Time.time; Pop("ROCKED!", Palette.Red, d.HeadPoint + Vector3.up * 0.45f, 1.2f); Comment(d.profile.name.Split(' ')[0] + " is HURT! He's in trouble!"); }
            if (a.isPlayer)
            {
                CameraFX.Shake(0.05f + pk * 0.1f);
                if (power || counter || pk > 1f) CameraFX.HitStop(0.035f + pk * 0.03f);
                CameraFX.FovPunch(-pk * 1.2f);
            }
            if (d.isPlayer)
            {
                CameraFX.Shake(0.22f + pk * 0.28f);
                CameraFX.KickFrom(cam != null ? cam.Cam : null, dir, 3f + pk * 5f);
                CameraFX.Flash(new Color(0.7f, 0f, 0f), 0.2f + pk * 0.25f);
                CameraFX.Chroma(0.2f + pk * 0.35f);
                if (!body) CameraFX.Lens(-0.08f * pk);
                if (d.Rocked) { CameraFX.Dizzy(0.55f + pk * 0.2f, d.rockedT); CameraFX.Blur(0.45f, 1f); }
                if (counter || pk > 1.1f) CameraFX.HitStop(0.06f);
            }
            if (counter && pk > 1f) CameraFX.SlowMo(0.4f, 0.22f);

            if (kd) Knockdown(d, a, dir, contact, pk, counter);
        }
        float lastRockPop;

        // ================================================================== knockdowns
        void Knockdown(Boxer v, Boxer by, Vector3 dir, Vector3 point, float pk, bool counter)
        {
            bool ko = v.headHP < -28f || v.kdRound >= 2 || (v.kdTotal >= 3 && Random.value < 0.6f);
            by.round.knockdowns++; by.total.knockdowns++;
            replay.MarkKO();
            v.KnockDown(dir, point, pk, ko);
            ring.Jolt(point, dir * 6f);
            Game.Audio?.Play2D("canvas", 0.9f);
            Boxing.Arena?.Excite(1f);
            CameraFX.SlowMo(0.25f, ko ? 1.1f : 0.6f);
            CameraFX.HitStop(0.09f);
            CameraFX.Shake(0.5f);
            if (v.isPlayer) { CameraFX.Flash(Color.white, 0.8f); CameraFX.Dizzy(1f, 3f); CameraFX.Blur(1f, 2f); }
            Pop(ko ? "KNOCKOUT!" : "KNOCKDOWN!", Palette.Red, v.HeadPoint + Vector3.up * 0.6f, 1.6f);
            Comment(ko ? "DOWN GOES " + v.profile.name.ToUpperInvariant() + "! HE'S OUT COLD!" : "DOWN GOES " + v.profile.name.ToUpperInvariant() + "!");
            downed = v;
            if (v.kdRound >= 3) { EndFight(by, "TKO", "Three knockdowns in round " + Round); return; }
            if (ko) { koTime = Time.time; v.state = BoxerState.KO; EndFight(by, "KO", "Knockout, round " + Round + " " + ClockString); return; }
            SetPhase(MatchPhase.Knockdown);
            count = 0; countTick = -1.3f;
            getUpMeter = 0f; getUpHits = 0; getUpMarker = 0f;
            getUpZone = Mathf.Lerp(0.12f, 0.3f, v.profile.stats.heart / 100f) * Mathf.Lerp(1f, 0.6f, (v.kdTotal - 1) / 3f);
            var neutral = (ring.CornerPos(2) - v.rig.hips.position).sqrMagnitude > (ring.CornerPos(3) - v.rig.hips.position).sqrMagnitude ? 2 : 3;
            by.forcedTarget = ring.CornerPos(neutral, 0.8f);
            by.state = BoxerState.Corner;
            // AI decides when (and whether) to beat the count
            if (!v.isPlayer)
            {
                float will = v.profile.stats.heart / 100f + 0.25f - v.kdTotal * 0.18f - Mathf.Clamp01(-v.headHP / 30f) * 0.5f + (Game.Difficulty == Difficulty.Brutal ? 0.15f : 0f);
                aiGetUpAt = will > Random.value * 0.9f ? Random.Range(4, 10) : 11;
            }
        }

        public void LiverKnockdown(Boxer v)
        {
            if (phase != MatchPhase.Fight || v.IsDown) return;
            Comment("A LIVER SHOT! " + v.profile.name.Split(' ')[0] + " folds in half!");
            Pop("LIVER SHOT", Palette.Orange, v.rig.chest.position + Vector3.up * 0.4f, 1.2f);
            if (v.isPlayer) { CameraFX.Flash(new Color(0.5f, 0.3f, 0f), 0.4f); CameraFX.Blur(0.6f, 2f); }
            Knockdown(v, v.opponent, -v.transform.forward + Vector3.down * 0.5f, v.rig.chest.position, 0.4f, false);
        }

        void TickCount(float dt)
        {
            var v = downed;
            if (v == null)
            {
                resumeT -= dt;
                if (resumeT <= 0f) Resume();
                return;
            }
            countTick += dt;
            if (countTick >= 1f)
            {
                countTick -= 1f;
                count++;
                Game.Audio?.Play2D("count", 0.7f, 1f + count * 0.02f);
                referee.Signal(count.ToString());
                if (count >= 10) { v.state = BoxerState.KO; if (v.rig.face != null) v.rig.face.ko = true; EndFight(v.opponent, "KO", "Counted out, round " + Round + " " + ClockString); return; }
            }
            if (count < 1) return;
            // the player fights to get up
            if (v.isPlayer)
            {
                getUpMarker += markerDir * dt * (1.1f + v.kdTotal * 0.25f);
                if (getUpMarker > 1f) { getUpMarker = 1f; markerDir = -1f; } else if (getUpMarker < 0f) { getUpMarker = 0f; markerDir = 1f; }
                if (InputHub.Down(Btn.Jump) || InputHub.Down(Btn.Fire))
                {
                    float c = 0.5f;
                    if (Mathf.Abs(getUpMarker - c) < getUpZone * 0.5f) { getUpHits++; getUpMeter += 1f / (2f + v.kdTotal); Game.Audio?.Play2D("ui_confirm", 0.6f); CameraFX.Kick(new Vector3(-2f, 0, 0)); }
                    else { getUpMeter = Mathf.Max(0f, getUpMeter - 0.15f); Game.Audio?.Play2D("ui_error", 0.5f); }
                }
                if (getUpMeter >= 1f) GetUp(v);
            }
            else if (count >= aiGetUpAt) GetUp(v);
        }

        void GetUp(Boxer v)
        {
            v.GetUp();
            referee.Signal("Can you continue?");
            Comment(v.profile.name.Split(' ')[0] + " beats the count at " + count + "!");
            Boxing.Arena?.Excite(0.5f);
            resumeT = 2.2f;
            downed = null;
        }

        void Resume()
        {
            Red.forcedTarget = Blue.forcedTarget = null;
            if (Red.state == BoxerState.GettingUp || Red.state == BoxerState.Corner) Red.state = BoxerState.Fighting;
            if (Blue.state == BoxerState.GettingUp || Blue.state == BoxerState.Corner) Blue.state = BoxerState.Fighting;
            SetPhase(MatchPhase.Fight);
            referee.Signal("BOX!");
        }

        // ================================================================== rounds
        void StartRound(int r)
        {
            Round = r;
            clock = RoundLength;
            Red.kdRound = Blue.kdRound = 0;
            Red.round = new RoundStats(); Blue.round = new RoundStats();
            Red.forcedTarget = Blue.forcedTarget = null;
            Red.transform.position = ring.CornerPos(0, 1.3f) + Vector3.up * (CanvasY - ring.CornerPos(0, 1.3f).y);
            Blue.transform.position = ring.CornerPos(1, 1.3f) + Vector3.up * (CanvasY - ring.CornerPos(1, 1.3f).y);
            Red.state = Blue.state = BoxerState.Intro;
            SetPhase(MatchPhase.RoundStart);
            if (stool0 != null) { Destroy(stool0); stool0 = null; }
            Game.UI?.Banner("ROUND " + r, r == Rounds ? "FINAL ROUND" : Red.profile.name + "  vs  " + Blue.profile.name, Palette.Red);
        }

        public string ClockString { get { float c = Mathf.Max(0f, RoundLength - clock); return ((int)(c / 60f)) + ":" + ((int)(c % 60f)).ToString("00"); } }
        public string ClockLeft { get { float c = Mathf.Max(0f, clock); return ((int)(c / 60f)) + ":" + ((int)(c % 60f)).ToString("00"); } }

        void EndRound()
        {
            Game.Audio?.Play2D("bell3", 0.9f);
            referee.Signal("TIME!");
            ScoreRound();
            Red.state = Blue.state = BoxerState.Corner;
            Red.forcedTarget = ring.CornerPos(0, 0.65f);
            Blue.forcedTarget = ring.CornerPos(1, 0.65f);
            if (Red.state == BoxerState.Clinch || Blue.state == BoxerState.Clinch) BreakClinch();
            SetPhase(MatchPhase.RoundEnd);
            Boxing.Arena?.Excite(0.3f);
        }

        void ScoreRound()
        {
            foreach (var j in judges)
            {
                float r = Points(Red.round, Blue.round, j), b = Points(Blue.round, Red.round, j);
                float margin = (r - b) / Mathf.Max(1f, r + b);
                margin += Random.Range(-0.08f, 0.08f);
                int rs = 10, bs = 10;
                if (margin > 0.06f) bs = 9; else if (margin < -0.06f) rs = 9;
                else if (Random.value < 0.5f) { if (margin >= 0) bs = 9; else rs = 9; }
                rs -= Blue.round.knockdowns; bs -= Red.round.knockdowns;
                rs = Mathf.Max(rs, 6); bs = Mathf.Max(bs, 6);
                if (rs == bs && rs < 10) { rs++; bs++; }
                j.red.Add(rs); j.blue.Add(bs);
            }
        }

        static float Points(RoundStats me, RoundStats them, Judge j)
            => me.jabsLanded * 1f * j.wActivity + me.powerLanded * 1.9f * j.wPower + me.damage * 0.06f * j.wPower + me.evaded * 0.35f * j.wDefense + me.blocked * 0.15f * j.wDefense
               + me.centerTime * 0.05f * j.wRing + me.pressureTime * 0.03f * j.wRing + me.thrown * 0.08f * j.wActivity + me.counters * 0.8f;

        // ================================================================== corner
        void CornerBegin()
        {
            cornerChoice = -1;
            var pr = Red.round;
            var inj = Red.rig.injury;
            if (inj != null && inj.MaxCut > 0.4f) cornerAdvice = "That cut is ugly. Let me work on it or the doc stops this.";
            else if (inj != null && Mathf.Max(inj.EyeClosure(true), inj.EyeClosure(false)) > 0.3f) cornerAdvice = "Your eye is closing. Keep that side covered.";
            else if (Red.stamina < 35f || Red.staminaMax < 70f) cornerAdvice = "You're gassing! Stop loading up on every punch and breathe.";
            else if (pr.landed < Blue.round.landed) cornerAdvice = "He's outworking you. Double the jab and go downstairs.";
            else if (Blue.round.bodyLanded < 3 && Blue.profile.style == FightStyle.Swarmer) cornerAdvice = "He's coming forward with his head. Catch him with the uppercut.";
            else cornerAdvice = "Good round! Keep your hands up and make him miss.";
            // doctor check
            foreach (var b in new[] { Red, Blue })
            {
                var i = b.rig.injury;
                if (i == null) continue;
                bool bad = i.MaxCut > 0.92f || i.EyeClosure(true) > 0.96f || i.EyeClosure(false) > 0.96f;
                if (bad && Random.value < 0.5f)
                {
                    Say("RINGSIDE DOCTOR", "I can't let " + b.profile.name.Split(' ')[0] + " continue. That's it!");
                    EndFight(b.opponent, "TKO", "Doctor stoppage after round " + Round);
                    return;
                }
            }
            if (Round >= Rounds) { Decision(); return; }
            // AI corner work
            Blue.rig.injury?.Treat(0.25f, 0.15f);
            Recover(Blue, 1f);
            if (stool0 == null)
            {
                stool0 = new GameObject("Stool");
                Util.Primitive(PrimitiveType.Cylinder, "Seat", stool0.transform, Vector3.zero, new Vector3(0.45f, 0.25f, 0.45f), Mats.Cached("stool", () => Mats.Lit(new Color(0.15f, 0.15f, 0.17f), null, 0.6f, 0.5f)));
                stool0.transform.position = ring.CornerPos(0, 0.95f) + Vector3.down * 0.0f + Vector3.up * 0.25f;
            }
        }

        public void ChooseCorner(int i)
        {
            if (phase != MatchPhase.Corner || cornerChoice >= 0) return;
            cornerChoice = i;
            var inj = Red.rig.injury;
            switch (i)
            {
                case 0: inj?.Treat(0.55f, 0.08f); break;
                case 1: inj?.Treat(0.1f, 0.35f); break;
                case 2: Red.staminaMax = Mathf.Min(105f, Red.staminaMax + 8f); Red.headHP = Mathf.Min(Red.headCap, Red.headHP + 8f); break;
                case 3: aggressionBuff = 1f; break;
            }
            if (i != 3) aggressionBuff = 0f;
            Game.Audio?.Play2D("ui_confirm", 0.6f);
        }

        void CornerEnd()
        {
            if (phase != MatchPhase.Corner) return;
            if (cornerChoice < 0) Red.rig.injury?.Treat(0.2f, 0.1f);
            Recover(Red, 1f);
            StartRound(Round + 1);
        }

        void Recover(Boxer b, float k)
        {
            b.staminaMax = Mathf.Min(108f, b.staminaMax + 4f * k);
            b.stamina = b.staminaMax;
            b.headHP = Mathf.Min(b.headCap, b.headHP + Mathf.Lerp(10f, 20f, b.profile.stats.heart / 100f) * k);
            b.bodyHP = Mathf.Min(100f, b.bodyHP + 10f * k);
            b.recentHead = 0f; b.rockedT = 0f;
        }

        // ================================================================== ending
        void Decision()
        {
            int redCards = 0, blueCards = 0;
            foreach (var j in judges) { if (j.Red > j.Blue) redCards++; else if (j.Blue > j.Red) blueCards++; }
            string method;
            Boxer w = null;
            if (redCards >= 2 && blueCards == 0) { w = Red; method = redCards == 3 ? "UNANIMOUS DECISION" : "MAJORITY DECISION"; }
            else if (blueCards >= 2 && redCards == 0) { w = Blue; method = blueCards == 3 ? "UNANIMOUS DECISION" : "MAJORITY DECISION"; }
            else if (redCards == 2) { w = Red; method = "SPLIT DECISION"; }
            else if (blueCards == 2) { w = Blue; method = "SPLIT DECISION"; }
            else method = "DRAW";
            EndFight(w, method, "After " + Rounds + " rounds");
        }

        void EndFight(Boxer w, string method, string detail)
        {
            winner = w; draw = w == null;
            resultTitle = draw ? "DRAW" : w.profile.name.ToUpperInvariant() + " WINS";
            resultMethod = method + "  -  " + detail;
            Game.Audio?.Play2D("bell3", 1f);
            Boxing.Arena?.Excite(1f);
            Red.forcedTarget = Blue.forcedTarget = null;
            if (w != null)
            {
                if (!w.IsDown) w.state = BoxerState.Celebrate;
                var l = w.opponent;
                if (!l.IsDown) l.state = BoxerState.Dejected;
            }
            else { if (!Red.IsDown) Red.state = BoxerState.Dejected; if (!Blue.IsDown) Blue.state = BoxerState.Dejected; }
            bool ko = method == "KO" || method == "TKO";
            if (method == "KO") { SetPhase(MatchPhase.KOSequence); CameraFX.SlowMo(0.3f, 1.2f); }
            else Finish();
            // career
            bool playerWon = w == Red;
            Boxing.RecordResult(oppProfile, playerWon, draw, ko);
            purse = playerWon ? Mathf.RoundToInt(oppProfile.purse * (ko ? 1.25f : 1f)) : draw ? oppProfile.purse / 2 : oppProfile.purse / 4;
            xp = playerWon ? 300 + Round * 40 + (ko ? 120 : 0) : 120 + Round * 20;
            Game.Stats?.AddMoney(purse);
            Game.Stats?.AddXP(xp);
            if (playerWon) Game.Stats?.AddCred(Boxing.IsChampion ? 20 : 6);
            if (Red.rig.injury != null) Boxing.PlayerInjuries = Red.rig.injury.Save();
            Comment(draw ? "The judges can't split them!" : (w.profile.name.Split(' ')[0] + " wins by " + method.ToLowerInvariant() + "!"));
        }

        void Finish()
        {
            SetPhase(MatchPhase.Result);
            if (winner == Red && Boxing.IsChampion && oppProfile.id == "polly") Game.UI?.Banner("UNDISPUTED", "Champion of the Pit", Palette.Yellow);
        }

        /// <summary>Called by the results screen.</summary>
        public void Close()
        {
            if (phase == MatchPhase.Done) return;
            phase = MatchPhase.Done;
            var pc = Game.Player;
            if (pc != null)
            {
                pc.cc.enabled = true;
                pc.Teleport(playerReturnPos, 45f);
                pc.controlEnabled = true;
                pc.cameraOverride = false;
                pc.Cam.transform.localPosition = Vector3.zero;
                pc.Cam.transform.localRotation = Quaternion.identity;
                pc.Cam.fieldOfView = Game.Settings != null ? Game.Settings.fov : 78f;
            }
            if (Game.Weapons != null) Game.Weapons.forceFists = false;
            if (Game.Police != null) Game.Police.suppressed = false;
            if (winner != Red && !draw && Game.Stats != null) Game.Stats.dmg.health = Mathf.Max(Game.Stats.dmg.health, Game.Stats.dmg.maxHealth * 0.3f);
            if (cam != null) Destroy(cam);
            if (Red != null) Destroy(Red.gameObject);
            if (Blue != null) Destroy(Blue.gameObject);
            if (referee != null) Destroy(referee.gameObject);
            if (stool0 != null) Destroy(stool0);
            CameraFX.Clear();
            Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false;
            Boxing.Match = null;
            Destroy(gameObject);
            if (winner != Red && !draw) Game.UI?.Banner("THE MORNING AFTER", "Everything hurts. Doc Reyes can patch your face up.", Palette.Red);
        }

        /// <summary>Tear down without touching the player (quit to menu / load game).</summary>
        public void Abort()
        {
            phase = MatchPhase.Done;
            if (Red != null) Destroy(Red.gameObject);
            if (Blue != null) Destroy(Blue.gameObject);
            if (referee != null) Destroy(referee.gameObject);
            if (stool0 != null) Destroy(stool0);
            if (Game.Weapons != null) Game.Weapons.forceFists = false;
            if (Game.Police != null) Game.Police.suppressed = false;
            Boxing.Match = null;
            Destroy(gameObject);
        }

        void OnDestroy() { if (Boxing.Match == this) Boxing.Match = null; }

        // ================================================================== ropes
        public void CollectPushers(RingRopes r)
        {
            foreach (var b in new[] { Red, Blue })
            {
                if (b == null || b.rig == null) continue;
                if (b.rig.ragdolled)
                {
                    r.AddPusher(b.rig.chest.position, 0.24f, b.rig.chest.position.y - 0.4f, b.rig.chest.position.y + 0.4f, Vector3.zero);
                    r.AddPusher(b.rig.hips.position, 0.2f, b.rig.hips.position.y - 0.3f, b.rig.hips.position.y + 0.3f, Vector3.zero);
                    r.AddPusher(b.rig.head.position, 0.14f, b.rig.head.position.y - 0.1f, b.rig.head.position.y + 0.3f, Vector3.zero);
                }
                else
                {
                    var c = b.rig.chest.position;
                    r.AddPusher(new Vector3(c.x, 0, c.z), 0.27f, CanvasY + 0.3f, CanvasY + 1.75f, Vector3.zero);
                    var h = b.rig.hips.position;
                    r.AddPusher(new Vector3(h.x, 0, h.z), 0.22f, CanvasY + 0.2f, CanvasY + 1.1f, Vector3.zero);
                }
            }
            if (referee != null && referee.rig != null) { var p = referee.transform.position; r.AddPusher(p, 0.3f, CanvasY + 0.2f, CanvasY + 1.7f, Vector3.zero); }
        }

        // ================================================================== replay
        /// <summary>Records both fighters' skeletons every frame; plays the knockout back slower around the impact.</summary>
        class ReplayBuffer
        {
            const int Max = 360;
            struct Frame { public Vector3 rp, hp; public Quaternion rr; public Quaternion[] rot; }
            readonly Frame[][] frames = { new Frame[Max], new Frame[Max] };
            int head, count;
            long recorded, koAbs = -1;
            float playT; long playStart, playEnd;
            float recordAcc;
            public bool HasData => count > 30 && koAbs >= 0 && koAbs >= recorded - count + 20;
            Transform[][] cache;
            static Transform[] Bones(Boxer b) { var r = b.rig; return new[] { r.hips, r.torso, r.chest, r.neck, r.head, r.jaw, r.shoulderL, r.elbowL, r.handL, r.shoulderR, r.elbowR, r.handR, r.thighL, r.kneeL, r.ankleL, r.thighR, r.kneeR, r.ankleR }; }

            public void MarkKO() { koAbs = recorded; }

            public void Record(Boxer a, Boxer b)
            {
                recordAcc += Time.unscaledDeltaTime;
                if (recordAcc < 1f / 60f) return;
                recordAcc = 0f;
                if (cache == null) cache = new[] { Bones(a), Bones(b) };
                for (int k = 0; k < 2; k++)
                {
                    var box = k == 0 ? a : b;
                    var bones = cache[k];
                    var f = frames[k][head];
                    if (f.rot == null) f.rot = new Quaternion[bones.Length];
                    f.rp = box.transform.position; f.rr = box.transform.rotation; f.hp = box.rig.hips.localPosition;
                    for (int i = 0; i < bones.Length; i++) f.rot[i] = bones[i].localRotation;
                    frames[k][head] = f;
                }
                head = (head + 1) % Max;
                count = Mathf.Min(Max, count + 1);
                recorded++;
            }

            public void BeginPlayback()
            {
                long oldest = recorded - count;
                playStart = System.Math.Max(oldest, koAbs - 80);
                playEnd = System.Math.Min(recorded - 1, koAbs + 140);
                playT = 0f;
                foreach (var m in Object.FindObjectsByType<Boxer>(FindObjectsSortMode.None))
                    foreach (var rb in m.rig.hips.GetComponentsInChildren<Rigidbody>()) rb.isKinematic = true;
            }

            Frame At(int k, long abs) => frames[k][(int)(((abs % Max) + Max) % Max)];

            void Apply(BoxingMatch m, float absF)
            {
                long i0 = (long)Mathf.Floor(absF);
                float frac = absF - i0;
                long i1 = System.Math.Min(i0 + 1, recorded - 1);
                for (int k = 0; k < 2; k++)
                {
                    var box = k == 0 ? m.Red : m.Blue;
                    var bones = cache[k];
                    var f0 = At(k, i0); var f1 = At(k, i1);
                    if (f0.rot == null || f1.rot == null) continue;
                    box.transform.SetPositionAndRotation(Vector3.Lerp(f0.rp, f1.rp, frac), Quaternion.Slerp(f0.rr, f1.rr, frac));
                    box.rig.transform.localPosition = Vector3.zero; box.rig.transform.localRotation = Quaternion.identity;
                    box.rig.hips.localPosition = Vector3.Lerp(f0.hp, f1.hp, frac);
                    for (int i = 0; i < bones.Length; i++) bones[i].localRotation = Quaternion.Slerp(f0.rot[i], f1.rot[i], frac);
                }
            }

            /// <summary>Returns false once the replay has finished.</summary>
            public bool Playback(float dt, BoxingMatch m)
            {
                float abs = playStart + playT;
                // real speed far from the punch, heavy slow motion around it
                float near = Mathf.Abs(abs - koAbs);
                float rate = near < 40f ? 0.25f : near < 70f ? 0.55f : 1f;
                playT += dt * 60f * rate;
                abs = Mathf.Min(playStart + playT, playEnd);
                Apply(m, abs);
                return playStart + playT < playEnd;
            }

            public void EndPlayback(BoxingMatch m) { if (recorded > 0) Apply(m, recorded - 1); }
        }
    }

    /// <summary>The third man in the ring.</summary>
    public class RefereeBot : MonoBehaviour
    {
        public HumanoidRig rig;
        BoxingMatch match;
        Vector3 vel;
        float speed;
        public string shout; public float shoutT;
        float countArm;

        public static RefereeBot Create(BoxingMatch m)
        {
            var go = new GameObject("Referee");
            var krb = go.AddComponent<Rigidbody>(); krb.isKinematic = true; krb.useGravity = false;
            var r = go.AddComponent<RefereeBot>();
            r.match = m;
            go.transform.position = m.ring.CornerPos(2, 1.5f);
            var look = new Appearance
            {
                skin = Palette.SkinTones[3], hair = 2, hairColor = new Color(0.6f, 0.6f, 0.62f), beard = 2, beardColor = new Color(0.55f, 0.55f, 0.56f),
                jacket = new Color(0.92f, 0.92f, 0.94f), pants = new Color(0.04f, 0.04f, 0.05f), accent = new Color(0.1f, 0.1f, 0.1f), sleeves = 1, bulk = 1.05f, muscle = 0.3f, jaw = 0.7f, eyes = new Color(0.3f, 0.2f, 0.1f)
            };
            r.rig = HumanoidRig.Build(go.transform, look, null, false, 0);
            return r;
        }

        public void Signal(string s) { shout = s; shoutT = 1.4f; countArm = 1f; }

        public void Tick(float dt)
        {
            shoutT -= dt;
            countArm = Mathf.MoveTowards(countArm, 0f, dt * 2.2f);
            Vector3 target;
            Vector3 lookAt;
            var a = match.Red; var b = match.Blue;
            var mid = (a.transform.position + b.transform.position) * 0.5f;
            if (match.phase == MatchPhase.Knockdown && match.downed != null)
            {
                var dp = match.downed.rig.hips.position;
                var away = (dp - match.ring.Center).Flat();
                target = dp - (away.sqrMagnitude > 0.01f ? away.normalized : Vector3.forward) * 1.1f;
                lookAt = dp;
            }
            else
            {
                var line = (b.transform.position - a.transform.position).Flat();
                var perp = Vector3.Cross(Vector3.up, line.sqrMagnitude > 0.01f ? line.normalized : Vector3.forward);
                var c1 = mid + perp * 1.8f; var c2 = mid - perp * 1.8f;
                target = (c1 - match.ring.Center).sqrMagnitude < (c2 - match.ring.Center).sqrMagnitude ? c1 : c2;
                lookAt = mid + Vector3.up * 1.4f;
            }
            var pos = transform.position;
            var to = (target - pos).Flat();
            var wish = to.magnitude > 0.25f ? to.normalized * Mathf.Min(2.2f, to.magnitude * 2f) : Vector3.zero;
            vel = Vector3.MoveTowards(vel, wish, dt * 6f);
            pos += vel * dt;
            match.ring.Constrain(ref pos, ref vel, 0.3f);
            pos.y = match.CanvasY;
            transform.position = pos;
            var face = (lookAt - pos).Flat();
            if (face.sqrMagnitude > 0.01f) transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(face), dt * 6f);
            speed = vel.magnitude;
            rig.Animate(speed, false, false, dt);
            // counting / signalling arm
            if (countArm > 0f)
            {
                float k = Mathf.Sin(countArm * Mathf.PI);
                rig.shoulderR.localRotation = Quaternion.Euler(-100f - 50f * k, 0, 20f);
                rig.elbowR.localRotation = Quaternion.Euler(-30f + 20f * k, 0, 0);
            }
            if (match.phase == MatchPhase.Knockdown && match.downed != null)
            {
                rig.torso.localRotation *= Quaternion.Euler(18f, 0, 0);
                rig.hips.localPosition += Vector3.down * 0.12f;
            }
            rig.LookAt(lookAt);
            if (rig.face != null) rig.face.talk = shoutT > 0f ? 1f : 0f;
        }
    }
}
