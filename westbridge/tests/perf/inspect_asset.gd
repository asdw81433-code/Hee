extends Node
## Prints the structure of the imported character asset (debug helper).
func _ready() -> void:
	var ps: PackedScene = load("res://assets/characters/westbridge_characters.glb")
	var root := ps.instantiate()
	var sk: Skeleton3D = root.find_child("*", true, false) as Skeleton3D
	for n in root.find_children("*", "Skeleton3D", true, false):
		sk = n
	print("skeleton ", sk.get_path() if sk.is_inside_tree() else sk.name, " bones ", sk.get_bone_count())
	for i in mini(sk.get_bone_count(), 40):
		print("  bone ", i, " ", sk.get_bone_name(i), " parent ", sk.get_bone_parent(i), " global ", sk.get_bone_global_rest(i).origin)
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		n += 1
		var m: Mesh = mi.mesh
		if n < 6 or mi.name in ["Body", "Head", "Hair_Short", "Top_TShirt"]:
			var arr := m.surface_get_arrays(0)
			print("mesh ", mi.name, " parent ", mi.get_parent().name, " xf ", mi.transform.origin, " verts ", (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " blend ", m.get_blend_shape_count(), " mode ", (m as ArrayMesh).blend_shape_mode if m is ArrayMesh else -1, " skin binds ", mi.skin.get_bind_count() if mi.skin else -1, " bones arr ", arr[Mesh.ARRAY_BONES] != null)
			if mi.skin:
				print("    bind0 ", mi.skin.get_bind_name(0), " bone ", mi.skin.get_bind_bone(0))
			for b in m.get_blend_shape_count():
				print("    shape ", m.get_blend_shape_name(b))
	print("mesh instances ", n)
	root.free()
	get_tree().quit()
