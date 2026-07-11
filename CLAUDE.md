# QuadShot — FPV Flight Sandbox

3D FPV drone flight sandbox in Godot, growing into an action flight game. (Game title: **QuadShot** — one o; the repo folder keeps its historical `QuadShoot` spelling.) **The flight model is the product** — everything serves the human-in-the-loop tuning cycle. Milestone 0 spec: [FPV-SANDBOX-HANDOFF.md](FPV-SANDBOX-HANDOFF.md); everything after: [ROADMAP.md](ROADMAP.md) (read the relevant one before big changes).

## Running & verifying

- Godot 4.7 stable (standard/GDScript build, portable): `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe` (use the `_console` exe from CLI so output is visible).
- Run the game: `<exe> --path .`
- Headless verify after edits (treat warnings as errors):
  - Re-import: `<exe> --headless --import --path .`
  - Boot check: `<exe> --headless --quit-after 10 --path .`
  - Script parse check: `<exe> --headless --check-only -s <script.gd> --path .`

## Architecture

- `scenes/` — `main.tscn` (entry: environment + drone + combat + UI), `environment/greybox.tscn`, `drone/drone.tscn`, `combat/` (projectile, explosion, target, turret), `ui/` (debug_overlay, hud)
- `scripts/` — `drone/` (flight_controller, motor_model, input_handler, rate_controller), `combat/` (weapon, projectile+pool, health, turret, target, enemy_drone, wave_director, effects), `audio/` (sound_bank — synthesized, no external assets; motor/wind emitters), `ui/`, `tests/` (headless checks: hover, combat, wave)
- `resources/` — `tunable_config.gd` base + `flight_config.gd`/`combat_config.gd` and their `default_*.tres` (shared instances: every exporter of the same `.tres` sees live edits), shared shaders/materials
- Combat wiring: projectiles call `take_hit(damage)` on whatever they hit unless it shares the shooter's `team`; entities award score via a `destroyed(points)` signal that `main.gd` tallies; `SoundBank` is a scene node with a null-safe **static** API (not an autoload — autoloads don't exist under `--script` test runs).
- Physics tick is **240 Hz** (rate-controller stability); all flight code runs on the fixed tick.
- **Pilot axis convention** for all Vector3 rate/gain fields: x = roll (+right), y = pitch (+nose up), z = yaw (+right). Drone front is body **-Z**. Conversion from Godot space happens only in `FlightController._measured_rates()`.

## Conventions

- **No magic numbers in physics/input code** — every tunable is an `@export` in `FlightConfig`; scripts read it, the debug overlay writes it live.
- Static typing everywhere; `snake_case`; short focused functions; comments explain *why*, not *what*.
- Composition over inheritance; scenes minimal; `.tscn`/`.tres`/`project.godot` are hand-edited text — keep them small and diff-readable.
- Hand-written `.tscn` gotcha: exported Node properties need `node_paths=PackedStringArray("prop")` on the `[node]` line **and** `prop = NodePath("...")` in its body, or the reference silently loads as Nil.
- Never touch `.godot/`. No third-party addons or external assets without asking — greybox primitives and flat/procedural materials only.
- Explain non-obvious reasoning briefly; flag uncertainty instead of guessing silently.

## Controls & tuning

- Gamepad (Mode 2): left stick throttle/yaw, right stick pitch/roll. **A** arm (throttle at zero-thrust position), **B** reset, **Y** acro/angle mode, **X** FPV/chase camera, **RT** fire, **Start** debug overlay.
- Headless test suite under `scripts/tests/`: `hover_check.gd`, `combat_check.gd`, `wave_check.gd` — run all after flight/combat changes.
- Run flow (M3): arming starts a run (WaveDirector spawns escalating enemy waves); death ends it, shows the summary, and the next arm starts fresh. Score is run-scoped with a combo multiplier.
- Overlay: mouse tunes every `FlightConfig` field live while the gamepad flies. Save/Load persists to `user://flight_config.tres` (auto-loaded on startup); Defaults re-reads `default_flight_config.tres`. New defaults get baked into that `.tres` only when the human says the feel is right (handoff §14).

## Checkpoint protocol

Work is phased (handoff §11). **At each phase checkpoint: stop, summarize what changed and why, and wait for the human to run/fly it.** Flight feel cannot be evaluated by the agent — the human's hands are the test suite. Map feel feedback to config changes per handoff §14.
