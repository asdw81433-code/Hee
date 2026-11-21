class_name HUD
extends CanvasLayer
## In-game HUD: clock/weather/money, need bars, interaction prompt, toasts, FPS,
## touch controls and the physics debug overlay (F3).

var player: PlayerController
var touch: TouchControls
var debug_target: HumanoidBody
var root: Control
var _clock: Label
var _money: Label
var _bars: Dictionary = {}
var _prompt: Label
var _toast_box: VBoxContainer
var _fps: Label
var _debug: Label
var _debug_on: bool = false
var pause_menu: PauseMenu
var extra_info: Callable = Callable()


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_build_top_left()
	_prompt = UIKit.label("", 26)
	UIKit.anchor(_prompt, Control.PRESET_CENTER_BOTTOM, Vector2(-300, -170), Vector2(600, 40))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	root.add_child(_prompt)
	_toast_box = VBoxContainer.new()
	UIKit.anchor(_toast_box, Control.PRESET_CENTER_TOP, Vector2(-280, 90), Vector2(560, 10))
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)
	_fps = UIKit.label("", 18, UIKit.MUTED)
	UIKit.anchor(_fps, Control.PRESET_TOP_RIGHT, Vector2(-260, 8), Vector2(180, 30))
	root.add_child(_fps)
	_debug = UIKit.label("", 17)
	_debug.position = Vector2(16, 230)
	_debug.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug.add_theme_constant_override("outline_size", 5)
	_debug.visible = false
	root.add_child(_debug)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	root.add_child(touch)
	touch.visible = Settings.touch_controls_enabled()
	touch.pause_requested.connect(open_pause)
	pause_menu = PauseMenu.new()
	pause_menu.hud = self
	add_child(pause_menu)
	EventBus.interaction_prompt_changed.connect(_on_prompt)
	EventBus.toast.connect(show_toast)
	EventBus.money_changed.connect(func(_a: int, d: int, r: String) -> void:
		_update_money()
		if d != 0:
			show_toast(("+$%d" % d if d > 0 else "-$%d" % -d) + ("  " + r if r != "" else "")))
	EventBus.stats_changed.connect(_on_stats)
	EventBus.settings_applied.connect(func() -> void: touch.visible = Settings.touch_controls_enabled())
	EventBus.save_finished.connect(func(_s: int, ok: bool, msg: String) -> void: show_toast(msg if ok else "Save failed!"))
	_debug_on = bool(Settings.get_value("physics_debug", false))
	_debug.visible = _debug_on
	_update_money()


func _build_top_left() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.07, 0.1, 0.55), 14))
	panel.position = Vector2(14, 12)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var row := HBoxContainer.new()
	vb.add_child(row)
	_clock = UIKit.label("--:--", 24)
	row.add_child(_clock)
	_money = UIKit.label("$0", 24, Color(0.55, 0.95, 0.55))
	row.add_child(_money)
	for k in [["health", Color(0.9, 0.3, 0.3)], ["stamina", Color(0.95, 0.8, 0.3)], ["hunger", Color(0.9, 0.55, 0.25)], ["energy", Color(0.4, 0.7, 0.95)]]:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(230, 10)
		bar.show_percentage = false
		bar.max_value = 100
		var fill := StyleBoxFlat.new()
		fill.bg_color = k[1]
		fill.set_corner_radius_all(4)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.4)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		vb.add_child(bar)
		_bars[k[0]] = bar


func _on_prompt(text: String, available: bool) -> void:
	if touch.visible:
		_prompt.text = text if available else ""
	else:
		_prompt.text = ("[E] " + text) if available else ""


func _on_stats(s: Dictionary) -> void:
	for k in _bars.keys():
		_bars[k].value = float(s.get(k, 0.0))


func _update_money() -> void:
	_money.text = "  $%d" % Game.get_money()


## Small MAP button under the status panel (works with touch and mouse).
func add_map_button(map: MapScreen) -> void:
	var btn := UIKit.button("MAP", func() -> void: map.toggle(), Vector2(110, 52))
	btn.position = Vector2(14, 168)
	root.add_child(btn)


func show_toast(text: String) -> void:
	var l := UIKit.label(text, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_toast_box.add_child(l)
	if _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func open_pause() -> void:
	pause_menu.open()


func toggle_debug() -> void:
	_debug_on = not _debug_on
	_debug.visible = _debug_on
	Settings.set_value("physics_debug", _debug_on)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if pause_menu.is_open():
			pause_menu.close()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		toggle_debug()
	elif event is InputEventMouseButton and event.pressed and not touch.visible and not pause_menu.is_open():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	_clock.text = GameTime.get_clock_string()
	if extra_info.is_valid():
		_clock.text += "  " + str(extra_info.call())
	_fps.visible = bool(Settings.get_value("show_fps", true))
	if _fps.visible:
		_fps.text = "%d FPS  %d dc" % [Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	if _debug_on:
		var t := debug_target if debug_target else player
		if t and is_instance_valid(t):
			_debug.text = _format_debug(t)


func _format_debug(t: HumanoidBody) -> String:
	var d := t.phys.debug_info()
	var s := "PHYSICS DEBUG  (%s)\n" % t.name
	s += "State: %s   Recovery: %s\n" % [d.physics_state, d.recovery]
	s += "Balance: %.2f  COM off: %.3f m  capacity: %.1f\n" % [d.balance, d.com_offset, d.capacity]
	s += "Impact: %.1f N*s  dv %.2f m/s  part: %s  (%s)\n" % [d.impact_force, d.impact_dv, d.impact_part, d.severity]
	s += "Ragdoll: %s\n" % d.ragdoll
	s += "Animation: %s   hold: %s\n" % [d.animation, d.hold]
	s += "Joints: %s\n" % str(d.joints)
	s += "Injury %.2f  Stun %.2f  Speed %.1f m/s" % [d.injury, d.stun, t.ground_speed]
	return s
