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
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var l := UIKit.label("Loading Westbridge...", 40, UIKit.ACCENT)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-220, -30)
	_loading.add_child(l)


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	environment = EnvironmentController.new()
	environment.name = "Environment"
	add_child(environment)
	city = CityBuilder.new()
	city.build(self, 1984)
	environment.lamp_positions = city.lamp_positions
	environment.interior_positions = city.interior_light_positions
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.global_position = city.player_spawn
	player.rotation.y = PI * 0.5
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
		return "%s · %s" % [CityMap.district_at(player.global_position), environment.weather.capitalize().replace("_", " ")]
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
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
			environment.camera_ref = ac
		elif a.begins_with("hour="):
			GameTime.total_minutes = GameTime.get_day() * 1440.0 + float(a.substr(5)) * 60.0
		elif a.begins_with("weather="):
			environment.set_weather(a.substr(8), true)
	if "overview" in OS.get_cmdline_user_args():
		cam.pitch = -28.0
		cam.spring.spring_length = 26.0
		cam.yaw = deg_to_rad(-60.0)
	print("World built in %d ms: %d places, %d nav nodes, %d NPCs" % [Time.get_ticks_msec() - t0, city.places.size(), city.graph.node_count(), npcs.npcs.size()])
	Game.on_world_ready(self)
	_loading.queue_free()


func _unhandled_input(event: InputEvent) -> void:
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
