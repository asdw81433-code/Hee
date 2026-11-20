class_name Personality
extends RefCounted
## 18 personality traits (0..1). Generated from five correlated base factors so
## personalities are coherent (e.g. shy people are rarely very sociable).

const TRAITS := ["bravery", "fearfulness", "aggression", "kindness", "selfishness", "honesty",
	"shyness", "confidence", "intelligence", "laziness", "ambition", "friendliness",
	"sociability", "patience", "impulsiveness", "caution", "loyalty", "curiosity"]

const LABELS := {
	"bravery": ["Cowardly", "Brave"], "fearfulness": ["Calm", "Fearful"], "aggression": ["Gentle", "Aggressive"],
	"kindness": ["Cold", "Kind"], "selfishness": ["Generous", "Selfish"], "honesty": ["Dishonest", "Honest"],
	"shyness": ["Outgoing", "Shy"], "confidence": ["Insecure", "Confident"], "intelligence": ["Simple", "Smart"],
	"laziness": ["Hard-working", "Lazy"], "ambition": ["Unambitious", "Ambitious"], "friendliness": ["Unfriendly", "Friendly"],
	"sociability": ["Loner", "Social"], "patience": ["Impatient", "Patient"], "impulsiveness": ["Deliberate", "Impulsive"],
	"caution": ["Reckless", "Careful"], "loyalty": ["Fickle", "Loyal"], "curiosity": ["Incurious", "Curious"],
}

var t: Dictionary = {}


func _init() -> void:
	for k in TRAITS:
		t[k] = 0.5


func get_trait(name: String) -> float:
	return float(t.get(name, 0.5))


func set_trait(name: String, v: float) -> void:
	t[name] = clampf(v, 0.0, 1.0)


static func generate(rng: RandomNumberGenerator) -> Personality:
	var p := Personality.new()
	var e := clampf(rng.randfn(0.5, 0.2), 0.0, 1.0)   # extraversion
	var a := clampf(rng.randfn(0.55, 0.2), 0.0, 1.0)  # agreeableness
	var c := clampf(rng.randfn(0.5, 0.2), 0.0, 1.0)   # conscientiousness
	var n := clampf(rng.randfn(0.45, 0.2), 0.0, 1.0)  # neuroticism
	var o := clampf(rng.randfn(0.5, 0.2), 0.0, 1.0)   # openness
	var j := func(base: float) -> float: return clampf(base + rng.randfn(0.0, 0.1), 0.0, 1.0)
	p.t = {
		"sociability": j.call(e * 0.85 + 0.08),
		"shyness": j.call((1.0 - e) * 0.7 + n * 0.2),
		"confidence": j.call(e * 0.4 + (1.0 - n) * 0.45 + 0.05),
		"friendliness": j.call(a * 0.6 + e * 0.3 + 0.05),
		"kindness": j.call(a * 0.85 + 0.05),
		"selfishness": j.call((1.0 - a) * 0.75 + 0.05),
		"aggression": j.call((1.0 - a) * 0.5 + n * 0.3),
		"honesty": j.call(a * 0.45 + c * 0.4 + 0.05),
		"laziness": j.call((1.0 - c) * 0.85 + 0.05),
		"ambition": j.call(c * 0.5 + e * 0.25 + 0.1),
		"patience": j.call(c * 0.4 + (1.0 - n) * 0.45 + 0.05),
		"impulsiveness": j.call((1.0 - c) * 0.5 + n * 0.2 + e * 0.2),
		"caution": j.call(c * 0.45 + n * 0.35 + 0.05),
		"fearfulness": j.call(n * 0.75 + 0.05),
		"bravery": j.call((1.0 - n) * 0.55 + e * 0.25 + 0.05),
		"intelligence": j.call(o * 0.45 + rng.randf() * 0.45 + 0.05),
		"loyalty": j.call(a * 0.45 + c * 0.4 + 0.05),
		"curiosity": j.call(o * 0.85 + 0.05),
	}
	return p


## The most distinctive traits as readable labels, e.g. ["Very Lazy", "Brave", ...]
func top_labels(count: int = 4) -> Array:
	var items: Array = []
	for k in TRAITS:
		items.append([absf(get_trait(k) - 0.5), k])
	items.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var out: Array = []
	for it in items.slice(0, count):
		var v := get_trait(it[1])
		var lab: String = LABELS[it[1]][1 if v >= 0.5 else 0]
		if absf(v - 0.5) > 0.35:
			lab = "Very " + lab.to_lower()
		out.append(lab)
	return out


func to_dict() -> Dictionary:
	return t.duplicate()


static func from_dict(d: Dictionary) -> Personality:
	var p := Personality.new()
	for k in d.keys():
		p.t[k] = float(d[k])
	return p
