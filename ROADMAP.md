# QuadShot — Roadmap

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
- Post-checkpoint additions: Betaflight-style rate-loop filtering (feel), missile lock-on vs enemy drones, volume controls.

## M4 — The Run: roguelike structure ✅ (2026-07-11)

- Sortie structure: `sortie_waves` waves each, extra hostiles per sortie; clearing the last wave opens a fly-through exit gate; death ends the run.
- Between-sortie upgrade drafts (paused three-pick): weapons/utility only, applied to a run-scoped `RunMods` layer so no upgrade ever mutates the human-tuned configs.
- Meta progression: `user://profile.json` (runs, kills, best score/sorties); title overlay + bests in the death summary stand in for menus.

## M5 — The Look: art direction, then the graphics pass (look-lite pass ✅ 2026-07-14; full pass later)

- **Look-lite pass shipped game-wide (2026-07-14)**: AgX tonemap + glow/SSAO/fog/color-grade (live-tunable `LookConfig` + `LookController`), neon-grid ground, emissive role palette on combat objects, panel-seam structure shader. Zero external assets. Good enough for the near future.
- **Remaining for the full M5 (later)**: art-direction spike (2–3 visual prototypes, human picks), environment set, drone/enemy models, VFX polish, audio polish to match. Replays (M7) become interesting again after this second graphics upgrade.

## M6 — The War: living-theater campaign ← NEXT (design phase)

The gameplay model that makes the game unique: a procedurally generated, persistent, turn-based **living theater** — a war that develops as the player fights it. Falcon 4.0's dynamic campaign spirit on a roguelike node-map, on top of the sim-grade flight model.

- **Designed in [GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md)** — the living design doc + decision log (append-only history; read it before touching anything gameplay-related). Forks decided 2026-07-15: pilot-lives economy (F1), turn-based war ticks (F2), kinetic-first influence (F3), persistent portable-file saves with a deterministic serializable war-sim (F4).
- Pillars: Living Theater (nodes + war ticks + weather modifiers) · Sortie composition from war state · Frames/hardpoints/loadouts · Enemy counter-web bestiary · Reward economy & influence.
- Balance rigor: stat configs as `TunableConfig` resources, counter-matrix designed on paper first, headless combat-sim harness sweeping matchups before anything is flown.
- Build order: design iterations (P1 → P4 → P3 → P5 → P2 → harness), then the smallest vertical slice that delivers the feeling (~5 nodes, 2 frames, 3 weapons, 4 enemies).

## M7 — Feel & tech backlog (continuous, opportunistic; regrouped 2026-07-15)

- **Input** *(pulled forward — the one "do now")*: real FPV radio HID support targeting the **RadioMaster TX16S**, with a flexible input-binding layer designed to extend as the game grows (this covers most of "remapping"). Overlay QoL: collapsible config groups.
- **Weather** *(absorbed into M6/P1 as battlefield modifiers)*: dynamic wind, rain, hail, fog, heat wave, sandstorm — design lives in GAMEPLAY-DESIGN.md.
- **Physics** *(deferred, revisit later)*: propwash, ground effect, turtle mode (not needed near-term — 3D mode already recovers inverted).
- **Replays/ghosts** *(sits as-is)*: blackbox already records 240 Hz state and has proven itself as a debug channel; the player-facing feature waits for the full M5 graphics pass + a cinematic camera director (random static cameras would kill it).
- **Audio sweep** *(near-term, high-ROI)*: richer motor synthesis (harmonic stack + blade-pass tone driven by the motor model's live outputs), doppler on projectiles/missiles, low-health/lock/draft UI audio. engine-sim evaluated and declined (ICE physics, GPL, no clean embedding) — physics-driven synthesis stays the approach.
- **Diegetic menu system** *(back burner, from design doc v1.5)*: menus rendered in-engine as buildings viewed side-on — menu tree flattened left-to-right, floors = items — with an AI-run war-sim battlefield playing behind the title screen (F4.a synergy).
- **Settings/quality options** *(pre-release)*: graphics scaling for weaker GPUs (shadow resolution, glow toggle, resolution scale, LOD).
- **Commander mode** *(future gameplay branch, from F3)*: macro agency over allied AI, entering as an acquirable in-playthrough capability.
- **Multiplayer** *(pinned far-future, from F4.b)*: players joining a running battlefield to help; the deterministic war-sim keeps the door open.
- **VR/OpenXR** *(parked)*: acro + VR is nausea-inducing; skip for now.
