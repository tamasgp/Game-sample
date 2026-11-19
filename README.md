# Garden Match Sample: match-3 + garden restoration in Godot 4

A **heavily commented** learning project in the genre of "match-3 + home/garden
makeover" games: solve puzzle levels to earn stars, and spend the stars to
restore an overgrown garden while a gardener tells the story.

> **This is an original game in that genre, not a copy of any specific game.**
> It uses the genre's common mechanics (stars for tasks, style choices, lives,
> boosters, crates, special pieces), but its name, character, story, levels and
> art are all original. Copying a commercial game's name, characters, art or
> levels would infringe the owner's rights, and it wouldn't teach you more than
> building your own version.

* **Engine:** [Godot 4.3+](https://godotengine.org/download) (free, open source)
* **Language:** GDScript
* **Platforms:** Android, iOS, Web, Windows, macOS, Linux
* **Art:** everything is drawn in code, so there are no image files

---

## Quick start

1. Install **Godot 4.3 or newer** (standard version, not .NET).
2. Godot → **Import** → pick this folder's `project.godot`.
3. Press **F5** to run. The window is phone-shaped; use the mouse like a finger.

## How to play

**In the garden (home screen)**
* **Play**: opens the next level. Pick pre-level boosters, then start.
* **Tasks**: spend stars to restore things. Some tasks let you choose a style.
* Tap a restored object later to change its style for free.
* Top bar: **lives** (with refill timer), **coins**, **stars**.

**In a level**
* Swipe a piece toward a neighbour (or tap one piece, then a neighbour).
* Match 3+ in a line, or a 2×2 square. Reach every goal before moves run out.

| Match | Creates | Effect |
|-------|---------|--------|
| 4 in a line | Rocket | clears a row or column |
| L or T shape | Bomb | clears a 3×3 area |
| 5 in a line | Rainbow | clears every piece of one color |
| 2×2 square | Butterfly | clears its neighbours, then flies to a crate/weed and clears it |

**Combos:** swap two specials together:
* rocket + rocket: a cross (row and column)
* rocket + bomb: 3 rows and 3 columns
* bomb + bomb: a 5×5 blast
* rainbow + special: every piece of that color becomes that special
* rainbow + rainbow: clears the whole board

**Obstacles:**
* **Weeds** under pieces (match on top to clear them)
* **Crates** (break them with matches next to them, or with specials)

**Boosters:**
* Pre-level: rocket, bomb, rainbow. They start on the board.
* In-level: the **shovel** clears one piece or hits one crate, and doesn't use a move.

**End of level:**
* **Win**: leftover moves turn into rockets (bonus), then you get +1 star and coins.
* **Out of moves**: buy +5 moves with coins, or give up and lose a life.

---

## Project structure

```
scenes/            garden.tscn (home, main scene) and game.tscn (a level)
scripts/
  autoload/        GameState: stars, coins, lives, boosters, tasks, saving
  data/            level_data.gd (levels + generator), garden_data.gd (tasks, story)
  match3/          The puzzle: board_model (rules), board_view (animation + input),
                   tile_view (pieces), board_effect, level_goals
  garden/          garden_screen (home screen), garden_object (restorable objects)
  ui/              game_screen (level HUD/flow), modal (popups), dialog_box
                   (story text), ui_style, icon_view, star_row
tests/             Headless unit tests for the puzzle rules
docs/              Learning guide with concepts and exercises
```

**Suggested reading order:**

1. `scripts/match3/board_model.gd`: all the puzzle rules, no graphics
2. `scripts/match3/board_view.gd`: the turn loop with `await`, animations, input
3. `scripts/ui/game_screen.gd`: goals, moves, winning/losing, boosters
4. `scripts/autoload/game_state.gd`: the 3-currency economy, lives timer, saving
5. `scripts/garden/garden_screen.gd`: the meta game, tasks, dialog
6. `docs/LEARNING_GUIDE.md`: concepts and exercises

For the design and build roadmap, see **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)**.

## Running the unit tests

```bash
godot --headless --import                              # once: builds the class list
godot --headless --script res://tests/test_runner.gd   # exit code 0 = all passed
```

## Exporting

**Editor → Manage Export Templates → Download**, then **Project → Export…**.
Desktop and Web need nothing extra. Android needs the Android SDK + JDK 17.
iOS needs a Mac with Xcode. Guide:
<https://docs.godotengine.org/en/stable/tutorials/export/index.html>

## Status

This code was written without a Godot editor available to run it. If Godot
reports an error when you open or run it, the message gives the file and line,
and it will most likely be a small fix.
