## BoardModel: the RULES of the match-3 puzzle, with no graphics at all.
##
## WHY A SEPARATE "MODEL"?
## ----------------------
## Game code gets messy fast when rules and visuals are mixed together.
## Here we split them (a pattern often called Model/View):
##
##   * BoardModel (this file) knows WHERE every piece is and WHAT happens when
##     you swap two pieces. It never draws anything and never waits for
##     animations. That makes it fast, predictable and easy to unit test
##     (see tests/test_runner.gd).
##
##   * BoardView (board_view.gd) draws the pieces and plays the animations.
##     It asks the model "what happened?" and then shows it to the player.
##
## COORDINATES
## -----------
## Cells are addressed with Vector2i(x, y):
##   x = column, 0 is the LEFT edge
##   y = row,    0 is the TOP edge  (so "falling" means y gets bigger)
##
## The grid is stored column-first: _cells[x][y].
##
## THE TURN, STEP BY STEP
## ----------------------
##   1. swap(a, b)                     -> exchange two pieces
##   2. resolve_matches(...)           -> find matches, trigger specials,
##                                        remove pieces, create new specials
##   3. apply_gravity()                -> pieces fall down, new ones spawn on top
##   4. go back to 2 until nothing more matches ("cascades")
##   5. if no move is possible any more -> shuffle()
##
## BoardView drives this loop and animates between the steps.
class_name BoardModel
extends RefCounted


# ---------------------------------------------------------------------------
# Constants and types
# ---------------------------------------------------------------------------

## Kinds of special pieces. A normal piece has Special.NONE.
##   ROCKET_H : created by matching 4 in a row horizontally; clears its ROW.
##   ROCKET_V : created by matching 4 in a column; clears its COLUMN.
##   BOMB     : created by an L or T shaped match; clears the area around it.
##   RAINBOW  : created by matching 5 in a line; clears every piece of one color.
enum Special { NONE, ROCKET_H, ROCKET_V, BOMB, RAINBOW }

## A rainbow piece matches no color, so it gets this "color".
const RAINBOW_COLOR := -1
## Special "target color" meaning "every piece on the board" (two rainbows swapped).
const ALL_COLORS := -2
## What _color_at() returns for an empty / hole cell. Never equal to a real color.
const NO_COLOR := -3

## A bomb clears every cell within this many steps (1 = 3x3 square).
const BOMB_RADIUS := 1
## Points for every piece removed. Multiplied by the cascade level.
const POINTS_PER_PIECE := 10
## Bonus points for creating a special piece.
const POINTS_PER_SPECIAL := 50


## One piece on the board.
##
## Each piece gets a unique `id`. The view uses that id to find the sprite
## (TileView) that belongs to this piece, even after it has moved around.
class Piece extends RefCounted:
	var id: int
	## 0 .. num_colors-1 for normal pieces, RAINBOW_COLOR (-1) for rainbows.
	var color: int
	## One of BoardModel.Special (stored as int).
	var special: int

	func _init(p_id: int, p_color: int, p_special: int = 0) -> void:
		id = p_id
		color = p_color
		special = p_special


## Everything that happened during ONE clear step.
## The model fills this in; the view reads it to know what to animate,
## and the game screen reads it to update score and goals.
class ClearResult extends RefCounted:
	## Pieces taken off the board: Array of { "piece": Piece, "cell": Vector2i }
	var removed: Array = []
	## Special pieces born in this step: Array of { "piece": Piece, "cell": Vector2i }
	var created: Array = []
	## Specials that exploded: Array of { "special": int, "cell": Vector2i }
	var activated: Array = []
	## Cells whose ice lost one layer: Array of Vector2i
	var ice_hits: Array = []
	## Points earned in this step.
	var score: int = 0

	func is_empty() -> bool:
		return removed.is_empty() and created.is_empty()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var width: int = 0
var height: int = 0
## How many different normal colors may appear (3..6). Fewer = easier level.
var num_colors: int = 5

## _cells[x][y] -> Piece, or null if the cell is empty (briefly, during a turn).
var _cells: Array = []
## _playable[x][y] -> bool. False means a "hole" that is not part of the board.
var _playable: Array = []
## _ice[x][y] -> int, layers of ice under the piece (0 = none).
## Making a match on top of ice removes one layer. Clearing all ice can be a level goal.
var _ice: Array = []

## Counter used to hand out unique piece ids.
var _next_id: int = 1

## Our own random number generator. Giving it a fixed seed makes the board
## reproducible, which is great for tests and for debugging a reported bug.
var rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Builds the board from a text layout, one string per row:
##   "."  normal playable cell
##   "i"  playable cell with 1 layer of ice
##   "I"  playable cell with 2 layers of ice
##   "#"  hole (not part of the board)
##
## Pass `random_seed >= 0` for a reproducible board, or leave it at -1 for a random one.
func setup(layout: Array, colors: int, random_seed: int = -1) -> void:
	num_colors = clampi(colors, 3, 6)
	height = layout.size()
	width = 0
	for row in layout:
		width = maxi(width, String(row).length())

	_cells = _make_grid(null)
	_playable = _make_grid(false)
	_ice = _make_grid(0)

	for y in height:
		var row: String = layout[y]
		for x in width:
			# Short rows are padded with holes.
			var ch: String = row[x] if x < row.length() else "#"
			_playable[x][y] = ch != "#"
			if ch == "i":
				_ice[x][y] = 1
			elif ch == "I":
				_ice[x][y] = 2

	if random_seed >= 0:
		rng.seed = random_seed
	else:
		rng.randomize()

	fill_initial()


## Creates a width x height grid (array of columns) filled with `value`.
func _make_grid(value: Variant) -> Array:
	var grid: Array = []
	for x in width:
		var column: Array = []
		column.resize(height)
		column.fill(value)
		grid.append(column)
	return grid


## Fills every playable cell with a random piece so that:
##   * there are NO matches at the start (the player should make the first one)
##   * at least ONE valid move exists
func fill_initial() -> void:
	for attempt in 100:
		# Fill column by column, top to bottom. When we reach a cell, the cells
		# to its LEFT and ABOVE are already filled, so those are the only ones
		# we need to check to avoid creating a match.
		for x in width:
			for y in height:
				var cell := Vector2i(x, y)
				if is_playable(cell):
					_cells[x][y] = _new_piece(_pick_color_without_match(cell))
				else:
					_cells[x][y] = null
		if not find_possible_move().is_empty():
			return
	# With 3+ colors on a normal sized board this practically never happens.
	push_warning("BoardModel: could not generate a board with a possible move.")


## Picks a random color that would NOT complete a 3-in-a-row with the
## two cells to the left or the two cells above.
func _pick_color_without_match(cell: Vector2i) -> int:
	var forbidden := {}
	var left1 := _color_at(cell + Vector2i(-1, 0))
	if left1 >= 0 and left1 == _color_at(cell + Vector2i(-2, 0)):
		forbidden[left1] = true
	var up1 := _color_at(cell + Vector2i(0, -1))
	if up1 >= 0 and up1 == _color_at(cell + Vector2i(0, -2)):
		forbidden[up1] = true

	var options: Array = []
	for color in num_colors:
		if not forbidden.has(color):
			options.append(color)
	# At most 2 colors are forbidden and we always have >= 3, so never empty.
	return options[rng.randi_range(0, options.size() - 1)]


## Replaces the colors of the board from digit strings. Intended for TESTS and
## debugging, so you can build an exact situation:
##   "0".."5" = color, "R" = rainbow, "-" = empty cell, anything else = keep.
func load_colors(rows: Array) -> void:
	for y in mini(rows.size(), height):
		var row: String = rows[y]
		for x in mini(row.length(), width):
			if not _playable[x][y]:
				continue
			var ch: String = row[x]
			if ch == "R":
				_cells[x][y] = _new_piece(RAINBOW_COLOR, Special.RAINBOW)
			elif ch == "-":
				_cells[x][y] = null
			elif ch.is_valid_int():
				_cells[x][y] = _new_piece(ch.to_int())


# ---------------------------------------------------------------------------
# Small queries
# ---------------------------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_playable(cell: Vector2i) -> bool:
	return in_bounds(cell) and _playable[cell.x][cell.y]


func get_piece(cell: Vector2i) -> Piece:
	if not in_bounds(cell):
		return null
	return _cells[cell.x][cell.y]


func set_piece(cell: Vector2i, piece: Piece) -> void:
	if is_playable(cell):
		_cells[cell.x][cell.y] = piece


func get_ice(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return 0
	return _ice[cell.x][cell.y]


## Total number of ice layers left on the board (for the "clear the ice" goal).
func total_ice() -> int:
	var total := 0
	for x in width:
		for y in height:
			total += int(_ice[x][y])
	return total


## Color at a cell, or NO_COLOR for holes / empty cells / outside the board.
func _color_at(cell: Vector2i) -> int:
	var piece := get_piece(cell)
	if piece == null:
		return NO_COLOR
	return piece.color


static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	# Adjacent = exactly one step apart horizontally OR vertically (no diagonals).
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _new_piece(color: int, special: int = Special.NONE) -> Piece:
	var piece := Piece.new(_next_id, color, special)
	_next_id += 1
	return piece


func _random_color() -> int:
	return rng.randi_range(0, num_colors - 1)


# ---------------------------------------------------------------------------
# Swapping
# ---------------------------------------------------------------------------

## Exchanges the pieces in two cells. No rule checks here: see is_valid_swap().
func swap(a: Vector2i, b: Vector2i) -> void:
	var temp: Piece = _cells[a.x][a.y]
	_cells[a.x][a.y] = _cells[b.x][b.y]
	_cells[b.x][b.y] = temp


## A swap is valid if the two cells are neighbours with pieces in them AND
## either one of them is a special piece (specials can always be fired)
## or the swap creates at least one match.
func is_valid_swap(a: Vector2i, b: Vector2i) -> bool:
	if not (is_playable(a) and is_playable(b) and are_adjacent(a, b)):
		return false
	var pa := get_piece(a)
	var pb := get_piece(b)
	if pa == null or pb == null:
		return false
	if pa.special != Special.NONE or pb.special != Special.NONE:
		return true
	# Try it, look, undo it. Cheap, because we only look around the two cells.
	swap(a, b)
	var makes_match := _has_match_at(a) or _has_match_at(b)
	swap(a, b)
	return makes_match


## True if the piece at `cell` is part of a horizontal or vertical line of 3+.
func _has_match_at(cell: Vector2i) -> bool:
	var color := _color_at(cell)
	if color < 0:
		return false
	var horizontal := 1 + _count_same(cell, Vector2i.LEFT, color) + _count_same(cell, Vector2i.RIGHT, color)
	var vertical := 1 + _count_same(cell, Vector2i.UP, color) + _count_same(cell, Vector2i.DOWN, color)
	return horizontal >= 3 or vertical >= 3


## Counts how many pieces of `color` follow `cell` in direction `dir`.
func _count_same(cell: Vector2i, dir: Vector2i, color: int) -> int:
	var count := 0
	var current := cell + dir
	while _color_at(current) == color:
		count += 1
		current += dir
	return count


## Searches for any valid move. Returns [a, b] or [] if the board is stuck.
## Used for the "hint" animation and to decide when to shuffle.
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


## When a swap involves special pieces, they explode even without a match.
## Call this AFTER swap(a, b). Returns a list of "forced activations":
##   Array of { "cell": Vector2i, "target_color": int }
## `target_color` only matters for rainbows (which color they wipe out).
func special_swap_activations(a: Vector2i, b: Vector2i) -> Array:
	var pa := get_piece(a)
	var pb := get_piece(b)
	if pa == null or pb == null:
		return []
	var forced: Array = []

	# Rainbow + rainbow: wipe the whole board.
	if pa.special == Special.RAINBOW and pb.special == Special.RAINBOW:
		forced.append({"cell": a, "target_color": ALL_COLORS})
		return forced

	# Rainbow + anything: remove every piece with the other piece's color.
	if pa.special == Special.RAINBOW:
		forced.append({"cell": a, "target_color": pb.color})
		return forced
	if pb.special == Special.RAINBOW:
		forced.append({"cell": b, "target_color": pa.color})
		return forced

	# Rockets and bombs simply go off where they are.
	if pa.special != Special.NONE:
		forced.append({"cell": a, "target_color": -1})
	if pb.special != Special.NONE:
		forced.append({"cell": b, "target_color": -1})
	return forced


# ---------------------------------------------------------------------------
# Finding matches
# ---------------------------------------------------------------------------

## Finds every straight line ("run") of 3+ same colored pieces.
## Returns Array of { "cells": Array[Vector2i], "horizontal": bool, "color": int }
func _find_runs() -> Array:
	var runs: Array = []

	# Horizontal runs: walk each row from left to right.
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
					runs.append({"cells": cells, "horizontal": true, "color": color})
			x += length

	# Vertical runs: walk each column from top to bottom. Same idea.
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
					runs.append({"cells": cells, "horizontal": false, "color": color})
			y += length

	return runs


## Groups runs that share a cell. An L or T shape is one horizontal run plus
## one vertical run that cross, and we want to treat it as ONE match.
## Returns Array of { "cells": Dictionary(Vector2i -> true), "runs": Array, "color": int }
func find_matches() -> Array:
	var groups: Array = []
	for run in _find_runs():
		var run_cells: Array = run["cells"]
		var merged := {"cells": {}, "runs": [run], "color": run["color"]}
		for cell in run_cells:
			merged["cells"][cell] = true

		# Absorb every existing group this run touches.
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


## Decides which special piece (if any) a match group creates.
func _special_for_group(group: Dictionary) -> int:
	var longest := 0
	var longest_horizontal := true
	var has_horizontal := false
	var has_vertical := false
	for run in group["runs"]:
		var length: int = run["cells"].size()
		var horizontal: bool = run["horizontal"]
		if horizontal:
			has_horizontal = true
		else:
			has_vertical = true
		if length > longest:
			longest = length
			longest_horizontal = horizontal

	if longest >= 5:
		return Special.RAINBOW
	if has_horizontal and has_vertical:
		return Special.BOMB  # L or T shape
	if longest == 4:
		return Special.ROCKET_H if longest_horizontal else Special.ROCKET_V
	return Special.NONE


## Where should a newly created special appear?
## Where the player dragged the piece, if that cell is part of the match
## (that feels right to players). Otherwise in the middle of the longest run.
func _pick_spawn_cell(group: Dictionary, preferred_cells: Array) -> Vector2i:
	var group_cells: Dictionary = group["cells"]
	for cell in preferred_cells:
		if group_cells.has(cell):
			return cell
	var longest: Array = []
	for run in group["runs"]:
		var cells: Array = run["cells"]
		if cells.size() > longest.size():
			longest = cells
	return longest[int(longest.size() / 2.0)]


# ---------------------------------------------------------------------------
# Resolving a step: matches -> explosions -> removal -> new specials
# ---------------------------------------------------------------------------

## Performs ONE clear step and returns what happened.
##
##   preferred_cells : the two swapped cells (for placing new specials), or []
##   forced          : specials that must go off (from special_swap_activations)
##   cascade         : 0 for the player's own match, 1, 2, ... for chain reactions.
##                     Later cascades are worth more points.
##
## If the returned result is_empty(), nothing happened and the turn is over.
func resolve_matches(preferred_cells: Array = [], forced: Array = [], cascade: int = 0) -> ClearResult:
	var result := ClearResult.new()
	# We use Dictionaries as "sets": the keys are cells, the values are unused.
	var to_clear := {}
	var creations: Array = []

	# 1) Normal matches.
	for group in find_matches():
		to_clear.merge(group["cells"])
		var special := _special_for_group(group)
		if special != Special.NONE:
			creations.append({
				"cell": _pick_spawn_cell(group, preferred_cells),
				"special": special,
				"color": group["color"],
			})

	# 2) Specials the player fired by swapping them.
	var target_colors := {}
	for activation in forced:
		to_clear[activation["cell"]] = true
		target_colors[activation["cell"]] = activation["target_color"]

	# 3) Chain reactions. Every special piece that is about to be removed
	#    explodes, which may hit more specials, and so on. This is a classic
	#    "work list" (breadth-first) algorithm: keep a list of cells still to
	#    check, and add new cells to it as explosions reach them.
	var exploded := {}
	var work: Array = to_clear.keys()
	while not work.is_empty():
		var cell: Vector2i = work.pop_back()
		if exploded.has(cell):
			continue
		var piece := get_piece(cell)
		if piece == null or piece.special == Special.NONE:
			continue
		exploded[cell] = true
		result.activated.append({"cell": cell, "special": piece.special})
		var target: int = target_colors.get(cell, -1)
		for hit in _special_area(cell, piece, target):
			if not to_clear.has(hit):
				to_clear[hit] = true
				work.append(hit)

	# 4) Remove pieces and crack ice underneath them.
	for key in to_clear.keys():
		var cell: Vector2i = key
		var piece := get_piece(cell)
		if piece == null or not is_playable(cell):
			continue
		result.removed.append({"piece": piece, "cell": cell})
		_cells[cell.x][cell.y] = null
		if _ice[cell.x][cell.y] > 0:
			_ice[cell.x][cell.y] -= 1
			result.ice_hits.append(cell)

	# 5) Place the newly created specials (they replace a removed piece).
	for creation in creations:
		var cell: Vector2i = creation["cell"]
		var special: int = creation["special"]
		var color: int = RAINBOW_COLOR if special == Special.RAINBOW else int(creation["color"])
		var piece := _new_piece(color, special)
		_cells[cell.x][cell.y] = piece
		result.created.append({"piece": piece, "cell": cell})

	result.score = result.removed.size() * POINTS_PER_PIECE * (cascade + 1) \
			+ creations.size() * POINTS_PER_SPECIAL
	return result


## Which cells does a special piece hit when it explodes at `cell`?
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
			for dx in range(-BOMB_RADIUS, BOMB_RADIUS + 1):
				for dy in range(-BOMB_RADIUS, BOMB_RADIUS + 1):
					cells.append(cell + Vector2i(dx, dy))
		Special.RAINBOW:
			# A rainbow set off by a chain reaction (not by a swap) picks the
			# most common color, which is the most helpful choice for the player.
			var color := target_color
			if color < 0 and color != ALL_COLORS:
				color = _most_common_color()
			for x in width:
				for y in height:
					var other := get_piece(Vector2i(x, y))
					if other != null and (color == ALL_COLORS or other.color == color):
						cells.append(Vector2i(x, y))
	# Drop cells that are outside the board or holes.
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


# ---------------------------------------------------------------------------
# Gravity and refilling
# ---------------------------------------------------------------------------

## Makes pieces fall into empty cells and spawns new pieces at the top.
## Holes are skipped: a piece above a hole falls "through" it to the next
## playable cell, which keeps the logic simple and works fine visually.
##
## Returns { "moves": Array, "spawns": Array } where every entry is
##   { "piece": Piece, "from": Vector2i, "to": Vector2i }
## For spawns, "from" is ABOVE the board (negative y) so the view can animate
## the new piece dropping in.
func apply_gravity() -> Dictionary:
	var moves: Array = []
	var spawns: Array = []

	for x in width:
		# The playable cells of this column, from the BOTTOM up.
		var slots: Array = []
		for y in range(height - 1, -1, -1):
			if _playable[x][y]:
				slots.append(Vector2i(x, y))

		# "Two pointer" compaction: `read` scans every slot bottom-up, `write`
		# is the lowest slot that still needs a piece.
		var write := 0
		for read in slots.size():
			var from: Vector2i = slots[read]
			var piece: Piece = _cells[from.x][from.y]
			if piece == null:
				continue
			var to: Vector2i = slots[write]
			if to != from:
				_cells[to.x][to.y] = piece
				_cells[from.x][from.y] = null
				moves.append({"piece": piece, "from": from, "to": to})
			write += 1

		# Every slot from `write` upwards is now empty: spawn new pieces.
		for i in range(write, slots.size()):
			var to: Vector2i = slots[i]
			var piece := _new_piece(_random_color())
			_cells[to.x][to.y] = piece
			# Stack the spawn points above the board so pieces arrive in order.
			var start := Vector2i(x, -1 - (i - write))
			spawns.append({"piece": piece, "from": start, "to": to})

	return {"moves": moves, "spawns": spawns}


# ---------------------------------------------------------------------------
# Shuffling when stuck
# ---------------------------------------------------------------------------

## Rearranges the existing pieces until the board has no matches and at least
## one possible move. Returns the moves for animation:
##   Array of { "piece": Piece, "from": Vector2i, "to": Vector2i }
func shuffle() -> Array:
	var cells: Array = []
	var pieces: Array = []
	var original := {}  # piece id -> cell before shuffling
	for x in width:
		for y in height:
			var piece := get_piece(Vector2i(x, y))
			if piece != null:
				cells.append(Vector2i(x, y))
				pieces.append(piece)
				original[piece.id] = Vector2i(x, y)

	var solved := false
	for attempt in 200:
		# Fisher-Yates shuffle: the standard, unbiased way to shuffle an array.
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

	# Very unlikely fallback: recolor the normal pieces (keeping their ids, so
	# the view can simply refresh them) until the board is valid.
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
