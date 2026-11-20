class_name CharacterMeshFactory
extends RefCounted
## Turns a CharacterAppearance into a single skinned, vertex-colored mesh:
## stylized body (smooth skinned torso/limbs), big expressive eyes with lids,
## brows, mouth, nose, hair, beard and layered clothing that really sits on the body.

const EYE_WHITE := Color(0.97, 0.96, 0.93)
const PUPIL := Color(0.04, 0.035, 0.03)
const MOUTH := Color(0.20, 0.09, 0.08)

static var _material: StandardMaterial3D


static func shared_material() -> StandardMaterial3D:
	if _material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.78
		m.metallic_specular = 0.35
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.rim_enabled = true
		m.rim = 0.18
		m.rim_tint = 0.6
		_material = m
	return _material


var a: CharacterAppearance
var mb: SkinnedMeshBuilder
var g: Dictionary          ## bone name -> global rest position
var bi: Dictionary         ## bone name -> index
var head_center: Vector3
var head_radii: Vector3
var _hd: float = 1.0


static func build(appearance: CharacterAppearance, skeleton: Skeleton3D, detail: float = 1.0) -> ArrayMesh:
	var f := CharacterMeshFactory.new()
	return f._build(appearance, skeleton, detail)


func _build(appearance: CharacterAppearance, skeleton: Skeleton3D, detail: float) -> ArrayMesh:
	a = appearance
	mb = SkinnedMeshBuilder.new()
	mb.detail = detail
	g = HumanoidDef.global_rest_positions(a.body_dims())
	for i in skeleton.get_bone_count():
		bi[skeleton.get_bone_name(i)] = i
	_hd = 1.0
	head_center = g["Head"] + Vector3(0, 0.15 * a.head_height, 0.005)
	head_radii = Vector3(0.118 * a.head_width, 0.168 * a.head_height, 0.125)
	_build_torso()
	_build_arms()
	_build_legs()
	_build_neck()
	_build_head()
	_build_face()
	_build_hair()
	_build_beard()
	_build_hat()
	_build_glasses()
	_build_accessories()
	return mb.build_mesh(true)


func B(n: String) -> int:
	return bi.get(n, 0)


# ------------------------------------------------------------------ helpers
func _weight_mult() -> float:
	return 1.0 + a.weight * 0.35


func _clothing_pad() -> float:
	match a.jacket:
		1, 2:
			return 0.012
		3, 4:
			return 0.008
		5:
			return 0.03
	if a.top == 4 or a.top == 6:
		return 0.008
	return 0.0


func _has_sleeved_jacket() -> bool:
	return a.jacket in [1, 2, 5]


## Chain weight: hat-function blending around each joint along an ordered chain.
static func _chain_weight(pos: float, joints: Array, bones_idx: Array) -> Array:
	# joints: ascending positions where each bone starts; bones_idx same length.
	var n := joints.size()
	var k := 0
	for i in n:
		if pos >= joints[i]:
			k = i
	var start: float = joints[k]
	var end: float = joints[k + 1] if k + 1 < n else start + 1.0
	var f := clampf((pos - start) / maxf(end - start, 0.0001), 0.0, 1.0)
	if k > 0 and f < 0.3:
		return [bones_idx[k], bones_idx[k - 1], 0.5 * (1.0 - f / 0.3)]
	if k + 1 < n and f > 0.7:
		return [bones_idx[k], bones_idx[k + 1], 0.5 * (f - 0.7) / 0.3]
	return [bones_idx[k], -1, 0.0]


# ------------------------------------------------------------------ torso
var _torso_y0: float
var _torso_y1: float


func _build_torso() -> void:
	var female := a.gender == CharacterAppearance.Gender.FEMALE
	var w := a.weight
	var hipw := (1.12 if female else 1.0) * (1.0 + w * 0.22)
	var waist := (0.9 if female else 1.0) * (1.0 + w * 0.38)
	var belly := 1.0 + w * 0.6
	var chest := 1.0 + w * 0.15
	var shoulders := (0.9 if female else 1.0) * (1.0 + w * 0.1)
	var bust := 1.12 if female else 1.0
	match a.build:
		CharacterAppearance.Build.THIN:
			waist *= 0.9; chest *= 0.9; shoulders *= 0.93; hipw *= 0.93
		CharacterAppearance.Build.MUSCULAR:
			chest *= 1.14; shoulders *= 1.14; waist *= 0.98
	var pad := _clothing_pad()
	var y0: float = g["Hips"].y - 0.075
	var y1: float = g["Neck"].y + 0.015
	_torso_y0 = y0
	_torso_y1 = y1
	var keys := [
		[y0, 0.13 * hipw, 0.10],
		[g["Hips"].y + 0.02, 0.148 * hipw, 0.112 * minf(belly, 1.25)],
		[g["Spine"].y + 0.04, 0.128 * waist, 0.098 * belly],
		[g["Chest"].y + 0.07, 0.148 * chest, 0.112 * chest * bust],
		[g["UpperChest"].y + 0.08, 0.162 * shoulders, 0.102 * chest],
		[g["Neck"].y - 0.02, 0.118 * shoulders, 0.08],
		[y1, 0.055, 0.05],
	]
	var profile: Array = []
	for k in keys:
		var t: float = (k[0] - y0) / (y1 - y0)
		profile.append(Vector3(t, k[1] + pad, k[2] + pad))
	var joints := [y0 - 1.0, g["Spine"].y, g["Chest"].y, g["UpperChest"].y, g["Neck"].y]
	var bone_ids := [B("Hips"), B("Spine"), B("Chest"), B("UpperChest"), B("Neck")]
	var weight_at := func(t: float) -> Array:
		return _chain_weight(lerpf(y0, y1, t), joints, bone_ids)
	var color_at := func(t: float, phi: float) -> Color:
		return _torso_color(lerpf(y0, y1, t), phi)
	# Hard color edges where clothing changes.
	var split_ts: Array = []
	for y in _torso_split_heights():
		split_ts.append((y - y0) / (y1 - y0))
	var split_phis: Array = []
	var open := _jacket_open_half()
	if open > 0.0:
		split_phis = [-open, open]
	mb.add_tube(Vector3(0, y0, 0), Vector3(0, y1, 0), profile, 16, color_at, weight_at, split_ts, split_phis, Vector3(0, 0, 1), 3)
	# Pelvis / crotch cover
	var crotch_col := a.pants_color if a.pants != 3 else a.pants_color
	mb.add_ellipsoid(Transform3D(Basis.IDENTITY, g["Hips"] + Vector3(0, -0.075, 0)),
		Vector3(0.13 * hipw, 0.08, 0.098), crotch_col, B("Hips"), {"lat_max": 10.0, "rings": 5})
	# Belt
	if a.belt and a.pants != 3:
		var by: float = g["Hips"].y + 0.035
		var r := SkinnedMeshBuilder._profile_at(profile, (by - y0) / (y1 - y0))
		var belt_col := Color(0.18, 0.12, 0.08)
		mb.add_tube(Vector3(0, by - 0.018, 0), Vector3(0, by + 0.018, 0),
			[Vector3(0, r.x + 0.006, r.y + 0.006), Vector3(1, r.x + 0.006, r.y + 0.006)], 16,
			func(_t: float, _p: float) -> Color: return belt_col,
			func(_t: float) -> Array: return [B("Hips"), -1, 0.0], [], [], Vector3(0, 0, 1), 1)
		mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, by, r.y + 0.01)), Vector3(0.04, 0.03, 0.01), Color(0.75, 0.70, 0.55), B("Hips"))
	# Shirt details
	var front_z := func(y: float) -> float:
		return SkinnedMeshBuilder._profile_at(profile, (y - y0) / (y1 - y0)).y
	if a.top == 2 or a.top == 5:   # collar + buttons
		var cy: float = g["Neck"].y - 0.005
		for side in [1.0, -1.0]:
			var basis := Basis(Vector3(0, 0, 1), deg_to_rad(28.0 * side)).rotated(Vector3(1, 0, 0), deg_to_rad(-20))
			mb.add_box(Transform3D(basis, Vector3(0.035 * side, cy, front_z.call(cy) - 0.005)), Vector3(0.05, 0.035, 0.012), a.top_color.lightened(0.08), B("UpperChest"))
		var n_buttons := 4 if a.top == 2 else 2
		for k in n_buttons:
			var yy: float = g["UpperChest"].y + 0.06 - k * 0.07
			if _jacket_open_half() > 0.0 or a.jacket == 0:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, Vector3(0, yy, front_z.call(yy) + 0.002)), Vector3(0.006, 0.006, 0.003), a.top_color.darkened(0.35), B("Chest"), {"rings": 3, "segs": 5})
	if a.top == 4:   # hoodie: hood bunched behind neck + pocket
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, g["Neck"] + Vector3(0, 0.0, -0.085)), Vector3(0.115, 0.065, 0.07), a.top_color.darkened(0.06), B("UpperChest"), {"rings": 6, "segs": 10})
		if a.jacket == 0:
			var py: float = g["Spine"].y + 0.04
			mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, py, front_z.call(py) + 0.004)), Vector3(0.16, 0.08, 0.012), a.top_color.darkened(0.08), B("Spine"))
	# Cargo pockets
	if a.pants == 4:
		for side in [1.0, -1.0]:
			pass


func _jacket_open_half() -> float:
	match a.jacket:
		1:
			return 0.36
		2:
			return 0.30
		3:
			return 0.0
		5:
			return 0.0
	return 0.0


func _torso_split_heights() -> Array:
	var out: Array = [_waist_line()]
	if a.jacket in [1, 2, 3, 4, 5]:
		out.append(_jacket_hem())
	if a.jacket == 4:
		out.append_array([g["Spine"].y - 0.01, g["Spine"].y + 0.025, g["Chest"].y + 0.03, g["Chest"].y + 0.065])
	return out


func _waist_line() -> float:
	return g["Hips"].y + 0.05


func _jacket_hem() -> float:
	return g["Hips"].y - 0.04 if a.jacket in [1, 2, 5] else g["Hips"].y + 0.03


func _torso_color(y: float, phi: float) -> Color:
	var shirt := a.top_color
	var base := shirt if y >= _waist_line() else a.pants_color
	if a.pants == 3 and y < _waist_line():
		base = a.pants_color   # skirt waistband
	if a.top == 3:   # tank top: bare upper shoulders/neck area handled by arms
		pass
	if a.jacket != 0 and y >= _jacket_hem():
		var open := _jacket_open_half()
		var show_shirt := open > 0.0 and absf(phi) < open
		if a.jacket == 3 or a.jacket == 4:
			show_shirt = absf(phi) < 0.06 and a.jacket == 3
		if not show_shirt:
			base = a.jacket_color
			if a.jacket == 4:
				var bands := [[g["Spine"].y - 0.01, g["Spine"].y + 0.025], [g["Chest"].y + 0.03, g["Chest"].y + 0.065]]
				for bnd in bands:
					if y >= bnd[0] and y <= bnd[1]:
						base = Color(0.86, 0.87, 0.82)
			if a.jacket == 5 and int((y - _torso_y0) * 28.0) % 2 == 0:
				base = a.jacket_color.darkened(0.08)
		elif y < _waist_line():
			base = a.pants_color
	return base


# ------------------------------------------------------------------ arms
func _build_arms() -> void:
	var thick := (1.0 + a.weight * 0.35) * (1.25 if a.build == CharacterAppearance.Build.MUSCULAR else 1.0) * (0.9 if a.build == CharacterAppearance.Build.THIN else 1.0)
	var pad := _clothing_pad()
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Left" else -1.0
		var ua: Vector3 = g[side + "UpperArm"]
		var la: Vector3 = g[side + "LowerArm"]
		var ha: Vector3 = g[side + "Hand"]
		var total := ua.distance_to(la) + la.distance_to(ha)
		var te := ua.distance_to(la) / total
		var sleeve_t := _sleeve_end()
		var sleeve_pad := pad if sleeve_t > 0.5 else 0.0
		var profile := [
			Vector3(0.0, 0.05 * thick + sleeve_pad, 0.046 * thick + sleeve_pad),
			Vector3(te * 0.5, 0.042 * thick + sleeve_pad, 0.04 * thick + sleeve_pad),
			Vector3(te, 0.034 * thick + sleeve_pad * 0.6, 0.033 * thick + sleeve_pad * 0.6),
			Vector3(te + (1.0 - te) * 0.35, 0.036 * thick, 0.032 * thick),
			Vector3(1.0, 0.026 * thick, 0.024 * thick),
		]
		var sleeve_col := a.jacket_color if _has_sleeved_jacket() else a.top_color
		var skin := a.skin_color
		var color_at := func(t: float, _phi: float) -> Color:
			return sleeve_col if t < sleeve_t else skin
		var joints := [-1.0, te]
		var ids := [B(side + "UpperArm"), B(side + "LowerArm")]
		var weight_at := func(t: float) -> Array:
			return _chain_weight(t, joints, ids)
		mb.add_tube(ua, ha + Vector3(0, -0.005, 0), profile, 11, color_at, weight_at, [sleeve_t], [], Vector3(0, 0, 1), 3)
		# Shoulder cap blends into the torso.
		var cap_col := sleeve_col if a.top != 3 or _has_sleeved_jacket() else skin
		if a.jacket in [3, 4] and a.top == 3:
			cap_col = a.jacket_color
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ua + Vector3(-0.012 * sgn, 0.0, 0)),
			Vector3(0.054 * thick + pad, 0.052 * thick + pad, 0.05 * thick + pad), cap_col, B(side + "UpperArm"),
			{"bone2": B("UpperChest"), "w2": 0.35, "rings": 7, "segs": 10})
		# Hand: mitten palm + thumb
		var hand_b := B(side + "Hand")
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ha + Vector3(0, -0.058, 0.004)), Vector3(0.026, 0.056, 0.019) * clampf(thick, 1.0, 1.2), skin, hand_b, {"rings": 6, "segs": 9})
		var tb := Basis(Vector3(0, 0, 1), deg_to_rad(-25.0 * sgn)).rotated(Vector3(1, 0, 0), deg_to_rad(-25))
		mb.add_ellipsoid(Transform3D(tb, ha + Vector3(-0.018 * sgn, -0.035, 0.02)), Vector3(0.011, 0.028, 0.011), skin, hand_b, {"rings": 4, "segs": 7})
		# Watch on left wrist
		if a.watch and side == "Left":
			var wy := ha + Vector3(0, 0.03, 0)
			mb.add_tube(wy + Vector3(0, -0.012, 0), wy + Vector3(0, 0.012, 0),
				[Vector3(0, 0.031 * thick, 0.029 * thick), Vector3(1, 0.031 * thick, 0.029 * thick)], 10,
				func(_t: float, _p: float) -> Color: return a.watch_color,
				func(_t: float) -> Array: return [B("LeftLowerArm"), -1, 0.0], [], [], Vector3(0, 0, 1), 1)
			mb.add_box(Transform3D(Basis.IDENTITY, wy + Vector3(0.03 * thick, 0, 0)), Vector3(0.008, 0.026, 0.022), Color(0.85, 0.85, 0.8), B("LeftLowerArm"))


func _sleeve_end() -> float:
	if _has_sleeved_jacket():
		return 0.97
	match a.top:
		0, 5:
			return 0.24
		3:
			return 0.0
		_:
			return 0.97


# ------------------------------------------------------------------ legs
func _build_legs() -> void:
	var thick := (1.0 + a.weight * 0.4) * (1.15 if a.build == CharacterAppearance.Build.MUSCULAR else 1.0) * (0.9 if a.build == CharacterAppearance.Build.THIN else 1.0)
	if a.gender == CharacterAppearance.Gender.FEMALE:
		thick *= 1.05
	var loose := 1.12 if a.pants == 4 else (1.06 if a.pants == 0 else 1.0)
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Left" else -1.0
		var ul: Vector3 = g[side + "UpperLeg"]
		var ll: Vector3 = g[side + "LowerLeg"]
		var ft: Vector3 = g[side + "Foot"]
		var total := ul.distance_to(ll) + ll.distance_to(ft)
		var tk := ul.distance_to(ll) / total
		var pants_end := _pants_end()
		var lp := loose if pants_end > 0.9 else 1.0
		var profile := [
			Vector3(0.0, 0.074 * thick * lp, 0.074 * thick * lp),
			Vector3(tk * 0.4, 0.064 * thick * lp, 0.066 * thick * lp),
			Vector3(tk, 0.047 * thick * lp, 0.05 * thick * lp),
			Vector3(tk + (1.0 - tk) * 0.25, 0.05 * thick * lp, 0.055 * thick * lp),
			Vector3(1.0, 0.036 * thick * lp, 0.038 * thick * lp),
		]
		var skin := a.skin_color
		var socks := a.socks_color
		var pc := a.pants_color
		var color_at := func(t: float, _phi: float) -> Color:
			if t < pants_end:
				return pc
			if t > 0.86:
				return socks
			return skin
		var joints := [-1.0, tk]
		var ids := [B(side + "UpperLeg"), B(side + "LowerLeg")]
		var weight_at := func(t: float) -> Array:
			if t < 0.06:
				return [B(side + "UpperLeg"), B("Hips"), 0.3 * (1.0 - t / 0.06)]
			return _chain_weight(t, joints, ids)
		var splits := [pants_end] if pants_end < 0.99 else []
		if pants_end < 0.86:
			splits.append(0.86)
		mb.add_tube(ul + Vector3(0, 0.03, 0), ft, profile, 11, color_at, weight_at, splits, [], Vector3(0, 0, 1), 3)
		if a.pants == 4:   # cargo pocket
			var pp := ul.lerp(ll, 0.45) + Vector3(0.068 * sgn * thick, 0, 0.0)
			mb.add_box(Transform3D(Basis.IDENTITY, pp), Vector3(0.014, 0.09, 0.08), a.pants_color.darkened(0.12), B(side + "UpperLeg"))
		_build_shoe(side, ft)
	if a.pants == 3:   # skirt
		var hy: float = g["Hips"].y
		mb.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, hy - 0.17, 0)), 0.15 * (1.0 + a.weight * 0.2), 0.235, 0.36, a.pants_color, B("Hips"), 16, false)


func _pants_end() -> float:
	match a.pants:
		2:
			return 0.42
		3:
			return 0.0
	return 1.0


func _build_shoe(side: String, ft: Vector3) -> void:
	var fb := B(side + "Foot")
	var col := a.shoes_color
	var flatten := func(u: Vector3) -> Vector3:
		return Vector3(u.x, maxf(u.y, -0.45), u.z)
	if a.shoes == 3:   # sandals: skin foot + sole
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ft + Vector3(0, -0.035, 0.045)), Vector3(0.042, 0.035, 0.105), a.skin_color, fb, {"deform": flatten, "rings": 6, "segs": 10})
		mb.add_box(Transform3D(Basis.IDENTITY, ft + Vector3(0, -0.062, 0.045)), Vector3(0.09, 0.016, 0.24), col, fb)
		return
	var size := Vector3(0.05, 0.048, 0.122)
	if a.shoes == 2:
		size = Vector3(0.044, 0.04, 0.13)
	mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ft + Vector3(0, -0.032, 0.048)), size, col, fb, {"deform": flatten, "rings": 7, "segs": 12})
	if a.shoes == 0:   # sneaker sole stripe
		mb.add_box(Transform3D(Basis.IDENTITY, ft + Vector3(0, -0.06, 0.048)), Vector3(0.096, 0.012, 0.236), Color(0.93, 0.93, 0.9), fb)
	if a.shoes == 1:   # boot shaft
		var ll := "Left" if side == "Left" else "Right"
		mb.add_cylinder(Transform3D(Basis.IDENTITY, ft + Vector3(0, 0.05, 0)), 0.05, 0.052, 0.13, col, B(ll + "LowerLeg"), 10, false)


# ------------------------------------------------------------------ neck & head
func _build_neck() -> void:
	var thick := 1.0 + a.weight * 0.3
	if a.build == CharacterAppearance.Build.MUSCULAR:
		thick *= 1.25
	var n0: Vector3 = g["Neck"] + Vector3(0, -0.02, 0)
	var n1: Vector3 = g["Head"] + Vector3(0, 0.07, 0)
	var joints := [-1.0, (g["Head"].y - n0.y) / (n1.y - n0.y)]
	var ids := [B("Neck"), B("Head")]
	var skin := a.skin_color
	mb.add_tube(n0, n1, [Vector3(0, 0.046 * thick, 0.044 * thick), Vector3(1, 0.04 * thick, 0.042 * thick)], 10,
		func(_t: float, _p: float) -> Color: return skin,
		func(t: float) -> Array: return _chain_weight(t, joints, ids), [], [], Vector3(0, 0, 1), 2)


func _head_deform(u: Vector3) -> Vector3:
	var taper := lerpf(a.jaw_width, 1.0, smoothstep(-0.95, 0.25, u.y))
	var zt := lerpf(0.9, 1.0, smoothstep(-0.95, 0.2, u.y))
	return Vector3(u.x * taper, u.y, u.z * zt)


func _build_head() -> void:
	var hb := B("Head")
	var skin := a.skin_color
	var deform := Callable(self, "_head_deform")
	mb.add_ellipsoid(Transform3D(Basis.IDENTITY, head_center), head_radii, skin, hb, {"deform": deform, "rings": 12, "segs": 18})
	# Ears
	for sgn in [1.0, -1.0]:
		var ep := head_center + Vector3(head_radii.x * 0.93 * sgn, -0.015, -0.005)
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep), Vector3(0.017, 0.031, 0.022), skin.darkened(0.05), hb, {"rings": 5, "segs": 8})
	# Nose
	var ns := a.nose_size
	var nose_col := skin.darkened(0.04)
	var np := head_center + Vector3(0, -0.04 * a.head_height, head_radii.z - 0.002)
	match a.nose_shape:
		0:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, np), Vector3(0.02, 0.022, 0.022) * ns, nose_col, hb, {"rings": 6, "segs": 9})
		1:
			mb.add_ellipsoid(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(20)), np + Vector3(0, -0.008, 0.004)), Vector3(0.016, 0.034, 0.03) * ns, nose_col, hb, {"rings": 6, "segs": 9})
		2:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, np + Vector3(0, -0.01, -0.004)), Vector3(0.015, 0.014, 0.017) * ns, nose_col, hb, {"rings": 5, "segs": 8})
		_:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, np), Vector3(0.03, 0.02, 0.02) * ns, nose_col, hb, {"rings": 6, "segs": 9})


func _build_face() -> void:
	var es := a.eye_size
	var old := a.age > 58
	var white := EYE_WHITE if not old else Color(0.96, 0.87, 0.85)
	var lid_col := a.skin_color.darkened(0.06)
	for side in ["L", "R"]:
		var eb := B("Eye" + side)
		var lb := B("Lid" + side)
		var ep: Vector3 = g["Eye" + side]
		var r := 0.047 * es
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep), Vector3(r, r, r * 0.95), white, eb, {"rings": 8, "segs": 12})
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep + Vector3(0, 0, r * 0.86)), Vector3(0.017, 0.017, 0.008) * es, a.eye_color.darkened(0.25), eb, {"rings": 4, "segs": 8})
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep + Vector3(0, 0, r * 0.97)), Vector3(0.0095, 0.0095, 0.005) * es, PUPIL, eb, {"rings": 3, "segs": 7})
		# Upper lid: upper half shell; FaceRig rotates it to open / close.
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep), Vector3(r * 1.07, r * 1.07, r * 1.03), lid_col, lb, {"lat_min": 0.0, "lat_max": 90.0, "rings": 5, "segs": 12})
		# Lower lid / eye bag (static, on head)
		var bag_col := lid_col.darkened(0.12 if old else 0.03)
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, ep), Vector3(r * 1.05, r * 1.05, r * 1.02), bag_col, B("Head"), {"lat_min": -90.0, "lat_max": -58.0, "rings": 3, "segs": 12})
		# Brow
		var sgn := 1.0 if side == "L" else -1.0
		var thick: float = [0.6, 1.0, 1.45, 1.9][clampi(a.brow_style, 0, 3)]
		var bb := Basis(Vector3(0, 1, 0), deg_to_rad(16.0 * sgn))
		mb.add_box(Transform3D(bb, g["Brow" + side]), Vector3(0.052, 0.0095 * thick, 0.012), a.brow_color, B("Brow" + side))
	# Mouth: centre bar (scaled open by FaceRig) + two corners that curve for emotions.
	var mw := a.mouth_width
	mb.add_ellipsoid(Transform3D(Basis.IDENTITY, g["Mouth"]), Vector3(0.016 * mw, 0.0042, 0.006), MOUTH, B("Mouth"), {"rings": 4, "segs": 8})
	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		mb.add_ellipsoid(Transform3D(Basis.IDENTITY, g["Mouth" + side] + Vector3(0.011 * mw * sgn, 0, 0)), Vector3(0.014 * mw, 0.0038, 0.0055), MOUTH, B("Mouth" + side), {"rings": 3, "segs": 7})
	# Age lines on the forehead
	if a.age > 50:
		for k in 3:
			var fy := head_center.y + 0.075 + k * 0.014
			mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, fy, head_center.z + head_radii.z * 0.86 - k * 0.006)), Vector3(0.07 - k * 0.008, 0.0025, 0.004), a.skin_color.darkened(0.25), B("Head"))


# ------------------------------------------------------------------ hair
func _hairline(front: float, back: float) -> Callable:
	return func(lon: float) -> float:
		return lerpf(front, back, (1.0 - cos(lon)) * 0.5)


func _hair_shell(scale: float, front: float, back: float, color: Color, extra := {}) -> void:
	var opts := {"deform": Callable(self, "_head_deform"), "rings": 7, "segs": 18, "lat_min_fn": _hairline(front, back), "lat_max": 90.0}
	opts.merge(extra, true)
	mb.add_ellipsoid(Transform3D(Basis.IDENTITY, head_center), head_radii * scale, color, B("Head"), opts)


func _build_hair() -> void:
	var hc := a.hair_color
	var hb := B("Head")
	var c := head_center
	var r := head_radii
	match a.hair_style:
		1:
			_hair_shell(1.055, 36.0, -30.0, hc)
		2:
			_hair_shell(1.02, 40.0, -32.0, hc.lerp(a.skin_color, 0.25))
		3:
			_hair_shell(1.05, 38.0, -28.0, hc)
			for k in 8:
				var ang := deg_to_rad(-60.0 + k * 17.0)
				var tilt := deg_to_rad(-25.0 + (k % 3) * 18.0)
				var bas := Basis(Vector3(1, 0, 0), tilt + 0.3).rotated(Vector3(0, 1, 0), ang * 0.35)
				var pos := c + Vector3(sin(ang) * r.x * 0.55, r.y * 0.86, cos(ang) * r.z * 0.25 - 0.01)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.035
				cone.height = 0.085
				cone.radial_segments = 6
				cone.rings = 1
				mb.add_primitive(cone, Transform3D(bas, pos), hc, hb)
		4:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.055, -0.025)), r * Vector3(1.38, 1.05, 1.3), hc, hb, {"rings": 9, "segs": 16, "lat_min": -20.0})
		5:
			_hair_shell(1.06, 30.0, -40.0, hc)
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c + Vector3(0, -0.13, -0.06)), Vector3(r.x * 1.05, 0.2, 0.075), hc, hb, {"rings": 7, "segs": 12})
			for sgn in [1.0, -1.0]:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c + Vector3(r.x * 0.88 * sgn, -0.07, -0.015)), Vector3(0.035, 0.15, 0.07), hc, hb, {"rings": 6, "segs": 8})
		6:
			_hair_shell(1.05, 33.0, -30.0, hc)
			mb.add_ellipsoid(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(25)), c + Vector3(0, -0.02, -r.z * 1.15)), Vector3(0.04, 0.11, 0.04), hc, hb, {"rings": 6, "segs": 8})
		7:
			_hair_shell(1.05, 33.0, -30.0, hc)
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.82, -r.z * 0.55)), Vector3(0.055, 0.05, 0.055), hc, hb, {"rings": 6, "segs": 10})
		8:
			for sgn in [1.0, -1.0]:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c + Vector3(r.x * 0.93 * sgn, 0.0, -0.035)), Vector3(0.032, 0.045, 0.06), hc, hb, {"rings": 5, "segs": 8})
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c), r * 1.04, hc, hb, {"deform": Callable(self, "_head_deform"), "lat_min": -28.0, "lat_max": 2.0, "lon_min": 110.0, "lon_max": 250.0, "rings": 3, "segs": 10})
		9:
			_hair_shell(1.05, 36.0, -30.0, hc)
			mb.add_ellipsoid(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-20)), c + Vector3(0, r.y * 0.8, r.z * 0.45)), Vector3(0.085, 0.05, 0.075), hc, hb, {"rings": 6, "segs": 10})
		10:
			var bob := func(lon: float) -> float:
				return lerpf(32.0, -34.0, smoothstep(0.25, 0.85, absf(lon) / PI))
			_hair_shell(1.075, 0.0, 0.0, hc, {"lat_min_fn": bob})
	if a.brow_style < 0:
		pass


func _build_beard() -> void:
	var hc := a.hair_color
	var hb := B("Head")
	var c := head_center
	var r := head_radii
	var mouth: Vector3 = g["Mouth"]
	match a.beard_style:
		1:   # goatee
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, -0.04, -0.008)), Vector3(0.028, 0.032, 0.02), hc, hb, {"rings": 6, "segs": 10})
			for sgn in [1.0, -1.0]:
				mb.add_box(Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(8.0 * sgn)), mouth + Vector3(0.034 * sgn, -0.014, -0.006)), Vector3(0.008, 0.04, 0.01), hc, hb)
			if a.mustache_style == 0:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, 0.014, 0.0)), Vector3(0.036, 0.008, 0.009), hc, hb, {"rings": 3, "segs": 8})
		2:   # full beard on the jaw
			var top := func(lon: float) -> float:
				return lerpf(-36.0, 2.0, smoothstep(0.3, 1.55, absf(lon)))
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c), r * 1.05, hc, hb, {"deform": Callable(self, "_head_deform"), "lat_min": -90.0, "lat_max_fn": top, "lon_min": -105.0, "lon_max": 105.0, "rings": 6, "segs": 14})
		3:   # chin strap
			var top2 := func(lon: float) -> float:
				return lerpf(-58.0, -12.0, smoothstep(0.4, 1.55, absf(lon)))
			var bot2 := func(lon: float) -> float:
				return lerpf(-72.0, -30.0, smoothstep(0.4, 1.55, absf(lon)))
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, c), r * 1.04, hc, hb, {"deform": Callable(self, "_head_deform"), "lat_min_fn": bot2, "lat_max_fn": top2, "lon_min": -100.0, "lon_max": 100.0, "rings": 3, "segs": 14})
		4:   # soul patch
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, -0.02, 0)), Vector3(0.01, 0.012, 0.006), hc, hb, {"rings": 3, "segs": 6})
	match a.mustache_style:
		1:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, 0.013, 0.002)), Vector3(0.032, 0.006, 0.008), hc, hb, {"rings": 3, "segs": 8})
		2:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, 0.015, 0.002)), Vector3(0.04, 0.012, 0.013), hc, hb, {"rings": 4, "segs": 10})
		3:
			mb.add_ellipsoid(Transform3D(Basis.IDENTITY, mouth + Vector3(0, 0.014, 0.002)), Vector3(0.038, 0.01, 0.012), hc, hb, {"rings": 4, "segs": 10})
			for sgn in [1.0, -1.0]:
				mb.add_ellipsoid(Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-55.0 * sgn)), mouth + Vector3(0.042 * sgn, 0.0, -0.004)), Vector3(0.006, 0.02, 0.006), hc, hb, {"rings": 3, "segs": 6})


func _build_hat() -> void:
	if a.hat == 0:
		return
	var hb := B("Head")
	var c := head_center
	var r := head_radii
	var col := a.hat_color
	match a.hat:
		1, 5:
			_hair_shell(1.1, 24.0, 6.0, col)
			var dir := 1.0 if a.hat == 1 else -1.0
			mb.add_ellipsoid(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-8.0 * dir)), c + Vector3(0, r.y * 0.42, r.z * 0.95 * dir)), Vector3(r.x * 0.82, 0.012, 0.085), col.darkened(0.12), hb, {"rings": 4, "segs": 14})
		2:
			_hair_shell(1.11, 28.0, -4.0, col, {"deform": func(u: Vector3) -> Vector3: return _head_deform(u) * Vector3(1, 1.1, 1)})
			mb.add_tube(c + Vector3(0, r.y * 0.25, 0), c + Vector3(0, r.y * 0.48, 0),
				[Vector3(0, r.x * 1.12, r.z * 1.12), Vector3(1, r.x * 1.1, r.z * 1.1)], 16,
				func(_t: float, _p: float) -> Color: return col.darkened(0.1),
				func(_t: float) -> Array: return [hb, -1, 0.0], [], [], Vector3(0, 0, 1), 1)
		3:
			mb.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.95, -0.005)), 0.1, 0.118, 0.13, col, hb, 14)
			mb.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.6, -0.005)), 0.2, 0.2, 0.012, col.darkened(0.08), hb, 18)
			mb.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.68, -0.005)), 0.12, 0.12, 0.025, col.darkened(0.45), hb, 14, false)
		4:
			mb.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.9, 0)), 0.1, 0.13, 0.11, col, hb, 14)
			mb.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, r.y * 0.55, 0)), 0.13, 0.19, 0.045, col.darkened(0.06), hb, 16, false)


func _build_glasses() -> void:
	if a.glasses == 0:
		return
	var hb := B("Head")
	var col := a.glasses_color
	var es := a.eye_size
	var face_z: float = g["EyeL"].z + 0.047 * es + 0.012
	for side in ["L", "R"]:
		var sgn := 1.0 if side == "L" else -1.0
		var ep: Vector3 = g["Eye" + side]
		var p := Vector3(ep.x, ep.y, face_z)
		var ring_basis := Basis(Vector3(1, 0, 0), PI * 0.5)
		match a.glasses:
			1:
				mb.add_torus(Transform3D(ring_basis, p), 0.034 * es, 0.04 * es, col, hb, 16, 4)
			2:
				for k in 4:
					var vertical := k % 2 == 0
					var off := Vector3(0, (0.032 if k == 0 else -0.032) * es, 0) if vertical else Vector3((0.04 if k == 1 else -0.04) * es, 0, 0)
					var size := Vector3(0.086 * es, 0.007, 0.007) if vertical else Vector3(0.007, 0.07 * es, 0.007)
					mb.add_box(Transform3D(Basis.IDENTITY, p + off), size, col, hb)
			3:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, p), Vector3(0.042 * es, 0.032 * es, 0.006), Color(0.05, 0.05, 0.06), hb, {"rings": 4, "segs": 12})
		# temple arm to the ear
		var ear := Vector3(head_radii.x * 0.95 * sgn, p.y, head_center.z - 0.01)
		var start := Vector3(p.x + 0.04 * es * sgn, p.y, p.z - 0.005)
		var mid := (start + ear) * 0.5
		var arm_basis := Basis.looking_at((ear - start).normalized(), Vector3.UP)
		mb.add_box(Transform3D(arm_basis, mid), Vector3(0.005, 0.006, start.distance_to(ear)), col, hb)
	mb.add_box(Transform3D(Basis.IDENTITY, Vector3(0, g["EyeL"].y + 0.004, face_z)), Vector3(maxf(0.02, (g["EyeL"].x - g["EyeR"].x) - 0.07 * es), 0.006, 0.006), col, hb)


func _build_accessories() -> void:
	var uc := B("UpperChest")
	match a.accessory:
		1:
			mb.add_torus(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(18)), g["Neck"] + Vector3(0, -0.03, 0.012)), 0.055, 0.062, a.accessory_color, uc, 14, 4)
		2:
			for sgn in [1.0, -1.0]:
				mb.add_ellipsoid(Transform3D(Basis.IDENTITY, head_center + Vector3(head_radii.x * 0.95 * sgn, -0.05, 0.0)), Vector3(0.008, 0.008, 0.008), a.accessory_color, B("Head"), {"rings": 3, "segs": 6})
		3:
			mb.add_torus(Transform3D(Basis.IDENTITY, g["Neck"] + Vector3(0, 0.01, 0)), 0.04, 0.085, a.accessory_color, B("Neck"), 14, 6)
			mb.add_box(Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(8)), g["UpperChest"] + Vector3(0.05, 0.02, 0.11)), Vector3(0.055, 0.2, 0.02), a.accessory_color.darkened(0.08), uc)
	match a.bag:
		1:
			var bp: Vector3 = g["Chest"] + Vector3(0, 0.07, -0.16 - _clothing_pad())
			mb.add_box(Transform3D(Basis.IDENTITY, bp), Vector3(0.25, 0.3, 0.11), a.bag_color, B("Chest"))
			mb.add_box(Transform3D(Basis.IDENTITY, bp + Vector3(0, -0.07, -0.06)), Vector3(0.19, 0.12, 0.03), a.bag_color.darkened(0.12), B("Chest"))
			for sgn in [1.0, -1.0]:
				var top: Vector3 = g["UpperChest"] + Vector3(0.075 * sgn, 0.09, 0.0)
				mb.add_box(Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(10)), top + Vector3(0, -0.06, 0.1)), Vector3(0.03, 0.2, 0.012), a.bag_color.darkened(0.25), uc)
		2:
			mb.add_box(Transform3D(Basis.IDENTITY, g["Hips"] + Vector3(-0.19, 0.02, 0.02)), Vector3(0.06, 0.16, 0.2), a.bag_color, B("Hips"))
			var strap_basis := Basis(Vector3(0, 0, 1), deg_to_rad(-38))
			mb.add_box(Transform3D(strap_basis, g["Chest"] + Vector3(-0.02, 0.07, 0.125 + _clothing_pad())), Vector3(0.03, 0.5, 0.01), a.bag_color.darkened(0.25), B("Chest"))
