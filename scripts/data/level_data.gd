## LevelData: the puzzle levels.
##
## ============================================================================
## HANDCRAFTED + GENERATED LEVELS
## ============================================================================
## Games in this genre have thousands of levels. Designers hand-make them with
## level editors. A sample can't ship that many, so we do both:
##
##   * The first levels (LEVELS below) are handcrafted. They introduce each
##     mechanic one at a time, which is exactly what real games do:
##       level 1 plain matching, 2 weeds, 3 crates, 4 holes, ...
##   * After them, generate_level() creates levels from the level NUMBER as a
##     random seed. The same number always gives the same level (try it!),
##     which is called "deterministic procedural generation".
##
## ============================================================================
## LEVEL FIELDS
## ============================================================================
##   moves   how many swaps the player gets
##   colors  number of different pieces (3..6). Fewer = easier.
##   layout  one string per row:
##             "." cell   "#" hole   "w"/"W" weeds (1/2 layers)
##             "c"/"C" crate (1/2 hit points)
##   goals   see level_goals.gd
##   coins   reward for winning (plus a bonus for leftover moves)
##
## Piece colors (see tile_view.gd for how they're drawn):
##   0 red apple, 1 orange flower, 2 yellow star, 3 green leaf,
##   4 blue drop, 5 purple berry
class_name LevelData
extends RefCounted

const LEVELS: Array = [
	# 1 - Just matching. Few colors, lots of moves: impossible to lose.
	{
		"moves": 20, "colors": 4, "coins": 30,
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
		"goals": [{"type": "collect", "color": 0, "amount": 12}],
	},
	# 2 - Introduces WEEDS.
	{
		"moves": 20, "colors": 4, "coins": 30,
		"layout": [
			"........",
			"........",
			"..wwww..",
			"..wwww..",
			"..wwww..",
			"..wwww..",
			"........",
			"........",
		],
		"goals": [{"type": "weeds"}],
	},
	# 3 - Introduces CRATES.
	{
		"moves": 22, "colors": 5, "coins": 35,
		"layout": [
			"........",
			"........",
			"........",
			"........",
			"ccc..ccc",
			"........",
			"........",
			"........",
		],
		"goals": [{"type": "crates"}],
	},
	# 4 - Holes in the board change how pieces fall.
	{
		"moves": 22, "colors": 5, "coins": 35,
		"layout": [
			"##....##",
			"#......#",
			"........",
			"...##...",
			"...##...",
			"........",
			"#......#",
			"##....##",
		],
		"goals": [
			{"type": "collect", "color": 1, "amount": 15},
			{"type": "collect", "color": 4, "amount": 15},
		],
	},
	# 5 - Weeds AND crates: two goals at once.
	{
		"moves": 25, "colors": 5, "coins": 40,
		"layout": [
			"........",
			".w.ww.w.",
			"........",
			"cc....cc",
			"cc....cc",
			"........",
			".w.ww.w.",
			"........",
		],
		"goals": [{"type": "weeds"}, {"type": "crates"}],
	},
	# 6 - Double weeds need two matches each.
	{
		"moves": 25, "colors": 5, "coins": 40,
		"layout": [
			"........",
			"........",
			".WWWWWW.",
			".W....W.",
			".W....W.",
			".WWWWWW.",
			"........",
			"........",
		],
		"goals": [{"type": "weeds"}],
	},
	# 7 - Crates in the MIDDLE: pieces must slide diagonally around them.
	{
		"moves": 25, "colors": 5, "coins": 45,
		"layout": [
			"........",
			"........",
			"...cc...",
			"..cCCc..",
			"..cCCc..",
			"...cc...",
			"........",
			"........",
		],
		"goals": [{"type": "crates"}, {"type": "collect", "color": 3, "amount": 20}],
	},
	# 8 - Six colors: matches are harder to find.
	{
		"moves": 28, "colors": 6, "coins": 45,
		"layout": [
			"........",
			"ww....ww",
			"ww....ww",
			"........",
			"........",
			"ww....ww",
			"ww....ww",
			"........",
		],
		"goals": [{"type": "weeds"}, {"type": "collect", "color": 5, "amount": 15}],
	},
	# 9 - A wall of tough crates guarding the weeds. The gap in the middle
	#     is important: it's the only way new pieces can reach the bottom!
	{
		"moves": 28, "colors": 5, "coins": 50,
		"layout": [
			"........",
			"........",
			"........",
			"CCC..CCC",
			"wwwwwwww",
			"wwwwwwww",
			"........",
			"........",
		],
		"goals": [{"type": "crates"}, {"type": "weeds"}],
	},
	# 10 - A diamond board.
	{
		"moves": 26, "colors": 5, "coins": 55,
		"layout": [
			"###..###",
			"##....##",
			"#..ww..#",
			"..wWWw..",
			"..wWWw..",
			"#..ww..#",
			"##....##",
			"###..###",
		],
		"goals": [{"type": "weeds"}],
	},
]


## Total levels is unlimited because of the generator. This is just the
## handcrafted count.
static func handcrafted_count() -> int:
	return LEVELS.size()


## Returns level number `index` (0-based).
static func get_level(index: int) -> Dictionary:
	if index < LEVELS.size():
		return LEVELS[index]
	return generate_level(index)


## Builds a level from its number. It gets slowly harder as the number grows.
static func generate_level(index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 7919 + 17   # any formula works; a prime spreads seeds out

	# Difficulty grows with the level number, but stops growing at some point.
	var difficulty := clampf(float(index - LEVELS.size()) / 30.0, 0.0, 1.0)
	var colors := 5 if rng.randf() > difficulty * 0.6 else 6
	var weed_chance := lerpf(0.15, 0.35, difficulty)
	var crate_chance := lerpf(0.05, 0.18, difficulty)

	# Generate the LEFT half of the board and mirror it. Symmetric boards look
	# designed, while fully random ones look messy.
	var rows: Array = []
	for y in 8:
		var left := ""
		for x in 4:
			var roll := rng.randf()
			# Never put crates in the center column (x == 3, mirrored to 4), so
			# new pieces can always fall down to the bottom of the board.
			if y >= 2 and x < 3 and roll < crate_chance:
				left += "C" if rng.randf() < difficulty * 0.5 else "c"
			elif roll < crate_chance + weed_chance:
				left += "W" if rng.randf() < difficulty * 0.4 else "w"
			else:
				left += "."
		var right := ""
		for i in range(3, -1, -1):   # mirror: read the left half backwards
			right += left[i]
		rows.append(left + right)

	# Pick goals based on what the board contains.
	var layout_text := "".join(PackedStringArray(rows))
	var goals: Array = []
	if layout_text.contains("w") or layout_text.contains("W"):
		goals.append({"type": "weeds"})
	if layout_text.contains("c") or layout_text.contains("C"):
		goals.append({"type": "crates"})
	if goals.size() < 2:
		goals.append({"type": "collect", "color": rng.randi_range(0, colors - 1), "amount": 15 + int(difficulty * 15)})

	return {
		"moves": 30 - int(difficulty * 6),
		"colors": colors,
		"coins": 50,
		"layout": rows,
		"goals": goals,
	}
