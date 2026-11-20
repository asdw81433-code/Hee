class_name RagdollRig
extends RefCounted
## Physical skeleton (PhysicalBoneSimulator3D + PhysicalBone3D with joint limits).
## Built lazily the first time a character needs physics and only inserted into the
## scene tree while it is in use, so idle characters cost nothing.
##
## Joint frames: cone-twist twist axis = joint X, hinge axis = joint Z.
## Bones point down (-Y) for limbs and up (+Y) for the spine, rest rotations are identity.

const LAYER_RAGDOLL := 1 << 3
const MASK := 1 | (1 << 4) | (1 << 6)   # world, props, vehicles (no self collision)

## bone, shape(capsule/sphere/box), radius or size, body center offset kind, joint, params, mass fraction
const DEF := [
	{"bone": "Hips", "shape": "box", "size": Vector3(0.3, 0.2, 0.2), "center": "self", "joint": "none", "mass": 0.15},
	{"bone": "Spine", "shape": "capsule", "r": 0.11, "center": "child:Chest", "joint": "cone", "dir": 1, "swing": 22.0, "twist": 15.0, "mass": 0.10},
	{"bone": "Chest", "shape": "capsule", "r": 0.12, "center": "child:UpperChest", "joint": "cone", "dir": 1, "swing": 18.0, "twist": 14.0, "mass": 0.12},
	{"bone": "UpperChest", "shape": "capsule", "r": 0.13, "center": "child:Neck", "joint": "cone", "dir": 1, "swing": 14.0, "twist": 10.0, "mass": 0.10},
	{"bone": "Head", "shape": "sphere", "r": 0.13, "center": "offset", "offset": Vector3(0, 0.15, 0), "joint": "cone", "dir": 1, "swing": 40.0, "twist": 38.0, "mass": 0.08},
	{"bone": "LeftUpperArm", "shape": "capsule", "r": 0.05, "center": "child:LeftLowerArm", "joint": "cone", "dir": -1, "swing": 80.0, "twist": 45.0, "mass": 0.03},
	{"bone": "LeftLowerArm", "shape": "capsule", "r": 0.042, "center": "child:LeftHand", "joint": "hinge", "lo": -145.0, "hi": 0.0, "mass": 0.02},
	{"bone": "LeftHand", "shape": "box", "size": Vector3(0.06, 0.13, 0.04), "center": "offset", "offset": Vector3(0, -0.065, 0), "joint": "cone", "dir": -1, "swing": 35.0, "twist": 20.0, "mass": 0.007},
	{"bone": "RightUpperArm", "shape": "capsule", "r": 0.05, "center": "child:RightLowerArm", "joint": "cone", "dir": -1, "swing": 80.0, "twist": 45.0, "mass": 0.03},
	{"bone": "RightLowerArm", "shape": "capsule", "r": 0.042, "center": "child:RightHand", "joint": "hinge", "lo": -145.0, "hi": 0.0, "mass": 0.02},
	{"bone": "RightHand", "shape": "box", "size": Vector3(0.06, 0.13, 0.04), "center": "offset", "offset": Vector3(0, -0.065, 0), "joint": "cone", "dir": -1, "swing": 35.0, "twist": 20.0, "mass": 0.007},
	{"bone": "LeftUpperLeg", "shape": "capsule", "r": 0.075, "center": "child:LeftLowerLeg", "joint": "cone", "dir": -1, "swing": 55.0, "twist": 18.0, "mass": 0.10},
	{"bone": "LeftLowerLeg", "shape": "capsule", "r": 0.055, "center": "child:LeftFoot", "joint": "hinge", "lo": 0.0, "hi": 145.0, "mass": 0.045},
	{"bone": "LeftFoot", "shape": "box", "size": Vector3(0.09, 0.07, 0.24), "center": "offset", "offset": Vector3(0, -0.035, 0.06), "joint": "hinge", "lo": -35.0, "hi": 40.0, "mass": 0.015},
	{"bone": "RightUpperLeg", "shape": "capsule", "r": 0.075, "center": "child:RightLowerLeg", "joint": "cone", "dir": -1, "swing": 55.0, "twist": 18.0, "mass": 0.10},
	{"bone": "RightLowerLeg", "shape": "capsule", "r": 0.055, "center": "child:RightFoot", "joint": "hinge", "lo": 0.0, "hi": 145.0, "mass": 0.045},
	{"bone": "RightFoot", "shape": "box", "size": Vector3(0.09, 0.07, 0.24), "center": "offset", "offset": Vector3(0, -0.035, 0.06), "joint": "hinge", "lo": -35.0, "hi": 40.0, "mass": 0.015},
]

## Hinge sign: +1 keeps the limits as written, -1 mirrors them (set by tests if the
## physics engine uses the opposite convention).
static var hinge_sign: float = 1.0

var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bones: Dictionary = {}       ## bone name -> PhysicalBone3D
var attached: bool = false
var simulating: bool = false
var simulated_bones: Array = []
var body_mass: float = 70.0
var _exceptions: Array[RID] = []


func build(sk: Skeleton3D, p_body_mass: float) -> void:
	skeleton = sk
	body_mass = p_body_mass
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	for d in DEF:
		var pb := _make_bone(d)
		simulator.add_child(pb)
		bones[d["bone"]] = pb


func _make_bone(d: Dictionary) -> PhysicalBone3D:
	var bone: String = d["bone"]
	var bi := skeleton.find_bone(bone)
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + bone
	pb.bone_name = bone
	var center := Vector3.ZERO
	var length := 0.2
	var kind: String = d["center"]
	if kind.begins_with("child:"):
		var child_i := skeleton.find_bone(kind.substr(6))
		var child_off := skeleton.get_bone_rest(child_i).origin
		center = child_off * 0.5
		length = child_off.length()
	elif kind == "offset":
		center = d["offset"]
	pb.body_offset = Transform3D(Basis.IDENTITY, center)
	var cs := CollisionShape3D.new()
	match String(d["shape"]):
		"capsule":
			var cap := CapsuleShape3D.new()
			cap.radius = d["r"]
			cap.height = maxf(length + d["r"] * 0.6, d["r"] * 2.0 + 0.01)
			cs.shape = cap
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = d["r"]
			cs.shape = sp
		"box":
			var bx := BoxShape3D.new()
			bx.size = d["size"]
			cs.shape = bx
	pb.add_child(cs)
	pb.mass = maxf(body_mass * float(d["mass"]), 0.4)
	pb.friction = 0.85
	pb.bounce = 0.0
	pb.linear_damp = 0.15
	pb.angular_damp = 1.2
	pb.collision_layer = LAYER_RAGDOLL
	pb.collision_mask = MASK
	pb.can_sleep = true
	match String(d["joint"]):
		"none":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		"cone":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			# twist axis (X) along the bone direction
			pb.joint_rotation = Vector3(0, 0, PI * 0.5 * float(d.get("dir", 1)))
			pb.set("joint_constraints/swing_span", float(d["swing"]))
			pb.set("joint_constraints/twist_span", float(d["twist"]))
		"hinge":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			# hinge axis (Z) -> model X so knees/elbows bend in the sagittal plane
			pb.joint_rotation = Vector3(0, PI * 0.5, 0)
			var lo: float = d["lo"] * hinge_sign
			var hi: float = d["hi"] * hinge_sign
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_lower", minf(lo, hi))
			pb.set("joint_constraints/angular_limit_upper", maxf(lo, hi))
	return pb


func add_collision_exception(rid: RID) -> void:
	_exceptions.append(rid)


## Inserts the simulator as the LAST skeleton modifier.
func attach() -> void:
	if attached:
		return
	skeleton.add_child(simulator)
	skeleton.move_child(simulator, -1)
	for rid in _exceptions:
		simulator.physical_bones_add_collision_exception(rid)
	attached = true


func detach() -> void:
	if not attached:
		return
	stop()
	skeleton.remove_child(simulator)
	attached = false


## Places every physical bone on the current animated pose.
func snap_to_pose() -> void:
	var sk_global := skeleton.global_transform
	for b in bones.keys():
		var pb: PhysicalBone3D = bones[b]
		var bi := skeleton.find_bone(b)
		pb.global_transform = sk_global * skeleton.get_bone_global_pose(bi) * pb.body_offset


## subset empty = full ragdoll
func start(subset: Array = []) -> void:
	attach()
	snap_to_pose()
	simulator.influence = 1.0
	simulated_bones = subset.duplicate()
	if subset.is_empty():
		simulator.physical_bones_start_simulation()
	else:
		var names: Array[StringName] = []
		for s in subset:
			names.append(StringName(s))
		simulator.physical_bones_start_simulation(names)
	simulating = true


func stop() -> void:
	if simulating and attached:
		simulator.physical_bones_stop_simulation()
	simulating = false
	simulated_bones = []


func set_influence(v: float) -> void:
	if attached:
		simulator.influence = clampf(v, 0.0, 1.0)


func is_full() -> bool:
	return simulating and simulated_bones.is_empty()


func set_velocity(v: Vector3) -> void:
	for b in bones.keys():
		if simulated_bones.is_empty() or b in simulated_bones:
			bones[b].linear_velocity = v


## Applies an impulse to the physical bone closest to the world point.
func apply_impulse_at(world_pos: Vector3, impulse: Vector3) -> String:
	var best := ""
	var best_d := INF
	for b in bones.keys():
		if not (simulated_bones.is_empty() or b in simulated_bones):
			continue
		var d: float = bones[b].global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = b
	if best != "":
		var pb: PhysicalBone3D = bones[best]
		pb.apply_impulse(impulse, world_pos - pb.global_position)
	return best


func hips() -> PhysicalBone3D:
	return bones["Hips"]


func head() -> PhysicalBone3D:
	return bones["Head"]


func max_speed() -> float:
	var m := 0.0
	for b in bones.values():
		m = maxf(m, (b as PhysicalBone3D).linear_velocity.length())
	return m


func is_valid_state() -> bool:
	# Detect explosions / NaNs: every bone must stay near the hips.
	var hp := hips().global_position
	for b in bones.values():
		var p: Vector3 = (b as PhysicalBone3D).global_position
		if not p.is_finite() or p.distance_to(hp) > 2.5:
			return false
	return true


## Angle (degrees) between a bone and its child, for the debug overlay.
func joint_angle(bone: String, child: String) -> float:
	if not bones.has(bone) or not bones.has(child):
		return 0.0
	var a: Basis = bones[bone].global_basis
	var b: Basis = bones[child].global_basis
	return rad_to_deg((a.y).angle_to(b.y))
