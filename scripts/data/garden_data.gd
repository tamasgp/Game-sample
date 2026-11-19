## GardenData: the garden areas, their restoration tasks, and the story.
##
## ============================================================================
## THE META GAME
## ============================================================================
## This is what keeps players coming back to the puzzles:
##
##     win a level  ->  earn a star  ->  spend stars on a task  ->  the garden
##     gets prettier and the story moves on  ->  "one more level for the next
##     task!"
##
## Every task restores one object. Many tasks let the player CHOOSE between
## three styles (bench color, flower type, ...). Choices make players feel
## the garden is THEIRS, and they can change them later by tapping the object.
##
## ============================================================================
## TASK FIELDS
## ============================================================================
##   id        unique key, stored in the save file. Never rename it after
##             release, or players lose their progress!
##   title     shown in the task list
##   cost      stars needed
##   object    which GardenObject this task restores (see garden_object.gd)
##   requires  task ids that must be done first. This turns the list into a
##             small "dependency graph", so tasks appear in a sensible order
##             and only a few are offered at once.
##   options   (optional) style names to choose from
##   say       what the gardener says after the task is done
##
## OBJECT FIELDS (per area)
##   kind      how garden_object.gd draws it
##   pos       position as fractions of the screen (0..1), so the garden
##             adapts to any screen size
##   scale     size multiplier
class_name GardenData
extends RefCounted

## The gardener who tells the story. An original character for this sample.
const HELPER_NAME := "Olive"

const INTRO_LINES: Array = [
	"Oh, hello! I'm Olive. My grandma left me this garden...",
	"It used to be the prettiest garden in town. Now look at it!",
	"Every puzzle you solve earns a star. With stars, we can fix things up.",
	"Tap PLAY to earn your first star, then open the TASKS list!",
]

const AREAS: Array = [
	{
		"name": "Old Courtyard",
		"background": "courtyard",
		"objects": {
			"gate": {"kind": "gate", "pos": Vector2(0.5, 0.32), "scale": 1.0},
			"tree": {"kind": "tree", "pos": Vector2(0.18, 0.38), "scale": 1.0},
			"path": {"kind": "path", "pos": Vector2(0.5, 0.6), "scale": 1.0},
			"fountain": {"kind": "fountain", "pos": Vector2(0.5, 0.52), "scale": 1.0},
			"flowerbed": {"kind": "flowerbed", "pos": Vector2(0.2, 0.66), "scale": 1.0},
			"bench": {"kind": "bench", "pos": Vector2(0.8, 0.62), "scale": 1.0},
			"lanterns": {"kind": "lanterns", "pos": Vector2(0.5, 0.6), "scale": 1.0},
			"weeds": {"kind": "weeds", "pos": Vector2(0.5, 0.6), "scale": 1.0},
		},
		"tasks": [
			{"id": "weeds", "title": "Pull out the weeds", "cost": 1, "object": "weeds", "requires": [],
				"say": "Much better! I can finally see the old stone path."},
			{"id": "path", "title": "Repair the stone path", "cost": 1, "object": "path", "requires": ["weeds"],
				"say": "No more tripping over broken stones!"},
			{"id": "flowerbed", "title": "Plant a flower bed", "cost": 1, "object": "flowerbed", "requires": ["weeds"],
				"options": ["Red roses", "Yellow tulips", "Lavender"],
				"say": "Grandma always said flowers make people smile."},
			{"id": "fountain", "title": "Restore the fountain", "cost": 2, "object": "fountain", "requires": ["path"],
				"options": ["Classic stone", "Blue tiles", "Golden"],
				"say": "Listen to that water! It works again!"},
			{"id": "bench", "title": "Build a bench", "cost": 2, "object": "bench", "requires": ["path"],
				"options": ["Oak wood", "White", "Red"],
				"say": "A perfect spot to rest after a long day of gardening."},
			{"id": "tree", "title": "Plant an apple tree", "cost": 2, "object": "tree", "requires": ["flowerbed"],
				"say": "In a few years we'll have apple pie every week!"},
			{"id": "lanterns", "title": "Hang lanterns", "cost": 1, "object": "lanterns", "requires": ["bench", "fountain"],
				"options": ["Warm yellow", "Cool blue", "Pink"],
				"say": "Now the garden looks lovely even at night."},
			{"id": "gate", "title": "Fix the garden gate", "cost": 2, "object": "gate", "requires": ["lanterns", "tree"],
				"say": "The courtyard is finished! I wonder what's behind the gate..."},
		],
	},
	{
		"name": "Lakeside",
		"background": "lakeside",
		"objects": {
			"pond": {"kind": "pond", "pos": Vector2(0.5, 0.52), "scale": 1.0},
			"lilies": {"kind": "lilies", "pos": Vector2(0.5, 0.52), "scale": 1.0},
			"bridge": {"kind": "bridge", "pos": Vector2(0.5, 0.52), "scale": 1.0},
			"gazebo": {"kind": "gazebo", "pos": Vector2(0.78, 0.3), "scale": 1.0},
			"boat": {"kind": "boat", "pos": Vector2(0.25, 0.64), "scale": 1.0},
			"reeds": {"kind": "reeds", "pos": Vector2(0.14, 0.78), "scale": 1.0},
		},
		"tasks": [
			{"id": "pond", "title": "Clean the pond", "cost": 1, "object": "pond", "requires": [],
				"say": "Wow, the water is so clear! I can see fish!"},
			{"id": "reeds", "title": "Plant reeds", "cost": 1, "object": "reeds", "requires": ["pond"],
				"say": "The ducks will love these."},
			{"id": "lilies", "title": "Plant water lilies", "cost": 1, "object": "lilies", "requires": ["pond"],
				"options": ["White", "Pink", "Yellow"],
				"say": "They look like little floating stars."},
			{"id": "bridge", "title": "Build a bridge", "cost": 2, "object": "bridge", "requires": ["pond"],
				"options": ["Wooden", "Red", "Stone"],
				"say": "Now we can walk across the pond!"},
			{"id": "boat", "title": "Repair the rowing boat", "cost": 2, "object": "boat", "requires": ["reeds"],
				"say": "Who wants to go for a ride?"},
			{"id": "gazebo", "title": "Build a gazebo", "cost": 3, "object": "gazebo", "requires": ["bridge", "lilies"],
				"options": ["White", "Green", "Blue"],
				"say": "The whole garden is restored! Grandma would be so proud. Thank you!"},
		],
	},
]


static func area_count() -> int:
	return AREAS.size()


static func get_area(index: int) -> Dictionary:
	return AREAS[clampi(index, 0, AREAS.size() - 1)]


## Finds a task by id in any area. Returns {} if it doesn't exist.
static func find_task(task_id: String) -> Dictionary:
	for area in AREAS:
		for task in area["tasks"]:
			if task["id"] == task_id:
				return task
	return {}


## The task (if any) that restores `object_id` in an area.
static func task_for_object(area: Dictionary, object_id: String) -> Dictionary:
	for task in area["tasks"]:
		if task["object"] == object_id:
			return task
	return {}
