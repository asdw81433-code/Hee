class_name SkinnedMeshBuilder
extends RefCounted
## Accumulates vertex-colored, bone-weighted geometry into a single ArrayMesh surface.
## One surface + one shared material = one draw call per character (mobile friendly).
##
## Winding convention (Godot): triangles are clockwise when seen from the front.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var indices := PackedInt32Array()
## Segment multiplier: 1.0 = full detail, ~0.55 = distant LOD.
var detail: float = 1.0


func vertex_count() -> int:
	return verts.size()


func _v(p: Vector3, n: Vector3, c: Color, b0: int, b1: int = -1, w1: float = 0.0) -> int:
	var i := verts.size()
	verts.append(p)
	normals.append(n)
	colors.append(c)
	if b1 < 0 or w1 <= 0.0:
		bones.append_array(PackedInt32Array([b0, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	else:
		bones.append_array(PackedInt32Array([b0, b1, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0 - w1, w1, 0.0, 0.0]))
	return i


## a = bottom-left, b = bottom-right, c = top-right, d = top-left (seen from outside)
func _quad(a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, d, c, a, c, b]))


func _segs(base: int) -> int:
	return maxi(4, int(round(base * detail)))


# --------------------------------------------------------------------------
## Lat/long ellipsoid (or a patch of it).
## opts: rings, segs, lat_min, lat_max (deg), lon_min, lon_max (deg, 0 = +Z front,
##       +90 = +X), lat_min_fn (Callable(lon_rad)->deg), lat_max_fn,
##       deform (Callable(Vector3 unit)->Vector3 unit), bone2, w2 (secondary bone weight),
##       color_fn (Callable(Vector3 unit)->Color)
func add_ellipsoid(xform: Transform3D, radii: Vector3, color: Color, bone: int, opts: Dictionary = {}) -> void:
	var rings: int = _segs(opts.get("rings", 9))
	var segs: int = _segs(opts.get("segs", 14))
	var lat_min: float = opts.get("lat_min", -90.0)
	var lat_max: float = opts.get("lat_max", 90.0)
	var lon_min: float = opts.get("lon_min", -180.0)
	var lon_max: float = opts.get("lon_max", 180.0)
	var lat_min_fn: Callable = opts.get("lat_min_fn", Callable())
	var lat_max_fn: Callable = opts.get("lat_max_fn", Callable())
	var deform: Callable = opts.get("deform", Callable())
	var color_fn: Callable = opts.get("color_fn", Callable())
	var bone2: int = opts.get("bone2", -1)
	var w2: float = opts.get("w2", 0.0)
	var base := verts.size()
	for j in segs + 1:
		var lon := deg_to_rad(lerpf(lon_min, lon_max, float(j) / segs))
		var la0 := lat_min
		var la1 := lat_max
		if lat_min_fn.is_valid():
			la0 = lat_min_fn.call(lon)
		if lat_max_fn.is_valid():
			la1 = lat_max_fn.call(lon)
		for i in rings + 1:
			var lat := deg_to_rad(lerpf(la0, la1, float(i) / rings))
			var u := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
			var n_unit := u
			if deform.is_valid():
				u = deform.call(u)
			var p := Vector3(u.x * radii.x, u.y * radii.y, u.z * radii.z)
			var n := Vector3(n_unit.x / radii.x, n_unit.y / radii.y, n_unit.z / radii.z).normalized()
			var c := color
			if color_fn.is_valid():
				c = color_fn.call(n_unit)
			_v(xform * p, (xform.basis * n).normalized(), c, bone, bone2, w2)
	var stride := rings + 1
	for j in segs:
		for i in rings:
			var a := base + j * stride + i
			var b := base + (j + 1) * stride + i
			_quad(a, b, b + 1, a + 1)


# --------------------------------------------------------------------------
## Tube along p0 -> p1 with an elliptical, tapered cross-section.
## profile: Array of Vector3(t, radius_side, radius_front), t in [0,1] ascending.
## color_at: Callable(t, phi) -> Color ; weight_at: Callable(t) -> [bone0, bone1, w1]
## split_ts / split_phis: parameter values where a hard color edge is needed.
## front: reference direction used for phi = 0.
func add_tube(p0: Vector3, p1: Vector3, profile: Array, base_segs: int, color_at: Callable,
		weight_at: Callable, split_ts: Array = [], split_phis: Array = [],
		front: Vector3 = Vector3.FORWARD * -1.0, rows_per_key: int = 2, phi_range: Vector2 = Vector2(-PI, PI)) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.0001:
		return
	var d := axis / length
	var f := (front - d * front.dot(d))
	if f.length() < 0.001:
		f = Vector3.RIGHT
	f = f.normalized()
	var s := d.cross(f).normalized()
	# --- rows (t) ---
	var ts: Array = []
	var key_count := profile.size()
	var row_total := maxi(2, (key_count - 1) * rows_per_key)
	row_total = maxi(2, int(round(row_total * clampf(detail, 0.5, 1.0))))
	for k in row_total + 1:
		var t := float(k) / row_total
		ts.append(Vector2(t, t))
	for st in split_ts:
		var stf: float = st
		if stf > 0.001 and stf < 0.999:
			ts.append(Vector2(stf, stf - 0.0005))
			ts.append(Vector2(stf, stf + 0.0005))
	ts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	# --- columns (phi) ---
	var segs := _segs(base_segs)
	var phis: Array = []
	for k in segs + 1:
		var ph := lerpf(phi_range.x, phi_range.y, float(k) / segs)
		phis.append(Vector2(ph, ph))
	for sp in split_phis:
		var spf: float = sp
		if spf > phi_range.x + 0.001 and spf < phi_range.y - 0.001:
			phis.append(Vector2(spf, spf - 0.0005))
			phis.append(Vector2(spf, spf + 0.0005))
	phis.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	var base := verts.size()
	for col in phis:
		var phi: float = col.x
		var phi_eval: float = col.y
		var sn := sin(phi)
		var cs := cos(phi)
		for row in ts:
			var t: float = row.x
			var t_eval: float = row.y
			var r := _profile_at(profile, t)
			var center := p0 + axis * t
			var p := center + s * (r.x * sn) + f * (r.y * cs)
			var n := (s * (sn / maxf(r.x, 0.001)) + f * (cs / maxf(r.y, 0.001))).normalized()
			var w: Array = weight_at.call(t)
			_v(p, n, color_at.call(t_eval, phi_eval), w[0], w[1], w[2])
	var stride := ts.size()
	for j in phis.size() - 1:
		for i in ts.size() - 1:
			var a := base + j * stride + i
			var b := base + (j + 1) * stride + i
			_quad(a, b, b + 1, a + 1)


static func _profile_at(profile: Array, t: float) -> Vector2:
	if t <= profile[0].x:
		return Vector2(profile[0].y, profile[0].z)
	for k in range(1, profile.size()):
		var a: Vector3 = profile[k - 1]
		var b: Vector3 = profile[k]
		if t <= b.x:
			var u := smoothstep(0.0, 1.0, (t - a.x) / maxf(b.x - a.x, 0.0001))
			return Vector2(lerpf(a.y, b.y, u), lerpf(a.z, b.z, u))
	var last: Vector3 = profile[profile.size() - 1]
	return Vector2(last.y, last.z)


# --------------------------------------------------------------------------
func add_box(xform: Transform3D, size: Vector3, color: Color, bone: int, bone2: int = -1, w2: float = 0.0) -> void:
	var h := size * 0.5
	# normal, u (right), v (up) with u x v = n
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for fc in faces:
		var n: Vector3 = fc[0]
		var u: Vector3 = fc[1]
		var v: Vector3 = fc[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var wn := (xform.basis * n).normalized()
		var a := _v(xform * (c - uu - vv), wn, color, bone, bone2, w2)
		var b := _v(xform * (c + uu - vv), wn, color, bone, bone2, w2)
		var cc := _v(xform * (c + uu + vv), wn, color, bone, bone2, w2)
		var d := _v(xform * (c - uu + vv), wn, color, bone, bone2, w2)
		_quad(a, b, cc, d)


## Appends Godot primitive mesh arrays (TorusMesh, CylinderMesh, ...).
func add_primitive(mesh: PrimitiveMesh, xform: Transform3D, color: Color, bone: int, bone2: int = -1, w2: float = 0.0) -> void:
	var arr := mesh.get_mesh_arrays()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base := verts.size()
	for k in pv.size():
		_v(xform * pv[k], (xform.basis * pn[k]).normalized(), color, bone, bone2, w2)
	for k in pi.size():
		indices.append(base + pi[k])


func add_cylinder(xform: Transform3D, r_top: float, r_bottom: float, height: float, color: Color, bone: int, base_segs: int = 12, caps: bool = true) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = height
	cm.radial_segments = _segs(base_segs)
	cm.rings = 1
	cm.cap_top = caps
	cm.cap_bottom = caps
	add_primitive(cm, xform, color, bone)


func add_torus(xform: Transform3D, inner: float, outer: float, color: Color, bone: int, rings: int = 16, sides: int = 6) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = _segs(rings)
	tm.ring_segments = maxi(3, _segs(sides))
	add_primitive(tm, xform, color, bone)


# --------------------------------------------------------------------------
func build_mesh(skinned: bool = true) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
