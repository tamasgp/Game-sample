# Learning Guide

This guide walks through the game-development ideas used in this sample, points
to the code where each one appears, and ends with exercises in increasing
difficulty. Read it alongside the source. Every script has a header comment
that goes into more detail.

---

## Part 1: Godot basics used here

### Nodes, scenes and the scene tree
Everything in Godot is a **node**. Nodes form a tree. A **scene** (`.tscn`) is a
saved branch of that tree. When you call
`get_tree().change_scene_to_file("res://scenes/game.tscn")`, Godot frees the
current scene and loads the new one.

* Each screen here is one scene: `main_menu`, `game`, `aquarium`.
* Child nodes are created in code with `Node.new()` + `add_child()`.
  → `scripts/ui/game_screen.gd`, `_build_ui()`

### Node2D vs Control
* **Node2D**: game objects that are positioned freely (pieces, fish, effects).
* **Control**: UI elements that use anchors and containers (buttons, labels, panels).
* You can mix them. The board (a Node2D) lives inside a Control area.
  → `game_screen.gd`, `_fit_board()`

### The game loop: `_ready`, `_process`, `_draw`
| Callback | When it runs | Used for |
|----------|--------------|----------|
| `_ready()` | once, when the node enters the tree | setup |
| `_process(delta)` | every frame; `delta` = seconds since last frame | movement, timers |
| `_draw()` | when `queue_redraw()` was called | custom drawing |
| `_input(event)` | for every input event | reading touches / mouse |

**Always multiply movement by `delta`**, so speed is in pixels **per second**
and doesn't depend on frame rate.
→ `aquarium_fish.gd`: `position += velocity * delta`

### Signals
Signals let a node announce "something happened" without knowing who cares.
```gdscript
signal turn_finished          # declare
turn_finished.emit()          # fire
board_view.turn_finished.connect(_on_turn_finished)   # listen
```
Rule of thumb: **call down, signal up.** Parents call methods on children.
Children emit signals that parents listen to.
→ `board_view.gd` (emits) and `game_screen.gd` (connects)

### Tweens
A Tween animates a property from its current value to a target over time.
```gdscript
var tween := create_tween()
tween.tween_property(tile, "position", target, 0.2)
await tween.finished
```
* `set_parallel(true)`: run all animations at once
* `set_trans()/set_ease()`: the motion curve (bounce, back, quad...)
* `chain()`: wait for previous ones before continuing
→ `board_view.gd`, `board_effect.gd`

### Coroutines with `await`
`await something` pauses the function until the signal fires, while the rest of
the game keeps running. That lets us write the turn as a readable sequence.
→ `board_view.gd`, `_play_turn()`

### Autoloads (singletons)
A script registered in *Project Settings → Autoload* exists once for the whole
game and survives scene changes.
→ `scripts/autoload/game_state.gd`

---

## Part 2: Match-3 techniques

### Separate the rules from the visuals
`BoardModel` is a plain object (`RefCounted`, not a Node). It changes the grid
instantly. `BoardView` then animates the change. This makes the rules:
* **testable** (see `tests/test_runner.gd`)
* **deterministic** (same seed = same board, which helps with bug reports)
* **reusable** (an AI or level solver can simulate moves without graphics)

### Generating a board without matches
Fill the board cell by cell. For each cell, don't pick a color that matches
the two cells to the left or the two above.
→ `board_model.gd`, `_pick_color_without_match()`

### Finding matches
1. Scan each row for runs of 3+ equal colors, then each column.
2. Merge runs that share a cell into one **group** (this finds L and T shapes).
3. Look at the group's shape to decide which special to create.
→ `_find_runs()`, `find_matches()`, `_special_for_group()`

### Chain reactions with a work list
When a special is removed it explodes and may hit other specials. We keep a
list of cells still to check, and every explosion adds new cells to it. This is
basically a **breadth-first search**, an algorithm you will use often
(flood fills, path finding, ...).
→ `resolve_matches()`, step 3

### Gravity with "two pointers"
For each column, walk from the bottom up. A `read` index finds pieces, and a
`write` index marks the lowest empty slot. Pieces move from `read` to `write`.
Whatever is left at the top gets new pieces.
→ `apply_gravity()`

### Detecting a stuck board
Try every possible swap (right and down neighbours), check for a match,
then undo. If none works, shuffle (Fisher-Yates) until the board is playable.
→ `find_possible_move()`, `shuffle()`

### Game feel ("juice")
Small touches make a big difference:
* pieces **bounce** when they land (`TRANS_BOUNCE`)
* new specials **pop** in (`TRANS_BACK`)
* floating **score text** with a cascade multiplier
* **beams and blasts** for specials
* a **hint pulse** after 5 seconds idle
* invalid swaps **swap back** instead of doing nothing

Try changing the timing constants at the top of `board_view.gd` to see how
much the feel changes.

---

## Part 3: Meta game techniques

### The core/meta loop
Puzzle → coins → aquarium → motivation → puzzle. The economy numbers (rewards in
`level_data.gd`, prices in `aquarium_catalog.gd`) decide how long it takes to
earn each item. Tuning them is a real game-design job.

### Saving data
* Save to `user://`. `res://` is read-only in exported games.
* JSON numbers load as floats, so convert them with `int()`.
* Store item **ids**, not indices, so reordering the catalog doesn't break saves.
* Keep a `version` field for future migrations.
→ `game_state.gd`

### Steering behaviours
Instead of moving straight to a target, blend the current velocity toward a
desired velocity. The result is smooth, natural-looking motion.
→ `aquarium_fish.gd`, `_process()`

### Procedural drawing
Shapes are built from math: circles from `cos/sin`, stars by alternating two
radii, swaying plants with `sin(time + offset)`, coral with **recursion**.
→ `ui_style.gd`, `aquarium_decoration.gd`

---

## Part 4: Exercises

### Warm-up
1. Change the colors in `TileView.COLORS`. Run the game.
2. Add a 7th level in `level_data.gd` with a heart-shaped layout using `#` holes.
3. Make the bomb bigger: change `BOMB_RADIUS` to `2`. Does the effect still fit?
4. Add a new fish to `aquarium_catalog.gd` with your own colors and speed.

### Intermediate
5. **Move counter warning:** make the moves label pulse (Tween on `scale`) when
   5 or fewer moves are left. Hint: set `pivot_offset` to the label's center.
6. **Sound:** add `AudioStreamPlayer` nodes and play a sound in
   `_on_pieces_cleared`. Free sounds: kenney.nl, freesound.org.
7. **Rebuild the HUD in the editor:** create a `hud.tscn` scene visually and
   instance it from `game_screen.gd` instead of `_build_ui()`.
8. **Double-tap to fire a special** without swapping it.
9. **Rocket + rocket combo:** when two rockets are swapped together, clear both
   the row AND the column. Look at `special_swap_activations()`.

### Advanced
10. **Stone blocker:** a new cell type that can't hold pieces and breaks when a
    match happens next to it. Needs changes in the layout parser, `resolve_matches`
    and `_draw`. Write a unit test first!
11. **Level bot:** write a script that plays each level 500 times with random
    valid moves and prints the win rate. Use it to balance `moves`.
12. **Hungry fish:** fish get hungry over time and change color when hungry.
    Fed fish slowly produce coins you can collect by tapping.
13. **State machine:** rewrite `_play_turn` as an explicit state machine and
    compare the readability.

---

## Further reading

* Godot docs, "Your first 2D game": <https://docs.godotengine.org/en/stable/getting_started/first_2d_game/>
* GDScript reference: <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html>
* "Juice it or lose it" (talk about game feel) by Martin Jonasson & Petri Purho
* Craig Reynolds, "Steering Behaviors For Autonomous Characters"
* *Game Programming Patterns* by Robert Nystrom (free online), especially the
  Observer (signals), State and Game Loop chapters
