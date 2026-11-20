class_name CityBlocks
extends RefCounted
## Builds the content of each city block (buildings, props, places, interiors).
## Block-local frame: origin = block centre, north = -Z. Usable lot = |x|,|z| < 21,
## sidewalk ring 21..24 (raised 0.15 m).

const K := GeoBatch.Kind
const Y := CityMap.CURB_H
const HOUSE_COLORS := [Color(0.93, 0.89, 0.8), Color(0.66, 0.78, 0.86), Color(0.86, 0.75, 0.6), Color(0.72, 0.82, 0.7),
	Color(0.92, 0.82, 0.62), Color(0.78, 0.66, 0.7), Color(0.6, 0.66, 0.72), Color(0.95, 0.95, 0.93)]
const ROOF_COLORS := [Color(0.35, 0.28, 0.25), Color(0.25, 0.27, 0.32), Color(0.45, 0.25, 0.2), Color(0.3, 0.33, 0.3)]
const CAR_COLORS := [Color(0.15, 0.42, 0.22), Color(0.7, 0.12, 0.1), Color(0.85, 0.85, 0.85), Color(0.15, 0.18, 0.35),
	Color(0.12, 0.12, 0.13), Color(0.55, 0.55, 0.58), Color(0.85, 0.65, 0.2), Color(0.35, 0.55, 0.7)]

var cb: CityBuilder
var b: GeoBatch
var cols: ColliderSet
var node: Node3D
var c: Vector3
var ring: Array
var rng: RandomNumberGenerator
var i: int
var j: int


func _init(p_builder: CityBuilder) -> void:
	cb = p_builder
	rng = cb.rng


## Local -> world transform helper (yaw: 0 faces +Z/south, PI faces north, PI/2 east, -PI/2 west).
func X(local: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), c + Vector3(local.x, Y + local.y, local.z))


func W(local: Vector3) -> Vector3:
	return c + Vector3(local.x, Y + local.y, local.z)


## Seat yaw so a sitter at p faces `target` (body forward is -Z).
static func face_yaw(p: Vector3, target: Vector3) -> float:
	return atan2(p.x - target.x, p.z - target.z)


func build_block(p_i: int, p_j: int) -> void:
	i = p_i
	j = p_j
	c = CityMap.block_center(i, j)
	b = GeoBatch.new()
	cols = ColliderSet.new()
	node = Node3D.new()
	node.name = "Block_%d_%d" % [i, j]
	cb.root.add_child(node)
	# Raised platform (sidewalk ring + lot).
	b.abox(c + Vector3(0, (Y - 0.3) * 0.5, 0), Vector3(CityMap.BLOCK, Y + 0.3, CityMap.BLOCK), Color(0.7, 0.69, 0.66), K.TILES)
	b.abox(c + Vector3(0, Y * 0.5, 0) + Vector3(0, 0.001, 0), Vector3(CityMap.BLOCK + 0.05, Y, CityMap.BLOCK + 0.05), Color(0.62, 0.61, 0.58), K.CONCRETE, 0.0, 0.0, ["bottom", "top"])
	cols.add_box(c + Vector3(0, (Y - 0.3) * 0.5, 0), Vector3(CityMap.BLOCK, Y + 0.3, CityMap.BLOCK))
	ring = cb.graph.add_ring(c, 22.5, 4, Y)
	cb.block_rings[Vector2i(i, j)] = ring
	var t := CityMap.block_type(i, j)
	match t:
		"houses": _houses()
		"apartments": _apartments()
		"park": _park()
		"sports_park": _sports_park()
		"market": _market()
		"diner_block": _diner_block()
		"town_plaza": _town_plaza()
		"warehouse": _warehouse()
		"shops": _shops("shops")
		"shops2": _shops("shops2")
		"quickstop": _quickstop()
		"garage_yard": _garage_yard()
		"offices": _offices(8, 6)
		"offices2": _offices(10, 5)
		"bank_hotel": _bank_hotel()
		"parking": _parking()
	_street_furniture(t)
	var mi := b.to_instance("Geometry")
	mi.visibility_range_end = cb.view_distance
	mi.visibility_range_end_margin = 20.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	node.add_child(mi)
	node.add_child(cols.build("Collision"))


func _lot_ground(color: Color, kind: int, inset: float = 21.0) -> void:
	b.floor_quad(c + Vector3(0, Y + 0.004, 0), Vector2(inset * 2.0, inset * 2.0), color, kind)


# ------------------------------------------------------------------ residential
func _houses() -> void:
	_lot_ground(Color(0.38, 0.55, 0.28), K.GRASS)
	var street: String = CityMap.STREETS_EW[j]
	var k := 0
	for side in [1.0, -1.0]:
		var yaw: float = 0.0 if side > 0 else PI
		for lx in [-14.0, 0.0, 14.0]:
			var w := rng.randf_range(7.5, 9.5)
			var d := rng.randf_range(8.0, 10.0)
			var floors := 1 if rng.randf() < 0.45 else 2
			var z: float = side * (21.0 - 6.5 - d * 0.5)
			var wall: Color = HOUSE_COLORS[rng.randi() % HOUSE_COLORS.size()]
			var roof: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()]
			var trim := Color(0.95, 0.94, 0.9) if rng.randf() < 0.7 else wall.darkened(0.35)
			var entry := BuildingKit.house(b, cols, X(Vector3(lx, 0, z), yaw), w, d, floors, wall, roof, trim, rng)
			cb.add_to_skyline(W(Vector3(lx, 0, z)), Vector3(w, floors * 2.9 + 2.0, d), wall, K.WOOD)
			# front walk, fence with gate, mailbox
			var fence_z: float = side * 20.6
			var walk_len := absf(fence_z - (z + side * (d * 0.5 + 2.6)))
			b.floor_quad(W(Vector3(lx, 0.01, fence_z - side * walk_len * 0.5)), Vector2(1.4, walk_len), Color(0.68, 0.66, 0.62), K.TILES)
			PropsKit.picket_fence(b, cols, W(Vector3(lx - 6.8, 0, fence_z)), W(Vector3(lx + 6.8, 0, fence_z)), Color(0.95, 0.95, 0.93), 6.8, 1.6)
			PropsKit.mailbox(b, W(Vector3(lx + 1.5, 0, fence_z + side * 0.4)), yaw)
			# driveway + car
			b.floor_quad(W(Vector3(lx + w * 0.5 + 1.6, 0.008, side * 15.5)), Vector2(2.8, 11.0), Color(0.6, 0.6, 0.58), K.CONCRETE)
			if rng.randf() < 0.55:
				PropsKit.car(b, cols, X(Vector3(lx + w * 0.5 + 1.6, 0, side * 14.5), yaw + (PI if rng.randf() < 0.5 else 0.0)), CAR_COLORS[rng.randi() % CAR_COLORS.size()], rng.randi() % 3)
			# backyard tree
			if rng.randf() < 0.7:
				cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), W(Vector3(lx + rng.randf_range(-4, 4), 0, side * 3.0))))
			var names := ["Miller", "Garcia", "Nguyen", "Okafor", "Kowalski", "Haddad", "Svensson", "Tanaka", "Moreau", "Rossi", "Brennan", "Park"]
			var hname: String = "%d %s" % [10 + (i * 7 + j * 3 + k) * 2, street]
			var p := cb.add_place("home", hname, entry, ring, {"tags": ["home", "sleep", "food"], "capacity": 4})
			p.inside_pos = W(Vector3(lx, 0, z))
			p.name = "%s house, %s" % [names[(i * 6 + j * 4 + k) % names.size()], hname]
			k += 1
	# Fences along the side streets between the rows.
	for sx in [-1.0, 1.0]:
		PropsKit.picket_fence(b, cols, W(Vector3(sx * 20.6, 0, -6.5)), W(Vector3(sx * 20.6, 0, 6.5)), Color(0.9, 0.9, 0.88))


func _apartments() -> void:
	_lot_ground(Color(0.4, 0.55, 0.3), K.GRASS)
	var e1 := BuildingKit.apartment(b, cols, X(Vector3(-5, 0, 11), 0.0), 26.0, 12.0, 4, Color(0.62, 0.36, 0.28), rng)
	cb.add_to_skyline(W(Vector3(-5, 0, 11)), Vector3(26, 13, 12), Color(0.62, 0.36, 0.28), K.BRICK)
	var e2 := BuildingKit.apartment(b, cols, X(Vector3(-5, 0, -11), PI), 26.0, 11.0, 3, Color(0.75, 0.7, 0.6), rng)
	cb.add_to_skyline(W(Vector3(-5, 0, -11)), Vector3(26, 10, 11), Color(0.75, 0.7, 0.6), K.BRICK)
	cb.sign_label(node, "Maple Court Apartments", W(Vector3(-5, 3.8, 17.2)), 0.0, 64)
	var p1 := cb.add_place("apartment", "Maple Court Apts A", e1, ring, {"tags": ["home", "sleep", "food"], "capacity": 16})
	p1.inside_pos = W(Vector3(-5, 0, 11))
	var p2 := cb.add_place("apartment", "Maple Court Apts B", e2, ring, {"tags": ["home", "sleep", "food"], "capacity": 12})
	p2.inside_pos = W(Vector3(-5, 0, -11))
	# Player's home: enterable unit facing the east street.
	var hx := X(Vector3(14.5, 0, 0), PI * 0.5)
	var info := BuildingKit.hollow(b, cols, hx, 11.0, 8.0, 3.0, Color(0.85, 0.8, 0.7), K.WOOD, Color(0.55, 0.42, 0.3), 1.2, 3.0)
	b.box(hx * Transform3D(Basis.IDENTITY, Vector3(0, 3.4, 0)), Vector3(11.6, 0.5, 8.6), Color(0.3, 0.3, 0.33), K.ROOF)
	cb.add_to_skyline(W(Vector3(14.5, 0, 0)), Vector3(8, 3.6, 11), Color(0.85, 0.8, 0.7), K.WOOD)
	cb.sign_label(node, "Unit 1A", (hx * Transform3D(Basis.IDENTITY, Vector3(3.0, 2.7, 4.1))).origin, PI * 0.5, 48)
	var door := Door.new()
	door.transform = hx * Transform3D(Basis.IDENTITY, Vector3(3.0, 0, 3.9))
	door.color = Color(0.3, 0.45, 0.55)
	door.width = 1.2
	node.add_child(door)
	# furniture (local frame of the unit: front wall +Z)
	BuildingKit.counter(b, cols, hx * Transform3D(Basis.IDENTITY, Vector3(-3.6, 0, -3.2)), 3.2, Color(0.85, 0.85, 0.82), Color(0.45, 0.32, 0.22))
	b.box(hx * Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.95, -0.8)), Vector3(0.8, 1.9, 0.7), Color(0.9, 0.9, 0.92), K.METAL)
	cols.add(hx * Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.95, -0.8)), Vector3(0.8, 1.9, 0.7))
	BuildingKit.table(b, cols, hx * Transform3D(Basis.IDENTITY, Vector3(-2.2, 0, 0.6)), Vector2(1.2, 0.9), Color(0.55, 0.4, 0.28))
	BuildingKit.chair(b, hx * Transform3D(Basis(Vector3.UP, PI), Vector3(-2.2, 0, 1.4)), Color(0.5, 0.36, 0.25))
	# bed
	var bed_xf := hx * Transform3D(Basis.IDENTITY, Vector3(3.6, 0, -2.4))
	b.box(bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(1.7, 0.5, 2.2), Color(0.45, 0.3, 0.2), K.WOOD)
	b.box(bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0.1)), Vector3(1.6, 0.18, 2.0), Color(0.3, 0.45, 0.65), K.PAINT)
	b.box(bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.8)), Vector3(1.2, 0.15, 0.4), Color(0.95, 0.95, 0.93), K.PAINT)
	b.box(bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -1.1)), Vector3(1.7, 1.4, 0.1), Color(0.4, 0.27, 0.18), K.WOOD)
	cols.add(bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(1.7, 0.6, 2.2))
	var bed := SimpleInteractable.new()
	bed.action = "bed"
	bed.interact_radius = 2.2
	bed.transform = bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 1.2))
	node.add_child(bed)
	# wardrobe
	var wr_xf := hx * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(5.1, 0, 0.2))
	b.box(wr_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(1.6, 2.0, 0.6), Color(0.5, 0.36, 0.25), K.WOOD)
	cols.add(wr_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(1.6, 2.0, 0.6))
	var wardrobe := SimpleInteractable.new()
	wardrobe.action = "wardrobe"
	wardrobe.transform = wr_xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0.6))
	node.add_child(wardrobe)
	# sofa + TV
	var sofa_xf := hx * Transform3D(Basis(Vector3.UP, PI), Vector3(0.6, 0, 2.3))
	b.box(sofa_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.22, 0)), Vector3(2.0, 0.44, 0.85), Color(0.35, 0.5, 0.45), K.PAINT)
	b.box(sofa_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.62, -0.35)), Vector3(2.0, 0.6, 0.2), Color(0.33, 0.47, 0.42), K.PAINT)
	cols.add(sofa_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), Vector3(2.0, 0.8, 0.85))
	var seat := Seat.new()
	seat.transform = sofa_xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.0, 0.15))
	node.add_child(seat)
	b.box(hx * Transform3D(Basis.IDENTITY, Vector3(0.6, 1.3, -3.7)), Vector3(1.6, 0.9, 0.08), Color(0.05, 0.05, 0.06), K.GLASS)
	b.box(hx * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.35, -3.6)), Vector3(1.8, 0.7, 0.45), Color(0.4, 0.3, 0.22), K.WOOD)
	BuildingKit.ceiling_light(b, (hx * Transform3D(Basis.IDENTITY, Vector3(0, 2.95, 0))).origin)
	cb.interior_light_positions.append((hx * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 0))).origin)
	var home := cb.add_place("player_home", "Your apartment (Unit 1A)", info["door_world"], ring, {"tags": ["home"], "enterable": true})
	cb.add_interior(home, info["door_inside"], [{"pos": (bed_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.4))).origin, "kind": "stand"}])
	cb.player_home = home
	cb.player_spawn = (info["door_world"] as Vector3) + (hx.basis * Vector3(0, 0, 1.5)) + Vector3(0, 0.05, 0)
	# yard props
	PropsKit.planter(b, cols, W(Vector3(8, 0, 17)), Color(0.9, 0.3, 0.4))
	PropsKit.planter(b, cols, W(Vector3(8, 0, -17)), Color(0.95, 0.8, 0.2))
	PropsKit.dumpster(b, cols, X(Vector3(-19.5, 0, 0), PI * 0.5), Color(0.15, 0.4, 0.2))
	var bin := SimpleInteractable.new()
	bin.action = "trash"
	bin.transform = X(Vector3(-18.2, 0.8, 0), PI * 0.5)
	node.add_child(bin)


# ------------------------------------------------------------------ parks
func _park() -> void:
	_lot_ground(Color(0.36, 0.56, 0.27), K.GRASS)
	var path_col := Color(0.76, 0.7, 0.58)
	b.floor_quad(W(Vector3(0, 0.012, 0)), Vector2(3.0, 42.0), path_col, K.DIRT)
	b.floor_quad(W(Vector3(0, 0.013, 0)), Vector2(42.0, 3.0), path_col, K.DIRT)
	# fountain
	b.cylinder(W(Vector3(0, 0.3, 0)), 4.2, 4.4, 0.6, Color(0.65, 0.63, 0.6), K.CONCRETE, 20)
	b.cylinder(W(Vector3(0, 0.55, 0)), 3.8, 3.8, 0.1, Color(0.3, 0.5, 0.6), K.WATER, 20)
	b.cylinder(W(Vector3(0, 1.4, 0)), 0.35, 0.5, 1.8, Color(0.65, 0.63, 0.6), K.CONCRETE, 10)
	b.cylinder(W(Vector3(0, 2.35, 0)), 1.2, 0.6, 0.3, Color(0.65, 0.63, 0.6), K.CONCRETE, 14)
	cols.add_box(W(Vector3(0, 0.35, 0)), Vector3(8.4, 0.7, 8.4))
	var spots: Array = []
	for k in 8:
		var a := TAU * k / 8.0
		var bp := Vector3(cos(a) * 9.5, 0, sin(a) * 9.5)
		if absf(bp.x) < 2.5 or absf(bp.z) < 2.5:
			bp = Vector3(cos(a + 0.4) * 9.5, 0, sin(a + 0.4) * 9.5)
		var yaw := face_yaw(bp, Vector3.ZERO)   # face the fountain
		var bxf := X(bp, yaw + PI)
		PropsKit.bench(b, cols, bxf)
		var seat := Seat.new()
		seat.transform = X(bp, yaw)
		seat.transform.origin += seat.transform.basis.z * -0.05
		node.add_child(seat)
		spots.append({"pos": seat.transform.origin, "yaw": yaw, "kind": "seat", "seat": seat})
	for k in 18:
		var p := Vector3(rng.randf_range(-19, 19), 0, rng.randf_range(-19, 19))
		if absf(p.x) < 3.5 or absf(p.z) < 3.5 or p.length() < 12.0:
			continue
		cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.4)), W(p)))
	for p in [Vector3(-14, 0, 14), Vector3(14, 0, -14)]:
		BuildingKit.table(b, cols, X(p), Vector2(2.0, 0.9), Color(0.5, 0.36, 0.22))
	for p in [Vector3(-3, 0, 14), Vector3(3, 0, -14), Vector3(14, 0, 3), Vector3(-14, 0, -3)]:
		cb.lamp_positions.append(PropsKit.lamp(b, cols, W(p), 0.0))
	for p in [Vector3(6, 0, 6), Vector3(-6, 0, -6)]:
		PropsKit.planter(b, cols, W(p), Color.from_hsv(rng.randf(), 0.6, 0.9))
	var park := cb.add_place("park", "Maple Park", W(Vector3(0, 0, 20.5)), ring, {"tags": ["leisure", "social", "free", "outdoor", "jog"], "capacity": 30})
	park.spots = spots
	for s in park.spots:
		s["taken_by"] = -1
	for s in spots:
		var nid := cb.graph.add_node(s["pos"])
		cb.graph.link_to_nearest(nid, ring)
		s["node"] = nid
	cb.sign_label(node, "MAPLE PARK", W(Vector3(0, 2.2, 21.5)), 0.0, 80, Color(0.95, 0.9, 0.7))
	b.box(X(Vector3(0, 1.2, 21.4)), Vector3(4.0, 1.2, 0.15), Color(0.35, 0.25, 0.15), K.WOOD)


func _sports_park() -> void:
	_lot_ground(Color(0.38, 0.56, 0.28), K.GRASS)
	# basketball court
	var court := X(Vector3(-8, 0.01, 0), PI * 0.5)
	b.box(court, Vector3(15.0, 0.02, 26.0), Color(0.62, 0.32, 0.25), K.CONCRETE)
	b.box(court * Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0)), Vector3(14.0, 0.01, 0.1), Color(0.95, 0.95, 0.9), K.ROAD_PAINT)
	for sz in [-1.0, 1.0]:
		var hp := court * Transform3D(Basis.IDENTITY, Vector3(0, 0, sz * 12.5))
		b.cylinder((hp * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))).origin, 0.08, 0.08, 3.2, Color(0.2, 0.2, 0.22), K.METAL, 8)
		b.box(hp * Transform3D(Basis.IDENTITY, Vector3(0, 3.3, -sz * 0.3)), Vector3(1.8, 1.1, 0.06), Color(0.95, 0.95, 0.95), K.PAINT)
		b.primitive(_torus(0.2, 0.24), hp * Transform3D(Basis.IDENTITY, Vector3(0, 3.05, -sz * 0.6)), Color(0.9, 0.35, 0.1), K.METAL)
		cols.add(hp * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), Vector3(0.2, 3.2, 0.2))
	# playground
	var pg := X(Vector3(11, 0, 6))
	b.floor_quad(W(Vector3(11, 0.01, 6)), Vector2(14, 16), Color(0.82, 0.74, 0.55), K.DIRT)
	for sx in [-2.0, 2.0]:
		b.box(pg * Transform3D(Basis(Vector3.BACK, 0.25 * signf(sx)), Vector3(sx, 1.2, -3)), Vector3(0.1, 2.5, 0.1), Color(0.8, 0.2, 0.2), K.METAL)
	b.box(pg * Transform3D(Basis.IDENTITY, Vector3(0, 2.4, -3)), Vector3(4.3, 0.1, 0.1), Color(0.8, 0.2, 0.2), K.METAL)
	for sx in [-1.0, 1.0]:
		b.box(pg * Transform3D(Basis.IDENTITY, Vector3(sx, 0.55, -3)), Vector3(0.6, 0.06, 0.25), Color(0.2, 0.3, 0.7), K.PAINT)
	b.box(pg * Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 1.0, 3.2)), Vector3(0.9, 0.08, 3.4), Color(0.95, 0.75, 0.15), K.PAINT)
	b.box(pg * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 1.6)), Vector3(1.2, 2.0, 1.2), Color(0.25, 0.55, 0.85), K.PAINT)
	cols.add(pg * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 1.6)), Vector3(1.2, 2.0, 1.2))
	var spots: Array = []
	for p in [Vector3(4, 0, -16), Vector3(16, 0, -16)]:
		var yaw := face_yaw(p, Vector3(p.x, 0, 0))
		PropsKit.bench(b, cols, X(p, yaw + PI))
		var seat := Seat.new()
		seat.transform = X(p, yaw)
		node.add_child(seat)
		spots.append({"pos": seat.transform.origin, "yaw": yaw, "kind": "seat", "seat": seat})
	for k in 10:
		var tp := Vector3(rng.randf_range(4, 19), 0, rng.randf_range(-19, -8))
		cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), W(tp)))
	var court_place := cb.add_place("sports", "Birch Ave Courts", W(Vector3(-8, 0, 20.5)), ring, {"tags": ["leisure", "sports", "social", "free", "outdoor"], "capacity": 10, "open": 7.0, "close": 22.0})
	for k in 6:
		court_place.spots.append({"pos": W(Vector3(-8 + rng.randf_range(-5, 5), 0, rng.randf_range(-9, 9))), "yaw": rng.randf() * TAU, "kind": "stand", "taken_by": -1})
	var pg_place := cb.add_place("park", "Birch Playground", W(Vector3(11, 0, 20.5)), ring, {"tags": ["leisure", "free", "outdoor", "social"], "capacity": 12})
	pg_place.spots = spots
	for s in spots:
		s["taken_by"] = -1
	cb.lamp_positions.append(PropsKit.lamp(b, cols, W(Vector3(-0.5, 0, 0)), PI * 0.5))


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 5
	return t


# ------------------------------------------------------------------ old town
func _market() -> void:
	_lot_ground(Color(0.72, 0.68, 0.6), K.TILES)
	var names := ["Sunrise Bakery", "Book Nook"]
	var wall_cols := [Color(0.78, 0.55, 0.38), Color(0.55, 0.6, 0.7)]
	for k in 2:
		var lx := -10.0 + k * 20.0
		var e := BuildingKit.shopfront(b, cols, X(Vector3(lx, 0, -15), PI), 16.0, 11.0, 2, wall_cols[k], K.BRICK, Color.from_hsv(rng.randf(), 0.6, 0.75), Color(0.95, 0.88, 0.7), rng)
		cb.add_to_skyline(W(Vector3(lx, 0, -15)), Vector3(16, 6.8, 11), wall_cols[k], K.BRICK)
		cb.sign_label(node, names[k], W(Vector3(lx, 3.55, -20.6)), PI, 64, Color(0.25, 0.15, 0.1))
		var tags := ["food", "shop", "work"] if k == 0 else ["shop", "leisure", "work"]
		cb.add_place("shop", names[k], e, ring, {"tags": tags, "open": 7.0 if k == 0 else 10.0, "close": 18.0 if k == 0 else 20.0,
			"jobs": [{"title": "Baker" if k == 0 else "Bookseller", "wage": 15, "start": 6.0 if k == 0 else 10.0, "end": 14.0 if k == 0 else 18.0, "slots": 2}]})
	# stalls
	var stall_spots: Array = []
	for k in 8:
		var gx := -15.0 + (k % 4) * 10.0
		var gz := 0.0 + (k / 4) * 10.0
		var sxf := X(Vector3(gx, 0, gz), PI if k / 4 == 0 else 0.0)
		var canopy := Color.from_hsv(float(k) / 8.0, 0.55, 0.85)
		for px in [-1.4, 1.4]:
			for pz in [-1.0, 1.0]:
				b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(px, 1.2, pz)), Vector3(0.08, 2.4, 0.08), Color(0.4, 0.3, 0.2), K.WOOD)
		b.box(sxf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 2.45, 0)), Vector3(3.2, 0.06, 2.6), canopy, K.PAINT)
		BuildingKit.counter(b, cols, sxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.6)), 2.6, Color(0.55, 0.4, 0.25), Color(0.5, 0.36, 0.22))
		for q in 4:
			b.sphere((sxf * Transform3D(Basis.IDENTITY, Vector3(-0.9 + q * 0.6, 1.15, 0.6))).origin, Vector3(0.22, 0.12, 0.22), Color.from_hsv(rng.randf(), 0.75, 0.85), K.PAINT, 7)
		PropsKit.crate_stack(b, cols, (sxf * Transform3D(Basis.IDENTITY, Vector3(1.2, 0, -0.6))).origin, rng)
		stall_spots.append({"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.8))).origin, "yaw": sxf.basis.get_euler().y + PI, "kind": "stand", "taken_by": -1})
	var market := cb.add_place("market", "Old Town Market", W(Vector3(0, 0, 20.5)), ring, {"tags": ["food", "groceries", "shop", "social", "leisure", "work", "outdoor"],
		"open": 7.0, "close": 19.0, "capacity": 30, "jobs": [{"title": "Market vendor", "wage": 13, "start": 7.0, "end": 15.0, "slots": 4}]})
	market.spots = stall_spots
	cb.sign_label(node, "OLD TOWN MARKET", W(Vector3(0, 4.2, 20.0)), 0.0, 96, Color(0.98, 0.85, 0.45))
	b.box(X(Vector3(-6, 0, 20)), Vector3(0.2, 4.6, 0.2), Color(0.3, 0.2, 0.12), K.WOOD)
	b.box(X(Vector3(6, 0, 20)), Vector3(0.2, 4.6, 0.2), Color(0.3, 0.2, 0.12), K.WOOD)
	b.box(X(Vector3(0, 4.1, 20)), Vector3(12.4, 0.8, 0.2), Color(0.45, 0.2, 0.15), K.WOOD)
	for p in [Vector3(-18, 0, 14), Vector3(18, 0, 14)]:
		PropsKit.bench(b, cols, X(p, PI))
		var seat := Seat.new()
		seat.transform = X(p, 0.0)
		node.add_child(seat)


func _diner_block() -> void:
	_lot_ground(Color(0.6, 0.6, 0.58), K.CONCRETE)
	# Rosie's Diner (enterable) facing south
	var dxf := X(Vector3(-6, 0, 12), 0.0)
	var info := BuildingKit.hollow(b, cols, dxf, 18.0, 11.0, 3.6, Color(0.92, 0.9, 0.85), K.PAINT, Color(0.85, 0.85, 0.82), 1.6, -5.0)
	b.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 5.55)), Vector3(18.0, 0.5, 0.15), Color(0.75, 0.15, 0.15), K.PAINT)
	b.box(dxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 5.55)), Vector3(18.0, 0.5, 0.12), Color(0.75, 0.15, 0.15), K.PAINT)
	for k in 4:
		BuildingKit._win(b, dxf, Vector3(-1.0 + k * 2.7, 1.75, 5.5), Vector2(2.2, 1.4), Color(0.75, 0.75, 0.78), rng.randf())
	b.box(dxf * Transform3D(Basis.IDENTITY, Vector3(-1.0, 4.4, 5.4)), Vector3(7.0, 1.0, 0.2), Color(0.95, 0.3, 0.35), K.SIGN)
	cb.sign_label(node, "Rosie's Diner", (dxf * Transform3D(Basis.IDENTITY, Vector3(-1.0, 4.4, 5.5))).origin, 0.0, 110, Color(1, 0.95, 0.85))
	cb.add_to_skyline(W(Vector3(-6, 0, 12)), Vector3(18, 4, 11), Color(0.92, 0.9, 0.85), K.PAINT)
	var door := Door.new()
	door.auto = true
	door.width = 1.4
	door.color = Color(0.6, 0.75, 0.8)
	door.transform = dxf * Transform3D(Basis.IDENTITY, Vector3(-5.0, 0, 5.4))
	node.add_child(door)
	# interior: counter with stools, booths
	BuildingKit.counter(b, cols, dxf * Transform3D(Basis.IDENTITY, Vector3(3.5, 0, -2.6)), 7.0, Color(0.9, 0.9, 0.88), Color(0.75, 0.15, 0.15))
	b.box(dxf * Transform3D(Basis.IDENTITY, Vector3(3.5, 1.6, -5.1)), Vector3(8.0, 1.0, 0.4), Color(0.85, 0.85, 0.87), K.METAL)
	var spots: Array = []
	for k in 4:
		var t_xf := dxf * Transform3D(Basis.IDENTITY, Vector3(-6.0, 0, -3.6 + k * 2.2))
		BuildingKit.table(b, cols, t_xf, Vector2(1.0, 1.2), Color(0.85, 0.85, 0.82))
		for side in [-1.0, 1.0]:
			var seat_xf := dxf * Transform3D(Basis(Vector3.UP, -PI * 0.5 * side), Vector3(-6.0 - side * 0.95, 0, -3.6 + k * 2.2))
			b.box(seat_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(1.2, 0.5, 0.55), Color(0.75, 0.15, 0.15), K.PAINT)
			b.box(seat_xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.3)), Vector3(1.2, 1.0, 0.12), Color(0.7, 0.13, 0.13), K.PAINT)
			var seat := Seat.new()
			seat.transform = seat_xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.0, 0.05))
			node.add_child(seat)
			spots.append({"pos": seat.transform.origin, "yaw": seat.transform.basis.get_euler().y, "kind": "seat", "seat": seat})
	for k in 5:
		var st := dxf * Transform3D(Basis.IDENTITY, Vector3(0.8 + k * 1.3, 0, -1.6))
		b.cylinder((st * Transform3D(Basis.IDENTITY, Vector3(0, 0.38, 0))).origin, 0.22, 0.22, 0.08, Color(0.75, 0.15, 0.15), K.PAINT, 10)
		b.cylinder((st * Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0))).origin, 0.04, 0.06, 0.36, Color(0.7, 0.7, 0.72), K.METAL, 6)
		spots.append({"pos": st.origin, "yaw": st.basis.get_euler().y + PI, "kind": "counter"})
	var order := SimpleInteractable.new()
	order.action = "food"
	order.price = 12
	order.info_text = "Rosie's burger"
	order.transform = dxf * Transform3D(Basis.IDENTITY, Vector3(3.5, 1.1, -1.9))
	node.add_child(order)
	for k in 3:
		BuildingKit.ceiling_light(b, (dxf * Transform3D(Basis.IDENTITY, Vector3(-5 + k * 5, 3.55, 0))).origin)
	cb.interior_light_positions.append((dxf * Transform3D(Basis.IDENTITY, Vector3(-2, 3.0, 0))).origin)
	var diner := cb.add_place("diner", "Rosie's Diner", info["door_world"], ring, {"tags": ["food", "social", "work"], "open": 6.0, "close": 23.0, "price": 2, "enterable": true,
		"capacity": 14, "jobs": [{"title": "Waiter", "wage": 14, "start": 7.0, "end": 15.0, "slots": 2}, {"title": "Cook", "wage": 16, "start": 11.0, "end": 19.0, "slots": 1}]})
	cb.add_interior(diner, info["door_inside"], spots)
	order.place = diner
	door.place = diner
	# north side shops
	var names := ["Lucky Laundromat", "Hank's Hardware", "Bean There Cafe"]
	for k in 3:
		var lx := -14.0 + k * 14.0
		var e := BuildingKit.shopfront(b, cols, X(Vector3(lx, 0, -15), PI), 12.5, 11.0, 2, Color.from_hsv(rng.randf(), 0.25, 0.75), K.BRICK if k != 1 else K.PAINT, Color.from_hsv(rng.randf(), 0.6, 0.7), Color(0.95, 0.9, 0.75), rng)
		cb.add_to_skyline(W(Vector3(lx, 0, -15)), Vector3(12.5, 6.8, 11), Color(0.7, 0.6, 0.5), K.BRICK)
		cb.sign_label(node, names[k], W(Vector3(lx, 3.55, -20.6)), PI, 58, Color(0.2, 0.15, 0.1))
		var tags: Array = [["shop", "work"], ["shop", "work"], ["coffee", "food", "social", "work"]][k]
		var p := cb.add_place("cafe" if k == 2 else "shop", names[k], e, ring, {"tags": tags, "open": 7.0 if k == 2 else 9.0, "close": 20.0,
			"jobs": [{"title": ["Laundry attendant", "Store clerk", "Barista"][k], "wage": [12, 14, 13][k], "start": 8.0, "end": 16.0, "slots": 2}]})
		if k == 2:
			var cof := SimpleInteractable.new()
			cof.action = "coffee"
			cof.price = 4
			cof.info_text = "Coffee"
			cof.place = p
			cof.transform = Transform3D(Basis.IDENTITY, e + Vector3(1.5, 1.0, 0))
			node.add_child(cof)
	# back lot
	PropsKit.dumpster(b, cols, X(Vector3(14, 0, 2), PI * 0.5), Color(0.2, 0.35, 0.55))
	PropsKit.car(b, cols, X(Vector3(12, 0, 10), PI * 0.5), CAR_COLORS[rng.randi() % CAR_COLORS.size()])


func _town_plaza() -> void:
	_lot_ground(Color(0.74, 0.71, 0.66), K.TILES)
	var hall := X(Vector3(0, 0, -9), 0.0)
	var stone := Color(0.85, 0.82, 0.74)
	b.box(hall * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)), Vector3(26.0, 10.0, 14.0), stone, K.CONCRETE)
	cols.add(hall * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)), Vector3(26.0, 10.0, 14.0))
	for k in 6:
		b.cylinder((hall * Transform3D(Basis.IDENTITY, Vector3(-7.5 + k * 3.0, 3.6, 8.2))).origin, 0.45, 0.5, 7.2, Color(0.92, 0.9, 0.85), K.CONCRETE, 12)
		cols.add(hall * Transform3D(Basis.IDENTITY, Vector3(-7.5 + k * 3.0, 3.6, 8.2)), Vector3(0.9, 7.2, 0.9))
	b.box(hall * Transform3D(Basis.IDENTITY, Vector3(0, 7.5, 8.2)), Vector3(18.0, 0.8, 2.6), stone.lightened(0.05), K.CONCRETE)
	b.gable_roof(hall * Transform3D(Basis.IDENTITY, Vector3(0, 7.9, 8.2)), Vector3(18.0, 0, 2.6), 1.6, stone, stone)
	for k in 3:
		b.box(hall * Transform3D(Basis.IDENTITY, Vector3(0, 0.12 + k * 0.12, 8.0 + 2.0 - k * 0.4)), Vector3(16.0, 0.24 + k * 0.24, 0.8), stone.darkened(0.05), K.CONCRETE)
	b.box(hall * Transform3D(Basis.IDENTITY, Vector3(0, 14.0, -1.0)), Vector3(4.0, 8.0, 4.0), stone, K.CONCRETE)
	b.cylinder((hall * Transform3D(Basis.IDENTITY, Vector3(0, 15.0, 1.05))).origin, 1.2, 1.2, 0.1, Color(0.95, 0.95, 0.9), K.SIGN, 16, hall.basis * Basis(Vector3.RIGHT, PI * 0.5))
	b.cylinder((hall * Transform3D(Basis.IDENTITY, Vector3(0, 19.0, -1.0))).origin, 0.0, 2.8, 2.5, Color(0.3, 0.42, 0.38), K.ROOF, 4)
	for f in 2:
		for k in 6:
			BuildingKit._win(b, hall, Vector3(-11 + k * 4.4, 2.2 + f * 4.0, 7.0), Vector2(1.4, 2.2), Color(0.95, 0.95, 0.9), rng.randf())
	cb.sign_label(node, "WESTBRIDGE TOWN HALL", (hall * Transform3D(Basis.IDENTITY, Vector3(0, 9.0, 9.6))).origin, 0.0, 100, Color(0.2, 0.18, 0.15))
	cb.add_to_skyline(W(Vector3(0, 0, -9)), Vector3(26, 12, 14), stone, K.CONCRETE)
	cb.add_place("office", "Westbridge Town Hall", (hall * Transform3D(Basis.IDENTITY, Vector3(0, 0, 10.8))).origin, ring, {"tags": ["work", "services"], "open": 9.0, "close": 17.0,
		"jobs": [{"title": "Clerk", "wage": 18, "start": 9.0, "end": 17.0, "slots": 4}]})
	# plaza: statue, trees, benches
	b.box(X(Vector3(0, 0.6, 9)), Vector3(2.4, 1.2, 2.4), Color(0.6, 0.6, 0.6), K.CONCRETE)
	b.cylinder(W(Vector3(0, 2.2, 9)), 0.35, 0.45, 2.0, Color(0.42, 0.5, 0.45), K.METAL, 10)
	b.sphere(W(Vector3(0, 3.5, 9)), Vector3(0.4, 0.5, 0.4), Color(0.42, 0.5, 0.45), K.METAL, 10)
	cols.add_box(W(Vector3(0, 1.5, 9)), Vector3(2.4, 3.0, 2.4))
	var spots: Array = []
	for p in [Vector3(-8, 0, 6), Vector3(8, 0, 6), Vector3(-8, 0, 14), Vector3(8, 0, 14)]:
		var yaw := face_yaw(p, Vector3(0, 0, p.z))
		PropsKit.bench(b, cols, X(p, yaw + PI))
		var seat := Seat.new()
		seat.transform = X(p, yaw)
		node.add_child(seat)
		spots.append({"pos": seat.transform.origin, "yaw": yaw, "kind": "seat", "seat": seat})
	for p in [Vector3(-15, 0, 4), Vector3(15, 0, 4), Vector3(-15, 0, 16), Vector3(15, 0, 16)]:
		cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), W(p)))
		PropsKit.planter(b, cols, W(p + Vector3(0, 0, 3.0)), Color.from_hsv(rng.randf(), 0.6, 0.9))
	var plaza := cb.add_place("plaza", "Town Plaza", W(Vector3(0, 0, 20.5)), ring, {"tags": ["leisure", "social", "free", "outdoor"], "capacity": 25})
	plaza.spots = spots
	for s in spots:
		s["taken_by"] = -1
	var board := SimpleInteractable.new()
	board.action = "info"
	board.prompt = "Read notice board"
	board.info_text = "WESTBRIDGE NOTICE: Farmers market daily 7-19 in Old Town. Jobs: QuickStop, Rosie's, Logistics depot."
	board.transform = X(Vector3(4, 1.2, 18), 0.0)
	node.add_child(board)
	b.box(X(Vector3(4, 1.2, 18)), Vector3(1.6, 1.2, 0.1), Color(0.45, 0.3, 0.2), K.WOOD)
	b.box(X(Vector3(4, 1.25, 18.06)), Vector3(1.4, 1.0, 0.02), Color(0.9, 0.88, 0.8), K.PAINT)


# ------------------------------------------------------------------ industrial
func _warehouse() -> void:
	_lot_ground(Color(0.55, 0.55, 0.54), K.CONCRETE)
	var wxf := X(Vector3(-4, 0, -6), 0.0)
	var metal := Color(0.62, 0.66, 0.7)
	b.box(wxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(30.0, 8.0, 18.0), metal, K.METAL)
	cols.add(wxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(30.0, 8.0, 18.0))
	for k in 16:
		b.box(wxf * Transform3D(Basis.IDENTITY, Vector3(-14.5 + k * 1.93, 4.0, 9.03)), Vector3(0.12, 8.0, 0.06), metal.darkened(0.15), K.METAL)
	b.gable_roof(wxf * Transform3D(Basis.IDENTITY, Vector3(0, 8.0, 0)), Vector3(30.4, 0, 18.4), 2.0, Color(0.45, 0.48, 0.5), metal)
	for k in 3:
		b.box(wxf * Transform3D(Basis.IDENTITY, Vector3(-9 + k * 9.0, 2.2, 9.05)), Vector3(4.0, 4.4, 0.1), Color(0.75, 0.6, 0.2), K.METAL)
	b.box(wxf * Transform3D(Basis.IDENTITY, Vector3(0, 6.6, 9.1)), Vector3(12.0, 1.2, 0.1), Color(0.15, 0.35, 0.6), K.SIGN)
	cb.sign_label(node, "WESTBRIDGE LOGISTICS", (wxf * Transform3D(Basis.IDENTITY, Vector3(0, 6.6, 9.2))).origin, 0.0, 110)
	cb.add_to_skyline(W(Vector3(-4, 0, -6)), Vector3(30, 9, 18), metal, K.METAL)
	var p := cb.add_place("warehouse", "Westbridge Logistics", (wxf * Transform3D(Basis.IDENTITY, Vector3(9, 0, 10.5))).origin, ring, {"tags": ["work"], "open": 6.0, "close": 20.0,
		"jobs": [{"title": "Warehouse worker", "wage": 15, "start": 6.0, "end": 14.0, "slots": 4}, {"title": "Forklift driver", "wage": 17, "start": 12.0, "end": 20.0, "slots": 2}]})
	for k in 4:
		p.spots.append({"pos": (wxf * Transform3D(Basis.IDENTITY, Vector3(-10 + k * 6.0, 0, 12))).origin, "yaw": 0.0, "kind": "work", "taken_by": -1})
	# containers & pallets
	var ccols := [Color(0.7, 0.2, 0.15), Color(0.15, 0.4, 0.6), Color(0.2, 0.5, 0.3), Color(0.85, 0.55, 0.15)]
	for k in 4:
		var cxf := X(Vector3(14.0, 0, -14.0 + k * 3.0), PI * 0.5)
		b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(2.5, 2.6, 6.0), ccols[k], K.METAL)
		cols.add(cxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(2.5, 2.6, 6.0))
	for k in 6:
		PropsKit.crate_stack(b, cols, W(Vector3(-16 + k * 2.2, 0, 12)), rng)
	# forklift (static)
	var fl := X(Vector3(4, 0, 13), 0.4)
	b.box(fl * Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0)), Vector3(1.2, 1.0, 2.0), Color(0.95, 0.7, 0.1), K.METAL)
	b.box(fl * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, -0.2)), Vector3(1.1, 0.08, 1.2), Color(0.2, 0.2, 0.2), K.METAL)
	b.box(fl * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 1.1)), Vector3(1.0, 2.6, 0.1), Color(0.25, 0.25, 0.27), K.METAL)
	cols.add(fl * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Vector3(1.2, 1.6, 2.2))


func _garage_yard() -> void:
	_lot_ground(Color(0.5, 0.5, 0.49), K.CONCRETE)
	var gxf := X(Vector3(-6, 0, 4), -PI * 0.5)
	var info := BuildingKit.hollow(b, cols, gxf, 16.0, 12.0, 5.0, Color(0.85, 0.8, 0.7), K.BRICK, Color(0.45, 0.45, 0.46), 9.0, 0.0)
	b.box(gxf * Transform3D(Basis.IDENTITY, Vector3(0, 5.5, 0)), Vector3(16.4, 0.4, 12.4), Color(0.3, 0.3, 0.32), K.METAL)
	b.box(gxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 6.1)), Vector3(9.0, 1.0, 0.15), Color(0.85, 0.2, 0.15), K.SIGN)
	cb.sign_label(node, "MIKE'S AUTO REPAIR", (gxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 6.2))).origin, -PI * 0.5, 96)
	cb.add_to_skyline(W(Vector3(-6, 0, 4)), Vector3(12, 5.5, 16), Color(0.85, 0.8, 0.7), K.BRICK)
	PropsKit.car(b, cols, gxf * Transform3D(Basis.IDENTITY, Vector3(-3, 0, 0)), CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	PropsKit.car(b, cols, gxf * Transform3D(Basis.IDENTITY, Vector3(3, 0, 1)), CAR_COLORS[rng.randi() % CAR_COLORS.size()], 1)
	for k in 5:
		b.cylinder((gxf * Transform3D(Basis.IDENTITY, Vector3(-7.0, 0.15 + k * 0.28, -4.5))).origin, 0.38, 0.38, 0.26, Color(0.1, 0.1, 0.1), K.PAINT, 10)
	var garage := cb.add_place("garage", "Mike's Auto Repair", info["door_world"], ring, {"tags": ["work", "services"], "open": 8.0, "close": 18.0, "enterable": true,
		"jobs": [{"title": "Mechanic", "wage": 18, "start": 8.0, "end": 17.0, "slots": 3}]})
	cb.add_interior(garage, info["door_inside"], [{"pos": (gxf * Transform3D(Basis.IDENTITY, Vector3(-3, 0, 2.6))).origin, "kind": "work"}, {"pos": (gxf * Transform3D(Basis.IDENTITY, Vector3(3, 0, 3.2))).origin, "kind": "work"}])
	var sx := X(Vector3(12, 0, -10), 0.0)
	var e := BuildingKit.shopfront(b, cols, sx, 12.0, 10.0, 1, Color(0.6, 0.62, 0.66), K.CONCRETE, Color(0.2, 0.3, 0.5), Color(0.95, 0.85, 0.3), rng)
	cb.sign_label(node, "Parts & Bolts", (sx * Transform3D(Basis.IDENTITY, Vector3(0, 3.55, 5.1))).origin, 0.0, 60, Color(0.15, 0.12, 0.1))
	cb.add_place("shop", "Parts & Bolts", e, ring, {"tags": ["shop", "work"], "open": 8.0, "close": 18.0, "jobs": [{"title": "Parts clerk", "wage": 14, "start": 9.0, "end": 17.0, "slots": 1}]})
	cb.add_to_skyline(W(Vector3(12, 0, -10)), Vector3(12, 4, 10), Color(0.6, 0.62, 0.66), K.CONCRETE)


# ------------------------------------------------------------------ shops / downtown
func _shops(variant: String) -> void:
	_lot_ground(Color(0.58, 0.58, 0.56), K.CONCRETE)
	var names: Array = ["Pixel Palace", "Spin Records", "Fresh Market", "Corner Pharmacy", "Golden Wok", "Iron Gym"] if variant == "shops" else ["Daily Grind Coffee", "Post Office", "Bella's Salon", "Thrift Corner", "Noodle Bar", "Lake Dr Clinic"]
	var types: Array = [["shop", "leisure"], ["shop", "leisure"], ["groceries", "food", "shop"], ["shop", "services"], ["food", "social"], ["sports", "leisure"]] if variant == "shops" else [["coffee", "food", "social"], ["services"], ["services", "shop"], ["shop"], ["food", "social", "nightlife"], ["services"]]
	var k := 0
	for side in [-1.0, 1.0]:
		var yaw: float = -PI * 0.5 if side < 0 else PI * 0.5
		for lz in [-12.0, 0.0, 12.0]:
			var x: float = side * 15.0
			var floors := rng.randi_range(2, 3)
			var wall := Color.from_hsv(rng.randf(), rng.randf_range(0.15, 0.35), rng.randf_range(0.6, 0.85))
			var e := BuildingKit.shopfront(b, cols, X(Vector3(x, 0, lz), yaw), 11.5, 12.0, floors, wall, K.BRICK if rng.randf() < 0.5 else K.PAINT, Color.from_hsv(rng.randf(), 0.65, 0.7), Color(0.98, 0.92, 0.78), rng)
			cb.add_to_skyline(W(Vector3(x, 0, lz)), Vector3(12, floors * 3.1 + 0.8, 11.5), wall, K.BRICK)
			var sign_pos := W(Vector3(x + side * 6.1, 3.55, lz))
			cb.sign_label(node, names[k], sign_pos, yaw, 56, Color(0.18, 0.14, 0.1))
			var tags: Array = types[k].duplicate()
			tags.append("work")
			var open := 7.0 if "coffee" in tags else (10.0 if "food" in tags else 9.0)
			var close := 23.0 if "nightlife" in tags else (21.0 if "food" in tags else 19.0)
			var ptype := "cafe" if "coffee" in tags else ("restaurant" if "food" in tags and not "groceries" in tags else ("gym" if "sports" in tags else "shop"))
			var p := cb.add_place(ptype, names[k], e, ring, {"tags": tags, "open": open, "close": close,
				"jobs": [{"title": "Staff", "wage": 13 + k, "start": open, "end": minf(open + 8.0, close), "slots": 2}]})
			if ptype in ["cafe", "restaurant"]:
				var act := SimpleInteractable.new()
				act.action = "coffee" if ptype == "cafe" else "food"
				act.price = 4 if ptype == "cafe" else 10
				act.info_text = names[k]
				act.place = p
				act.transform = Transform3D(Basis.IDENTITY, e + Vector3(0, 1.0, 0))
				node.add_child(act)
			if floors >= 3 and rng.randf() < 0.6:
				var h := cb.add_place("apartment", "%s upstairs flat" % names[k], e + Basis(Vector3.UP, yaw) * Vector3(2.5, 0, 0), ring, {"tags": ["home", "sleep", "food"], "capacity": 3})
				h.inside_pos = W(Vector3(x, 0, lz))
			k += 1
	# courtyard parking
	for q in 4:
		PropsKit.car(b, cols, X(Vector3(-3.0 + q * 2.6, 0, 10.0 if q % 2 == 0 else -8.0), 0.0), CAR_COLORS[rng.randi() % CAR_COLORS.size()], q % 3)
	PropsKit.dumpster(b, cols, X(Vector3(0, 0, -17), 0.0), Color(0.2, 0.45, 0.25))


func _quickstop() -> void:
	_lot_ground(Color(0.3, 0.31, 0.33), K.ASPHALT)
	var sxf := X(Vector3(8, 0, -9), PI * 0.5)
	var info := BuildingKit.hollow(b, cols, sxf, 16.0, 11.0, 3.8, Color(0.95, 0.95, 0.94), K.PAINT, Color(0.88, 0.88, 0.86), 1.8, -4.0)
	b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 5.6)), Vector3(16.2, 0.6, 0.15), Color(0.1, 0.55, 0.3), K.SIGN)
	for k in 3:
		BuildingKit._win(b, sxf, Vector3(0.0 + k * 2.7, 1.5, 5.5), Vector2(2.3, 2.0), Color(0.2, 0.22, 0.24), rng.randf())
	cb.sign_label(node, "QuickStop 24/7", (sxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.4, 5.6))).origin, PI * 0.5, 120, Color(0.98, 0.95, 0.85))
	b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.4, 5.5)), Vector3(8.0, 1.0, 0.2), Color(0.1, 0.55, 0.3), K.SIGN)
	cb.add_to_skyline(W(Vector3(8, 0, -9)), Vector3(11, 4.2, 16), Color(0.95, 0.95, 0.94), K.PAINT)
	var door := Door.new()
	door.auto = true
	door.width = 1.6
	door.color = Color(0.65, 0.78, 0.82)
	door.transform = sxf * Transform3D(Basis.IDENTITY, Vector3(-4.0, 0, 5.4))
	node.add_child(door)
	for k in 3:
		BuildingKit.shelf(b, cols, sxf * Transform3D(Basis.IDENTITY, Vector3(1.5, 0, -2.6 + k * 2.4)), 6.0, rng)
	for k in 5:
		var fxf := sxf * Transform3D(Basis.IDENTITY, Vector3(-4.5 + k * 2.2, 0, -5.1))
		b.box(fxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 0)), Vector3(2.0, 2.1, 0.6), Color(0.85, 0.87, 0.9), K.METAL)
		b.box(fxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0.31)), Vector3(1.8, 1.8, 0.02), Color(0.7, 0.85, 0.95), K.SIGN)
		cols.add(fxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 0)), Vector3(2.0, 2.1, 0.6))
	BuildingKit.counter(b, cols, sxf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-5.5, 0, 1.0)), 3.5, Color(0.25, 0.25, 0.27), Color(0.1, 0.55, 0.3))
	b.box(sxf * Transform3D(Basis.IDENTITY, Vector3(-5.5, 1.25, 1.5)), Vector3(0.4, 0.35, 0.3), Color(0.15, 0.15, 0.16), K.METAL)
	for k in 3:
		BuildingKit.ceiling_light(b, (sxf * Transform3D(Basis.IDENTITY, Vector3(-4 + k * 4, 3.75, 0))).origin)
	cb.interior_light_positions.append((sxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.2, 0))).origin)
	var shop := SimpleInteractable.new()
	shop.action = "shop"
	shop.price = 8
	shop.info_text = "groceries"
	shop.transform = sxf * Transform3D(Basis.IDENTITY, Vector3(-4.6, 1.1, 1.0))
	node.add_child(shop)
	var snack := SimpleInteractable.new()
	snack.action = "snack"
	snack.price = 3
	snack.info_text = "snack"
	snack.transform = sxf * Transform3D(Basis.IDENTITY, Vector3(1.5, 1.0, 0.0))
	node.add_child(snack)
	var qs := cb.add_place("store", "QuickStop 24/7", info["door_world"], ring, {"tags": ["groceries", "food", "shop", "work", "shelter"], "open": 0.0, "close": 24.0, "enterable": true,
		"capacity": 10, "jobs": [{"title": "Cashier", "wage": 13, "start": 6.0, "end": 14.0, "slots": 1}, {"title": "Cashier (late)", "wage": 15, "start": 14.0, "end": 22.0, "slots": 1}, {"title": "Night clerk", "wage": 17, "start": 22.0, "end": 6.0, "slots": 1}]})
	cb.add_interior(qs, info["door_inside"], [
		{"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(-4.6, 0, 1.0))).origin, "kind": "counter"},
		{"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(1.5, 0, -1.4))).origin, "kind": "browse"},
		{"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(4.0, 0, 1.0))).origin, "kind": "browse"},
		{"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(-1.0, 0, -4.3))).origin, "kind": "browse"},
		{"pos": (sxf * Transform3D(Basis.IDENTITY, Vector3(-6.2, 0, 1.0))).origin, "kind": "work"},
	])
	shop.place = qs
	snack.place = qs
	door.place = qs
	# fuel canopy + pumps
	var cxf := X(Vector3(-8, 0, 8), 0.0)
	b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)), Vector3(14.0, 0.6, 9.0), Color(0.95, 0.95, 0.95), K.PAINT)
	b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.85, 0)), Vector3(14.1, 0.3, 9.1), Color(0.1, 0.55, 0.3), K.SIGN)
	for px in [-4.0, 4.0]:
		b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(px, 2.4, 0)), Vector3(0.5, 4.8, 0.5), Color(0.9, 0.9, 0.9), K.PAINT)
		cols.add(cxf * Transform3D(Basis.IDENTITY, Vector3(px, 2.4, 0)), Vector3(0.5, 4.8, 0.5))
		for pz in [-2.5, 2.5]:
			b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(px, 0.9, pz)), Vector3(0.8, 1.8, 0.5), Color(0.85, 0.2, 0.15), K.PAINT)
			b.box(cxf * Transform3D(Basis.IDENTITY, Vector3(px, 1.35, pz + 0.26)), Vector3(0.5, 0.35, 0.02), Color(0.3, 0.9, 0.5), K.SIGN)
			cols.add(cxf * Transform3D(Basis.IDENTITY, Vector3(px, 0.9, pz)), Vector3(0.8, 1.8, 0.5))
	cb.lamp_positions.append(cxf * Vector3(0, 4.5, 0))
	# vending machine outside
	var vxf := X(Vector3(3.0, 0, -15.5), PI * 0.5)
	b.box(vxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), Vector3(1.0, 1.9, 0.8), Color(0.75, 0.12, 0.12), K.PAINT)
	b.box(vxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.15, 0.41)), Vector3(0.8, 1.3, 0.02), Color(0.95, 0.4, 0.35), K.SIGN)
	cols.add(vxf * Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), Vector3(1.0, 1.9, 0.8))
	var vend := SimpleInteractable.new()
	vend.action = "vending"
	vend.price = 3
	vend.info_text = "Fizzle soda"
	vend.transform = vxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0.6))
	node.add_child(vend)
	cb.sign_label(node, "FIZZLE", (vxf * Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0.44))).origin, PI * 0.5, 40)
	# parking lines
	for k in 5:
		b.floor_quad(W(Vector3(10.0, 0.012, 4 + k * 3.0)), Vector2(5.0, 0.12), Color(0.9, 0.9, 0.85), K.ROAD_PAINT)
	PropsKit.car(b, cols, X(Vector3(10.5, 0, 5.5), PI * 0.5), CAR_COLORS[rng.randi() % CAR_COLORS.size()])
	PropsKit.car(b, cols, X(Vector3(10.5, 0, 11.5), -PI * 0.5), CAR_COLORS[rng.randi() % CAR_COLORS.size()], 1)
	# bus stop on the south edge
	PropsKit.bus_stop(b, cols, X(Vector3(0, 0, 22.2), PI), Color(0.95, 0.85, 0.3))
	cb.add_place("bus_stop", "Mill Rd bus stop", W(Vector3(0, 0, 21.5)), ring, {"tags": ["transit", "shelter", "outdoor"], "capacity": 6})


func _offices(floors_a: int, floors_b: int) -> void:
	_lot_ground(Color(0.66, 0.65, 0.62), K.TILES)
	var names := ["Harbor Tower", "Kessler Building"] if floors_a == 8 else ["Northgate Center", "Lakeview Offices"]
	var e1 := BuildingKit.tower(b, cols, X(Vector3(-6, 0, -6), PI), 18.0, 16.0, floors_a, Color(0.75, 0.74, 0.72), rng)
	var e2 := BuildingKit.tower(b, cols, X(Vector3(10, 0, 9), PI * 0.5), 12.0, 14.0, floors_b, Color(0.55, 0.57, 0.6), rng)
	cb.add_to_skyline(W(Vector3(-6, 0, -6)), Vector3(18, floors_a * 3.4 + 2.0, 16), Color(0.36, 0.46, 0.55), K.GLASS)
	cb.add_to_skyline(W(Vector3(10, 0, 9)), Vector3(14, floors_b * 3.4 + 2.0, 12), Color(0.36, 0.46, 0.55), K.GLASS)
	cb.sign_label(node, names[0], W(Vector3(-6, 4.6, -15.6)), PI, 72)
	cb.sign_label(node, names[1], W(Vector3(16.7, 4.6, 9)), PI * 0.5, 72)
	for k in 2:
		cb.add_place("office", names[k], [e1, e2][k], ring, {"tags": ["work"], "open": 8.0, "close": 19.0, "capacity": 40,
			"jobs": [{"title": "Office assistant", "wage": 19, "start": 9.0, "end": 17.0, "slots": 6}, {"title": "Security guard", "wage": 15, "start": 18.0, "end": 6.0, "slots": 1}]})
	for p in [Vector3(-14, 0, 12), Vector3(-4, 0, 12), Vector3(4, 0, -16)]:
		PropsKit.planter(b, cols, W(p), Color.from_hsv(rng.randf(), 0.5, 0.9))
	var occ := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = Vector3(17.0, floors_a * 3.4, 15.0)
	occ.occluder = bo
	occ.position = W(Vector3(-6, floors_a * 1.7, -6))
	node.add_child(occ)


func _bank_hotel() -> void:
	_lot_ground(Color(0.68, 0.66, 0.62), K.TILES)
	var bxf := X(Vector3(-9, 0, 9), 0.0)
	var stone := Color(0.88, 0.85, 0.78)
	b.box(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(16.0, 8.0, 12.0), stone, K.CONCRETE)
	cols.add(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(16.0, 8.0, 12.0))
	for k in 4:
		b.cylinder((bxf * Transform3D(Basis.IDENTITY, Vector3(-4.5 + k * 3.0, 3.2, 6.8))).origin, 0.4, 0.45, 6.4, Color(0.94, 0.92, 0.88), K.CONCRETE, 12)
		cols.add(bxf * Transform3D(Basis.IDENTITY, Vector3(-4.5 + k * 3.0, 3.2, 6.8)), Vector3(0.8, 6.4, 0.8))
	b.box(bxf * Transform3D(Basis.IDENTITY, Vector3(0, 6.8, 6.8)), Vector3(12.0, 0.8, 1.8), stone, K.CONCRETE)
	BuildingKit._door(b, bxf, Vector3(0, 0, 6.0), Color(0.3, 0.25, 0.2), Color(0.75, 0.65, 0.35), 1.8)
	cb.sign_label(node, "PINEWOOD SAVINGS BANK", (bxf * Transform3D(Basis.IDENTITY, Vector3(0, 6.8, 7.7))).origin, 0.0, 70, Color(0.2, 0.18, 0.12))
	cb.add_to_skyline(W(Vector3(-9, 0, 9)), Vector3(16, 8, 12), stone, K.CONCRETE)
	cb.add_place("bank", "Pinewood Savings Bank", (bxf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 8.6))).origin, ring, {"tags": ["work", "services", "bank"], "open": 9.0, "close": 16.0,
		"jobs": [{"title": "Bank teller", "wage": 20, "start": 9.0, "end": 16.0, "slots": 3}]})
	var hxf := X(Vector3(7, 0, -6), PI * 0.5)
	var e := BuildingKit.tower(b, cols, hxf, 16.0, 14.0, 7, Color(0.82, 0.72, 0.62), rng)
	b.box(hxf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 9.5)), Vector3(8.0, 0.3, 5.0), Color(0.55, 0.15, 0.15), K.PAINT)
	cb.sign_label(node, "WESTBRIDGE GRAND HOTEL", (hxf * Transform3D(Basis.IDENTITY, Vector3(0, 5.4, 7.2))).origin, PI * 0.5, 80, Color(0.98, 0.88, 0.55))
	cb.add_to_skyline(W(Vector3(7, 0, -6)), Vector3(14, 26, 16), Color(0.82, 0.72, 0.62), K.GLASS)
	cb.add_place("hotel", "Westbridge Grand Hotel", e, ring, {"tags": ["work", "sleep", "food", "nightlife"], "open": 0.0, "close": 24.0, "capacity": 30, "price": 3,
		"jobs": [{"title": "Receptionist", "wage": 16, "start": 7.0, "end": 15.0, "slots": 2}, {"title": "Housekeeper", "wage": 14, "start": 8.0, "end": 16.0, "slots": 3}]})


func _parking() -> void:
	_lot_ground(Color(0.29, 0.3, 0.32), K.ASPHALT)
	for row in 3:
		for k in 8:
			var x := -16.0 + k * 4.4
			var z := -14.0 + row * 13.0
			b.floor_quad(W(Vector3(x - 2.2, 0.012, z)), Vector2(0.12, 5.0), Color(0.9, 0.9, 0.85), K.ROAD_PAINT)
			if rng.randf() < 0.55:
				PropsKit.car(b, cols, X(Vector3(x, 0, z), 0.0 if rng.randf() < 0.5 else PI), CAR_COLORS[rng.randi() % CAR_COLORS.size()], rng.randi() % 3)
	var booth := X(Vector3(18, 0, 18), 0.0)
	b.box(booth * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(2.0, 2.6, 2.0), Color(0.9, 0.85, 0.3), K.PAINT)
	b.box(booth * Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 1.01)), Vector3(1.6, 1.0, 0.02), Color(0.3, 0.4, 0.5), K.GLASS)
	cols.add(booth * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Vector3(2.0, 2.6, 2.0))
	cb.add_place("parking", "City Parking", W(Vector3(18, 0, 20.5)), ring, {"tags": ["work"], "open": 6.0, "close": 22.0,
		"jobs": [{"title": "Parking attendant", "wage": 12, "start": 6.0, "end": 14.0, "slots": 1}]})
	cb.sign_label(node, "CITY PARKING", W(Vector3(18, 3.0, 19.1)), 0.0, 64)


# ------------------------------------------------------------------ sidewalk furniture
func _street_furniture(t: String) -> void:
	var residential := t in ["houses", "apartments", "sports_park"]
	var downtown := t in ["offices", "offices2", "bank_hotel", "parking", "shops", "shops2", "quickstop"]
	var edge := 23.3
	for side in 4:
		var yaw: float = [PI, PI * 0.5, 0.0, -PI * 0.5][side]   # lamp arm points to the road
		for off in [-11.0, 11.0]:
			var lp: Vector3
			match side:
				0: lp = Vector3(off, 0, -edge)
				1: lp = Vector3(edge, 0, off)
				2: lp = Vector3(off, 0, edge)
				_: lp = Vector3(-edge, 0, off)
			if residential:
				continue
			cb.lamp_positions.append(PropsKit.lamp(b, cols, W(lp), yaw))
		if downtown or t in ["market", "town_plaza", "diner_block"]:
			for off2 in [-17.0, 0.0, 17.0]:
				var tp: Vector3
				match side:
					0: tp = Vector3(off2, 0, -22.3)
					1: tp = Vector3(22.3, 0, off2)
					2: tp = Vector3(off2, 0, 22.3)
					_: tp = Vector3(-22.3, 0, off2)
				if rng.randf() < 0.65:
					cb.tree_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.8), W(tp)))
					b.box(Transform3D(Basis.IDENTITY, W(tp) + Vector3(0, 0.01, 0)), Vector3(1.2, 0.02, 1.2), Color(0.35, 0.28, 0.2), K.DIRT)
	if residential:
		# power poles + sagging wires along the north and south edges
		for side in [-1.0, 1.0]:
			var tops: Array = []
			for k in 4:
				var pp := W(Vector3(-19.0 + k * 12.7, 0, side * 23.1))
				tops.append(PropsKit.power_pole(b, cols, pp, 0.0))
				if k % 2 == 0:
					cb.lamp_positions.append(PropsKit.lamp(b, cols, pp + Vector3(0, 0, 0.001), PI if side < 0 else 0.0))
			for k in tops.size() - 1:
				PropsKit.wire(b, tops[k], tops[k + 1], [-0.9, 0.0, 0.9])
	# hydrants, bins, corner signs
	PropsKit.hydrant(b, W(Vector3(-21.5, 0, 22.4)))
	PropsKit.trash_bin(b, cols, W(Vector3(22.4, 0, -21.5)), Color(0.2, 0.35, 0.6) if downtown else Color(0.2, 0.45, 0.25))
	var ns: String = CityMap.STREETS_NS[i + 1]
	var ew: String = CityMap.STREETS_EW[clampi(j, 0, CityMap.STREETS_EW.size() - 1)]
	var corner := W(Vector3(23.2, 0, 23.2))
	b.cylinder(corner + Vector3(0, 1.4, 0), 0.04, 0.04, 2.8, Color(0.3, 0.35, 0.3), K.METAL, 6)
	b.box(Transform3D(Basis.IDENTITY, corner + Vector3(0, 2.75, 0)), Vector3(0.05, 0.22, 1.3), Color(0.15, 0.45, 0.25), K.PAINT)
	b.box(Transform3D(Basis.IDENTITY, corner + Vector3(0, 2.5, 0)), Vector3(1.3, 0.22, 0.05), Color(0.15, 0.45, 0.25), K.PAINT)
	var l1 := cb.sign_label(node, ns, corner + Vector3(0.05, 2.75, 0), PI * 0.5, 28)
	l1.visibility_range_end = 30.0
	var l2 := cb.sign_label(node, ew, corner + Vector3(0, 2.5, 0.05), 0.0, 28)
	l2.visibility_range_end = 30.0
	if downtown and (i + j) % 2 == 0:
		PropsKit.traffic_light(b, cols, W(Vector3(23.4, 0, 21.0)), PI * 0.5)
	elif not downtown:
		PropsKit.stop_sign(b, W(Vector3(23.3, 0, 20.5)), PI * 0.5)
	if t in ["shops", "shops2", "diner_block", "market"]:
		for p in [Vector3(-8, 0, 22.4), Vector3(8, 0, -22.4)]:
			var yaw2 := PI if p.z > 0 else 0.0
			PropsKit.bench(b, cols, X(p, yaw2))
			var seat := Seat.new()
			seat.transform = X(p, yaw2 + PI)
			node.add_child(seat)
