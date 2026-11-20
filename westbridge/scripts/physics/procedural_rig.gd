class_name ProceduralRig
extends SkeletonModifier3D
## Procedural layer applied on top of the AnimationTree output:
##  * spring-damper "physical" hit reactions per bone (upper body reacts while legs keep walking)
##  * acceleration / braking lean, banking into turns, slope lean
##  * balance compensation from BalanceController (torso counter-lean + arm flailing)
##  * emotion posture (slump, chest out, hunched)
##  * head + eye look-at with angle limits
##  * two-bone foot IK with pelvis adjustment (no floating / sinking feet)
## All rotations are applied in model space: new_local = parent^-1 * q * parent * local.

const SPRING_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg"]
const SPRING_K := {"Hips": 90.0, "Spine": 70.0, "Chest": 60.0, "UpperChest": 60.0, "Neck": 55.0, "Head": 45.0,
	"LeftUpperArm": 28.0, "LeftLowerArm": 32.0, "RightUpperArm": 28.0, "RightLowerArm": 32.0,
	"LeftUpperLeg": 80.0, "RightUpperLeg": 80.0}
const SPRING_GAIN := {"Hips": 0.25, "Spine": 0.6, "Chest": 0.8, "UpperChest": 0.8, "Neck": 1.1, "Head": 1.6,
	"LeftUpperArm": 2.4, "LeftLowerArm": 2.6, "RightUpperArm": 2.4, "RightLowerArm": 2.6,
	"LeftUpperLeg": 0.6, "RightUpperLeg": 0.6}
const MAX_SPRING_ANGLE := 1.0   # rad

# ---- inputs (set by HumanoidBody each frame) ----
var local_accel: Vector3 = Vector3.ZERO        ## model-space acceleration (z = forward)
var turn_rate: float = 0.0                       ## rad/s, positive = turning left
var speed: float = 0.0
var slope_pitch: float = 0.0                     ## rad, positive = uphill ahead
var balance_offset: Vector2 = Vector2.ZERO       ## model-space COM offset (x = left, y = forward)
var balance_instability: float = 0.0             ## 0..1
var posture: Dictionary = {"slump": 0.0, "chest_out": 0.0, "hunch": 0.0, "head_down": 0.0}
var look_target: Vector3 = Vector3.ZERO
var look_weight: float = 0.0
var foot_ik_enabled: bool = true
var grounded: bool = true
var ik_ray_mask: int = 1
var detail_full: bool = true
var exclude_rids: Array[RID] = []

# ---- state ----
var _idx: Dictionary = {}
var _spring_off: Dictionary = {}
var _spring_vel: Dictionary = {}
var _lean: Vector2 = Vector2.ZERO
var _bank: float = 0.0
var _look: Vector2 = Vector2.ZERO
var _pelvis_off: float = 0.0
var _foot_delta: Dictionary = {"Left": 0.0, "Right": 0.0}
var _foot_normal: Dictionary = {"Left": Vector3.UP, "Right": Vector3.UP}
var _ik_weight: float = 0.0
var _time: float = 0.0
var last_debug: Dictionary = {}


func setup(sk: Skeleton3D) -> void:
	for i in sk.get_bone_count():
		_idx[sk.get_bone_name(i)] = i
	for b in SPRING_BONES:
		_spring_off[b] = Vector3.ZERO
		_spring_vel[b] = Vector3.ZERO


## Hit reaction: point & impulse in model space (impulse in N*s scaled down by mass).
func apply_hit(model_point: Vector3, model_impulse: Vector3, body_mass: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var scale := 1.0 / maxf(body_mass, 20.0)
	for b in SPRING_BONES:
		var gp := sk.get_bone_global_pose(_idx[b]).origin
		var r := model_point - gp
		var dist := r.length()
		var w := exp(-(dist * dist) / 0.09)
		var torque := r.cross(model_impulse)
		var dv: Vector3 = torque * (w * scale * SPRING_GAIN[b] * 6.0)
		_spring_vel[b] = (_spring_vel[b] + dv).limit_length(14.0)


func spring_energy() -> float:
	var e := 0.0
	for b in SPRING_BONES:
		e += _spring_off[b].length()
	return e


func reset_springs() -> void:
	for b in SPRING_BONES:
		_spring_off[b] = Vector3.ZERO
		_spring_vel[b] = Vector3.ZERO


# ------------------------------------------------------------------ helpers
func _gp(sk: Skeleton3D, b: String) -> Transform3D:
	return sk.get_bone_global_pose(_idx[b])


## Rotates bone `b` by model-space quaternion q around its own pivot.
func _rot_model(sk: Skeleton3D, b: String, q: Quaternion) -> void:
	var i: int = _idx[b]
	var parent := sk.get_bone_parent(i)
	var local := sk.get_bone_pose_rotation(i)
	var pq := Quaternion.IDENTITY
	if parent >= 0:
		pq = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var nl := (pq.inverse() * q * pq * local).normalized()
	sk.set_bone_pose_rotation(i, nl)


static func _q(axis: Vector3, angle: float) -> Quaternion:
	if absf(angle) < 0.00001:
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), angle)


# ------------------------------------------------------------------ main
func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _idx.is_empty():
		return
	delta = minf(delta, 0.05)
	_time += delta
	_update_springs(delta)
	_apply_torso(sk, delta)
	_apply_springs(sk)
	if detail_full:
		_apply_arm_flail(sk)
		_apply_look(sk, delta)
		_apply_foot_ik(sk, delta)


func _update_springs(delta: float) -> void:
	for b in SPRING_BONES:
		var k: float = SPRING_K[b]
		var c := 2.0 * sqrt(k) * 0.55
		var off: Vector3 = _spring_off[b]
		var vel: Vector3 = _spring_vel[b]
		vel += (-k * off - c * vel) * delta
		off += vel * delta
		if off.length() > MAX_SPRING_ANGLE:
			off = off.limit_length(MAX_SPRING_ANGLE)
			vel *= 0.5
		_spring_off[b] = off
		_spring_vel[b] = vel


func _apply_springs(sk: Skeleton3D) -> void:
	for b in SPRING_BONES:
		var off: Vector3 = _spring_off[b]
		var ang := off.length()
		if ang > 0.002:
			_rot_model(sk, b, Quaternion(off / ang, ang))


func _apply_torso(sk: Skeleton3D, delta: float) -> void:
	# Lean from acceleration (forward accel -> lean forward), clamp ~14 deg.
	var target_lean := Vector2(
		clampf(-local_accel.x * 0.022, -0.2, 0.2),
		clampf(local_accel.z * 0.026 + slope_pitch * 0.45, -0.22, 0.3))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta * 7.0))
	# Balance: the whole body tilts about the feet in the direction the COM drifts
	# (Root pivot), while the hips/spine bend against it (hip strategy).
	var off := balance_offset.limit_length(0.6)
	if off.length() > 0.001:
		_rot_model(sk, "Root", _q(Vector3.RIGHT, off.y * 0.95) * _q(Vector3.BACK, -off.x * 0.95))
		_rot_model(sk, "Spine", _q(Vector3.RIGHT, -off.y * 0.45) * _q(Vector3.BACK, off.x * 0.45))
	var target_bank := clampf(-turn_rate * speed * 0.035, -0.28, 0.28)
	_bank = lerpf(_bank, target_bank, 1.0 - exp(-delta * 6.0))
	var slump: float = posture.get("slump", 0.0)
	var chest_out: float = posture.get("chest_out", 0.0)
	var hunch: float = posture.get("hunch", 0.0)
	var head_down: float = posture.get("head_down", 0.0)
	var x_axis := Vector3.RIGHT
	var z_axis := Vector3.BACK
	# forward lean = rotation about +X; sideways about +Z (positive tilts to character's right)
	_rot_model(sk, "Hips", _q(x_axis, _lean.y * 0.35) * _q(z_axis, _bank * 0.5 + _lean.x * 0.3))
	_rot_model(sk, "Spine", _q(x_axis, _lean.y * 0.4 + slump * 0.12 + hunch * 0.14 - chest_out * 0.05) * _q(z_axis, _bank * 0.3 + _lean.x * 0.4))
	_rot_model(sk, "Chest", _q(x_axis, _lean.y * 0.25 + slump * 0.1 + hunch * 0.12 - chest_out * 0.08) * _q(z_axis, _lean.x * 0.3))
	if slump > 0.01 or hunch > 0.01 or chest_out > 0.01:
		var sh := slump * 0.18 + hunch * 0.1 - chest_out * 0.08
		_rot_model(sk, "LeftShoulder", _q(z_axis, sh * 0.6) * _q(x_axis, -hunch * 0.15))
		_rot_model(sk, "RightShoulder", _q(z_axis, -sh * 0.6) * _q(x_axis, -hunch * 0.15))
	# Keep the head roughly level when the torso leans (vestibular reflex).
	_rot_model(sk, "Neck", _q(x_axis, -_lean.y * 0.5 + head_down * 0.2 + slump * 0.12 - chest_out * 0.04))
	_rot_model(sk, "Head", _q(x_axis, head_down * 0.18) * _q(z_axis, -_bank * 0.4 - _lean.x * 0.3))


func _apply_arm_flail(sk: Skeleton3D) -> void:
	if balance_instability < 0.03:
		return
	var a := clampf(balance_instability, 0.0, 1.0)
	var wob := sin(_time * 13.0)
	var wob2 := sin(_time * 11.0 + 1.3)
	_rot_model(sk, "LeftUpperArm", _q(Vector3.BACK, a * (1.1 + wob * 0.35)) * _q(Vector3.RIGHT, -a * (0.4 + wob2 * 0.5)))
	_rot_model(sk, "RightUpperArm", _q(Vector3.BACK, -a * (1.1 + wob2 * 0.35)) * _q(Vector3.RIGHT, -a * (0.4 + wob * 0.5)))
	_rot_model(sk, "LeftLowerArm", _q(Vector3.RIGHT, -a * 0.6))
	_rot_model(sk, "RightLowerArm", _q(Vector3.RIGHT, -a * 0.6))


func _apply_look(sk: Skeleton3D, delta: float) -> void:
	var want := Vector2.ZERO
	if look_weight > 0.01:
		var to_model := sk.global_transform.affine_inverse()
		var t := to_model * look_target
		var head_pos := _gp(sk, "Head").origin + Vector3(0, 0.15, 0)
		var dir := t - head_pos
		var chest_basis := _gp(sk, "UpperChest").basis
		var fwd := chest_basis * Vector3.BACK
		fwd.y = 0.0
		if fwd.length() > 0.01 and dir.length() > 0.05:
			fwd = fwd.normalized()
			var flat := Vector3(dir.x, 0, dir.z)
			var yaw := fwd.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length() > 0.01 else 0.0
			var pitch := atan2(dir.y, flat.length())
			# Behind the character: don't snap the head round, just glance.
			if absf(yaw) > deg_to_rad(110.0):
				yaw = signf(yaw) * deg_to_rad(40.0)
			want = Vector2(clampf(yaw, deg_to_rad(-75), deg_to_rad(75)), clampf(pitch, deg_to_rad(-40), deg_to_rad(35))) * look_weight
	_look = _look.lerp(want, 1.0 - exp(-delta * 6.0))
	if _look.length() < 0.002:
		return
	var side_axis := _gp(sk, "UpperChest").basis.x.normalized()
	_rot_model(sk, "Neck", _q(Vector3.UP, _look.x * 0.4) * _q(side_axis, -_look.y * 0.4))
	_rot_model(sk, "Head", _q(Vector3.UP, _look.x * 0.6) * _q(side_axis, -_look.y * 0.6))


func _apply_foot_ik(sk: Skeleton3D, delta: float) -> void:
	var want_w := 1.0 if (foot_ik_enabled and grounded) else 0.0
	_ik_weight = move_toward(_ik_weight, want_w, delta * 5.0)
	if _ik_weight <= 0.001:
		_pelvis_off = 0.0
		return
	var world := sk.global_transform
	var space := sk.get_world_3d().direct_space_state
	var anim_ankle: Dictionary = {}
	for side in ["Left", "Right"]:
		var foot_m := _gp(sk, side + "Foot").origin
		anim_ankle[side] = foot_m
		var foot_w := world * foot_m
		var up := world.basis.y.normalized()
		var q := PhysicsRayQueryParameters3D.create(foot_w + up * 0.55, foot_w - up * 0.75, ik_ray_mask, exclude_rids)
		var hit := space.intersect_ray(q)
		var target_delta := 0.0
		var nrm := Vector3.UP
		if not hit.is_empty():
			var ground_m: Vector3 = world.affine_inverse() * hit.position
			target_delta = clampf(ground_m.y, -0.4, 0.4)
			nrm = (world.basis.inverse() * hit.normal).normalized()
		_foot_delta[side] = lerpf(_foot_delta[side], target_delta, 1.0 - exp(-delta * 14.0))
		_foot_normal[side] = _foot_normal[side].lerp(nrm, 1.0 - exp(-delta * 10.0)).normalized()
	var pelvis_target := minf(minf(_foot_delta["Left"], _foot_delta["Right"]), 0.0)
	_pelvis_off = lerpf(_pelvis_off, pelvis_target, 1.0 - exp(-delta * 12.0)) * _ik_weight
	var hips_i: int = _idx["Hips"]
	sk.set_bone_pose_position(hips_i, sk.get_bone_pose_position(hips_i) + Vector3(0, _pelvis_off, 0))
	for side in ["Left", "Right"]:
		var target: Vector3 = anim_ankle[side] + Vector3(0, _foot_delta[side] * _ik_weight, 0)
		_two_bone(sk, side + "UpperLeg", side + "LowerLeg", side + "Foot", target)
		# Align the foot with the ground normal (limited).
		var n: Vector3 = _foot_normal[side]
		var tilt := Vector3.UP.angle_to(n)
		if tilt > 0.01:
			var axis := Vector3.UP.cross(n).normalized()
			_rot_model(sk, side + "Foot", Quaternion(axis, minf(tilt, 0.5) * _ik_weight))
	last_debug = {"pelvis": _pelvis_off, "foot_l": _foot_delta["Left"], "foot_r": _foot_delta["Right"]}


## Analytic two-bone IK in model space, keeps the current bend plane.
func _two_bone(sk: Skeleton3D, upper: String, lower: String, end: String, target: Vector3) -> void:
	var h := _gp(sk, upper).origin
	var k := _gp(sk, lower).origin
	var e := _gp(sk, end).origin
	if e.distance_to(target) < 0.002:
		return
	var a := h.distance_to(k)
	var b := k.distance_to(e)
	var to_t := target - h
	var d := clampf(to_t.length(), 0.05, a + b - 0.002)
	var dir_t := to_t.normalized()
	var n := (k - h).cross(e - h)
	if n.length() < 0.00001:
		n = Vector3.RIGHT
	n = (n - dir_t * n.dot(dir_t))
	if n.length() < 0.00001:
		n = Vector3.RIGHT
	n = n.normalized()
	var cos_h := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var k_new := h + dir_t.rotated(n, -acos(cos_h)) * a
	var u0 := (k - h).normalized()
	var u1 := (k_new - h).normalized()
	if u0.dot(u1) < 0.99999:
		_rot_model(sk, upper, Quaternion(u0, u1))
	k = _gp(sk, lower).origin
	e = _gp(sk, end).origin
	var l0 := (e - k).normalized()
	var l1 := (target - k).normalized()
	if l0.dot(l1) < 0.99999:
		_rot_model(sk, lower, Quaternion(l0, l1))
