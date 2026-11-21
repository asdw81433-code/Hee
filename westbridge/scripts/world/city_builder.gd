class_name CityBuilder
extends RefCounted
## Builds WESTBRIDGE in two passes:
##
## 1. DATA PASS (at load, every cell of the 17x12 grid): runs the block / district
##    generators with geometry disabled to create places, jobs, the pedestrian
##    network, lamp positions and the low-detail skyline (HLOD). Each cell uses its
##    own deterministic seed (CityMap.cell_seed).
## 2. VISUAL PASS (streamed): when the player comes within range of a cell the same
##    generator runs again with the same seed and builds meshes, colliders, labels,
##    doors, seats, trees, roads and terrain for that cell only. Cells far away are
##    freed again. Far ground/roads, water, skyline and forests are always loaded.

const K := GeoBatch.Kind

var root: Node3D
var world_seed: int = 1984
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
var tree_spots: Array = []             ## round trees of the cell being built (Transform3D)
var pine_spots: Array = []             ## all forest pines (render)
var data_mode: bool = true
var cells: Dictionary = {}             ## Vector2i -> {"places": [], "pines": [], "node": Node3D}
var inodes: Dictionary = {}            ## Vector2i intersection -> graph node
var load_radius: float = 290.0
var unload_radius: float = 380.0
var stats := {"loaded": 0, "loads": 0, "unloads": 0, "data_ms": 0, "last_load_ms": 0.0, "mismatch": 0}

var _cur_cell: Vector2i
var _place_cursor: int = 0
var _world_root: Node3D
var game_world: Node                  ## GameWorld (service points open its menus)


func build(parent: Node3D, p_seed: int = 1984) -> void:
	world_seed = p_seed
	view_distance = float(Settings.get_value("view_distance", 220.0))
	load_radius = view_distance + 70.0
	unload_radius = view_distance + 160.0
	_world_root = Node3D.new()
	_world_root.name = "City"
	parent.add_child(_world_root)
	var t0 := Time.get_ticks_msec()
	# ---- data pass
	data_mode = true
	root = Node3D.new()          # throw-away parent: nodes made by the generators are freed below
	_create_inodes()
	for key in CityMap.all_cells():
		if CityMap.cell_kind(key.x, key.y) == "block":
			_cell_data(key)
	for key in CityMap.all_cells():
		if CityMap.cell_kind(key.x, key.y) != "block":
			_cell_data(key)
	_link_network()
	root.free()
	_bind_seats_all(null)
	root = _world_root
	data_mode = false
	stats.data_ms = Time.get_ticks_msec() - t0
	# ---- always-loaded far geometry
	var far := GeoBatch.new()
	for key in CityMap.all_cells():
		WorldTerrain.build_far_cell(far, key.x, key.y)
	RoadBuilder.build_far(far)
	var far_mi := far.to_instance("FarGround")
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(far_mi)
	root.add_child(WorldTerrain.outer_ring())
	root.add_child(WorldTerrain.water())
	root.add_child(WorldTerrain.world_bounds())
	_build_backdrop()
	_build_forest()
	var sky_mi := skyline.to_instance("Skyline")
	sky_mi.visibility_range_begin = view_distance - 25.0
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sky_mi)


# ------------------------------------------------------------------ data pass
func _cell_data(key: Vector2i) -> void:
	cells[key] = {"places": [], "pines": [], "node": null}
	_cur_cell = key
	rng.seed = CityMap.cell_seed(world_seed, key.x, key.y)
	_run_generator(key)


func _run_generator(key: Vector2i) -> void:
	if CityMap.is_original_town(key.x, key.y):
		CityBlocks.new(self).build_block(key.x, key.y)
	elif CityMap.cell_kind(key.x, key.y) == "block":
		DistrictBlocks.new(self).build_block(key.x, key.y)
	else:
		DistrictBlocks.new(self).build_open_cell(key.x, key.y)


## One graph node per road intersection (used by rural paths, bridges, crossings).
func _create_inodes() -> void:
	for a in range(CityMap.GI_MIN, CityMap.GI_MAX + 2):
		for bb in range(CityMap.GJ_MIN, CityMap.GJ_MAX + 2):
			if RoadBuilder.intersection_width(a, bb) > 0.0:
				var p := CityMap.intersection(a, bb)
				p.y = CityMap.road_height_at(p.x, p.z) + 0.05
				inodes[Vector2i(a, bb)] = graph.add_node(p)


func _is_block(gi: int, gj: int) -> bool:
	return CityMap.cell_kind(gi, gj) == "block" and block_rings.has(Vector2i(gi, gj))


## Crosswalks between neighbouring blocks; intersection nodes chained along every
## road that is not a plain street between two blocks (dirt roads, bridges,
## highway crossings, streets on the edge of town) and tied to the block corners.
func _link_network() -> void:
	var net_inodes := {}
	for a in range(CityMap.GI_MIN, CityMap.GI_MAX + 2):
		for bb in range(CityMap.GJ_MIN, CityMap.GJ_MAX + 2):
			# vertical edge between cells (a-1, bb) and (a, bb)
			var kv := CityMap.vedge(a, bb)
			if kv != "":
				if kv == "street" and _is_block(a - 1, bb) and _is_block(a, bb):
					var w: Array = block_rings[Vector2i(a - 1, bb)]
					var e: Array = block_rings[Vector2i(a, bb)]
					_crosswalk(w[4], e[0])
					_crosswalk(w[8], e[12])
				else:
					_chain(Vector2i(a, bb), Vector2i(a, bb + 1), net_inodes)
			# horizontal edge between cells (a, bb-1) and (a, bb)
			var kh := CityMap.hedge(a, bb)
			if kh != "":
				if kh == "street" and _is_block(a, bb - 1) and _is_block(a, bb):
					var n: Array = block_rings[Vector2i(a, bb - 1)]
					var s: Array = block_rings[Vector2i(a, bb)]
					_crosswalk(n[12], s[0])
					_crosswalk(n[8], s[4])
				else:
					_chain(Vector2i(a, bb), Vector2i(a + 1, bb), net_inodes)
	# Intersections that only join block-to-block streets carry no paths: drop them.
	for key in inodes.keys():
		if not net_inodes.has(key):
			var lone: int = inodes[key]
			if graph.astar.get_point_connections(lone).is_empty():
				graph.astar.remove_point(lone)
				inodes.erase(key)
	for key in net_inodes.keys():
		var nid: int = inodes[key]
		for corner in [[Vector2i(-1, -1), 8], [Vector2i(0, -1), 12], [Vector2i(-1, 0), 4], [Vector2i(0, 0), 0]]:
			var ck: Vector2i = key + (corner[0] as Vector2i)
			if _is_block(ck.x, ck.y):
				graph.connect_nodes(nid, (block_rings[ck] as Array)[corner[1]])


func _crosswalk(a: int, b: int) -> void:
	graph.connect_nodes(a, b)
	graph.crosswalk_edges.append([a, b])


func _chain(k0: Vector2i, k1: Vector2i, net: Dictionary) -> void:
	if inodes.has(k0) and inodes.has(k1):
		graph.connect_nodes(inodes[k0], inodes[k1])
		net[k0] = true
		net[k1] = true


## Graph nodes an open (rural / beach) cell's places can attach to.
func open_cell_links(gi: int, gj: int) -> Array:
	var out: Array = []
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var k: Vector2i = Vector2i(gi, gj) + d
		if inodes.has(k):
			out.append(inodes[k])
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var k2: Vector2i = Vector2i(gi, gj) + d
		if block_rings.has(k2):
			out.append_array(block_rings[k2])
	return out


# ------------------------------------------------------------------ helpers used by the generators
func add_place(type: String, pname: String, entry: Vector3, ring: Array, opts: Dictionary = {}) -> Place:
	var cell: Dictionary = cells[_cur_cell]
	if not data_mode:
		# Visual pass: hand back the place created by the data pass (same order).
		if _place_cursor < (cell.places as Array).size():
			_place_cursor += 1
			return cell.places[_place_cursor - 1]
		return Place.new()
	var p := Place.new()
	p.id = places.size()
	p.type = type
	p.name = pname
	p.district = CityMap.district_at(entry)
	p.entry_pos = Vector3(entry.x, CityMap.ground_y(entry.x, entry.z), entry.z)
	if ring.is_empty() and graph.node_count() > 0:
		ring = [graph.nearest(p.entry_pos)]   # remote spot: walk across country to the closest path
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
	(cell.places as Array).append(p)
	return p


## Interior walkable spots connected to the door.
func add_interior(p: Place, door_inside: Vector3, spots: Array) -> void:
	if not data_mode:
		return
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
	if not data_mode:
		return
	skyline.abox(center + Vector3(0, size.y * 0.5, 0), size, color, kind, 0.0, 0.5)


## Forest pine at a world position (data pass only; collision comes with the cell).
func add_pine(pos: Vector3, s: float, yaw: float) -> void:
	if not data_mode:
		return
	var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * (0.95 + fposmod(yaw, 0.3)), s)), pos)
	pine_spots.append(t)
	(cells[_cur_cell].pines as Array).append(t)


# ------------------------------------------------------------------ streaming
func is_loaded(key: Vector2i) -> bool:
	return cells.has(key) and cells[key].node != null


func load_cell(key: Vector2i) -> void:
	if not cells.has(key) or cells[key].node != null:
		return
	var t0 := Time.get_ticks_usec()
	var cell_node := Node3D.new()
	cell_node.name = "Cell_%d_%d" % [key.x, key.y]
	_world_root.add_child(cell_node)
	# Re-run the generator in visual mode, isolating every data-pass side effect.
	var saved := [graph, block_rings.get(key), lamp_positions, interior_light_positions, player_spawn, player_home]
	var spot_sizes: Array = []
	var spot_arrays: Array = []
	for p in cells[key].places:
		spot_sizes.append((p as Place).spots.size())
		spot_arrays.append((p as Place).spots)
	root = cell_node
	graph = PedGraph.new()
	lamp_positions = []
	interior_light_positions = []
	tree_spots = []
	_cur_cell = key
	_place_cursor = 0
	data_mode = false
	rng.seed = CityMap.cell_seed(world_seed, key.x, key.y)
	_run_generator(key)
	if _place_cursor != (cells[key].places as Array).size():
		stats.mismatch += 1     # visual pass diverged from the data pass (must stay 0)
		push_warning("Cell %s: visual pass made %d places, data pass %d" % [str(key), _place_cursor, (cells[key].places as Array).size()])
	graph = saved[0]
	if saved[1] != null:
		block_rings[key] = saved[1]
	lamp_positions = saved[2]
	interior_light_positions = saved[3]
	player_spawn = saved[4]
	player_home = saved[5]
	root = _world_root
	# Generators may append spots directly; keep the data-pass spots and point the
	# seat spots at the Seat nodes that now exist in this cell.
	for k in spot_sizes.size():
		var pl := cells[key].places[k] as Place
		pl.spots = spot_arrays[k]          # generators may replace the array...
		pl.spots.resize(spot_sizes[k])     # ...or append to it
	_place_cursor = 0
	_bind_seats(cells[key].places, cell_node)
	# Terrain, roads, trees and tree collision of the cell.
	var tb := GeoBatch.new()
	var cols := ColliderSet.new()
	if CityMap.cell_kind(key.x, key.y) != "block":
		WorldTerrain.build_cell_ground(tb, key.x, key.y)
	RoadBuilder.build_cell(tb, cols, key.x, key.y, [])
	if not tb.is_empty():
		var mi := tb.to_instance("Ground")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = view_distance + 40.0
		cell_node.add_child(mi)
	for t in cells[key].pines:
		cols.add_box((t as Transform3D).origin + Vector3(0, 1.5, 0), Vector3(0.5, 3.0, 0.5))
	for t in tree_spots:
		cols.add_box((t as Transform3D).origin + Vector3(0, 1.3, 0), Vector3(0.4, 2.6, 0.4))
	var body := cols.build("RoadsTreesCollision")
	body.add_child(WorldTerrain.cell_collision(key.x, key.y))
	cell_node.add_child(body)
	if not tree_spots.is_empty():
		var mm := _multimesh("Trees", PropsKit.round_tree_mesh(), tree_spots, 0.0, view_distance)
		cell_node.add_child(mm)
	tree_spots = []
	_add_service_points(cells[key].places, cell_node)
	cells[key].node = cell_node
	stats.loaded += 1
	stats.loads += 1
	stats.last_load_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Shop counters / job boards / ATMs at every place that offers the player something.
func _add_service_points(cell_places: Array, cell_node: Node3D) -> void:
	var others: Array = []
	for n in cell_node.find_children("*", "SimpleInteractable", true, false):
		others.append(n)
	for p in cell_places:
		var pl := p as Place
		if not ServicePoint.wants(pl):
			continue
		var pos := pl.inside_pos if pl.enterable else pl.entry_pos
		# A quick-buy counter right at the same door is folded into the menu ("Use now").
		for o in others:
			var si := o as SimpleInteractable
			var gp: Vector3 = si.global_position if si.is_inside_tree() else si.position
			if si.place == pl and Vector2(gp.x - pos.x, gp.z - pos.z).length() < 1.6:
				si.enabled = false
		var sp := ServicePoint.new()
		sp.name = "Service_%d" % pl.id
		sp.place = pl
		sp.world = game_world
		sp.position = pos
		cell_node.add_child(sp)


func unload_cell(key: Vector2i) -> void:
	if not is_loaded(key):
		return
	_bind_seats(cells[key].places, null)
	(cells[key].node as Node3D).queue_free()
	cells[key].node = null
	stats.loaded -= 1
	stats.unloads += 1


## Loads cells near `pos` (nearest first, within a per-frame time budget) and
## unloads far ones. Cells within 70 m are always loaded immediately so the
## player never stands on missing ground (teleports, fast vehicles).
func update_streaming(pos: Vector3, budget_ms: float = 6.0) -> void:
	var t0 := Time.get_ticks_usec()
	var want: Array = []
	for key in cells.keys():
		var c := CityMap.block_center(key.x, key.y)
		var d := Vector2(c.x - pos.x, c.z - pos.z).length()
		if d > unload_radius:
			unload_cell(key)
		elif d < load_radius and cells[key].node == null:
			want.append([d, key])
	want.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for w in want:
		if w[0] > 70.0 and (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break
		load_cell(w[1])


## Seat spots reference Seat nodes, which only exist while the cell is loaded.
func _bind_seats(cell_places: Array, cell_node: Node3D) -> void:
	var seats: Array = cell_node.find_children("*", "Seat", true, false) if cell_node else []
	for p in cell_places:
		for spot in (p as Place).spots:
			if not (spot as Dictionary).has("seat"):
				continue
			spot["seat"] = null
			for st in seats:
				if (st as Node3D).transform.origin.distance_to(spot["pos"]) < 0.08 or (st as Node3D).global_transform.origin.distance_to(spot["pos"]) < 0.08:
					spot["seat"] = st
					break


func _bind_seats_all(_n: Variant) -> void:
	for key in cells.keys():
		_bind_seats(cells[key].places, null)


func load_all_near(pos: Vector3) -> void:
	update_streaming(pos, 1e9)


# ------------------------------------------------------------------ always-loaded scenery
func _build_forest() -> void:
	# Extra pines outside the playable grid (render only).
	var r := CityMap.world_rect()
	var orng := RandomNumberGenerator.new()
	orng.seed = world_seed + 99
	for k in 1500:
		var p := Vector3(orng.randf_range(r.position.x - 260.0, r.end.x + 260.0), 0, orng.randf_range(r.position.y - 260.0, r.end.y + 40.0))
		if r.grow(CityMap.PITCH * 0.6).has_point(Vector2(p.x, p.z)):
			continue
		p.y = CityMap.height_at(p.x, p.z)
		if p.y < CityMap.SEA_LEVEL + 0.3:
			continue
		var s := orng.randf_range(0.9, 1.7)
		pine_spots.append(Transform3D(Basis(Vector3.UP, orng.randf() * TAU).scaled(Vector3(s, s * orng.randf_range(0.9, 1.25), s)), p))
	var near_mesh := PropsKit.pine_tree_mesh(0)
	var far_mesh := PropsKit.pine_tree_mesh(1)
	var chunks: Dictionary = {}
	for t in pine_spots:
		var o: Vector3 = (t as Transform3D).origin
		var key := Vector2i(int(floor(o.x / 120.0)), int(floor(o.z / 120.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t)
	for key in chunks.keys():
		var arr: Array = chunks[key]
		var near_mi := _multimesh("Pines_%d_%d" % [key.x, key.y], near_mesh, arr, 0.0, 150.0)
		near_mi.visibility_range_end_margin = 10.0
		root.add_child(near_mi)
		var far_mi := _multimesh("PinesFar_%d_%d" % [key.x, key.y], far_mesh, arr, 150.0, view_distance + 500.0)
		far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(far_mi)


func _multimesh(n: String, mesh: Mesh, xforms: Array, begin: float, end: float) -> MultiMeshInstance3D:
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
	return mmi


func _build_backdrop() -> void:
	var b := GeoBatch.new()
	var brng := RandomNumberGenerator.new()
	brng.seed = world_seed + 7
	var centre := CityMap.world_rect().get_center()
	for k in 26:
		var a := TAU * k / 26.0 + brng.randf_range(-0.08, 0.08)
		var dir := Vector2(cos(a), sin(a))
		if dir.y > 0.35:
			continue    # open sea to the south
		var dist := brng.randf_range(1000, 1200)
		var p := centre + dir * dist
		var h := brng.randf_range(120, 260)
		var r := brng.randf_range(200, 320)
		var col := Color(0.32, 0.42, 0.36).lerp(Color(0.45, 0.52, 0.6), brng.randf())
		b.cylinder(Vector3(p.x, h * 0.5 - 5.0, p.y), brng.randf_range(10, 40), r, h, col, K.GRASS, 9)
	var mi := b.to_instance("Mountains")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
