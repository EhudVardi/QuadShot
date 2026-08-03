# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then the tail of
[GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md) — entries **v2.03–v2.14** are this
session's, and **Iteration 14 (A1–A7, A.q1–A.q6)** is the one that decides what
happens next.

**BEFORE WRITING ANY REPORT, read `.claude/skills/report-back/SKILL.md`.** The
user asked for it explicitly (2026-08-03): every report is Goal / Terms / What I
found / What's next, and the Terms section defines every coined or project word.
The reason matters more than the rule — working alone you invent vocabulary that
feels ordinary within minutes, and a report the user cannot parse cannot be
argued with, which costs you the pushback that is the most valuable thing they
give this project.

**HEAD when this was written: the v2.15 commit. Working tree clean.
`PILOT_VERSION` is 7. 19 headless checks, all passing.**

---

## WAITING ON THE HUMAN'S HANDS: the INGRESS (A6 / W.q7) — BUILT 2026-08-03

**The pilot now starts OUTSIDE the target area and flies their own approach.**
Read the v2.15 entry at the tail of GAMEPLAY-DESIGN.md; TESTING.md says how to
fly it. It is a FEEL change and the human's hands are the test, so nothing that
depends on how the approach plays should be started before they have flown one.

What shipped, in four lines: the drone is put down on the deck 140-195 m out on
`spec["approach"]["bearing_deg"]`, facing the target; `SIGHT_COVERAGE` and the
check that guarded it are deleted rather than kept beside it; `sortie_check` now
asserts the ingress against the egress line and the signal leash, on the spec's
bearing, at a range that provably varies; and the greybox ground went 200 m to
600 m so the approach is not flown over the void.

**Two things were deliberately NOT built, and both have the same reason.**
Detection-on-sight (firing `detected` when a garrison unit can see you) and the
`corridors`/`cover` half of the approach both need somewhere to hide. The
approach is currently flat empty ground, so a sight test would fire at a fixed
distance on every sortie and buy no counterplay at all — reserves ten seconds
earlier, nothing else. **Detection and cover are one feature**; they land with
P1.9's terrain, which is A6's own motivation (*"hills that allow a smart player
to... fly low to avoid SAM sites"*). Do not ship half of it.

### What to ask the human after they fly it

1. **Is 140-195 m the right band?** It is bounded below by the egress line and
   above by the FPV leash, so there is not much room, but the whole band can
   shift if the leash moves with it.
2. **Is the target legible from the ingress?** There is no waypoint marker on
   purpose. If they cannot find it, the answer is either a HUD marker or a
   brighter objective, and that is a design call.
3. **Does the layered garrison finally read as layers from the air?** That is the
   thing the clamp was destroying and the whole reason this was worth doing.

### Then, in order

**The aegis rework** (A2, A.q1 decided — it stays only where bombers are BASED
and flies outward, carrying a magazine), then **the Lance** (A5, A.q4 says after
the aegis, A.q6 still open), then **the Phalanx** (A7 — the heavy defender the
roster does not have, and the escalation anchor). **P1.9's terrain** has moved up
the list on its own merits: it is now blocking two named mechanics rather than
being a look-and-feel item.

---

## Sections 1-4 below are the older state, kept for the reasoning trail

---

## 0. Standing rules that cost real time to learn — do not rediscover them

1. **Compare cells WITHIN a single run, never across runs.** The ordering is the
   finding; the decimals move.
2. **A cell that reads "0%" is equally consistent with a tough enemy, a broken
   enemy, and an enemy that flew out of the level.** Four separate Falx bugs
   looked identical from the results table. **Every new type or mechanic gets a
   behaviour check the day it lands** — `falx`, `screamer`, `composition`,
   `heat`, `ammo`, `sortie`, `war_loop`.
3. **Never read an enemy's facing from its BODY basis.** A freshly spawned enemy
   has identity rotation and zero velocity. Read the heading (velocity).
4. **Any new bestiary type joins `ENEMIES_FOR_STAMP` (delivery_bench), `ENEMIES`
   (lethality_check) AND `WarManifest.ROSTER` the same day.** The third one is
   new and it is there because the falx and the screamer missed it for two weeks
   (v1.96) — `manifest_check` now asserts the two rosters against each other.
5. **Watch one cell instead of all of them.** `tools\watch_matchups.cmd screamer`.
   A filtered run is a LOOK — no artifact, no asserts.
6. **LOOK AT VISUAL WORK, do not reason about it.** Two traps in a screenshot
   rig: `force_draw()` photographs the PREVIOUS aim because a camera transform
   set this frame does not reach the rendering server until the frame flushes;
   and a node driving its own shader uniforms every physics tick overwrites
   whatever the rig set, so freeze it with `set_physics_process(false)`.
7. **Run the full check suite before each commit. Commit each item separately.**
   **No `Co-Authored-By` trailer.** Commit messages follow the user's nested
   format — invoke the `commit-message` skill. **The user authorised the agent to
   commit directly (2026-07-31)**, having previously required the message be
   handed over; the format is unchanged.
   Match checks by **exit code**, not by grepping for a tag — several print
   `[motor_damage]`, not `[motor_damage_check]`, and a tag-matching loop reports a
   passing check as failed.
8. **Any pilot behaviour change is a `PILOT_VERSION` bump**, costing a ~45 min
   re-measure. Batch behaviour edits and bump once.
9. **Feel judgements are the human's.** Pick a sensible default, say it is
   provisional, flag it. Never tune a roster number to make a bench cell read
   better.
10. **Anything that can STOP a weapon firing is a delivery input** and belongs in
    the config stamp. Learned twice now (v1.95) — see §3.

---

## 1. WHAT JUST LANDED: the war is playable

**`SortieComposer.compose()` had no caller outside its own tests.** It does now.

```
<godot> --path . scenes/sortie.tscn -- --node 8
```

A theater is generated, a node is composed into a `sortie_spec`, and
`SortieRunner` builds exactly what the spec describes — layered garrison,
objective structures, reserves that arrive because of **what you did**. Flatten
the hot-white structures and fly back out past 105 m. The result is priced back
into the war, the war ticks, and the state saves to `user://war.save`.

Four phases shipped, all covered by checks:

| phase | what |
|---|---|
| 1 (v1.96) | the falx and screamer join `WarManifest`; `gnats` → `gnat`; the escort rule enforced |
| 2 (v1.97) | `SortieRunner` + `ObjectiveAsset` + `scenes/sortie.tscn` + `sortie_check` |
| 3 (v1.98) | `WarSim.apply_sortie` + `WarSave` + `war_loop_check` |
| 4 (v1.99–v2.00) | `spec["pads"]` spent (W.q4 decided); `sortie_bench` (H9's sortie layer) |

**FLOWN BY HANDS 2026-07-31** (v1.99), node 8: *"was difficult as it should. no
heal so i had to fly a broken drone."* The zero-pad experience was P2.6's
difficulty knob working exactly as designed — a heavily garrisoned node earns no
pads — **and** a real gap, since nothing read `spec["pads"]` yet. Both were true;
the second is now fixed. Nothing in a composed sortie is balanced, and per H6 it
must not be tuned before it is measured.

---

## 2. WAITING ON THE HUMAN'S HANDS

| what | shipped at | where |
|---|---|---|
| **A composed sortie, flown** | node 8 = strike, node 0 = dogfight | `scenes/sortie.tscn` |
| Objective hull | 200 each, 3 per factory | `ObjectiveAsset.hull` |
| Blaster duty cycle | 30 bolts, 2.10 s vent | `CombatConfig` Heat |
| Flak magazine / missile rack | 24 / 6 | `CombatConfig` Magazines |
| Gates per sortie / charges | 3 decaying to 1 / 2 each | `WaveDirector.GATES_*` |
| Salvage drop rate | 35%, split 70/30 toward flak | `WaveDirector.SALVAGE_CHANCE` |
| Falx & screamer doctrine | see `WarManifest.DOCTRINE` | pacing, wholly a feel call |

Confirmed by play (2026-07-31): the arcade run is *"more fun now"* after v1.93's
retraction of the wave-clear re-arm, which is the change most likely to have
produced it — gates and kills are the only ways to re-arm.

---

## 3. THE DEBTS, and what moved

### Retired

- **The board's re-measure.** Done twice, green both times, pilot v7.
- **`jam_range` vs `missile_lock_range`.** Decided: the gap stays and IS the
  counterplay.
- **The Atlas's −0.67 "paper-vs-measured gap".** Diagnosed, reproduced
  bit-for-bit: it is **lock acquisition**, not durability. The Atlas spends 4%
  hull to the Kestrel's 9% and survives 76.7 s against 12.0 s — but fires **0.8
  missiles where the Kestrel fires 3**, at an identical 1.00 hit rate. The
  un-modeled factor is that a heavy frame pays for its stability in lock time,
  and `aim_quality` measures how well a frame holds a gun line, not how long it
  takes to earn a launch.

### Open

- **H7's 127-sortie debt is untouched** — the soak still reads median 127 at
  skill 0.9 and **zero wins at 0.3 and 0.6**. It is now *approachable* for the
  first time, because real sorties can be flown and priced, but closing it needs
  measured SDI from composed sorties (H9's sortie layer), not another look at
  the proxy.
- **The delivery bench does not reproduce, and it is mostly the TURRET**
  (v1.95b, narrowed v2.01). 34 of 47 factor cells came back bit-identical across
  two runs of the identical command; **all five movers over 0.09 are turret
  cells**, and the ORDERING inverted — `kestrel x turret [jink]` read 0.08 then
  0.36 against a `[steady]` of 0.40 then 0.22, i.e. "dodging helps fivefold" and
  "dodging hurts" from the same command. **Read the turret column's order as
  unproven.**

  **What v2.01 established, by re-reading the two archived logs (cost: zero):**

  1. **The threat's shot counts are bit-identical across both runs** — 50 for
     every turret cell, 38 for every raider cell, 15 for static. So the threat's
     cadence is not moving, and no explanation resting on *how many rounds were
     fired* survives. The 0.5 s vs 0.667 s float-boundary theory is dead.
  2. **The PILOT'S OWN gun shot count moves, which is the actual finding.**
     `kestrel x turret [jink]` fired 112 bolts in one run and 64 in the other;
     `[steady]` 113 then 96; `atlas x turret [auto]` 51 then 63. **A hit-test
     threshold cannot change how many shots the pilot took.** The drone flew a
     *different flight*, so this is trajectory divergence and never was scoring
     noise. Longer cells would not have fixed it.
  3. **Correction to v1.95b**: "every raider cell reproduced exactly" was wrong.
     `atlas x raider [steady]` moved 0.11 → 0.08 (gun 11/63 → 9/51). It sat under
     the 0.09 mover threshold, so *"all movers over 0.09 are turret cells"* still
     holds — but the stronger claim does not, and this is not a pure turret
     column.

  **Ruled out by reading the code**, so no one re-runs them: projectile hits
  impart **no impulse** (`projectile.gd` raycasts and calls `take_hit`, nothing
  else); `apply_hit_to_motors` is wired in `main.gd` and `sortie.gd` only, never
  in the bench; every element of the loop runs on `_physics_process` at a fixed
  240 Hz delta, so idle-frame rate cannot leak in; there is no RNG anywhere in
  the pilot; and the bench tears an arena down a **full frame before** it builds
  the next, so cross-cell body contamination is not available either.

  **The live candidate is a threshold INSIDE THE PILOT, not in the hit test.**
  `ReferencePilot.jink_hold_cone_deg` (14°) gates `_shot_lined_up` — while the
  gun line sits inside that cone the jink *stops* so the pilot can shoot. Forcing
  `jink_mode` to ALWAYS or NEVER does **not** bypass it. So an ε-level attitude
  difference flips whether the pilot is jinking or shooting on a given tick, and
  that decision changes both the trajectory and the shot count from there on —
  a divergence amplifier that operates in every mode, which is exactly the
  signature above. **Unproven.** The cheap test is to log the per-tick
  `_shot_lined_up` transitions for one turret cell across two processes and find
  the first tick they disagree.
- **Nobody has measured a human hand-aiming with the gun director OFF.** Until
  that exists every jammed gun cell is bot-bounded.
- **Nothing here is unexplained any more.** `ammo_check`'s intermittent failure
  RECURRED, was captured (*"1 gates laid inside scenery across 6 sorties"*), and
  was a **deferred free**: `queue_free()` takes until end of frame and the sweep
  lays six sorties inside one. The gates were always placed correctly; the check
  was wrong. Fixed and 8/8 green.

---

## 4. THE NEXT JOB: the war room (P1.8)

Agreed with the user 2026-08-01, after this inventory was taken.

**BUILT, same day. Iteration 13 (C1-C10) was proposed, steered (C.q1-C.q7) and
all five phases of C9 shipped — read it before anything below, which is the
reasoning it was written from.** The campaign is playable end to end with no
command line: menu tower -> WAR ROOM -> pick a node -> ENTER -> fly -> debrief ->
the tick plays out on the map. See v2.03-v2.10 for how it was arrived at, and
TESTING.md for how to run it.

**What that closed:** the death path (P5.4 — no respawn, the pilot leaves the
roster, the kills still dent), P1.q4's *exit without save* (which needed nothing
built), and P1.3's fog finally reaching a human. **THE NEXT JOB is the list
below, unchanged.**

### What is actually built, counted rather than remembered

| axis | built | designed | gap |
|---|---|---|---|
| **Enemy types** | 6 - raider, turret, gnat, aegis, falx, screamer | 7 | **Sentinel** |
| **Player frames** | 2 - Kestrel, Atlas | more later (P3) | - |
| **Player weapons** | 3 - blaster (heat), flak pod, missile rack | - | - |
| **Mission archetypes** | **2 flyable** - strike, dogfight | 7 composed | sead, strike_cap, decapitation, interdiction, raid |

**The headline: there is more enemy content than there are places to use it.**
`SLICE_ARCHETYPES` is `[strike, dogfight]`, so `SortieRunner` refuses five of the
seven archetypes the composer already generates correctly - **15 of 30 nodes in a
theater cannot be flown.** Half the map is scenery.

Seed 4242, for repro commands: dogfights are nodes **0, 1, 4, 6, 7, 9, 12, 15,
23, 24, 28**; strikes are **8, 11, 18, 19**; everything else is not slice-ready.
**Pass `--no-persist` or you fly whatever the saved war has become, not this
list.** Naming an archetype is not naming a node - see v2.02 for the flight that
cost.

### Why the war room, and why now

**Every number it needs already exists and is already computed.** `sortie.gd`
prints the entire briefing and debrief to the console today: archetype,
objective, layered garrison, reserves and their timings, pad count, node
strength, capture flag - then afterwards garrison before/after, the dent,
captured/degraded, the war tick, pilots left, the winner. `WarManifest.project()`
already produces the intel-fogged view an inspection card would show.
`WarSave` already does F4's portable file.

It is a text war room with no face. This is UI over systems that work, which is
the cheapest kind of big feature.

| P1.8 asks for | state |
|---|---|
| Theater map: hex nodes, ownership, front line, supply edges, weather, range rings | **data yes / screen no** |
| Node inspection: intel card (freshness-stamped), garrison estimate, forecast | **data yes / screen no** - `WarManifest.project()` |
| Pilot roster (F1) + hangar (P3 frames/loadouts) | roster NUMBER exists in `state["pilots"]`; no UI, no hangar |
| Sortie select -> briefing -> fly -> debrief -> war tick as animated map movement | briefing/fly/debrief exist as console text; **select is `--node` on the command line**; the animation does not exist |
| Save/exit anywhere, one portable file | **DONE** |

The genuinely new engineering is the hex map and the tick animation. The
briefing and debrief screens are largely reformatting text that already exists.

### Two things that are WAITING on it, deliberately

1. ~~**The death path.**~~ **CLOSED 2026-08-01 (v2.06), by the war room rather
   than by a plaster.** P5.4 decided it - *"you redeploy fresh from Home
   Airbase"* - and there is now a Home Airbase to redeploy from. `sortie.gd`'s
   arcade respawn is deleted: death ends the sortie, the pilot leaves the roster,
   the kills still dent (P2.q4), and the room takes the debrief. The user's
   *"lets not use plasters over something that eventually will be built. i have
   patience"* was the right call - the wait cost nothing and the fix is three
   lines shorter than any of the three interim patches offered.
2. **W.q8, the hold phase.** The user's design: clearing an objective starts a
   clock during which friendly forces move in and the enemy pushes to reclaim.
   It is the leading answer and **nothing is built against it**, partly because
   "allies move in and take control" is only legible once a map can show them
   doing it. Read W.q8 in full before touching the egress, the capture gate, the
   reserve budget or the death path - it touches all four.

### After the war room, in order

1. ~~**Open up the other five archetypes.**~~ **DONE 2026-08-01 (v2.11).** All
   seven fly; the flyable count on seed 4242 went 9 -> 15. The five cost one new
   firing site (`detected`) plus P1.5's HQ shield, which was enforced for the
   proxy and not for the player. **None of the five have been measured** — that
   is now job 2's problem, and it has more to chew on than it did before.
2. ~~**The long `sortie_bench` sweep at a realistic cap.**~~ **RUN 2026-08-03
   (v2.13):** 78 cells x 3 reps at a 300 s cap, all seven archetypes. **The SDI
   SATURATES** - 234 reps, zero completions at every depth - so the completion
   rate cannot see the curve at all. The signal is the DENT priced as a fraction
   of the node's strength: **54% cleared at depth 3 falling to 21% at depth 7**,
   then flat because `garrison_cap` is 40. `sortie_bench` now prints that as a
   `cleared` column. Read BALANCE.md's "The SDI saturates" section before acting
   on any of it - three caveats there decide what the numbers mean.
3. **The Sentinel**, closing the bestiary. Least urgent: six types is already
   more variety than two archetypes can show off.

### Still pinned

- **Iteration 11 — the transit gate.** Read T2 before writing any code.
- **The stargate pool rework** (v1.91b) — blocked on a house-rule call about
  procedural noise. **Ask before picking one.**
- **R.q5**: "energy" as a resource distinct from the blaster's heat is a later
  conversation, deliberately not designed.

---

## 5. Recently landed, for context

| entry | what |
|---|---|
| v1.98 | the loop home: flown sorties dent the war, and it saves |
| v1.97 | the bridge: a composed sortie becomes a fight you can fly |
| v1.96 | the war learns the falx and the screamer; one type id |
| v1.95b | the delivery bench does not reproduce, and it is the turret |
| v1.95 | the board re-measured green; the Atlas diagnosed; the stamp fixed |
| v1.94 | Iteration 12 proposed and part-steered |
| v2.02 | the hold question (W.q8) raised; the escort guard deleted; death left unplastered |
| v2.01 | an outside audit, verified not accepted: three checks that could not fail, two campaign-destroyers |
| v2.00 | the sortie layer: difficulty MEASURED for the first time |
| v1.99 | the pads are spent (W.q4); the ammo_check flake diagnosed as a deferred free |
| v1.93 | the wave-clear re-arm retracted; solid gates; salvage beacons |
