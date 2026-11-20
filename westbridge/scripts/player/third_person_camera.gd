class_name ThirdPersonCamera
extends Node3D
## Over-the-shoulder third person camera with collision (SpringArm3D), smoothing,
## touch/mouse look, auto-recentre behind the player, sprint FOV and ragdoll follow.

@export var target_path: NodePath
@export var pivot_height: float = 1.55
@export var shoulder_offset: float = 0.35
@export var min_pitch: float = -65.0
@export var max_pitch: float = 40.0

var target: HumanoidBody
var yaw: float = 0.0
var pitch: float = -12.0
var spring: SpringArm3D
var camera: Camera3D
var _idle_look_time: float = 0.0
var _fov_base: float = 68.0
var _follow_pos: Vector3


func _ready() -> void:
	top_level = true
	# Updated every rendered frame, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spring = SpringArm3D.new()
	spring.margin = 0.2
	spring.collision_mask = 1
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = _fov_base
	camera.far = float(Settings.get_value("view_distance", 220.0)) + 60.0
	camera.near = 0.08
	spring.add_child(camera)
	camera.current = true
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as HumanoidBody
	EventBus.settings_applied.connect(_on_settings)
	_on_settings()
	if target:
		_follow_pos = target.global_position
		yaw = target.rotation.y


func _on_settings() -> void:
	spring.spring_length = float(Settings.get_value("cam_distance", 4.2))
	if camera:
		camera.far = float(Settings.get_value("view_distance", 220.0)) + 60.0


func set_target(t: HumanoidBody) -> void:
	target = t
	_follow_pos = t.global_position
	yaw = t.rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		PlayerInput.mouse_look += event.relative
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		spring.spring_length = maxf(1.6, spring.spring_length - 0.3)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		spring.spring_length = minf(8.0, spring.spring_length + 0.3)


func _process(delta: float) -> void:
	if target == null:
		return
	var sens := float(Settings.get_value("cam_sensitivity", 1.0))
	var look := PlayerInput.look
	var inv := -1.0 if bool(Settings.get_value("cam_invert_y", false)) else 1.0
	yaw -= look.x * 0.0042 * sens
	pitch = clampf(pitch - look.y * 0.0042 * sens * 57.3 * inv, min_pitch, max_pitch)
	# Auto recentre behind a moving player when the user isn't steering the camera.
	if look.length() > 0.5:
		_idle_look_time = 0.0
	else:
		_idle_look_time += delta
	if _idle_look_time > 2.0 and target.ground_speed > 2.0:
		var behind := target.rotation.y
		yaw = lerp_angle(yaw, behind, 1.0 - exp(-delta * 0.9))
	var focus := target.global_position
	if target.is_down() and target.phys.ragdoll:
		focus = target.phys.ragdoll.hips().global_position - Vector3(0, 0.9, 0)
	_follow_pos = _follow_pos.lerp(focus, 1.0 - exp(-delta * 14.0))
	global_position = _follow_pos + Vector3(0, pivot_height, 0)
	rotation = Vector3(deg_to_rad(pitch), yaw, 0)
	spring.position = Vector3(shoulder_offset, 0, 0)
	var sprinting := target.ground_speed > 5.5
	camera.fov = lerpf(camera.fov, _fov_base + (8.0 if sprinting else 0.0), 1.0 - exp(-delta * 3.0))


## Horizontal camera basis used to make movement camera-relative.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
