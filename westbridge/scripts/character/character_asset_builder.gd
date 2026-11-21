class_name CharacterAssetBuilder
extends RefCounted
## Builds one character mesh from the Blender part library:
##   appearance -> list of parts + colours -> bake body/head shape keys -> face tweaks
##   -> merge into ONE vertex-coloured skinned surface on the game skeleton.

const EYE_WHITE := Color(0.97, 0.96, 0.93)
const MOUTH := Color(0.2, 0.09, 0.08)
const EYE_RADIUS := 0.05   ## eyeball radius in the Blender asset
const HAIR := ["", "Hair_Short", "Hair_Buzz", "Hair_Spiky", "Hair_Afro", "Hair_Long", "Hair_Ponytail", "Hair_Bun", "Hair_SideTufts", "Hair_Quiff", "Hair_Bob"]
const BEARD := ["", "Beard_Goatee", "Beard_Full", "Beard_ChinStrap", "Beard_SoulPatch"]
const MUSTACHE := ["", "Mustache_Thin", "Mustache_Thick", "Mustache_Handlebar"]
const NOSE := ["Nose_Round", "Nose_Long", "Nose_Button", "Nose_Wide"]
const TOPS := ["Top_TShirt", "Top_LongSleeve", "Top_ButtonShirt", "Top_Tank", "Top_Hoodie", "Top_Polo", "Top_Sweater"]
const JACKETS := ["", "Jacket_Open", "Jacket_Blazer", "Jacket_Vest", "Jacket_Vest", "Jacket_Puffer", "Jacket_PoliceVest"]
const PANTS := ["Pants_Long", "Pants_Long", "Pants_Shorts", "Pants_Skirt", "Pants_Cargo"]
const SHOES := ["Shoes_Sneakers", "Shoes_Boots", "Shoes_Dress", "Shoes_Sandals"]
const HATS := ["", "Hat_Cap", "Hat_Beanie", "Hat_Brimmed", "Hat_Bucket", "Hat_Cap", "Hat_PoliceCap"]
const GLASSES := ["", "Glasses_Round", "Glasses_Square", "Glasses_Sun"]
const BAGS := ["", "Bag_Backpack", "Bag_Shoulder"]
const ACCESSORIES := ["", "Acc_Necklace", "Acc_Earrings", "Acc_Scarf"]
## Must match COVER_BITS in tools/blender/build_characters.py: a body triangle is
## dropped when its 3 vertices all carry the bit of a garment that is worn.
const COVER_BITS := {"Top_TShirt": 0, "Top_LongSleeve": 1, "Top_ButtonShirt": 2, "Top_Polo": 3, "Top_Tank": 4,
	"Top_Hoodie": 5, "Top_Sweater": 6, "Pants_Long": 7, "Pants_Shorts": 8, "Pants_Cargo": 9, "Socks": 10, "Shoes": 11}
const SMALL_PARTS := ["Iris_L", "Iris_R", "LowerLid_L", "LowerLid_R", "Detail_Buttons", "Text_PoliceVest", "Detail_CapBadge", "Watch", "Acc_Earrings"]


static func _pick(arr: Array, i: int) -> String:
	return arr[clampi(i, 0, arr.size() - 1)]


## [[part, color, {opts}], ...]
static func part_list(a: CharacterAppearance) -> Array:
	var L: Array = []
	var skin := a.skin_color
	var old := a.age > 58
	L.append(["Body", skin, {}])
	L.append(["HeadBase", skin, {}])
	L.append(["Ears", skin.darkened(0.05), {}])
	# Style: characters have no nose (nose_shape / nose_size are kept only for old saves).
	for s in ["L", "R"]:
		L.append(["EyeWhite_" + s, Color(0.96, 0.87, 0.85) if old else EYE_WHITE, {"eye": s}])
		L.append(["Iris_" + s, a.eye_color.darkened(0.25), {"eye": s}])
		L.append(["Pupil_" + s, Color(0.03, 0.03, 0.03), {"eye": s}])
		L.append(["Lid_" + s, skin.darkened(0.07), {"eye": s}])
		L.append(["LowerLid_" + s, skin.darkened(0.14 if old else 0.09), {"eye": s}])
		if a.brow_style >= 0:
			L.append(["Brow_" + s, a.brow_color, {"brow": [0.6, 1.0, 1.4, 1.8][clampi(a.brow_style, 0, 3)]}])
	L.append(["MouthCenter", MOUTH, {"mouth": true}])
	L.append(["MouthCorner_L", MOUTH, {"mouth": true}])
	L.append(["MouthCorner_R", MOUTH, {"mouth": true}])
	# Hair (squeezed under hats)
	var hair := _pick(HAIR, a.hair_style)
	var hat := _pick(HATS, a.hat)
	if hair != "":
		var opts := {}
		if hat != "":
			if hair in ["Hair_Afro", "Hair_Spiky", "Hair_Quiff"]:
				hair = "Hair_Short"
			if hair != "Hair_Buzz":   # the buzz cut is a thin scalp shell already
				opts["shrink"] = 0.92
		L.append([hair, a.hair_color, opts])
	if _pick(BEARD, a.beard_style) != "":
		L.append([_pick(BEARD, a.beard_style), a.hair_color, {}])
	if _pick(MUSTACHE, a.mustache_style) != "":
		L.append([_pick(MUSTACHE, a.mustache_style), a.hair_color, {}])
	# Clothing
	var top := _pick(TOPS, a.top)
	var jacket := _pick(JACKETS, a.jacket)
	L.append([top, a.top_color, {}])
	if top == "Top_ButtonShirt" or top == "Top_Polo":
		L.append(["Detail_Collar", a.top_color.lightened(0.08), {}])
	if top == "Top_ButtonShirt" and (jacket == "" or jacket in ["Jacket_Open", "Jacket_Blazer"]):
		L.append(["Detail_Buttons", a.top_color.darkened(0.35), {}])
	if top == "Top_Hoodie":
		L.append(["Detail_Hood", a.top_color.darkened(0.06), {}])
		if jacket == "":
			L.append(["Detail_HoodiePocket", a.top_color.darkened(0.08), {}])
	if jacket != "":
		var jc := a.jacket_color
		if a.jacket == 4:
			jc = Color(0.95, 0.68, 0.1)
		L.append([jacket, jc, {}])
		if a.jacket == 4:
			L.append(["Detail_HiVisStripes", Color(0.86, 0.87, 0.82), {}])
		if jacket == "Jacket_PoliceVest":
			L.append(["Text_PoliceVest", Color(0.95, 0.95, 0.95), {}])
			L.append(["Detail_Pouches", jc.darkened(0.25), {}])
	var pants := _pick(PANTS, a.pants)
	L.append([pants, a.pants_color, {}])
	if a.pants == 4:
		L.append(["Detail_CargoPockets", a.pants_color.darkened(0.12), {}])
	if a.pants == 2 or a.pants == 3:
		L.append(["Socks", a.socks_color, {}])
	if a.belt and pants != "Pants_Skirt":
		L.append(["Belt", Color(0.18, 0.12, 0.08), {}])
		L.append(["Detail_Buckle", Color(0.82, 0.72, 0.45), {}])
	var shoes := _pick(SHOES, a.shoes)
	L.append([shoes, a.shoes_color, {}])
	if shoes != "Shoes_Sandals":
		L.append([shoes + "_Sole", Color(0.93, 0.93, 0.9) if shoes == "Shoes_Sneakers" else a.shoes_color.darkened(0.45), {}])
	# Headwear & accessories
	if hat != "":
		L.append([hat, a.hat_color, {"backwards": a.hat == 5}])
		if hat == "Hat_PoliceCap":
			L.append(["Detail_CapBadge", Color(0.98, 0.8, 0.22), {}])
	if _pick(GLASSES, a.glasses) != "":
		L.append([_pick(GLASSES, a.glasses), a.glasses_color, {}])
	if _pick(BAGS, a.bag) != "":
		L.append([_pick(BAGS, a.bag), a.bag_color, {}])
	if _pick(ACCESSORIES, a.accessory) != "":
		L.append([_pick(ACCESSORIES, a.accessory), a.accessory_color, {}])
	if a.watch:
		L.append(["Watch", a.watch_color, {}])
	return L


static func body_shape_weights(a: CharacterAppearance) -> Dictionary:
	var heavy := clampf((a.weight - 0.5) / 0.5, 0.0, 1.0) + (0.35 if a.build == CharacterAppearance.Build.HEAVY else 0.0)
	var thin := clampf((0.35 - a.weight) / 0.35, 0.0, 1.0) + (0.5 if a.build == CharacterAppearance.Build.THIN else 0.0)
	return {
		"Female": 1.0 if a.gender == CharacterAppearance.Gender.FEMALE else 0.0,
		"Heavy": clampf(heavy, 0.0, 1.0),
		"Thin": clampf(thin, 0.0, 1.0),
		"Muscular": 1.0 if a.build == CharacterAppearance.Build.MUSCULAR else 0.0,
		"HeadWide": (a.head_width - 1.0) / 0.15,
		"HeadLong": (a.head_height - 1.0) / 0.15,
		"JawWide": maxf(0.0, (a.jaw_width - 0.84) / 0.21),
		"JawNarrow": maxf(0.0, (0.84 - a.jaw_width) / 0.16),
	}


static func eye_scale(a: CharacterAppearance) -> float:
	return 1.0 + (a.eye_size - 1.0) * 0.5


## Sideways shift factor of each eye (x * factor).
static func eye_offset(a: CharacterAppearance) -> float:
	return (a.eye_spacing - 1.0) * 0.5


static func worn_mask(list: Array) -> int:
	var m := 0
	for e in list:
		var n: String = e[0]
		if COVER_BITS.has(n):
			m |= 1 << int(COVER_BITS[n])
		elif n.begins_with("Shoes_") and not n.ends_with("_Sole") and n != "Shoes_Sandals":
			m |= 1 << int(COVER_BITS["Shoes"])
	return m


## Library part for a name at the given detail level (LOD1 parts are suffixed "_LOD1").
static func resolve_part(pname: String, detail: int) -> String:
	if detail > 0:
		if pname in SMALL_PARTS:
			return ""
		if CharacterAssetLibrary.parts.has(pname + "_LOD1"):
			return pname + "_LOD1"
	return pname if CharacterAssetLibrary.parts.has(pname) else ""


## Builds the merged mesh. `scale` = character height factor (skeleton is scaled the same).
## detail 0 = close-up parts, 1 = the Blender LOD1 set (distant NPCs).
static func build(a: CharacterAppearance, skeleton: Skeleton3D, scale: float, detail: int = 0) -> ArrayMesh:
	var lib := CharacterAssetLibrary
	var keys := body_shape_weights(a)
	var rest: Dictionary = lib.rest_positions
	var head_c: Vector3 = rest["Head"] + Vector3(0, 0.15, 0.005)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var bone_idx: Dictionary = {}
	for i in skeleton.get_bone_count():
		bone_idx[skeleton.get_bone_name(i)] = i
	var list := part_list(a)
	var worn := worn_mask(list)
	for entry in list:
		var pname := resolve_part(entry[0], detail)
		if pname == "":
			continue
		var p: Dictionary = lib.parts[pname]
		var col: Color = entry[1]
		var opts: Dictionary = entry[2]
		var pv: PackedVector3Array = p.v
		var pn: PackedVector3Array = p.n
		var pi: PackedInt32Array = p.i
		var shapes: Dictionary = p.shapes
		# Hidden-surface removal: drop body triangles that lie under worn clothes,
		# then keep only the vertices still referenced.
		var tris := PackedInt32Array()
		if p.has("mask") and worn != 0:
			var mk: PackedInt32Array = p.mask
			for t in range(0, pi.size(), 3):
				if (mk[pi[t]] & mk[pi[t + 1]] & mk[pi[t + 2]] & worn) == 0:
					tris.append(pi[t])
					tris.append(pi[t + 1])
					tris.append(pi[t + 2])
		else:
			tris = pi
		var remap := PackedInt32Array()
		remap.resize(pv.size())
		remap.fill(-1)
		for k in tris:
			remap[k] = 0
		# per-part local transform (face tweaks, hats)
		var xf := Transform3D.IDENTITY
		if opts.has("eye"):
			# Pivot on the front of the eyeball: big eyes grow back into the head
			# instead of bulging out of the face.
			# The modelled eyes already fill the face, so the creator's size/spacing
			# sliders act at half strength here.
			var ec: Vector3 = rest["Eye" + String(opts.eye)]
			xf = _scale_about(ec + Vector3(0, 0, EYE_RADIUS), Vector3.ONE * eye_scale(a)).translated(Vector3(ec.x * eye_offset(a), 0, 0))
		elif opts.has("scale"):
			xf = _scale_about(p.center, Vector3.ONE * float(opts.scale))
		elif opts.has("brow"):
			var pc: Vector3 = p.center
			xf = _scale_about(pc, Vector3(1.0, float(opts.brow), 1.0 + (float(opts.brow) - 1.0) * 0.3)).translated(Vector3(pc.x * eye_offset(a), 0, 0))
		elif opts.has("mouth"):
			xf = _scale_about(rest["Mouth"], Vector3(a.mouth_width, 1.0, 1.0))
		elif opts.has("shrink"):
			xf = _scale_about(head_c, Vector3.ONE * float(opts.shrink))
		if opts.get("backwards", false):
			xf = Transform3D(Basis(Vector3.UP, PI), head_c - Basis(Vector3.UP, PI) * head_c)
		var active_shapes: Array = []
		for kname in shapes.keys():
			var w: float = keys.get(kname, 0.0)
			if absf(w) > 0.001:
				active_shapes.append([shapes[kname], w])
		for i in pv.size():
			if remap[i] < 0:
				continue
			remap[i] = verts.size()
			var v := pv[i]
			for sh in active_shapes:
				v += (sh[0] as PackedVector3Array)[i] * float(sh[1])
			v = xf * v
			verts.append(v * scale)
			norms.append((xf.basis * pn[i]).normalized())
			cols.append(col)
			var infl: Array = p.b[i]
			var bi := PackedInt32Array([0, 0, 0, 0])
			var bw := PackedFloat32Array([0, 0, 0, 0])
			var total := 0.0
			for k in mini(infl.size(), 4):
				bi[k] = bone_idx.get(infl[k][0], 0)
				bw[k] = infl[k][1]
				total += bw[k]
			if total <= 0.0:
				bw[0] = 1.0
				bi[0] = bone_idx.get("Head", 0)
				total = 1.0
			for k in 4:
				bw[k] /= total
			bones.append_array(bi)
			weights.append_array(bw)
		for k in tris:
			indices.append(remap[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _scale_about(c: Vector3, s: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(s), c - Basis.from_scale(s) * c)


## Skeleton with identity-rotation rests at the asset's joint positions (scaled).
static func build_skeleton(scale: float, eye_spacing: float = 1.0) -> Skeleton3D:
	var lib := CharacterAssetLibrary
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var global_pos: Dictionary = {}
	for bn in lib.bone_order:
		var p: Vector3 = lib.rest_positions[bn] * scale
		if bn in ["EyeL", "EyeR", "LidL", "LidR", "BrowL", "BrowR"]:
			p.x *= 1.0 + (eye_spacing - 1.0) * 0.5
		global_pos[bn] = p
	for bn in lib.bone_order:
		var idx := sk.add_bone(bn)
		var parent: String = lib.bone_parents[bn]
		var local: Vector3 = global_pos[bn]
		if parent != "":
			sk.set_bone_parent(idx, sk.find_bone(parent))
			local -= global_pos[parent]
		sk.set_bone_rest(idx, Transform3D(Basis.IDENTITY, local))
	sk.reset_bone_poses()
	return sk
