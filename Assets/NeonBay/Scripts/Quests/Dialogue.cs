using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public class DChoice
    {
        public string text;
        public string next;
        public string tag;            // shown in brackets, e.g. [COOL 6]
        public Func<bool> visible;
        public Func<bool> enabled;
        public Action act;
        public bool IsVisible => visible == null || visible();
        public bool IsEnabled => enabled == null || enabled();
    }

    public class DNode
    {
        public string id, speaker, text;
        public readonly List<DChoice> choices = new List<DChoice>();
        public string next;
        public Action enter;
    }

    public class DialogueTree
    {
        public string id, npcId, questId;
        public readonly Dictionary<string, DNode> nodes = new Dictionary<string, DNode>();
        public string start = "start";
        public Action onEnd;
        DNode last;

        public DialogueTree(string id) { this.id = id; }

        public DialogueTree Say(string nodeId, string speaker, string text, string next = null, Action enter = null)
        {
            var n = new DNode { id = nodeId, speaker = speaker, text = text, next = next, enter = enter };
            nodes[nodeId] = n;
            last = n;
            if (nodes.Count == 1) start = nodeId;
            return this;
        }

        public DialogueTree Opt(string text, string next, Action act = null, Func<bool> visible = null, string tag = null, Func<bool> enabled = null)
        {
            last.choices.Add(new DChoice { text = text, next = next, act = act, visible = visible, tag = tag, enabled = enabled });
            return this;
        }

        /// <summary>Skill check option: shown to everyone, only selectable when the attribute is high enough.</summary>
        public DialogueTree Check(Attr a, int level, string text, string next, Action act = null)
        {
            return Opt(text, next, act, null, "[" + a.ToString().ToUpperInvariant() + " " + level + "]", () => Game.Stats != null && Game.Stats.Attr(a) >= level);
        }

        /// <summary>Origin-exclusive option: only visible for that background.</summary>
        public DialogueTree Origin(Origin o, string text, string next, Action act = null)
        {
            return Opt(text, next, act, () => Game.Profile != null && Game.Profile.origin == o, "[" + CharacterProfile.OriginName(o).ToUpperInvariant() + "]");
        }

        public DialogueTree Pay(int cost, string text, string next, Action act = null)
        {
            return Opt(text, next, () => { Game.Stats.Spend(cost); act?.Invoke(); }, null, "[$" + cost + "]", () => Game.Stats != null && Game.Stats.Money >= cost);
        }

        public DialogueTree End(Action act = null) { last.next = null; if (act != null) { var prev = last.enter; last.enter = () => { prev?.Invoke(); act(); }; } return this; }
    }

    /// <summary>Runs dialogue trees; the UI reads Current/Node and calls Choose.</summary>
    public class DialogueSystem : MonoBehaviour
    {
        public DialogueTree Current { get; private set; }
        public DNode Node { get; private set; }
        public NPC Speaker { get; private set; }
        public float typeProgress;
        readonly Dictionary<string, Func<NPC, DialogueTree>> defaults = new Dictionary<string, Func<NPC, DialogueTree>>();

        void Awake() { Game.Dialogue = this; }

        public void RegisterDefault(string npcId, Func<NPC, DialogueTree> make) => defaults[npcId] = make;

        public void TalkTo(NPC npc)
        {
            if (npc == null) return;
            DialogueTree tree = null;
            if (!string.IsNullOrEmpty(npc.npcId) && Game.Quests != null && Game.Quests.talkOverrides.TryGetValue(npc.npcId, out var t)) tree = t;
            if (tree == null && !string.IsNullOrEmpty(npc.npcId) && defaults.TryGetValue(npc.npcId, out var f)) tree = f(npc);
            if (tree == null && !string.IsNullOrEmpty(npc.shopId) && npc.shopId != "fixer" && npc.shopId != "ring") { Game.UI?.OpenShop(npc.shopId, npc.displayName); return; }
            if (tree == null)
            {
                Game.UI?.Bark(npc, SmallTalk.Line(npc));
                return;
            }
            Begin(tree, npc);
        }

        public void Begin(DialogueTree tree, NPC npc)
        {
            Current = tree;
            Speaker = npc;
            Game.Manager?.SetState(GameState.Dialogue);
            Go(tree.start);
        }

        void Go(string nodeId)
        {
            if (nodeId == null || !Current.nodes.TryGetValue(nodeId, out var n)) { Finish(); return; }
            Node = n;
            typeProgress = 0f;
            n.enter?.Invoke();
            if (Current == null) return; // enter action may have ended the dialogue (e.g. opened a shop)
            Game.Audio?.Play2D("ui_blip", 0.25f);
        }

        public List<DChoice> VisibleChoices()
        {
            var l = new List<DChoice>();
            if (Node == null) return l;
            foreach (var c in Node.choices) if (c.IsVisible) l.Add(c);
            return l;
        }

        public void Continue()
        {
            if (Node == null) return;
            if (typeProgress < 1f) { typeProgress = 1f; return; }
            if (VisibleChoices().Count > 0) return;
            Go(Node.next);
        }

        public void Choose(DChoice c)
        {
            if (c == null || !c.IsEnabled) { Game.Audio?.Play2D("ui_error", 0.5f); return; }
            Game.Audio?.Play2D("ui_confirm", 0.5f);
            c.act?.Invoke();
            if (Current == null) return;
            Go(c.next);
        }

        public void Finish()
        {
            var tree = Current;
            var npc = Speaker;
            Current = null; Node = null; Speaker = null;
            if (Game.Manager != null && Game.Manager.State == GameState.Dialogue) Game.Manager.SetState(GameState.Playing);
            if (tree != null)
            {
                tree.onEnd?.Invoke();
                GameEvents.RaiseDialogueEnded(tree.id);
                if (!string.IsNullOrEmpty(tree.npcId)) Game.Quests?.Signal("talk:" + tree.npcId);
                else if (npc != null && !string.IsNullOrEmpty(npc.npcId)) Game.Quests?.Signal("talk:" + npc.npcId);
            }
        }

        /// <summary>Ends dialogue immediately without firing quest signals (used when a node opens another screen).</summary>
        public void Abort()
        {
            Current = null; Node = null; Speaker = null;
        }

        void Update()
        {
            if (Current == null) return;
            typeProgress = Mathf.Min(1f, typeProgress + Time.unscaledDeltaTime * 60f / Mathf.Max(20f, Node != null && Node.text != null ? Node.text.Length : 20f));
            if (Speaker != null && Game.Player != null) Game.Player.LookAt(Speaker.rig.HeadPos, 5f);
        }
    }

    public static class SmallTalk
    {
        static readonly string[] civ =
        {
            "Rain again. Acid count's high, keep your collar up.", "You lost? Market's that way. Everything's that way.",
            "Don't look at the Helix drones. They remember faces.", "Eh. Whatever it is, it'll pass. Or it won't.",
            "My cousin got his arms chromed at Doc Reyes'. Now he can't stop arm-wrestling strangers.",
            "Metro's late again. Somebody jumped the third rail. Or got pushed.", "Got a light? Nah, forget it. The smog's enough.",
            "Heard the Saints hijacked the billboards in the Spire last night. Played cartoons for an hour.",
            "Watch your wallet near the Docks. And your kidneys.", "Hungry? The chili dogs at the night market are real beef. Mostly."
        };
        static readonly string[] vendor = { "Best prices in the Bay, I swear on my grandmother's implants.", "Buying or browsing? Browsing costs extra.", "Come back when you've got creds, friend." };

        public static string Line(NPC npc)
        {
            if (npc.archetype == Archetype.Vendor) return vendor[UnityEngine.Random.Range(0, vendor.Length)];
            if (npc.faction == FactionId.Police) return "Move along, citizen. Keep your hands where I can see them.";
            if (npc.faction == FactionId.Jackals) return "Eyes down, choom. This block belongs to the Jackals.";
            if (npc.faction == FactionId.Lotus) return "Madame doesn't take meetings with strangers.";
            return civ[UnityEngine.Random.Range(0, civ.Length)];
        }
    }
}
