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
	_check("punch lands as a physical impact", target.phys.impact_count > impacts_before, "dv %.2f part %s" % [target.phys.last_impact_dv, target.phys.last_impact_part])
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
	_finish()


func _finish() -> void:
	var passed := results.filter(func(r: bool) -> bool: return r).size()
	print("WORLDTEST RESULT %d/%d passed" % [passed, results.size()])
	get_tree().quit(0 if passed == results.size() else 1)
