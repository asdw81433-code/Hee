class_name CityMap
extends RefCounted
## WESTBRIDGE world layout.
##
## The world is a grid of 58 m cells (48 m lot + 10 m road). The original 5x4 town
## (cells gi 0..4, gj 0..3) is preserved unchanged in the middle; the rest of the
## world is described by district rectangles around it:
##
##   north  : Fort Calder military base (NW), Hillside (elevated), summit park,
##            Neon Row entertainment district (NE, across the river)
##   middle : Route 9 highway corridor (gj = -1) crossing the whole map,
##            Countryside (W), Pine Grove suburbs, the original town, the Calder river,
##            Downtown CBD (E)
##   south  : Harbor Industrial + container port (SW), Westbridge Beach town,
##            the beach itself and the sea.
##
## Coordinates: cell (gi, gj) centre = ((gi-2)*58, 0, (gj-1.5)*58). North = -Z.

const BLOCK := 48.0
const ROAD := 10.0
const PITCH := BLOCK + ROAD
const SIDEWALK := 3.0
const CURB_H := 0.15
const COLS := 5          ## original town (kept for compatibility)
const ROWS := 4
const GI_MIN := -7
const GI_MAX := 9
const GJ_MIN := -5
const GJ_MAX := 6
const SEA_LEVEL := -0.8
const RIVER_LEVEL := -1.8
const RIVER_X := 174.0
const HIGHWAY_Z := -145.0
const HIGHWAY_W := 20.0
## Horizontal grid lines (index b) where a bridge crosses the river.
const BRIDGE_LINES := [-2, 1, 3, 5]
## Vertical grid lines (index a) where streets cross Route 9 at a junction.
const HIGHWAY_JUNCTIONS := [-5, -3, 0, 2, 4, 7, 9]

## [col][row] block types of the original town
const LAYOUT := [
	["houses", "houses", "apartments", "houses"],
	["houses", "park", "houses", "sports_park"],
	["market", "diner_block", "town_plaza", "warehouse"],
	["shops", "quickstop", "shops2", "garage_yard"],
	["offices", "bank_hotel", "parking", "offices2"],
]

const DISTRICTS := ["Maple Heights", "Maple Heights", "Old Town", "Old Town", "Downtown"]
const STREETS_NS := ["Cedar Ln", "Birch Ave", "Main St", "Mill Rd", "Harbor Rd", "Lake Dr"]
const STREETS_EW := ["Pine St", "Oak St", "Elm St", "Market St", "Quarry Rd"]
const _NS_POOL := ["Ridge Rd", "Fort Rd", "Sawmill Ln", "Hollow Rd", "Linden Ave", "Aspen Way", "Willow Ln",
	"River Rd", "Grand Ave", "Bay St", "Lighthouse Rd", "Canal St", "Summit Rd"]
const _EW_POOL := ["Vista Dr", "Crest Rd", "Overlook Rd", "Hillcrest Ave", "Route 9 South", "Sycamore St",
	"Shore Dr", "Beach Blvd", "Dock St", "Pier Rd", "Highland Ave", "Neon Blvd"]

## Colour of each district on the map.
const DISTRICT_COLORS := {
	"Maple Heights": Color(0.55, 0.75, 0.45), "Old Town": Color(0.85, 0.62, 0.42), "Downtown": Color(0.45, 0.6, 0.85),
	"Pine Grove": Color(0.6, 0.8, 0.55), "Hillside": Color(0.5, 0.65, 0.4), "Neon Row": Color(0.85, 0.4, 0.75),
	"Westbridge Beach": Color(0.95, 0.85, 0.55), "Harbor Industrial": Color(0.6, 0.6, 0.62), "Fort Calder": Color(0.45, 0.5, 0.35),
	"Countryside": Color(0.7, 0.75, 0.4), "Route 9": Color(0.4, 0.4, 0.42), "Calder River": Color(0.3, 0.5, 0.75), "Sea": Color(0.25, 0.45, 0.7),
}

static var _types: Dictionary = {}


# ------------------------------------------------------------------ cells
static func _init_types() -> void:
	if not _types.is_empty():
		return
	var t := _types
	# Original town
	for i in COLS:
		for j in ROWS:
			t[Vector2i(i, j)] = LAYOUT[i][j]
	# Pine Grove suburbs (gi -4..-1, gj 0..3)
	var sub := [["sub_houses", "sub_houses", "sub_park", "sub_houses"],
		["sub_houses", "school", "sub_houses", "church"],
		["supermarket", "sub_houses", "sub_houses", "water_tower"],
		["sub_houses", "community_pool", "sub_houses", "sub_houses"]]
	for k in 4:
		for j in 4:
			t[Vector2i(-4 + k, j)] = sub[k][j]
	# Hillside (gi -1..4, gj -4..-2) + summit (gj -5)
	var hill := {-2: ["villas", "villas", "hill_cafe", "villas", "villas", "villas"],
		-3: ["villas", "mansion", "villas", "villas", "vineyard", "villas"],
		-4: ["mansion", "villas", "villas", "observatory", "villas", "mansion"],
		-5: ["hill_park", "hill_park", "lookout", "hill_park", "hill_park", "radio_tower"]}
	for j in hill.keys():
		for k in 6:
			t[Vector2i(-1 + k, j)] = hill[j][k]
	# Neon Row entertainment (gi 6..8, gj -4..-2)
	var ent := {-2: ["nightlife", "cinema", "nightlife"], -3: ["arcade_bowling", "arena", "nightlife"], -4: ["concert_hall", "nightlife", "fun_park"]}
	for j in ent.keys():
		for k in 3:
			t[Vector2i(6 + k, j)] = ent[j][k]
	# Downtown CBD (gi 6..8, gj 0..3)
	var dt := [["towers", "police_hq", "towers", "city_mall"],
		["central_plaza", "towers_tall", "central_station", "towers"],
		["towers", "hospital", "towers", "res_towers"]]
	for k in 3:
		for j in 4:
			t[Vector2i(6 + k, j)] = dt[k][j]
	# Beach town (gj 4) and beach (gj 5)
	var beach_town := {0: "beach_houses", 1: "beach_shops", 2: "pier_plaza", 3: "beach_shops", 4: "beach_houses", 6: "resort", 7: "marina", 8: "lighthouse_park", 9: "beach_houses"}
	for gi in beach_town.keys():
		t[Vector2i(gi, 4)] = beach_town[gi]
	for gi in [0, 1, 2, 3, 4, 6, 7, 8, 9, -7, -6, -5]:
		t[Vector2i(gi, 5)] = "beach"
	t[Vector2i(2, 5)] = "beach_pier"
	t[Vector2i(7, 5)] = "beach_marina"
	# Harbor Industrial (gi -4..-1, gj 4..5)
	var ind := {4: ["factory", "warehouses", "rail_yard", "scrapyard"], 5: ["fuel_depot", "container_port", "container_port", "fish_docks"]}
	for j in ind.keys():
		for k in 4:
			t[Vector2i(-4 + k, j)] = ind[j][k]
	# Fort Calder military base (gi -7..-4, gj -5..-3)
	var mil := {-5: ["mil_runway", "mil_runway", "mil_runway", "mil_runway"],
		-4: ["mil_hangar", "mil_hangar", "mil_tower", "mil_motorpool"],
		-3: ["mil_barracks", "mil_hq", "mil_training", "mil_gate"]}
	for j in mil.keys():
		for k in 4:
			t[Vector2i(-7 + k, j)] = mil[j][k]
	# Countryside
	var rural := {
		Vector2i(-7, 0): "forest", Vector2i(-6, 0): "rural_gas", Vector2i(-5, 0): "farm",
		Vector2i(-7, 1): "field", Vector2i(-6, 1): "farm", Vector2i(-5, 1): "field",
		Vector2i(-7, 2): "orchard", Vector2i(-6, 2): "windmill_farm", Vector2i(-5, 2): "field",
		Vector2i(-7, 3): "forest", Vector2i(-6, 3): "campground", Vector2i(-5, 3): "farm",
		Vector2i(-7, 4): "forest", Vector2i(-6, 4): "field", Vector2i(-5, 4): "forest",
		Vector2i(-7, -2): "field", Vector2i(-6, -2): "farm", Vector2i(-5, -2): "field", Vector2i(-4, -2): "field",
		Vector2i(-3, -5): "forest", Vector2i(-2, -5): "forest", Vector2i(-3, -4): "orchard", Vector2i(-2, -4): "farm",
		Vector2i(-3, -3): "field", Vector2i(-2, -3): "field", Vector2i(-3, -2): "farm", Vector2i(-2, -2): "field",
		Vector2i(9, -5): "forest", Vector2i(9, -4): "forest", Vector2i(9, -3): "forest", Vector2i(9, -2): "forest",
		Vector2i(9, 0): "forest", Vector2i(9, 1): "field", Vector2i(9, 2): "farm", Vector2i(9, 3): "forest",
		Vector2i(6, -5): "forest", Vector2i(7, -5): "forest", Vector2i(8, -5): "forest",
	}
	for k in rural.keys():
		t[k] = rural[k]
	# Calder river + lake, Route 9 highway corridor
	for j in range(GJ_MIN, 6):
		t[Vector2i(5, j)] = "river"
	t[Vector2i(5, -5)] = "lake"
	for gi in range(GI_MIN, GI_MAX + 1):
		t[Vector2i(gi, -1)] = "highway"


static func cell_type(gi: int, gj: int) -> String:
	_init_types()
	if gj > GJ_MAX - 1 or gj >= 6:
		return "sea"
	if gi < GI_MIN or gi > GI_MAX or gj < GJ_MIN:
		return "outside"
	return _types.get(Vector2i(gi, gj), "forest")


## block = raised urban block with sidewalks; rural = open land with paths;
## water / corridor / beach / outside handled specially.
static func cell_kind(gi: int, gj: int) -> String:
	var t := cell_type(gi, gj)
	match t:
		"sea", "river", "lake":
			return "water"
		"highway":
			return "corridor"
		"beach", "beach_pier", "beach_marina":
			return "beach"
		"outside":
			return "outside"
		"forest", "field", "farm", "orchard", "windmill_farm", "campground", "rural_gas", "hill_park", "lookout", "radio_tower":
			return "rural"
	return "block"


## Rural cells that people travel to (they get dirt roads).
static func is_rural_destination(gi: int, gj: int) -> bool:
	return cell_type(gi, gj) in ["farm", "windmill_farm", "campground", "rural_gas", "lookout", "radio_tower", "orchard"]


static func cell_district(gi: int, gj: int) -> String:
	var t := cell_type(gi, gj)
	if gi >= 0 and gi <= 4 and gj >= 0 and gj <= 3:
		if t in ["warehouse", "garage_yard"]:
			return "Harbor Industrial"
		return DISTRICTS[gi]
	if t == "highway":
		return "Route 9"
	if t in ["river", "lake"]:
		return "Calder River"
	if t == "sea":
		return "Sea"
	if t.begins_with("mil_"):
		return "Fort Calder"
	if gj >= 4:
		if gi >= -4 and gi <= -1:
			return "Harbor Industrial"
		return "Westbridge Beach" if gi >= 0 else "Countryside"
	if gi >= -4 and gi <= -1 and gj >= 0:
		return "Pine Grove"
	if gi >= -1 and gi <= 4 and gj <= -2:
		return "Hillside"
	if gi >= 6 and gi <= 8 and gj <= -2 and gj >= -4:
		return "Neon Row"
	if gi >= 6 and gi <= 8 and gj >= 0:
		return "Downtown"
	return "Countryside"


## Street name of vertical grid line a (x = (a-2.5)*58) / horizontal line b.
static func street_ns(a: int) -> String:
	if a >= 0 and a < STREETS_NS.size():
		return STREETS_NS[a]
	return _NS_POOL[posmod(a + 7, _NS_POOL.size())]


static func street_ew(b: int) -> String:
	if b >= 0 and b < STREETS_EW.size():
		return STREETS_EW[b]
	return _EW_POOL[posmod(b + 5, _EW_POOL.size())]


## Every cell of the playable grid (row-major, north to south).
static func all_cells() -> Array:
	var out: Array = []
	for gj in range(GJ_MIN, GJ_MAX + 1):
		for gi in range(GI_MIN, GI_MAX + 1):
			out.append(Vector2i(gi, gj))
	return out


static func is_original_town(gi: int, gj: int) -> bool:
	return gi >= 0 and gi < COLS and gj >= 0 and gj < ROWS


## Deterministic per-cell seed so the data pass and the streamed visual pass of a
## cell replay exactly the same random sequence.
static func cell_seed(world_seed: int, gi: int, gj: int) -> int:
	return hash([world_seed, gi, gj])


## Number of urban blocks (raised blocks with sidewalks) in the world.
static func urban_block_count() -> int:
	var n := 0
	for c in all_cells():
		if cell_kind(c.x, c.y) == "block":
			n += 1
	return n


## All district names that contain at least one cell.
static func district_names() -> Array:
	var d := {}
	for c in all_cells():
		var k := cell_kind(c.x, c.y)
		if k == "water" or k == "outside":
			continue
		d[cell_district(c.x, c.y)] = true
	return d.keys()


static func block_center(i: int, j: int) -> Vector3:
	return Vector3((i - (COLS - 1) * 0.5) * PITCH, 0.0, (j - (ROWS - 1) * 0.5) * PITCH)


## Cell centre including terrain height.
static func cell_center(gi: int, gj: int) -> Vector3:
	var p := block_center(gi, gj)
	p.y = height_at(p.x, p.z)
	return p


static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(round(pos.x / PITCH + (COLS - 1) * 0.5)), int(round(pos.z / PITCH + (ROWS - 1) * 0.5)))


static func block_type(i: int, j: int) -> String:
	return cell_type(i, j)


static func district_at(pos: Vector3) -> String:
	var c := cell_of(pos)
	if absf(pos.z - HIGHWAY_Z) < HIGHWAY_W * 0.5 + 1.0:
		return "Route 9"
	return cell_district(c.x, c.y)


## Intersection (a, b) world position (flat).
static func intersection(a: int, b: int) -> Vector3:
	return Vector3((a - 2.5) * PITCH, 0.0, (b - 2.0) * PITCH)


## Half extent of the original town incl. the outer ring roads (compatibility).
static func half_extent() -> Vector2:
	return Vector2(COLS * PITCH * 0.5 + ROAD * 0.5, ROWS * PITCH * 0.5 + ROAD * 0.5)


## World bounds (x0, z0, x1, z1) of the whole grid.
static func world_rect() -> Rect2:
	var a := intersection(GI_MIN, GJ_MIN)
	var b := intersection(GI_MAX + 1, GJ_MAX + 1)
	return Rect2(a.x, a.z, b.x - a.x, b.z - a.z)


static func road_xs() -> Array:
	var out: Array = []
	for i in COLS + 1:
		out.append((i - COLS * 0.5) * PITCH)
	return out


static func road_zs() -> Array:
	var out: Array = []
	for j in ROWS + 1:
		out.append((j - ROWS * 0.5) * PITCH)
	return out


# ------------------------------------------------------------------ roads
## Road kind on the vertical grid edge between cells (a-1, b) and (a, b).
## "" = no road, "street", "dirt", "crossing" (N-S road through the highway corridor)
static func vedge(a: int, b: int) -> String:
	var w := cell_kind(a - 1, b)
	var e := cell_kind(a, b)
	if w == "corridor" and e == "corridor":
		# Route 9 junctions: only on chosen lines where streets continue on both sides.
		if a in HIGHWAY_JUNCTIONS and vedge(a, b - 1) != "" and vedge(a, b + 1) != "":
			return "crossing"
		return ""
	if _is_sea(a - 1, b) or _is_sea(a, b):
		return ""
	if w == "block" or e == "block":
		if w == "water" and e == "water":
			return ""
		return "street"
	if (w == "rural" and is_rural_destination(a - 1, b)) or (e == "rural" and is_rural_destination(a, b)):
		if w != "water" and e != "water" and w != "outside" and e != "outside" and w != "beach" and e != "beach":
			return "dirt"
	return ""


static func _is_sea(gi: int, gj: int) -> bool:
	return cell_type(gi, gj) == "sea"


## Road kind on the horizontal grid edge between cells (a, b-1) and (a, b).
static func hedge(a: int, b: int) -> String:
	var n := cell_kind(a, b - 1)
	var s := cell_kind(a, b)
	if n == "water" and s == "water":
		return "bridge" if a == 5 and b in BRIDGE_LINES else ""
	if _is_sea(a, b - 1) or _is_sea(a, b):
		return ""
	if n == "block" or s == "block":
		if n == "water" and s == "water":
			return ""
		return "street"
	if n == "corridor" or s == "corridor":
		var other_gj := b - 1 if s == "corridor" else b
		if cell_kind(a, other_gj) == "rural" and is_rural_destination(a, other_gj):
			return "dirt"
		return ""
	if (n == "rural" and is_rural_destination(a, b - 1)) or (s == "rural" and is_rural_destination(a, b)):
		if n != "water" and s != "water" and n != "outside" and s != "outside" and n != "beach" and s != "beach":
			return "dirt"
	return ""


static func road_width(kind: String) -> float:
	return 6.0 if kind == "dirt" else ROAD


# ------------------------------------------------------------------ terrain
## Ground height (metres) anywhere in the world. Smooth, analytic, cheap.
static func height_at(x: float, z: float) -> float:
	var h := 0.0
	# Hills north of Route 9, west of the river.
	var hill_n := smoothstep(-172.0, -355.0, z)
	var hill_x := smoothstep(-300.0, -205.0, x) * (1.0 - smoothstep(118.0, 150.0, x))
	h += hill_n * 20.0 * hill_x
	# Summit ridge with a rounded top.
	var summit := smoothstep(-352.0, -395.0, z) * hill_x
	h += summit * (6.0 + 3.0 * sin(x * 0.021 + 0.6))
	# North-east forest hills behind Neon Row.
	h += smoothstep(-352.0, -420.0, z) * smoothstep(200.0, 260.0, x) * 8.0
	# Calder river valley (with the lake at its source).
	var dx := absf(x - RIVER_X)
	if z < 236.0:
		var valley := 1.0 - smoothstep(19.0, 20.5, dx)
		h = lerpf(h, -3.8, valley)
	var lake := Vector2(x - RIVER_X, z + 377.0).length()
	h = lerpf(h, -3.8, 1.0 - smoothstep(24.0, 30.0, lake))
	# Coast: sand slopes into the sea south of the coastal road. The Harbor Industrial
	# quays (x -377..-145) stay flat; the sea starts right at the quay wall.
	var coast := smoothstep(178.0, 234.0, z) * 1.7 + smoothstep(232.0, 320.0, z) * 5.5
	var quay := smoothstep(-392.0, -377.0, x) * (1.0 - smoothstep(-145.0, -130.0, x)) * (1.0 - smoothstep(232.0, 236.0, z))
	h -= coast * (1.0 - quay)
	return h


## Height used for road surfaces: bridges stay level over the river.
static func road_height_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	if absf(x - RIVER_X) < 26.0 and z < 236.0:
		return maxf(h, 0.0)
	return h


## Walkable surface height of a lot/sidewalk at (x, z): terrain + curb.
static func ground_y(x: float, z: float) -> float:
	return height_at(x, z) + CURB_H


static func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < (RIVER_LEVEL if z < 180.0 else SEA_LEVEL) - 0.2


static func water_level_at(x: float, z: float) -> float:
	if z > 178.0:
		return SEA_LEVEL
	if absf(x - RIVER_X) < 21.0 or Vector2(x - RIVER_X, z + 377.0).length() < 30.0:
		return RIVER_LEVEL
	return -100.0
