class_name CityBuilder
extends RefCounted
## Builds WESTBRIDGE: ground, roads with markings, raised blocks with sidewalks,
## buildings/props (via CityBlocks), pedestrian network, places, vegetation and the
## mountain backdrop. Static geometry is batched per block (1 draw call each) with a
## low-detail skyline mesh for distance (HLOD), so it stays cheap on phones.

const K := GeoBatch.Kind

var root: Node3D
var graph := PedGraph.new()
var places: Array = []
var lamp_positions: Array = []
var interior_light_positions: Array = []
var rng := RandomNumberGenerator.new()
var skyline := GeoBatch.new()
var player_spawn: Vector3 = Vector3.ZERO
var player_home: Place
var block_rings: Dictionary = {}       ## Vector2i -> ring node ids
var view_distance: float = 220.0
var tree_spots: Array = []             ## extra round trees (Transform3D)
var pine_spots: Array = []


func build(parent: Node3D, p_seed: int = 1984) -> void:
	rng.seed = p_seed
	view_distance = float(Settings.get_value("view_distance", 220.0))
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)
	_build_ground()
	_build_roads()
	var blocks := CityBlocks.new(self)
	for i in CityMap.COLS:
		for j in CityMap.ROWS:
			blocks.build_block(i, j)
	_connect_crosswalks()
	_build_vegetation()
	_build_backdrop()
	var sky_mi := skyline.to_instance("Skyline")
	sky_mi.visibility_range_begin = view_distance - 25.0
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sky_mi)


# ------------------------------------------------------------------ helpers used by CityBlocks
func add_place(type: String, pname: String, entry: Vector3, ring: Array, opts: Dictionary = {}) -> Place:
	var p := Place.new()
	p.id = places.size()
	p.type = type
	p.name = pname
	p.district = CityMap.district_at(entry)
	p.entry_pos = Vector3(entry.x, CityMap.CURB_H, entry.z)
	p.entry_node = graph.add_node(p.entry_pos)
	graph.link_to_nearest(p.entry_node, ring)
	p.inside_pos = opts.get("inside", p.entry_pos)
	p.open_hour = opts.get("open", 0.0)
	p.close_hour = opts.get("close", 24.0)
	p.tags = opts.get("tags", [])
	p.capacity = opts.get("capacity", 8)
	p.price_level = opts.get("price", 1)
	p.jobs = opts.get("jobs", [])
	p.enterable = opts.get("enterable", false)
	places.append(p)
	return p


## Interior walkable spots connected to the door.
func add_interior(p: Place, door_inside: Vector3, spots: Array) -> void:
	var din := graph.add_node(door_inside)
	graph.connect_nodes(p.entry_node, din)
	p.interior_nodes.append(din)
	for s in spots:
		var sp: Vector3 = s["pos"]
		var nid := graph.add_node(sp)
		graph.connect_nodes(din, nid)
		p.interior_nodes.append(nid)
		var d: Dictionary = s.duplicate()
		d["node"] = nid
		d["taken_by"] = -1
		p.spots.append(d)
	p.inside_pos = door_inside


func sign_label(parent: Node3D, text: String, pos: Vector3, yaw: float, size: int = 72, color: Color = Color(1, 0.96, 0.86)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.05, 0.06)
	l.position = pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.12)
	l.rotation.y = yaw
	l.visibility_range_end = 90.0
	parent.add_child(l)
	return l


func add_to_skyline(center: Vector3, size: Vector3, color: Color, kind: int) -> void:
	skyline.abox(center + Vector3(0, size.y * 0.5, 0), size, color, kind, 0.0, rng.randf())


# ------------------------------------------------------------------ ground & roads
func _build_ground() -> void:
	var b := GeoBatch.new()
	b.floor_quad(Vector3(0, -0.02, 0), Vector2(1400, 1400), Color(0.36, 0.5, 0.27), K.GRASS)
	var mi := b.to_instance("Ground")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var cols := ColliderSet.new()
	cols.add_box(Vector3(0, -0.5, 0), Vector3(1400, 1.0, 1400))
	root.add_child(cols.build("GroundCollision"))


func _build_roads() -> void:
	var b := GeoBatch.new()
	var he := CityMap.half_extent()
	var asphalt := Color(0.24, 0.25, 0.27)
	var white := Color(0.92, 0.92, 0.88)
	var yellow := Color(0.95, 0.75, 0.2)
	var rw := CityMap.ROAD
	for x in CityMap.road_xs():
		b.floor_quad(Vector3(x, 0.0, 0), Vector2(rw, he.y * 2.0), asphalt, K.ASPHALT)
	for z in CityMap.road_zs():
		b.floor_quad(Vector3(0, 0.001, z), Vector2(he.x * 2.0, rw), asphalt, K.ASPHALT)
	# Centre dashes + edge lines between intersections, crosswalks at each intersection.
	for x in CityMap.road_xs():
		var zs := CityMap.road_zs()
		for k in zs.size() - 1:
			var z0: float = zs[k] + rw * 0.5 + 2.2
			var z1: float = zs[k + 1] - rw * 0.5 - 2.2
			var z := z0
			while z < z1 - 1.5:
				b.floor_quad(Vector3(x, 0.012, z + 1.25), Vector2(0.15, 2.5), yellow, K.ROAD_PAINT)
				z += 5.0
			for side in [-1.0, 1.0]:
				b.floor_quad(Vector3(x + side * (rw * 0.5 - 0.35), 0.012, (z0 + z1) * 0.5), Vector2(0.12, z1 - z0), white, K.ROAD_PAINT)
	for z in CityMap.road_zs():
		var xs := CityMap.road_xs()
		for k in xs.size() - 1:
			var x0: float = xs[k] + rw * 0.5 + 2.2
			var x1: float = xs[k + 1] - rw * 0.5 - 2.2
			var x := x0
			while x < x1 - 1.5:
				b.floor_quad(Vector3(x + 1.25, 0.012, z), Vector2(2.5, 0.15), yellow, K.ROAD_PAINT)
				x += 5.0
			for side in [-1.0, 1.0]:
				b.floor_quad(Vector3((x0 + x1) * 0.5, 0.012, z + side * (rw * 0.5 - 0.35)), Vector2(x1 - x0, 0.12), white, K.ROAD_PAINT)
	for x in CityMap.road_xs():
		for z in CityMap.road_zs():
			for k in 6:
				var off := -rw * 0.5 + 1.0 + k * 1.6
				b.floor_quad(Vector3(x + off, 0.013, z - rw * 0.5 - 1.1), Vector2(0.8, 2.0), white, K.ROAD_PAINT)
				b.floor_quad(Vector3(x + off, 0.013, z + rw * 0.5 + 1.1), Vector2(0.8, 2.0), white, K.ROAD_PAINT)
				b.floor_quad(Vector3(x - rw * 0.5 - 1.1, 0.013, z + off), Vector2(2.0, 0.8), white, K.ROAD_PAINT)
				b.floor_quad(Vector3(x + rw * 0.5 + 1.1, 0.013, z + off), Vector2(2.0, 0.8), white, K.ROAD_PAINT)
			# manhole
			b.cylinder(Vector3(x + 2.0, 0.005, z + 2.0), 0.4, 0.4, 0.01, Color(0.2, 0.2, 0.21), K.METAL, 10)
	var mi := b.to_instance("Roads")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _connect_crosswalks() -> void:
	# Each block ring has per_side = 4 nodes -> corners at 0, 4, 8, 12:
	# 0 = (-h,-h) NW, 4 = (h,-h) NE, 8 = (h,h) SE, 12 = (-h,h) SW
	for i in CityMap.COLS:
		for j in CityMap.ROWS:
			var r: Array = block_rings[Vector2i(i, j)]
			if i + 1 < CityMap.COLS:
				var e: Array = block_rings[Vector2i(i + 1, j)]
				graph.connect_nodes(r[4], e[0])
				graph.connect_nodes(r[8], e[12])
				graph.crosswalk_edges.append([r[4], e[0]])
				graph.crosswalk_edges.append([r[8], e[12]])
			if j + 1 < CityMap.ROWS:
				var s: Array = block_rings[Vector2i(i, j + 1)]
				graph.connect_nodes(r[12], s[0])
				graph.connect_nodes(r[8], s[4])
				graph.crosswalk_edges.append([r[12], s[0]])
				graph.crosswalk_edges.append([r[8], s[4]])


# ------------------------------------------------------------------ vegetation & backdrop
func _build_vegetation() -> void:
	var he := CityMap.half_extent()
	# Forest ring around the town.
	var attempts := 2600
	for k in attempts:
		var p := Vector3(rng.randf_range(-430, 430), 0, rng.randf_range(-400, 400))
		if absf(p.x) < he.x + 14.0 and absf(p.z) < he.y + 14.0:
			continue
		var s := rng.randf_range(0.8, 1.6)
		pine_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s)), p))
	_multimesh("Pines", PropsKit.pine_tree_mesh(), pine_spots, 0.0, view_distance + 260.0)
	_multimesh("Trees", PropsKit.round_tree_mesh(), tree_spots, 0.0, view_distance)
	# Collision for trees close to the town edge only.
	var cols := ColliderSet.new()
	for t in pine_spots:
		var o: Vector3 = (t as Transform3D).origin
		if absf(o.x) < he.x + 60.0 and absf(o.z) < he.y + 60.0:
			cols.add_box(o + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))
	for t in tree_spots:
		cols.add_box((t as Transform3D).origin + Vector3(0, 1.3, 0), Vector3(0.4, 2.6, 0.4))
	root.add_child(cols.build("TreeCollision"))


func _multimesh(n: String, mesh: Mesh, xforms: Array, begin: float, end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = GeoBatch.material()
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	root.add_child(mmi)


func _build_backdrop() -> void:
	var b := GeoBatch.new()
	var n := 18
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.1, 0.1)
		var dist := rng.randf_range(560, 720)
		var h := rng.randf_range(90, 210)
		var r := rng.randf_range(160, 260)
		var c := Color(0.32, 0.42, 0.36).lerp(Color(0.45, 0.52, 0.6), rng.randf())
		b.cylinder(Vector3(cos(a) * dist, h * 0.5 - 5.0, sin(a) * dist), rng.randf_range(10, 40), r, h, c, K.GRASS, 9)
	var mi := b.to_instance("Mountains")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
