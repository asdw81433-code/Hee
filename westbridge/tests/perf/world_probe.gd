## Debug: builds the full world, loads every cell once and reports stats/errors.
extends Node3D


func _ready() -> void:
	var cb := CityBuilder.new()
	var t0 := Time.get_ticks_msec()
	cb.build(self, 1984)
	print("PROBE data pass %d ms, total build %d ms" % [cb.stats.data_ms, Time.get_ticks_msec() - t0])
	print("PROBE places %d, nav nodes %d, components %d, urban blocks %d, districts %s" % [cb.places.size(), cb.graph.node_count(), cb.graph.component_count(), CityMap.urban_block_count(), str(CityMap.district_names())])
	var comp := cb.graph.components()
	var sizes := {}
	for id in comp.keys():
		sizes[comp[id]] = sizes.get(comp[id], 0) + 1
	if sizes.size() > 1:
		var small: Array = []
		for id in comp.keys():
			if sizes[comp[id]] < 50 and small.size() < 12:
				small.append([comp[id], cb.graph.pos(id)])
		print("PROBE component sizes ", sizes, " sample small: ", small)
	var jobs := 0
	var types := {}
	for p in cb.places:
		types[(p as Place).type] = types.get((p as Place).type, 0) + 1
		for jj in (p as Place).jobs:
			jobs += int(jj.slots)
	print("PROBE job slots %d, place types %s" % [jobs, str(types)])
	var worst := 0.0
	var worst_key := Vector2i.ZERO
	var t1 := Time.get_ticks_msec()
	for key in CityMap.all_cells():
		var a := Time.get_ticks_usec()
		cb.load_cell(key)
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		if ms > worst:
			worst = ms
			worst_key = key
	print("PROBE loaded all %d cells in %d ms (worst %.1f ms at %s %s)" % [cb.stats.loaded, Time.get_ticks_msec() - t1, worst, str(worst_key), CityMap.cell_type(worst_key.x, worst_key.y)])
	var seats := 0
	var bound := 0
	for p in cb.places:
		for s in (p as Place).spots:
			if (s as Dictionary).has("seat"):
				seats += 1
				if s.seat != null:
					bound += 1
	print("PROBE seat spots %d bound %d" % [seats, bound])
	var bad_nodes := 0
	for p in cb.places:
		if not cb.graph.astar.has_point((p as Place).entry_node):
			bad_nodes += 1
		for s in (p as Place).spots:
			if (s as Dictionary).has("node") and not cb.graph.astar.has_point(int(s.node)):
				bad_nodes += 1
	print("PROBE dangling node ids after streaming: %d" % bad_nodes)
	for key in CityMap.all_cells():
		cb.unload_cell(key)
	await get_tree().process_frame
	print("PROBE unloaded, loaded=%d nodes=%d" % [cb.stats.loaded, get_tree().get_node_count()])
	get_tree().quit()
