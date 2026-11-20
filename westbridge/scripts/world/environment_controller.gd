class_name EnvironmentController
extends Node3D
## Day/night cycle, weather (clear, cloudy, rain, heavy rain, fog), sky, sun/moon,
## fog, wet streets, rain particles and a small pool of street/interior lights that
## follows the camera (only a handful of real lights are ever active -> mobile friendly).

const WEATHERS := ["clear", "cloudy", "rain", "heavy_rain", "fog"]
const WEATHER_WEIGHTS := {"clear": 5.0, "cloudy": 3.0, "rain": 1.6, "heavy_rain": 0.6, "fog": 0.9}

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var rain: GPUParticles3D
var weather: String = "clear"
var _weather_blend: Dictionary = {"cloud": 0.0, "rain": 0.0, "fog": 0.0}
var _next_weather_minutes: float = 0.0
var _wetness: float = 0.0
var lamp_positions: Array = []
var interior_positions: Array = []
var _lights: Array[OmniLight3D] = []
var _indoor_lights: Array[OmniLight3D] = []
var _light_timer: float = 0.0
var camera_ref: Camera3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("savable")
	rng.randomize()
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.62, 0.6, 0.56)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.6
	add_child(sun)
	for k in 8:
		var l := OmniLight3D.new()
		l.omni_range = 13.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.82, 0.55)
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		add_child(l)
		_lights.append(l)
	for k in 3:
		var l2 := OmniLight3D.new()
		l2.omni_range = 9.0
		l2.light_energy = 0.0
		l2.light_color = Color(1.0, 0.95, 0.88)
		add_child(l2)
		_indoor_lights.append(l2)
	_build_rain()
	EventBus.settings_applied.connect(_apply_settings)
	_apply_settings()
	_next_weather_minutes = GameTime.total_minutes + rng.randf_range(120, 300)
	_update_sky(0.0, true)


func save_key() -> String:
	return "environment"


func save_state() -> Dictionary:
	return {"weather": weather, "next": _next_weather_minutes, "wet": _wetness}


func load_state(d: Dictionary) -> void:
	set_weather(String(d.get("weather", "clear")), true)
	_next_weather_minutes = float(d.get("next", GameTime.total_minutes + 120.0))
	_wetness = float(d.get("wet", 0.0))


func _apply_settings() -> void:
	sun.shadow_enabled = bool(Settings.get_value("shadows", true))
	var vd := float(Settings.get_value("view_distance", 220.0))
	env.fog_depth_begin = vd * 0.35
	env.fog_depth_end = vd + 120.0


func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 0.9
	rain.visibility_aabb = AABB(Vector3(-20, -12, -20), Vector3(40, 30, 40))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.5, 18)
	pm.direction = Vector3(0.08, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = mat
	rain.draw_pass_1 = quad
	rain.emitting = false
	add_child(rain)


func set_weather(w: String, instant: bool = false) -> void:
	if not w in WEATHERS:
		w = "clear"
	weather = w
	_next_weather_minutes = GameTime.total_minutes + rng.randf_range(150, 420)
	if instant:
		_weather_blend = _weather_target()
	EventBus.weather_changed.emit(StringName(w))


func is_raining() -> bool:
	return weather == "rain" or weather == "heavy_rain"


func _weather_target() -> Dictionary:
	match weather:
		"cloudy":
			return {"cloud": 0.65, "rain": 0.0, "fog": 0.15}
		"rain":
			return {"cloud": 0.85, "rain": 0.6, "fog": 0.3}
		"heavy_rain":
			return {"cloud": 1.0, "rain": 1.0, "fog": 0.45}
		"fog":
			return {"cloud": 0.5, "rain": 0.0, "fog": 1.0}
	return {"cloud": 0.0, "rain": 0.0, "fog": 0.0}


func _pick_next_weather() -> void:
	var total := 0.0
	for k in WEATHER_WEIGHTS.keys():
		total += WEATHER_WEIGHTS[k]
	var r := rng.randf() * total
	for k in WEATHER_WEIGHTS.keys():
		r -= WEATHER_WEIGHTS[k]
		if r <= 0.0:
			set_weather(k)
			break
	_next_weather_minutes = GameTime.total_minutes + rng.randf_range(150, 420)


func _process(delta: float) -> void:
	if GameTime.total_minutes >= _next_weather_minutes:
		_pick_next_weather()
	_update_sky(delta, false)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.4
		_update_lights()
	var cam := camera_ref if camera_ref else get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 9, 0) - cam.global_basis.z * 6.0


func _update_sky(delta: float, instant: bool) -> void:
	var target := _weather_target()
	var k := 1.0 if instant else 1.0 - exp(-delta * 0.15)
	for key in _weather_blend.keys():
		_weather_blend[key] = lerpf(_weather_blend[key], target[key], k)
	var cloud: float = _weather_blend.cloud
	var rainy: float = _weather_blend.rain
	var foggy: float = _weather_blend.fog
	var h := GameTime.get_hour_float()
	var night := GameTime.get_night_factor()
	# Sun path: rises 6:00 in the east, sets ~19:00 in the west.
	var day_t := clampf((h - 6.0) / 13.0, 0.0, 1.0)
	var elev := sin(day_t * PI) * 62.0
	var az := lerpf(-100.0, 100.0, day_t)
	if night > 0.5:
		elev = 38.0
		az = 20.0
	sun.rotation_degrees = Vector3(-maxf(elev, 6.0), az, 0)
	var dusk := clampf(1.0 - absf(elev - 8.0) / 18.0, 0.0, 1.0) * (1.0 - night)
	var sun_col := Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.62, 0.35), dusk)
	sun_col = sun_col.lerp(Color(0.55, 0.65, 0.95), night)
	sun.light_color = sun_col
	sun.light_energy = lerpf(lerpf(1.25, 0.12, night), 0.35, cloud * 0.8) * (1.0 - rainy * 0.3)
	sun.shadow_opacity = lerpf(1.0, 0.35, cloud)
	var top := Color(0.32, 0.53, 0.82).lerp(Color(0.4, 0.42, 0.5), cloud).lerp(Color(0.03, 0.05, 0.1), night)
	var hor := Color(0.72, 0.8, 0.88).lerp(Color(0.95, 0.65, 0.45), dusk).lerp(Color(0.62, 0.64, 0.68), cloud).lerp(Color(0.08, 0.1, 0.16), night)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor.darkened(0.15)
	sky_mat.ground_bottom_color = hor.darkened(0.5)
	sky_mat.sun_angle_max = lerpf(30.0, 4.0, cloud)
	env.ambient_light_energy = lerpf(lerpf(0.85, 0.35, night), 0.75, cloud * (1.0 - night))
	env.background_energy_multiplier = lerpf(1.0, 0.5, night)
	env.fog_light_color = hor.lerp(Color(0.7, 0.72, 0.75), foggy * (1.0 - night))
	env.fog_density = lerpf(0.004, 0.035, foggy) + rainy * 0.008
	env.fog_light_energy = lerpf(1.0, 0.4, night)
	# Wet streets dry slowly after rain.
	if rainy > 0.2:
		_wetness = minf(1.0, _wetness + delta * 0.05 * rainy)
	else:
		_wetness = maxf(0.0, _wetness - delta * 0.004)
	RenderingServer.global_shader_parameter_set("wetness", _wetness)
	RenderingServer.global_shader_parameter_set("night_factor", night)
	rain.emitting = rainy > 0.25
	rain.amount_ratio = clampf(rainy, 0.2, 1.0)


func _update_lights() -> void:
	var cam := camera_ref if camera_ref else get_viewport().get_camera_3d()
	if cam == null:
		return
	var night := GameTime.get_night_factor()
	var cp := cam.global_position
	var energy: float = night * 1.6 + _weather_blend.cloud * 0.3 * (1.0 - night)
	var sorted: Array = []
	if energy > 0.05:
		for p in lamp_positions:
			var d: float = (p as Vector3).distance_squared_to(cp)
			if d < 90.0 * 90.0:
				sorted.append([d, p])
		sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _lights.size():
		var l := _lights[k]
		if k < sorted.size():
			l.global_position = sorted[k][1] - Vector3(0, 0.3, 0)
			l.light_energy = energy
			l.visible = true
		else:
			l.visible = false
	var indoor: Array = []
	for p in interior_positions:
		var d2: float = (p as Vector3).distance_squared_to(cp)
		if d2 < 40.0 * 40.0:
			indoor.append([d2, p])
	indoor.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _indoor_lights.size():
		var l2 := _indoor_lights[k]
		if k < indoor.size():
			l2.global_position = indoor[k][1]
			l2.light_energy = 1.1
			l2.visible = true
		else:
			l2.visible = false
