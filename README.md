# Fishdom Sample: a match-3 + aquarium game in Godot 4

A small, **heavily commented** learning project that recreates the *gameplay
style* of games like Fishdom: solve match-3 puzzle levels to earn coins, then
spend them on fish and decorations for your own aquarium.

All graphics are drawn in code, so the project contains no image files. Every
script starts with a header comment explaining what it does and which game-dev
concepts it shows.

* **Engine:** [Godot 4.3+](https://godotengine.org/download) (free, open source)
* **Language:** GDScript
* **Platforms:** Android, iOS, Web, Windows, macOS, Linux

> This is an original sample for learning. It uses no names, art or assets
> from Fishdom.

---

## Quick start

1. Download **Godot 4.3 or newer** (standard version, not .NET).
2. Start Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** (or the ▶ button) to run.

The desktop window is a phone-shaped 450×800. Use the mouse like a finger.

### Controls

| Action | How |
|--------|-----|
| Swap pieces | Swipe a piece toward a neighbour, **or** tap a piece then tap a neighbour |
| Fire a special | Swap it with any neighbour |
| Feed fish | Tap the water in the aquarium |

### Rules

* Line up 3+ identical pieces horizontally or vertically.
* **4 in a row** → Rocket (clears its row or column)
* **L or T shape** → Bomb (clears the 3×3 area around it)
* **5 in a row** → Rainbow (swap it with a piece to clear every piece of that color)
* Ice cells crack when you match on top of them.
* Meet all goals before you run out of moves. Unused moves give bonus coins.

---

## Project structure

```
scenes/          Screen scenes (each is a root Control + a script)
scripts/
  autoload/      GameState: coins, progress, saving (global singleton)
  data/          Level definitions and shop catalog (pure data)
  match3/        The puzzle: model (rules), view (visuals + input), effects
  aquarium/      The tank, fish AI, decorations, shop
  ui/            Menus, HUD and shared styling helpers
tests/           Headless unit tests for the puzzle rules
docs/            Learning guide with concepts and exercises
```

**Suggested reading order:**

1. `scripts/match3/board_model.gd`: the rules of match-3 (no graphics)
2. `scripts/match3/board_view.gd`: how the rules are animated and played
3. `scripts/ui/game_screen.gd`: levels, goals, winning and losing
4. `scripts/autoload/game_state.gd`: progress and saving
5. `scripts/aquarium/aquarium_fish.gd`: steering behaviour for fish
6. `docs/LEARNING_GUIDE.md`: concepts and exercises

For the design and build roadmap, see **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)**.

---

## Running the unit tests

```bash
# once: let Godot import the project and build its class list
godot --headless --import
# run the tests (exit code 0 = all passed)
godot --headless --script res://tests/test_runner.gd
```

(`godot` is the Godot executable. On Windows/macOS use its full path.)

---

## Exporting to other platforms

In the editor: **Editor → Manage Export Templates → Download**, then
**Project → Export… → Add…** and pick a platform.

| Platform | What you need |
|----------|---------------|
| Windows / macOS / Linux | Nothing extra. |
| Web | Nothing extra. Serve the exported folder with a web server, e.g. `python -m http.server`. Opening the HTML file directly does not work. |
| Android | Android SDK + OpenJDK 17. Set their paths in *Editor Settings → Export → Android*. A debug keystore is created for you. |
| iOS | A Mac with Xcode and an Apple developer account. Godot exports an Xcode project that you build and sign in Xcode. |

The official guide covers each platform in detail:
<https://docs.godotengine.org/en/stable/tutorials/export/index.html>

---

## Status

This code was written without a Godot editor available to run it. If Godot
reports an error when you open or run the project, it will most likely be a
small typo-level fix. The error message gives the file and line.
