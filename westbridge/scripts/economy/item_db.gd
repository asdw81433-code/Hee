class_name ItemDB
extends RefCounted
## Every item the player can buy, carry, use, give or sell, and which places sell what.
##
## effects: changes to player stats when used (hunger/energy/health/stamina, 0..100).
## kind:    consumable | gift | clothing | tool | misc
## Prices are base prices; a place's price level (0 cheap .. 3 luxury) scales them.

const ITEMS := {
	# --- food
	"apple": {"name": "Apple", "kind": "consumable", "cat": "food", "price": 1, "effects": {"hunger": 8, "health": 1}, "anim": "eat"},
	"banana": {"name": "Banana", "kind": "consumable", "cat": "food", "price": 1, "effects": {"hunger": 9, "energy": 2}, "anim": "eat"},
	"chips": {"name": "Bag of chips", "kind": "consumable", "cat": "food", "price": 2, "effects": {"hunger": 12}, "anim": "eat"},
	"chocolate": {"name": "Chocolate bar", "kind": "consumable", "cat": "food", "price": 2, "effects": {"hunger": 10, "energy": 5}, "anim": "eat"},
	"energy_bar": {"name": "Energy bar", "kind": "consumable", "cat": "food", "price": 3, "effects": {"hunger": 14, "stamina": 25}, "anim": "eat"},
	"sandwich": {"name": "Sandwich", "kind": "consumable", "cat": "food", "price": 6, "effects": {"hunger": 32}, "anim": "eat"},
	"pizza_slice": {"name": "Pizza slice", "kind": "consumable", "cat": "food", "price": 5, "effects": {"hunger": 26, "energy": 3}, "anim": "eat"},
	"burger": {"name": "Burger & fries", "kind": "consumable", "cat": "food", "price": 9, "effects": {"hunger": 48, "energy": 4, "health": -1}, "anim": "eat"},
	"fish_taco": {"name": "Fish tacos", "kind": "consumable", "cat": "food", "price": 7, "effects": {"hunger": 36}, "anim": "eat"},
	"salad": {"name": "Garden salad", "kind": "consumable", "cat": "food", "price": 8, "effects": {"hunger": 28, "health": 4}, "anim": "eat"},
	"pastry": {"name": "Croissant", "kind": "consumable", "cat": "food", "price": 3, "effects": {"hunger": 14, "energy": 3}, "anim": "eat"},
	"ice_cream": {"name": "Ice cream", "kind": "consumable", "cat": "food", "price": 4, "effects": {"hunger": 10, "energy": 3}, "anim": "eat"},
	"steak_dinner": {"name": "Steak dinner", "kind": "consumable", "cat": "food", "price": 24, "effects": {"hunger": 75, "energy": 8, "health": 3}, "anim": "eat"},
	"fresh_fish": {"name": "Fresh fish (cooked)", "kind": "consumable", "cat": "food", "price": 9, "effects": {"hunger": 40, "health": 3}, "anim": "eat"},
	"groceries": {"name": "Bag of groceries", "kind": "consumable", "cat": "food", "price": 16, "effects": {"hunger": 60, "energy": 5}, "anim": "eat"},
	"popcorn": {"name": "Popcorn", "kind": "consumable", "cat": "food", "price": 5, "effects": {"hunger": 12}, "anim": "eat"},
	# --- drinks
	"water": {"name": "Bottle of water", "kind": "consumable", "cat": "drink", "price": 1, "effects": {"stamina": 15, "energy": 2}, "anim": "drink"},
	"soda": {"name": "Soda", "kind": "consumable", "cat": "drink", "price": 2, "effects": {"energy": 8, "hunger": 4}, "anim": "drink"},
	"coffee": {"name": "Coffee", "kind": "consumable", "cat": "drink", "price": 4, "effects": {"energy": 22}, "anim": "drink"},
	"espresso": {"name": "Espresso", "kind": "consumable", "cat": "drink", "price": 3, "effects": {"energy": 28, "stamina": -5}, "anim": "drink"},
	"tea": {"name": "Iced tea", "kind": "consumable", "cat": "drink", "price": 3, "effects": {"energy": 12, "stamina": 5}, "anim": "drink"},
	"juice": {"name": "Orange juice", "kind": "consumable", "cat": "drink", "price": 3, "effects": {"energy": 6, "health": 2}, "anim": "drink"},
	"smoothie": {"name": "Fruit smoothie", "kind": "consumable", "cat": "drink", "price": 6, "effects": {"energy": 10, "hunger": 12, "health": 2}, "anim": "drink"},
	"energy_drink": {"name": "Energy drink", "kind": "consumable", "cat": "drink", "price": 4, "effects": {"energy": 35, "health": -2}, "anim": "drink"},
	"mocktail": {"name": "Neon mocktail", "kind": "consumable", "cat": "drink", "price": 8, "effects": {"energy": 6, "stamina": 10}, "anim": "drink"},
	# --- medical
	"bandage": {"name": "Bandage", "kind": "consumable", "cat": "medical", "price": 5, "effects": {"health": 15}, "anim": "pick_up"},
	"painkillers": {"name": "Painkillers", "kind": "consumable", "cat": "medical", "price": 9, "effects": {"health": 30, "energy": -4}, "anim": "eat"},
	"first_aid": {"name": "First aid kit", "kind": "consumable", "cat": "medical", "price": 25, "effects": {"health": 70}, "anim": "pick_up"},
	# --- gifts (give to NPCs from the talk menu)
	"flowers": {"name": "Bunch of flowers", "kind": "gift", "cat": "gift", "price": 12, "gift": 0.16},
	"chocolate_box": {"name": "Box of chocolates", "kind": "gift", "cat": "gift", "price": 10, "gift": 0.13},
	"teddy": {"name": "Teddy bear", "kind": "gift", "cat": "gift", "price": 18, "gift": 0.2},
	# --- clothing (changes your outfit when used)
	"sunglasses": {"name": "Sunglasses", "kind": "clothing", "cat": "clothes", "price": 25, "wear": {"glasses": 3}},
	"cap": {"name": "Baseball cap", "kind": "clothing", "cat": "clothes", "price": 18, "wear": {"hat": 1}},
	"beanie": {"name": "Beanie", "kind": "clothing", "cat": "clothes", "price": 15, "wear": {"hat": 2}},
	"hoodie": {"name": "Hoodie", "kind": "clothing", "cat": "clothes", "price": 38, "wear": {"top": 4}},
	"polo": {"name": "Polo shirt", "kind": "clothing", "cat": "clothes", "price": 28, "wear": {"top": 5}},
	"blazer": {"name": "Blazer", "kind": "clothing", "cat": "clothes", "price": 90, "wear": {"jacket": 2}},
	"puffer": {"name": "Puffer jacket", "kind": "clothing", "cat": "clothes", "price": 75, "wear": {"jacket": 5}},
	"sneakers": {"name": "Sneakers", "kind": "clothing", "cat": "clothes", "price": 45, "wear": {"shoes": 0}},
	"boots": {"name": "Work boots", "kind": "clothing", "cat": "clothes", "price": 55, "wear": {"shoes": 1}},
	"backpack": {"name": "Backpack (+10 slots)", "kind": "clothing", "cat": "clothes", "price": 60, "wear": {"bag": 1}, "capacity": 10},
	# --- tools & misc
	"flashlight": {"name": "Flashlight", "kind": "tool", "cat": "tool", "price": 15},
	"fishing_rod": {"name": "Fishing rod", "kind": "tool", "cat": "tool", "price": 45},
	"newspaper": {"name": "Westbridge Gazette", "kind": "misc", "cat": "misc", "price": 2, "desc": "job ads"},
	"lottery": {"name": "Scratch lottery ticket", "kind": "misc", "cat": "misc", "price": 3, "desc": "scratch to win up to $500"},
	"scrap": {"name": "Scrap metal", "kind": "misc", "cat": "misc", "price": 6, "desc": "sell at a scrapyard"},
}

## What each kind of place sells (place.type first, then tags).
const BY_TYPE := {
	"store": ["groceries", "apple", "banana", "chips", "chocolate", "sandwich", "water", "soda", "juice", "energy_drink", "bandage", "newspaper", "lottery"],
	"gas_station": ["chips", "chocolate", "energy_bar", "sandwich", "water", "soda", "coffee", "energy_drink", "bandage", "flashlight", "newspaper", "lottery"],
	"cafe": ["coffee", "espresso", "tea", "pastry", "sandwich", "smoothie", "juice"],
	"diner": ["burger", "sandwich", "salad", "pizza_slice", "coffee", "soda", "ice_cream"],
	"restaurant": ["steak_dinner", "salad", "burger", "fish_taco", "juice", "soda"],
	"food": ["ice_cream", "smoothie", "soda", "water"],
	"food_stand": ["fish_taco", "burger", "soda", "water"],
	"bar": ["mocktail", "soda", "chips", "burger"],
	"club": ["mocktail", "energy_drink", "soda", "water"],
	"cinema": ["popcorn", "soda", "chocolate"],
	"arcade": ["pizza_slice", "soda", "chips"],
	"arena": ["burger", "popcorn", "soda", "water"],
	"fun_park": ["ice_cream", "popcorn", "soda", "teddy"],
	"mall": ["hoodie", "polo", "blazer", "puffer", "sneakers", "boots", "cap", "beanie", "sunglasses", "backpack", "flowers", "chocolate_box", "teddy", "pizza_slice", "coffee"],
	"shop": ["cap", "sunglasses", "water", "soda", "ice_cream", "fishing_rod", "flowers"],
	"market": ["apple", "banana", "groceries", "flowers", "pastry", "juice"],
	"fish_market": ["fresh_fish", "fish_taco", "water"],
	"farm": ["apple", "banana", "groceries", "juice"],
	"orchard": ["apple", "juice"],
	"winery": ["juice", "salad", "steak_dinner"],
	"hospital": ["bandage", "painkillers", "first_aid", "water", "juice"],
	"hotel": ["coffee", "steak_dinner", "salad", "juice"],
	"marina": ["fishing_rod", "water", "soda", "sunglasses"],
	"scrapyard": ["boots", "flashlight"],
	"campground": ["water", "energy_bar", "flashlight"],
	"transit": ["coffee", "newspaper", "water", "sandwich"],
	"church": [],
}
## Items a place will buy back (40 % of the base price).
const BUYS := {"scrapyard": ["scrap"], "mall": ["hoodie", "polo", "blazer", "puffer", "sneakers", "boots", "cap", "beanie", "sunglasses", "backpack"], "fish_market": ["fresh_fish"]}
const PRICE_MULT := [0.8, 1.0, 1.35, 1.8]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func item_name(id: String) -> String:
	return String(ITEMS.get(id, {}).get("name", id))


static func catalog_for(p: Place) -> Array:
	if p == null:
		return []
	if BY_TYPE.has(p.type):
		return BY_TYPE[p.type]
	# Tag fallback only for businesses (homes are tagged "food" too).
	if p.jobs.is_empty() or p.type in ["home", "apartment", "barracks"]:
		return []
	if "coffee" in p.tags:
		return BY_TYPE["cafe"]
	if "groceries" in p.tags:
		return BY_TYPE["store"]
	if "food" in p.tags:
		return BY_TYPE["diner"]
	if "shop" in p.tags:
		return BY_TYPE["shop"]
	return []


static func price_at(id: String, p: Place) -> int:
	var base := int(ITEMS.get(id, {}).get("price", 0))
	var lvl := clampi(p.price_level if p else 1, 0, 3)
	return maxi(1, int(round(base * PRICE_MULT[lvl])))


static func buys(p: Place, id: String) -> bool:
	return p != null and id in BUYS.get(p.type, [])


static func sell_price(id: String) -> int:
	return maxi(1, int(int(ITEMS.get(id, {}).get("price", 0)) * 0.4))
