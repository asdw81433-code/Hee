class_name NPCBody
extends HumanoidBody
## Pooled physical body for a nearby NPC. Follows the brain's path along the
## pedestrian network with local avoidance, performs activities (sitting, working,
## chatting, phone, eating), shows emotions on face/posture and plays event reactions.
## Also acts as the player's "Talk to ..." interactable.

var manager: NPCManager
var npc: NPCData
var interact_radius: float = 2.2
var _lod: int = 0
var _expr_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3
var _punch_cd: float = 0.0
var _wave_cd: float = 0.0
var _seat: Seat = null
var _glance_target: Vector3
var _glance_until: float = 0.0
var _avoid := Vector3.ZERO


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


func attach(n: NPCData) -> void:
	npc = n
	add_to_group("interactable")
	add_to_group("npc_body")
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	setup_humanoid(n.appearance, 0)
	phys.strength = clampf(0.3 + n.trait_value("bravery") * 0.3 + (0.2 if n.appearance.build == CharacterAppearance.Build.MUSCULAR else 0.0) - (0.2 if n.age > 65 else 0.0), 0.1, 1.0)
	phys.balance_skill = clampf(0.65 - absf(n.age - 30) * 0.008 + n.skills.get("fitness", 0.3) * 0.3, 0.1, 1.0)
	phys.reaction_time = clampf(0.12 + n.trait_value("caution") * 0.05 + maxf(0, n.age - 40) * 0.003, 0.08, 0.35)
	phys.fear = n.trait_value("fearfulness")
	phys.recovery_ability = clampf(1.0 - n.age / 100.0, 0.2, 0.9)
	global_position = n.pos
	rotation.y = n.yaw
	velocity = Vector3.ZERO
	collider.disabled = false
	control_locked = false
	_last_pos = n.pos
	_stuck_timer = 0.0
	walk_speed = 1.25 + (1.0 - n.trait_value("laziness")) * 0.25 - maxf(0.0, n.age - 55) * 0.01
	model.face.set_expression(n.emotion.face_weights())


func detach() -> void:
	if npc:
		npc.pos = global_position
		npc.yaw = rotation.y
	_leave_seat()
	if phys.ragdoll and phys.ragdoll.attached:
		phys.ragdoll.detach()
	phys.state = HumanoidPhysics.State.NORMAL
	phys.recovery = HumanoidPhysics.Recovery.NONE
	npc = null
	remove_from_group("interactable")
	remove_from_group("npc_body")
	remove_from_group("humanoid")
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	global_position = Vector3(0, -500, 0)


func set_lod(level: int) -> void:
	if level == _lod:
		return
	_lod = level
	model.set_detail(level)
	model.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


# ------------------------------------------------------------------ interactable API
func interact_position() -> Vector3:
	return global_position


func can_interact(_actor: Node) -> bool:
	return npc != null and not is_down() and npc.reaction != "flee"


func get_prompt(_actor: Node) -> String:
	return "Talk to %s" % npc.first_name if npc.knows(NPCData.PLAYER_ID) else "Talk to stranger"


func interact(actor: Node) -> void:
	var w := Game.current_world
	if w and w.get("hud"):
		var dlg := NPCDialog.new()
		dlg.npc = npc
		dlg.body = self
		dlg.manager = manager
		dlg.player = actor
		(w.get("hud") as HUD).add_child(dlg)


# ------------------------------------------------------------------ behaviour
func _physics_process(delta: float) -> void:
	if npc == null:
		return
	_punch_cd = maxf(0.0, _punch_cd - delta)
	_wave_cd = maxf(0.0, _wave_cd - delta)
	if npc.reaction != "":
		_do_reaction(delta)
	elif not npc.path.is_empty():
		_follow_path(delta)
	else:
		_do_activity(delta)
	super._physics_process(delta)
	if not is_down():
		npc.pos = global_position
		npc.yaw = rotation.y
	_update_expression(delta)


func _follow_path(delta: float) -> void:
	_leave_seat()
	control_locked = false
	if npc.path_index >= npc.path.size():
		npc.path = PackedVector3Array()
		manager.arrive(npc)
		return
	var target := npc.path[npc.path_index]
	var to := target - global_position
	to.y = 0.0
	var d := to.length()
	var last := npc.path_index == npc.path.size() - 1
	if d < (0.45 if last else 0.9):
		npc.path_index += 1
		return
	var dir := to / maxf(d, 0.001)
	dir = (dir + _avoidance() * 0.9).normalized()
	move_dir = dir
	var hurry := npc.action == "work" and "late" in npc.action_reason
	desired_speed = jog_speed if hurry else walk_speed
	if npc.emotion.get_e("sad") > 0.5:
		desired_speed *= 0.85
	if last and d < 1.5:
		desired_speed = minf(desired_speed, walk_speed * 0.7)
	# Stuck detection: if we barely moved for 3 s, skip ahead (or re-path).
	if global_position.distance_to(_last_pos) < 0.05:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_pos = global_position
	if _stuck_timer > 3.0:
		_stuck_timer = 0.0
		npc.path_index += 1
		if npc.path_index < npc.path.size():
			global_position = global_position.lerp(npc.path[npc.path_index], 0.5)


func _avoidance() -> Vector3:
	var push := Vector3.ZERO
	for b in manager.body_of.values():
		var o := b as NPCBody
		if o == self:
			continue
		var off := global_position - o.global_position
		off.y = 0.0
		var dd := off.length()
		if dd < 1.4 and dd > 0.01:
			push += off / dd * (1.4 - dd)
	if manager.player:
		var off2 := global_position - manager.player.global_position
		off2.y = 0.0
		if off2.length() < 1.5 and off2.length() > 0.01:
			push += off2.normalized() * (1.5 - off2.length()) * 1.2
	return push.limit_length(1.0)


func _do_activity(_delta: float) -> void:
	move_dir = Vector3.ZERO
	desired_speed = 0.0
	var anim := model.animator
	var spot := manager.current_spot(npc)
	match npc.action:
		"chat":
			var other := manager.body_for(npc.talk_partner)
			if other:
				face_dir_override = (other.global_position - global_position)
				face_dir_override.y = 0.0
				model.rig.look_target = other.head_position()
				model.rig.look_weight = 1.0
			model.face.talking = int(GameTime.total_minutes * 2.0 + npc.id) % 3 != 0
			if not anim.is_upper_busy() and manager.rng.randf() < 0.02:
				anim.play_upper(["talk", "talk2", "laugh", "point"][manager.rng.randi() % 4] if npc.emotion.get_e("angry") < 0.4 else "angry")
			anim.set_hold("none")
			return
		_:
			model.face.talking = false
			face_dir_override = Vector3.ZERO
	if spot.has("seat") and spot.seat is Seat and npc.action != "work":
		_sit(spot.seat)
		anim.set_hold("hold_phone" if npc.action in ["rest", "leisure"] and npc.id % 2 == 0 else "none")
		return
	if spot.has("yaw"):
		rotation.y = lerp_angle(rotation.y, float(spot.yaw), 0.1)
	match npc.action:
		"work":
			anim.set_hold("hold_work" if spot.get("kind", "") in ["work", "counter"] else "hold_arms_crossed")
		"leisure", "socialize":
			anim.set_hold("hold_phone" if npc.trait_value("sociability") < 0.4 else "none")
		"shelter", "wander":
			anim.set_hold("hold_umbrella" if manager.is_raining() else "hold_pockets")
		_:
			anim.set_hold("none")
	# Look at the player when they are close and the NPC is curious/knows them.
	if manager.player and global_position.distance_to(manager.player.global_position) < 5.0:
		model.rig.look_target = manager.player.global_position + Vector3(0, 1.6, 0)
		model.rig.look_weight = clampf(0.4 + npc.trait_value("curiosity") * 0.6, 0.0, 1.0)
	elif Time.get_ticks_msec() / 1000.0 < _glance_until:
		model.rig.look_target = _glance_target + Vector3(0, 1.6, 0)
		model.rig.look_weight = 1.0
	else:
		model.rig.look_weight = 0.0


func _sit(seat: Seat) -> void:
	if _seat == seat:
		return
	if not seat.reserve(self):
		return
	_seat = seat
	control_locked = true
	collider.disabled = true
	var xf := seat.sit_transform()
	global_position = xf.origin
	rotation.y = xf.basis.get_euler().y
	model.animator.set_state("sit_down")


func _leave_seat() -> void:
	if _seat:
		_seat.release(self)
		_seat = null
		collider.disabled = false
		control_locked = false
		global_position += -global_basis.z * 0.45
		model.animator.set_state("stand_up")


func _update_expression(delta: float) -> void:
	_expr_timer -= delta
	if _expr_timer > 0.0:
		return
	_expr_timer = 0.3
	var fw := npc.emotion.face_weights()
	fw["tired"] = clampf(1.0 - float(npc.needs.energy) / 100.0, 0.0, 1.0) * 0.8
	model.face.set_expression(fw)
	model.rig.posture = {
		"slump": npc.emotion.get_e("sad") * 0.8 + fw.tired * 0.4,
		"chest_out": npc.trait_value("confidence") * 0.5 + npc.emotion.get_e("angry") * 0.5,
		"hunch": npc.emotion.get_e("fear") * 0.9 + npc.trait_value("shyness") * 0.25,
		"head_down": npc.emotion.get_e("sad") * 0.6 + npc.emotion.get_e("embarrassed") * 0.8,
	}
	phys.fatigue = fw.tired * 0.7
	phys.fear = maxf(npc.trait_value("fearfulness") * 0.5, npc.emotion.get_e("fear"))


# ------------------------------------------------------------------ social gestures
func wave_at(other: NPCData) -> void:
	if _wave_cd > 0.0 or not npc.path.is_empty() and npc.action == "work":
		return
	_wave_cd = 20.0
	model.animator.play_upper("wave")
	glance_at(other.pos)


func glance_at(p: Vector3) -> void:
	_glance_target = p
	_glance_until = Time.get_ticks_msec() / 1000.0 + 2.0


func can_see(world_point: Vector3) -> bool:
	var from := head_position()
	var to_p := world_point - from
	# Field of view ~220 degrees (people notice loud events beside them too).
	var fwd := -global_basis.z
	if fwd.dot(to_p.normalized()) < -0.35 and to_p.length() > 6.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, world_point, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ reactions to events
func _do_reaction(_delta: float) -> void:
	_leave_seat()
	var src := npc.reaction_source
	var away := global_position - src
	away.y = 0.0
	var toward := -away
	model.face.talking = npc.reaction in ["confront", "call_police", "help"]
	match npc.reaction:
		"flee":
			move_dir = away.normalized() if away.length() > 0.1 else -global_basis.z
			desired_speed = run_speed if away.length() < 25.0 else 0.0
			model.animator.set_hold("none")
		"watch", "film":
			move_dir = Vector3.ZERO
			desired_speed = 0.0
			face_dir_override = toward
			model.rig.look_target = src + Vector3(0, 1.3, 0)
			model.rig.look_weight = 1.0
			model.animator.set_hold("hold_phone" if npc.reaction == "film" else "hold_arms_crossed")
		"call_police":
			move_dir = away.normalized() * 0.5 if away.length() < 8.0 else Vector3.ZERO
			desired_speed = walk_speed
			model.animator.set_hold("hold_phone")
		"help":
			var victim_body := manager.body_for(int(npc.get_meta("help_target", -1)))
			var goal := victim_body.global_position if victim_body else src
			var to := goal - global_position
			to.y = 0.0
			move_dir = to.normalized() if to.length() > 1.4 else Vector3.ZERO
			desired_speed = jog_speed
			model.animator.set_hold("none")
		"confront":
			var target_pos := src
			if manager.player and int(npc.get_meta("confront_target", -1)) == NPCData.PLAYER_ID:
				target_pos = manager.player.global_position
			var to2 := target_pos - global_position
			to2.y = 0.0
			face_dir_override = to2
			if to2.length() > 1.3:
				move_dir = to2.normalized()
				desired_speed = jog_speed
			else:
				move_dir = Vector3.ZERO
				if _punch_cd <= 0.0 and npc.trait_value("aggression") > 0.45:
					_punch_cd = 1.6
					model.animator.play_upper("punch_r")
					get_tree().create_timer(0.2).timeout.connect(_land_punch)
				elif not model.animator.is_upper_busy():
					model.animator.play_upper("angry")
		"shout":
			move_dir = Vector3.ZERO
			face_dir_override = toward
			if not model.animator.is_upper_busy():
				model.animator.play_upper("angry")
		_:
			move_dir = Vector3.ZERO


func _land_punch() -> void:
	if npc == null or manager.player == null:
		return
	var p := manager.player as HumanoidBody
	if p and p.global_position.distance_to(global_position) < 1.6:
		var dir := (p.global_position - global_position).normalized()
		var imp := ImpactData.create(p.global_position + Vector3(0, 1.35, 0) - dir * 0.2, dir, 60.0 + npc.trait_value("aggression") * 40.0, ImpactData.Source.PUNCH, self)
		p.receive_impact(imp)
		if p is PlayerController:
			(p as PlayerController).stats.health = maxf(0.0, (p as PlayerController).stats.health - 6.0)
