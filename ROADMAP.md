# QuadShoot — Roadmap

Successor to the Milestone 0 phase plan in [FPV-SANDBOX-HANDOFF.md](FPV-SANDBOX-HANDOFF.md) §11. The handoff remains the spec for the flight sandbox; this document owns everything after it. The dream: **an action flight game — dogfights, shooting, explosions — built on a flight model that feels real,** with graphics that eventually earn the gameplay.

## Standing principles

- **The flight model stays the product.** Combat must never compromise the 240 Hz tick or the tuned feel. Perf regressions are bugs.
- Every new tunable follows the `FlightConfig` pattern: a `Resource` with `@export` fields, edited live in the overlay (the row generator in `debug_overlay.gd` is reusable for new config resources).
- Checkpoint protocol continues: every milestone ends with the human playing and judging.
- **Asset policy** (decide before M1 audio/models): procedural/synth placeholders, CC0 packs (e.g. Kenney), or commissioned art later. Third-party assets need explicit human sign-off.

## M1 — First Blood: shooting & explosions ✅ (2026-07-11)

Fly the greybox loop popping targets; it should feel like an action-game trailer moment.

- `fire` InputMap action (right trigger); fixed forward hardpoint on the drone.
- Physical projectiles with visible tracers, pooled — not hitscan; leading targets at speed is the fun.
- FPV reticle; hit markers; score counter.
- Destructible static targets (balloons/panels) in the greybox: pop → explosion (CPUParticles3D, emissive flash, light pulse, debris) → despawn.
- **Audio enters the project**: shots, explosions, motor whine pitched by motor output, wind rush by airspeed. Source per asset policy.
- Perf guard: pooling for projectiles/particles; headless stress scene proving tick stability.

## M2 — Return Fire: they fight back ✅ (2026-07-11; threat direction indicator deferred to M3 polish)

- Player health; damage from hits and hard crashes; death → explosion → respawn at pad.
- Enemy turrets: acquire, lead the shot, volley; destructible with M1's explosion kit.
- Threat feedback: hit flash, damage direction hint, health readout.
- Balance knobs in a `CombatConfig` resource, live-tunable via the overlay machinery.

## M3 — The Hunt: mobile enemies & a combat loop ✅ (2026-07-11)

- Enemy drones with simple aerial state machines (patrol → chase → strafe/orbit); open-air, no navmesh.
- Encounter director: waves, spawn zones, escalation; a bigger arena beyond the greybox.
- Score/combo, kill feed, end-of-run summary. (Damage-direction indicator from M2 landed here.)

## M4 — The Run: roguelike structure ← NEXT

- Sortie/sector structure with exit gates; escalating encounters; death ends the run.
- Between-sortie upgrade drafts — weapons/utility first; flight-model mods only with great care (never break the tuned feel).
- Meta progression + profile persistence; minimal menus (title / run / death).

## M5 — The Look: art direction, then the graphics pass

- **Art-direction spike first**: 2–3 cheap visual prototypes of the same arena corner (e.g. stylized neon sci-fi vs low-poly military); the human picks. Deliberately deferred until combat is proven fun.
- Then: environment set, lighting + post (bloom, tonemapping, fog), drone/enemy models, VFX polish, cohesive palette, audio polish to match.

## M6 — Feel & tech backlog (continuous, opportunistic)

- Flight: propwash, wind, ground effect, turtle mode.
- Real FPV radio (HID) support; VR/OpenXR (both flagged "planned later" in the handoff).
- Settings/remapping UI, quality options.
- Flight replays/ghosts — 240 Hz state recording is cheap, and replays are a killer feature for a flight game.
