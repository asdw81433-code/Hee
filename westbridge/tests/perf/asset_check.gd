## Debug: builds asset characters and prints triangle counts, bounds and shape-key sanity.
extends Node3D


func _tris(m: Mesh) -> int:
	return (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _aabb(m: Mesh) -> AABB:
	return m.get_aabb()


func _ready() -> void:
	print("ASSET available ", CharacterAssetLibrary.available(), " parts ", CharacterAssetLibrary.parts.size())
	for pn in ["Body", "Body_LOD1"]:
		var pd: Dictionary = CharacterAssetLibrary.parts[pn]
		var hist := {}
		if pd.has("mask"):
			for m in (pd.mask as PackedInt32Array):
				hist[m] = hist.get(m, 0) + 1
		print("  ", pn, " mask values ", hist.size(), " sample ", hist.keys().slice(0, 8), " has mask ", pd.has("mask"))
	var body: Dictionary = CharacterAssetLibrary.parts["Body"]
	for k in body.shapes.keys():
		var mx := 0.0
		for d in (body.shapes[k] as PackedVector3Array):
			mx = maxf(mx, d.length())
		print("  Body shape ", k, " max delta ", snappedf(mx, 0.001))
	var head: Dictionary = CharacterAssetLibrary.parts["HeadBase"]
	for k in head.shapes.keys():
		var mx := 0.0
		for d in (head.shapes[k] as PackedVector3Array):
			mx = maxf(mx, d.length())
		print("  Head shape ", k, " max delta ", snappedf(mx, 0.001))
	var rng0 := RandomNumberGenerator.new()
	rng0.seed = 0
	var ap0 := CharacterAppearance.new().randomize_look(rng0, -1, -1, "police")
	var line := ""
	for e in CharacterAssetBuilder.part_list(ap0):
		if CharacterAssetLibrary.parts.has(e[0]):
			line += "%s=%d " % [e[0], (CharacterAssetLibrary.parts[e[0]].i as PackedInt32Array).size() / 3]
	print("PARTS police: ", line)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for role in ["", "police", "worker", "office", "cafe"]:
		for seed in 4:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed * 31 + role.length()
			var ap := CharacterAppearance.new().randomize_look(rng, -1, -1, role)
			var sk := CharacterAssetBuilder.build_skeleton(ap.height, ap.eye_spacing)
			var full := CharacterAssetBuilder.build(ap, sk, ap.height, 0)
			var red := CharacterAssetBuilder.build(ap, sk, ap.height, 1)
			n += 2
			if seed < 2:
				print("CHAR role=%s seed=%d tris full %d reduced %d aabb %s" % [role, seed, _tris(full), _tris(red), _aabb(full)])
			sk.free()
	print("BUILD avg ms ", (Time.get_ticks_usec() - t0) / 1000.0 / n)
	get_tree().quit()
