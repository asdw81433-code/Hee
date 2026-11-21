class_name CharacterAppearance
extends Resource
## Everything that defines how a human looks. Used by the player, NPCs, the
## Character Creator and the (future) NPC Creator. Serializable to Dictionary.

enum Gender { MALE, FEMALE, OTHER }
enum Build { THIN, NORMAL, HEAVY, MUSCULAR }

const HAIR_STYLES := ["Bald", "Short", "Buzz", "Spiky", "Afro", "Long", "Ponytail", "Bun", "Side tufts", "Quiff", "Bob"]
const BEARD_STYLES := ["None", "Goatee", "Full beard", "Chin strap", "Soul patch"]
const MUSTACHE_STYLES := ["None", "Thin", "Thick", "Handlebar"]
const BROW_STYLES := ["Thin", "Normal", "Thick", "Bushy"]
const EYE_SHAPES := ["Round", "Sleepy", "Narrow", "Wide"]
const NOSE_SHAPES := ["Round", "Long", "Button", "Wide"]
const TOPS := ["T-shirt", "Long sleeve", "Button shirt", "Tank top", "Hoodie", "Polo", "Sweater"]
const JACKETS := ["None", "Open jacket", "Blazer", "Vest", "Hi-vis vest", "Puffer", "Police vest"]
const PANTS := ["Trousers", "Jeans", "Shorts", "Skirt", "Cargo"]
const SHOES := ["Sneakers", "Boots", "Dress shoes", "Sandals"]
const HATS := ["None", "Cap", "Beanie", "Fedora", "Bucket hat", "Backwards cap", "Police cap"]
## Uniform pieces are only given by roles, never rolled for random civilians.
const CIVILIAN_JACKETS := 6
const CIVILIAN_HATS := 6
const GLASSES := ["None", "Round", "Square", "Sunglasses"]
const BAGS := ["None", "Backpack", "Shoulder bag"]
const ACCESSORIES := ["None", "Necklace", "Earrings", "Scarf"]

const SKIN_TONES := [
	Color(0.98, 0.84, 0.70), Color(0.95, 0.77, 0.60), Color(0.90, 0.70, 0.52),
	Color(0.80, 0.58, 0.40), Color(0.66, 0.45, 0.30), Color(0.52, 0.34, 0.22),
	Color(0.40, 0.26, 0.17), Color(0.30, 0.19, 0.13),
]
const HAIR_COLORS := [
	Color(0.08, 0.06, 0.05), Color(0.22, 0.14, 0.08), Color(0.40, 0.25, 0.12),
	Color(0.62, 0.38, 0.18), Color(0.82, 0.62, 0.32), Color(0.72, 0.30, 0.14),
	Color(0.55, 0.55, 0.57), Color(0.88, 0.88, 0.86),
]
const EYE_COLORS := [
	Color(0.25, 0.16, 0.08), Color(0.10, 0.08, 0.06), Color(0.20, 0.42, 0.70),
	Color(0.25, 0.50, 0.30), Color(0.45, 0.42, 0.30), Color(0.40, 0.45, 0.50),
]
const CLOTH_COLORS := [
	Color(0.12, 0.13, 0.15), Color(0.92, 0.92, 0.90), Color(0.20, 0.30, 0.55),
	Color(0.12, 0.42, 0.22), Color(0.62, 0.16, 0.14), Color(0.85, 0.62, 0.20),
	Color(0.42, 0.30, 0.22), Color(0.52, 0.52, 0.55), Color(0.30, 0.22, 0.40),
	Color(0.15, 0.50, 0.55), Color(0.88, 0.45, 0.30), Color(0.70, 0.72, 0.40),
	Color(0.35, 0.40, 0.25), Color(0.20, 0.24, 0.32),
]

@export var gender: int = Gender.MALE
@export_range(0.85, 1.15) var height: float = 1.0
@export_range(0.0, 1.0) var weight: float = 0.45
@export var build: int = Build.NORMAL
@export var skin_color: Color = SKIN_TONES[1]

@export_range(0.85, 1.2) var head_width: float = 1.0
@export_range(0.9, 1.2) var head_height: float = 1.0
@export_range(0.65, 1.1) var jaw_width: float = 0.85
@export_range(0.8, 1.35) var eye_size: float = 1.0
@export_range(0.85, 1.15) var eye_spacing: float = 1.0
@export var eye_color: Color = EYE_COLORS[0]
@export var eye_shape: int = 0
@export var brow_style: int = 1
@export var brow_color: Color = HAIR_COLORS[1]
@export_range(0.6, 1.6) var nose_size: float = 1.0
@export var nose_shape: int = 0
@export_range(0.7, 1.3) var mouth_width: float = 1.0

@export var hair_style: int = 1
@export var hair_color: Color = HAIR_COLORS[1]
@export var beard_style: int = 0
@export var mustache_style: int = 0

@export var top: int = 0
@export var top_color: Color = CLOTH_COLORS[3]
@export var jacket: int = 0
@export var jacket_color: Color = CLOTH_COLORS[6]
@export var pants: int = 0
@export var pants_color: Color = CLOTH_COLORS[0]
@export var shoes: int = 0
@export var shoes_color: Color = CLOTH_COLORS[0]
@export var socks_color: Color = CLOTH_COLORS[1]
@export var hat: int = 0
@export var hat_color: Color = CLOTH_COLORS[2]
@export var glasses: int = 0
@export var glasses_color: Color = Color(0.12, 0.12, 0.12)
@export var bag: int = 0
@export var bag_color: Color = CLOTH_COLORS[6]
@export var accessory: int = 0
@export var accessory_color: Color = Color(0.85, 0.72, 0.30)
@export var watch: bool = false
@export var watch_color: Color = Color(0.15, 0.15, 0.17)
@export var belt: bool = true
@export var age: int = 30


const _FIELDS := [
	"gender", "height", "weight", "build", "skin_color", "head_width", "head_height", "jaw_width",
	"eye_size", "eye_spacing", "eye_color", "eye_shape", "brow_style", "brow_color", "nose_size",
	"nose_shape", "mouth_width", "hair_style", "hair_color", "beard_style", "mustache_style", "top",
	"top_color", "jacket", "jacket_color", "pants", "pants_color", "shoes", "shoes_color",
	"socks_color", "hat", "hat_color", "glasses", "glasses_color", "bag", "bag_color", "accessory",
	"accessory_color", "watch", "watch_color", "belt", "age",
]


## Skeleton dimensions derived from body settings.
func body_dims() -> Dictionary:
	var female := gender == Gender.FEMALE
	var muscular := build == Build.MUSCULAR
	return {
		"height": height * (0.95 if female else 1.0),
		"leg": 1.0,
		"arm": 1.0,
		"torso": 1.0,
		"shoulders": (0.9 if female else 1.0) * (1.12 if muscular else 1.0) * (1.0 + weight * 0.12),
		"hips": (1.12 if female else 1.0) * (1.0 + weight * 0.2),
		"neck": 1.0 if not muscular else 0.9,
		"head": 1.0,
		"eye_spacing": eye_spacing,
	}


## Rough body mass in kg (used by physics / balance).
func body_mass() -> float:
	var base := 52.0 + weight * 55.0
	if build == Build.MUSCULAR:
		base += 12.0
	elif build == Build.THIN:
		base -= 6.0
	if gender == Gender.FEMALE:
		base -= 7.0
	return base * height * height


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f in _FIELDS:
		var v: Variant = get(f)
		if v is Color:
			d[f] = [v.r, v.g, v.b]
		else:
			d[f] = v
	return d


func from_dict(d: Dictionary) -> CharacterAppearance:
	for f in _FIELDS:
		if not d.has(f):
			continue
		var cur: Variant = get(f)
		var v: Variant = d[f]
		if cur is Color and v is Array and v.size() >= 3:
			set(f, Color(v[0], v[1], v[2]))
		elif cur is int:
			set(f, int(v))
		elif cur is float:
			set(f, float(v))
		elif cur is bool:
			set(f, bool(v))
	return self


static func from_dictionary(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	return a.from_dict(d)


func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


func _tint(rng: RandomNumberGenerator, c: Color, amount: float = 0.06) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amount, amount), 0, 1),
		clampf(c.g + rng.randf_range(-amount, amount), 0, 1),
		clampf(c.b + rng.randf_range(-amount, amount), 0, 1))


## Random but believable look. `role` tweaks clothing (e.g. "worker", "office").
func randomize_look(rng: RandomNumberGenerator, p_gender: int = -1, p_age: int = -1, role: String = "") -> CharacterAppearance:
	gender = p_gender if p_gender >= 0 else (Gender.MALE if rng.randf() < 0.5 else Gender.FEMALE)
	age = p_age if p_age >= 0 else rng.randi_range(18, 75)
	height = clampf(rng.randfn(1.0, 0.045), 0.88, 1.12)
	weight = clampf(rng.randfn(0.42 + (age - 30) * 0.004, 0.2), 0.0, 1.0)
	var r := rng.randf()
	build = Build.THIN if r < 0.2 else (Build.NORMAL if r < 0.7 else (Build.HEAVY if r < 0.88 else Build.MUSCULAR))
	if build == Build.HEAVY:
		weight = maxf(weight, 0.65)
	elif build == Build.THIN:
		weight = minf(weight, 0.3)
	skin_color = _tint(rng, _pick(rng, SKIN_TONES), 0.03)
	head_width = rng.randf_range(0.88, 1.15)
	head_height = rng.randf_range(0.92, 1.18)
	jaw_width = rng.randf_range(0.68, 1.05)
	eye_size = rng.randf_range(0.85, 1.3)
	eye_spacing = rng.randf_range(0.88, 1.12)
	eye_color = _pick(rng, EYE_COLORS)
	eye_shape = rng.randi() % EYE_SHAPES.size()
	nose_size = rng.randf_range(0.7, 1.5)
	nose_shape = rng.randi() % NOSE_SHAPES.size()
	mouth_width = rng.randf_range(0.75, 1.25)
	# Hair darkens/greys with age.
	hair_color = _pick(rng, HAIR_COLORS)
	if age > 55 and rng.randf() < 0.7:
		hair_color = HAIR_COLORS[6] if rng.randf() < 0.5 else HAIR_COLORS[7]
	brow_color = hair_color.darkened(0.15)
	brow_style = rng.randi() % BROW_STYLES.size()
	if gender == Gender.FEMALE:
		hair_style = _pick(rng, [5, 6, 7, 10, 1, 4, 5, 10])
		beard_style = 0
		mustache_style = 0
		brow_style = mini(brow_style, 1)
	else:
		hair_style = _pick(rng, [0, 1, 2, 3, 4, 8, 9, 1, 2])
		if age > 50 and rng.randf() < 0.45:
			hair_style = _pick(rng, [0, 8])
		beard_style = rng.randi() % BEARD_STYLES.size() if rng.randf() < 0.4 else 0
		mustache_style = rng.randi() % MUSTACHE_STYLES.size() if rng.randf() < 0.3 else 0
	# Clothing
	top = rng.randi() % TOPS.size()
	top_color = _tint(rng, _pick(rng, CLOTH_COLORS))
	jacket = rng.randi() % CIVILIAN_JACKETS if rng.randf() < 0.45 else 0
	if jacket == 4:
		jacket = 1
	jacket_color = _tint(rng, _pick(rng, CLOTH_COLORS))
	pants = rng.randi() % PANTS.size()
	if gender != Gender.FEMALE and pants == 3:
		pants = 1
	pants_color = _tint(rng, _pick(rng, [CLOTH_COLORS[0], CLOTH_COLORS[2], CLOTH_COLORS[6], CLOTH_COLORS[7], CLOTH_COLORS[13], CLOTH_COLORS[12]]))
	shoes = rng.randi() % SHOES.size()
	shoes_color = _pick(rng, [CLOTH_COLORS[0], CLOTH_COLORS[1], CLOTH_COLORS[6], CLOTH_COLORS[7]])
	socks_color = _pick(rng, CLOTH_COLORS)
	hat = rng.randi() % CIVILIAN_HATS if rng.randf() < 0.3 else 0
	hat_color = _tint(rng, _pick(rng, CLOTH_COLORS))
	glasses = rng.randi() % GLASSES.size() if rng.randf() < (0.25 + age * 0.004) else 0
	bag = rng.randi() % BAGS.size() if rng.randf() < 0.25 else 0
	bag_color = _tint(rng, _pick(rng, CLOTH_COLORS))
	accessory = rng.randi() % ACCESSORIES.size() if rng.randf() < 0.3 else 0
	watch = rng.randf() < 0.4
	belt = pants != 3 and rng.randf() < 0.7
	match role:
		"worker":
			jacket = 4
			jacket_color = Color(0.95, 0.65, 0.10)
			pants = 4
			shoes = 1
		"office":
			top = 2
			jacket = 2 if rng.randf() < 0.6 else 0
			pants = 0 if gender == Gender.MALE or rng.randf() < 0.5 else 3
			shoes = 2
		"police":
			top = 2
			top_color = Color(0.18, 0.26, 0.48)
			jacket = 6
			jacket_color = Color(0.13, 0.14, 0.17)
			pants = 0
			pants_color = Color(0.12, 0.15, 0.28)
			hat = 6
			hat_color = Color(0.13, 0.17, 0.32)
			shoes = 1
		"cafe", "shop":
			top = 5
			jacket = 0
	return self
