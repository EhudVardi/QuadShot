# QuadShot — Codebase Analysis & Handoff Report

**Date:** 2026-07-21 · **Analyzed at commit:** `6b2c25b` (design-doc v1.25; Phase 3 + Phase 3.5 shipped, heading into Phase 4)
**Prepared for:** the QuadShot development agent (another Claude), to accelerate the M6 vertical-slice build.
**Prepared by:** a deep read-only analysis over the entire source tree (all docs + ~7,300 lines of GDScript + scenes/resources), synthesized from focused sub-analyses of each subsystem.

> **How to use this document.** §1–4 orient you (state, the rules you must not break, architecture, and the built-vs-designed gap). §5 is the findings ledger — bugs/risks with `file:line` and *why it matters*, with a "recently resolved" subsection so you don't re-fix landed work. §6–9 are forward-looking: slice sequencing, test debt, quick wins, and — importantly — **what is already right and must not be "fixed."** Read §2 and §9 before you touch anything.

> **Two caveats.** (1) An earlier draft of this report was written against commit `6ee184b`; this version is re-synced to `6b2c25b` (18 newer commits: the bestiary + the Phase 3.5 balance instrument). Several earlier findings are now **resolved** — see §5.0. (2) Godot is not installed on the machine this ran on (the documented `C:\Tools\Godot\…` path is absent here), so **nothing was verified by running the engine or the suites.** Everything is from static reading. Your first action should be to run the headless checks and `tools/balance_report` to establish a real green baseline. Line numbers are as of `6b2c25b`.

---

## 1. Where the project is right now

QuadShot is far past its "M0 flight sandbox" origins.

- **The flight model (the product) is mature and excellent.** 240 Hz rate loop, Betaflight-style filtering (gyro/D-term/FF LPFs, I-term relax, crash-condition gating), exact tick-rate-independent discretization, hover-centered/3D throttle curves, acro + angle + autopilot modes, gamepad + USB-radio input, a per-tick CSV blackbox. Clean, well-commented (comments say *why*). This is the crown jewel — see §9.
- **Combat, roguelike run structure, look-pass, pause/slow-mo, and a wounded-quad damage model all ship.** Blaster + missile with an honest ballistic FCS reticle, pooled projectiles, turrets, mobile enemy drones, waves/sorties/upgrade-drafts, exit/repair gates, motor-degradation damage, synthesized audio.
- **The M6 "living theater" campaign is fully *designed* (paper phase complete) and the vertical slice is *mid-build*.** `GAMEPLAY-DESIGN.md` (now 3,931 lines, append-only) holds seven steered iterations (P1 theater, P4 bestiary, P3 arsenal, P5 economy, P2 mission composition, the balance harness, the damage model). Build state as of v1.25:
  - **Phase 3 (bestiary) shipped:** the slice-four enemies are all real — Raider + Turret (canonized) + **Gnat** (boids swarm) + **Aegis** (shielded ticking-bomb). The `EnemyConfig` migration is complete; the durability/shield model is implemented in `Health`.
  - **Phase 3.5 (the balance instrument) shipped:** a layered balance CI — Layer 1 lethality (config arithmetic, verified against the real `Health`), Layer 2 delivery (aim × evasion benched in isolation), and a prediction-vs-validation duel harness, with `BALANCE.md`, a `PILOT_VERSION` pin, `tools/balance_report`, and a non-headless **watch mode**.
  - **Next: Phase 4** — the flak pod (3rd weapon column, the Gnat answer) + Atlas (2nd frame), then the H.q4 hands-on difficulty calibration once the slice is flyable end-to-end.

**The single most important context for you:** the *design* describes a huge strategic game; the *code* is still a single hand-built greybox arena (`main.tscn`) + a headless war-sim that has **no connection to the flyable game yet**, and a headless balance harness. Almost all of P1/P2/P3/P5 is designed-not-built. That gap is the roadmap (§4, §6).

---

## 2. The rules you must not break (load-bearing conventions)

1. **Flight feel is the human's to judge — never claim it.** Physics/feel changes stop at a checkpoint: summarize what changed and why, then wait for the human to fly it (handoff §11/§14; the feel→config mapping table is in handoff §14).
2. **No magic numbers in physics/input code.** Every flight/input tunable is an `@export` on a config; scripts read it, the overlay writes it live. (Combat and war-sim violate this in spirit — §5 — but don't add new ones.)
3. **Determinism is the M6 thesis.** The `war/` modules are seed-driven and serializable *on purpose* (F4 portable save). Preserve it religiously. **Do not introduce `randomize()`, wall-clock `Time`, or Dictionary-iteration-order dependence into anything that must be deterministic.** Note the two determinism *contracts*: the war-sim is **bit-exact** (`var_to_str` round-trip = the save); the matchup harness is deliberately **AI-level, not bit-exact** (float variance across processes can flip a knife-edge rep — read aggregate movement, not single reps). Don't conflate them.
4. **Physics runs at 240 Hz on the fixed tick.** All flight code lives in `_physics_process`. Perf regressions that threaten the tick are bugs. (One current violator: `repair_gate.gd` uses `_process` — §5.)
5. **Pilot axis convention** everywhere outside `FlightController._measured_rates()`: `x=roll(+right)`, `y=pitch(+nose up)`, `z=yaw(+right)`; front is body **-Z**.
6. **Hand-edited `.tscn` gotcha:** exported Node properties need **both** `node_paths=PackedStringArray("prop")` on the `[node]` line **and** `prop = NodePath("...")` in the body, or the reference silently loads as Nil. (Applied correctly today.)
7. **Configs are the human-calibrated baseline; upgrades never mutate them** (`RunMods` static layer). New defaults get baked into `default_*.tres` only when the human says the feel is right.
8. **The balance instrument has its own contract — read `BALANCE.md` before acting on its output.** It is CI for the *player's* fights, **not a war oracle**. A predicted-vs-validated gap is the instrument's *output* (it names an un-modeled factor), not a number to tune away. **`PILOT_VERSION` (in `reference_pilot.gd`) pins the measuring brain — bump it on ANY pilot behavior change, then re-measure deliberately.** Numbers from different pilot versions never share a table.
9. **Never touch `.godot/`; no third-party addons/assets without asking.** Append-only design doc (superseded entries are marked, not deleted).

**Headless verification (run after every edit; treat warnings as errors):**
```
<exe> --headless --import --path .
<exe> --headless --quit-after 10 --path .
<exe> --headless --check-only -s <script.gd> --path .
```
Correctness checks live in `scripts/tests/`; the balance instrument runs via `tools/balance_report` (§7 — note the test story is now *two* fragmented pieces).

---

## 3. Architecture map

**Entry & orchestration** — `scenes/main.tscn` → `scripts/main.gd` (Node3D root). **This is the only flyable scene** — a hardcoded greybox arena. `dev_map.tscn` mirrors it as a bigger testbed and additionally hosts Gnat/Aegis specimens. `main.gd` (now 328 lines, down from 405 after the reticle extraction) orchestrates camera, pause/slow-mo, run/score/combo, HUD markers, player damage→motor→video-glitch feedback, death/respawn.

**Flight (`scripts/drone/`)** — `flight_controller.gd` (RigidBody3D loop) → `rate_controller.gd` (PID+filters) + `motor_model.gd` (mixer, motor lag, per-motor health) + `input_handler.gd` + `flight_presets.gd` + `blackbox.gd`. Reads `FlightConfig` + optional `DamageConfig`.

**Combat (`scripts/combat/`)** — player `weapon.gd`/`missile_system.gd` (under `Drone/FpvCamera`); `projectile(+pool)`, `missile`, `turret`, `enemy_drone` (Raider), **`gnat.gd`/`gnat_swarm.gd`** (swarm), **`aegis.gd`/`shield_shell.gd`** (shielded bomber), `wave_director`, `health.gd` (shared HP + **shield threshold-gate**), `target`, `effects`/`explosion`, `run_mods`/`upgrades`, `exit_gate`/`repair_gate`. Team routing: projectiles call `take_hit()` unless collider shares the shooter's `team`; entities emit `destroyed(points)` tallied by `main.gd`.

**War-sim (`scripts/war/`) — the M6 core** — `theater_generator.gd` (seeded hex theater → serializable state Dict) + `war_sim.gd` (deterministic tick engine). `var_to_str` round-trips the state = the portable save. Benches: `war_soak.gd`, `war_trace.gd`.

**Balance instrument (`scripts/balance/` + `scripts/tests/` + `tools/`) — NEW** — `lethality.gd` (Layer 1 config arithmetic + state-split + combos) + `prediction.gd` (join) + `delivery_bench.gd` (Layer 2 aim/evasion) + `lethality_check.gd` (verifies replay vs shipped `Health`) + `matchup_harness.gd` (validation duels + watch mode) + `reference_pilot.gd` (the scripted proxy) + `bench_view.gd` (shared watch-mode helper) + `reticle_solver.gd` (shared FCS geometry). Data artifact: `balance/delivery_factors.json`. Primer: `BALANCE.md`. Runner: `tools/balance_report.cmd` (+ `watch_matchups.cmd`, `watch_delivery.cmd`).

**Config infra (`resources/`)** — `tunable_config.gd` base (reflective `copy_from`/save/load) subclassed by `flight/combat/enemy/damage/war/look/weather/audio_config` + `input_bindings`. Shared `.tres` instances propagate overlay edits live.

**UI (`scripts/ui/`)** — `debug_overlay.gd` (spec-table-driven rows), `hud.gd`, `draft_screen.gd`, `crosshair.gd`. The overlay also owns runtime input-binding setup (§5).

---

## 4. Built vs. designed — the gap that is the roadmap

| Pillar / system | Designed | Built in code | Gap |
|---|---|---|---|
| **Flight model** | — | ✅ Mature | Polish only |
| **P1 Living Theater** | Full (P1.1–P1.9) | war-sim skeleton runs **headless only** | No command-room scene, no map render, no campaign save↔game wiring |
| **P2 Mission composition** | Full; `compose(seed,node,war,tier)→sortie_spec` | ❌ Nothing; `wave_director` is the one shipped archetype | The composer doesn't exist; sorties are hand-placed |
| **P3 Frames/hardpoints/arsenal** | Full; 4 frames, 5 weapons, E-bay | ❌ One hardcoded blaster + missile on `CombatConfig` | No frame/loadout/hardpoint/weapon resource seam |
| **P4 Bestiary + counter-matrix** | Full; 12 archetypes | **Slice-four all built** (Raider/Turret/Gnat/Aegis); durability model live; mini-web banded vs P4.3 | Gnat/Aegis exist as **specimens + harness rows only — not in the live wave loop** (see §5). Flak-answer weapon is Phase 4 |
| **P5 Economy & influence** | Full; salvage/influence/pilots | ❌ M4 `RunMods` + score only | No campaign currencies, depot, or pilots-as-lives in gameplay |
| **Damage model (Iter 7)** | Full (D1–D9) | ✅ Motors + video breakup (player-only) | Props/frame/battery/FCS surfaces + enemy symmetry deferred |
| **Balance harness (Iter 6)** | Full (H1–H9) | ✅ **Unit layer shipped** (lethality + delivery + prediction/validation + state-split + watch mode) | Sortie & economy harness layers unbuilt; reference-pilot competence datum low + a known no-standoff defect (§5) |
| **Weather / biomes** | Designed | Tags generated in war-sim; `WeatherConfig` inert stub | Only `&"fog"` has any sim effect; biomes unused (+ a bug, §5) |

The war-sim's `_proxy_sortie` is a **skill-parameterized coin flip** — the seam where a *real flown sortie outcome* feeds back into the war tick (via `strength_cost` as the exchange rate) is the central integration challenge (§6). **Design doctrine to internalize (v1.23):** *the war never fights kinetically* — unattended battles resolve by strength arithmetic; kinetic combat exists only in the player's own sorties (the sortie IS the deaggregation bubble). "The war shapes your fights; your fights dent the war."

---

## 5. Findings ledger

Severity: **BUG** (wrong today) · **RISK** (latent/conditional, or blocks M6) · **SMELL** (debt) · **GAP** (missing seam/coverage). `file:line` at `6b2c25b`.

### 5.0 · Recently resolved (since the `6ee184b` baseline — do NOT re-open)

- **✅ Durability is now real.** `Health` (`health.gd`) implements the P4.3 shield **threshold-gate** (under-threshold hits splash off entirely, a breaking hit carries excess to hull, regen after a quiet spell) with `struck`/`shield_absorbed`/`shield_broken` signals and `configure_shield()`. The Aegis uses it; `lethality_check.gd` verifies the replay against it. (`EnemyConfig.armor` is still applied nowhere — but this is now *documented* as a "known-inert field" in `BALANCE.md`, not a silent gap.)
- **✅ Reticle/FCS geometry extracted** to a shared `ReticleSolver` (`reticle_solver.gd`), used by `main.gd` — the "reticle never lies" guarantee is now one implementation by construction, and `main.gd` shrank ~80 lines. (Caveat: the *harness* watch-mode HUD that was meant to reuse it is not actually wired yet — see BUG-H1.)
- **✅ The reference-pilot gun-run was reframed and largely fixed** (four real bugs: 44°-tilt throttle compensation — it had been *sinking out of the world* every duel; LOS-rate feed-forward; a ground guard; the trigger). The remaining Blaster×Raider "0%" is now correctly attributed to the *bot's aim datum* (0.14 hit-rate on a static target), not the weapon — the layered model predicts `++` from config + isolated benches, matching the human's hand-band.
- **✅ Blackbox filenames** are now sortable `flight_YYYYMMDD_HHMMSS.csv` (was ms-since-engine-start).
- **✅ Missile LOS multi-part fix** (`missile_system.gd:131-140`): lock now accepts the target's own child colliders (`is_ancestor_of`), so the Aegis's shield shell no longer blocks its own lock. **Note for you: every future multi-part enemy needs this.**

### 🔴 Highest priority (block or bite the slice)

- **RISK-1 · The in-mission layer is non-deterministic — contradicts the M6 harness/replay thesis.** The `war/` modules are seeded; gameplay RNG/time are not:
  - `wave_director.gd:40` `_rng.randomize()`; `_spawn_enemy` leaves `ai_seed=-1`, so live enemies (`enemy_drone.gd:42`, and `gnat_swarm.gd:46`) randomize positions/orbit/wander/jitter. WaveDirector has no seed field.
  - `upgrades.gd:50` `pool.shuffle()` on the un-seeded global RNG — drafts non-reproducible.
  - `main.gd:197` combo timing keys off wall-clock `Time.get_ticks_msec()` (also unaffected by `Engine.time_scale`, so it misbehaves under slow-mo).
  - The harness seeds its own combatants (`ai_seed`), so this doesn't block Phase 4 — but the **composed-sortie harness (P2.11) and any replay need a run/encounter seed threaded WaveDirector → enemy `ai_seed`**, plus seeded `shuffle`/tick-based combo. The "difficulty is measured, not authored" (H6) claim depends on it. Build this seam before the composer.
- **GAP-A (new) · Gnat and Aegis are built but not in the live game loop.** They're placed in `dev_map.tscn` (specimens; Aegis `loop_route=true` for shield practice) and added to the overlay BESTIARY, but `main.tscn` doesn't spawn them and `wave_director.gd:15` still instantiates only `enemy_drone.tscn` (Raider). So the swarm and the ticking-bomb mechanics exist, are tunable, and are benched — but the actual sortie/scoring loop only fights Raiders + placed Turrets. **Wiring the slice-four into waves/sorties (and the Aegis `detonated`→"player failed the intercept" outcome into scoring) is unbuilt.**
- **BUG-2 · `theater_generator.gd:160-165` — 2 of 7 biomes unreachable.** `_nearest_biome` uses the seed index (0–4, since `_pick_biome_seeds` picks `mini(5,…)`) directly as `BIOMES[best % 7]`, so `&"coastal"`(5)/`&"canyon"`(6) can never be assigned. Latent today (biomes inert), a real bug once P1.9/P2 consume biomes.
- **BUG-3 · `war_sim.gd:207-226` — the HQ decapitation gate is bypassable.** `_proxy_sortie` forbids hitting the HQ until `command_alive <= hq_unlock_command_posts` (`:91,110-112`), but `_allied_offensive` picks any adjacent enemy node incl. the HQ with no gate, and `_resolve_attack` sets `winner="player"` on HQ capture (`:225-226`). Once sorties grind the HQ garrison down, a stacked neighbor takes it with the command network intact — contradicting the "campaigns stall with an intact enemy brain" doctrine. Gate both win paths.

### 🟠 Determinism / serialization integrity (war-sim files unchanged since baseline — all still stand)

- **RISK-2 · "Bit-exact round-trip" rests entirely on the `snappedf(…,0.001)` garrison quantization, and nothing enforces it for new fields.** `war_sim.gd:40-41` re-quantizes only `garrison`. **Any future evolving float (the P5 economy adds salvage/influence) added without a `snappedf` pass silently breaks the F4 save.** Comment every float write site; consider one quantize pass in `tick()`.
- **RISK-3 · The soak's serialization test is JSON-hash, not `var_to_str` bit-exact** (`war_soak.gd:46-50,71`) — JSON truncates doubles, so sub-precision loss passes. The "provably lossless / bit-for-bit" comments (`war_sim.gd:37-39`) overstate it. Assert `var_to_str(a)==var_to_str(b)` directly.
- **RISK-4 · `garrison_cap` is not an invariant** — `_reinforce_front` (`:250`) and the mauled refund (`:229`) exceed it; the soak never checks.
- **RISK-5 · Soak loops have no independent safety cap** (`war_soak.gd:82-83,106-107`) — they rely solely on `_check_end`; a regression hangs the harness forever. Add a hard tick ceiling.

### 🟠 Correctness / lifecycle

- **BUG-4 · Overlay COMBAT sliders show stale defaults at startup.** The overlay (child) snapshots slider values in `_ready` *before* `main._ready` (parent, last) runs `combat_config.load_from_user()` (`main.gd:42-43`, `debug_overlay.gd`). Live config is correct, but COMBAT sliders show the *default* until Load is clicked. (Flight/audio/look/enemy are fine — their owners load before the overlay builds their rows.)
- **BUG-5 · `damage_config` is never auto-loaded from `user://` on boot.** Confirmed: nothing calls `damage_config.load_from_user()` (contrast every other config). User-saved damage tuning is silently ignored until the Load button. One-line fix.
- **BUG-6 · `wave_director.gd:117` — stale `_next_wave` timer leaks into the next run.** The inter-wave `SceneTreeTimer` is never tracked/cancelled; `end_run()` frees enemies but not the pending timer. Ending a run during intermission and re-arming before it fires spawns an out-of-sequence wave.
- **RISK-6 · Two uncoordinated pause mechanisms.** `draft_screen.gd` uses `get_tree().paused=true`; `main.gd:105-113` uses `Engine.time_scale`+autopilot+binding-context. Entering the exit gate while slow-mo pause is active never clears it, so the game resumes in slow-mo with paused bindings. Also `create_timer(respawn_delay)` (`main.gd:315`) is time-scale-affected → death during slow-mo stretches respawn ~30×.
- **RISK-7 · Gameplay actions fire while typing a preset name in flight.** `_handle_pause` guards only `pause_toggle` against `LineEdit` focus, but `camera_toggle` (`main.gd:72`) and `reset_drone`/`fire` polling are unguarded — typing into `name_edit` mid-flight can toggle camera / reset. The same early-return also swallows `pause_switch` edge detection (`main.gd:93,97-102`), desyncing `_pause_switch_was`.
- **RISK-8 · Core input setup lives in the debug overlay.** Loading `input_bindings` and the `apply()` that rewrites the InputMap and *creates* `arm_switch`/`pause_switch`/`missile_auto_switch` happen only because the overlay's `_ready` runs. `main.gd` depends on those. **Any scene/headless path without the overlay gets factory bindings and missing actions — move this to a dedicated input owner before M6 adds non-arena scenes.**
- **RISK-9 · Unguarded division by `enemy_config.muzzle_speed`** in AI lead math (`turret.gd:92`, `enemy_drone.gd:128`) — a `0` in a bestiary `.tres` yields inf/NaN. `ReticleSolver`/`main` guard with `maxf(…,1.0)`; the AI doesn't.
- **RISK-10 · Scorers wired once via a group scan at `_ready`** (`main.gd:46-48`); dynamically spawned/reinstanced targets/turrets won't connect to `destroyed`. Latent as M6 adds spawners/the composer.
- **REF-DEFECT (new, documented & parked) · The reference pilot rams the Aegis.** With the gun director removed from missile cells (v1.25), Missile×Aegis flips to 0% — the pilot has no standoff; its aim loop pitches the uptilted gun line onto the target, driving it forward into the bomber (39.7 m→0.5 m), too close to lock (cone 82°). This is a real pilot defect the conflated instrument had masked. **Deliberately left unfixed** — a standoff behavior is a `PILOT_VERSION` bump + a full re-measure, not a quiet edit. Don't "fix" it casually; follow the pin discipline.

### 🟡 Perf (watch as sorties get big — P2 wants expansive maps, many entities)

- **RISK-11 · `Effects.impact` reuses the full `Explosion` scene for every bolt impact** (`effects.gd:18-19`), incl. walls/ground/misses (`projectile.gd:73`) — two `CPUParticles3D` + `OmniLight3D` + `Tween` + timer + sound at ~10 shots/s from player + enemies. The one genuinely hot VFX path, not pooled or lightened.
- **RISK-12 · Per-tick (240 Hz) group scans + allocations** in fire-assist (`weapon.gd`) and missile lock (`missile_system.gd`) — fresh `enemies+turrets` array each tick. `gnat_swarm._physics_process` is O(n²) but `n≤~12` by design and cheap (documented).
- Per-frame in `main.gd`: `get_viewport().get_camera_3d()` 3× (`:122,133,144`); the overlay rebuilds a formatted telemetry string every frame. Cache the camera per `_process`; dirty-flag the overlay string if it profiles hot.

### 🟡 Smells / debt

- **SMELL-1 · Balance constants hardcoded throughout `war_sim.gd`** — proxy-sortie scoring/odds (`:96-121`), attack resolution (`:216-230`), allied threshold `2.6-skill` (`:191`), reinforce thresholds, and all of `_sortie_risk`/`_target_value`/`_garrison_type_multiplier`/`_fort_for_type`. **For a project whose whole methodology is "sweep the levers," these should be `WarConfig` fields.** (The player-side balance layer now models this rigorously — the war-sim's own constants are the remaining opaque ones.)
- **SMELL-2 · Ballistics still partly duplicated.** The reticle extraction removed `main.gd`'s copy, but `weapon._fire`/`_assist_solution` and `ReticleSolver.solve` still independently recompute origin/velocity/drop, and AI lead lives in `turret`/`enemy_drone`. LOS raycast is duplicated across `turret`/`enemy_drone`/`missile_system`/`weapon`. **A shared ballistics/LOS module** is the natural home for per-weapon/hardpoint stats (P3) and would centralize the muzzle math the reticle mirrors.
- **SMELL-3 · Node-type knowledge scattered across four `match` statements** in the war-sim; adding a P4 node type means editing four sites.
- **SMELL-4 · `_neighbors` recomputes adjacency by O(n) scan every call** (`war_sim.gd:283-290`); every BFS calls it per node → ~O(n²–n³)/tick. Fine at n=30, but **materialize the neighbor lists at generation** (the "beehive graph" is never actually built) — cheap win + the natural home for cached distances.
- **SMELL-5 · Enemy fire can score points for the player** — targets are `team="neutral"` (`target.gd:20`), so strayed enemy bolts destroy them and `destroyed` credits the player (`main.gd:196`).
- **SMELL-6 · `repair_gate.gd:28-30` decrements cooldown in `_process`** (frame-rate-dependent; violates the fixed-tick rule) and reaches health via stringly-typed `get_node("Health")`. **Explicitly on the team's radar** — the v1.23 log queues a "risk-based review of P2-era code (motor_model damage coupling, repair_gate)."
- **SMELL-7 · `Health.heal`/`revive` emit no signal** — healers each remember to call `set_health` afterward; easy to desync a future healer.
- **SMELL-8 · `main.gd` still concentrates run/score/combo, damage feedback, death/respawn, pause** (reticle math now extracted). Candidates to pull into their own controllers before M6 grows the file.
- **SMELL-9 · `crosshair.gd` (`hud.tscn:15`) draws a static center circle overlapping the FCS reticle's boresight** — likely redundant legacy.
- **SMELL-10 · Baked `Environment` values in `greybox.tscn`/`dev_room.tscn` are largely dead** — `LookController` re-applies `LookConfig` every frame, overwriting the hand-authored `.tscn` numbers after frame 1. A trap. (The two scenes also duplicate the whole environment header.)
- **SMELL-11 · `war_sim.gd` keeps mutating state after a mid-tick winner is set** (`:26-36`). Deterministic (harmless to reproducibility) but could surprise a UI rendering the final state.

### 🟡 Gaps (missing seams — mostly expected pre-slice, flagged so you don't trip)

- **GAP-1 · No loadout/hardpoint/frame abstraction.** One hardcoded blaster + missile, stats on the player-wide `CombatConfig`. **Promote a `Weapon`/hardpoint resource** as step one toward P3 frames — the flak pod (Phase 4) is the forcing function.
- **GAP-2 · No strategic-layer scene or state machine.** The war-sim runs headless; no command-room scene, hex-map render, composer, or campaign save↔gameplay wiring. `main.gd`/`main.tscn` assume one arena. **The biggest structural build ahead** (§6).
- **GAP-3 · `caution` is generated and serialized but never read** (`theater_generator.gd:88`); only `aggression` feeds behavior. "Theaters fight differently" is half-implemented.
- **GAP-4 · Pilots have no terminal loss condition.** `_check_end` ends only on home/HQ capture or `max_ticks`; `_allied_offensive` still runs at 0 pilots, so a war is winnable with zero pilots left. Wire out-of-pilots → the F1/F4.a spectator epilogue.
- **GAP-5 · Campaign-length target (25–40 sorties) printed but never asserted** (`war_soak.gd:118-122`); win-rate monotonicity checks only the two endpoints; determinism/serialization run one seed each.
- **GAP-6 · Weather/biome layer is thin** — 7 weather types generated, only `&"fog"` has effect; biomes are unused tags (+ BUG-2); `WeatherConfig` inert. Know this before wiring the composer to them.
- **GAP-7 · Overlay rows are spec-table-driven, not reflective** (`debug_overlay.gd`), and no-op silently on a misspelled field. The Gnat's swarm fields required a hand-added block (the +7-line diff this phase) — **this cost is paid per new field and grows with M6's ~10 new configs.** The *persistence* layer (`TunableConfig.copy_from`) is already reflective; consider making row-gen reflective too (drive from `property_list` + per-field range metadata).

### 🟣 Balance instrument (Phase 3.5) — code-level findings

The instrument is a genuine advance (§9), but a line-by-line read of the two largest new files (`delivery_bench.gd`, `matchup_harness.gd`) surfaced these:

- **BUG-H1 · The harness watch-mode HUD is dead code.** `matchup_harness.gd:261` `_update_hud()` is defined but never called; the RUN phase only drives retarget/pilot. So the reticle/health overlay the file header and `ReticleSolver`'s docstring advertise ("the harness draws the same reticle when you watch a duel") does not actually render. Either wire it into the run loop or drop the claim.
- **BUG-H2 · `delivery_bench.gd` keeps firing missiles through the GRACE window on the aim cell.** `_cease_fire()` (`:379-382`) clears `fire_override`, but GRACE still calls `_pilot.update()`, which re-sets `missile.fire_override = true` every tick (`reference_pilot.gd:174`). Late grace launches can't resolve and book as misses, biasing `aim:missile` *down*. Masked today only because `aim:missile` measures 1.0 — it will bias any harder aim-missile target the roster adds.
- **RISK-H1 · Structural asserts use hard-coded matchup indices.** `matchup_harness.gd:371,374,381` guard rig sanity via `_win_rate(1/2/5)` (positional into `MATCHUPS`). Phase 4 inserts Flak/Atlas rows "as one list entry" (per the file header), which silently repoints these asserts at the wrong cells (the Blaster×Aegis shield-gate assert could end up guarding a non-Aegis row). Switch to name/type lookup **before** adding rows.
- **RISK-H2 · `delivery_factors.json` rots against pilot version only, not config drift.** The staleness guard compares `pilot_version` alone (`matchup_harness.gd:421-429`); a `CombatConfig`/`EnemyConfig` change that alters real aim/evasion (muzzle_speed, enemy speed/accel, lock params) without a `PILOT_VERSION` bump leaves the predicted column silently using stale factors. Add a config hash/stamp to the artifact.
- **SMELL-H1 · The turret-evasion "control" cell isn't flagged `"control": true`** (`delivery_bench.gd:75-76`), so `_score_cell` never applies `CONTROL_MIN_RATE` to it. A bench regression dropping turret evasion to 0.5 would pass silently — a control that doesn't guard.
- **SMELL-H2 · Benches mutate `fire_assist_miss_m` on the shared (loaded, not duplicated) `default_combat_config.tres`** (`delivery_bench.gd:177,201`, `matchup_harness.gd:201`). Reset per cell so harmless today, but live mutation of a committed shared resource — fragile if cells ever run concurrently. (Enemy configs are correctly `.duplicate()`d.)
- **GAP-H1 · RNG-free enemies collapse the rep sample.** Turret and Aegis carry no `ai_seed`/RNG, so all `REPS=6` duels are bit-identical; win-rate quantizes to 0%/100% and the band can only read `++`/`--` for them (a deterministic turret win reads `++`, never the paper `0`). Extra reps are wasted and resolution is lost for exactly the deterministic types.
- **GAP-H2 · `evasion:raider` is measured at a single fixed `ai_seed=0`** (`delivery_bench.gd:285`), not averaged, while duels sample seeds 0–5 — whatever seed-0's wander does biases the committed factor.
- **OPPORTUNITY-H · `evasion:gnat` is measured with `swarm_pursuit_gain=0`** (boiling in place) while the duel runs full pursuit + stings — deliberate per the separability model, but it guarantees a predicted-vs-validated gnat gap a reader can misread as a defect. Add a one-line "different rulers" callout to the mini-web output (as the pack-mode note already has).

**Confirmed clean by this pass:** the measured path IS fully seeded (`enemy_drone`/`gnat_swarm` from `ai_seed`; remaining `randomize()`/wall-clock reads are cosmetic and outside the bench path); the non-bit-exact contract is stated (`matchup_harness.gd:17-22`); `balance_report.cmd` stops early on a Layer-1/2 failure; and a `PILOT_VERSION` mismatch does blank the predicted column as designed.

---

## 6. The slice build ahead — sequencing & the real integration challenges

Design slice cut: 1 biome (cyberpunk city), 2 archetypes (Strike + Dogfight), 2 frames (Kestrel + Atlas), 3 weapons (Blaster + Missile + Flak pod), 4 enemies (all built), gun director as first acquisition, motor damage (shipped), salvage-only economy, floor+ceiling harness checks.

1. **Phase 4 (the team's stated next step):** the **flak pod** (3rd weapon column — the designed Gnat answer; note `Blaster×Gnats` currently bands `--` precisely because flak doesn't exist yet) + **Atlas** (2nd frame). Measure both on the *unconflated* Phase 3.5 instrument (the whole point of building it first). Adding the flak pod is the forcing function for **GAP-1** (promote a per-weapon resource).
2. **Wire the slice-four into the live loop (GAP-A)** and the Aegis `detonated` outcome into scoring — today they're specimens/benched only.
3. **Make the mission layer deterministic (RISK-1)** before the composer — the reference pilot / composed-sortie harness / any replay depend on a threadable run seed.
4. **Allied kinetic presence (new v1.23 steering — WANTED, composer-era):** allied units should *fight in-scene*, not resolve as tokens ("making the player feel like HE IS THE WAR"). The concrete work is stated in the doc: enemies are kinematic steering agents; an ally is the same code with `team="ally"` + **team-generalized targeting — enemies currently hardcode the player as target, and that hardcode is the work.** This also prepays commander mode (F3). Not slice, but a clean, decided future you may touch early.
5. **The war↔sortie bridge is the central unbuilt seam (GAP-2).** Today `_proxy_sortie` is a coin flip. The real loop: present the theater → human picks a node → `compose(seed,node,war,tier)→sortie_spec` (P2, doesn't exist) → build a sortie scene from it → fly it → feed the *real* outcome back into `WarSim.tick()` (via `strength_cost`) → persist (the `var_to_str` save works). **This needs a new scene/state-machine layer `main.gd` doesn't anticipate.** Consider a thin `CampaignController` + a placeholder command-room scene early, to close the loop end-to-end before content deepens.
6. **Promote war-sim constants to `WarConfig` (SMELL-1/3)** as you touch it — the harness is meant to sweep them.
7. **Clear the queued P2-era risk review** the team already flagged: `repair_gate` `_process` (SMELL-6), motor-damage coupling.

---

## 7. Test & harness state

The test story is now **two fragmented pieces**:

**(A) Correctness checks (`scripts/tests/`)** — genuine pass/fail (a real strength): `hover_check`, `combat_check`, `wave_check`, `missile_check`, `repair_check`, `motor_damage_check`, `run_check`, plus `war_soak` (war-sim invariants, with the GAP-5/RISK-3/4/5 caveats). **Still no single runner**, and **CLAUDE.md's list still omits `repair_check` and `motor_damage_check`.** `step_response`/`rate_tune_sweep` only *print* — so **flight-feel regressions still have almost no automated guard** (only `hover_check`/`motor_damage_check`).

**(B) The balance instrument (NEW, `scripts/balance/` + `tools/`)** — a genuine advance:
- **`tools/balance_report`** runs all three layers in dependency order, stopping early on failure — the aggregate runner the earlier draft said was missing (for balance, at least).
- **Layer 1 (`lethality.gd`)** derives kill-or-never / shots-to-kill / TTK by replaying `Health.take`'s exact rules; **`lethality_check.gd` plants shots into a *real* `Health` node and fails if replay and shipped code drift** — a real correctness guard, and the state-split (shielded vs cracked) + derived combos are clean, self-documenting code.
- **Layer 2 (`delivery_bench.gd`)** measures aim (agent vs static immortal target) and evasion (frozen perfect-shooter vs mover) in isolation, with control cells that fail if the perfect shooter itself can't shoot.
- **`prediction.gd`** joins them with its four assumptions written into the file; **watch mode** (drop `--headless`) renders duels with the real HUD via `ReticleSolver`, now standing policy (`bench_view.gd`).

**Test debt that remains:**
- **No player-side config `var_to_str` round-trip test** (the war side has one; the player configs don't) — a natural companion to the F4 discipline.
- **`combat_check` pins no config fields** — it inherits the developer's `user://` saved combat config, so a saved low `muzzle_speed`/high gravity fails it on a clean tree. (Other checks defensively pin.) Tests also mutate shared default `.tres` in memory — safe *only* because headless never saves.
- **The reference pilot's competence datum is low (aim 0.14 on a static target) and carries the known no-standoff defect** (REF-DEFECT). Both are `PILOT_VERSION`-gated — improving the pilot is a deliberate full re-measure, by design.
- **Separability (`aim × evasion`) is an explicit, un-validated assumption** (stated in `prediction.gd`) — a jinking mover is likely harder than the product implies. Fine for ranking; don't read predicted TTK as a wall clock (it omits lock + time-of-flight, by definition).
- **No aggregate runner for the (A) correctness checks** and no `README`; each is invoked by hand. Add one that also **bypasses `user://` configs** (load only `default_*.tres`).
- `sound_bank.gd` is null-safe only in `play_at()`; `_ready`/`_process`/`set_muffled` dereference `audio_config` unguarded.
- **Balance-harness robustness items** — a dead watch-mode HUD, a grace-window firing bug, hard-coded assert indices that Phase 4's new rows will silently misalign, factors that rot against pilot version but not config drift, an unguarded "control" cell, single-seed `evasion:raider`, and rep-sample collapse for RNG-free enemies — are catalogued in §5 🟣 (BUG-H1/H2, RISK-H1/H2, SMELL-H1/H2, GAP-H1/H2). **RISK-H1 in particular should be fixed before Phase 4 inserts matrix rows.**

---

## 8. Quick wins (cheap, high-value, low-risk)

- Auto-load `damage_config` on boot (BUG-5) — one call.
- Guard `muzzle_speed` division in `turret.gd:92`/`enemy_drone.gd:128` (RISK-9).
- Add a hard tick ceiling to the soak loops (RISK-5); assert `var_to_str` string-equality instead of the JSON hash (RISK-3).
- Add cheap soak invariants: `garrison ∈ [0,cap]`, `pilots ≥ 0`, exactly one `home`/one `hq` (RISK-4).
- Fix the biome index bug (BUG-2); delete/fold `caution` (GAP-3) and the legacy `crosshair` circle (SMELL-9).
- Extend the `LineEdit` typing guard to `camera_toggle`/`reset_drone`, and stop it swallowing `pause_switch` edges (RISK-7).
- Pin `combat_check`'s config fields like the other checks do; add a correctness-suite runner that loads only defaults (§7).

---

## 9. What is already right — do NOT "fix" these

- **The flight model (`scripts/drone/`).** Tick-rate-independent discretization, Betaflight-faithful filtering + I-term relax + crash gating, honest hover-throttle from the thrust model, asymmetric motor-out damage the rate loop genuinely fights. The USP; treat changes as feel-checkpoint work only.
- **The war-sim determinism foundation.** Seeded RNG stored *in* state and restored/saved each tick, deterministic sort tiebreaks, float quantization, node-array (not order-dependent Dict) iteration. The §5 fragilities are about *preserving* it, not rewriting it.
- **The Phase 3.5 balance instrument.** The layered model (lethality × delivery, duel demoted to validation), `lethality_check` verifying the replay against the real `Health`, the state-split, and `PILOT_VERSION` pinning are exemplary rigor (the watch mode's *plumbing* is in place via `bench_view.gd`, though its HUD overlay is currently unwired — BUG-H1). The **`Blaster × Raider` vindication** — the layered model predicting `++` from config arithmetic + two isolated benches, matching the human's hand-band, after the integrated duel had misreported the weapon for a whole phase — is the methodology proving itself. Respect the H5 division of labor: **the harness measures balance; the hands measure feel.**
- **The bestiary implementation.** `Health`'s opt-in threshold-gate shield, the Gnat's cloud-is-the-unit boids, the Aegis as a physical `ShieldShell` barrier (born from a real playtest finding: the decorative bubble read as broken), and the missile-LOS multi-part fix are all careful, well-motivated work.
- **The `TunableConfig` reflection pattern** — reflective persistence scales to new config types for free. (Only the *overlay rows* aren't reflective yet — GAP-7.)
- **The damage model, audio synthesis, and design/checkpoint discipline** — the wounded-quad loop is a human-validated USP asset; audio is deterministic/allocation-light/headless-stubbed; `GAMEPLAY-DESIGN.md` is an unusually rigorous append-only decision log where every balance number is meant to be *measured*, not authored.
- **Scene-wiring hygiene** — the `node_paths`/`NodePath` gotcha is applied correctly; `dev_map` genuinely mirrors `main`; `profile.gd` degrades gracefully on corrupt JSON.

---

## Appendix — where things live

- **Docs (read first):** `CLAUDE.md` (rules), `BALANCE.md` (the balance instrument's contract), `FPV-SANDBOX-HANDOFF.md` (M0 flight spec + tuning §14), `ROADMAP.md`, `GAMEPLAY-DESIGN.md` (M6 bible + decision log — the v1.22–v1.25 tail is the current build state).
- **Flight:** `scripts/drone/*` + `resources/flight_config.gd` + `resources/damage_config.gd`.
- **Combat:** `scripts/combat/*` + `resources/{combat,enemy}_config.gd` + `scenes/combat/*` (incl. `gnat*`, `aegis`, `shield_shell`).
- **War-sim (M6 core):** `scripts/war/*` + `resources/war_config.gd` + `scripts/tests/{war_soak,war_trace}.gd`.
- **Balance instrument:** `scripts/balance/{lethality,prediction}.gd` + `scripts/tests/{lethality_check,delivery_bench,matchup_harness,reference_pilot,bench_view}.gd` + `scripts/ui/reticle_solver.gd` + `balance/delivery_factors.json` + `tools/*.cmd` + `BALANCE.md`.
- **UI/config infra:** `scripts/ui/*`, `scripts/main.gd`, `resources/tunable_config.gd`, `resources/input_bindings.gd`, `resources/look_config.gd`, `scripts/environment/look_controller.gd`.
- **Current work front:** decision-log v1.25 → **Phase 4** (flak pod + Atlas), on the now-unconflated, state-aware, watchable balance instrument; then the H.q4 hands-on difficulty calibration once the slice is flyable end-to-end.
