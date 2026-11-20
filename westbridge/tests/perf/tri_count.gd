## Prints triangle counts of every world part + one character (performance budget check).
extends Node3D
func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
func _ready() -> void:
	var cb := CityBuilder.new()
	cb.build(self, 1984)
	var groups := {}
	for n in cb.root.get_children():
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = n.multimesh
			groups[n.name] = _tris(mm.mesh) * mm.instance_count
		elif n is MeshInstance3D:
			groups[n.name] = _tris(n.mesh)
		else:
			for c in n.get_children():
				if c is MeshInstance3D:
					groups["blocks"] = groups.get("blocks", 0) + _tris(c.mesh)
	print("TRIS ", groups)
	var ap := CharacterAppearance.new()
	var sk := HumanoidDef.build_skeleton(ap.body_dims())
	print("TRIS character full ", _tris(CharacterMeshFactory.build(ap, sk, 1.0)), " reduced ", _tris(CharacterMeshFactory.build(ap, sk, 0.55)))
	get_tree().quit()
