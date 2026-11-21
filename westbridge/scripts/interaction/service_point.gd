class_name ServicePoint
extends Interactable
## The entrance of a place that offers something to the player: a shop counter,
## job openings, a bank / ATM, a hotel desk, your workplace's time clock.
## Spawned at the door of every such place when its cell streams in.

var place: Place
var world: Node
static var _ring_mesh: Mesh


static func wants(p: Place) -> bool:
	return not ItemDB.catalog_for(p).is_empty() or not p.jobs.is_empty() or Economy.has_bank(p) or p.type == "hotel"


func _ready() -> void:
	super()
	interact_radius = 3.2
	# A soft yellow ring on the ground marks where to stand (one shared mesh).
	if _ring_mesh == null:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.62
		tm.outer_radius = 0.72
		tm.rings = 24
		tm.ring_segments = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.82, 0.25, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.material = mat
		_ring_mesh = tm
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.position = Vector3(0, 0.05, 0)
	mi.scale = Vector3(1, 0.3, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 30.0
	add_child(mi)


func interact_position() -> Vector3:
	return place.entry_pos if place else global_position


func get_prompt(_actor: Node) -> String:
	if place == null:
		return ""
	var parts: Array = []
	var eco: Economy = world.economy if world else null
	if eco and not eco.job.is_empty() and int(eco.job.place) == place.id and eco.shift_state() == "open":
		return "Start shift at %s" % place.name
	if not ItemDB.catalog_for(place).is_empty():
		parts.append("shop")
	if not place.jobs.is_empty():
		parts.append("jobs")
	if Economy.has_bank(place):
		parts.append("ATM" if place.type != "bank" else "bank")
	if place.type == "hotel":
		parts.append("rooms")
	var closed := "" if place.is_open(GameTime.get_hour_float()) else " (closed)"
	return "%s%s - %s" % [place.name, closed, " / ".join(parts)]


func interact(_actor: Node) -> void:
	if world and world.has_method("open_place_menu"):
		world.open_place_menu(place)
