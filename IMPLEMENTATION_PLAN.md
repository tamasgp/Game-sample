# Implementation Plan: Fishdom-style Sample Game

This plan explains **what** we are building, **why** each technical decision was
made, and **in what order** to build it. It is written for someone learning game
development, so each phase lists the concepts you will practise in it.

---

## 1. Game concept

Fishdom combines two loops:

| Loop | What the player does | Why it matters |
|------|----------------------|----------------|
| **Core loop** (minutes) | Solve a match-3 puzzle level: swap pieces, make matches, meet goals within a move limit. | Moment-to-moment fun. |
| **Meta loop** (days) | Spend coins earned from levels on fish and decorations for a personal aquarium. | A long-term reason to keep playing. |

```
   ┌──────────────┐  win   ┌───────────┐  spend  ┌──────────────┐
   │ Puzzle level │ ─────► │   Coins   │ ──────► │  Aquarium    │
   └──────────────┘        └───────────┘         └──────────────┘
          ▲                                             │
          └─────────── "I want the next fish!" ─────────┘
```

### Scope of this sample (MVP)

* 6 handcrafted match-3 levels with move limits and goals
  (collect colors, break ice, reach a score).
* Special pieces: **rocket** (match 4), **bomb** (L/T match), **rainbow** (match 5),
  plus chain reactions and special swaps.
* Cascades with increasing score multiplier, hints after idling, auto-shuffle when stuck.
* Stars (1–3) per level, coin rewards, level unlocking.
* Aquarium with 6 fish and 6 decorations to buy, fish that swim with steering
  behaviour and chase food when you tap the water.
* Persistent save game (JSON in `user://`).
* Runs on **Android, iOS, Windows, macOS, Linux and Web** from one codebase.

### Out of scope (see section 7, "Next steps")

Sound, real art assets, boosters, lives/energy, a world map, monetisation,
cloud saves, analytics.

---

## 2. Technology choice

**Engine: Godot 4.3+ with GDScript.**

| Requirement | How Godot meets it |
|-------------|--------------------|
| Not iOS-only | One project exports to Android, iOS, desktop and Web. |
| Good for learning | Free and open source, small download, beginner-friendly Python-like language, excellent docs. |
| 2D focus | Dedicated 2D engine (not 3D with a 2D mode), pixel-based coordinates, built-in tweens. |
| No licence fees | MIT licence, no royalties. |

**Renderer: Compatibility (OpenGL ES 3 / WebGL 2).** It has the widest device
support, including browsers, and the game only needs simple 2D.

**Art: drawn in code** with `_draw()`. The sample needs no image files, and you
can see how the drawing API works. Section 7 describes how to swap in sprites.

---

## 3. Architecture

### 3.1 Folder layout

```
project.godot              Engine settings (window size, autoloads, renderer)
scenes/                    One tiny .tscn per screen (root node + script)
  main_menu.tscn
  game.tscn
  aquarium.tscn
scripts/
  autoload/game_state.gd   Global: coins, progress, owned items, save/load
  data/level_data.gd       All levels as plain data
  data/aquarium_catalog.gd All shop items as plain data
  match3/board_model.gd    PURE LOGIC: grid, matching, specials, gravity
  match3/level_goals.gd    PURE LOGIC: goal tracking
  match3/board_view.gd     Visuals + input + turn animation loop
  match3/tile_view.gd      Drawing of a single piece
  match3/board_effect.gd   Short-lived explosion/beam effects
  aquarium/aquarium_screen.gd      Tank, feeding, shop UI
  aquarium/aquarium_fish.gd        Fish drawing + steering AI
  aquarium/aquarium_decoration.gd  Decoration drawing
  ui/main_menu.gd          Level select
  ui/game_screen.gd        HUD, goals, win/lose, results popup
  ui/ui_style.gd           Shared colors, button/label factories, shape helpers
  ui/star_row.gd           Custom-drawn star rating control
tests/test_runner.gd       Headless unit tests for the pure-logic classes
docs/LEARNING_GUIDE.md     Concepts explained + exercises
```

### 3.2 Key design decisions

1. **Model/View separation for the puzzle.**
   `BoardModel` holds rules and state and never waits or draws.
   `BoardView` animates what the model reports.
   *Benefits:* unit-testable rules, deterministic behaviour with a seed,
   the visuals can be replaced without touching the rules.

2. **Turn loop as a coroutine.**
   `BoardView._play_turn()` is written top-to-bottom with `await` between
   animation steps (swap → clear → fall → repeat), instead of a state machine
   spread across callbacks. This is the most readable approach for a learner.
   (A larger game might switch to an explicit state machine, see 7.)

3. **Signals for communication upward.**
   `BoardView` emits `move_committed`, `pieces_cleared`, `turn_finished`.
   `GameScreen` listens and applies the *level* rules (moves, score, goals).
   The board doesn't know what a "level" is, so it can be reused for other modes.

4. **Data-driven content.**
   Levels and shop items are dictionaries in `level_data.gd` / `aquarium_catalog.gd`.
   Adding content does not require changing logic.

5. **One autoload for persistent state.**
   `GameState` is the only global. It also carries the "selected level" between
   scenes. Everything else is owned by its scene.

6. **UI built in code.**
   Each screen's `.tscn` contains only a root node; children are created in
   `_ready()`. This keeps the sample readable as plain text. In your own
   projects you would usually build menus in the editor.

7. **Resolution independence.**
   Design resolution 720×1280 portrait with `canvas_items` stretch and `expand`
   aspect. The board is drawn at 80 px per cell and the whole node is scaled to fit.

### 3.3 Turn sequence

```
Player swipes A→B
      │
      ▼
model.swap(A,B) ──► animate swap
      │
      ▼
forced = model.special_swap_activations(A,B)
result = model.resolve_matches([A,B], forced)
      │
      ├── result empty? ──► swap back (no move used) ──► done
      │
      ▼
emit move_committed  (GameScreen: moves -= 1)
      │
      ▼
┌─► emit pieces_cleared(result)  (GameScreen: score, goals)
│   animate clear / effects / new specials
│   gravity = model.apply_gravity() ──► animate falling + spawning
│   result = model.resolve_matches([], [], cascade+1)
└── while result not empty
      │
      ▼
no moves left? ──► model.shuffle() ──► animate
      │
      ▼
emit turn_finished  (GameScreen: win? lose?)
```

---

## 4. Implementation phases

Each phase leaves you with something runnable. Commit after each one.

### Phase 0: Project setup *(~1 hour)*
- [x] Create Godot project, portrait 720×1280, Compatibility renderer.
- [x] Configure stretch mode and touch-to-mouse emulation.
- [x] Add `.gitignore` for `.godot/`.

*Concepts:* project settings, `res://` vs `user://`, version control for Godot.

### Phase 1: Static board *(~half a day)*
- [x] `BoardModel.setup()` from text layout (holes, ice).
- [x] Random fill **without** starting matches.
- [x] `TileView` draws 6 distinct shapes/colors.
- [x] `BoardView` creates tiles and draws the cell background.

*Concepts:* 2D arrays, `_draw()`, nodes and the scene tree, coordinate conversion.

### Phase 2: Input and swapping *(~half a day)*
- [x] Swipe detection and tap-tap selection.
- [x] `is_valid_swap()`, invalid swaps animate back.
- [x] Tween-based swap animation.

*Concepts:* input events, `make_input_local`, tweens, `await`.

### Phase 3: Matching, gravity, cascades *(~1 day)*
- [x] Horizontal/vertical run detection, merging runs into L/T groups.
- [x] Remove pieces, gravity with holes, refill from the top.
- [x] Cascade loop with score multiplier.
- [x] `find_possible_move()` + shuffle when stuck.
- [x] Unit tests for all of the above.

*Concepts:* grid algorithms, work-list algorithms, unit testing, seeded RNG.

### Phase 4: Special pieces *(~1 day)*
- [x] Rocket (4), bomb (L/T), rainbow (5), spawn at swipe position.
- [x] Chain reactions (specials triggering specials).
- [x] Special swaps (rainbow + color, rainbow + rainbow, rocket/bomb fire on swap).
- [x] Visual effects (beams, blasts, sparkles), score popups.

*Concepts:* breadth-first processing, fire-and-forget effect nodes.

### Phase 5: Level rules and HUD *(~1 day)*
- [x] Level data (moves, colors, layout, goals, star thresholds, coins).
- [x] `LevelGoals` (collect / ice / score).
- [x] HUD: moves, score, goal icons. Win/lose detection, results popup.
- [x] Hints after 5 seconds of inactivity.

*Concepts:* data-driven design, signals, containers and anchors.

### Phase 6: Meta game *(~1 day)*
- [x] `GameState` autoload: coins, stars, unlocks, inventory.
- [x] JSON save/load in `user://` (with float→int caveat).
- [x] Main menu with level grid and stars.
- [x] Aquarium: background, sand, bubbles, light rays.
- [x] Fish with steering behaviour; decorations; shop with previews.
- [x] Tap to feed: food sinks, fish chase and eat it.

*Concepts:* autoloads/singletons, persistence, steering behaviours, recursion (coral).

### Phase 7: Platform builds *(~half a day)*
- [ ] Install export templates (Editor → Manage Export Templates).
- [ ] Add export presets: Android, iOS, Web, Windows/macOS/Linux.
- [ ] Android: install the Android SDK + JDK 17, set paths in Editor Settings, create a debug keystore.
- [ ] iOS: requires a Mac with Xcode; export an Xcode project and build from there.
- [ ] Web: export, then serve with a local web server (`python -m http.server`).
- [ ] Test on at least one real phone (touch feel and performance).

*Concepts:* export templates, signing, platform differences.

### Phase 8: Polish (suggested next work)
See section 7.

---

## 5. Testing strategy

| Layer | How | Where |
|-------|-----|-------|
| Puzzle rules | Automated unit tests on `BoardModel` / `LevelGoals` with fixed seeds and hand-written boards (`load_colors`). | `tests/test_runner.gd` |
| Level balance | Play each level; ideally a bot that plays random valid moves 1000× and reports win rate. | Future work |
| UI / feel | Manual testing on desktop + one phone. Check different aspect ratios with the editor's window size override. | Manual |
| Save system | Win a level, quit, restart, verify coins/stars. Corrupt the save file and verify the game starts fresh. | Manual |

Run tests headless:

```bash
godot --headless --import                         # once, builds the class cache
godot --headless --script res://tests/test_runner.gd
```

---

## 6. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Generated board has no valid moves | `fill_initial()` retries; `shuffle()` after every turn when stuck, with recolor fallback. |
| Input during animations corrupts state | `BoardView.busy` flag blocks input until `turn_finished`. |
| Different screen shapes break layout | Container-based UI + scaled board + `expand` stretch aspect. |
| Save format changes break old saves | `SAVE_VERSION` field, defensive `get()` with defaults, unknown item ids ignored. |
| JSON numbers load as floats | Explicit `int()` conversions in `GameState.load_game()`. |
| Tween with no animations errors | `_finish()` helper kills empty tweens instead of awaiting them. |

---

## 7. Next steps (ideas to extend the sample)

Roughly in order of learning value:

1. **Sound & music:** add an `AudioManager` autoload with `AudioStreamPlayer`s;
   play sounds on swap, match, special, win. Add a mute toggle saved in `GameState`.
2. **Real art:** replace `TileView._draw()` with a `Sprite2D` and textures
   (e.g. from kenney.nl, CC0). Add `GPUParticles2D` for explosions.
3. **Boosters:** hammer (remove one piece), extra moves. Purchasable with coins.
4. **More blockers:** stone (needs adjacent match), chains (piece can't move),
   "collect item" pieces that must reach the bottom row (Fishdom-style).
5. **World map:** a scrolling path of levels instead of a grid.
6. **Fish needs:** fish get hungry over time; a happy tank pays out bonus coins
   (gives the aquarium gameplay, not just decoration).
7. **Level editor:** an in-game or editor-plugin tool that writes level data.
8. **State machine:** replace the coroutine turn loop with explicit states
   (IDLE, SWAPPING, CLEARING, FALLING, SHUFFLING) when adding features like
   boosters that interrupt the flow.
9. **Localisation:** `tr()` + CSV translation files.
10. **Monetisation/analytics/cloud save:** platform plugins (only once the core is fun!).

---

## 8. Definition of done (MVP)

The code for every item below is written. The unchecked items still need a
play-through in the engine to confirm them.

- [x] Unit tests are written for the puzzle rules and goals.
- [ ] All 6 levels are winnable and losable (play-test and tune `moves` / `stars`).
- [ ] Coins and stars persist across restarts.
- [ ] All 12 shop items can be bought and appear in the aquarium.
- [ ] Unit tests pass when run in Godot (not run yet, see README).
- [ ] Exported and tested on Android + Web + one desktop OS.
