# FPV Flight Sandbox — Claude Code Project Handoff

**Milestone 0: a minimal running app with a flyable quadcopter, controlled by gamepad.**

This document is the source of truth for bootstrapping the project. Read it fully before writing any code, then start in plan mode and propose a plan for Phase 0 and Phase 1 before implementing anything.

---

## 1. What this project is

A 3D FPV drone game inspired by (but not cloning) the *feel* of FPV roguelike shooters like Firehawk FPV. The long-term vision includes combat and a roguelike progression loop, but **none of that is in scope now**. Everything depends on one thing: a quadcopter flight model that feels genuinely good to fly. That is this milestone.

Guiding principle: **the flight model is the product.** Every decision in this milestone serves the iterate-and-tune loop between the developer (the human) and the code.

## 2. Milestone 0 — Definition of Done

The milestone is complete when ALL of the following are true:

1. The Godot project opens and runs without errors or warnings in the console.
2. A greybox test environment loads: ground plane, a few obstacles, 3–5 gates to fly through, a spawn pad.
3. A quadcopter can be **armed, flown in acro (rate) mode, and reset** using a standard gamepad (Xbox-style layout).
4. An optional **angle (self-level) mode** can be toggled for accessibility while testing.
5. A debug/tuning overlay can be toggled in-game, showing live telemetry and allowing **live editing of all flight parameters**, with save/load of the config.
6. FPV camera view with configurable uptilt, plus a third-person chase camera toggle for debugging.
7. Stable 60+ FPS on the target machine; physics behaves identically regardless of framerate (fixed tick).

## 3. Tech stack & environment

- **Engine:** Godot 4.x, latest stable (4.4+). Standard build (GDScript), NOT the .NET build. Do not assume version-specific CLI flags or APIs from memory — verify against the docs for the installed version.
- **Language:** GDScript with static typing everywhere (`var x: float`, typed function signatures, typed arrays).
- **Renderer:** Forward+ (Vulkan). Target machine is Windows 11 with an AMD RX 9070 XT — no vendor-specific workarounds expected.
- **Editor workflow:** The human uses VS Code. All scenes (`.tscn`), resources (`.tres`), and `project.godot` are text — you can and should create/edit them directly as text files. Keep them small and diff-readable.
- **Version control:** Git from the first commit. `.gitignore` must exclude `.godot/`. Small, focused commits with clear messages, roughly one commit per coherent step.

## 4. First actions (Phase 0 — bootstrap)

1. Create the Godot project skeleton as text files (`project.godot`, folder structure below).
2. Create a `CLAUDE.md` in the repo root summarizing: the architecture, the conventions in §5, how to run/verify the project, and the checkpoint protocol in §11. Keep it short; link to this handoff for detail.
3. Initialize git, first commit.
4. Configure `project.godot`: Forward+ renderer, **physics tick rate 240 Hz** (`physics/common/physics_ticks_per_second = 240` — a fast tick keeps the rate controller stable and is standard for FPV sims), window 1920×1080 windowed, and the InputMap actions from §7.
5. Create the greybox test scene (§9) and confirm it runs.

**Checkpoint: stop and ask the human to open/run the project before proceeding to Phase 1.**

### Folder structure

```
/project.godot
/CLAUDE.md
/scenes/
    main.tscn              # entry: environment + drone + UI
    environment/greybox.tscn
    drone/drone.tscn
    ui/debug_overlay.tscn
/scripts/
    drone/flight_controller.gd
    drone/motor_model.gd
    drone/input_handler.gd
    ui/debug_overlay.gd
/resources/
    flight_config.gd       # Resource script (class_name FlightConfig)
    default_flight_config.tres
```

Adjust if there's good reason, but explain the reasoning.

## 5. Conventions (also go in CLAUDE.md)

- **No magic numbers in physics or input code.** Every tunable lives in `FlightConfig` (a custom `Resource` with `@export` vars, grouped with `@export_group`). Scripts read from the config; the overlay writes to it live.
- Static typing everywhere; `snake_case`; short focused functions; comments explain *why*, not *what*.
- Composition over inheritance; scenes stay minimal.
- Never hand-edit anything under `.godot/`.
- Do not add third-party addons/plugins or external assets without asking. Greybox visuals only: `BoxMesh`, `PlaneMesh`, `TorusMesh`, flat materials, one checker/grid material for the ground so speed is readable.
- The human wants to understand the reasoning behind non-obvious choices — explain briefly as you go, and flag uncertainty honestly rather than guessing silently.

## 6. Flight model specification

Implemented on a `RigidBody3D` (the drone frame). All values below are **defaults in `FlightConfig`**, not constants.

### 6.1 Airframe

- Mass: `0.65 kg`. Let Godot compute inertia from a reasonable collision shape (flat box ≈ 0.28 × 0.08 × 0.28 m) initially; add manual inertia override to the config later if tuning demands it.
- Quad-X layout, arm length `0.12 m`: motor positions at (±0.12, 0, ±0.12) in body space (front-left/front-right/back-left/back-right). Motors FL/BR spin one direction, FR/BL the other (matters only for yaw reaction torque).

### 6.2 Motors & thrust

- Thrust-to-weight ratio (TWR): `4.5`. Max total thrust = `TWR × mass × g`; per-motor max = total / 4.
- Each motor produces thrust along **body +Y** at its mounting position (`apply_force` with position offset), so differential thrust naturally creates roll/pitch torque.
- **Motor lag:** first-order low-pass on each motor's output, time constant `0.05 s`. This is essential to the feel — instant thrust feels arcade-y.
- **Yaw:** model reaction torque as a torque about body Y proportional to the summed signed motor outputs (CW pairs positive, CCW negative), with a yaw authority coefficient in the config. This is a simplification of prop torque and it's fine — feel over physical purity.

### 6.3 Rate controller (acro mode — the core)

Runs in `_physics_process` at the fixed tick:

1. **Stick → target rates.** Per axis: apply deadzone, then expo (`out = (1-e)·x + e·x³`, expo default `0.3`), then scale by max rate. Defaults: roll `800°/s`, pitch `800°/s`, yaw `550°/s`. (Betaflight-style rc_rate/super_rate curves can come later; keep it max-rate + expo for now.)
2. **PID per axis on angular rate error** (target − actual body angular velocity, in body space). Starting gains (will be tuned live): P `0.004`, I `0.002`, D `0.00003` per axis — treat these as order-of-magnitude starting points, expect the human to retune. D term on measurement (not error) to avoid derivative kick; I term clamped (anti-windup) and reset on disarm.
3. **Mixer (quad-X):** combine throttle + roll + pitch + yaw PID outputs into 4 motor commands with standard X mixing, clamp each to `[idle, 1.0]` while armed. **Air-mode behavior:** idle floor `0.05` so attitude authority is retained at zero throttle.

### 6.4 Angle mode (secondary)

Self-level mode for testing accessibility: stick deflection maps to a target attitude angle (max `55°` roll/pitch), an attitude P loop (`P ≈ 6.0`) converts attitude error to a target rate, which feeds the **same** rate controller. Yaw stays rate-based. Toggled at runtime.

### 6.5 Drag & damping

- Translational: quadratic drag `F = -c·|v|·v` with `c ≈ 0.03` (per-axis-tunable later if needed).
- Small angular damping via the config (not Godot's built-in damping — keep it explicit in our model so it's tunable in the overlay).
- No propwash, ground effect, or wind in this milestone.

### 6.6 Arm / disarm / reset / crash

- Disarmed: motors forced to 0, PID integrators reset. Arming only allowed at low throttle (< 5%).
- Reset: teleport to spawn pad, zero velocities, disarm.
- No damage model yet — colliding is fine, the drone just bounces/tumbles. (A "you're upside down on the floor" situation is what Reset is for.)

## 7. Input specification (gamepad, Mode 2)

InputMap actions defined in `project.godot`:

| Action | Default binding (Xbox layout) |
|---|---|
| `throttle` | Left stick vertical |
| `yaw` | Left stick horizontal |
| `pitch` | Right stick vertical |
| `roll` | Right stick horizontal |
| `arm_toggle` | A |
| `reset_drone` | B |
| `flight_mode_toggle` | Y |
| `camera_toggle` | X |
| `overlay_toggle` | Start |

- Deadzone `0.08` on all axes, applied before expo.
- **Throttle on a self-centering stick** needs special handling. Implement two selectable curves in the config:
  - `raw`: stick `[-1, 1]` → throttle `[0, 1]` linearly.
  - `hover_centered` (default): mid-stick maps to the computed hover throttle (`mass·g / max_total_thrust`), with a smooth monotonic curve to 0 and 1 at the extremes. This makes a springy gamepad stick livable.
- Keyboard fallback (WASD-ish + space) is nice-to-have, low priority — gamepad is the target device.

## 8. Debug & tuning overlay

A toggleable `CanvasLayer` UI. Function over beauty.

**Telemetry (always visible when open):** FPS + physics tick, armed state, flight mode, altitude, speed (m/s and km/h), per-axis target vs. actual rates (small live plots if cheap, numbers otherwise), 4 motor output bars.

**Tuning panel:** controls bound live to every `FlightConfig` field — PID gains, max rates, expo, TWR, motor lag, drag, throttle curve type, camera uptilt/FOV. Plus: Save (to `user://flight_config.tres`), Load, Reset-to-defaults. Config auto-loads on startup if a saved one exists.

Mouse interacts with the overlay while gamepad keeps flying the drone — tuning mid-hover is the whole point.

## 9. Test environment (greybox)

- 200 × 200 m ground plane with a grid/checker material (speed perception needs texture).
- A spawn pad, 8–12 boxes of varying sizes to weave around, 3–5 gates (torus or box-frame) at varying heights forming a rough loop.
- One `DirectionalLight3D` + `WorldEnvironment` with plain sky. No fancy lighting.

## 10. Camera

- **FPV camera:** child of the drone frame, configurable uptilt (default `25°`), FOV default `115°`. This is the primary view.
- **Chase camera:** smoothed third-person follow, for debugging physics visually. Toggle with `camera_toggle`.

## 11. Phased plan & checkpoint protocol

Work in phases. **At each checkpoint, stop, summarize what changed and why, and wait for the human to fly/test and give feedback before continuing.** Flight feel cannot be evaluated by the agent — the human's hands are the test suite.

- **Phase 0 — Bootstrap.** §4. Checkpoint: project runs, empty greybox renders.
- **Phase 1 — It flies (crudely).** Rigid body + motors + thrust + gravity + motor lag. Temporary keyboard input: arm + raw collective throttle only. Checkpoint: drone lifts off, hovers roughly, falls believably.
- **Phase 2 — It flies (properly).** Gamepad input pipeline, rate controller, mixer, air-mode idle, arm/disarm/reset, FPV camera. Checkpoint: the human flies acro and gives feel feedback. Expect iteration here.
- **Phase 3 — It tunes.** Debug overlay with live tuning + persistence, angle mode, chase camera, hover-centered throttle curve. Checkpoint: a full tuning session; milestone review against §2.

## 12. Verification (agent-side)

- After edits, verify scripts parse and the project imports cleanly by running Godot headless from the CLI (check the installed version's docs for the exact flags — e.g. a headless import/quit run — rather than assuming).
- Watch the console output when launching scenes; treat warnings as errors to be fixed or explicitly justified.
- Physics correctness sanity checks that CAN be automated are welcome (e.g., a headless test that hover throttle ≈ `mass·g / max_thrust` holds altitude within tolerance) — but keep them lightweight, don't build a test framework.

## 13. Explicitly OUT of scope for Milestone 0

Weapons, enemies, damage, roguelike loop, base/meta progression, sound, VR/OpenXR, real FPV radio (HID) support, multiplayer, menus/settings screens, art assets, propwash/wind. Do not scaffold ahead for these. Some (VR, real radio input) are planned later — clean architecture is enough preparation; speculative abstraction is not.

## 14. Tuning protocol (human ↔ agent loop)

When feel feedback arrives (e.g., "it oscillates on roll", "yaw feels mushy", "throttle is twitchy"), map it to the model deliberately: oscillation → P too high or D too low on that axis; slow drift correction → I; mushy/laggy response → motor lag too high or P too low; twitchy sticks → expo/deadzone/max-rate; floaty → drag or TWR. Propose specific config changes with reasoning, let the human apply them live in the overlay, and only bake new defaults into `default_flight_config.tres` when the human says the feel is right.
