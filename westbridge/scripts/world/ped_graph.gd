class_name PedGraph
extends RefCounted
## Pedestrian navigation network (sidewalk rings, crosswalks, park paths, doors,
## building interiors) on top of AStar3D. Cheap enough to path hundreds of NPCs and
## also used by the off-screen simulation to move people between places.

var astar := AStar3D.new()
var _next_id: int = 0
var crosswalk_edges: Array = []   ## [a, b] pairs that cross a road


func add_node(pos: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	astar.add_point(id, pos)
	return id


func connect_nodes(a: int, b: int) -> void:
	if a >= 0 and b >= 0 and a != b and not astar.are_points_connected(a, b):
		astar.connect_points(a, b, true)


func pos(id: int) -> Vector3:
	return astar.get_point_position(id)


func nearest(p: Vector3) -> int:
	return astar.get_closest_point(p)


func path(from_id: int, to_id: int) -> PackedVector3Array:
	if from_id < 0 or to_id < 0:
		return PackedVector3Array()
	return astar.get_point_path(from_id, to_id)


func path_ids(from_id: int, to_id: int) -> PackedInt64Array:
	return astar.get_id_path(from_id, to_id)


func node_count() -> int:
	return astar.get_point_count()


## Adds a closed loop of nodes along a rectangle (inset sidewalk ring).
## Returns ids in order; corners are at index 0, n, 2n, 3n (n = per_side).
func add_ring(center: Vector3, half: float, per_side: int, y: float) -> Array:
	var ids: Array = []
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for c in 4:
		var a: Vector3 = corners[c]
		var b: Vector3 = corners[(c + 1) % 4]
		for k in per_side:
			var p := center + a.lerp(b, float(k) / per_side)
			p.y = y
			ids.append(add_node(p))
	for k in ids.size():
		connect_nodes(ids[k], ids[(k + 1) % ids.size()])
	return ids


## Connects `id` to the nearest node of `candidates` (or the whole graph).
func link_to_nearest(id: int, candidates: Array) -> int:
	var best := -1
	var best_d := INF
	var p := pos(id)
	for c in candidates:
		if c == id:
			continue
		var d := p.distance_to(pos(c))
		if d < best_d:
			best_d = d
			best = c
	connect_nodes(id, best)
	return best


## Every node reachable from node 0? (used by tests)
func is_connected_graph() -> bool:
	return component_count() <= 1


func _old_is_connected_graph() -> bool:
	if node_count() == 0:
		return true
	var ids := astar.get_point_ids()
	var start: int = ids[0]
	for id in ids:
		if id == start:
			continue
		if astar.get_id_path(start, id).is_empty():
			return false
	return true


## Number of connected components (BFS over the AStar connections).
func component_count() -> int:
	var seen := {}
	var comps := 0
	for id in astar.get_point_ids():
		if seen.has(id):
			continue
		comps += 1
		var stack: Array = [id]
		seen[id] = true
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			for nb in astar.get_point_connections(cur):
				if not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
	return comps


## Component id per node (for diagnostics).
func components() -> Dictionary:
	var comp := {}
	var n := 0
	for id in astar.get_point_ids():
		if comp.has(id):
			continue
		var stack: Array = [id]
		comp[id] = n
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			for nb in astar.get_point_connections(cur):
				if not comp.has(nb):
					comp[nb] = n
					stack.append(nb)
		n += 1
	return comp


## Random walk of `steps` hops from `start`, never ending further than max_dist from origin.
func random_walk(start: int, rng: RandomNumberGenerator, steps: int, origin: Vector3, max_dist: float) -> int:
	var cur := start
	for k in steps:
		var nbs := astar.get_point_connections(cur)
		if nbs.is_empty():
			break
		var nxt: int = nbs[rng.randi() % nbs.size()]
		if pos(nxt).distance_to(origin) > max_dist:
			continue
		cur = nxt
	return cur
