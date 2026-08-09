# PLAN-FULL-SCALE.md — the aircraft-scale overhaul

**Status: PROPOSED, not started. Written 2026-08-09 for review, then for a fresh
session to execute.**

Read [CLAUDE.md](CLAUDE.md), [TESTING.md](TESTING.md) and
[HANDOFF-NEXT.md](HANDOFF-NEXT.md) first. This document covers one thing: the
decision to stop being a game about small remote-controlled machines and become
a game about full-size aircraft over vast terrain, and everything that decision
drags with it.

---

## 0. The decision, in the user's own words

> *"i'm considering removing the actual original assumption that we are flying a
> radio drone, and instead we are IN the drone. the vtx effects can still stay as
> mechanical limitations of a manned vehicle vision equipement."*

> *"one of the stones on my original dream is truly vast environments."*

> *"an arena feels too small for what i feel this game should be... this is a
> different gameplay mode imho."*

> *"the look and feel of our game identity will be flashed out soon, now that we
> decided if we are not talking about small remote control devices/toys that
> fight each other, but a more serious, 'real world' feel, full size aircrafts
> style."*

**Five decisions were taken in conversation and only two of them have any code
behind them.** They are listed in §1. Everything else in this document is how to
carry them out.

**The stated worry, and it is the right one:**

> *"most important is the scaling of everything, which im worry about, and how it
> affects the physics."*

§3 is the honest answer to that, and it contains a fork only the user can settle.

---

## 1. The five decisions

| # | Decision | Status |
|---|---|---|
| D1 | **The pilot is IN the aircraft.** The FPV radio-link premise goes. Video-feed breakup stays, reframed as a manned vehicle's optics. | decided, nothing built |
| D2 | **The Kestrel becomes 2–4 m** rather than 0.28 m, with everything else in proportion. | decided, nothing built |
| D3 | **Two gameplay modes.** The arcade/roguelike run keeps its arena. The campaign sortie becomes a large navigated map: insert, cross, accomplish, escape. | decided, nothing built |
| D4 | **The signal leash goes**, replaced by map edges with about a 100 m margin. | decided, nothing built |
| D5 | **Vast terrain**, smooth, kilometres across. | **BUILT** — `TerrainField` / `TerrainMesh`, 6.1 km in ~93k triangles, not yet wired into the game |

**D1 fixes a contradiction that already exists**, and this is the strongest
argument for it rather than the fiction. P5.4 already costs a PILOT from the war
room's roster when the aircraft dies. That has never made sense for a remote
operator sitting in a bunker; it makes complete sense for someone aboard. The
campaign's most interesting resource stops being a bookkeeping oddity.

**D3 is what protects the existing game.** The wave director, the draft, the combo
score, the exit gate — that whole loop is an arena game and it is good at being
one. Stretching it over kilometres would ruin it. Nothing in this plan touches it
except the scale pass.

---

## 2. What is NOT changing

Worth stating plainly, because the list is longer than the list of things that
are:

- **The war layer.** `WarSim`, `WarManifest`, `SortieComposer`, the war room, the
  save. All abstract; scale is not a concept there.
- **The bestiary's behaviour.** Eight types, all signed off. Their *numbers* move
  in the scale pass; their logic does not.
- **The flight model's architecture.** `FlightController`, `MotorModel`,
  `RateController`, the 240 Hz tick, the pilot axis convention. Numbers move.
- **The balance instrument's structure.** Three layers plus validation. Every
  number it has ever produced becomes void (see §6), but the machine is fine.
- **The arcade run.** Per D3.

---

## 3. THE SCALE QUESTION — the physics, honestly

This is the part the user asked for and it deserves the most care.

### 3.1 The one thing that does not scale

**Gravity is 9.8 m/s² whatever you do.** Every other consequence below follows
from that single asymmetry. If gravity scaled with the world, none of this would
matter.

### 3.2 What scales, and by what law

Let **S** be the linear scale factor. Going from a 0.28 m quad to a 3 m aircraft
is **S ≈ 10.7**.

| Quantity | Law | Why |
|---|---|---|
| Length | ×S | by definition |
| Area (wing, frontal) | ×S² | |
| Mass | ×S³ | same density |
| Thrust needed to hover | ×S³ | must equal weight |
| **Moment of inertia** | **×S⁵** | mass × length² |
| Torque available | ×S³ | thrust × arm = S² × S |
| **Angular acceleration** | **×S⁻²** | torque ÷ inertia |

**The fifth and seventh rows are the whole problem.** Angular acceleration falls
as the square of scale. At S = 10.7 a physically honest aircraft is **≈ 115×
slower to change attitude** than the current quad. That is not a tuning
difference; it is the difference between an FPV freestyle quad and a helicopter.

**This is real physics and it is why a 747 does not roll like a quad.** It is not
a bug to be tuned away.

### 3.3 THE FORK — and it is the user's, not the agent's

**Option A — simulation-honest.** Let the rates fall. A 3 m aircraft rolls at
100–200 deg/s instead of 600–900. Flying becomes deliberate, momentum-led,
"heavy". Gains a genuinely different and more serious feel; loses the FPV
freestyle agility that is currently the product.

**Option B — arcade (the Firehawk reading).** Keep something close to today's
agility on a 3 m body. Physically absurd, entirely legitimate for a game, and it
is what the user's own reference points to. The aircraft *looks* full-size and
*flies* like a quad.

**Option C — split by airframe.** The Kestrel keeps quad-like agility (a small,
fast, twitchy machine at the light end); the Atlas gets the honest heavy handling.
Scale becomes a design axis rather than a global constant, and P3.4's frame
classes stop being a stat block and start being a flight model.

**The agent's recommendation is C, then B if C proves too much work.** C is the
only option that turns the cost into content. But **this must be answered before
any number is touched**, because A, B and C produce three different retunes and
doing one then another is doing it twice.

### 3.4 Froude scaling — the tool for keeping motion *looking* right

If the goal is that a big aircraft *reads* as big rather than as a small one
filmed close up, the classical answer is **Froude scaling**:

- length ×S
- **time ×√S**
- **speed ×√S**
- force ×S³

At S = 10.7 that makes everything happen **≈ 3.3× slower** and cruise speeds
**≈ 3.3× faster** in absolute terms. A quad at 25 m/s becomes an aircraft at
82 m/s that *looks* like it is moving at the same relative pace.

**This is a lens, not an instruction.** It tells you what "physically honest for
this size" means so that any departure from it is a choice somebody made rather
than an accident. Option B above is a deliberate departure from Froude; it should
be recorded as one.

### 3.5 What is safe, and what to avoid

**SAFE, verified against Godot 4.7:**

- **Float precision.** 32-bit transforms give sub-millimetre precision at 6 km
  and roughly 1 cm at 100 km. Not a concern at the scales in this plan. A
  floating origin becomes worth discussing past ~50 km, not before.
- **The 240 Hz tick.** Larger, slower-rotating bodies are *easier* to integrate,
  not harder. The tick rate exists for rate-loop stability and can stay.
- **Collision margins.** Godot's defaults are tuned for roughly human-scale
  objects. At 0.28 m the current drone is *below* that sweet spot; 3 m is
  comfortably inside it. This gets better, not worse.

**AVOID:**

- **Do not model at 1×1×1 and scale the node.** It is not more efficient — the
  GPU and physics costs are identical — and scaled collision shapes are a known
  source of unreliable behaviour, non-uniform scale especially. **Author every
  collider at true world size.**
- **Do not scale by editing 200 numbers by hand.** See §4.

---

## 4. HOW TO ACTUALLY DO THE SCALE PASS

The danger is not the physics; it is doing this as a sprawling manual retune
across dozens of `.tres` files and losing track of what has been converted.

### 4.1 One conversion, written down, applied once

Add a single module — call it `Scale` — holding the chosen factor and the laws
from §3.2. **It is a one-shot migration tool, not a runtime multiplier.** Runtime
scaling would mean every config number lies about itself forever, which is
exactly the "tunable that does not mean what it says" trap the terrain work hit
twice in one day.

The procedure:

1. Pick S and the fork answer (§3.3).
2. Write a conversion script that reads every `.tres`, applies the correct law
   per field, and writes it back.
3. Run it once. Commit the diff as its own commit, with the script.
4. Delete nothing — the script is the record of what was done and why.

**Every field must be classified by its law**, and getting this wrong silently is
the main risk in the whole plan. Lengths, speeds, masses, forces, rates, times
and dimensionless ratios all scale differently. **A field whose law is unclear
gets a comment, not a guess.**

### 4.2 The inventory — what scale actually touches

Counted from the current tree. This is the checklist.

**Flight (per frame, ×2 frames):**
`mass`, `arm_length`, `thrust_to_weight_ratio` (dimensionless — do NOT scale),
`max_rate_deg` (the fork decides), rate PID gains (retune, do not convert —
gains are not physical quantities), `drag_coefficient`, `angular_damping`,
`chase_distance`, `chase_height`, `max_angle_deg` (dimensionless).

**Frames:** `hull`, `armor` — arguably dimensionless game currency; decide and
record.

**Combat (`CombatConfig`, ~40 fields):** `muzzle_speed`, `projectile_lifetime`,
`fire_assist_range`, `missile_lock_range`, `missile_speed`,
`missile_turn_rate_deg`, `missile_prox_radius`, `flak_muzzle_speed`,
`flak_arm_distance`, `flak_fuse_radius`, `flak_burst_radius`,
`crash_damage_speed`.

**Bestiary (`EnemyConfig` × 8 types):** `speed`, `accel`, `turn_speed_deg`,
`sight_range`, `preferred_range`, `muzzle_speed`, `swarm_spacing`,
`swarm_sting_radius`, `bomb_radius`, `blast_fuse_radius`, `mount` geometry, the
Phalanx's shell radii and `stern_vent_arc_deg`.

**Sortie geometry:** `EGRESS_RADIUS` (105), `INGRESS_MIN_M`/`INGRESS_MAX_M`
(140/195), `MIN_SEPARATION_M` (6), the layered garrison ring radii.

**Environments:** the greybox, the dev room, `CityLayout`'s `block_size`,
`road_width`, floor heights, gate apertures, `ResupplyGate` and `RepairGate`
dimensions, pad sizes.

**The menu tower — and this one is a trap.** You fly *through windows* to select
a leaf. Window apertures, floor heights and the building's whole massing are
sized against a 0.28 m body. At 3 m the menu becomes unflyable. `menu_check`
guards the tree, not the geometry.

**Audio:** emitter rolloff distances, doppler.

**HUD:** reticle range ticks, radar scale, the damage-direction indicator.

**Terrain:** `amplitude_m`, `noise_frequency`, `cell_m` — but note the terrain
was authored *for* the vast world and may already be at the right scale. Check
rather than convert.

### 4.3 What must NOT be converted

- **PID gains.** They are controller tuning, not physical quantities. Converting
  them produces nonsense. They must be **re-tuned** with `rate_tune_sweep.gd` and
  `step_response.gd` after the masses and inertias move.
- **Dimensionless ratios**: thrust-to-weight, expo, `aim_jitter_deg`, all the
  `*_chance` fields, `strength_cost`, points.
- **Times that are game pacing** rather than physics: `shield_regen_delay`,
  `stern_vent_cycle_s`, `combo_window`, wave intermissions. These are design
  rhythms. Froude says they should scale; the game says they are pacing. **Record
  the choice.**

---

## 5. PHASES

Ordered so that each one ends somewhere flyable, and so the expensive
irreversible steps come after the cheap reversible ones.

### Phase 1 — Decide, do not build

Answer §3.3's fork and pick S. Write both into GAMEPLAY-DESIGN as a numbered
Iteration with steering questions, the way A.q1–A.q10 worked for the Phalanx.
**No code.** Cost: one conversation. **This is the whole gate.**

### Phase 2 — The aircraft alone

Scale one frame and its flight model. Nothing else. Fly it in the dev room at
current world scale — the aircraft will be comically large against the existing
props and that is *fine and informative*. Retune the rate loop. Get a verdict on
feel before anything depends on it.

Deliverable: the human says "yes, this is what a full-size aircraft should fly
like."

### Phase 3 — The conversion pass

The §4.1 script across every remaining config. The menu tower and the city need
hand attention rather than a multiplier. Board green, everything flyable.

Deliverable: the whole game at the new scale, playing as it did before.

### Phase 4 — Terrain into the game

Wire `TerrainMesh` into the real scenes. This is the phase the terrain work was
built for and it is mostly **teaching things to ask `height_at` instead of
assuming zero**: enemy station-keeping and minimum altitude, the aegis's bomb,
the Lance's run, `SortieRunner._point_for`, the ingress put-down, `CityLayout`'s
foundations, crash damage.

Deliverable: a sortie fought over real ground.

### Phase 5 — The large sortie (D3)

The campaign sortie becomes a navigated map. `EGRESS_RADIUS`, the ingress band
and the concentric garrison rings are all arena constructs and will not survive.
Replace the signal leash with map edges (D4).

Deliverable: insert, cross, accomplish, escape.

### Phase 6 — Detection and cover

The feature deferred since A6 because there was nowhere to hide. Now there is.
Detection-on-sight plus the approach's corridors and cover, which the composer
already emits and nothing reads.

Deliverable: A.q7 answered — the approach is contested.

---

## 6. VERIFICATION, AND THE COST NOBODY SHOULD BE SURPRISED BY

**Every balance number in the project becomes void at Phase 3.** Layer 1's
arithmetic, Layer 2's delivery factors, Layer 3's survivability, every published
counter-web band. They were measured on a 0.28 m aircraft.

This is not avoidable and it is not a disaster — but it must be **planned as one
event, not discovered forty times**:

1. `PILOT_VERSION` bumps once, at Phase 3, because the reference pilot's geometry
   assumptions move with the world.
2. `tools/balance_report` runs once after Phase 3 settles (~70 minutes).
3. **Every number quoted in GAMEPLAY-DESIGN before that point is historical.**
   The design doc is append-only, so they stay — but the Phase 3 entry must say
   plainly that everything above it was measured at the old scale.

**The config stamp already protects against quoting stale factors**, which is
exactly the situation it was built for. It will refuse the old file. Let it.

**The board is the safety net through all of this.** 23 checks; they encode
behaviour rather than numbers, so most should survive a scale change. **The ones
that will break are the ones asserting distances**, and each break is
informative: `sortie_check`'s ingress band, `phalanx_check`'s orbit geometry,
`falx_check`'s reach, `war_room_check`'s hex projection (probably not — it is
abstract). **Fix them by re-deriving the threshold from the new scale, never by
relaxing it until it passes.**

---

## 7. RISKS, RANKED

1. **The flight model is the product, and Phase 2 changes it.** If the new feel
   is worse, everything downstream is built on a worse game. This is why Phase 2
   is isolated and gated on a human verdict. **Do not proceed past it on the
   agent's judgement.**
2. **The menu tower may become unflyable** and it is the game's front door.
   Budget real time for it; a multiplier will not do.
3. **Silent misclassification in the conversion.** A speed scaled by S instead of
   √S is a number that looks plausible and is wrong. Mitigation: the script is
   reviewed field by field, and it prints every conversion it makes.
4. **Scope.** Six phases. Phases 1–3 are the overhaul; 4–6 are new features that
   happen to need it. **They can stop after Phase 3** and have a complete,
   consistent, full-scale game.
5. **The city was authored for a 0.28 m body.** Street widths and window
   apertures may need redesign rather than rescaling, because a 3 m aircraft
   threading a city is a different game from a palm-sized one doing it.

---

## 8. OPEN QUESTIONS FOR THE FRESH SESSION TO ASK

Numbered so they can be answered by reference, in the project's own convention.

- **S.q1** — Which fork in §3.3: simulation-honest, arcade, or split by airframe?
  **Nothing may be built before this is answered.**
- **S.q2** — What is S exactly? The user said *"2-3m size bodies as the size of
  the kestrel, maybe 4m."* Pick one number.
- **S.q3** — Do game-pacing times scale (Froude) or stay put? Shield regen, vent
  cycles, wave intermissions, combo window.
- **S.q4** — Are `hull`/`armor`/`damage` physical or abstract currency? If
  abstract they do not scale, and the whole damage model is untouched.
- **S.q5** — Does the arcade run get rescaled too, or does it keep its current
  proportions as a deliberately different register? D3 says two modes; this asks
  whether "two modes" extends to two scales.
- **S.q6** — The menu tower: rescale it, or redesign it for the new aircraft?
- **S.q7** — Does the city get rescaled or redesigned? (§7.5)

---

## 9. WHAT EXISTS TODAY, FOR THE FRESH SESSION

- **HEAD is `d2c94ef`.** Board 23/23 green. Tree clean. `PILOT_VERSION` 7.
- **The terrain is built and is NOT wired into the game.** `scenes/terrain_map.tscn`
  and `scenes/desert_map.tscn` fly it; `main.tscn` and `sortie.tscn` do not
  reference it. See `TerrainField`, `TerrainMesh`, `terrain_check`.
- **The Phalanx is closed** and its numbers are signed off. Do not reopen.
- **A voxel/terraced ground was built and rejected** on 2026-08-08 and has been
  fully removed from the tree and squashed out of the history. **Do not
  re-propose blocky ground.** What survived is the LOD ring architecture, which
  the user explicitly praised.
- One known visual artefact: a faint pale band on some dune flanks in the
  mid-distance, believed to be a residual LOD seam. Flagged, not fixed.
