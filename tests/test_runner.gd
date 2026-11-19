## A tiny unit test runner for the pure-logic classes (no plugins needed).
##
## HOW TO RUN (from the project folder):
##     godot --headless --import                          (once)
##     godot --headless --script res://tests/test_runner.gd
## The exit code is 0 when every test passed, 1 otherwise.
##
## WHY TEST GAME CODE?
## Match-3 rules have many edge cases (L shapes, squares, combos, crates,
## diagonal falling...). Clicking through the game to check each one is slow
## and unreliable. These tests build exact board situations and check the
## result in milliseconds. Run them after every rule change.
##
## HOW TO READ A TEST
## Most tests: build a small board, overwrite its colors with load_colors()
## (digits = colors, "-" = empty), do something, then check() the result.
## The comments next to the boards explain why the board looks the way it does.
extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	# Every method whose name starts with "test_" runs automatically.
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


## A board with a fixed seed. Without a layout it's 8x8 and empty of obstacles.
func make_board(layout: Array = [], colors: int = 5) -> BoardModel:
	if layout.is_empty():
		for i in 8:
			layout.append("........")
	var model := BoardModel.new()
	model.setup(layout, colors, 1234)
	return model


## Rows where no two neighbours share a color, so there are no matches and no
## squares anywhere. Row y is (x + 2y) mod 5:   01234 / 23401 / 40123 / ...
func pattern_rows(w: int, h: int) -> Array:
	var rows: Array = []
	for y in h:
		var row := ""
		for x in w:
			row += str((x + 2 * y) % 5)
		rows.append(row)
	return rows


func open_rows(w: int, h: int) -> Array:
	var rows: Array = []
	for y in h:
		rows.append(".".repeat(w))
	return rows


# =============================================================================
# BOARD GENERATION
# =============================================================================

func test_new_board_has_no_matches_and_a_move() -> void:
	# Many seeds: generation must ALWAYS satisfy both rules.
	for seed_value in 50:
		var model := BoardModel.new()
		model.setup(open_rows(8, 8), 5, seed_value)
		check(model.find_matches().is_empty(), "seed %d: board starts with a match" % seed_value)
		check(not model.find_possible_move().is_empty(), "seed %d: no possible move" % seed_value)


func test_layout_layers() -> void:
	var model := make_board(["#.wW", "cC..", "...."])
	check(not model.is_playable(Vector2i(0, 0)), "# is a hole")
	check(model.get_piece(Vector2i(0, 0)) == null, "holes have no piece")
	check(model.total_weeds() == 3, "w + W = 3 weed layers, got %d" % model.total_weeds())
	check(model.total_crates() == 2, "2 crates, got %d" % model.total_crates())
	check(model.get_piece(Vector2i(0, 1)) == null, "a crate cell holds no piece")
	check(model.crate_hp(Vector2i(1, 1)) == 2, "C has 2 hit points")


# =============================================================================
# MATCHING AND SPECIAL CREATION
# =============================================================================

func test_invalid_swap_is_rejected() -> void:
	var model := make_board(open_rows(4, 2))
	model.load_colors(["0101", "2323"])
	check(not model.is_valid_swap(Vector2i(0, 0), Vector2i(1, 0)), "swap without match must be invalid")
	check(not model.is_valid_swap(Vector2i(0, 0), Vector2i(2, 0)), "non-adjacent swap must be invalid")


func test_simple_match_of_three() -> void:
	var model := make_board(open_rows(4, 3))
	model.load_colors([
		"0012",
		"2301",   # swapping (2,0) and (2,1) brings this 0 up -> row 0 = 000
		"3123",
	])
	check(model.is_valid_swap(Vector2i(2, 0), Vector2i(2, 1)), "swap should be valid")
	model.swap(Vector2i(2, 0), Vector2i(2, 1))
	var result := model.resolve_matches([Vector2i(2, 0), Vector2i(2, 1)])
	check(result.removed.size() == 3, "expected 3 removed, got %d" % result.removed.size())
	check(result.created.is_empty(), "3 in a row creates no special")
	check(result.score == 3 * BoardModel.POINTS_PER_PIECE, "unexpected score %d" % result.score)


func test_square_creates_butterfly() -> void:
	var model := make_board(open_rows(4, 3))
	model.load_colors([
		"0012",   # the four 0s in the top-left corner form a 2x2 square
		"0034",
		"1243",
	])
	var result := model.resolve_matches([])
	check(result.removed.size() == 4, "a square removes 4, got %d" % result.removed.size())
	check(result.created.size() == 1 and result.created[0]["piece"].special == BoardModel.Special.BUTTERFLY,
			"a square should create a BUTTERFLY")


func test_match_of_four_creates_rocket() -> void:
	var model := make_board(open_rows(6, 2))
	model.load_colors(["000012", "123423"])
	# (1, 0) plays the role of the cell the player dragged.
	var result := model.resolve_matches([Vector2i(1, 0)])
	check(result.created.size() == 1, "4 in a row should create one special")
	if result.created.size() == 1:
		check(result.created[0]["piece"].special == BoardModel.Special.ROCKET_H, "horizontal 4 makes ROCKET_H")
		check(result.created[0]["cell"] == Vector2i(1, 0), "special appears at the dragged cell")


func test_match_of_five_creates_rainbow() -> void:
	var model := make_board(open_rows(6, 2))
	model.load_colors(["000001", "123423"])
	var result := model.resolve_matches([])
	check(result.created.size() == 1 and result.created[0]["piece"].special == BoardModel.Special.RAINBOW,
			"5 in a row makes a RAINBOW")


func test_l_shape_creates_bomb() -> void:
	var model := make_board(open_rows(4, 3))
	model.load_colors([
		"0001",   # row 0 (x 0..2) and column 0 (y 0..2) share the corner
		"0232",
		"0313",
	])
	var result := model.resolve_matches([])
	check(result.removed.size() == 5, "L shape removes 5, got %d" % result.removed.size())
	check(result.created.size() == 1 and result.created[0]["piece"].special == BoardModel.Special.BOMB,
			"L shape makes a BOMB")


# =============================================================================
# CRATES AND WEEDS
# =============================================================================

func test_match_next_to_crate_breaks_it() -> void:
	var model := make_board(["....", "c..."])
	model.load_colors(["0001", "-234"])   # the crate at (0,1) touches (0,0)
	var result := model.resolve_matches([])
	check(result.crate_hits.size() == 1, "the crate next to the match is hit, got %d" % result.crate_hits.size())
	check(result.crate_hits.size() == 1 and result.crate_hits[0]["destroyed"], "a 1-hp crate is destroyed")
	check(model.total_crates() == 0, "no crates left")


func test_tough_crate_needs_two_hits() -> void:
	var model := make_board(["....", "C..."])
	model.load_colors(["0001", "-234"])
	var result := model.resolve_matches([])
	check(result.crate_hits.size() == 1 and not result.crate_hits[0]["destroyed"], "a 2-hp crate survives one hit")
	check(model.crate_hp(Vector2i(0, 1)) == 1, "the crate has 1 hp left")


func test_weeds_break_under_match() -> void:
	var model := make_board(["www.", "...."])
	model.load_colors(["0001", "2323"])
	var result := model.resolve_matches([])
	check(result.weed_hits.size() == 3, "3 weed cells hit, got %d" % result.weed_hits.size())
	check(model.total_weeds() == 0, "no weeds left")


func test_shovel_hits_piece_and_crate() -> void:
	var model := make_board(["c....", ".....", "....."])
	model.load_colors(pattern_rows(5, 3))
	var on_piece := model.resolve_matches([], [], 0, [Vector2i(3, 2)])
	check(on_piece.removed.size() == 1, "the shovel removes exactly one piece")
	var on_crate := model.resolve_matches([], [], 0, [Vector2i(0, 0)])
	check(on_crate.crate_hits.size() == 1 and model.total_crates() == 0, "the shovel breaks a crate")


# =============================================================================
# SPECIALS AND COMBOS
# =============================================================================

func test_rocket_clears_row_and_hits_crate() -> void:
	var model := make_board(["......", "....c.", "......"])
	model.load_colors(["012301", "230123", "301230"])   # no matches anywhere
	model.get_piece(Vector2i(1, 1)).special = BoardModel.Special.ROCKET_H
	var result := model.resolve_matches([], [{"cell": Vector2i(1, 1), "target_color": -1, "combo": "", "consumed": []}])
	check(result.removed.size() == 5, "row of 6 minus the crate = 5 pieces, got %d" % result.removed.size())
	check(result.crate_hits.size() == 1, "the rocket hits the crate in its row")


func test_rainbow_clears_one_color() -> void:
	var model := make_board(open_rows(4, 2))
	model.load_colors(["R101", "2121"])
	model.swap(Vector2i(0, 0), Vector2i(1, 0))   # swap the rainbow with a "1"
	var forced := model.special_swap_activations(Vector2i(0, 0), Vector2i(1, 0))
	var result := model.resolve_matches([], forced)
	check(result.removed.size() == 5, "four 1s + the rainbow, got %d" % result.removed.size())


func test_rocket_rocket_combo_makes_a_cross() -> void:
	var model := make_board(open_rows(5, 5))
	model.load_colors(pattern_rows(5, 5))
	model.get_piece(Vector2i(2, 2)).special = BoardModel.Special.ROCKET_H
	model.get_piece(Vector2i(3, 2)).special = BoardModel.Special.ROCKET_V
	model.swap(Vector2i(2, 2), Vector2i(3, 2))
	var forced := model.special_swap_activations(Vector2i(2, 2), Vector2i(3, 2))
	check(forced.size() == 1 and forced[0]["combo"] == "cross", "two rockets make a 'cross' combo")
	var result := model.resolve_matches([], forced)
	# Row 2 (5 cells) + column 3 (5 cells), sharing one cell = 9.
	check(result.removed.size() == 9, "cross removes 9, got %d" % result.removed.size())
	check(result.activated.size() == 1, "the consumed rocket does not fire separately")


func test_chain_reaction() -> void:
	var model := make_board(open_rows(3, 3))
	model.load_colors(["012", "120", "201"])
	model.get_piece(Vector2i(0, 0)).special = BoardModel.Special.ROCKET_H   # hits row 0...
	model.get_piece(Vector2i(2, 0)).special = BoardModel.Special.ROCKET_V   # ...which fires this one
	var result := model.resolve_matches([], [{"cell": Vector2i(0, 0), "target_color": -1, "combo": "", "consumed": []}])
	check(result.activated.size() == 2, "both rockets fire, got %d" % result.activated.size())
	check(result.removed.size() == 5, "row 0 + column 2 = 5, got %d" % result.removed.size())


func test_butterfly_flies_to_crate() -> void:
	var model := make_board([".....", ".....", ".....", ".....", "....c"])
	model.load_colors(pattern_rows(5, 5))
	model.get_piece(Vector2i(0, 0)).special = BoardModel.Special.BUTTERFLY
	var result := model.resolve_matches([], [{"cell": Vector2i(0, 0), "target_color": -1, "combo": "", "consumed": []}])
	check(result.flights.size() == 1 and result.flights[0]["to"] == Vector2i(4, 4), "the butterfly targets the crate")
	check(result.crate_hits.size() == 1, "the crate is hit")
	check(result.removed.size() == 3, "itself + its 2 neighbours in the corner, got %d" % result.removed.size())


# =============================================================================
# GRAVITY
# =============================================================================

func _all_open_cells_filled(model: BoardModel) -> bool:
	for x in model.width:
		for y in model.height:
			var cell := Vector2i(x, y)
			if model.is_open(cell) and model.get_piece(cell) == null:
				return false
	return true


func test_gravity_fills_every_cell() -> void:
	var model := make_board(["#...", "....", "....", "...."])
	model.load_colors(["-0--", "-1-2", "0-3-", "1-0-"])
	var gravity := model.apply_gravity()
	check(_all_open_cells_filled(model), "every open cell should be filled")
	check(not gravity["moves"].is_empty(), "some pieces fell")
	check(not gravity["spawns"].is_empty(), "some pieces spawned")


func test_pieces_slide_diagonally_under_crate() -> void:
	var model := make_board(["...", ".c.", "..."])
	model.load_colors(["012", "3-4", "0-1"])   # (1,2) is empty, under the crate
	var gravity := model.apply_gravity()
	check(_all_open_cells_filled(model), "the cell under the crate gets filled by a diagonal slide")
	check(not gravity["moves"].is_empty(), "pieces moved")


func test_every_level_can_refill() -> void:
	# Level design check: empty the whole board and let gravity refill it.
	# If some open cell stays empty, pieces can never reach it (for example
	# a cell under a wall of crates), which would leave holes in the board.
	for index in 40:   # all handcrafted levels and a batch of generated ones
		var level := LevelData.get_level(index)
		var model := BoardModel.new()
		model.setup(level["layout"], int(level["colors"]), index)
		for x in model.width:
			for y in model.height:
				model.set_piece(Vector2i(x, y), null)
		model.apply_gravity()
		check(_all_open_cells_filled(model), "level %d has cells that pieces can never reach" % (index + 1))


# =============================================================================
# SHUFFLE, BOOSTERS, GOALS, LEVELS
# =============================================================================

func test_shuffle_produces_playable_board() -> void:
	var model := make_board()
	model.shuffle()
	check(model.find_matches().is_empty(), "shuffled board has no matches")
	check(not model.find_possible_move().is_empty(), "shuffled board has a move")


func test_place_special_randomly() -> void:
	var model := make_board()
	var cell := model.place_special_randomly(BoardModel.Special.BOMB)
	check(cell != BoardModel.NO_CELL and model.get_piece(cell).special == BoardModel.Special.BOMB,
			"a random piece became a bomb")


func test_goals() -> void:
	var goals := LevelGoals.new()
	goals.setup([{"type": "collect", "color": 2, "amount": 2}, {"type": "crates"}], 0, 3)
	check(not goals.is_complete(), "goals don't start complete")
	goals.on_pieces_removed([
		{"piece": BoardModel.Piece.new(1, 2, 0), "cell": Vector2i.ZERO},
		{"piece": BoardModel.Piece.new(2, 2, 0), "cell": Vector2i.ZERO},
	])
	check(not goals.is_complete(), "crates still missing")
	goals.on_obstacles_remaining(0, 0)
	check(goals.is_complete(), "both goals done")


func test_generated_levels_are_deterministic() -> void:
	var a := LevelData.get_level(50)
	var b := LevelData.get_level(50)
	check(a["layout"] == b["layout"], "the same level number gives the same level")
	check(a["layout"].size() == 8 and String(a["layout"][0]).length() == 8, "generated boards are 8x8")
	check(not a["goals"].is_empty(), "generated levels have goals")
