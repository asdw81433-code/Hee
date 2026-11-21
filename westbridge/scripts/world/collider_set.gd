class_name ColliderSet
extends RefCounted
## Collects static collision boxes for a chunk and turns them into one StaticBody3D.

var boxes: Array = []   ## [Transform3D, Vector3 size]
var enabled: bool = true


func add(xform: Transform3D, size: Vector3) -> void:
	if not enabled:
		return
	boxes.append([xform, size])


func add_box(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	if not enabled:
		return
	boxes.append([Transform3D(Basis(Vector3.UP, yaw), center), size])


func build(name: String, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = layer
	body.collision_mask = 0
	for b in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[1]
		cs.shape = sh
		cs.transform = b[0]
		body.add_child(cs)
	return body
