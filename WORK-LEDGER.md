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
   any work.
3. **Do the task. Commit the work.**
4. **Set it to `DONE`, write the one-line finding, commit.**
5. **Move to the next task.** Do not skip ahead, do not batch.
6. **If a task is blocked or wrong-headed**, set it `SKIPPED`, write one line
   saying why, commit, and go to the next one.

**Never leave the tree dirty between tasks.** Work on `master` — branches only
when the human explicitly asks (2026-08-15 ruling).

## Status

| # | task | status | finding |
|---|---|---|---|
| 1 | Hit separation (E4.3) — a round straddles a small frame, takes one part of a big one | DONE | `hit_footprint_m` 0.25 m, frame-independent BY DESIGN — kestrel/atlas touch 3 rotors (79% on the worst), condor/roc touch 1 (100%), hexa touches 4 (51%); damage conserved at 0.2400 on every frame. Also added `tools/board.sh`: a `for` loop can never match a permission allowlist, one script can |
| 2 | `separation_check` — the guard for task 1 | DONE | board now 25; the trap named in the file is that "a hit damages the right component" passes on the OLD code too — only a comparison across frame sizes distinguishes them; 3 mutations run, each failing a different sentence |
| 3 | Per-component armour as data (E4.2), all zeros so nothing moves | DONE | `FrameConfig.component_armor`, flat, applied in the single `_damage_component` chokepoint so no future path can bypass it; empty everywhere so zero is an exact no-op (0.2400 to 4 dp). **Found an interaction task 4 must reckon with:** separation splits a round into one big share plus small ones, and flat plating eats the small ones entirely — so armour is worth MORE on a small tightly-packed frame, the opposite of where E4.2 expects it carried |
| 4 | Author armour onto the heavy frames from role, provisional | DONE | Rotor plating, all PROVISIONAL, denominated in raider bolts (a bolt strips 0.048 at severity 0.6): roc 0.024 medium (E.q7's worked example verbatim), condor 0.012 light, atlas 0.006 a token, kestrel/hexa nothing with the absence authored. **The ledger's trap is real and runs BOTH WAYS**: per ROUND a point of plating is worth 2.71x more on a 0.28 m frame (it eats separation's small shares whole), but per FIGHT it inverts — the Roc's 0.024 saves 8.8x what the Atlas's 0.006 does, because it is hit 6x as often. E4.2's assumption holds, it needed the right denominator. `armor_bench` is the standing witness; `separation_check` gained claim 5 (2 mutations). **The Condor is now the roster's most rotor-fragile frame in a fight** (1.336 lost per 100 bolts fired vs Kestrel 0.418, Roc 1.248) — reported, not tuned. Plating costs no mass yet, which leaves E.q7's loop open |
| 5 | **Plating costs mass** — close E.q7's loop with the human's own shell model | DONE | Dry mass stays authored, plate mass is DERIVED on top, and TWR droops by itself because the thrust budget is bought with the dry airframe (roc 12.0 -> 11.75). One anchored constant: armour 1.0 = 50 mm of steel = 392.5 kg/m2. **The physics PAYS for E4.2 rather than obeying it** — plate mass goes as area (S²) and airframe mass as volume (S³), so the same 0.024 plate costs the Kestrel 14.3% of its dry mass and the Roc 2.1%: the big frame carries armour 6.7x more cheaply. **Unplanned finding: the hexa pays 21.4% for the same protection** (six plates, not four) — E4.1's redundancy and E4.2's armour compete for one mass budget, which neither section says. Also caught `board.sh` never being able to read `lethality`'s verdict at all |
| 6 | The collision bug: a building strike that sometimes registers nothing | DONE | **REPRODUCED, and it is a defect, not a trade-off — NOT fixed, because the fix changes what a crash costs and that is signed-off feel.** Cause: `body_entered` is an ENTER signal and a whole building is ONE `StaticBody3D`, so a scrape that never separates is priced once, at whatever the FIRST touch was worth. Measured: drift in at 4 m/s (free, 0.00 hull), hold contact, then fly into it at **60 m/s — one event, zero damage**. That is the "sometimes": what matters is how fast you ENTERED contact, not how hard you are hitting. Ruled out by checking: missing colliders (buildings do build `StaticBody3D` per slab), contact monitoring (on, 4 contacts), tunnelling (would need ~288 m/s at 240 Hz). **My shallow-graze prediction was WRONG and `graze_bench` corrected it** — friction scrubs speed along the wall too, so a graze costs ~1.4x pure geometry and only a 5° scrape was free at 60 m/s. Awaiting their ruling on the fix |
| 7 | HUD: a top-down plate of the airframe with equipment where it physically sits | TODO | |
| 8 | The pilot-in-the-loop instrument — the human as the reading | TODO | |
| 9 | `Lethality` Layer 1 rework (E8): expected hits-to-kill + expected FIRST FAILURE | TODO | |
| 10 | `lethality_check` plants shots at NAMED LOCATIONS (E8) | TODO | |
| 11 | Board + benches + handoff refresh | TODO | |

### PINNED, EXPLICITLY NOT THIS SESSION

**Iteration 18 — the macro scale-and-roster wishlist.** The human's words:
*"i want to have (later, not cutting this session) a session of creative
definition and construction of the full size scale of items in the game... i want
to see how the fighting in a fight scale of the condor/roc can be... i imagine
different turrets, missile sams, flak, i imagine land vehicles that some can shoot
me some not, humans shoot me. i need creativity."*

Also in scope when it runs: **player weapon upgrades**, and **sound as design**
rather than polish — *"the blaster sound for example right now sounds like a water
gun, so a roc cannon need to sound respectively powerful, i keep hearing in my head
the sound of the a10 warthouge large minigun."*

**The central question, and it is theirs:** the Kestrel is true to scale as a real
racing quad, and the scaled-down hobby playground *"is still a true asset of this
game"*. So does QuadShot become one continuous scale ladder, or keep two honest
registers — a models playground and a war? Everything else hangs off that, so it
goes first.

**FORMAT: GAMEPLAY-DESIGN.md's own iteration format, not the `brainstorming`
skill.** Brainstorming converges — one design, terminating in `writing-plans` —
and its own rules say to decompose a multi-subsystem request and pick one. This
session needs the opposite motion. The iteration format (a letter, numbered
sections, open questions answered by ID) is what P3.3's roster and P4.8's bestiary
came out of. Brainstorming is right LATER, for one bounded piece off the wishlist,
which is exactly what it was used for once here already
(`docs/superpowers/specs/2026-07-25-b3-interiors-design.md`, B3 interiors).

The full prompt was handed to the human in chat on 2026-08-15.

---

**Re-ordered 2026-08-15 after the human read task 4's report.** Tasks 5 to 8 are
theirs and did not exist before that message; the two `Lethality` tasks were 5
and 6 and are pushed back rather than dropped. E8's schedule constraint still
holds — the Layer 1 rework must land before L6.3's single re-measure or that
re-measure happens twice — and nothing has scheduled that re-measure yet, so
there is room.

---

## The tasks in full

### 1. Hit separation (E4.3)

**Design:** GAMEPLAY-DESIGN.md Iteration 17, **E4.3** — and the design doc calls
it *"the one that is free, and the model's central symmetry"*:

> A Kestrel's four rotors sit inside 0.28 m; a Roc's sit across 3.0 m. **The same
> geometry that makes the big frame easier to hit makes each hit less
> concentrated** — one round takes one component instead of straddling three. So
> exposure grows with size and concentration falls with size, and they move in
> the same ratio. That symmetry is not authored, it falls out of building the
> airframe at its true size, and it is the strongest argument that a located
> damage model is the RIGHT answer to L3.

**What changes:** `apply_hit_to_motors` currently picks exactly ONE nearest
component by dot product, whatever the airframe's size. That is the same
behaviour on a 0.28 m quad and a 3.0 m aircraft, so the symmetry E4.3 rests on
does not exist yet.

It becomes: a round has a **footprint in metres** (weapon property, deliberately
frame-independent — that is what creates the size effect), and every component
inside that footprint of the impact point shares the damage, weighted by
distance. Damage is conserved: a hit that straddles three does not do three
times as much.

**The acceptance test is the symmetry itself:** the same round on a Kestrel must
touch MORE components than on a Roc, measured, with no per-frame constant doing
the work.

**Keep single-rotor behaviour reachable** — a hit that lands squarely on one
component of a big frame must still take exactly that one, which is what makes
E7's *"if in two different runs i get the same engine hit — thats a lession"*
possible.

### 2. `separation_check`

Every new mechanic gets its check the day it lands. Ask *"would this still pass
if the feature were deleted?"* — and note the trap: an assertion that "a hit
damages at least one component" passes on the old code too. **The claim that
separates the two is a comparison across FRAME SIZES**, so it has to be two runs
differing only in the airframe.

Also hold: damage is conserved (total dealt is independent of how many parts it
straddles), and a crash is still the whole-frame event E6 requires.

### 3. Per-component armour as data (E4.2)

> Not a flat pool. A 500 kg airframe can carry plating over its power bus and its
> gyro; a 650 g quad carries nothing. **Armour that protects a NAMED thing is
> legible in a way a hull number never is** — "they got my power bus through the
> plating" is a sentence a pilot can learn from.

`AirframeComponents.Part` gains an `armor` value, and damage routed to a
component is reduced by it. **Ships as zero on every component of every frame**,
so the board is unchanged and this is a pure data addition. Task 4 authors the
values.

### 4. Author armour onto the heavy frames

**E.q7 governs this and it DISSOLVED the balance-target question:** armour
follows from VALUE and EXPOSURE, never from a ratio. The user's worked example is
the specification: *"say the Roc is heavy AND powerful, so i would equip it with
medium armor, because it may be more expensive so i would protect it more."*

**Author from role, then measure — do not tune toward a number.** A bad
measurement is information about the design, not a licence to fudge a cell green.

**Mark every value PROVISIONAL and put it on the human's flight list.** Armour
changes what survives, which is feel.

### 5. Plating costs mass — E.q7's loop, closed

**The human's ruling, given twice, and the second time with the model:**

> *"since we agreed that armor is simply something that reduces damage taken, we
> can say its equivalent to the thickness of the shell. so the mass is roughly
> thickness times the shell plan area may be be right"*

So armour value IS plate thickness, and mass is `density x thickness x area`.
E.q7's fiction becomes arithmetic: *"the engineer would have to reinforce it with
armor, which would then make it heavier, affecting the balance."*

**THE PHYSICS PAYS FOR E4.2 RATHER THAN JUST OBEYING IT.** Plate mass goes as
`t x S²` and airframe mass as `S³`, so at equal thickness a big frame spends a
SMALLER fraction of itself on the same armour. That is the square-cube law, and
it is the real reason *"a 500 kg airframe can carry plating; a 650 g quad carries
nothing"* is true instead of merely stated. Measure it and say so.

**MASS IS A FLIGHT-FEEL NUMBER AND IS NORMALLY OFF LIMITS.** This is authorised
and only this: derived plate mass, never a hand-edit of `FlightConfig.mass`.

- Dry mass stays the authored config value. Plate mass is DERIVED and added on
  top, so `.tres` files keep saying what the airframe weighs empty.
- **TWR must droop.** The thrust budget is bought with the dry airframe, so
  adding plate mass without adding thrust is what makes armour cost performance.
  If it does not droop, the loop is still open and the task is not done.
- Print the ladder before and after. `hover_check` flies every roster frame, so
  a frame that can no longer hover fails the board rather than surprising a pilot.

### 6. The collision bug

Reported from the Condor flight: *"there's a bug where sometimes i collid with
the buildings and it may not have registered, no damage at all. lets see if it
will happen again."*

**They deprioritised it and it is still worth an audit**, because it lands in the
crash path that E6 just rewrote. Cheap things to rule out, in order: is the free
band (`crash_damage_g` 73.5) simply eating a glancing touch, which would be
CORRECT behaviour; does the building's collision layer reach the drone's contact
monitor at all; and can a fast Condor TUNNEL through a wall between physics ticks,
which would explain "sometimes" better than anything else.

**Do not manufacture a fix for a bug not reproduced.** Report what the path can
and cannot drop, and give them a route that would reproduce it deliberately.

### 7. HUD — a top-down plate of the airframe

The human's design, quoted so it is not paraphrased away:

> *"have a top image of our craft (a projection of the craft from top to bottom)
> with equipment shown and what is mounted and where. so rotors health can then
> located where its physically is in the image, the vtx can located somewhere
> reasonable on the craft, and more equipment such as weapons, armour, etc."*
>
> *"for rotors a simple circle that use the color hue to express the rotor state,
> for vtx it can show some shap that express 'transmitting' using the color hue.
> each gauge should have the value of it printed as characters, inside the shape
> or next to it."*

**`AirframeComponents` was built for exactly this and nobody has used it yet.**
Every part already carries a `position` in body space and a `health`, so the plate
is a projection of data that exists — not a new bookkeeping system. Read mounts
from the registry, never re-author them, or the hexa breaks the widget again
(that was scar instance five).

### 8. The pilot-in-the-loop instrument

> *"i want to create an instrument that will put ME as the pilot of a reading you
> can run and test or recognize patterns, etc. you tell me the situation, what you
> want me to do, and then read the result and compare to your assertions. it would
> bring you a new source of results to argue on. after all, the player is here to
> be served."*

**The precedent is `aim_drill.tscn` (H.q4) and this generalises it.** That one
puts the human on the bot aim bench's exact ruler and writes deviation data to
`user://blackbox/aim_drill_*.json`. What is being asked for is the same shape for
ANY question: a stated situation, a stated task, a recorded run, and a comparison
against what the agent predicted.

The thing that makes it an instrument rather than a demo is the **prediction
written down BEFORE the human flies**, so the comparison can embarrass it.

### 9. `Lethality` Layer 1 rework (E8)

A component model breaks Layer 1's assumption that "hits to kill" is one number.
The proposal, from E8:

- keep a scalar **expected** hits-to-kill, computed under the hit-location
  distribution, so every existing band still has something to compare against;
- gain a second output that matters more for feel: **expected FIRST FAILURE** —
  which component goes first, and after how many hits. *"That is the number a
  pilot experiences, and nothing in the instrument reports it today."*

### 10. `lethality_check` at named locations

E8 again: *"`lethality_check` must be extended to plant shots at NAMED LOCATIONS
rather than into an undifferentiated pool, or Layer 1's new arithmetic has no
witness."*

### 11. Board, benches, handoff

- The 25-check board, all green.
- `swarm_bench`, `city_load_bench`, `tunnel_check` PASS.
- `--headless --import` clean; boot every scene touched. Warnings are errors.
- Fold every finding into `HANDOFF-NEXT.md` and delete this file.

**`board.sh` COULD NOT READ `lethality`'S VERDICT AND NOBODY NOTICED.** Its grep
was anchored (`PASS$`) and that check signs off with *"PASS - calculator matches
Health.take on every cell"*, so every full board run reported NO VERDICT. The
first occurrence was blamed on two Godot processes overlapping — a guess, stated
as a cause, and wrong. It reproduced on a board running completely alone, and
testing the grep against the check's saved output took one command and settled it.

**The lesson is the project's own and it was ignored for an hour: measure, do not
reason.** The harness failed SAFE, which is the only reason it surfaced at all —
a verdict it cannot read counts as not-green. An anchored grep that had instead
matched too much would have reported a broken check as passing, forever.
