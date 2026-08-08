# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then the tail of
[GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md) — entries **v2.21 onward** are the most
recent session's, and **Iteration 14 (A1–A7, A.q1–A.q9)** is the one that decides
what happens next.

---

## WHERE IT STANDS, 2026-08-08 — read this block first

**Board 22/22 green. `PILOT_VERSION` 7 (untouched). EIGHT roster types. Tree
clean.**

**A.q10 IS BUILT AND IT IS THE WHOLE SESSION.** Read **v2.38** at the tail of
GAMEPLAY-DESIGN.md. The Phalanx's tracking arc is gone; its screen is now two
counter-rotating shells of slotted armour plus a stern vent that opens on a
window. The FORTRESS half (hull, mounts, size, battery) was signed off and was
not touched.

- **The pattern had to be DESIGNED, and the first design was refuted by its own
  first measurement.** A plain two-shell rotation does NOT punish camping — the
  open fraction is just the product of the two duty cycles, so a camper and an
  orbiter read the same 16%. What makes it work is that a pilot can SEE a slot
  and fly into it: locked to a shell's rotation, **42% open against a camper's
  17%**, and a single shell would hand the camper 38%.
- **The screen is a BARRIER, not a battery** — `shield_max` 300 → 0. The old arc
  spent its pool in about a second, which is half of why it never read.
- **A real bug the rework introduced and a rig caught**: the stern vent's
  collider pushed its own parent `CharacterBody3D` off station at 5 m/s (49.6 m
  in 5 s). Fixed with `add_collision_exception_with`; `phalanx_check` now guards
  it with a stage that could not have caught it before.
- **Layer 1 was 600 points short of every Phalanx fight** — it priced the hull
  and ignored the battery, which every round from every bearing meets first.
  Fixed in the model and the planted rig at once.
- **THE RE-MEASURE IS DONE and the delivery artifact did not move by a byte**
  (v2.39). All three layers PASS, pilot v7, `balance/delivery_factors.json`
  bit-identical *including the config stamp* — predicted before running, because
  no shield field has ever been in `DELIVERY_FIELDS_ENEMY` and the phalanx
  evasion cell forces the screen off. **The four un-modeled-factor flags are the
  same four as v2.37 and none is a Phalanx row.**
  - **The Atlas row validates the P4.4 reband**: `Atlas x Phalanx` paper `0` ->
    validated `0`, vs Kestrel **+0.08** — the heavy frame now does slightly
    better than the light one against this type, the opposite of the `--` the
    tracking arc earned.
  - **And the type got measurably more dangerous**, which nobody chose: damage
    spent on the pilot over a 10 s duel went **3.3 -> 16.7** (blaster) and
    **4.2 -> 9.2** (missile), because a screen that refuses more of your fire
    means you strip the battery slower and more guns stay alive. Still far
    gentler than Layer 1's 4.0 s paper kill. Cross-run comparison, so read the
    decimals softly.

**NOT FLOWN.** This is the top of the list, and the routes (three skills, in
order) are in TESTING.md's `phalanx_check` section.

### The one number the human has to judge

The fortress was signed off at 1300 points against a screen that *nominally* shut
65% of the time and in practice evaporated in about a second — so the fight they
approved was roughly 1300 points at near-full delivery. It is now 1300 points at
**17–42%** delivery. **On paper that is a 2.4x to 6x longer fight.** If it drags,
the shield fields are the ones to move and all nine are sliders under BESTIARY:
**gap widths set how OFTEN it is open, rates set how LONG each window lasts.**

---

## WHERE IT STOOD, 2026-08-07

**Board 22/22 green. `PILOT_VERSION` 7 (untouched). EIGHT roster types.
`balance/delivery_factors.json` re-measured with the new type in it, PASS, committed.**

Eight things landed. Read **v2.28–v2.35** at the tail of GAMEPLAY-DESIGN.md.

0. **THE PHALANX IS BUILT AND THEN REWORKED (A7, v2.34 + v2.35)**. Flown once;
   the user asked for a **flying fortress** and got a gunboat, so hull 140 ->
   700, mounts 3x30 -> 6x100, and the body is now 6 x 2 x 8 m. **The arc wraps
   past the beam** (250 deg, opening astern) and the slew dropped to 28 deg/s
   to keep that opening reachable — a pairing that was MEASURED, because arc
   290 at slew 45 never opens at all. **A real bug was fixed**: the screen only
   turned toward whatever had SHOT it, so it never looked at a pilot who had
   not yet fired. **NOT FLOWN in this form.**
   - **Two pre-existing model divergences surfaced with it**, neither about
     this type: the planted rig never modelled the blaster's heat vent (no
     target had ever outlasted the sink), and `Lethality.incoming` priced a
     six-gun body as a single turret (20 hits / 23.8 s to kill a Kestrel; now
     4.0 s). Both fixed. **`lethality_check` now takes ~8 min.**
   - **What it IS**: the roster's first heavy DEFENDER, closing the escalation
     hole where `HEAVY_TYPES` held a bomber that is never in defence and a jammer
     with no weapon. Its screen covers an ARC and tracks the threat it can SEE, so
     parking in one orbit slot stops your damage landing while every surviving
     mount shoots you anyway — no slot is both safe and useful. Mounts strip one
     at a time. Every design fork was the user's call.
   - ~~**Next action: the re-measure**~~ **DONE** (v2.37). All three layers PASS,
     pilot v7, artifact committed. The diff is four lines: the stamp and three new
     phalanx cells. **Nothing else moved** — every pre-existing cell came back
     bit-identical, the second time in one day Track 5 has paid out as a readable
     diff rather than as a claim.
   - **WHAT IT SAYS ABOUT THE TYPE, and both halves are it working:** evasion
     **0.99 / 0.96 / 1.00** — a station-keeping fortress does not dodge, so its
     defence is entirely the arc — and **all four duel rows read `win 0%`**,
     because 1300 points behind a shield shut 65% of the time does not fall inside
     the harness's 10 s cap. **No false finding is raised**: `model_kills` already
     requires the predicted ttk to fit the cap, so model and fight agree. Four
     cells ARE flagged for un-modeled factors and **none is a Phalanx row**
     (Blaster x Raider, Blaster x Falx, Missile x Screamer, Flak x Screamer — all
     pre-existing).
   - **THE READING THAT MATTERS FOR THE NEXT FLIGHT (H6 — recorded, not acted
     on):** in a real duel the Phalanx spent only **3.3 / 4.2 / 27.5 damage on the
     pilot over 10 s**, against Layer 1's prediction of a **4.0 s kill**. That gap
     is the 0.9 s spin-up plus six guns losing their line on a moving target. The
     worry that "4 s to kill a Kestrel is too sharp" is **probably unfounded** —
     against a pilot who keeps moving it is far gentler than paper. Fly it before
     touching `damage` or `fire_rate`.

1. **A.q8 CLOSED — the Lance's warning is continuous and proximity-driven**
   (v2.28). A looping alarm whose volume and beep-rate track `warning_level()`, a
   new public scalar that saturates at `blast_fuse_radius`, so full alarm means
   *inside the envelope that actually hurts you*. Silent 0–2.5 s, opens at −21 dB
   on the lock at 41.6 m, swells to −3 dB, saturates at 11.2 m. **The user flew
   it: *"i think its good now."***
2. **A.q9 CLOSED — the Lance bends its run by 6 deg/s** (v2.30), a maximum
   course-change RATE (never a blend), zero-able, and measured: it eats 5.6 m of a
   dodge, so the break you need goes 11 m → about 17 m. **NOT FLOWN.**
3. **THE AEGIS'S SHIELD WAS BROKEN AND IT IS THE BIGGEST FIND** (v2.29). Hull hits
   never delayed the screen's return, and the screen came back as a **0.05-point
   sliver** that absorbed every chip round forever — so **a blaster could not kill
   an aegis at all after the first four seconds**. One fix: any arriving hit holds
   the screen down. It now does exactly what the user described. **NOT FLOWN.**
4. **THE AEGIS IS 3x TOUGHER AND A SHADE FASTER** (v2.31, the user's call): hull
   80 → 240, speed 7 → 8, on their principle *"the less it can maneuver, the more
   hull it should carry."* **NOT FLOWN.**
5. **UNITS NO LONGER SPAWN INSIDE ONE ANOTHER** (v2.32). Rejection sampling in
   `SortieRunner._point_for`; closest pair across 90 sorties went 0.53 m → 6.18 m.
   The check for it **shipped unfailable at 16 bodies** and now runs at 48.
6. **THE LANCE'S EVASION CELLS WERE MEASURING A STOPWATCH** (v2.33). The bench's
   "immortal" Lance frees itself at 6.02 s of a 25 s cell, and the frozen shooter
   holds its trigger down regardless — so **76% of the cell was an empty arena**
   booked as missed shots. Blaster evasion 0.23 → **0.85**. It closes the
   `Blaster x Lance` anomaly this file had listed as unexplained.

### WAITING ON THE HUMAN'S HANDS — the standing reminder

The user asked to be reminded of this (2026-08-07): *"remind me about these
results later, i could not test them yet."* **Everything below is built, checked
and committed, and none of it has been judged by a human.** Signed-off items are
listed too, so the difference is unambiguous.

| what | verdict |
|---|---|
| **The Phalanx's ROTATING SCREEN + stern vent** (v2.38) | **UNFLOWN — the big one** |
| The Phalanx as a FORTRESS (v2.35) | SIGNED OFF: *"its an air fortress with many turrets that takes a lot of damage to take down"* |
| The aegis shield LOOP: missile, then stay on it, then it rearms (v2.29) | partly — they confirmed it "takes way more damage", not the rearm rhythm |
| Units no longer overlapping in a sortie (v2.32) | **UNFLOWN** — needs a composed sortie, not the dev room |
| Lance continuous warning (v2.28) | SIGNED OFF: *"i think its good now"* |
| Lance steering at 6 deg/s (v2.30) | SIGNED OFF: *"the lance is ok now"* |
| Aegis 3x hull, +1 speed (v2.31) | SIGNED OFF: *"a more worthy enemy"* |
| Phalanx v1 (v2.34) | flown, and the feedback became v2.35 |

**THE LANCE IS CLOSED.** They tuned it live, that tuning was never saved (the
overlay only persists on SAVE, and there is no `user://enemy_lance.tres`), and
after being told so they said *"the lance is ok now"* — so the shipped 6 deg/s
stands and the 6 -> 9 bump offered earlier is **withdrawn unless they raise it**.

**Routes**, all from `<godot> --path . scenes/dev_map.tscn`:

- **Phalanx** at **(-70, 16, 60)**, northwest, open sky. Commit to a fast orbit:
  the shield's opening should appear at about **2 s**, last about **3.5 s**, then
  close. Strip a gun (4 blaster bolts on one bearing) and feel the return fire
  drop. **If the window never appears the slew is too fast; if it is always open
  the arc is too narrow** — both are live sliders under BESTIARY.
- **Aegis** at **(70, 20, -90)**. Missile to break the screen, then *stay on it*
  with the blaster: the hull must keep falling. Stop for 5 s and the screen comes
  back.
- **Overlapping units** needs a composed sortie: `<godot> --path .
  scenes/sortie.tscn` or the war room.

**One number to watch on the Phalanx:** Layer 1 says six mounts kill a Kestrel in
**4.0 s**. That is the value most likely to be too sharp, and it is the first
thing to move if the fight feels unfair rather than hard.

### THE NEXT JOB, and the first item is a decision

1. ~~**THE RE-MEASURE**~~ **DONE.** All three layers PASS, pilot v7, artifact
   committed. **The diff is three lines** — the stamp, and the two lance cells the
   rig fix moved. **49 of 52 cells came back bit-identical**, which is Track 5's
   reproducibility finally paying out as a DIFF rather than as a claim. An earlier
   in-flight run was killed at 40 minutes when v2.33 surfaced; finishing a
   measurement already known to be wrong only produces a number somebody quotes
   later, and the stamp cannot catch it because the stamp covers CONFIGS and that
   was the RIG.
   - **THE INSTRUMENT'S OUTPUT, for the human and not for tuning (H6):**
     `Blaster x Lance` reads paper `0` -> predicted `++` -> validated `++`, win
     100%, ttk 1.4 s, zero damage taken. **Predicted and validated now AGREE**, so
     what is left is a paper-vs-measured gap — and Layer 1 names its cause in one
     line: **the Lance has hull 22 against a 25-damage bolt, so ONE blaster hit
     kills it** while it holds perfectly still for 1.15 s. P4.2's *"chip gun `0`,
     one honest window"* does not survive its own hull number in a 1v1 duel. It
     may still hold in a real sortie where that window is contested; that is the
     question, and it is the user's.
   - **The Aegis duel rows stay compromised** for v2.22's reason (the harness's
     intercept clock cannot resolve a bomber needing three passes inside its cap),
     so `Missile x Aegis` at 0% is **not** evidence about the hull retune.
2. **Fly the Phalanx and items 2–4 above.** Routes are in TESTING.md and in the
   report. The Phalanx specimen is in the dev room at **(-70, 16, 60)**.
3. ~~**Build the Phalanx**~~ **DONE**, and the re-measure it was batched with is
   the item above.
4. **THE LANCE'S DEFAULTS ARE STILL THE "a bit weak" ONES.** The user tuned it
   live and liked the result — *"i've played with its parameters, its a bit more
   dangerous"* — but the overlay only persists on SAVE and there is no
   `user://enemy_lance.tres`, so that tuning was lost. Their standing note is
   *"does not turn enough to be able to actually catch me"*, and the measured next
   step is `run_steer_deg_s` 6 -> 9, which takes the dodge it eats from 5.6 m to
   12.3 m. **Ask before moving it** — and batch it into the same re-measure.
5. **A.q6 IS SETTLED FOR NOW** (2026-08-07): *"for now lets make the lance target
   only me. when we'll start working on the allied side we'll start looking into
   the subject of target ranking."* The `_find_player()` seam stays, and
   `lance_check` still asserts its shape.
6. Then the standing queue below: P1.9 terrain, the bestiary screen, the
   target-ranking layer (blocked on allied assets, per item 5).

### Three things worth carrying forward

- **A LOAD-BEARING COMMENT WAS FALSE, and that is a different failure from an
  unfailable check.** `delivery_bench` asserted in prose that immortality stopped
  the Lance ending its own cell. It had been read at least twice by someone
  wondering about that exact cell, and each time it answered the question and
  stopped the enquiry. **A wrong comment is worse than no comment, because it is
  an authority.** Check claims, not just numbers.
- **The seventh unfailable check was found, and it was INHERITED** — `lance_check`
  proved commitment with a MAXIMUM distance, which is reached on the tick of the
  teleport. It read **56.09 m at every steering rate including 45 deg/s**, so a
  perfectly homing enemy passed it. v2.26 had fixed that stage's *trigger* and left
  its *measure*. Now on closest approach with a deliberately-set 25 m threshold.
- **The two-run comparison is the shape that works** for a mechanic whose output
  is not directly assertable (a sound, a trajectory): fly the SAME situation twice
  changing only the thing under test, and assert the difference. It caught a
  timer-driven warning and a dead steering knob on the same day.

---

## WHERE IT STOOD, 2026-08-06 (end of session)

**HEAD `be7e232`. Board 21/21 green. Tree clean. `PILOT_VERSION` 7 (untouched).
Seven roster types. Track 5 is CLOSED.**

### The five things that landed, and what each one costs you to know

1. **TRACK 5'S ROOT CAUSE WAS A CAMERA** (v2.23/v2.25). `FlightController`
   applied the FPV camera's 44-degree uptilt only in `_process` — the IDLE frame
   — so whether it existed on the first physics tick depended on machine load.
   **The weapon is a child of that camera and `ReferencePilot` aims by the gun's
   basis**, so the bot read a level gun, decided it was on target, and commanded
   nothing. Its first pitch command measured **0.00008 in one process and -3.84
   in another**.
   - **BOTH symptoms went**: 49 of 49 delivery cells now bit-identical across two
     processes, AND a cell reads the same alone as inside the full run (5 of 5,
     two byte-identical down to the gun count). v2.23 claimed the history effect
     survived; that was an inference stated without a re-test, corrected in v2.25.
   - **`balance/delivery_factors.json` is a stable measurement for the first
     time.** Standing rule 1 (compare within a run) stays as hygiene.
   - It was also a real one-frame defect in the GAME.
2. **THE AEGIS BOMB IS A BOMB** (v2.21). It leaves the rack, falls ~2 s, and
   detonates on the ground. The blast lives on the BOMB, so a bomber killed after
   release still lands it — **interception's deadline is the release, not the
   kill**. Release is a bombsight (predicted impact on the aim point), because a
   lead computed from level flight was 23 m wide on the re-attack passes.
   **FLOWN AND LIKED**: *"i kinda like the bomb dropping. they drop slow, giving
   a heavy feeling."* Deferred by the user: *"the explosion maybe should be
   bigger, but thats not for now."*
3. **THE LANCE SHIPPED AND WAS FLOWN** (v2.24/v2.26, A5). Telegraphs 1.15 s, then
   commits to a line it cannot steer, then detonates. A proximity fuse was added
   after the first flight and validated on the second: *"proximity now makes it
   more dangerous."*
4. **COMMITTED FLYERS NO LONGER WEDGE ON GEOMETRY** (v2.26). A bomber was
   measured pressing into a building at 0.0 m/s for the rest of the scene. Two
   fixes: an unstick (no travel for 0.8 s -> climb) and an egress that flies back
   the way it CAME rather than straight on into whatever the run was pointed at.
5. **THE WAR ROOM TAKES A CONTROLLER**: Cross launches, Circle backs out, Square
   cycles the airframe. An unrecognised pad button prints its index to the
   console — **if Cross still does nothing, that index is what is needed.**

### THE NEXT JOB: three items, in this order

1. **A.q8 — the Lance's warning should be CONTINUOUS and proximity-driven.**
   *"i feel that the lock should have more dramatic sound, a continous warning
   sound that increase the more the danger is close."* The current cue is a
   1.05 s one-shot at the start of the wind-up, so it goes quiet for the whole
   run — the stretch where the information is worth most. Needs a LOOPING emitter
   modulated by a live scalar; the only precedent in the project is the drone's
   own motor/wind emitters (`scripts/audio/`). **Drive it off
   `blast_fuse_radius`**, so the warning and the damage read the same number.
2. **A.q9 — let the Lance steer SLIGHTLY during its run.** *"maybe we can allow
   it to steer slightly toward the target to make it even more dangerous and
   interesting."* **Read v2.27 before building it**: this trades against the
   type's founding rule (P4.2's *"aimed at where you are, so being somewhere else
   is the answer"*), so it must be a CONFIG KNOB that is zero-able, and it should
   be a maximum course-change RATE rather than a blend toward the player — a rate
   cap punishes a small dodge while leaving a real break effective.
   **Tune it together with the fuse**: both narrow the same escape, and doing one
   blind after the other is how a type becomes undodgeable without anyone
   choosing that. `lance_check`'s commitment assertion is the line that has to
   survive; re-tune its threshold deliberately rather than relaxing it until it
   passes.
3. **The aegis is either FASTER or TOUGHER** — the user's call from the bomb-run
   flight, still unspent. Not done because `speed` and `hull` are both in the
   delivery config stamp, so either costs a full re-measure (~55 min).
   **Batch it with any other config tuning rather than paying that twice.**

### Smaller, known, and unfixed

- **Units spawn overlapping each other.** `SortieRunner._point_for` picks a
  uniformly random ring angle with no minimum separation, so aegis (and now
  Lance) bodies can sit inside one another. The user saw it. Contained fix:
  rejection-sample against already-placed units.
- **`Blaster x Lance` reads `++` and its paper band says `0`.** The user does not
  believe it and neither do I: the duel spawns the Lance 40 m away, so it spends
  the fight seeking and telegraphing. Its measured EVASION (0.23 blaster / 0.58
  flak / 1.00 missile) matches the user's own ordering exactly. The band is the
  rig, not the gun.
- **The aegis bombs empty ground** on purpose (A.q1 sends it out along your
  ingress toward your territory) — but there is nothing out there, because
  **allied assets do not exist**. Same hole blocks A.q6's target ranking.

### After that — the standing queue, unchanged

1. **P1.9's terrain.** Still the biggest unblocked item, and it now gates three
   named mechanics: detection-on-sight, the approach's corridors/cover, and
   A.q7's real answer. It is also what a moving GROUND unit would need.
2. **The Phalanx (A7)** — the heavy DEFENDER the roster still lacks. With the
   aegis out of defensive garrisons, escalation leans on a jammer with no weapon
   and the Lance, which is cheap rather than heavy.
3. **A BESTIARY game mode** — a menu-tower leaf showing every enemy, ally and
   weapon with their statistics. The first screen whose purpose is the designer's
   view. Cheap now that `WarView.card_lines` renders facts as text.
4. **The target-ranking layer + allied assets** (A.q6, answered and stubbed). The
   Lance is the third type to hard-code the player. Needs allied assets first.
5. **The Sentinel**, closing the seven-type bestiary.
6. **W.q8's hold phase**, **raid provenance**, **Iteration 11's transit gate**,
   and the **stargate pool rework** (blocked on a house-rule call about
   procedural noise — ask before picking one).

### How to price any of it

**BALANCE.md now has a costing section**, counted from the Lance rather than
estimated: 3 new content files, 5 one-line registrations, 1 mandatory behaviour
check, zero new code in existing systems, and ~12–16 new measurements. The one
thing that makes it multiplicative is a type whose damage the existing factors
cannot describe — that has happened once (the flak pod forced `splash`).

---

## WHERE IT STOOD EARLIER ON 2026-08-06 (kept for the reasoning trail)

**Board 21/21 green. `PILOT_VERSION` still 7. The Lance is the seventh roster
type. TRACK 5 IS CLOSED.**

1. **TRACK 5'S ROOT CAUSE WAS A CAMERA** (v2.23). `FlightController` applied the
   FPV camera's 44-degree uptilt only in `_process` — the IDLE frame — so whether
   it existed on the first physics tick depended on machine load. **The weapon is
   a child of that camera and `ReferencePilot` aims by the gun's basis**, so the
   bot read a level gun, concluded it was on target, and commanded nothing. Its
   first pitch command measured **0.00008 in one process and -3.84 in another**.
   - Fixed by applying the camera config in `_ready` too. **Proof: 49 of 49
     delivery cells bit-identical across two processes**, and the printed output
     of both 49-cell runs is byte-identical.
   - **`balance/delivery_factors.json` is a stable measurement for the first
     time.** The within-run comparison rule stays as hygiene, not as a crutch.
   - It was also a real one-frame defect in the GAME.
   - **The history effect went too** (v2.25, corrected). A cell now reads the
     same alone as it does inside the full 52-cell run — **5 of 5 cells, two of
     them byte-identical down to the pilot's gun count**. It was always one race:
     whether an idle frame fell before a cell's first physics tick depended on
     what the process had just been doing, which is why cell ORDER appeared to
     matter as well. v2.23 claimed it survived; that was an inference stated
     without a re-test.
   - **Standing rule 1 stays anyway** — compare cells WITHIN a run. It costs
     nothing and is still correct hygiene.
2. **THE LANCE SHIPPED** (v2.24, A5). Telegraphs for 1.15 s, then commits to a
   straight line it cannot steer. Killing it during the telegraph costs you no
   blast. **A.q6 is stubbed on the user's call** — it always targets the player —
   and `lance_check` asserts the SHAPE of that stub so the ranking layer has a
   named home. **Unflown and unbalanced**; the blaster's paper `0` measured `++`
   and that gap is H6's output, not a number to move.
3. **THE WAR ROOM TAKES A CONTROLLER** — Cross launches, Circle backs out, Square
   cycles the airframe, and an unrecognised pad button prints its index.
4. **BALANCE.md NOW PRICES A NEW TYPE** — counted from the Lance, with the
   checklist and the one thing that makes it multiplicative.

**Waiting on the human's hands:** the aegis bomb and its pacing, and the Lance's
telegraph. Routes for both are in the report and in the dev room.

**Next, in the user's own order: park Track 5 and BUILD** — the Phalanx (A7),
P1.9's terrain, the bestiary screen.

---

## WHERE IT STOOD, 2026-08-05 (LATE SESSION)

**HEAD is `2ed598c`. Board 20/20 green. `PILOT_VERSION` still 7. Tree clean.**

Three things landed, each its own commit, and the third changes what you can
trust.

1. **THE AEGIS BOMB IS A BOMB** (`664c862`, v2.21). It leaves the rack, falls for
   ~2 s and detonates on the ground. The blast moved out of the bomber and into
   the bomb, so **interception's deadline is the RELEASE, not the kill** — a
   bomber killed after letting go still lands that one. The release is a
   BOMBSIGHT (predicted impact on the aim point) rather than a lead distance,
   because a lead computed from level flight was 23 m wide on the re-attack
   passes; worst miss is now 0.8 m against a 9 m blast. New knob
   `EnemyConfig.bomb_fall_gravity_scale` — **the fall IS the telegraph**.
   **NOT FLOWN BY HANDS.**
2. **THE "FLIES A BIT TO THE CENTER" NOTE IS MEASURED, NOT TUNED** (v2.21b).
   Pass 1 crosses the arena; **passes 2 and 3 never come back inside 84 m**, at
   any spawn bearing, against an outer garrison ring at 74 m. Two of three bombs
   land where the player has no reason to be. **This is a pacing call and it is
   waiting on the human** — see the question at the end of v2.21b.
3. **TRACK 5 IS ANSWERED** (`2ed598c`, v2.22), and the answer has a cost.
   - **An isolated cell reproduces bit-for-bit across processes** (6720 ticks).
     **A multi-cell run does not**: the identical command measured
     `evade: kestrel x raider [jink]` at **0.29 and 0.00**.
   - The divergence is a **binary -0.0817 rad/s pitch impulse on a cell's first
     tick**, present or absent. The **first cell of a run never diverges**.
   - **`jink_hold_cone_deg` is refuted** — `jinking()` returns before reading it
     in both ALWAYS and NEVER, which are the very cells named as the movers.
   - **`balance/delivery_factors.json` is therefore not a stable measurement.**
     Standing rule 1 has been protecting the project from this all along.
   - The instrument is permanent: `delivery_bench -- --trace <dir>` and
     `-- --range A:B`. **The remaining unknown is narrow**: what applies the
     impulse. The arena teardown is ruled out by experiment.
   - **Also found: the predicted column had been blank on every harness run since
     v2.18**, because the falx reach buff staled the config stamp and nobody read
     the line that said so. Re-measured; it is live again (`156fdb3`).
   - **And the aegis rework killed the harness's intercept clock**: `_bombed` is
     unreachable inside a 10 s cap now that a bomber needs three passes, so the
     Aegis rows read the same 0% for a different reason. Recorded in the file;
     the rig-side fix (`payload = 1`) is deliberately NOT taken because it moves
     a published band.

---

## WHERE IT STOOD BEFORE THAT, 2026-08-05

**The board is 20 checks, all green.** `aegis_check` is the newest and it landed
with the rework it guards.

**Three things happened in the last session, in this order.**

1. **An outside audit was triaged and fixed** — seven findings, six confirmed
   exactly, one (F6) confirmed in mechanism and **wrong** in its stated symptom,
   plus an eighth found by following the audit's own safety advice. The request
   and the response are committed as `AUDIT-REQUEST-2026-08-04_.md` and
   `AUDIT-HANDOFF-2026-08-04.md`. Every fix is its own commit carrying the
   mutation that proves it. See v2.17.
   - The campaign-destroyer was real: a node ground below the cheapest unit's
     price offered a sortie with **nothing in it and no way to end it**, in 34 of
     40 seeds under ordinary play.
   - **The board was editing the human's real `profile.json`** — `runs` 158 → 159
     every time either of us ran it, for months. `wave_check` was the culprit,
     not `run_check`. Fixed at the source; `PlayerProfile.save()` now refuses to
     write headless.
2. **A.q7 was measured and then decided** (v2.18). Shots ARE fired on the
   approach and they miss by a median **1.5 m against a 0.28 m drone**; line of
   sight is innocent at 0–1% of gun-frames. **The falx already contests** — twice
   a raider's engagement per body, eight times a turret's — and still lands
   nothing. The user declined the one-line dispersion fix on identity grounds and
   chose **terrain (P1.9) plus a small falx reach buff** (`sight_range` 90 → 110).
3. **The aegis rework shipped** (v2.19): it carries a payload, flies a pass per
   bomb, survives them, and **goes home** when it is spent. It lives only where
   bombers are BASED and its run goes OUT along the corridor you came in on.

### FLOWN 2026-08-05 — both verdicts are in

- **The falx is a HIT.** *"its awesome! i like that enemy, it flys like a fast jet
  and i can see its projectiles flying towards me before it even clears out of the
  fog... I LIKE IT!"* A.q7 validated, and what they praise is exactly what the
  reach buff bought rather than lethality, which was left alone on purpose.
- **The aegis STRUCTURE works and its BOMB does not.** Three passes, the
  re-attack loop, the escape and its message all read correctly. But: *"it looked
  like it got an explosion right next to it... i didnt see anything dropped and
  explode on the ground."* That is exactly what the code does — `_drop_bomb`
  explodes at `route_end`, which carries `BOMB_RUN_HEIGHT` 26 m, so the blast
  goes off in mid-air at the bomber's own position and **nothing ever falls**.
  **This is the top of the next session's list.**
- Unresolved from the same flight: *"it seems to fly a bit to the center but still
  out of the actual fight."* Not settled by one sortie; look before tuning.

### STANDING RULE ADDED 2026-08-05 — read this before costing any change

**Breaking an in-progress saved war is ALLOWED and PREFERRED over slowing
development.** Bump `SAVE_VERSION`, change the state shape, delete the save. The
user starts a new war and enjoys doing it. Full wording in `CLAUDE.md` under
Conventions. The only carve-out: a test must still never destroy user data by
*accident* — deliberate schema breaks are progress, a crashed borrow is a bug.

### The next things, and none of them are started

1. **P1.9's terrain.** It now blocks three named mechanics rather than one:
   detection-on-sight, the approach's corridors/cover, and A.q7's real answer.
   This is the biggest unblocked item on the list.
2. **The Lance** (A5) — but **A.q6 is still open**: is it aimed at the player, or
   at something that is not necessarily the player? They are different enemies.
   **Ask before building.**
3. **The Phalanx** (A7) — and it is now the exposed edge rather than a nice-to-
   have. With the aegis out of defensive garrisons, the only heavy thing left in
   defence is a jammer with no weapon, so *"the war escalates"* still means
   *"the war gets foggier"* almost everywhere.
4. **A BESTIARY game mode** (new, the user's idea): a menu-tower leaf showing
   every enemy, ally and weapon with their statistics — *"a macro view of the
   current content."* The first screen whose purpose is the designer's view.
5. **Raid provenance** — a field on the bomber-raid structure that does not exist
   yet, so that killing a bomber weakens the node that LAUNCHED it. Cheapest to
   add the day raids are built.

### Two debts that did NOT move, and one that got worse

- **`sortie_bench` and `delivery_bench` still do not reproduce across processes**,
  so the sortie difficulty sweep remains unattributed. The audit's Track 5 was
  never reached; **the 15 `static var`s are still un-enumerated**. This is still
  the highest-value open question in the project.
- **`aim_jitter_deg` is now on the board as a GLOBAL difficulty knob** rather than
  a per-problem lever — the user's call, and the reasoning is worth keeping: a
  falx pilot must not aim better because you evade more.
- **The aegis change invalidates any measured factor involving it.**
  `delivery_bench`'s aegis cells are protected (they run with `loop_route`, which
  short-circuits the rework), but `matchup_harness`'s Aegis rows now fight a
  bomber that makes three passes before leaving. **Re-measure before trusting
  them.**

**BEFORE WRITING ANY REPORT, read `.claude/skills/report-back/SKILL.md`.** The
user asked for it explicitly (2026-08-03): every report is Goal / Terms / What I
found / What's next, and the Terms section defines every coined or project word.
The reason matters more than the rule — working alone you invent vocabulary that
feels ordinary within minutes, and a report the user cannot parse cannot be
argued with, which costs you the pushback that is the most valuable thing they
give this project.

**HEAD when this was written: the v2.19 commit. Working tree clean.
`PILOT_VERSION` is 7 (unchanged - nothing touched the pilot). 20 headless checks,
all passing.**

---

## FLOWN AND VALIDATED: the INGRESS (A6 / W.q7) — BUILT 2026-08-03, flown 2026-08-04

**The user flew it: *"i did, and its awesome, and the true way to go."*** A6 is
settled. Two things came back with the verdict, and the second is now the most
interesting open question in the project:

1. **The 140-195 m band is not perceptible** (*"i didnt feel any real difference...
   its either or i think"*). Nothing changed on that yet - the band is bounded
   below by the egress line and above by the signal leash, so there is little room
   anyway.
2. **THE APPROACH IS UNCONTESTED, AND IT IS NOT A PLACEMENT PROBLEM.** *"on both
   cases the enemy did not attack me until i engaged."* The obvious hypothesis - a
   ring of three bodies does not cover your arrival bearing - was **measured and
   refuted**: walking the real ingress line for all 30 nodes of seed 4242, **0 of
   30 fail to have the pilot in sight before the centre**, and the pilot flies a
   mean of only **49 m unseen**. The gap is between SEEING and REACHING: a raider
   is **14 m/s** with an **18 m** preferred range, a turret is **0 m/s** with 45 m
   of sight, and a quad on an ingress run beats both. Full reasoning, the
   confidence of each claim, and the one cheap test that settles it are in
   GAMEPLAY-DESIGN v2.16. **Read it before touching the roster** - it is the same
   hole A7 named, seen from the other end, and the falx may already be the answer.

---

## The build detail, kept for reference

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

### The three questions that were asked, and what came back

1. **Is 140-195 m the right band?** Answered: it makes no perceptible difference.
   Left alone for now.
2. **Is the target legible from the ingress?** Not raised as a problem, so treat
   it as fine until it is.
3. **Does the layered garrison read as layers from the air?** **No** - and that is
   item 2 at the top of this file, the live question.

### One new debt came out of measuring it, and it is the instrument's

**`sortie_bench` does not reproduce across processes, and the sortie A/B is
therefore unattributed.** The full 234-rep sweep was re-run at identical settings
after the bench was pointed at the real ingress; `cleared` came back at roughly
half its previous value at every depth. That is NOT a finding about difficulty:
re-running four of the newly-zero cells in isolation showed `node 13 sam/city
blaster` reading `hull 0%, dent 0.0, timeout` in the sweep and a live fight with a
kill and 71% of hull spent on its own. Same shape as v2.01's delivery-bench
diagnosis - results depending on what ran before them in one process. **Tune
nothing on those numbers.** Full table and reasoning in BALANCE.md.

**What the sweep DID find, solidly (two independent histories agree): the bench
tows a screamer around the map.** The retargeting policy takes the nearest threat
inside 60 m and can never let go, so against a screamer (holds standoff, carries
no weapon) or an aegis (shield hard-counters a chip gun, flying a route rather
than fighting) the pilot orbits at 30 m for the whole sortie and drifts to 149 m
from the centre.

**HALF-FIXED 2026-08-04, and the half that remains is the interesting one.** The
user chose the arena rule over the give-up-on-a-target rule, on the reasoning that
the second is pilot judgement and the first is a rig constraint - which is the
right separation. `sortie_bench.IN_FIGHT_RADIUS_M` now refuses to target anything
dragged past `EGRESS_RADIUS` from the sortie centre, and the drift is gone: node
21's pilot went from swinging 99-149 m out to holding 18-96 m, with 5 target
switches in 120 s and no chatter. **The zero dent did not move**, because the
pilot is now stalemated in place against a screamer whose jam shuts its own gun
director. No arena rule can see that. Only the give-up-on-a-target rule can, and
the case for adding it is in BALANCE.md - it is what separates "the blaster is
weak here" from "the blaster achieved literally nothing". **The user has not been
asked for that one yet.**

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
4. **Any new bestiary type joins FIVE lists the same day**, not three:
   `ENEMIES_FOR_STAMP` **and a delivery CELL** (delivery_bench), `ENEMIES`
   (lethality_check), `WarManifest.ROSTER`, `WaveDirector.ROSTER`+`PLAN`, **and a
   `matchup_harness` row**. The last one is not optional bookkeeping: the harness
   builds its config stamp from its OWN table, so a type in `ENEMIES_FOR_STAMP`
   and not in the harness makes the two stamps disagree forever and SILENTLY
   blanks the predicted column (v2.36). The original three-item version of this
   rule was written before two of those lists existed. The third one is
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
