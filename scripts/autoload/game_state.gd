## GameState: the player's progress, available from every scene.
##
## ============================================================================
## WHAT IS AN AUTOLOAD?
## ============================================================================
## project.godot lists this script under [autoload]. Godot creates ONE
## instance when the game starts, adds it to the scene tree, and keeps it alive
## across scene changes. Any script can then write `GameState.coins`.
##
## Keep autoloads for things that are truly global (save data, settings,
## audio). Gameplay logic doesn't belong here: global state makes code harder
## to follow and test.
##
## (An autoload must NOT declare a `class_name` equal to its autoload name.)
##
## ============================================================================
## THE ECONOMY OF THIS GAME (three currencies, each with its own job)
## ============================================================================
##   STARS  earned by winning levels (1 each), spent on garden tasks.
##          The ONLY way to progress the story. You can't buy them.
##   COINS  earned by winning levels, spent on boosters and on extra moves
##          when a level is about to be lost.
##   LIVES  you need one to play. Losing (or quitting) a level costs one, and
##          they refill over real time. This paces play sessions.
##
## ============================================================================
## SAVING
## ============================================================================
## Progress is written as JSON to "user://save_game.json". "user://" is a
## writable per-game folder that Godot maps to the right place on each
## platform. "res://" (the project) is read-only in exported games.
extends Node

signal coins_changed(amount: int)
signal stars_changed(amount: int)
signal lives_changed(amount: int)
signal boosters_changed
signal garden_changed

const SAVE_PATH := "user://save_game.json"
const SAVE_VERSION := 1

const STARTING_COINS := 200
const MAX_LIVES := 5
## Seconds until one life comes back.
const LIFE_REFILL_SECONDS := 20 * 60
## Prices in coins.
const EXTRA_MOVES_PRICE := 100
const EXTRA_MOVES_AMOUNT := 5
const LIVES_REFILL_PRICE := 200
const BOOSTER_PRICES := {"rocket": 60, "bomb": 80, "rainbow": 120, "shovel": 100}
const STARTING_BOOSTERS := {"rocket": 1, "bomb": 1, "rainbow": 1, "shovel": 2}

var coins: int = STARTING_COINS
var stars: int = 0
var lives: int = MAX_LIVES
## When the countdown to the next life started (Unix time, in seconds).
## Using real-world time means lives refill even while the game is closed.
var life_timer_start: int = 0
## Booster id -> how many the player owns.
var boosters: Dictionary = {}
## Index of the next level to play (0-based). Each win moves it on by one.
var current_level: int = 0
## Garden progress: task id -> chosen style option (0 if the task has none).
var completed_tasks: Dictionary = {}
var area_index: int = 0
var seen_intro: bool = false

## Boosters chosen on the level start popup. The game screen uses them up.
## (Not saved: it's only used while switching from the garden to a level.)
var pending_boosters: Array = []


func _ready() -> void:
	load_game()


## _process runs every frame. Here it adds back lives as time passes.
func _process(_delta: float) -> void:
	_update_lives()


# =============================================================================
# COINS AND STARS
# =============================================================================

func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)
	save_game()


## Spends coins if there are enough. Returns true on success.
func try_spend_coins(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	coins_changed.emit(coins)
	save_game()
	return true


func try_spend_stars(amount: int) -> bool:
	if amount > stars:
		return false
	stars -= amount
	stars_changed.emit(stars)
	save_game()
	return true


## Records a won level: +1 star, the coin reward, and on to the next level.
func complete_level(coin_reward: int) -> void:
	stars += 1
	coins += coin_reward
	current_level += 1
	stars_changed.emit(stars)
	coins_changed.emit(coins)
	save_game()


# =============================================================================
# LIVES
# =============================================================================
# The usual pattern: store WHEN the countdown started, not "seconds left".
# The number of lives earned is (now - start) / refill time. That works across
# app restarts and you never have to save a constantly changing timer.

func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _update_lives() -> void:
	if lives >= MAX_LIVES:
		return
	var elapsed := _now() - life_timer_start
	if elapsed < LIFE_REFILL_SECONDS:
		return
	var earned := elapsed / LIFE_REFILL_SECONDS   # integer division on purpose
	lives = mini(MAX_LIVES, lives + earned)
	# Keep the leftover time, so a half-finished countdown isn't lost.
	life_timer_start += earned * LIFE_REFILL_SECONDS
	lives_changed.emit(lives)
	save_game()


func has_life() -> bool:
	return lives > 0


## Takes a life (when a level is lost or abandoned).
func lose_life() -> void:
	if lives <= 0:
		return
	if lives == MAX_LIVES:
		# The countdown only runs while lives are missing, so start it now.
		life_timer_start = _now()
	lives -= 1
	lives_changed.emit(lives)
	save_game()


## Seconds until the next life, or 0 if lives are full.
func seconds_to_next_life() -> int:
	if lives >= MAX_LIVES:
		return 0
	return maxi(0, LIFE_REFILL_SECONDS - (_now() - life_timer_start))


func refill_lives() -> void:
	lives = MAX_LIVES
	lives_changed.emit(lives)
	save_game()


# =============================================================================
# BOOSTERS
# =============================================================================

func booster_count(id: String) -> int:
	return int(boosters.get(id, 0))


func add_booster(id: String, amount: int = 1) -> void:
	boosters[id] = booster_count(id) + amount
	boosters_changed.emit()
	save_game()


## Uses one booster. Returns false if the player has none.
func use_booster(id: String) -> bool:
	if booster_count(id) <= 0:
		return false
	boosters[id] = booster_count(id) - 1
	boosters_changed.emit()
	save_game()
	return true


func buy_booster(id: String) -> bool:
	if not try_spend_coins(int(BOOSTER_PRICES.get(id, 999999))):
		return false
	add_booster(id)
	return true


# =============================================================================
# GARDEN
# =============================================================================

func is_task_done(task_id: String) -> bool:
	return completed_tasks.has(task_id)


func task_option(task_id: String) -> int:
	return int(completed_tasks.get(task_id, 0))


## A task can be started when it isn't done and all its requirements are.
func is_task_available(task: Dictionary) -> bool:
	if is_task_done(task["id"]):
		return false
	for required in task["requires"]:
		if not is_task_done(required):
			return false
	return true


## Pays the stars and marks the task done. Returns false if not affordable.
func complete_task(task: Dictionary, option: int) -> bool:
	if not is_task_available(task) or not try_spend_stars(int(task["cost"])):
		return false
	completed_tasks[task["id"]] = option
	garden_changed.emit()
	save_game()
	return true


## Changes the style of an already restored object (free).
func set_task_option(task_id: String, option: int) -> void:
	if is_task_done(task_id):
		completed_tasks[task_id] = option
		garden_changed.emit()
		save_game()


func is_area_complete(index: int) -> bool:
	for task in GardenData.get_area(index)["tasks"]:
		if not is_task_done(task["id"]):
			return false
	return true


func advance_area() -> void:
	if area_index < GardenData.area_count() - 1:
		area_index += 1
		garden_changed.emit()
		save_game()


func mark_intro_seen() -> void:
	seen_intro = true
	save_game()


# =============================================================================
# SAVE / LOAD
# =============================================================================

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"stars": stars,
		"lives": lives,
		"life_timer_start": life_timer_start,
		"boosters": boosters,
		"current_level": current_level,
		"completed_tasks": completed_tasks,
		"area_index": area_index,
		"seen_intro": seen_intro,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	# The file closes automatically when `file` goes out of scope.


func load_game() -> void:
	_reset_values()
	if FileAccess.file_exists(SAVE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			var data: Dictionary = parsed
			# IMPORTANT: JSON has a single number type, so every number comes
			# back as a float (5 -> 5.0). Convert with int() where we expect whole
			# numbers, including the values inside dictionaries.
			coins = int(data.get("coins", STARTING_COINS))
			stars = int(data.get("stars", 0))
			lives = int(data.get("lives", MAX_LIVES))
			life_timer_start = int(data.get("life_timer_start", 0))
			current_level = int(data.get("current_level", 0))
			area_index = int(data.get("area_index", 0))
			seen_intro = bool(data.get("seen_intro", false))
			var saved_boosters: Dictionary = data.get("boosters", {})
			for id in saved_boosters:
				boosters[id] = int(saved_boosters[id])
			var saved_tasks: Dictionary = data.get("completed_tasks", {})
			for id in saved_tasks:
				completed_tasks[id] = int(saved_tasks[id])
		else:
			push_warning("Save file is damaged, starting fresh.")
	_update_lives()
	_emit_all()


## Wipes all progress.
func reset_progress() -> void:
	_reset_values()
	save_game()
	_emit_all()


func _reset_values() -> void:
	coins = STARTING_COINS
	stars = 0
	lives = MAX_LIVES
	life_timer_start = 0
	boosters = STARTING_BOOSTERS.duplicate()
	current_level = 0
	completed_tasks = {}
	area_index = 0
	seen_intro = false


func _emit_all() -> void:
	coins_changed.emit(coins)
	stars_changed.emit(stars)
	lives_changed.emit(lives)
	boosters_changed.emit()
	garden_changed.emit()
