class_name NPCData
extends RefCounted
## Everything that makes one townsperson unique. Lives for the whole game whether or
## not the NPC currently has a body in the world.

const PLAYER_ID := -100

var id: int = 0
var first_name: String = ""
var last_name: String = ""
var age: int = 30
var gender: int = 0
var appearance: CharacterAppearance
var personality: Personality
var emotion := NPCEmotion.new()
var memory := NPCMemory.new()

var needs: Dictionary = {"hunger": 80.0, "energy": 80.0, "social": 70.0, "fun": 70.0, "hygiene": 80.0}
var money: int = 200
var home_food: int = 6               ## meals in the fridge
var home_place: int = -1
var job: Dictionary = {}             ## {place, title, wage, start, end, days:[0..6]}
var job_experience: float = 0.0      ## game hours worked
var hobbies: Array = []
var goals: Array = []
var life_story: String = ""
var wake_hour: float = 7.0
var sleep_hour: float = 23.0
var health: float = 100.0
var skills: Dictionary = {}          ## e.g. {"cooking": 0.3, "fitness": 0.5}

## other id -> {friendship, trust, respect, fear, anger, attraction, jealousy, familiarity, type}
var relationships: Dictionary = {}

# ---- simulation state ----
var pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var at_place: int = -1               ## place currently inside / using
var inside: bool = false             ## hidden inside a building
var lod: int = 2                     ## 0 full, 1 reduced, 2 abstract
var action: String = "idle"
var action_reason: String = ""
var action_target: int = -1          ## place id
var action_spot: int = -1
var action_until: float = 0.0        ## game minutes
var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var day_plan: Array = []             ## [{hour, what, place}]
var plan_day: int = -1
var skip_work_today: bool = false
var late_minutes: float = 0.0
var sick_today: bool = false
var talk_partner: int = -1
var last_decision: float = -9999.0
var last_score_table: Array = []     ## for the inspector: [[action, score, reason], ...]
var reaction: String = ""            ## current event reaction (flee, watch, help, call_police, confront)
var reaction_until: float = 0.0
var reaction_source: Vector3 = Vector3.ZERO
var wanted_by_npcs: int = 0


func full_name() -> String:
	return first_name + " " + last_name


func trait_value(t: String) -> float:
	return personality.get_trait(t)


func has_job() -> bool:
	return not job.is_empty()


func works_today(weekday: int) -> bool:
	return has_job() and weekday in job.get("days", [])


func rel(other: int) -> Dictionary:
	if not relationships.has(other):
		relationships[other] = {"friendship": 0.0, "trust": 0.0, "respect": 0.0, "fear": 0.0, "anger": 0.0,
			"attraction": 0.0, "jealousy": 0.0, "familiarity": 0.0, "type": "stranger"}
	return relationships[other]


func knows(other: int) -> bool:
	return relationships.has(other) and float(relationships[other].familiarity) > 0.15


## Relationship label from the separate values.
func relation_label(other: int) -> String:
	if not relationships.has(other):
		return "Stranger"
	var r: Dictionary = relationships[other]
	if r.type == "partner":
		return "Partner"
	if r.type == "family":
		return "Family"
	var f: float = r.friendship
	if float(r.anger) > 0.6 or f < -0.5:
		return "Enemy"
	if float(r.fear) > 0.6:
		return "Afraid of"
	if f > 0.7:
		return "Best friend"
	if f > 0.35:
		return "Friend"
	if float(r.jealousy) > 0.5:
		return "Rival"
	if float(r.familiarity) > 0.15:
		return "Acquaintance"
	return "Stranger"


func change_rel(other: int, changes: Dictionary) -> void:
	var r := rel(other)
	for k in changes.keys():
		if k == "type":
			r.type = changes[k]
		else:
			r[k] = clampf(float(r.get(k, 0.0)) + float(changes[k]), -1.0 if k == "friendship" else 0.0, 1.0)
	if r.type == "stranger" and float(r.familiarity) > 0.15:
		r.type = "acquaintance"


func friends() -> Array:
	var out: Array = []
	for k in relationships.keys():
		if float(relationships[k].friendship) > 0.35 or relationships[k].type in ["family", "partner"]:
			out.append(k)
	return out


func to_dict() -> Dictionary:
	var rels := {}
	for k in relationships.keys():
		rels[str(k)] = relationships[k].duplicate()
	return {
		"id": id, "first": first_name, "last": last_name, "age": age, "gender": gender,
		"appearance": appearance.to_dict(), "personality": personality.to_dict(), "emotion": emotion.to_dict(),
		"memory": memory.to_array(), "needs": needs.duplicate(), "money": money, "home_food": home_food,
		"home": home_place, "job": job.duplicate(), "exp": job_experience, "hobbies": hobbies.duplicate(), "goals": goals.duplicate(),
		"story": life_story, "wake": wake_hour, "sleep": sleep_hour, "health": health, "skills": skills.duplicate(),
		"rels": rels, "pos": [pos.x, pos.y, pos.z], "yaw": yaw, "at_place": at_place, "inside": inside,
	}


static func from_dict(d: Dictionary) -> NPCData:
	var n := NPCData.new()
	n.id = int(d.id)
	n.first_name = d.first
	n.last_name = d.last
	n.age = int(d.age)
	n.gender = int(d.gender)
	n.appearance = CharacterAppearance.from_dictionary(d.appearance)
	n.personality = Personality.from_dict(d.personality)
	n.emotion.from_dict(d.get("emotion", {}))
	n.memory.from_array(d.get("memory", []))
	for k in d.needs.keys():
		n.needs[k] = float(d.needs[k])
	n.money = int(d.money)
	n.home_food = int(d.get("home_food", 4))
	n.home_place = int(d.home)
	n.job = d.get("job", {})
	n.job_experience = float(d.get("exp", 0.0))
	n.hobbies = d.get("hobbies", [])
	n.goals = d.get("goals", [])
	n.life_story = d.get("story", "")
	n.wake_hour = float(d.get("wake", 7.0))
	n.sleep_hour = float(d.get("sleep", 23.0))
	n.health = float(d.get("health", 100.0))
	n.skills = d.get("skills", {})
	var rels: Dictionary = d.get("rels", {})
	for k in rels.keys():
		n.relationships[int(k)] = rels[k]
	var p: Array = d.get("pos", [0, 0, 0])
	n.pos = Vector3(p[0], p[1], p[2])
	n.yaw = float(d.get("yaw", 0.0))
	n.at_place = int(d.get("at_place", -1))
	n.inside = bool(d.get("inside", false))
	return n
