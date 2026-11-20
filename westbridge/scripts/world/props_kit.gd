class_name PropsKit
extends RefCounted
## Street furniture and small props, batched into the block GeoBatch.
## Everything faces local +Z; `xf` places it in the world.

const K := GeoBatch.Kind


static func lamp(b: GeoBatch, cols: ColliderSet, pos: Vector3, yaw: float) -> Vector3:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.cylinder(xf * Vector3(0, 2.6, 0), 0.07, 0.1, 5.2, Color(0.22, 0.24, 0.26), K.METAL, 8)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.1, 0.55)), Vector3(0.1, 0.1, 1.2), Color(0.22, 0.24, 0.26), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 1.1)), Vector3(0.45, 0.14, 0.6), Color(0.2, 0.2, 0.22), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.92, 1.1)), Vector3(0.36, 0.04, 0.5), Color(1.0, 0.86, 0.6), K.SIGN)
	cols.add_box(pos + Vector3(0, 2.6, 0), Vector3(0.2, 5.2, 0.2))
	return xf * Vector3(0, 4.8, 1.1)


static func bench(b: GeoBatch, cols: ColliderSet, xf: Transform3D) -> void:
	var wood := Color(0.55, 0.36, 0.2)
	var iron := Color(0.15, 0.16, 0.17)
	for k in 3:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -0.15 + k * 0.15)), Vector3(1.8, 0.05, 0.12), wood, K.WOOD)
	for k in 2:
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.75 + k * 0.17, -0.27)), Vector3(1.8, 0.1, 0.04), wood, K.WOOD)
	for sx in [-0.8, 0.8]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.22, 0)), Vector3(0.06, 0.45, 0.5), iron, K.METAL)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.7, -0.27)), Vector3(0.06, 0.55, 0.06), iron, K.METAL)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(1.8, 0.5, 0.5))


static func trash_bin(b: GeoBatch, cols: ColliderSet, pos: Vector3, color: Color) -> void:
	b.cylinder(pos + Vector3(0, 0.45, 0), 0.3, 0.27, 0.9, color, K.METAL, 10)
	b.cylinder(pos + Vector3(0, 0.92, 0), 0.32, 0.32, 0.06, color.darkened(0.3), K.METAL, 10)
	cols.add_box(pos + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6))


static func dumpster(b: GeoBatch, cols: ColliderSet, xf: Transform3D, color: Color) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.65, 0)), Vector3(1.9, 1.2, 1.1), color, K.METAL)
	b.box(xf * Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 1.3, 0.05)), Vector3(1.95, 0.08, 1.2), color.darkened(0.25), K.METAL)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.65, 0)), Vector3(1.9, 1.3, 1.1))


static func hydrant(b: GeoBatch, pos: Vector3) -> void:
	var red := Color(0.8, 0.15, 0.12)
	b.cylinder(pos + Vector3(0, 0.3, 0), 0.12, 0.14, 0.6, red, K.METAL, 8)
	b.sphere(pos + Vector3(0, 0.62, 0), Vector3(0.13, 0.1, 0.13), red, K.METAL, 8)
	b.box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.38, 0)), Vector3(0.36, 0.08, 0.08), red, K.METAL)


static func mailbox(b: GeoBatch, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(0.08, 1.0, 0.08), Color(0.35, 0.25, 0.15), K.WOOD)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)), Vector3(0.22, 0.24, 0.45), Color(0.2, 0.3, 0.55), K.METAL)


static func power_pole(b: GeoBatch, cols: ColliderSet, pos: Vector3, yaw: float) -> Vector3:
	var wood := Color(0.36, 0.26, 0.18)
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.cylinder(pos + Vector3(0, 4.5, 0), 0.11, 0.15, 9.0, wood, K.WOOD, 7)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 8.4, 0)), Vector3(2.2, 0.14, 0.14), wood, K.WOOD)
	for sx in [-0.9, 0.0, 0.9]:
		b.cylinder(xf * Vector3(sx, 8.55, 0), 0.04, 0.05, 0.16, Color(0.75, 0.78, 0.8), K.PAINT, 6)
	b.cylinder(xf * Vector3(0.3, 7.4, 0), 0.22, 0.22, 0.6, Color(0.5, 0.52, 0.55), K.METAL, 8)
	cols.add_box(pos + Vector3(0, 4.5, 0), Vector3(0.3, 9.0, 0.3))
	return pos + Vector3(0, 8.6, 0)


## Sagging wire between two pole tops (approximated by segments).
static func wire(b: GeoBatch, a: Vector3, c: Vector3, offsets: Array) -> void:
	var dir := (c - a)
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var side := flat.cross(Vector3.UP).normalized()
	for off in offsets:
		var o: Vector3 = side * float(off)
		var segs := 6
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var p0 := a.lerp(c, t0) + o - Vector3(0, sin(t0 * PI) * 0.7, 0)
			var p1 := a.lerp(c, t1) + o - Vector3(0, sin(t1 * PI) * 0.7, 0)
			var mid := (p0 + p1) * 0.5
			var length := p0.distance_to(p1)
			if length < 0.01:
				continue
			var basis := Basis.looking_at((p1 - p0).normalized(), Vector3.UP)
			b.box(Transform3D(basis, mid), Vector3(0.025, 0.025, length), Color(0.08, 0.08, 0.08), K.PAINT, 0.0, ["bottom", "top"])


static func bus_stop(b: GeoBatch, cols: ColliderSet, xf: Transform3D, ad_color: Color) -> void:
	var frame := Color(0.2, 0.22, 0.25)
	for sx in [-1.6, 1.6]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 1.25, -0.6)), Vector3(0.08, 2.5, 0.08), frame, K.METAL)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 1.25, 0.6)), Vector3(0.08, 2.5, 0.08), frame, K.METAL)
	b.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(0, 2.55, 0)), Vector3(3.6, 0.1, 1.6), frame, K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.62)), Vector3(3.1, 1.9, 0.04), Color(0.6, 0.75, 0.8), K.GLASS)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(1.6, 1.4, 0)), Vector3(0.06, 1.7, 1.1), ad_color, K.SIGN)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.3, 0.45, -0.35)), Vector3(2.0, 0.06, 0.4), Color(0.5, 0.33, 0.2), K.WOOD)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.62)), Vector3(3.2, 2.6, 0.1))
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(1.6, 1.3, 0)), Vector3(0.1, 2.6, 1.2))


static func tree_round(b: GeoBatch, cols: ColliderSet, pos: Vector3, scale: float, leaf: Color) -> void:
	b.cylinder(pos + Vector3(0, 1.3 * scale, 0), 0.12 * scale, 0.18 * scale, 2.6 * scale, Color(0.36, 0.25, 0.16), K.WOOD, 7)
	b.sphere(pos + Vector3(0, 3.4 * scale, 0), Vector3(1.6, 1.4, 1.6) * scale, leaf, K.FOLIAGE, 9)
	b.sphere(pos + Vector3(0.6, 2.9, 0.4) * scale, Vector3(1.0, 0.9, 1.0) * scale, leaf.darkened(0.08), K.FOLIAGE, 7)
	cols.add_box(pos + Vector3(0, 1.3 * scale, 0), Vector3(0.35, 2.6, 0.35) * scale)


static func planter(b: GeoBatch, cols: ColliderSet, pos: Vector3, flower: Color) -> void:
	b.box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.3, 0)), Vector3(1.2, 0.6, 1.2), Color(0.55, 0.53, 0.5), K.CONCRETE)
	b.sphere(pos + Vector3(0, 0.75, 0), Vector3(0.55, 0.3, 0.55), Color(0.25, 0.5, 0.22), K.FOLIAGE, 8)
	for k in 5:
		var a := k * 1.25
		b.sphere(pos + Vector3(cos(a) * 0.3, 0.92, sin(a) * 0.3), Vector3(0.1, 0.08, 0.1), flower, K.PAINT, 6)
	cols.add_box(pos + Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2))


static func picket_fence(b: GeoBatch, cols: ColliderSet, a: Vector3, c: Vector3, color: Color, gap_center: float = -1.0, gap_width: float = 1.6) -> void:
	var length := a.distance_to(c)
	var dir := (c - a) / maxf(length, 0.001)
	var yaw := atan2(dir.x, dir.z) + PI * 0.5
	var n := int(length / 0.18)
	for k in n:
		var t := (k + 0.5) * 0.18
		if gap_center >= 0.0 and absf(t - gap_center) < gap_width * 0.5:
			continue
		var p := a + dir * t
		b.box(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.45, 0)), Vector3(0.08, 0.9, 0.03), color, K.PAINT, 0.0, ["bottom", "top"])
	for h in [0.3, 0.7]:
		var segs: Array = [[0.0, length]]
		if gap_center >= 0.0:
			segs = [[0.0, gap_center - gap_width * 0.5], [gap_center + gap_width * 0.5, length]]
		for s in segs:
			if s[1] - s[0] < 0.05:
				continue
			var mid: Vector3 = a + dir * ((s[0] + s[1]) * 0.5)
			b.box(Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, h, -0.03)), Vector3(s[1] - s[0], 0.07, 0.03), color, K.PAINT)
			if h == 0.3:
				cols.add(Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 0.5, 0)), Vector3(s[1] - s[0], 1.0, 0.1))


## Decorative parked car (drivable cars arrive in Phase 5).
static func car(b: GeoBatch, cols: ColliderSet, xf: Transform3D, color: Color, kind: int = 0) -> void:
	var glass := Color(0.25, 0.3, 0.36)
	var length := 4.3 if kind != 1 else 5.0
	var height := 0.75 if kind != 2 else 0.85
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)), Vector3(1.85, height, length), color, K.METAL)
	if kind == 1:   # pickup: cab + bed
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.32, 0.55)), Vector3(1.75, 0.7, 1.7), color, K.METAL)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.32, 0.55)), Vector3(1.78, 0.45, 1.5), glass, K.GLASS)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.05, -1.4)), Vector3(1.75, 0.2, 2.0), color.darkened(0.3), K.METAL)
	else:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.28, -0.15)), Vector3(1.7, 0.62, 2.3), color, K.METAL)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.15)), Vector3(1.73, 0.44, 2.1), glass, K.GLASS)
	for sx in [-0.95, 0.95]:
		for sz in [-length * 0.32, length * 0.32]:
			b.cylinder(xf * Vector3(sx * 0.98, 0.36, sz), 0.36, 0.36, 0.28, Color(0.08, 0.08, 0.09), K.PAINT, 10, xf.basis * Basis(Vector3.BACK, PI * 0.5))
	for sx in [-0.65, 0.65]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.75, length * 0.5)), Vector3(0.35, 0.14, 0.04), Color(1, 0.95, 0.8), K.SIGN)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.78, -length * 0.5)), Vector3(0.32, 0.12, 0.04), Color(0.8, 0.1, 0.08), K.SIGN)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), Vector3(1.9, 1.5, length))


static func traffic_light(b: GeoBatch, cols: ColliderSet, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var dark := Color(0.14, 0.15, 0.16)
	b.cylinder(pos + Vector3(0, 2.0, 0), 0.07, 0.09, 4.0, dark, K.METAL, 8)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0.15)), Vector3(0.35, 1.0, 0.3), dark, K.METAL)
	var lights := [Color(0.9, 0.15, 0.1), Color(0.95, 0.7, 0.1), Color(0.2, 0.85, 0.3)]
	for k in 3:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.92 - k * 0.3, 0.31)), Vector3(0.18, 0.18, 0.03), lights[k] * (1.0 if k != 1 else 0.6), K.SIGN)
	cols.add_box(pos + Vector3(0, 2.0, 0), Vector3(0.2, 4.0, 0.2))


static func stop_sign(b: GeoBatch, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	b.cylinder(pos + Vector3(0, 1.2, 0), 0.04, 0.04, 2.4, Color(0.6, 0.62, 0.64), K.METAL, 6)
	b.cylinder(xf * Vector3(0, 2.4, 0.05), 0.33, 0.33, 0.04, Color(0.8, 0.12, 0.1), K.PAINT, 8, xf.basis * Basis(Vector3.RIGHT, PI * 0.5))


static func crate_stack(b: GeoBatch, cols: ColliderSet, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(1, 3)
	for k in n:
		var s := rng.randf_range(0.45, 0.7)
		b.abox(pos + Vector3(rng.randf_range(-0.15, 0.15), s * 0.5 + k * 0.6, rng.randf_range(-0.15, 0.15)), Vector3(s, s, s), Color(0.62, 0.45, 0.25), K.WOOD, rng.randf() * 0.4)
	cols.add_box(pos + Vector3(0, n * 0.3, 0), Vector3(0.7, n * 0.6, 0.7))


static func pine_tree_mesh() -> ArrayMesh:
	var b := GeoBatch.new()
	b.cylinder(Vector3(0, 1.0, 0), 0.14, 0.22, 2.0, Color(0.33, 0.23, 0.15), K.WOOD, 6)
	var greens := [Color(0.16, 0.34, 0.2), Color(0.19, 0.38, 0.22), Color(0.22, 0.43, 0.25)]
	for k in 4:
		var y := 1.6 + k * 1.55
		var r := 2.2 - k * 0.45
		b.cylinder(Vector3(0, y + 1.0, 0), 0.0, r, 2.6, greens[mini(k, 2)], K.FOLIAGE, 9)
	return b.build_mesh()


static func round_tree_mesh() -> ArrayMesh:
	var b := GeoBatch.new()
	b.cylinder(Vector3(0, 1.3, 0), 0.12, 0.18, 2.6, Color(0.36, 0.25, 0.16), K.WOOD, 6)
	b.sphere(Vector3(0, 3.4, 0), Vector3(1.6, 1.4, 1.6), Color(0.3, 0.5, 0.22), K.FOLIAGE, 9)
	b.sphere(Vector3(0.6, 2.9, 0.4), Vector3(1.0, 0.9, 1.0), Color(0.27, 0.46, 0.2), K.FOLIAGE, 7)
	return b.build_mesh()
