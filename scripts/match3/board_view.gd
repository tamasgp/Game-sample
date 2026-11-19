## BoardView: shows the BoardModel on screen and turns touches into moves.
##
## RESPONSIBILITIES
##   * draw the board background, weeds and crates (in _draw())
##   * own one TileView node per piece and keep them in sync with the model
##   * read input: swipe a piece, or tap one piece and then a neighbour
##   * run the TURN LOOP and animate every step with tweens
##   * the shovel tool and the end-of-level bonus
##   * tell the game screen what happened, using SIGNALS
##
## It knows nothing about levels, goals, moves or coins. Those belong to the
## game screen (game_screen.gd). Because of that, this board could be reused
## in another game mode without changes.
##
## ============================================================================
## COROUTINES WITH `await`
## ============================================================================
## _play_turn() contains lines like `await _animate_clear(result)`. `await`
## PAUSES the function until the animation is done, then continues on the next
## line. The rest of the game keeps running meanwhile. So a long sequence of
## animations can be written as normal top-to-bottom code instead of a chain of
## callbacks. A function that contains `await` is called a coroutine.
class_name BoardView
extends Node2D

## A valid swap was made: the player used up one move.
signal move_committed
## Pieces/crates/weeds were cleared. The game screen updates score and goals.
signal pieces_cleared(result: BoardModel.ClearResult)
## The whole turn (all cascades included) is finished and the board is idle.
signal turn_finished
## The shovel was used on a cell (the game screen takes one shovel away).
signal tool_used

## One cell is 80 "board pixels". The game screen scales the whole node to
## fit the screen, so this number never needs to change.
const TILE := 80.0
## How far a finger must move (board pixels) before it counts as a swipe.
const SWIPE_THRESHOLD := TILE * 0.35
## Seconds of doing nothing before a hint is shown.
const HINT_DELAY := 5.0
const NO_CELL := Vector2i(-1, -1)

# Animation timings in seconds. Tweak these to change the game's "feel".
const SWAP_TIME := 0.18
const CLEAR_TIME := 0.22
const FLIGHT_TIME := 0.4
const FALL_TIME_PER_ROW := 0.07
const FALL_TIME_MIN := 0.15

var model: BoardModel
## False = ignore input (level over, popup open, bonus playing...).
var input_enabled: bool = true
## True while a turn is being animated. Input is ignored meanwhile.
var busy: bool = false
## "" = normal play. "shovel" = the next tap hits a cell with the shovel.
var tool_mode: String = ""

## piece id -> TileView. How we find the picture of a model piece.
var _tiles: Dictionary = {}
var _press_cell: Vector2i = NO_CELL
var _press_pos: Vector2 = Vector2.ZERO
var _selected: Vector2i = NO_CELL
var _idle_time: float = 0.0
var _hint_cells: Array = []


# =============================================================================
# SETUP AND COORDINATES
# =============================================================================

## Connects the view to a model and creates a TileView for every piece.
func setup(p_model: BoardModel) -> void:
	model = p_model
	for tile in _tiles.values():
		tile.queue_free()
	_tiles.clear()
	for x in model.width:
		for y in model.height:
			var piece := model.get_piece(Vector2i(x, y))
			if piece != null:
				_create_tile(piece, Vector2i(x, y))
	queue_redraw()


func board_size() -> Vector2:
	return Vector2(model.width, model.height) * TILE


## Center of a cell in this node's local coordinates.
func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


## The cell under a local position (may be outside the board).
func pos_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func _create_tile(piece: BoardModel.Piece, cell: Vector2i) -> TileView:
	var tile := TileView.new()
	tile.setup(piece, TILE)
	tile.position = cell_to_pos(cell)
	add_child(tile)
	_tiles[piece.id] = tile
	return tile


func _tile_at(cell: Vector2i) -> TileView:
	var piece := model.get_piece(cell)
	if piece == null or not _tiles.has(piece.id):
		return null
	return _tiles[piece.id]


## Redraws the tile at a cell after its piece changed (e.g. became special).
func refresh_cell(cell: Vector2i) -> void:
	var tile := _tile_at(cell)
	if tile != null:
		tile.refresh(model.get_piece(cell))


# =============================================================================
# DRAWING THE BOARD: cells, weeds, crates
# =============================================================================
# Children (the TileViews) are drawn AFTER their parent, so everything drawn
# here appears UNDER the pieces. Weeds should be under pieces, so that works
# well. Crate cells have no piece, so drawing crates here is fine too.

func _draw() -> void:
	if model == null:
		return
	for x in model.width:
		for y in model.height:
			var cell := Vector2i(x, y)
			if not model.is_playable(cell):
				continue
			var rect := Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)).grow(-2.0)
			# A light checkerboard helps the eye follow rows and columns.
			var shade := Color(0.85, 0.75, 0.55, 0.85) if (x + y) % 2 == 0 else Color(0.78, 0.67, 0.47, 0.85)
			draw_rect(rect, shade)

			var weeds := model.get_weeds(cell)
			if weeds > 0:
				_draw_weeds(rect, weeds)
			if model.has_crate(cell):
				_draw_crate(rect, model.crate_hp(cell))


## Weeds: green tufts. Two layers = denser and darker.
func _draw_weeds(rect: Rect2, layers: int) -> void:
	var green := Color(0.3, 0.6, 0.2) if layers == 1 else Color(0.18, 0.42, 0.12)
	draw_rect(rect.grow(-3.0), Color(green, 0.55))
	# A few grass blades. The positions are fixed fractions of the cell so
	# they don't jump around every time the board is redrawn.
	var blades := [Vector2(0.2, 0.85), Vector2(0.35, 0.8), Vector2(0.5, 0.88), Vector2(0.68, 0.82), Vector2(0.82, 0.86)]
	for i in blades.size():
		var base: Vector2 = rect.position + blades[i] * rect.size
		var tip := base + Vector2((i % 3 - 1) * 6.0, -rect.size.y * (0.35 + 0.1 * layers))
		draw_line(base, tip, green.darkened(0.2), 4.0, true)


## Crates: wooden planks. Damaged (1 hp left of 2) crates show cracks.
func _draw_crate(rect: Rect2, hp: int) -> void:
	var inner := rect.grow(-4.0)
	var wood := Color(0.62, 0.42, 0.2) if hp >= 2 else Color(0.72, 0.52, 0.28)
	draw_rect(inner, wood)
	draw_rect(inner, wood.darkened(0.45), false, 4.0)
	# Planks and a diagonal brace, like a real crate.
	for i in range(1, 3):
		var y := inner.position.y + inner.size.y * i / 3.0
		draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), wood.darkened(0.3), 2.0)
	draw_line(inner.position, inner.end, wood.darkened(0.35), 5.0)
	if hp >= 2:
		# Metal corners mark a tough crate.
		for corner in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
			draw_circle(corner, 6.0, Color(0.6, 0.62, 0.66))


# =============================================================================
# INPUT
# =============================================================================
# A Node2D isn't part of the GUI system, so we use _input(), which sees every
# event first. We then check ourselves that the touch is on the board.
# Touches arrive as mouse events ("emulate_mouse_from_touch" in project.godot),
# so one handler covers mouse AND touch screens.

func _input(event: InputEvent) -> void:
	if model == null or not input_enabled or busy:
		return
	# Convert from screen coordinates into OURS (our position and scale).
	var local_event := make_input_local(event)

	var button := local_event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_reset_idle()
		var cell := pos_to_cell(button.position)
		if button.pressed:
			if tool_mode != "":
				# Tool mode: the press itself is the action.
				if model.is_playable(cell) and (model.get_piece(cell) != null or model.has_crate(cell)):
					_play_tool(cell)
				return
			if model.get_piece(cell) != null:
				_press_cell = cell
				_press_pos = button.position
			else:
				_press_cell = NO_CELL
				_set_selected(NO_CELL)
		else:
			# Released without swiping far enough: treat it as a tap.
			if _press_cell != NO_CELL and cell == _press_cell:
				_on_tap(cell)
			_press_cell = NO_CELL
		return

	var motion := local_event as InputEventMouseMotion
	if motion != null and _press_cell != NO_CELL:
		var delta := motion.position - _press_pos
		if delta.length() >= SWIPE_THRESHOLD:
			var dir := Vector2i.ZERO
			if absf(delta.x) > absf(delta.y):
				dir = Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
			else:
				dir = Vector2i.DOWN if delta.y > 0 else Vector2i.UP
			var from := _press_cell
			_press_cell = NO_CELL   # one swipe = one swap
			_try_swap(from, from + dir)


## Tap-tap controls: the first tap selects, tapping a neighbour swaps.
func _on_tap(cell: Vector2i) -> void:
	if _selected == NO_CELL:
		_set_selected(cell)
	elif _selected == cell:
		_set_selected(NO_CELL)
	elif BoardModel.are_adjacent(_selected, cell):
		var from := _selected
		_set_selected(NO_CELL)
		_try_swap(from, cell)
	else:
		_set_selected(cell)


func _set_selected(cell: Vector2i) -> void:
	if _selected != NO_CELL:
		var old_tile := _tile_at(_selected)
		if old_tile != null:
			old_tile.selected = false
	_selected = cell
	if cell != NO_CELL:
		var tile := _tile_at(cell)
		if tile != null:
			tile.selected = true


func _try_swap(a: Vector2i, b: Vector2i) -> void:
	_set_selected(NO_CELL)
	if model.get_piece(a) == null or model.get_piece(b) == null:
		return
	# Start the coroutine WITHOUT await: the input handler returns right away
	# and the turn plays out over the next frames.
	_play_turn(a, b)


# =============================================================================
# THE TURN LOOP
# =============================================================================

func _play_turn(a: Vector2i, b: Vector2i) -> void:
	busy = true
	_reset_idle()

	# 1) Swap in the model, then animate both tiles to their new cells.
	model.swap(a, b)
	await _animate_to_model_positions([a, b], SWAP_TIME)

	# 2) Did it do anything? Specials always fire; otherwise we need a match.
	var forced := model.special_swap_activations(a, b)
	var result := model.resolve_matches([a, b], forced, 0)
	if result.is_empty():
		# Not a valid move: swap back. The player does NOT lose a move.
		model.swap(a, b)
		await _animate_to_model_positions([a, b], SWAP_TIME)
		busy = false
		return

	move_committed.emit()
	await _resolve_loop(result)
	busy = false
	turn_finished.emit()


## Uses the shovel on a cell.
func _play_tool(cell: Vector2i) -> void:
	busy = true
	tool_mode = ""
	tool_used.emit()
	var result := model.resolve_matches([], [], 0, [cell])
	await _resolve_loop(result)
	busy = false
	turn_finished.emit()


## The cascade loop shared by swaps, tools and the bonus:
## clear -> fall -> look for new matches -> repeat. Shuffles if stuck.
func _resolve_loop(first_result: BoardModel.ClearResult) -> void:
	var result := first_result
	var cascade := 0
	while not result.is_empty():
		pieces_cleared.emit(result)
		await _animate_clear(result, cascade)
		var gravity := model.apply_gravity()
		await _animate_gravity(gravity)
		cascade += 1
		result = model.resolve_matches([], [], cascade)

	if model.find_possible_move().is_empty():
		var moves := model.shuffle()
		await _animate_shuffle(moves)
	_idle_time = 0.0   # the hint timer starts at the end of the turn


## End-of-level BONUS: every move left over turns a random piece into a
## rocket, then they all fire. Pure celebration (and extra score)! The game
## screen awaits this coroutine before showing the results.
func play_bonus(rockets: int) -> void:
	busy = true
	var forced: Array = []
	for i in rockets:
		var cell := model.place_special_randomly(BoardModel.Special.ROCKET_H)
		if cell == BoardModel.NO_CELL:
			break
		refresh_cell(cell)
		var tile := _tile_at(cell)
		if tile != null:
			# A quick "pop" so the player sees each rocket appear.
			tile.scale = Vector2(1.6, 1.6)
			create_tween().tween_property(tile, "scale", Vector2.ONE, 0.2)
		forced.append({"cell": cell, "target_color": -1, "combo": "", "consumed": []})
		await get_tree().create_timer(0.08).timeout
	if not forced.is_empty():
		await _resolve_loop(model.resolve_matches([], forced, 0))
	busy = false


# =============================================================================
# ANIMATIONS
# =============================================================================

## Moves the tiles of the pieces now in `cells` to those cells' positions.
func _animate_to_model_positions(cells: Array, duration: float) -> void:
	var tween := create_tween().set_parallel(true)
	var count := 0
	for cell in cells:
		var tile := _tile_at(cell)
		if tile != null:
			tween.tween_property(tile, "position", cell_to_pos(cell), duration) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			count += 1
	await _finish(tween, count)


## Waits for a tween, or kills it if it has no animations.
## (Godot reports an error when a Tween runs with nothing in it.)
func _finish(tween: Tween, animation_count: int) -> void:
	if animation_count == 0:
		tween.kill()
		return
	await tween.finished


func _animate_clear(result: BoardModel.ClearResult, cascade: int) -> void:
	# 1) Butterflies fly to their targets first.
	if not result.flights.is_empty():
		await _animate_flights(result.flights)

	# 2) Explosion effects (fire and forget: they delete themselves).
	for activation in result.activated:
		_spawn_special_effect(activation["cell"], activation["special"], activation["combo"])
	for hit in result.crate_hits:
		var color := Color(0.7, 0.5, 0.25) if hit["destroyed"] else Color(1, 0.9, 0.6)
		BoardEffect.spawn(self, BoardEffect.Kind.SPARKLE, cell_to_pos(hit["cell"]), TILE * 0.7, 0.0, color)

	# 3) Removed pieces shrink and fade; new specials pop in.
	var tween := create_tween().set_parallel(true)
	var count := 0
	var dying: Array = []
	var center := Vector2.ZERO
	for entry in result.removed:
		var piece: BoardModel.Piece = entry["piece"]
		if not _tiles.has(piece.id):
			continue
		var tile: TileView = _tiles[piece.id]
		_tiles.erase(piece.id)
		dying.append(tile)
		center += tile.position
		tween.tween_property(tile, "scale", Vector2.ZERO, CLEAR_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(tile, "modulate:a", 0.0, CLEAR_TIME)
		count += 1

	for entry in result.created:
		var new_tile := _create_tile(entry["piece"], entry["cell"])
		new_tile.scale = Vector2.ZERO
		tween.tween_property(new_tile, "scale", Vector2.ONE, CLEAR_TIME * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		count += 1

	if not dying.is_empty():
		_spawn_score_popup(center / dying.size(), result.score, cascade)

	# Weeds and crates are drawn in _draw(), so ask for a redraw.
	if not result.weed_hits.is_empty() or not result.crate_hits.is_empty():
		queue_redraw()

	await _finish(tween, count)
	for tile in dying:
		tile.queue_free()


## A butterfly picture flies from its cell to its target along a curve.
func _animate_flights(flights: Array) -> void:
	var tween := create_tween().set_parallel(true)
	var flyers: Array = []
	for flight in flights:
		var flyer := TileView.new()
		flyer.setup(BoardModel.Piece.new(0, 0, BoardModel.Special.BUTTERFLY), TILE)
		flyer.position = cell_to_pos(flight["from"])
		flyer.z_index = 20
		add_child(flyer)
		flyers.append(flyer)
		var start: Vector2 = flyer.position
		var end := cell_to_pos(flight["to"])
		# tween_method calls a function with values from 0.0 to 1.0. We use it
		# to follow a CURVE: a straight line plus an upward arc (sin(t * PI)
		# is 0 at both ends and 1 in the middle).
		# `func(t): ...` is a LAMBDA: a small unnamed function stored in a
		# variable. It "captures" flyer, start and end from this loop iteration.
		var follow_curve := func(t: float) -> void:
			flyer.position = start.lerp(end, t) + Vector2(0, -TILE * 1.5 * sin(t * PI))
		tween.tween_method(follow_curve, 0.0, 1.0, FLIGHT_TIME)
	await tween.finished
	for flyer in flyers:
		flyer.queue_free()


func _animate_gravity(gravity: Dictionary) -> void:
	var tween := create_tween().set_parallel(true)
	var count := 0

	for move in gravity["moves"]:
		var piece: BoardModel.Piece = move["piece"]
		var tile: TileView = _tiles.get(piece.id)
		if tile == null:
			continue
		var to: Vector2i = move["to"]
		var from: Vector2i = move["from"]
		_tween_fall(tween, tile, to, to.y - from.y)
		count += 1

	for spawn in gravity["spawns"]:
		var from: Vector2i = spawn["from"]
		var to: Vector2i = spawn["to"]
		var tile := _create_tile(spawn["piece"], to)
		tile.position = cell_to_pos(from)
		# New pieces start invisible above the board and fade in while they
		# drop, so we don't need to hide (clip) the area above the board.
		tile.modulate.a = 0.0
		tween.tween_property(tile, "modulate:a", 1.0, 0.15)
		_tween_fall(tween, tile, to, to.y - from.y)
		count += 1

	await _finish(tween, count)


## Falling uses TRANS_BOUNCE, so pieces land with a little bounce.
func _tween_fall(tween: Tween, tile: TileView, to: Vector2i, rows: int) -> void:
	var duration := maxf(FALL_TIME_MIN, rows * FALL_TIME_PER_ROW)
	tween.tween_property(tile, "position", cell_to_pos(to), duration) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _animate_shuffle(moves: Array) -> void:
	_spawn_text_popup(board_size() / 2.0, "Shuffle!", Color(1, 1, 1), 48)
	var tween := create_tween().set_parallel(true)
	var count := 0
	for move in moves:
		var piece: BoardModel.Piece = move["piece"]
		var tile: TileView = _tiles.get(piece.id)
		if tile == null:
			continue
		tile.refresh(piece)   # the shuffle fallback may have changed the color
		tween.tween_property(tile, "position", cell_to_pos(move["to"]), 0.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		count += 1
	await _finish(tween, count)


func _spawn_special_effect(cell: Vector2i, special: int, combo: String) -> void:
	var pos := cell_to_pos(cell)
	var size := board_size()
	var beam := TILE * 0.7
	match combo:
		"cross":
			BoardEffect.spawn(self, BoardEffect.Kind.ROW_BEAM, Vector2(size.x / 2.0, pos.y), size.x, beam)
			BoardEffect.spawn(self, BoardEffect.Kind.COLUMN_BEAM, Vector2(pos.x, size.y / 2.0), size.y, beam)
			return
		"big_cross":
			BoardEffect.spawn(self, BoardEffect.Kind.ROW_BEAM, Vector2(size.x / 2.0, pos.y), size.x, TILE * 3.0)
			BoardEffect.spawn(self, BoardEffect.Kind.COLUMN_BEAM, Vector2(pos.x, size.y / 2.0), size.y, TILE * 3.0)
			return
		"big_bomb":
			BoardEffect.spawn(self, BoardEffect.Kind.BLAST, pos, TILE * (BoardModel.BIG_BOMB_RADIUS + 0.5), 0.0, Color(1, 0.6, 0.2))
			return
		"all":
			BoardEffect.spawn(self, BoardEffect.Kind.SPARKLE, size / 2.0, size.x, 0.0, Color(1, 0.6, 1))
			return
	match special:
		BoardModel.Special.ROCKET_H:
			BoardEffect.spawn(self, BoardEffect.Kind.ROW_BEAM, Vector2(size.x / 2.0, pos.y), size.x, beam)
		BoardModel.Special.ROCKET_V:
			BoardEffect.spawn(self, BoardEffect.Kind.COLUMN_BEAM, Vector2(pos.x, size.y / 2.0), size.y, beam)
		BoardModel.Special.BOMB:
			BoardEffect.spawn(self, BoardEffect.Kind.BLAST, pos, TILE * (BoardModel.BOMB_RADIUS + 0.5), 0.0, Color(1, 0.6, 0.2))
		BoardModel.Special.RAINBOW:
			BoardEffect.spawn(self, BoardEffect.Kind.SPARKLE, pos, TILE * 2.0, 0.0, Color(1, 0.5, 1))
		BoardModel.Special.BUTTERFLY:
			BoardEffect.spawn(self, BoardEffect.Kind.BLAST, pos, TILE * 1.2, 0.0, Color(1, 0.5, 0.8))


func _spawn_score_popup(pos: Vector2, points: int, cascade: int) -> void:
	var text := "+%d" % points
	if cascade > 0:
		text += "  x%d" % (cascade + 1)
	_spawn_text_popup(pos, text, UIStyle.ACCENT, 32 + cascade * 4)


## Floating text that drifts up, fades out and deletes itself.
func _spawn_text_popup(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var label := UIStyle.label(text, font_size, color)
	label.size = Vector2(300, 60)
	label.position = pos - label.size / 2.0
	label.z_index = 30
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# =============================================================================
# HINTS
# =============================================================================

func _process(delta: float) -> void:
	if model == null or busy or not input_enabled:
		return
	_idle_time += delta
	if _idle_time >= HINT_DELAY and _hint_cells.is_empty():
		_hint_cells = model.find_possible_move()
		for cell in _hint_cells:
			var tile := _tile_at(cell)
			if tile != null:
				tile.hinting = true


func _reset_idle() -> void:
	_idle_time = 0.0
	_clear_hint()


func _clear_hint() -> void:
	for cell in _hint_cells:
		var tile := _tile_at(cell)
		if tile != null:
			tile.hinting = false
	_hint_cells.clear()
