class_name NPCManager
extends Node
## Owns the whole population. Responsibilities:
##  * staggered AI ticks (nobody thinks every frame; far NPCs think less often)
##  * LOD: near NPCs get a pooled NPCBody (full AI + animation + physics), mid range a
##    reduced body, far / indoor NPCs are simulated abstractly along the walk network
##  * places, routing, spots, hiring, encounters between NPCs, event reactions
##  * save / load and catching up after time skips (sleeping)

const OUTDOOR_TYPES := ["park", "plaza", "market", "sports", "bus_stop", "parking"]
const NEAR := 55.0
const MID := 105.0
const ABSTRACT_SPEED := 1.4
const ABSTRACT_SPEEDUP := 6.0   ## off-screen people also use buses/bikes/cars

var world: Node3D
var city: CityBuilder
var places: Array = []
var npcs: Array = []                 ## Array[NPCData]
var bodies: Array = []               ## pooled NPCBody
var body_of: Dictionary = {}         ## npc id -> NPCBody
var max_bodies: int = 16
var rng := RandomNumberGenerator.new()
var player: Node3D
var _tick_index: int = 0
var _last_tick_min: Dictionary = {}  ## npc id -> game minutes of last tick
var _lod_timer: float = 0.0
var _encounter_timer: float = 0.0
var _last_world_minutes: float = -1.0
var _move_accum: Dictionary = {}
var population: int = 60
var stats := {"embodied": 0, "ticks_per_sec": 0, "decisions": 0}
var _tick_counter: int = 0
var _tick_window: float = 0.0


func setup(p_world: Node3D, p_city: CityBuilder) -> void:
	world = p_world
	city = p_city
	places = city.places
	rng.seed = 4242
	add_to_group("savable")
	match int(Settings.get_value("graphics_quality", 1)):
		0:
			population = 40
			max_bodies = 10
		2:
			population = 85
			max_bodies = 22
		_:
			population = 60
			max_bodies = 16
	npcs = NPCGenerator.generate(places, population, 777)
	for n in npcs:
		_last_tick_min[n.id] = GameTime.total_minutes
	_last_world_minutes = GameTime.total_minutes
	# Initial decisions so the town is already busy.
	for n in npcs:
		NPCBrain.decide(n, self)
		# Spread people around: anyone travelling starts somewhere along the route.
		if not (n as NPCData).path.is_empty():
			var steps := rng.randi_range(0, (n as NPCData).path.size() - 1)
			n.path_index = steps
			n.pos = n.path[steps]
	EventBus.world_event.connect(_on_world_event)
	EventBus.character_impacted.connect(_on_impacted)


func save_key() -> String:
	return "npcs"


func save_state() -> Dictionary:
	var arr: Array = []
	for n in npcs:
		arr.append((n as NPCData).to_dict())
	return {"npcs": arr}


func load_state(d: Dictionary) -> void:
	for id in body_of.keys():
		_release_body(id)
	var arr: Array = d.get("npcs", [])
	if arr.is_empty():
		return
	npcs = []
	for p in places:
		(p as Place).residents = []
		for s in (p as Place).spots:
			s["taken_by"] = -1
	for nd in arr:
		var n := NPCData.from_dict(nd)
		npcs.append(n)
		if n.home_place >= 0:
			places[n.home_place].residents.append(n.id)
		_last_tick_min[n.id] = GameTime.total_minutes
	for n in npcs:
		n.action = "idle"
		n.path = PackedVector3Array()
		if n.at_place >= 0 and not place_is_indoor(n.at_place):
			n.inside = false
		NPCBrain.decide(n, self)
	_last_world_minutes = GameTime.total_minutes


# ------------------------------------------------------------------ queries used by the brain
func place_name(id: int) -> String:
	return (places[id] as Place).name if id >= 0 and id < places.size() else "?"


func place_price(id: int) -> int:
	return (places[id] as Place).price_level if id >= 0 else 1


func place_is_indoor(id: int) -> bool:
	if id < 0 or id >= places.size():
		return false
	return not ((places[id] as Place).type in OUTDOOR_TYPES)


func is_raining() -> bool:
	var env := world.get("environment") as EnvironmentController if world else null
	return env != null and env.is_raining()


func hobby_tags(n: NPCData) -> Array:
	var map := {"jogging": ["jog", "outdoor"], "basketball": ["sports"], "reading": ["leisure"], "gaming": ["leisure"],
		"music": ["leisure"], "cooking": ["groceries"], "shopping": ["shop"], "coffee": ["coffee"], "people watching": ["social", "free"],
		"gardening": ["outdoor"], "photography": ["outdoor", "leisure"], "fitness": ["sports"]}
	var out: Array = []
	for h in n.hobbies:
		out.append_array(map.get(h, ["leisure"]))
	if out.is_empty():
		out = ["leisure"]
	return out


func pick_place(n: NPCData, tags: Array, p_rng: RandomNumberGenerator, open_now: bool = true, max_dist: float = INF) -> int:
	var h := GameTime.get_hour_float()
	var best := -1
	var best_s := -INF
	var raining := is_raining()
	for p in places:
		var pl := p as Place
		if pl.type in ["home", "apartment", "player_home"]:
			continue
		var ok := false
		for t in tags:
			if t in pl.tags:
				ok = true
				break
		if not ok:
			continue
		if open_now and not pl.is_open(h):
			continue
		var d := n.pos.distance_to(pl.entry_pos)
		if d > max_dist:
			continue
		var s := -d / 220.0 + p_rng.randf() * 0.5
		if pl.price_level >= 2 and n.money < 60:
			s -= 0.6
		if raining and pl.type in OUTDOOR_TYPES:
			s -= 0.8
		if pl.occupants.size() >= pl.capacity:
			s -= 1.0
		if s > best_s:
			best_s = s
			best = pl.id
	return best


func nearest_place_with(pos: Vector3, tags: Array, open_now: bool) -> int:
	var h := GameTime.get_hour_float()
	var best := -1
	var bd := INF
	for p in places:
		var pl := p as Place
		var ok := false
		for t in tags:
			if t in pl.tags:
				ok = true
		if not ok or (open_now and not pl.is_open(h)) or pl.type in OUTDOOR_TYPES:
			continue
		var d := pos.distance_to(pl.entry_pos)
		if d < bd:
			bd = d
			best = pl.id
	return best


func place_with_open_job(n: NPCData) -> int:
	var cands: Array = []
	for p in places:
		var pl := p as Place
		if not pl.jobs.is_empty() and pl.is_open(GameTime.get_hour_float()) and _free_job(pl) != {}:
			cands.append(pl.id)
	if cands.is_empty():
		return -1
	cands.sort_custom(func(a: int, b: int) -> bool: return n.pos.distance_to(places[a].entry_pos) < n.pos.distance_to(places[b].entry_pos))
	return cands[0]


func _free_job(pl: Place) -> Dictionary:
	for jdef in pl.jobs:
		var used := 0
		for n in npcs:
			if (n as NPCData).has_job() and int(n.job.place) == pl.id and n.job.title == jdef.title:
				used += 1
		if used < int(jdef.get("slots", 1)):
			return jdef
	return {}


## Interview: confident, smart, hard-working applicants get hired more easily.
func try_hire(n: NPCData, place_id: int) -> bool:
	var pl: Place = places[place_id]
	var jdef := _free_job(pl)
	if jdef.is_empty():
		return false
	var chance := 0.35 + n.trait_value("confidence") * 0.25 + n.trait_value("intelligence") * 0.2 - n.trait_value("laziness") * 0.2
	if rng.randf() > chance:
		n.emotion.add("sad", 0.2)
		n.action_reason = "interview at %s went badly" % pl.name
		return false
	n.job = {"place": pl.id, "title": jdef.title, "wage": int(jdef.wage), "start": float(jdef.start), "end": float(jdef.end), "days": [0, 1, 2, 3, 4]}
	n.emotion.add("happy", 0.5)
	n.emotion.add("excited", 0.5)
	n.action_reason = "got hired as %s!" % jdef.title
	n.plan_day = -1
	return true


# ------------------------------------------------------------------ routing & places
func route_to(n: NPCData, place_id: int) -> void:
	var from := city.graph.nearest(n.pos)
	var to: int
	if place_id < 0:
		# wander: random node within ~120 m
		var tries := 0
		to = from
		while tries < 10:
			var cand := rng.randi_range(0, city.graph.node_count() - 1)
			if city.graph.pos(cand).distance_to(n.pos) < 140.0:
				to = cand
				break
			tries += 1
	else:
		to = (places[place_id] as Place).entry_node
	n.path = city.graph.path(from, to)
	n.path_index = 0
	if n.path.size() > 0 and n.path[0].distance_to(n.pos) < 0.5:
		n.path_index = 1
	if n.path_index >= n.path.size():
		n.path = PackedVector3Array()


## Destination reached (entry of the target place, or a spot inside it).
func arrive(n: NPCData) -> void:
	n.path = PackedVector3Array()
	n.path_index = 0
	var pid := n.action_target
	if pid < 0:
		NPCBrain.begin_activity(n, self)
		return
	var pl: Place = places[pid]
	if n.at_place != pid:
		n.at_place = pid
		pl.occupants[n.id] = true
		# Outdoor places and modelled interiors: walk to a spot and stay visible.
		if not pl.spots.is_empty() and (pl.type in OUTDOOR_TYPES or pl.enterable):
			var kind := "seat" if n.action in ["rest", "socialize", "eat_out", "coffee", "leisure"] else ""
			if n.action == "work":
				kind = "work"
			var si := pl.free_spot(kind)
			if si < 0:
				si = pl.free_spot("")
			if si >= 0:
				pl.spots[si]["taken_by"] = n.id
				n.action_spot = si
				var sp: Dictionary = pl.spots[si]
				var target: Vector3 = sp["pos"]
				if sp.has("node"):
					n.path = city.graph.path(pl.entry_node, int(sp["node"]))
				else:
					n.path = PackedVector3Array([target])
				n.path_index = 0
				if not n.path.is_empty():
					return   # will call arrive() again at the spot
		if pl.type in OUTDOOR_TYPES or pl.enterable:
			n.inside = false
		else:
			n.inside = true
			n.pos = pl.inside_pos
	NPCBrain.begin_activity(n, self)


func exit_place(n: NPCData) -> void:
	if n.at_place >= 0:
		var pl: Place = places[n.at_place]
		pl.occupants.erase(n.id)
		if n.inside:
			n.pos = pl.entry_pos
	release_spot(n)
	n.inside = false
	n.at_place = -1


func release_spot(n: NPCData) -> void:
	if n.action_spot >= 0 and n.at_place >= 0:
		var pl: Place = places[n.at_place]
		if n.action_spot < pl.spots.size() and int(pl.spots[n.action_spot].get("taken_by", -1)) == n.id:
			pl.spots[n.action_spot]["taken_by"] = -1
	n.action_spot = -1


func current_spot(n: NPCData) -> Dictionary:
	if n.action_spot >= 0 and n.at_place >= 0:
		var pl: Place = places[n.at_place]
		if n.action_spot < pl.spots.size():
			return pl.spots[n.action_spot]
	return {}


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if npcs.is_empty():
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	# Catch up after a big time skip (sleeping): coarse simulation steps.
	var now := GameTime.total_minutes
	if _last_world_minutes >= 0.0 and now - _last_world_minutes > 30.0:
		fast_forward(now - _last_world_minutes)
	_last_world_minutes = now
	_tick_brains(delta)
	_move_abstract(delta)
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		_update_lod()
	_encounter_timer -= delta
	if _encounter_timer <= 0.0:
		_encounter_timer = 1.0
		_encounters()
	_tick_window += delta
	if _tick_window >= 1.0:
		stats.ticks_per_sec = _tick_counter
		_tick_counter = 0
		_tick_window = 0.0


func _tick_brains(_delta: float) -> void:
	# Round robin: every NPC is ticked about every 0.6 s (near) .. 2 s (far).
	var per_frame := maxi(2, int(ceil(npcs.size() / 30.0)))
	for k in per_frame:
		_tick_index = (_tick_index + 1) % npcs.size()
		var n: NPCData = npcs[_tick_index]
		var interval := 0.3 if n.lod == 0 else (1.0 if n.lod == 1 else 2.0)
		var mins := GameTime.total_minutes - float(_last_tick_min.get(n.id, GameTime.total_minutes))
		if mins < interval * GameTime.minutes_per_second and n.action != "idle":
			continue
		_last_tick_min[n.id] = GameTime.total_minutes
		NPCBrain.tick(n, self, maxf(mins, 0.0))
		_tick_counter += 1
		if n.reaction != "" and GameTime.total_minutes > n.reaction_until:
			n.reaction = ""
			NPCBrain.decide(n, self)


func _move_abstract(delta: float) -> void:
	var step := ABSTRACT_SPEED * ABSTRACT_SPEEDUP * delta * GameTime.minutes_per_second
	for n in npcs:
		var nd := n as NPCData
		if body_of.has(nd.id) or nd.path.is_empty() or nd.reaction != "":
			continue
		var remaining := step
		while remaining > 0.0 and nd.path_index < nd.path.size():
			var target := nd.path[nd.path_index]
			var to := target - nd.pos
			var d := to.length()
			if d <= remaining:
				nd.pos = target
				remaining -= d
				nd.path_index += 1
			else:
				nd.pos += to / d * remaining
				nd.yaw = atan2(-to.x, -to.z)
				remaining = 0.0
		if nd.path_index >= nd.path.size():
			arrive(nd)


func fast_forward(minutes: float) -> void:
	var stepm := 15.0
	var t := 0.0
	while t < minutes:
		var chunk := minf(stepm, minutes - t)
		for n in npcs:
			var nd := n as NPCData
			NPCBrain.decay_needs(nd, chunk)
			if not nd.path.is_empty():
				nd.pos = nd.path[nd.path.size() - 1]
				arrive(nd)
			if nd.action_until > 0.0 and GameTime.total_minutes - minutes + t + chunk >= nd.action_until:
				NPCBrain.finish_activity(nd, self)
				nd.action_until = 0.0
				NPCBrain.decide(nd, self)
		t += chunk
	for n in npcs:
		_last_tick_min[n.id] = GameTime.total_minutes


# ------------------------------------------------------------------ LOD / bodies
func _update_lod() -> void:
	if player == null:
		return
	var pp := player.global_position
	var cands: Array = []
	for n in npcs:
		var nd := n as NPCData
		var d := nd.pos.distance_to(pp)
		var visible_spot := not nd.inside
		nd.lod = 0 if d < NEAR else (1 if d < MID else 2)
		if visible_spot and d < MID:
			cands.append([d, nd])
		else:
			nd.lod = 2 if not body_of.has(nd.id) else nd.lod
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var want: Dictionary = {}
	for k in mini(cands.size(), max_bodies):
		want[cands[k][1].id] = cands[k]
	# Release bodies that are no longer wanted (hysteresis: keep if within MID + 10).
	for id in body_of.keys():
		if not want.has(id):
			var b2: NPCBody = body_of[id]
			# Never pop someone out of existence while they are lying on the ground.
			if not b2.is_down():
				_release_body(id)
	var assigned := 0
	for id in want.keys():
		if body_of.has(id):
			var bd: NPCBody = body_of[id]
			# Full mesh + face/IK only up close; everyone else uses the light mesh.
			bd.set_lod(0 if want[id][0] < 20.0 else 1)
			continue
		if assigned >= 2:
			break   # spread the cost of building characters over frames
		if body_of.size() >= max_bodies:
			break
		_assign_body(npcs[id])
		assigned += 1
	stats.embodied = body_of.size()


func _assign_body(n: NPCData) -> void:
	var body: NPCBody = null
	for b in bodies:
		if (b as NPCBody).npc == null:
			body = b
			break
	if body == null:
		body = NPCBody.new()
		body.manager = self
		body.name = "NPCBody%d" % bodies.size()
		world.add_child(body)
		bodies.append(body)
	body.attach(n)
	body_of[n.id] = body


func _release_body(id: int) -> void:
	var b: NPCBody = body_of.get(id)
	if b:
		b.detach()
	body_of.erase(id)


func body_for(id: int) -> NPCBody:
	return body_of.get(id)


# ------------------------------------------------------------------ social encounters
func _encounters() -> void:
	# Embodied NPCs passing each other: greet friends, sometimes stop to chat or meet someone new.
	var embodied: Array = body_of.keys()
	for a_i in embodied.size():
		for b_i in range(a_i + 1, embodied.size()):
			var a: NPCData = npcs[embodied[a_i]]
			var b: NPCData = npcs[embodied[b_i]]
			if a.pos.distance_squared_to(b.pos) > 16.0:
				continue
			_maybe_interact(a, b, true)
	# Abstract: people at the same outdoor/social place mingle.
	if rng.randf() < 0.3:
		var by_place: Dictionary = {}
		for n in npcs:
			var nd := n as NPCData
			if nd.at_place >= 0 and nd.action in ["socialize", "leisure", "eat_out", "coffee", "work", "rest"] and nd.action_until > 0.0:
				if not by_place.has(nd.at_place):
					by_place[nd.at_place] = []
				by_place[nd.at_place].append(nd)
		for pid in by_place.keys():
			var group: Array = by_place[pid]
			if group.size() >= 2:
				var a2: NPCData = group[rng.randi() % group.size()]
				var b2: NPCData = group[rng.randi() % group.size()]
				if a2 != b2:
					_maybe_interact(a2, b2, false)


func _maybe_interact(a: NPCData, b: NPCData, visible: bool) -> void:
	if a.reaction != "" or b.reaction != "" or a.action == "chat" or b.action == "chat":
		return
	var know := a.knows(b.id)
	var fa := float(a.rel(b.id).friendship) if know else 0.0
	if a.action == "work" and b.action == "work" and a.at_place == b.at_place:
		a.change_rel(b.id, {"familiarity": 0.02, "friendship": 0.01})
		b.change_rel(a.id, {"familiarity": 0.02, "friendship": 0.01})
		return
	if know:
		if fa < -0.3:
			# Avoid / glare at people they dislike.
			a.emotion.add("irritated", 0.2)
			if visible and body_of.has(a.id):
				body_of[a.id].glance_at(b.pos)
			return
		var p_chat := 0.25 + (a.trait_value("sociability") + b.trait_value("sociability")) * 0.2 + fa * 0.3
		if a.action_until <= 0.0 and a.action in ["work", "sleep"]:
			p_chat *= 0.2   # in a hurry to work
		if visible and body_of.has(a.id):
			body_of[a.id].wave_at(b)
		if rng.randf() < p_chat:
			_start_chat(a, b, visible)
	else:
		var p_meet := (a.trait_value("sociability") * 0.5 + a.trait_value("friendliness") * 0.3 - a.trait_value("shyness") * 0.4) * 0.12
		if rng.randf() < p_meet:
			a.change_rel(b.id, {"familiarity": 0.25, "friendship": 0.08, "type": "acquaintance"})
			b.change_rel(a.id, {"familiarity": 0.25, "friendship": 0.06, "type": "acquaintance"})
			a.memory.add("met_new_person", b.id, GameTime.total_minutes, place_name(a.at_place), 0.3, 0.3)
			_start_chat(a, b, visible)


func _start_chat(a: NPCData, b: NPCData, _visible: bool) -> void:
	var minutes := rng.randf_range(4.0, 15.0)
	for pair in [[a, b], [b, a]]:
		var x: NPCData = pair[0]
		var y: NPCData = pair[1]
		x.set_meta("resume_action", x.action)
		x.action = "chat"
		x.action_reason = "chatting with %s (%s)" % [y.first_name, x.relation_label(y.id).to_lower()]
		x.talk_partner = y.id
		x.action_until = GameTime.total_minutes + minutes
		x.path = PackedVector3Array()
		var compat := 0.06 - absf(x.trait_value("aggression") - y.trait_value("aggression")) * 0.05
		x.change_rel(y.id, {"familiarity": 0.05, "friendship": compat, "trust": compat * 0.5})
		x.memory.add("chat", y.id, GameTime.total_minutes, place_name(x.at_place), 0.15, 0.2)
		x.emotion.add("happy", 0.08)


# ------------------------------------------------------------------ events & reactions
## Non-violent knocks (bumps, thrown objects) still scare / annoy people.
func _on_impacted(body: Node, info: Dictionary) -> void:
	if body is NPCBody and (body as NPCBody).npc and int(info.get("source", -1)) != ImpactData.Source.PUNCH:
		var n: NPCData = (body as NPCBody).npc
		if float(info.get("dv", 0.0)) > 0.8:
			n.emotion.add("fear", 0.2)
			n.emotion.add("irritated", 0.2)


func _on_world_event(ev: Dictionary) -> void:
	if ev.get("type", "") != "assault":
		return
	var pos: Vector3 = ev.position
	var victim = ev.get("victim")
	var instigator = ev.get("instigator")
	var victim_id := -1
	if victim is NPCBody and (victim as NPCBody).npc:
		victim_id = (victim as NPCBody).npc.id
	var inst_id: int = NPCData.PLAYER_ID if instigator is PlayerController else (instigator.npc.id if instigator is NPCBody and instigator.npc else -1)
	for id in body_of.keys():
		var n: NPCData = npcs[id]
		var b: NPCBody = body_of[id]
		var d := n.pos.distance_to(pos)
		if d > float(ev.get("radius", 25.0)):
			continue
		if n.id != victim_id and not b.can_see(pos + Vector3(0, 1.2, 0)):
			continue
		NPCReactions.react(n, b, ev, victim_id, inst_id, self)


# ------------------------------------------------------------------ player social actions
func npc_from_body(b: Node) -> NPCData:
	return (b as NPCBody).npc if b is NPCBody else null
