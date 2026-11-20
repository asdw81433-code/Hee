class_name NPCGenerator
extends RefCounted
## Creates the town population: households, jobs, families, friendships, rivals,
## hobbies, goals and a short life story for every person.

const MALE_NAMES := ["Arlo", "Ben", "Caleb", "Dmitri", "Eli", "Felix", "Gus", "Hector", "Ivan", "Jonah", "Kofi", "Leo", "Marco", "Nate", "Omar",
	"Pete", "Quinn", "Raj", "Sam", "Theo", "Ulrich", "Vince", "Wes", "Yusuf", "Zane", "Hank", "Otis", "Ray", "Tomas", "Wade"]
const FEMALE_NAMES := ["Ada", "Bea", "Clara", "Dina", "Esme", "Fay", "Gwen", "Hana", "Iris", "June", "Kira", "Lena", "Mira", "Nora", "Olive",
	"Priya", "Rosa", "Sara", "Tess", "Uma", "Vera", "Wren", "Yara", "Zoe", "Mei", "Ines", "Lucia", "Amara", "Freya", "Rosie"]
const LAST_NAMES := ["Abbott", "Barnes", "Castillo", "Dorsey", "Ellison", "Fairbanks", "Grady", "Holloway", "Ibarra", "Jensen", "Kaplan",
	"Lindqvist", "Mbeki", "Novak", "Okafor", "Petrov", "Quintero", "Rourke", "Sato", "Thorne", "Underwood", "Varga", "Whitlock",
	"Xu", "Yilmaz", "Zielinski", "Moreau", "Haddad", "Brennan", "Kowalski"]
const HOBBIES := ["jogging", "basketball", "reading", "gaming", "music", "cooking", "shopping", "coffee", "people watching", "gardening", "photography", "fitness"]
const GOALS := ["get promoted", "save $5,000", "make new friends", "find a partner", "get fit", "open a business", "buy a car", "move to a bigger home", "learn to cook", "travel the world"]


static func generate(places: Array, count: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var homes: Array = places.filter(func(p: Place) -> bool: return p.type in ["home", "apartment"])
	var job_slots: Array = []
	for p in places:
		for jdef in (p as Place).jobs:
			for s in int(jdef.get("slots", 1)):
				job_slots.append({"place": p.id, "title": jdef.title, "wage": int(jdef.wage), "start": float(jdef.start), "end": float(jdef.end)})
	var npcs: Array = []
	var home_i := 0
	var guard := 0
	while npcs.size() < count and guard < 1000:
		guard += 1
		var home: Place = homes[home_i % homes.size()]
		home_i += 1
		var cap := mini(home.capacity, rng.randi_range(1, 3) if home.type == "home" else rng.randi_range(1, 2))
		var family_name: String = LAST_NAMES[rng.randi() % LAST_NAMES.size()]
		var household: Array = []
		var couple := cap >= 2 and rng.randf() < 0.6
		for k in cap:
			if npcs.size() >= count:
				break
			var n := _make_person(rng, npcs.size(), family_name if (k == 0 or couple or rng.randf() < 0.5) else LAST_NAMES[rng.randi() % LAST_NAMES.size()])
			n.home_place = home.id
			home.residents.append(n.id)
			n.pos = home.inside_pos
			n.inside = true
			n.at_place = home.id
			npcs.append(n)
			household.append(n)
		# Household relationships
		for a in household:
			for b2 in household:
				if a == b2:
					continue
				var same_family: bool = a.last_name == b2.last_name
				if couple and household.size() >= 2 and ((a == household[0] and b2 == household[1]) or (a == household[1] and b2 == household[0])):
					a.change_rel(b2.id, {"friendship": 0.75, "trust": 0.7, "attraction": 0.7, "familiarity": 1.0, "type": "partner"})
				elif same_family:
					a.change_rel(b2.id, {"friendship": 0.6, "trust": 0.6, "familiarity": 1.0, "type": "family"})
				else:
					a.change_rel(b2.id, {"friendship": 0.3, "trust": 0.3, "familiarity": 0.8, "type": "roommate"})
	# Jobs
	job_slots.shuffle()
	for n in npcs:
		var nn := n as NPCData
		if nn.age >= 66 or job_slots.is_empty():
			continue
		if rng.randf() < 0.12:
			continue   # unemployed, looking for work
		var slot: Dictionary = job_slots.pop_back()
		var days := [0, 1, 2, 3, 4]
		if rng.randf() < 0.35:
			days = [rng.randi_range(0, 2), 3, 4, 5, 6]
		slot["days"] = days
		nn.job = slot
		nn.money += rng.randi_range(100, 900)
	# Coworkers, neighbours, random friendships, rivals
	for a in npcs:
		for b2 in npcs:
			var na := a as NPCData
			var nb := b2 as NPCData
			if na.id >= nb.id:
				continue
			var p_know := 0.0
			if na.has_job() and nb.has_job() and int(na.job.place) == int(nb.job.place):
				p_know = 0.85
			elif na.home_place == nb.home_place:
				p_know = 0.0
			else:
				p_know = 0.02 + 0.06 * (na.trait_value("sociability") + nb.trait_value("sociability")) * 0.5
			if rng.randf() < p_know:
				var compat := 1.0 - absf(na.trait_value("friendliness") - nb.trait_value("friendliness")) - absf(na.trait_value("aggression") - nb.trait_value("aggression")) * 0.5
				var f := clampf(rng.randfn(compat * 0.45, 0.2), -0.6, 0.85)
				var kind := "coworker" if p_know > 0.5 else "acquaintance"
				na.change_rel(nb.id, {"friendship": f, "trust": f * 0.7, "familiarity": rng.randf_range(0.3, 0.9), "type": kind})
				nb.change_rel(na.id, {"friendship": f + rng.randf_range(-0.1, 0.1), "trust": f * 0.6, "familiarity": rng.randf_range(0.3, 0.9), "type": kind})
				if f < -0.25:
					na.change_rel(nb.id, {"anger": 0.3, "jealousy": rng.randf() * 0.5})
					nb.change_rel(na.id, {"anger": 0.25})
	for n in npcs:
		(n as NPCData).life_story = _story(n, places, rng)
	return npcs


static func _make_person(rng: RandomNumberGenerator, id: int, last: String) -> NPCData:
	var n := NPCData.new()
	n.id = id
	n.gender = CharacterAppearance.Gender.MALE if rng.randf() < 0.5 else CharacterAppearance.Gender.FEMALE
	n.first_name = (MALE_NAMES if n.gender == 0 else FEMALE_NAMES)[rng.randi() % 30]
	n.last_name = last
	var r := rng.randf()
	n.age = rng.randi_range(18, 29) if r < 0.3 else (rng.randi_range(30, 49) if r < 0.68 else (rng.randi_range(50, 64) if r < 0.88 else rng.randi_range(65, 84)))
	n.personality = Personality.generate(rng)
	n.appearance = CharacterAppearance.new().randomize_look(rng, n.gender, n.age)
	n.money = rng.randi_range(20, 600)
	n.home_food = rng.randi_range(0, 8)
	n.wake_hour = clampf(rng.randfn(6.6 + n.trait_value("laziness") * 1.6, 0.5), 5.0, 10.0)
	n.sleep_hour = clampf(rng.randfn(22.5 + n.trait_value("impulsiveness") * 1.2 - (0.5 if n.age > 60 else 0.0), 0.6), 21.0, 25.5)
	n.needs = {"hunger": rng.randf_range(50, 90), "energy": rng.randf_range(60, 95), "social": rng.randf_range(40, 90), "fun": rng.randf_range(40, 90), "hygiene": rng.randf_range(60, 95)}
	var hob := HOBBIES.duplicate()
	hob.shuffle()
	n.hobbies = hob.slice(0, rng.randi_range(1, 3))
	var g := GOALS.duplicate()
	g.shuffle()
	n.goals = g.slice(0, rng.randi_range(1, 2))
	n.skills = {"cooking": rng.randf(), "fitness": rng.randf(), "social": n.trait_value("sociability"), "work": rng.randf() * 0.5}
	return n


static func _story(n: NPCData, places: Array, rng: RandomNumberGenerator) -> String:
	var home_name := (places[n.home_place] as Place).name if n.home_place >= 0 else "somewhere"
	var job_text := "is currently looking for work"
	if n.has_job():
		job_text = "works as a %s at %s" % [String(n.job.title).to_lower(), (places[int(n.job.place)] as Place).name]
	elif n.age >= 66:
		job_text = "is retired"
	var origin: String = ["was born in Westbridge", "moved here from the coast", "grew up on a farm outside town", "came to Westbridge for a fresh start", "moved here after college"][rng.randi() % 5]
	var traits := n.personality.top_labels(2)
	return "%s (%d) %s, lives at %s and %s. Known as %s and %s. Dreams to %s; enjoys %s." % [
		n.full_name(), n.age, origin, home_name, job_text, String(traits[0]).to_lower(), String(traits[1]).to_lower(),
		n.goals[0], ", ".join(n.hobbies)]
