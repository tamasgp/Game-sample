## GardenScreen: the HOME screen. The garden, the task list, the Play button.
##
## This is the first scene the game opens (see run/main_scene in
## project.godot). It's where the "meta game" happens:
##
##     [ Play ] -> level start popup (pick boosters) -> game scene
##              -> win: +1 star -> back here
##     [ Tasks ] -> spend stars -> an object is restored (maybe choose a
##                  style) -> the gardener comments -> area complete?
##
## SCENE STRUCTURE (built in code in _ready):
##
##     GardenScreen (Control, this script)   draws the background in _draw()
##     ├── _world (Node2D)                   all GardenObjects
##     ├── HUD (MarginContainer)             lives / coins / stars, buttons
##     └── _dialog (DialogBox)               the story character
##     (+ popups created by Modal when needed)
##
## Children are drawn after (on top of) their parent, in child order, so the
## list above is also the drawing order from back to front.
extends Control

const GAME_SCENE := "res://scenes/game.tscn"

var _world: Node2D
## object id -> GardenObject
var _objects: Dictionary = {}
var _area: Dictionary = {}

var _lives_label: Label
var _life_timer_label: Label
var _coins_label: Label
var _stars_label: Label
var _area_label: Label
var _play_button: Button
var _tasks_badge: Label
var _dialog: DialogBox


func _ready() -> void:
	_world = Node2D.new()
	add_child(_world)
	_build_hud()
	_dialog = DialogBox.new()
	add_child(_dialog)

	# Keep the HUD in sync with the save data. Whenever GameState emits one of
	# these signals, the connected function runs.
	# (We connect METHODS here, not lambdas: Godot automatically disconnects a
	# method when its node is freed, e.g. when we switch to the game scene.)
	GameState.coins_changed.connect(_on_stat_changed)
	GameState.stars_changed.connect(_on_stat_changed)
	GameState.lives_changed.connect(_on_stat_changed)
	resized.connect(_layout_objects)

	_build_area()
	_refresh_hud()

	if not GameState.seen_intro:
		# Wait one frame so the screen is fully laid out before the dialog.
		await get_tree().process_frame
		await _dialog.say(GardenData.INTRO_LINES)
		GameState.mark_intro_seen()


func _on_stat_changed(_amount: int) -> void:
	_refresh_hud()


func _process(_delta: float) -> void:
	# The life countdown changes every second, so we update it every frame.
	# (Setting a Label's text to the same value is cheap.)
	if GameState.lives >= GameState.MAX_LIVES:
		_life_timer_label.text = "Full"
	else:
		var seconds := GameState.seconds_to_next_life()
		_life_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	# The background has animated parts (clouds), so redraw it.
	queue_redraw()


# =============================================================================
# THE GARDEN ITSELF
# =============================================================================

## Creates the GardenObjects of the current area.
func _build_area() -> void:
	for child in _world.get_children():
		child.queue_free()
	_objects.clear()
	_area = GardenData.get_area(GameState.area_index)
	_area_label.text = _area["name"]

	var defs: Dictionary = _area["objects"]
	for id in defs:
		var def: Dictionary = defs[id]
		var object := GardenObject.new()
		object.setup(id, def["kind"])
		var task := GardenData.task_for_object(_area, id)
		if not task.is_empty():
			object.restored = GameState.is_task_done(task["id"])
			object.option = GameState.task_option(task["id"])
		_world.add_child(object)
		_objects[id] = object
	_layout_objects()


## Places and scales every object for the current screen size.
func _layout_objects() -> void:
	if _area.is_empty():
		return
	var unit := size.x / 720.0   # design units -> real pixels
	var defs: Dictionary = _area["objects"]
	for id in _objects:
		var object: GardenObject = _objects[id]
		var def: Dictionary = defs[id]
		var pos: Vector2 = def["pos"]
		object.position = Vector2(pos.x * size.x, pos.y * size.y)
		object.scale = Vector2.ONE * unit * float(def["scale"])
		# Objects lower on the screen are closer to the viewer: draw them in
		# front. Flat objects (path, pond, weeds) get fixed layers instead.
		match String(def["kind"]):
			"path", "pond":
				object.z_index = -100
			"lilies", "bridge":
				object.z_index = -90
			"weeds":
				object.z_index = 90
			_:
				object.z_index = int(pos.y * 100.0)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	UIStyle.draw_vertical_gradient(self, rect, Color(0.5, 0.78, 0.38), Color(0.28, 0.55, 0.22))
	var t := Time.get_ticks_msec() / 1000.0
	if _area.get("background", "") == "courtyard":
		# Sky strip and an old brick wall, starting below the HUD bar so the
		# gate's arch stays visible.
		UIStyle.draw_vertical_gradient(self, Rect2(0, 0, size.x, size.y * 0.17), Color(0.55, 0.8, 1.0), Color(0.8, 0.92, 1.0))
		var wall := Rect2(0, size.y * 0.16, size.x, size.y * 0.16)
		draw_rect(wall, Color(0.62, 0.45, 0.36))
		var brick_h := wall.size.y / 6.0
		for row in 6:
			var y := wall.position.y + row * brick_h
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.45, 0.32, 0.25), 2.0)
			var offset := 0.0 if row % 2 == 0 else 30.0
			var x := offset
			while x < size.x:
				draw_line(Vector2(x, y), Vector2(x, y + brick_h), Color(0.45, 0.32, 0.25), 2.0)
				x += 60.0
	else:
		# Lakeside: sky and a row of distant trees.
		UIStyle.draw_vertical_gradient(self, Rect2(0, 0, size.x, size.y * 0.16), Color(0.55, 0.8, 1.0), Color(0.85, 0.95, 1.0))
		var x := 0.0
		var i := 0
		while x < size.x + 60.0:
			draw_circle(Vector2(x, size.y * 0.17), 45.0 + (i % 3) * 10.0, Color(0.2, 0.45, 0.2))
			x += 55.0
			i += 1
	# Two clouds drifting slowly across the sky; fposmod wraps them around.
	for k in 2:
		var cx := fposmod(t * (12.0 + k * 6.0) + k * 400.0, size.x + 200.0) - 100.0
		var cy := size.y * (0.04 + k * 0.03)
		for blob in [Vector2(-30, 0), Vector2(0, -12), Vector2(30, 0)]:
			draw_circle(Vector2(cx, cy) + blob, 22.0, Color(1, 1, 1, 0.9))


## Taps on the garden: tapping a restored object that has style options
## lets the player change its style.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# Test objects front to back (highest z_index first).
	var candidates: Array = _objects.values()
	candidates.sort_custom(func(a: GardenObject, b: GardenObject) -> bool: return a.z_index > b.z_index)
	for object in candidates:
		var garden_object: GardenObject = object
		if not garden_object.restored or not garden_object.contains_point(get_global_transform() * button.position):
			continue
		var task := GardenData.task_for_object(_area, garden_object.object_id)
		if task.has("options"):
			accept_event()
			_choose_option(task, true)
			return


# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	# Full-screen containers must IGNORE the mouse, or they would swallow the
	# taps meant for the garden (handled in _gui_input above).
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# ----- Top bar: lives, coins, stars -----
	var top_panel := UIStyle.panel()
	column.add_child(top_panel)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 30)
	top_panel.add_child(top)

	var lives := UIStyle.icon_counter("heart", "", 30)
	_lives_label = lives.get_child(1)
	top.add_child(lives)
	_life_timer_label = UIStyle.label("", 20, UIStyle.TEXT_DIM)
	_life_timer_label.custom_minimum_size = Vector2(70, 0)
	lives.add_child(_life_timer_label)

	var coins := UIStyle.icon_counter("coin", str(GameState.coins), 30)
	_coins_label = coins.get_child(1)
	top.add_child(coins)

	var stars := UIStyle.icon_counter("star", "", 30)
	_stars_label = stars.get_child(1)
	top.add_child(stars)

	_area_label = UIStyle.label("", 28, UIStyle.TEXT)
	column.add_child(_area_label)

	# Spacer: pushes the buttons to the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	# ----- Bottom: Tasks and Play -----
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)

	var tasks := UIStyle.button("Tasks", 32, Vector2(220, 110), UIStyle.BLUE)
	tasks.pressed.connect(_open_tasks)
	bottom.add_child(tasks)
	# A red "!" badge on the corner of the button when a task is affordable.
	_tasks_badge = UIStyle.label("!", 30)
	var badge_style := UIStyle.box(UIStyle.HEART, 22)
	badge_style.set_content_margin_all(2)
	_tasks_badge.add_theme_stylebox_override("normal", badge_style)
	_tasks_badge.custom_minimum_size = Vector2(44, 44)
	_tasks_badge.position = Vector2(184, -12)
	tasks.add_child(_tasks_badge)

	_play_button = UIStyle.button("", 40, Vector2(0, 110))
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_on_play_pressed)
	bottom.add_child(_play_button)


func _refresh_hud() -> void:
	_lives_label.text = str(GameState.lives)
	_coins_label.text = str(GameState.coins)
	_stars_label.text = str(GameState.stars)
	_play_button.text = "Play  Level %d" % (GameState.current_level + 1)
	_tasks_badge.visible = _has_affordable_task() or (GameState.is_area_complete(GameState.area_index)
			and GameState.area_index < GardenData.area_count() - 1)


func _available_tasks() -> Array:
	var result: Array = []
	for task in _area["tasks"]:
		if GameState.is_task_available(task):
			result.append(task)
	return result


func _has_affordable_task() -> bool:
	for task in _available_tasks():
		if GameState.stars >= int(task["cost"]):
			return true
	return false


# =============================================================================
# TASKS
# =============================================================================

func _open_tasks() -> void:
	var tasks: Array = _area["tasks"]
	var done := 0
	for task in tasks:
		if GameState.is_task_done(task["id"]):
			done += 1

	var box := Modal.open(self, "Tasks", 620.0)
	box.add_child(UIStyle.label("%s: %d / %d done" % [_area["name"], done, tasks.size()], 26, UIStyle.TEXT_DIM))

	if done == tasks.size():
		if GameState.area_index < GardenData.area_count() - 1:
			box.add_child(UIStyle.label("This area is restored!", 30))
			var next := UIStyle.button("Go to the next area")
			var on_next := func() -> void:
				Modal.close(box)
				_go_to_next_area()
			next.pressed.connect(on_next)
			box.add_child(next)
		else:
			box.add_child(UIStyle.label("The whole garden is restored!\nKeep playing levels for coins.", 28))
	else:
		for task in _available_tasks():
			box.add_child(_make_task_row(task, box))

	var close := UIStyle.button("Close", 28, Vector2(0, 76), UIStyle.BLUE)
	close.pressed.connect(func() -> void: Modal.close(box))
	box.add_child(close)


func _make_task_row(task: Dictionary, box: VBoxContainer) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := UIStyle.label(task["title"], 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var cost := int(task["cost"])
	var go := UIStyle.button("%d" % cost, 28, Vector2(130, 72), UIStyle.ORANGE)
	go.disabled = GameState.stars < cost
	go.add_child(IconView.new("star", 36.0))
	# `bind()` stores extra arguments in a Callable, so the button calls
	# _start_task(task, box) with THIS row's task.
	go.pressed.connect(_start_task.bind(task, box))
	row.add_child(go)
	return row


func _start_task(task: Dictionary, tasks_box: VBoxContainer) -> void:
	Modal.close(tasks_box)
	if task.has("options"):
		_choose_option(task, false)
	else:
		_finish_task(task, 0)


## Lets the player pick a style. `already_done` = true when changing the
## style of an object that was restored earlier (free, no stars spent).
func _choose_option(task: Dictionary, already_done: bool) -> void:
	var box := Modal.open(self, "Choose a style")
	box.add_child(UIStyle.label(task["title"], 26, UIStyle.TEXT_DIM))
	var options: Array = task["options"]
	for i in options.size():
		var button := UIStyle.button(options[i], 30, Vector2(0, 80), UIStyle.BUTTON)
		# This lambda "captures" `i`, so each button remembers its own option.
		var on_pick := func() -> void:
			Modal.close(box)
			if already_done:
				GameState.set_task_option(task["id"], i)
				_refresh_object(task)
			else:
				_finish_task(task, i)
		button.pressed.connect(on_pick)
		box.add_child(button)
	var cancel := UIStyle.button("Cancel", 26, Vector2(0, 66), UIStyle.BLUE)
	cancel.pressed.connect(func() -> void: Modal.close(box))
	box.add_child(cancel)


## Spends the stars, restores the object with a little show, and lets the
## gardener talk. A coroutine (it awaits the dialog).
func _finish_task(task: Dictionary, option: int) -> void:
	if not GameState.complete_task(task, option):
		return
	_refresh_hud()
	var object: GardenObject = _objects.get(task["object"])
	if object != null:
		_refresh_object(task)
		# "Pop": start a bit smaller and spring back to the normal size.
		var normal_scale := object.scale
		object.scale = normal_scale * 0.7
		var tween := create_tween()
		tween.tween_property(object, "scale", normal_scale, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		# Reuse the board's sparkle effect at the object's spot.
		BoardEffect.spawn(_world, BoardEffect.Kind.SPARKLE, object.position + Vector2(0, -60), 160.0, 0.0, Color(1, 0.95, 0.5))
		BoardEffect.spawn(_world, BoardEffect.Kind.BLAST, object.position + Vector2(0, -60), 110.0, 0.0, Color(1, 1, 0.8))

	await _dialog.say([task["say"]])

	if GameState.is_area_complete(GameState.area_index):
		if GameState.area_index < GardenData.area_count() - 1:
			await _dialog.say(["We did it! The %s is restored!" % _area["name"], "Let's see what's next..."])
			_go_to_next_area()
		else:
			await _dialog.say(["The garden is complete. You're the best gardener ever!"])


func _refresh_object(task: Dictionary) -> void:
	var object: GardenObject = _objects.get(task["object"])
	if object != null:
		object.restored = GameState.is_task_done(task["id"])
		object.option = GameState.task_option(task["id"])


func _go_to_next_area() -> void:
	GameState.advance_area()
	# Fade out, rebuild, fade in: a simple, cheap scene transition.
	var tween := create_tween()
	tween.tween_property(_world, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_build_area)
	tween.tween_callback(_refresh_hud)
	tween.tween_property(_world, "modulate:a", 1.0, 0.4)


# =============================================================================
# PLAY: lives check and the level start popup
# =============================================================================

func _on_play_pressed() -> void:
	if not GameState.has_life():
		_show_no_lives()
		return
	_show_level_start()


func _show_no_lives() -> void:
	var box := Modal.open(self, "No lives left")
	box.add_child(UIStyle.icon_counter("heart", "Next life in %d min" % ceili(GameState.seconds_to_next_life() / 60.0), 28))
	var refill := UIStyle.button("Refill lives (%d coins)" % GameState.LIVES_REFILL_PRICE, 28, Vector2(0, 86), UIStyle.ORANGE)
	refill.disabled = GameState.coins < GameState.LIVES_REFILL_PRICE
	var on_refill := func() -> void:
		if GameState.try_spend_coins(GameState.LIVES_REFILL_PRICE):
			GameState.refill_lives()
		Modal.close(box)
	refill.pressed.connect(on_refill)
	box.add_child(refill)
	var close := UIStyle.button("Wait", 26, Vector2(0, 70), UIStyle.BLUE)
	close.pressed.connect(func() -> void: Modal.close(box))
	box.add_child(close)


## The popup before a level: shows the goals and lets the player pick
## pre-level boosters (they appear on the board as special pieces).
func _show_level_start() -> void:
	var level := LevelData.get_level(GameState.current_level)
	var box := Modal.open(self, "Level %d" % (GameState.current_level + 1), 600.0)

	box.add_child(UIStyle.label("Goals", 26, UIStyle.TEXT_DIM))
	var goal_row := HBoxContainer.new()
	goal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	goal_row.add_theme_constant_override("separation", 30)
	box.add_child(goal_row)
	for goal in level["goals"]:
		goal_row.add_child(UIStyle.label(_describe_goal(goal), 26))

	box.add_child(UIStyle.label("Boosters", 26, UIStyle.TEXT_DIM))
	var booster_row := HBoxContainer.new()
	booster_row.alignment = BoxContainer.ALIGNMENT_CENTER
	booster_row.add_theme_constant_override("separation", 16)
	box.add_child(booster_row)

	# Which boosters are switched on. A Dictionary used as a set.
	var selected := {}
	var specials := {"rocket": BoardModel.Special.ROCKET_H, "bomb": BoardModel.Special.BOMB,
			"rainbow": BoardModel.Special.RAINBOW}
	for id in specials:
		booster_row.add_child(_make_booster_toggle(id, specials[id], selected))

	var play := UIStyle.button("Play!", 40, Vector2(0, 100))
	var on_play := func() -> void:
		GameState.pending_boosters.clear()
		for booster_id in selected:
			if GameState.use_booster(booster_id):
				GameState.pending_boosters.append(booster_id)
		get_tree().change_scene_to_file(GAME_SCENE)
	play.pressed.connect(on_play)
	box.add_child(play)
	var close := UIStyle.button("Close", 26, Vector2(0, 66), UIStyle.BLUE)
	close.pressed.connect(func() -> void: Modal.close(box))
	box.add_child(close)


func _describe_goal(goal: Dictionary) -> String:
	match String(goal["type"]):
		"collect":
			var names := ["apples", "flowers", "stars", "leaves", "drops", "berries"]
			return "%d %s" % [int(goal["amount"]), names[int(goal["color"]) % names.size()]]
		"weeds":
			return "Clear weeds"
		_:
			return "Break crates"


## A booster button: tap to switch it on/off. With none left, tapping buys one.
func _make_booster_toggle(id: String, special: int, selected: Dictionary) -> Button:
	var button := UIStyle.button("", 22, Vector2(140, 140), UIStyle.PANEL.lightened(0.15))
	button.toggle_mode = true   # a Button that stays pressed until tapped again
	var icon := UIStyle.piece_icon(1, special, 70.0)
	icon.position = Vector2(35, 14)
	button.add_child(icon)
	var count_label := UIStyle.label("", 22)
	count_label.position = Vector2(0, 92)
	count_label.size = Vector2(140, 40)
	button.add_child(count_label)

	# A local function that refreshes the button text. Lambdas can be stored
	# in variables and called later with .call().
	var refresh := func() -> void:
		var count := GameState.booster_count(id)
		if count > 0:
			count_label.text = "x%d" % count + ("  ON" if selected.has(id) else "")
		else:
			count_label.text = "Buy %d" % int(GameState.BOOSTER_PRICES[id])
	refresh.call()

	var on_toggled := func(on: bool) -> void:
		# Switching on a booster you don't have tries to buy one first.
		if on and GameState.booster_count(id) == 0 and not GameState.buy_booster(id):
			button.set_pressed_no_signal(false)   # couldn't afford it
			return
		if on:
			selected[id] = true
		else:
			selected.erase(id)
		refresh.call()
	button.toggled.connect(on_toggled)
	return button
