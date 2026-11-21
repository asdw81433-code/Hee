class_name CharacterAssetLibrary
extends RefCounted
## Loads the modular character asset made in Blender
## (assets/characters/westbridge_characters.glb, built by tools/blender/build_characters.py)
## and caches every part in skeleton space: vertices, normals, bone NAMES + weights and
## blend-shape deltas. CharacterAssetBuilder then picks parts for an appearance and
## merges them into ONE skinned mesh bound to the game's own skeleton (same bone
## names and joint positions), so animation, FaceRig, ProceduralRig and ragdolls work
## unchanged.

const ASSET_PATH := "res://assets/characters/westbridge_characters.glb"

static var _loaded: bool = false
static var _ok: bool = false
static var rest_positions: Dictionary = {}     ## bone name -> Vector3 (model space)
static var bone_parents: Dictionary = {}       ## bone name -> parent name ("" for root)
static var bone_order: Array = []
static var parts: Dictionary = {}              ## part name -> Dictionary (see _extract)


static func available() -> bool:
	if not _loaded:
		_load()
	return _ok


static func _load() -> void:
	_loaded = true
	if not ResourceLoader.exists(ASSET_PATH):
		push_warning("Character asset not found, using procedural characters: " + ASSET_PATH)
		return
	var ps := load(ASSET_PATH) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	var sk: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null:
		root.free()
		return
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		bone_order.append(bn)
		rest_positions[bn] = sk.get_bone_global_rest(i).origin
		var p := sk.get_bone_parent(i)
		bone_parents[bn] = sk.get_bone_name(p) if p >= 0 else ""
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var d := _extract(mi as MeshInstance3D, sk)
		if not d.is_empty():
			parts[String(mi.name)] = d
	root.free()
	_ok = parts.has("Body") and parts.has("HeadBase") and rest_positions.has("Head") and rest_positions.has("Mouth")
	if not _ok:
		push_warning("Character asset incomplete, using procedural characters")


## Converts one imported part into skeleton-space data with bone names.
static func _extract(mi: MeshInstance3D, sk: Skeleton3D) -> Dictionary:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var skin := mi.skin
	if skin == null or bones.is_empty():
		return {}
	var per := bones.size() / maxi(verts.size(), 1)
	# bind index -> bone name, and bind index -> (rest_global * bind) to bring vertices to skeleton space
	var bind_names: Array = []
	var to_skel: Array = []
	for b in skin.get_bind_count():
		var bname := String(skin.get_bind_name(b))
		var bone_i := sk.find_bone(bname) if bname != "" else skin.get_bind_bone(b)
		if bname == "" and bone_i >= 0:
			bname = sk.get_bone_name(bone_i)
		bind_names.append(bname)
		var rest := sk.get_bone_global_rest(bone_i) if bone_i >= 0 else Transform3D.IDENTITY
		to_skel.append(rest * skin.get_bind_pose(b))
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(verts.size())
	out_n.resize(verts.size())
	var out_bones: Array = []      # per vertex: [[name, weight], ...]
	for i in verts.size():
		var best := 0
		var bw := -1.0
		var infl: Array = []
		for k in per:
			var w := weights[i * per + k]
			var bi := bones[i * per + k]
			if w > 0.0001:
				infl.append([bind_names[bi], w])
				if w > bw:
					bw = w
					best = bi
		var xf: Transform3D = to_skel[best]
		out_v[i] = xf * verts[i]
		out_n[i] = (xf.basis * norms[i]).normalized()
		out_bones.append(infl)
	# Blend shapes as deltas in skeleton space.
	var shapes: Dictionary = {}
	var bsa := mesh.surface_get_blend_shape_arrays(0)
	for s in mesh.get_blend_shape_count():
		var sv: PackedVector3Array = bsa[s][Mesh.ARRAY_VERTEX]
		var delta := PackedVector3Array()
		delta.resize(verts.size())
		var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
		for i in verts.size():
			var target: Vector3 = sv[i] + (verts[i] if relative else Vector3.ZERO)
			var b0: int = 0
			var bw0 := -1.0
			for k in per:
				if weights[i * per + k] > bw0:
					bw0 = weights[i * per + k]
					b0 = bones[i * per + k]
			delta[i] = (to_skel[b0] as Transform3D) * target - out_v[i]
		shapes[String(mesh.get_blend_shape_name(s))] = delta
	var center := Vector3.ZERO
	for v in out_v:
		center += v
	center /= maxf(out_v.size(), 1)
	var d := {"v": out_v, "n": out_n, "i": idx, "b": out_bones, "shapes": shapes, "center": center}
	# Garment-coverage bitmask: colour attribute "CoverMask" written by the Blender
	# builder, 4 bits per RGB channel (only the body carries it).
	var cm = arr[Mesh.ARRAY_COLOR]
	if cm != null and (cm as PackedColorArray).size() == verts.size():
		var mask := PackedInt32Array()
		mask.resize(verts.size())
		for i in verts.size():
			var c: Color = (cm as PackedColorArray)[i]
			mask[i] = int(roundf(c.r * 15.0)) | (int(roundf(c.g * 15.0)) << 4) | (int(roundf(c.b * 15.0)) << 8)
		d["mask"] = mask
	return d
