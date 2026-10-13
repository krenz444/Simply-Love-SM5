# Keyboard Mode engine-state tests

These tests drive the real game (portable ITGmania) and assert on **engine state**:
`GAMESTATE` current song, `SCREENMAN:get_input_redirected`, player join state, index build
count. They deliberately do not assert on Lua handler return values: for the top screen the
engine ignores them (`ScreenManager::Input` runs `Screen::Input` first, then discards the
callback result), which is why the earlier sequence/escape tests could pass while bugs shipped.

## Run

1. Use a **separate** portable install (copy `Program/`, `Data/`, `Save/`, `Themes/_fallback`;
   junction `Songs/`) and a clone of this theme in `Themes/Simply Love`. Do not run it from the
   install another agent/session is editing.
2. For each scenario (`enter omnibar start arbit cats perf index guard`):

   ```
   python -I tests/keyboard_mode/run_scenarios.py --root <portable root> --scenario enter --out <evidence dir>
   ```
3. `python -I tests/keyboard_mode/assert_scenarios.py <evidence dir>`

`run_scenarios.py` writes `Save/dev_scenarios.flag`; the theme then loads
`CategoryNavigation/DevScenarios.lua`, which is dev-only and excluded from cabinet deployments
(`tools/deploy_cabinet.py`). No OS-level keyboard or mouse input is ever sent; scenarios call
theme code directly and the runner captures the game window with `PrintWindow`.

## Notes

* The sandbox boots with `TestInitialScreen=ScreenSelectMusic`; the engine's
  `ScreenSelectMusic::Init` then forces versus/P1/master=P1 on every entry, so join-state logic
  is tested by calling the overlay function directly (`guard` scenario).
* Timings are from a 188-song library. `SONG_INDEX_BUILD` lines in `Logs/log.txt` give the real
  per-library cost; measure on the full library before quoting any figure.
* The `perf` and `index` checks use thresholds appropriate for the 188-song staging library.
