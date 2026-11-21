class_name GeoBatch
extends RefCounted
## Collects static, vertex-colored geometry for one chunk of the city so the whole
## chunk renders as ONE draw call with the shared world shader.
## UV.x stores the surface type (see shaders/world.gdshader), UV.y a random value.

enum Kind { PAINT, BRICK, WOOD, TILES, ASPHALT, GRASS, GLASS, ROOF, SIGN, ROAD_PAINT, CONCRETE, DIRT, METAL, WATER, FOLIAGE }

static var _material: ShaderMaterial

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
## When false every call is ignored: the city's data pass runs the same generator
## code as the visual pass (same RNG sequence) without building any geometry.
var enabled: bool = true


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/world.gdshader")
	return _material


func is_empty() -> bool:
	return verts.is_empty()


func _v(p: Vector3, n: Vector3, c: Color, kind: int, rnd: float) -> int:
	var i := verts.size()
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(Vector2(kind, rnd))
	return i


func _quad(a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, d, c, a, c, b]))


## Oriented box. Faces listed in `skip` ("top","bottom","+x"...) are not generated.
func box(xform: Transform3D, size: Vector3, color: Color, kind: int = Kind.PAINT, rnd: float = 0.0, skip: Array = ["bottom"]) -> void:
	if not enabled:
		return
	var h := size * 0.5
	var faces := [
		["+z", Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		["-z", Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		["+x", Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		["-x", Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		["top", Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		["bottom", Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for f in faces:
		if f[0] in skip:
			continue
		var n: Vector3 = f[1]
		var u: Vector3 = f[2]
		var v: Vector3 = f[3]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var wn := (xform.basis * n).normalized()
		var a := _v(xform * (c - uu - vv), wn, color, kind, rnd)
		var b := _v(xform * (c + uu - vv), wn, color, kind, rnd)
		var cc := _v(xform * (c + uu + vv), wn, color, kind, rnd)
		var d := _v(xform * (c - uu + vv), wn, color, kind, rnd)
		_quad(a, b, cc, d)


## Axis-aligned convenience: box from center + size, optional Y rotation.
func abox(center: Vector3, size: Vector3, color: Color, kind: int = Kind.PAINT, yaw: float = 0.0, rnd: float = 0.0, skip: Array = ["bottom"]) -> void:
	box(Transform3D(Basis(Vector3.UP, yaw), center), size, color, kind, rnd, skip)


## Flat horizontal quad (y up).
func floor_quad(center: Vector3, size: Vector2, color: Color, kind: int, yaw: float = 0.0) -> void:
	if not enabled:
		return
	var b := Basis(Vector3.UP, yaw)
	var hx := b * Vector3(size.x * 0.5, 0, 0)
	var hz := b * Vector3(0, 0, size.y * 0.5)
	var a := _v(center - hx + hz, Vector3.UP, color, kind, 0.0)
	var bb := _v(center + hx + hz, Vector3.UP, color, kind, 0.0)
	var c := _v(center + hx - hz, Vector3.UP, color, kind, 0.0)
	var d := _v(center - hx - hz, Vector3.UP, color, kind, 0.0)
	_quad(a, bb, c, d)


## Quad from 4 world points: a = bottom-left, b = bottom-right, c = top-right, d = top-left
## (seen from the side the normal points to).
func quad_pts(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, kind: int, rnd: float = 0.0) -> void:
	if not enabled:
		return
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0 and absf(n.y) > 0.5:
		n = -n
	var ia := _v(a, n, color, kind, rnd)
	var ib := _v(b, n, color, kind, rnd)
	var ic := _v(c, n, color, kind, rnd)
	var id := _v(d, n, color, kind, rnd)
	_quad(ia, ib, ic, id)


func tri_pts(a: Vector3, b: Vector3, c: Vector3, color: Color, kind: int) -> void:
	if not enabled:
		return
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var ia := _v(a, n, color, kind, 0.0)
	var ib := _v(b, n, color, kind, 0.0)
	var ic := _v(c, n, color, kind, 0.0)
	indices.append_array(PackedInt32Array([ia, ic, ib]))


## Gable roof along local X, ridge height `rise`.
func gable_roof(xform: Transform3D, size: Vector3, rise: float, color: Color, gable_color: Color) -> void:
	if not enabled:
		return
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var p := [
		xform * Vector3(-hx, 0, hz), xform * Vector3(hx, 0, hz), xform * Vector3(hx, rise, 0), xform * Vector3(-hx, rise, 0),
		xform * Vector3(hx, 0, -hz), xform * Vector3(-hx, 0, -hz),
	]
	var n_front := (xform.basis * Vector3(0, hz, rise).normalized()).normalized()
	var n_back := (xform.basis * Vector3(0, hz, -rise).normalized()).normalized()
	n_back = Vector3(n_back.x, absf(n_back.y), n_back.z)
	var a := _v(p[0], n_front, color, Kind.ROOF, 0.0)
	var b := _v(p[1], n_front, color, Kind.ROOF, 0.0)
	var c := _v(p[2], n_front, color, Kind.ROOF, 0.0)
	var d := _v(p[3], n_front, color, Kind.ROOF, 0.0)
	_quad(a, b, c, d)
	var nb := (xform.basis * Vector3(0, hz, -rise)).normalized()
	a = _v(p[4], nb, color, Kind.ROOF, 0.0)
	b = _v(p[5], nb, color, Kind.ROOF, 0.0)
	c = _v(p[3], nb, color, Kind.ROOF, 0.0)
	d = _v(p[2], nb, color, Kind.ROOF, 0.0)
	_quad(a, b, c, d)
	# gable triangles
	var nr := (xform.basis * Vector3.RIGHT).normalized()
	var t0 := _v(p[1], nr, gable_color, Kind.WOOD, 0.0)
	var t1 := _v(p[4], nr, gable_color, Kind.WOOD, 0.0)
	var t2 := _v(p[2], nr, gable_color, Kind.WOOD, 0.0)
	indices.append_array(PackedInt32Array([t0, t2, t1]))
	var nl := -nr
	t0 = _v(p[5], nl, gable_color, Kind.WOOD, 0.0)
	t1 = _v(p[0], nl, gable_color, Kind.WOOD, 0.0)
	t2 = _v(p[3], nl, gable_color, Kind.WOOD, 0.0)
	indices.append_array(PackedInt32Array([t0, t2, t1]))


func primitive(mesh: PrimitiveMesh, xform: Transform3D, color: Color, kind: int = Kind.PAINT, rnd: float = 0.0) -> void:
	if not enabled:
		return
	var arr := mesh.get_mesh_arrays()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base := verts.size()
	for k in pv.size():
		_v(xform * pv[k], (xform.basis * pn[k]).normalized(), color, kind, rnd)
	for k in pi.size():
		indices.append(base + pi[k])


func cylinder(center: Vector3, r_top: float, r_bot: float, height: float, color: Color, kind: int = Kind.PAINT, segs: int = 10, xform_basis: Basis = Basis.IDENTITY) -> void:
	if not enabled:
		return
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	primitive(cm, Transform3D(xform_basis, center), color, kind)


func sphere(center: Vector3, radius: Vector3, color: Color, kind: int = Kind.PAINT, segs: int = 10) -> void:
	if not enabled:
		return
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	primitive(sm, Transform3D(Basis.from_scale(radius), center), color, kind)


func append(other: GeoBatch) -> void:
	if not enabled:
		return
	var base := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	colors.append_array(other.colors)
	uvs.append_array(other.uvs)
	for i in other.indices:
		indices.append(base + i)


func build_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func to_instance(name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = build_mesh()
	mi.material_override = material()
	return mi
