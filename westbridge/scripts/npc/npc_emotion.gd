class_name NPCEmotion
extends RefCounted
## Emotions caused by events and needs. Each value 0..1 relaxes toward a baseline
## that depends on personality and needs. Drives faces, posture, walk speed and choices.

const KEYS := ["happy", "sad", "angry", "fear", "excited", "bored", "embarrassed", "stressed", "relaxed", "irritated", "curious"]

var v: Dictionary = {}


func _init() -> void:
	for k in KEYS:
		v[k] = 0.0
	v.relaxed = 0.4
	v.happy = 0.3


func get_e(k: String) -> float:
	return float(v.get(k, 0.0))


func add(k: String, amount: float) -> void:
	v[k] = clampf(get_e(k) + amount, 0.0, 1.0)


## Baselines from needs (0..100) and personality.
func update(game_minutes: float, needs: Dictionary, p: Personality) -> void:
	var hunger := 1.0 - float(needs.hunger) / 100.0
	var tired := 1.0 - float(needs.energy) / 100.0
	var lonely := 1.0 - float(needs.social) / 100.0
	var bored_n := 1.0 - float(needs.fun) / 100.0
	var base := {
		"happy": clampf(0.45 - hunger * 0.3 - tired * 0.2 - lonely * 0.2 + p.get_trait("friendliness") * 0.15, 0.0, 1.0),
		"sad": clampf(lonely * 0.35 + p.get_trait("fearfulness") * 0.1 - 0.1, 0.0, 1.0),
		"angry": 0.0,
		"fear": 0.0,
		"excited": 0.0,
		"bored": clampf(bored_n * 0.7, 0.0, 1.0),
		"embarrassed": 0.0,
		"stressed": clampf(hunger * 0.25 + tired * 0.25 + p.get_trait("fearfulness") * 0.15, 0.0, 1.0),
		"relaxed": clampf(0.5 - tired * 0.2 - hunger * 0.2 + p.get_trait("patience") * 0.15, 0.0, 1.0),
		"irritated": clampf(hunger * 0.3 + tired * 0.25 + p.get_trait("aggression") * 0.15 - p.get_trait("patience") * 0.15, 0.0, 1.0),
		"curious": p.get_trait("curiosity") * 0.3,
	}
	var k := 1.0 - pow(0.96, game_minutes)   # ~4% per game minute toward baseline
	for key in KEYS:
		v[key] = lerpf(get_e(key), float(base[key]), k)


func dominant() -> String:
	var best := "relaxed"
	var bv := 0.0
	for k in KEYS:
		if get_e(k) > bv:
			bv = get_e(k)
			best = k
	return best


func face_weights() -> Dictionary:
	return {"happy": get_e("happy") + get_e("excited") * 0.5, "sad": get_e("sad"), "angry": maxf(get_e("angry"), get_e("irritated") * 0.6),
		"fear": get_e("fear"), "surprise": get_e("excited") * 0.3, "tired": 0.0}


func to_dict() -> Dictionary:
	return v.duplicate()


func from_dict(d: Dictionary) -> void:
	for k in d.keys():
		v[k] = float(d[k])
