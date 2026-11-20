extends Node
## 24h world clock. 1 real second = `minutes_per_second` game minutes (default 1),
## so a full day lasts 24 real minutes.

const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

signal minute_passed(total_minutes: float)

var total_minutes: float = 8.0 * 60.0   ## minutes since day 0, 00:00
var minutes_per_second: float = 1.0
var running: bool = false

var _last_hour: int = -1
var _last_day: int = -1
var _minute_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not running:
		return
	advance(delta * minutes_per_second)


## Advances the clock by game minutes and emits hour/day signals.
func advance(minutes: float) -> void:
	total_minutes += minutes
	_minute_accum += minutes
	if _minute_accum >= 1.0:
		_minute_accum = fmod(_minute_accum, 1.0)
		minute_passed.emit(total_minutes)
	var h := get_hour()
	var d := get_day()
	if d != _last_day:
		_last_day = d
		EventBus.day_changed.emit(d)
	if h != _last_hour:
		_last_hour = h
		EventBus.hour_changed.emit(d, h)


func get_day() -> int:
	return int(floor(total_minutes / 1440.0))


func get_minute_of_day() -> float:
	return fposmod(total_minutes, 1440.0)


func get_hour() -> int:
	return int(get_minute_of_day() / 60.0)


func get_hour_float() -> float:
	return get_minute_of_day() / 60.0


func get_weekday() -> int:
	return get_day() % 7


func is_weekend() -> bool:
	return get_weekday() >= 5


func is_night() -> bool:
	var h := get_hour_float()
	return h < 6.0 or h >= 20.0


## 0 at full day, 1 at full night with smooth dusk/dawn.
func get_night_factor() -> float:
	var h := get_hour_float()
	if h >= 7.0 and h <= 18.5:
		return 0.0
	if h > 18.5 and h < 20.5:
		return smoothstep(18.5, 20.5, h)
	if h >= 5.0 and h < 7.0:
		return 1.0 - smoothstep(5.0, 7.0, h)
	return 1.0


func get_clock_string() -> String:
	var m := int(get_minute_of_day())
	return "%s %02d:%02d" % [WEEKDAYS[get_weekday()], m / 60, m % 60]


## Skips forward until `target_hour` (next occurrence). Used by sleeping.
func skip_to_hour(target_hour: float) -> float:
	var now := get_hour_float()
	var diff := target_hour - now
	if diff <= 0.0:
		diff += 24.0
	var minutes := diff * 60.0
	advance(minutes)
	return minutes


func save_state() -> Dictionary:
	return {"total_minutes": total_minutes, "minutes_per_second": minutes_per_second}


func load_state(d: Dictionary) -> void:
	total_minutes = float(d.get("total_minutes", 8.0 * 60.0))
	minutes_per_second = float(d.get("minutes_per_second", 1.0))
	_last_hour = -1
	_last_day = -1
