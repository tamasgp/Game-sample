## LevelGoals: keeps track of what the player must achieve to win a level.
##
## Like BoardModel, this is pure logic (no drawing), so it is easy to test.
## The game screen feeds it events ("these pieces were removed", "score is now
## X") and asks "is_complete()?" at the end of every turn.
##
## Supported goal types (as written in level_data.gd):
##   { "type": "collect", "color": 2, "amount": 20 }  -> remove 20 pieces of color 2
##   { "type": "ice" }                                -> break every ice layer
##   { "type": "score", "amount": 3000 }              -> reach 3000 points
class_name LevelGoals
extends RefCounted

## Emitted whenever progress changes, so the HUD knows to refresh.
## (Signals are Godot's built-in "observer pattern": other objects connect to
## them and get called back, without this class knowing who is listening.)
signal changed

## Each goal: { "type": String, "color": int, "target": int, "progress": int }
var goals: Array = []


## `goal_defs` comes from the level data. `initial_ice` is BoardModel.total_ice()
## right after the board was built (the ice goal needs to know the total).
func setup(goal_defs: Array, initial_ice: int) -> void:
	goals.clear()
	for def in goal_defs:
		var type: String = def.get("type", "")
		var goal := {"type": type, "color": int(def.get("color", -1)), "target": 0, "progress": 0}
		match type:
			"collect":
				goal["target"] = int(def.get("amount", 10))
			"score":
				goal["target"] = int(def.get("amount", 1000))
			"ice":
				goal["target"] = initial_ice
			_:
				push_warning("LevelGoals: unknown goal type '%s'" % type)
				continue
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


## Call with BoardModel.total_ice() after ice was hit.
func on_ice_remaining(remaining: int) -> void:
	for goal in goals:
		if goal["type"] == "ice":
			goal["progress"] = goal["target"] - remaining
	changed.emit()


func on_score_changed(score: int) -> void:
	for goal in goals:
		if goal["type"] == "score":
			goal["progress"] = mini(score, goal["target"])
	changed.emit()


static func is_goal_done(goal: Dictionary) -> bool:
	return int(goal["progress"]) >= int(goal["target"])


## The level is won when EVERY goal is done.
func is_complete() -> bool:
	for goal in goals:
		if not is_goal_done(goal):
			return false
	return true


## How many more are needed, for display ("x 12").
static func remaining(goal: Dictionary) -> int:
	return maxi(0, int(goal["target"]) - int(goal["progress"]))
