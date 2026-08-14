# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then
**GAMEPLAY-DESIGN.md's Iteration 16 (L)**, the new **Iteration 17 (E)** and the
log entries **v2.46–v2.49** at its tail.

---

## WHERE IT STANDS, 2026-08-14 — read this block first

**Branch `full-scale`. Board 23/23 green. Tree CLEAN. `PILOT_VERSION` 7
(untouched). `master` is untouched and 36 commits behind. Nothing pushed.**

**L13 PHASE 0 IS COMPLETE.** All three of its tasks are measured and the answers
are in `GAMEPLAY-DESIGN.md` v2.46 and v2.49. The short version:

- **The size-class roster's founding premise is TRUE.** Ten small units do not
  merely hurt a Roc, they delete it — 1.2 s of fire against a hovering target,
  where a Kestrel takes 5.6 s. Nothing downstream is blocked.
- **But the same measurement is the argument for Phase 1.** Every frame took
  exactly 13 hits; the whole spread is geometry. A 3 m airframe is a bigger
  target carrying an identical 100-point hull.
- **The exposure gap is 6.3x, not 115x**, because enemy aim jitter is uniform in
  radius so hit chance is linear in size rather than quadratic. **That number is
  the budget the component model has to hit, and it is why L.q1's frontal-area
  law was the wrong one** — 6x is reachable, 115x was not.
- **Nothing tunnels.** At every speed the roster can reach, against walls down to
  the 0.12 m curb trim. The margins are Kestrel 2.0x, Condor 8.0x, Roc 8.0x, and
  **the big frame is the SAFE one** — the opposite of the assumption the test was
  written on.
- **The city scales linearly** — flat cost per block from 20 blocks to 400 — so
  its size is a budget decision, not a structural limit.

**Iteration 17 (E) IS FULLY STEERED** (2026-08-15). All eight questions came
back. It is still paper only — nothing is built — but nothing is blocked either.
Read `E steering — ANSWERED` before touching it. The four that changed the design:

- **E.q7 DISSOLVED.** The exposure gap is not a target to author, it is an
  OUTPUT. Design an airframe from its role, its geometry gives it an exposure,
  its designer answers that with armour, the armour costs mass. **The 6.3x figure
  is now a measurement that tells you how much armour the fiction demands**, not
  a budget to hit.
- **E6's mechanism is peak DECELERATION, not kinetic energy** — so a crash loads
  every component at once instead of being a lump aimed at the hull pool.
- **Components are an OPT-IN TRAIT**, and the Phalanx is not at risk because its
  screen is a defence mechanic, not a damage model — nothing on it fails.
- **Components are NOT equal.** The user's ranking: rotors dominate, a damaged VTX
  is survivable because a stable aircraft can be flown and fired blind.

---

## WHAT THIS SESSION ADDED

Six commits on `full-scale` (`a519451` .. `996d81d`):

| commit | what |
|---|---|
| `a519451` | closed a user-config leak into every bench in the suite |
| `8253a91` | the feasibility bench (`swarm_bench.gd`) |
| `37efdda` | the scale yard's signs rebuilt as physical objects (L.q10) |
| `9aef668` | the big city, `city_load_bench`, `tunnel_check` |
| `996d81d` | Iteration 17 drafted on paper |
| (next) | phase 0 steering applied: sign legs removed, scaled city deleted |

**New things to run** (both documented in TESTING.md §2):

```
<godot> --headless -s scripts/tests/swarm_bench.gd      --path .
<godot> --headless -s scripts/tests/city_load_bench.gd  --path .
<godot> --headless -s scripts/tests/tunnel_check.gd     --path .
<godot>            --path . scenes/city_map.tscn         the big city, 12x15

```

---

## THE HUMAN'S FLIGHT LIST — things waiting for hands, not for code

Nothing below is blocked on the agent. All of it wants eyes.

1. ~~The scale yard's new signs.~~ **SIGNED OFF 2026-08-15** — *"works
   great!"*, *"the dual side of them is great."* The legs are removed on their
   call (*"the signs can float in space"*); `READ_RATIO` is untouched.
2. ~~The big city.~~ **CLOSED 2026-08-15** — *"the city is indeed big... this is
   good enough now. no need for more work."* One thing noticed and deliberately
   not fixed: *"the furniture seems to load in when it wants"*, which is the
   interior distance LOD popping at 140 m and is the mechanism that keeps a big
   city affordable at all.
3. ~~The scaled city.~~ **Deleted 2026-08-15** — the user rejected the premise,
   not the execution: the world stays at real human scale, so a 10.7x city is
   exactly the conversion pass V.q10 closed. The heavy frame's relationship to a
   city is *"an extreme flyby at the main route"*, which is a content idea at
   REAL scale rather than a bigger city.

---

## WHAT IS WAITING, in order

### 1. PHASE 1, in E10's order — unblocked, and start at the top

**Crash deceleration first.** It is the least exciting piece and the guard the
rest is unsafe without, it needs no components, and it is checkable the day it
lands. The mechanism is settled (E6 as corrected); the calibration is the
Kestrel's current crash behaviour, which is signed off and must not move.

Then the component registry as data with no new failure modes, then redundancy,
then located armour, then the `Lethality` rework.

**Two things are PINNED rather than scheduled:** repair priced as a resource
(E.q3, connects to P5.6's repair bill, which has never repaired anything in
particular) and magazine detonation (E.q6, pairs with the SAM and Sentinel).

### 2. THE ROTOR EXPERIMENT (E.q1) — low priority, high curiosity, cheap

Explicitly *"a very interesting direction to have fun with"* rather than a task.
**The good news is in the steering entry: the simulation does not need extending.**
`MotorModel.apply_thrust` is already positional, so a hexacopter is the same
physics with six entries. What is hard-coded is the LAYOUT — `MOTOR_COUNT` and
the three ±1 sign tables — across about six files. Estimate a day, low risk
because `hover_check` flies every roster frame. Two parts want hands:
`yaw_authority` needs re-tuning for a 3+3 spin split, and the motor audio's
four-emitter detune scheme was tuned by ear.

### 3. THEN PHASE 2, the pilot (L6.2, L10.2)

Anticipatory planning, a per-class manoeuvre planner behind one shared pilot, a
pilot competence benchmark, and a `PILOT_VERSION` bump.

### 4. AND ONE RE-MEASURE (L6.3), scheduled and not discovered

**It must land after Phase 1 and Phase 2, or it lands twice** — L7's risk 3.

---

## HOUSE RULES THAT ARE EASY TO MISS

- **COMMIT AS YOU GO — you do not need to ask.** Standing preference, confirmed
  2026-08-14: *"i really like the way you manage our project versioning, i want
  to maintain that."* Use the `commit-message` skill's nested format, commit each
  finished piece of verified work, **never push, never touch `master`**. If a
  generic session instruction says to commit only when asked, that is a default
  and this is the project's norm — raise the conflict rather than quietly obeying
  it.
- **No `Co-Authored-By` trailer.** The user purged it from history. Same rule:
  raise the conflict if a session instruction says otherwise.
- **Breaking a saved war is allowed and preferred** over slowing development.
- **Report back with the `report-back` skill's structure**, in PLAIN LANGUAGE.
- **GAMEPLAY-DESIGN.md is APPEND-ONLY** and is CRLF — append with
  `sed 's/$/\r/' file >> GAMEPLAY-DESIGN.md`.
- **Treat warnings as errors**, including the engine's leaked-ObjectDB warning at
  exit: two benches written this session leaked orphan nodes created just to read
  a default off them, and a bench that prints warnings teaches people to ignore
  warnings.
- **Never write to `user://` from a bench or check.**
- **THE ENGINE IS NOT A COMMITMENT** (user, 2026-08-15): *"we dont have to commit
  to the godot engine, we are using it now to have a base to design the game
  identity and see how it feels... we might even migrate to a different engine."*
  Build the things that survive a migration — the flight model's maths, the war
  layer's purity, the balance rulers, the design record — and do not design around
  engine-shaped limits. Measurements of engine behaviour are findings to carry
  forward, not constraints to obey.
- **BEFORE CALLING SOMETHING AN ENGINE LIMIT, CHECK WHOSE CONSTANT IT IS.** The
  agent described the 128-round projectile ceiling as "an engine limit wearing
  balance's clothes", meaning *a limit in the plumbing rather than the design*,
  and it was reasonably read as *a limit in Godot*. It is neither:
  `ProjectilePool.POOL_SIZE` is our own `const int = 128`, and raising it is a
  one-line edit bounded only by the ~330-unit CPU wall v2.46 measured. Pinned, not
  raised, per the user — but pinned as **ours**.
  - **This happened twice in two messages** (the pool, then enemy components), so
    it is a pattern rather than a slip. The engine-portability position is real
    and standing, and precisely because it is real it **must not become the
    answer to every constraint** — doing that hides the limits a new engine would
    not fix. Enemy components are bounded by how many balance cells a human will
    read, which no engine changes.

### The scars

**A CONSTANT THAT WAS CORRECT AT ONE SCALE IS A BUG ON A SIZE LADDER.** Four live
instances in five days: the overlay's Kestrel-ranged sliders, the wind's 35 m/s
saturation, the motor audio's `unit_size` and pitch band, and `CityLayout`'s
footprint law and street furniture. **The remaining un-audited places are the
HUD's range ticks, the reticle and the radar scale** — and note the pattern has
only ever bitten where something is compared against a per-FRAME quantity, so the
HUD is the obvious next place. (`MenuFloorFrame`'s metre-denominated mullion
spacing was a fifth, and is retired rather than fixed: nothing is built at a scale
that exposes it now the scaled city is gone.)

**Check what `user://` is overriding before believing any config experiment.**
Found live this session: `FlightController._ready` loaded
`user://damage_config.tres` outside the `load_user_overrides` guard, so every
bench in the suite inherited the human's saved damage tuning. It was harmless on
the day it was found, which is exactly why it was worth closing.

**Ask of every check "would this still pass if the feature were deleted?"** It
earned its keep three times this session: it caught a load bench measuring the
clock instead of the work, a city bench whose generator never ran, and it is why
`tunnel_check` asserts that something DOES tunnel at the absurd end.

### And one about diagnosis

**Measure; do not reason.** The first load instrument read 4.169 ms per tick at
every unit count and looked like a beautifully optimised game — it was measuring
Godot's real-time pacing. `Performance.TIME_PHYSICS_PROCESS` was not the fix
either. The tunnelling result inverted the assumption that prompted the test.
**Query the engine's actual defaults; print the actual numbers.**

---

## WHAT NEEDS THE HUMAN — do not attempt these

- Any flight-feel number. TWR, rates, PID gains, `motor_lag_tau`, rotor count.
- The audio mix by ear.
- Fog and look config.
- The menu tower redesign (L12), including `MenuFloorFrame`'s scale constants.
- Anything on `master`.

## THE MENU TOWER GAINED A CONCRETE CONSTRAINT (L12)

The user corrected what the scaled city was ever for, and it was never scale:
*"what i meant is something that is true to scale for the real world, but with
appertures (windows, passage ways) that allow something like the roc to pass
within, so that the menu would be feasable."*

**Every enterable opening is sized against a NAMED FRAME**, and which frame is a
property of the building. The default target is the **Kestrel** — *"openings that
need to at least allow the kestrel to pass through"* — with the Condor as the
stretch where a building wants to admit something heavier. That is a
`BuildingGenerator` / `MenuFloorFrame` parameter (`window_size` already exists at
3.0 x 2.4 m), not a world scale. A 1.2 m Condor wants about a 2 m clear opening.

## STILL OPEN AND DELIBERATELY UNANSWERED

- **V.q12** — TWR across the ladder. The user is content to leave it.
- **The Commander's fiction** — person or central computer hub (L.q9).
- **`continuous_cd`** — measured to fix every tunnelling case and deliberately
  left off, because the shipped configuration is safe at reachable speeds.
