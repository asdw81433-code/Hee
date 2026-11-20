class_name HumanoidPhysics
extends Node
## Physical behaviour of a human: balance, impact reactions, partial and full
## ragdoll, and the smart get-up (recovery) sequence.
##
##   NORMAL ──impact──> balance sim ──drift>step──> STUMBLING (corrective steps)
##                                   └─drift>fall──> RAGDOLL (full physics)
##   RAGDOLL ──settled──> RECOVERING: check space -> align -> blend physics->anim -> get up

signal fell
signal recovered

enum State { NORMAL, STUMBLING, RAGDOLL, RECOVERING }
enum Recovery { NONE, SETTLING, CHECKING_SPACE, ALIGNING, BLENDING, GETTING_UP, BLOCKED }

const STATE_NAMES := ["Animated", "Stumbling", "Ragdoll", "Recovering"]
const RECOVERY_NAMES := ["-", "Settling", "Checking space", "Aligning", "Blending physics->anim", "Getting up", "Blocked (retry)"]
const ARM_CHAINS := {"Left": ["LeftUpperArm", "LeftLowerArm", "LeftHand"], "Right": ["RightUpperArm", "RightLowerArm", "RightHand"]}

var body: HumanoidBody
var balance := BalanceController.new()
var ragdoll: RagdollRig
var state: int = State.NORMAL
var recovery: int = Recovery.NONE

# Physical traits (0..1 unless noted)
var mass: float = 70.0
var strength: float = 0.5
var balance_skill: float = 0.5
var reaction_time: float = 0.15
var recovery_ability: float = 0.5
var fatigue: float = 0.0
var fear: float = 0.0
var injury: float = 0.0
var blocking: bool = false

# Debug / telemetry
var last_impact_force: float = 0.0
var last_impact_dv: float = 0.0
var last_impact_part: String = "-"
var last_impact_severity: String = "-"
var impact_count: int = 0

var _partial_timer: float = 0.0
var _partial_influence: float = 0.0
var _rec_timer: float = 0.0
var _settle_timer: float = 0.0
var _blend: float = 0.0
var _retries: int = 0
var _getup_state: String = ""
var _pending_velocity: Vector3 = Vector3.ZERO
var _pending_impulse: Array = []
var _stumble_timer: float = 0.0
var _ragdoll_time: float = 0.0


func setup(p_body: HumanoidBody) -> void:
	body = p_body
	balance.pendulum_height = maxf(0.6, body.model.hips_height * 1.05)
	_sync_traits()


func _sync_traits() -> void:
	balance.strength = strength
	balance.balance_skill = balance_skill
	balance.reaction_time = reaction_time
	balance.fatigue = fatigue
	balance.injury = injury


func _notification(what: int) -> void:
	# A detached ragdoll rig is not in the tree: free it explicitly.
	if what == NOTIFICATION_PREDELETE and ragdoll and not ragdoll.attached and is_instance_valid(ragdoll.simulator):
		ragdoll.simulator.free()


func _ensure_ragdoll() -> void:
	if ragdoll == null or ragdoll.skeleton != body.model.skeleton:
		ragdoll = RagdollRig.new()
		ragdoll.build(body.model.skeleton, mass)
		ragdoll.add_collision_exception(body.get_rid())


func is_ragdoll() -> bool:
	return state == State.RAGDOLL or (state == State.RECOVERING and recovery <= Recovery.BLENDING)


func has_control() -> bool:
	return state == State.NORMAL or (state == State.STUMBLING and _stumble_timer <= 0.0)


func is_busy() -> bool:
	return state != State.NORMAL


# ------------------------------------------------------------------ impacts
func receive_impact(info: ImpactData) -> void:
	impact_count += 1
	last_impact_force = info.impulse
	var dir := info.direction
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = -body.global_basis.z
	dir = dir.normalized()
	var model_pt: Vector3 = body.model.skeleton.global_transform.affine_inverse() * info.position
	var part := _body_part(model_pt)
	last_impact_part = part
	if state == State.RAGDOLL or (state == State.RECOVERING and recovery <= Recovery.BLENDING):
		if ragdoll and ragdoll.simulating:
			ragdoll.apply_impulse_at(info.position, info.direction * info.impulse)
		last_impact_severity = "ragdoll"
		_emit(info)
		return
	var impulse := info.impulse
	# Blocking absorbs frontal blows.
	if blocking:
		var facing := -body.global_basis.z
		if facing.dot(-dir) > 0.35 and info.source in [ImpactData.Source.PUNCH, ImpactData.Source.KICK, ImpactData.Source.PUSH]:
			impulse *= 0.3
	var height_factor := clampf(model_pt.y / maxf(body.model.hips_height, 0.5), 0.4, 1.5)
	var dv := impulse / mass * (0.55 + 0.45 * height_factor)
	# Moving bodies are easier to unbalance sideways; fear makes people flinch harder.
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	dv *= 1.0 + speed * 0.06 + fear * 0.15
	last_impact_dv = dv
	last_impact_severity = "light" if dv < 0.8 else ("medium" if dv < 2.2 else "heavy")
	var dv2 := Vector2(dir.x, dir.z) * dv
	# Leg sweep: feet are knocked out, the COM is left behind.
	if part == "legs" and dv > 0.7:
		balance.add_offset(-Vector2(dir.x, dir.z) * minf(dv * 0.12, 0.3))
		balance.stun = minf(1.0, balance.stun + 0.25)
	if part == "head":
		balance.stun = minf(1.0, balance.stun + clampf(dv * 0.35, 0.0, 0.9))
	balance.add_velocity(dv2 * 0.85)
	# Instant knock-down for huge impacts (cars, big objects).
	if dv > 5.5 or (part == "head" and dv > 3.5):
		_start_ragdoll(Vector3(dv2.x, minf(dv * 0.25, 2.5), dv2.y), info)
		_emit(info)
		return
	# Spring reaction of the bones near the hit + flinch animation.
	var model_imp: Vector3 = body.model.skeleton.global_transform.basis.inverse() * (info.direction * impulse)
	body.model.rig.apply_hit(model_pt, model_imp, mass)
	if dv > 0.25:
		body.model.animator.play_upper(_hit_clip(dir, part))
	if body.model.face:
		body.model.face.set_expression({"surprise": clampf(dv, 0.3, 1.0), "fear": fear})
	# Partial ragdoll for arms that take a solid hit.
	if part.begins_with("arm_") and dv > 0.6 and dv < 3.0:
		var side := "Left" if part == "arm_l" else "Right"
		_start_partial(ARM_CHAINS[side], info.position, info.direction * impulse * 0.5, 0.55 + dv * 0.1)
	elif part == "head" and dv > 1.0:
		_start_partial(["Head"], info.position, info.direction * impulse * 0.25, 0.45)
	_emit(info)


func _emit(info: ImpactData) -> void:
	var d := info.to_dict()
	d["severity"] = last_impact_severity
	d["part"] = last_impact_part
	d["dv"] = last_impact_dv
	EventBus.character_impacted.emit(body, d)


func _body_part(model_pt: Vector3) -> String:
	var hh := body.model.hips_height
	if model_pt.y > hh + 0.52:
		return "head"
	if model_pt.y < hh - 0.05:
		return "legs"
	if absf(model_pt.x) > 0.17 and model_pt.y > hh + 0.05:
		return "arm_l" if model_pt.x > 0.0 else "arm_r"
	return "torso"


func _hit_clip(dir: Vector3, part: String) -> String:
	if part == "head":
		return "hit_head"
	var fwd := -body.global_basis.z
	var right := body.global_basis.x
	var f := fwd.dot(dir)
	var r := right.dot(dir)
	if absf(f) >= absf(r):
		return "hit_front" if f < 0.0 else "hit_back"
	# pushed toward the character's right = hit came from the left side
	return "hit_left" if r > 0.0 else "hit_right"


func _start_partial(chain: Array, pos: Vector3, impulse: Vector3, duration: float) -> void:
	if state != State.NORMAL and state != State.STUMBLING:
		return
	_ensure_ragdoll()
	if ragdoll.simulating:
		return
	ragdoll.start(chain)
	_partial_timer = duration
	_partial_influence = 0.85
	ragdoll.set_influence(_partial_influence)
	_pending_impulse = [pos, impulse]


# ------------------------------------------------------------------ ragdoll
func _start_ragdoll(extra_velocity: Vector3, info: ImpactData = null) -> void:
	_ensure_ragdoll()
	if ragdoll.simulating:
		ragdoll.stop()
	state = State.RAGDOLL
	recovery = Recovery.SETTLING
	_ragdoll_time = 0.0
	_settle_timer = 0.0
	_retries = 0
	_partial_timer = 0.0
	ragdoll.start()
	_pending_velocity = Vector3(body.velocity.x, maxf(body.velocity.y, -20.0), body.velocity.z) + extra_velocity
	_pending_impulse = [info.position, info.direction * info.impulse * 0.35] if info else []
	body.on_ragdoll_started()
	injury = minf(1.0, injury + 0.08 + (0.02 if info == null else clampf(info.impulse / 1500.0, 0.0, 0.4)))
	balance.reset()
	fell.emit()
	EventBus.character_fell.emit(body)


## Public: knock the character down (falls, debug button, car hits...)
func knock_down(velocity: Vector3) -> void:
	if state == State.RAGDOLL:
		return
	_start_ragdoll(velocity)


# ------------------------------------------------------------------ update
func physics_update(delta: float) -> void:
	if not _pending_impulse.is_empty() and ragdoll and ragdoll.simulating:
		ragdoll.apply_impulse_at(_pending_impulse[0], _pending_impulse[1])
		_pending_impulse = []
	if _pending_velocity != Vector3.ZERO and ragdoll and ragdoll.simulating:
		ragdoll.set_velocity(_pending_velocity)
		_pending_velocity = Vector3.ZERO
	_sync_traits()
	injury = maxf(0.0, injury - delta * 0.004)
	match state:
		State.NORMAL, State.STUMBLING:
			_update_balance(delta)
			_update_partial(delta)
		State.RAGDOLL:
			_update_ragdoll(delta)
		State.RECOVERING:
			_update_recovery(delta)


func _update_balance(delta: float) -> void:
	var ext := Vector2.ZERO
	# Low friction floors: abrupt direction changes make you slip.
	balance.friction = body.floor_friction
	if body.floor_friction < 0.35 and body.is_on_floor():
		var acc := Vector2(body.horizontal_accel.x, body.horizontal_accel.z)
		if acc.length() > 6.0:
			ext -= acc * (0.35 - body.floor_friction) * 0.6
	var res := balance.step(delta, ext)
	_stumble_timer = maxf(0.0, _stumble_timer - delta)
	match int(res.result):
		BalanceController.Result.FALL:
			var v2: Vector2 = balance.velocity
			_start_ragdoll(Vector3(v2.x, 0.0, v2.y) * 1.3)
			return
		BalanceController.Result.STEP:
			var d2: Vector2 = res.step_dir
			body.begin_balance_step(Vector3(d2.x, 0, d2.y), res.step_len)
			state = State.STUMBLING
			_stumble_timer = 0.24
			if body.model.animator.current_state == "loco":
				body.model.animator.set_state("stumble")
	if state == State.STUMBLING and balance.instability() < 0.15 and _stumble_timer <= 0.0:
		state = State.NORMAL
	var inst := balance.instability()
	var rig := body.model.rig
	var to_model := body.model.skeleton.global_transform.basis.inverse()
	var off3: Vector3 = to_model * Vector3(balance.offset.x, 0, balance.offset.y)
	rig.balance_offset = Vector2(off3.x, off3.z)
	rig.balance_instability = clampf(inst * 1.4 - 0.1, 0.0, 1.0)


func _update_partial(delta: float) -> void:
	if ragdoll == null or not ragdoll.simulating or ragdoll.is_full():
		return
	_partial_timer -= delta
	if _partial_timer < 0.0:
		_partial_influence = move_toward(_partial_influence, 0.0, delta * 3.0)
		ragdoll.set_influence(_partial_influence)
		if _partial_influence <= 0.0:
			ragdoll.detach()


func _update_ragdoll(delta: float) -> void:
	_ragdoll_time += delta
	if not ragdoll.is_valid_state():
		push_warning("Ragdoll became unstable, resetting to pose")
		ragdoll.stop()
		ragdoll.start()
	body.follow_ragdoll(ragdoll.hips().global_position)
	var speed := ragdoll.max_speed()
	if speed < 0.35 and _ragdoll_time > 0.8:
		_settle_timer += delta
	else:
		_settle_timer = 0.0
	var min_time := lerpf(2.2, 1.0, recovery_ability)
	if (_settle_timer > 0.45 and _ragdoll_time > min_time) or _ragdoll_time > 6.0:
		state = State.RECOVERING
		recovery = Recovery.CHECKING_SPACE
		_rec_timer = 0.0


func _update_recovery(delta: float) -> void:
	_rec_timer += delta
	match recovery:
		Recovery.CHECKING_SPACE, Recovery.BLOCKED:
			if recovery == Recovery.BLOCKED and _rec_timer < 1.0:
				return
			var spot: Variant = body.find_standing_spot(ragdoll.hips().global_position)
			if spot == null:
				_retries += 1
				recovery = Recovery.BLOCKED
				_rec_timer = 0.0
				# Wriggle free: small impulse on the hips toward open space.
				ragdoll.hips().apply_central_impulse(Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)) * mass * 0.6)
				if _retries < 4:
					return
				spot = body.global_position
			_align_and_blend(spot)
		Recovery.BLENDING:
			_blend = minf(1.0, _blend + delta / 0.6)
			ragdoll.set_influence(1.0 - smoothstep(0.0, 1.0, _blend))
			if _blend >= 1.0:
				ragdoll.detach()
				recovery = Recovery.GETTING_UP
				_rec_timer = 0.0
		Recovery.GETTING_UP:
			if body.model.animator.current_state != _getup_state or _rec_timer > 3.5:
				state = State.NORMAL
				recovery = Recovery.NONE
				balance.reset()
				body.on_recovered()
				recovered.emit()
				EventBus.character_recovered.emit(body)


func _align_and_blend(spot: Vector3) -> void:
	var hips_b: PhysicalBone3D = ragdoll.hips()
	var head_b: PhysicalBone3D = ragdoll.head()
	# Hips body +Z = the character's front. Facing up => lying on the back.
	var front: Vector3 = hips_b.global_basis.z
	var on_back := front.y > 0.0
	var axis: Vector3 = (head_b.global_position - hips_b.global_position)
	axis.y = 0.0
	if axis.length() < 0.05:
		axis = -body.global_basis.z
	axis = axis.normalized()
	# Getup clips: on the back the feet point to model +Z; face down the head does.
	var model_fwd := -axis if on_back else axis
	_getup_state = "getup_back" if on_back else "getup_front"
	body.place_for_recovery(spot, model_fwd)
	body.model.animator.set_state(_getup_state)
	recovery = Recovery.BLENDING
	_blend = 0.0


# ------------------------------------------------------------------ debug
func debug_info() -> Dictionary:
	var joints := {}
	var sk := body.model.skeleton
	for pair in [["LeftUpperLeg", "LeftLowerLeg", "L knee"], ["RightUpperLeg", "RightLowerLeg", "R knee"],
			["LeftUpperArm", "LeftLowerArm", "L elbow"], ["UpperChest", "Head", "Neck"]]:
		var a := sk.get_bone_global_pose(sk.find_bone(pair[0])).basis.y
		var b := sk.get_bone_global_pose(sk.find_bone(pair[1])).basis.y
		joints[pair[2]] = snappedf(rad_to_deg(a.angle_to(b)), 0.1)
	return {
		"physics_state": STATE_NAMES[state],
		"recovery": RECOVERY_NAMES[recovery],
		"balance": snappedf(1.0 - balance.instability(), 0.01),
		"com_offset": snappedf(balance.offset.length(), 0.001),
		"capacity": snappedf(balance.capacity(), 0.1),
		"impact_force": snappedf(last_impact_force, 0.1),
		"impact_dv": snappedf(last_impact_dv, 0.01),
		"impact_part": last_impact_part,
		"severity": last_impact_severity,
		"ragdoll": ("full" if ragdoll and ragdoll.is_full() else ("partial " + str(ragdoll.simulated_bones) if ragdoll and ragdoll.simulating else "off")),
		"animation": body.model.animator.current_state + (" + " + body.model.animator.last_action if body.model.animator.is_upper_busy() else ""),
		"hold": body.model.animator.current_hold,
		"joints": joints,
		"injury": snappedf(injury, 0.01),
		"stun": snappedf(balance.stun, 0.01),
	}
