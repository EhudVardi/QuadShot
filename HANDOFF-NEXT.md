# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then the tail of
[GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md) (entries v1.85–v1.92) for how the
current state was arrived at.

**HEAD when this was written: `d7d1d86`. `PILOT_VERSION` is 7. 16 headless
checks, all passing.**

---

## 0. Standing rules that cost real time to learn — do not rediscover them

1. **Compare cells WITHIN a single run, never across runs.** The ordering is the
   finding; the decimals move. A jinking cell swung 2x between two runs of the
   same command.
2. **A cell that reads "0%" is equally consistent with a tough enemy, a broken
   enemy, and an enemy that flew out of the level.** Four separate Falx bugs
   looked identical from the results table. **Every new type or mechanic gets a
   behaviour check the day it lands** — see `falx_check`, `screamer_check`,
   `composition_check`, `heat_check`, `ammo_check`.
3. **Never read an enemy's facing from its BODY basis.** A freshly spawned enemy
   has identity rotation and zero velocity. Read the heading (velocity).
4. **Any new bestiary type joins `ENEMIES_FOR_STAMP` (delivery_bench) AND
   `ENEMIES` (lethality_check) the same day**, or its stats drift without
   invalidating the factors measured under them.
5. **Watch one cell instead of all of them.** Both benches take a name filter:
   `tools\watch_matchups.cmd screamer`. A filtered run is a LOOK — it writes no
   artifact and skips every assert.
6. **LOOK AT VISUAL WORK, do not reason about it.** Three separate defects in
   the last two days were invisible in code and obvious in a screenshot (the
   gate blooming to a white disc, `ripple_scale` read as radians, the Screamer's
   dish giving away its own cloak). Two throwaway rigs are worth rebuilding:
   park a camera on a subject in `dev_map` and save a PNG. **Two traps in that
   rig itself**: a camera transform set this frame does not reach the rendering
   server until the frame flushes, so `force_draw()` photographs the PREVIOUS
   aim; and a node that drives its own shader uniforms every physics tick will
   overwrite whatever the rig set, so freeze it with `set_physics_process(false)`.
7. **Run the full 16-check suite before each commit.** Commit each item
   separately. **No `Co-Authored-By` trailer.** Commit messages follow the user's
   nested format — invoke the `commit-message` skill.
8. **Any pilot behaviour change is a `PILOT_VERSION` bump**, which costs a full
   ~45 min re-measure. Batch behaviour edits and bump once.
9. **Feel judgements are the human's.** Pick a sensible default, say it is
   provisional, and flag it. Never tune a roster number to make a bench cell
   read better.

---

## 1. THE DEBT: the board owes a re-measure *(do this before any balance claim)*

**v1.91 changed the blaster and v1.92 changed the flak and the missile.** These
are not visual changes: the delivery bench and the duel harness fly the real
weapons, so every cell involving them now carries a duty cycle or a magazine.

- **`PILOT_VERSION` does NOT bump** — the pilot's brain is unchanged, the
  weapons under it are not.
- **No number measured before 2026-07-31 belongs in a table with one measured
  after it.**
- A filtered blaster LOOK after the heat change showed **no band moved**, and
  round counts dropping only where volume already exceeded a magazine
  (`Blaster x Screamer` 69 -> ~50 rounds). Suggestive, not measured: that is a
  cross-run comparison, which rule 1 forbids treating as a finding.
- **`tools\balance_report.cmd`, ~45 minutes.** Read [BALANCE.md](BALANCE.md)
  before acting on any of it.

---

## 2. WAITING ON THE HUMAN'S HANDS (nothing here can be settled by a bench)

Every number below is provisional and was chosen to be flyable, not correct.

| what | shipped at | where |
|---|---|---|
| Blaster duty cycle | 30 bolts, 2.10 s vent (~59%) | `CombatConfig` Heat |
| Flak magazine | 24 shells | `CombatConfig` Magazines |
| Missile rack | 6 | `CombatConfig` Magazines |
| Gates per sortie | 3 at sortie 1, decaying to 1 | `WaveDirector.GATES_*` |
| Charges per gate | 2 | `ResupplyGate.charges` |
| Salvage drop rate | 35%, split 70/30 toward flak | `WaveDirector.SALVAGE_CHANCE` |
| Screamer cloak | distortion 0.045, reveal 0.3 s, floor 0.15 | `cloak.gdshader`, `screamer.gd` |
| Screamer cloak dial | `cloak_strength` 0.8 | `default_enemy_screamer.tres` |
| Wave composition | see `WaveDirector.PLAN` | pacing, wholly a feel call |

Two specific questions worth answering while flying:

- **Does the wave-clear re-arm make the gates pointless?** R.q2 says ammo is a
  sortie resource and R.q3 says a wave clear refills it; together they move the
  unit of scarcity to the WAVE. That is probably the better game, but it costs
  P2.6's pad-poor knob most of its bite. If gates feel like scenery, this is why.
- **Does `Rapid Blaster` still feel like an upgrade?** It now buys rounds per
  second and spends them out of the same heat sink, so stacking it without
  `Heat Sinks` or `Vent Ports` buys a shorter burst.

---

## 3. OPEN AND NOT STARTED

### 3a. The stargate pool is not what the user aimed for *(v1.91b)*

*"its cool but not what i aimed for."* The gap is **structural, not tuning**, and
the reasoning is written into `resources/portal.gdshader`'s header next to the
code it would replace. Two differences:

1. **Polar UVs**, so detail wraps angularly around the disc. Concentric `sin()`
   rings alone read as a struck drum; the reference has angular churn.
2. **Two noise layers scrolling in opposite directions, the first displacing the
   second's UVs** — domain-warped noise. Periodic trigonometry cannot get there;
   the eye reads periodicity as machinery.

**The blocker is the house rule on assets.** Proper noise needs either a
procedurally generated `NoiseTexture2D` (no file on disk, probably acceptable —
**ask**) or a hash-based value-noise function written by hand. That choice is the
first decision of the rework, not a detail of it.

### 3b. Iteration 11 — the transit gate *(PINNED, and the user wants it)*

*"i understand its tricky, but it would bring something extremely unique to our
game."* Design and the user's own implementation references are in
GAMEPLAY-DESIGN Iteration 11 (T1, T2, T2b, T3). **Read T2 before writing any
code** — the hard parts are not the shader:

1. **The camera.** Rotating an FPV pilot's world 90 degrees in one frame is an
   assault. Instantaneous vs blended vs yaw-aligned-only is the fork that
   decides whether this ships at all.
2. **The rate loop.** 240 Hz off measured body rates: a discontinuous basis is a
   discontinuity in `_measured_rates` and an infinite D-term derivative. This
   needs an explicit teleport path that reseeds the loop's history, not a silent
   transform swap.
3. **Seeing through it** costs a second camera to a viewport texture. Affordable
   for one pair; not obviously for several.
4. **Projectiles, missiles mid-flight, and enemy awareness.** "No" is a fine
   answer to all three, but it has to be *decided* — a player will try to shoot
   through it in the first minute.

### 3c. Still open from earlier sessions

- **`jam_range` (55 m) is smaller than `missile_lock_range` (60 m)**, so a
  missile can lock from outside the Screamer's bubble entirely. The fix is one
  number and is **the user's call**.
- **Nobody has measured a human hand-aiming with the gun director OFF.** H.q4's
  drill was flown with it on. Until that exists, every jammed gun cell is
  bot-bounded.
- **The Atlas loses badly when outnumbered** (-0.67 vs the Kestrel against 3
  raiders) where P3.4's paper expects `0`. Sharpest paper-vs-measured gap on the
  board.
- **R.q5 is pinned by the user**: "energy" as a resource distinct from the
  blaster's charge meter is a later conversation, deliberately not designed yet.

---

## 4. Recently landed, for context

| entry | what |
|---|---|
| v1.92 | magazines, resupply gates, salvage drops, GlowText3D digits |
| v1.91 | blaster heat sink; Layer 1 learns the duty cycle |
| v1.90 | Screamer's antenna cloaks on a `cloak_strength` dial; exit gate is a pool |
| v1.89 | the Screamer cloaks (screen-space refraction driven by the jam level) |
| v1.87 | gnats in 6 of 9 waves |
| v1.86 | the flak pod stops riding the blaster's upgrade cards |
| v1.85 | run mode gets the roster — waves are composed, not counted |
