## LevelData: the list of levels, written as plain data.
##
## DATA-DRIVEN DESIGN
## ------------------
## The levels are not code: they are just dictionaries. The game screen reads
## them and builds the level. This means a designer can add or tune levels
## without touching any game logic. Real games often keep this in JSON files,
## a spreadsheet, or a custom level editor; we use a GDScript constant
## because it needs no file loading and the editor checks the syntax for us.
##
## LEVEL FIELDS
##   name    : shown in the HUD
##   moves   : how many swaps the player gets
##   colors  : number of different pieces (3..6, fewer = easier)
##   layout  : one string per row. "." cell, "i" ice, "I" double ice, "#" hole
##   goals   : see level_goals.gd for the goal types
##   stars   : score needed for 1, 2 and 3 stars (winning always gives >= 1)
##   coins   : reward for winning (plus a bonus for every unused move)
##
## Piece colors: 0 red shell, 1 orange starfish, 2 yellow star,
##               3 green leaf, 4 blue pearl, 5 purple urchin
## (see tile_view.gd for how each color is drawn)
class_name LevelData
extends RefCounted

const LEVELS: Array = [
	{
		"name": "Coral Cove",
		"moves": 20,
		"colors": 4,
		"layout": [
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
		],
		"goals": [{"type": "collect", "color": 0, "amount": 15}],
		"stars": [500, 1500, 2500],
		"coins": 40,
	},
	{
		"name": "Shell Beach",
		"moves": 22,
		"colors": 5,
		"layout": [
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
		],
		"goals": [
			{"type": "collect", "color": 1, "amount": 15},
			{"type": "collect", "color": 4, "amount": 15},
		],
		"stars": [1000, 2500, 4000],
		"coins": 50,
	},
	{
		"name": "Frozen Lagoon",
		"moves": 25,
		"colors": 5,
		"layout": [
			"........",
			"........",
			"..iiii..",
			"..iiii..",
			"..iiii..",
			"..iiii..",
			"........",
			"........",
		],
		"goals": [{"type": "ice"}],
		"stars": [1000, 3000, 5000],
		"coins": 60,
	},
	{
		"name": "Sunken Ship",
		"moves": 25,
		"colors": 5,
		"layout": [
			"##....##",
			"#......#",
			"........",
			"...ii...",
			"...ii...",
			"........",
			"#......#",
			"##....##",
		],
		"goals": [
			{"type": "ice"},
			{"type": "collect", "color": 2, "amount": 20},
		],
		"stars": [1500, 3500, 5500],
		"coins": 70,
	},
	{
		"name": "Kelp Forest",
		"moves": 30,
		"colors": 6,
		"layout": [
			"........",
			".i.ii.i.",
			"........",
			".i.ii.i.",
			"........",
			".i.ii.i.",
			"........",
			"........",
			"........",
		],
		"goals": [
			{"type": "ice"},
			{"type": "score", "amount": 4000},
		],
		"stars": [4000, 6000, 8000],
		"coins": 80,
	},
	{
		"name": "Deep Trench",
		"moves": 30,
		"colors": 6,
		"layout": [
			"...##...",
			"..iiii..",
			".iIIIIi.",
			".iIIIIi.",
			"..iiii..",
			"...##...",
			"........",
			"........",
		],
		"goals": [
			{"type": "ice"},
			{"type": "collect", "color": 5, "amount": 25},
		],
		"stars": [3000, 6000, 9000],
		"coins": 100,
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


## Converts a final score into 1..3 stars using the level's thresholds.
static func stars_for_score(level: Dictionary, score: int) -> int:
	var thresholds: Array = level.get("stars", [0, 0, 0])
	var stars := 1  # finishing the level always earns one star
	for i in range(1, thresholds.size()):
		if score >= int(thresholds[i]):
			stars = i + 1
	return stars
