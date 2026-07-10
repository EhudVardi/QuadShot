# QuadShoot — FPV Flight Sandbox

3D FPV drone flight sandbox in Godot. **The flight model is the product** — everything serves the human-in-the-loop tuning cycle. Full spec: [FPV-SANDBOX-HANDOFF.md](FPV-SANDBOX-HANDOFF.md) (source of truth, read it before big changes).

## Running & verifying

- Godot 4.7 stable (standard/GDScript build, portable): `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe` (use the `_console` exe from CLI so output is visible).
- Run the game: `<exe> --path .`
- Headless verify after edits (treat warnings as errors):
  - Re-import: `<exe> --headless --import --path .`
  - Boot check: `<exe> --headless --quit-after 10 --path .`
  - Script parse check: `<exe> --headless --check-only -s <script.gd> --path .`

## Architecture

- `scenes/` — `main.tscn` (entry: environment + drone + UI), `environment/greybox.tscn`, `drone/drone.tscn`, `ui/debug_overlay.tscn`
- `scripts/` — `drone/` (flight_controller, motor_model, input_handler), `ui/`
- `resources/` — `flight_config.gd` (`class_name FlightConfig`), `default_flight_config.tres`, shared shaders/materials
- Physics tick is **240 Hz** (rate-controller stability); all flight code runs on the fixed tick.
- **Pilot axis convention** for all Vector3 rate/gain fields: x = roll (+right), y = pitch (+nose up), z = yaw (+right). Drone front is body **-Z**. Conversion from Godot space happens only in `FlightController._measured_rates()`.

## Conventions

- **No magic numbers in physics/input code** — every tunable is an `@export` in `FlightConfig`; scripts read it, the debug overlay writes it live.
- Static typing everywhere; `snake_case`; short focused functions; comments explain *why*, not *what*.
- Composition over inheritance; scenes minimal; `.tscn`/`.tres`/`project.godot` are hand-edited text — keep them small and diff-readable.
- Never touch `.godot/`. No third-party addons or external assets without asking — greybox primitives and flat/procedural materials only.
- Explain non-obvious reasoning briefly; flag uncertainty instead of guessing silently.

## Checkpoint protocol

Work is phased (handoff §11). **At each phase checkpoint: stop, summarize what changed and why, and wait for the human to run/fly it.** Flight feel cannot be evaluated by the agent — the human's hands are the test suite. Map feel feedback to config changes per handoff §14.
