extends Node3D
## Visual check: several random characters + a camera, saves a screenshot and quits.

@export var shot_path := "user://char_preview.png"
var frames := 0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.7, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	ground.mesh = pm
	add_child(ground)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var anims := ["idle", "walk", "idle", "run", "idle"]
	for i in 5:
		var m := CharacterModel.new()
		add_child(m)
		var ap := CharacterAppearance.new().randomize_look(rng)
		if i == 0:
			ap.hair_style = 8; ap.age = 70; ap.jacket = 1; ap.eye_shape = 1
		m.build(ap)
		m.position = Vector3((i - 2) * 0.9, 0, 0)
		m.animator.set_locomotion([0.0, 1.4, 0.0, 4.8, 0.0][i])
		m.face.set_expression({["happy","sad","angry","fear","surprise"][i]: 1.0})
	var cam := Camera3D.new()
	add_child(cam)
	var args := OS.get_cmdline_user_args()
	if "close" in args:
		cam.look_at_from_position(Vector3(0, 1.62, 1.55), Vector3(0, 1.6, 0))
		cam.fov = 50
	else:
		cam.look_at_from_position(Vector3(0, 1.3, 3.6), Vector3(0, 1.0, 0))

func _process(_d: float) -> void:
	frames += 1
	if frames == 40:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("SHOT_SAVED ", ProjectSettings.globalize_path(shot_path))
		get_tree().quit()
