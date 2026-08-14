# WORK-LEDGER.md — the resumable unattended run

**This file exists so a session wall costs a paste and nothing else.**

A fresh session cannot see what a previous one was doing, and a usage limit can
end a session mid-task with no warning. The fix is not cleverness about tokens —
it is making the work **resumable**: every task is small enough to finish and
commit on its own, and this file records exactly where the run got to.

Delete this file when the run is over and its findings are folded into
`HANDOFF-NEXT.md`.

## THE PROTOCOL — follow it exactly

1. **Read this file first**, before any other doc. The first task whose status is
   not `DONE` or `SKIPPED` is your task.
2. **Set it to `WIP` and commit that one-line change immediately**, before doing
   any work. If a wall lands mid-task, the next session sees `WIP`, checks
   `git status` for partial work, and knows whether to continue or restart it.
3. **Do the task. Commit the work.** One task, one commit — or a few, if the task
   genuinely has separable parts.
4. **Set it to `DONE`, write the one-line finding, commit.**
5. **Move to the next task.** Do not skip ahead, do not batch, do not "just
   quickly also" anything.
6. **If a task is blocked or turns out to be wrong-headed**, set it `SKIPPED`,
   write one line saying why, commit, and go to the next one. Do not invent a
   substitute and do not stop the run.

**Never leave the tree dirty between tasks.** A clean tree is what makes a wall
harmless.

## Status

| # | task | status | finding |
|---|---|---|---|
| 1 | Crash damage as peak deceleration (E6, E10 step 1) | DONE | `v^2/(2*s*g)` with ONE frame-independent crush distance; Kestrel's free band and 28.667 m/s lethal speed both exact; the tick cannot supply a deceleration, so `s` had to be authored |
| 2 | `crash_check.gd` — the guard for task 1 | DONE | 4 claims, board now 24; 6 mutations run and one SURVIVED (main's stale-bearing clear was untested code) — fixed by planting the bearing an armour-absorbed hit really leaves; also found a live `user://` leak into every check that boots `main.tscn` |
| 3 | HUD scale audit: range ticks, reticle, radar (scar 3) | WIP | |
| 4 | Component registry as data, no new failure modes (E10 step 2) | TODO | |
| 5 | Derived hit location generalised beyond rotors (E.q2) | TODO | |
| 6 | HUD component pips extended (E.q5, player-side only) | TODO | |
| 7 | The hexa frame (E.q1) — 6 rotors, layout tables generalised | TODO | |
| 8 | Board + benches + handoff refresh | TODO | |

---

## The tasks in full

### 1. Crash damage as peak deceleration

**Design:** GAMEPLAY-DESIGN.md, Iteration 17 section E6, **as corrected by the
`E steering — ANSWERED` entry.** Read the correction, not just E6 — the draft
said kinetic energy and the user replaced it with acceleration, and the reason
matters: *"damage like trauma is caused by the abrupt acceleration, where all
parts feel a devestating force that shakes the integrity of the entire frame."*

**What changes:** `FlightController._on_body_entered` currently emits
`crashed.emit((_previous_velocity - linear_velocity).length())` — a delta-v,
which is blind to mass and blind to how abruptly the stop happened. It becomes
peak deceleration in g over the impact.

**Two properties the result must have, and they are the acceptance test:**

- **A crash loads EVERY component at once.** That is the whole content of the
  user's model and the thing that distinguishes it from an energy lump aimed at
  the hull pool. `crash_motor_scale` already frays all four rotors, so it had the
  right shape with the wrong driver underneath — keep the shape.
- **A heavy frame is NOT safer.** Peak deceleration does not care what you weigh:
  a Roc and a Kestrel stopping from the same speed over the same distance pull
  the same g. This is the anti-invulnerability clause and it is the reason the
  task is first.

**The calibration point, and it is a hard constraint:** the Kestrel's current
crash behaviour is signed off and must not move. Tune the new formula so the
Kestrel's typical crashes land where they land today, then let the other frames
fall where the physics puts them. **If the Kestrel's numbers move, the task is
wrong**, however good the formula looks.

### 2. `crash_check.gd`

Every new mechanic gets its check the day it lands. Ask of every stage *"would
this still pass if the feature were deleted?"*

Claims worth holding, each as two runs differing in one thing:

- The same speed into the same wall on two frames of different MASS produces
  comparable deceleration — mass is not a shield.
- A gentle landing and a wall at speed differ by orders of magnitude, and the
  gentle one stays under the damage threshold.
- A crash damages **all** components, not the nearest one — the opposite of a
  bullet, which is located. That contrast is the check's most valuable stage
  because it is the one a naive implementation gets wrong.
- Faster is worse, superlinearly.

Register it in TESTING.md and bump the board from 23 to 24.

### 3. HUD scale audit

**The standing scar, and a fifth instance is probably sitting there.** *A
constant that was correct for one airframe is a bug on a size ladder* has bitten
four times: the overlay's Kestrel-ranged sliders, the wind's 35 m/s saturation,
the motor audio's `unit_size` and pitch band, and `CityLayout`'s footprint law.
The named un-audited places are **the HUD's range ticks, the reticle and the
radar scale**.

**Measure before changing anything.** For each of the three, print what it
actually reads on a Kestrel, a Condor and a Roc — the tick spacing in metres, the
reticle's angular size, the radar's range in metres. A number that is identical
across all three, and that ought to scale with the frame's speed, reach or size,
is the bug. **A number that is correctly frame-independent is NOT a bug** — the
horizon line and the artificial horizon should not scale, and saying so is part
of the audit's output.

Report the audit even if it finds nothing. "Audited, three constants, all
correctly frame-independent" is a real result and closes the scar.

### 4. Component registry as data

E10 step 2. **No new failure modes in this task** — it is a refactor that makes
the existing components addressable, and the board must be unchanged at the end.

E3 lists eight components with four already built (four rotors, the VTX). Give
them a data description: an id, a position on the airframe, a health, and what
its loss costs. Rotors and the VTX adopt it without changing behaviour.

**The test that this task is honest: the 23-check board passes before and after,
and `motor_damage_check` and `repair_check` pass unmodified.** If either needed
editing, behaviour moved and this was not a refactor.

### 5. Derived hit location beyond rotors

E.q2, answered `derived`. `FlightController.apply_hit_to_motors` already picks
the damaged rotor by dot product against each rotor's position, and **it is
already count-agnostic and layout-agnostic**. Generalise it from "nearest rotor"
to "nearest component" over task 4's registry.

Keep the existing behaviour for rotors bit-identical — a hit that damaged rotor 2
before must damage rotor 2 after.

### 6. HUD component pips

E.q5, player-side only. **The user explicitly ruled OUT per-enemy damage
visuals** (no smoke from a wounded enemy — it costs the vastness), so this task
touches the player's HUD and nothing else.

`hud.gd` already draws four motor pips that empty and redden, plus a VTX input.
Extend that same widget over task 4's registry. **Do not build a new panel.**
Most damage is felt through the sticks and the feed; the pips are for what you
cannot feel.

### 7. The hexa frame — LOW PRIORITY, do only if 1–6 are DONE

E.q1. Explicitly *"a very interesting direction to have fun with"* rather than a
task, so it is last and it is optional.

**Build the hexa (6 rotors). Do NOT build the tri (3).** A tricopter cannot
cancel reaction torque by counter-rotation and needs a servo-tilted tail rotor —
that is a new control mechanism and a design job, not a table job. See the
`E steering round 2` entry.

`MotorModel.apply_thrust` is already positional, so the physics does not change.
What is hard-coded is the layout: `MOTOR_COUNT` and the three ±1 sign tables
(`X_SIGNS`, `Z_SIGNS`, `SPIN_DIRECTIONS`), read by the mixer in
`_run_rate_control`, plus `_apply_frame_geometry`, `MotorAudio`, and four display
consumers.

**Two parts want hands and must be left alone**: `yaw_authority` needs re-tuning
for a 3+3 spin split, and the motor audio's four-emitter detune scheme was tuned
by ear. **Ship the hexa flying with the quad's numbers and say plainly that both
want a human**, rather than guessing at either.

The quad frames must be bit-identical afterwards — `hover_check` flies every
roster frame and will catch a broken mixer immediately.

### 8. Board, benches, handoff

- The 23-check board (24 if task 2 landed), all green.
- `swarm_bench`, `city_load_bench`, `tunnel_check` all PASS.
- `--headless --import` clean; boot every scene touched. Warnings are errors.
- Fold every finding into `HANDOFF-NEXT.md` and delete this file.
