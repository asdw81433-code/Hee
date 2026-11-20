class_name HumanoidDef
extends RefCounted
## Bone layout shared by every human in the game (player + NPCs).
## Names follow Godot's SkeletonProfileHumanoid so retargeted animations from real
## assets (glTF/FBX with a humanoid rig) can be dropped in later.
##
## Model space: character faces +Z, up is +Y, character's LEFT side is +X.
## All rest rotations are identity, so procedural rotations read as model-space axes:
##   legs/arms: negative X rotation swings the limb forward
##   spine:     positive X rotation leans the torso forward

const BASE_HIPS_HEIGHT := 0.94

## Upper-body bones (used for layered animation filters).
const UPPER_BODY := [
	"Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
]
const ARM_L := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]
const ARM_R := ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const LEG_L := ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes"]
const LEG_R := ["RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
const FACE_BONES := ["EyeL", "EyeR", "LidL", "LidR", "BrowL", "BrowR", "Mouth", "MouthL", "MouthR"]


## Returns an ordered list of {name, parent, pos} for the given body dimensions.
## dims keys: height (scale), leg (scale), arm (scale), torso (scale), shoulders, hips, neck, head
static func bone_list(dims: Dictionary) -> Array:
	var h: float = dims.get("height", 1.0)
	var leg: float = dims.get("leg", 1.0) * h
	var arm: float = dims.get("arm", 1.0) * h
	var tor: float = dims.get("torso", 1.0) * h
	var sh: float = dims.get("shoulders", 1.0)
	var hp: float = dims.get("hips", 1.0)
	var nk: float = dims.get("neck", 1.0) * h
	var hd: float = dims.get("head", 1.0)
	var hips_y := 0.07 * h + 0.40 * leg + 0.41 * leg + 0.06 * h
	var b: Array = []
	b.append({"name": "Root", "parent": "", "pos": Vector3.ZERO})
	b.append({"name": "Hips", "parent": "Root", "pos": Vector3(0, hips_y, 0)})
	b.append({"name": "Spine", "parent": "Hips", "pos": Vector3(0, 0.10 * tor, 0)})
	b.append({"name": "Chest", "parent": "Spine", "pos": Vector3(0, 0.12 * tor, 0)})
	b.append({"name": "UpperChest", "parent": "Chest", "pos": Vector3(0, 0.12 * tor, 0)})
	b.append({"name": "Neck", "parent": "UpperChest", "pos": Vector3(0, 0.15 * tor, 0)})
	b.append({"name": "Head", "parent": "Neck", "pos": Vector3(0, 0.10 * nk, 0)})
	for side in [1.0, -1.0]:
		var p := "Left" if side > 0.0 else "Right"
		b.append({"name": p + "Shoulder", "parent": "UpperChest", "pos": Vector3(0.04 * side, 0.11 * tor, 0)})
		b.append({"name": p + "UpperArm", "parent": p + "Shoulder", "pos": Vector3(0.14 * sh * side * h, -0.02 * h, 0)})
		b.append({"name": p + "LowerArm", "parent": p + "UpperArm", "pos": Vector3(0, -0.27 * arm, 0)})
		b.append({"name": p + "Hand", "parent": p + "LowerArm", "pos": Vector3(0, -0.25 * arm, 0)})
	for side in [1.0, -1.0]:
		var p := "Left" if side > 0.0 else "Right"
		b.append({"name": p + "UpperLeg", "parent": "Hips", "pos": Vector3(0.09 * hp * side * h, -0.06 * h, 0)})
		b.append({"name": p + "LowerLeg", "parent": p + "UpperLeg", "pos": Vector3(0, -0.41 * leg, 0)})
		b.append({"name": p + "Foot", "parent": p + "LowerLeg", "pos": Vector3(0, -0.40 * leg, 0)})
		b.append({"name": p + "Toes", "parent": p + "Foot", "pos": Vector3(0, -0.05 * h, 0.11 * h)})
	# Face rig (children of Head). Positions are relative to the head joint.
	var eye_sp: float = dims.get("eye_spacing", 1.0)
	b.append({"name": "EyeL", "parent": "Head", "pos": Vector3(0.052 * eye_sp, 0.165, 0.098) * hd})
	b.append({"name": "EyeR", "parent": "Head", "pos": Vector3(-0.052 * eye_sp, 0.165, 0.098) * hd})
	b.append({"name": "LidL", "parent": "Head", "pos": Vector3(0.052 * eye_sp, 0.165, 0.098) * hd})
	b.append({"name": "LidR", "parent": "Head", "pos": Vector3(-0.052 * eye_sp, 0.165, 0.098) * hd})
	b.append({"name": "BrowL", "parent": "Head", "pos": Vector3(0.056 * eye_sp, 0.228, 0.112) * hd})
	b.append({"name": "BrowR", "parent": "Head", "pos": Vector3(-0.056 * eye_sp, 0.228, 0.112) * hd})
	b.append({"name": "Mouth", "parent": "Head", "pos": Vector3(0, 0.062, 0.118) * hd})
	b.append({"name": "MouthL", "parent": "Mouth", "pos": Vector3(0.022, 0, -0.002) * hd})
	b.append({"name": "MouthR", "parent": "Mouth", "pos": Vector3(-0.022, 0, -0.002) * hd})
	return b


## Builds a Skeleton3D with identity-rotation rests at the given positions.
static func build_skeleton(dims: Dictionary) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for e in bone_list(dims):
		var idx := sk.add_bone(e["name"])
		if e["parent"] != "":
			sk.set_bone_parent(idx, sk.find_bone(e["parent"]))
		sk.set_bone_rest(idx, Transform3D(Basis.IDENTITY, e["pos"]))
	sk.reset_bone_poses()
	return sk


## Global (model space) rest position of every bone, keyed by name.
static func global_rest_positions(dims: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for e in bone_list(dims):
		var p: Vector3 = e["pos"]
		if e["parent"] != "":
			p += out[e["parent"]]
		out[e["name"]] = p
	return out


static func mirror_name(bone: String) -> String:
	if bone.begins_with("Left"):
		return "Right" + bone.substr(4)
	if bone.begins_with("Right"):
		return "Left" + bone.substr(5)
	if bone.ends_with("L") and bone in FACE_BONES:
		return bone.substr(0, bone.length() - 1) + "R"
	if bone.ends_with("R") and bone in FACE_BONES:
		return bone.substr(0, bone.length() - 1) + "L"
	return bone
