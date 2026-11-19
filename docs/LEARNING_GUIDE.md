# Learning Guide

Read this next to the source code. Each section names the file to open.
Every script also starts with a long header comment.

---

## Part 1: Godot building blocks used here

### Nodes, scenes, the scene tree
Everything is a **node**, and nodes form a tree. A **scene** (`.tscn`) is a
saved branch of that tree. `get_tree().change_scene_to_file(path)` swaps the
whole screen. This game has two scenes: `garden.tscn` (home) and `game.tscn`.
Their children are created in code in `_ready()`.

### Node2D vs Control
* **Node2D**: free-moving game things (pieces, garden objects, effects).
* **Control**: UI with anchors and containers (buttons, labels, popups).
* They mix well: the board (Node2D) sits inside a Control area and is scaled
  to fit (`game_screen.gd` → `_fit_board()`).

### The main callbacks
| Callback | When | Used for |
|----------|------|----------|
| `_ready()` | once, entering the tree | building the screen |
| `_process(delta)` | every frame | timers, animation, life countdown |
| `_draw()` | after `queue_redraw()` | all the procedural art |
| `_input(event)` | every input event | board touches |
| `_gui_input(event)` | input on this Control | garden taps, dialog taps |

### Signals: "call down, signal up"
```gdscript
signal turn_finished                                  # declare (board_view.gd)
turn_finished.emit()                                  # fire
board_view.turn_finished.connect(_on_turn_finished)   # listen (game_screen.gd)
```

### Tweens and `await`
```gdscript
var tween := create_tween().set_parallel(true)
tween.tween_property(tile, "position", target, 0.2).set_trans(Tween.TRANS_BOUNCE)
await tween.finished
```
`await` pauses the function, not the game. → `board_view.gd` `_play_turn()`

### Lambdas
A lambda is a small unnamed function stored in a variable:
```gdscript
var on_buy := func() -> void:
    GameState.buy_booster("shovel")
    Modal.close(box)          # uses `box` from the surrounding code ("capture")
buy.pressed.connect(on_buy)
```
→ `game_screen.gd`, `garden_screen.gd`. Note: connect *methods* (not lambdas)
to autoload signals, so they are disconnected automatically when the scene
is freed.

### Autoloads
`GameState` exists once for the whole game and survives scene changes.
→ `scripts/autoload/game_state.gd`

---

## Part 2: Match-3 techniques

| Technique | Where | Idea |
|-----------|-------|------|
| Rules separate from visuals | `board_model.gd` | testable, reproducible, reusable |
| Fill without matches | `_pick_color_without_match` | check left, up, and the 2×2 corner |
| Finding shapes | `_find_runs`, `find_matches` | runs + squares, merged into groups by shared cells |
| Choosing the special | `_special_for_group` | priority: 5-line > L/T > 4-line > square |
| Chain reactions | `resolve_matches` step 4 | a work list (breadth-first) |
| Combos | `special_swap_activations` | two specials → one stronger effect, the other is "consumed" |
| Butterfly targeting | `_butterfly_target` | priority lists: crates, then weeds, then anything |
| Gravity with obstacles | `apply_gravity` | step simulation: fall, spawn, then diagonal slide |
| Stuck detection | `find_possible_move`, `shuffle` | try every swap; Fisher-Yates shuffle |
| Game feel | `board_view.gd` | bounce, pop, beams, curved flights, score popups, hints, bonus |

---

## Part 3: Meta-game techniques

* **Three currencies with separate jobs** (stars, coins, lives). See the
  table in `game_state.gd`. Mixing them up is a classic design mistake.
* **Real-time timers:** save *when* a countdown started, then compute.
  → `GameState._update_lives()`
* **Dependency graph of tasks:** `requires` keeps the list short and ordered.
  → `garden_data.gd`, `GameState.is_task_available()`
* **Choices create ownership:** 3 style options per task, changeable later.
  → `garden_screen.gd` `_choose_option()`
* **Story as data:** dialog lines live next to the tasks they belong to.
* **Typewriter text:** tween `Label.visible_ratio`, and a tap skips ahead.
  → `dialog_box.gd`
* **Deterministic procedural levels:** same seed, same level.
  → `LevelData.generate_level()`

---

## Part 4: Exercises

### Warm-up
1. Change a task's cost or the bench colors in `garden_object.gd`.
2. Add level 11 to `LEVELS` with a heart-shaped layout using `#`.
3. Give new players 5 shovels (`STARTING_BOOSTERS`). Delete the save file to test:
   `user://` is shown in Godot under *Project → Open User Data Folder*.
4. Make lives refill every 30 seconds to test the timer quickly.

### Intermediate
5. **Butterfly + rocket combo:** the butterfly carries a rocket to its target
   and fires it there. Start in `special_swap_activations` and write a test first.
6. **Spreading weeds:** if no weed was cleared this turn, one weed spreads to a
   neighbouring cell.
7. **A third area** with 5 new tasks and 2 new object kinds.
8. **Settings popup:** a sound toggle and a "reset progress" button
   (`GameState.reset_progress()` exists).
9. **Rebuild the level HUD in the Godot editor** as a `.tscn` and instance it.

### Advanced
10. **Drop items:** a piece type that can't be matched and must fall to the
    bottom row to be collected (a new goal type).
11. **Level bot:** play each level 500× with random valid moves using only
    `BoardModel` and print the win rates. Use it to tune `moves`.
12. **Panning garden:** make the garden twice as tall as the screen and scroll
    it with a drag gesture and a `Camera2D`.
13. **Sprites:** replace `TileView._draw()` with a `Sprite2D` (see the comment
    at the top of `tile_view.gd`).

---

## Further reading

* Godot "Your first 2D game": <https://docs.godotengine.org/en/stable/getting_started/first_2d_game/>
* GDScript reference: <https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html>
* *Game Programming Patterns*, Robert Nystrom (free online): Observer, State, Game Loop
* "Juice it or lose it", a talk on game feel by Martin Jonasson and Petri Purho
* GDC talks on free-to-play economy and progression design
