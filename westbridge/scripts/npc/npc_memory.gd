class_name NPCMemory
extends RefCounted
## What an NPC remembers. Each memory has an importance and a strength that fades
## over (game) time; important memories fade very slowly, trivial ones are forgotten.
## NPCs only remember what they witnessed or were told (`source` = "seen"/"told"/"self").

const MAX_MEMORIES := 40

var entries: Array = []   ## Array of Dictionary


## event: assaulted, helped, robbed, gift, insult, compliment, chat, witnessed_fight,
## worked_with, argued, saw_accident, ...
func add(event: String, who: int, time_min: float, place: String, importance: float, feeling: float, source: String = "self", detail: String = "") -> Dictionary:
	# Repeated small events reinforce the existing memory instead of piling up.
	for m in entries:
		if m.event == event and m.who == who and time_min - float(m.time) < 120.0:
			m.strength = minf(1.0, float(m.strength) + 0.3)
			m.importance = maxf(float(m.importance), importance)
			m.time = time_min
			return m
	var m := {"event": event, "who": who, "time": time_min, "place": place, "importance": clampf(importance, 0.0, 1.0),
		"feeling": clampf(feeling, -1.0, 1.0), "strength": 1.0, "source": source, "detail": detail}
	entries.append(m)
	if entries.size() > MAX_MEMORIES:
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.importance) * float(a.strength) > float(b.importance) * float(b.strength))
		entries.resize(MAX_MEMORIES)
	return m


## Fading: per game hour strength *= decay; importance 1 -> almost permanent.
func decay(game_minutes: float) -> void:
	var hours := game_minutes / 60.0
	for k in range(entries.size() - 1, -1, -1):
		var m: Dictionary = entries[k]
		var rate := lerpf(0.06, 0.0015, float(m.importance))
		m.strength = float(m.strength) * pow(1.0 - rate, hours)
		if float(m.strength) < 0.05:
			entries.remove_at(k)


func about(who: int) -> Array:
	return entries.filter(func(m: Dictionary) -> bool: return int(m.who) == who)


## Net feeling toward someone from memories (-1..1).
func sentiment(who: int) -> float:
	var s := 0.0
	for m in about(who):
		s += float(m.feeling) * float(m.importance) * float(m.strength)
	return clampf(s, -1.0, 1.0)


func most_important(count: int = 3) -> Array:
	var arr := entries.duplicate()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.importance) * float(a.strength) > float(b.importance) * float(b.strength))
	return arr.slice(0, count)


func to_array() -> Array:
	return entries.duplicate(true)


func from_array(a: Array) -> void:
	entries = a.duplicate(true)
