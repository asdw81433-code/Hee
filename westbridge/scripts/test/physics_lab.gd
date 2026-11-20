extends Node3D
## PHYSICS LAB: test arena for the character physics & animation system.
## Push from any direction, throw objects, slopes, stairs, wall, ledges, ice, dummies
## with different strength/fatigue/fear. F3 / "Debug" shows the live physics state.
## Run with `-- labtest` for the automated test sequence (prints PASS/FAIL, exits).

var player: PlayerController
var cam: ThirdPersonCamera
var hud: HUD
var dummies: Array[HumanoidBody] = []
var target_index: int = 0
var _test_mode: bool = false
var _results: Array = []


func _ready() -> void:
	_build_environment()
	_build_arena()
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0, 0.1, 6)
	cam = ThirdPersonCamera.new()
	add_child(cam)
	cam.set_target(player)
	player.camera_rig = cam
	_spawn_dummies()
	hud = HUD.new()
	add_child(hud)
	hud.player = player
	hud.debug_target = dummies[0]
	if not hud._debug_on:
		hud._debug_on = true
		hud._debug.visible = true
	_build_panel()
	GameTime.running = true
	if "labtest" in OS.get_cmdline_user_args():
		_test_mode = true
		_run_tests()
	elif "demo" in OS.get_cmdline_user_args():
		_demo()


## Scripted demo used for screenshots: medium push, heavy push, thrown crate.
func _demo() -> void:
	cam.yaw = deg_to_rad(20)
	cam.pitch = -14
	await _wait(1.0)
	target_index = 1
	push("front", 140.0)
	target_index = 0
	await _wait(0.4)
	push("left", 420.0)
	target_index = 2
	throw_object(false)


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_arena() -> void:
	var ground_col := Color(0.55, 0.57, 0.55)
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), Vector3(80, 1, 80), ground_col)
	# Grid lines for reading motion
	for i in range(-6, 7):
		Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(i * 5.0, 0.005, 0)), Vector3(0.05, 0.01, 60), Color(0.45, 0.47, 0.45))
		Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(0, 0.005, i * 5.0)), Vector3(60, 0.01, 0.05), Color(0.45, 0.47, 0.45))
	# Slopes 20 and 35 degrees
	for s in [[20.0, 12.0, Color(0.75, 0.6, 0.4)], [35.0, 18.0, Color(0.72, 0.45, 0.35)]]:
		var ang := deg_to_rad(s[0])
		var length := 8.0
		var xf := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(s[1], sin(ang) * length * 0.5 - 0.2, -2))
		Geo.static_box(self, xf, Vector3(4, 0.4, length), s[2])
	# Stairs (real steps)
	for k in 9:
		var top := 0.18 * (k + 1)
		Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(-10, top * 0.5, -1 - k * 0.32)), Vector3(3, top, 0.32), Color(0.6, 0.6, 0.66))
	# Platform at the top of the stairs (ledge 1.6m) and tower (5m)
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(-10, 0.81, -5.22)), Vector3(3, 1.62, 3), Color(0.5, 0.52, 0.6))
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(-18, 2.5, -6.5)), Vector3(3, 5, 3), Color(0.45, 0.48, 0.56))
	# Wall
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -14)), Vector3(14, 3, 0.5), Color(0.75, 0.72, 0.68))
	# Ice patch (friction 0.05)
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(6, 0.02, 12)), Vector3(8, 0.04, 8), Color(0.75, 0.9, 1.0), 0.05)
	# Furniture-like obstacles
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(-4, 0.38, 10)), Vector3(1.6, 0.76, 0.8), Color(0.5, 0.35, 0.22))
	Geo.static_box(self, Transform3D(Basis.IDENTITY, Vector3(-2.8, 0.23, 10)), Vector3(0.45, 0.46, 0.45), Color(0.5, 0.35, 0.22))
	# Dynamic crates
	for k in 4:
		var c := Geo.rigid_box(self, Vector3(-6 + k * 0.7, 0.3, 14), Vector3(0.5, 0.5, 0.5), 12.0, Color(0.7, 0.5, 0.25))
		c.add_child(ThrownObject.new())
	var lbls := [["SLOPE 20°", Vector3(12, 3.5, 2.5)], ["SLOPE 35°", Vector3(18, 5, 2.5)], ["STAIRS", Vector3(-10, 3, 0)],
		["TOWER 5m", Vector3(-18, 6, -5)], ["WALL", Vector3(0, 3.4, -13.6)], ["ICE", Vector3(6, 1.2, 12)]]
	for l in lbls:
		var lab := Label3D.new()
		lab.text = l[0]
		lab.font_size = 64
		lab.position = l[1]
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.outline_size = 12
		add_child(lab)


func _spawn_dummies() -> void:
	var specs := [
		{"name": "Average", "pos": Vector3(0, 0.1, 0), "strength": 0.5, "balance": 0.5, "fatigue": 0.0, "fear": 0.2, "seed": 3},
		{"name": "Strong", "pos": Vector3(3, 0.1, 0), "strength": 0.95, "balance": 0.85, "fatigue": 0.0, "fear": 0.0, "seed": 11},
		{"name": "TiredScared", "pos": Vector3(-3, 0.1, 0), "strength": 0.3, "balance": 0.3, "fatigue": 0.8, "fear": 0.9, "seed": 21},
	]
	for s in specs:
		var d := HumanoidBody.new()
		d.name = s["name"]
		d.collision_layer = 1 << 2
		d.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 4)
		add_child(d)
		var rng := RandomNumberGenerator.new()
		rng.seed = s["seed"]
		var ap := CharacterAppearance.new().randomize_look(rng)
		if s["name"] == "Strong":
			ap.build = CharacterAppearance.Build.MUSCULAR
			ap.weight = 0.6
		d.setup_humanoid(ap)
		d.global_position = s["pos"]
		d.phys.strength = s["strength"]
		d.phys.balance_skill = s["balance"]
		d.phys.fatigue = s["fatigue"]
		d.phys.fear = s["fear"]
		d.rotation.y = 0.0
		dummies.append(d)


# ------------------------------------------------------------------ actions
func _target() -> HumanoidBody:
	if target_index < dummies.size():
		return dummies[target_index]
	return player


func push(dir_name: String, impulse: float, height: float = 1.25) -> void:
	var t := _target()
	var fwd := -t.global_basis.z
	var right := t.global_basis.x
	var dir: Vector3 = {"front": -fwd, "back": fwd, "left": right, "right": -right}[dir_name]
	var pos := t.global_position + Vector3(0, height, 0) - dir * 0.25
	t.receive_impact(ImpactData.create(pos, dir, impulse, ImpactData.Source.PUSH))


func throw_object(ball: bool) -> void:
	var t := _target()
	# Tests throw from straight in front (nobody in between); the button picks a random side.
	var angle := 0.0 if _test_mode else randf() * TAU
	var from := t.global_position + Vector3(0, 1.4, 4).rotated(Vector3.UP, angle)
	var body: RigidBody3D
	if ball:
		body = Geo.rigid_ball(self, from, 0.18, 2.5, Color(0.9, 0.3, 0.2))
	else:
		body = Geo.rigid_box(self, from, Vector3(0.5, 0.5, 0.5), 18.0, Color(0.7, 0.5, 0.25))
	body.add_child(ThrownObject.new())
	var aim := t.global_position + Vector3(0, 1.2, 0)
	var speed := 14.0 if ball else 9.0
	var flight := from.distance_to(aim) / speed
	# Compensate gravity so the object actually reaches the chest.
	body.linear_velocity = (aim - from).normalized() * speed + Vector3(0, 0.5 * 9.8 * flight, 0)
	get_tree().create_timer(8.0).timeout.connect(body.queue_free)


func knock_down() -> void:
	var t := _target()
	t.phys.knock_down(-t.global_basis.z * 3.0 + Vector3(0, 1, 0))


func reset_all() -> void:
	for i in dummies.size():
		var d := dummies[i]
		if d.phys.ragdoll and d.phys.ragdoll.attached:
			d.phys.ragdoll.detach()
		d.phys.state = HumanoidPhysics.State.NORMAL
		d.phys.recovery = HumanoidPhysics.Recovery.NONE
		d.phys.balance.reset()
		d.collider.disabled = false
		d.model.rig.active = true
		d.global_position = Vector3([0.0, 3.0, -3.0][i], 0.1, 0)
		d.model.animator.set_state("loco")


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.theme = UIKit.theme()
	UIKit.anchor(panel, Control.PRESET_TOP_RIGHT, Vector2(-560, 50), Vector2(260, 600))
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.06, 0.08, 0.1, 0.8), 12))
	hud.root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var tlabel := UIKit.label("Target: " + _target().name, 18, UIKit.ACCENT)
	vb.add_child(tlabel)
	var sz := Vector2(230, 34)
	vb.add_child(UIKit.button("Next target", func() -> void:
		target_index = (target_index + 1) % (dummies.size() + 1)
		hud.debug_target = _target()
		tlabel.text = "Target: " + _target().name, sz))
	for row in [["front", "Front"], ["back", "Back"], ["left", "Left"], ["right", "Right"]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.add_child(UIKit.label(row[1], 16))
		for f in [["S", 45.0], ["M", 130.0], ["L", 420.0]]:
			hb.add_child(UIKit.button(f[0], push.bind(row[0], f[1]), Vector2(56, 34)))
		vb.add_child(hb)
	vb.add_child(UIKit.button("Hit head", func() -> void: push("front", 160.0, 1.7), sz))
	vb.add_child(UIKit.button("Leg sweep", func() -> void: push("left", 200.0, 0.35), sz))
	vb.add_child(UIKit.button("Throw ball", throw_object.bind(true), sz))
	vb.add_child(UIKit.button("Throw crate", throw_object.bind(false), sz))
	vb.add_child(UIKit.button("Knock down", knock_down, sz))
	vb.add_child(UIKit.button("Reset dummies", reset_all, sz))
	vb.add_child(UIKit.button("Back to menu", Game.return_to_menu, sz))


# ------------------------------------------------------------------ automated tests
func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append([name, ok, detail])
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + detail if detail != "" else ""))


## Waits in simulated physics time (robust when rendering is slow).
func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout


func _run_tests() -> void:
	await _wait(1.0)
	var avg := dummies[0]
	var strong := dummies[1]
	var weak := dummies[2]
	# 1. light push: no fall, recovers
	target_index = 0
	push("front", 45.0)
	var max_off := 0.0
	for i in 30:
		await _wait(0.05)
		max_off = maxf(max_off, avg.phys.balance.offset.length())
	_check("light push keeps balance", not avg.phys.is_ragdoll() and max_off < 0.2, "peak offset %.3f" % max_off)
	await _wait(1.0)
	_check("light push settles", avg.phys.state == HumanoidPhysics.State.NORMAL and avg.phys.balance.offset.length() < 0.05)
	# 2. medium push: corrective steps, no ragdoll for the strong dummy
	target_index = 1
	var start_pos := strong.global_position
	push("front", 130.0)
	var stepped := false
	for i in 40:
		await _wait(0.05)
		stepped = stepped or strong.phys.state == HumanoidPhysics.State.STUMBLING
	_check("medium push -> strong dummy steps, stays up", stepped and not strong.phys.is_ragdoll(), "moved %.2f m" % strong.global_position.distance_to(start_pos))
	# 3. same medium push on weak (tired, scared) dummy: bigger reaction
	target_index = 2
	push("front", 130.0)
	var weak_peak := 0.0
	var weak_fell := false
	for i in 40:
		await _wait(0.05)
		weak_peak = maxf(weak_peak, weak.phys.balance.offset.length())
		weak_fell = weak_fell or weak.phys.is_ragdoll()
	_check("weak dummy reacts more than strong", weak_fell or weak_peak > 0.12, "peak %.3f fell=%s" % [weak_peak, weak_fell])
	await _wait(6.0)
	# 4. heavy push: ragdoll + valid physics + recovery
	target_index = 0
	push("left", 420.0)
	await _wait(0.4)
	_check("heavy push -> full ragdoll", avg.phys.ragdoll != null and avg.phys.ragdoll.is_full())
	var valid := true
	var knee_ok := true
	var elbow_ok := true
	var saw_blend := false
	for i in 30:
		await _wait(0.05)
		saw_blend = saw_blend or avg.phys.recovery == HumanoidPhysics.Recovery.BLENDING
		if avg.phys.ragdoll and avg.phys.ragdoll.simulating:
			valid = valid and avg.phys.ragdoll.is_valid_state()
			knee_ok = knee_ok and _bend_ok(avg, "LeftUpperLeg", "LeftLowerLeg", true) and _bend_ok(avg, "RightUpperLeg", "RightLowerLeg", true)
			elbow_ok = elbow_ok and _bend_ok(avg, "LeftUpperArm", "LeftLowerArm", false)
	_check("ragdoll stays stable (no explosion)", valid)
	_check("knees only bend backwards", knee_ok)
	_check("elbows only bend forwards", elbow_ok)
	var recovered := false
	for i in 200:
		await _wait(0.05)
		saw_blend = saw_blend or avg.phys.recovery == HumanoidPhysics.Recovery.BLENDING
		if avg.phys.state == HumanoidPhysics.State.NORMAL:
			recovered = true
			break
	_check("ragdoll -> blended get-up -> normal control", recovered and saw_blend, "recovery seen=%s  %s" % [saw_blend, str(avg.phys.debug_info())])
	# 5. fall from the 5 m tower
	reset_all()
	await _wait(0.5)
	avg.global_position = Vector3(-18, 5.1, -6.5)
	await _wait(0.3)
	avg.move_dir = Vector3(1, 0, 0)
	avg.desired_speed = 3.0
	var fell_hard := false
	for i in 60:
		if avg.global_position.x > -16.0:
			avg.move_dir = Vector3.ZERO
		await _wait(0.05)
		fell_hard = fell_hard or avg.phys.is_ragdoll() or avg.model.animator.current_state == "land_hard"
	_check("5 m fall -> hard landing or ragdoll", fell_hard, "state %s" % avg.model.animator.current_state)
	await _wait(7.0)
	# 6. thrown crate knocks somebody over / makes them stumble
	reset_all()
	await _wait(0.5)
	target_index = 2
	var count_before := weak.phys.impact_count
	throw_object(false)
	await _wait(1.5)
	_check("thrown crate delivers an impact", weak.phys.impact_count > count_before, "dv %.2f" % weak.phys.last_impact_dv)
	await _wait(6.0)
	# 7. walk up the stairs and the 20 degree slope
	reset_all()
	await _wait(0.5)
	strong.global_position = Vector3(-10, 0.1, 1.5)
	strong.rotation.y = 0.0
	strong.move_dir = Vector3(0, 0, -1)
	strong.desired_speed = 1.5
	await _wait(5.0)
	strong.move_dir = Vector3.ZERO
	_check("climbs stairs (step-up)", strong.global_position.y > 1.2, "height %.2f pos %s %s" % [strong.global_position.y, strong.global_position, strong.phys.STATE_NAMES[strong.phys.state]])
	strong.global_position = Vector3(12, 0.1, 2.5)
	await _wait(0.3)
	strong.move_dir = Vector3(0, 0, -1)
	strong.desired_speed = 3.0
	await _wait(2.5)
	strong.move_dir = Vector3.ZERO
	_check("walks up 20 degree slope", strong.global_position.y > 1.0, "height %.2f" % strong.global_position.y)
	# 8. run then stop: inertia (doesn't stop instantly)
	reset_all()
	await _wait(0.5)
	avg.global_position = Vector3(0, 0.1, 4)
	avg.move_dir = Vector3(1, 0, 0)
	avg.desired_speed = 4.8
	await _wait(1.5)
	var v0 := avg.ground_speed
	avg.move_dir = Vector3.ZERO
	var p0 := avg.global_position
	await _wait(1.0)
	var brake_dist := avg.global_position.distance_to(p0)
	_check("running stop has inertia", v0 > 4.0 and brake_dist > 0.5 and brake_dist < 3.0, "v0 %.1f brake %.2f m" % [v0, brake_dist])
	var passed := 0
	for r in _results:
		if r[1]:
			passed += 1
	print("LABTEST RESULT %d/%d passed" % [passed, _results.size()])
	get_tree().quit(0 if passed == _results.size() else 1)


## True if the child bone bends to the anatomically correct side of its parent.
func _bend_ok(h: HumanoidBody, parent: String, child: String, knee: bool) -> bool:
	var sk := h.model.skeleton
	var pb := sk.get_bone_global_pose(sk.find_bone(parent)).basis
	var cdir := sk.get_bone_global_pose(sk.find_bone(child)).basis * Vector3.DOWN
	var local := pb.inverse() * cdir
	return local.z < 0.25 if knee else local.z > -0.25
