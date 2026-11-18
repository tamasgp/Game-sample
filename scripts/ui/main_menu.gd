## MainMenu: title, coin count, level picker and the button to the aquarium.
##
## This is the first scene (see run/main_scene in project.godot). It reads the
## player's progress from the GameState autoload to decide which levels are
## unlocked and how many stars each one has.
extends Control

var _coins_label: Label
var _bubbles: Array = []  # simple background animation, see _process()


func _ready() -> void:
	_build_ui()
	# Keep the coin label up to date even if coins change while we're here
	# (for example after pressing "Reset progress").
	GameState.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(GameState.coins)
	_init_bubbles()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	margin.add_child(column)

	column.add_child(UIStyle.label("Fishdom Sample", 64, UIStyle.ACCENT))
	column.add_child(UIStyle.label("Match pieces, earn coins, build your aquarium!", 24, UIStyle.TEXT_DIM))

	_coins_label = UIStyle.label("", 36, UIStyle.ACCENT)
	column.add_child(_coins_label)

	# ----- Level grid -----
	var panel := UIStyle.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	panel.add_child(inner)
	inner.add_child(UIStyle.label("Levels", 36))

	# GridContainer places children in rows of `columns` items.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(grid)

	for i in LevelData.count():
		grid.add_child(_make_level_button(i))

	# ----- Bottom buttons -----
	var aquarium := UIStyle.button("My Aquarium", 34, Vector2(0, 96), Color(0.15, 0.45, 0.8))
	aquarium.pressed.connect(_on_aquarium_pressed)
	column.add_child(aquarium)

	var reset := UIStyle.button("Reset progress", 22, Vector2(0, 56), Color(0.5, 0.2, 0.25))
	reset.pressed.connect(_on_reset_pressed)
	column.add_child(reset)


## One level tile: number, name and stars. Locked levels are disabled.
func _make_level_button(index: int) -> Control:
	var unlocked := GameState.is_unlocked(index)
	var level := LevelData.get_level(index)

	var button := UIStyle.button("", 30, Vector2(200, 170),
			UIStyle.BUTTON if unlocked else UIStyle.BUTTON_DISABLED)
	button.disabled = not unlocked
	# `bind()` stores an extra argument in the callable, so every button calls
	# the same function but with its own level index.
	button.pressed.connect(_on_level_pressed.bind(index))

	# Put a small layout INSIDE the button. Children of a Button are drawn on
	# top of it; we make them ignore the mouse so the button still gets clicks.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var number := UIStyle.label(str(index + 1) if unlocked else "Locked", 40 if unlocked else 26)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(number)
	var title := UIStyle.label(level["name"], 18, UIStyle.TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	box.add_child(StarRow.new(GameState.get_stars(index), 16.0))
	return button


func _on_level_pressed(index: int) -> void:
	GameState.selected_level = index
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_aquarium_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/aquarium.tscn")


func _on_reset_pressed() -> void:
	GameState.reset_progress()
	# Easiest way to refresh every button: reload this scene.
	get_tree().reload_current_scene()


func _on_coins_changed(amount: int) -> void:
	_coins_label.text = "Coins: %d" % amount


# ---------------------------------------------------------------------------
# Background: water gradient with rising bubbles
# ---------------------------------------------------------------------------

func _init_bubbles() -> void:
	for i in 25:
		_bubbles.append({
			"pos": Vector2(randf() * 720.0, randf() * 1280.0),
			"radius": randf_range(3.0, 10.0),
			"speed": randf_range(30.0, 90.0),
		})


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for bubble in _bubbles:
		# Vector2 is a VALUE type: copy it out, change it, and store it back.
		var pos: Vector2 = bubble["pos"]
		pos.y -= float(bubble["speed"]) * delta
		# Wobble left and right while rising.
		pos.x += sin(time * 2.5 + float(bubble["radius"])) * 0.4
		if pos.y < -20.0:
			# Recycle bubbles that left the screen instead of creating new ones.
			pos = Vector2(randf() * size.x, size.y + 20.0)
		bubble["pos"] = pos
	# Our drawing changes every frame, so ask Godot to call _draw() again.
	queue_redraw()


func _draw() -> void:
	UIStyle.draw_vertical_gradient(self, Rect2(Vector2.ZERO, size), UIStyle.WATER_TOP, UIStyle.WATER_BOTTOM)
	for bubble in _bubbles:
		draw_arc(bubble["pos"], bubble["radius"], 0.0, TAU, 16, Color(1, 1, 1, 0.5), 2.0, true)
