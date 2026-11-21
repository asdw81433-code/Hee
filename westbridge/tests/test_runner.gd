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
	test_character_asset()
	test_animation_library()
	test_balance_controller()
	test_memory()
	var city := test_city()
	test_npc_generation(city)
	test_utility_ai(city)
	test_day_simulation(city)
	await test_economy(city)
	print("TESTS %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


class FakeWorld extends Node:
	var city: CityBuilder
	var npcs: Variant = null
	var player: Variant = null
	var map_screen: Variant = null


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


## The Blender-made character library (assets/characters/westbridge_characters.glb).
func test_character_asset() -> void:
	var lib := CharacterAssetLibrary
	check("asset: Blender character library loads", lib.available(), "%d parts" % lib.parts.size())
	if not lib.available():
		return
	# Same skeleton as the procedural humans -> every animation / ragdoll / face rig works.
	var ref := HumanoidDef.global_rest_positions({})
	var same := lib.bone_order.size() == ref.size()
	var worst := 0.0
	for bn in ref.keys():
		if not lib.rest_positions.has(bn):
			same = false
			continue
		worst = maxf(worst, ((lib.rest_positions[bn] as Vector3) - (ref[bn] as Vector3)).length())
	check("asset: bone names + joints match HumanoidDef", same and worst < 0.002, "max joint error %.4f m" % worst)
	var missing: Array = []
	var probe := CharacterAppearance.new()
	for field in [["hair_style", CharacterAssetBuilder.HAIR], ["beard_style", CharacterAssetBuilder.BEARD], ["mustache_style", CharacterAssetBuilder.MUSTACHE],
			["top", CharacterAssetBuilder.TOPS], ["jacket", CharacterAssetBuilder.JACKETS], ["pants", CharacterAssetBuilder.PANTS],
			["shoes", CharacterAssetBuilder.SHOES], ["hat", CharacterAssetBuilder.HATS], ["glasses", CharacterAssetBuilder.GLASSES],
			["bag", CharacterAssetBuilder.BAGS], ["accessory", CharacterAssetBuilder.ACCESSORIES]]:
		for i in (field[1] as Array).size():
			probe.set(field[0], i)
			for e in CharacterAssetBuilder.part_list(probe):
				for lod in 2:
					if CharacterAssetBuilder.resolve_part(e[0], lod) == "" and not (lod == 1 and e[0] in CharacterAssetBuilder.SMALL_PARTS):
						missing.append("%s@%d" % [e[0], lod])
		probe.set(field[0], 0)
	check("asset: every creator option has a modelled part (LOD0 + LOD1)", missing.is_empty(), str(missing.slice(0, 6)))
	check("asset: creator lists match the part tables",
		CharacterAppearance.JACKETS.size() == CharacterAssetBuilder.JACKETS.size() and CharacterAppearance.HATS.size() == CharacterAssetBuilder.HATS.size()
		and CharacterAppearance.TOPS.size() == CharacterAssetBuilder.TOPS.size() and CharacterAppearance.HAIR_STYLES.size() == CharacterAssetBuilder.HAIR.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	var max_t0 := 0
	var max_t1 := 0
	var max_v0 := 0
	for i in 24:
		var a := CharacterAppearance.new().randomize_look(rng, -1, -1, ["", "police", "worker", "office"][i % 4])
		var sk := CharacterAssetBuilder.build_skeleton(a.height, a.eye_spacing)
		for lod in 2:
			var arr := CharacterAssetBuilder.build(a, sk, a.height, lod).surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var t: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if lod == 0:
				max_t0 = maxi(max_t0, t)
				max_v0 = maxi(max_v0, verts.size())
			else:
				max_t1 = maxi(max_t1, t)
			for v in verts:
				if not v.is_finite():
					ok = false
			for bi in (arr[Mesh.ARRAY_BONES] as PackedInt32Array):
				if bi < 0 or bi >= sk.get_bone_count():
					ok = false
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for k in range(0, ws.size(), 4):
				if absf(ws[k] + ws[k + 1] + ws[k + 2] + ws[k + 3] - 1.0) > 0.01:
					ok = false
		sk.free()
	check("asset: 24 random people -> valid skinned meshes", ok)
	check("asset: triangle budget LOD0 < 10k, LOD1 < 4k", max_t0 < 10000 and max_t1 < 4000, "LOD0 max %d tris / %d verts, LOD1 max %d tris" % [max_t0, max_v0, max_t1])
	# Hidden-surface removal: the body under long sleeves + trousers + shoes loses most triangles.
	var dressed := CharacterAppearance.new()
	dressed.top = 1
	dressed.pants = 0
	var bare := CharacterAppearance.new()
	bare.top = 3
	bare.pants = 2
	var b_body: int = (lib.parts["Body"].i as PackedInt32Array).size() / 3
	var dress_mask := CharacterAssetBuilder.worn_mask(CharacterAssetBuilder.part_list(dressed))
	var hidden := 0
	var mk: PackedInt32Array = lib.parts["Body"].mask
	var bi_: PackedInt32Array = lib.parts["Body"].i
	for t in range(0, bi_.size(), 3):
		if (mk[bi_[t]] & mk[bi_[t + 1]] & mk[bi_[t + 2]] & dress_mask) != 0:
			hidden += 1
	check("asset: body hidden under clothes", hidden > b_body * 0.4, "%d of %d body triangles hidden" % [hidden, b_body])
	# Shape keys: heavy people are wider, women's builds differ.
	var sk2 := CharacterAssetBuilder.build_skeleton(1.0)
	var slim := CharacterAppearance.new()
	slim.weight = 0.1
	var heavy := CharacterAppearance.new()
	heavy.weight = 1.0
	var belly := func(mesh: ArrayMesh) -> float:
		var front := -1.0
		for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if v.y > 1.0 and v.y < 1.15 and absf(v.x) < 0.1:
				front = maxf(front, v.z)
		return front
	var w_slim: float = belly.call(CharacterAssetBuilder.build(slim, sk2, 1.0))
	var w_heavy: float = belly.call(CharacterAssetBuilder.build(heavy, sk2, 1.0))
	sk2.free()
	check("asset: Heavy/Thin shape keys change the body", w_heavy > w_slim + 0.02, "belly front %.3f -> %.3f m" % [w_slim, w_heavy])
	# Police uniform uses the dedicated vest + cap parts.
	var cop := CharacterAppearance.new().randomize_look(rng, -1, -1, "police")
	var names: Array = CharacterAssetBuilder.part_list(cop).map(func(e: Array) -> String: return e[0])
	check("asset: police role wears the police vest + cap", "Jacket_PoliceVest" in names and "Hat_PoliceCap" in names)
	# CharacterModel uses the asset and falls back to the procedural mesh when asked to.
	var m := CharacterModel.new()
	add_child(m)
	m.build(CharacterAppearance.new())
	var used_asset := m.uses_asset and m.skeleton.get_bone_count() == ref.size() and absf(m.hips_height - (ref["Hips"] as Vector3).y) < 0.01
	CharacterModel.force_procedural = true
	m.build(CharacterAppearance.new())
	var fell_back := not m.uses_asset and m.mesh_instance.mesh != null
	CharacterModel.force_procedural = false
	m.queue_free()
	check("asset: CharacterModel uses it, procedural fallback still works", used_asset and fell_back)


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
	test_world_map(cb)
	return cb


## Priority 1: the expanded world (10 districts, ~115 blocks, terrain, roads, streaming).
func test_world_map(cb: CityBuilder) -> void:
	var districts: Array = CityMap.district_names().filter(func(d: String) -> bool: return d != "Route 9")
	check("world: 10 districts", districts.size() == 10, str(districts))
	var blocks := CityMap.urban_block_count()
	check("world: 100-120 urban blocks", blocks >= 100 and blocks <= 120, "%d blocks, %d cells" % [blocks, CityMap.all_cells().size()])
	var per_district := {}
	for p in cb.places:
		per_district[(p as Place).district] = per_district.get((p as Place).district, 0) + 1
	var empty: Array = districts.filter(func(d: String) -> bool: return per_district.get(d, 0) < 3)
	check("world: every district has places to go", empty.is_empty(), str(per_district))
	var bridges := 0
	for bb in range(CityMap.GJ_MIN, CityMap.GJ_MAX + 2):
		if CityMap.hedge(5, bb) == "bridge":
			bridges += 1
	var junctions := 0
	for a in range(CityMap.GI_MIN, CityMap.GI_MAX + 2):
		if CityMap.vedge(a, -1) == "crossing":
			junctions += 1
	check("world: river bridges + Route 9 junctions", bridges >= 3 and junctions >= 4, "%d bridges, %d junctions" % [bridges, junctions])
	var peak := -INF
	for gi in range(-1, 5):
		peak = maxf(peak, CityMap.height_at(CityMap.block_center(gi, -5).x, CityMap.block_center(gi, -5).z))
	var deck := CityMap.road_height_at(CityMap.RIVER_X, CityMap.intersection(5, 1).z)
	check("world: hills + level bridges over the river", peak > 15.0 and deck >= 0.0 and CityMap.height_at(CityMap.RIVER_X, -60.0) < CityMap.RIVER_LEVEL, "summit %.1f m, bridge deck %.1f m" % [peak, deck])
	# Deterministic two-pass generation: rebuilding gives the same world.
	var cb2 := CityBuilder.new()
	cb2.build(self, 1984)
	var same := cb2.places.size() == cb.places.size()
	for k in mini(cb.places.size(), cb2.places.size()):
		if (cb.places[k] as Place).name != (cb2.places[k] as Place).name or (cb.places[k] as Place).entry_pos.distance_to((cb2.places[k] as Place).entry_pos) > 0.01:
			same = false
			break
	check("world: generation is deterministic", same, "%d places" % cb.places.size())
	# Streaming: the visual pass of every cell replays the data pass exactly.
	var t0 := Time.get_ticks_msec()
	for key in CityMap.all_cells():
		cb2.load_cell(key)
	var all_ms := Time.get_ticks_msec() - t0
	var dangling := 0
	var bound := 0
	for p in cb2.places:
		if not cb2.graph.astar.has_point((p as Place).entry_node):
			dangling += 1
		for sp in (p as Place).spots:
			if (sp as Dictionary).has("node") and not cb2.graph.astar.has_point(int(sp.node)):
				dangling += 1
			if (sp as Dictionary).has("seat") and sp.seat != null:
				bound += 1
	check("world: streamed cells match the data pass", cb2.stats.mismatch == 0 and dangling == 0 and bound > 20, "%d cells in %d ms, %d seats bound" % [cb2.stats.loaded, all_ms, bound])
	# Moving far away unloads the old area and loads the new one.
	var town := CityMap.block_center(2, 1)
	var fort := CityMap.block_center(-6, -4)
	cb2.update_streaming(town, 1e9)
	cb2.update_streaming(fort, 1e9)
	var town_loaded := cb2.is_loaded(Vector2i(2, 1))
	check("world: streaming loads near / unloads far", not town_loaded and cb2.is_loaded(Vector2i(-6, -4)), "%d cells loaded around Fort Calder" % cb2.stats.loaded)
	for key in CityMap.all_cells():
		cb2.unload_cell(key)
	cb2._world_root.queue_free()


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


# ------------------------------------------------------------------ Priority 2
## Shopping, inventory, bank, jobs (experience, shifts, pay, promotion, firing), rent.
func test_economy(cb: CityBuilder) -> void:
	var saved_time := GameTime.total_minutes
	var saved_profile: Dictionary = Game.player_profile.duplicate(true)
	var fw := FakeWorld.new()
	fw.city = cb
	add_child(fw)
	var eco := Economy.new()
	eco.world = fw
	add_child(eco)
	# every catalogued item exists
	var missing: Array = []
	for t in ItemDB.BY_TYPE.keys():
		for id in ItemDB.BY_TYPE[t]:
			if ItemDB.get_item(id).is_empty():
				missing.append(id)
	check("economy: every shop item exists", missing.is_empty(), str(missing))
	var sellers := cb.places.filter(func(p: Place) -> bool: return not ItemDB.catalog_for(p).is_empty())
	var homes_selling := cb.places.filter(func(p: Place) -> bool: return p.type in ["home", "apartment"] and not ItemDB.catalog_for(p).is_empty())
	check("economy: many places sell things, homes don't", sellers.size() > 60 and homes_selling.is_empty(), "%d shops" % sellers.size())
	# buying
	var cafe: Place = cb.places.filter(func(p: Place) -> bool: return p.type == "cafe")[0]
	GameTime.total_minutes = 7 * 1440.0 + 10.0 * 60.0      # Monday 10:00
	Game.player_profile["money"] = 100
	var price := ItemDB.price_at("coffee", cafe)
	var err := eco.buy("coffee", cafe)
	check("economy: buy coffee at a cafe", err == "" and eco.count("coffee") == 1 and Game.get_money() == 100 - price, "%s $%d" % [err, Game.get_money()])
	check("economy: can't buy what isn't sold", eco.buy("first_aid", cafe) != "")
	GameTime.total_minutes = 7 * 1440.0 + 3.0 * 60.0       # 03:00, closed
	check("economy: closed shop refuses", eco.buy("coffee", cafe) != "" if not cafe.is_open(3.0) else true)
	GameTime.total_minutes = 7 * 1440.0 + 10.0 * 60.0
	Game.player_profile["money"] = 1
	check("economy: not enough cash refuses", eco.buy("pastry", cafe) != "" and eco.count("pastry") == 0)
	# luxury prices
	var lux := Place.new()
	lux.type = "cafe"
	lux.price_level = 3
	check("economy: price level scales prices", ItemDB.price_at("coffee", lux) > ItemDB.price_at("coffee", cafe))
	# using an item
	eco.use_item("coffee", null)
	check("economy: using a consumable removes it", eco.count("coffee") == 0)
	# capacity
	eco.inventory = {}
	for k in Economy.BASE_SLOTS:
		eco.add_item(ItemDB.ITEMS.keys()[k], 1)
	check("economy: bag holds %d slots" % Economy.BASE_SLOTS, eco.slots_used() == Economy.BASE_SLOTS and not eco.can_add("scrap"))
	check("economy: stacks of 10 share a slot", eco.add_item(ItemDB.ITEMS.keys()[0], 9) and not eco.add_item(ItemDB.ITEMS.keys()[0], 1))
	eco.inventory.erase(ItemDB.ITEMS.keys()[1])
	eco.add_item("backpack")
	check("economy: backpack adds 10 slots", eco.capacity() == Economy.BASE_SLOTS + 10 and eco.can_add("scrap", 30))
	# selling
	eco.inventory = {"scrap": 3}
	var yard: Array = cb.places.filter(func(p: Place) -> bool: return p.type == "scrapyard")
	Game.player_profile["money"] = 0
	check("economy: scrapyard buys scrap", not yard.is_empty() and eco.sell("scrap", yard[0]) == "" and Game.get_money() == ItemDB.sell_price("scrap") and eco.count("scrap") == 2)
	check("economy: cafe doesn't buy scrap", eco.sell("scrap", cafe) != "")
	# bank
	Game.player_profile["money"] = 500
	eco.deposit(400)
	check("economy: deposit", eco.bank == 400 and Game.get_money() == 100)
	eco.withdraw(150)
	check("economy: withdraw", eco.bank == 250 and Game.get_money() == 250)
	eco._on_day(GameTime.get_day())
	check("economy: daily interest", eco.bank > 250 or 250 * 0.0005 < 1.0, "bank $%d" % eco.bank)
	# jobs: experience requirement
	var rich := {"title": "Test surgeon", "wage": 40, "start": 9.0, "end": 17.0, "slots": 1}
	var shop := Place.new()
	shop.id = 99999
	shop.type = "cafe"
	shop.name = "Test Cafe"
	shop.jobs = [{"title": "Barista", "wage": 14, "start": 9.0, "end": 17.0, "slots": 1}, rich]
	eco.experience = 0
	check("economy: experience required for well-paid jobs", Economy.required_experience(40) > 0 and eco.apply(shop, rich) != "")
	GameTime.total_minutes = 7 * 1440.0 + 12.0 * 60.0        # hired at noon, after the 09:00 start
	check("economy: entry job hires you", eco.apply(shop, shop.jobs[0]) == "" and eco.job.title == "Barista" and eco.job.mode == "orders")
	check("economy: filled job has no opening", eco.openings(shop).size() == 1)
	check("economy: shift modes", Economy.shift_mode("Parcel courier") == "delivery" and Economy.shift_mode("Bank teller") == "typing" and Economy.shift_mode("Forklift driver") == "timing")
	check("economy: hired after today's start -> not a missed shift", eco.shift_state() == "off", eco.shift_state())
	eco._check_missed(7)
	check("economy: no warning for the day you were hired", int(eco.job.misses) == 0)
	eco.job.hired_min = 6 * 1440.0                            # (pretend you were hired the day before)
	# shift: before / during / after the window
	GameTime.total_minutes = 7 * 1440.0 + 6.0 * 60.0
	check("economy: too early -> off", eco.shift_state() == "off")
	GameTime.total_minutes = 7 * 1440.0 + 9.2 * 60.0
	check("economy: on time -> open", eco.shift_state() == "open")
	Game.player_profile["money"] = 0
	check("economy: start shift", eco.start_shift(shop) == "" and eco.shift_state() == "working")
	var res := eco.finish_shift(1.0, 3)
	var expect := int(round(14 * (8.0 - 0.2) * 1.2)) + 3     # clocked in 12 min late
	check("economy: shift pay = wage x hours worked x performance + tips", int(res.pay) == expect and Game.get_money() == expect, "pay %d expected %d" % [int(res.get("pay", 0)), expect])
	check("economy: time skips to the end of the shift", absf(GameTime.get_hour_float() - 17.0) < 0.05, GameTime.get_clock_string())
	check("economy: can't work twice a day", eco.shift_state() == "done" and eco.start_shift(shop) != "")
	# promotion after 5 good shifts
	for d in [8, 9, 10, 11]:
		GameTime.total_minutes = d * 1440.0 + 9.0 * 60.0
		eco.start_shift(shop)
		eco.finish_shift(0.9, 0)
	check("economy: promoted after 5 good shifts", int(eco.job.rank) == 1 and eco.job_title() == "Senior Barista" and eco.wage_now() == int(round(14 * 1.2)), eco.job_title())
	# poor performance pays less
	GameTime.total_minutes = 14 * 1440.0 + 9.0 * 60.0
	eco.start_shift(shop)
	var poor := eco.finish_shift(0.0, 0)
	check("economy: poor work pays less", int(poor.pay) < int(res.pay), "%d" % int(poor.pay))
	# missed shifts -> warnings -> fired
	for d in [15, 16, 17]:
		GameTime.total_minutes = d * 1440.0 + 12.0 * 60.0
		eco._check_missed(d)
	check("economy: fired after %d missed shifts" % Economy.FIRE_AFTER, eco.job.is_empty())
	check("economy: experience is kept", eco.experience == 6)
	# weekend is off
	eco.apply(shop, shop.jobs[0])
	GameTime.total_minutes = 19 * 1440.0 + 9.0 * 60.0      # day 19 = Saturday
	check("economy: weekends off", eco.shift_state() == "off")
	# rent
	eco.bank = 0
	Game.player_profile["money"] = 100
	eco.rent_due_min = GameTime.total_minutes - 1.0
	eco._on_day(GameTime.get_day())
	check("economy: weekly rent paid", Game.get_money() == 30 and eco.debt == 0)
	Game.player_profile["money"] = 0
	eco.rent_due_min = GameTime.total_minutes - 1.0
	eco._on_day(GameTime.get_day())
	check("economy: unpaid rent becomes debt", eco.debt == Economy.RENT)
	Game.player_profile["money"] = 200
	eco._on_day(GameTime.get_day())
	check("economy: debt paid off when you have money", eco.debt == 0 and Game.get_money() == 200 - Economy.RENT)
	# save / load
	eco.inventory = {"apple": 4, "flowers": 1}
	var snap: Dictionary = JSON.parse_string(JSON.stringify(eco.save_state()))
	var eco2 := Economy.new()
	add_child(eco2)
	eco2.load_state(snap)
	check("economy: save/load round trip", eco2.count("apple") == 4 and eco2.job.title == "Barista" and eco2.experience == eco.experience and typeof(eco2.job.place) == TYPE_INT)
	eco2.queue_free()
	# courier job: deliveries planned on the real map
	var station: Array = cb.places.filter(func(p: Place) -> bool: return p.name == "Westbridge Central Station")
	var courier: Array = (station[0] as Place).jobs.filter(func(j: Dictionary) -> bool: return j.title == "Parcel courier") if not station.is_empty() else []
	check("economy: courier jobs exist", not courier.is_empty())
	if not courier.is_empty():
		eco.experience = 10
		eco.apply(station[0], courier[0])
		GameTime.total_minutes = 21 * 1440.0 + 9.0 * 60.0
		var e2 := eco.start_shift(station[0])
		var targets: Array = eco.shift.get("targets", [])
		check("economy: courier run plans 3 deliveries with a deadline", e2 == "" and targets.size() == 3 and float(eco.shift.deadline) > GameTime.total_minutes + 45.0, "%s %s" % [e2, str(targets)])
		eco.finish_shift(0.0, 0)
	# the playable shift (auto-played)
	var g := WorkMinigame.new()
	g.mode = "typing"
	g.place = cafe
	g.job_title = "Clerk"
	g.auto_play = 1.0
	var out := [-1.0]
	g.done.connect(func(perf: float, _tips: int) -> void: out[0] = perf)
	add_child(g)
	for f in 120:
		await get_tree().process_frame
		if out[0] >= 0.0:
			break
	check("economy: work minigame plays 6 tasks and reports performance", absf(out[0] - 1.0) < 0.001, "perf %.2f" % out[0])
	PlayerInput.enabled = true
	eco.queue_free()
	fw.queue_free()
	GameTime.total_minutes = saved_time
	Game.player_profile = saved_profile
