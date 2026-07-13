# QuadShot — FPV Flight Sandbox

3D FPV drone flight sandbox in Godot, growing into an action flight game. (Game title: **QuadShot** — one o; the repo folder keeps its historical `QuadShoot` spelling.) **The flight model is the product** — everything serves the human-in-the-loop tuning cycle. Milestone 0 spec: [FPV-SANDBOX-HANDOFF.md](FPV-SANDBOX-HANDOFF.md); everything after: [ROADMAP.md](ROADMAP.md) (read the relevant one before big changes).

## Running & verifying

- Godot 4.7 stable (standard/GDScript build, portable): `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe` (use the `_console` exe from CLI so output is visible).
- Run the game: `<exe> --path .`
- Run the **dev room** testbed: `<exe> --path . scenes/dev_map.tscn` — a big sandbox map that mirrors main's wiring and gets a specimen of every game element as they're added (shooting range, city block, slalom, tunnel, platforms, crash wall). It also carries the **look pass** (post/atmosphere): a `LookController` (`scripts/environment/look_controller.gd`) applies `LookConfig` (`resources/look_config.gd`, AgX tonemap + glow/SSAO/fog/color-grade/sun) onto its Environment every frame, live-tuned via the overlay's LOOK section. Main/greybox stays vanilla (its overlay leaves `look_config` null, so the LOOK section is skipped) until the look is proven and rolled in.
- Headless verify after edits (treat warnings as errors):
  - Re-import: `<exe> --headless --import --path .`
  - Boot check: `<exe> --headless --quit-after 10 --path .`
  - Script parse check: `<exe> --headless --check-only -s <script.gd> --path .`

## Architecture

- `scenes/` — `main.tscn` (entry: environment + drone + combat + UI), `dev_map.tscn` (dev-room testbed, same wiring), `environment/` (greybox, dev_room), `drone/drone.tscn`, `combat/` (projectile, explosion, target, turret), `ui/` (debug_overlay, hud, draft_screen)
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

- Gamepad (Mode 2): left stick throttle/yaw, right stick pitch/roll. **A** arm (throttle at zero-thrust position), **B** reset, **Y** acro/angle mode, **X** FPV/chase camera, **RT** fire blaster, **LT** fire missile (requires lock: hold an enemy near the reticle until the diamond turns red), **Start** debug overlay.
- Headless test suite under `scripts/tests/`: `hover_check.gd`, `combat_check.gd`, `wave_check.gd`, `missile_check.gd`, `run_check.gd` — run all after flight/combat changes.
- Rate-loop wobble is fought with the FlightConfig **Filtering** group (gyro LPF, D-term LPF, RC smoothing — Betaflight-style), never by changing the physics.
- Rate feel is a `rate_preset` dropdown at the top of the overlay's FLIGHT section (`FlightPresets`, `scripts/drone/flight_presets.gd`): Default/Cinematic/Freestyle/Race, each an atomic snapshot of rate_p/i/d/ff + angular_damping. Hand-tuning any of those five fields falls through to "Custom" — detected live by comparing the config against every preset, not tracked as separate state. Bench-tune new presets with `scripts/tests/rate_tune_sweep.gd` and `step_response.gd` before adding them.
- Run flow (M4): arming starts a run of sorties (`sortie_waves` waves each); clearing a sortie opens the exit gate, and flying it triggers a paused upgrade draft applied to the run-scoped `RunMods` static layer (never to the configs). Death ends the run, records `user://profile.json`, shows the summary; the next arm starts fresh (`RunMods.reset()`). Score is run-scoped with a combo multiplier.
- Overlay: mouse tunes every `FlightConfig` field live while the gamepad flies. Save/Load persists to `user://flight_config.tres` (auto-loaded on startup); Defaults re-reads `default_flight_config.tres`. New defaults get baked into that `.tres` only when the human says the feel is right (handoff §14).

## Checkpoint protocol

Work is phased (handoff §11). **At each phase checkpoint: stop, summarize what changed and why, and wait for the human to run/fly it.** Flight feel cannot be evaluated by the agent — the human's hands are the test suite. Map feel feedback to config changes per handoff §14.
