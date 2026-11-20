class_name TouchControls
extends Control
## Mobile on-screen controls drawn and hit-tested by one Control (cheap + true multitouch):
##   left half  : floating virtual joystick
##   right half : drag to look
##   buttons    : sprint (toggle), jump, interact, attack, block (hold), crouch, vehicle, pause
## Layout can be edited in-game (drag buttons) and is saved in Settings.control_layout.

signal pause_requested

const DEFAULTS := {
	"attack": {"pos": Vector2(0.905, 0.76), "r": 54.0, "label": "PUNCH", "kind": "tap"},
	"jump": {"pos": Vector2(0.80, 0.87), "r": 48.0, "label": "JUMP", "kind": "tap"},
	"block": {"pos": Vector2(0.935, 0.55), "r": 44.0, "label": "BLOCK", "kind": "hold"},
	"interact": {"pos": Vector2(0.785, 0.64), "r": 48.0, "label": "USE", "kind": "tap"},
	"sprint": {"pos": Vector2(0.685, 0.86), "r": 44.0, "label": "RUN", "kind": "toggle"},
	"crouch": {"pos": Vector2(0.675, 0.69), "r": 38.0, "label": "CROUCH", "kind": "tap"},
	"vehicle": {"pos": Vector2(0.935, 0.36), "r": 40.0, "label": "CAR", "kind": "tap"},
	"pause": {"pos": Vector2(0.965, 0.07), "r": 30.0, "label": "II", "kind": "tap"},
}

var editing: bool = false
var interact_text: String = ""
var interact_available: bool = false
var _buttons: Dictionary = {}           ## id -> {pos(px), r, label, kind}
var _touch_owner: Dictionary = {}       ## touch index -> "joy" | "look" | button id | "edit:<id>"
var _joy_center: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _joy_active: bool = false
var _pressed: Dictionary = {}
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	EventBus.interaction_prompt_changed.connect(func(t: String, ok: bool) -> void:
		interact_text = t
		interact_available = ok
		queue_redraw())
	EventBus.controls_layout_changed.connect(_layout)
	EventBus.settings_applied.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	var scale := float(Settings.get_value("controls_scale", 1.0))
	for id in DEFAULTS.keys():
		var d: Dictionary = DEFAULTS[id]
		var o: Dictionary = Settings.control_layout.get(id, {})
		var p: Vector2 = d["pos"]
		if o.has("x"):
			p = Vector2(float(o["x"]), float(o["y"]))
		var s: float = float(o.get("s", 1.0))
		_buttons[id] = {"pos": p * vs, "r": float(d["r"]) * scale * s, "label": d["label"], "kind": d["kind"]}
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_down(t.index, t.position)
		else:
			_on_up(t.index, t.position)
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		_on_drag(dr.index, dr.position, dr.relative)


func _hit_button(p: Vector2) -> String:
	for id in _buttons.keys():
		var b: Dictionary = _buttons[id]
		if p.distance_to(b["pos"]) <= float(b["r"]) * 1.15:
			return id
	return ""


func _on_down(idx: int, p: Vector2) -> void:
	var vs := get_viewport_rect().size
	var id := _hit_button(p)
	if editing:
		if id != "":
			_touch_owner[idx] = "edit:" + id
		return
	if id != "":
		_touch_owner[idx] = id
		_press_button(id, true)
		get_viewport().set_input_as_handled()
		return
	if p.x < vs.x * 0.42 and p.y > vs.y * 0.25:
		_touch_owner[idx] = "joy"
		_joy_center = p
		_joy_pos = p
		_joy_active = true
	elif p.x >= vs.x * 0.42:
		_touch_owner[idx] = "look"
	queue_redraw()


func _on_up(idx: int, _p: Vector2) -> void:
	var owner: String = _touch_owner.get(idx, "")
	_touch_owner.erase(idx)
	if owner == "joy":
		_joy_active = false
		PlayerInput.touch_move = Vector2.ZERO
	elif owner.begins_with("edit:"):
		_save_layout(owner.substr(5))
	elif owner != "" and owner != "look":
		_press_button(owner, false)
	queue_redraw()


func _on_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	var owner: String = _touch_owner.get(idx, "")
	if owner == "joy":
		var max_r := 90.0 * float(Settings.get_value("controls_scale", 1.0))
		var d := (p - _joy_center)
		if d.length() > max_r * 1.6:
			_joy_center = p - d.normalized() * max_r * 1.6   # base follows the thumb
		_joy_pos = p
		var v := (p - _joy_center) / max_r
		PlayerInput.touch_move = v.limit_length(1.0)
		queue_redraw()
	elif owner == "look":
		PlayerInput.touch_look += rel * 1.6
	elif owner.begins_with("edit:"):
		var id := owner.substr(5)
		_buttons[id]["pos"] = p
		queue_redraw()


func _press_button(id: String, down: bool) -> void:
	var kind: String = _buttons[id]["kind"]
	_pressed[id] = down
	match kind:
		"tap":
			if down:
				if id == "pause":
					pause_requested.emit()
				else:
					PlayerInput.press(id)
		"hold":
			if id == "block":
				PlayerInput.touch_block = down
		"toggle":
			if down and id == "sprint":
				PlayerInput.touch_sprint = not PlayerInput.touch_sprint
	queue_redraw()


func _process(_delta: float) -> void:
	# Sprint toggle switches itself off when the player stops.
	if PlayerInput.touch_sprint and PlayerInput.touch_move.length() < 0.1 and not _joy_active:
		PlayerInput.touch_sprint = false
		queue_redraw()


func _save_layout(id: String) -> void:
	var vs := get_viewport_rect().size
	var p: Vector2 = _buttons[id]["pos"] / vs
	var o: Dictionary = Settings.control_layout.get(id, {})
	o["x"] = p.x
	o["y"] = p.y
	Settings.control_layout[id] = o
	Settings.save_settings()


func set_editing(on: bool) -> void:
	editing = on
	PlayerInput.clear()
	queue_redraw()


func _draw() -> void:
	var alpha := float(Settings.get_value("controls_opacity", 0.75))
	var base_col := Color(1, 1, 1, 0.14 * alpha * 1.4)
	var ring := Color(1, 1, 1, 0.55 * alpha)
	# Joystick
	var vs := get_viewport_rect().size
	var joy_c := _joy_center if _joy_active else Vector2(vs.x * 0.14, vs.y * 0.76)
	var joy_p := _joy_pos if _joy_active else joy_c
	var jr := 90.0 * float(Settings.get_value("controls_scale", 1.0))
	draw_circle(joy_c, jr, base_col)
	draw_arc(joy_c, jr, 0, TAU, 48, ring, 3.0, true)
	draw_circle(joy_c + (joy_p - joy_c).limit_length(jr), jr * 0.42, Color(1, 1, 1, 0.45 * alpha))
	# Buttons
	for id in _buttons.keys():
		var b: Dictionary = _buttons[id]
		var r: float = b["r"]
		var pos: Vector2 = b["pos"]
		var active: bool = _pressed.get(id, false)
		if id == "sprint":
			active = PlayerInput.touch_sprint
		if id == "block":
			active = PlayerInput.touch_block
		var fill := Color(UIKit.ACCENT, 0.75 * alpha) if active else Color(0.08, 0.1, 0.13, 0.45 * alpha)
		if id == "interact" and not interact_available and not editing:
			fill = Color(0.08, 0.1, 0.13, 0.2 * alpha)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0, TAU, 40, ring if not editing else UIKit.ACCENT, 3.0 if not editing else 4.0, true)
		var text: String = b["label"]
		if id == "interact" and interact_available and interact_text != "":
			text = interact_text.split(" ")[0].to_upper()
		var fs := int(clampf(r * 0.36, 13.0, 22.0))
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, pos + Vector2(-tw * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.92 * maxf(alpha, 0.5)))
	if editing:
		draw_string(_font, Vector2(vs.x * 0.5 - 260, 60), "Drag buttons to move them", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UIKit.ACCENT)
