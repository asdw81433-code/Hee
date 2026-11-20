class_name Place
extends RefCounted
## A location NPCs (and the player) can use: home, shop, workplace, park bench...

var id: int = -1
var type: String = ""            ## home, apartment, shop, cafe, diner, store, office, park, bench, market, ...
var name: String = ""
var district: String = ""
var entry_pos: Vector3           ## door / entrance on the walkable network
var entry_node: int = -1         ## PedGraph node id
var inside_pos: Vector3          ## where an NPC "is" when inside (abstract sim)
var spots: Array = []            ## [{pos: Vector3, yaw: float, kind: "seat"/"counter"/"stand", taken_by: -1}]
var open_hour: float = 0.0
var close_hour: float = 24.0
var tags: Array = []             ## food, coffee, groceries, work, leisure, social, sleep, shelter, nightlife, sports
var capacity: int = 8
var price_level: int = 1         ## 0 free .. 3 expensive
var enterable: bool = false      ## has a modeled interior
var jobs: Array = []             ## [{title, wage, start, end, slots}]
var residents: Array = []        ## NPC ids living here
var occupants: Dictionary = {}   ## npc id -> true (currently inside / using)
var interior_nodes: Array = []   ## PedGraph nodes inside the building


func is_open(hour: float) -> bool:
	if close_hour >= 24.0 and open_hour <= 0.0:
		return true
	if close_hour > open_hour:
		return hour >= open_hour and hour < close_hour
	return hour >= open_hour or hour < close_hour   # overnight


func has_tag(t: String) -> bool:
	return t in tags


func free_spot(kind: String = "") -> int:
	for i in spots.size():
		var s: Dictionary = spots[i]
		if int(s.get("taken_by", -1)) < 0 and (kind == "" or s.get("kind", "") == kind):
			return i
	return -1


func describe() -> String:
	return "%s (%s)" % [name, type]
