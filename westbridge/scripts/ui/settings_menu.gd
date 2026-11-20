class_name SettingsMenu
extends Control
## Graphics / Controls / Audio settings. Used from the main menu and pause menu.

signal closed
signal edit_controls_requested

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vb := UIKit.modal(self, "Settings", 900)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	for t in [["Graphics", _graphics], ["Controls", _controls], ["Camera", _camera], ["Audio", _audio]]:
		tabs.add_child(UIKit.button(t[0], _show.bind(t[1]), Vector2(180, 52)))
	vb.add_child(UIKit.button("Done", func() -> void:
		Settings.save_settings()
		closed.emit()
		queue_free()))
	_show(_graphics)


func _show(builder: Callable) -> void:
	for c in _content.get_children():
		c.queue_free()
	builder.call()


func _graphics() -> void:
	_content.add_child(UIKit.option_row("Quality preset", ["Low", "Medium", "High"], int(Settings.get_value("graphics_quality")), func(i: int) -> void:
		Settings.apply_quality_preset(i)
		_show(_graphics)))
	_content.add_child(UIKit.option_row("FPS limit", ["30", "60"], 0 if int(Settings.get_value("fps_cap")) == 30 else 1, func(i: int) -> void:
		Settings.set_value("fps_cap", 30 if i == 0 else 60)))
	_content.add_child(UIKit.slider_row("Render scale", 0.5, 1.0, 0.05, float(Settings.get_value("render_scale")), func(v: float) -> void:
		Settings.set_value("render_scale", v)))
	_content.add_child(UIKit.slider_row("View distance", 120, 400, 10, float(Settings.get_value("view_distance")), func(v: float) -> void:
		Settings.set_value("view_distance", v)))
	_content.add_child(UIKit.check_row("Shadows", bool(Settings.get_value("shadows")), func(on: bool) -> void:
		Settings.set_value("shadows", on)))
	_content.add_child(UIKit.check_row("Show FPS", bool(Settings.get_value("show_fps")), func(on: bool) -> void:
		Settings.set_value("show_fps", on)))
	_content.add_child(UIKit.check_row("Physics debug overlay", bool(Settings.get_value("physics_debug")), func(on: bool) -> void:
		Settings.set_value("physics_debug", on)))


func _controls() -> void:
	_content.add_child(UIKit.option_row("Touch controls", ["Auto", "On", "Off"], ["auto", "on", "off"].find(String(Settings.get_value("touch_controls"))), func(i: int) -> void:
		Settings.set_value("touch_controls", ["auto", "on", "off"][i])))
	_content.add_child(UIKit.slider_row("Button size", 0.7, 1.5, 0.05, float(Settings.get_value("controls_scale")), func(v: float) -> void:
		Settings.set_value("controls_scale", v)))
	_content.add_child(UIKit.slider_row("Button opacity", 0.2, 1.0, 0.05, float(Settings.get_value("controls_opacity")), func(v: float) -> void:
		Settings.set_value("controls_opacity", v)))
	var row := HBoxContainer.new()
	row.add_child(UIKit.button("Edit button layout", func() -> void:
		edit_controls_requested.emit()
		closed.emit()
		queue_free(), Vector2(320, 56)))
	row.add_child(UIKit.button("Reset layout", func() -> void:
		Settings.reset_control_layout(), Vector2(260, 56)))
	_content.add_child(row)
	_content.add_child(UIKit.label("Keyboard: WASD move, Shift sprint, Alt walk, Space jump, E use,\nLMB/J punch, RMB/K block, C crouch, F3 physics debug, Esc pause", 18, UIKit.MUTED))


func _camera() -> void:
	_content.add_child(UIKit.slider_row("Sensitivity", 0.2, 3.0, 0.05, float(Settings.get_value("cam_sensitivity")), func(v: float) -> void:
		Settings.set_value("cam_sensitivity", v)))
	_content.add_child(UIKit.check_row("Invert Y", bool(Settings.get_value("cam_invert_y")), func(on: bool) -> void:
		Settings.set_value("cam_invert_y", on)))
	_content.add_child(UIKit.slider_row("Camera distance", 2.0, 8.0, 0.1, float(Settings.get_value("cam_distance")), func(v: float) -> void:
		Settings.set_value("cam_distance", v)))


func _audio() -> void:
	for k in [["Master", "master_volume"], ["Music", "music_volume"], ["Effects", "sfx_volume"], ["Ambient", "ambient_volume"]]:
		var key: String = k[1]
		_content.add_child(UIKit.slider_row(k[0], 0.0, 1.0, 0.05, float(Settings.get_value(key)), func(v: float) -> void:
			Settings.set_value(key, v)))
