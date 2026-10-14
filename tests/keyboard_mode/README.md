# Keyboard Mode engine-state tests

These tests drive the real game (portable ITGmania) and assert on **engine state**:
`GAMESTATE` current song, `SCREENMAN:get_input_redirected`, player join state, index build
count, the row the wheel is actually *displaying*, whether the engine's own "Press START for
options" prompt ran. They deliberately do not assert on Lua handler return values: for the top
screen the engine ignores them (`ScreenManager::Input` runs `Screen::Input` first, then discards
the callback result), which is why the earlier sequence/escape tests could pass while bugs shipped.

## Run

1. Use a **separate** portable install (copy `Program/`, `Data/`, `Save/`, `Themes/_fallback`;
   junction `Songs/`) and a clone of this theme in `Themes/Simply Love`. Do not run it from the
   install another agent/session is editing.
2. For each scenario:

   ```
   python -I tests/keyboard_mode/run_scenarios.py --root <portable root> --scenario enter --out <evidence dir>
   ```

   | scenario | what it checks |
   |---|---|
   | `enter` | Tab: engine song == highlighted row |
   | `omnibar` | search from another pack in Keyboard Mode: engine follows |
   | `start` | Start runs the engine's `MenuStart` (options prompt, `StartFinalized`), input back with the engine |
   | `omnibar_play` | Omnibar Shift+Enter takes the same engine path |
   | `omnibar_wheel`, `exit_visual`, `jump_group` | the wheel DISPLAYS the engine's song after a cross-pack move |
   | `arbit` | handler outcomes identical in both callback orders |
   | `cats` | A-Z covers every song, BPM tiers partition, favorites, PLAYED |
   | `perf`, `index` | cursor-move cost; one index build across screen entries |
   | `guard` | single-style join guard keeps the master player |
   | `played_fx` | building PLAYED inserts no profile entries |
   | `ctrl_g` | leaderboard redirects input; typing does not open the Omnibar over it |
   | `ctrl_l` | run with `--hide-save-file WindowsKeyboardLayout.lua`: layout cycling never errors |
   | `reload` | full "Reload Songs" with an unchanged count: the index is rebuilt (needs the sandbox metrics note below) |

3. `python -I tests/keyboard_mode/assert_scenarios.py <evidence dir>`

`run_scenarios.py` writes `Save/dev_scenarios.flag`; the theme then loads
`CategoryNavigation/DevScenarios.lua`, which is dev-only and excluded from cabinet deployments
(`tools/deploy_cabinet.py`). No OS-level keyboard or mouse input is ever sent; scenarios call
theme code directly and the runner captures the game window with `PrintWindow`. The runner puts
`ThemePrefs.ini`, `KeyboardLayout.txt` and the recents/history files back when it finishes, and
only reads a `log.txt` whose "Log starting" timestamp is from the process it launched.

## Notes

* The sandbox boots with `TestInitialScreen=ScreenSelectMusic`; the engine's
  `ScreenSelectMusic::Init` then forces versus/P1/master=P1 on every entry, so join-state logic
  is tested by calling the overlay function directly (`guard` scenario).
* `reload` needs `[ScreenReloadSongs] NextScreen="ScreenSelectMusic"` in the **sandbox's**
  `Themes/_fallback/metrics.ini` (production goes through the title menu, which resets game
  state). The scenario clears the engine's own song references first and never dereferences a
  cached Song: it only compares pointers.
* Timings are from a 188-song library. `SONG_INDEX_BUILD` lines in `Logs/log.txt` give the real
  per-library cost; measure on the full library before quoting any figure.
* The `perf` and `index` checks use thresholds appropriate for the 188-song staging library.
