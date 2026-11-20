class_name Door
extends Interactable
## Hinged door with real collision. `auto` doors (shops) open for anyone nearby
## during opening hours; manual doors toggle on interact. Closed shops refuse entry.

@export var width: float = 1.1
@export var height: float = 2.1
@export var auto: bool = false
@export var color: Color = Color(0.42, 0.28, 0.18)
var place: Place = null
var is_open: bool = false
var _hinge: Node3D
var _body: StaticBody3D
var _angle: float = 0.0
var _check_timer: float = 0.0
var _close_timer: float = 0.0


func _ready() -> void:
	super._ready()
	interact_radius = 1.8
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.position = Vector3(width * 0.5, height * 0.5, 0)
	_hinge.add_child(_body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, height, 0.06)
	cs.shape = sh
	_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.06)
	mi.mesh = bm
	mi.material_override = Geo.material(color, 0.6)
	_body.add_child(mi)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	knob.mesh = sm
	knob.material_override = Geo.material(Color(0.85, 0.75, 0.4), 0.3)
	knob.position = Vector3(width * 0.36, -0.05, 0.06)
	_body.add_child(knob)


func _is_allowed() -> bool:
	if place == null:
		return true
	return place.is_open(GameTime.get_hour_float())


func get_prompt(_actor: Node) -> String:
	if not _is_allowed():
		return "Closed (opens %02d:00)" % int(place.open_hour)
	return "Close door" if is_open else "Open door"


func interact(actor: Node) -> void:
	if not _is_allowed():
		EventBus.toast.emit("%s is closed. Opens at %02d:00" % [place.name, int(place.open_hour)])
		return
	set_open(not is_open)
	if actor is HumanoidBody:
		(actor as HumanoidBody).model.animator.play_upper("open_door")


func set_open(v: bool) -> void:
	is_open = v
	_close_timer = 4.0


func _physics_process(delta: float) -> void:
	if auto or is_open:
		_check_timer -= delta
		if _check_timer <= 0.0:
			_check_timer = 0.25
			var someone := false
			if _is_allowed():
				for h in get_tree().get_nodes_in_group("humanoid"):
					if (h as Node3D).global_position.distance_squared_to(global_position) < 4.0:
						someone = true
						break
			if auto and someone:
				is_open = true
				_close_timer = 1.5
			elif someone:
				_close_timer = 4.0
	if is_open:
		_close_timer -= delta
		if _close_timer <= 0.0 and auto:
			is_open = false
	var target := -1.65 if is_open else 0.0
	_angle = move_toward(_angle, target, delta * 3.5)
	_hinge.rotation.y = _angle
