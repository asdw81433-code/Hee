class_name CharacterCreator
extends Control
## Detailed character creator with live 3D preview (drag to rotate, zoom face/body).
## Also used in-game as the wardrobe (clothing tabs only).

signal finished(appearance: CharacterAppearance)

var wardrobe_mode: bool = false
var edit_appearance: CharacterAppearance
var _model: CharacterModel
var _cam: Camera3D
var _pivot: Node3D
var _content: VBoxContainer
var _name_edit: LineEdit
var _rebuild_pending: bool = false
var _zoom_face: bool = false
var _current_tab: Callable
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	_rng.randomize()
	if edit_appearance == null:
		edit_appearance = CharacterAppearance.new().randomize_look(_rng, CharacterAppearance.Gender.MALE, 27)
		edit_appearance.hat = 0
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.15, 1.0 if not wardrobe_mode else 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 0)
	add_child(hb)
	hb.add_child(_build_preview())
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(640, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	var vb := VBoxContainer.new()
	right.add_child(vb)
	vb.add_child(UIKit.label("WARDROBE" if wardrobe_mode else "CREATE YOUR CHARACTER", 30, UIKit.ACCENT))
	var tabs := HFlowContainer.new()
	vb.add_child(tabs)
	var tab_list: Array = [["Clothes", _tab_clothes], ["Extras", _tab_accessories]]
	if not wardrobe_mode:
		tab_list = [["Body", _tab_body], ["Face", _tab_face], ["Hair", _tab_hair]] + tab_list
	for t in tab_list:
		tabs.add_child(UIKit.button(t[0], _show_tab.bind(t[1]), Vector2(140, 50)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	if not wardrobe_mode:
		_name_edit = LineEdit.new()
		_name_edit.text = "Alex"
		_name_edit.placeholder_text = "Name"
		_name_edit.custom_minimum_size = Vector2(180, 54)
		bottom.add_child(_name_edit)
		bottom.add_child(UIKit.button("Random", _randomize, Vector2(130, 54)))
		bottom.add_child(UIKit.button("Back", func() -> void: Game.return_to_menu(), Vector2(110, 54)))
		bottom.add_child(UIKit.button("Start", _finish, Vector2(150, 54)))
	else:
		bottom.add_child(UIKit.button("Cancel", func() -> void:
			finished.emit(null)
			queue_free(), Vector2(200, 54)))
		bottom.add_child(UIKit.button("Done", _finish, Vector2(200, 54)))
	_show_tab(tab_list[0][1])
	_rebuild()


func _build_preview() -> Control:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.24, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	sv.add_child(key)
	var floor_mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.25
	cyl.height = 0.1
	floor_mi.mesh = cyl
	floor_mi.position = Vector3(0, -0.05, 0)
	floor_mi.material_override = Geo.material(Color(0.3, 0.33, 0.38))
	sv.add_child(floor_mi)
	_pivot = Node3D.new()
	sv.add_child(_pivot)
	_model = CharacterModel.new()
	_pivot.add_child(_model)
	_cam = Camera3D.new()
	_cam.fov = 40
	sv.add_child(_cam)
	_update_camera()
	svc.gui_input.connect(_on_preview_input)
	return svc


func _on_preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_pivot.rotation.y += ev.relative.x * 0.01
	elif ev is InputEventScreenDrag:
		_pivot.rotation.y += ev.relative.x * 0.01
	elif ev is InputEventMouseButton and ev.pressed and ev.double_click:
		_zoom_face = not _zoom_face
		_update_camera()


func _update_camera() -> void:
	if _zoom_face:
		_cam.look_at_from_position(Vector3(0, 1.68, 1.3), Vector3(0, 1.66, 0))
	else:
		_cam.look_at_from_position(Vector3(0, 1.15, 4.4), Vector3(0, 0.95, 0))


func _process(delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild()
	if _model and _model.face:
		_model.face.set_expression({"happy": 0.35})


func _rebuild() -> void:
	_model.build(edit_appearance, 0)
	_model.animator.set_locomotion(0.0)


func _changed() -> void:
	_rebuild_pending = true


func _set_prop(prop: String, value: Variant) -> void:
	edit_appearance.set(prop, value)
	_changed()


func _show_tab(builder: Callable) -> void:
	_current_tab = builder
	for ch in _content.get_children():
		ch.queue_free()
	builder.call()


func _opt(title: String, prop: String, options: Array) -> void:
	_content.add_child(UIKit.option_row(title, options, int(edit_appearance.get(prop)), func(i: int) -> void: _set_prop(prop, i)))


func _slider(title: String, prop: String, a: float, b: float) -> void:
	_content.add_child(UIKit.slider_row(title, a, b, 0.01, float(edit_appearance.get(prop)), func(v: float) -> void: _set_prop(prop, v)))


func _colors(title: String, prop: String, palette: Array) -> void:
	_content.add_child(UIKit.color_row(title, palette, edit_appearance.get(prop), func(c: Color) -> void:
		_set_prop(prop, c)
		_show_tab.call_deferred(_current_tab)))


func _tab_body() -> void:
	_opt("Gender", "gender", ["Male", "Female", "Other"])
	_slider("Height", "height", 0.85, 1.15)
	_slider("Weight", "weight", 0.0, 1.0)
	_opt("Build", "build", ["Thin", "Normal", "Heavy", "Muscular"])
	_colors("Skin", "skin_color", CharacterAppearance.SKIN_TONES)
	_content.add_child(UIKit.slider_row("Age", 18, 80, 1, edit_appearance.age, func(v: float) -> void: _set_prop("age", int(v))))


func _tab_face() -> void:
	_content.add_child(UIKit.label("Double-click the preview to zoom on the face", 16, UIKit.MUTED))
	_slider("Head width", "head_width", 0.85, 1.2)
	_slider("Head height", "head_height", 0.9, 1.2)
	_slider("Jaw", "jaw_width", 0.65, 1.1)
	_opt("Eye shape", "eye_shape", CharacterAppearance.EYE_SHAPES)
	_slider("Eye size", "eye_size", 0.8, 1.35)
	_slider("Eye spacing", "eye_spacing", 0.85, 1.15)
	_colors("Eye color", "eye_color", CharacterAppearance.EYE_COLORS)
	_opt("Brows", "brow_style", CharacterAppearance.BROW_STYLES)
	_opt("Nose", "nose_shape", CharacterAppearance.NOSE_SHAPES)
	_slider("Nose size", "nose_size", 0.6, 1.6)
	_slider("Mouth width", "mouth_width", 0.7, 1.3)


func _tab_hair() -> void:
	_opt("Hair", "hair_style", CharacterAppearance.HAIR_STYLES)
	_colors("Hair color", "hair_color", CharacterAppearance.HAIR_COLORS)
	_colors("Brow color", "brow_color", CharacterAppearance.HAIR_COLORS)
	_opt("Beard", "beard_style", CharacterAppearance.BEARD_STYLES)
	_opt("Mustache", "mustache_style", CharacterAppearance.MUSTACHE_STYLES)


func _tab_clothes() -> void:
	_opt("Top", "top", CharacterAppearance.TOPS)
	_colors("Top color", "top_color", CharacterAppearance.CLOTH_COLORS)
	_opt("Jacket", "jacket", CharacterAppearance.JACKETS)
	_colors("Jacket color", "jacket_color", CharacterAppearance.CLOTH_COLORS)
	_opt("Pants", "pants", CharacterAppearance.PANTS)
	_colors("Pants color", "pants_color", CharacterAppearance.CLOTH_COLORS)
	_opt("Shoes", "shoes", CharacterAppearance.SHOES)
	_colors("Shoe color", "shoes_color", CharacterAppearance.CLOTH_COLORS)
	_colors("Socks", "socks_color", CharacterAppearance.CLOTH_COLORS)


func _tab_accessories() -> void:
	_opt("Hat", "hat", CharacterAppearance.HATS)
	_colors("Hat color", "hat_color", CharacterAppearance.CLOTH_COLORS)
	_opt("Glasses", "glasses", CharacterAppearance.GLASSES)
	_opt("Bag", "bag", CharacterAppearance.BAGS)
	_colors("Bag color", "bag_color", CharacterAppearance.CLOTH_COLORS)
	_opt("Accessory", "accessory", CharacterAppearance.ACCESSORIES)
	_content.add_child(UIKit.check_row("Watch", edit_appearance.watch, func(on: bool) -> void: _set_prop("watch", on)))
	_content.add_child(UIKit.check_row("Belt", edit_appearance.belt, func(on: bool) -> void: _set_prop("belt", on)))


func _randomize() -> void:
	edit_appearance = CharacterAppearance.new().randomize_look(_rng)
	_show_tab(_current_tab)
	_changed()


func _finish() -> void:
	if wardrobe_mode:
		finished.emit(edit_appearance)
		queue_free()
		return
	var pname := _name_edit.text.strip_edges()
	if pname == "":
		pname = "Alex"
	Game.start_new_game(edit_appearance.to_dict(), pname)
