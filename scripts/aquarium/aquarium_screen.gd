## AquariumScreen: the player's tank. Spend coins on fish and decorations,
## and tap the water to feed the fish.
##
## SCENE STRUCTURE (built in code in _ready):
##
##   AquariumScreen (Control, this script)   draws water, light rays, sand,
##   │                                       bubbles and food in _draw()
##   ├── _decor_layer (Node2D)               AquariumDecoration nodes
##   ├── _fish_layer (Node2D)                AquariumFish nodes
##   └── HUD (MarginContainer)               top bar + bottom buttons
##       (and the shop popup when open)
##
## Godot draws children after (on top of) their parent, in child order.
## So the order above is also the drawing order, back to front.
extends Control

## Space reserved for the HUD at the top and the buttons at the bottom.
const TOP_RESERVED := 170.0
const SAND_HEIGHT := 200.0
const FOOD_SINK_SPEED := 45.0
const FOOD_LIFETIME := 10.0
## Fish notice food within this distance.
const FOOD_SIGHT := 450.0

var _decor_layer: Node2D
var _fish_layer: Node2D
## item id -> node, so we only create nodes for newly bought items.
var _item_nodes: Dictionary = {}

var _sand_top: float = 1000.0
var _tank_rect: Rect2 = Rect2()

## Food pellets: Array of { "pos": Vector2, "age": float }
var _food: Array = []
var _bubbles: Array = []
var _pebbles: Array = []
var _time: float = 0.0

var _coins_label: Label
var _shop: Control = null


func _ready() -> void:
	_decor_layer = Node2D.new()
	add_child(_decor_layer)
	_fish_layer = Node2D.new()
	add_child(_fish_layer)
	_build_hud()

	for i in 18:
		_bubbles.append({"pos": Vector2(randf() * 720.0, randf() * 1280.0),
				"radius": randf_range(3.0, 9.0), "speed": randf_range(25.0, 70.0)})
	for i in 40:
		# Pebble positions as fractions (0..1), so they scale with the screen.
		_pebbles.append({"x": randf(), "y": randf(), "r": randf_range(3.0, 8.0),
				"shade": randf_range(-0.15, 0.15)})

	GameState.coins_changed.connect(_on_coins_changed)
	GameState.inventory_changed.connect(_sync_items)
	resized.connect(_update_layout)

	_on_coins_changed(GameState.coins)
	_update_layout()
	_sync_items()


# ---------------------------------------------------------------------------
# Layout and items
# ---------------------------------------------------------------------------

## Recomputes the tank area from the current screen size.
func _update_layout() -> void:
	_sand_top = size.y - SAND_HEIGHT
	_tank_rect = Rect2(60.0, TOP_RESERVED, maxf(10.0, size.x - 120.0), maxf(10.0, _sand_top - TOP_RESERVED))
	for id in _item_nodes:
		var node: Node2D = _item_nodes[id]
		if node is AquariumFish:
			(node as AquariumFish).set_bounds(_tank_rect)
		else:
			_place_decoration(node, AquariumCatalog.get_item(id))


## Creates nodes for owned items that don't have one yet.
func _sync_items() -> void:
	for id in GameState.owned_items:
		if _item_nodes.has(id):
			continue
		var item := AquariumCatalog.get_item(id)
		if item.is_empty():
			continue  # an item from an old version that no longer exists
		if item["kind"] == "fish":
			var fish := AquariumFish.new()
			fish.setup(item, _tank_rect)
			# New fish enter from the top of the water.
			fish.position = Vector2(randf_range(_tank_rect.position.x, _tank_rect.end.x), _tank_rect.position.y)
			_fish_layer.add_child(fish)
			_item_nodes[id] = fish
		else:
			var decoration := AquariumDecoration.new()
			decoration.setup(item)
			_decor_layer.add_child(decoration)
			_place_decoration(decoration, item)
			_item_nodes[id] = decoration


func _place_decoration(node: Node2D, item: Dictionary) -> void:
	# "x" is a fraction of the width; sit slightly into the sand.
	node.position = Vector2(float(item["x"]) * size.x, _sand_top + 40.0)


# ---------------------------------------------------------------------------
# HUD and shop
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	# IMPORTANT: containers that cover the whole screen must IGNORE the mouse,
	# otherwise they swallow the taps meant for the water (see _gui_input).
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var top_panel := UIStyle.panel()
	column.add_child(top_panel)
	var top := HBoxContainer.new()
	top_panel.add_child(top)
	var back := UIStyle.button("Back", 26, Vector2(120, 70), Color(0.2, 0.4, 0.7))
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_child(back)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	title_box.add_child(UIStyle.label("My Aquarium", 34))
	title_box.add_child(UIStyle.label("Tap the water to feed your fish", 20, UIStyle.TEXT_DIM))
	_coins_label = UIStyle.label("", 28, UIStyle.ACCENT)
	_coins_label.custom_minimum_size = Vector2(150, 0)
	top.add_child(_coins_label)

	# A spacer that pushes the buttons to the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var shop := UIStyle.button("Shop", 32, Vector2(0, 90), Color(0.85, 0.5, 0.1))
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop.pressed.connect(_open_shop)
	bottom.add_child(shop)
	var play := UIStyle.button("Play Levels", 32, Vector2(0, 90))
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(_on_play_pressed)
	bottom.add_child(play)


func _on_play_pressed() -> void:
	# Jump straight into the furthest unlocked level.
	GameState.selected_level = GameState.highest_unlocked
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_coins_changed(amount: int) -> void:
	_coins_label.text = "%d coins" % amount


func _open_shop() -> void:
	if _shop != null:
		_shop.queue_free()

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_shop = overlay

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(minf(640.0, size.x - 40.0), minf(1000.0, size.y - 120.0))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UIStyle.label("Shop", 44, UIStyle.ACCENT))
	box.add_child(UIStyle.label("You have %d coins" % GameState.coins, 26))

	# ScrollContainer lets the list be longer than the screen.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	for item in AquariumCatalog.ITEMS:
		list.add_child(_make_shop_row(item))

	var close := UIStyle.button("Close", 30, Vector2(0, 80), Color(0.2, 0.4, 0.7))
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _make_shop_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# Preview: reuse the real fish/decoration drawing, frozen and scaled down.
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(110, 90)
	preview.clip_contents = true
	row.add_child(preview)
	if item["kind"] == "fish":
		var fish := AquariumFish.new()
		fish.setup(item, Rect2(55, 45, 0, 0))
		fish.position = Vector2(60, 45)
		fish.set_process(false)  # don't swim around inside the shop
		preview.add_child(fish)
	else:
		var decoration := AquariumDecoration.new()
		decoration.setup(item)
		decoration.position = Vector2(55, 88)
		decoration.scale = Vector2(0.4, 0.4)
		preview.add_child(decoration)

	var name_label := UIStyle.label(item["name"], 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var id: String = item["id"]
	var price: int = item["price"]
	var button: Button
	if GameState.owns(id):
		button = UIStyle.button("Owned", 24, Vector2(170, 70), UIStyle.BUTTON_DISABLED)
		button.disabled = true
	else:
		button = UIStyle.button("Buy %d" % price, 24, Vector2(170, 70), Color(0.85, 0.5, 0.1))
		button.disabled = GameState.coins < price
		button.pressed.connect(_on_buy_pressed.bind(id))
	row.add_child(button)
	return row


func _on_buy_pressed(id: String) -> void:
	if GameState.buy_item(id):
		# Rebuild the shop so the "Owned" state and coin total update.
		_open_shop()


func _close_shop() -> void:
	if _shop != null:
		_shop.queue_free()
		_shop = null


# ---------------------------------------------------------------------------
# Feeding: tapping the water drops food
# ---------------------------------------------------------------------------

## _gui_input() receives mouse/touch events that land on THIS control and are
## not taken by a child control (like a button) first.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# Ignore taps on the HUD at the top, on the sand, or while the shop is open.
	if button.position.y < TOP_RESERVED or button.position.y > _sand_top or _shop != null:
		return
	# Drop a few pellets spread around the tap.
	for i in 3:
		_food.append({"pos": button.position + Vector2(randf_range(-25, 25), randf_range(-10, 10)), "age": 0.0})
	accept_event()


func _process(delta: float) -> void:
	_time += delta
	_update_food(delta)
	_update_bubbles(delta)
	queue_redraw()


func _update_food(delta: float) -> void:
	# 1) Pellets sink, then lie on the sand until they dissolve.
	for pellet in _food:
		var pos: Vector2 = pellet["pos"]
		if pos.y < _sand_top + 10.0:
			pos.y += FOOD_SINK_SPEED * delta
			pos.x += sin(_time * 3.0 + pos.y * 0.05) * 0.3
		pellet["pos"] = pos
		pellet["age"] = float(pellet["age"]) + delta
	_food = _food.filter(func(p: Dictionary) -> bool: return float(p["age"]) < FOOD_LIFETIME)

	# 2) Every fish looks for the closest pellet and eats it when close enough.
	for node in _fish_layer.get_children():
		var fish := node as AquariumFish
		var best := -1
		var best_distance := FOOD_SIGHT
		for i in _food.size():
			var distance := fish.position.distance_to(_food[i]["pos"])
			if distance < best_distance:
				best_distance = distance
				best = i
		if best == -1:
			fish.has_food_target = false
		elif best_distance < fish.length * 0.4:
			_food.remove_at(best)
			fish.has_food_target = false
			fish.on_ate()
		else:
			fish.has_food_target = true
			fish.food_target = _food[best]["pos"]


func _update_bubbles(delta: float) -> void:
	for bubble in _bubbles:
		var pos: Vector2 = bubble["pos"]
		pos.y -= float(bubble["speed"]) * delta
		pos.x += sin(_time * 2.0 + float(bubble["radius"])) * 0.3
		if pos.y < TOP_RESERVED - 40.0:
			pos = Vector2(randf() * size.x, _sand_top)
		bubble["pos"] = pos


# ---------------------------------------------------------------------------
# Drawing the tank background
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Water.
	UIStyle.draw_vertical_gradient(self, Rect2(Vector2.ZERO, size), UIStyle.WATER_TOP, UIStyle.WATER_BOTTOM)

	# Light rays: wide translucent triangles from the surface that sway slowly.
	for i in 4:
		var x := size.x * (0.15 + i * 0.25) + sin(_time * 0.4 + i) * 40.0
		var ray := PackedVector2Array([
			Vector2(x - 30, 0), Vector2(x + 30, 0),
			Vector2(x + 140, _sand_top), Vector2(x - 20, _sand_top)])
		draw_colored_polygon(ray, Color(1, 1, 1, 0.05))

	# Sand: a wavy top edge, then a filled area down to the bottom.
	var sand := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var x := size.x * i / steps
		sand.append(Vector2(x, _sand_top + sin(i * 0.8) * 10.0))
	sand.append(Vector2(size.x, size.y))
	sand.append(Vector2(0, size.y))
	var sand_color := Color(0.85, 0.75, 0.5)
	draw_colored_polygon(sand, sand_color)
	for pebble in _pebbles:
		var p := Vector2(float(pebble["x"]) * size.x, _sand_top + 25.0 + float(pebble["y"]) * (SAND_HEIGHT - 40.0))
		draw_circle(p, pebble["r"], sand_color.darkened(0.15 + float(pebble["shade"])))

	# Bubbles.
	for bubble in _bubbles:
		draw_arc(bubble["pos"], bubble["radius"], 0.0, TAU, 14, Color(1, 1, 1, 0.45), 2.0, true)

	# Food pellets, fading out near the end of their life.
	for pellet in _food:
		var alpha := clampf((FOOD_LIFETIME - float(pellet["age"])) / 2.0, 0.0, 1.0)
		draw_circle(pellet["pos"], 6.0, Color(0.55, 0.3, 0.1, alpha))
		draw_circle(pellet["pos"] + Vector2(-1.5, -1.5), 2.0, Color(0.9, 0.7, 0.4, alpha))
