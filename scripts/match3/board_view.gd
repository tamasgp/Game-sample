## BoardView: shows the BoardModel on screen and turns player input into moves.
##
## RESPONSIBILITIES
##   * Draw the board background and ice (in _draw()).
##   * Own one TileView node per piece and keep them in sync with the model.
##   * Read touch/mouse input: swipe a piece, or tap one piece then a neighbour.
##   * Run the TURN LOOP and animate every step with Tweens.
##   * Tell the game screen what happened, using signals.
##
## It does NOT know about levels, goals, moves or score. That's the game
## screen's job (game_screen.gd). Keeping it this way means you could reuse the
## board in a different game mode (endless mode, time attack, ...) unchanged.
##
## COROUTINES WITH `await`
## -----------------------
## The turn loop (_play_turn) uses `await` to pause until an animation is
## finished, then continues on the next line. The game keeps running while it
## waits (other nodes still update and draw). This lets us write a sequence of
## animations as normal top-to-bottom code instead of a pile of callbacks.
class_name BoardView
extends Node2D

## A valid swap was made, so the player used up one move.
signal move_committed
## Pieces were cleared. The game screen updates score and goals from this.
signal pieces_cleared(result: BoardModel.ClearResult)
## The whole turn (including all cascades) is over and the board is idle.
signal turn_finished

## Size of one cell in "board pixels". The game screen scales the whole
## BoardView node to fit the screen, so this number never needs to change.
const TILE := 80.0
## How far (in board pixels) a finger must move before it counts as a swipe.
const SWIPE_THRESHOLD := TILE * 0.35
## Seconds of doing nothing before we show a hint.
const HINT_DELAY := 5.0
## Means "no cell". (Vector2i can't be null, so we use an impossible value.)
const NO_CELL := Vector2i(-1, -1)

# Animation timings, in seconds. Tweak these to change the "feel".
const SWAP_TIME := 0.18
const CLEAR_TIME := 0.22
const FALL_TIME_PER_ROW := 0.07
const FALL_TIME_MIN := 0.15

var model: BoardModel
## When false the board ignores input (used when the level is over).
var input_enabled: bool = true
## True while a turn is being animated. Input is ignored while busy.
var busy: bool = false

## piece id -> TileView. This is how we find the node for a model piece.
var _tiles: Dictionary = {}
## Where the current press/touch started.
var _press_cell: Vector2i = NO_CELL
var _press_pos: Vector2 = Vector2.ZERO
## Cell selected by a tap (for tap-tap swapping).
var _selected: Vector2i = NO_CELL
var _idle_time: float = 0.0
var _hint_cells: Array = []


# ---------------------------------------------------------------------------
# Setup and coordinate helpers
# ---------------------------------------------------------------------------

## Connects the view to a model and creates a TileView for every piece.
func setup(p_model: BoardModel) -> void:
	model = p_model
	for tile in _tiles.values():
		tile.queue_free()
	_tiles.clear()
	for x in model.width:
		for y in model.height:
			var cell := Vector2i(x, y)
			var piece := model.get_piece(cell)
			if piece != null:
				_create_tile(piece, cell)
	queue_redraw()


## Size of the whole board in board pixels.
func board_size() -> Vector2:
	return Vector2(model.width, model.height) * TILE


## Center of a cell, in this node's local coordinates.
func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


## Which cell contains a local position. May return a cell outside the board.
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


# ---------------------------------------------------------------------------
# Drawing the board background
# ---------------------------------------------------------------------------

func _draw() -> void:
	if model == null:
		return
	# Child nodes (the TileViews) are drawn AFTER their parent, so everything
	# drawn here appears underneath the pieces.
	for x in model.width:
		for y in model.height:
			var cell := Vector2i(x, y)
			if not model.is_playable(cell):
				continue
			var rect := Rect2(Vector2(x, y) * TILE, Vector2(TILE, TILE)).grow(-2.0)
			# Checkerboard pattern helps the eye find rows and columns.
			var shade := Color(0.05, 0.2, 0.4, 0.75) if (x + y) % 2 == 0 else Color(0.08, 0.27, 0.5, 0.75)
			draw_rect(rect, shade)

			var ice := model.get_ice(cell)
			if ice > 0:
				# More layers = more opaque, with a thicker frame.
				var ice_color := Color(0.75, 0.95, 1.0, 0.35 + 0.25 * ice)
				draw_rect(rect.grow(-3.0), ice_color)
				draw_rect(rect.grow(-3.0), Color(1, 1, 1, 0.9), false, 2.0 * ice)
				# A couple of diagonal "cracks" to make it read as ice.
				draw_line(rect.position + Vector2(10, 18), rect.position + Vector2(30, 8), Color(1, 1, 1, 0.8), 2.0)
				draw_line(rect.end - Vector2(12, 26), rect.end - Vector2(28, 12), Color(1, 1, 1, 0.8), 2.0)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
# We use _input() instead of _gui_input()/_unhandled_input() because a Node2D
# is not part of the GUI system. _input() sees every event first, so we must
# check ourselves that the press is actually on the board.
#
# Touches arrive as mouse events thanks to "emulate_mouse_from_touch" in
# project.godot, so this one handler covers mouse AND touch screens.

func _input(event: InputEvent) -> void:
	if model == null or not input_enabled or busy:
		return
	# Convert the event position from screen coordinates into OUR coordinates
	# (taking our position and scale into account).
	var local_event := make_input_local(event)

	var button := local_event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_reset_idle()
		var cell := pos_to_cell(button.position)
		if button.pressed:
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
			# Pick the main direction of the swipe.
			var dir := Vector2i.ZERO
			if absf(delta.x) > absf(delta.y):
				dir = Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
			else:
				dir = Vector2i.DOWN if delta.y > 0 else Vector2i.UP
			var from := _press_cell
			_press_cell = NO_CELL  # one swipe = one swap
			_try_swap(from, from + dir)


## Tap-tap controls: first tap selects, tapping a neighbour swaps.
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
	# Start the turn coroutine. We don't `await` it here: the input handler
	# returns immediately and the turn plays out over the next frames.
	_play_turn(a, b)


# ---------------------------------------------------------------------------
# The turn loop
# ---------------------------------------------------------------------------

func _play_turn(a: Vector2i, b: Vector2i) -> void:
	busy = true
	_reset_idle()

	# 1) Swap in the model, then animate the two tiles to their new cells.
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

	# 3) Cascades: clear -> fall -> check again, until the board settles.
	var cascade := 0
	while not result.is_empty():
		pieces_cleared.emit(result)
		await _animate_clear(result, cascade)
		var gravity := model.apply_gravity()
		await _animate_gravity(gravity)
		cascade += 1
		result = model.resolve_matches([], [], cascade)

	# 4) If the player has no possible move left, shuffle the board.
	if model.find_possible_move().is_empty():
		var moves := model.shuffle()
		await _animate_shuffle(moves)

	_idle_time = 0.0  # the hint timer starts counting from the end of the turn
	busy = false
	turn_finished.emit()


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

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


## Waits for a tween, or kills it if nothing was added to it.
## (Godot reports an error if a Tween runs with no animations in it.)
func _finish(tween: Tween, animation_count: int) -> void:
	if animation_count == 0:
		tween.kill()
		return
	await tween.finished


func _animate_clear(result: BoardModel.ClearResult, cascade: int) -> void:
	# Explosions first, so they appear on top of the disappearing pieces.
	for activation in result.activated:
		_spawn_special_effect(activation["cell"], activation["special"])

	# Shrink and fade every removed piece.
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

	# New special pieces "pop" into existence where the match was made.
	for entry in result.created:
		var tile := _create_tile(entry["piece"], entry["cell"])
		tile.scale = Vector2.ZERO
		tween.tween_property(tile, "scale", Vector2.ONE, CLEAR_TIME * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		count += 1

	if not dying.is_empty():
		_spawn_score_popup(center / dying.size(), result.score, cascade)

	# Ice may have cracked: redraw the background.
	if not result.ice_hits.is_empty():
		queue_redraw()

	await _finish(tween, count)
	for tile in dying:
		tile.queue_free()


func _animate_gravity(gravity: Dictionary) -> void:
	var tween := create_tween().set_parallel(true)
	var count := 0

	for move in gravity["moves"]:
		var piece: BoardModel.Piece = move["piece"]
		var tile: TileView = _tiles.get(piece.id)
		if tile == null:
			continue
		var rows: int = move["to"].y - move["from"].y
		_tween_fall(tween, tile, move["to"], rows)
		count += 1

	for spawn in gravity["spawns"]:
		var from: Vector2i = spawn["from"]
		var to: Vector2i = spawn["to"]
		var tile := _create_tile(spawn["piece"], to)
		tile.position = cell_to_pos(from)
		# New pieces start invisible above the board and fade in as they drop,
		# so we don't need to clip the area above the board.
		tile.modulate.a = 0.0
		tween.tween_property(tile, "modulate:a", 1.0, 0.15)
		_tween_fall(tween, tile, to, to.y - from.y)
		count += 1

	await _finish(tween, count)


## Falling uses TRANS_BOUNCE so pieces land with a little bounce.
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
		tile.refresh(piece)  # the shuffle fallback may have changed its color
		tween.tween_property(tile, "position", cell_to_pos(move["to"]), 0.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		count += 1
	await _finish(tween, count)


func _spawn_special_effect(cell: Vector2i, special: int) -> void:
	var pos := cell_to_pos(cell)
	var size := board_size()
	match special:
		BoardModel.Special.ROCKET_H:
			BoardEffect.spawn(self, BoardEffect.Kind.ROW_BEAM, Vector2(size.x / 2.0, pos.y), size.x, TILE * 0.7)
		BoardModel.Special.ROCKET_V:
			BoardEffect.spawn(self, BoardEffect.Kind.COLUMN_BEAM, Vector2(pos.x, size.y / 2.0), size.y, TILE * 0.7)
		BoardModel.Special.BOMB:
			BoardEffect.spawn(self, BoardEffect.Kind.BLAST, pos, TILE * (BoardModel.BOMB_RADIUS + 0.5), 0.0, Color(1, 0.6, 0.2))
		BoardModel.Special.RAINBOW:
			BoardEffect.spawn(self, BoardEffect.Kind.SPARKLE, pos, TILE * 2.0, 0.0, Color(1, 0.5, 1))


func _spawn_score_popup(pos: Vector2, points: int, cascade: int) -> void:
	var text := "+%d" % points
	if cascade > 0:
		text += "  x%d" % (cascade + 1)
	_spawn_text_popup(pos, text, UIStyle.ACCENT, 32 + cascade * 4)


## Floating text that drifts upward and fades out, then deletes itself.
func _spawn_text_popup(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var label := UIStyle.label(text, font_size, color)
	label.size = Vector2(300, 60)
	label.position = pos - label.size / 2.0
	label.z_index = 10  # draw above the tiles
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# ---------------------------------------------------------------------------
# Hints
# ---------------------------------------------------------------------------

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
