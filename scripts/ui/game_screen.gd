## GameScreen: one puzzle level. It wires all the match-3 parts together.
##
##     GameState.current_level
##            │
##            ▼
##     LevelData ──level dictionary──► GameScreen ──creates──► BoardModel
##                                         │                      ▲
##                                         │ creates              │ reads / changes
##                                         ▼                      │
##                                     BoardView ─────────────────┘
##                                         │
##                                         └── signals ──► GameScreen updates
##                                                         moves, score, goals,
##                                                         and decides win/lose
##
## The game screen owns the LEVEL rules (moves, goals, boosters, lives,
## rewards). BoardModel owns the PUZZLE rules (matching, specials, gravity).
##
## THE END OF A LEVEL
##   win:  "Level complete!" -> leftover moves become rockets (bonus) ->
##         results popup (+1 star, coins) -> back to the garden
##   out of moves: offer 5 extra moves for coins ->
##         yes: keep playing / no: lose a life -> "try again" or garden
extends Control

const GARDEN_SCENE := "res://scenes/garden.tscn"
## Coins per leftover move, paid after the bonus.
const COINS_PER_LEFTOVER_MOVE := 5

var level_index: int = 0
var level: Dictionary = {}
var model: BoardModel
var goals: LevelGoals
var moves_left: int = 0
var score: int = 0
var _level_over: bool = false

# UI nodes we update later.
var board_view: BoardView
var _board_area: Control
var _moves_label: Label
var _score_label: Label
var _goals_box: HBoxContainer
var _shovel_button: Button
var _tool_hint: Label


func _ready() -> void:
	level_index = GameState.current_level
	level = LevelData.get_level(level_index)
	moves_left = int(level["moves"])

	# --- Rules: model and goals from the level data ---
	model = BoardModel.new()
	model.setup(level["layout"], int(level["colors"]))
	_apply_pre_level_boosters()
	goals = LevelGoals.new()
	goals.setup(level["goals"], model.total_weeds(), model.total_crates())

	# --- Visuals ---
	_build_ui()
	board_view.setup(model)

	# --- Wiring ---
	# `some_signal.connect(function)`: call `function` whenever the signal is
	# emitted. Children talk UP to their parent this way, without knowing
	# anything about the parent. ("Call down, signal up.")
	board_view.move_committed.connect(_on_move_committed)
	board_view.pieces_cleared.connect(_on_pieces_cleared)
	board_view.turn_finished.connect(_on_turn_finished)
	board_view.tool_used.connect(_on_tool_used)
	goals.changed.connect(_refresh_goals)
	GameState.boosters_changed.connect(_refresh_shovel)
	_board_area.resized.connect(_fit_board)

	_refresh_hud()
	_refresh_goals()
	_refresh_shovel()
	# Containers finish computing their sizes later this frame, so we wait
	# with call_deferred() before measuring the board area.
	_fit_board.call_deferred()


## Boosters chosen on the level start popup become special pieces on the board.
func _apply_pre_level_boosters() -> void:
	var specials := {
		"rocket": BoardModel.Special.ROCKET_H,
		"bomb": BoardModel.Special.BOMB,
		"rainbow": BoardModel.Special.RAINBOW,
	}
	for id in GameState.pending_boosters:
		if specials.has(id):
			model.place_special_randomly(specials[id])
	GameState.pending_boosters.clear()


func _draw() -> void:
	UIStyle.draw_vertical_gradient(self, Rect2(Vector2.ZERO, size), UIStyle.BG_TOP, UIStyle.BG_BOTTOM)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# =============================================================================
# BUILDING THE UI
# =============================================================================
#   [ Quit ]      Level 12 / Score         Moves 20
#   [goal] [goal]
#   ┌──────────────────────────────┐
#   │           board              │   <- takes all remaining space
#   └──────────────────────────────┘
#   [ shovel x2 ]   "Tap a piece or crate"

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# ----- Top bar -----
	var top_panel := UIStyle.panel()
	column.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top_panel.add_child(top)

	var quit := UIStyle.button("Quit", 26, Vector2(120, 70), UIStyle.BLUE)
	quit.pressed.connect(_on_quit_pressed)
	top.add_child(quit)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # take the spare width
	top.add_child(info)
	info.add_child(UIStyle.label("Level %d" % (level_index + 1), 30))
	_score_label = UIStyle.label("", 22, UIStyle.TEXT_DIM)
	info.add_child(_score_label)

	var moves_box := VBoxContainer.new()
	moves_box.custom_minimum_size = Vector2(120, 0)
	top.add_child(moves_box)
	moves_box.add_child(UIStyle.label("Moves", 22, UIStyle.TEXT_DIM))
	_moves_label = UIStyle.label("", 44, UIStyle.ACCENT)
	moves_box.add_child(_moves_label)

	# ----- Goals bar -----
	var goals_panel := UIStyle.panel()
	column.add_child(goals_panel)
	_goals_box = HBoxContainer.new()
	_goals_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_goals_box.add_theme_constant_override("separation", 40)
	goals_panel.add_child(_goals_box)

	# ----- Board area -----
	_board_area = Control.new()
	_board_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_board_area)
	# A Node2D can live inside a Control; its position is then relative to
	# the Control's top-left corner.
	board_view = BoardView.new()
	_board_area.add_child(board_view)

	# ----- Booster bar -----
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	_shovel_button = UIStyle.button("", 26, Vector2(170, 90), UIStyle.ORANGE)
	_shovel_button.pressed.connect(_on_shovel_pressed)
	bottom.add_child(_shovel_button)
	# An icon inside the button, on the left.
	var shovel_icon := IconView.new("shovel", 56.0)
	shovel_icon.position = Vector2(10, 17)
	_shovel_button.add_child(shovel_icon)
	_tool_hint = UIStyle.label("", 24, UIStyle.TEXT)
	_tool_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_tool_hint)


## Scales and centers the board in its area. BoardView always works in its
## own 80-pixels-per-cell units, so we just scale the node. Input still works
## because BoardView uses make_input_local(), which includes our scale.
func _fit_board() -> void:
	if model == null:
		return
	var area := _board_area.size
	var board := board_view.board_size()
	if area.x <= 0 or area.y <= 0:
		return
	var factor := minf(area.x / board.x, area.y / board.y)
	board_view.scale = Vector2(factor, factor)
	# Centered horizontally, at the TOP vertically (close to the goals).
	board_view.position = Vector2((area.x - board.x * factor) / 2.0, 0.0)


# =============================================================================
# HUD UPDATES
# =============================================================================

func _refresh_hud() -> void:
	_moves_label.text = str(moves_left)
	_score_label.text = "Score: %d" % score
	var moves_color := UIStyle.HEART if moves_left <= 5 else UIStyle.ACCENT
	_moves_label.add_theme_color_override("font_color", moves_color)


## Rebuilds the goal widgets. Simple, and fast enough for 1-3 goals.
func _refresh_goals() -> void:
	for child in _goals_box.get_children():
		child.queue_free()
	for goal in goals.goals:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.add_child(_make_goal_icon(goal))
		var done := LevelGoals.is_goal_done(goal)
		var text := "Done" if done else str(LevelGoals.remaining(goal))
		item.add_child(UIStyle.label(text, 30, Color(0.6, 1, 0.5) if done else UIStyle.TEXT))
		_goals_box.add_child(item)


func _make_goal_icon(goal: Dictionary) -> Control:
	match String(goal["type"]):
		"collect":
			return UIStyle.piece_icon(int(goal["color"]), BoardModel.Special.NONE)
		"weeds":
			return _square_icon(Color(0.3, 0.6, 0.2), Color(0.15, 0.35, 0.1))
		_:
			return _square_icon(Color(0.65, 0.45, 0.22), Color(0.35, 0.22, 0.1))


func _square_icon(fill: Color, border: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(56, 56)
	var square := Panel.new()
	square.add_theme_stylebox_override("panel", UIStyle.box(fill, 6, border, 4))
	square.position = Vector2(6, 6)
	square.size = Vector2(44, 44)
	holder.add_child(square)
	return holder


func _refresh_shovel() -> void:
	var count := GameState.booster_count("shovel")
	if board_view != null and board_view.tool_mode == "shovel":
		_shovel_button.text = "     Cancel"
		_tool_hint.text = "Tap a piece or crate"
	else:
		_shovel_button.text = "     x%d" % count if count > 0 else "     +"
		_tool_hint.text = ""


# =============================================================================
# REACTING TO THE BOARD
# =============================================================================

func _on_move_committed() -> void:
	moves_left -= 1
	_refresh_hud()


func _on_pieces_cleared(result: BoardModel.ClearResult) -> void:
	score += result.score
	goals.on_pieces_removed(result.removed)
	if not result.weed_hits.is_empty() or not result.crate_hits.is_empty():
		goals.on_obstacles_remaining(model.total_weeds(), model.total_crates())
	_refresh_hud()


func _on_tool_used() -> void:
	GameState.use_booster("shovel")
	_refresh_shovel()


## Called when the board has completely settled after a move or a tool.
func _on_turn_finished() -> void:
	if _level_over:
		return
	if goals.is_complete():
		_win()
	elif moves_left <= 0:
		_offer_extra_moves()


# =============================================================================
# SHOVEL BOOSTER
# =============================================================================

func _on_shovel_pressed() -> void:
	if _level_over or board_view.busy:
		return
	if board_view.tool_mode == "shovel":
		board_view.tool_mode = ""         # tapping again cancels
	elif GameState.booster_count("shovel") > 0:
		board_view.tool_mode = "shovel"
	else:
		_offer_buy_shovel()
		return
	_refresh_shovel()


func _offer_buy_shovel() -> void:
	board_view.input_enabled = false
	var price: int = GameState.BOOSTER_PRICES["shovel"]
	var box := Modal.open(self, "Shovel")
	box.add_child(UIStyle.label("Removes any piece or hits a crate.\nIt doesn't use a move!", 26))
	var row := Modal.button_row(box)
	var buy := UIStyle.button("Buy (%d coins)" % price, 26, Vector2(260, 80), UIStyle.ORANGE)
	buy.disabled = GameState.coins < price
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A LAMBDA (a small unnamed function stored in a variable). It can use
	# `box` because lambdas "capture" the local variables around them.
	var on_buy := func() -> void:
		GameState.buy_booster("shovel")
		board_view.input_enabled = true
		Modal.close(box)
	buy.pressed.connect(on_buy)
	row.add_child(buy)
	var cancel := UIStyle.button("No thanks", 26, Vector2(200, 80), UIStyle.BLUE)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on_cancel := func() -> void:
		board_view.input_enabled = true
		Modal.close(box)
	cancel.pressed.connect(on_cancel)
	row.add_child(cancel)


# =============================================================================
# WINNING
# =============================================================================

func _win() -> void:
	_level_over = true
	board_view.input_enabled = false
	board_view.tool_mode = ""

	await _show_banner("Level Complete!")

	# BONUS: leftover moves turn into rockets that all fire.
	var leftover := moves_left
	if leftover > 0:
		await _show_banner("Bonus!")
		moves_left = 0
		_refresh_hud()
		await board_view.play_bonus(leftover)

	var coins := int(level["coins"]) + leftover * COINS_PER_LEFTOVER_MOVE
	GameState.complete_level(coins)

	var box := Modal.open(self, "Level %d complete!" % (level_index + 1))
	box.add_child(UIStyle.label("Score: %d" % score, 30))
	var rewards := HBoxContainer.new()
	rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	rewards.add_theme_constant_override("separation", 40)
	rewards.add_child(UIStyle.icon_counter("star", "+1", 36))
	rewards.add_child(UIStyle.icon_counter("coin", "+%d" % coins, 36))
	box.add_child(rewards)
	var go := UIStyle.button("Continue")
	go.pressed.connect(_go_to_garden)
	box.add_child(go)


## A big text that zooms in, stays for a moment, and fades out.
## It's a coroutine: callers `await` it to wait until it's gone.
func _show_banner(text: String) -> void:
	var banner := UIStyle.label(text, 72, UIStyle.ACCENT)
	banner.size = Vector2(size.x, 120)
	banner.position = Vector2(0, size.y / 2.0 - 60.0)
	# pivot_offset is the point a Control scales and rotates around. Without
	# it, the text would grow from its top-left corner.
	banner.pivot_offset = banner.size / 2.0
	banner.z_index = 40
	add_child(banner)
	var tween := create_tween()
	tween.tween_property(banner, "scale", Vector2.ONE, 0.35).from(Vector2(0.3, 0.3)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.7)
	tween.tween_property(banner, "modulate:a", 0.0, 0.3)
	await tween.finished
	banner.queue_free()


# =============================================================================
# LOSING
# =============================================================================

func _offer_extra_moves() -> void:
	board_view.input_enabled = false
	var box := Modal.open(self, "Out of moves!")
	box.add_child(UIStyle.label("So close! Get %d more moves?" % GameState.EXTRA_MOVES_AMOUNT, 28))

	var buy := UIStyle.button("+%d moves  (%d coins)" % [GameState.EXTRA_MOVES_AMOUNT, GameState.EXTRA_MOVES_PRICE],
			28, Vector2(0, 90), UIStyle.ORANGE)
	buy.disabled = GameState.coins < GameState.EXTRA_MOVES_PRICE
	var on_buy := func() -> void:
		if GameState.try_spend_coins(GameState.EXTRA_MOVES_PRICE):
			moves_left += GameState.EXTRA_MOVES_AMOUNT
			_refresh_hud()
			board_view.input_enabled = true
			Modal.close(box)
	buy.pressed.connect(on_buy)
	box.add_child(buy)

	var give_up := UIStyle.button("Give up", 26, Vector2(0, 70), UIStyle.BLUE)
	var on_give_up := func() -> void:
		Modal.close(box)
		_lose()
	give_up.pressed.connect(on_give_up)
	box.add_child(give_up)


func _lose() -> void:
	_level_over = true
	board_view.input_enabled = false
	GameState.lose_life()

	var box := Modal.open(self, "Level failed")
	box.add_child(UIStyle.label("You lost a life.", 28))
	box.add_child(UIStyle.icon_counter("heart", "%d left" % GameState.lives, 32))
	if GameState.has_life():
		var retry := UIStyle.button("Try again")
		retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
		box.add_child(retry)
	var garden := UIStyle.button("Back to garden", 28, Vector2(0, 80), UIStyle.BLUE)
	garden.pressed.connect(_go_to_garden)
	box.add_child(garden)


func _on_quit_pressed() -> void:
	# Not while a turn is animating: the turn might end the level while the
	# popup is open, and then "Keep playing" or "Quit" would do the wrong thing.
	if _level_over or board_view.busy:
		return
	board_view.input_enabled = false
	var box := Modal.open(self, "Quit level?")
	box.add_child(UIStyle.label("You will lose a life.", 28))
	var row := Modal.button_row(box)
	var quit := UIStyle.button("Quit", 28, Vector2(220, 80), UIStyle.HEART.darkened(0.2))
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on_quit := func() -> void:
		if not _level_over:   # double check: never charge a life after a win
			GameState.lose_life()
		_go_to_garden()
	quit.pressed.connect(on_quit)
	row.add_child(quit)
	var stay := UIStyle.button("Keep playing", 28, Vector2(220, 80))
	stay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var on_stay := func() -> void:
		board_view.input_enabled = not _level_over
		Modal.close(box)
	stay.pressed.connect(on_stay)
	row.add_child(stay)


func _go_to_garden() -> void:
	get_tree().change_scene_to_file(GARDEN_SCENE)
