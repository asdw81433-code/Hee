class_name NPCDialog
extends Control
## Talking to an NPC. Responses depend on personality, mood, memories and the
## relationship with the player. "Inspect" shows the AI internals (needs, utility
## scores, plan, relationships, memories) so you can see why they act as they do.

var npc: NPCData
var body: NPCBody
var manager: NPCManager
var player: Node
var _vb: VBoxContainer
var _line: Label
const PID := NPCData.PLAYER_ID


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerInput.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	body.control_locked = true
	body.face_dir_override = (player as Node3D).global_position - body.global_position
	body.model.rig.look_target = (player as Node3D).global_position + Vector3(0, 1.6, 0)
	body.model.rig.look_weight = 1.0
	_main()


func _close() -> void:
	PlayerInput.enabled = true
	if body and is_instance_valid(body):
		body.control_locked = false
		body.face_dir_override = Vector3.ZERO
		body.model.face.talking = false
	queue_free()


func _main(said: String = "") -> void:
	for c in get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 300)
	UIKit.anchor(panel, Control.PRESET_CENTER_BOTTOM, Vector2(-430, -330), Vector2(860, 300))
	add_child(panel)
	_vb = VBoxContainer.new()
	panel.add_child(_vb)
	var known := npc.knows(PID)
	var title := npc.full_name() if known else "Stranger (%s, ~%d)" % ["man" if npc.gender == 0 else "woman", int(npc.age / 5) * 5]
	_vb.add_child(UIKit.label(title + "   ·   " + npc.relation_label(PID) + "   ·   mood: " + npc.emotion.dominant(), 24, UIKit.ACCENT))
	_line = UIKit.label("\"" + (said if said != "" else _greeting()) + "\"", 24)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.custom_minimum_size = Vector2(820, 70)
	_vb.add_child(_line)
	body.model.face.talking = true
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if is_instance_valid(body) and body.model:
			body.model.face.talking = false)
	var row := HFlowContainer.new()
	_vb.add_child(row)
	for opt in [["Chat", _chat], ["How's your day?", _day], ["Compliment", _compliment], ["Insult", _insult], ["Give $10", _gift], ["Give item", _gift_menu], ["Inspect (AI)", _inspect], ["Bye", _close]]:
		row.add_child(UIKit.button(opt[0], opt[1], Vector2(180, 52)))


func _attitude() -> float:
	var r := npc.rel(PID)
	return float(r.friendship) + npc.memory.sentiment(PID) * 0.6 - float(r.anger) * 0.8 - float(r.fear) * 0.3


func _greeting() -> String:
	var att := _attitude()
	var mood := npc.emotion.dominant()
	if float(npc.rel(PID).anger) > 0.4 and not npc.memory.about(PID).is_empty():
		var m: Dictionary = npc.memory.most_important(1)[0] if not npc.memory.most_important(1).is_empty() else {}
		if m.get("event", "") == "assaulted":
			return "You! You're the one who hit me. Stay away from me!" if npc.trait_value("fearfulness") > 0.5 else "You've got some nerve showing your face after hitting me."
		return "I saw what you did. I don't want any trouble."
	if not npc.knows(PID):
		if npc.trait_value("shyness") > 0.65:
			return "Oh... um, hi. Do I know you?"
		if npc.trait_value("friendliness") > 0.6:
			return "Hey there! Haven't seen you around before. I'm %s." % npc.first_name
		return "Yeah? What do you want?"
	if att > 0.5:
		return "Hey, good to see you again! What's up?"
	if mood == "angry" or mood == "irritated":
		return "Not now, I'm in a bad mood."
	if mood == "sad":
		return "Oh, hi... sorry, it's been a rough day."
	return "Oh, hi again."


func _chat() -> void:
	var p := npc.personality
	var ok_chance := 0.4 + p.get_trait("sociability") * 0.4 + _attitude() * 0.4 - p.get_trait("shyness") * 0.2
	var said := ""
	if randf() < ok_chance:
		npc.change_rel(PID, {"familiarity": 0.2, "friendship": 0.06 + p.get_trait("friendliness") * 0.05, "trust": 0.03})
		npc.needs.social = minf(100.0, float(npc.needs.social) + 12.0)
		npc.emotion.add("happy", 0.1)
		npc.memory.add("chat", PID, GameTime.total_minutes, manager.place_name(npc.at_place), 0.2, 0.3)
		var topics := ["My name's %s, by the way. I %s." % [npc.first_name, "work at " + manager.place_name(int(npc.job.place)) if npc.has_job() else ("am retired" if npc.age > 65 else "am between jobs right now")],
			"I'm really into %s lately." % npc.hobbies[0], "One day I want to %s." % npc.goals[0],
			"Did you hear? The market in Old Town has the best apples.", "This town's alright. Quiet, mostly."]
		if not npc.memory.entries.is_empty():
			var mem: Dictionary = npc.memory.most_important(1)[0]
			if mem.event == "witnessed_assault":
				topics.append("Did you hear about the fight? I saw it myself. %s." % String(mem.detail).capitalize())
		said = topics[randi() % topics.size()]
		body.model.animator.play_upper("talk")
	else:
		npc.change_rel(PID, {"familiarity": 0.05})
		said = ["I'm kind of busy.", "Uh, sure... anyway, I gotta go.", "Maybe another time."][randi() % 3]
	_main(said)


func _day() -> void:
	var a := npc.action
	var txt := "Right now I'm %s — %s." % [_action_text(a), npc.action_reason]
	if npc.has_job():
		txt += " I work %02d:00-%02d:00 as a %s." % [int(npc.job.start), int(npc.job.end) % 24, String(npc.job.title).to_lower()]
	if npc.trait_value("honesty") < 0.3 and randf() < 0.5:
		txt = "Oh, nothing much. Just... walking around."   # some people lie
	npc.change_rel(PID, {"familiarity": 0.1})
	_main(txt)


func _action_text(a: String) -> String:
	return {"sleep": "about to sleep", "work": "on my way to work / working", "eat_home": "having a meal at home", "eat_out": "grabbing food",
		"coffee": "getting coffee", "groceries": "buying groceries", "socialize": "meeting people", "leisure": "doing something fun",
		"rest": "taking a break", "relax_home": "heading home to relax", "shelter": "getting out of the rain", "wander": "just walking around",
		"job_hunt": "looking for a job", "chat": "chatting", "idle": "thinking"}.get(a, a)


func _compliment() -> void:
	var p := npc.personality
	if p.get_trait("confidence") < 0.35:
		npc.emotion.add("embarrassed", 0.4)
		npc.change_rel(PID, {"friendship": 0.08, "attraction": 0.03, "familiarity": 0.1})
		_main("Oh! Th-thanks... nobody ever says that.")
	elif p.get_trait("honesty") > 0.6 and _attitude() < -0.2:
		npc.change_rel(PID, {"familiarity": 0.05})
		_main("Flattery won't make me forget what you did.")
	else:
		npc.emotion.add("happy", 0.25)
		npc.change_rel(PID, {"friendship": 0.1, "respect": 0.03, "familiarity": 0.1})
		npc.memory.add("compliment", PID, GameTime.total_minutes, manager.place_name(npc.at_place), 0.3, 0.5)
		body.model.animator.play_upper("laugh")
		_main("Ha, thanks! You're alright.")


func _insult() -> void:
	var p := npc.personality
	npc.change_rel(PID, {"friendship": -0.2, "anger": 0.15 + p.get_trait("aggression") * 0.2, "familiarity": 0.1})
	npc.memory.add("insulted", PID, GameTime.total_minutes, manager.place_name(npc.at_place), 0.5, -0.6)
	if p.get_trait("aggression") > 0.65 and p.get_trait("bravery") > 0.5:
		npc.emotion.add("angry", 0.8)
		npc.reaction = "confront"
		npc.reaction_source = (player as Node3D).global_position
		body.set_meta("confront_target", PID)
		npc.reaction_until = GameTime.total_minutes + 12.0 * GameTime.minutes_per_second
		_close()
		EventBus.toast.emit("%s is furious!" % npc.first_name)
		return
	if p.get_trait("fearfulness") > 0.6 or p.get_trait("shyness") > 0.6:
		npc.emotion.add("sad", 0.5)
		npc.emotion.add("embarrassed", 0.5)
		_main("...why would you say that?")
	else:
		npc.emotion.add("angry", 0.4)
		body.model.animator.play_upper("angry")
		_main("Get lost, jerk.")


func _gift() -> void:
	if not Game.spend_money(10, "gift to " + npc.first_name):
		return
	npc.money += 10
	var p := npc.personality
	npc.change_rel(PID, {"friendship": 0.12 + (0.05 if p.get_trait("selfishness") > 0.6 else 0.0), "trust": 0.05, "familiarity": 0.15})
	npc.memory.add("gift", PID, GameTime.total_minutes, manager.place_name(npc.at_place), 0.45, 0.7)
	npc.emotion.add("happy", 0.35)
	_main("For me? Wow, thank you!" if p.get_trait("honesty") > 0.4 else "Heh. Don't mind if I do.")


## Give something from your bag. Gifts mean more than snacks; generous people
## care less about the value, greedy people more.
func _gift_menu() -> void:
	var eco: Economy = Game.current_world.economy if Game.current_world and Game.current_world.get("economy") else null
	if eco == null:
		return
	for c in get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	UIKit.anchor(panel, Control.PRESET_CENTER_BOTTOM, Vector2(-430, -330), Vector2(860, 300))
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(UIKit.label("Give %s something:" % (npc.first_name if npc.knows(PID) else "them"), 24, UIKit.ACCENT))
	var row := HFlowContainer.new()
	vb.add_child(row)
	var any := false
	for id in eco.inventory.keys():
		var it := ItemDB.get_item(id)
		if String(it.kind) in ["gift", "consumable"]:
			any = true
			row.add_child(UIKit.button(String(it.name), func() -> void: give_item(id, eco), Vector2(260, 52)))
	if not any:
		vb.add_child(UIKit.label("You have nothing to give. Flowers, chocolates and teddies are sold at the mall and markets.", 20, UIKit.MUTED))
	row.add_child(UIKit.button("Back", func() -> void: _main(), Vector2(160, 52)))


func give_item(id: String, eco: Economy) -> void:
	var it := ItemDB.get_item(id)
	if not eco.remove_item(id):
		return
	var p := npc.personality
	var value: float = float(it.get("gift", 0.03 + 0.004 * float(it.get("price", 1))))
	var greed := p.get_trait("selfishness")
	npc.change_rel(PID, {"friendship": value * (0.8 + greed * 0.5), "trust": value * 0.4, "familiarity": 0.12})
	npc.memory.add("gift", PID, GameTime.total_minutes, manager.place_name(npc.at_place), 0.3 + value, 0.7)
	npc.emotion.add("happy", 0.2 + value)
	if String(it.kind) == "consumable":
		npc.needs["hunger"] = minf(100.0, float(npc.needs.get("hunger", 50.0)) + float((it.get("effects", {}) as Dictionary).get("hunger", 10)))
	var line := "Oh, %s! That's so sweet of you." % String(it.name).to_lower() if value >= 0.12 else ("Thanks, I was getting hungry." if String(it.kind) == "consumable" else "Thanks!")
	_main(line)


func _inspect() -> void:
	for c in get_children():
		c.queue_free()
	var vb := UIKit.modal(self, npc.full_name(), 1100)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1060, 470)
	vb.add_child(scroll)
	var lab := UIKit.label(_inspect_text(), 17)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD
	lab.custom_minimum_size = Vector2(1030, 0)
	scroll.add_child(lab)
	vb.add_child(UIKit.button("Back", func() -> void: _main()))


func _inspect_text() -> String:
	var s := npc.life_story + "\n\n"
	s += "Personality: " + ", ".join(npc.personality.top_labels(6)) + "\n"
	var traits := []
	for t in Personality.TRAITS:
		traits.append("%s %.2f" % [t, npc.trait_value(t)])
	s += "  " + "  ".join(traits) + "\n\n"
	s += "Needs: hunger %d  energy %d  social %d  fun %d  hygiene %d   Money $%d   Food at home %d\n" % [npc.needs.hunger, npc.needs.energy, npc.needs.social, npc.needs.fun, npc.needs.hygiene, npc.money, npc.home_food]
	var em := []
	for k in NPCEmotion.KEYS:
		if npc.emotion.get_e(k) > 0.1:
			em.append("%s %.2f" % [k, npc.emotion.get_e(k)])
	s += "Emotions: " + ", ".join(em) + "\n\n"
	s += "NOW: %s  —  %s\n" % [npc.action.to_upper(), npc.action_reason]
	s += "Utility scores: "
	for row in npc.last_score_table:
		s += "%s %.2f | " % [row[0], row[1]]
	s += "\n\nToday's plan:\n"
	for e in npc.day_plan:
		s += "  %02d:%02d  %s\n" % [int(e.hour) % 24, int(fposmod(float(e.hour), 1.0) * 60.0), e.what]
	s += "\nRelationships:\n"
	var count := 0
	for other in npc.relationships.keys():
		if count > 10:
			break
		var r: Dictionary = npc.relationships[other]
		var who: String = "You" if other == PID else (manager.npcs[other].full_name() if other >= 0 and other < manager.npcs.size() else "?")
		s += "  %s: %s (friendship %.2f, trust %.2f, anger %.2f, fear %.2f)\n" % [who, npc.relation_label(other), r.friendship, r.trust, r.anger, r.fear]
		count += 1
	s += "\nMemories:\n"
	for m in npc.memory.most_important(6):
		var who2: String = "you" if int(m.who) == PID else (manager.npcs[int(m.who)].first_name if int(m.who) >= 0 and int(m.who) < manager.npcs.size() else "someone")
		s += "  %s with %s at %s (importance %.2f, strength %.2f) %s\n" % [m.event, who2, m.place, m.importance, m.strength, m.detail]
	return s
