class_name ThrownObject
extends Node
## Attach to a RigidBody3D: when it hits a HumanoidBody it delivers an ImpactData
## computed from its real mass and velocity (reduced-mass collision model).

var body: RigidBody3D
var _cooldown: Dictionary = {}


func _ready() -> void:
	body = get_parent() as RigidBody3D
	body.body_entered.connect(_on_hit)


func _on_hit(other: Node) -> void:
	var h: HumanoidBody = null
	if other is HumanoidBody:
		h = other
	elif other is PhysicalBone3D:
		var n := other.get_parent()
		while n and not (n is HumanoidBody):
			n = n.get_parent()
		h = n as HumanoidBody
	if h == null:
		return
	var now := Time.get_ticks_msec()
	if _cooldown.get(h, 0) > now:
		return
	_cooldown[h] = now + 400
	var v := body.linear_velocity
	if v.length() < 1.5:
		return
	var info := ImpactData.from_object(body.global_position, v, body.mass, h.phys.mass, ImpactData.Source.OBJECT, self)
	h.receive_impact(info)
