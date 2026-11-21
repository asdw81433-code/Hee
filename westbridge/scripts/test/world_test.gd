class_name WorldTest
extends Node
## In-world integration test, started with `-- worldtest`:
## NPC bodies spawn and walk, punching an NPC triggers victim + witness reactions and
## memories, the player can talk to NPCs, sit, save, sleep (time skip) and the
## off-screen simulation catches up. Prints PASS/FAIL and quits.

var world: GameWorld
var results: Array = []


func _ready() -> void:
	world = get_parent() as GameWorld
	_run()


func _check(name: String, ok: bool, detail: String = "") -> void:
	results.append(ok)
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + detail if detail != "" else ""))


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func _run() -> void:
	while world.npcs == null or world.player == null:
		await get_tree().process_frame
	await _wait(4.0)
	var m := world.npcs
	var p := world.player
	_check("npc bodies spawned near the player", m.body_of.size() > 0, "%d embodied of %d" % [m.body_of.size(), m.npcs.size()])
	# Walk the player to the middle of town so plenty of people are around.
	p.global_position = CityMap.block_center(2, 1) + Vector3(-23.0, 0.3, 0.0)
	await _wait(4.0)
	var before := {}
	for id in m.body_of.keys():
		before[id] = m.body_of[id].global_position
	await _wait(3.0)
	var moved := 0
	for id in before.keys():
		if m.body_of.has(id) and m.body_of[id].global_position.distance_to(before[id]) > 1.0:
			moved += 1
	_check("embodied NPCs walk around", moved > 0, "%d moving" % moved)
	var acts := {}
	for n in m.npcs:
		acts[n.action] = acts.get(n.action, 0) + 1
	_check("population is busy with different activities", acts.size() >= 4, str(acts))
	# --- punch the nearest NPC ---
	var target: NPCBody = null
	var best := INF
	for b in m.body_of.values():
		var nb := b as NPCBody
		if nb.is_down() or nb.npc.reaction != "":
			continue
		var d := nb.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			target = nb
	if target == null:
		_check("found an NPC to test reactions", false)
		_finish()
		return
	var victim := target.npc
	target.npc.path = PackedVector3Array()
	target.npc.action_until = GameTime.total_minutes + 30.0
	var tpos := target.global_position
	var dir := (-target.global_basis.z).normalized()
	p.global_position = tpos + dir * 0.9 + Vector3(0, 0.05, 0)
	p.rotation.y = atan2(dir.x, dir.z)
	await _wait(0.4)
	# Interaction prompt should target the NPC.
	await _wait(0.3)
	_check("player can talk to the NPC in front", p.interactor.current == target, str(p.interactor.current))
	var impacts_before := target.phys.impact_count
	p.attack()
	await _wait(0.8)
	_check("punch lands as a physical impact", target.phys.impact_count > impacts_before, "dv %.2f part %s  (target %s at %s, player at %s, district %s)" % [target.phys.last_impact_dv, target.phys.last_impact_part, victim.action, str(target.global_position.snapped(Vector3.ONE * 0.1)), str(p.global_position.snapped(Vector3.ONE * 0.1)), CityMap.district_at(target.global_position)])
	_check("victim reacts (confront / flee / shout)", victim.reaction in ["confront", "flee", "shout"], "reaction=%s" % victim.reaction)
	var mem := victim.memory.about(NPCData.PLAYER_ID)
	_check("victim remembers being assaulted by the player", mem.any(func(e: Dictionary) -> bool: return e.event == "assaulted"))
	_check("victim's relationship with the player soured", float(victim.rel(NPCData.PLAYER_ID).anger) > 0.4 and float(victim.rel(NPCData.PLAYER_ID).friendship) < 0.0)
	var witnesses := 0
	var kinds := {}
	for b in m.body_of.values():
		var nb2 := b as NPCBody
		if nb2.npc and nb2.npc != victim and nb2.npc.reaction != "":
			witnesses += 1
			kinds[nb2.npc.reaction] = true
	print("      witnesses reacting: %d %s" % [witnesses, str(kinds.keys())])
	var saw := 0
	for n in m.npcs:
		if n != victim and n.memory.entries.any(func(e: Dictionary) -> bool: return e.event == "witnessed_assault"):
			saw += 1
	_check("only NPCs who could see it remember it", saw <= m.body_of.size(), "%d remember, %d embodied" % [saw, m.body_of.size()])
	await _wait(6.0)
	# --- save / sleep / fast forward ---
	var ok_save := SaveSystem.save_game(2, "worldtest")
	var env := SaveSystem.read_slot(2)
	_check("in-world save contains player, NPCs, time, weather", ok_save and env.sections.has("player") and env.sections.has("npcs") and env.sections.has("environment") and env.sections.npcs.npcs.size() == m.npcs.size())
	var t0 := GameTime.total_minutes
	GameTime.skip_to_hour(7.0)
	await _wait(0.5)
	var idle := 0
	for n in m.npcs:
		if n.action == "idle":
			idle += 1
	_check("time skip (sleep) -> simulation catches up", GameTime.total_minutes > t0 and idle == 0, "skipped %d min" % int(GameTime.total_minutes - t0))
	# --- load restores NPC memories ---
	var victim_id := victim.id
	m.load_state(env.sections.npcs)
	var restored: NPCData = m.npcs[victim_id]
	_check("load restores NPC memories & relationships", restored.memory.about(NPCData.PLAYER_ID).size() > 0 and float(restored.rel(NPCData.PLAYER_ID).anger) > 0.3)
	SaveSystem.delete_slot(2)
	# --- big world: teleport across town (streaming) and swim in the river ---
	world.teleport_player(CityMap.block_center(7, 2) + Vector3(-23.0, 0, 0))
	await _wait(1.5)
	world.city.update_streaming(p.global_position, 1e9)
	_check("teleport to Downtown streams the area in", world.city.is_loaded(Vector2i(7, 2)) and p.is_on_floor() and CityMap.district_at(p.global_position) == "Downtown",
		"%d cells loaded, y %.2f, %s" % [world.city.stats.loaded, p.global_position.y, CityMap.district_at(p.global_position)])
	var river := Vector3(CityMap.RIVER_X, 0, -29.0)   # open water between two bridges
	world.city.load_all_near(river)
	p.global_position = Vector3(river.x, 0.5, river.z)
	await _wait(3.0)
	var surface := CityMap.water_level_at(p.global_position.x, p.global_position.z)
	_check("falling into the river -> swimming at the surface", p.swimming and p.global_position.y > surface - 1.6 and p.global_position.y < surface, "y %.2f, water %.2f" % [p.global_position.y, surface])
	await _economy_test(world, p)
	_finish()


## Priority 2 in the real world: walk up to a shop door, open its menu, buy
## something, get hired, come back at shift time, play the shift, get paid.
func _economy_test(world: Node, p: PlayerController) -> void:
	var eco: Economy = world.economy
	# a weekday morning
	var d := GameTime.get_day() + 1
	while d % 7 >= 5:
		d += 1
	GameTime.total_minutes = d * 1440.0 + 10.0 * 60.0
	# a cafe / shop with an opening that needs no experience, close to home
	var home: Vector3 = world.city.player_spawn
	var best: Place = null
	var best_job: Dictionary = {}
	for pl in world.city.places:
		var q := pl as Place
		if ItemDB.catalog_for(q).is_empty() or not q.is_open(10.0) or q.enterable:
			continue
		for jd in eco.openings(q):
			if Economy.required_experience(int(jd.wage)) == 0 and Economy.shift_mode(String(jd.title)) == "orders" and float(jd.start) >= 6.0 and float(jd.start) <= 12.0:
				if best == null or q.entry_pos.distance_to(home) < best.entry_pos.distance_to(home):
					best = q
					best_job = jd
	_check("found a shop that is hiring", best != null, best.name if best else "")
	if best == null:
		return
	world.teleport_player(best.entry_pos + Vector3(0.5, 0, 0.5))
	await _wait(1.2)
	var sp: Node = p.interactor.current
	_check("shop door offers a service point", sp is ServicePoint and (sp as ServicePoint).place == best, "%s -> %s" % [best.name, str(sp)])
	Game.player_profile["money"] = 200
	p.interactor.interact()
	await _wait(0.3)
	var menu: PlaceMenu = null
	for c in world.hud.get_children():
		if c is PlaceMenu:
			menu = c
	_check("interact opens the place menu", menu != null)
	if menu == null:
		return
	# press the first "Buy" button like a player would
	var item: String = ItemDB.catalog_for(best)[0]
	var cash0 := Game.get_money()
	var buy_btn := _find_button(menu, "Buy")
	if buy_btn:
		buy_btn.pressed.emit()
	await _wait(0.2)
	_check("buying from the menu takes cash and fills the bag", eco.count(item) == 1 and Game.get_money() == cash0 - ItemDB.price_at(item, best), "%s x%d, $%d -> $%d" % [item, eco.count(item), cash0, Game.get_money()])
	# apply for the job
	menu._show("jobs")
	await _wait(0.2)
	var applied := false
	for row in menu._body.get_children():
		var l := row.get_child(0) as Label
		if l and l.text.begins_with(String(best_job.title) + "  -"):
			for b in row.get_children():
				if b is Button and (b as Button).text == "Apply" and not (b as Button).disabled:
					(b as Button).pressed.emit()
					applied = true
	await _wait(0.2)
	_check("apply in the menu -> hired", applied and not eco.job.is_empty() and int(eco.job.place) == best.id, eco.job_title())
	menu._close()
	await _wait(0.2)
	# inventory screen
	var inv: InventoryUI = world.open_inventory()
	await _wait(0.2)
	_check("bag screen lists the item", inv != null and _find_label(inv, ItemDB.item_name(item)) != null)
	if inv:
		inv._close()
	await _wait(0.2)
	if eco.job.is_empty():
		return
	# come back at shift time, clock in, play the shift
	var d2 := GameTime.get_day() + 1
	while d2 % 7 >= 5:
		d2 += 1
	GameTime.total_minutes = d2 * 1440.0 + float(eco.job.start) * 60.0 - 10.0
	await _wait(0.5)
	_check("shift is open at the start time", eco.shift_state() == "open", eco.shift_state())
	_check("prompt says Start shift", sp != null and is_instance_valid(sp) and String(sp.get_prompt(p)).begins_with("Start shift"), String(sp.get_prompt(p)) if is_instance_valid(sp) else "")
	p.interactor.interact()
	await _wait(0.3)
	menu = null
	for c in world.hud.get_children():
		if c is PlaceMenu:
			menu = c
	var start_btn := _find_button(menu, "Start shift") if menu else null
	_check("menu offers Start shift", start_btn != null and not start_btn.disabled)
	if start_btn == null:
		return
	var cash1 := Game.get_money()
	start_btn.pressed.emit()
	await _wait(0.3)
	var game: WorkMinigame = null
	for c in world.hud.get_children():
		if c is WorkMinigame:
			game = c
	_check("shift opens the work minigame", game != null and game.mode == "orders")
	if game == null:
		return
	game.auto_play = 0.85
	await _wait(6.0)
	_check("finishing the shift pays and gives experience", Game.get_money() > cash1 and eco.experience == 1 and eco.shift.is_empty(),
		"$%d -> $%d, %s" % [cash1, Game.get_money(), str(eco.history[0]) if not eco.history.is_empty() else "no result"])
	_check("clock jumps to the end of the shift", absf(GameTime.get_hour_float() - fmod(float(eco.job.end), 24.0)) < 0.3, GameTime.get_clock_string())


func _find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n
	return null


func _find_label(root: Node, prefix: String) -> Label:
	for n in root.find_children("*", "Label", true, false):
		if (n as Label).text.begins_with(prefix):
			return n
	return null


func _finish() -> void:
	var passed := results.filter(func(r: bool) -> bool: return r).size()
	print("WORLDTEST RESULT %d/%d passed" % [passed, results.size()])
	get_tree().quit(0 if passed == results.size() else 1)
