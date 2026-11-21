class_name CharacterAnimator
extends AnimationTree
## Layered AnimationTree for every human:
##
##   [state: Transition] -- loco (BlendSpace1D idle/walk/jog/run/sprint + injured blend + TimeScale)
##                       -- crouch, jump, fall, land, sit, lie, getup_*, stumble, stop_run ...
##   -> full_shot  (OneShot, whole body actions: dodge, kick, pick up...)
##   -> hold_blend (Blend2 filtered to upper body: phone, block, carry... loops)
##   -> upper_shot (OneShot filtered to upper body: punch, wave, talk, hit flinches...)
##
## All transitions cross-fade; nothing switches instantly.

const STATES := ["loco", "crouch", "jump", "fall", "land", "land_hard", "sit", "sit_down", "stand_up",
	"lie", "sleep", "getup_back", "getup_front", "stumble", "stop_run"]
const FULL_ACTIONS := ["dodge_l", "dodge_r", "dodge_back", "kick", "shocked", "pick_up"]
const UPPER_ACTIONS := ["punch_r", "punch_l", "wave", "talk", "talk2", "eat", "drink", "laugh", "angry",
	"open_door", "point", "cheer", "flinch", "hit_front", "hit_back", "hit_left", "hit_right", "hit_head"]
const HOLDS := ["none", "hold_block", "hold_phone", "hold_arms_crossed", "hold_pockets", "hold_carry", "hold_umbrella", "hold_work"]
## Non-looping states that return to locomotion when finished.
const AUTO_RETURN := {"jump": "fall", "land": "loco", "land_hard": "loco", "stand_up": "loco", "sit_down": "sit",
	"stumble": "loco", "stop_run": "loco", "getup_back": "loco", "getup_front": "loco"}

static var _shared_root: AnimationNodeBlendTree

var current_state: String = "loco"
var current_hold: String = "none"
var last_action: String = ""
var _state_time: float = 0.0
var _hold_amount: float = 0.0
var _hold_target: float = 0.0
var _speed: float = 0.0
var _gait: float = 0.0
var _injury: float = 0.0
var cadence_scale: float = 1.0   ## emotion/fatigue tweak of stride frequency
var stride_scale: float = 1.0    ## body proportion: shorter legs -> quicker steps (set by CharacterModel)


func setup() -> void:
	add_animation_library("", AnimLibraryBuilder.get_library())
	tree_root = _get_shared_root()
	root_node = NodePath("..")
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	active = true
	set("parameters/state/transition_request", "loco")
	set("parameters/hold_sel/transition_request", "none")
	set("parameters/hold_blend/blend_amount", 0.0)


static func _get_shared_root() -> AnimationNodeBlendTree:
	if _shared_root != null:
		return _shared_root
	var bt := AnimationNodeBlendTree.new()
	# --- locomotion ---
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 4.0
	bs.sync = true
	var i := 0.0
	for n in ["idle", "walk", "jog", "run", "sprint"]:
		var an := AnimationNodeAnimation.new()
		an.animation = n
		_add_point(bs, an, i, n)
		i += 1.0
	bt.add_node("loco_bs", bs, Vector2(0, 0))
	var inj := AnimationNodeBlendSpace1D.new()
	inj.min_space = 0.0
	inj.max_space = 1.0
	inj.sync = true
	for pair in [["injured_idle", 0.0], ["injured_walk", 1.0]]:
		var an2 := AnimationNodeAnimation.new()
		an2.animation = pair[0]
		_add_point(inj, an2, pair[1], pair[0])
	bt.add_node("inj_bs", inj, Vector2(0, 200))
	var inj_blend := AnimationNodeBlend2.new()
	bt.add_node("inj", inj_blend, Vector2(250, 100))
	bt.connect_node("inj", 0, "loco_bs")
	bt.connect_node("inj", 1, "inj_bs")
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("loco_ts", ts, Vector2(450, 100))
	bt.connect_node("loco_ts", 0, "inj")
	var cr := AnimationNodeBlendSpace1D.new()
	cr.min_space = 0.0
	cr.max_space = 1.0
	cr.sync = true
	for pair in [["crouch_idle", 0.0], ["crouch_walk", 1.0]]:
		var an3 := AnimationNodeAnimation.new()
		an3.animation = pair[0]
		_add_point(cr, an3, pair[1], pair[0])
	bt.add_node("crouch_bs", cr, Vector2(250, 300))
	# --- state selector ---
	var st := AnimationNodeTransition.new()
	st.xfade_time = 0.22
	bt.add_node("state", st, Vector2(700, 100))
	for idx in STATES.size():
		var sname: String = STATES[idx]
		st.add_input(sname)
		match sname:
			"loco":
				bt.connect_node("state", idx, "loco_ts")
			"crouch":
				bt.connect_node("state", idx, "crouch_bs")
			_:
				var a := AnimationNodeAnimation.new()
				a.animation = sname
				var node_name := "st_" + sname
				bt.add_node(node_name, a, Vector2(450, 300 + idx * 60))
				bt.connect_node("state", idx, node_name)
		st.set_input_reset(idx, sname != "loco" and sname != "crouch")
	# --- full body one-shot ---
	var full_sel := _make_selector(bt, "full_sel", FULL_ACTIONS, Vector2(700, 600))
	var full_shot := AnimationNodeOneShot.new()
	full_shot.fadein_time = 0.12
	full_shot.fadeout_time = 0.2
	bt.add_node("full_shot", full_shot, Vector2(950, 100))
	bt.connect_node("full_shot", 0, "state")
	bt.connect_node("full_shot", 1, full_sel)
	# --- upper body holds ---
	var hold_sel := _make_selector(bt, "hold_sel", HOLDS, Vector2(950, 600))
	var hold_blend := AnimationNodeBlend2.new()
	_apply_upper_filter(hold_blend)
	bt.add_node("hold_blend", hold_blend, Vector2(1200, 100))
	bt.connect_node("hold_blend", 0, "full_shot")
	bt.connect_node("hold_blend", 1, hold_sel)
	# --- upper body one-shot ---
	var upper_sel := _make_selector(bt, "upper_sel", UPPER_ACTIONS, Vector2(1200, 600))
	var upper_shot := AnimationNodeOneShot.new()
	upper_shot.fadein_time = 0.1
	upper_shot.fadeout_time = 0.22
	_apply_upper_filter(upper_shot)
	bt.add_node("upper_shot", upper_shot, Vector2(1450, 100))
	bt.connect_node("upper_shot", 0, "hold_blend")
	bt.connect_node("upper_shot", 1, upper_sel)
	bt.connect_node("output", 0, "upper_shot")
	_shared_root = bt
	return bt


## Godot 4.7 names blend points; older 4.x versions take only (node, pos).
static func _add_point(space: AnimationNodeBlendSpace1D, node: AnimationRootNode, pos: float, point_name: String) -> void:
	if Engine.get_version_info().minor >= 7:
		space.call("add_blend_point", node, pos, -1, point_name)
	else:
		space.call("add_blend_point", node, pos)


static func _make_selector(bt: AnimationNodeBlendTree, sel_name: String, clips: Array, pos: Vector2) -> String:
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.15
	bt.add_node(sel_name, tr, pos)
	for idx in clips.size():
		var clip: String = clips[idx]
		tr.add_input(clip)
		tr.set_input_reset(idx, true)
		var node_name := sel_name + "_" + clip
		var a := AnimationNodeAnimation.new()
		a.animation = "idle" if clip == "none" else clip
		bt.add_node(node_name, a, pos + Vector2(-250, idx * 50))
		bt.connect_node(sel_name, idx, node_name)
	return sel_name


static func _apply_upper_filter(node: AnimationNode) -> void:
	node.filter_enabled = true
	for b in HumanoidDef.UPPER_BODY:
		node.set_filter_path(NodePath("Skeleton:" + b), true)


# ------------------------------------------------------------------ control API
## speed in m/s on the ground plane. injury 0..1 blends into limping.
func set_locomotion(speed: float, injury: float = 0.0) -> void:
	_speed = speed
	_injury = injury


func set_state(state_name: String) -> void:
	if state_name == current_state:
		return
	if not state_name in STATES:
		push_warning("CharacterAnimator: unknown state %s" % state_name)
		return
	current_state = state_name
	_state_time = 0.0
	set("parameters/state/transition_request", state_name)


func play_full(action: String) -> float:
	if not action in FULL_ACTIONS:
		return 0.0
	last_action = action
	set("parameters/full_sel/transition_request", action)
	set("parameters/full_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return float(AnimLibraryBuilder.clip_lengths.get(action, 0.5))


func play_upper(action: String) -> float:
	if not action in UPPER_ACTIONS:
		return 0.0
	last_action = action
	set("parameters/upper_sel/transition_request", action)
	set("parameters/upper_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return float(AnimLibraryBuilder.clip_lengths.get(action, 0.5))


func is_upper_busy() -> bool:
	return bool(get("parameters/upper_shot/active"))


func set_hold(hold: String) -> void:
	if not hold in HOLDS:
		hold = "none"
	if hold == current_hold:
		return
	if hold != "none":
		set("parameters/hold_sel/transition_request", hold)
		current_hold = hold
		_hold_target = 1.0
	else:
		_hold_target = 0.0
		current_hold = "none"


func state_length(state_name: String) -> float:
	return float(AnimLibraryBuilder.clip_lengths.get(state_name, 0.5))


## Maps ground speed to gait index (0 idle .. 4 sprint) and stride frequency.
static func gait_from_speed(speed: float) -> Vector2:
	var pts := [Vector3(0.0, 0.0, 0.45), Vector3(1.4, 1.0, 0.95), Vector3(3.0, 2.0, 1.32),
		Vector3(4.8, 3.0, 1.56), Vector3(6.8, 4.0, 1.8)]
	if speed <= 0.0:
		return Vector2(0.0, 0.45)
	for k in range(1, pts.size()):
		var a: Vector3 = pts[k - 1]
		var b: Vector3 = pts[k]
		if speed <= b.x:
			var t := (speed - a.x) / (b.x - a.x)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	var last: Vector3 = pts[pts.size() - 1]
	return Vector2(last.y, last.z * speed / last.x)


func _process(delta: float) -> void:
	_state_time += delta
	var target := gait_from_speed(_speed)
	_gait = lerpf(_gait, target.x, 1.0 - exp(-delta * 10.0))
	set("parameters/loco_bs/blend_position", _gait)
	set("parameters/inj_bs/blend_position", clampf(_speed / 1.2, 0.0, 1.0))
	set("parameters/inj/blend_amount", _injury)
	set("parameters/loco_ts/scale", target.y * cadence_scale * stride_scale * lerpf(1.0, 0.85, _injury))
	set("parameters/crouch_bs/blend_position", clampf(_speed / 1.5, 0.0, 1.0))
	set("parameters/crouch_bs/blend_position", clampf(_speed / 1.5, 0.0, 1.0))
	_hold_amount = move_toward(_hold_amount, _hold_target, delta * 4.0)
	set("parameters/hold_blend/blend_amount", _hold_amount)
	if AUTO_RETURN.has(current_state) and _state_time >= state_length(current_state):
		set_state(AUTO_RETURN[current_state])
