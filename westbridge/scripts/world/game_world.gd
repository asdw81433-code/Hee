class_name GameWorld
extends Node3D
## Root of the playable world: builds the city, spawns the player, camera, HUD,
## environment and the NPC population, and wires them together.

var city: CityBuilder
var environment: EnvironmentController
var player: PlayerController
var cam: ThirdPersonCamera
var hud: HUD
var npcs: NPCManager
var _fade: ColorRect
var _loading: CanvasLayer
var map_screen: MapScreen
var economy: Economy
## Point the world streams around (the player; an aerial test camera's target).
var stream_focus: Node3D
var _stream_timer: float = 0.0


func _ready() -> void:
	add_to_group("game_world")
	_show_loading()
	# Let the loading screen render before the (synchronous) city build.
	await get_tree().process_frame
	await get_tree().process_frame
	_build()


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var l := UIKit.label("Loading Westbridge...", 40, UIKit.ACCENT)
	UIKit.anchor(l, Control.PRESET_CENTER, Vector2(-220, -30), Vector2(440, 60))
	_loading.add_child(l)


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	environment = EnvironmentController.new()
	environment.name = "Environment"
	add_child(environment)
	economy = Economy.new()
	economy.name = "Economy"
	economy.world = self
	add_child(economy)
	city = CityBuilder.new()
	city.game_world = self
	city.build(self, 1984)
	city.load_all_near(city.player_spawn)
	environment.lamp_positions = city.lamp_positions
	environment.interior_positions = city.interior_light_positions
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.global_position = city.player_spawn
	player.rotation.y = PI * 0.5
	stream_focus = player
	cam = ThirdPersonCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.set_target(player)
	player.camera_rig = cam
	environment.camera_ref = cam.camera
	npcs = NPCManager.new()
	npcs.name = "NPCs"
	add_child(npcs)
	npcs.setup(self, city)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.player = player
	hud.extra_info = func() -> String:
		var s := "%s · %s" % [CityMap.district_at(player.global_position), environment.weather.capitalize().replace("_", " ")]
		s += _job_line()
		if map_screen and map_screen.waypoint != null:
			var to: Vector3 = (map_screen.waypoint as Vector3) - player.global_position
			if Vector2(to.x, to.z).length() < 6.0:
				map_screen.set_waypoint(null)
				EventBus.toast.emit("Waypoint reached")
			else:
				var ang := fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
				var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
				s += "\n> %dm %s" % [int(Vector2(to.x, to.z).length()), dirs[int(round(ang / 45.0)) % 8]]
		return s
	map_screen = MapScreen.new()
	map_screen.name = "MapScreen"
	map_screen.world = self
	hud.add_map_button(map_screen)
	hud.add_bag_button(func() -> void: open_inventory())
	hud.root.add_child(map_screen)     # added last: covers the HUD while open
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(_fade)
	for a in OS.get_cmdline_user_args():
		# Testing aid: aerial=x,y,z,tx,ty,tz places a fixed camera.
		if a.begins_with("aerial="):
			var v := a.substr(7).split_floats(",")
			var ac := Camera3D.new()
			ac.far = 1500.0
			add_child(ac)
			ac.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
			ac.current = true
			# Stream around the camera itself (like the player), far areas use the skyline LOD.
			var focus := Node3D.new()
			add_child(focus)
			focus.global_position = Vector3(v[0], 0.0, v[2]).lerp(Vector3(v[3], 0.0, v[5]), 0.35)
			stream_focus = focus
			city.load_all_near(focus.global_position)
			environment.camera_ref = ac
		elif a.begins_with("hour="):
			GameTime.total_minutes = GameTime.get_day() * 1440.0 + float(a.substr(5)) * 60.0
			environment.set_weather(environment.weather, true)
		elif a == "demo_talk":
			get_tree().create_timer(5.0, true, true).timeout.connect(func() -> void:
				var near: NPCBody = null
				for b in npcs.body_of.values():
					if near == null or (b as NPCBody).global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
						near = b
				if near:
					player.global_position = near.global_position + (-near.global_basis.z) * 1.6
					player.rotation.y = near.rotation.y + PI
					near.interact(player)
					if "inspect" in OS.get_cmdline_user_args():
						get_tree().create_timer(1.0, true, true).timeout.connect(func() -> void:
							for c in hud.get_children():
								if c is NPCDialog:
									(c as NPCDialog)._inspect()))
		elif a.begins_with("weather="):
			environment.set_weather(a.substr(8), true)
		elif a.begins_with("spawn="):
			var sv := a.substr(6).split_floats(",")
			var sp := CityMap.block_center(int(sv[0]), int(sv[1])) + Vector3(sv[2], 0.0, sv[3])
			city.load_all_near(sp)
			sp.y = maxf(CityMap.ground_y(sp.x, sp.z), CityMap.road_height_at(sp.x, sp.z)) + 0.4
			player.global_position = sp
			player.rotation.y = deg_to_rad(sv[4]) if sv.size() > 4 else 0.0
			cam.set_target(player)
		elif a == "perf":
			var timer := Timer.new()
			timer.wait_time = 2.0
			timer.autostart = true
			add_child(timer)
			timer.timeout.connect(func() -> void:
				print("PERF fps %d | process %.2f ms | physics %.2f ms | draw calls %d | primitives %d | objects %d | npc bodies %d | npc ticks/s %d" % [
					Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					Performance.get_monitor(Performance.OBJECT_COUNT), npcs.stats.embodied, npcs.stats.ticks_per_sec]))
	_economy_demos()
	if "openmap" in OS.get_cmdline_user_args():
		map_screen.set_waypoint(city.places.filter(func(pl: Place) -> bool: return pl.type == "hospital")[0].entry_pos)
		map_screen.open()
	if "overview" in OS.get_cmdline_user_args():
		cam.pitch = -28.0
		cam.spring.spring_length = 26.0
		cam.yaw = deg_to_rad(-60.0)
	print("World built in %d ms: %d places, %d nav nodes, %d NPCs" % [Time.get_ticks_msec() - t0, city.places.size(), city.graph.node_count(), npcs.npcs.size()])
	Game.on_world_ready(self)
	_loading.queue_free()
	if "worldtest" in OS.get_cmdline_user_args():
		add_child(WorldTest.new())


func _process(delta: float) -> void:
	if city == null or stream_focus == null or not is_instance_valid(stream_focus):
		return
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.1
		city.update_streaming(stream_focus.global_position)


## Teleport helper (map screen, tests): loads the destination first.
func teleport_player(pos: Vector3) -> void:
	city.load_all_near(pos)
	player.global_position = Vector3(pos.x, maxf(CityMap.ground_y(pos.x, pos.z), CityMap.road_height_at(pos.x, pos.z)) + 0.4, pos.z)
	player.velocity = Vector3.ZERO


func player_home() -> Place:
	return city.player_home


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") and map_screen:
		map_screen.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and PlayerInput.enabled:
		open_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quicksave"):
		SaveSystem.save_game(0, "Quick save")
	elif event.is_action_pressed("quickload"):
		Game.continue_game(0)


## Fades to black, runs `during` (time skip), fades back.
func fade_sleep(during: Callable) -> void:
	PlayerInput.enabled = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.8)
	tw.tween_callback(during)
	tw.tween_interval(0.6)
	tw.tween_property(_fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: PlayerInput.enabled = true)


func open_wardrobe() -> void:
	var w := CharacterCreator.new()
	w.wardrobe_mode = true
	w.edit_appearance = player.appearance.duplicate()
	hud.add_child(w)
	get_tree().paused = true
	w.finished.connect(func(ap: CharacterAppearance) -> void:
		get_tree().paused = false
		if ap:
			player.rebuild_appearance(ap)
			Game.player_profile["appearance"] = ap.to_dict()
			EventBus.toast.emit("Outfit changed"))


# ------------------------------------------------------------------ economy (Priority 2)
## Shop / jobs / bank / hotel menu of a place (opened by its ServicePoint).
func open_place_menu(p: Place) -> PlaceMenu:
	var m := PlaceMenu.new()
	m.world = self
	m.place = p
	m.eco = economy
	hud.add_child(m)
	return m


func open_inventory() -> InventoryUI:
	for c in hud.get_children():
		if c is InventoryUI or c is PlaceMenu or c is WorkMinigame or c is NPCDialog:
			return null
	var inv := InventoryUI.new()
	inv.world = self
	inv.eco = economy
	hud.add_child(inv)
	return inv


## Called when a shift starts: the work itself (a playable minigame) or a delivery run.
func begin_work(p: Place) -> WorkMinigame:
	if economy.shift.is_empty():
		return null
	if String(economy.shift.mode) == "delivery":
		EventBus.toast.emit("Courier run: deliver %d parcels before %s" % [(economy.shift.targets as Array).size(), _clock_at(float(economy.shift.deadline))])
		return null
	var g := WorkMinigame.new()
	g.mode = String(economy.shift.mode)
	g.place = p
	g.job_title = economy.job_title()
	g.done.connect(func(perf: float, tips: int) -> void:
		fade_sleep(func() -> void: economy.finish_shift(perf, tips)))
	hud.add_child(g)
	return g


## Testing aids for screenshots: demo_shop=<place type>, demo_work=<orders|timing|typing>,
## demo_bag, demo_courier. Each stands the player at a real place and opens the real UI.
func _economy_demos() -> void:
	var args: Array = Array(OS.get_cmdline_user_args())
	var want_type := ""
	for a in args:
		if a.begins_with("demo_shop="):
			want_type = a.substr(10)
	var demo := want_type != "" or "demo_bag" in args or "demo_courier" in args or args.any(func(a: String) -> bool: return a.begins_with("demo_work="))
	if not demo:
		return
	Game.add_money(340 - Game.get_money(), "demo")
	var pick: Place = null
	for pl in city.places:
		var q := pl as Place
		var ok := q.type == want_type if want_type != "" else (q.name == "Westbridge Central Station" if "demo_courier" in args else q.type == "cafe")
		if ok and not q.enterable and (pick == null or q.entry_pos.distance_to(city.player_spawn) < pick.entry_pos.distance_to(city.player_spawn)):
			pick = q
	if pick == null:
		return
	# Stand in front of the door, facing it, camera over the shoulder.
	var away := Vector3(pick.entry_pos.x - pick.inside_pos.x, 0, pick.entry_pos.z - pick.inside_pos.z)
	if away.length() < 0.5:
		var links := city.graph.astar.get_point_connections(pick.entry_node)
		var nn: Vector3 = city.graph.pos(links[0]) if links.size() > 0 else pick.entry_pos + Vector3(0, 0, 3)
		away = Vector3(nn.x - pick.entry_pos.x, 0, nn.z - pick.entry_pos.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	teleport_player(pick.entry_pos + away * 2.2)
	player.rotation.y = atan2(away.x, away.z) + PI
	cam.yaw = player.rotation.y + PI
	cam.set_target(player)
	for k in ["coffee", "sandwich", "apple", "flowers", "lottery", "bandage"]:
		economy.add_item(k, 1 + int(k == "apple") * 3)
	get_tree().create_timer(4.0, true, true).timeout.connect(func() -> void:
		if "demo_bag" in args:
			economy.experience = 3
			economy.apply(pick, pick.jobs[0])
			open_inventory()
			return
		if "demo_courier" in args:
			economy.experience = 10
			var cj: Array = pick.jobs.filter(func(j: Dictionary) -> bool: return Economy.shift_mode(String(j.title)) == "delivery")
			economy.apply(pick, cj[0])
			GameTime.total_minutes = (GameTime.get_day() + (7 - GameTime.get_weekday()) % 7) * 1440.0 + float(cj[0].start) * 60.0
			economy.start_shift(pick)
			begin_work(pick)
			return
		for a in args:
			if a.begins_with("demo_work="):
				economy.experience = 12
				economy.apply(pick, pick.jobs[0])
				economy.job.mode = a.substr(10)
				GameTime.total_minutes = (GameTime.get_day() + (7 - GameTime.get_weekday()) % 7) * 1440.0 + float(pick.jobs[0].start) * 60.0
				economy.start_shift(pick)
				var g := begin_work(pick)
				if g and a.substr(10) == "orders":
					g.get_tree().create_timer(0.5, true, true).timeout.connect(func() -> void:
						var btns := g.find_children("*", "Button", true, false)
						if btns.size() > 2:
							(btns[1] as Button).pressed.emit())
				return
		open_place_menu(pick))


func _clock_at(total_min: float) -> String:
	var m := int(total_min) % 1440
	return "%02d:%02d" % [m / 60, m % 60]


## Short job reminder for the HUD info line.
func _job_line() -> String:
	if economy == null or economy.job.is_empty():
		return ""
	var j := economy.job
	if not economy.shift.is_empty():
		if String(economy.shift.mode) == "delivery":
			return "\nCourier run %d/%d · due %s" % [int(economy.shift.done), (economy.shift.targets as Array).size(), _clock_at(float(economy.shift.deadline))]
		return "\nAt work"
	match economy.shift_state():
		"open":
			return "\nWORK NOW: %s at %s" % [economy.job_title(), j.place_name]
		"off":
			return "\nWork %02d:00 · %s" % [int(j.start), j.place_name]
	return ""
