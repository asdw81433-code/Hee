extends Node
## Game-wide state: player profile, scene flow, input map, pending save data.

const WORLD_SCENE := "res://scenes/game_world.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"
const PHYSICS_LAB_SCENE := "res://scenes/physics_lab.tscn"

## Player identity + wallet. Appearance is stored as a CharacterAppearance dictionary.
var player_profile: Dictionary = {
	"name": "Alex",
	"appearance": {},
	"money": 250,
}

var current_world: Node = null
var pending_sections: Dictionary = {}
var current_slot: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input_map()
	_setup_screenshot_tool()


## Testing aid: `-- shots=2,5.5 shotname=city` saves screenshots at those times
## (seconds of simulated physics time, so slow software rendering doesn't skew them)
## into user://shots/ and quits after the last one.
var _shot_times: Array = []
var _shot_name := "shot"
var _shot_clock := 0.0
var _shot_index := 0


func _setup_screenshot_tool() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			for t in a.substr(6).split(","):
				_shot_times.append(float(t))
		elif a.begins_with("shotname="):
			_shot_name = a.substr(9)
		elif a.begins_with("quit_after="):
			get_tree().create_timer(float(a.substr(11)), true, true).timeout.connect(func() -> void: get_tree().quit())
	if not _shot_times.is_empty():
		DirAccess.make_dir_recursive_absolute("user://shots")


func _physics_process(delta: float) -> void:
	if _shot_index >= _shot_times.size():
		return
	_shot_clock += delta
	if _shot_clock >= float(_shot_times[_shot_index]):
		var idx := _shot_index
		_shot_index += 1
		var last := _shot_index >= _shot_times.size()
		await RenderingServer.frame_post_draw
		var path := "user://shots/%s_%d.png" % [_shot_name, idx]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
		if last:
			get_tree().quit()


# ------------------------------------------------------------------ input map
func _setup_input_map() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("walk", [KEY_ALT, KEY_CTRL])
	_add_action("jump", [KEY_SPACE])
	_add_action("interact", [KEY_E])
	_add_action("attack", [KEY_J], [MOUSE_BUTTON_LEFT])
	_add_action("block", [KEY_K], [MOUSE_BUTTON_RIGHT])
	_add_action("vehicle", [KEY_F])
	_add_action("crouch", [KEY_C])
	_add_action("pause", [KEY_ESCAPE, KEY_P])
	_add_action("toggle_debug", [KEY_F3])
	_add_action("quicksave", [KEY_F5])
	_add_action("quickload", [KEY_F9])
	_add_action("inspect", [KEY_TAB])


func _add_action(action: String, keys: Array, mouse_buttons: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in mouse_buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


# ------------------------------------------------------------------ money
func get_money() -> int:
	return int(player_profile.get("money", 0))


func add_money(amount: int, reason: String = "") -> void:
	player_profile["money"] = get_money() + amount
	EventBus.money_changed.emit(get_money(), amount, reason)


## Returns false (and changes nothing) when the player can't afford it.
func spend_money(amount: int, reason: String = "") -> bool:
	if amount > get_money():
		EventBus.toast.emit("Not enough money ($%d needed)" % amount)
		return false
	player_profile["money"] = get_money() - amount
	EventBus.money_changed.emit(get_money(), -amount, reason)
	return true


# ------------------------------------------------------------------ flow
func start_new_game(appearance: Dictionary, player_name: String) -> void:
	player_profile = {"name": player_name, "appearance": appearance, "money": 250}
	pending_sections = {}
	GameTime.load_state({"total_minutes": 8.0 * 60.0 + 30.0})
	_go_to_world()


func continue_game(slot: int) -> bool:
	var env := SaveSystem.read_slot(slot)
	if env.is_empty():
		EventBus.toast.emit("No save found in slot %d" % (slot + 1))
		return false
	current_slot = slot
	pending_sections = env["sections"]
	if pending_sections.has("game"):
		load_state(pending_sections["game"])
	if pending_sections.has("time"):
		GameTime.load_state(pending_sections["time"])
	_go_to_world()
	return true


func _go_to_world() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


## Called by the world once all savable nodes exist.
func on_world_ready(world: Node) -> void:
	current_world = world
	if not pending_sections.is_empty():
		SaveSystem.apply_sections(pending_sections)
		pending_sections = {}
	GameTime.running = true


func return_to_menu() -> void:
	GameTime.running = false
	current_world = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func open_physics_lab() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(PHYSICS_LAB_SCENE)


func open_character_creator() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(CREATOR_SCENE)


func save_state() -> Dictionary:
	return {"profile": player_profile.duplicate(true)}


func load_state(d: Dictionary) -> void:
	if d.has("profile"):
		player_profile = d["profile"]
