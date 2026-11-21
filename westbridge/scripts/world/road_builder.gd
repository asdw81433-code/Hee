class_name RoadBuilder
extends RefCounted
## Road surfaces for the whole world grid, built per cell so they stream with it.
## A cell (gi, gj) owns its west edge vedge(gi, gj), its north edge hedge(gi, gj) and
## its north-west intersection (gi, gj); the last column/row also owns the far edges.
## Roads follow the terrain (CityMap.road_height_at); bridges stay level and get
## their own collision; Route 9 is built by the corridor cells (gj = -1).

const K := GeoBatch.Kind
const ASPHALT := Color(0.24, 0.25, 0.27)
const DIRT := Color(0.47, 0.39, 0.29)
const WHITE := Color(0.92, 0.92, 0.88)
const YELLOW := Color(0.95, 0.75, 0.2)
const STEP := 6.0


static func rh(x: float, z: float) -> float:
	return CityMap.road_height_at(x, z)


## Strip from p0 along unit dir (x or z axis) of length len and width w, following the road height.
static func strip(b: GeoBatch, p0: Vector3, dir: Vector3, length: float, w: float, col: Color, kind: int, lift: float, side_off: float = 0.0) -> void:
	if length <= 0.01:
		return
	var n := Vector3(-dir.z, 0, dir.x)
	var pieces := maxi(1, int(ceil(length / STEP)))
	for k in pieces:
		var a := p0 + dir * (length * k / pieces) + n * side_off
		var c := p0 + dir * (length * (k + 1) / pieces) + n * side_off
		var a0 := a - n * w * 0.5
		var a1 := a + n * w * 0.5
		var c0 := c - n * w * 0.5
		var c1 := c + n * w * 0.5
		a0.y = rh(a0.x, a0.z) + lift
		a1.y = rh(a1.x, a1.z) + lift
		c0.y = rh(c0.x, c0.z) + lift
		c1.y = rh(c1.x, c1.z) + lift
		b.quad_pts(a1, c1, c0, a0, col, kind)


## Kind of the 4 edges around intersection (a, b): [north, south, west, east].
static func incident(a: int, b: int) -> Array:
	return [CityMap.vedge(a, b - 1), CityMap.vedge(a, b), CityMap.hedge(a - 1, b), CityMap.hedge(a, b)]


static func intersection_width(a: int, b: int) -> float:
	var w := 0.0
	for k in incident(a, b):
		if k != "":
			w = maxf(w, CityMap.road_width(k))
	return w


## Visual road geometry owned by cell (gi, gj).
static func build_cell(b: GeoBatch, cols: ColliderSet, gi: int, gj: int, lamps: Array) -> void:
	var edges: Array = [["v", gi, gj], ["h", gi, gj]]
	var corners: Array = [Vector2i(gi, gj)]
	if gi == CityMap.GI_MAX:
		edges.append(["v", gi + 1, gj])
		corners.append(Vector2i(gi + 1, gj))
	if gj == CityMap.GJ_MAX:
		edges.append(["h", gi, gj + 1])
		corners.append(Vector2i(gi, gj + 1))
	if gi == CityMap.GI_MAX and gj == CityMap.GJ_MAX:
		corners.append(Vector2i(gi + 1, gj + 1))
	for e in edges:
		_edge(b, cols, e[0], e[1], e[2])
	for c in corners:
		_intersection(b, c.x, c.y)
	if CityMap.cell_type(gi, gj) == "highway":
		_highway_section(b, cols, gi, lamps)


static func _edge(b: GeoBatch, cols: ColliderSet, axis: String, a: int, bb: int) -> void:
	var kind: String = CityMap.vedge(a, bb) if axis == "v" else CityMap.hedge(a, bb)
	if kind == "":
		return
	var w := CityMap.road_width(kind)
	var p0: Vector3
	var dir: Vector3
	var iw0: float
	var iw1: float
	if axis == "v":
		p0 = CityMap.intersection(a, bb)
		dir = Vector3(0, 0, 1)
		iw0 = intersection_width(a, bb)
		iw1 = intersection_width(a, bb + 1)
	else:
		p0 = CityMap.intersection(a, bb)
		dir = Vector3(1, 0, 0)
		iw0 = intersection_width(a, bb)
		iw1 = intersection_width(a + 1, bb)
	var start := p0 + dir * iw0 * 0.5
	var length := CityMap.PITCH - (iw0 + iw1) * 0.5
	if kind == "bridge":
		_bridge(b, cols, start, dir, length, w)
		return
	var col := DIRT if kind == "dirt" else ASPHALT
	strip(b, start, dir, length, w, col, K.DIRT if kind == "dirt" else K.ASPHALT, 0.0)
	if kind == "dirt":
		return
	# Markings: centre dashes, edge lines, crosswalks at both ends, a manhole.
	var d := 2.2
	while d < length - 3.7:
		strip(b, start + dir * d, dir, 2.5, 0.15, YELLOW, K.ROAD_PAINT, 0.012)
		d += 5.0
	for side in [-1.0, 1.0]:
		strip(b, start + dir * 2.2, dir, length - 4.4, 0.12, WHITE, K.ROAD_PAINT, 0.012, side * (w * 0.5 - 0.35))
	for end in [0.0, 1.0]:
		var at: Vector3 = start + dir * (1.1 if end == 0.0 else length - 1.1)
		for k in 6:
			var off := -w * 0.5 + 1.0 + k * 1.6
			strip(b, at - dir * 1.0, dir, 2.0, 0.8, WHITE, K.ROAD_PAINT, 0.013, off)
	var mh := start + dir * 6.0 + Vector3(-dir.z, 0, dir.x) * 2.0
	b.cylinder(Vector3(mh.x, rh(mh.x, mh.z) + 0.005, mh.z), 0.4, 0.4, 0.01, Color(0.2, 0.2, 0.21), K.METAL, 10)


static func _intersection(b: GeoBatch, a: int, bb: int) -> void:
	var w := intersection_width(a, bb)
	if w <= 0.0:
		return
	var dirt := true
	for k in incident(a, bb):
		if k != "" and k != "dirt":
			dirt = false
	var p := CityMap.intersection(a, bb)
	# Intersections next to a bridge stay at the bridge deck height.
	strip(b, p - Vector3(0, 0, w * 0.5), Vector3(0, 0, 1), w, w, DIRT if dirt else ASPHALT, K.DIRT if dirt else K.ASPHALT, 0.0)


static func _bridge(b: GeoBatch, cols: ColliderSet, start: Vector3, dir: Vector3, length: float, w: float) -> void:
	var n := Vector3(-dir.z, 0, dir.x)
	var y := maxf(rh(start.x, start.z), 0.0)
	var mid := start + dir * length * 0.5
	var deck := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(mid.x, y - 0.3, mid.z))
	b.box(deck, Vector3(w + 1.6, 0.6, length), Color(0.62, 0.6, 0.57), K.CONCRETE, 0.0, [])
	cols.add(deck, Vector3(w + 1.6, 0.6, length))
	strip(b, start, dir, length, w, ASPHALT, K.ASPHALT, 0.01)
	var d := 2.0
	while d < length - 3.0:
		strip(b, start + dir * d, dir, 2.5, 0.15, YELLOW, K.ROAD_PAINT, 0.02)
		d += 5.0
	for side in [-1.0, 1.0]:
		var rail := Transform3D(deck.basis, Vector3(mid.x, y + 0.55, mid.z) + n * side * (w * 0.5 + 0.55))
		b.box(rail, Vector3(0.35, 1.1, length), Color(0.75, 0.74, 0.7), K.CONCRETE)
		cols.add(rail, Vector3(0.35, 1.1, length))
	var k := 4.0
	while k < length:
		var pp := start + dir * k
		b.abox(Vector3(pp.x, CityMap.RIVER_LEVEL - 2.5, pp.z), Vector3(1.6, y + 2.2 - CityMap.RIVER_LEVEL + 0.3, w * 0.8), Color(0.55, 0.54, 0.5), K.CONCRETE, atan2(dir.z, dir.x) + PI * 0.5)
		k += 12.0


## Route 9: 4 lanes + shoulders through the corridor cell, a level bridge over the river.
static func _highway_section(b: GeoBatch, cols: ColliderSet, gi: int, lamps: Array) -> void:
	var cx := CityMap.block_center(gi, -1).x
	var z := CityMap.HIGHWAY_Z
	var hw := CityMap.HIGHWAY_W
	var x0 := cx - CityMap.PITCH * 0.5
	var start := Vector3(x0, 0, z)
	var dir := Vector3(1, 0, 0)
	var length := CityMap.PITCH
	var river := CityMap.cell_type(gi, -1) == "river" or CityMap.cell_kind(gi, -1) == "water"
	if absf(cx - CityMap.RIVER_X) < 1.0:
		river = true
	if river:
		_bridge(b, cols, start, dir, length, hw)
	else:
		strip(b, start, dir, length, hw, Color(0.21, 0.22, 0.24), K.ASPHALT, 0.002)
	# lane markings: dashed lane lines, double yellow median, white edges
	var d := 0.0
	while d < length - 1.0:
		for off in [-5.0, 5.0]:
			strip(b, start + dir * d, dir, 3.0, 0.15, WHITE, K.ROAD_PAINT, 0.014, off)
		d += 9.0
	for off in [-0.2, 0.2]:
		strip(b, start, dir, length, 0.12, YELLOW, K.ROAD_PAINT, 0.014, off)
	for off in [-hw * 0.5 + 0.6, hw * 0.5 - 0.6]:
		strip(b, start, dir, length, 0.15, WHITE, K.ROAD_PAINT, 0.014, off)
	# guard rails, with gaps where streets cross at junctions
	var gaps: Array = []
	for a in [gi, gi + 1]:
		if CityMap.vedge(a, -1) == "crossing":
			gaps.append(CityMap.intersection(a, 0).x)
	for side in [-1.0, 1.0]:
		var zr: float = z + side * (hw * 0.5 + 0.8)
		var x := x0
		while x < x0 + length - 0.5:
			var seg_end := minf(x + 4.0, x0 + length)
			var blocked := false
			for g in gaps:
				if absf((x + seg_end) * 0.5 - g) < 7.5:
					blocked = true
			if not blocked:
				var y := rh((x + seg_end) * 0.5, zr)
				var xf := Transform3D(Basis.IDENTITY, Vector3((x + seg_end) * 0.5, y + 0.55, zr))
				b.box(xf, Vector3(seg_end - x, 0.3, 0.12), Color(0.78, 0.78, 0.76), K.METAL)
				b.box(Transform3D(Basis.IDENTITY, Vector3(x + 0.1, y + 0.35, zr)), Vector3(0.12, 0.7, 0.12), Color(0.5, 0.5, 0.5), K.METAL)
				cols.add(xf, Vector3(seg_end - x, 0.9, 0.2))
			x = seg_end
	# median light poles
	var lx := x0 + 10.0
	while lx < x0 + length:
		var y2 := rh(lx, z)
		b.cylinder(Vector3(lx, y2 + 4.5, z), 0.1, 0.14, 9.0, Color(0.55, 0.56, 0.58), K.METAL, 6)
		for side in [-1.0, 1.0]:
			b.box(Transform3D(Basis.IDENTITY, Vector3(lx, y2 + 8.9, z + side * 1.2)), Vector3(0.25, 0.12, 2.4), Color(0.55, 0.56, 0.58), K.METAL)
		cols.add_box(Vector3(lx, y2 + 4.5, z), Vector3(0.3, 9.0, 0.3))
		lx += 29.0


## Far LOD: one coarse quad strip per road edge (always loaded).
static func build_far(b: GeoBatch) -> void:
	for a in range(CityMap.GI_MIN, CityMap.GI_MAX + 2):
		for bb in range(CityMap.GJ_MIN, CityMap.GJ_MAX + 2):
			for axis in ["v", "h"]:
				var kind: String = CityMap.vedge(a, bb) if axis == "v" else CityMap.hedge(a, bb)
				if kind == "":
					continue
				var p0 := CityMap.intersection(a, bb)
				var dir := Vector3(0, 0, 1) if axis == "v" else Vector3(1, 0, 0)
				_far_strip(b, p0, dir, CityMap.PITCH, CityMap.road_width(kind), DIRT if kind == "dirt" else ASPHALT)
	var x0 := CityMap.world_rect().position.x
	_far_strip(b, Vector3(x0, 0, CityMap.HIGHWAY_Z), Vector3(1, 0, 0), CityMap.world_rect().size.x, CityMap.HIGHWAY_W, Color(0.21, 0.22, 0.24))


static func _far_strip(b: GeoBatch, p0: Vector3, dir: Vector3, length: float, w: float, col: Color) -> void:
	var n := Vector3(-dir.z, 0, dir.x)
	var pieces := maxi(1, int(length / 20.0))
	for k in pieces:
		var a := p0 + dir * (length * k / pieces)
		var c := p0 + dir * (length * (k + 1) / pieces)
		var pts: Array = [a + n * w * 0.5, c + n * w * 0.5, c - n * w * 0.5, a - n * w * 0.5]
		for i in 4:
			var p: Vector3 = pts[i]
			p.y = rh(p.x, p.z) - 0.2
			pts[i] = p
		b.quad_pts(pts[0], pts[1], pts[2], pts[3], col, K.ASPHALT)
