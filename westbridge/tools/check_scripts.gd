extends Node
## Loads every .gd file in the project so the GDScript compiler reports all errors.
## Usage: godot --headless --path . res://tools/check_scripts.tscn

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
	var files: Array = []
	_scan("res://", files)
	var failed := 0
	for f in files:
		if String(f).ends_with("check_scripts.gd"):
			continue
		var res: Resource = load(f)
		var ok := false
		if res is GDScript:
			ok = (res as GDScript).can_instantiate()
		if not ok:
			failed += 1
			print("FAILED: ", f)
	print("CHECKED %d scripts, %d failed" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _scan(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_scan(dir.path_join(sub), out)
