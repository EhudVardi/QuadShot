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
| 2 | `separation_check` — the guard for task 1 | WIP | |
| 3 | Per-component armour as data (E4.2), all zeros so nothing moves | TODO | |
| 4 | Author armour onto the heavy frames from role, provisional | TODO | |
| 5 | `Lethality` Layer 1 rework (E8): expected hits-to-kill + expected FIRST FAILURE | TODO | |
| 6 | `lethality_check` plants shots at NAMED LOCATIONS (E8) | TODO | |
| 7 | Board + benches + handoff refresh | TODO | |

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

### 5. `Lethality` Layer 1 rework (E8)

A component model breaks Layer 1's assumption that "hits to kill" is one number.
The proposal, from E8:

- keep a scalar **expected** hits-to-kill, computed under the hit-location
  distribution, so every existing band still has something to compare against;
- gain a second output that matters more for feel: **expected FIRST FAILURE** —
  which component goes first, and after how many hits. *"That is the number a
  pilot experiences, and nothing in the instrument reports it today."*

### 6. `lethality_check` at named locations

E8 again: *"`lethality_check` must be extended to plant shots at NAMED LOCATIONS
rather than into an undifferentiated pool, or Layer 1's new arithmetic has no
witness."*

### 7. Board, benches, handoff

- The 24-check board (25 if task 2 landed), all green.
- `swarm_bench`, `city_load_bench`, `tunnel_check` PASS.
- `--headless --import` clean; boot every scene touched. Warnings are errors.
- Fold every finding into `HANDOFF-NEXT.md` and delete this file.
