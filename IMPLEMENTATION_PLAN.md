# Implementation Plan: Garden Match Sample

This plan explains **what** we build, **why** each decision was made, and
**in which order** to build it. Each phase lists the game-dev concepts you
practise in it.

---

## 1. Concept

A match-3 puzzle game with a garden-restoration meta game, in the style of the
popular "match-3 + makeover" genre.

### Original, not a copy

The request was a clone "as identical as possible" of a commercial game. We
built an **original game in the same genre** instead:

| Kept: genre mechanics (not owned by anyone) | Replaced: anything that belongs to the original game |
|----------------------------------------------|------------------------------------------------------|
| Win levels → stars → spend on tasks | Name, logo, title |
| Choose 1 of 3 styles per task | Characters (our helper is "Olive", an original gardener) |
| Lives with a refill timer, coins, boosters | Story, dialog, garden areas and layout |
| Rockets, bombs, rainbow, a square-match flyer | Art, music, sounds, UI look |
| Crates, ground tiles (weeds), extra moves offer | Level designs |

This is also the better learning path. Copying assets teaches nothing about
design, and building your own variations teaches everything.

### Game loops

```
         ┌──────────── core loop (minutes) ────────────┐
         │  swap → match → specials → goals → win/lose │
         └───────────────────────┬─────────────────────┘
                                 │ +1 star, +coins
                                 ▼
         ┌──────────── meta loop (days) ───────────────┐
         │ spend stars → restore object → choose style │
         │ → story line → new tasks unlock → area done │
         └───────────────────────┬─────────────────────┘
                                 │ "one more level for the next task"
                                 ▼
                           back to Play
```

### The economy (3 currencies, each with one job)

| Currency | Earned by | Spent on | Purpose |
|----------|-----------|----------|---------|
| ⭐ Stars | 1 per won level | Garden tasks | Story progress. Can't be bought. |
| 🪙 Coins | Won levels + leftover moves | Boosters, +5 moves, lives refill | Helps when stuck |
| ❤️ Lives | 1 per 20 minutes (max 5) | Lost on failing/quitting a level | Paces sessions |

---

## 2. Technology

* **Godot 4.3+, GDScript:** free, exports to Android/iOS/Web/desktop, and the
  language is beginner-friendly.
* **Compatibility renderer:** widest device support, including browsers.
* **Procedural art (`_draw()`):** no asset files, and every visual is readable
  code. Swapping in sprites later is a local change (see 7).
* **UI built in code:** each scene is a root node plus a script, so everything
  can be read top to bottom with comments.

---

## 3. Architecture

```
                      ┌──────────────────────┐
                      │ GameState (autoload) │  stars, coins, lives, boosters,
                      │   save/load JSON     │  tasks, current level
                      └──────────┬───────────┘
              ┌──────────────────┴───────────────────┐
              ▼                                      ▼
   garden.tscn (GardenScreen)              game.tscn (GameScreen)
   ├─ GardenObject × N  (before/after)     ├─ BoardModel  (pure rules)
   ├─ DialogBox (story)                    ├─ LevelGoals  (pure rules)
   └─ Modal popups (tasks, level start)    ├─ BoardView   (animation + input)
              ▲                            │   └─ TileView × N, BoardEffect
              │ GardenData (tasks, story)  └─ Modal popups (win, lose, +moves)
              │                                      ▲
              └──────────── LevelData (levels + generator) ─────┘
```

### Key decisions

1. **Model/View split for the puzzle.** `BoardModel` changes data instantly
   and returns a `ClearResult`. `BoardView` animates it. The rules can be
   tested without graphics and are reproducible with a seed.
2. **Turn loop as a coroutine** (`await` between steps). It's readable, and
   one `_resolve_loop()` is shared by swaps, the shovel and the win bonus.
3. **"Call down, signal up."** BoardView emits `move_committed`,
   `pieces_cleared`, `turn_finished`, `tool_used`. GameScreen applies the
   level rules. The board knows nothing about levels or coins.
4. **Data-driven content.** Levels, tasks, dialog and object placement are
   plain data. A generator makes unlimited levels from the level number
   (deterministic).
5. **Task dependency graph.** `requires` on each task unlocks them gradually,
   so the player always has 1–3 clear choices.
6. **Real-time lives.** Store the *start time* of the countdown, not the
   remaining seconds. It survives restarts and is simple to compute.
7. **Step-based gravity simulation.** It handles holes, crates and diagonal
   sliding with one simple, provably finishing loop.

### Turn sequence

```
swipe A→B ─► model.swap ─► animate
            forced = special_swap_activations(A,B)     (specials / combos)
            result = resolve_matches([A,B], forced)
            empty? ─► swap back, no move used
            move_committed ─► _resolve_loop:
                 ┌─► pieces_cleared(result) → score, goals
                 │   animate: butterfly flights → explosions → shrink → pop specials
                 │   gravity = apply_gravity() → animate falls / slides / spawns
                 │   result = resolve_matches([], [], cascade+1)
                 └── until empty
            stuck? ─► shuffle
            turn_finished ─► win? (banner → bonus rockets → rewards)
                             out of moves? (offer +5 moves → lose life)
```

---

## 4. Phases

Every phase ends with something runnable. Commit after each.

### Phase 1: Board basics *(done)*
- [x] Layout parsing: holes, weeds (1–2 layers), crates (1–2 hp)
- [x] Initial fill without lines OR squares, guaranteed possible move
- [x] TileView shapes/colors, board background, weeds and crates drawing

*Concepts:* 2D grids, layered cell data, `_draw()`.

### Phase 2: Input and swapping *(done)*
- [x] Swipe + tap-tap input via `_input` + `make_input_local`
- [x] Valid-swap check (lines, squares, specials), swap-back animation

*Concepts:* input events, coordinate spaces, tweens, `await`.

### Phase 3: Matching and gravity *(done)*
- [x] Run detection (H/V), 2×2 square detection, grouping into shapes
- [x] Step-based gravity: straight falls, spawns, diagonal slides around crates
- [x] Cascades with score multiplier, auto-shuffle

*Concepts:* grid algorithms, simulation loops, termination arguments.

### Phase 4: Specials, combos, obstacles *(done)*
- [x] Rocket / bomb / rainbow / butterfly creation and effects
- [x] Chain reactions (work-list algorithm)
- [x] Combos: cross, big cross, big bomb, rainbow convert, rainbow+rainbow
- [x] Crates hit by adjacent matches and explosions; weeds under pieces
- [x] Butterfly targeting priority (crates > weeds > anything)

*Concepts:* BFS-style processing, priority selection, effect nodes.

### Phase 5: Level flow *(done)*
- [x] 10 handcrafted tutorial-style levels + deterministic generator
- [x] Goals: collect color, clear weeds, break crates
- [x] HUD, shovel booster with tool mode, pre-level boosters
- [x] Win banner, leftover-moves bonus rockets, rewards popup
- [x] Out-of-moves offer (+5 for coins), lose life, quit confirmation

*Concepts:* data-driven design, procedural generation, signals, coroutines.

### Phase 6: Meta game *(done)*
- [x] GameState: stars, coins, lives with real-time refill, boosters, saving
- [x] Garden screen with 2 areas, 14 restorable objects (before/after states)
- [x] Task list with dependencies, star costs, style choices, restyling
- [x] Dialog box with typewriter effect, intro, per-task lines, area completion
- [x] Level start popup with booster selection, no-lives popup with refill

*Concepts:* autoloads, persistence, economy design, UI flows.

### Phase 7: Verify and ship *(to do)*
- [ ] Open in Godot, fix any typo-level errors, run the unit tests
- [ ] Play-test levels 1–15 and tune `moves`
- [ ] Export presets for Android, Web and one desktop OS; test on a real phone

---

## 5. Testing

| What | How |
|------|-----|
| Puzzle rules | `tests/test_runner.gd`: hand-built boards with `load_colors()` (matches, squares, crates, weeds, combos, butterfly targeting, diagonal gravity, shovel, generator) |
| Balance | Play-test. Better: a bot that plays random valid moves 1000× per level and reports the win rate (exercise in the guide) |
| Economy | Count stars needed per area vs. levels needed. Aim for about 1–2 sessions per area |
| Persistence | Win, quit, restart: stars/coins/tasks kept. Change the clock to test lives |

---

## 6. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Cells under crates never refill | Diagonal sliding in gravity, plus a level design rule: no two crates side by side (the generator follows it). `test_every_level_can_refill` checks 40 levels |
| Garden objects drawing over UI | z_index layers: objects 0–100, HUD 1000, popups 2000, dialog 2100 |
| Input during animation | `busy` flag; popups disable `input_enabled` |
| Stuck board | `find_possible_move()` + shuffle with recolor fallback |
| Save format changes | `version` field, defaults for missing keys, ids never renamed |
| JSON numbers become floats | Explicit `int()` on load, including dictionary values |
| Signals to freed scenes | Autoload signals connect to *methods* (auto-disconnected), not lambdas |

---

## 7. Next steps

1. **Sound and music**: an `AudioManager` autoload; sounds for swap, match, combo, task done.
2. **Real art**: sprites for pieces, painted garden backgrounds, `CPUParticles2D` effects.
3. **More obstacles**: drop items that must reach the bottom, chains, spreading weeds.
4. **Camera**: a larger garden you can pan around with `Camera2D` and drag gestures.
5. **More areas** in `garden_data.gd`, each with new object kinds.
6. **Daily rewards and events**: login streaks, limited-time tasks.
7. **Level editor**: an editor plugin or an in-game tool that writes level dictionaries.
8. **Localization**: `tr()` and CSV translations for all text and dialog.
