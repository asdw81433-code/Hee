class_name Economy
extends Node
## The player's economy (Priority 2): inventory, cash (Game.player_profile.money),
## bank account, job (apply, shifts, attendance, pay, promotions, getting fired),
## weekly rent and daily bank interest. Saved in the "economy" save section.

signal inventory_changed
signal job_changed
signal bank_changed(balance: int)
signal shift_started(info: Dictionary)
signal shift_finished(result: Dictionary)

const BASE_SLOTS := 12
const STACK := 10
const RENT := 70
const RENT_PERIOD_MIN := 7.0 * 1440.0
const SHIFT_GRACE_EARLY := 0.75     ## hours before the start you may clock in
const SHIFT_GRACE_LATE := 1.5       ## hours after the start you may still clock in
const PROMOTE_AFTER := 5            ## good shifts per promotion
const FIRE_AFTER := 3               ## missed shifts before you're fired

var world: Node
var inventory: Dictionary = {}       ## item id -> count
var bank: int = 0
var debt: int = 0
var job: Dictionary = {}             ## {place, title, wage, start, end, days, rank, shifts, good, misses, hired_min, last_shift_day, last_missed_day}
var experience: int = 0              ## total shifts ever worked
var rent_due_min: float = -1.0
var shift: Dictionary = {}           ## active shift
var history: Array = []              ## last results (newest first)
var totals := {"earned": 0, "spent": 0, "rent_paid": 0}


func _ready() -> void:
	add_to_group("savable")
	EventBus.hour_changed.connect(_on_hour)
	EventBus.day_changed.connect(_on_day)
	if rent_due_min < 0.0:
		rent_due_min = GameTime.total_minutes + RENT_PERIOD_MIN


# ------------------------------------------------------------------ inventory
func capacity() -> int:
	var extra := 0
	for id in inventory.keys():
		extra = maxi(extra, int(ItemDB.get_item(id).get("capacity", 0)))
	return BASE_SLOTS + extra


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func slots_used() -> int:
	var n := 0
	for id in inventory.keys():
		n += int(ceil(float(inventory[id]) / STACK))
	return n


func can_add(id: String, n: int = 1) -> bool:
	var have := count(id)
	var extra_slots := int(ceil(float(have + n) / STACK)) - int(ceil(float(have) / STACK))
	return slots_used() + extra_slots <= capacity()


func add_item(id: String, n: int = 1) -> bool:
	if ItemDB.get_item(id).is_empty() or not can_add(id, n):
		return false
	inventory[id] = count(id) + n
	inventory_changed.emit()
	return true


func remove_item(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	inventory[id] = count(id) - n
	if int(inventory[id]) <= 0:
		inventory.erase(id)
	inventory_changed.emit()
	return true


## Buys one item at a place. Returns "" on success or the reason it failed.
func buy(id: String, p: Place) -> String:
	if p and not p.is_open(GameTime.get_hour_float()):
		return "%s is closed" % p.name
	if not (id in ItemDB.catalog_for(p)):
		return "Not sold here"
	if not can_add(id):
		return "Your bag is full"
	var price := ItemDB.price_at(id, p)
	if not Game.spend_money(price, ItemDB.item_name(id)):
		return "Not enough cash ($%d)" % price
	totals.spent += price
	add_item(id)
	return ""


func sell(id: String, p: Place) -> String:
	if not ItemDB.buys(p, id):
		return "They don't buy that here"
	if not remove_item(id):
		return "You don't have one"
	var price := ItemDB.sell_price(id)
	Game.add_money(price, "sold %s" % ItemDB.item_name(id))
	totals.earned += price
	return ""


## Uses an item from the bag. Returns a message for the player.
func use_item(id: String, player: Node) -> String:
	var it := ItemDB.get_item(id)
	if it.is_empty() or count(id) <= 0:
		return "You don't have that"
	match String(it.kind):
		"consumable":
			remove_item(id)
			if player and player.has_method("restore_stats"):
				player.restore_stats(it.get("effects", {}))
				if player.get("model") and player.model.animator:
					player.model.animator.play_upper(String(it.get("anim", "eat")))
			return "Used %s" % it.name
		"clothing":
			if player and player.get("appearance"):
				var ap: CharacterAppearance = player.appearance
				for k in (it.wear as Dictionary).keys():
					ap.set(k, int(it.wear[k]))
				player.rebuild_appearance(ap)
				Game.player_profile["appearance"] = ap.to_dict()
			return "You put on the %s" % String(it.name).to_lower()
		"gift":
			return "Give it to someone: talk to them and choose Gift"
		"tool":
			return "%s: you'll need this for activities" % it.name
		_:
			if id == "lottery":
				remove_item(id)
				var r := randf()
				var win := 500 if r < 0.005 else (25 if r < 0.06 else (5 if r < 0.25 else 0))
				if win > 0:
					Game.add_money(win, "lottery win!")
					return "You won $%d!" % win
				return "No luck this time"
			if id == "newspaper":
				remove_item(id)
				return "Job ads: %s" % ", ".join(_job_ads())
	return ""


func _job_ads() -> Array:
	var out: Array = []
	if world == null:
		return ["(no world)"]
	for p in world.city.places:
		for o in openings(p):
			out.append("%s at %s ($%d/h)" % [o.title, p.name, o.wage])
			if out.size() >= 3:
				return out
	return out if not out.is_empty() else ["nothing today"]


# ------------------------------------------------------------------ bank
func deposit(amount: int) -> String:
	amount = mini(amount, Game.get_money())
	if amount <= 0:
		return "No cash to deposit"
	if not Game.spend_money(amount, "bank deposit"):
		return "Not enough cash"
	bank += amount
	bank_changed.emit(bank)
	return ""


func withdraw(amount: int) -> String:
	amount = mini(amount, bank)
	if amount <= 0:
		return "Your account is empty"
	bank -= amount
	Game.add_money(amount, "bank withdrawal")
	bank_changed.emit(bank)
	return ""


static func has_bank(p: Place) -> bool:
	return p != null and (p.type in ["bank", "mall", "transit", "gas_station"] or "bank" in p.tags)


# ------------------------------------------------------------------ jobs
## Required total shifts of experience for a job paying `wage` per hour.
static func required_experience(wage: int) -> int:
	return clampi((wage - 17) / 2, 0, 12)


## Job definitions at `p` that still have a free slot.
func openings(p: Place) -> Array:
	var out: Array = []
	if p == null:
		return out
	for jd in p.jobs:
		var taken := 0
		if world and world.npcs:
			for n in world.npcs.npcs:
				if (n as NPCData).has_job() and int(n.job.place) == p.id and String(n.job.title) == String(jd.title):
					taken += 1
		if not job.is_empty() and int(job.place) == p.id and String(job.title) == String(jd.title):
			taken += 1
		if taken < int(jd.get("slots", 1)):
			out.append(jd)
	return out


func apply(p: Place, jd: Dictionary) -> String:
	if not openings(p).any(func(o: Dictionary) -> bool: return o.title == jd.title):
		return "No opening for %s right now" % jd.title
	var need := required_experience(int(jd.wage))
	if experience < need:
		return "They want %d shifts of experience (you have %d)" % [need, experience]
	if not job.is_empty():
		quit_job(true)
	job = {"place": p.id, "place_name": p.name, "title": jd.title, "wage": int(jd.wage), "start": float(jd.start), "end": float(jd.end),
		"days": [0, 1, 2, 3, 4], "rank": 0, "shifts": 0, "good": 0, "misses": 0, "hired_min": GameTime.total_minutes,
		"last_shift_day": -1, "last_missed_day": -1, "mode": shift_mode(String(jd.title))}
	job_changed.emit()
	return ""


func quit_job(silent: bool = false) -> void:
	if job.is_empty():
		return
	if not silent:
		EventBus.toast.emit("You quit your job at %s" % job.place_name)
	job = {}
	job_changed.emit()


func job_title() -> String:
	if job.is_empty():
		return ""
	return ("Senior " if int(job.rank) == 1 else ("Lead " if int(job.rank) >= 2 else "")) + String(job.title)


func wage_now() -> int:
	return int(round(int(job.get("wage", 0)) * pow(1.2, int(job.get("rank", 0)))))


static func shift_mode(title: String) -> String:
	var t := title.to_lower()
	for k in ["courier", "delivery"]:
		if k in t:
			return "delivery"
	for k in ["barista", "cashier", "waiter", "cook", "bartender", "server", "staff", "retail", "vendor", "fishmonger", "ticket", "receptionist",
			"usher", "host", "box office", "baker", "bookseller", "clerk (", "store clerk", "laundry", "attendant"]:
		if k in t:
			return "orders"
	for k in ["analyst", "office", "clerk", "teller", "dispatcher", "teacher", "doctor", "nurse", "controller", "technician", "guide", "projectionist", "foreman", "officer"]:
		if k in t:
			return "typing"
	return "timing"


static func shift_hours(start: float, end: float) -> float:
	var h := end - start
	if h <= 0.0:
		h += 24.0
	return h


## "none" | "off" (not a work day / too early) | "open" (can clock in) | "done" | "missed" | "working"


static func state_text(st: String) -> String:
	return {"none": "no job", "off": "not now", "open": "you can clock in now", "done": "worked today", "missed": "missed today's shift", "working": "working"}.get(st, st)


func shift_state() -> String:
	if job.is_empty():
		return "none"
	if not shift.is_empty():
		return "working"
	var day := GameTime.get_day()
	var hour := GameTime.get_hour_float()
	var start := float(job.start)
	# night shift that started yesterday evening counts for yesterday
	var work_day := day
	var rel := hour - start
	if rel < -12.0:
		rel += 24.0
		work_day -= 1
	elif rel > 12.0:
		rel -= 24.0
		work_day += 1
	if not (posmod(work_day, 7) in job.days):
		return "off"
	if int(job.last_shift_day) == work_day:
		return "done"
	if int(job.last_missed_day) == work_day:
		return "missed"
	if float(job.hired_min) > work_day * 1440.0 + start * 60.0 and rel > SHIFT_GRACE_LATE:
		return "off"            # hired after today's shift started: you start next work day
	if rel >= -SHIFT_GRACE_EARLY and rel <= SHIFT_GRACE_LATE:
		return "open"
	return "off" if rel < 0.0 else "missed"


func start_shift(p: Place) -> String:
	if job.is_empty() or p == null or int(job.place) != p.id:
		return "You don't work here"
	var st := shift_state()
	if st != "open":
		return {"off": "Your shift is %02d:00-%02d:00 on weekdays" % [int(job.start), int(job.end) % 24], "done": "You already worked today",
			"missed": "Too late - you missed today's shift", "working": "You're already working"}.get(st, "Not now")
	var hour := GameTime.get_hour_float()
	var late := hour - float(job.start)
	if late < -12.0:
		late += 24.0
	shift = {"place": p.id, "mode": job.mode, "start_min": GameTime.total_minutes, "late": maxf(0.0, late), "work_day": GameTime.get_day() if late >= -1.0 else GameTime.get_day() + 1}
	if job.mode == "delivery":
		_plan_deliveries(p)
	shift_started.emit(shift.duplicate())
	return ""


func _plan_deliveries(origin: Place) -> void:
	var cands: Array = []
	if world:
		for q in world.city.places:
			var d: float = (q as Place).entry_pos.distance_to(origin.entry_pos)
			if q != origin and d > 50.0 and d < 260.0 and not ((q as Place).type in ["park", "beach", "plaza", "bench", "forest", "field"]):
				cands.append(q.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameTime.total_minutes) + origin.id
	var targets: Array = []
	for k in mini(3, cands.size()):
		targets.append(cands.pop_at(rng.randi_range(0, cands.size() - 1)))
	shift["targets"] = targets
	shift["done"] = 0
	# Route length at a jog (~3 m per game minute at 1 min/s) plus slack.
	var route := 0.0
	var at := origin.entry_pos
	for id in targets:
		var q2: Place = world.city.places[id]
		route += at.distance_to(q2.entry_pos)
		at = q2.entry_pos
	shift["deadline"] = GameTime.total_minutes + route / 3.0 + 45.0
	_point_to_next()


func _point_to_next() -> void:
	if world == null or not world.get("map_screen") or world.map_screen == null:
		return
	var t: Array = shift.get("targets", [])
	if int(shift.done) < t.size():
		var q: Place = world.city.places[t[int(shift.done)]]
		world.map_screen.set_waypoint(q.entry_pos)
		EventBus.toast.emit("Deliver the parcel to %s" % q.name)


func _process(_delta: float) -> void:
	if shift.is_empty() or shift.mode != "delivery" or world == null or world.player == null:
		return
	var t: Array = shift.targets
	if int(shift.done) < t.size():
		var q: Place = world.city.places[t[int(shift.done)]]
		var pp: Vector3 = world.player.global_position
		if Vector2(pp.x - q.entry_pos.x, pp.z - q.entry_pos.z).length() < 6.0:
			shift.done = int(shift.done) + 1
			EventBus.toast.emit("Parcel delivered (%d/%d)" % [shift.done, t.size()])
			if world.map_screen:
				world.map_screen.set_waypoint(null)
			_point_to_next()
	if int(shift.done) >= t.size() or GameTime.total_minutes > float(shift.deadline):
		finish_shift(float(shift.done) / maxf(t.size(), 1), 0)


## Ends the active shift: pay, stats, time skip to the end of the shift, promotion.
func finish_shift(performance: float, tips: int) -> Dictionary:
	if shift.is_empty():
		return {}
	performance = clampf(performance, 0.0, 1.0)
	var hours := shift_hours(float(job.start), float(job.end))
	var worked := maxf(1.0, hours - float(shift.late))
	var pay := int(round(wage_now() * worked * (0.6 + 0.6 * performance))) + tips
	Game.add_money(pay, "%s shift" % job_title())
	totals.earned += pay
	experience += 1
	job.shifts = int(job.shifts) + 1
	job.last_shift_day = int(shift.work_day)
	var good := performance >= 0.65 and float(shift.late) < 0.5
	if good:
		job.good = int(job.good) + 1
		if int(job.good) % 3 == 0 and int(job.misses) > 0:
			job.misses = int(job.misses) - 1
	var result := {"pay": pay, "performance": performance, "hours": worked, "tips": tips, "promoted": false, "title": job_title()}
	if good and int(job.good) >= PROMOTE_AFTER * (int(job.rank) + 1) and int(job.rank) < 2:
		job.rank = int(job.rank) + 1
		result.promoted = true
		result.title = job_title()
	# Skip to the end of the shift (the world simulation catches up), tire the player.
	var end_min := float(job.end) * 60.0
	var now_min := GameTime.get_minute_of_day()
	var to_end := end_min - now_min
	if to_end < 0.0:
		to_end += 1440.0
	if to_end > 0.0 and to_end < 12.0 * 60.0:
		GameTime.advance(to_end)
	if world and world.player:
		world.player.restore_stats({"energy": -worked * 4.0, "hunger": -worked * 5.0})
	history.push_front(result)
	history = history.slice(0, 10)
	shift = {}
	shift_finished.emit(result)
	EventBus.toast.emit("Shift done: +$%d (%d%%)%s" % [pay, int(performance * 100.0), "  PROMOTED to %s!" % result.title if result.promoted else ""])
	return result


func _on_hour(_day: int, _hour: int) -> void:
	if job.is_empty() or not shift.is_empty():
		return
	if shift_state() == "missed":
		var rel := GameTime.get_hour_float() - float(job.start)
		_check_missed(GameTime.get_day() if rel > -12.0 else GameTime.get_day() - 1)


## Records a missed shift for `work_day` if it was a work day the player didn't work.
func _check_missed(work_day: int) -> void:
	if job.is_empty() or not (posmod(work_day, 7) in job.days):
		return
	if int(job.last_missed_day) == work_day or int(job.last_shift_day) == work_day:
		return
	var start_min := work_day * 1440.0 + float(job.start) * 60.0
	if float(job.hired_min) > start_min or GameTime.total_minutes < start_min + SHIFT_GRACE_LATE * 60.0:
		return
	job.last_missed_day = work_day
	job.misses = int(job.misses) + 1
	if int(job.misses) >= FIRE_AFTER:
		EventBus.toast.emit("You were fired from %s for missing shifts" % job.place_name)
		job = {}
	else:
		EventBus.toast.emit("You missed your shift at %s (warning %d/%d)" % [job.place_name, job.misses, FIRE_AFTER - 1])
	job_changed.emit()


func _on_day(day: int) -> void:
	if shift.is_empty():
		_check_missed(day - 1)
	# daily bank interest (0.05 %)
	if bank > 0:
		bank += maxi(0, int(bank * 0.0005))
		bank_changed.emit(bank)
	if debt > 0:
		_pay(debt, "rent arrears")
	if GameTime.total_minutes >= rent_due_min:
		rent_due_min += RENT_PERIOD_MIN
		if not _pay(RENT, "weekly rent"):
			debt += RENT
			EventBus.toast.emit("Rent of $%d is overdue! Debt: $%d" % [RENT, debt])
		else:
			totals.rent_paid += RENT


## Pays from the bank first, then cash. Returns false (paying nothing) if not enough.
func _pay(amount: int, reason: String) -> bool:
	if bank + Game.get_money() < amount:
		return false
	var from_bank := mini(bank, amount)
	bank -= from_bank
	if amount - from_bank > 0:
		Game.spend_money(amount - from_bank, reason)
	if reason == "rent arrears":
		debt = 0
	bank_changed.emit(bank)
	EventBus.toast.emit("Paid $%d %s" % [amount, reason])
	return true


func days_until_rent() -> int:
	return maxi(0, int(ceil((rent_due_min - GameTime.total_minutes) / 1440.0)))


# ------------------------------------------------------------------ save
func save_key() -> String:
	return "economy"


func save_state() -> Dictionary:
	return {"inventory": inventory.duplicate(), "bank": bank, "debt": debt, "job": job.duplicate(true), "experience": experience,
		"rent_due_min": rent_due_min, "history": history.duplicate(true), "totals": totals.duplicate()}


func load_state(d: Dictionary) -> void:
	inventory = {}
	var inv: Dictionary = d.get("inventory", {})
	for k in inv.keys():
		inventory[String(k)] = int(inv[k])
	bank = int(d.get("bank", 0))
	debt = int(d.get("debt", 0))
	job = d.get("job", {})
	for k in ["place", "rank", "shifts", "good", "misses", "last_shift_day", "last_missed_day", "wage"]:
		if job.has(k):
			job[k] = int(job[k])
	if job.has("days"):
		job.days = (job.days as Array).map(func(x: Variant) -> int: return int(x))
	experience = int(d.get("experience", 0))
	rent_due_min = float(d.get("rent_due_min", GameTime.total_minutes + RENT_PERIOD_MIN))
	history = d.get("history", [])
	totals = d.get("totals", totals)
	shift = {}
	inventory_changed.emit()
	job_changed.emit()
	bank_changed.emit(bank)
