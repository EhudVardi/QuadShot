# PLAN-FULL-SCALE.md — the aircraft-scale overhaul

**Status: STEERED. Phase 1 is answered, Phase 2 is BUILT and awaiting a flight
verdict. Lives on branch `full-scale`; discarding the branch discards the whole
experiment.** Written 2026-08-09.

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

**Six decisions were taken in conversation; two have code behind them.** They are listed in §1. Everything else in this document is how to
carry them out.

**The stated worry, and it is the right one:**

> *"most important is the scaling of everything, which im worry about, and how it
> affects the physics."*

§3 is the honest answer to that. The fork it once contained is now **answered**
(§3.3) and the answer is better than either option the agent offered.

---

## 1. The five decisions

| # | Decision | Status |
|---|---|---|
| D1 | **The pilot is IN the aircraft.** The FPV radio-link premise goes. Video-feed breakup stays, reframed as a manned vehicle's optics. | decided, nothing built |
| D2 | **The Kestrel becomes 2–4 m** rather than 0.28 m, with everything else in proportion. | decided, nothing built |
| D3 | **Two gameplay modes.** The campaign sortie becomes a large navigated map: insert, cross, accomplish, escape. The arcade run stays an arena — **but a SCALED one** (see below). | decided, nothing built |
| D4 | **The signal leash goes**, replaced by map edges with about a 100 m margin. | decided, nothing built |
| D5 | **Vast terrain**, smooth, kilometres across. | **BUILT** — `TerrainField` / `TerrainMesh`, 6.1 km in ~93k triangles, not yet wired into the game |

**D1 fixes a contradiction that already exists**, and this is the strongest
argument for it rather than the fiction. P5.4 already costs a PILOT from the war
room's roster when the aircraft dies. That has never made sense for a remote
operator sitting in a bunker; it makes complete sense for someone aboard. The
campaign's most interesting resource stops being a bookkeeping oddity.

**D3 is what protects the existing game.** The wave director, the draft, the combo
score, the exit gate — that whole loop is an arena game and it is good at being
one. Stretching it over kilometres would ruin it.

**BUT IT IS NOT EXEMPT FROM THE SCALE PASS, and this was a correction the user had
to make to an earlier draft of this document.** In their words:

> *"whatever happens to all the existing things we have, EVERYTHING is scaled the
> same way. so for ex. the arena as the game mode environment is absolutely kept,
> but it will scale with everything else. it would just stay a relatively confined
> arena, as opposed to the vastness of the war room and the nodes maps."*

So the arena grows by S along with everything in it and stays **relatively**
confined. It is not stretched — the aircraft grew too, so the fight keeps its
proportions. **There is exactly one world scale and everything obeys it.**

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
- **The arcade run's STRUCTURE.** Waves, drafts, score, the exit gate. Its
  geometry scales with everything else — see D3.

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

**Read the last three rows together and then read §3.3, because this table is
only half the story.** It assumes thrust stays *realistic* — scaling as S² the
way a propeller's disc area does. On that assumption angular acceleration falls
as S⁻², roughly **115×** at S = 10.7, which is the difference between a freestyle
quad and a helicopter.

**That assumption is exactly what the chosen answer refuses.** Thrust is where
the fiction is spent, and §3.3 shows the penalty collapses to LINEAR the moment
it is. The table stays because it is the honest baseline any departure is
measured against.

### 3.3 THE FORK — ANSWERED: honest physics, fictional propulsion

**The user rejected both of the agent's alternatives and proposed a better third
thing.** Their reasoning, because it is the design principle and not just a
preference:

> *"if we are still talking about partially fiction world, what prevents us from
> fictioning new technology that produces engines that have thrust/weight ratio
> that are currently not achievable... the same way that an F1 car is an extreme
> example of how a toy car would have behaved in a real world, but pushing physics
> to the extreme putting a huge engine and a light frame so that it would SEEM like
> its almost an rc car, not a real one."*

> *"keep real physics calculations, stretch technology to fiction, and see what
> comes on the other side."*

On G forces: *"since we are still half way into fiction we can say that humanity
also developed a device that allows the human body to withstand the extreme G
forces."*

They rejected **arcade** (*"sounds like faking which im not fond of... firehawk
is fun enough, it really is ridiculous while still hold a real-world design,
which for me breaks the immersion"*) and **split-by-airframe** (*"feels like the
worst - being indecisive"*).

**AND THE ARITHMETIC SAYS THEY ARE RIGHT, which is the important part.** The
agent's original framing — that scaling costs S⁻² of angular agility, roughly
115× — assumed thrust stays realistic. Derived properly:

```
angular acceleration  =  torque / inertia
                      =  (c · Thrust · arm) / (k · mass · arm²)
                      =  (c/k) · g · TWR / arm
```

**α ∝ TWR / arm_length. MASS CANCELS ENTIRELY.**

Three consequences, and all three matter:

1. **A light frame does not buy agility.** Only thrust-to-weight and size do.
   The F1 analogy is exact — it is the engine, not the weight saving.
2. **The penalty is LINEAR in scale, not quadratic**, once thrust is free to be
   fictional. At S = 10.7 you lose 10.7× — not 115×.
3. **It is bought back by one number that already exists.**
   `thrust_to_weight_ratio` is a config field with a slider on it.

Measured on the real body at S = 10.7:

| | small quad | 3 m aircraft, TWR 12 | 3 m aircraft, TWR 48.2 |
|---|---|---|---|
| angular acceleration | 21,455 deg/s² | 5,341 deg/s² | 21,455 deg/s² |
| agility vs. today | 100% | **25%** | **100%** |
| hover throttle | 22% | 8.3% | **2.1%** |

**THE REAL TRADE IS NOT AGILITY VERSUS REALISM. IT IS AGILITY VERSUS THROTTLE
RESOLUTION.** A TWR high enough to restore FPV agility puts hover at 2% stick,
which is unflyable without a throttle curve. `FlightConfig.throttle_curve`
already exists and is the obvious lever; this has not been explored yet and is
the first thing to try if TWR 12 feels too heavy.

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
than an accident. The chosen answer — real rigid-body physics driven by fictional
engines — departs from Froude deliberately and by a stated amount: the TWR.

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

### Phase 1 — Decide, do not build — **DONE**

§3.3 is answered (honest physics, fictional propulsion) and S is chosen: **3.0 m,
S = 10.714**. The GAMEPLAY-DESIGN Iteration is still unwritten.

### Phase 2 — The aircraft alone — **BUILT, AWAITING A FLIGHT VERDICT**

The Kestrel alone is scaled. Nothing else in the game is. Flown against the
existing world it will be comically large, and that is *fine and informative*.

| | before | after | law |
|---|---|---|---|
| body | 0.28 m | 3.0 m | ×S |
| mass | 0.65 kg | 500 kg | light frame, deliberately under density |
| arm | 0.12 m | 1.286 m | ×S |
| TWR | 4.5 | 12.0 | the fiction dial |
| max rate | 580 deg/s | 160 deg/s | what TWR 12 can actually reach |
| drag coefficient | 0.03 | 3.44 | ×S² (it multiplies \|v\|·v, so it carries area) |
| angular damping | 0.013 | 1148 | ×inertia, to hold the damping ratio |

Measured, not assumed: **hover_check passes with 0.000 m drift**, and the rate
loop reaches half its commanded step in **150–233 ms** against roughly 20–50 ms
for the small quad. That slowness IS Option A rendered honestly.

Deliverable: the human says whether that is a game they want to fly.

### Phase 3 — The conversion pass

The §4.1 script across every remaining config. The menu tower and the city need
hand attention rather than a multiplier. Board green, everything flyable.

Deliverable: the whole game at the new scale, playing as it did before.

**A known limit that Phase 4 will have to face:** a terrain ring rebuilds on the
main thread and costs **26–47 ms** depending on `ring_cells`. That is a visible
hitch, and its frequency scales with how fast the pilot crosses cells. It is
survivable at aircraft scale with coarse cells (measured at 3% of the frame
budget) and it will NOT survive a fast aircraft over fine terrain. The fix is to
build rings on a worker thread, or to spread one rebuild across several frames.
Neither is hard; both are out of scope until something needs them.

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
   - **THIS HAS ALREADY HAPPENED ONCE, and the instance is instructive.** The FPV
     camera's offset was scaled correctly by ×S — and that was the bug. At 0.28 m
     a camera slightly forward of the body centre is *inside the hull* and the
     near plane harmlessly clips it away; at 3 m the same relative position puts
     the lens inside a solid airframe with the nose marker filling the screen.
     **Scaling a camera OFFSET is not the same as scaling a camera POSITION** —
     one of them has to clear geometry, and no scaling law knows that. Expect
     more of these wherever a number's *correctness* depends on something other
     than proportion.
4. **Scope.** Six phases. Phases 1–3 are the overhaul; 4–6 are new features that
   happen to need it. **They can stop after Phase 3** and have a complete,
   consistent, full-scale game.
5. **`user://` CONFIG SILENTLY OVERRIDES SCALED DEFAULTS, and it cost real time
   already.** `TunableConfig.load_from_user` loads a saved partial config over
   the shipped one, so a stale `user://flight_kestrel.tres` kept the OLD rate
   gains on the scaled airframe and made it look structurally unflyable. An
   experiment that raised the gains 10× produced a **bit-identical** result,
   which is the tell — a knob that changes nothing is a knob that is not
   connected. **Before judging any scale change, check what `user://` is
   overriding.** The file has been moved aside to
   `flight_kestrel.PRESCALE-BACKUP.tres`.
6. **The city was authored for a 0.28 m body.** Street widths and window
   apertures may need redesign rather than rescaling, because a 3 m aircraft
   threading a city is a different game from a palm-sized one doing it.

---

## 8. OPEN QUESTIONS FOR THE FRESH SESSION TO ASK

Numbered so they can be answered by reference, in the project's own convention.

- ~~**S.q1**~~ **ANSWERED**: honest physics, fictional propulsion. See §3.3.
- ~~**S.q2**~~ **ANSWERED**: 3.0 m, S = 10.714.
- ~~**S.q5**~~ **ANSWERED**: everything scales uniformly, arcade arena included.
- **S.q8** *(new)* — Is TWR 12 the right feel, or should the throttle curve be
  used to afford a much higher one? This is the whole point of the Phase 2
  flight and it cannot be answered from a bench.
- **S.q3** — Do game-pacing times scale (Froude) or stay put? Shield regen, vent
  cycles, wave intermissions, combo window.
- **S.q4** — Are `hull`/`armor`/`damage` physical or abstract currency? If
  abstract they do not scale, and the whole damage model is untouched.
- **S.q6** — The menu tower: rescale it, or redesign it for the new aircraft?
- **S.q7** — Does the city get rescaled or redesigned? (§7.5)

---

## 9. WHAT EXISTS TODAY, FOR THE FRESH SESSION

- **The scale work lives on branch `full-scale`.** `master` is untouched and
  green. **Discarding this whole direction is `git branch -D full-scale`** — that
  is why it is a branch, and it is the user's own instruction after the voxel
  attempt had to be squashed out of `master`'s history instead.
- **On `master`: board 23/23 green, tree clean, `PILOT_VERSION` 7.**
- **On `full-scale` (`68f9193`): only the Kestrel and the desert test map are
  scaled.** The rest of the game is at the old scale, so most of the board is
  expected to fail there and that is not a regression — it is Phase 3's inventory
  writing itself. `hover_check` and `terrain_check` DO pass and are the two worth
  keeping green through Phase 2.
- **The Phase 2 flight venue is `scenes/desert_map.tscn`**: 3 km of dunes, no
  combat, `free_flight` on so arming does not start a run. The aircraft is put
  down on the terrain by `TerrainEnvironment`.
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
