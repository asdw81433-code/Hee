class_name Geo
extends RefCounted
## Small helpers for building static level geometry in code (boxes with collision,
## vertex-colored batched meshes, simple materials).

static var _mat_cache: Dictionary = {}


static func material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_mat_cache[key] = m
	return m


## Static box with mesh + collision. Returns the StaticBody3D.
static func static_box(parent: Node, xform: Transform3D, size: Vector3, color: Color, friction: float = 1.0, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.transform = xform
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material(color)
	body.add_child(mi)
	if friction != 1.0:
		var pm := PhysicsMaterial.new()
		pm.friction = friction
		body.physics_material_override = pm
	parent.add_child(body)
	return body


static func rigid_box(parent: Node, pos: Vector3, size: Vector3, mass: float, color: Color) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 1 << 4
	rb.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
	rb.position = pos
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material(color)
	rb.add_child(mi)
	parent.add_child(rb)
	return rb


static func rigid_ball(parent: Node, pos: Vector3, radius: float, mass: float, color: Color) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.collision_layer = 1 << 4
	rb.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
	rb.position = pos
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = material(color, 0.5)
	rb.add_child(mi)
	parent.add_child(rb)
	return rb
