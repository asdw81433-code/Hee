extends Control
## Title screen: New game, Continue, Load, Settings, Physics Lab, Quit.
## A slowly orbiting 3D backdrop shows a few townspeople.

var _box: VBoxContainer
var _cam: Camera3D
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	GameTime.running = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.06, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 70)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.08, 0.1, 0.13, 0.86), 20))
	add_child(panel)
	_box = VBoxContainer.new()
	panel.add_child(_box)
	_box.add_child(UIKit.label("WESTBRIDGE", 64, UIKit.ACCENT))
	_box.add_child(UIKit.label("City Life Simulator", 24, UIKit.MUTED))
	var cont := UIKit.button("Continue", func() -> void:
		var s := SaveSystem.latest_slot()
		if s >= 0:
			Game.continue_game(s), Vector2(320, 60))
	cont.disabled = not SaveSystem.has_any_save()
	_box.add_child(cont)
	_box.add_child(UIKit.button("New game", Game.open_character_creator, Vector2(320, 60)))
	var load_b := UIKit.button("Load game", _load_page, Vector2(320, 60))
	load_b.disabled = not SaveSystem.has_any_save()
	_box.add_child(load_b)
	_box.add_child(UIKit.button("Settings", _settings, Vector2(320, 60)))
	_box.add_child(UIKit.button("Physics Lab (test arena)", Game.open_physics_lab, Vector2(320, 60)))
	if not OS.has_feature("mobile"):
		_box.add_child(UIKit.button("Quit", func() -> void: get_tree().quit(), Vector2(320, 60)))
	_box.add_child(UIKit.label("v0.2 — Phase 1 + 2 build", 16, UIKit.MUTED))


func _build_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	svc.add_child(sv)
	var root := Node3D.new()
	sv.add_child(root)
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.42, 0.65)
	sky_mat.sky_horizon_color = Color(0.95, 0.7, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.02
	env.fog_light_color = Color(0.9, 0.7, 0.55)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, -60, 0)
	sun.light_color = Color(1.0, 0.75, 0.5)
	sun.shadow_enabled = true
	root.add_child(sun)
	var b := GeoBatch.new()
	b.floor_quad(Vector3.ZERO, Vector2(200, 200), Color(0.4, 0.52, 0.3), GeoBatch.Kind.GRASS)
	b.floor_quad(Vector3(0, 0.01, 4), Vector2(200, 9), Color(0.25, 0.26, 0.28), GeoBatch.Kind.ASPHALT)
	b.floor_quad(Vector3(0, 0.02, 1.0), Vector2(200, 3), Color(0.68, 0.67, 0.64), GeoBatch.Kind.TILES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 7:
		BuildingKit.house(b, ColliderSet.new(), Transform3D(Basis.IDENTITY, Vector3(-30 + k * 11.0, 0, -9)), 8.0, 8.0, 1 + k % 2, CityBlocks.HOUSE_COLORS[k % 8], CityBlocks.ROOF_COLORS[k % 4], Color(0.95, 0.95, 0.92), rng)
	for k in 40:
		var t := PropsKit.pine_tree_mesh()
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = GeoBatch.material()
		mi.position = Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-40, -18))
		mi.scale = Vector3.ONE * rng.randf_range(0.9, 1.6)
		root.add_child(mi)
	root.add_child(b.to_instance("Street"))
	for k in 4:
		var m := CharacterModel.new()
		root.add_child(m)
		m.build(CharacterAppearance.new().randomize_look(rng))
		m.position = Vector3(-3 + k * 2.0, 0, 1.0 + (k % 2) * 0.5)
		m.rotation.y = rng.randf_range(-0.6, 0.6)
		m.animator.set_locomotion(0.0)
		m.face.set_expression({["happy", "angry", "sad", "surprise"][k]: 0.8})
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.look_at_from_position(Vector3(4, 1.7, 7.5), Vector3(0, 1.3, 0))


func _process(delta: float) -> void:
	_t += delta
	if _cam:
		var a := sin(_t * 0.1) * 0.35
		_cam.look_at_from_position(Vector3(4.0 + sin(a) * 3.0, 1.7, 7.5 + cos(a)), Vector3(0, 1.3, 0))


func _load_page() -> void:
	var vb := UIKit.modal(self, "Load game", 640)
	for i in SaveSystem.MAX_SLOTS:
		var info := SaveSystem.slot_info(i)
		var text := "Slot %d   " % (i + 1) + (("%s  (%s)" % [info.get("game_clock", ""), String(info.get("timestamp", "")).replace("T", " ")]) if not info.is_empty() else "— empty —")
		var bt := UIKit.button(text, func() -> void: Game.continue_game(i), Vector2(580, 56))
		bt.disabled = info.is_empty()
		vb.add_child(bt)
	vb.add_child(UIKit.button("Back", func() -> void: vb.get_meta("root").queue_free()))


func _settings() -> void:
	add_child(SettingsMenu.new())
