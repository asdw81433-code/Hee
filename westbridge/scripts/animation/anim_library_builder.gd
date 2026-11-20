class_name AnimLibraryBuilder
extends RefCounted
## Procedurally authored keyframe animations for the HumanoidDef skeleton.
## Poses are written as Euler degrees per bone (see HumanoidDef for axis conventions)
## and baked into real Animation resources with cubic-interpolated rotation tracks.
##
## IMPORTANT: these are hand-keyed procedural clips, not motion capture. The
## AnimationTree + procedural layers + physics make them feel alive, and any clip can be
## replaced by a real asset with the same name (SkeletonProfileHumanoid bone names).

const SHORT := {
	"H": "Hips", "S": "Spine", "C": "Chest", "UC": "UpperChest", "N": "Neck", "Hd": "Head",
	"LS": "LeftShoulder", "RS": "RightShoulder",
	"LUA": "LeftUpperArm", "RUA": "RightUpperArm", "LLA": "LeftLowerArm", "RLA": "RightLowerArm",
	"LH": "LeftHand", "RH": "RightHand",
	"LUL": "LeftUpperLeg", "RUL": "RightUpperLeg", "LLL": "LeftLowerLeg", "RLL": "RightLowerLeg",
	"LF": "LeftFoot", "RF": "RightFoot", "LT": "LeftToes", "RT": "RightToes",
}
const BODY_KEYS := ["H", "S", "C", "UC", "N", "Hd", "LS", "RS", "LUA", "RUA", "LLA", "RLA", "LH", "RH",
	"LUL", "RUL", "LLL", "RLL", "LF", "RF", "LT", "RT"]

## Relaxed standing pose every clip starts from.
const STANCE := {
	"LUA": Vector3(2, 0, 8), "RUA": Vector3(2, 0, -8),
	"LLA": Vector3(-12, 0, 0), "RLA": Vector3(-12, 0, 0),
	"LUL": Vector3(-2, 0, 1), "RUL": Vector3(-2, 0, -1),
	"LLL": Vector3(4, 0, 0), "RLL": Vector3(4, 0, 0),
	"LF": Vector3(-2, 0, 0), "RF": Vector3(-2, 0, 0),
}

static var _library: AnimationLibrary
static var clip_lengths: Dictionary = {}


static func get_library() -> AnimationLibrary:
	if _library == null:
		_library = _build()
	return _library


# ------------------------------------------------------------------ DSL helpers
static func P(over: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for k in BODY_KEYS:
		d[k] = STANCE.get(k, Vector3.ZERO)
	d["P"] = Vector3.ZERO
	for k in over.keys():
		d[k] = over[k]
	return d


static func mirror(pose: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in pose.keys():
		var v: Vector3 = pose[k]
		var nk: String = k
		if k.begins_with("L") and SHORT.has("R" + k.substr(1)):
			nk = "R" + k.substr(1)
		elif k.begins_with("R") and SHORT.has("L" + k.substr(1)):
			nk = "L" + k.substr(1)
		if k == "P":
			out[nk] = Vector3(-v.x, v.y, v.z)
		else:
			out[nk] = Vector3(v.x, -v.y, -v.z)
	return out


static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for k in a.keys():
		out[k] = a[k].lerp(b.get(k, a[k]), t)
	return out


static func _clip(clip_name: String, length: float, loop: bool, keys: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var all_keys: Dictionary = {}
	for k in keys:
		for bk in k[1].keys():
			all_keys[bk] = true
	for bk in all_keys.keys():
		if bk == "P":
			var tp := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(tp, NodePath("Skeleton:Hips"))
			anim.track_set_interpolation_type(tp, Animation.INTERPOLATION_CUBIC)
			for k in keys:
				var off: Vector3 = k[1].get("P", Vector3.ZERO)
				anim.position_track_insert_key(tp, k[0], Vector3(0, HumanoidDef.BASE_HIPS_HEIGHT, 0) + off)
			continue
		var bone: String = SHORT.get(bk, bk)
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton:" + bone))
		anim.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
		for k in keys:
			var e: Vector3 = k[1].get(bk, STANCE.get(bk, Vector3.ZERO))
			anim.rotation_track_insert_key(tr, k[0], Quaternion.from_euler(e * (PI / 180.0)))
	clip_lengths[clip_name] = length
	return anim


static func _cycle(clip_name: String, a: Dictionary, b: Dictionary, length: float = 1.0) -> Animation:
	# a = left contact, b = passing (left support). Mirrors for the right side.
	return _clip(clip_name, length, true, [[0.0, a], [length * 0.25, b], [length * 0.5, mirror(a)], [length * 0.75, mirror(b)], [length, a]])


## Gait generator: returns [contact, passing] poses.
static func _gait(g: Dictionary) -> Array:
	var lean: float = g.get("lean", 3.0)
	var tw: float = g.get("twist", 5.0)
	var base: Dictionary = g.get("base", {})
	var contact := P(base)
	contact.merge({
		"LUL": Vector3(g.thigh_fwd, 0, 1), "LLL": Vector3(g.knee_contact, 0, 0), "LF": Vector3(g.foot_contact, 0, 0),
		"RUL": Vector3(g.thigh_back, 0, -1), "RLL": Vector3(g.knee_push, 0, 0), "RF": Vector3(g.foot_push, 0, 0),
		"LUA": Vector3(g.arm_back, 0, g.get("arm_out", 8.0)), "RUA": Vector3(g.arm_fwd, 0, -g.get("arm_out", 8.0)),
		"LLA": Vector3(g.elbow_back, 0, 0), "RLA": Vector3(g.elbow_fwd, 0, 0),
		"H": Vector3(0, -tw, 0), "S": Vector3(lean * 0.5, 0, 0), "C": Vector3(lean * 0.5, tw * 1.6, 0),
		"Hd": Vector3(-lean * 0.6, -tw * 0.5, 0), "P": Vector3(0, g.bob_low, 0),
	}, true)
	var pass_pose := P(base)
	pass_pose.merge({
		"LUL": Vector3(g.thigh_support, 0, 1), "LLL": Vector3(g.knee_support, 0, 0), "LF": Vector3(g.get("foot_support", 0.0), 0, 0),
		"RUL": Vector3(g.thigh_swing, 0, -1), "RLL": Vector3(g.knee_swing, 0, 0), "RF": Vector3(g.foot_swing, 0, 0),
		"LUA": Vector3(g.arm_mid, 0, g.get("arm_out", 8.0)), "RUA": Vector3(-g.arm_mid, 0, -g.get("arm_out", 8.0)),
		"LLA": Vector3(g.elbow_mid, 0, 0), "RLA": Vector3(g.elbow_mid, 0, 0),
		"H": Vector3(0, 0, g.get("roll", 3.0)), "S": Vector3(lean * 0.5, 0, 0), "C": Vector3(lean * 0.5, 0, 0),
		"Hd": Vector3(-lean * 0.6, 0, 0), "P": Vector3(0, g.bob_high, 0),
	}, true)
	return [contact, pass_pose]


# ------------------------------------------------------------------ library
static func _build() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var add := func(n: String, anim: Animation) -> void:
		lib.add_animation(n, anim)

	# ---------- locomotion (all 1.0 s, phase aligned so they blend cleanly) ----------
	var idle_a := P({"C": Vector3(0, 0, 0), "P": Vector3(0, -0.004, 0)})
	var idle_b := P({"C": Vector3(-1.8, 0, 0), "S": Vector3(-0.6, 0, 0), "LUA": Vector3(1, 0, 9.5), "RUA": Vector3(1, 0, -9.5), "P": Vector3(0, 0.002, 0), "Hd": Vector3(1.5, 0, 0)})
	add.call("idle", _clip("idle", 1.0, true, [[0.0, idle_a], [0.5, idle_b], [1.0, idle_a]]))

	var walk := _gait({"thigh_fwd": -24.0, "knee_contact": 4.0, "foot_contact": -12.0, "thigh_back": 17.0, "knee_push": 24.0, "foot_push": 16.0,
		"thigh_support": -2.0, "knee_support": 7.0, "thigh_swing": -14.0, "knee_swing": 50.0, "foot_swing": -6.0,
		"arm_fwd": -18.0, "arm_back": 16.0, "elbow_fwd": -26.0, "elbow_back": -10.0, "arm_mid": 1.0, "elbow_mid": -16.0,
		"bob_low": -0.026, "bob_high": 0.012, "lean": 4.0, "twist": 5.0})
	add.call("walk", _cycle("walk", walk[0], walk[1]))

	var jog := _gait({"thigh_fwd": -32.0, "knee_contact": 14.0, "foot_contact": -10.0, "thigh_back": 24.0, "knee_push": 50.0, "foot_push": 22.0,
		"thigh_support": 4.0, "knee_support": 24.0, "thigh_swing": -28.0, "knee_swing": 88.0, "foot_swing": 0.0,
		"arm_fwd": -30.0, "arm_back": 28.0, "elbow_fwd": -78.0, "elbow_back": -62.0, "arm_mid": 0.0, "elbow_mid": -70.0,
		"bob_low": -0.045, "bob_high": 0.025, "lean": 9.0, "twist": 6.0, "arm_out": 12.0})
	add.call("jog", _cycle("jog", jog[0], jog[1]))

	var run := _gait({"thigh_fwd": -40.0, "knee_contact": 18.0, "foot_contact": -8.0, "thigh_back": 30.0, "knee_push": 68.0, "foot_push": 28.0,
		"thigh_support": 8.0, "knee_support": 32.0, "thigh_swing": -44.0, "knee_swing": 105.0, "foot_swing": 5.0,
		"arm_fwd": -42.0, "arm_back": 38.0, "elbow_fwd": -88.0, "elbow_back": -70.0, "arm_mid": 0.0, "elbow_mid": -82.0,
		"bob_low": -0.055, "bob_high": 0.04, "lean": 13.0, "twist": 7.0, "arm_out": 13.0})
	add.call("run", _cycle("run", run[0], run[1]))

	var sprint := _gait({"thigh_fwd": -52.0, "knee_contact": 22.0, "foot_contact": -4.0, "thigh_back": 34.0, "knee_push": 82.0, "foot_push": 32.0,
		"thigh_support": 10.0, "knee_support": 36.0, "thigh_swing": -62.0, "knee_swing": 118.0, "foot_swing": 10.0,
		"arm_fwd": -58.0, "arm_back": 50.0, "elbow_fwd": -92.0, "elbow_back": -78.0, "arm_mid": 0.0, "elbow_mid": -88.0,
		"bob_low": -0.06, "bob_high": 0.05, "lean": 19.0, "twist": 8.0, "arm_out": 14.0})
	add.call("sprint", _cycle("sprint", sprint[0], sprint[1]))

	# Injured: limping on the right leg, hand pressed on the side.
	var inj_base := {"RUA": Vector3(-24, 0, -4), "RLA": Vector3(-95, 0, 0), "S": Vector3(10, 0, 0), "Hd": Vector3(6, 0, 0)}
	var limp_a := P(inj_base)
	limp_a.merge({"LUL": Vector3(-22, 0, 1), "LLL": Vector3(6, 0, 0), "RUL": Vector3(10, 0, -2), "RLL": Vector3(12, 0, 0), "LUA": Vector3(14, 0, 12), "C": Vector3(4, 0, -5), "P": Vector3(0, -0.02, 0)}, true)
	var limp_b := P(inj_base)
	limp_b.merge({"LUL": Vector3(-2, 0, 1), "LLL": Vector3(8, 0, 0), "RUL": Vector3(-12, 0, -2), "RLL": Vector3(28, 0, 0), "LUA": Vector3(0, 0, 12), "C": Vector3(4, 0, 3), "P": Vector3(0, 0.0, 0)}, true)
	var limp_c := P(inj_base)
	limp_c.merge({"LUL": Vector3(14, 0, 1), "LLL": Vector3(20, 0, 0), "RUL": Vector3(-18, 0, -2), "RLL": Vector3(8, 0, 0), "LUA": Vector3(-12, 0, 12), "C": Vector3(10, 0, 9), "H": Vector3(0, 0, -6), "P": Vector3(0, -0.05, 0)}, true)
	add.call("injured_walk", _clip("injured_walk", 1.0, true, [[0.0, limp_a], [0.35, limp_b], [0.6, limp_c], [0.85, limp_b], [1.0, limp_a]]))
	var inj_idle := P(inj_base)
	inj_idle.merge({"C": Vector3(6, 0, 6), "H": Vector3(0, 0, -4), "RLL": Vector3(14, 0, 0), "RUL": Vector3(-6, 0, -2), "P": Vector3(0, -0.02, 0)}, true)
	add.call("injured_idle", _clip("injured_idle", 1.0, true, [[0.0, inj_idle], [0.5, blend(inj_idle, P(inj_base), 0.25)], [1.0, inj_idle]]))

	# Crouch
	var crouch := P({"H": Vector3(18, 0, 0), "S": Vector3(10, 0, 0), "C": Vector3(6, 0, 0), "Hd": Vector3(-26, 0, 0),
		"LUL": Vector3(-92, 0, 4), "RUL": Vector3(-92, 0, -4), "LLL": Vector3(118, 0, 0), "RLL": Vector3(118, 0, 0),
		"LF": Vector3(-44, 0, 0), "RF": Vector3(-44, 0, 0), "LUA": Vector3(-26, 0, 12), "RUA": Vector3(-26, 0, -12),
		"LLA": Vector3(-50, 0, 0), "RLA": Vector3(-50, 0, 0), "P": Vector3(0, -0.36, -0.04)})
	add.call("crouch_idle", _clip("crouch_idle", 1.0, true, [[0.0, crouch], [0.5, blend(crouch, P({"C": Vector3(4, 0, 0)}), 0.05)], [1.0, crouch]]))
	var cw_a := crouch.duplicate()
	cw_a.merge({"LUL": Vector3(-108, 0, 4), "LLL": Vector3(110, 0, 0), "RUL": Vector3(-72, 0, -4), "RLL": Vector3(126, 0, 0), "LF": Vector3(-30, 0, 0), "RF": Vector3(-50, 0, 0), "P": Vector3(0, -0.38, -0.04)}, true)
	var cw_b := crouch.duplicate()
	cw_b.merge({"LUL": Vector3(-86, 0, 4), "LLL": Vector3(116, 0, 0), "RUL": Vector3(-100, 0, -4), "RLL": Vector3(132, 0, 0), "P": Vector3(0, -0.34, -0.04)}, true)
	add.call("crouch_walk", _cycle("crouch_walk", cw_a, cw_b))

	# ---------- air ----------
	var jump0 := P({"P": Vector3(0, -0.12, 0), "S": Vector3(14, 0, 0), "LUL": Vector3(-34, 0, 2), "RUL": Vector3(-34, 0, -2), "LLL": Vector3(56, 0, 0), "RLL": Vector3(56, 0, 0), "LF": Vector3(-20, 0, 0), "RF": Vector3(-20, 0, 0), "LUA": Vector3(40, 0, 12), "RUA": Vector3(40, 0, -12)})
	var jump1 := P({"P": Vector3(0, 0.02, 0), "S": Vector3(-3, 0, 0), "LUL": Vector3(-8, 0, 2), "RUL": Vector3(6, 0, -2), "LLL": Vector3(20, 0, 0), "RLL": Vector3(10, 0, 0), "LF": Vector3(28, 0, 0), "RF": Vector3(30, 0, 0), "LUA": Vector3(-62, 0, 20), "RUA": Vector3(-55, 0, -20), "LLA": Vector3(-30, 0, 0), "RLA": Vector3(-30, 0, 0)})
	add.call("jump", _clip("jump", 0.32, false, [[0.0, jump0], [0.32, jump1]]))
	var fall_a := P({"LUL": Vector3(-28, 0, 6), "RUL": Vector3(-6, 0, -6), "LLL": Vector3(40, 0, 0), "RLL": Vector3(22, 0, 0), "LUA": Vector3(-30, 0, 55), "RUA": Vector3(-20, 0, -62), "LLA": Vector3(-30, 0, 0), "RLA": Vector3(-26, 0, 0), "S": Vector3(4, 0, 0), "Hd": Vector3(-8, 0, 0)})
	var fall_b := P({"LUL": Vector3(-10, 0, 6), "RUL": Vector3(-26, 0, -6), "LLL": Vector3(24, 0, 0), "RLL": Vector3(42, 0, 0), "LUA": Vector3(-18, 0, 68), "RUA": Vector3(-34, 0, -52), "LLA": Vector3(-24, 0, 0), "RLA": Vector3(-34, 0, 0), "S": Vector3(2, 0, 0), "Hd": Vector3(-10, 0, 0)})
	add.call("fall", _clip("fall", 0.9, true, [[0.0, fall_a], [0.45, fall_b], [0.9, fall_a]]))
	var land0 := P({"P": Vector3(0, -0.17, 0.0), "S": Vector3(22, 0, 0), "C": Vector3(6, 0, 0), "Hd": Vector3(-18, 0, 0), "LUL": Vector3(-52, 0, 3), "RUL": Vector3(-46, 0, -3), "LLL": Vector3(86, 0, 0), "RLL": Vector3(80, 0, 0), "LF": Vector3(-34, 0, 0), "RF": Vector3(-34, 0, 0), "LUA": Vector3(-34, 0, 22), "RUA": Vector3(-30, 0, -22), "LLA": Vector3(-40, 0, 0), "RLA": Vector3(-40, 0, 0)})
	add.call("land", _clip("land", 0.42, false, [[0.0, land0], [0.18, blend(land0, P({}), 0.35)], [0.42, P({})]]))
	var landh := P({"P": Vector3(0, -0.42, 0.05), "H": Vector3(30, 0, 0), "S": Vector3(20, 0, 0), "C": Vector3(10, 0, 0), "Hd": Vector3(-30, 0, 0), "LUL": Vector3(-110, 0, 6), "RUL": Vector3(-96, 0, -6), "LLL": Vector3(130, 0, 0), "RLL": Vector3(124, 0, 0), "LF": Vector3(-50, 0, 0), "RF": Vector3(-56, 0, 0), "LUA": Vector3(-70, 0, 18), "RUA": Vector3(-60, 0, -18), "LLA": Vector3(-10, 0, 0), "RLA": Vector3(-14, 0, 0)})
	add.call("land_hard", _clip("land_hard", 1.1, false, [[0.0, landh], [0.45, landh], [0.8, blend(landh, P({}), 0.55)], [1.1, P({})]]))

	# ---------- sitting / lying ----------
	var sit := P({"P": Vector3(0, -0.47, -0.06), "S": Vector3(-5, 0, 0), "C": Vector3(-2, 0, 0), "Hd": Vector3(4, 0, 0),
		"LUL": Vector3(-86, 0, 6), "RUL": Vector3(-86, 0, -6), "LLL": Vector3(84, 0, 0), "RLL": Vector3(84, 0, 0), "LF": Vector3(0, 0, 0), "RF": Vector3(0, 0, 0),
		"LUA": Vector3(-24, 0, 10), "RUA": Vector3(-24, 0, -10), "LLA": Vector3(-38, 0, 0), "RLA": Vector3(-38, 0, 0)})
	add.call("sit", _clip("sit", 2.0, true, [[0.0, sit], [1.0, blend(sit, P({"C": Vector3(-4, 0, 0)}), 0.12)], [2.0, sit]]))
	var sit_mid := P({"P": Vector3(0, -0.28, 0.04), "S": Vector3(28, 0, 0), "Hd": Vector3(-20, 0, 0), "LUL": Vector3(-56, 0, 4), "RUL": Vector3(-56, 0, -4), "LLL": Vector3(66, 0, 0), "RLL": Vector3(66, 0, 0), "LF": Vector3(-10, 0, 0), "RF": Vector3(-10, 0, 0), "LUA": Vector3(-30, 0, 12), "RUA": Vector3(-30, 0, -12)})
	add.call("sit_down", _clip("sit_down", 0.9, false, [[0.0, P({})], [0.45, sit_mid], [0.9, sit]]))
	add.call("stand_up", _clip("stand_up", 0.9, false, [[0.0, sit], [0.45, sit_mid], [0.9, P({})]]))
	var lie := P({"H": Vector3(-90, 0, 0), "P": Vector3(0, -0.8, 0), "Hd": Vector3(-4, 0, 0), "LUL": Vector3(-4, 0, 3), "RUL": Vector3(-4, 0, -3), "LLL": Vector3(8, 0, 0), "RLL": Vector3(8, 0, 0), "LF": Vector3(20, 0, 0), "RF": Vector3(20, 0, 0), "LUA": Vector3(0, 0, 14), "RUA": Vector3(0, 0, -14), "LLA": Vector3(-10, 0, 0), "RLA": Vector3(-10, 0, 0)})
	add.call("lie", _clip("lie", 3.0, true, [[0.0, lie], [1.5, blend(lie, P({"H": Vector3(-90, 0, 0), "C": Vector3(-2, 0, 0), "P": Vector3(0, -0.8, 0)}), 0.3)], [3.0, lie]]))
	add.call("sleep", _clip("sleep", 4.0, true, [[0.0, lie], [2.0, blend(lie, P({"H": Vector3(-90, 0, 0), "C": Vector3(-3, 0, 0), "P": Vector3(0, -0.8, 0)}), 0.4)], [4.0, lie]]))

	# ---------- recovery (get up) ----------
	var gb1 := P({"H": Vector3(-35, 0, 0), "P": Vector3(0, -0.8, -0.04), "S": Vector3(4, 0, 0), "LUL": Vector3(-55, 0, 6), "RUL": Vector3(-55, 0, -6), "LLL": Vector3(10, 0, 0), "RLL": Vector3(10, 0, 0), "LUA": Vector3(42, 0, 22), "RUA": Vector3(42, 0, -22), "LLA": Vector3(-6, 0, 0), "RLA": Vector3(-6, 0, 0), "Hd": Vector3(14, 0, 0)})
	var gb2 := P({"H": Vector3(8, 0, 0), "P": Vector3(0, -0.76, 0.05), "S": Vector3(22, 0, 0), "C": Vector3(10, 0, 0), "LUL": Vector3(-138, 0, 8), "RUL": Vector3(-130, 0, -8), "LLL": Vector3(140, 0, 0), "RLL": Vector3(135, 0, 0), "LF": Vector3(-20, 0, 0), "RF": Vector3(-20, 0, 0), "LUA": Vector3(-40, 0, 18), "RUA": Vector3(30, 0, -30), "LLA": Vector3(-30, 0, 0), "RLA": Vector3(-5, 0, 0), "Hd": Vector3(-10, 0, 0)})
	var g_crouch := P({"H": Vector3(26, 0, 0), "P": Vector3(0, -0.5, 0.08), "S": Vector3(14, 0, 0), "C": Vector3(6, 0, 0), "Hd": Vector3(-24, 0, 0), "LUL": Vector3(-102, 0, 6), "RUL": Vector3(-96, 0, -6), "LLL": Vector3(122, 0, 0), "RLL": Vector3(118, 0, 0), "LF": Vector3(-46, 0, 0), "RF": Vector3(-46, 0, 0), "LUA": Vector3(-34, 0, 20), "RUA": Vector3(-30, 0, -20), "LLA": Vector3(-30, 0, 0), "RLA": Vector3(-30, 0, 0)})
	var g_rise := P({"H": Vector3(9, 0, 0), "P": Vector3(0, -0.13, 0.02), "S": Vector3(9, 0, 0), "LUL": Vector3(-28, 0, 3), "RUL": Vector3(-24, 0, -3), "LLL": Vector3(38, 0, 0), "RLL": Vector3(34, 0, 0), "LF": Vector3(-10, 0, 0), "RF": Vector3(-10, 0, 0), "LUA": Vector3(-8, 0, 14), "RUA": Vector3(-8, 0, -14)})
	add.call("getup_back", _clip("getup_back", 2.6, false, [[0.0, lie], [0.55, gb1], [1.15, gb2], [1.7, g_crouch], [2.2, g_rise], [2.6, P({})]]))
	var prone := P({"H": Vector3(88, 0, 0), "P": Vector3(0, -0.82, 0), "Hd": Vector3(-30, 0, 0), "LUL": Vector3(2, 0, 4), "RUL": Vector3(2, 0, -4), "LLL": Vector3(6, 0, 0), "RLL": Vector3(6, 0, 0), "LF": Vector3(40, 0, 0), "RF": Vector3(40, 0, 0), "LUA": Vector3(-40, 0, 30), "RUA": Vector3(-40, 0, -30), "LLA": Vector3(-60, 0, 0), "RLA": Vector3(-60, 0, 0)})
	var gf1 := P({"H": Vector3(72, 0, 0), "P": Vector3(0, -0.74, 0), "S": Vector3(-16, 0, 0), "C": Vector3(-8, 0, 0), "Hd": Vector3(-28, 0, 0), "LUL": Vector3(10, 0, 4), "RUL": Vector3(10, 0, -4), "LLL": Vector3(20, 0, 0), "RLL": Vector3(20, 0, 0), "LF": Vector3(40, 0, 0), "RF": Vector3(40, 0, 0), "LUA": Vector3(-82, 0, 14), "RUA": Vector3(-82, 0, -14), "LLA": Vector3(-8, 0, 0), "RLA": Vector3(-8, 0, 0)})
	var gf2 := P({"H": Vector3(58, 0, 0), "P": Vector3(0, -0.6, -0.06), "S": Vector3(4, 0, 0), "Hd": Vector3(-30, 0, 0), "LUL": Vector3(-62, 0, 6), "RUL": Vector3(-58, 0, -6), "LLL": Vector3(96, 0, 0), "RLL": Vector3(92, 0, 0), "LF": Vector3(30, 0, 0), "RF": Vector3(30, 0, 0), "LUA": Vector3(-62, 0, 10), "RUA": Vector3(-62, 0, -10), "LLA": Vector3(-4, 0, 0), "RLA": Vector3(-4, 0, 0)})
	add.call("getup_front", _clip("getup_front", 2.6, false, [[0.0, prone], [0.5, gf1], [1.1, gf2], [1.7, g_crouch], [2.2, g_rise], [2.6, P({})]]))

	# ---------- balance / impacts ----------
	var st1 := P({"S": Vector3(-14, 0, 0), "C": Vector3(-8, 0, 0), "Hd": Vector3(-12, 0, 0), "RUL": Vector3(30, 0, -4), "RLL": Vector3(30, 0, 0), "LUL": Vector3(-14, 0, 4), "LLL": Vector3(18, 0, 0), "LUA": Vector3(-46, 0, 52), "RUA": Vector3(-38, 0, -60), "LLA": Vector3(-34, 0, 0), "RLA": Vector3(-30, 0, 0), "P": Vector3(0, -0.05, 0)})
	var st2 := P({"S": Vector3(-6, 0, 0), "C": Vector3(-4, 0, 0), "LUL": Vector3(26, 0, 4), "LLL": Vector3(34, 0, 0), "RUL": Vector3(-10, 0, -4), "RLL": Vector3(20, 0, 0), "LUA": Vector3(-30, 0, 62), "RUA": Vector3(-46, 0, -48), "LLA": Vector3(-40, 0, 0), "RLA": Vector3(-34, 0, 0), "P": Vector3(0, -0.06, 0)})
	add.call("stumble", _clip("stumble", 0.95, false, [[0.0, P({})], [0.18, st1], [0.45, st2], [0.72, blend(st2, P({}), 0.6)], [0.95, P({})]]))
	var stop1 := P({"H": Vector3(-6, 0, 0), "S": Vector3(-10, 0, 0), "C": Vector3(-4, 0, 0), "LUL": Vector3(-44, 0, 2), "LLL": Vector3(6, 0, 0), "LF": Vector3(-22, 0, 0), "RUL": Vector3(22, 0, -2), "RLL": Vector3(58, 0, 0), "RF": Vector3(10, 0, 0), "LUA": Vector3(-34, 0, 18), "RUA": Vector3(-20, 0, -18), "LLA": Vector3(-60, 0, 0), "RLA": Vector3(-60, 0, 0), "P": Vector3(0, -0.08, 0)})
	add.call("stop_run", _clip("stop_run", 0.6, false, [[0.0, stop1], [0.3, blend(stop1, P({}), 0.5)], [0.6, P({})]]))

	var hit := func(over: Dictionary) -> Animation:
		return null
	var hf := P({"S": Vector3(-8, 0, 0), "C": Vector3(-12, 0, 0), "Hd": Vector3(-22, 0, 0), "LUA": Vector3(-30, 0, 24), "RUA": Vector3(-26, 0, -24), "LLA": Vector3(-60, 0, 0), "RLA": Vector3(-60, 0, 0)})
	add.call("hit_front", _clip("hit_front", 0.55, false, [[0.0, P({})], [0.1, hf], [0.55, P({})]]))
	var hb := P({"S": Vector3(12, 0, 0), "C": Vector3(14, 0, 0), "Hd": Vector3(20, 0, 0), "LUA": Vector3(26, 0, 22), "RUA": Vector3(26, 0, -22)})
	add.call("hit_back", _clip("hit_back", 0.55, false, [[0.0, P({})], [0.1, hb], [0.55, P({})]]))
	var hl := P({"S": Vector3(0, 0, 8), "C": Vector3(0, -8, 14), "Hd": Vector3(0, 0, 20), "LUA": Vector3(-10, 0, 30), "RUA": Vector3(-10, 0, -26)})
	add.call("hit_left", _clip("hit_left", 0.55, false, [[0.0, P({})], [0.1, hl], [0.55, P({})]]))
	add.call("hit_right", _clip("hit_right", 0.55, false, [[0.0, P({})], [0.1, mirror(hl)], [0.55, P({})]]))
	var hh := P({"N": Vector3(-14, 0, 0), "Hd": Vector3(-34, 8, 0), "C": Vector3(-6, 0, 0), "LUA": Vector3(-46, 0, 30), "RUA": Vector3(-40, 0, -30), "LLA": Vector3(-90, 0, 0), "RLA": Vector3(-90, 0, 0)})
	add.call("hit_head", _clip("hit_head", 0.7, false, [[0.0, P({})], [0.1, hh], [0.4, blend(hh, P({}), 0.4)], [0.7, P({})]]))

	# ---------- combat ----------
	var guard := P({"LUA": Vector3(-58, 0, 22), "RUA": Vector3(-50, 0, -24), "LLA": Vector3(-112, 0, 0), "RLA": Vector3(-118, 0, 0), "C": Vector3(6, 0, 0), "Hd": Vector3(8, 0, 0)})
	add.call("block", _clip("block", 1.0, true, [[0.0, guard], [0.5, blend(guard, P({"C": Vector3(8, 0, 0)}), 0.06)], [1.0, guard]]))
	var pr0 := guard.duplicate()
	pr0.merge({"C": Vector3(4, -14, 0), "RUA": Vector3(-30, 0, -28), "RLA": Vector3(-120, 0, 0)}, true)
	var pr1 := guard.duplicate()
	pr1.merge({"S": Vector3(6, 0, 0), "C": Vector3(8, 26, 0), "UC": Vector3(0, 10, 0), "RUA": Vector3(-86, 0, -4), "RLA": Vector3(-6, 0, 0), "Hd": Vector3(4, -18, 0)}, true)
	add.call("punch_r", _clip("punch_r", 0.48, false, [[0.0, guard], [0.1, pr0], [0.2, pr1], [0.48, guard]]))
	add.call("punch_l", _clip("punch_l", 0.48, false, [[0.0, guard], [0.1, mirror(pr0)], [0.2, mirror(pr1)], [0.48, guard]]))
	var kick1 := P({"S": Vector3(-16, 0, 0), "RUL": Vector3(-28, 0, -4), "RLL": Vector3(90, 0, 0), "LUA": Vector3(-30, 0, 40), "RUA": Vector3(10, 0, -40)})
	var kick2 := P({"S": Vector3(-22, 0, 0), "RUL": Vector3(-82, 0, -4), "RLL": Vector3(4, 0, 0), "RF": Vector3(30, 0, 0), "LUA": Vector3(-36, 0, 50), "RUA": Vector3(20, 0, -46), "LLL": Vector3(10, 0, 0)})
	add.call("kick", _clip("kick", 0.75, false, [[0.0, P({})], [0.18, kick1], [0.32, kick2], [0.55, kick1], [0.75, P({})]]))
	var dl := P({"P": Vector3(0, -0.14, 0), "S": Vector3(8, 0, -18), "C": Vector3(0, 0, -10), "LUL": Vector3(-30, 0, 24), "LLL": Vector3(44, 0, 0), "RUL": Vector3(-6, 0, -6), "RLL": Vector3(10, 0, 0), "LUA": Vector3(-40, 0, 30), "RUA": Vector3(-40, 0, -20), "LLA": Vector3(-90, 0, 0), "RLA": Vector3(-90, 0, 0)})
	add.call("dodge_l", _clip("dodge_l", 0.5, false, [[0.0, P({})], [0.15, dl], [0.5, P({})]]))
	add.call("dodge_r", _clip("dodge_r", 0.5, false, [[0.0, P({})], [0.15, mirror(dl)], [0.5, P({})]]))
	var db := P({"P": Vector3(0, -0.12, -0.05), "S": Vector3(-14, 0, 0), "LUL": Vector3(18, 0, 3), "LLL": Vector3(30, 0, 0), "RUL": Vector3(-30, 0, -3), "RLL": Vector3(40, 0, 0), "LUA": Vector3(-50, 0, 26), "RUA": Vector3(-50, 0, -26), "LLA": Vector3(-100, 0, 0), "RLA": Vector3(-100, 0, 0)})
	add.call("dodge_back", _clip("dodge_back", 0.5, false, [[0.0, P({})], [0.15, db], [0.5, P({})]]))

	# ---------- social / everyday upper-body actions ----------
	var wave_up := P({"RUA": Vector3(-10, 0, -150), "RLA": Vector3(-35, 0, 18), "Hd": Vector3(0, -8, 0)})
	var wave_b := P({"RUA": Vector3(-10, 0, -150), "RLA": Vector3(-35, 0, -22), "Hd": Vector3(0, -8, 0)})
	add.call("wave", _clip("wave", 1.4, false, [[0.0, P({})], [0.3, wave_up], [0.55, wave_b], [0.8, wave_up], [1.05, wave_b], [1.4, P({})]]))
	var t1 := P({"LUA": Vector3(-24, 0, 14), "RUA": Vector3(-30, 0, -18), "LLA": Vector3(-64, 0, 0), "RLA": Vector3(-80, 0, 0), "Hd": Vector3(3, 4, 0)})
	var t2 := P({"LUA": Vector3(-34, 0, 22), "RUA": Vector3(-16, 0, -12), "LLA": Vector3(-88, 0, 0), "RLA": Vector3(-52, 0, 0), "Hd": Vector3(-3, -5, 0), "C": Vector3(2, 0, 0)})
	add.call("talk", _clip("talk", 2.4, false, [[0.0, P({})], [0.4, t1], [1.0, t2], [1.6, t1], [2.4, P({})]]))
	add.call("talk2", _clip("talk2", 2.0, false, [[0.0, P({})], [0.5, mirror(t2)], [1.2, mirror(t1)], [2.0, P({})]]))
	var eat_up := P({"RUA": Vector3(-38, 0, -18), "RLA": Vector3(-142, 0, 0), "Hd": Vector3(8, 0, 0)})
	var eat_dn := P({"RUA": Vector3(-26, 0, -12), "RLA": Vector3(-90, 0, 0), "Hd": Vector3(10, 0, 0)})
	add.call("eat", _clip("eat", 2.2, false, [[0.0, P({})], [0.4, eat_up], [0.8, eat_dn], [1.3, eat_up], [1.8, eat_dn], [2.2, P({})]]))
	var drink_up := P({"RUA": Vector3(-44, 0, -16), "RLA": Vector3(-140, 0, 0), "Hd": Vector3(-24, 0, 0), "N": Vector3(-6, 0, 0)})
	add.call("drink", _clip("drink", 1.8, false, [[0.0, P({})], [0.45, drink_up], [1.3, drink_up], [1.8, P({})]]))
	var laugh_a := P({"S": Vector3(10, 0, 0), "C": Vector3(6, 0, 0), "Hd": Vector3(-16, 0, 0), "LUA": Vector3(-18, 0, 6), "RUA": Vector3(-18, 0, -6), "LLA": Vector3(-82, 0, 0), "RLA": Vector3(-82, 0, 0)})
	var laugh_b := laugh_a.duplicate()
	laugh_b.merge({"S": Vector3(4, 0, 0), "C": Vector3(-4, 0, 0), "Hd": Vector3(-24, 0, 0)}, true)
	add.call("laugh", _clip("laugh", 1.6, false, [[0.0, P({})], [0.25, laugh_a], [0.5, laugh_b], [0.75, laugh_a], [1.0, laugh_b], [1.6, P({})]]))
	var ang := P({"C": Vector3(-6, 0, 0), "Hd": Vector3(6, 0, 0), "LUA": Vector3(-36, 0, 28), "RUA": Vector3(-36, 0, -28), "LLA": Vector3(-92, 0, 0), "RLA": Vector3(-92, 0, 0)})
	var ang2 := ang.duplicate()
	ang2.merge({"LUA": Vector3(-46, 0, 34), "RUA": Vector3(-46, 0, -34), "LLA": Vector3(-74, 0, 0), "RLA": Vector3(-74, 0, 0), "Hd": Vector3(12, 0, 0)}, true)
	add.call("angry", _clip("angry", 1.4, false, [[0.0, P({})], [0.3, ang], [0.55, ang2], [0.8, ang], [1.05, ang2], [1.4, P({})]]))
	var shock := P({"S": Vector3(-12, 0, 0), "C": Vector3(-6, 0, 0), "Hd": Vector3(-10, 0, 0), "LUA": Vector3(-62, 0, 26), "RUA": Vector3(-62, 0, -26), "LLA": Vector3(-122, 0, 0), "RLA": Vector3(-122, 0, 0), "P": Vector3(0, -0.04, -0.03), "LUL": Vector3(8, 0, 4), "LLL": Vector3(14, 0, 0)})
	add.call("shocked", _clip("shocked", 1.1, false, [[0.0, P({})], [0.12, shock], [0.7, shock], [1.1, P({})]]))
	var pick := P({"P": Vector3(0, -0.36, -0.02), "S": Vector3(40, 0, 0), "C": Vector3(10, 0, 0), "Hd": Vector3(-20, 0, 0), "LUL": Vector3(-78, 0, 6), "RUL": Vector3(-70, 0, -6), "LLL": Vector3(100, 0, 0), "RLL": Vector3(94, 0, 0), "LF": Vector3(-28, 0, 0), "RF": Vector3(-28, 0, 0), "RUA": Vector3(-62, 0, -8), "RLA": Vector3(-14, 0, 0)})
	add.call("pick_up", _clip("pick_up", 1.3, false, [[0.0, P({})], [0.5, pick], [0.75, pick], [1.3, P({})]]))
	var door := P({"RUA": Vector3(-62, 0, -10), "RLA": Vector3(-30, 0, 0), "C": Vector3(4, 8, 0)})
	add.call("open_door", _clip("open_door", 0.8, false, [[0.0, P({})], [0.3, door], [0.55, door], [0.8, P({})]]))
	var point := P({"RUA": Vector3(-84, 0, -6), "RLA": Vector3(-4, 0, 0), "Hd": Vector3(0, -6, 0)})
	add.call("point", _clip("point", 1.2, false, [[0.0, P({})], [0.3, point], [0.9, point], [1.2, P({})]]))
	var cheer := P({"LUA": Vector3(-20, 0, 150), "RUA": Vector3(-20, 0, -150), "LLA": Vector3(-20, 0, 0), "RLA": Vector3(-20, 0, 0), "Hd": Vector3(-14, 0, 0)})
	add.call("cheer", _clip("cheer", 1.3, false, [[0.0, P({})], [0.3, cheer], [0.6, blend(cheer, P({}), 0.2)], [0.9, cheer], [1.3, P({})]]))
	var flinch := P({"S": Vector3(10, 0, 0), "C": Vector3(8, 0, 0), "Hd": Vector3(16, 0, 0), "LUA": Vector3(-60, 0, 30), "RUA": Vector3(-60, 0, -30), "LLA": Vector3(-125, 0, 0), "RLA": Vector3(-125, 0, 0)})
	add.call("flinch", _clip("flinch", 0.7, false, [[0.0, P({})], [0.1, flinch], [0.4, flinch], [0.7, P({})]]))

	# ---------- holds (looping upper-body overlays) ----------
	var phone := P({"RUA": Vector3(-22, 0, -6), "RLA": Vector3(-104, 0, 0), "RH": Vector3(-10, 0, 0), "Hd": Vector3(24, 0, 0), "N": Vector3(6, 0, 0)})
	add.call("hold_phone", _clip("hold_phone", 2.0, true, [[0.0, phone], [1.0, blend(phone, P({"RUA": Vector3(-24, 0, -8), "RLA": Vector3(-108, 0, 0), "Hd": Vector3(22, 0, 0), "N": Vector3(6, 0, 0)}), 1.0)], [2.0, phone]]))
	var crossed := P({"LUA": Vector3(-22, -62, 6), "RUA": Vector3(-20, 58, -6), "LLA": Vector3(-96, 0, 0), "RLA": Vector3(-100, 0, 0)})
	add.call("hold_arms_crossed", _clip("hold_arms_crossed", 2.0, true, [[0.0, crossed], [1.0, crossed], [2.0, crossed]]))
	var pockets := P({"LUA": Vector3(10, 0, 14), "RUA": Vector3(10, 0, -14), "LLA": Vector3(-34, 0, 0), "RLA": Vector3(-34, 0, 0), "LH": Vector3(0, 0, -10), "RH": Vector3(0, 0, 10)})
	add.call("hold_pockets", _clip("hold_pockets", 2.0, true, [[0.0, pockets], [1.0, pockets], [2.0, pockets]]))
	var carry := P({"LUA": Vector3(-34, 0, 14), "RUA": Vector3(-34, 0, -14), "LLA": Vector3(-74, 0, 0), "RLA": Vector3(-74, 0, 0), "C": Vector3(-4, 0, 0)})
	add.call("hold_carry", _clip("hold_carry", 2.0, true, [[0.0, carry], [1.0, carry], [2.0, carry]]))
	var umbrella := P({"RUA": Vector3(-34, 0, -16), "RLA": Vector3(-98, 0, 0)})
	add.call("hold_umbrella", _clip("hold_umbrella", 2.0, true, [[0.0, umbrella], [1.0, umbrella], [2.0, umbrella]]))
	var work_a := P({"S": Vector3(10, 0, 0), "LUA": Vector3(-40, 0, 10), "RUA": Vector3(-34, 0, -12), "LLA": Vector3(-40, 0, 0), "RLA": Vector3(-56, 0, 0), "Hd": Vector3(18, 0, 0)})
	var work_b := P({"S": Vector3(10, 0, 0), "LUA": Vector3(-32, 0, 14), "RUA": Vector3(-44, 0, -8), "LLA": Vector3(-58, 0, 0), "RLA": Vector3(-36, 0, 0), "Hd": Vector3(16, 6, 0)})
	add.call("hold_work", _clip("hold_work", 1.6, true, [[0.0, work_a], [0.8, work_b], [1.6, work_a]]))
	add.call("hold_block", _clip("hold_block", 1.0, true, [[0.0, guard], [1.0, guard]]))
	return lib
