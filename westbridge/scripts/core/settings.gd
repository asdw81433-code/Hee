extends Node
## Persistent player settings (graphics, controls, audio, camera).
## Stored in user://settings.cfg, applied immediately when changed.

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

var values: Dictionary = {
	"graphics_quality": Quality.MEDIUM,
	"fps_cap": 60,
	"render_scale": 1.0,
	"view_distance": 220.0,
	"shadows": true,
	"show_fps": true,
	"cam_sensitivity": 1.0,
	"cam_invert_y": false,
	"cam_distance": 4.2,
	"master_volume": 0.9,
	"music_volume": 0.6,
	"sfx_volume": 0.9,
	"ambient_volume": 0.7,
	"touch_controls": "auto",   # auto | on | off
	"controls_opacity": 0.75,
	"controls_scale": 1.0,
	"physics_debug": false,
	"character_assets": true,   # Blender-made character meshes (false = procedural fallback)
}

## Per-button layout overrides: { "jump": {"anchor": Vector2(0.9, 0.8), "scale": 1.0}, ... }
var control_layout: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant, apply_now: bool = true) -> void:
	values[key] = value
	if apply_now:
		apply()
		save_settings()


## Graphics preset presets change several values at once.
func apply_quality_preset(q: int) -> void:
	values["graphics_quality"] = q
	match q:
		Quality.LOW:
			values["render_scale"] = 0.7
			values["view_distance"] = 150.0
			values["shadows"] = false
			values["fps_cap"] = 30
		Quality.MEDIUM:
			values["render_scale"] = 0.85
			values["view_distance"] = 220.0
			values["shadows"] = true
			values["fps_cap"] = 60
		Quality.HIGH:
			values["render_scale"] = 1.0
			values["view_distance"] = 320.0
			values["shadows"] = true
			values["fps_cap"] = 60
	apply()
	save_settings()


func apply() -> void:
	Engine.max_fps = int(values["fps_cap"])
	# Low preset halves physics cost on weak phones.
	Engine.physics_ticks_per_second = 30 if int(values["graphics_quality"]) == Quality.LOW else 60
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(float(values["render_scale"]), 0.5, 1.0)
		vp.msaa_3d = Viewport.MSAA_DISABLED if int(values["graphics_quality"]) == Quality.LOW else Viewport.MSAA_2X
	_apply_audio()
	if is_inside_tree():
		EventBus.settings_applied.emit()


func _apply_audio() -> void:
	_set_bus_volume("Master", float(values["master_volume"]))
	_set_bus_volume("Music", float(values["music_volume"]))
	_set_bus_volume("SFX", float(values["sfx_volume"]))
	_set_bus_volume("Ambient", float(values["ambient_volume"]))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func touch_controls_enabled() -> bool:
	match String(values["touch_controls"]):
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values.keys():
		cfg.set_value("settings", k, values[k])
	cfg.set_value("controls", "layout", control_layout)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in values.keys():
		if cfg.has_section_key("settings", k):
			values[k] = cfg.get_value("settings", k)
	var layout: Variant = cfg.get_value("controls", "layout", {})
	if layout is Dictionary:
		control_layout = layout


func reset_control_layout() -> void:
	control_layout = {}
	save_settings()
	EventBus.controls_layout_changed.emit()
