class_name FaceRig
extends SkeletonModifier3D
## Drives the face bones every frame: emotion expressions, blinking, eye gaze and
## talking mouth movement. Runs after the body animation and the procedural rig.

## Base lid closedness per CharacterAppearance.EYE_SHAPES (round, sleepy, narrow, wide)
const LID_BASE := [0.14, 0.44, 0.34, 0.02]

var expression: Dictionary = {"happy": 0.0, "sad": 0.0, "angry": 0.0, "fear": 0.0, "surprise": 0.0, "tired": 0.0}
var _expr: Dictionary = expression.duplicate()
var lid_base: float = 0.14
var talking: bool = false
var gaze_target: Vector3 = Vector3.ZERO
var gaze_weight: float = 0.0
var detail_full: bool = true

var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _talk_phase: float = 0.0
var _saccade: Vector2 = Vector2.ZERO
var _saccade_timer: float = 0.5
var _gaze: Vector2 = Vector2.ZERO
var _bones: Dictionary = {}
var _rest: Dictionary = {}


func setup(sk: Skeleton3D, eye_shape: int) -> void:
	lid_base = LID_BASE[clampi(eye_shape, 0, 3)]
	for n in HumanoidDef.FACE_BONES:
		var idx := sk.find_bone(n)
		_bones[n] = idx
		_rest[n] = sk.get_bone_rest(idx).origin
	_bones["Head"] = sk.find_bone("Head")
	_blink_timer = randf_range(1.0, 4.0)


func set_expression(values: Dictionary) -> void:
	for k in values.keys():
		expression[k] = clampf(float(values[k]), 0.0, 1.0)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _bones.is_empty():
		return
	for k in _expr.keys():
		_expr[k] = lerpf(_expr[k], expression.get(k, 0.0), 1.0 - exp(-delta * 6.0))
	var happy: float = _expr.happy
	var sad: float = _expr.sad
	var angry: float = _expr.angry
	var fear: float = _expr.fear
	var surprise: float = _expr.surprise
	var tired: float = _expr.tired

	# ---- blink ----
	var blink := 0.0
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(1.8, 5.5) * (0.6 if fear > 0.4 else 1.0)
	if _blink_t >= 0.0:
		_blink_t += delta
		blink = sin(clampf(_blink_t / 0.16, 0.0, 1.0) * PI)
		if _blink_t > 0.16:
			_blink_t = -1.0

	# ---- lids ----
	var closed := lid_base + tired * 0.32 + angry * 0.2 + sad * 0.14 + happy * 0.08 - surprise * 0.5 - fear * 0.35
	closed = clampf(closed, 0.0, 0.85)
	closed = lerpf(closed, 1.0, blink)
	var lid_angle := lerpf(-72.0, 92.0, closed)
	var lid_tilt := angry * 16.0 - sad * 14.0
	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		sk.set_bone_pose_rotation(_bones["Lid" + side], Quaternion.from_euler(Vector3(deg_to_rad(lid_angle), 0, deg_to_rad(lid_tilt * sgn))))

	if not detail_full:
		return

	# ---- brows ----
	var brow_rot := angry * 22.0 - sad * 18.0 - fear * 10.0
	var brow_up := surprise * 0.014 + fear * 0.01 + sad * 0.004 + happy * 0.003 - angry * 0.007
	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		var bn: String = "Brow" + side
		sk.set_bone_pose_rotation(_bones[bn], Quaternion.from_euler(Vector3(0, 0, deg_to_rad(brow_rot * sgn))))
		sk.set_bone_pose_position(_bones[bn], _rest[bn] + Vector3(0, brow_up, 0))

	# ---- mouth ----
	var smile := happy * 28.0 - sad * 22.0 - angry * 16.0 - fear * 6.0
	var open := 1.0 + surprise * 2.6 + fear * 0.9
	if talking:
		_talk_phase += delta * randf_range(9.0, 14.0)
		open += maxf(0.0, sin(_talk_phase)) * 2.2 + 0.3
	var width := 1.0 + happy * 0.18 - surprise * 0.25
	sk.set_bone_pose_scale(_bones["Mouth"], Vector3(width, open, 1.0))
	sk.set_bone_pose_rotation(_bones["MouthL"], Quaternion.from_euler(Vector3(0, 0, deg_to_rad(smile))))
	sk.set_bone_pose_rotation(_bones["MouthR"], Quaternion.from_euler(Vector3(0, 0, deg_to_rad(-smile))))

	# ---- eyes / gaze ----
	_saccade_timer -= delta
	if _saccade_timer <= 0.0:
		_saccade_timer = randf_range(0.4, 2.2)
		_saccade = Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0)) * (2.0 if fear > 0.4 else 1.0)
	var want := _saccade
	if gaze_weight > 0.01:
		var head_g: Transform3D = sk.global_transform * sk.get_bone_global_pose(_bones["Head"])
		var eye_rest: Vector3 = _rest["EyeL"]
		var local: Vector3 = head_g.affine_inverse() * gaze_target - eye_rest
		var yaw := rad_to_deg(atan2(local.x, maxf(local.z, 0.05)))
		var pitch := -rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length()))
		want = want.lerp(Vector2(clampf(yaw, -26, 26), clampf(pitch, -16, 16)), gaze_weight)
	_gaze = _gaze.lerp(want, 1.0 - exp(-delta * 18.0))
	var eye_q := Quaternion.from_euler(Vector3(deg_to_rad(_gaze.y), deg_to_rad(_gaze.x), 0))
	sk.set_bone_pose_rotation(_bones["EyeL"], eye_q)
	sk.set_bone_pose_rotation(_bones["EyeR"], eye_q)
