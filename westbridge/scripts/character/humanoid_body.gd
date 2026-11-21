class_name HumanoidBody
extends CharacterBody3D
## Shared movement + animation + physics body for the player and every NPC.
## Controllers (player input or NPC AI) only set `move_dir`, `desired_speed`,
## `wants_jump`, `crouching`... This class turns that into motion with inertia,
## acceleration, braking, turning, stepping, jumping, falling and physical reactions.

signal landed(impact_speed: float)

const GRAVITY := 18.0
const STEP_HEIGHT := 0.42

@export var walk_speed: float = 1.45
@export var jog_speed: float = 3.1
@export var run_speed: float = 4.8
@export var sprint_speed: float = 6.8
@export var jump_velocity: float = 6.2

var appearance: CharacterAppearance
var model: CharacterModel
var phys: HumanoidPhysics
var collider: CollisionShape3D

# ---- control inputs ----
var move_dir: Vector3 = Vector3.ZERO      ## world-space, length 0..1
var desired_speed: float = 0.0
var wants_jump: bool = false
var crouching: bool = false
var face_dir_override: Vector3 = Vector3.ZERO
var control_locked: bool = false           ## sitting, talking, scripted...

# ---- telemetry ----
var horizontal_accel: Vector3 = Vector3.ZERO
var floor_friction: float = 1.0
var turn_rate: float = 0.0
var airborne_time: float = 0.0
var ground_speed: float = 0.0

var _prev_velocity: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _was_on_floor: bool = true
var _fall_peak_speed: float = 0.0
var _step_dir: Vector3 = Vector3.ZERO
var _step_time: float = 0.0
var _step_speed: float = 0.0
var _capsule: CapsuleShape3D
var _was_running_fast: float = 0.0
var _step_up_cooldown: float = 0.0


func setup_humanoid(p_appearance: CharacterAppearance, detail: int = 0) -> void:
	add_to_group("humanoid")
	appearance = p_appearance
	if model == null:
		model = CharacterModel.new()
		model.name = "Model"
		add_child(model)
		model.rotation.y = PI     # model faces +Z, body forward is -Z
	model.build(appearance, detail)
	if collider == null:
		collider = CollisionShape3D.new()
		_capsule = CapsuleShape3D.new()
		collider.shape = _capsule
		add_child(collider)
	_capsule.radius = 0.26 + appearance.weight * 0.06
	_capsule.height = maxf(model.total_height, _capsule.radius * 2.0 + 0.1)
	collider.position = Vector3(0, _capsule.height * 0.5, 0)
	if phys == null:
		phys = HumanoidPhysics.new()
		phys.name = "Physics"
		add_child(phys)
	phys.mass = appearance.body_mass()
	phys.setup(self)
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(48.0)
	safe_margin = 0.02
	model.rig.exclude_rids = [get_rid()]


func rebuild_appearance(p_appearance: CharacterAppearance) -> void:
	setup_humanoid(p_appearance, model.detail_level if model else 0)


# ------------------------------------------------------------------ movement
func _physics_process(delta: float) -> void:
	if model == null:
		return
	phys.physics_update(delta)
	if phys.is_ragdoll():
		return
	if model.position.length_squared() > 0.000001:
		model.position = model.position.lerp(Vector3.ZERO, 1.0 - exp(-delta * 12.0))
	_move(delta)
	_animate(delta)


## True while the body is in deep water (river, lake, sea).
var swimming: bool = false
const SWIM_SPEED := 1.9
const SWIM_DEPTH := 1.15      ## surface height minus body origin while floating


func _water_surface() -> float:
	return CityMap.water_level_at(global_position.x, global_position.z)


func _move(delta: float) -> void:
	var surface := _water_surface()
	swimming = surface > -50.0 and global_position.y < surface - SWIM_DEPTH + 0.15
	var on_floor := is_on_floor() and not swimming
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var speed_now := hvel.length()
	var target := Vector3.ZERO
	var can_control := phys.has_control() and not control_locked
	if can_control and move_dir.length() > 0.01:
		var spd := desired_speed * clampf(move_dir.length(), 0.0, 1.0)
		if crouching:
			spd = minf(spd, 1.4)
		if swimming:
			spd = minf(spd, SWIM_SPEED)
		spd *= lerpf(1.0, 0.55, phys.injury)
		target = move_dir.normalized() * spd
	# Balance step overrides input: the body is pushed into a corrective step.
	if _step_time > 0.0:
		_step_time -= delta
		target = _step_dir * _step_speed
	# Inertia: accelerate gradually, brake harder; less grip on slippery floors.
	var grip := clampf(floor_friction / 0.6, 0.15, 1.0) if on_floor else 0.2
	var accel := 9.0 if target.length() > speed_now else 13.0
	if speed_now > 5.0 and target.length() > speed_now:
		accel = 6.0
	if _step_time > 0.0:
		accel = 30.0
	# Sharp reversal at speed: brake first (pivot) before turning.
	if speed_now > 3.5 and target.length() > 0.1 and hvel.normalized().dot(target.normalized()) < -0.2:
		target = Vector3.ZERO
	var new_h := hvel.move_toward(target, accel * grip * delta)
	horizontal_accel = (new_h - hvel) / maxf(delta, 0.0001)
	velocity.x = new_h.x
	velocity.z = new_h.z
	# Gravity / jump (buoyancy while swimming: float with the head above water,
	# jump or push into a bank to climb out)
	if swimming:
		airborne_time = 0.0
		_fall_peak_speed = 0.0
		var target_y := surface - SWIM_DEPTH
		velocity.y = clampf((target_y - global_position.y) * 4.0, -2.0, 3.0)
		if can_control and (wants_jump or (is_on_wall() and target.length() > 0.5)):
			velocity.y = 6.5
	elif on_floor:
		airborne_time = 0.0
		if wants_jump and can_control and not crouching:
			velocity.y = jump_velocity
			model.animator.set_state("jump")
			on_floor = false
	else:
		airborne_time += delta
		velocity.y -= GRAVITY * delta
		_fall_peak_speed = maxf(_fall_peak_speed, -velocity.y)
	wants_jump = false
	var before := global_position
	move_and_slide()
	_try_step_up(delta, before, target if target.length() > new_h.length() else new_h)
	_handle_collisions()
	_update_floor_info()
	# Landing
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		_on_landed(_fall_peak_speed)
		_fall_peak_speed = 0.0
	_was_on_floor = now_floor
	# Turning toward movement / override direction
	var face := face_dir_override
	if face.length() < 0.01 and can_control and target.length() > 0.2:
		face = target
	elif face.length() < 0.01 and _step_time <= 0.0 and new_h.length() > 0.6 and can_control:
		face = new_h
	if face.length() > 0.01:
		var want_yaw := atan2(-face.x, -face.z)
		var turn_speed := deg_to_rad(lerpf(720.0, 260.0, clampf(speed_now / sprint_speed, 0.0, 1.0)))
		var diff := wrapf(want_yaw - rotation.y, -PI, PI)
		rotation.y += clampf(diff, -turn_speed * delta, turn_speed * delta)
	turn_rate = wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = rotation.y
	ground_speed = Vector2(velocity.x, velocity.z).length()


func _try_step_up(_delta: float, before: Vector3, wanted: Vector3) -> void:
	# Climb stairs / curbs: if blocked by a low obstacle, probe above it one capsule
	# radius ahead; when there is floor up there, lift the body (vertical only) and let
	# the next frame carry it forward. Foot IK hides the small pop.
	_step_up_cooldown -= _delta
	if not is_on_wall() or not _was_on_floor or wanted.length() < 0.3 or _step_up_cooldown > 0.0:
		return
	var moved := (global_position - before)
	moved.y = 0.0
	var want := wanted * get_physics_process_delta_time()
	if moved.length() > want.length() * 0.7:
		return
	var xf := global_transform
	if test_move(xf, Vector3(0, STEP_HEIGHT, 0)):
		return
	xf.origin.y += STEP_HEIGHT
	var fwd := wanted.normalized() * (_capsule.radius + 0.06)
	if test_move(xf, fwd):
		return
	# Thin ray under the probe position finds the tread height exactly (a shape
	# sweep would catch the nosing of the next step on tight stairs).
	var probe := xf.origin + fwd
	var ray := PhysicsRayQueryParameters3D.create(probe, probe + Vector3(0, -STEP_HEIGHT - 0.1, 0), collision_mask & 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.7:
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.02 and rise <= STEP_HEIGHT:
		var old := global_position
		global_position = Vector3(probe.x, hit.position.y + 0.01, probe.z)
		velocity.y = 0.0
		# Climb at the speed the character is walking, not one step per frame.
		_step_up_cooldown = fwd.length() / maxf(wanted.length(), 0.5)
		# Keep the visual where it was and let it catch up smoothly.
		model.position -= global_basis.inverse() * (global_position - old)


func _update_floor_info() -> void:
	floor_friction = 1.0
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y > 0.6:
			var col := c.get_collider()
			if col is StaticBody3D and (col as StaticBody3D).physics_material_override:
				floor_friction = (col as StaticBody3D).physics_material_override.friction
			elif col and col.has_meta("friction"):
				floor_friction = float(col.get_meta("friction"))
			break


func _handle_collisions() -> void:
	var speed := Vector2(_prev_velocity.x, _prev_velocity.z).length()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		var n := c.get_normal()
		var closing := -_prev_velocity.dot(n)
		if other is HumanoidBody and closing > 1.6:
			var o := other as HumanoidBody
			var pos := c.get_position() + Vector3(0, 1.1, 0)
			var imp := ImpactData.from_object(pos, -n * closing, phys.mass, o.phys.mass, ImpactData.Source.BUMP, self)
			o.receive_impact(imp)
			var back := ImpactData.from_object(global_position + Vector3(0, 1.1, 0), n * closing * 0.5, o.phys.mass, phys.mass, ImpactData.Source.BUMP, o)
			receive_impact(back)
		elif other is RigidBody3D:
			var rb := other as RigidBody3D
			rb.apply_central_impulse(-n * phys.mass * closing * 0.15)
		elif absf(n.y) < 0.3 and closing > 5.0 and speed > 5.0:
			# Ran face-first into a wall.
			receive_impact(ImpactData.create(c.get_position() + Vector3(0, 1.2, 0), n, phys.mass * closing * 0.55, ImpactData.Source.WALL))
	_prev_velocity = velocity


func _on_landed(fall_speed: float) -> void:
	landed.emit(fall_speed)
	if fall_speed > 15.0:
		phys.knock_down(Vector3(velocity.x, -fall_speed * 0.3, velocity.z))
		phys.injury = minf(1.0, phys.injury + (fall_speed - 14.0) * 0.06)
	elif fall_speed > 9.5:
		model.animator.set_state("land_hard")
		phys.balance.add_velocity(Vector2(velocity.x, velocity.z) * 0.15)
		phys.injury = minf(1.0, phys.injury + 0.04)
	elif fall_speed > 3.0:
		model.animator.set_state("land")


func _animate(delta: float) -> void:
	var anim := model.animator
	var sp := ground_speed
	anim.set_locomotion(sp, phys.injury)
	var st := anim.current_state
	if not is_on_floor() and airborne_time > 0.22 and st != "jump" and velocity.y < -2.0 and phys.state == HumanoidPhysics.State.NORMAL:
		anim.set_state("fall")
	elif is_on_floor():
		if st == "fall":
			anim.set_state("loco")
		if not control_locked and (st == "loco" or st == "crouch"):
			anim.set_state("crouch" if crouching else "loco")
		# Braking from a run: plant a foot and lean back.
		if st == "loco" and _was_running_fast > 4.2 and sp < 1.2 and move_dir.length() < 0.1:
			anim.set_state("stop_run")
	_was_running_fast = lerpf(_was_running_fast, sp, 1.0 - exp(-delta * 6.0)) if sp > _was_running_fast else lerpf(_was_running_fast, sp, 1.0 - exp(-delta * 2.5))
	# Feed the procedural rig.
	var rig := model.rig
	var local := global_basis.inverse() * horizontal_accel
	rig.local_accel = Vector3(-local.x, 0, -local.z)
	rig.turn_rate = turn_rate
	rig.speed = sp
	rig.grounded = is_on_floor() and anim.current_state in ["loco", "crouch", "stop_run", "land", "stumble"]
	var fn := get_floor_normal() if is_on_floor() else Vector3.UP
	var fwd := -global_basis.z
	rig.slope_pitch = -asin(clampf(fn.dot(fwd), -1.0, 1.0)) if fn.y < 0.999 else 0.0
	anim.cadence_scale = lerpf(1.0, 0.88, phys.fatigue)


# ------------------------------------------------------------------ physics hooks
func receive_impact(info: ImpactData) -> void:
	phys.receive_impact(info)


func begin_balance_step(dir: Vector3, length: float) -> void:
	_step_dir = dir.normalized()
	_step_time = 0.22
	_step_speed = length / 0.22


func on_ragdoll_started() -> void:
	collider.disabled = true
	velocity = Vector3.ZERO
	model.rig.active = false
	model.rig.reset_springs()


func on_recovered() -> void:
	model.rig.active = true


## While ragdolled the capsule follows the hips so AI/camera/streaming stay valid.
func follow_ragdoll(hips_pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(hips_pos + Vector3.UP * 0.3, hips_pos + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(q)
	var ground := hips_pos.y - 0.15
	if not hit.is_empty():
		ground = hit.position.y
	# Simulated bones live in world space, so moving the body does not move the ragdoll.
	global_position = Vector3(hips_pos.x, ground, hips_pos.z)


## Returns a free standing position near `around` (or null).
func find_standing_spot(around: Vector3) -> Variant:
	var space := get_world_3d().direct_space_state
	var shape_q := PhysicsShapeQueryParameters3D.new()
	shape_q.shape = _capsule
	shape_q.collision_mask = 1 | (1 << 4) | (1 << 6) | (1 << 2) | (1 << 1)
	shape_q.exclude = [get_rid()]
	var offsets: Array = [Vector3.ZERO]
	for r in [0.45, 0.9]:
		for k in 8:
			var a := TAU * k / 8.0
			offsets.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for off in offsets:
		var p: Vector3 = around + off
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 2.5, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		shape_q.transform = Transform3D(Basis.IDENTITY, ground + Vector3(0, _capsule.height * 0.5 + 0.05, 0))
		if space.intersect_shape(shape_q, 1).is_empty():
			return ground
	return null


func place_for_recovery(spot: Vector3, model_forward: Vector3) -> void:
	global_position = spot
	# body forward (-Z) = model +Z
	rotation.y = atan2(-model_forward.x, -model_forward.z)
	_prev_yaw = rotation.y
	collider.disabled = false
	velocity = Vector3.ZERO
	model.rig.reset_springs()
	model.rig.active = true


func is_down() -> bool:
	return phys.is_ragdoll()


func head_position() -> Vector3:
	return model.head_world_position()
