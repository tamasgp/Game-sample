## BoardModel: the RULES of the match-3 puzzle. No graphics, no waiting.
##
## ============================================================================
## WHY IS THIS A SEPARATE CLASS?
## ============================================================================
## Game code gets messy when rules and visuals are mixed together, so we split
## them (the "Model / View" pattern):
##
##   * BoardModel (this file) knows WHERE every piece is and WHAT happens when
##     two pieces are swapped. It changes its data instantly and returns a
##     description of what happened.
##   * BoardView (board_view.gd) reads that description and ANIMATES it.
##
## Benefits:
##   - The rules can be unit tested in milliseconds (tests/test_runner.gd).
##   - With a fixed random seed the board is 100% reproducible, which is
##     priceless when a player reports a bug.
##   - A bot or level-balancing tool can play thousands of moves without
##     drawing anything.
##
## ============================================================================
## COORDINATES
## ============================================================================
## A cell is a Vector2i(x, y):
##     x = column, 0 is the LEFT edge
##     y = row,    0 is the TOP edge    ->  "falling" means y gets BIGGER
## Grids are stored column-first, so a cell is read as  _cells[x][y].
##
## ============================================================================
## WHAT CAN BE IN A CELL?  (several "layers" stacked on top of each other)
## ============================================================================
##     layer         stored in     meaning
##     -----------   -----------   ---------------------------------------------
##     playable?     _playable     false = a hole, the cell is not on the board
##     weeds         _weeds        0..2 layers UNDER the piece. Matching on top
##                                 removes one layer. (A level goal.)
##     crate         _crates       0..2 hit points. A crate fills the cell
##                                 INSTEAD of a piece, never falls, and is
##                                 damaged by matches NEXT to it and by
##                                 explosions. (A level goal.)
##     piece         _cells        the colored piece (or null = empty)
##
## ============================================================================
## ONE TURN, STEP BY STEP  (BoardView drives this loop and animates each step)
## ============================================================================
##   1. swap(a, b)                     exchange two pieces
##   2. special_swap_activations()     did the swap involve special pieces?
##   3. resolve_matches(...)           find matches, fire specials (with chain
##                                     reactions), remove pieces, damage weeds
##                                     and crates, create new specials
##   4. apply_gravity()                pieces fall (and slide diagonally around
##                                     crates), new pieces spawn at the top
##   5. back to 3 until nothing matches any more ("cascades")
##   6. if no move is possible:  shuffle()
class_name BoardModel
extends RefCounted


# =============================================================================
# CONSTANTS AND TYPES
# =============================================================================

## The kinds of special pieces. A normal piece has Special.NONE.
##
##   Created by            Special      Effect when it fires
##   ------------------    ---------    ----------------------------------------
##   4 in a row (horiz.)   ROCKET_H     clears its whole ROW
##   4 in a column         ROCKET_V     clears its whole COLUMN
##   L or T shape          BOMB         clears the 3x3 square around it
##   5 in a line           RAINBOW      clears every piece of ONE color
##   2x2 square            BUTTERFLY    clears the 4 cells around it, then flies
##                                      to one more cell (a crate or weeds if
##                                      possible) and clears that too
enum Special { NONE, ROCKET_H, ROCKET_V, BOMB, RAINBOW, BUTTERFLY }

## A rainbow matches no color, so its color is this special value.
const RAINBOW_COLOR := -1
## "Target color" meaning EVERY piece (used when two rainbows are swapped).
const ALL_COLORS := -2
## What _color_at() returns for empty cells, holes, crates and outside the board.
## It is never equal to a real color, so it can never be part of a match.
const NO_COLOR := -3
## Means "no cell". Vector2i can't be null, so we use an impossible value.
const NO_CELL := Vector2i(-1000, -1000)

## The four neighbours of a cell (right, left, down, up). No diagonals.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## A bomb clears every cell within this distance (1 = a 3x3 square).
const BOMB_RADIUS := 1
## Two bombs swapped together make a bigger blast (2 = a 5x5 square).
const BIG_BOMB_RADIUS := 2

# Scoring. A later cascade multiplies the points for pieces.
const POINTS_PER_PIECE := 10
const POINTS_PER_SPECIAL := 50
const POINTS_PER_CRATE := 30
const POINTS_PER_WEED := 20


## One piece on the board.
##
## Each piece gets a unique `id`, handed out once and never reused. The view
## keeps a dictionary "id -> picture node", so it can find the picture of a
## piece even after the piece has moved around the grid.
class Piece extends RefCounted:
	var id: int
	## 0 .. num_colors-1 for normal pieces, RAINBOW_COLOR (-1) for rainbows.
	var color: int
	## One of BoardModel.Special. Stored as a plain int, because an inner class
	## can't easily use its outer class's enum as a type.
	var special: int

	func _init(p_id: int, p_color: int, p_special: int = 0) -> void:
		id = p_id
		color = p_color
		special = p_special


## Everything that happened during ONE clear step, handed to the view (to
## animate it) and to the game screen (to update score and goals).
class ClearResult extends RefCounted:
	## Pieces taken off the board: Array of { "piece": Piece, "cell": Vector2i }
	var removed: Array = []
	## New special pieces born this step: Array of { "piece": Piece, "cell": Vector2i }
	var created: Array = []
	## Specials that went off: Array of { "cell": Vector2i, "special": int, "combo": String }
	var activated: Array = []
	## Butterfly flights: Array of { "from": Vector2i, "to": Vector2i }
	var flights: Array = []
	## Cells whose weeds lost a layer: Array of Vector2i
	var weed_hits: Array = []
	## Crates that were hit: Array of { "cell": Vector2i, "destroyed": bool }
	var crate_hits: Array = []
	## Points earned in this step.
	var score: int = 0

	## True when nothing at all happened, which means the turn is over.
	func is_empty() -> bool:
		return removed.is_empty() and created.is_empty() and crate_hits.is_empty()


# =============================================================================
# STATE
# =============================================================================

var width: int = 0
var height: int = 0
## How many different normal colors appear (3..6). Fewer colors = easier,
## because random pieces match more often.
var num_colors: int = 5

var _cells: Array = []      ## _cells[x][y]    -> Piece or null
var _playable: Array = []   ## _playable[x][y] -> bool
var _weeds: Array = []      ## _weeds[x][y]    -> int (layers)
var _crates: Array = []     ## _crates[x][y]   -> int (hit points, 0 = no crate)

## Counter for handing out unique piece ids.
var _next_id: int = 1

## Our own random number generator. Using our own (instead of the global
## randi()) lets us set a seed for reproducible boards in tests.
var rng := RandomNumberGenerator.new()


# =============================================================================
# SETUP
# =============================================================================

## Builds the board from a text layout, one string per row:
##     "."  normal cell            "#"  hole (not part of the board)
##     "w"  1 layer of weeds       "W"  2 layers of weeds
##     "c"  crate with 1 hit point "C"  crate with 2 hit points
##
## `random_seed >= 0` gives a reproducible board, -1 a random one.
func setup(layout: Array, colors: int, random_seed: int = -1) -> void:
	num_colors = clampi(colors, 3, 6)
	height = layout.size()
	width = 0
	for row in layout:
		width = maxi(width, String(row).length())

	_cells = _make_grid(null)
	_playable = _make_grid(false)
	_weeds = _make_grid(0)
	_crates = _make_grid(0)

	for y in height:
		var row: String = layout[y]
		for x in width:
			# Short rows are padded with holes.
			var ch: String = row[x] if x < row.length() else "#"
			_playable[x][y] = ch != "#"
			match ch:
				"w":
					_weeds[x][y] = 1
				"W":
					_weeds[x][y] = 2
				"c":
					_crates[x][y] = 1
				"C":
					_crates[x][y] = 2

	if random_seed >= 0:
		rng.seed = random_seed
	else:
		rng.randomize()

	fill_initial()


## Creates a width x height grid (an Array of columns) filled with `value`.
func _make_grid(value: Variant) -> Array:
	var grid: Array = []
	for x in width:
		var column: Array = []
		column.resize(height)
		column.fill(value)
		grid.append(column)
	return grid


## Fills every open cell with a random piece so that:
##   * the board starts with NO matches (the player should make the first one)
##   * at least ONE valid move exists
func fill_initial() -> void:
	for attempt in 100:
		# Fill column by column, top to bottom. When we reach a cell, the cells
		# to its LEFT and ABOVE are already filled, so those are the only
		# neighbours we must check to avoid creating a match.
		for x in width:
			for y in height:
				var cell := Vector2i(x, y)
				if is_open(cell):
					_cells[x][y] = _new_piece(_pick_color_without_match(cell))
				else:
					_cells[x][y] = null
		if not find_possible_move().is_empty():
			return
	push_warning("BoardModel: could not generate a board with a possible move.")


## A random color that does NOT complete a line of 3 (with the two cells to
## the left or the two above) and does NOT complete a 2x2 square (with the
## left, upper and upper-left cells).
func _pick_color_without_match(cell: Vector2i) -> int:
	var forbidden := {}
	var left := _color_at(cell + Vector2i(-1, 0))
	var up := _color_at(cell + Vector2i(0, -1))
	if left >= 0 and left == _color_at(cell + Vector2i(-2, 0)):
		forbidden[left] = true
	if up >= 0 and up == _color_at(cell + Vector2i(0, -2)):
		forbidden[up] = true
	if left >= 0 and left == up and left == _color_at(cell + Vector2i(-1, -1)):
		forbidden[left] = true

	var options: Array = []
	for color in num_colors:
		if not forbidden.has(color):
			options.append(color)
	# At most 2 colors are forbidden and there are always >= 3, so `options`
	# is never empty.
	return options[rng.randi_range(0, options.size() - 1)]


## Overwrites piece colors from digit strings. For TESTS and debugging:
##     "0".."5" = color, "R" = rainbow, "-" = empty cell, anything else = keep.
func load_colors(rows: Array) -> void:
	for y in mini(rows.size(), height):
		var row: String = rows[y]
		for x in mini(row.length(), width):
			if not is_open(Vector2i(x, y)):
				continue
			var ch: String = row[x]
			if ch == "R":
				_cells[x][y] = _new_piece(RAINBOW_COLOR, Special.RAINBOW)
			elif ch == "-":
				_cells[x][y] = null
			elif ch.is_valid_int():
				_cells[x][y] = _new_piece(ch.to_int())


# =============================================================================
# SMALL QUERIES
# =============================================================================

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Part of the board (not a hole)?
func is_playable(cell: Vector2i) -> bool:
	return in_bounds(cell) and _playable[cell.x][cell.y]


func has_crate(cell: Vector2i) -> bool:
	return in_bounds(cell) and int(_crates[cell.x][cell.y]) > 0


func crate_hp(cell: Vector2i) -> int:
	return int(_crates[cell.x][cell.y]) if in_bounds(cell) else 0


## Can this cell hold a piece? (On the board and not blocked by a crate.)
func is_open(cell: Vector2i) -> bool:
	return is_playable(cell) and not has_crate(cell)


func get_piece(cell: Vector2i) -> Piece:
	if not in_bounds(cell):
		return null
	return _cells[cell.x][cell.y]


## Puts a piece (or null) into an open cell. Used by tests and tools.
func set_piece(cell: Vector2i, piece: Piece) -> void:
	if is_open(cell):
		_cells[cell.x][cell.y] = piece


func get_weeds(cell: Vector2i) -> int:
	return int(_weeds[cell.x][cell.y]) if in_bounds(cell) else 0


## Total weed LAYERS left (for the "clear the weeds" goal).
func total_weeds() -> int:
	var total := 0
	for x in width:
		for y in height:
			total += int(_weeds[x][y])
	return total


## Number of crates left (counting crates, not hit points).
func total_crates() -> int:
	var total := 0
	for x in width:
		for y in height:
			if int(_crates[x][y]) > 0:
				total += 1
	return total


## Color at a cell, or NO_COLOR for anything that can't be matched.
func _color_at(cell: Vector2i) -> int:
	var piece := get_piece(cell)
	if piece == null:
		return NO_COLOR
	return piece.color


static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	# Exactly one step apart horizontally OR vertically.
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


static func is_rocket(special: int) -> bool:
	return special == Special.ROCKET_H or special == Special.ROCKET_V


func _new_piece(color: int, special: int = Special.NONE) -> Piece:
	var piece := Piece.new(_next_id, color, special)
	_next_id += 1
	return piece


func _random_color() -> int:
	return rng.randi_range(0, num_colors - 1)


func _random_rocket() -> int:
	return Special.ROCKET_H if rng.randi_range(0, 1) == 0 else Special.ROCKET_V


# =============================================================================
# SWAPPING
# =============================================================================

## Exchanges the pieces of two cells. No rule checks here (see is_valid_swap).
func swap(a: Vector2i, b: Vector2i) -> void:
	var temp: Piece = _cells[a.x][a.y]
	_cells[a.x][a.y] = _cells[b.x][b.y]
	_cells[b.x][b.y] = temp


## A swap is valid if the cells are neighbours that both hold pieces, AND
## either one of them is special (specials can always be fired) or the swap
## creates a match.
func is_valid_swap(a: Vector2i, b: Vector2i) -> bool:
	if not (is_open(a) and is_open(b) and are_adjacent(a, b)):
		return false
	var pa := get_piece(a)
	var pb := get_piece(b)
	if pa == null or pb == null:
		return false
	if pa.special != Special.NONE or pb.special != Special.NONE:
		return true
	# Try it, look, undo it. It's cheap because we only look near the 2 cells.
	swap(a, b)
	var makes_match := _has_match_at(a) or _has_match_at(b)
	swap(a, b)
	return makes_match


## Is the piece at `cell` part of a line of 3+ or of a 2x2 square?
func _has_match_at(cell: Vector2i) -> bool:
	var color := _color_at(cell)
	if color < 0:
		return false
	var horizontal := 1 + _count_same(cell, Vector2i.LEFT, color) + _count_same(cell, Vector2i.RIGHT, color)
	var vertical := 1 + _count_same(cell, Vector2i.UP, color) + _count_same(cell, Vector2i.DOWN, color)
	return horizontal >= 3 or vertical >= 3 or _in_square(cell, color)


## Counts how many pieces of `color` follow `cell` in direction `dir`.
func _count_same(cell: Vector2i, dir: Vector2i, color: int) -> int:
	var count := 0
	var current := cell + dir
	while _color_at(current) == color:
		count += 1
		current += dir
	return count


## Is `cell` part of any 2x2 square of `color`? A cell belongs to up to four
## squares, so we test the four possible top-left corners.
func _in_square(cell: Vector2i, color: int) -> bool:
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			var corner: Vector2i = cell + Vector2i(dx, dy)
			if _is_square(corner, color):
				return true
	return false


## Are the 4 cells with `corner` as top-left all `color`?
func _is_square(corner: Vector2i, color: int) -> bool:
	return _color_at(corner) == color \
			and _color_at(corner + Vector2i(1, 0)) == color \
			and _color_at(corner + Vector2i(0, 1)) == color \
			and _color_at(corner + Vector2i(1, 1)) == color


## Searches for any valid move. Returns [a, b], or [] if the board is stuck.
func find_possible_move() -> Array:
	for x in width:
		for y in height:
			var a := Vector2i(x, y)
			# Checking only RIGHT and DOWN covers every pair exactly once.
			for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b: Vector2i = a + dir
				if is_valid_swap(a, b):
					return [a, b]
	return []


## Call AFTER swap(a, b). If the swap involved special pieces, returns the
## "forced activations" that make them go off even without a match.
##
## Each activation is a Dictionary:
##     "cell"            where it goes off
##     "target_color"    for rainbows: which color to clear
##     "combo"           "" for a normal blast, or the name of a combo:
##                       "cross", "big_cross", "big_bomb", "all", "convert"
##     "consumed"        cells whose special is absorbed by the combo (they
##                       are removed but do NOT fire on their own)
##     "convert_special" only for "convert": which special to turn pieces into
##
## COMBOS (two specials swapped together are stronger than both alone):
##     rocket + rocket      -> "cross"      row AND column
##     rocket + bomb        -> "big_cross"  3 rows AND 3 columns
##     bomb   + bomb        -> "big_bomb"   5x5 square
##     rainbow + rainbow    -> "all"        the whole board
##     rainbow + special    -> "convert"    every piece of that special's color
##                                          turns into that special and fires
##     rainbow + normal     -> clears every piece of that color
##     anything with a butterfly: both simply fire
func special_swap_activations(a: Vector2i, b: Vector2i) -> Array:
	var pa := get_piece(a)
	var pb := get_piece(b)
	if pa == null or pb == null:
		return []
	var sa := pa.special
	var sb := pb.special
	if sa == Special.NONE and sb == Special.NONE:
		return []

	# --- Rainbow cases ---
	if sa == Special.RAINBOW and sb == Special.RAINBOW:
		return [_activation(b, ALL_COLORS, "all", [a])]
	if sa == Special.RAINBOW or sb == Special.RAINBOW:
		var rainbow_cell := a if sa == Special.RAINBOW else b
		var other := pb if sa == Special.RAINBOW else pa
		if other.special == Special.NONE:
			return [_activation(rainbow_cell, other.color, "", [])]
		var convert_activation := _activation(rainbow_cell, other.color, "convert", [])
		convert_activation["convert_special"] = other.special
		return [convert_activation]

	# --- Two non-rainbow specials: maybe a combo ---
	if sa != Special.NONE and sb != Special.NONE:
		var combo := _combo_name(sa, sb)
		if combo != "":
			# The combo goes off where the player dropped the piece (b), and the
			# special at a is "consumed" by it.
			return [_activation(b, -1, combo, [a])]

	# --- Otherwise every special involved fires on its own ---
	var forced: Array = []
	if sa != Special.NONE:
		forced.append(_activation(a, -1, "", []))
	if sb != Special.NONE:
		forced.append(_activation(b, -1, "", []))
	return forced


func _activation(cell: Vector2i, target_color: int, combo: String, consumed: Array) -> Dictionary:
	return {"cell": cell, "target_color": target_color, "combo": combo, "consumed": consumed}


func _combo_name(sa: int, sb: int) -> String:
	if is_rocket(sa) and is_rocket(sb):
		return "cross"
	if (is_rocket(sa) and sb == Special.BOMB) or (sa == Special.BOMB and is_rocket(sb)):
		return "big_cross"
	if sa == Special.BOMB and sb == Special.BOMB:
		return "big_bomb"
	return ""


# =============================================================================
# FINDING MATCHES
# =============================================================================

## Finds every straight line of 3+ and every 2x2 square of one color.
## Returns Array of { "cells": Array[Vector2i], "kind": "h"|"v"|"square", "color": int }
func _find_runs() -> Array:
	var runs: Array = []

	# Horizontal lines: walk each row left to right. When a color starts,
	# measure how long it continues. Jump past it and continue.
	for y in height:
		var x := 0
		while x < width:
			var color := _color_at(Vector2i(x, y))
			var length := 1
			if color >= 0:
				while x + length < width and _color_at(Vector2i(x + length, y)) == color:
					length += 1
				if length >= 3:
					var cells: Array = []
					for i in length:
						cells.append(Vector2i(x + i, y))
					runs.append({"cells": cells, "kind": "h", "color": color})
			x += length

	# Vertical lines: the same, top to bottom in each column.
	for x in width:
		var y := 0
		while y < height:
			var color := _color_at(Vector2i(x, y))
			var length := 1
			if color >= 0:
				while y + length < height and _color_at(Vector2i(x, y + length)) == color:
					length += 1
				if length >= 3:
					var cells: Array = []
					for i in length:
						cells.append(Vector2i(x, y + i))
					runs.append({"cells": cells, "kind": "v", "color": color})
			y += length

	# 2x2 squares: test every possible top-left corner.
	for x in width - 1:
		for y in height - 1:
			var corner := Vector2i(x, y)
			var color := _color_at(corner)
			if color >= 0 and _is_square(corner, color):
				runs.append({
					"cells": [corner, corner + Vector2i(1, 0), corner + Vector2i(0, 1), corner + Vector2i(1, 1)],
					"kind": "square",
					"color": color,
				})

	return runs


## Groups runs that share a cell into one MATCH. For example, an L shape is a
## horizontal and a vertical run that cross. It should count as ONE match
## (making one bomb), not two.
## Returns Array of { "cells": Dictionary(Vector2i -> true), "runs": Array, "color": int }
func find_matches() -> Array:
	var groups: Array = []
	for run in _find_runs():
		var run_cells: Array = run["cells"]
		var merged := {"cells": {}, "runs": [run], "color": run["color"]}
		for cell in run_cells:
			merged["cells"][cell] = true

		# Absorb every existing group this run overlaps with. (A run may join
		# two groups that were separate until now, so we check all of them.)
		var untouched: Array = []
		for group in groups:
			var group_cells: Dictionary = group["cells"]
			var overlaps := false
			for cell in run_cells:
				if group_cells.has(cell):
					overlaps = true
					break
			if overlaps:
				merged["cells"].merge(group_cells)
				merged["runs"].append_array(group["runs"])
			else:
				untouched.append(group)
		untouched.append(merged)
		groups = untouched
	return groups


## Which special (if any) does a match group create? Bigger shapes win.
func _special_for_group(group: Dictionary) -> int:
	var longest := 0
	var longest_horizontal := true
	var has_h := false
	var has_v := false
	var has_square := false
	for run in group["runs"]:
		var kind: String = run["kind"]
		if kind == "square":
			has_square = true
			continue
		var length: int = run["cells"].size()
		if kind == "h":
			has_h = true
		else:
			has_v = true
		if length > longest:
			longest = length
			longest_horizontal = kind == "h"

	if longest >= 5:
		return Special.RAINBOW
	if has_h and has_v:
		return Special.BOMB          # L or T shape
	if longest == 4:
		return Special.ROCKET_H if longest_horizontal else Special.ROCKET_V
	if has_square:
		return Special.BUTTERFLY
	return Special.NONE


## Where does the new special appear? Where the player dragged the piece, if
## that cell is part of the match (it feels right). Otherwise in the middle
## of the biggest run.
func _pick_spawn_cell(group: Dictionary, preferred_cells: Array) -> Vector2i:
	var group_cells: Dictionary = group["cells"]
	for cell in preferred_cells:
		if group_cells.has(cell):
			return cell
	var biggest: Array = []
	for run in group["runs"]:
		var cells: Array = run["cells"]
		if cells.size() > biggest.size():
			biggest = cells
	return biggest[int(biggest.size() / 2.0)]


# =============================================================================
# RESOLVING ONE STEP
# =============================================================================

## Performs ONE clear step and returns what happened.
##
##   preferred_cells  the two swapped cells (where new specials should appear)
##   forced           activations from special_swap_activations()
##   cascade          0 for the player's own move, 1, 2, ... for chain
##                    reactions after pieces fall. Later ones score more.
##   extra_cells      cells hit by a tool (the shovel booster). A piece there
##                    is removed (a special fires), a crate takes a hit.
##
## If the result is_empty(), nothing happened and the turn is over.
func resolve_matches(preferred_cells: Array = [], forced: Array = [], cascade: int = 0,
		extra_cells: Array = []) -> ClearResult:
	var result := ClearResult.new()
	# Dictionaries used as SETS: the keys matter, the values are just `true`.
	# Sets avoid counting the same cell twice.
	var to_clear := {}       # cells whose piece will be removed
	var crate_damage := {}   # crates that lose 1 hit point this step
	var creations: Array = []

	# ---- 1) Normal matches ---------------------------------------------------
	var matched := {}
	for group in find_matches():
		matched.merge(group["cells"])
		var special := _special_for_group(group)
		if special != Special.NONE:
			creations.append({
				"cell": _pick_spawn_cell(group, preferred_cells),
				"special": special,
				"color": group["color"],
			})
	to_clear.merge(matched)

	# A match damages crates right NEXT to it (not diagonally).
	for key in matched:
		var cell: Vector2i = key
		for dir in DIRS:
			if has_crate(cell + dir):
				crate_damage[cell + dir] = true

	# ---- 2) Tool hits (shovel) ---------------------------------------------
	for cell in extra_cells:
		if has_crate(cell):
			crate_damage[cell] = true
		elif get_piece(cell) != null:
			to_clear[cell] = true

	# ---- 3) Specials fired by the swap -------------------------------------
	var activation_for := {}   # cell -> activation Dictionary
	var exploded := {}         # cells whose special already fired (or was consumed)
	for activation in forced:
		var cell: Vector2i = activation["cell"]
		to_clear[cell] = true
		activation_for[cell] = activation
		for consumed in activation["consumed"]:
			to_clear[consumed] = true
			exploded[consumed] = true   # absorbed into the combo: won't fire alone

	# ---- 4) Chain reactions -------------------------------------------------
	# Every special that is about to be removed goes off. Its blast may reach
	# more specials, which go off too, and so on. This is a "work list"
	# (breadth-first) algorithm: `work` holds cells still to look at, and every
	# blast adds the cells it reaches.
	var work: Array = to_clear.keys()
	while not work.is_empty():
		var cell: Vector2i = work.pop_back()
		if exploded.has(cell):
			continue
		var piece := get_piece(cell)
		if piece == null or piece.special == Special.NONE:
			continue
		exploded[cell] = true

		var activation: Dictionary = activation_for.get(cell, {})
		var combo: String = activation.get("combo", "")
		var target: int = activation.get("target_color", -1)
		result.activated.append({"cell": cell, "special": piece.special, "combo": combo})

		var area: Array
		if combo == "convert":
			area = _convert_color_to_special(target, int(activation["convert_special"]))
		elif combo != "":
			area = _combo_area(cell, combo)
		elif piece.special == Special.BUTTERFLY:
			area = _butterfly_area(cell, to_clear, crate_damage, result)
		else:
			area = _special_area(cell, piece, target)

		for hit in area:
			if has_crate(hit):
				crate_damage[hit] = true
			elif not to_clear.has(hit) and get_piece(hit) != null:
				to_clear[hit] = true
				work.append(hit)

	# ---- 5) Remove pieces, damage the weeds underneath ----------------------
	for key in to_clear.keys():
		var cell: Vector2i = key
		var piece := get_piece(cell)
		if piece == null or not is_open(cell):
			continue
		result.removed.append({"piece": piece, "cell": cell})
		_cells[cell.x][cell.y] = null
		if int(_weeds[cell.x][cell.y]) > 0:
			_weeds[cell.x][cell.y] -= 1
			result.weed_hits.append(cell)

	# ---- 6) Damage crates ---------------------------------------------------
	for key in crate_damage.keys():
		var cell: Vector2i = key
		_crates[cell.x][cell.y] -= 1
		result.crate_hits.append({"cell": cell, "destroyed": int(_crates[cell.x][cell.y]) == 0})

	# ---- 7) Place the new specials (each replaces a removed piece) ----------
	for creation in creations:
		var cell: Vector2i = creation["cell"]
		var special: int = creation["special"]
		var color: int = RAINBOW_COLOR if special == Special.RAINBOW else int(creation["color"])
		var piece := _new_piece(color, special)
		_cells[cell.x][cell.y] = piece
		result.created.append({"piece": piece, "cell": cell})

	result.score = result.removed.size() * POINTS_PER_PIECE * (cascade + 1) \
			+ creations.size() * POINTS_PER_SPECIAL \
			+ result.crate_hits.size() * POINTS_PER_CRATE \
			+ result.weed_hits.size() * POINTS_PER_WEED
	return result


## The cells a special hits when it fires on its own.
func _special_area(cell: Vector2i, piece: Piece, target_color: int) -> Array:
	var cells: Array = []
	match piece.special:
		Special.ROCKET_H:
			for x in width:
				cells.append(Vector2i(x, cell.y))
		Special.ROCKET_V:
			for y in height:
				cells.append(Vector2i(cell.x, y))
		Special.BOMB:
			cells = _square_area(cell, BOMB_RADIUS)
		Special.RAINBOW:
			# A rainbow set off by a chain reaction (not by a swap) has no target
			# color, so it picks the most common one (the most helpful choice).
			var color := target_color
			if color < 0 and color != ALL_COLORS:
				color = _most_common_color()
			for x in width:
				for y in height:
					var other := get_piece(Vector2i(x, y))
					if other != null and (color == ALL_COLORS or other.color == color):
						cells.append(Vector2i(x, y))
	return _only_playable(cells)


## The cells a combo hits.
func _combo_area(cell: Vector2i, combo: String) -> Array:
	var cells: Array = []
	match combo:
		"cross":
			for x in width:
				cells.append(Vector2i(x, cell.y))
			for y in height:
				cells.append(Vector2i(cell.x, y))
		"big_cross":
			for offset in [-1, 0, 1]:
				for x in width:
					cells.append(Vector2i(x, cell.y + offset))
				for y in height:
					cells.append(Vector2i(cell.x + offset, y))
		"big_bomb":
			cells = _square_area(cell, BIG_BOMB_RADIUS)
		"all":
			for x in width:
				for y in height:
					cells.append(Vector2i(x, y))
	return _only_playable(cells)


## Every cell within `radius` steps of `center` (a square).
func _square_area(center: Vector2i, radius: int) -> Array:
	var cells: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			cells.append(center + Vector2i(dx, dy))
	return cells


## Butterfly: the 4 neighbours, plus one flight target somewhere else.
func _butterfly_area(cell: Vector2i, to_clear: Dictionary, crate_damage: Dictionary,
		result: ClearResult) -> Array:
	var cells: Array = [cell]
	for dir in DIRS:
		cells.append(cell + dir)
	var target := _butterfly_target(cell, cells, to_clear, crate_damage)
	if target != NO_CELL:
		cells.append(target)
		result.flights.append({"from": cell, "to": target})
	return _only_playable(cells)


## Picks where a butterfly flies. Most useful first:
##   1. a crate that isn't already being hit
##   2. a piece standing on weeds
##   3. any other piece
## Cells already being cleared (or right next to the butterfly) are skipped,
## so the flight isn't wasted.
func _butterfly_target(from: Vector2i, nearby: Array, to_clear: Dictionary, crate_damage: Dictionary) -> Vector2i:
	var crates: Array = []
	var weeds: Array = []
	var others: Array = []
	for x in width:
		for y in height:
			var cell := Vector2i(x, y)
			if nearby.has(cell) or to_clear.has(cell):
				continue
			if has_crate(cell):
				if not crate_damage.has(cell):
					crates.append(cell)
			elif get_piece(cell) != null:
				if get_weeds(cell) > 0:
					weeds.append(cell)
				else:
					others.append(cell)
	for candidates in [crates, weeds, others]:
		if not candidates.is_empty():
			return candidates[rng.randi_range(0, candidates.size() - 1)]
	return NO_CELL


## Rainbow + special combo: every normal piece of `color` becomes `special`.
## Returns those cells. The chain-reaction loop then makes them all fire.
func _convert_color_to_special(color: int, special: int) -> Array:
	var cells: Array = []
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece == null or piece.color != color:
				continue
			if piece.special == Special.NONE:
				# Rockets get a random direction each, which looks more exciting.
				piece.special = _random_rocket() if is_rocket(special) else special
			cells.append(Vector2i(x, y))
	return cells


func _only_playable(cells: Array) -> Array:
	return cells.filter(func(c: Vector2i) -> bool: return is_playable(c))


func _most_common_color() -> int:
	var counts := {}
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece != null and piece.color >= 0:
				counts[piece.color] = int(counts.get(piece.color, 0)) + 1
	var best_color := 0
	var best_count := -1
	for color in counts:
		if int(counts[color]) > best_count:
			best_count = counts[color]
			best_color = color
	return best_color


# =============================================================================
# GRAVITY AND REFILLING
# =============================================================================

## Makes pieces fall into empty cells, spawns new pieces at the top, and lets
## pieces SLIDE DIAGONALLY into cells that nothing can fall into from above
## (for example the cells under a crate).
##
## HOW IT WORKS: a small step-by-step SIMULATION. Each round:
##   1. every piece with an empty open cell directly below moves down one row
##      (we sweep from the bottom up, so a whole column drops together)
##   2. the top open cell of every column ("spawn cell") gets a new piece if
##      it's empty
##   3. only if NOTHING moved in 1 and 2: a piece may slide diagonally down
##      into an empty cell that can't be fed from above
## We repeat until a round changes nothing. Pieces only ever move down, so
## this always finishes.
##
## Returns { "moves": Array, "spawns": Array }, each entry
##     { "piece": Piece, "from": Vector2i, "to": Vector2i }
## "from" is where the piece was before gravity (for spawns: a cell ABOVE the
## board, so the view can animate it dropping in). The view animates a
## straight line from "from" to "to", which is close enough for diagonal slides.
func apply_gravity() -> Dictionary:
	var tracked := {}        # piece id -> { "piece", "from", "spawned" }
	var spawned_in := {}     # column x -> how many pieces spawned there so far

	for round_index in 10000:   # a safety limit; real boards need far fewer
		var moved := false

		# 1) Straight down.
		for y in range(height - 2, -1, -1):
			for x in width:
				var cell := Vector2i(x, y)
				var piece := get_piece(cell)
				var below := Vector2i(x, y + 1)
				if piece != null and is_open(below) and get_piece(below) == null:
					_move_piece(tracked, piece, cell, below)
					moved = true

		# 2) Spawn new pieces.
		for x in width:
			var spawn := _spawn_cell(x)
			if spawn != NO_CELL and get_piece(spawn) == null:
				var piece := _new_piece(_random_color())
				_cells[spawn.x][spawn.y] = piece
				var count: int = spawned_in.get(x, 0)
				spawned_in[x] = count + 1
				# Stack the starting points above the board so pieces arrive in order.
				tracked[piece.id] = {"piece": piece, "from": Vector2i(x, spawn.y - 1 - count), "spawned": true}
				moved = true

		if moved:
			continue

		# 3) Diagonal slides, only when nothing could fall straight.
		var slid := false
		for y in range(height - 2, -1, -1):
			for x in width:
				var cell := Vector2i(x, y)
				var piece := get_piece(cell)
				if piece == null or slid:
					continue
				for dx in [-1, 1]:
					var target := Vector2i(x + dx, y + 1)
					if is_open(target) and get_piece(target) == null and not _fed_from_above(target):
						_move_piece(tracked, piece, cell, target)
						slid = true
						break
		if not slid:
			break

	# Look up where every tracked piece ended up.
	var moves: Array = []
	var spawns: Array = []
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece == null or not tracked.has(piece.id):
				continue
			var info: Dictionary = tracked[piece.id]
			var entry := {"piece": piece, "from": info["from"], "to": Vector2i(x, y)}
			if info["spawned"]:
				spawns.append(entry)
			elif entry["from"] != entry["to"]:
				moves.append(entry)
	return {"moves": moves, "spawns": spawns}


func _move_piece(tracked: Dictionary, piece: Piece, from: Vector2i, to: Vector2i) -> void:
	_cells[to.x][to.y] = piece
	_cells[from.x][from.y] = null
	# Remember only the FIRST position, so we know the full distance moved.
	if not tracked.has(piece.id):
		tracked[piece.id] = {"piece": piece, "from": from, "spawned": false}


## The topmost playable cell of a column, where new pieces appear.
## NO_CELL if that cell is blocked by a crate (nothing spawns until it breaks).
func _spawn_cell(x: int) -> Vector2i:
	for y in height:
		var cell := Vector2i(x, y)
		if is_playable(cell):
			return cell if is_open(cell) else NO_CELL
	return NO_CELL


## Will this empty cell be filled from straight above (by a falling piece or a
## spawn)? If not, it's allowed to receive a diagonal slide.
func _fed_from_above(cell: Vector2i) -> bool:
	var spawn := _spawn_cell(cell.x)
	var y := cell.y - 1
	while y >= 0:
		# Everything above the spawn cell counts as "sky": pieces come from there.
		if spawn != NO_CELL and y < spawn.y:
			return true
		var above := Vector2i(cell.x, y)
		if not is_open(above):
			return false   # a crate or a hole blocks the way
		if get_piece(above) != null:
			return true    # this piece will fall down
		y -= 1
	return spawn != NO_CELL


# =============================================================================
# SHUFFLING WHEN STUCK
# =============================================================================

## Rearranges the pieces until there are no matches and at least one move.
## Returns moves for the animation: Array of { "piece", "from", "to" }
func shuffle() -> Array:
	var cells: Array = []
	var pieces: Array = []
	var original := {}   # piece id -> cell before shuffling
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece != null:
				cells.append(Vector2i(x, y))
				pieces.append(piece)
				original[piece.id] = Vector2i(x, y)

	var solved := false
	for attempt in 200:
		# Fisher-Yates: the standard way to shuffle an array fairly.
		for i in range(pieces.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var temp: Variant = pieces[i]
			pieces[i] = pieces[j]
			pieces[j] = temp
		for i in cells.size():
			var cell: Vector2i = cells[i]
			_cells[cell.x][cell.y] = pieces[i]
		if find_matches().is_empty() and not find_possible_move().is_empty():
			solved = true
			break

	# Very unlikely fallback: recolor normal pieces (keeping their ids, so the
	# view only has to refresh them) until the board is valid.
	var recolor_attempts := 0
	while not solved and recolor_attempts < 100:
		recolor_attempts += 1
		for cell in cells:
			var piece := get_piece(cell)
			if piece.special == Special.NONE:
				piece.color = _random_color()
		solved = find_matches().is_empty() and not find_possible_move().is_empty()

	var moves: Array = []
	for cell in cells:
		var piece := get_piece(cell)
		moves.append({"piece": piece, "from": original[piece.id], "to": cell})
	return moves


# =============================================================================
# BOOSTERS
# =============================================================================

## Turns a random normal piece into `special` (used by the pre-level boosters
## and by the end-of-level bonus). For rockets, pass either rocket type and
## the direction is chosen at random. Returns the cell, or NO_CELL if there
## was no normal piece left.
func place_special_randomly(special: int) -> Vector2i:
	var candidates: Array = []
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece != null and piece.special == Special.NONE:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return NO_CELL
	var cell: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	var chosen := get_piece(cell)
	chosen.special = _random_rocket() if is_rocket(special) else special
	if special == Special.RAINBOW:
		chosen.color = RAINBOW_COLOR
	return cell
