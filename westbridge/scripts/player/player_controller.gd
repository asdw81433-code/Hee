class_name PlayerController
extends HumanoidBody
## The player: camera-relative movement, stamina, punching, blocking, interacting.
## Movement physics, animation and reactions come from HumanoidBody.

signal stats_updated(stats: Dictionary)

var camera_rig: ThirdPersonCamera
var interactor: PlayerInteractor
var stats: Dictionary = {"health": 100.0, "stamina": 100.0, "hunger": 80.0, "energy": 85.0}
var _attack_cooldown: float = 0.0
var _punch_left: bool = false
var _pending_hit: float = -1.0
var _stats_timer: float = 0.0
var seated_on: Node = null


func _ready() -> void:
	add_to_group("player")
	add_to_group("savable")
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 2) | (1 << 4) | (1 << 6)
	var ap := CharacterAppearance.new()
	var saved: Dictionary = Game.player_profile.get("appearance", {})
	if saved.is_empty():
		ap.randomize_look(RandomNumberGenerator.new(), CharacterAppearance.Gender.MALE, 28)
		ap.hat = 0
	else:
		ap.from_dict(saved)
	setup_humanoid(ap, 0)
	phys.strength = 0.6
	phys.balance_skill = 0.6
	phys.reaction_time = 0.12
	phys.recovery_ability = 0.7
	interactor = PlayerInteractor.new()
	interactor.name = "Interactor"
	add_child(interactor)
	EventBus.player_spawned.emit(self)


func save_key() -> String:
	return "player"


func save_state() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "yaw": rotation.y,
		"stats": stats.duplicate(), "appearance": appearance.to_dict(), "injury": phys.injury}


func load_state(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
	rotation.y = float(d.get("yaw", 0.0))
	var st: Dictionary = d.get("stats", {})
	for k in st.keys():
		stats[k] = float(st[k])
	if d.has("appearance"):
		rebuild_appearance(CharacterAppearance.from_dictionary(d["appearance"]))
	phys.injury = float(d.get("injury", 0.0))
	velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_target(self)


func _physics_process(delta: float) -> void:
	PlayerInput.poll()
	_read_controls(delta)
	super._physics_process(delta)
	_update_combat(delta)
	_update_stats(delta)


func _read_controls(_delta: float) -> void:
	var in_move := PlayerInput.move
	if seated_on != null:
		if in_move.length() > 0.5 or PlayerInput.just_pressed("jump"):
			stand_up()
		move_dir = Vector3.ZERO
		return
	var basis := camera_rig.flat_basis() if camera_rig else Basis.IDENTITY
	var dir := basis * Vector3(in_move.x, 0, in_move.y)
	move_dir = dir.limit_length(1.0)
	var mag := in_move.length()
	if mag < 0.05:
		desired_speed = 0.0
	elif PlayerInput.sprint and stats.stamina > 1.0:
		desired_speed = sprint_speed
	elif PlayerInput.walk or mag < 0.45:
		desired_speed = walk_speed
	elif mag < 0.85:
		desired_speed = jog_speed
	else:
		desired_speed = run_speed
	if PlayerInput.just_pressed("jump"):
		wants_jump = true
	if PlayerInput.just_pressed("crouch"):
		crouching = not crouching
	if PlayerInput.just_pressed("interact") and interactor:
		interactor.interact()
	phys.blocking = PlayerInput.block and phys.has_control()
	model.animator.set_hold("hold_block" if phys.blocking else "none")
	if PlayerInput.just_pressed("attack"):
		attack()


func attack() -> void:
	if _attack_cooldown > 0.0 or not phys.has_control() or control_locked:
		return
	_attack_cooldown = 0.45
	_punch_left = not _punch_left
	model.animator.play_upper("punch_l" if _punch_left else "punch_r")
	_pending_hit = 0.19
	stats.stamina = maxf(0.0, stats.stamina - 4.0)


func _update_combat(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _pending_hit < 0.0:
		return
	_pending_hit -= delta
	if _pending_hit > 0.0:
		return
	_pending_hit = -1.0
	var fwd := -global_basis.z
	var center := global_position + Vector3(0, 1.3, 0) + fwd * 0.75
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.45
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = (1 << 2) | (1 << 4) | (1 << 3)
	q.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var done := {}
	for h in hits:
		var col: Object = h.collider
		if col is HumanoidBody and not done.has(col):
			done[col] = true
			var target := col as HumanoidBody
			var hit_pos := target.global_position + Vector3(0, 1.35, 0) - fwd * 0.2
			var power := 70.0 * (0.8 + 0.4 * phys.strength)
			var imp := ImpactData.create(hit_pos, fwd + Vector3(0, 0.1, 0), power, ImpactData.Source.PUNCH, self)
			imp.damage = 8.0
			target.receive_impact(imp)
			EventBus.world_event.emit({"type": "assault", "position": global_position, "radius": 25.0,
				"severity": 0.6, "instigator": self, "victim": target, "time": GameTime.total_minutes})
		elif col is PhysicalBone3D:
			(col as PhysicalBone3D).apply_central_impulse(fwd * 35.0)
		elif col is RigidBody3D and not done.has(col):
			done[col] = true
			(col as RigidBody3D).apply_impulse(fwd * 40.0, center - (col as RigidBody3D).global_position)


func _update_stats(delta: float) -> void:
	var sprinting := ground_speed > run_speed + 0.3
	if sprinting:
		stats.stamina = maxf(0.0, stats.stamina - delta * 14.0)
	else:
		stats.stamina = minf(100.0, stats.stamina + delta * (9.0 if ground_speed < 2.0 else 5.0))
	var game_minutes := delta * GameTime.minutes_per_second if GameTime.running else 0.0
	stats.hunger = maxf(0.0, stats.hunger - game_minutes * 0.045)
	stats.energy = maxf(0.0, stats.energy - game_minutes * (0.03 + (0.04 if sprinting else 0.0)))
	phys.fatigue = clampf(1.0 - stats.energy / 100.0, 0.0, 1.0) * 0.6 + (0.3 if stats.stamina < 10.0 else 0.0)
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		stats_updated.emit(stats)
		EventBus.stats_changed.emit(stats)


# ------------------------------------------------------------------ seats
func sit_on(seat: Node3D, sit_transform: Transform3D) -> void:
	seated_on = seat
	control_locked = true
	velocity = Vector3.ZERO
	global_position = sit_transform.origin
	rotation.y = sit_transform.basis.get_euler().y
	collider.disabled = true
	model.animator.set_state("sit_down")


func stand_up() -> void:
	if seated_on == null:
		return
	if seated_on.has_method("release"):
		seated_on.release(self)
	seated_on = null
	collider.disabled = false
	global_position += -global_basis.z * 0.45
	model.animator.set_state("stand_up")
	get_tree().create_timer(0.6).timeout.connect(func() -> void: control_locked = false)


func restore_stats(changes: Dictionary) -> void:
	for k in changes.keys():
		stats[k] = clampf(float(stats.get(k, 0.0)) + float(changes[k]), 0.0, 100.0)
	EventBus.stats_changed.emit(stats)
