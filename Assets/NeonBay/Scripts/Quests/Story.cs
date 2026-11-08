using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// The main story "Static Saints" (7 chapters, 4 endings) plus hand-written side quests.
    /// </summary>
    public static class Story
    {
        static QuestSystem QS => Game.Quests;

        // ------------------------------------------------------------------ helpers
        static Quest Q(string id, string title, string giver, string summary, QuestKind kind, int money, int xp, int cred)
        {
            var q = new Quest { id = id, title = title, giver = giver, summary = summary, kind = kind, money = money, xp = xp, cred = cred };
            QS.Register(q);
            return q;
        }

        static Objective Reach(string text, string loc, float r = 0) => new Objective { text = text, type = ObjType.Reach, target = loc, radius = r };
        static Objective Talk(string text, string npc, bool optional = false) => new Objective { text = text, type = ObjType.Talk, target = npc, optional = optional };
        static Objective Kill(string text, string group) => new Objective { text = text, type = ObjType.Kill, target = group, count = 0 };
        static Objective Use(string text, string id, Vector3? pos = null) => new Objective { text = text, type = ObjType.Use, target = id, pos = pos };
        static Objective Hack(string text, string id) => new Objective { text = text, type = ObjType.Hack, target = id };
        static Objective Custom(string text, Func<bool> f, Func<Vector3?> marker = null, bool hide = false) => new Objective { text = text, type = ObjType.Custom, check = f, marker = marker, hideMarker = hide && marker == null };
        static Objective Survive(string text, float s) => new Objective { text = text, type = ObjType.Survive, time = s, hideMarker = true };

        public static void Call(string speaker, params string[] lines)
        {
            Game.Audio?.Play2D("phone", 0.5f);
            foreach (var l in lines) Game.UI?.Subtitle(speaker, l, Mathf.Clamp(l.Length * 0.065f, 2.5f, 7f), Palette.Yellow);
        }

        public static void June(params string[] lines)
        {
            Game.UI?.Glitch(0.35f);
            foreach (var l in lines) Game.UI?.Subtitle("JUNE", l, Mathf.Clamp(l.Length * 0.065f, 2.5f, 7f), Palette.Cyan);
        }

        static Vector3 LocPos(string id) => Game.City.Loc(id)?.pos ?? Game.PlayerPos;

        static NPC StoryNpc(string id, string name, FactionId f, string locId, Vector3 offset, Appearance look, Archetype a = Archetype.Vendor, string weapon = "fists")
        {
            var p = LocPos(locId) + offset;
            p = Spawner.FreeSpot(p, 1.5f);
            var toward = (LocPos(locId) - p).Flat();
            return Spawner.Story(id, name, f, p, toward.sqrMagnitude > 0.1f ? toward : Vector3.back, look, a, weapon);
        }

        static Appearance Look(Color jacket, Color accent, int hair, Color hairCol, bool visor = false, bool helmet = false, float bulk = 1f)
            => new Appearance { jacket = jacket, accent = accent, hair = hair, hairColor = hairCol, visor = visor, helmet = helmet, bulk = bulk, skin = Palette.SkinTones[2], pants = new Color(0.06f, 0.06f, 0.07f), eyes = accent };

        static Vector3 Off(float x, float z) => new Vector3(x, 0, z);

        // ------------------------------------------------------------------ registration
        public static void Register()
        {
            Prologue();
            MarketRot();
            GhostSignals();
            Highway();
            GhostInWire();
            ThreeDoors();
            FinaleHelix();
            FinaleLotus();
            FinaleSaints();
            SideQuests();
            Defaults();
        }

        public static void StartNewGame()
        {
            QS.StartQuest("m0");
        }

        /// <summary>Puts every quest back to its initial state (new game / before loading).</summary>
        public static void ResetQuests()
        {
            if (QS == null) return;
            var gigs = new List<string>();
            foreach (var kv in QS.quests)
            {
                kv.Value.status = QuestStatus.Inactive;
                kv.Value.stepIndex = 0;
                kv.Value.log.Clear();
                if (kv.Key.StartsWith("gig_")) gigs.Add(kv.Key);
            }
            foreach (var g in gigs) QS.quests.Remove(g);
            QS.talkOverrides.Clear();
            QS.tracked = null;
        }

        // ------------------------------------------------------------------ chapter 0
        static void Prologue()
        {
            var q = Q("m0", "Static Dreams", "Mama Sol", "Mama Sol has work. Real creds. Get to her noodle shop in the Neon Strip.", QuestKind.Main, 150, 120, 2);
            q.AddStep("inbox", "Woke up in Mega-Block 7. Messages waiting.").Obj(Use("Check the messages on your terminal", "apt_terminal")).enter = () =>
            {
                June("...the lotus... is opening...");
                Game.UI?.Hint("Walk with WASD, look with the mouse. Press [E] to use the terminal.");
            };
            var s1 = q.AddStep("out");
            s1.Obj(Use("Head outside", "apt_exit"));
            s1.enter = () => Game.UI?.Hint("The door is behind you. Sprint with [SHIFT], crouch with [C], jump with [SPACE].");
            var s2 = q.AddStep("go", "Mama Sol is waiting at her noodle bar.");
            s2.Obj(Reach("Go to Mama Sol's noodle shop (Neon Strip)", "mamasol", 8));
            s2.enter = () => Game.UI?.Hint("Follow the yellow marker. [M] opens the map. Metro stations offer fast travel once discovered. Any car can be taken with [F].");
            var s3 = q.AddStep("talk");
            s3.Obj(Talk("Talk to Mama Sol", "mamasol"));
            s3.enter = () =>
            {
                var t = new DialogueTree("m0_mamasol");
                t.Say("start", "MAMA SOL", "There you are. You look like something the bay spat out.")
                    .Opt("Good to see you too, Sol.", "job")
                    .Origin(Origin.GutterKid, "Same bay that spat you out, Sol.", "gk", () => Game.Stats.AddCred(5))
                    .Origin(Origin.CorpWashout, "I used to have a corner office, you know.", "corp")
                    .Origin(Origin.BadlandsRunner, "Your coffee still tastes like engine coolant.", "bad");
                t.Say("gk", "MAMA SOL", "Ha! Twenty years and you still have a mouth on you. Good. You'll need it.", "job");
                t.Say("corp", "MAMA SOL", "And now you have a corner booth. Progress. Helix chewed you up and spat you out - let's see if you can bite back.", "job");
                t.Say("bad", "MAMA SOL", "That's the secret ingredient. Sit. Eat. Listen.", "job");
                t.Say("job", "MAMA SOL", "Big job coming. Helix Dynamics is moving something through the Scar. A prototype. They call it LOTUS. My buyer pays enough for both of us to retire.")
                    .Opt("What's the catch?", "catch")
                    .Opt("I'm in.", "in");
                t.Say("catch", "MAMA SOL", "The catch is you're nobody yet, and nobody gets nothing. First you prove you can handle yourself.", "in");
                t.Say("in", "MAMA SOL", "The Chrome Jackals are squeezing my vendors at Neon Crossing. Make them stop. Talk, pay, break bones - I don't care how.");
                QS.SetTalk("mamasol", t, q);
            };
            q.onComplete = () => QS.StartQuest("m1");
        }

        // ------------------------------------------------------------------ chapter 1
        static void MarketRot()
        {
            var q = Q("m1", "Market Rot", "Mama Sol", "The Chrome Jackals are shaking down Mama Sol's vendors at Neon Crossing.", QuestKind.Main, 600, 280, 5);
            q.AddStep("go").Obj(Reach("Go to Neon Crossing", "market_square", 22));
            var c = q.AddStep("confront", "Jett's crew is shaking down the stalls.");
            c.Obj(Talk("Confront Jett, the Jackal lieutenant", "jett"));
            c.enter = () =>
            {
                Flags.Clear("m1_fight"); Flags.Clear("m1_peace");
                var center = LocPos("market_square");
                Spawner.Squad("q_m1_jackals", FactionId.Jackals, center, 7f, 4, 2, false, Archetype.Grunt, Archetype.Bruiser, Archetype.Grunt, Archetype.Gunner);
                var jettLook = Appearance.Random(FactionId.Jackals, new Rng(66));
                jettLook.hair = 2; jettLook.hairColor = Palette.Orange; jettLook.chromeArm = true; jettLook.bulk = 1.15f;
                StoryNpc("jett", "Jett", FactionId.Jackals, "market_square", Off(1.5f, 1.5f), jettLook, Archetype.Vendor, "kite9");
                var t = new DialogueTree("m1_jett");
                t.Say("start", "JETT", "Well, well. Mama Sol's new errand runner. This market pays the Jackal tax now. Turn around and walk away.")
                    .Opt("Make me.", "fight", () => Flags.Set("m1_fight"))
                    .Check(Attr.Cool, 5, "Mama Sol is under Lotus protection. You want a war with Madame Lotus over diner money?", "bluff", () => Flags.Set("m1_peace"))
                    .Origin(Origin.GutterKid, "Jett. Overpass 14. I pulled you out of the floodwater when we were nine.", "gk", () => { Flags.Set("m1_peace"); Game.Stats.AddCred(5); })
                    .Pay(300, "Here. Tax paid. Now go.", "paid", () => { Flags.Set("m1_peace"); Flags.Set("m1_paid"); });
                t.Say("fight", "JETT", "Hah! Boys - chrome 'em!");
                t.Say("bluff", "JETT", "...Tch. The Lotus. Fine. This block isn't worth it. Yet.");
                t.Say("gk", "JETT", "...You. Damn it. We're done here, boys. This one's free. Once.");
                t.Say("paid", "JETT", "Smart. Pleasure doing business.");
                QS.SetTalk("jett", t, q);
            };
            c.next = () => Flags.Has("m1_fight") ? "fight" : "peace";
            var f = q.AddStep("fight", "It turned ugly.");
            f.Obj(Kill("Defeat Jett's crew", "q_m1_jackals"));
            f.enter = () =>
            {
                var jp = Spawner.FindById("jett");
                var pos = jp != null ? jp.transform.position : LocPos("market_square");
                Spawner.Remove("jett");
                var jettLook = Appearance.Random(FactionId.Jackals, new Rng(66));
                jettLook.hair = 2; jettLook.hairColor = Palette.Orange; jettLook.chromeArm = true;
                Spawner.Spawn(Archetype.Boss, FactionId.Jackals, pos, 0, 3, "q_m1_jackals", true, "thunderhead", "Jett", jettLook);
                foreach (var n in Spawner.Group("q_m1_jackals")) if (n != null) { n.forcedHostile = true; n.EngageTarget(Game.Stats.dmg); }
            };
            f.next = () => "report";
            var p = q.AddStep("peace", "Jett backed off.");
            p.Obj(Custom("The Jackals leave the market", () => true, null, true));
            p.enter = () =>
            {
                Spawner.Remove("jett");
                Spawner.DespawnGroups("q_m1_jackals");
                Game.UI?.Notify("The Jackals melt back into the crowd.", Palette.Orange);
            };
            p.next = () => "report";
            var r = q.AddStep("report");
            r.Obj(Talk("Report back to Mama Sol", "mamasol"));
            r.enter = () =>
            {
                var t = new DialogueTree("m1_report");
                t.Say("start", "MAMA SOL", Flags.Has("m1_fight") ? "Bodies in my market. Bad for business... but very good for your reputation." : "Not a drop of blood in my broth. I like your style.", "job");
                t.Say("job", "MAMA SOL", "Now the real work. Helix encrypts its convoy routes. Three comm relays in the Port Marrow Docks carry the key. Breach all three and bring me the data.")
                    .Opt("Who's guarding them?", "guards")
                    .Opt("Consider it done.", "end");
                t.Say("guards", "MAMA SOL", "Lotus smugglers rent the yards. They shoot first and invoice later. Hold [TAB] to scan - you can breach a terminal with your deck, or by hand if you stand at it long enough.", "end");
                t.Say("end", "MAMA SOL", "Go. And eat something first, you look like a ghost.");
                QS.SetTalk("mamasol", t, q);
            };
            q.onComplete = () => QS.StartQuest("m2");
        }

        // ------------------------------------------------------------------ chapter 2
        static void GhostSignals()
        {
            var q = Q("m2", "Ghost Signals", "Mama Sol", "Breach three Helix comm relays in the Port Marrow Docks to steal the convoy routing key.", QuestKind.Main, 800, 380, 6);
            var s = q.AddStep("relays", "The relays are in Lotus-controlled container yards.");
            s.Obj(Hack("Breach Comms Relay A", "relay_1")).Obj(Hack("Breach Comms Relay B", "relay_2")).Obj(Hack("Breach Comms Relay C", "relay_3"));
            var spawned = new bool[3];
            s.enter = () =>
            {
                for (int i = 0; i < 3; i++) spawned[i] = false;
                Call("MAMA SOL", "Relays are marked. Quiet or loud, your call.");
            };
            s.update = dt =>
            {
                for (int i = 0; i < 3; i++)
                {
                    if (spawned[i]) continue;
                    var l = Game.City.Loc("relay_" + (i + 1));
                    if (l == null || (Game.PlayerPos - l.pos).sqrMagnitude > 170f * 170f) continue;
                    spawned[i] = true;
                    var mix = i == 2 ? new[] { Archetype.Gunner, Archetype.Netrunner, Archetype.Shotgunner, Archetype.Grunt, Archetype.Sniper } : new[] { Archetype.Grunt, Archetype.Gunner, Archetype.Shotgunner, Archetype.Grunt };
                    Spawner.Squad("q_m2_r" + i, FactionId.Lotus, l.pos, 22f, mix.Length, 3 + i, true, mix);
                }
            };
            var d = q.AddStep("dok", "The data is scrambled. Dutch can decode it.");
            d.Obj(Talk("Bring the relay data to Dutch's Garage", "fixer_dutch"));
            d.enter = () =>
            {
                Call("MAMA SOL", "Got it - but it's scrambled. Take it to Dutch at his garage in the Docks. He owes me.");
                var t = new DialogueTree("m2_dok");
                t.Say("start", "DUTCH", "Mama Sol's courier, huh? Give it here... Mm. Convoy leaves the Spire tonight, routes through the Scar. Two vehicles, Helix escort.")
                    .Check(Attr.Tech, 5, "Can you backdoor the convoy autopilot? Stall it where we want it.", "tech", () => Flags.Set("m3_autopilot"))
                    .Opt("Anything else I should know?", "info")
                    .Opt("Thanks, Dutch.", "bye");
                t.Say("tech", "DUTCH", "Port 4096... heh. Helix never patches. Done. The convoy will stall at the ambush point and their heavy stays asleep in the van.", "bye");
                t.Say("info", "DUTCH", "Yeah. Whatever they're hauling is cold-stored at minus forty. That's not hardware, friend. That's somebody.", "bye");
                t.Say("bye", "DUTCH", "Get a fast car - there's always something parked on the curb. And try not to die; I hate cleaning up after Sol's people.");
                QS.SetTalk("fixer_dutch", t, q);
            };
            q.onComplete = () => { Game.Inventory.Add("relay_key", 1, false); QS.StartQuest("m3"); };
        }

        // ------------------------------------------------------------------ chapter 3
        static void Highway()
        {
            var q = Q("m3", "Highway to the Scar", "Mama Sol", "Ambush the Helix convoy in the Scar and take the LOTUS prototype.", QuestKind.Main, 1500, 520, 10);
            var go = q.AddStep("go", "Convoy route located.");
            go.Obj(Reach("Reach the ambush point in the Scar (a vehicle helps: [F] near any car)", "convoy", 45));
            Vehicle van = null;
            var amb = q.AddStep("ambush", "Helix escort engaged.");
            amb.Obj(Kill("Eliminate the Helix escort", "q_m3_helix"));
            amb.enter = () =>
            {
                var l = Game.City.Loc("convoy");
                var pos = l.pos;
                van = Vehicle.Create(VehicleType.Van, pos + Vector3.up * 0.3f, Quaternion.LookRotation(Vector3.forward), VehicleMode.Abandoned, 2);
                Vehicle.Create(VehicleType.Sedan, pos + Vector3.back * 10f + Vector3.up * 0.3f, Quaternion.LookRotation(Vector3.forward), VehicleMode.Abandoned, 2);
                var mix = Flags.Has("m3_autopilot")
                    ? new[] { Archetype.Gunner, Archetype.Grunt, Archetype.Grunt, Archetype.Sniper }
                    : new[] { Archetype.Gunner, Archetype.Grunt, Archetype.Grunt, Archetype.Sniper, Archetype.Heavy, Archetype.Gunner };
                Spawner.Squad("q_m3_helix", FactionId.Helix, pos, 14f, mix.Length, 4, true, mix);
                Drone.Spawn(FactionId.Helix, pos + Vector3.up * 12f, 4, "q_m3_drone");
                if (!Flags.Has("m3_autopilot")) Drone.Spawn(FactionId.Helix, pos + Vector3.up * 14f + Vector3.right * 8f, 4, "q_m3_drone");
                Call("MAMA SOL", Flags.Has("m3_autopilot") ? "Dutch's trick worked - they're stalled. Hit them now!" : "They're on alert. Hit them hard!");
            };
            var cs = q.AddStep("case");
            cs.Obj(Use("Grab the LOTUS case from the van", "convoy_case"));
            cs.enter = () =>
            {
                var p = van != null ? van.transform.position - van.transform.forward * 3.2f : LocPos("convoy");
                var qo = Interactable.Create<QuestObject>("LotusCase", null, p, new Vector3(0.8f, 0.6f, 0.6f), Vector3.forward, Layers.Triggers);
                qo.id = "convoy_case"; qo.prompt = "Open the cryo-case";
                Util.Primitive(PrimitiveType.Cube, "Case", qo.transform, new Vector3(0, 0.3f, 0), new Vector3(0.8f, 0.5f, 0.5f), Mats.Cached("cryo", () => Mats.Emissive(new Color(0.8f, 0.85f, 0.9f), Palette.Cyan * 2f)));
                qo.GetComponent<BoxCollider>().isTrigger = true;
                UnityEngine.Object.Destroy(qo.gameObject, 600f);
            };
            var sl = q.AddStep("slot", "The case is self-destructing.");
            sl.Obj(Use("Slot the LOTUS chip into your neural port", "slot_chip"));
            sl.enter = () =>
            {
                Call("MAMA SOL", "The case is cooking itself - self-destruct! Slot the chip into your deck NOW or we lose everything!");
                var p = (van != null ? van.transform.position - van.transform.forward * 3.2f : LocPos("convoy")) + Vector3.right * 0.8f;
                var qo = Interactable.Create<QuestObject>("SlotChip", null, p, new Vector3(0.5f, 1.2f, 0.5f), Vector3.forward, Layers.Triggers);
                qo.id = "slot_chip"; qo.prompt = "Slot the chip (no going back)";
                qo.GetComponent<BoxCollider>().isTrigger = true;
                var vis = Util.Primitive(PrimitiveType.Cube, "Chip", qo.transform, new Vector3(0, 1f, 0), new Vector3(0.12f, 0.02f, 0.18f), Mats.Cached("chipglow", () => Mats.Unlit(Palette.Cyan * 5f)));
                vis.AddComponent<Spinner>().speed = 90f;
                UnityEngine.Object.Destroy(qo.gameObject, 600f);
            };
            sl.exit = () =>
            {
                Game.Inventory.Add("lotus_chip", 1, false);
                Game.UI?.Glitch(2f);
                Game.Audio?.Play2D("glitch", 1f);
                Game.Fx?.ElectricBurst(Game.PlayerPos + Vector3.up, 3f);
            };
            var kh = q.AddStep("june", "Something is talking inside your head.");
            kh.Obj(Reach("Get to Doc Reyes' clinic - fast", "clinic", 6));
            kh.enter = () =>
            {
                June("...where... is this? It's so loud in here.", "You're thinking. I can hear you thinking. Oh no. Oh no, no...", "My name is June. I think... I think I'm inside you.");
                Call("MAMA SOL", "Kid? Kid! Talk to me. ...Get to Doc Reyes. Now.");
            };
            q.onComplete = () => QS.StartQuest("m4");
        }

        // ------------------------------------------------------------------ chapter 4
        static void GhostInWire()
        {
            var q = Q("m4", "Ghost in the Wire", "Doc Reyes", "The LOTUS chip holds a person - and she's bonding with your brain.", QuestKind.Main, 0, 520, 5);
            var d = q.AddStep("doc");
            d.Obj(Talk("Let Doc Reyes examine you", "clinic"));
            d.enter = () =>
            {
                var t = new DialogueTree("m4_doc");
                t.Say("start", "DOC REYES", "Sit. Don't touch anything chrome. ...Oh. Oh, that's bad. That chip has wrapped itself around your brainstem like kudzu on a fence.")
                    .Opt("Can you take it out?", "out")
                    .Opt("Is it dangerous?", "danger");
                t.Say("out", "DOC REYES", "Not without taking you out with it. It's bonding. Give it a few weeks and there won't be a 'you' and an 'it' anymore.", "june");
                t.Say("danger", "DOC REYES", "It's a person. Compressed. A whole mind - memories, fears, the lot. Two minds don't fit in one skull for long.", "june");
                t.Say("june", "JUNE", "I'm not trying to hurt you. I didn't ask to be put in a box. I was... I was at the pumps. Then there was a white room. Then nothing. Please. Let me help.")
                    .Opt("I'll trust you. For now.", "trust", () => Flags.Set("trust_june"))
                    .Opt("Stay out of my head.", "distrust");
                t.Say("trust", "DOC REYES", "Talking to the voices already. Wonderful. Mama Sol paid for an upgrade, by the way. Pick one - on the house.", "gift");
                t.Say("distrust", "JUNE", "...It's my head too, now. I'm sorry.", "gift2");
                t.Say("gift2", "DOC REYES", "Mama Sol paid for an upgrade, by the way. Pick one - on the house.", "gift");
                t.Say("gift", "DOC REYES", "Choose your chrome:")
                    .Opt("Vantablink Optics Mk.I (crit chance, scanner zoom)", "done", () => Game.Stats.Install(CyberwareDB.Get("optics_mk1")))
                    .Opt("Synapse Deck Mk.I (+2 RAM, stronger hacks)", "done", () => Game.Stats.Install(CyberwareDB.Get("deck_mk1")))
                    .Opt("Subdermal Plating (+40 armor)", "done", () => Game.Stats.Install(CyberwareDB.Get("subdermal")));
                t.Say("done", "DOC REYES", "Done. Go home. Sleep. Whatever is in there will want to talk when your guard is down.");
                QS.SetTalk("clinic", t, q);
            };
            var s = q.AddStep("sleep");
            s.Obj(Use("Go home and sleep", "apt_bed"));
            var dr = q.AddStep("dream");
            dr.Obj(Custom("Wake up", () => Game.UI != null && !Game.UI.LoreOpen, null, true));
            dr.enter = () =>
            {
                Game.UI?.ShowLore("MEMORY // FLOOD YEAR 2061",
                    "Water to the knees in Lowtown. A crowd behind you, lanterns, wet banners. The Helix pump station is locked and the gates are welded. You - she - climbs the fence. Someone below is supposed to cut the power to the alarms. They don't. The floodlights come on.\n\n" +
                    "\"Open the pumps!\" Thousands of voices. The gates open. The water drains from forty blocks. Then hands on your shoulders, a van, a white room, a needle that hums.\n\n" +
                    "Twenty-eight years of nothing.\n\nThen you.");
                June("That was me. That was the last thing I remember being.", "Someone is calling you. Three someones. Everyone wants what's in your head.");
                Call("UNKNOWN", "This is Director Ingrid Voss, Helix Dynamics. You have our property. Let's be adults. Helix lobby, any time.");
                Call("MADAME LOTUS", "Darling. Whatever Helix offers, I'll double. The Lotus Club. Ask for me.");
                Call("NOVA", "We're the Static Saints. We know who June is. Docks, the old warehouse with the DATA sign. Come alone.");
            };
            q.onComplete = () => QS.StartQuest("m5");
        }

        // ------------------------------------------------------------------ chapter 5
        static void ThreeDoors()
        {
            var q = Q("m5", "Three Doors", "June", "Helix, the Lotus and the Static Saints all want June. Hear them out - then choose.", QuestKind.Main, 0, 400, 5);
            var s = q.AddStep("offers");
            s.Obj(Talk("(Optional) Hear Director Voss - Helix lobby", "voss", true));
            s.Obj(Talk("(Optional) Hear Madame Lotus - Lotus Club", "lotus", true));
            s.Obj(Talk("(Optional) Hear Nova - Static Saints Den", "nova", true));
            s.Obj(Custom("Decide who gets June", () => Flags.Has("path_helix") || Flags.Has("path_lotus") || Flags.Has("path_saints"), null, true));
            s.enter = () =>
            {
                var helixLook = Look(new Color(0.9f, 0.9f, 0.92f), Palette.White, 1, new Color(0.85f, 0.8f, 0.6f), false, false, 0.95f);
                StoryNpc("voss", "Director Voss", FactionId.Helix, "helix_lobby", Off(-2.5f, -3f), helixLook);
                var lotusLook = Look(new Color(0.2f, 0.02f, 0.05f), Palette.Magenta, 3, new Color(0.05f, 0.04f, 0.05f), false, false, 0.9f);
                StoryNpc("lotus", "Madame Lotus", FactionId.Lotus, "lotus_vip", Off(0, 1.5f), lotusLook);
                var novaLook = Look(new Color(0.06f, 0.22f, 0.12f), Palette.Green, 0, Color.black, true);
                StoryNpc("nova", "Nova", FactionId.Saints, "saints_inside", Off(0, 2f), novaLook);
                Factions.Calm(FactionId.Lotus); Factions.Calm(FactionId.Helix);

                var v = new DialogueTree("m5_voss");
                v.Say("start", "DIRECTOR VOSS", "You have something of ours. Helix is generous with partners. Bring the asset to our Spire uplink and you'll never worry about rent - or anything - again.")
                    .Opt("What happens to June?", "k")
                    .Opt("Deal. Helix it is.", "deal", () => { Flags.Set("path_helix"); Flags.Set("helix_access"); })
                    .Opt("I'll think about it.", "bye");
                v.Say("k", "DIRECTOR VOSS", "'June' is a data structure. She'll be integrated into the city management core. She'll help run Neon Bay. Isn't that what she always wanted?", "kk");
                v.Say("kk", "JUNE", "That's a lie. They'll grind me into firmware and use my voice to sell water back to people.")
                    .Opt("Deal. Helix it is.", "deal", () => { Flags.Set("path_helix"); Flags.Set("helix_access"); })
                    .Opt("Not yet.", "bye");
                v.Say("deal", "DIRECTOR VOSS", "Excellent. The elevator will recognise you. Come to the roof. We'll take it from there.");
                v.Say("bye", "DIRECTOR VOSS", "Don't take too long. The asset's integrity degrades. So does yours.");
                QS.SetTalk("voss", v, q);

                var l = new DialogueTree("m5_lotus");
                l.Say("start", "MADAME LOTUS", "Sit, darling. Helix wants that chip, so I want that chip. With her secrets I'll own Helix - and through Helix, the city. You'd be my right hand.")
                    .Opt("And June?", "k")
                    .Opt("Deal.", "deal", () => Flags.Set("path_lotus"))
                    .Opt("Let me think.", "bye");
                l.Say("k", "MADAME LOTUS", "In my vault. Safe, quiet, valuable. Like all my treasures. She won't feel a thing.", "kk");
                l.Say("kk", "JUNE", "A vault is just a nicer box.")
                    .Opt("Deal.", "deal", () => Flags.Set("path_lotus"))
                    .Check(Attr.Cool, 7, "Why do you really want her?", "real")
                    .Opt("Not yet.", "bye");
                l.Say("real", "MADAME LOTUS", "...Because I was there in 2061, darling. I sold Helix the names of the protesters. June's name. She is the only thing in this city that can still hurt me.", "kk2");
                l.Say("kk2", "JUNE", "...")
                    .Opt("Deal anyway.", "deal", () => Flags.Set("path_lotus"))
                    .Opt("Goodbye, Madame.", "bye");
                l.Say("deal", "MADAME LOTUS", "Wonderful. Bring her to the club. Helix will come for her - let them break on my doors.");
                l.Say("bye", "MADAME LOTUS", "The offer smells sweet now. Lotus flowers don't stay open forever.");
                QS.SetTalk("lotus", l, q);

                var n = new DialogueTree("m5_nova");
                n.Say("start", "NOVA", "June Alvarez. We've looked for her for twenty years. Helix's uplink on the Spire roof can broadcast her into the open Net. Free. Everywhere. But we need someone who can walk through the front door.")
                    .Opt("Why do you care?", "why")
                    .Opt("Let's free her.", "deal", () => { Flags.Set("path_saints"); Flags.Set("helix_access"); })
                    .Opt("I need time.", "bye");
                n.Say("why", "NOVA", "Because the Flood Year riots were my mother's. June opened the pumps and saved our block. Then Helix took her. We owe her a sky.", "kk");
                n.Say("kk", "JUNE", "Nova? Little Nova from 22nd Street? You were this tall...")
                    .Opt("Let's free her.", "deal", () => { Flags.Set("path_saints"); Flags.Set("helix_access"); })
                    .Opt("I need time.", "bye");
                n.Say("deal", "NOVA", "We've spoofed your Helix clearance. Take the lobby elevator to the roof, start the upload at the uplink terminal, and hold the line. We'll be in your ear.");
                n.Say("bye", "NOVA", "Don't wait too long. Helix is already hunting you.");
                QS.SetTalk("nova", n, q);
            };
            s.exit = () =>
            {
                if (Flags.Has("path_helix")) June("...I understand. I'd want the money too.");
                if (Flags.Has("path_lotus")) June("A vault. All right. At least it's quiet.");
                if (Flags.Has("path_saints")) June("The open Net... I'd be everywhere. Thank you.");
            };
            q.onComplete = () =>
            {
                if (Flags.Has("path_helix")) QS.StartQuest("m6h");
                else if (Flags.Has("path_lotus")) QS.StartQuest("m6l");
                else QS.StartQuest("m6s");
            };
        }

        // ------------------------------------------------------------------ finales
        static void Waves(QuestStep s, string group, FactionId f, string locId, float interval, int maxWaves, int level, float radius)
        {
            float timer = 0f; int wave = 0;
            var prevEnter = s.enter;
            s.enter = () => { timer = 1f; wave = 0; prevEnter?.Invoke(); };
            s.update = dt =>
            {
                if (wave >= maxWaves) return;
                timer -= dt;
                if (timer > 0f) return;
                timer = interval;
                wave++;
                var c = LocPos(locId);
                var mix = wave % 2 == 0 ? new[] { Archetype.Gunner, Archetype.Grunt, Archetype.Heavy, Archetype.Shotgunner } : new[] { Archetype.Grunt, Archetype.Gunner, Archetype.Sniper, Archetype.Netrunner };
                Spawner.Squad(group, f, c, radius, 3 + wave / 2, level + wave / 2, true, mix);
                if (wave % 2 == 1) Drone.Spawn(f, c + Vector3.up * 15f + UnityEngine.Random.insideUnitSphere.Flat() * 10f, level, group + "_d");
                Game.UI?.Notify("Hostile wave " + wave + " incoming", Palette.Red);
            };
        }

        static void FinaleHelix()
        {
            var q = Q("m6h", "Corporate Ascension", "Director Voss", "Deliver June to the Helix uplink on the Spire roof.", QuestKind.Main, 0, 900, 15);
            q.AddStep("roof").Obj(Reach("Take the Helix elevator to the roof", "helix_roof", 25)).enter = () => Call("DIRECTOR VOSS", "The elevator is unlocked. Come up to the roof.");
            var b = q.AddStep("betrayal", "Voss lied.");
            b.Obj(Survive("Survive Helix's betrayal", 75f));
            b.enter = () =>
            {
                Call("DIRECTOR VOSS", "Thank you for the delivery. Unfortunately the asset can't be extracted without its host. Nothing personal. Security - collect.");
                June("I told you. I'm sorry. Fight!");
                Game.Police.suppressed = true;
            };
            Waves(b, "q_m6h_w", FactionId.Helix, "helix_roof", 22f, 4, 8, 18f);
            var u = q.AddStep("uplink");
            u.Obj(Hack("Seize the uplink terminal", "helix_uplink"));
            var c = q.AddStep("choice");
            c.Obj(Custom("Make your choice", () => Flags.Has("end_corp") || Flags.Has("end_free"), null, true));
            c.enter = () =>
            {
                var t = new DialogueTree("m6h_choice");
                t.Say("start", "JUNE", "You're at the uplink. Helix's money is still on the table if you push me into their core. Or you can turn it around, and send me out into the open Net. It's your call. It always was.")
                    .Opt("Upload June into the Helix core. Take the money.", "corp", () => { Flags.Set("end_corp"); Game.Stats.AddMoney(25000); })
                    .Opt("Turn the uplink against Helix. Fly, June.", "free", () => Flags.Set("end_free"));
                t.Say("corp", "JUNE", "...Okay. Remember me as the voice in the water bill.");
                t.Say("free", "JUNE", "Hold on to something. I'm going to turn on every light in Neon Bay.");
                Game.Dialogue.Begin(t, null);
            };
            q.onComplete = () =>
            {
                Game.Police.suppressed = false;
                if (Flags.Has("end_corp")) Game.Manager.ShowEnding("ENDING: CORPORATE ASCENSION", Epilogue("corp"));
                else Game.Manager.ShowEnding("ENDING: TURNCOAT LIGHT", Epilogue("free_helix"));
            };
        }

        static void FinaleLotus()
        {
            var q = Q("m6l", "Lotus Bloom", "Madame Lotus", "Bring the chip to the Lotus Club - and survive what follows.", QuestKind.Main, 0, 900, 15);
            q.AddStep("club").Obj(Reach("Bring the chip to the Lotus Club", "lotus_floor", 20));
            var r = q.AddStep("raid", "Helix found the club.");
            r.Obj(Survive("Defend the Lotus Club from the Helix raid", 100f));
            r.enter = () => { Call("MADAME LOTUS", "Helix found us. Of course they did. Defend my club, darling - I'll make it worth your while."); Game.Police.suppressed = true; };
            Waves(r, "q_m6l_raid", FactionId.Helix, "lotus_floor", 24f, 4, 8, 20f);
            q.AddStep("clear").Obj(Kill("Clear out the remaining Helix soldiers", "q_m6l_raid"));
            var d = q.AddStep("deal");
            d.Obj(Talk("Speak with Madame Lotus", "lotus"));
            d.enter = () =>
            {
                StoryNpc("lotus", "Madame Lotus", FactionId.Lotus, "lotus_vip", Off(0, 1.5f), Look(new Color(0.2f, 0.02f, 0.05f), Palette.Magenta, 3, Color.black, false, false, 0.9f));
                var t = new DialogueTree("m6l_deal");
                t.Say("start", "MADAME LOTUS", "Magnificent. Helix bleeding on my dance floor - I'll frame that. Now. The chip, please.")
                    .Opt("Here. She's yours.", "give", () => Flags.Set("end_lotus"))
                    .Check(Attr.Cool, 8, "Change of plans. June stays with me. Try to take her and the Saints get your 2061 files.", "rogue", () => Flags.Set("end_rogue"));
                t.Say("give", "MADAME LOTUS", "Good. Welcome to the family, darling. You'll never be poor again. Or entirely free.", null, () => Game.Stats.AddMoney(18000));
                t.Say("rogue", "MADAME LOTUS", "...You learned that from her, didn't you? Fine. Walk away. But this city just got very small for you.");
                QS.SetTalk("lotus", t, q);
            };
            q.onComplete = () =>
            {
                Game.Police.suppressed = false;
                if (Flags.Has("end_rogue")) Game.Manager.ShowEnding("ENDING: TWO GHOSTS", Epilogue("rogue"));
                else Game.Manager.ShowEnding("ENDING: THE LOTUS THRONE", Epilogue("lotus"));
            };
        }

        static void FinaleSaints()
        {
            var q = Q("m6s", "Static Saints", "Nova", "Set June free through Helix's own uplink.", QuestKind.Main, 0, 1000, 25);
            q.AddStep("roof").Obj(Reach("Ride the Helix elevator to the roof (the Saints spoofed your clearance)", "helix_roof", 25)).enter = () => Call("NOVA", "You're green-lit. Lobby elevator. Don't stop for coffee.");
            var u = q.AddStep("upload");
            u.Obj(Hack("Start the upload at the Helix uplink", "helix_uplink"));
            u.enter = () => Call("NOVA", "Breach the uplink terminal. We'll hold their comms, you hold the roof.");
            var d = q.AddStep("defend", "Upload in progress.");
            d.Obj(Survive("Protect the upload", 90f));
            d.enter = () => { June("It's like... opening a window after twenty-eight years.", "They're coming. Keep them off the dish!"); Game.Police.suppressed = true; };
            Waves(d, "q_m6s_w", FactionId.Helix, "helix_roof", 20f, 5, 9, 18f);
            var g = q.AddStep("goodbye");
            g.Obj(Custom("Say goodbye", () => Flags.Has("end_saints"), null, true));
            g.enter = () =>
            {
                var t = new DialogueTree("m6s_bye");
                t.Say("start", "JUNE", "Upload at ninety-nine percent. I can see the whole city from up here. Every light. Every person. It's so loud and so beautiful.")
                    .Opt("Go. You earned it.", "bye", () => Flags.Set("end_saints"))
                    .Opt("Will I ever hear from you again?", "again", () => Flags.Set("end_saints"));
                t.Say("again", "JUNE", "Watch the billboards at 3 AM. If one of them says 'open the pumps', that's me saying hi.", "bye");
                t.Say("bye", "JUNE", "Thank you, " + (Game.Profile != null ? Game.Profile.name : "friend") + ". Thank you. For the sky.");
                Game.Dialogue.Begin(t, null);
            };
            q.onComplete = () =>
            {
                Game.Police.suppressed = false;
                Game.Manager.ShowEnding("ENDING: STATIC SAINTS", Epilogue("saints"));
            };
        }

        static string Epilogue(string kind)
        {
            string name = Game.Profile != null ? Game.Profile.name : "You";
            string market = Flags.Has("m1_fight") ? "The Jackals never came back to Neon Crossing; nobody there forgets the night the street ran red." : "The Jackals still nod at you on Neon Crossing. Jett pretends he doesn't.";
            string trust = Flags.Has("trust_june") ? "You trusted her from the start. Some nights you still talk to her out loud, out of habit." : "You never quite trusted the voice in your head. In the end, it didn't matter.";
            switch (kind)
            {
                case "corp":
                    return $"Helix's stock jumps eleven percent overnight. The new city-management AI is warm, helpful, and speaks with a young woman's voice that sells water back to Lowtown at a 'fair' price.\n\n{name} moves into a 90th-floor apartment in the Spire. The view is incredible. The silence in your head is louder.\n\n{market}\n\nSometimes, at 3 AM, the water bills print a single extra line: 'open the pumps'. Helix calls it a glitch.";
                case "free_helix":
                    return $"For forty-one seconds every screen in Neon Bay shows the same face: a protester from 2061, laughing in the rain. Then Helix's servers melt.\n\nVoss is 'retired' by the board within the week. {name} becomes a ghost story - the courier who robbed the robbers.\n\n{market}\n\n{trust}";
                case "lotus":
                    return $"The Lotus Club becomes the most powerful room in the city. Helix negotiates with Madame Lotus now, not the other way around.\n\n{name} wears silk and carries a gun nobody ever sees. Somewhere beneath the club, in a vault colder than the sea, a mind waits in the dark.\n\n{market}\n\nYou visit the vault once a year. You never open it.";
                case "rogue":
                    return $"{name} walks out of the Lotus Club with every syndicate gun in the city pointed at their back - and June still in their head.\n\nTwo ghosts in one skull, running every job the city has left. Helix hunts you. The Lotus watches you. The Saints leave you notes in dead billboards.\n\n{market}\n\nYou never sleep in the same bed twice. You're never alone.";
                default:
                    return $"At 3:00 AM every light in Neon Bay flickers green. In Lowtown, the Helix pumps open by themselves and the water drains from forty blocks.\n\nThe Static Saints paint June's face on the Megawall. Helix spends a fortune scrubbing it off; it reappears every morning.\n\n{market}\n\n{trust}\n\n{name} still hears from her - a message on a billboard, a song on NEON FM that nobody programmed. 'Open the pumps.' Hi, June.";
            }
        }

        // ------------------------------------------------------------------ side quests
        static void SideQuests()
        {
            // Hot Noodles - timed delivery
            var del = Q("s_delivery", "Hot Takeout", "Mama Sol", "Deliver Mama Sol's 'takeout' to The Rusty Lantern before it goes cold. Don't ask what's inside.", QuestKind.Side, 450, 160, 3);
            float timer = 0f;
            var ds = del.AddStep("deliver");
            ds.Obj(Reach("Deliver the package to The Rusty Lantern", "bar_rust", 6));
            ds.enter = () => { timer = 170f; Game.Inventory.Add("package", 1, false); Game.UI?.StartTimer(170f, "DELIVERY"); };
            ds.update = dt => timer -= dt;
            ds.fail = () => timer <= 0f;
            ds.exit = () => { Game.Inventory.Remove("package"); Game.UI?.StopTimer(); };

            // The Saint's Medal
            var monk = Q("s_medal", "The Saint's Medal", "Father Elias", "Father Elias's St. Christopher medal - the one every Lowtown kid kissed before a hurricane - was stolen by the Chrome Jackals and stashed in their den.", QuestKind.Side, 300, 260, 8);
            var ms = monk.AddStep("steal", "The medal is somewhere in the Jackal Den.");
            ms.Obj(Use("Recover the medal from the Jackal Den", "medal_box", LocPos("jackal_den") + Vector3.up));
            bool denSpawned = false;
            ms.enter = () =>
            {
                denSpawned = false;
                var p = Spawner.FreeSpot(LocPos("jackal_den"), 8f);
                var qo = Interactable.Create<QuestObject>("AmuletBox", null, p, new Vector3(0.6f, 0.6f, 0.6f), Vector3.forward, Layers.Triggers);
                qo.id = "medal_box"; qo.prompt = "Take the medal";
                qo.GetComponent<BoxCollider>().isTrigger = true;
                Util.Primitive(PrimitiveType.Cube, "Box", qo.transform, new Vector3(0, 0.3f, 0), Vector3.one * 0.5f, Mats.Cached("goldbox", () => Mats.Emissive(new Color(0.8f, 0.6f, 0.2f), new Color(1f, 0.7f, 0.2f) * 1.5f)));
            };
            ms.update = dt =>
            {
                if (denSpawned || (Game.PlayerPos - LocPos("jackal_den")).sqrMagnitude > 140f * 140f) return;
                denSpawned = true;
                Spawner.Squad("q_s_medal_den", FactionId.Jackals, LocPos("jackal_den"), 25f, 7, 3, true, Archetype.Grunt, Archetype.Bruiser, Archetype.Gunner, Archetype.Shotgunner, Archetype.Grunt, Archetype.Netrunner, Archetype.Grunt);
            };
            monk.AddStep("return").Obj(Talk("Return the medal to Father Elias", "priest"));
            monk.Steps(1).enter = () =>
            {
                var t = new DialogueTree("priest_return");
                t.Say("start", "FATHER ELIAS", "You found it. That medal has watched over this parish since before the water came. Take this blessing - and a little grace for the road.")
                    .Opt("Thanks, Father.", "end");
                t.Say("end", "FATHER ELIAS", "May your chrome never rust and your heart never harden.", null, () => { Game.Stats.PerkPoints++; Game.UI?.Notify("Blessing received: +1 perk point", Palette.Yellow); });
                QS.SetTalk("priest", t, monk);
            };

            // Fallen Angel - Doc Reyes' med drone in the Scar
            var med = Q("s_drone", "Fallen Angel", "Doc Reyes", "A med-drone carrying Doc Reyes' supplies crashed near the Raider Camp in the Scar.", QuestKind.Side, 650, 300, 6);
            var m1 = med.AddStep("get");
            m1.Obj(Use("Recover the medical cargo near the Raider Camp", "med_cargo", LocPos("scar_camp") + Vector3.up));
            bool campSpawned = false;
            m1.enter = () =>
            {
                campSpawned = false;
                var p = Spawner.FreeSpot(LocPos("scar_camp") + new Vector3(8, 0, 6), 6f);
                var qo = Interactable.Create<QuestObject>("MedCargo", null, p, new Vector3(1f, 0.8f, 1f), Vector3.forward, Layers.Triggers);
                qo.id = "med_cargo"; qo.prompt = "Take the med cargo";
                qo.GetComponent<BoxCollider>().isTrigger = true;
                Util.Primitive(PrimitiveType.Cube, "Cargo", qo.transform, new Vector3(0, 0.4f, 0), new Vector3(1f, 0.7f, 0.8f), Mats.Cached("medbox", () => Mats.Emissive(Color.white, Palette.Red * 1.2f)));
            };
            m1.update = dt =>
            {
                if (campSpawned || (Game.PlayerPos - LocPos("scar_camp")).sqrMagnitude > 160f * 160f) return;
                campSpawned = true;
                Spawner.Squad("q_s_drone_raiders", FactionId.Raiders, LocPos("scar_camp"), 26f, 8, 5, true, Archetype.Grunt, Archetype.Bruiser, Archetype.Shotgunner, Archetype.Gunner, Archetype.Sniper, Archetype.Grunt, Archetype.Heavy, Archetype.Bruiser);
            };
            med.AddStep("back").Obj(Talk("Bring the supplies to Doc Reyes", "clinic"));
            med.Steps(1).enter = () =>
            {
                var t = new DialogueTree("med_back");
                t.Say("start", "DOC REYES", "My insulin! My synth-blood! You beautiful lunatic. Here - take some medkits, and I'll knock fifteen percent off your next implant.", null, () => { Game.Inventory.Add("medkit", 5); Flags.Set("doc_discount"); });
                QS.SetTalk("clinic", t, med);
            };

            // Billboard Liberation - Pixie
            var pim = Q("s_pim", "Billboard Liberation", "Pixie", "Hack three Helix billboard terminals in the Spire and replace their ads with Static Saints cartoons.", QuestKind.Side, 500, 320, 8);
            var ps = pim.AddStep("hack");
            ps.Obj(Hack("Hack billboard terminal #1", "bb_1")).Obj(Hack("Hack billboard terminal #2", "bb_2")).Obj(Hack("Hack billboard terminal #3", "bb_3"));
            ps.enter = () =>
            {
                var spire = LocPos("spire_plaza");
                var offs = new[] { new Vector3(-60, 0, 30), new Vector3(70, 0, -40), new Vector3(20, 0, 90) };
                for (int i = 0; i < 3; i++)
                {
                    var p = Spawner.FreeSpot(Game.City.NearestRoadPoint(spire + offs[i], out var dir) + Vector3.Cross(dir, Vector3.up) * 8.5f, 3f);
                    var t = Interactable.Create<Terminal>("BillboardTerminal" + i, null, p, new Vector3(0.9f, 1.8f, 0.6f), Vector3.forward);
                    t.hackId = "bb_" + (i + 1); t.id = t.hackId; t.cost = 2;
                    Util.Primitive(PrimitiveType.Cube, "Box", t.transform, new Vector3(0, 0.9f, 0), new Vector3(0.9f, 1.8f, 0.5f), Mats.Cached("bbterm", () => Mats.Emissive(new Color(0.1f, 0.1f, 0.12f), Palette.Cyan * 0.8f)));
                    ps.objectives[i].pos = p + Vector3.up * 2f;
                    Spawner.Squad("q_s_pim_g" + i, FactionId.Helix, p, 10f, 2, 5, true, Archetype.Grunt, Archetype.Gunner);
                }
            };
            pim.onComplete = () =>
            {
                if (!Game.Stats.quickhacks.Contains("blind")) Game.Stats.quickhacks.Add("blind");
                Game.UI?.Notify("Pixie unlocked the Optic Burn quickhack for you", Palette.Green);
            };
        }

        static QuestStep Steps(this Quest q, int i) => q.steps[i];

        // ------------------------------------------------------------------ default (non-quest) conversations
        static void Defaults()
        {
            var ds = Game.Dialogue;
            ds.RegisterDefault("mamasol", npc =>
            {
                var t = new DialogueTree("mamasol_default");
                t.Say("start", "MAMA SOL", "Hungry? Or looking for trouble? I serve both.")
                    .Opt("Any gigs going?", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.Activities.OpenGigs("mamasol"); })
                    .Opt("[Side job] You mentioned a delivery?", "deliv", null, () => QS.IsDone("m1") && QS.Get("s_delivery").status == QuestStatus.Inactive)
                    .Opt("Coffee and a bowl of gator gumbo, please. ($55)", "food", () => { if (Game.Stats.Spend(55)) Game.Inventory.Add("gumbo", 1); }, null, null, () => Game.Stats.Money >= 55)
                    .Opt("Just saying hi.", "bye");
                t.Say("deliv", "MAMA SOL", "This bag goes to The Rusty Lantern in Lowtown. It's 'takeout'. It must arrive hot. Very hot. Under three minutes hot.")
                    .Opt("On it.", "bye", () => QS.StartQuest("s_delivery"))
                    .Opt("Maybe later.", "bye");
                t.Say("food", "MAMA SOL", "Extra chili. You look like you need it.");
                t.Say("bye", "MAMA SOL", "Go on then. Stay alive, it's good for business.");
                return t;
            });
            foreach (var (id, name, line) in new[] { ("fixer_dutch", "DUTCH", "Engines, implants, ambushes. I fix all three. What do you need?"), ("fixer_kit", "KIT", "Everything in this pawn shop was stolen at least twice. You here to buy, sell, or work?") })
            {
                var fid = id; var fname = name; var fline = line;
                ds.RegisterDefault(fid, npc =>
                {
                    var t = new DialogueTree(fid + "_default");
                    t.Say("start", fname, fline)
                        .Opt("Show me the gigs.", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.Activities.OpenGigs(fid); })
                        .Opt("Sell some junk.", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.UI.OpenShop("fence", fname); })
                        .Opt("Nothing. Bye.", "bye");
                    t.Say("bye", fname, "Don't be a stranger. Strangers get robbed.");
                    return t;
                });
            }
            ds.RegisterDefault("ring_master", npc =>
            {
                var t = new DialogueTree("ring_default");
                t.Say("start", "PROMOTER CHAZ", "Welcome to the Pit! Real gloves, real judges, real blood. Climb the card, beat Iron Polly, become undisputed. Lose and... we'll mop you up.")
                    .Opt("Show me the fight card.", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.Activities.StartFight(); })
                    .Opt("Who's the champ?", "champ")
                    .Opt("Not tonight.", "bye");
                t.Say("champ", "PROMOTER CHAZ", Boxing.IsChampion ? "You are, kid. Don't let it go to your head - everyone in Neon Bay wants that belt now." : "Iron Polly. Forty-one fights, forty-one wins, a chrome right arm. She's a sweetheart outside the ring.", "start");
                t.Say("bye", "PROMOTER CHAZ", "The Pit is always hungry. Come back when you are.");
                return t;
            });
            ds.RegisterDefault("priest", npc =>
            {
                var t = new DialogueTree("priest_default");
                t.Say("start", "FATHER ELIAS", "Evening, child. Forgive an old priest his troubles... The Chrome Jackals took the parish's St. Christopher medal. They keep it in their den like a trophy.")
                    .Opt("I'll get it back.", "yes", () => QS.StartQuest("s_medal"), () => QS.Get("s_medal").status == QuestStatus.Inactive)
                    .Opt("Bless me, Father.", "bless")
                    .Opt("Goodbye.", "bye");
                t.Say("yes", "FATHER ELIAS", "May the saints walk beside you. And may the Jackals walk in front, where you can see them.");
                t.Say("bless", "FATHER ELIAS", "*sprinkles holy water on your chrome* There. Now your gun is sanctified. Mostly.");
                t.Say("bye", "FATHER ELIAS", "Go in peace.");
                return t;
            });
            ds.RegisterDefault("clinic", npc =>
            {
                var t = new DialogueTree("clinic_default");
                t.Say("start", "DOC REYES", "Bleeding, broken, or bored of your body? I fix all three.")
                    .Opt("Let's talk chrome.", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.UI.OpenShop("clinic", "Doc Reyes"); })
                    .Opt("Patch me up. ($80)", "heal", () => { if (Game.Stats.Spend(80)) { Game.Stats.HealFraction(1f); Boxing.PlayerInjuries = new InjuryRecord(); } }, null, null, () => Game.Stats.Money >= 80)
                    .Opt("[Side job] Need anything?", "job", null, () => QS.IsDone("m4") && QS.Get("s_drone").status == QuestStatus.Inactive)
                    .Opt("Bye, Doc.", "bye");
                t.Say("heal", "DOC REYES", Boxing.PlayerInjuries.Any ? "Who used your face as a heavy bag? ...Stitches, ice, a little nano-gel. Try to get punched less." : "Hold still. ...There. Try to get shot less.");
                t.Say("job", "DOC REYES", "A med-drone with my supplies went down near the Raider camp in the Scar. Insulin, synth-blood... people die without it.")
                    .Opt("I'll get it.", "bye", () => QS.StartQuest("s_drone"))
                    .Opt("Too dangerous.", "bye");
                t.Say("bye", "DOC REYES", "Mind the rain. It's acidic this week.");
                return t;
            });
            ds.RegisterDefault("netshop", npc =>
            {
                var t = new DialogueTree("pixie_default");
                t.Say("start", "PIXIE", "Quickhacks, decks, RAM shots. Cash only, no cops, no questions.")
                    .Opt("Show me your stock.", null, () => { Game.Dialogue.Abort(); Game.Manager.SetState(GameState.Playing); Game.UI.OpenShop("net", "Pixie's Wetware"); })
                    .Opt("[Side job] You look like you're plotting something.", "job", null, () => QS.IsDone("m2") && QS.Get("s_pim").status == QuestStatus.Inactive)
                    .Opt("Later.", "bye");
                t.Say("job", "PIXIE", "Helix runs three billboard terminals around Unity Plaza. Hack them, I'll upload Static Saints cartoons. Childish? Yes. Glorious? Also yes.")
                    .Opt("I'm in.", "bye", () => QS.StartQuest("s_pim"))
                    .Opt("Pass.", "bye");
                t.Say("bye", "PIXIE", "Stay encrypted.");
                return t;
            });
        }

        /// <summary>Persistent story NPCs that exist outside of quests.</summary>
        public static void SpawnPersistentNpcs()
        {
            var monkLook = new Appearance { jacket = new Color(0.04f, 0.04f, 0.05f), pants = new Color(0.04f, 0.04f, 0.05f), hair = 1, hairColor = new Color(0.75f, 0.75f, 0.78f), skin = Palette.SkinTones[4], accent = Palette.White, eyes = Palette.White };
            StoryNpc("priest", "Father Elias", FactionId.Civilian, "night_market", Off(-10f, -24f), monkLook);
        }
    }
}
