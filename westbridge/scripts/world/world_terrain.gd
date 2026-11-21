class_name WorldTerrain
extends RefCounted
## Terrain for every world cell: near ground meshes, collision (box when flat,
## HeightMapShape3D on hills/river banks/coast), far LOD ground, the outer
## landscape around the map and the water surfaces (sea, Calder river, lake).

const K := GeoBatch.Kind
const CELL := CityMap.PITCH
const HALF := CityMap.PITCH * 0.5

const GROUND_COLORS := {
	"forest": [Color(0.27, 0.4, 0.21), K.GRASS], "field": [Color(0.52, 0.47, 0.3), K.DIRT],
	"farm": [Color(0.38, 0.52, 0.27), K.GRASS], "orchard": [Color(0.36, 0.5, 0.26), K.GRASS],
	"windmill_farm": [Color(0.4, 0.53, 0.28), K.GRASS], "campground": [Color(0.33, 0.47, 0.25), K.GRASS],
	"rural_gas": [Color(0.38, 0.5, 0.28), K.GRASS], "hill_park": [Color(0.33, 0.48, 0.25), K.GRASS],
	"lookout": [Color(0.36, 0.5, 0.27), K.GRASS], "radio_tower": [Color(0.34, 0.48, 0.26), K.GRASS],
	"beach": [Color(0.88, 0.8, 0.6), K.DIRT], "beach_pier": [Color(0.88, 0.8, 0.6), K.DIRT], "beach_marina": [Color(0.88, 0.8, 0.6), K.DIRT],
	"highway": [Color(0.38, 0.5, 0.29), K.GRASS], "river": [Color(0.32, 0.3, 0.26), K.DIRT], "lake": [Color(0.32, 0.3, 0.26), K.DIRT],
	"sea": [Color(0.75, 0.7, 0.55), K.DIRT], "outside": [Color(0.3, 0.44, 0.23), K.GRASS],
}


static func ground_style(t: String) -> Array:
	return GROUND_COLORS.get(t, [Color(0.36, 0.5, 0.27), K.GRASS])


static func cell_is_flat(gi: int, gj: int) -> bool:
	var c := CityMap.block_center(gi, gj)
	var h0 := CityMap.height_at(c.x, c.z)
	for dx in [-HALF, -HALF * 0.5, 0.0, HALF * 0.5, HALF]:
		for dz in [-HALF, -HALF * 0.5, 0.0, HALF * 0.5, HALF]:
			if absf(CityMap.height_at(c.x + dx, c.z + dz) - h0) > 0.01:
				return false
	return true


## Near terrain surface for a cell (only cells that show bare ground).
static func build_cell_ground(b: GeoBatch, gi: int, gj: int, step: float = 4.142857) -> void:
	var t := CityMap.cell_type(gi, gj)
	var st := ground_style(t)
	var c := CityMap.block_center(gi, gj)
	var n := int(round(CELL / step))
	var base_col: Color = st[0]
	for ix in n:
		for iz in n:
			var x0 := c.x - HALF + ix * step
			var z0 := c.z - HALF + iz * step
			var col := base_col
			# Wet sand / shoreline tint
			var hh := CityMap.height_at(x0, z0)
			if t.begins_with("beach") and hh < CityMap.SEA_LEVEL + 0.25:
				col = base_col.darkened(0.25)
			grid_quad(b, x0, z0, step, col, st[1], 0.0)


## One quad following the terrain (heights sampled at the 4 corners).
static func grid_quad(b: GeoBatch, x0: float, z0: float, s: float, col: Color, kind: int, lift: float) -> void:
	var p00 := Vector3(x0, CityMap.height_at(x0, z0) + lift, z0)
	var p10 := Vector3(x0 + s, CityMap.height_at(x0 + s, z0) + lift, z0)
	var p11 := Vector3(x0 + s, CityMap.height_at(x0 + s, z0 + s) + lift, z0 + s)
	var p01 := Vector3(x0, CityMap.height_at(x0, z0 + s) + lift, z0 + s)
	b.quad_pts(p01, p11, p10, p00, col, kind)


## Collision for the 58x58 m cell square.
static func cell_collision(gi: int, gj: int) -> CollisionShape3D:
	var c := CityMap.block_center(gi, gj)
	var cs := CollisionShape3D.new()
	cs.name = "Terrain"
	if cell_is_flat(gi, gj):
		var bs := BoxShape3D.new()
		bs.size = Vector3(CELL, 2.0, CELL)
		cs.shape = bs
		cs.position = Vector3(c.x, CityMap.height_at(c.x, c.z) - 1.0, c.z)
		return cs
	var hm := HeightMapShape3D.new()
	var n := int(CELL) + 1
	hm.map_width = n
	hm.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for iz in n:
		for ix in n:
			data[iz * n + ix] = CityMap.height_at(c.x - HALF + ix, c.z - HALF + iz)
	hm.map_data = data
	cs.shape = hm
	cs.position = Vector3(c.x, 0.0, c.z)
	return cs


## Very coarse ground used by the far LOD groups for cells that are not loaded.
static func build_far_cell(b: GeoBatch, gi: int, gj: int) -> void:
	var t := CityMap.cell_type(gi, gj)
	var kind := CityMap.cell_kind(gi, gj)
	var col: Color
	var k: int
	if kind == "block":
		col = Color(0.55, 0.55, 0.54)
		k = K.CONCRETE
	else:
		var st := ground_style(t)
		col = st[0]
		k = st[1]
	var c := CityMap.block_center(gi, gj)
	var s := CELL / 4.0
	for ix in 4:
		for iz in 4:
			grid_quad(b, c.x - HALF + ix * s, c.z - HALF + iz * s, s, col, k, -0.35)


## Landscape outside the playable grid (low detail, always visible).
static func outer_ring() -> MeshInstance3D:
	var b := GeoBatch.new()
	var r := CityMap.world_rect()
	var s := 40.0
	var x := -1300.0
	while x < 1300.0:
		var z := -1300.0
		while z < 1300.0:
			# Skip only quads fully inside the grid (the far cell ground covers those);
			# quads straddling the edge overlap it slightly so there is never a gap.
			var inside := x >= r.position.x and x + s <= r.end.x and z >= r.position.y and z + s <= r.end.y
			if not inside:
				var hh := CityMap.height_at(x, z)
				var col := Color(0.29, 0.42, 0.22) if hh > CityMap.SEA_LEVEL else Color(0.7, 0.66, 0.5)
				grid_quad(b, x, z, s, col, K.GRASS if hh > CityMap.SEA_LEVEL else K.DIRT, -0.05)
			z += s
		x += s
	var mi := b.to_instance("OuterTerrain")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func water() -> MeshInstance3D:
	var b := GeoBatch.new()
	var sea_col := Color(0.18, 0.42, 0.55)
	var riv_col := Color(0.2, 0.38, 0.42)
	# Sea (south)
	b.quad_pts(Vector3(-1400, CityMap.SEA_LEVEL, 1400), Vector3(1400, CityMap.SEA_LEVEL, 1400), Vector3(1400, CityMap.SEA_LEVEL, 178), Vector3(-1400, CityMap.SEA_LEVEL, 178), sea_col, K.WATER)
	# River (lake to the coastal bridge)
	var x0 := CityMap.RIVER_X - 20.0
	var x1 := CityMap.RIVER_X + 20.0
	b.quad_pts(Vector3(x0, CityMap.RIVER_LEVEL, 182), Vector3(x1, CityMap.RIVER_LEVEL, 182), Vector3(x1, CityMap.RIVER_LEVEL, -378), Vector3(x0, CityMap.RIVER_LEVEL, -378), riv_col, K.WATER)
	# Lake
	var segs := 20
	var lc := Vector3(CityMap.RIVER_X, CityMap.RIVER_LEVEL, -377.0)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := lc + Vector3(cos(a0), 0, sin(a0)) * 29.0
		var p1 := lc + Vector3(cos(a1), 0, sin(a1)) * 29.0
		b.tri_pts(lc, p1, p0, riv_col, K.WATER)
	var mi := b.to_instance("Water")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Invisible walls around the playable area.
static func world_bounds() -> StaticBody3D:
	var r := CityMap.world_rect().grow(CELL * 0.9)
	var cols := ColliderSet.new()
	var cx := r.get_center().x
	var cz := r.get_center().y
	cols.add_box(Vector3(cx, 20, r.position.y), Vector3(r.size.x, 80, 2))
	cols.add_box(Vector3(cx, 20, r.end.y + 120.0), Vector3(r.size.x, 80, 2))
	cols.add_box(Vector3(r.position.x, 20, cz + 60.0), Vector3(2, 80, r.size.y + 120.0))
	cols.add_box(Vector3(r.end.x, 20, cz + 60.0), Vector3(2, 80, r.size.y + 120.0))
	return cols.build("WorldBounds")
