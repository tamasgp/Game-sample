## GameScreen: one puzzle level. It connects all the match-3 pieces together.
##
##   LevelData ──(level dictionary)──► GameScreen ──creates──► BoardModel
##                                         │                     ▲
##                                         │ creates             │ reads/changes
##                                         ▼                     │
##                                     BoardView ────────────────┘
##                                         │
##                                         └─signals─► GameScreen updates
##                                                      score, moves, goals,
##                                                      and decides win / lose
##
## The game screen owns the "level rules" (move limit, goals, stars, coins),
## while BoardModel owns the "puzzle rules" (matching, specials, gravity).
extends Control

var level_index: int = 0
var level: Dictionary = {}
var model: BoardModel
var goals: LevelGoals
var moves_left: int = 0
var score: int = 0
var _level_over: bool = false

# UI nodes we need to update later.
var board_view: BoardView
var _board_area: Control
var _moves_label: Label
var _score_label: Label
var _goals_box: HBoxContainer


func _ready() -> void:
	level_index = GameState.selected_level
	level = LevelData.get_level(level_index)
	moves_left = int(level["moves"])

	# --- Rules: build the model and the goals from the level data ---
	model = BoardModel.new()
	model.setup(level["layout"], int(level["colors"]))
	goals = LevelGoals.new()
	goals.setup(level["goals"], model.total_ice())

	# --- Visuals ---
	_build_ui()
	board_view.setup(model)

	# --- Wiring: react to what happens on the board ---
	# `signal.connect(callable)` registers a function to be called when the
	# signal is emitted. This is how child nodes talk "up" to their parent
	# without knowing anything about it.
	board_view.move_committed.connect(_on_move_committed)
	board_view.pieces_cleared.connect(_on_pieces_cleared)
	board_view.turn_finished.connect(_on_turn_finished)
	goals.changed.connect(_refresh_goals)
	# Re-fit the board whenever the screen size changes (rotation, window resize).
	_board_area.resized.connect(_fit_board)

	_refresh_hud()
	_refresh_goals()
	# Wait one frame so containers have finished calculating their sizes.
	_fit_board.call_deferred()


func _draw() -> void:
	UIStyle.draw_vertical_gradient(self, Rect2(Vector2.ZERO, size), UIStyle.WATER_TOP, UIStyle.WATER_BOTTOM)


func _notification(what: int) -> void:
	# Redraw the background gradient when our size changes.
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# ---------------------------------------------------------------------------
# Building the UI
# ---------------------------------------------------------------------------
# Layout (top to bottom):
#   [ Menu ]  Level name / score            Moves: 20
#   [ goal ] [ goal ] [ goal ]
#   ┌──────────────────────────┐
#   │        the board         │   <- _board_area, takes all remaining space
#   └──────────────────────────┘

func _build_ui() -> void:
	# MarginContainer keeps everything away from the screen edges.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	# VBoxContainer stacks its children vertically.
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

	var menu_button := UIStyle.button("Menu", 26, Vector2(120, 70), Color(0.2, 0.4, 0.7))
	menu_button.pressed.connect(_go_to_menu)
	top.add_child(menu_button)

	var info := VBoxContainer.new()
	# SIZE_EXPAND_FILL: "take all the spare horizontal space".
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UIStyle.label("%d. %s" % [level_index + 1, level["name"]], 28))
	_score_label = UIStyle.label("", 24, UIStyle.TEXT_DIM)
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

	# A Node2D can live inside a Control. Its position is then relative to the
	# Control's top-left corner.
	board_view = BoardView.new()
	_board_area.add_child(board_view)


## Scales and centers the board inside the available area.
## BoardView always works in its own "board pixels" (80 per cell), and we just
## scale the whole node. Input still works because BoardView converts event
## positions with make_input_local(), which takes the scale into account.
func _fit_board() -> void:
	if model == null:
		return
	var area := _board_area.size
	var board := board_view.board_size()
	if area.x <= 0 or area.y <= 0:
		return
	var factor := minf(area.x / board.x, area.y / board.y)
	board_view.scale = Vector2(factor, factor)
	board_view.position = (area - board * factor) / 2.0


# ---------------------------------------------------------------------------
# HUD updates
# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	_moves_label.text = str(moves_left)
	_score_label.text = "Score: %d" % score
	# Warn the player when moves are running out.
	var moves_color := Color(1, 0.35, 0.3) if moves_left <= 5 else UIStyle.ACCENT
	_moves_label.add_theme_color_override("font_color", moves_color)


## Rebuilds the goal widgets. Simple and fast enough for a handful of goals.
func _refresh_goals() -> void:
	for child in _goals_box.get_children():
		child.queue_free()
	for goal in goals.goals:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.add_child(_make_goal_icon(goal))
		var done := LevelGoals.is_goal_done(goal)
		var text := "Done" if done else "x %d" % LevelGoals.remaining(goal)
		if goal["type"] == "score" and not done:
			text = "%d" % int(goal["target"])
		item.add_child(UIStyle.label(text, 28, Color(0.5, 1, 0.5) if done else UIStyle.TEXT))
		_goals_box.add_child(item)


## A small picture for a goal: the piece to collect, an ice block, or a star.
func _make_goal_icon(goal: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(56, 56)
	match String(goal["type"]):
		"collect":
			# Reuse the real piece drawing code at a smaller scale.
			var tile := TileView.new()
			tile.setup(BoardModel.Piece.new(0, int(goal["color"]), BoardModel.Special.NONE), 80.0)
			tile.position = Vector2(28, 28)
			tile.scale = Vector2(0.65, 0.65)
			holder.add_child(tile)
		"ice":
			var ice := Panel.new()
			ice.add_theme_stylebox_override("panel", UIStyle.box(Color(0.75, 0.95, 1.0, 0.8), 6, Color(1, 1, 1), 3))
			ice.position = Vector2(8, 8)
			ice.size = Vector2(40, 40)
			holder.add_child(ice)
		_:
			var star := StarRow.new(1, 18.0, 1)
			star.size = Vector2(56, 56)
			holder.add_child(star)
	return holder


# ---------------------------------------------------------------------------
# Reacting to the board
# ---------------------------------------------------------------------------

func _on_move_committed() -> void:
	moves_left -= 1
	_refresh_hud()


func _on_pieces_cleared(result: BoardModel.ClearResult) -> void:
	score += result.score
	goals.on_pieces_removed(result.removed)
	if not result.ice_hits.is_empty():
		goals.on_ice_remaining(model.total_ice())
	goals.on_score_changed(score)
	_refresh_hud()


## Called once the board has completely settled after a move.
func _on_turn_finished() -> void:
	if _level_over:
		return
	if goals.is_complete():
		_win()
	elif moves_left <= 0:
		_lose()


func _win() -> void:
	_level_over = true
	board_view.input_enabled = false
	var stars := LevelData.stars_for_score(level, score)
	# Unused moves are worth extra coins. This rewards playing efficiently.
	var coins := int(level["coins"]) + moves_left * 5
	GameState.complete_level(level_index, stars, coins)
	_show_results(true, stars, coins)


func _lose() -> void:
	_level_over = true
	board_view.input_enabled = false
	_show_results(false, 0, 0)


# ---------------------------------------------------------------------------
# Results popup
# ---------------------------------------------------------------------------

func _show_results(won: bool, stars: int, coins: int) -> void:
	# A dark, full-screen layer that also blocks clicks to what is beneath.
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# CenterContainer keeps its child in the middle of the screen.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	box.add_child(UIStyle.label("Level Complete!" if won else "Out of Moves", 48, UIStyle.ACCENT))
	if won:
		box.add_child(StarRow.new(stars, 34.0))
		box.add_child(UIStyle.label("Score: %d" % score, 32))
		box.add_child(UIStyle.label("+%d coins" % coins, 32, UIStyle.ACCENT))
		if level_index + 1 < LevelData.count():
			var next := UIStyle.button("Next Level")
			next.pressed.connect(_play_level.bind(level_index + 1))
			box.add_child(next)
		var aquarium := UIStyle.button("Visit Aquarium", 30, Vector2(0, 80), Color(0.15, 0.45, 0.8))
		aquarium.pressed.connect(_go_to_aquarium)
		box.add_child(aquarium)
	else:
		box.add_child(UIStyle.label("Score: %d" % score, 32))
		var retry := UIStyle.button("Try Again")
		retry.pressed.connect(_play_level.bind(level_index))
		box.add_child(retry)

	var menu := UIStyle.button("Main Menu", 30, Vector2(0, 80), Color(0.2, 0.4, 0.7))
	menu.pressed.connect(_go_to_menu)
	box.add_child(menu)

	# Fade the popup in.
	overlay.modulate.a = 0.0
	create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _play_level(index: int) -> void:
	GameState.selected_level = index
	# Reloading the current scene runs _ready() again with the new level.
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _go_to_aquarium() -> void:
	get_tree().change_scene_to_file("res://scenes/aquarium.tscn")
