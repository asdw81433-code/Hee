class_name CharacterModel
extends Node3D
## Visual human: Skeleton3D + single skinned mesh + AnimationTree + procedural modifiers.
## Modifier order on the skeleton: ProceduralRig -> FaceRig -> (PhysicalBoneSimulator3D)
## The model faces +Z. Owners rotate it to match their gameplay forward.

signal rebuilt

var appearance: CharacterAppearance
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var animator: CharacterAnimator
var rig: ProceduralRig
var face: FaceRig
var detail_level: int = 0      ## 0 = full, 1 = reduced
var _meshes: Dictionary = {}   ## detail -> ArrayMesh
var hips_height: float = HumanoidDef.BASE_HIPS_HEIGHT
var total_height: float = 1.8
var uses_asset: bool = false   ## true when the Blender-made mesh library is used
var _asset_scale: float = 1.0

## Global switch (also exposed in Settings as "character_assets").
static var force_procedural: bool = false


static func asset_enabled() -> bool:
	if force_procedural:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var st := tree.root.get_node_or_null("Settings")
		if st and not bool(st.get_value("character_assets", true)):
			return false
	return CharacterAssetLibrary.available()


func build(p_appearance: CharacterAppearance, p_detail: int = 0) -> void:
	appearance = p_appearance
	detail_level = p_detail
	_clear()
	uses_asset = asset_enabled()
	if uses_asset:
		# Blender asset: uniform scale of the modelled body (shape keys do the rest).
		var dims := appearance.body_dims()
		_asset_scale = float(dims["height"])
		skeleton = CharacterAssetBuilder.build_skeleton(_asset_scale, appearance.eye_spacing)
		var rest: Dictionary = CharacterAssetLibrary.rest_positions
		hips_height = (rest["Hips"] as Vector3).y * _asset_scale
		total_height = ((rest["Head"] as Vector3).y + 0.34 * appearance.head_height) * _asset_scale
	else:
		var dims := appearance.body_dims()
		skeleton = HumanoidDef.build_skeleton(dims)
		var rests := HumanoidDef.global_rest_positions(dims)
		hips_height = rests["Hips"].y
		total_height = rests["Head"].y + 0.34 * appearance.head_height
	add_child(skeleton)
	skeleton.motion_scale = hips_height / HumanoidDef.BASE_HIPS_HEIGHT
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.material_override = CharacterMeshFactory.shared_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_meshes.clear()
	_apply_mesh()
	rig = ProceduralRig.new()
	rig.name = "ProceduralRig"
	skeleton.add_child(rig)
	rig.setup(skeleton)
	face = FaceRig.new()
	face.name = "FaceRig"
	skeleton.add_child(face)
	face.setup(skeleton, appearance.eye_shape)
	if animator == null:
		animator = CharacterAnimator.new()
		animator.name = "Animator"
		add_child(animator)
		animator.setup()
	else:
		animator.clear_caches()
	# Clips were authored for 0.94 m hips: shorter legs take quicker steps so feet don't slide.
	animator.stride_scale = clampf(HumanoidDef.BASE_HIPS_HEIGHT / maxf(hips_height, 0.3), 0.8, 1.35)
	rebuilt.emit()


func _clear() -> void:
	if skeleton:
		skeleton.queue_free()
		remove_child(skeleton)
	skeleton = null


func _apply_mesh() -> void:
	if not _meshes.has(detail_level):
		if uses_asset:
			_meshes[detail_level] = CharacterAssetBuilder.build(appearance, skeleton, _asset_scale, detail_level)
		else:
			var detail := 1.0 if detail_level == 0 else 0.55
			_meshes[detail_level] = CharacterMeshFactory.build(appearance, skeleton, detail)
	mesh_instance.mesh = _meshes[detail_level]


## Swaps mesh detail and enables/disables the expensive procedural parts.
func set_detail(level: int) -> void:
	if level == detail_level and mesh_instance.mesh != null:
		return
	detail_level = level
	_apply_mesh()
	rig.detail_full = level == 0
	face.detail_full = level == 0


func set_appearance(p_appearance: CharacterAppearance) -> void:
	build(p_appearance, detail_level)


func bone_world_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


func head_world_position() -> Vector3:
	return bone_world_position("Head") + global_basis.y * 0.15
