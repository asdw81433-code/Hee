extends Node
## JSON save system with atomic writes, checksum validation and rotating backups.
##
## Layout per slot N:
##   user://saves/slot_N.json        <- current
##   user://saves/slot_N.bak1.json   <- previous
##   user://saves/slot_N.bak2.json   <- the one before
## Writing goes to slot_N.tmp first, is re-read and verified, then rotated in.
## Loading falls back to the backups when the main file is missing or corrupted.

const SAVE_DIR := "user://saves"
const FORMAT_VERSION := 2
const MAX_SLOTS := 4

## Nodes in this group must implement: save_key() -> String, save_state() -> Dictionary,
## load_state(data: Dictionary) -> void
const SAVABLE_GROUP := &"savable"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func slot_path(slot: int, suffix: String = "") -> String:
	return "%s/slot_%d%s.json" % [SAVE_DIR, slot, suffix]


## Collects data from every savable node + global singletons.
func collect_state() -> Dictionary:
	var sections: Dictionary = {}
	sections["time"] = GameTime.save_state()
	sections["game"] = Game.save_state()
	for node in get_tree().get_nodes_in_group(SAVABLE_GROUP):
		if node.has_method("save_state") and node.has_method("save_key"):
			sections[node.save_key()] = node.save_state()
	return sections


func save_game(slot: int, label: String = "") -> bool:
	var sections := collect_state()
	var ok := write_slot(slot, sections, label)
	EventBus.save_finished.emit(slot, ok, "Saved" if ok else "Save failed")
	return ok


## Low-level write used by save_game and the tests.
func write_slot(slot: int, sections: Dictionary, label: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var body := JSON.stringify(sections)
	var envelope := {
		"format": FORMAT_VERSION,
		"label": label,
		"timestamp": Time.get_datetime_string_from_system(),
		"game_clock": GameTime.get_clock_string(),
		"checksum": body.sha256_text(),
		"data": body,
	}
	var tmp := slot_path(slot, ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot open %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(envelope))
	f.close()
	# Verify the temp file before replacing anything.
	if _read_envelope(tmp).is_empty():
		push_error("SaveSystem: verification of temp save failed")
		return false
	_rotate_backups(slot)
	var err := DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		push_error("SaveSystem: rename failed (%s)" % error_string(err))
		return false
	return true


func _rotate_backups(slot: int) -> void:
	var main := slot_path(slot)
	var b1 := slot_path(slot, ".bak1")
	var b2 := slot_path(slot, ".bak2")
	if FileAccess.file_exists(b1):
		if FileAccess.file_exists(b2):
			DirAccess.remove_absolute(b2)
		DirAccess.rename_absolute(b1, b2)
	if FileAccess.file_exists(main):
		DirAccess.rename_absolute(main, b1)


## Returns {} when the file is missing or invalid.
func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("SaveSystem: %s is not valid JSON" % path)
		return {}
	var parsed: Dictionary = json.data
	var env: Dictionary = parsed
	if not env.has("data") or not env.has("checksum"):
		return {}
	var body := String(env["data"])
	if body.sha256_text() != String(env["checksum"]):
		push_warning("SaveSystem: checksum mismatch in %s" % path)
		return {}
	var json2 := JSON.new()
	if json2.parse(body) != OK or not (json2.data is Dictionary):
		return {}
	var data: Dictionary = json2.data
	env["sections"] = data
	return env


## Reads a slot, trying backups. Returns {} when nothing usable exists.
func read_slot(slot: int) -> Dictionary:
	for suffix in ["", ".bak1", ".bak2"]:
		var env := _read_envelope(slot_path(slot, suffix))
		if not env.is_empty():
			if suffix != "":
				push_warning("SaveSystem: slot %d restored from backup %s" % [slot, suffix])
			env["restored_from"] = suffix
			return env
	return {}


func slot_info(slot: int) -> Dictionary:
	var env := read_slot(slot)
	if env.is_empty():
		return {}
	return {"label": env.get("label", ""), "timestamp": env.get("timestamp", ""),
		"game_clock": env.get("game_clock", ""), "restored_from": env.get("restored_from", "")}


func has_any_save() -> bool:
	for i in MAX_SLOTS:
		if not slot_info(i).is_empty():
			return true
	return false


func latest_slot() -> int:
	var best := -1
	var best_ts := ""
	for i in MAX_SLOTS:
		var info := slot_info(i)
		if info.is_empty():
			continue
		if String(info["timestamp"]) > best_ts:
			best_ts = String(info["timestamp"])
			best = i
	return best


## Applies loaded sections to singletons and savable nodes currently in the tree.
func apply_sections(sections: Dictionary) -> void:
	if sections.has("time"):
		GameTime.load_state(sections["time"])
	for node in get_tree().get_nodes_in_group(SAVABLE_GROUP):
		if node.has_method("load_state") and node.has_method("save_key"):
			var key: String = node.save_key()
			if sections.has(key):
				node.load_state(sections[key])


func delete_slot(slot: int) -> void:
	for suffix in ["", ".bak1", ".bak2", ".tmp"]:
		var p := slot_path(slot, suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
