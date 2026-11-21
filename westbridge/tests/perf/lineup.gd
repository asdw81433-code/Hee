## In-engine lineup of characters built from the Blender asset (for screenshots/review).
##   godot --path . res://tests/perf/lineup.tscn -- shots=1.5 shotname=lineup [view=face|lod|body] [procedural]
extends Node3D

const LOOKS := [
	["", 11], ["police", 3], ["worker", 5], ["office", 2], ["cafe", 8], ["", 21], ["", 40], ["office", 9],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view := "body"
	for a in args:
		if a.begins_with("view="):
			view = a.substr(5)
	CharacterModel.force_procedural = "procedural" in args
	_stage()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	match view:
		"face":
			for i in 3:
				_person(LOOKS[i][0], LOOKS[i][1], Vector3((i - 1) * 0.62, 0, 0), 0, 0.0)
			cam.fov = 30
			cam.look_at_from_position(Vector3(0, 1.62, 2.25), Vector3(0, 1.6, 0))
		"lod":
			for i in 3:
				_person(LOOKS[i][0], LOOKS[i][1], Vector3(-1.9 + i * 0.85, 0, 0), 0, 0.0)
				_person(LOOKS[i][0], LOOKS[i][1], Vector3(0.6 + i * 0.85, 0, 0), 1, 0.0)
			cam.fov = 36
			cam.look_at_from_position(Vector3(0, 1.1, 4.6), Vector3(0, 0.95, 0))
		"body":
			# base types: slim / average / heavy / muscular / female, same clothes
			var kinds := [["thin", 0.1], ["avg", 0.4], ["heavy", 1.0], ["muscular", 0.4], ["female", 0.4], ["female heavy", 0.9]]
			for i in kinds.size():
				var a := CharacterAppearance.new()
				a.weight = kinds[i][1]
				if kinds[i][0] == "muscular":
					a.build = CharacterAppearance.Build.MUSCULAR
				if (kinds[i][0] as String).begins_with("female"):
					a.gender = CharacterAppearance.Gender.FEMALE
					a.hair_style = 6
				a.top_color = Color(0.25, 0.45, 0.8)
				a.pants_color = Color(0.17, 0.2, 0.3)
				_spawn(a, Vector3((i - 2.5) * 0.82, 0, 0), 0, 0.0)
			cam.fov = 36
			cam.look_at_from_position(Vector3(0, 1.1, 4.9), Vector3(0, 0.95, 0))
		_:
			for i in LOOKS.size():
				_person(LOOKS[i][0], LOOKS[i][1], Vector3((i - 3.5) * 0.78, 0, 0), 0, deg_to_rad(randf_range(-12, 12)))
			cam.fov = 38
			cam.look_at_from_position(Vector3(0, 1.15, 5.6), Vector3(0, 0.95, 0))


func _person(role: String, seed: int, pos: Vector3, detail: int, yaw: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_spawn(CharacterAppearance.new().randomize_look(rng, -1, -1, role), pos, detail, yaw)


func _spawn(a: CharacterAppearance, pos: Vector3, detail: int, yaw: float) -> void:
	var m := CharacterModel.new()
	add_child(m)
	m.position = pos
	m.rotation.y = yaw
	m.build(a, detail)
	m.set_detail(detail)


func _stage() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.45, 0.62, 0.86)
	mat.sky_horizon_color = Color(0.78, 0.83, 0.9)
	mat.ground_horizon_color = Color(0.7, 0.72, 0.74)
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.64, 0.6)
	ground.material_override = gm
	add_child(ground)
