## LevelGoals: tracks what the player must do to win a level.
##
## Pure logic (no drawing), like BoardModel, so it's easy to test.
## The game screen feeds it events and asks is_complete() after every turn.
##
## Goal types, as written in level_data.gd:
##     { "type": "collect", "color": 2, "amount": 20 }   remove 20 pieces of color 2
##     { "type": "weeds" }                               remove every weed layer
##     { "type": "crates" }                              break every crate
##
## For "weeds" and "crates" the target is counted from the board itself when
## the level starts, so level designers never have to count them by hand.
class_name LevelGoals
extends RefCounted

## Emitted whenever progress changes, so the HUD can refresh.
## Signals are Godot's built-in "observer pattern": listeners connect to them
## and get called back, and this class never needs to know who they are.
signal changed

## Each goal is { "type": String, "color": int, "target": int, "progress": int }
var goals: Array = []


## `initial_weeds` and `initial_crates` come from the board right after setup.
func setup(goal_defs: Array, initial_weeds: int, initial_crates: int) -> void:
	goals.clear()
	for def in goal_defs:
		var goal_type: String = def.get("type", "")
		var goal := {"type": goal_type, "color": int(def.get("color", -1)), "target": 0, "progress": 0}
		match goal_type:
			"collect":
				goal["target"] = int(def.get("amount", 10))
			"weeds":
				goal["target"] = initial_weeds
			"crates":
				goal["target"] = initial_crates
			_:
				push_warning("LevelGoals: unknown goal type '%s'" % goal_type)
				continue   # inside `match`, this continues the `for` loop
		goals.append(goal)
	changed.emit()


## Call with ClearResult.removed (Array of { "piece": Piece, "cell": Vector2i }).
func on_pieces_removed(removed: Array) -> void:
	var any_change := false
	for goal in goals:
		if goal["type"] != "collect":
			continue
		for entry in removed:
			if entry["piece"].color == goal["color"] and goal["progress"] < goal["target"]:
				goal["progress"] += 1
				any_change = true
	if any_change:
		changed.emit()


## Call after a step with the board's remaining weeds and crates.
## progress = how many there were at the start - how many are left.
func on_obstacles_remaining(weeds_left: int, crates_left: int) -> void:
	for goal in goals:
		match String(goal["type"]):
			"weeds":
				goal["progress"] = int(goal["target"]) - weeds_left
			"crates":
				goal["progress"] = int(goal["target"]) - crates_left
	changed.emit()


static func is_goal_done(goal: Dictionary) -> bool:
	return int(goal["progress"]) >= int(goal["target"])


## The level is won when EVERY goal is done.
func is_complete() -> bool:
	for goal in goals:
		if not is_goal_done(goal):
			return false
	return true


## How many are still needed (for the "x 12" label).
static func remaining(goal: Dictionary) -> int:
	return maxi(0, int(goal["target"]) - int(goal["progress"]))
