## A tiny unit test runner for the pure-logic classes (no plugins needed).
##
## HOW TO RUN (from the project folder):
##     godot --headless --script res://tests/test_runner.gd
##
## (Open the project in the Godot editor at least once first, so Godot builds
## its list of `class_name` scripts. Or run `godot --headless --import`.)
##
## WHY TEST GAME CODE?
## Match-3 rules have lots of edge cases (L shapes, chain reactions, holes...).
## Clicking through the game to check each one is slow. These tests build exact
## board situations and check the result in milliseconds. When you change the
## rules, run them again to make sure you didn't break anything.
##
## For bigger projects, look at the GUT or gdUnit4 testing add-ons.
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	# Every method whose name starts with "test_" is run automatically.
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			call(method_name)
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: ", message)


## Helper: an 8x8 board with a fixed seed.
func make_board(colors: int = 5, layout: Array = []) -> BoardModel:
	if layout.is_empty():
		for i in 8:
			layout.append("........")
	var model := BoardModel.new()
	model.setup(layout, colors, 1234)
	return model


# ---------------------------------------------------------------------------
# Board generation
# ---------------------------------------------------------------------------

func test_new_board_has_no_matches_and_a_move() -> void:
	# Try many seeds: generation must ALWAYS satisfy both rules.
	for seed_value in 50:
		var layout: Array = []
		for i in 8:
			layout.append("........")
		var model := BoardModel.new()
		model.setup(layout, 5, seed_value)
		check(model.find_matches().is_empty(), "seed %d: board starts with a match" % seed_value)
		check(not model.find_possible_move().is_empty(), "seed %d: board has no possible move" % seed_value)


func test_holes_stay_empty() -> void:
	var model := make_board(5, ["#......#", "........", "........", "........"])
	check(not model.is_playable(Vector2i(0, 0)), "hole should not be playable")
	check(model.get_piece(Vector2i(0, 0)) == null, "hole should have no piece")
	check(model.get_piece(Vector2i(1, 0)) != null, "normal cell should have a piece")


func test_ice_is_counted() -> void:
	var model := make_board(5, ["..i.....", "...I....", "........"])
	check(model.total_ice() == 3, "expected 3 ice layers, got %d" % model.total_ice())


# ---------------------------------------------------------------------------
# Swapping and matching
# ---------------------------------------------------------------------------

func test_invalid_swap_is_rejected() -> void:
	var model := make_board(5, ["....", "...."])
	model.load_colors(["0101", "2323"])
	check(not model.is_valid_swap(Vector2i(0, 0), Vector2i(1, 0)), "swap without a match must be invalid")
	check(not model.is_valid_swap(Vector2i(0, 0), Vector2i(2, 0)), "non-adjacent swap must be invalid")


func test_simple_match_of_three() -> void:
	var model := make_board(5, ["....", "....", "...."])
	model.load_colors([
		"0012",
		"2301",
		"3123",
	])
	# Swapping (2,0) with (2,1) brings the 0 from row 1 up: row 0 becomes 000.
	check(model.is_valid_swap(Vector2i(2, 0), Vector2i(2, 1)), "swap should be valid")
	model.swap(Vector2i(2, 0), Vector2i(2, 1))
	var result := model.resolve_matches([Vector2i(2, 0), Vector2i(2, 1)])
	check(result.removed.size() == 3, "expected 3 removed, got %d" % result.removed.size())
	check(result.created.is_empty(), "a match of 3 creates no special")
	check(result.score == 3 * BoardModel.POINTS_PER_PIECE, "unexpected score %d" % result.score)


func test_match_of_four_creates_rocket() -> void:
	var model := make_board(5, ["......", "......"])
	model.load_colors([
		"000012",
		"123423",
	])
	# Row 0 already holds a match of 4, so we can resolve it directly.
	# Passing (1, 0) as the "preferred" cell pretends the player dragged it there.
	var result := model.resolve_matches([Vector2i(1, 0)])
	check(result.created.size() == 1, "match of 4 should create one special")
	if result.created.size() == 1:
		var piece: BoardModel.Piece = result.created[0]["piece"]
		check(piece.special == BoardModel.Special.ROCKET_H, "horizontal 4 should make ROCKET_H")
		check(result.created[0]["cell"] == Vector2i(1, 0), "special should appear at the preferred cell")


func test_match_of_five_creates_rainbow() -> void:
	var model := make_board(5, ["......", "......"])
	model.load_colors(["000001", "123423"])
	var result := model.resolve_matches([])
	check(result.created.size() == 1, "match of 5 should create one special")
	if result.created.size() == 1:
		var piece: BoardModel.Piece = result.created[0]["piece"]
		check(piece.special == BoardModel.Special.RAINBOW, "5 in a row should make a RAINBOW")


func test_l_shape_creates_bomb() -> void:
	var model := make_board(5, ["....", "....", "...."])
	model.load_colors([
		"0001",
		"0232",
		"0313",
	])
	var result := model.resolve_matches([])
	check(result.removed.size() == 5, "L shape should remove 5, got %d" % result.removed.size())
	check(result.created.size() == 1 and result.created[0]["piece"].special == BoardModel.Special.BOMB,
			"L shape should create a BOMB")


# ---------------------------------------------------------------------------
# Specials
# ---------------------------------------------------------------------------

func test_rocket_clears_row() -> void:
	var model := make_board(5, ["......", "......", "......"])
	model.load_colors(["012301", "230123", "301230"])
	var rocket := model.get_piece(Vector2i(2, 1))
	rocket.special = BoardModel.Special.ROCKET_H
	var forced := [{"cell": Vector2i(2, 1), "target_color": -1}]
	var result := model.resolve_matches([], forced)
	check(result.removed.size() == 6, "rocket should clear the whole row of 6, got %d" % result.removed.size())


func test_rainbow_clears_one_color() -> void:
	var model := make_board(5, ["....", "...."])
	model.load_colors(["R101", "2121"])
	# Swap the rainbow with the "1" next to it.
	model.swap(Vector2i(0, 0), Vector2i(1, 0))
	var forced := model.special_swap_activations(Vector2i(0, 0), Vector2i(1, 0))
	var result := model.resolve_matches([], forced)
	# Four 1s plus the rainbow itself.
	check(result.removed.size() == 5, "rainbow should remove all 1s + itself, got %d" % result.removed.size())


func test_chain_reaction() -> void:
	var model := make_board(5, ["...", "...", "..."])
	model.load_colors(["012", "120", "201"])
	model.get_piece(Vector2i(0, 0)).special = BoardModel.Special.ROCKET_H  # hits row 0
	model.get_piece(Vector2i(2, 0)).special = BoardModel.Special.ROCKET_V  # hit by it -> column 2
	var result := model.resolve_matches([], [{"cell": Vector2i(0, 0), "target_color": -1}])
	check(result.activated.size() == 2, "both rockets should fire, got %d" % result.activated.size())
	check(result.removed.size() == 5, "row 0 + column 2 = 5 cells, got %d" % result.removed.size())


# ---------------------------------------------------------------------------
# Gravity and shuffling
# ---------------------------------------------------------------------------

func test_gravity_fills_every_cell() -> void:
	var model := make_board(5, ["#...", "....", "....", "...."])
	model.load_colors(["-0--", "-1-2", "0-3-", "1-0-"])
	var gravity := model.apply_gravity()
	for x in model.width:
		for y in model.height:
			var cell := Vector2i(x, y)
			if model.is_playable(cell):
				check(model.get_piece(cell) != null, "cell %s should be filled" % cell)
	check(not gravity["moves"].is_empty(), "some pieces should have fallen")
	check(not gravity["spawns"].is_empty(), "some pieces should have spawned")


func test_ice_breaks_under_match() -> void:
	var model := make_board(5, ["iii.", "...."])
	model.load_colors(["0001", "2323"])
	var result := model.resolve_matches([])
	check(result.ice_hits.size() == 3, "3 ice cells should crack, got %d" % result.ice_hits.size())
	check(model.total_ice() == 0, "no ice should be left")


func test_shuffle_produces_playable_board() -> void:
	var model := make_board(5)
	model.shuffle()
	check(model.find_matches().is_empty(), "shuffled board should have no matches")
	check(not model.find_possible_move().is_empty(), "shuffled board should have a move")


# ---------------------------------------------------------------------------
# Goals and stars
# ---------------------------------------------------------------------------

func test_collect_goal() -> void:
	var goals := LevelGoals.new()
	goals.setup([{"type": "collect", "color": 2, "amount": 2}], 0)
	check(not goals.is_complete(), "goal should not start complete")
	var fake_removed := [
		{"piece": BoardModel.Piece.new(1, 2, 0), "cell": Vector2i.ZERO},
		{"piece": BoardModel.Piece.new(2, 3, 0), "cell": Vector2i.ZERO},
		{"piece": BoardModel.Piece.new(3, 2, 0), "cell": Vector2i.ZERO},
	]
	goals.on_pieces_removed(fake_removed)
	check(goals.is_complete(), "two pieces of color 2 should complete the goal")


func test_stars_for_score() -> void:
	var level := {"stars": [100, 200, 300]}
	check(LevelData.stars_for_score(level, 0) == 1, "winning gives at least 1 star")
	check(LevelData.stars_for_score(level, 250) == 2, "250 should give 2 stars")
	check(LevelData.stars_for_score(level, 999) == 3, "999 should give 3 stars")
