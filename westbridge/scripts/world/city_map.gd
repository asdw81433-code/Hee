class_name CityMap
extends RefCounted
## WESTBRIDGE layout data: grid of blocks, districts, street names.
## Phase 1-2 builds the central part of the city (Maple Heights residential,
## Old Town, the edge of Downtown and a slice of the Industrial district).
## Later phases append more districts (Beach, Hillside, Entertainment) to this map.

const BLOCK := 48.0          ## block lot size incl. sidewalks
const ROAD := 10.0           ## road width
const PITCH := BLOCK + ROAD
const SIDEWALK := 3.0
const CURB_H := 0.15
const COLS := 5
const ROWS := 4

## [col][row] block types
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


static func block_center(i: int, j: int) -> Vector3:
	return Vector3((i - (COLS - 1) * 0.5) * PITCH, 0.0, (j - (ROWS - 1) * 0.5) * PITCH)


static func block_type(i: int, j: int) -> String:
	return LAYOUT[i][j]


static func district_at(pos: Vector3) -> String:
	var i := clampi(int(round(pos.x / PITCH + (COLS - 1) * 0.5)), 0, COLS - 1)
	var j := clampi(int(round(pos.z / PITCH + (ROWS - 1) * 0.5)), 0, ROWS - 1)
	if block_type(i, j) in ["warehouse", "garage_yard"]:
		return "Industrial"
	return DISTRICTS[i]


## Half extent of the whole city incl. the outer ring roads.
static func half_extent() -> Vector2:
	return Vector2(COLS * PITCH * 0.5 + ROAD * 0.5, ROWS * PITCH * 0.5 + ROAD * 0.5)


## x positions of north-south road centre lines (including the outer ring).
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
