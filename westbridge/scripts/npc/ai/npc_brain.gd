class_name NPCBrain
extends RefCounted
## Utility-AI decision making + action execution for one NPC.
## Works identically whether the NPC has a body (near the player) or is simulated
## abstractly (far away / inside buildings). The NPCManager moves bodies or abstract
## positions along `n.path`; the brain only decides and applies effects.
##
## Each candidate action gets a score from considerations: needs, personality,
## time of day, weather, money, location, relationships and the daily plan.

const ACTIONS := ["sleep", "work", "eat_home", "eat_out", "coffee", "groceries", "socialize",
	"leisure", "rest", "relax_home", "shelter", "wander", "job_hunt"]

## Need change per game minute while doing an activity.
const EFFECTS := {
	"sleep": {"energy": 0.26, "hunger": 0.04, "hygiene": 0.0},
	"work": {"energy": -0.05, "fun": -0.04, "social": 0.03},
	"eat_home": {"hunger": 2.6, "fun": 0.1},
	"eat_out": {"hunger": 2.2, "social": 0.5, "fun": 0.4},
	"coffee": {"energy": 0.9, "social": 0.3, "fun": 0.2},
	"groceries": {"fun": 0.05},
	"socialize": {"social": 1.3, "fun": 0.5},
	"leisure": {"fun": 1.3, "energy": -0.03},
	"rest": {"energy": 0.3},
	"relax_home": {"fun": 0.5, "hygiene": 1.2, "energy": 0.05},
	"shelter": {},
	"wander": {"fun": 0.25},
	"job_hunt": {},
	"chat": {"social": 1.6, "fun": 0.4},
}
const DECAY := {"hunger": 0.085, "energy": 0.055, "social": 0.045, "fun": 0.05, "hygiene": 0.03}


static func urgency(value: float, curve: float = 1.3) -> float:
	return pow(clampf((100.0 - value) / 100.0, 0.0, 1.0), curve)


static func hour_in(h: float, a: float, b: float) -> bool:
	a = fposmod(a, 24.0)
	b = fposmod(b, 24.0)
	if a <= b:
		return h >= a and h < b
	return h >= a or h < b


# ------------------------------------------------------------------ needs
static func decay_needs(n: NPCData, minutes: float) -> void:
	var soc_mult := 0.6 + n.trait_value("sociability") * 0.8
	for k in DECAY.keys():
		var rate: float = DECAY[k]
		if k == "social":
			rate *= soc_mult
		if k == "fun":
			rate *= 0.7 + n.trait_value("curiosity") * 0.6
		if k == "energy" and n.action == "sleep":
			continue
		n.needs[k] = clampf(float(n.needs[k]) - rate * minutes, 0.0, 100.0)
	# Lunch break: people at work grab something to eat around noon.
	if n.action == "work" and n.action_until > 0.0 and hour_in(GameTime.get_hour_float(), 12.0, 13.0) and float(n.needs.hunger) < 75.0:
		n.needs.hunger = minf(100.0, float(n.needs.hunger) + 1.6 * minutes)
	var eff: Dictionary = EFFECTS.get(n.action, {})
	if n.action == "chat" or (n.action_until > 0.0 and n.path.is_empty()):
		for k in eff.keys():
			n.needs[k] = clampf(float(n.needs[k]) + float(eff[k]) * minutes, 0.0, 100.0)
	n.emotion.update(minutes, n.needs, n.personality)
	n.memory.decay(minutes)


# ------------------------------------------------------------------ daily plan
static func make_day_plan(n: NPCData, m: NPCManager) -> void:
	var day := GameTime.get_day()
	if n.plan_day == day:
		return
	n.plan_day = day
	var rng := m.rng
	var wd := GameTime.get_weekday()
	n.sick_today = rng.randf() < 0.02 + (1.0 - n.health / 100.0) * 0.2
	n.skip_work_today = n.works_today(wd) and rng.randf() < n.trait_value("laziness") * 0.07 + (0.15 if n.emotion.get_e("sad") > 0.6 else 0.0)
	n.late_minutes = maxf(0.0, rng.randfn(n.trait_value("laziness") * 25.0 - 10.0, 12.0))
	n.day_plan = []
	n.day_plan.append({"hour": n.wake_hour + n.late_minutes / 60.0, "what": "Wake up" + (" (overslept)" if n.late_minutes > 20.0 else "")})
	if n.works_today(wd):
		if n.sick_today:
			n.day_plan.append({"hour": n.wake_hour + 0.2, "what": "Call in sick"})
		elif n.skip_work_today:
			n.day_plan.append({"hour": float(n.job.start), "what": "Skip work (not feeling it)"})
		else:
			n.day_plan.append({"hour": float(n.job.start), "what": "Work: %s at %s" % [n.job.title, m.place_name(int(n.job.place))]})
			n.day_plan.append({"hour": float(n.job.end), "what": "Finish work"})
	# Evening meetup with a friend (sociable people plan more).
	var friends := n.friends()
	if not friends.is_empty() and rng.randf() < 0.15 + n.trait_value("sociability") * 0.4:
		var f: int = friends[rng.randi() % friends.size()]
		var spot := m.pick_place(n, ["social"], rng)
		if spot >= 0 and f < m.npcs.size():
			var at := rng.randf_range(17.5, 20.5)
			var entry := {"hour": at, "what": "Meet %s at %s" % [m.npcs[f].first_name, m.place_name(spot)], "meet": f, "place": spot}
			n.day_plan.append(entry)
			var other: NPCData = m.npcs[f]
			if other.plan_day == day:
				other.day_plan.append({"hour": at, "what": "Meet %s at %s" % [n.first_name, m.place_name(spot)], "meet": n.id, "place": spot})
	n.day_plan.append({"hour": n.sleep_hour, "what": "Go to bed"})
	n.day_plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.hour) < float(b.hour))


static func planned_meetup(n: NPCData) -> Dictionary:
	var h := GameTime.get_hour_float()
	for e in n.day_plan:
		if e.has("meet") and h >= float(e.hour) - 0.4 and h < float(e.hour) + 1.2:
			return e
	return {}


# ------------------------------------------------------------------ scoring
static func score_all(n: NPCData, m: NPCManager) -> Array:
	var h := GameTime.get_hour_float()
	var wd := GameTime.get_weekday()
	var raining := m.is_raining()
	var outdoors := not n.inside and not m.place_is_indoor(n.at_place)
	var night := hour_in(h, n.sleep_hour, n.wake_hour + n.late_minutes / 60.0)
	var evening := h >= 17.0 and h < 22.5
	var weekend := wd >= 5
	var lazy := n.trait_value("laziness")
	var out: Array = []
	var add := func(a: String, s: float, why: String) -> void:
		out.append([a, s, why])

	# Sleep
	var e_u := urgency(n.needs.energy, 1.5)
	var s_sleep := maxf(e_u * 1.25, (0.95 if night else 0.05)) * (0.85 + lazy * 0.3)
	if n.works_today(wd) and hour_in(h, float(n.job.start), float(n.job.end)) and n.needs.energy > 12.0:
		s_sleep *= 0.25
	add.call("sleep", s_sleep, "tired (energy %d)" % int(n.needs.energy) if e_u > 0.4 else ("it's bedtime" if night else "a nap"))

	# Work
	if n.works_today(wd) and not n.sick_today and not n.skip_work_today:
		var start: float = float(n.job.start)
		var end: float = float(n.job.end)
		var commute := 0.6
		var in_window := hour_in(h, start - commute, end)
		if in_window:
			var late := hour_in(h, start, end)
			var s_work := 1.0 + n.trait_value("ambition") * 0.15 - lazy * 0.12 + (0.25 if late else 0.0)
			add.call("work", s_work, "shift %02d:00-%02d:00%s" % [int(start), int(end) % 24, " (running late!)" if late and n.at_place != int(n.job.place) else ""])

	# Eating
	var h_u := urgency(n.needs.hunger, 1.3)
	var meal_time := hour_in(h, 7.0, 9.0) or hour_in(h, 12.0, 13.5) or hour_in(h, 18.0, 20.0)
	var s_eat := h_u * 1.15 + (0.18 if meal_time and n.needs.hunger < 70.0 else 0.0) + (0.4 if n.needs.hunger < 15.0 else 0.0)
	var frugal := n.trait_value("caution") * 0.5 + (1.0 - n.trait_value("impulsiveness")) * 0.3
	if n.home_food > 0:
		add.call("eat_home", s_eat * (0.75 + frugal * 0.4 + (0.3 if n.at_place == n.home_place else 0.0)), "hungry (%d), food at home" % int(n.needs.hunger))
	if n.money >= 12:
		add.call("eat_out", s_eat * (0.6 + n.trait_value("sociability") * 0.3 + n.trait_value("impulsiveness") * 0.3 - frugal * 0.2), "hungry (%d), eating out" % int(n.needs.hunger))
	# Coffee
	if n.money >= 5 and hour_in(h, 6.0, 12.0) and n.needs.energy < 75.0:
		add.call("coffee", 0.32 + (0.25 if "coffee" in n.hobbies else 0.0) + urgency(n.needs.energy) * 0.3, "morning coffee")
	# Groceries
	if n.home_food <= 2 and n.money >= 25:
		add.call("groceries", 0.45 + n.trait_value("caution") * 0.15 + (0.2 if n.home_food == 0 else 0.0), "fridge is empty")
	# Social
	var soc_u := urgency(n.needs.social, 1.2)
	var meet := planned_meetup(n)
	var s_soc := soc_u * (0.45 + n.trait_value("sociability") * 0.7) * (1.25 if evening or weekend else 0.8) * (1.0 - n.trait_value("shyness") * 0.3)
	if not meet.is_empty():
		s_soc = maxf(s_soc, 0.9 + n.trait_value("loyalty") * 0.2)
	if raining:
		s_soc *= 0.7
	add.call("socialize", s_soc, ("meeting a friend" if not meet.is_empty() else "lonely (social %d)" % int(n.needs.social)))
	# Leisure / hobbies
	var fun_u := urgency(n.needs.fun, 1.2)
	add.call("leisure", fun_u * (0.45 + n.trait_value("curiosity") * 0.3 + lazy * 0.1) * (0.6 if raining else 1.0), "bored (fun %d) -> %s" % [int(n.needs.fun), n.hobbies[0] if not n.hobbies.is_empty() else "hobby"])
	# Rest on a bench
	if outdoors and n.needs.energy < 45.0:
		add.call("rest", 0.35 + lazy * 0.2, "needs a break")
	# Relax at home
	add.call("relax_home", 0.15 + (0.35 if h >= n.sleep_hour - 2.0 or h < 5.0 else 0.0) + (0.25 if raining and outdoors else 0.0) + urgency(n.needs.hygiene) * 0.4 + n.emotion.get_e("stressed") * 0.2,
		"winding down at home")
	# Rain shelter
	if raining and outdoors:
		add.call("shelter", 0.7 + n.trait_value("caution") * 0.2 - n.trait_value("bravery") * 0.1, "it's raining")
	# Wander / explore
	add.call("wander", 0.07 + n.trait_value("curiosity") * 0.15 + (0.1 if weekend else 0.0), "exploring town")
	# Job hunting
	if not n.has_job() and n.age < 66 and hour_in(h, 9.0, 17.0):
		add.call("job_hunt", (0.55 if n.money < 300 else 0.2) + n.trait_value("ambition") * 0.3 - lazy * 0.15, "needs a job ($%d left)" % n.money)
	# Personality-flavoured noise + inertia for the current action
	for item in out:
		item[1] += m.rng.randf_range(-0.04, 0.04)
		if item[0] == n.action and n.action_until > GameTime.total_minutes:
			item[1] += 0.12
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return out


# ------------------------------------------------------------------ decide & start
static func decide(n: NPCData, m: NPCManager) -> void:
	make_day_plan(n, m)
	var scores := score_all(n, m)
	n.last_score_table = scores.slice(0, 6)
	n.last_decision = GameTime.total_minutes
	for item in scores:
		if _try_start(n, item[0], item[2], m):
			return
	_start(n, "wander", -1, "nothing better to do", 20.0, m)


static func _try_start(n: NPCData, a: String, why: String, m: NPCManager) -> bool:
	var rng := m.rng
	match a:
		"sleep":
			if n.home_place < 0:
				return false
			var dur := clampf((95.0 - float(n.needs.energy)) / 0.26, 30.0, 600.0)
			_start(n, "sleep", n.home_place, why, dur, m)
		"work":
			var end: float = float(n.job.end)
			var mins := fposmod(end - GameTime.get_hour_float(), 24.0) * 60.0
			_start(n, "work", int(n.job.place), why, maxf(mins, 15.0), m)
		"eat_home", "relax_home":
			if n.home_place < 0:
				return false
			_start(n, a, n.home_place, why, 25.0 if a == "eat_home" else rng.randf_range(40.0, 120.0), m)
		"eat_out":
			var p := m.pick_place(n, ["food"], rng, true)
			if p < 0:
				return false
			_start(n, a, p, why + " at " + m.place_name(p), rng.randf_range(30.0, 50.0), m)
		"coffee":
			var p2 := m.pick_place(n, ["coffee"], rng, true)
			if p2 < 0:
				return false
			_start(n, a, p2, why + " at " + m.place_name(p2), rng.randf_range(15.0, 30.0), m)
		"groceries":
			var p3 := m.pick_place(n, ["groceries"], rng, true)
			if p3 < 0:
				return false
			_start(n, a, p3, why + " -> " + m.place_name(p3), 20.0, m)
		"socialize":
			var meet := planned_meetup(n)
			var p4: int = int(meet.place) if not meet.is_empty() else m.pick_place(n, ["social"], rng, true)
			if p4 < 0:
				return false
			_start(n, a, p4, why + " at " + m.place_name(p4), rng.randf_range(40.0, 100.0), m)
		"leisure":
			var tags := m.hobby_tags(n)
			var p5 := m.pick_place(n, tags, rng, true)
			if p5 < 0:
				return false
			_start(n, a, p5, why + " at " + m.place_name(p5), rng.randf_range(45.0, 120.0), m)
		"rest":
			var p6 := m.pick_place(n, ["leisure", "free"], rng, true, 120.0)
			if p6 < 0:
				return false
			_start(n, a, p6, why, 20.0, m)
		"shelter":
			var p7 := m.nearest_place_with(n.pos, ["shelter", "shop", "food", "coffee"], true)
			if p7 < 0:
				return false
			_start(n, a, p7, why + " -> " + m.place_name(p7), 40.0, m)
		"wander":
			_start(n, a, -1, why, rng.randf_range(10.0, 30.0), m)
		"job_hunt":
			var p8 := m.place_with_open_job(n)
			if p8 < 0:
				return false
			_start(n, a, p8, why + " -> asking at " + m.place_name(p8), 30.0, m)
		_:
			return false
	return true


static func _start(n: NPCData, a: String, place_id: int, why: String, duration: float, m: NPCManager) -> void:
	var prev := n.action
	if n.action_spot >= 0 and n.action_target >= 0:
		m.release_spot(n)
	n.action = a
	n.action_reason = why
	n.action_target = place_id
	n.action_spot = -1
	n.action_until = 0.0
	n.talk_partner = -1
	n.set_meta("duration", duration)
	if place_id >= 0 and n.at_place == place_id and (n.inside or n.path.is_empty()):
		begin_activity(n, m)
	else:
		if n.at_place >= 0 and n.inside:
			m.exit_place(n)
		m.route_to(n, place_id)
		if n.path.is_empty() and place_id >= 0:
			m.arrive(n)
	if prev != a:
		EventBus.npc_action_changed.emit(n.id, a, why)


## Called when the NPC reaches its destination.
static func begin_activity(n: NPCData, m: NPCManager) -> void:
	var dur: float = n.get_meta("duration", 30.0)
	n.action_until = GameTime.total_minutes + dur
	match n.action:
		"groceries":
			n.money -= 25
			n.home_food += 8
		"coffee":
			n.money -= 4
		"eat_out":
			var price := 8 + m.place_price(n.action_target) * 5
			n.money -= price
		"eat_home":
			n.home_food = maxi(0, n.home_food - 1)
		"job_hunt":
			m.try_hire(n, n.action_target)
	n.emotion.add("happy", 0.05)


## Called when the activity time is over.
static func finish_activity(n: NPCData, m: NPCManager) -> void:
	match n.action:
		"work":
			var hours: float = float(n.get_meta("duration", 480.0)) / 60.0
			var pay := int(float(n.job.wage) * hours)
			n.money += pay
			n.job_experience += hours
			n.emotion.add("happy", 0.08)
			n.emotion.add("stressed", 0.1)
		"socialize", "eat_out", "coffee":
			n.emotion.add("happy", 0.1)


## Progresses the NPC; `minutes` = game minutes since the last tick.
static func tick(n: NPCData, m: NPCManager, minutes: float) -> void:
	decay_needs(n, minutes)
	if n.reaction != "":
		return
	var now := GameTime.total_minutes
	if n.action_until > 0.0 and now >= n.action_until:
		finish_activity(n, m)
		n.action_until = 0.0
		decide(n, m)
		return
	# Interrupts: urgent needs or weather, re-evaluated every ~30 game minutes.
	if now - n.last_decision > 30.0:
		var scores := score_all(n, m)
		n.last_decision = now
		if not scores.is_empty() and scores[0][0] != n.action and scores[0][1] > 1.0 and (n.action in ["wander", "leisure", "rest", "relax_home", "socialize", "idle"] or scores[0][0] == "shelter" or scores[0][1] > 1.25):
			decide(n, m)
	if n.action == "idle":
		decide(n, m)
