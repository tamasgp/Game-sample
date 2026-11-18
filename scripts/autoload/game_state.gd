## GameState: the player's progress, available from every scene.
##
## WHAT IS AN AUTOLOAD?
## --------------------
## project.godot lists this script under [autoload]. Godot creates ONE
## instance of it when the game starts, adds it to the scene tree, and keeps
## it alive while scenes change. Any script can then write `GameState.coins`.
##
## Use autoloads for things that truly are global (save data, settings,
## audio manager). Avoid putting gameplay logic here: global state makes code
## harder to follow and test.
##
## Note: autoload scripts should NOT declare a `class_name` with the same name
## as the autoload, otherwise Godot reports a name conflict.
##
## SAVING
## ------
## Progress is written as JSON to "user://save_game.json". The "user://"
## folder is a per-game writable folder that Godot maps to the right place on
## each platform (AppData on Windows, the app sandbox on iOS/Android,
## IndexedDB in a web browser, ...). "res://" (the project folder) is
## READ-ONLY in an exported game, so never save there.
extends Node

## Emitted when the coin count changes (UI labels listen to this).
signal coins_changed(new_amount: int)
## Emitted when an aquarium item is bought.
signal inventory_changed

const SAVE_PATH := "user://save_game.json"
## Bump this when the save format changes, so old saves can be migrated.
const SAVE_VERSION := 1
const STARTING_COINS := 100

var coins: int = STARTING_COINS
## Index of the furthest level the player may play (0 = only the first one).
var highest_unlocked: int = 0
## Best star count per level. Keys are level indices AS STRINGS, because JSON
## object keys are always strings.
var level_stars: Dictionary = {}
## Ids of owned aquarium items (see aquarium_catalog.gd).
var owned_items: Array = []

## Which level the player picked on the menu. This is how we pass data
## from one scene to the next: the menu sets it, the game screen reads it.
var selected_level: int = 0


func _ready() -> void:
	load_game()


# ---------------------------------------------------------------------------
# Coins and items
# ---------------------------------------------------------------------------

func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)
	save_game()


## Spends coins if the player has enough. Returns true on success.
func try_spend(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	coins_changed.emit(coins)
	save_game()
	return true


func owns(item_id: String) -> bool:
	return owned_items.has(item_id)


## Buys an item from the catalog. Returns true if it worked.
func buy_item(item_id: String) -> bool:
	var item := AquariumCatalog.get_item(item_id)
	if item.is_empty() or owns(item_id):
		return false
	if not try_spend(int(item["price"])):
		return false
	owned_items.append(item_id)
	inventory_changed.emit()
	save_game()
	return true


# ---------------------------------------------------------------------------
# Level progress
# ---------------------------------------------------------------------------

func get_stars(level_index: int) -> int:
	return int(level_stars.get(str(level_index), 0))


func is_unlocked(level_index: int) -> bool:
	return level_index <= highest_unlocked


## Records a win: keeps the best star count, unlocks the next level,
## and pays out the coin reward.
func complete_level(level_index: int, stars: int, coin_reward: int) -> void:
	var key := str(level_index)
	level_stars[key] = maxi(stars, get_stars(level_index))
	highest_unlocked = maxi(highest_unlocked, mini(level_index + 1, LevelData.count() - 1))
	add_coins(coin_reward)  # also saves


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"highest_unlocked": highest_unlocked,
		"level_stars": level_stars,
		"owned_items": owned_items,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save game: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	# The file is closed automatically when `file` goes out of scope.


func load_game() -> void:
	_reset_values()
	if not FileAccess.file_exists(SAVE_PATH):
		return  # first launch: keep the defaults
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is damaged, starting fresh.")
		return
	var data: Dictionary = parsed
	# IMPORTANT: JSON has only one number type, so every number comes back as a
	# float (100 -> 100.0). Convert with int() when we expect whole numbers.
	coins = int(data.get("coins", STARTING_COINS))
	highest_unlocked = int(data.get("highest_unlocked", 0))
	level_stars = data.get("level_stars", {})
	for id in data.get("owned_items", []):
		if not owned_items.has(id):
			owned_items.append(String(id))
	coins_changed.emit(coins)
	inventory_changed.emit()


## Wipes all progress (used by the "Reset" button on the main menu).
func reset_progress() -> void:
	_reset_values()
	save_game()
	coins_changed.emit(coins)
	inventory_changed.emit()


func _reset_values() -> void:
	coins = STARTING_COINS
	highest_unlocked = 0
	level_stars = {}
	owned_items = AquariumCatalog.starter_ids()
