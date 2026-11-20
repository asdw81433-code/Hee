class_name NPCReactions
extends RefCounted
## How a single NPC responds to a violent event it witnessed (or suffered).
## The choice is computed from personality, relationship with victim/attacker,
## emotions, distance, and how many others are around. Phase 3 extends this with
## gossip, social media and police reports.

static func react(n: NPCData, body: NPCBody, ev: Dictionary, victim_id: int, inst_id: int, m: NPCManager) -> void:
	var now := GameTime.total_minutes
	var pos: Vector3 = ev.position
	var severity: float = ev.get("severity", 0.5)
	var place := m.place_name(n.at_place)
	n.reaction_source = pos
	if n.id == victim_id:
		_victim(n, inst_id, severity, place, m)
		return
	var p := n.personality
	var f_victim := float(n.rel(victim_id).friendship) if victim_id >= 0 and n.knows(victim_id) else 0.0
	var f_inst := float(n.rel(inst_id).friendship) if n.knows(inst_id) else 0.0
	var dist := n.pos.distance_to(pos)
	var helpers := 0
	for other in m.body_of.values():
		var on := (other as NPCBody).npc
		if on and on.reaction in ["help", "confront"]:
			helpers += 1
	var options := {
		"flee": p.get_trait("fearfulness") * 0.8 + p.get_trait("caution") * 0.3 - p.get_trait("bravery") * 0.4 + severity * 0.3 + (0.2 if dist < 6.0 else 0.0),
		"help": p.get_trait("bravery") * 0.55 + p.get_trait("kindness") * 0.35 + f_victim * 0.7 - p.get_trait("fearfulness") * 0.3 + (0.15 if helpers > 0 else 0.0) - f_inst * 0.4,
		"confront": p.get_trait("aggression") * 0.5 + p.get_trait("bravery") * 0.3 + f_victim * 0.5 - f_inst * 0.6 - 0.25,
		"call_police": p.get_trait("honesty") * 0.35 + p.get_trait("caution") * 0.35 + p.get_trait("kindness") * 0.2 - p.get_trait("selfishness") * 0.2 - f_inst * 0.5,
		"film": p.get_trait("curiosity") * 0.5 + p.get_trait("impulsiveness") * 0.35 - p.get_trait("kindness") * 0.25,
		"watch": p.get_trait("curiosity") * 0.45 + 0.1,
		"ignore": p.get_trait("selfishness") * 0.4 + (1.0 - p.get_trait("curiosity")) * 0.3 + p.get_trait("patience") * 0.1 - severity * 0.2 + (0.3 if dist > 18.0 else 0.0),
		"side_with_attacker": f_inst * 0.9 + p.get_trait("aggression") * 0.15 - f_victim * 0.6 - 0.2,
	}
	var best := "watch"
	var bs := -INF
	for k in options.keys():
		var s: float = options[k] + m.rng.randf_range(-0.08, 0.08)
		if s > bs:
			bs = s
			best = k
	n.memory.add("witnessed_assault", inst_id, now, place, 0.55 + severity * 0.3, -0.6 if best != "side_with_attacker" else 0.2, "seen",
		"saw %s hit %s" % ["you" if inst_id == NPCData.PLAYER_ID else m.npcs[inst_id].first_name if inst_id >= 0 else "someone", m.npcs[victim_id].first_name if victim_id >= 0 else "someone"])
	if inst_id == NPCData.PLAYER_ID:
		n.change_rel(inst_id, {"familiarity": 0.1, "fear": 0.15 + p.get_trait("fearfulness") * 0.2, "friendship": -0.15 if best != "side_with_attacker" else 0.05, "trust": -0.2})
	match best:
		"ignore":
			n.emotion.add("irritated", 0.1)
			return
		"side_with_attacker":
			best = "watch"
			n.emotion.add("excited", 0.3)
		"flee":
			n.emotion.add("fear", 0.7)
		"help":
			body.set_meta("help_target", victim_id)
			n.emotion.add("angry", 0.3)
		"confront":
			body.set_meta("confront_target", inst_id)
			n.emotion.add("angry", 0.6)
		"call_police":
			n.emotion.add("fear", 0.3)
			EventBus.toast.emit("%s is calling the police!" % n.first_name)
			EventBus.world_event.emit({"type": "police_report", "position": pos, "reporter": n.id, "suspect": inst_id, "time": now})
		"film":
			n.emotion.add("excited", 0.4)
	n.reaction = best
	# Reactions play out in real time (~10-22 s), expressed in game minutes.
	n.reaction_until = now + m.rng.randf_range(10.0, 22.0) * GameTime.minutes_per_second
	body.model.face.set_expression(n.emotion.face_weights())


static func _victim(n: NPCData, inst_id: int, severity: float, place: String, m: NPCManager) -> void:
	var p := n.personality
	n.memory.add("assaulted", inst_id, GameTime.total_minutes, place, 0.9, -1.0, "self", "was punched")
	n.change_rel(inst_id, {"familiarity": 0.3, "anger": 0.5 + p.get_trait("aggression") * 0.3, "fear": 0.2 + p.get_trait("fearfulness") * 0.4,
		"trust": -0.6, "friendship": -0.45, "respect": -0.1})
	var fight := p.get_trait("aggression") * 0.6 + p.get_trait("bravery") * 0.5 + float(n.rel(inst_id).anger) * 0.3 - p.get_trait("fearfulness") * 0.5
	var flee := p.get_trait("fearfulness") * 0.7 + p.get_trait("caution") * 0.3 + severity * 0.2 - p.get_trait("bravery") * 0.3
	n.emotion.add("angry", 0.6)
	n.emotion.add("fear", 0.4 + p.get_trait("fearfulness") * 0.4)
	if fight > flee and fight > 0.45:
		n.reaction = "confront"
		var b := m.body_for(n.id)
		if b:
			b.set_meta("confront_target", inst_id)
	elif flee > 0.35:
		n.reaction = "flee"
	else:
		n.reaction = "shout"
	n.reaction_until = GameTime.total_minutes + m.rng.randf_range(8.0, 20.0) * GameTime.minutes_per_second
