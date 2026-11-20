extends Node3D
## Automated tests (run headless):
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when everything passes.

var _pass := 0
var _fail := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("PASS  ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("FAIL  ", name, ("  " + detail) if detail != "" else "")


func _ready() -> void:
	await get_tree().process_frame
	test_save_system()
	test_appearance_and_mesh()
	test_animation_library()
	test_balance_controller()
	test_memory()
	var city := test_city()
	test_npc_generation(city)
	test_utility_ai(city)
	test_day_simulation(city)
	print("TESTS %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ------------------------------------------------------------------
func test_save_system() -> void:
	var slot := 3
	SaveSystem.delete_slot(slot)
	var data := {"time": {"total_minutes": 1234.0}, "game": {"profile": {"name": "Tester", "money": 77}}, "x": [1, 2, 3]}
	check("save: write slot", SaveSystem.write_slot(slot, data, "test"))
	var env := SaveSystem.read_slot(slot)
	check("save: read back", not env.is_empty() and env.sections.game.profile.name == "Tester" and int(env.sections.game.profile.money) == 77)
	data.game.profile.money = 99
	SaveSystem.write_slot(slot, data, "test2")
	check("save: backup rotated", FileAccess.file_exists(SaveSystem.slot_path(slot, ".bak1")))
	# Corrupt the main file -> must fall back to backup.
	var f := FileAccess.open(SaveSystem.slot_path(slot), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var env2 := SaveSystem.read_slot(slot)
	check("save: corrupted file -> restored from backup", not env2.is_empty() and env2.restored_from == ".bak1" and int(env2.sections.game.profile.money) == 77)
	# Tampered checksum
	SaveSystem.write_slot(slot, data, "test3")
	var text := FileAccess.get_file_as_string(SaveSystem.slot_path(slot)).replace("99", "98")
	var f2 := FileAccess.open(SaveSystem.slot_path(slot), FileAccess.WRITE)
	f2.store_string(text)
	f2.close()
	check("save: checksum mismatch detected", SaveSystem.read_slot(slot).restored_from != "")
	SaveSystem.delete_slot(slot)


func test_appearance_and_mesh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var ok := true
	var min_v := 1 << 30
	var max_v := 0
	var looks := {}
	for i in 30:
		var a := CharacterAppearance.new().randomize_look(rng)
		var d := a.to_dict()
		var b := CharacterAppearance.from_dictionary(JSON.parse_string(JSON.stringify(d)))
		if JSON.stringify(b.to_dict()) != JSON.stringify(d):
			ok = false
		looks[JSON.stringify([a.hair_style, a.top, a.jacket, a.pants, a.hat, a.skin_color.to_html()])] = true
		var sk := HumanoidDef.build_skeleton(a.body_dims())
		var mesh := CharacterMeshFactory.build(a, sk, 1.0)
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		min_v = mini(min_v, verts.size())
		max_v = maxi(max_v, verts.size())
		for v in verts:
			if not v.is_finite():
				ok = false
				break
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		for bi in bones:
			if bi < 0 or bi >= sk.get_bone_count():
				ok = false
				break
		sk.free()
	check("appearance: dict round trip + valid skinned meshes", ok, "verts %d..%d" % [min_v, max_v])
	check("appearance: 30 random people look different", looks.size() >= 28, "%d unique" % looks.size())
	check("mesh budget: < 9000 verts per character", max_v < 9000)


func test_animation_library() -> void:
	var lib := AnimLibraryBuilder.get_library()
	var sk := HumanoidDef.build_skeleton({})
	var ok := true
	var bad := ""
	for an in lib.get_animation_list():
		var anim := lib.get_animation(an)
		for t in anim.get_track_count():
			var path := String(anim.track_get_path(t))
			var bone := path.get_slice(":", 1)
			if sk.find_bone(bone) < 0:
				ok = false
				bad = path
	check("animations: every track targets an existing bone", ok, bad)
	var needed: Array = CharacterAnimator.STATES + CharacterAnimator.FULL_ACTIONS + CharacterAnimator.UPPER_ACTIONS + ["idle", "walk", "jog", "run", "sprint", "injured_walk", "crouch_walk"]
	var missing := needed.filter(func(n: String) -> bool: return n != "loco" and n != "crouch" and not lib.has_animation(n))
	check("animations: all states/actions have clips", missing.is_empty(), str(missing))
	check("animations: library size", lib.get_animation_list().size() >= 45, "%d clips" % lib.get_animation_list().size())
	sk.free()


func test_balance_controller() -> void:
	var results := {}
	for dv in [0.5, 1.6, 4.0]:
		var b := BalanceController.new()
		b.strength = 0.5
		b.balance_skill = 0.5
		b.add_velocity(Vector2(dv, 0))
		var fell := false
		var steps := 0
		for i in 120:
			var r := b.step(1.0 / 60.0)
			if r.result == BalanceController.Result.FALL:
				fell = true
				break
			if r.result == BalanceController.Result.STEP:
				steps += 1
		results[dv] = [fell, steps, b.offset.length()]
	check("balance: light push recovers without stepping", not results[0.5][0] and results[0.5][1] == 0)
	check("balance: medium push -> corrective steps, stays up", not results[1.6][0] and results[1.6][1] > 0, str(results[1.6]))
	check("balance: heavy push -> fall", results[4.0][0])
	var weak := BalanceController.new()
	weak.strength = 0.1
	weak.fatigue = 0.9
	var strong := BalanceController.new()
	strong.strength = 0.95
	check("balance: tired weak body has less capacity", weak.capacity() < strong.capacity() * 0.6)


func test_memory() -> void:
	var m := NPCMemory.new()
	m.add("chat", 5, 0.0, "park", 0.1, 0.2)
	m.add("assaulted", -100, 0.0, "street", 0.95, -1.0)
	m.decay(60.0 * 72.0)   # three days
	var events := m.entries.map(func(e: Dictionary) -> String: return e.event)
	check("memory: trivial events fade, important ones stay", not "chat" in events and "assaulted" in events)
	check("memory: sentiment toward attacker is negative", m.sentiment(-100) < -0.3)


# ------------------------------------------------------------------
func test_city() -> CityBuilder:
	var cb := CityBuilder.new()
	var t0 := Time.get_ticks_msec()
	cb.build(self, 1984)
	check("city: builds", cb.places.size() > 40, "%d places, %d ms" % [cb.places.size(), Time.get_ticks_msec() - t0])
	check("city: pedestrian network fully connected", cb.graph.is_connected_graph(), "%d nodes" % cb.graph.node_count())
	var unreachable := 0
	var homes := cb.places.filter(func(p: Place) -> bool: return p.type in ["home", "apartment"])
	for p in cb.places:
		if cb.graph.path((homes[0] as Place).entry_node, (p as Place).entry_node).is_empty():
			unreachable += 1
	check("city: every place reachable on foot", unreachable == 0)
	check("city: player home exists and is enterable", cb.player_home != null and cb.player_home.enterable)
	var types := {}
	for p in cb.places:
		types[(p as Place).type] = true
	check("city: variety of places", types.size() >= 12, str(types.keys()))
	var jobs := 0
	for p in cb.places:
		for j in (p as Place).jobs:
			jobs += int(j.slots)
	check("city: workplaces offer jobs", jobs > 40, "%d job slots" % jobs)
	return cb


func test_npc_generation(cb: CityBuilder) -> void:
	var npcs := NPCGenerator.generate(cb.places, 60, 777)
	check("npc: population", npcs.size() == 60)
	var names := {}
	var employed := 0
	var rels := 0
	var trait_sum := {}
	for n in npcs:
		names[(n as NPCData).full_name()] = true
		if n.has_job():
			employed += 1
		rels += n.relationships.size()
		for t in Personality.TRAITS:
			trait_sum[t] = trait_sum.get(t, []) + [n.trait_value(t)]
	check("npc: names mostly unique", names.size() >= 52, "%d unique" % names.size())
	check("npc: most adults employed", employed > 35, "%d employed" % employed)
	check("npc: social web exists", rels > 100, "%d relationships" % rels)
	var spread_ok := true
	for t in trait_sum.keys():
		var arr: Array = trait_sum[t]
		var mn: float = arr.min()
		var mx: float = arr.max()
		if mx - mn < 0.4:
			spread_ok = false
	check("npc: personalities vary on every trait", spread_ok)
	# Correlations: shy people should be less sociable on average.
	var shy_soc := 0.0
	var out_soc := 0.0
	var shy_n := 0
	var out_n := 0
	for n in npcs:
		if n.trait_value("shyness") > 0.6:
			shy_soc += n.trait_value("sociability")
			shy_n += 1
		elif n.trait_value("shyness") < 0.4:
			out_soc += n.trait_value("sociability")
			out_n += 1
	check("npc: coherent personalities (shy -> less sociable)", shy_n == 0 or out_n == 0 or shy_soc / shy_n < out_soc / out_n)


func _mgr(cb: CityBuilder) -> NPCManager:
	var m := NPCManager.new()
	add_child(m)
	m.world = self
	m.city = cb
	m.places = cb.places
	m.rng.seed = 1
	m.set_process(false)
	return m


func test_utility_ai(cb: CityBuilder) -> void:
	var m := _mgr(cb)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	m.npcs = NPCGenerator.generate(cb.places, 20, 99)
	var n: NPCData = m.npcs[0]
	n.plan_day = GameTime.get_day()
	n.day_plan = []
	GameTime.total_minutes = 2 * 1440.0 + 15.0 * 60.0   # Wed 15:00
	n.needs = {"hunger": 4.0, "energy": 80.0, "social": 80.0, "fun": 80.0, "hygiene": 80.0}
	n.job = {}
	var s := NPCBrain.score_all(n, m)
	check("ai: starving -> eat is top choice", String(s[0][0]).begins_with("eat"), str(s.slice(0, 3)))
	GameTime.total_minutes = 2 * 1440.0 + 23.6 * 60.0
	n.needs = {"hunger": 80.0, "energy": 15.0, "social": 80.0, "fun": 80.0, "hygiene": 80.0}
	n.sleep_hour = 23.0
	s = NPCBrain.score_all(n, m)
	check("ai: tired at night -> sleep", s[0][0] == "sleep", str(s.slice(0, 3)))
	GameTime.total_minutes = 2 * 1440.0 + 9.5 * 60.0
	n.needs = {"hunger": 70.0, "energy": 70.0, "social": 60.0, "fun": 60.0, "hygiene": 80.0}
	n.job = {"place": 5, "title": "Clerk", "wage": 15, "start": 9.0, "end": 17.0, "days": [0, 1, 2, 3, 4]}
	n.sick_today = false
	n.skip_work_today = false
	s = NPCBrain.score_all(n, m)
	check("ai: work hours on a weekday -> work", s[0][0] == "work", str(s.slice(0, 3)))
	# Personality matters: lonely sociable vs lonely shy person.
	var a: NPCData = m.npcs[1]
	var b: NPCData = m.npcs[2]
	for x in [a, b]:
		x.job = {}
		x.needs = {"hunger": 80.0, "energy": 80.0, "social": 20.0, "fun": 70.0, "hygiene": 80.0}
		x.plan_day = GameTime.get_day()
		x.day_plan = []
	a.personality.set_trait("sociability", 0.95)
	a.personality.set_trait("shyness", 0.05)
	b.personality.set_trait("sociability", 0.1)
	b.personality.set_trait("shyness", 0.95)
	GameTime.total_minutes = 5 * 1440.0 + 19.0 * 60.0   # Saturday evening
	var sa := _score_of(NPCBrain.score_all(a, m), "socialize")
	var sb := _score_of(NPCBrain.score_all(b, m), "socialize")
	check("ai: sociable person wants company more than a shy one", sa > sb + 0.2, "%.2f vs %.2f" % [sa, sb])
	m.queue_free()


func _score_of(table: Array, action: String) -> float:
	for r in table:
		if r[0] == action:
			return r[1]
	return 0.0


func test_day_simulation(cb: CityBuilder) -> void:
	var m := _mgr(cb)
	m.npcs = NPCGenerator.generate(cb.places, 60, 777)
	for p in cb.places:
		(p as Place).occupants = {}
		for s in (p as Place).spots:
			s["taken_by"] = -1
	GameTime.total_minutes = 7 * 1440.0 + 6.0 * 60.0   # Monday 06:00 (day 7)
	for n in m.npcs:
		NPCBrain.decide(n, m)
	var money_start := {}
	for n in m.npcs:
		money_start[n.id] = n.money
	var at_work_11 := 0
	var should_work := 0
	var asleep_3 := 0
	var actions_seen := {}
	var stuck := 0
	var min_hunger := 100.0
	var step := 5.0
	var t := 0.0
	while t < 48.0 * 60.0:
		GameTime.advance(step)
		for n in m.npcs:
			NPCBrain.tick(n, m, step)
			if n.reaction != "":
				n.reaction = ""
		m._move_abstract(step / GameTime.minutes_per_second)
		t += step
		var h := GameTime.get_hour_float()
		for n in m.npcs:
			actions_seen[n.action] = true
		if absf(h - 11.0) < 0.04 and GameTime.get_weekday() < 5:
			for n in m.npcs:
				if n.works_today(GameTime.get_weekday()) and hour_in(11.0, float(n.job.start), float(n.job.end)) and not n.sick_today and not n.skip_work_today:
					should_work += 1
					if n.action == "work" and n.at_place == int(n.job.place):
						at_work_11 += 1
		if absf(h - 3.0) < 0.04:
			for n in m.npcs:
				if n.action == "sleep":
					asleep_3 += 1
	for n in m.npcs:
		min_hunger = minf(min_hunger, float(n.needs.hunger))
		if n.action == "idle":
			stuck += 1
	var earned := 0
	for n in m.npcs:
		if n.has_job() and n.money > money_start[n.id]:
			earned += 1
	check("sim: workers are at work during shifts", should_work > 0 and float(at_work_11) / should_work > 0.6, "%d / %d" % [at_work_11, should_work])
	check("sim: most people sleep at 3 am", asleep_3 > 2 * 60 * 0.6, "%d / %d (2 nights)" % [asleep_3, 120])
	check("sim: varied daily activities", actions_seen.size() >= 8, str(actions_seen.keys()))
	check("sim: nobody stuck idle", stuck == 0)
	check("sim: people eat (no starvation)", min_hunger > 5.0, "min hunger %.1f" % min_hunger)
	check("sim: workers earn money", earned > 20, "%d earned" % earned)
	var befriended := 0
	for n in m.npcs:
		for r in n.relationships.values():
			if r.type == "acquaintance" and float(r.familiarity) > 0.2:
				befriended += 1
	check("sim: relationships exist after two days", befriended > 0, "%d acquaintances" % befriended)
	m.queue_free()


static func hour_in(h: float, a: float, b: float) -> bool:
	return NPCBrain.hour_in(h, a, b)
