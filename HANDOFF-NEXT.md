# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then
**GAMEPLAY-DESIGN.md's Iteration 17 (E)** together with the two entries after it,
`E steering — ANSWERED` and `E steering round 2 — ANSWERED`. The steering
**corrects the draft in three places**; read the corrections, not just E6.

---

## WHERE IT STANDS, 2026-08-15 — read this block first

**Branch `full-scale`. Board 24/24 green. Tree CLEAN. `PILOT_VERSION` 7
(untouched). `master` is untouched. Nothing pushed.**

**ITERATION 17 (E) PHASE 1 IS BUILT.** It went from paper to flying in one
unattended run: crash deceleration, its check, the component registry, derived
hit location, the HUD pips, and the hexa. The eight-task ledger that drove it is
deleted; every finding is below.

What is built, in E10's own order:

| E10 step | what | state |
|---|---|---|
| 1. Crash energy (E6) | peak deceleration, `v² / (2·s·g)` | **BUILT**, `crash_check` guards it |
| 2. Component registry (E3) | `AirframeComponents`, 8 rows, 4 live | **BUILT**, pure refactor |
| 3. Redundancy (E4.1) | the hexa, 6 rotors, layout as data | **BUILT**, wants hands |
| 4. Located armour (E4.2/E4.3) | — | not started |
| 5. `Lethality` Layer 1 rework (E8) | — | not started |
| 6. The skill surface (E7) | — | not started |

---

## THE FIVE FINDINGS WORTH CARRYING FORWARD

**1. THE PHYSICS TICK CANNOT GIVE YOU A DECELERATION, so the stopping distance
had to be authored.** Godot's solver removes the whole velocity in one step
whatever the step is, so the raw per-tick figure is `v / dt` — a number that
triples if anyone raises the tick rate and says nothing about the airframe.
Measured across the ladder at 3 to 131 m/s: every frame reports its full impact
speed as a single-tick delta-v, and that delta-v is already the peak of the whole
event. So crash damage is `v² / (2·s·g)` with `s` a **frame-independent**
`crash_crush_m` of 0.1 m. Making `s` scale with airframe size is defensible on
its own terms and would hand the Roc a 10.7x discount on every wall it meets,
which is exactly the *"no amount of redundancy makes a Roc a battering ram"* E6
forbids.

**2. THE FIFTH SCAR INSTANCE WAS REAL, AND IT WAS NOT WHERE IT WAS EXPECTED.**
The HUD's range ticks, reticle and radar were audited and are **clean** — the
ticks are weapon-denominated and the weapon is frame-independent, the lock cone
is an angle, the 0.4 m muzzle standoff is measured from the per-frame
`fpv_offset` so it scales, and there is no radar (it is a war-sim node type). The
actual instance was one file over, in the **motor pip widget**: `for i: int in 4`
against a hand-authored 2×2 offset table, which would have drawn four pips for a
six-rotor frame and silently dropped two rotors. Fixed by projecting each pip
from its rotor's own mount.

**3. A MUTATION SURVIVED, AND FIXING THAT IS MOST OF WHAT `crash_check` IS
WORTH.** Deleting main's `last_hit_direction = Vector3.ZERO` passed the check
unchanged. A crash frays all rotors only because `apply_hit_to_motors` finds *no*
direction, so the guard is really a claim about that field being empty — and the
crash was being flown on a clean airframe where it is empty anyway. **A hit the
plating eats entirely never emits a damage event, so nothing clears the bearing
it set, and the Atlas ships with 3 armor**: that state is reachable in the game,
and it is now planted on the drone before the drop. Same family as the Phalanx's
tracking mutation: *fixing what a test fires on does not fix what it reads.*

**4. A LIVE `user://` LEAK INTO EVERY CHECK THAT BOOTS `main.tscn`, AND IT IS
STILL OPEN.** `main.gd:_ready` calls `load_from_user()` on the **shared**
`default_combat_config.tres`, and seven configs come in that way —
`frame_kestrel`, `damage_config`, `audio_config`, `enemy_raider`,
`input_bindings`, `weather_config`, `combat_config`. So `repair_check`,
`run_check` and `crash_check` all measure whatever the human last saved. It is
harmless *today* only because the saved files override unrelated fields and
everything else falls back to script defaults that currently match the `.tres` —
which is precisely the shape of the `damage_config` leak closed on 2026-08-14.
`crash_check` defends itself (a `CACHE_MODE_IGNORE` private ruler, and
`reset_to_defaults()` on main's combat and damage configs). **Closing it properly
is unclaimed work**: `Frames.build` solves this for the drone with
`load_user_overrides = false`, and `main.tscn` has no equivalent flag.

**5. MEASURE, DO NOT REASON — it paid three times in one run.** A probe that
built drones and hit them inside `_initialize` read "all four rotors destroyed"
on every bearing; `add_child` there defers `_ready`, so `_motors` was Nil and
every reading was an engine error printed as 0.0. A half-built impact-tracking
*window* for the crash law was abandoned when the probe showed first contact is
the peak in all 27 cases — and that a window would have *merged* two real impacts
into one cheaper one. And the 0.4 m muzzle standoff looked exactly like the fifth
scar instance until the numbers said it was clear on all four frames.

---

## THE HUMAN'S FLIGHT LIST — things waiting for hands, not for code

**1. THE HEXA.** `<godot> --path . -- --frame hexa`. Six rotors on a ring at 30°
off the nose, alternating 3+3. It is the **Kestrel in every respect except the
layout** — same 0.28 m, 0.65 kg, TWR 4.5, same rates — because a hexa that also
changed mass or TWR would be an interesting aircraft and a useless experiment.
**Three things are known wrong for it and were deliberately left alone:**

- `yaw_authority` 1.5 is a quad number. Yaw torque is the summed signed rotor
  output, so a 3+3 split sums to ±6 at full differential where a quad sums to
  ±4 — **it has roughly 1.5x the Kestrel's yaw authority from the identical
  constant**, and the direction to tune is down.
- The rate gains are a quad's. The mixer commands each rotor in proportion to
  its real moment arm, and a generated ring sits at √2 arm-lengths where the
  quad-X's corners sit at 1 along each axis. **Expect it twitchier than the
  Kestrel.**
- The motor audio's four-emitter detune was tuned by ear in v2.43/v2.45. The
  spacing rule generalises to six; whether six sources at the same per-pair beat
  rate *sound* right is an ear question and is not answered.

**2. CRASH FEEL.** The free band and the lethal speed are pinned to the old law
exactly — a landing is still free (a set-down measures 4 g on a Kestrel, 40 g on
a Roc, against a 73.5 g floor) and a crash still kills a full-health Kestrel at
28.667 m/s. **Between those two points the laws cannot agree**, because one is
linear in speed and the other quadratic: the largest disagreement in the
survivable band is −10.2 points at 20 m/s, and the new law is the *gentler* one
there. Above the lethal speed it is far harsher, which is the intent. **One
ladder consequence to feel: the Atlas's 190-point hull now dies to a 37.8 m/s
crash rather than a 43.7 m/s one**, because a quadratic reaches a bigger hull
sooner than a linear law does.

**3. `severity` 1.0.** E.q8 chose *"absolutely '1 = full subsystem damage'"* as
the design target, and it still ships at 0.6 in `default_damage_config.tres`
because nobody has flown 1.0. It is a ten-second change in the overlay's DAMAGE
section. **Bake it the moment it is flown and confirmed.**

**4. THE HUD PIPS.** Nothing visible changed — no new failure modes exist, so
there is nothing new to show, and the quad layout is pixel-identical to 0.000000
px. The widget wants eyes the day a hexa or a fifth component is flown.

---

## WHAT IS WAITING, in order

### 1. FINISH PHASE 1 — E10 steps 4 and 5

**Located armour and separation (E4.2, E4.3).** Armour over *named* components,
which is what makes "they got my power bus through the plating" a sentence a
pilot can learn from. The registry already carries mounts for power, gyro, weapon
mount and magazine as fractions of `body_m`; they are `built: false` and
`routed: false`, so a component starts doing something by flipping two flags.

**Then the `Lethality` Layer 1 rework (E8)**, and it has a schedule constraint:
**it must land before L6.3's single re-measure or that re-measure happens
twice.**

### 2. THE DELIVERY STAMP IS STALE, DELIBERATELY

`hexa` joined `Frames.ROSTER`, so `Frames.all_configs()` moved and the committed
delivery factors are no longer considered current. That is the correct outcome
and this file's own long-standing rule (*"a new frame joins the stamp the day it
lands"*) — the roster genuinely moved. It folds into the scheduled re-measure
rather than needing one of its own.

### 3. THEN PHASE 2, the pilot (L6.2, L10.2)

Anticipatory planning, a per-class manoeuvre planner behind one shared pilot, a
pilot competence benchmark, and a `PILOT_VERSION` bump.

### 4. AND ONE RE-MEASURE (L6.3)

**After Phase 1 and Phase 2, or it lands twice** — L7's risk 3.

### PINNED, not scheduled

Repair priced as a resource (E.q3, connects to P5.6's repair bill, which has
never repaired anything in particular); magazine detonation (E.q6, pairs with the
SAM and Sentinel); the **tri** (E.q1 round 2 — three rotors cannot cancel
reaction torque by counter-rotation, so it needs a servo-tilted tail rotor, which
is thrust VECTORING and a genuinely different control mechanism; `MotorModel._ring`
says so at the point someone would reach for it).

---

## HOUSE RULES THAT ARE EASY TO MISS

- **COMMIT AS YOU GO — you do not need to ask.** Standing preference. Use the
  `commit-message` skill's nested format, commit each finished piece of verified
  work, **never push, never touch `master`**. If a generic session instruction
  says to commit only when asked, that is a default and this is the project's
  norm — raise the conflict rather than quietly obeying it.
- **No `Co-Authored-By` trailer.** The user purged it from history. Same rule:
  raise the conflict if a session instruction says otherwise.
- **Breaking a saved war is allowed and preferred** over slowing development.
- **Report back with the `report-back` skill's structure**, in PLAIN LANGUAGE.
- **GAMEPLAY-DESIGN.md is APPEND-ONLY** and is CRLF.
- **Treat warnings as errors**, including the engine's leaked-ObjectDB warning at
  exit.
- **Never write to `user://` from a bench or check** — and see finding 4 above
  for the read side, which is still open.
- **Keep Bash calls simple.** The project now has a `.claude/settings.json`
  allowlisting the Godot headless invocations; **the exe path in those patterns
  is unquoted**, so invoke it without quotes. `git add`/`git commit` are
  deliberately not allowlisted (they mutate), so those prompts are expected. Do
  file work with the Read/Write/Edit tools, never `sed -i` or shell redirects.
- **THE ENGINE IS NOT A COMMITMENT** (user, 2026-08-15). Build the things that
  survive a migration — the flight model's maths, the war layer's purity, the
  balance rulers, the design record — and do not design around engine-shaped
  limits. **Before calling something an engine limit, check whose constant it
  is**: `ProjectilePool.POOL_SIZE` is our own `const int = 128`.

### The scars

**A CONSTANT THAT WAS CORRECT AT ONE SCALE IS A BUG ON A SIZE LADDER.** Now five
confirmed: the overlay's Kestrel-ranged sliders, the wind's 35 m/s saturation,
the motor audio's `unit_size` and pitch band, `CityLayout`'s footprint law, and
**the HUD's motor pip block**. A sixth was found and fixed in the same run: the
motor audio's beat-spread guard was hard-coded to three steps, and six rotors put
the extremes five steps apart. **The named HUD places are now audited clean** —
see the scale-audit block at the head of `reticle_solver.gd`, which also records
the condition under which each verdict expires.

**Check what `user://` is overriding before believing any config experiment.**
See finding 4 — still open on the `main.tscn` side.

**Ask of every check "would this still pass if the feature were deleted?"** Seven
mutations are on record in `crash_check` alone, and the one that mattered is the
one that *passed*.

**Measure; do not reason.** See finding 5.
