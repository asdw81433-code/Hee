using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public enum QuestKind { Main, Side, Gig, Activity }
    public enum QuestStatus { Inactive, Active, Completed, Failed }
    public enum ObjType { Reach, Kill, Talk, Use, Hack, Collect, Survive, Drive, Custom }

    public class Objective
    {
        public string text;
        public ObjType type;
        public string target;          // location id / group id / npc id / interact id / hack id / item id
        public Vector3? pos;
        public float radius = 10f;
        public int count = 1;
        public int progress;
        public bool optional;
        public bool hideMarker;
        public Func<bool> check;
        public Func<Vector3?> marker;
        public float time;             // survive seconds
        public bool autoCount;         // kill count = whatever the step spawned

        public bool Done => progress >= count;

        public Vector3? MarkerPos
        {
            get
            {
                if (hideMarker || Done) return null;
                if (marker != null) return marker();
                if (pos.HasValue) return pos;
                switch (type)
                {
                    case ObjType.Reach:
                    case ObjType.Drive:
                        return Game.City.Loc(target)?.pos;
                    case ObjType.Talk:
                        {
                            var n = Spawner.FindById(target);
                            if (n != null) return n.rig.HeadPos + Vector3.up * 0.4f;
                            return Game.City.Loc(target)?.pos + Vector3.up * 1.8f;
                        }
                    case ObjType.Hack:
                    case ObjType.Use:
                        {
                            var l = Game.City.Loc(target + "_terminal") ?? Game.City.Loc(target);
                            return l?.pos + Vector3.up * 1.2f;
                        }
                    case ObjType.Kill:
                        {
                            Vector3 sum = Vector3.zero; int n = 0;
                            foreach (var npc in Spawner.Group(target)) if (npc != null && npc.state != NPCState.Dead) { sum += npc.transform.position; n++; }
                            return n > 0 ? sum / n + Vector3.up * 2f : (Vector3?)null;
                        }
                }
                return null;
            }
        }

        public string Display => type switch
        {
            ObjType.Kill => text + (count > 1 ? $" ({progress}/{count})" : ""),
            ObjType.Survive => text + $" ({Mathf.Max(0, Mathf.CeilToInt(time - progressTime))}s)",
            ObjType.Collect => text + (count > 1 ? $" ({progress}/{count})" : ""),
            _ => text
        };
        public float progressTime;
    }

    public class QuestStep
    {
        public string id;
        public string log;
        public readonly List<Objective> objectives = new List<Objective>();
        public Action enter;
        public Action<float> update;
        public Action exit;
        public Func<string> next;     // null = quest complete
        public bool any;              // complete when any non-optional objective is done
        public Func<bool> fail;

        public QuestStep Obj(Objective o) { objectives.Add(o); return this; }
    }

    public class Quest
    {
        public string id, title, giver, summary;
        public QuestKind kind;
        public int money, xp, cred;
        public readonly List<QuestStep> steps = new List<QuestStep>();
        public QuestStatus status;
        public int stepIndex;
        public Action onComplete;
        public string spec;        // serialized generator spec for gigs
        public readonly List<string> log = new List<string>();
        public QuestStep Step => stepIndex >= 0 && stepIndex < steps.Count ? steps[stepIndex] : null;

        public QuestStep AddStep(string id, string logText = null)
        {
            var s = new QuestStep { id = id, log = logText };
            steps.Add(s);
            return s;
        }

        public int IndexOf(string stepId) => steps.FindIndex(s => s.id == stepId);
    }

    /// <summary>Tracks quests, listens to gameplay events and moves objectives forward.</summary>
    public class QuestSystem : MonoBehaviour
    {
        public readonly Dictionary<string, Quest> quests = new Dictionary<string, Quest>();
        public readonly Dictionary<string, DialogueTree> talkOverrides = new Dictionary<string, DialogueTree>();
        public Quest tracked;
        public Func<string, Quest> gigFactory; // rebuilds gigs from a saved spec

        void Awake()
        {
            Game.Quests = this;
            GameEvents.NpcKilled += (npc, info) => { if (!string.IsNullOrEmpty(npc.groupId)) Signal("kill:" + npc.groupId); };
            GameEvents.Interacted += id => Signal("use:" + id);
            GameEvents.HackCompleted += id => Signal("hack:" + id);
            GameEvents.DialogueEnded += id => { };
            GameEvents.ItemAdded += (id, n) => Signal("item:" + id);
        }

        public void Register(Quest q)
        {
            quests[q.id] = q;
        }

        public Quest Get(string id) => id != null && quests.TryGetValue(id, out var q) ? q : null;
        public bool IsActive(string id) => Get(id)?.status == QuestStatus.Active;
        public bool IsDone(string id) => Get(id)?.status == QuestStatus.Completed;

        public void StartQuest(string id, bool announce = true)
        {
            var q = Get(id);
            if (q == null || q.status == QuestStatus.Active || q.status == QuestStatus.Completed) return;
            q.status = QuestStatus.Active;
            q.stepIndex = 0;
            if (tracked == null || tracked.status != QuestStatus.Active || q.kind == QuestKind.Main) tracked = q;
            if (announce)
            {
                Game.UI?.Banner(q.kind == QuestKind.Main ? "NEW JOB" : q.kind == QuestKind.Gig ? "GIG ACCEPTED" : "NEW QUEST", q.title, q.kind == QuestKind.Main ? Palette.Yellow : Palette.Cyan);
                Game.Audio?.Play2D("notify");
            }
            EnterStep(q);
        }

        void EnterStep(Quest q)
        {
            var s = q.Step;
            if (s == null) { Complete(q); return; }
            foreach (var o in s.objectives) { o.progress = 0; o.progressTime = 0; }
            if (!string.IsNullOrEmpty(s.log)) q.log.Add(s.log);
            s.enter?.Invoke();
            // Kill objectives sized by what actually spawned
            foreach (var o in s.objectives)
                if (o.type == ObjType.Kill && (o.count <= 0 || o.autoCount)) { o.autoCount = true; o.count = Mathf.Max(1, Spawner.Alive(o.target)); }
        }

        public void RestartStep(Quest q)
        {
            if (q == null || q.status != QuestStatus.Active) return;
            Spawner.DespawnGroups("q_" + q.id);
            ClearOverridesFor(q);
            EnterStep(q);
        }

        public void RestartActive()
        {
            foreach (var q in new List<Quest>(quests.Values)) if (q.status == QuestStatus.Active) RestartStep(q);
        }

        void ClearOverridesFor(Quest q)
        {
            var remove = new List<string>();
            foreach (var kv in talkOverrides) if (kv.Value.questId == q.id) remove.Add(kv.Key);
            foreach (var k in remove) talkOverrides.Remove(k);
        }

        public void SetTalk(string npcId, DialogueTree tree, Quest owner)
        {
            tree.questId = owner?.id;
            tree.npcId = npcId;
            talkOverrides[npcId] = tree;
        }

        public void ClearTalk(string npcId) => talkOverrides.Remove(npcId);

        /// <summary>Generic signal from gameplay ("kill:group", "use:id", "hack:id", "talk:npc", "item:id").</summary>
        public void Signal(string key)
        {
            foreach (var q in new List<Quest>(quests.Values))
            {
                if (q.status != QuestStatus.Active || q.Step == null) continue;
                bool changed = false;
                foreach (var o in q.Step.objectives)
                {
                    if (o.Done) continue;
                    string want = o.type switch
                    {
                        ObjType.Kill => "kill:" + o.target,
                        ObjType.Talk => "talk:" + o.target,
                        ObjType.Use => "use:" + o.target,
                        ObjType.Hack => "hack:" + o.target,
                        _ => null
                    };
                    if (want != null && want == key) { o.progress++; changed = true; if (o.Done && !o.optional) Game.Audio?.Play2D("ui_confirm", 0.5f); }
                }
                if (changed) Evaluate(q);
            }
        }

        void Update()
        {
            if (!Game.IsPlaying && Game.Manager != null && Game.Manager.State != GameState.Dialogue) return;
            float dt = Time.deltaTime;
            foreach (var q in new List<Quest>(quests.Values))
            {
                if (q.status != QuestStatus.Active || q.Step == null) continue;
                var s = q.Step;
                s.update?.Invoke(dt);
                if (q.status != QuestStatus.Active || q.Step != s) continue;
                bool changed = false;
                foreach (var o in s.objectives)
                {
                    if (o.Done) continue;
                    switch (o.type)
                    {
                        case ObjType.Reach:
                        case ObjType.Drive:
                            {
                                var p = o.pos ?? Game.City.Loc(o.target)?.pos;
                                float r = o.radius > 0 ? o.radius : (Game.City.Loc(o.target)?.radius ?? 10f);
                                if (p.HasValue && Game.HasPlayer && (Game.PlayerPos - p.Value).sqrMagnitude < r * r && Mathf.Abs(Game.PlayerPos.y - p.Value.y) < 12f && (o.type != ObjType.Drive || Game.Player.InVehicle))
                                { o.progress = o.count; changed = true; }
                                break;
                            }
                        case ObjType.Collect:
                            {
                                int n = Game.Inventory != null ? Game.Inventory.Count(o.target) : 0;
                                if (n != o.progress) { o.progress = Mathf.Min(n, o.count); changed = true; }
                                break;
                            }
                        case ObjType.Custom:
                            if (o.check != null && o.check()) { o.progress = o.count; changed = true; }
                            break;
                        case ObjType.Survive:
                            o.progressTime += dt;
                            if (o.progressTime >= o.time) { o.progress = o.count; changed = true; }
                            break;
                        case ObjType.Kill:
                            // groups can also shrink by despawning; count dead + missing
                            break;
                    }
                }
                if (s.fail != null && s.fail())
                {
                    Fail(q, "Objective failed");
                    continue;
                }
                if (changed) Evaluate(q);
            }
        }

        void Evaluate(Quest q)
        {
            var s = q.Step;
            if (s == null) return;
            bool done;
            if (s.any) done = s.objectives.Exists(o => !o.optional && o.Done);
            else done = s.objectives.TrueForAll(o => o.optional || o.Done);
            if (!done) return;
            s.exit?.Invoke();
            string next = s.next != null ? s.next() : null;
            if (next == null && q.stepIndex + 1 < q.steps.Count && s.next == null) q.stepIndex++;
            else if (next == null) { Complete(q); return; }
            else
            {
                int idx = q.IndexOf(next);
                if (idx < 0) { Complete(q); return; }
                q.stepIndex = idx;
            }
            Game.Audio?.Play2D("notify", 0.6f);
            EnterStep(q);
        }

        public void ForceAdvance(Quest q, string stepId = null)
        {
            if (q == null || q.status != QuestStatus.Active) return;
            q.Step?.exit?.Invoke();
            if (stepId == null) q.stepIndex++;
            else q.stepIndex = Mathf.Max(0, q.IndexOf(stepId));
            if (q.stepIndex >= q.steps.Count) { Complete(q); return; }
            EnterStep(q);
        }

        public void Complete(Quest q)
        {
            if (q.status == QuestStatus.Completed) return;
            q.status = QuestStatus.Completed;
            ClearOverridesFor(q);
            var stats = Game.Stats;
            float mult = stats != null ? stats.RewardMult : 1f;
            int money = Mathf.RoundToInt(q.money * mult);
            if (stats != null)
            {
                if (money > 0) stats.AddMoney(money);
                if (q.xp > 0) stats.AddXP(q.xp);
                if (q.cred > 0) stats.AddCred(q.cred);
            }
            Game.UI?.Banner(q.kind == QuestKind.Main ? "JOB COMPLETE" : "COMPLETE", q.title + (money > 0 ? "   +" + Util.Credits(money) : "") + (q.xp > 0 ? "   +" + q.xp + " XP" : ""), Palette.Green);
            Game.Audio?.Play2D("quest_done");
            Spawner.DespawnGroups("q_" + q.id + "_civ");
            if (tracked == q) tracked = NextTracked();
            q.onComplete?.Invoke();
            if (q.kind == QuestKind.Main || q.kind == QuestKind.Side) Game.Manager?.AutoSave();
        }

        public void Fail(Quest q, string reason)
        {
            if (q.kind == QuestKind.Main || q.kind == QuestKind.Side)
            {
                Game.UI?.Banner("MISSION FAILED", reason + " - retrying checkpoint", Palette.Red);
                RestartStep(q);
                return;
            }
            q.status = QuestStatus.Failed;
            ClearOverridesFor(q);
            Spawner.DespawnGroups("q_" + q.id);
            Game.UI?.Banner("FAILED", q.title + ": " + reason, Palette.Red);
            Game.Audio?.Play2D("ui_error");
            if (tracked == q) tracked = NextTracked();
        }

        public void Abandon(Quest q)
        {
            if (q.kind == QuestKind.Main) return;
            q.status = QuestStatus.Failed;
            ClearOverridesFor(q);
            Spawner.DespawnGroups("q_" + q.id);
            if (tracked == q) tracked = NextTracked();
        }

        Quest NextTracked()
        {
            foreach (var q in quests.Values) if (q.status == QuestStatus.Active && q.kind == QuestKind.Main) return q;
            foreach (var q in quests.Values) if (q.status == QuestStatus.Active) return q;
            return null;
        }

        public IEnumerable<Quest> Active
        {
            get { foreach (var q in quests.Values) if (q.status == QuestStatus.Active) yield return q; }
        }

        // ---------------------------------------------------------------- persistence
        public void SaveTo(SaveData d)
        {
            d.quests.Clear();
            foreach (var q in quests.Values)
            {
                if (q.status == QuestStatus.Inactive) continue;
                var qs = new QuestSave { id = q.id, status = (int)q.status, step = q.Step?.id, gigSpec = q.spec };
                d.quests.Add(qs);
            }
            d.trackedQuest = tracked?.id;
        }

        public void LoadFrom(SaveData d)
        {
            foreach (var q in quests.Values) { q.status = QuestStatus.Inactive; q.stepIndex = 0; }
            talkOverrides.Clear();
            foreach (var qs in d.quests)
            {
                var q = Get(qs.id);
                if (q == null && !string.IsNullOrEmpty(qs.gigSpec) && gigFactory != null) q = gigFactory(qs.gigSpec);
                if (q == null) continue;
                q.status = (QuestStatus)qs.status;
                q.stepIndex = Mathf.Max(0, q.IndexOf(qs.step));
            }
            tracked = Get(d.trackedQuest);
            // re-enter active steps so spawns/dialogue overrides exist again
            foreach (var q in new List<Quest>(quests.Values)) if (q.status == QuestStatus.Active) EnterStep(q);
            if (tracked == null || tracked.status != QuestStatus.Active) tracked = NextTracked();
        }
    }
}
