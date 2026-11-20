class_name PlayerInput
extends RefCounted
## Unified input state. Touch controls write into it; keyboard/mouse are merged in
## `poll()`. Gameplay code only reads from here, so every control scheme behaves the same.

static var touch_move: Vector2 = Vector2.ZERO     ## virtual joystick (-1..1)
static var touch_look: Vector2 = Vector2.ZERO     ## accumulated drag pixels this frame
static var touch_sprint: bool = false
static var touch_block: bool = false
static var touch_crouch: bool = false
static var _touch_pressed: Dictionary = {}        ## one-shot buttons: jump, interact, attack, vehicle, pause

static var mouse_look: Vector2 = Vector2.ZERO
static var move: Vector2 = Vector2.ZERO
static var look: Vector2 = Vector2.ZERO
static var sprint: bool = false
static var walk: bool = false
static var block: bool = false
static var crouch: bool = false
static var enabled: bool = true


static func press(action: String) -> void:
	_touch_pressed[action] = true


static func poll() -> void:
	var kb := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	move = touch_move if touch_move.length() > kb.length() else kb.limit_length(1.0)
	look = touch_look + mouse_look
	touch_look = Vector2.ZERO
	mouse_look = Vector2.ZERO
	sprint = touch_sprint or Input.is_action_pressed("sprint")
	walk = Input.is_action_pressed("walk")
	block = touch_block or Input.is_action_pressed("block")
	if not enabled:
		move = Vector2.ZERO
		look = Vector2.ZERO
		sprint = false
		block = false


## True once per press (keyboard or touch button).
static func just_pressed(action: String) -> bool:
	if not enabled:
		_touch_pressed.erase(action)
		return false
	var t: bool = _touch_pressed.get(action, false)
	_touch_pressed.erase(action)
	return t or Input.is_action_just_pressed(action)


static func clear() -> void:
	_touch_pressed.clear()
	touch_move = Vector2.ZERO
	touch_look = Vector2.ZERO
	touch_sprint = false
	touch_block = false
