class_name DistrictBlocks
extends CityBlocks
## Generators for every cell outside the original town: the nine new districts
## (Pine Grove suburbs, Hillside, Neon Row, Downtown CBD, Westbridge Beach, Harbor
## Industrial, Fort Calder, Countryside, Route 9) plus forests, fields, beaches.
##
## Urban cells reuse the CityBlocks frame (X/W helpers, ring, furniture). On sloped
## cells (Hillside) every helper follows the terrain and buildings stand on stone
## foundations. Open cells (rural, beach, corridor) have no platform; their places
## attach to the nearest road intersections.

const HILL_LIFT := 0.03
const STONE := Color(0.58, 0.55, 0.5)

var hill: bool = false
var open_cell: bool = false
var t: String = ""
var dname: String = ""


# ------------------------------------------------------------------ frame overrides
func X(local: Vector3, yaw: float = 0.0) -> Transform3D:
	if hill or open_cell:
		var wx := c.x + local.x
		var wz := c.z + local.z
		return Transform3D(Basis(Vector3.UP, yaw), Vector3(wx, CityMap.height_at(wx, wz) + HILL_LIFT + local.y, wz))
	return super(local, yaw)


func W(local: Vector3) -> Vector3:
	if hill or open_cell:
		var wx := c.x + local.x
		var wz := c.z + local.z
		return Vector3(wx, CityMap.height_at(wx, wz) + HILL_LIFT + local.y, wz)
	return super(local)


func _platform() -> void:
	if not hill:
		super()
		return
	# Sloped block: paved sidewalk strips that follow the hill (terrain collider underneath).
	for side in 4:
		var horizontal := side % 2 == 0
		var sgn := -1.0 if side < 2 else 1.0
		var steps := 8
		for k in steps:
			var a := -24.0 + 48.0 * k / steps
			var e := -24.0 + 48.0 * (k + 1) / steps
			var p: Array
			if horizontal:
				p = [Vector3(a, 0, sgn * 21.0), Vector3(e, 0, sgn * 21.0), Vector3(e, 0, sgn * 24.0), Vector3(a, 0, sgn * 24.0)]
			else:
				p = [Vector3(sgn * 21.0, 0, a), Vector3(sgn * 24.0, 0, a), Vector3(sgn * 24.0, 0, e), Vector3(sgn * 21.0, 0, e)]
			b.quad_pts(W(p[3]), W(p[2]), W(p[1]), W(p[0]), Color(0.68, 0.67, 0.64), K.TILES)


func _make_ring() -> Array:
	if not hill:
		return super()
	var ids: Array = []
	var corners := [Vector3(-22.5, 0, -22.5), Vector3(22.5, 0, -22.5), Vector3(22.5, 0, 22.5), Vector3(-22.5, 0, 22.5)]
	for k in 4:
		for s in 4:
			var lp: Vector3 = (corners[k] as Vector3).lerp(corners[(k + 1) % 4], s / 4.0)
			ids.append(cb.graph.add_node(W(lp) + Vector3(0, 0.05, 0)))
	for k in ids.size():
		cb.graph.connect_nodes(ids[k], ids[(k + 1) % ids.size()])
	return ids


func _lot_ground(color: Color, kind: int, inset: float = 21.0) -> void:
	if not hill:
		super(color, kind, inset)
		return
	var n := 7
	var s := inset * 2.0 / n
	for ix in n:
		for iz in n:
			var x0 := -inset + ix * s
			var z0 := -inset + iz * s
			b.quad_pts(W(Vector3(x0, -0.02, z0 + s)), W(Vector3(x0 + s, -0.02, z0 + s)), W(Vector3(x0 + s, -0.02, z0)), W(Vector3(x0, -0.02, z0)), color, kind)


## Building base: on slopes a stone foundation up to the highest corner.
func pad(lx: float, lz: float, yaw: float, w: float, d: float) -> Transform3D:
	if not (hill or open_cell):
		return X(Vector3(lx, 0, lz), yaw)
	var basis := Basis(Vector3.UP, yaw)
	var lo := INF
	var hi := -INF
	for cx in [-0.5, 0.0, 0.5]:
		for cz in [-0.5, 0.0, 0.5]:
			var p := Vector3(c.x + lx, 0, c.z + lz) + basis * Vector3(cx * w, 0, cz * d)
			var h := CityMap.height_at(p.x, p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var top := hi + 0.1
	var xf := Transform3D(basis, Vector3(c.x + lx, top, c.z + lz))
	if top - lo > 0.15:
		var fh := top - lo + 0.4
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, -fh * 0.5, 0)), Vector3(w + 0.6, fh, d + 0.6), STONE, K.CONCRETE, rng.randf())
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, -fh * 0.5, 0)), Vector3(w + 0.6, fh, d + 0.6))
	return xf


static func front_yaw(lz: float) -> float:
	return PI if lz < 0.0 else 0.0


# ------------------------------------------------------------------ entry points
func build_block(p_i: int, p_j: int) -> void:
	i = p_i
	j = p_j
	var cc := CityMap.block_center(i, j)
	hill = not WorldTerrain.cell_is_flat(i, j)
	t = CityMap.cell_type(i, j)
	dname = CityMap.cell_district(i, j)
	c = cc
	_begin(i, j)
	node.name = "Block_%d_%d_%s" % [i, j, t]
	match t:
		"sub_houses": _homes("suburb")
		"beach_houses": _homes("beach")
		"villas": _homes("villa")
		"towers": _towers(false, false)
		"towers_tall": _towers(true, false)
		"res_towers": _towers(false, true)
		"police_hq": _police_hq()
		"hospital": _hospital()
		"central_station": _station()
		"city_mall": _mall()
		"central_plaza": _plaza("Founders Plaza")
		"school": _school()
		"church": _church()
		"supermarket": _supermarket()
		"water_tower": _water_tower()
		"community_pool": _pool()
		"sub_park": _park()
		"hill_cafe": _hill_cafe()
		"mansion": _mansion()
		"vineyard": _vineyard()
		"observatory": _observatory()
		"nightlife": _nightlife()
		"cinema": _cinema()
		"arcade_bowling": _bowling()
		"arena": _arena()
		"concert_hall": _concert_hall()
		"fun_park": _fun_park()
		"beach_shops": _beach_shops()
		"pier_plaza": _pier_plaza()
		"resort": _resort()
		"marina": _marina()
		"lighthouse_park": _lighthouse()
		"factory": _factory()
		"warehouses": _warehouses()
		"rail_yard": _rail_yard()
		"scrapyard": _scrapyard()
		"fuel_depot": _fuel_depot()
		"container_port": _container_port()
		"fish_docks": _fish_docks()
		_:
			if t.begins_with("mil_"):
				_military(t)
			else:
				_lot_ground(Color(0.4, 0.55, 0.3), K.GRASS)
	_street_furniture(t)
	_finish()


## Cells without a raised block: countryside, parks on the summit, beach, corridor.
func build_open_cell(p_i: int, p_j: int) -> void:
	i = p_i
	j = p_j
	c = CityMap.block_center(i, j)
	c.y = CityMap.height_at(c.x, c.z)
	open_cell = true
	t = CityMap.cell_type(i, j)
	dname = CityMap.cell_district(i, j)
	b = GeoBatch.new()
	b.enabled = not cb.data_mode
	cols = ColliderSet.new()
	cols.enabled = not cb.data_mode
	node = Node3D.new()
	node.name = "Open_%d_%d_%s" % [i, j, t]
	cb.root.add_child(node)
	ring = cb.open_cell_links(i, j)
	match t:
		"forest": _forest(46)
		"field": _field()
		"farm": _farm()
		"orchard": _orchard()
		"windmill_farm": _windmill_farm()
		"campground": _campground()
		"rural_gas": _rural_gas()
		"hill_park": _hill_park()
		"lookout": _lookout()
		"radio_tower": _radio_tower()
		"beach": _beach(false)
		"beach_pier": _beach(true)
		"beach_marina": _beach_marina()
		"highway": _corridor()
	_finish()


func _place(type: String, pname: String, entry: Vector3, opts: Dictionary) -> Place:
	if ring.is_empty():
		ring = cb.open_cell_links(i, j)
	return cb.add_place(type, pname, entry, ring, opts)


func _job(title: String, wage: int, start: float, end: float, slots: int) -> Dictionary:
	return {"title": title, "wage": wage, "start": start, "end": end, "slots": slots}


func _name(pool: Array) -> String:
	return pool[posmod(i * 7 + j * 13, pool.size())]


# ------------------------------------------------------------------ generic buildings
## Box building with windows, door, roof trim. Front = local +Z. Returns the entrance.
func facade(xf: Transform3D, w: float, d: float, h: float, wall: Color, kind: int, opts: Dictionary = {}) -> Vector3:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), wall, kind, rng.randf())
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d))
	var trim: Color = opts.get("trim", wall.darkened(0.25))
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.2, 0)), Vector3(w + 0.3, 0.4, d + 0.3), trim, K.CONCRETE)
	var frame: Color = opts.get("frame", Color(0.9, 0.9, 0.88))
	if opts.get("windows", true):
		var rows := mini(int((h - 1.0) / 3.2), int(opts.get("max_rows", 5)))
		var nf := maxi(1, int(w / 3.0))
		var ns := maxi(1, int(d / 3.0))
		for r in rows:
			var y := 1.7 + r * 3.2
			for k in nf:
				var x := -w * 0.5 + (k + 0.5) * w / nf
				if r == 0 and absf(x) < 2.2:
					continue
				BuildingKit._win(b, xf, Vector3(x, y, d * 0.5), Vector2(1.3, 1.5), frame, rng.randf())
			for k in ns:
				var z := -d * 0.5 + (k + 0.5) * d / ns
				BuildingKit._win(b, xf, Vector3(w * 0.5, y, z), Vector2(1.3, 1.5), frame, rng.randf(), "+x")
				BuildingKit._win(b, xf, Vector3(-w * 0.5, y, z), Vector2(1.3, 1.5), frame, rng.randf(), "-x")
	BuildingKit._door(b, xf, Vector3(-0.7, 0, d * 0.5), Color(0.28, 0.35, 0.4), Color(0.2, 0.2, 0.22), 1.3)
	BuildingKit._door(b, xf, Vector3(0.7, 0, d * 0.5), Color(0.28, 0.35, 0.4), Color(0.2, 0.2, 0.22), 1.3)
	if opts.get("canopy", true):
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, d * 0.5 + 1.0)), Vector3(5.0, 0.2, 2.0), trim, K.CONCRETE)
	if opts.get("gable", false):
		b.gable_roof(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.4, 0)), Vector3(w + 0.6, 0, d + 0.6), opts.get("rise", 2.5), opts.get("roof", Color(0.35, 0.3, 0.28)), wall)
	if opts.has("sign"):
		cb.sign_label(node, opts.sign, (xf * Transform3D(Basis.IDENTITY, Vector3(0, minf(h - 1.0, 4.6), d * 0.5 + 0.1))).origin, xf.basis.get_euler().y, opts.get("sign_size", 72), opts.get("sign_color", Color(1, 0.96, 0.86)))
	return (xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, d * 0.5 + 1.4))).origin


func _sky(xf: Transform3D, size: Vector3, color: Color, kind: int) -> void:
	cb.add_to_skyline(xf.origin, size, color, kind)


func _parked_cars(lx0: float, lx1: float, lz: float, yaw: float, chance: float, palette: Array = CAR_COLORS) -> void:
	var x := lx0
	while x <= lx1:
		if rng.randf() < chance:
			PropsKit.car(b, cols, X(Vector3(x, 0, lz), yaw), palette[rng.randi() % palette.size()], rng.randi() % 3)
		x += 3.2


func _bench_seat(lp: Vector3, yaw: float) -> Dictionary:
	PropsKit.bench(b, cols, X(lp, yaw + PI))
	var seat := Seat.new()
	seat.transform = X(lp, yaw)
	seat.transform.origin += seat.transform.basis.z * -0.05
	node.add_child(seat)
	return {"pos": seat.transform.origin, "yaw": yaw, "kind": "seat", "seat": seat, "taken_by": -1}


func _trees(n: int, half: float = 19.0, keep_out: float = 0.0, scale: Vector2 = Vector2(0.8, 1.3)) -> void:
	for k in n:
		var p := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half))
		var s := rng.randf_range(scale.x, scale.y)
		var yaw := rng.randf() * TAU
		if keep_out > 0.0 and absf(p.x) < keep_out and absf(p.z) < keep_out:
			continue
		cb.tree_spots.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), W(p)))


func _fence(a: Vector3, e: Vector3, color: Color, h: float = 2.0) -> void:
	var la := W(a)
	var le := W(e)
	var mid := (la + le) * 0.5
	var flen := Vector2(le.x - la.x, le.z - la.z).length()
	var yaw := atan2(le.x - la.x, le.z - la.z)
	var xf := Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, h * 0.5, 0))
	b.box(xf, Vector3(0.06, h, flen), color, K.METAL, 0.0, [])
	var k := 0.0
	while k <= flen:
		b.box(Transform3D(Basis.IDENTITY, la.lerp(le, k / maxf(flen, 0.01)) + Vector3(0, h * 0.5, 0)), Vector3(0.1, h, 0.1), color.darkened(0.3), K.METAL)
		k += 3.0
	cols.add(xf, Vector3(0.15, h, flen))


# ------------------------------------------------------------------ residential
const BEACH_COLORS := [Color(0.98, 0.85, 0.75), Color(0.7, 0.88, 0.9), Color(0.98, 0.95, 0.7), Color(0.85, 0.95, 0.82), Color(0.95, 0.78, 0.82), Color(0.98, 0.98, 0.96)]
const VILLA_COLORS := [Color(0.96, 0.95, 0.92), Color(0.82, 0.8, 0.76), Color(0.9, 0.86, 0.78), Color(0.75, 0.72, 0.68)]
const SURNAMES := ["Abernathy", "Bianchi", "Castillo", "Dubois", "Eriksen", "Fischer", "Gallagher", "Hosseini", "Ito", "Jansen",
	"Kaur", "Lindqvist", "Mensah", "Novak", "Oyelaran", "Petrov", "Quinn", "Reyes", "Sato", "Torres", "Ulrich", "Varga", "Whitfield", "Yilmaz", "Zhou"]


func _homes(style: String) -> void:
	_lot_ground(Color(0.38, 0.55, 0.28) if style != "beach" else Color(0.82, 0.76, 0.58), K.GRASS if style != "beach" else K.DIRT)
	var xs: Array = [-10.5, 10.5] if style == "villa" else [-14.0, 0.0, 14.0]
	var k := 0
	for side in [1.0, -1.0]:
		var yaw: float = 0.0 if side > 0 else PI
		var street: String = CityMap.street_ew(j + 1) if side > 0 else CityMap.street_ew(j)
		for lx in xs:
			var w: float
			var d: float
			var floors: int
			var wall: Color
			match style:
				"villa":
					w = rng.randf_range(12.0, 14.0)
					d = rng.randf_range(9.0, 11.0)
					floors = 2
					wall = VILLA_COLORS[rng.randi() % VILLA_COLORS.size()]
				"beach":
					w = rng.randf_range(7.5, 9.0)
					d = rng.randf_range(7.5, 9.0)
					floors = 1 if rng.randf() < 0.5 else 2
					wall = BEACH_COLORS[rng.randi() % BEACH_COLORS.size()]
				_:
					w = rng.randf_range(8.5, 10.0)
					d = rng.randf_range(8.0, 9.5)
					floors = 1 if rng.randf() < 0.4 else 2
					wall = HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()]
			var z: float = side * (21.0 - 6.0 - d * 0.5)
			var xf := pad(lx, z, yaw, w + 0.6, d + 0.6)
			var entry: Vector3
			if style == "villa":
				entry = _modern_house(xf, w, d, wall)
			else:
				var roof: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()] if style == "suburb" else Color(0.55, 0.62, 0.7).lerp(Color(0.7, 0.4, 0.3), rng.randf())
				entry = BuildingKit.house(b, cols, xf, w, d, floors, wall, roof, Color(0.97, 0.97, 0.95), rng)
			_sky(xf, Vector3(w, floors * 3.0 + 2.0, d), wall, K.WOOD)
			var fence_z: float = side * 20.6
			match style:
				"suburb":
					PropsKit.picket_fence(b, cols, W(Vector3(lx - 6.8, 0, fence_z)), W(Vector3(lx + 6.8, 0, fence_z)), Color(0.95, 0.95, 0.93), 6.8, 1.6)
					b.floor_quad(W(Vector3(lx + w * 0.5 + 1.6, 0.008, side * 16.0)), Vector2(2.8, 9.0), Color(0.6, 0.6, 0.58), K.CONCRETE)
					if rng.randf() < 0.6:
						PropsKit.car(b, cols, X(Vector3(lx + w * 0.5 + 1.6, 0, side * 15.5), yaw), CAR_COLORS[rng.randi() % CAR_COLORS.size()], rng.randi() % 3)
					PropsKit.mailbox(b, W(Vector3(lx + 1.5, 0, fence_z + side * 0.4)), yaw)
				"beach":
					b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, d * 0.5 + 1.5)), Vector3(w, 0.5, 3.0), Color(0.7, 0.55, 0.38), K.WOOD)
					cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, d * 0.5 + 1.5)), Vector3(w, 0.5, 3.0))
				"villa":
					var pool := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.02, -d * 0.5 - 3.2))
					b.box(pool, Vector3(w * 0.7, 0.04, 3.6), Color(0.25, 0.6, 0.75), K.WATER)
					b.box(pool * Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), Vector3(w * 0.7 + 1.2, 0.03, 4.8), Color(0.85, 0.83, 0.78), K.TILES)
					for sx in [-1.0, 1.0]:
						var hx := xf * Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 + 1.2), 0.6, 0))
						b.box(hx, Vector3(0.9, 1.2, d + 4.0), Color(0.22, 0.4, 0.2), K.FOLIAGE)
						cols.add(hx, Vector3(0.9, 1.2, d + 4.0))
			if rng.randf() < 0.7:
				cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), W(Vector3(lx + rng.randf_range(-4, 4), 0, side * 2.5))))
			var number := 100 + (posmod(i, 50) * 20 + k * 4 + posmod(j, 7) * 2)
			var who: String = SURNAMES[posmod(i * 11 + j * 5 + k * 3, SURNAMES.size())]
			var label: String = {"villa": "villa", "beach": "beach house", "suburb": "house"}[style]
			var p := _place("home", "%s %s, %d %s" % [who, label, number, street], entry, {"tags": ["home", "sleep", "food"], "capacity": 5 if style == "villa" else 4, "price": 3 if style == "villa" else 1})
			p.inside_pos = xf.origin
			k += 1


func _modern_house(xf: Transform3D, w: float, d: float, wall: Color) -> Vector3:
	var h1 := 3.2
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h1 * 0.5, 0)), Vector3(w, h1, d), wall, K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.15, h1 + 1.6, -0.6)), Vector3(w * 0.7, 3.2, d - 1.2), wall.darkened(0.06), K.CONCRETE)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h1 * 0.5, 0)), Vector3(w, h1, d))
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.15, h1 + 1.6, -0.6)), Vector3(w * 0.7, 3.2, d - 1.2))
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.15, h1 * 2.0 + 0.1, -0.4)), Vector3(w * 0.7 + 1.2, 0.2, d), Color(0.25, 0.25, 0.27), K.ROOF)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h1 + 0.1, 0.3)), Vector3(w + 0.8, 0.2, d + 0.8), Color(0.3, 0.3, 0.32), K.ROOF)
	# big glass fronts
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.2, 1.5, d * 0.5 + 0.02)), Vector3(w * 0.45, 2.4, 0.06), Color(0.3, 0.42, 0.5), K.GLASS)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.15, h1 + 1.6, d * 0.5 - 1.2 + 0.02)), Vector3(w * 0.55, 2.2, 0.06), Color(0.3, 0.42, 0.5), K.GLASS)
	BuildingKit._door(b, xf, Vector3(-w * 0.3, 0, d * 0.5), Color(0.25, 0.2, 0.16), Color(0.2, 0.2, 0.2), 1.3)
	return (xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.3, 0, d * 0.5 + 1.2))).origin


# ------------------------------------------------------------------ Downtown CBD
const TOWER_NAMES := ["Calder Trust Tower", "Meridian Center", "Atlas Building", "One Westbridge", "Harborview Plaza", "Northstar Tower", "Granite Exchange", "Crown Point"]


func _towers(tall: bool, residential: bool) -> void:
	_lot_ground(Color(0.66, 0.65, 0.62), K.TILES)
	var specs: Array
	if tall:
		specs = [[Vector3(-4, 0, -4), 20.0, 20.0, rng.randi_range(26, 32)], [Vector3(13, 0, 13), 10.0, 10.0, rng.randi_range(8, 12)]]
	else:
		specs = [[Vector3(-8, 0, -8), 16.0, 15.0, rng.randi_range(12, 18)], [Vector3(9, 0, 9), 14.0, 14.0, rng.randi_range(9, 15)]]
	var k := 0
	for s in specs:
		var lp: Vector3 = s[0]
		var yaw := front_yaw(lp.z)
		var xf := pad(lp.x, lp.z, yaw, s[1], s[2])
		var entry: Vector3
		if residential:
			entry = BuildingKit.apartment(b, cols, xf, s[1], s[2], int(s[3]) / 2, Color(0.78, 0.74, 0.68).lerp(Color(0.55, 0.6, 0.66), rng.randf()), rng)
			_sky(xf, Vector3(s[1], int(s[3]) / 2 * 3.1 + 1.0, s[2]), Color(0.7, 0.68, 0.64), K.BRICK)
		else:
			entry = BuildingKit.tower(b, cols, xf, s[1], s[2], s[3], Color(0.72, 0.73, 0.75).lerp(Color(0.4, 0.42, 0.46), rng.randf()), rng)
			_sky(xf, Vector3(s[1], s[3] * 3.4 + 2.0, s[2]), Color(0.36, 0.46, 0.55), K.GLASS)
		var nm: String = TOWER_NAMES[posmod(i * 5 + j * 3 + k, TOWER_NAMES.size())]
		if residential:
			nm = ["Skyline Residences", "Riverside Lofts", "Parkview Apartments", "The Calder"][posmod(i + j + k, 4)]
			_place("apartment", nm, entry, {"tags": ["home", "sleep", "food"], "capacity": 24, "price": 2})
		else:
			_place("office", nm, entry, {"tags": ["work"], "open": 7.0, "close": 20.0, "capacity": 60, "jobs": [
				_job("Analyst", 24, 9.0, 17.0, 6), _job("Office assistant", 19, 8.0, 16.0, 4), _job("Security guard", 16, 18.0, 6.0, 1)]})
		cb.sign_label(node, nm, (xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.6, s[2] * 0.5 + 0.1))).origin, yaw, 70)
		var occ := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = Vector3(s[1] - 1.0, s[3] * 3.4 if not residential else int(s[3]) / 2 * 3.1, s[2] - 1.0)
		occ.occluder = bo
		occ.position = xf.origin + Vector3(0, bo.size.y * 0.5, 0)
		node.add_child(occ)
		k += 1
	for p in [Vector3(-14, 0, 14), Vector3(14, 0, -14), Vector3(4, 0, -16)]:
		PropsKit.planter(b, cols, W(p), Color.from_hsv(rng.randf(), 0.5, 0.9))


func _police_hq() -> void:
	_lot_ground(Color(0.62, 0.62, 0.6), K.TILES)
	var xf := pad(0, -5, PI, 32.0, 16.0)
	var e := facade(xf, 32.0, 16.0, 12.0, Color(0.72, 0.74, 0.78), K.CONCRETE, {"sign": "WESTBRIDGE POLICE DEPARTMENT", "sign_color": Color(0.85, 0.9, 1.0), "trim": Color(0.2, 0.28, 0.45)})
	_sky(xf, Vector3(32, 12, 16), Color(0.72, 0.74, 0.78), K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 12.8, 0)), Vector3(8, 1.2, 6), Color(0.3, 0.32, 0.36), K.METAL)
	b.cylinder((xf * Transform3D(Basis.IDENTITY, Vector3(12, 0, 10))).origin + Vector3(0, 5, 0), 0.08, 0.1, 10.0, Color(0.8, 0.8, 0.82), K.METAL, 6)
	b.box(Transform3D(Basis.IDENTITY, (xf * Transform3D(Basis.IDENTITY, Vector3(12, 0, 10))).origin + Vector3(0.7, 9.2, 0)), Vector3(1.4, 0.9, 0.04), Color(0.2, 0.35, 0.65), K.PAINT)
	_parked_cars(-16.0, 16.0, 14.0, 0.0, 0.8, [Color(0.1, 0.12, 0.2), Color(0.92, 0.92, 0.94)])
	_place("police", "Westbridge Police HQ", e, {"tags": ["work", "services"], "capacity": 40, "jobs": [
		_job("Police officer", 22, 6.0, 14.0, 4), _job("Police officer (late)", 23, 14.0, 22.0, 4), _job("Police officer (night)", 25, 22.0, 6.0, 2), _job("Dispatcher", 18, 8.0, 16.0, 2)]})


func _hospital() -> void:
	_lot_ground(Color(0.7, 0.7, 0.68), K.TILES)
	var xf := pad(0, -4, PI, 34.0, 20.0)
	var e := facade(xf, 34.0, 20.0, 15.0, Color(0.94, 0.94, 0.92), K.CONCRETE, {"sign": "ST. CALDER GENERAL HOSPITAL", "sign_color": Color(0.9, 0.2, 0.2), "frame": Color(0.6, 0.75, 0.85)})
	_sky(xf, Vector3(34, 15, 20), Color(0.94, 0.94, 0.92), K.CONCRETE)
	for r in [Vector3(4.0, 1.2, 0.3), Vector3(1.2, 4.0, 0.3)]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-12, 10.5, 10.2)), r, Color(0.85, 0.12, 0.12), K.SIGN)
	# helipad
	b.cylinder((xf * Transform3D(Basis.IDENTITY, Vector3(8, 15.45, 0))).origin, 5.0, 5.0, 0.1, Color(0.3, 0.32, 0.34), K.ASPHALT, 20)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(8, 15.52, 0)), Vector3(0.6, 0.02, 4.0), Color(0.95, 0.95, 0.9), K.ROAD_PAINT)
	# ambulance bay
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(12, 3.6, 13.5)), Vector3(10.0, 0.3, 7.0), Color(0.85, 0.2, 0.2), K.PAINT)
	for sx in [8.0, 16.0]:
		b.cylinder((xf * Transform3D(Basis.IDENTITY, Vector3(sx, 1.8, 16.5))).origin, 0.15, 0.15, 3.6, Color(0.8, 0.8, 0.8), K.METAL, 6)
	PropsKit.car(b, cols, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12, 0, 14)), Color(0.95, 0.95, 0.93), 2)
	_place("hospital", "St. Calder General Hospital", e, {"tags": ["work", "services", "shelter"], "capacity": 60, "jobs": [
		_job("Nurse", 24, 7.0, 15.0, 4), _job("Nurse (night)", 27, 19.0, 7.0, 2), _job("Doctor", 40, 8.0, 18.0, 3), _job("Paramedic", 25, 10.0, 22.0, 2)]})


func _station() -> void:
	_lot_ground(Color(0.64, 0.63, 0.6), K.TILES)
	var xf := pad(0, -4, PI, 38.0, 18.0)
	var e := facade(xf, 38.0, 18.0, 9.0, Color(0.78, 0.66, 0.52), K.BRICK, {"sign": "CENTRAL STATION", "max_rows": 2, "gable": true, "rise": 4.0, "roof": Color(0.32, 0.45, 0.5)})
	_sky(xf, Vector3(38, 13, 18), Color(0.78, 0.66, 0.52), K.BRICK)
	var tower := xf * Transform3D(Basis.IDENTITY, Vector3(15, 0, 4))
	b.box(tower * Transform3D(Basis.IDENTITY, Vector3(0, 9, 0)), Vector3(5, 18, 5), Color(0.75, 0.62, 0.48), K.BRICK)
	cols.add(tower * Transform3D(Basis.IDENTITY, Vector3(0, 9, 0)), Vector3(5, 18, 5))
	b.cylinder((tower * Transform3D(Basis.IDENTITY, Vector3(0, 15, 2.55))).origin, 1.6, 1.6, 0.1, Color(0.95, 0.93, 0.85), K.SIGN, 16, tower.basis * Basis(Vector3.RIGHT, PI * 0.5))
	b.cylinder((tower * Transform3D(Basis.IDENTITY, Vector3(0, 19.5, 0))).origin, 0.0, 3.6, 3.0, Color(0.3, 0.42, 0.46), K.ROOF, 4)
	_sky(tower, Vector3(5, 21, 5), Color(0.75, 0.62, 0.48), K.BRICK)
	var sp: Array = []
	for k in 4:
		sp.append(_bench_seat(Vector3(-12 + k * 8.0, 0, 14.0), PI))
	var p := _place("transit", "Westbridge Central Station", e, {"tags": ["transit", "shelter", "work"], "capacity": 50, "jobs": [_job("Ticket agent", 16, 6.0, 14.0, 2), _job("Ticket agent (late)", 17, 14.0, 22.0, 2), _job("Train conductor", 23, 7.0, 17.0, 3)]})
	if cb.data_mode:
		p.spots.append_array(sp)


func _mall() -> void:
	_lot_ground(Color(0.3, 0.31, 0.33), K.ASPHALT)
	var xf := pad(0, -6, PI, 40.0, 26.0)
	var e := facade(xf, 40.0, 26.0, 11.0, Color(0.85, 0.82, 0.78), K.CONCRETE, {"sign": "WESTBRIDGE MALL", "sign_size": 96, "max_rows": 2})
	_sky(xf, Vector3(40, 11, 26), Color(0.85, 0.82, 0.78), K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 13.1)), Vector3(12.0, 8.0, 0.2), Color(0.3, 0.42, 0.5), K.GLASS)
	_parked_cars(-18.0, 18.0, 15.0, 0.0, 0.6)
	_parked_cars(-18.0, 18.0, 19.5, PI, 0.5)
	_place("mall", "Westbridge Mall", e, {"tags": ["shop", "food", "coffee", "leisure", "shelter", "groceries", "work"], "open": 9.0, "close": 22.0, "capacity": 120, "price": 2, "jobs": [
		_job("Retail associate", 15, 9.0, 17.0, 6), _job("Retail associate (late)", 16, 14.0, 22.0, 4), _job("Food court cook", 15, 10.0, 18.0, 3), _job("Mall security", 17, 14.0, 22.0, 1)]})


func _plaza(pname: String) -> void:
	_lot_ground(Color(0.74, 0.7, 0.62), K.TILES)
	b.cylinder(W(Vector3(0, 0.35, 0)), 6.0, 6.2, 0.7, Color(0.68, 0.66, 0.62), K.CONCRETE, 24)
	b.cylinder(W(Vector3(0, 0.62, 0)), 5.6, 5.6, 0.1, Color(0.28, 0.5, 0.62), K.WATER, 24)
	b.cylinder(W(Vector3(0, 2.2, 0)), 0.5, 0.8, 3.2, Color(0.68, 0.66, 0.62), K.CONCRETE, 12)
	b.sphere(W(Vector3(0, 4.3, 0)), Vector3(0.8, 1.1, 0.8), Color(0.55, 0.5, 0.35), K.METAL, 10)
	cols.add_box(W(Vector3(0, 0.4, 0)), Vector3(12.0, 0.8, 12.0))
	var sp: Array = []
	for k in 8:
		var a := TAU * k / 8.0
		var lp := Vector3(cos(a) * 11.0, 0, sin(a) * 11.0)
		sp.append(_bench_seat(lp, face_yaw(lp, Vector3.ZERO)))
	_trees(14, 19.0, 14.0, Vector2(0.8, 1.1))
	var p := _place("plaza", pname, W(Vector3(0, 0, 20.5)), {"tags": ["social", "free", "outdoor", "leisure"], "capacity": 40, "price": 0})
	if cb.data_mode:
		p.spots.append_array(sp)


# ------------------------------------------------------------------ Pine Grove
func _school() -> void:
	_lot_ground(Color(0.4, 0.56, 0.3), K.GRASS)
	var xf := pad(-6, -9, PI, 30.0, 12.0)
	var e := facade(xf, 30.0, 12.0, 7.5, Color(0.72, 0.42, 0.32), K.BRICK, {"sign": "PINE GROVE ELEMENTARY", "max_rows": 2})
	var xf2 := pad(13, 4, -PI * 0.5, 14.0, 10.0)
	facade(xf2, 14.0, 10.0, 7.5, Color(0.72, 0.42, 0.32), K.BRICK, {"max_rows": 2, "canopy": false})
	_sky(xf, Vector3(30, 8, 12), Color(0.72, 0.42, 0.32), K.BRICK)
	# playground / field
	b.floor_quad(W(Vector3(-6, 0.01, 9)), Vector2(22, 14), Color(0.6, 0.35, 0.25), K.DIRT)
	for k in 2:
		var px := -14.0 + k * 16.0
		b.box(X(Vector3(px, 1.5, 9)), Vector3(0.1, 3.0, 0.1), Color(0.9, 0.9, 0.9), K.METAL)
		b.box(X(Vector3(px, 3.0, 9)), Vector3(0.1, 0.1, 2.4), Color(0.9, 0.9, 0.9), K.METAL)
	b.cylinder(W(Vector3(14, 5, -14)), 0.06, 0.08, 10.0, Color(0.8, 0.8, 0.8), K.METAL, 6)
	_place("school", "Pine Grove Elementary", e, {"tags": ["work"], "open": 7.0, "close": 17.0, "capacity": 80, "jobs": [_job("Teacher", 21, 7.5, 15.5, 6), _job("Janitor", 14, 14.0, 22.0, 1)]})


func _church() -> void:
	_lot_ground(Color(0.42, 0.56, 0.32), K.GRASS)
	var xf := pad(0, -2, PI, 12.0, 24.0)
	var e := facade(xf, 12.0, 24.0, 9.0, Color(0.9, 0.88, 0.82), K.CONCRETE, {"gable": true, "rise": 5.0, "roof": Color(0.32, 0.28, 0.26), "max_rows": 1, "canopy": false})
	var st := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 13.5))
	b.box(st * Transform3D(Basis.IDENTITY, Vector3(0, 8.0, 0)), Vector3(4.5, 16.0, 4.5), Color(0.88, 0.86, 0.8), K.CONCRETE)
	cols.add(st * Transform3D(Basis.IDENTITY, Vector3(0, 8.0, 0)), Vector3(4.5, 16.0, 4.5))
	b.cylinder(st.origin + Vector3(0, 20.0, 0), 0.0, 3.0, 8.0, Color(0.3, 0.28, 0.26), K.ROOF, 4)
	_sky(st, Vector3(4.5, 24.0, 4.5), Color(0.9, 0.88, 0.82), K.CONCRETE)
	_sky(xf, Vector3(12, 13, 24), Color(0.9, 0.88, 0.82), K.CONCRETE)
	_trees(8, 19.0, 9.0)
	_place("church", "St. Brendan's Church", (st * Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.2))).origin, {"tags": ["social", "free", "shelter"], "open": 7.0, "close": 20.0, "capacity": 60, "price": 0, "jobs": [_job("Caretaker", 13, 8.0, 16.0, 1)]})


func _supermarket() -> void:
	_lot_ground(Color(0.3, 0.31, 0.33), K.ASPHALT)
	var xf := pad(0, -7, PI, 32.0, 18.0)
	var e := facade(xf, 32.0, 18.0, 7.0, Color(0.92, 0.9, 0.84), K.CONCRETE, {"sign": "FRESHWAY MARKET", "sign_color": Color(0.3, 0.85, 0.35), "max_rows": 1, "trim": Color(0.2, 0.55, 0.25)})
	_sky(xf, Vector3(32, 7, 18), Color(0.92, 0.9, 0.84), K.CONCRETE)
	_parked_cars(-16.0, 16.0, 11.0, 0.0, 0.55)
	_parked_cars(-16.0, 16.0, 16.0, PI, 0.5)
	_place("store", "Freshway Market", e, {"tags": ["groceries", "shop", "food", "work"], "open": 7.0, "close": 22.0, "capacity": 40, "jobs": [_job("Cashier", 14, 7.0, 15.0, 3), _job("Cashier (late)", 15, 14.0, 22.0, 2), _job("Stocker", 14, 5.0, 13.0, 2)]})


func _water_tower() -> void:
	_lot_ground(Color(0.4, 0.55, 0.3), K.GRASS)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.cylinder(W(Vector3(sx * 3.5, 9.0, sz * 3.5)), 0.25, 0.3, 18.0, Color(0.6, 0.62, 0.64), K.METAL, 6)
			cols.add_box(W(Vector3(sx * 3.5, 9.0, sz * 3.5)), Vector3(0.6, 18.0, 0.6))
	b.cylinder(W(Vector3(0, 21.0, 0)), 6.0, 6.0, 6.0, Color(0.85, 0.87, 0.9), K.METAL, 18)
	b.cylinder(W(Vector3(0, 24.8, 0)), 0.5, 6.2, 1.6, Color(0.75, 0.78, 0.82), K.METAL, 18)
	cb.sign_label(node, "PINE GROVE", W(Vector3(0, 21.5, 6.1)), 0.0, 160, Color(0.2, 0.35, 0.6))
	_sky(X(Vector3.ZERO), Vector3(12, 26, 12), Color(0.85, 0.87, 0.9), K.METAL)
	_trees(10, 19.0, 7.0)
	_place("utility", "Pine Grove Water Works", W(Vector3(0, 0, 21.0)), {"tags": ["work"], "capacity": 6, "jobs": [_job("Water technician", 19, 8.0, 16.0, 2)]})


func _pool() -> void:
	_lot_ground(Color(0.82, 0.8, 0.75), K.TILES)
	b.box(X(Vector3(0, 0.02, 2)), Vector3(25.0, 0.04, 12.5), Color(0.3, 0.65, 0.8), K.WATER)
	for k in 5:
		b.box(X(Vector3(0, 0.05, -2.0 + k * 2.5)), Vector3(25.0, 0.02, 0.08), Color(0.9, 0.9, 0.95), K.ROAD_PAINT)
	var xf := pad(0, -15, PI, 22.0, 8.0)
	var e := facade(xf, 22.0, 8.0, 4.5, Color(0.6, 0.8, 0.9), K.PAINT, {"sign": "COMMUNITY POOL", "max_rows": 1})
	b.box(X(Vector3(14.5, 1.2, 2)), Vector3(1.2, 2.4, 1.2), Color(0.95, 0.95, 0.95), K.PAINT)
	_fence(Vector3(-20.5, 0, -20.5), Vector3(-20.5, 0, 20.5), Color(0.55, 0.6, 0.62))
	_fence(Vector3(20.5, 0, -20.5), Vector3(20.5, 0, 20.5), Color(0.55, 0.6, 0.62))
	_place("sports", "Pine Grove Community Pool", e, {"tags": ["sports", "leisure", "outdoor"], "open": 8.0, "close": 20.0, "capacity": 40, "jobs": [_job("Lifeguard", 15, 9.0, 17.0, 2)]})


# ------------------------------------------------------------------ Hillside
func _hill_cafe() -> void:
	_lot_ground(Color(0.42, 0.56, 0.3), K.GRASS)
	var xf := pad(0, 6, 0.0, 14.0, 9.0)
	var e := facade(xf, 14.0, 9.0, 4.2, Color(0.88, 0.8, 0.66), K.WOOD, {"sign": "SUMMIT VIEW CAFE", "gable": true, "rise": 2.0, "max_rows": 1})
	var sp: Array = []
	for k in 6:
		var tp := Vector3(-10 + (k % 3) * 10, 0, -8 - (k / 3) * 6)
		BuildingKit.table(b, cols, X(tp), Vector2(1.2, 1.2), Color(0.5, 0.36, 0.24))
		var seat := Seat.new()
		seat.transform = X(tp + Vector3(0, 0, 1.0), 0.0)
		node.add_child(seat)
		BuildingKit.chair(b, X(tp + Vector3(0, 0, 1.0), PI), Color(0.35, 0.3, 0.25))
		sp.append({"pos": seat.transform.origin, "yaw": 0.0, "kind": "seat", "seat": seat, "taken_by": -1})
	_trees(6, 19.0, 12.0)
	var p := _place("cafe", "Summit View Cafe", e, {"tags": ["coffee", "food", "social", "work"], "open": 7.0, "close": 21.0, "capacity": 20, "price": 2, "jobs": [_job("Barista", 14, 7.0, 15.0, 2), _job("Barista (late)", 15, 13.0, 21.0, 1)]})
	if cb.data_mode:
		p.spots.append_array(sp)


func _mansion() -> void:
	_lot_ground(Color(0.36, 0.52, 0.27), K.GRASS)
	var xf := pad(0, -4, 0.0, 22.0, 14.0)
	var e := BuildingKit.house(b, cols, xf, 22.0, 14.0, 3, Color(0.95, 0.93, 0.88), Color(0.28, 0.3, 0.34), Color(0.98, 0.98, 0.96), rng)
	_sky(xf, Vector3(22, 12, 14), Color(0.95, 0.93, 0.88), K.WOOD)
	for k in 4:
		b.cylinder((xf * Transform3D(Basis.IDENTITY, Vector3(-4.5 + k * 3.0, 3.0, 7.6))).origin, 0.35, 0.4, 6.0, Color(0.97, 0.96, 0.93), K.CONCRETE, 10)
	b.cylinder(W(Vector3(0, 0.4, 12)), 3.0, 3.2, 0.8, Color(0.7, 0.68, 0.64), K.CONCRETE, 16)
	b.cylinder(W(Vector3(0, 0.75, 12)), 2.7, 2.7, 0.1, Color(0.3, 0.55, 0.65), K.WATER, 16)
	for sx in [-1.0, 1.0]:
		b.box(X(Vector3(sx * 13.5, 0.9, 20.2)), Vector3(14.0, 1.8, 0.6), Color(0.6, 0.58, 0.54), K.CONCRETE)
		cols.add(X(Vector3(sx * 13.5, 0.9, 20.2)), Vector3(14.0, 1.8, 0.6))
	_trees(8, 19.0, 13.0, Vector2(1.0, 1.5))
	var owner: String = SURNAMES[posmod(i * 3 + j, SURNAMES.size())]
	_place("home", "%s Estate" % owner, e, {"tags": ["home", "sleep", "food"], "capacity": 6, "price": 3, "jobs": [_job("Gardener", 15, 8.0, 15.0, 1), _job("Housekeeper", 15, 8.0, 16.0, 1)]})


func _vineyard() -> void:
	_lot_ground(Color(0.5, 0.45, 0.32), K.DIRT)
	for r in 9:
		var z := -18.0 + r * 3.4
		b.box(X(Vector3(-4, 0.7, z)), Vector3(28.0, 1.4, 0.7), Color(0.28, 0.45, 0.2), K.FOLIAGE)
	var xf := pad(14, 0, -PI * 0.5, 10.0, 12.0)
	var e := facade(xf, 10.0, 12.0, 5.0, Color(0.82, 0.72, 0.56), K.WOOD, {"sign": "CALDER HILLS WINERY", "gable": true, "rise": 2.5, "max_rows": 1})
	_place("winery", "Calder Hills Winery", e, {"tags": ["leisure", "food", "social", "work"], "open": 10.0, "close": 20.0, "capacity": 20, "price": 2, "jobs": [_job("Vineyard worker", 14, 6.0, 14.0, 3), _job("Tasting host", 15, 12.0, 20.0, 1)]})


func _observatory() -> void:
	_lot_ground(Color(0.4, 0.54, 0.3), K.GRASS)
	var xf := pad(0, 0, PI, 16.0, 16.0)
	var e := facade(xf, 16.0, 16.0, 7.0, Color(0.88, 0.88, 0.86), K.CONCRETE, {"sign": "CALDER OBSERVATORY", "max_rows": 1})
	b.sphere((xf * Transform3D(Basis.IDENTITY, Vector3(0, 7.4, 0))).origin, Vector3(6.5, 5.5, 6.5), Color(0.85, 0.87, 0.9), K.METAL, 16)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 11.0, 0)), Vector3(1.2, 4.0, 6.0), Color(0.2, 0.22, 0.25), K.METAL)
	_sky(xf, Vector3(16, 13, 16), Color(0.88, 0.88, 0.86), K.CONCRETE)
	_place("observatory", "Calder Observatory", e, {"tags": ["leisure", "work"], "open": 12.0, "close": 24.0, "capacity": 25, "price": 1, "jobs": [_job("Astronomy guide", 18, 16.0, 24.0, 2)]})


# ------------------------------------------------------------------ Neon Row
const CLUB_NAMES := ["The Velvet Room", "Pulse", "Blue Lantern Bar", "Night Owl Lounge", "Static Club", "Copper Tap", "Moonshine Saloon", "Echo Bar", "Prism Club"]
const NEON := [Color(1.0, 0.25, 0.7), Color(0.25, 0.9, 1.0), Color(0.6, 0.3, 1.0), Color(1.0, 0.8, 0.2), Color(0.3, 1.0, 0.5)]


func _nightlife() -> void:
	_lot_ground(Color(0.3, 0.3, 0.33), K.TILES)
	var k := 0
	for side in [-1.0, 1.0]:
		for lx in [-11.0, 11.0]:
			var w := rng.randf_range(16.0, 19.0)
			var d := rng.randf_range(12.0, 14.0)
			var lz: float = side * (21.0 - 1.0 - d * 0.5)
			var yaw := front_yaw(lz)
			var xf := pad(lx, lz, yaw, w, d)
			var neon: Color = NEON[posmod(i + j + k, NEON.size())]
			var nm: String = CLUB_NAMES[posmod(i * 3 + j * 5 + k, CLUB_NAMES.size())]
			var e := facade(xf, w, d, rng.randf_range(6.5, 10.0), Color(0.18, 0.18, 0.22).lerp(Color(0.35, 0.2, 0.3), rng.randf()), K.BRICK, {"sign": nm, "sign_color": neon, "sign_size": 84, "frame": neon.darkened(0.3), "max_rows": 2})
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.08, d * 0.5 + 0.1)), Vector3(w - 1.0, 0.16, 0.06), neon, K.SIGN)
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + 0.5, 4.0, d * 0.5 + 0.1)), Vector3(0.12, 7.0, 0.06), neon, K.SIGN)
			_sky(xf, Vector3(w, 9, d), Color(0.2, 0.2, 0.25), K.BRICK)
			var club := k % 2 == 0
			_place("club" if club else "bar", nm, e, {"tags": ["nightlife", "social", "leisure", "food", "work"], "open": 18.0, "close": 3.0, "capacity": 40, "price": 2, "jobs": [
				_job("Bartender", 16, 18.0, 2.0, 2), _job("DJ" if club else "Server", 18 if club else 14, 20.0, 3.0, 1), _job("Bouncer", 17, 20.0, 3.0, 1)]})
			k += 1


func _cinema() -> void:
	_lot_ground(Color(0.32, 0.32, 0.35), K.TILES)
	var xf := pad(0, -6, PI, 30.0, 22.0)
	var e := facade(xf, 30.0, 22.0, 11.0, Color(0.55, 0.18, 0.2), K.PAINT, {"sign": "GRAND CINEMA", "sign_color": Color(1, 0.85, 0.3), "sign_size": 110, "windows": false})
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.6, 12.0)), Vector3(18.0, 1.6, 2.2), Color(0.95, 0.85, 0.4), K.SIGN)
	for k in 4:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-12 + k * 8.0, 2.2, 11.06)), Vector3(2.4, 3.4, 0.08), Color.from_hsv(rng.randf(), 0.6, 0.8), K.SIGN)
	_sky(xf, Vector3(30, 11, 22), Color(0.55, 0.18, 0.2), K.PAINT)
	_place("cinema", "Grand Cinema", e, {"tags": ["leisure", "social", "shelter", "work"], "open": 12.0, "close": 24.0, "capacity": 80, "price": 2, "jobs": [_job("Usher", 13, 16.0, 24.0, 2), _job("Projectionist", 16, 14.0, 24.0, 1)]})


func _bowling() -> void:
	_lot_ground(Color(0.32, 0.32, 0.35), K.TILES)
	var xf := pad(-4, 2, PI, 30.0, 18.0)
	var e := facade(xf, 30.0, 18.0, 7.0, Color(0.25, 0.45, 0.75), K.PAINT, {"sign": "STRIKE ZONE BOWL & ARCADE", "sign_color": Color(1.0, 0.35, 0.35), "windows": false})
	var pin := (xf * Transform3D(Basis.IDENTITY, Vector3(13, 7.5, 6))).origin
	b.cylinder(pin + Vector3(0, 2.5, 0), 0.6, 1.0, 5.0, Color(0.97, 0.97, 0.95), K.PAINT, 10)
	b.sphere(pin + Vector3(0, 5.6, 0), Vector3(0.7, 0.9, 0.7), Color(0.97, 0.97, 0.95), K.PAINT, 10)
	b.box(Transform3D(Basis.IDENTITY, pin + Vector3(0, 4.4, 0)), Vector3(1.3, 0.3, 1.3), Color(0.9, 0.1, 0.1), K.PAINT)
	_sky(xf, Vector3(30, 13, 18), Color(0.25, 0.45, 0.75), K.PAINT)
	_place("arcade", "Strike Zone Bowl & Arcade", e, {"tags": ["leisure", "sports", "social", "work"], "open": 11.0, "close": 1.0, "capacity": 50, "price": 1, "jobs": [_job("Lane attendant", 13, 15.0, 1.0, 2)]})


func _arena() -> void:
	_lot_ground(Color(0.6, 0.6, 0.58), K.CONCRETE)
	var cpos := W(Vector3(0, 0, 0))
	b.cylinder(cpos + Vector3(0, 7.0, 0), 18.5, 20.0, 14.0, Color(0.78, 0.78, 0.8), K.CONCRETE, 28)
	b.cylinder(cpos + Vector3(0, 14.6, 0), 15.0, 19.0, 1.2, Color(0.4, 0.45, 0.55), K.METAL, 28)
	cols.add_box(cpos + Vector3(0, 7.0, 0), Vector3(36.0, 14.0, 36.0))
	b.box(Transform3D(Basis.IDENTITY, cpos + Vector3(0, 5.0, 19.8)), Vector3(14.0, 2.0, 0.3), Color(0.2, 0.3, 0.6), K.SIGN)
	cb.sign_label(node, "CALDER ARENA", cpos + Vector3(0, 5.0, 19.95), 0.0, 120)
	cb.add_to_skyline(cpos, Vector3(38, 15, 38), Color(0.78, 0.78, 0.8), K.CONCRETE)
	_place("arena", "Calder Arena", cpos + Vector3(0, 0, 21.0), {"tags": ["leisure", "sports", "social", "work"], "open": 10.0, "close": 23.0, "capacity": 200, "price": 2, "jobs": [_job("Arena staff", 14, 16.0, 23.0, 4), _job("Groundskeeper", 15, 8.0, 16.0, 1)]})


func _concert_hall() -> void:
	_lot_ground(Color(0.7, 0.68, 0.64), K.TILES)
	var xf := pad(0, -4, PI, 32.0, 22.0)
	var e := facade(xf, 32.0, 22.0, 12.0, Color(0.88, 0.86, 0.8), K.CONCRETE, {"sign": "WESTBRIDGE CONCERT HALL", "max_rows": 3})
	b.sphere((xf * Transform3D(Basis.IDENTITY, Vector3(0, 12.2, 0))).origin, Vector3(14.0, 5.0, 9.0), Color(0.55, 0.65, 0.72), K.METAL, 16)
	_sky(xf, Vector3(32, 17, 22), Color(0.88, 0.86, 0.8), K.CONCRETE)
	_place("concert_hall", "Westbridge Concert Hall", e, {"tags": ["leisure", "social", "shelter", "work"], "open": 17.0, "close": 24.0, "capacity": 120, "price": 2, "jobs": [_job("Stage hand", 16, 16.0, 24.0, 2), _job("Box office clerk", 14, 15.0, 23.0, 1)]})


func _fun_park() -> void:
	_lot_ground(Color(0.75, 0.72, 0.66), K.TILES)
	# Ferris wheel
	var hub := W(Vector3(-8, 13.0, -6))
	var wheel_basis := Basis(Vector3.FORWARD, 0.0) * Basis(Vector3.RIGHT, PI * 0.5)
	var tor := TorusMesh.new()
	tor.inner_radius = 10.4
	tor.outer_radius = 11.0
	tor.rings = 32
	tor.ring_segments = 6
	b.primitive(tor, Transform3D(wheel_basis, hub), Color(0.92, 0.92, 0.95), K.METAL)
	for k in 12:
		var a := TAU * k / 12.0
		var dir := Vector3(cos(a), sin(a), 0)
		b.box(Transform3D(Basis(Vector3.BACK, a), hub + dir * 5.3), Vector3(10.6, 0.15, 0.15), Color(0.8, 0.8, 0.85), K.METAL)
		b.box(Transform3D(Basis.IDENTITY, hub + dir * 10.7 - Vector3(0, 0.9, 0)), Vector3(1.4, 1.2, 1.4), Color.from_hsv(k / 12.0, 0.6, 0.9), K.PAINT)
	for sx in [-1.0, 1.0]:
		b.box(Transform3D(Basis(Vector3.BACK, sx * 0.3), W(Vector3(-8 + sx * 3.5, 6.5, -6))), Vector3(0.5, 13.5, 0.5), Color(0.85, 0.2, 0.2), K.METAL)
	cols.add_box(W(Vector3(-8, 6.5, -6)), Vector3(9.0, 13.0, 1.5))
	# Carousel
	var cp := W(Vector3(10, 0, 8))
	b.cylinder(cp + Vector3(0, 0.3, 0), 5.0, 5.0, 0.6, Color(0.9, 0.85, 0.6), K.WOOD, 18)
	b.cylinder(cp + Vector3(0, 2.2, 0), 0.4, 0.4, 3.8, Color(0.95, 0.8, 0.3), K.METAL, 8)
	b.cylinder(cp + Vector3(0, 4.6, 0), 0.0, 5.6, 1.8, Color(0.9, 0.25, 0.35), K.PAINT, 18)
	cols.add_box(cp + Vector3(0, 1.5, 0), Vector3(9.0, 3.0, 9.0))
	b.cylinder(W(Vector3(0, 0, 0)) + Vector3(0, 6.0, 0), 0.1, 0.1, 12.0, Color(0.9, 0.9, 0.9), K.METAL, 6)
	cb.add_to_skyline(hub, Vector3(22, 24, 2), Color(0.92, 0.92, 0.95), K.METAL)
	for k in 3:
		var sxf := X(Vector3(-16 + k * 6.0, 0, 15), 0.0)
		b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)), Vector3(3.0, 2.4, 2.4), Color.from_hsv(rng.randf(), 0.5, 0.95), K.PAINT)
		b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 0.4)), Vector3(3.4, 0.2, 3.4), Color(0.95, 0.95, 0.95), K.PAINT)
		cols.add(sxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)), Vector3(3.0, 2.4, 2.4))
	cb.sign_label(node, "NEON ROW FUN PARK", W(Vector3(0, 4.0, 20.0)), 0.0, 96, Color(1.0, 0.6, 0.9))
	_place("fun_park", "Neon Row Fun Park", W(Vector3(0, 0, 20.5)), {"tags": ["leisure", "outdoor", "social", "food", "work"], "open": 12.0, "close": 24.0, "capacity": 120, "price": 2, "jobs": [_job("Ride operator", 14, 12.0, 20.0, 3), _job("Snack vendor", 13, 14.0, 24.0, 2)]})


# ------------------------------------------------------------------ Westbridge Beach
func _beach_shops() -> void:
	_lot_ground(Color(0.78, 0.74, 0.62), K.TILES)
	var shops := [["Surf Shack", "shop", ["shop", "work"]], ["Scoops Ice Cream", "food", ["food", "social"]], ["The Salty Pelican", "diner", ["food", "social", "nightlife"]], ["Driftwood Coffee", "cafe", ["coffee", "food"]]]
	var k := 0
	for side in [-1.0, 1.0]:
		for lx in [-10.5, 10.5]:
			var s: Array = shops[posmod(k + i, shops.size())]
			var lz: float = side * 13.5
			var yaw := front_yaw(lz)
			var xf := pad(lx, lz, yaw, 16.0, 10.0)
			var wall: Color = BEACH_COLORS[posmod(k + j + i, BEACH_COLORS.size())]
			var e := BuildingKit.shopfront(b, cols, xf, 16.0, 10.0, 2, wall, K.PAINT, Color.from_hsv(rng.randf(), 0.55, 0.85), Color(0.2, 0.3, 0.45), rng)
			cb.sign_label(node, s[0], (xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.55, 5.25))).origin, yaw, 64)
			_sky(xf, Vector3(16, 7, 10), wall, K.PAINT)
			var tags: Array = (s[2] as Array).duplicate()
			tags.append("work")
			_place(s[1], s[0], e, {"tags": tags, "open": 8.0, "close": 22.0, "capacity": 20, "price": 1, "jobs": [_job("Staff", 13, 8.0, 16.0, 2), _job("Staff (late)", 14, 14.0, 22.0, 1)]})
			k += 1


func _pier_plaza() -> void:
	_plaza("Pier Plaza")
	for k in 3:
		var xf := X(Vector3(-14 + k * 14.0, 0, -16), PI)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(4.6, 2.6, 2.2), Color.from_hsv(rng.randf(), 0.4, 0.95), K.PAINT)
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(4.6, 2.6, 2.2))
	_place("food_stand", "Pier Taco Truck", W(Vector3(0, 0, -14.0)), {"tags": ["food", "social", "work"], "open": 11.0, "close": 22.0, "capacity": 12, "jobs": [_job("Taco cook", 14, 11.0, 19.0, 1)]})


func _resort() -> void:
	_lot_ground(Color(0.85, 0.82, 0.72), K.TILES)
	var xf := pad(0, -8, PI, 30.0, 14.0)
	var e := BuildingKit.tower(b, cols, xf, 30.0, 14.0, 8, Color(0.97, 0.96, 0.92), rng)
	cb.sign_label(node, "PALM COVE RESORT", (xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.6, 7.1))).origin, PI, 90, Color(0.2, 0.55, 0.7))
	_sky(xf, Vector3(30, 28, 14), Color(0.97, 0.96, 0.92), K.GLASS)
	b.box(X(Vector3(0, 0.02, 10)), Vector3(18.0, 0.04, 8.0), Color(0.3, 0.68, 0.82), K.WATER)
	_trees(8, 19.0, 0.0, Vector2(0.8, 1.1))
	_place("hotel", "Palm Cove Resort", e, {"tags": ["sleep", "food", "leisure", "nightlife", "work"], "capacity": 60, "price": 3, "jobs": [_job("Receptionist", 16, 7.0, 15.0, 2), _job("Housekeeper", 14, 8.0, 16.0, 3), _job("Pool attendant", 13, 10.0, 18.0, 1)]})


func _marina() -> void:
	_lot_ground(Color(0.72, 0.7, 0.64), K.CONCRETE)
	var xf := pad(-10, -8, PI, 14.0, 10.0)
	var e := facade(xf, 14.0, 10.0, 5.0, Color(0.92, 0.92, 0.9), K.WOOD, {"sign": "WESTBRIDGE MARINA", "max_rows": 1, "trim": Color(0.2, 0.35, 0.6)})
	for k in 4:
		_boat(X(Vector3(-12 + k * 8.0, 0.9, 10), 0.0), 7.0 + rng.randf() * 3.0)
	_place("marina", "Westbridge Marina", e, {"tags": ["work", "leisure", "outdoor"], "open": 6.0, "close": 20.0, "capacity": 20, "jobs": [_job("Dock hand", 15, 6.0, 14.0, 3), _job("Boat mechanic", 19, 8.0, 17.0, 1)]})


func _boat(xf: Transform3D, length: float) -> void:
	b.box(xf, Vector3(2.6, 1.2, length), Color(0.96, 0.96, 0.95), K.PAINT)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.9, -length * 0.1)), Vector3(2.0, 0.8, length * 0.4), Color(0.9, 0.9, 0.92), K.PAINT)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.4, 0)), Vector3(2.62, 0.3, length), Color(0.15, 0.25, 0.5), K.PAINT)
	cols.add(xf, Vector3(2.6, 1.6, length))


func _lighthouse() -> void:
	_lot_ground(Color(0.42, 0.56, 0.32), K.GRASS)
	var base := W(Vector3(6, 0, 4))
	for k in 6:
		b.cylinder(base + Vector3(0, 2.2 + k * 4.0, 0), 2.6 - k * 0.15, 2.75 - k * 0.15, 4.0, Color(0.95, 0.95, 0.93) if k % 2 == 0 else Color(0.85, 0.15, 0.15), K.PAINT, 16)
	b.cylinder(base + Vector3(0, 25.5, 0), 1.6, 1.6, 2.6, Color(1.0, 0.95, 0.7), K.SIGN, 12)
	b.cylinder(base + Vector3(0, 27.6, 0), 0.0, 2.0, 1.6, Color(0.15, 0.15, 0.17), K.METAL, 12)
	cols.add_box(base + Vector3(0, 13.0, 0), Vector3(5.0, 26.0, 5.0))
	cb.add_to_skyline(base, Vector3(5, 29, 5), Color(0.95, 0.95, 0.93), K.PAINT)
	cb.lamp_positions.append(base + Vector3(0, 25.5, 0))
	var sp: Array = []
	for k in 4:
		sp.append(_bench_seat(Vector3(-14 + k * 6.0, 0, -12), PI))
	_trees(8, 19.0, 9.0)
	var p := _place("park", "Lighthouse Point", W(Vector3(0, 0, -20.5)), {"tags": ["outdoor", "free", "leisure", "social"], "capacity": 30, "price": 0, "jobs": [_job("Lighthouse keeper", 16, 18.0, 6.0, 1)]})
	if cb.data_mode:
		p.spots.append_array(sp)


# ------------------------------------------------------------------ Harbor Industrial
func _factory() -> void:
	_lot_ground(Color(0.5, 0.5, 0.5), K.CONCRETE)
	var xf := pad(0, -4, PI, 36.0, 24.0)
	var e := facade(xf, 36.0, 24.0, 11.0, Color(0.62, 0.6, 0.56), K.METAL, {"sign": "CALDER STEEL WORKS", "max_rows": 1, "canopy": false})
	for k in 4:
		b.gable_roof(xf * Transform3D(Basis.IDENTITY, Vector3(-13.5 + k * 9.0, 11.4, 0)), Vector3(8.6, 0, 24.0), 2.2, Color(0.45, 0.47, 0.5), Color(0.6, 0.6, 0.58))
	for sx in [-10.0, -4.0]:
		var p := (xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0, -8))).origin
		b.cylinder(p + Vector3(0, 14.0, 0), 0.9, 1.2, 28.0, Color(0.55, 0.42, 0.36), K.BRICK, 12)
		cols.add_box(p + Vector3(0, 14.0, 0), Vector3(2.4, 28.0, 2.4))
		cb.add_to_skyline(p, Vector3(2.4, 28, 2.4), Color(0.55, 0.42, 0.36), K.BRICK)
	_sky(xf, Vector3(36, 13, 24), Color(0.62, 0.6, 0.56), K.METAL)
	_place("factory", "Calder Steel Works", e, {"tags": ["work"], "capacity": 80, "jobs": [_job("Factory worker", 18, 6.0, 14.0, 6), _job("Factory worker (late)", 19, 14.0, 22.0, 5), _job("Factory worker (night)", 21, 22.0, 6.0, 3), _job("Foreman", 26, 7.0, 15.0, 1)]})


func _warehouses() -> void:
	_lot_ground(Color(0.45, 0.45, 0.46), K.ASPHALT)
	var k := 0
	for lz in [-10.0, 10.0]:
		var yaw := front_yaw(lz)
		var xf := pad(-3, lz, yaw, 32.0, 14.0)
		var e := facade(xf, 32.0, 14.0, 8.0, [Color(0.55, 0.6, 0.66), Color(0.68, 0.55, 0.45)][k], K.METAL, {"windows": false, "canopy": false, "sign": ["HARBOR LOGISTICS", "BAYSIDE STORAGE"][k]})
		for d in 3:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-10 + d * 10.0, 2.2, 7.02)), Vector3(4.0, 4.4, 0.1), Color(0.35, 0.36, 0.38), K.METAL)
		_sky(xf, Vector3(32, 8, 14), Color(0.55, 0.6, 0.66), K.METAL)
		_place("warehouse", ["Harbor Logistics", "Bayside Storage"][k], e, {"tags": ["work"], "capacity": 30, "jobs": [_job("Warehouse worker", 15, 6.0, 14.0, 4), _job("Forklift driver", 17, 14.0, 22.0, 2)]})
		k += 1
	PropsKit.car(b, cols, X(Vector3(16, 0, 0), PI * 0.5), Color(0.75, 0.75, 0.72), 1)


func _rail_yard() -> void:
	_lot_ground(Color(0.42, 0.38, 0.32), K.DIRT)
	for t2 in 4:
		var z := -12.0 + t2 * 8.0
		for sx in [-0.72, 0.72]:
			b.box(X(Vector3(0, 0.1, z + sx)), Vector3(44.0, 0.12, 0.1), Color(0.45, 0.42, 0.4), K.METAL)
		var x := -20.0
		while x < 21.0:
			b.box(X(Vector3(x, 0.04, z)), Vector3(0.3, 0.08, 2.4), Color(0.35, 0.25, 0.18), K.WOOD)
			x += 1.0
		if t2 % 2 == 0:
			for car_k in 3:
				var cx := -14.0 + car_k * 12.0
				var col: Color = [Color(0.55, 0.25, 0.18), Color(0.2, 0.35, 0.5), Color(0.45, 0.45, 0.42)][car_k]
				b.box(X(Vector3(cx, 2.0, z)), Vector3(11.0, 3.0, 3.0), col, K.METAL)
				cols.add(X(Vector3(cx, 2.0, z)), Vector3(11.0, 3.0, 3.0))
	var xf := pad(14, 17, 0.0, 8.0, 6.0)
	var e := facade(xf, 8.0, 6.0, 4.0, Color(0.7, 0.6, 0.45), K.BRICK, {"max_rows": 1, "canopy": false, "sign": "YARD OFFICE"})
	_place("rail_yard", "Calder Rail Yard", e, {"tags": ["work"], "capacity": 20, "jobs": [_job("Rail worker", 18, 6.0, 14.0, 4), _job("Yard switcher (night)", 20, 22.0, 6.0, 2)]})


func _scrapyard() -> void:
	_lot_ground(Color(0.4, 0.37, 0.32), K.DIRT)
	for k in 14:
		var p := Vector3(rng.randf_range(-17, 17), 0, rng.randf_range(-15, 12))
		var stack := X(p, rng.randf() * TAU)
		PropsKit.car(b, cols, stack, Color(0.45, 0.35, 0.28).lerp(Color(0.5, 0.5, 0.48), rng.randf()), rng.randi() % 3)
		if rng.randf() < 0.4:
			PropsKit.car(b, cols, stack * Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 1.5, 0)), Color(0.5, 0.3, 0.22), 0)
	_fence(Vector3(-20.5, 0, -20.5), Vector3(20.5, 0, -20.5), Color(0.5, 0.52, 0.5), 2.4)
	_fence(Vector3(-20.5, 0, 20.5), Vector3(8, 0, 20.5), Color(0.5, 0.52, 0.5), 2.4)
	var xf := pad(14, 16, 0.0, 8.0, 6.0)
	var e := facade(xf, 8.0, 6.0, 3.5, Color(0.6, 0.55, 0.45), K.METAL, {"max_rows": 1, "canopy": false, "sign": "RUSTY'S SALVAGE"})
	_place("scrapyard", "Rusty's Salvage", e, {"tags": ["work", "shop"], "open": 7.0, "close": 18.0, "capacity": 10, "jobs": [_job("Salvage worker", 14, 7.0, 15.0, 3)]})


func _fuel_depot() -> void:
	_lot_ground(Color(0.5, 0.5, 0.48), K.CONCRETE)
	for k in 4:
		var p := W(Vector3(-11 + (k % 2) * 18.0, 0, -9 + (k / 2) * 16.0))
		b.cylinder(p + Vector3(0, 4.5, 0), 6.0, 6.0, 9.0, Color(0.9, 0.9, 0.88), K.METAL, 18)
		b.cylinder(p + Vector3(0, 9.2, 0), 0.4, 6.1, 0.8, Color(0.85, 0.85, 0.84), K.METAL, 18)
		cols.add_box(p + Vector3(0, 4.5, 0), Vector3(12.0, 9.0, 12.0))
		cb.add_to_skyline(p, Vector3(12, 9.6, 12), Color(0.9, 0.9, 0.88), K.METAL)
	b.box(X(Vector3(0, 1.0, 0)), Vector3(40.0, 0.4, 0.4), Color(0.75, 0.6, 0.2), K.METAL)
	_place("fuel_depot", "Harbor Fuel Depot", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 10, "jobs": [_job("Fuel technician", 20, 7.0, 15.0, 2), _job("Night watchman", 15, 22.0, 6.0, 1)]})


func _container_port() -> void:
	_lot_ground(Color(0.55, 0.55, 0.54), K.CONCRETE)
	var palette := [Color(0.75, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.2, 0.55, 0.3), Color(0.85, 0.6, 0.15), Color(0.6, 0.6, 0.62), Color(0.45, 0.25, 0.5)]
	for row in 4:
		for col in 3:
			var p := Vector3(-14 + col * 12.5, 0, -14 + row * 6.0)
			var stack := rng.randi_range(1, 3)
			for h in stack:
				b.box(X(p + Vector3(0, 1.3 + h * 2.6, 0)), Vector3(12.0, 2.55, 2.45), palette[rng.randi() % palette.size()], K.METAL, rng.randf())
			cols.add(X(p + Vector3(0, stack * 1.3, 0)), Vector3(12.0, stack * 2.6, 2.45))
	# gantry crane at the quay
	var gx := X(Vector3(0, 0, 16))
	for sx in [-9.0, 9.0]:
		b.box(gx * Transform3D(Basis.IDENTITY, Vector3(sx, 11, 0)), Vector3(1.0, 22.0, 1.0), Color(0.9, 0.55, 0.15), K.METAL)
		cols.add(gx * Transform3D(Basis.IDENTITY, Vector3(sx, 11, 0)), Vector3(1.0, 22.0, 1.0))
	b.box(gx * Transform3D(Basis.IDENTITY, Vector3(0, 22.5, 6.0)), Vector3(20.0, 1.4, 24.0), Color(0.9, 0.55, 0.15), K.METAL)
	cb.add_to_skyline(gx.origin, Vector3(20, 23, 24), Color(0.9, 0.55, 0.15), K.METAL)
	_place("port", "Westbridge Container Port", W(Vector3(-18, 0, -20.5)), {"tags": ["work"], "capacity": 40, "jobs": [_job("Dock worker", 19, 6.0, 14.0, 6), _job("Dock worker (late)", 20, 14.0, 22.0, 4), _job("Crane operator", 26, 7.0, 15.0, 2)]})


func _fish_docks() -> void:
	_lot_ground(Color(0.6, 0.58, 0.54), K.CONCRETE)
	var xf := pad(-6, -8, PI, 22.0, 12.0)
	var e := facade(xf, 22.0, 12.0, 5.5, Color(0.55, 0.65, 0.7), K.WOOD, {"sign": "BAYSIDE FISH MARKET", "gable": true, "rise": 2.0, "max_rows": 1})
	for k in 3:
		_boat(X(Vector3(-12 + k * 10.0, 0.9, 14), PI * 0.5 * (k % 2)), 8.0)
	_place("fish_market", "Bayside Fish Market", e, {"tags": ["groceries", "food", "work"], "open": 5.0, "close": 15.0, "capacity": 25, "jobs": [_job("Fisher", 16, 4.0, 12.0, 4), _job("Fishmonger", 14, 5.0, 13.0, 2)]})


# ------------------------------------------------------------------ Fort Calder
const OLIVE := Color(0.36, 0.4, 0.28)


func _military(kind: String) -> void:
	_lot_ground(Color(0.42, 0.46, 0.33) if kind != "mil_runway" else Color(0.38, 0.4, 0.36), K.GRASS if kind != "mil_runway" else K.CONCRETE)
	var p: Place
	match kind:
		"mil_runway":
			b.floor_quad(W(Vector3(0, 0.02, 0)), Vector2(48.0, 22.0), Color(0.25, 0.26, 0.27), K.ASPHALT)
			var x := -22.0
			while x < 22.0:
				b.floor_quad(W(Vector3(x, 0.03, 0)), Vector2(5.0, 0.6), Color(0.95, 0.95, 0.9), K.ROAD_PAINT)
				x += 9.0
			if posmod(i, 2) == 0:
				_plane(X(Vector3(0, 0, 0), PI * 0.5))
			p = _place("military", "Fort Calder Airfield", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 20, "jobs": [_job("Ground crew", 20, 6.0, 14.0, 3)]})
		"mil_hangar":
			for lx in [-11.0, 11.0]:
				var xf := pad(lx, -2, PI, 18.0, 24.0)
				b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(18.0, 8.0, 24.0), OLIVE, K.METAL)
				b.sphere((xf * Transform3D(Basis.IDENTITY, Vector3(0, 8.0, 0))).origin, Vector3(9.0, 3.5, 12.0), OLIVE.darkened(0.1), K.METAL, 12)
				cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)), Vector3(18.0, 10.0, 24.0))
				_sky(xf, Vector3(18, 11, 24), OLIVE, K.METAL)
			p = _place("military", "Fort Calder Hangars", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 30, "jobs": [_job("Aircraft mechanic", 23, 7.0, 15.0, 4)]})
		"mil_tower":
			var base := W(Vector3(0, 0, -4))
			b.box(Transform3D(Basis.IDENTITY, base + Vector3(0, 9.0, 0)), Vector3(4.0, 18.0, 4.0), Color(0.75, 0.74, 0.7), K.CONCRETE)
			b.box(Transform3D(Basis.IDENTITY, base + Vector3(0, 19.5, 0)), Vector3(7.0, 3.0, 7.0), Color(0.3, 0.4, 0.45), K.GLASS)
			b.box(Transform3D(Basis.IDENTITY, base + Vector3(0, 21.2, 0)), Vector3(8.0, 0.4, 8.0), Color(0.6, 0.6, 0.6), K.CONCRETE)
			cols.add_box(base + Vector3(0, 10.5, 0), Vector3(7.0, 21.0, 7.0))
			cb.add_to_skyline(base, Vector3(7, 21.5, 7), Color(0.75, 0.74, 0.7), K.CONCRETE)
			p = _place("military", "Fort Calder Control Tower", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 8, "jobs": [_job("Air traffic controller", 28, 8.0, 18.0, 2)]})
		"mil_motorpool":
			for k in 8:
				PropsKit.car(b, cols, X(Vector3(-15 + (k % 4) * 10.0, 0, -8 + (k / 4) * 14.0), 0.0), OLIVE.darkened(rng.randf() * 0.2), 1)
			p = _place("military", "Fort Calder Motor Pool", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 15, "jobs": [_job("Army mechanic", 21, 7.0, 15.0, 3)]})
		"mil_barracks":
			for k in 3:
				var xf2 := pad(0, -14 + k * 13.0, 0.0, 36.0, 8.0)
				facade(xf2, 36.0, 8.0, 4.0, Color(0.6, 0.58, 0.5), K.CONCRETE, {"max_rows": 1, "canopy": false})
				_sky(xf2, Vector3(36, 4, 8), Color(0.6, 0.58, 0.5), K.CONCRETE)
			p = _place("barracks", "Fort Calder Barracks", W(Vector3(0, 0, 20.5)), {"tags": ["home", "sleep", "food"], "capacity": 30})
		"mil_hq":
			var xf3 := pad(0, -4, PI, 28.0, 16.0)
			var e := facade(xf3, 28.0, 16.0, 9.0, Color(0.68, 0.66, 0.58), K.CONCRETE, {"sign": "FORT CALDER HEADQUARTERS", "trim": OLIVE})
			for sx in [-6.0, 6.0]:
				var fp := (xf3 * Transform3D(Basis.IDENTITY, Vector3(sx, 0, 12))).origin
				b.cylinder(fp + Vector3(0, 5.0, 0), 0.06, 0.08, 10.0, Color(0.85, 0.85, 0.85), K.METAL, 6)
				b.box(Transform3D(Basis.IDENTITY, fp + Vector3(0.75, 9.3, 0)), Vector3(1.5, 1.0, 0.04), OLIVE if sx < 0 else Color(0.2, 0.3, 0.6), K.PAINT)
			_sky(xf3, Vector3(28, 9, 16), Color(0.68, 0.66, 0.58), K.CONCRETE)
			p = _place("military", "Fort Calder HQ", e, {"tags": ["work"], "capacity": 40, "jobs": [_job("Soldier", 22, 6.0, 14.0, 6), _job("Soldier (night watch)", 24, 22.0, 6.0, 3), _job("Officer", 32, 8.0, 17.0, 2)]})
		"mil_training":
			b.floor_quad(W(Vector3(0, 0.02, 0)), Vector2(40.0, 30.0), Color(0.55, 0.45, 0.33), K.DIRT)
			for k in 6:
				var wx := -16.0 + k * 6.4
				b.box(X(Vector3(wx, 0.9, -6 + (k % 2) * 8.0)), Vector3(3.0, 1.8, 0.4), Color(0.5, 0.4, 0.3), K.WOOD)
				cols.add(X(Vector3(wx, 0.9, -6 + (k % 2) * 8.0)), Vector3(3.0, 1.8, 0.4))
			for k in 8:
				b.cylinder(W(Vector3(-14 + k * 4.0, 0.3, 10)), 0.6, 0.6, 0.6, Color(0.1, 0.1, 0.1), K.PAINT, 10)
			p = _place("military", "Fort Calder Training Ground", W(Vector3(0, 0, 20.5)), {"tags": ["work", "sports"], "capacity": 40, "jobs": [_job("Drill instructor", 25, 6.0, 14.0, 2)]})
		_:
			# Gate: guard house + barrier + sign
			var gxf := pad(8, 14, 0.0, 5.0, 4.0)
			facade(gxf, 5.0, 4.0, 3.2, Color(0.7, 0.68, 0.6), K.CONCRETE, {"max_rows": 1, "canopy": false})
			b.box(X(Vector3(0, 1.0, 19.0)), Vector3(9.0, 0.2, 0.2), Color(0.9, 0.2, 0.2), K.PAINT)
			cb.sign_label(node, "FORT CALDER  -  RESTRICTED AREA", W(Vector3(-8, 3.0, 20.3)), 0.0, 72, Color(1.0, 0.9, 0.3))
			b.box(X(Vector3(-8, 3.0, 20.2)), Vector3(9.0, 1.4, 0.2), OLIVE, K.SIGN)
			p = _place("military", "Fort Calder Main Gate", W(Vector3(0, 0, 20.5)), {"tags": ["work"], "capacity": 6, "jobs": [_job("Gate guard", 20, 6.0, 18.0, 2), _job("Gate guard (night)", 22, 18.0, 6.0, 2)]})
	# perimeter fence on the edges that face the outside of the base
	for side in 4:
		var nb: Vector2i = Vector2i(i, j) + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
		if CityMap.cell_type(nb.x, nb.y).begins_with("mil_"):
			continue
		var a := [Vector3(-20.8, 0, -20.8), Vector3(20.8, 0, -20.8), Vector3(20.8, 0, 20.8), Vector3(-20.8, 0, 20.8)]
		if kind == "mil_gate" and side == 2:
			_fence(a[2], Vector3(5, 0, 20.8), Color(0.55, 0.57, 0.55), 2.8)
			continue
		_fence(a[side], a[(side + 1) % 4], Color(0.55, 0.57, 0.55), 2.8)


func _plane(xf: Transform3D) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 0)), Vector3(2.4, 2.4, 18.0), Color(0.55, 0.58, 0.55), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 1.0)), Vector3(22.0, 0.35, 4.0), Color(0.5, 0.53, 0.5), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 4.2, -8.0)), Vector3(0.3, 3.6, 2.6), Color(0.5, 0.53, 0.5), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, -8.2)), Vector3(7.0, 0.3, 2.0), Color(0.5, 0.53, 0.5), K.METAL)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 0)), Vector3(22.0, 4.4, 18.0))


# ------------------------------------------------------------------ open land
func _forest(n: int) -> void:
	for k in n:
		var p := Vector3(rng.randf_range(-23, 23), 0, rng.randf_range(-23, 23))
		var s := rng.randf_range(0.9, 1.6)
		var yaw := rng.randf() * TAU
		cb.add_pine(W(p) - Vector3(0, HILL_LIFT, 0), s, yaw)


func _field() -> void:
	var crop: Color = [Color(0.75, 0.68, 0.3), Color(0.45, 0.6, 0.25), Color(0.6, 0.55, 0.32)][posmod(i + j, 3)]
	for r in 14:
		var z := -21.0 + r * 3.2
		var pts := [Vector3(-23, 0, z - 0.8), Vector3(23, 0, z - 0.8), Vector3(23, 0, z + 0.8), Vector3(-23, 0, z + 0.8)]
		b.quad_pts(W(pts[3]) + Vector3(0, 0.25, 0), W(pts[2]) + Vector3(0, 0.25, 0), W(pts[1]) + Vector3(0, 0.25, 0), W(pts[0]) + Vector3(0, 0.25, 0), crop, K.FOLIAGE)
	for k in 5:
		b.cylinder(W(Vector3(rng.randf_range(-18, 18), 0.6, rng.randf_range(-18, 18))), 0.65, 0.65, 1.2, Color(0.85, 0.75, 0.4), K.DIRT, 10, Basis(Vector3.RIGHT, PI * 0.5))
	_forest(4)


func _farm() -> void:
	var fxf := pad(-10, -10, PI, 9.0, 8.0)
	var e := BuildingKit.house(b, cols, fxf, 9.0, 8.0, 2, Color(0.95, 0.93, 0.88), Color(0.4, 0.25, 0.2), Color(0.98, 0.98, 0.96), rng)
	var bxf := pad(10, -6, PI * 0.5, 14.0, 10.0)
	b.box(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0)), Vector3(14.0, 7.0, 10.0), Color(0.62, 0.18, 0.14), K.WOOD)
	b.gable_roof(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 7.0, 0)), Vector3(14.6, 0, 10.6), 3.5, Color(0.3, 0.3, 0.32), Color(0.62, 0.18, 0.14))
	b.box(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 2.2, 5.05)), Vector3(4.0, 4.4, 0.1), Color(0.95, 0.95, 0.92), K.WOOD)
	cols.add(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0)), Vector3(14.0, 7.0, 10.0))
	var silo := W(Vector3(18, 0, -16))
	b.cylinder(silo + Vector3(0, 6.0, 0), 2.6, 2.6, 12.0, Color(0.75, 0.76, 0.78), K.METAL, 14)
	b.sphere(silo + Vector3(0, 12.0, 0), Vector3(2.6, 1.6, 2.6), Color(0.7, 0.72, 0.74), K.METAL, 12)
	cols.add_box(silo + Vector3(0, 6.0, 0), Vector3(5.2, 12.0, 5.2))
	cb.add_to_skyline(bxf.origin, Vector3(14, 10, 10), Color(0.62, 0.18, 0.14), K.WOOD)
	cb.add_to_skyline(silo, Vector3(5, 13, 5), Color(0.75, 0.76, 0.78), K.METAL)
	PropsKit.picket_fence(b, cols, W(Vector3(-23, 0, 4)), W(Vector3(23, 0, 4)), Color(0.85, 0.82, 0.75), 0.0, 3.0)
	_field_rows(Vector2(-22, 22), Vector2(6, 22), Color(0.48, 0.62, 0.26))
	PropsKit.car(b, cols, X(Vector3(2, 0, -2), 0.6), Color(0.2, 0.5, 0.2), 1)
	var owner: String = SURNAMES[posmod(i * 5 + j * 7, SURNAMES.size())]
	_place("farm", "%s Farm" % owner, e, {"tags": ["work", "groceries"], "open": 6.0, "close": 18.0, "capacity": 15, "jobs": [_job("Farmhand", 13, 5.0, 13.0, 3), _job("Tractor driver", 15, 6.0, 14.0, 1)]})
	_place("home", "%s farmhouse" % owner, (fxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 5.2))).origin, {"tags": ["home", "sleep", "food"], "capacity": 4})


func _field_rows(xr: Vector2, zr: Vector2, col: Color) -> void:
	var z := zr.x
	while z < zr.y:
		var pts := [Vector3(xr.x, 0, z), Vector3(xr.y, 0, z), Vector3(xr.y, 0, z + 1.4), Vector3(xr.x, 0, z + 1.4)]
		b.quad_pts(W(pts[3]) + Vector3(0, 0.2, 0), W(pts[2]) + Vector3(0, 0.2, 0), W(pts[1]) + Vector3(0, 0.2, 0), W(pts[0]) + Vector3(0, 0.2, 0), col, K.FOLIAGE)
		z += 3.0


func _orchard() -> void:
	for r in 7:
		for k in 7:
			var p := Vector3(-18 + k * 6.0, 0, -18 + r * 6.0)
			cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 0.9)), W(p)))
	var xf := pad(18, 19, 0.0, 5.0, 4.0)
	facade(xf, 5.0, 4.0, 3.0, Color(0.6, 0.45, 0.3), K.WOOD, {"max_rows": 1, "canopy": false})
	_place("orchard", "Golden Bough Orchard", (xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.0))).origin, {"tags": ["work", "outdoor", "leisure", "groceries"], "open": 7.0, "close": 18.0, "capacity": 20, "jobs": [_job("Fruit picker", 12, 6.0, 14.0, 4)]})


func _windmill_farm() -> void:
	for k in 3:
		var base := W(Vector3(-14 + k * 14.0, 0, -6 + (k % 2) * 10.0))
		b.cylinder(base + Vector3(0, 14.0, 0), 0.5, 0.9, 28.0, Color(0.95, 0.95, 0.95), K.PAINT, 10)
		var hub := base + Vector3(0, 28.0, 1.2)
		b.box(Transform3D(Basis.IDENTITY, hub + Vector3(0, 0, -1.0)), Vector3(1.2, 1.2, 3.0), Color(0.95, 0.95, 0.95), K.PAINT)
		for bl in 3:
			var a := TAU * bl / 3.0 + k
			b.box(Transform3D(Basis(Vector3.BACK, a), hub + Vector3(cos(a + PI * 0.5), sin(a + PI * 0.5), 0) * 6.0), Vector3(0.6, 12.0, 0.15), Color(0.97, 0.97, 0.97), K.PAINT)
		cols.add_box(base + Vector3(0, 14.0, 0), Vector3(1.8, 28.0, 1.8))
		cb.add_to_skyline(base, Vector3(2, 34, 2), Color(0.95, 0.95, 0.95), K.PAINT)
	_field_rows(Vector2(-22, 22), Vector2(8, 22), Color(0.55, 0.6, 0.28))
	_place("energy", "Calder Wind Farm", W(Vector3(0, 0, -21)), {"tags": ["work"], "capacity": 6, "jobs": [_job("Turbine technician", 22, 8.0, 16.0, 2)]})


func _campground() -> void:
	var sp: Array = []
	for k in 6:
		var p := Vector3(-15 + (k % 3) * 15.0, 0, -10 + (k / 3) * 14.0)
		var xf := X(p, rng.randf() * TAU)
		b.gable_roof(xf, Vector3(2.4, 0, 3.0), 1.7, Color.from_hsv(rng.randf(), 0.55, 0.75), Color.from_hsv(rng.randf(), 0.55, 0.7))
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Vector3(2.4, 1.6, 3.0))
	b.cylinder(W(Vector3(0, 0.15, 2)), 0.9, 1.0, 0.3, Color(0.4, 0.38, 0.35), K.CONCRETE, 10)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		sp.append(_bench_seat(Vector3(cos(a) * 3.2, 0, 2 + sin(a) * 3.2), face_yaw(Vector3(cos(a) * 3.2, 0, 2 + sin(a) * 3.2), Vector3(0, 0, 2))))
	_forest(18)
	var p2 := _place("campground", "Pinecrest Campground", W(Vector3(0, 0, 21)), {"tags": ["outdoor", "leisure", "free", "social"], "capacity": 30, "price": 0, "jobs": [_job("Park ranger", 17, 8.0, 18.0, 1)]})
	if cb.data_mode:
		p2.spots.append_array(sp)


func _rural_gas() -> void:
	var cxf := X(Vector3(0, 0, 6), 0.0)
	b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)), Vector3(16.0, 0.6, 9.0), Color(0.9, 0.2, 0.15), K.PAINT)
	for sx in [-6.0, 6.0]:
		b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(sx, 2.4, 0)), Vector3(0.4, 4.8, 0.4), Color(0.85, 0.85, 0.85), K.METAL)
		cols.add(cxf * Transform3D(Basis.IDENTITY, Vector3(sx, 2.4, 0)), Vector3(0.4, 4.8, 0.4))
		b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.5, 0.8, 0)), Vector3(0.9, 1.6, 0.6), Color(0.9, 0.9, 0.9), K.PAINT)
		cols.add(cxf * Transform3D(Basis.IDENTITY, Vector3(sx * 0.5, 0.8, 0)), Vector3(0.9, 1.6, 0.6))
	b.floor_quad(W(Vector3(0, 0.02, 4)), Vector2(24, 18), Color(0.32, 0.33, 0.35), K.ASPHALT)
	var sxf := pad(0, -10, 0.0, 14.0, 8.0)
	var e := BuildingKit.shopfront(b, cols, sxf, 14.0, 8.0, 1, Color(0.95, 0.93, 0.88), K.PAINT, Color(0.9, 0.2, 0.15), Color(0.9, 0.2, 0.15), rng)
	cb.sign_label(node, "ROUTE 9 GAS & SNACKS", (sxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.55, 4.2))).origin, 0.0, 60)
	cb.add_to_skyline(sxf.origin, Vector3(14, 4, 8), Color(0.95, 0.93, 0.88), K.PAINT)
	_place("gas_station", "Route 9 Gas & Snacks", e, {"tags": ["food", "groceries", "coffee", "shop", "work"], "capacity": 10, "jobs": [_job("Gas station attendant", 13, 6.0, 14.0, 1), _job("Night attendant", 15, 22.0, 6.0, 1)]})


func _hill_park() -> void:
	var sp: Array = []
	for k in 3:
		var lp := Vector3(-12 + k * 12.0, 0, rng.randf_range(-6, 6))
		sp.append(_bench_seat(lp, PI))
	_forest(14)
	_trees(6, 18.0)
	var p := _place("park", ["Summit Park", "Ridge Meadow", "Highland Green", "Calder Heights Park"][posmod(i, 4)], W(Vector3(0, 0, 21)), {"tags": ["outdoor", "free", "jog", "leisure"], "capacity": 25, "price": 0})
	if cb.data_mode:
		p.spots.append_array(sp)


func _lookout() -> void:
	var deck := X(Vector3(0, 0.6, 0))
	b.box(deck, Vector3(14.0, 0.4, 10.0), Color(0.55, 0.42, 0.3), K.WOOD)
	cols.add(deck, Vector3(14.0, 0.4, 10.0))
	for side in [-1.0, 1.0]:
		b.box(deck * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, side * 5.0)), Vector3(14.0, 0.1, 0.1), Color(0.4, 0.3, 0.22), K.WOOD)
	var sp: Array = []
	for k in 3:
		sp.append(_bench_seat(Vector3(-4 + k * 4.0, 0.8, 2.0), 0.0))
	b.cylinder(W(Vector3(5, 1.6, -3)), 0.06, 0.08, 1.4, Color(0.3, 0.3, 0.32), K.METAL, 6)
	b.box(X(Vector3(5, 2.4, -3)), Vector3(0.5, 0.25, 0.6), Color(0.2, 0.2, 0.22), K.METAL)
	_forest(10)
	var p := _place("park", "Calder Lookout", W(Vector3(0, 0, 21)), {"tags": ["outdoor", "free", "leisure", "social"], "capacity": 20, "price": 0})
	if cb.data_mode:
		p.spots.append_array(sp)


func _radio_tower() -> void:
	var base := W(Vector3(0, 0, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Transform3D(Basis(Vector3.BACK, -sx * 0.04) * Basis(Vector3.RIGHT, sz * 0.04), base + Vector3(sx * 1.6, 20.0, sz * 1.6)), Vector3(0.25, 40.0, 0.25), Color(0.85, 0.25, 0.2), K.METAL)
	for h in 10:
		b.box(Transform3D(Basis.IDENTITY, base + Vector3(0, 2.0 + h * 4.0, 0)), Vector3(3.6 - h * 0.12, 0.15, 3.6 - h * 0.12), Color(0.95, 0.95, 0.95), K.METAL)
	b.sphere(base + Vector3(0, 40.5, 0), Vector3(0.4, 0.4, 0.4), Color(1.0, 0.2, 0.1), K.SIGN, 8)
	cols.add_box(base + Vector3(0, 20.0, 0), Vector3(3.6, 40.0, 3.6))
	cb.add_to_skyline(base, Vector3(3.6, 41, 3.6), Color(0.85, 0.25, 0.2), K.METAL)
	cb.lamp_positions.append(base + Vector3(0, 40.5, 0))
	var xf := pad(10, 10, 0.0, 6.0, 5.0)
	facade(xf, 6.0, 5.0, 3.0, Color(0.75, 0.75, 0.72), K.CONCRETE, {"max_rows": 1, "canopy": false})
	_forest(16)
	_place("radio", "KWBR Radio Tower", (xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.6))).origin, {"tags": ["work"], "capacity": 5, "jobs": [_job("Broadcast technician", 21, 9.0, 17.0, 1)]})


# ------------------------------------------------------------------ beach & corridor
func _beach(pier: bool) -> void:
	var sp: Array = []
	for k in 6:
		var lp := Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-18, 0))
		if CityMap.height_at(c.x + lp.x, c.z + lp.z) < CityMap.SEA_LEVEL + 0.2:
			continue
		var top := W(lp)
		b.cylinder(top + Vector3(0, 1.2, 0), 0.04, 0.04, 2.4, Color(0.9, 0.9, 0.9), K.METAL, 6)
		b.cylinder(top + Vector3(0, 2.4, 0), 0.0, 1.4, 0.5, Color.from_hsv(rng.randf(), 0.6, 0.95), K.PAINT, 10)
		b.floor_quad(top + Vector3(0.9, 0.02, 0.6), Vector2(0.9, 1.9), Color.from_hsv(rng.randf(), 0.5, 0.95), K.PAINT)
	# lifeguard tower
	var lg := X(Vector3(8, 0, -10), 0.0)
	b.box(lg * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 0)), Vector3(2.6, 1.8, 2.6), Color(0.95, 0.85, 0.3), K.PAINT)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(lg * Transform3D(Basis.IDENTITY, Vector3(sx * 1.1, 0.9, sz * 1.1)), Vector3(0.15, 1.8, 0.15), Color(0.9, 0.9, 0.9), K.WOOD)
	cols.add(lg * Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)), Vector3(2.6, 3.5, 2.6))
	if pier:
		var start := W(Vector3(0, 0, -10))
		var length := 70.0
		var deck_y := maxf(start.y, CityMap.SEA_LEVEL + 1.4) + 0.4
		var pxf := Transform3D(Basis.IDENTITY, Vector3(start.x, deck_y, start.z + length * 0.5))
		b.box(pxf, Vector3(5.0, 0.35, length), Color(0.55, 0.42, 0.3), K.WOOD)
		cols.add(pxf, Vector3(5.0, 0.35, length))
		for side in [-1.0, 1.0]:
			b.box(pxf * Transform3D(Basis.IDENTITY, Vector3(side * 2.4, 0.6, 0)), Vector3(0.12, 0.9, length), Color(0.45, 0.35, 0.25), K.WOOD)
			cols.add(pxf * Transform3D(Basis.IDENTITY, Vector3(side * 2.4, 0.6, 0)), Vector3(0.15, 1.0, length))
		var z := 3.0
		while z < length:
			for side in [-1.0, 1.0]:
				b.cylinder(Vector3(start.x + side * 2.0, (deck_y + CityMap.SEA_LEVEL - 2.0) * 0.5, start.z + z), 0.2, 0.2, deck_y - CityMap.SEA_LEVEL + 2.0, Color(0.4, 0.3, 0.22), K.WOOD, 6)
			z += 6.0
		for k in 3:
			var bz := -10.0 + 20.0 + k * 15.0
			var ground := CityMap.height_at(c.x - 1.6, c.z + bz)
			sp.append(_bench_seat(Vector3(-1.6, deck_y + 0.18 - ground - HILL_LIFT, bz), PI * 0.5))
	var p := _place("beach" if not pier else "pier", "Westbridge Beach" if not pier else "Westbridge Pier", W(Vector3(0, 0, -22)), {"tags": ["outdoor", "free", "leisure", "social", "sports"], "capacity": 60, "price": 0})
	if cb.data_mode:
		p.spots.append_array(sp)


func _beach_marina() -> void:
	_beach(false)
	for k in 3:
		var dx := -14.0 + k * 14.0
		var start := W(Vector3(dx, 0, -6))
		var deck_y := maxf(start.y, CityMap.SEA_LEVEL + 1.0) + 0.3
		var dxf := Transform3D(Basis.IDENTITY, Vector3(start.x, deck_y, start.z + 20.0))
		b.box(dxf, Vector3(2.4, 0.3, 40.0), Color(0.55, 0.42, 0.3), K.WOOD)
		cols.add(dxf, Vector3(2.4, 0.3, 40.0))
		for bk in 2:
			_boat(Transform3D(Basis.IDENTITY, Vector3(start.x + 3.0, CityMap.SEA_LEVEL + 0.5, start.z + 14.0 + bk * 14.0)), 8.0)


func _corridor() -> void:
	# Route 9 street lights (the road itself is built by RoadBuilder).
	var lx := c.x - CityMap.PITCH * 0.5 + 10.0
	while lx < c.x + CityMap.PITCH * 0.5:
		var y := CityMap.road_height_at(lx, CityMap.HIGHWAY_Z)
		for side in [-1.0, 1.0]:
			cb.lamp_positions.append(Vector3(lx, y + 8.7, CityMap.HIGHWAY_Z + side * 2.2))
		lx += 29.0
