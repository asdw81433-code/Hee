using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// CPU boxer. Reads the opponent's punches with a human reaction delay and defends by style (slip, duck, shell,
    /// parry), throws style-specific combinations, counters after making you miss, cuts off the ring, escapes the
    /// ropes, clinches when hurt and goes for the finish when you're rocked.
    /// </summary>
    public class BoxerAI
    {
        readonly Boxer me, opp;
        readonly FightStyle style;
        readonly float skill;
        readonly List<List<(PunchType t, bool body, bool power)>> combos = new List<List<(PunchType, bool, bool)>>();
        readonly Queue<(PunchType t, bool body, bool power)> plan = new Queue<(PunchType, bool, bool)>();
        float think, comboCd = 1.2f, gap;
        PunchDef seenPunch; float seenAt; bool reacted;
        float defendHold; Vector3 defendLean; int defendGuard;
        float strafe = 1f, strafeT, feintT;
        float clinchCd = 3f, tauntCd = 8f;
        float desiredRange;

        public BoxerAI(Boxer me, Boxer opp)
        {
            this.me = me; this.opp = opp;
            style = me.profile.style;
            float diff = Game.Difficulty switch { Difficulty.Story => 0.35f, Difficulty.Normal => 0.6f, Difficulty.Hard => 0.78f, _ => 0.92f };
            skill = Mathf.Clamp01(diff * 0.7f + me.profile.stats.Overall / 100f * 0.4f);
            string[] lib;
            switch (style)
            {
                case FightStyle.OutBoxer: lib = new[] { "1", "1", "1 1", "1 2", "1 1 2", "1 2 3", "b1 1", "1 2 b3", "2 3 2" }; desiredRange = 1.18f; break;
                case FightStyle.Swarmer: lib = new[] { "b3 3", "1 2 b3", "3 2 3", "b4 b3 3", "5 2 3", "1 2 5 2", "b2 3", "3 b3 4" }; desiredRange = 0.72f; break;
                case FightStyle.Slugger: lib = new[] { "p2", "p4", "1 p2", "3 p2", "p6", "1 1 p2", "pb4" }; desiredRange = 0.9f; break;
                case FightStyle.Counter: lib = new[] { "1", "1 2", "b1", "1 b2" }; desiredRange = 1.05f; break;
                default: lib = new[] { "3 4 3", "p4 p3", "5 6 3 4", "1 2 3 4", "pb3 p3", "2 3 2 p3" }; desiredRange = 0.82f; break;
            }
            foreach (var s in lib) combos.Add(Parse(s));
        }

        static List<(PunchType, bool, bool)> Parse(string s)
        {
            var l = new List<(PunchType, bool, bool)>();
            foreach (var tok in s.Split(' '))
            {
                bool p = tok.Contains("p"), b = tok.Contains("b");
                char c = tok[tok.Length - 1];
                var t = (PunchType)Mathf.Clamp(c - '1', 0, 5);
                l.Add((t, b, p));
            }
            return l;
        }

        float Def => me.profile.stats.defense / 100f;

        public void Tick(float dt)
        {
            if (me.state == BoxerState.Intro) { me.move = new Vector2(Mathf.Sin(Time.time * 1.3f) * 0.3f, 0); return; }
            if (me.state != BoxerState.Fighting) { me.move = Vector2.zero; me.lean = Vector3.zero; me.guard = 0; plan.Clear(); return; }
            think -= dt; comboCd -= dt; gap -= dt; defendHold -= dt; clinchCd -= dt; tauntCd -= dt; strafeT -= dt; feintT -= dt;
            float dist = (opp.transform.position - me.transform.position).Flat().magnitude;
            float tired = 1f - Mathf.Clamp01(me.stamina / 60f);

            // ---------------------------------------------------------- defence: read the incoming punch
            if (opp.Punching && opp.Current != seenPunch) { seenPunch = opp.Current; seenAt = Time.time; reacted = false; }
            if (!opp.Punching) seenPunch = null;
            float reaction = Mathf.Lerp(0.34f, 0.1f, skill * (0.5f + Def * 0.5f)) * (me.Rocked ? 1.8f : 1f) * (1f + tired * 0.5f);
            if (seenPunch != null && !reacted && Time.time - seenAt >= reaction && opp.TimeToImpact > 0.015f)
            {
                reacted = true;
                float chance = Def * (0.5f + skill * 0.55f) * (1f - tired * 0.4f) * (me.Rocked ? 0.5f : 1f);
                if (style == FightStyle.Counter) chance += 0.15f;
                if (style == FightStyle.Slugger || style == FightStyle.Brawler) chance -= 0.1f;
                if (Random.value < chance && !me.Punching) ChooseDefence(opp.Current, opp.CurrentBody);
            }
            if (defendHold > 0f) { me.lean = defendLean; me.guard = defendGuard; }
            else
            {
                me.lean = Vector3.MoveTowards(me.lean, Vector3.zero, dt * 4f);
                // idle guard by style
                me.guard = (style == FightStyle.Swarmer && dist < 1.4f && !me.Punching && plan.Count == 0) || me.Rocked && Random.value < 0.6f ? 1 : 0;
                // head movement while waiting
                if (style == FightStyle.Counter || style == FightStyle.Swarmer) me.lean.x = Mathf.Sin(Time.time * 2.1f + me.GetHashCode()) * 0.35f;
            }

            // ---------------------------------------------------------- hurt: hold on or survive
            if (me.Rocked && dist < 0.9f && clinchCd <= 0f && Random.value < 0.02f + (1f - me.headHP / 100f) * 0.05f)
            {
                clinchCd = 6f;
                me.match.TryClinch(me);
            }

            // ---------------------------------------------------------- offence
            bool oppHurt = opp.Rocked || opp.stamina < 20f;
            float aggression = style == FightStyle.Swarmer || style == FightStyle.Brawler ? 1.2f : style == FightStyle.Counter ? 0.55f : 0.9f;
            if (oppHurt) aggression *= 1.8f;
            if (me.Rocked) aggression *= 0.3f;
            float reach = 0.92f + (style == FightStyle.OutBoxer ? 0.12f : 0f);
            bool inRange = dist < reach;
            // counter after making them miss or blocking
            if (me.counterWindow > 0f && inRange && plan.Count == 0 && !me.Punching && Random.value < 0.6f + skill * 0.3f)
            {
                var c = Random.value < 0.5f ? "2" : Random.value < 0.5f ? "3 2" : "6 3";
                if (style == FightStyle.Counter) c = Random.value < 0.5f ? "p2 3" : "3 p2";
                foreach (var x in Parse(c)) plan.Enqueue(x);
                gap = 0f;
            }
            if (plan.Count == 0 && comboCd <= 0f && inRange && me.stamina > 18f && Random.value < aggression * dt * 2.6f)
            {
                var combo = combos[Random.Range(0, combos.Count)];
                // go downstairs against a high guard, upstairs against a low one
                bool forceBody = opp.guard == 1 && Random.value < 0.6f;
                bool forceHead = opp.guard == 2;
                foreach (var x in combo) plan.Enqueue((x.t, forceHead ? false : x.body || forceBody && x.t != PunchType.Jab, x.power || oppHurt && Random.value < 0.4f));
                comboCd = Mathf.Lerp(1.6f, 0.55f, skill) / Mathf.Max(0.3f, aggression) + tired * 1.2f;
            }
            if (plan.Count > 0 && gap <= 0f && !me.Punching && me.CanAct)
            {
                var n = plan.Dequeue();
                if (dist < Boxing.Get(n.t).reach * 1.25f + 0.15f)
                {
                    me.QueuePunch(n.t, n.body, n.power && me.stamina > 30f);
                    gap = Random.Range(0.02f, 0.12f);
                }
                else plan.Clear();
            }

            // ---------------------------------------------------------- footwork
            if (strafeT <= 0f) { strafeT = Random.Range(1.2f, 3f); strafe = Random.value < 0.5f ? -1f : 1f; }
            float want = desiredRange * (oppHurt ? 0.8f : 1f) * (me.Rocked ? 1.5f : 1f);
            if (plan.Count > 0) want = Mathf.Min(want, 0.85f);
            float fwd = Mathf.Clamp((dist - want) * 2.2f, -1f, 1f);
            float lat = strafe * (style == FightStyle.OutBoxer ? 0.85f : style == FightStyle.Slugger ? 0.25f : 0.5f);
            if (me.OnRopes)
            {
                // spin off the ropes towards the open side
                var toCenter = (me.match.ring.Center - me.transform.position).Flat().normalized;
                lat = Vector3.Dot(toCenter, me.transform.right) > 0f ? 1f : -1f;
                fwd = Mathf.Max(fwd, 0.2f);
            }
            if (opp.OnRopes && (style == FightStyle.Swarmer || style == FightStyle.Brawler || oppHurt)) { lat *= 0.2f; fwd = Mathf.Max(fwd, 0.6f); }
            if (feintT <= 0f && style == FightStyle.OutBoxer && Random.value < 0.01f) { feintT = 0.4f; fwd = 1f; }
            me.move = new Vector2(lat, fwd);

            // ---------------------------------------------------------- showboat
            if (tauntCd <= 0f && me.headHP > opp.headHP + 35f && !me.Punching && Random.value < 0.004f)
            {
                tauntCd = 14f;
                me.Taunt();
                me.match.Pop("SHOWBOAT!", Palette.Magenta, me.HeadPoint + Vector3.up * 0.3f, 0.8f);
                Boxing.Arena?.Excite(0.2f);
            }
        }

        void ChooseDefence(PunchDef p, bool body)
        {
            defendHold = 0.38f;
            defendLean = Vector3.zero; defendGuard = 0;
            float r = Random.value;
            if (body) { defendGuard = 2; if (r < 0.25f) defendLean = new Vector3(0, 0, -1f); return; }
            switch (p.kind)
            {
                case PunchKind.Straight:
                    if (style == FightStyle.Counter && r < 0.65f || r < 0.35f) defendLean = new Vector3(Random.value < 0.5f ? -1f : 1f, -0.1f, 0f);
                    else if (r < 0.55f && skill > 0.6f) { defendGuard = 1; defendHold = 0.2f; } // parry timing
                    else if (r < 0.75f) defendLean = new Vector3(0, -1f, 0);
                    else defendGuard = 1;
                    break;
                case PunchKind.Hook:
                    if (r < 0.5f) defendLean = new Vector3(0, -1f, 0);
                    else defendGuard = 1;
                    break;
                default:
                    if (r < 0.55f) defendLean = new Vector3(0, 0, -1f);
                    else defendGuard = 1;
                    break;
            }
        }
    }
}
