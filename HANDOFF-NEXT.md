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

**Iteration 17 (E) is drafted and AWAITING STEERING.** Sections E1–E10, open
questions E.q1–E.q8. It is paper only; nothing is built.

---

## WHAT THIS SESSION ADDED

Six commits on `full-scale` (`a519451` .. `996d81d`):

| commit | what |
|---|---|
| `a519451` | closed a user-config leak into every bench in the suite |
| `8253a91` | the feasibility bench (`swarm_bench.gd`) |
| `37efdda` | the scale yard's signs rebuilt as physical objects (L.q10) |
| `9aef668` | the big city, the scaled city, `city_load_bench`, `tunnel_check` |
| `996d81d` | Iteration 17 drafted on paper |

**New things to run** (both documented in TESTING.md §2):

```
<godot> --headless -s scripts/tests/swarm_bench.gd      --path .
<godot> --headless -s scripts/tests/city_load_bench.gd  --path .
<godot> --headless -s scripts/tests/tunnel_check.gd     --path .
<godot>            --path . scenes/city_map.tscn         the big city, 12x15
<godot>            --path . scenes/scaled_city_map.tscn  the city at 10.7x
```

---

## THE HUMAN'S FLIGHT LIST — things waiting for hands, not for code

Nothing below is blocked on the agent. All of it wants eyes.

1. **The scale yard's new signs.** `<godot> --path . scenes/scale_map.tscn`.
   They no longer turn to face you and no longer disappear when close; each is a
   plate on posts, sized by the distance it is meant to be read from. Verified by
   screenshot from thirteen vantage points, but the verdict is theirs. The knob
   if it is wrong is one number: `ScaleYard.READ_RATIO`.
2. **The big city.** `<godot> --path . scenes/city_map.tscn` — 180 blocks,
   550 x 750 m. One observation to judge rather than a defect: the shared
   `default_look_config.tres` carries `fog_density = 0.006`, tuned when the city
   was 260 m deep, so from altitude the far half reads as haze. Down an avenue at
   street level it looks right.
3. **The scaled city.** `<godot> --path . scenes/scaled_city_map.tscn`, keys
   1/2/3. **Its facades are visibly wrong up close and the cause is known**:
   `MenuFloorFrame`'s wall, mullion and scaffold spacing are in metres and do not
   scale, so a 350 m building is tiled with human-scale window detail. That file
   is the menu tower's and was deliberately left alone.

---

## WHAT IS WAITING, in order

### 1. STEER ITERATION 17 (E) — the blocker

L13's phase 1 cannot start until E.q1–E.q8 come back. **E.q1 (does the heavy
frame get more than four rotors) and E.q7 (is the exposure target parity or
deliberate asymmetry) are the two that decide the shape of everything else.**

### 2. THEN PHASE 1, in E10's order

Crash energy first — it is the least exciting piece and the guard the rest is
unsafe without.

### 3. THEN PHASE 2, the pilot (L6.2, L10.2)

Anticipatory planning, a per-class manoeuvre planner behind one shared pilot, a
pilot competence benchmark, and a `PILOT_VERSION` bump.

### 4. THEN ONE RE-MEASURE (L6.3), scheduled and not discovered

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

### The scars, now five of the same shape

**A CONSTANT THAT WAS CORRECT AT ONE SCALE IS A BUG ON A SIZE LADDER.** Five
instances in five days: the overlay's Kestrel-ranged sliders, the wind's 35 m/s
saturation, the motor audio's `unit_size` and pitch band, `CityLayout`'s
footprint law and street furniture, and `MenuFloorFrame`'s mullion spacing (found,
not fixed). **The remaining un-audited places are the HUD's range ticks, the
reticle and the radar scale.**

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

## STILL OPEN AND DELIBERATELY UNANSWERED

- **V.q12** — TWR across the ladder. The user is content to leave it.
- **The Commander's fiction** — person or central computer hub (L.q9).
- **`continuous_cd`** — measured to fix every tunnelling case and deliberately
  left off, because the shipped configuration is safe at reachable speeds.
