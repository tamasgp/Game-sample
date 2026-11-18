## AquariumCatalog: everything the player can buy for their aquarium.
##
## This is the "meta game": the reason to keep playing puzzle levels.
## Winning levels earns coins, coins buy fish and decorations, and the
## aquarium becomes more alive. Fishdom (and many other puzzle games) use
## exactly this loop:  play -> earn -> spend -> see progress -> play again.
##
## Like level_data.gd, this is pure data. To add a new fish, add a dictionary.
##
## FIELDS
##   id     : unique key, stored in the save file. Never change an id after
##            release, or players lose the item!
##   kind   : "fish" or "decor"
##   name   : shown in the shop
##   price  : cost in coins (0 = free starter item)
##   Fish only:
##     body, fin : colors used to draw it
##     size      : body length in pixels
##     speed     : swimming speed in pixels per second
##     stripes   : number of white stripes on the body
##   Decor only:
##     shape  : how aquarium_decoration.gd draws it
##     x      : horizontal position in the tank, 0.0 (left) .. 1.0 (right)
##     scale  : size multiplier
##     color  : main color
class_name AquariumCatalog
extends RefCounted

const ITEMS: Array = [
	# ----- Fish -----
	{"id": "guppy", "kind": "fish", "name": "Guppy", "price": 0,
		"body": Color(1.0, 0.6, 0.2), "fin": Color(1.0, 0.35, 0.1),
		"size": 46.0, "speed": 70.0, "stripes": 0},
	{"id": "clownfish", "kind": "fish", "name": "Clownfish", "price": 60,
		"body": Color(1.0, 0.45, 0.05), "fin": Color(0.15, 0.1, 0.05),
		"size": 60.0, "speed": 80.0, "stripes": 2},
	{"id": "blue_tang", "kind": "fish", "name": "Blue Tang", "price": 90,
		"body": Color(0.15, 0.35, 0.95), "fin": Color(1.0, 0.85, 0.1),
		"size": 72.0, "speed": 95.0, "stripes": 0},
	{"id": "angelfish", "kind": "fish", "name": "Angelfish", "price": 120,
		"body": Color(0.95, 0.9, 0.5), "fin": Color(0.2, 0.2, 0.25),
		"size": 66.0, "speed": 55.0, "stripes": 3},
	{"id": "pufferfish", "kind": "fish", "name": "Pufferfish", "price": 150,
		"body": Color(0.85, 0.8, 0.45), "fin": Color(0.6, 0.5, 0.25),
		"size": 58.0, "speed": 45.0, "stripes": 0},
	{"id": "goldfish", "kind": "fish", "name": "Royal Goldfish", "price": 220,
		"body": Color(1.0, 0.8, 0.1), "fin": Color(1.0, 0.95, 0.6),
		"size": 80.0, "speed": 60.0, "stripes": 0},

	# ----- Decorations -----
	{"id": "seaweed", "kind": "decor", "name": "Seaweed", "price": 30,
		"shape": "plant", "x": 0.12, "scale": 1.0, "color": Color(0.2, 0.7, 0.3)},
	{"id": "rock", "kind": "decor", "name": "Big Rock", "price": 40,
		"shape": "rock", "x": 0.35, "scale": 1.0, "color": Color(0.45, 0.45, 0.5)},
	{"id": "coral", "kind": "decor", "name": "Pink Coral", "price": 70,
		"shape": "coral", "x": 0.85, "scale": 1.0, "color": Color(1.0, 0.45, 0.6)},
	{"id": "chest", "kind": "decor", "name": "Treasure Chest", "price": 100,
		"shape": "chest", "x": 0.62, "scale": 1.0, "color": Color(0.55, 0.32, 0.12)},
	{"id": "tall_kelp", "kind": "decor", "name": "Tall Kelp", "price": 80,
		"shape": "plant", "x": 0.95, "scale": 1.6, "color": Color(0.35, 0.55, 0.15)},
	{"id": "castle", "kind": "decor", "name": "Sand Castle", "price": 250,
		"shape": "castle", "x": 0.5, "scale": 1.0, "color": Color(0.85, 0.75, 0.5)},
]


static func get_item(id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == id:
			return item
	return {}


## Items that are free and owned from the start.
static func starter_ids() -> Array:
	var ids: Array = []
	for item in ITEMS:
		if int(item["price"]) == 0:
			ids.append(item["id"])
	return ids
