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
| 6b | **Fix the silent collision**: price contact continuously, not only on entry | DONE | Moved WHERE the impact is read, not WHAT is read: off `body_entered` (an ENTER signal) and onto the top of every physics tick while in contact. **E6's calibration is untouched to two decimals** — crash_check still reads 204.1 g / 37.76 at 20 m/s and 3.7 g / 0.00 for a set-down. The ledge case now costs 47.47 m/s and 311.18 hull where it cost ZERO before. Safe because 73.5 g needs 12 m/s of delta-v in ONE tick and full thrust builds 0.5 m/s per tick — so grinding can never trigger it and a strike spends its own speed, making it self-limiting (291 contact ticks priced, exactly 1 crossed). Guarded the three teleport paths that discard velocity by hand. **crash_check's velocity hold had to move from "until the crash fires" to "until contact"** — it was overwriting the very quantity it exists to measure. Board 25/25 |
| 6c | The SCALE MAP buildings — the ones the human actually meant | DONE | **The agent chased the wrong buildings.** The report said "buildings" and the agent went to the procedural city generator; the human meant `scale_map.tscn`. Flew a Condor into the 48-storey tower in the real scene: 8 m/s -> 0.00 hull, 12 m/s -> 0.00, **20 m/s -> 37.76**, 40 m/s -> dead. That 37.76 is `crash_check`'s exact figure, so **the scale map's crash chain is correct end to end** — colliders, `main.gd` wiring, the lot. The "sometimes no damage" is the FREE BAND working as designed: below 12.0 m/s head-on nothing is charged, and at a shallow angle that limit rises steeply (see `graze_bench`). Whether the free band is too generous is a DESIGN question for the human, not a defect. Probe deleted rather than committed: it degraded after the first lethal case and an untrustworthy instrument is worse than none |
| 7 | HUD: a top-down plate of the airframe with equipment where it physically sits | DONE | The plate draws the MACHINE first — arms to every rotor, hull, nose stub — then hangs each part on it. Rotor discs that empty AND redden with the value inside; a transmitting glyph for the VTX whose arcs thin as it dies; **armour as a ring around what it protects**, the first time plating is visible outside a `.tres`. The four description-only rows get a mark and deliberately NO reading. `hud_check` (board -> 26) **caught a real flaw on its first run**: the ring was normalised on `max(\|x\|,\|z\|)`, a SQUARE norm, while the plate draws a CIRCLE — quad rotors at 65.1 px against a hexa's 46.0. Now 46.0 everywhere. It also caught the check printing PASS *and* FAIL, because `quit()` does not return in GDScript and `board.sh` reads the last verdict line. **NOT judged by eye — `--headless` never calls `_draw`, so the board proves the layout and not the picture.** On the flight list |
| 7b | HUD round 2: hull on the plate, plate to centre, heat as a ring at the reticle | DONE | **Hull is drawn as the airframe's own body** — E5 marks the structure pool `located = false` because it IS the airframe, so the hull silhouette drains and reddens with the number inside, and losing integrity visibly empties the picture. Plate moved bottom-centre into the gap the retired hull/heat bars left (sticks' inner edges are at ±192, plate is 168 wide). **Heat became a generic `WeaponGauge`** — a half ring at the AIMING POINT, grey at idle, flashing on use, filling yellow bottom-to-top — carrying fraction/tint/label/side and knowing nothing about heat, so ammo is another instance not another widget. **The flash is derived from the value moving**, so nothing has to tell it the trigger was pulled. Hull stays a passed-in value because SIX callers feed `set_health` and only two feed the parts list. Also fed the plate in `sortie.gd`. Board 26/26; rendered boot clean; **not judged by eye** |
| 7c | HUD round 3: weapon gauges to the aiming point, attitude instruments | DONE | Colliding GUN/PWR/FCS/AMMO marks dropped from the plate (they carried a position and NO reading). `WeaponGauge` generalised over arc span/start: heat = right half, flak + missile = left quarters at nested radii, all filling toward the top. Targeting double-text was range-tick LABELS bunching as the fall-line compresses — marks stay, text thins. **Two attitude instruments, not one**: a wide DASHED horizon in Liftoff's grammar (reach is a fraction of viewport, not px) and a THRUST ARROW along body +Y with the tilt angle printed, because only `cos(tilt)` of thrust fights gravity and fast-and-low is where feel says nothing. Pitch ladder in real convention — 10° rungs, solid above / dashed below, rolling with the horizon — toggled by `hud_ladder_toggle` (H), an action rather than an overlay checkbox because the overlay has no boolean row type. **I shipped a sign error and caught it only by re-deriving**: world up is `(sin roll, −cos roll)`, I wrote `(−sin, −cos)` — identical at level, backwards under roll, invisible to a rendered boot. `hud_check` is now 10 claims, every attitude one asserted AT A ROLL, plus claim 10 refusing even-spaced rungs (60° belongs at 935 px, even spacing says 571) |
| 7d | HUD round 4: dashed horizon, pitch ladder, airframe level LINE | DONE | Horizon widened to ~80% of viewport (a FRACTION, not px) and dashed per the human's Liftoff reference. Pitch ladder in real convention: 10° rungs, labelled, **solid above / dashed below** (the cue that says sky-from-ground when the horizon is off-screen — the fast-and-low case), rolling WITH the horizon; toggled by `hud_ladder_toggle` (H), an action not an overlay checkbox because the overlay has no boolean row type. **The thrust arrow became a LINE on their call** — line-vs-line is a precise comparison where arrow-vs-line is coarse, and it IS the FPV tilt since the lens uptilt is why that plane misses the boresight. That collapsed both instruments into one function (`reference_pitch_roll`: world up → world horizon, thrust axis → airframe level) and **deleted** two helpers. Claims: #10 refuses even-spaced rungs (60° belongs at 935 px, even says 571); #9 sweeps tilt and holds gap == tilt == printed number at 0.5° too. **I wrote a tautology into #9** (passed `Vector3.UP` for both lines — a level aircraft's axis IS world up, so it compared the function to itself) and caught it before running. **I also corrupted `hud.gd` with a python text slice** and restored from the committed checkpoint — file work goes through Edit, never shell slicing |
| 7e | HUD round 5: the horizon becomes the line that follows the horizon | DONE | **The agent could have been LOOKING at the HUD all along and was not.** `hud_shot.gd` boots a scene, poses the airframe and saves a PNG per attitude — run windowed, then read the image. Three bugs, none findable by reasoning: (1) the level line was GREEN on dev_map's neon-green ground, and against the palette (green = pads) — now white with a dark backing stroke; (2) `fpv_uptilt_deg` 48 on a 94° lens puts level flight **19 px below the screen edge**, so both lines now PEG with chevrons rather than vanishing; (3) **the emphasis was on the wrong line** — in FPV the lens is bolted to the frame so the airframe plane is at a CONSTANT screen position and cannot follow the horizon (a 0/15/30/45° sweep shows it at an identical y while the horizon travels). The world horizon is now the prominent line and the airframe level is a short BRACKET. **The rig then caught a bug the fix introduced**: two different peg margins drew the lines 95 px apart at LEVEL, claiming a tilt that did not exist — one shared `PEG_MARGIN`, guarded by claim 9c. Board 26/26 |
| 8 | The pilot-in-the-loop instrument — the human as the reading | DONE | **The hard part was making the prediction unable to move, and it needed three mechanisms rather than one**: one committed JSON per drill (so `git log --format=%ct` dates THAT prediction and editing another cannot accuse it), a fingerprint of the prediction — **reasons included, because a rewritten argument is a different claim** — stamped into the run, and an ordering test. `DrillCompare` **refuses to grade** rather than grading against a moved goalpost, and `drill_check` asserts a refusal prints NO verdict rows. The anti-theatre claim is `MAX_BAND_FRACTION`: every measure declares what could physically have happened and a band over 40% of it fails the board, so *"somewhere between nothing and everything"* cannot pass as a prediction. Two drills fly (`hold_tilt`, and `rotor_out` with the airframe plate **hidden**, so it measures feel rather than whether you looked). **The screenshot rig found a bug reasoning could not**: a ColorRect parented to the brief label painted 82% black over the text, because a Control draws its children over ITSELF. **And the plumbing smoke test found a real measurement bug on its first run** — 60 Hz sampling off a 240 Hz tick recorded a call placed at 25% of a rotor as **20%**, a whole staircase step low, because `rotor_out` ends on an EVENT and the last sample predated the step it called. Board 27/27; 6 mutations on record. **Nothing is flown yet — both predictions are live and neither can now be edited without the report saying so** |
| 7f | HUD round 6 + the first flown drill results — all three from the human's hands | DONE | **The horizon stopped lying and stopped vanishing.** It was CLAMPED 210 px inside the edge and then DROPPED past a threshold, and the arithmetic says how badly: on a 94 deg lens (f = 503 px) the clamp detached the line at 33 deg of camera pitch — about **15 deg nose-down** — and the drop fired at 78.7 deg of camera pitch, which with 48 deg of uptilt is only **31 deg NOSE UP**. Both reachable in normal flight, which is why the human hit both. Now the world horizon is drawn at its true projection and simply LEAVES the screen, with edge arrows saying which way; the airframe BRACKET still pegs, because it is a fixed mark rather than a claim about the world. Tilt readout is now **signed** (negative nose-down) — a design choice, not a convention, because that readout is ours; the ladder keeps unsigned magnitudes with dashed below-horizon rungs, which IS the real-HUD convention and is what the human said to defer to. **The screenshot caught a flaw in the fix**: both chevron stacks drew their two arms COLLINEAR, so every "arrow" in the HUD had always been a flat dash — three of them read as an equals sign. VTX label moved above its symbol (it was running into the front-right rotor disc). `hud_check` -> 9d (a pitch sweep that refuses any clamp by demanding the offset keep GROWING past the edge) and 9e (the sign). **Drill results: `rotor_out` FALSIFIED my prediction completely and cleanly — 0.05 on all SEVEN attempts** where I said 0.45-0.70; the human detects ONE raider bolt of rotor loss, every time, in under two seconds, while the airframe moves 0.04 m. My reasoning modelled the steady state the integrator settles into and the cue is the STEP TRANSIENT. **`hold_tilt` produced NO reading at all** — 11 attempts across two sessions, never once inside the band — because the title "HOLD THE TILT" taught the wrong task and the pilot held LEVEL; the prediction is untested, not refuted, and the brief, the title and an in-band cue are fixed for a re-fly. Board **27/27 ALL GREEN**, lethality included |
| 7g | HUD round 7: the horizon upside down, and two stale readouts retired | DONE | **Round 6 shipped with the horizon running BACKWARDS when inverted, and every claim was green.** The human found it by rolling over. The offset was applied down SCREEN Y where it belongs along the aircraft's own up axis: writing world up in camera space as `u`, the horizon's closest point is `up * (f·u.z/h)` with `h = sqrt(u.x²+u.y²)`, and `up = (sin roll, −cos roll)` **rolls**. Screen-Y is the same answer at roll 0 and wrong everywhere else — inverted it is the exact NEGATIVE, so the line fled the horizon at twice the pitch rate. **At 90° of roll it failed invisibly instead**: the line is vertical there, so a vertical offset slid it along ITSELF and pinned the horizon to screen centre at every pitch. **A pitch sweep at roll 0 could never have caught this** — the claim that does is a comparison ACROSS ROLLS, the same shape `separation_check` needed across frame sizes. Fix is one line (`at = centre + horizon_offset(...)`), plus `screen_extent` so off-screen is measured along `up` (a 1920x1080 screen reaches 960 px sideways against 540 px vertically, and a height-only test calls a visible knife-edge horizon gone). Claim 9f + 1 mutation that fails three of its assertions at once. Also retired two stale readouts on the human's call: the duplicate "FLAK 24  MSL 6" line (the rings at the aiming point already carry label AND count where the pilot is looking) and the plate's "AIRFRAME" caption — a caption on a diagram that never needed one |
| 9 | `Lethality` Layer 1 rework (E8): expected hits-to-kill + expected FIRST FAILURE | DONE | **Half of E8's bill is not payable, and saying so is the result.** Expected FIRST FAILURE is built and is the pilot's number; expected HITS TO KILL is **unchanged by construction** — nothing a located hit can reach is lethal (a rotor at zero still makes `motor_min_thrust`) and what kills you is E5's deliberately undifferentiated pool, so a "distribution" there would be invention. E.q6's magazine is the pinned condition that would change it, written down rather than built. **The distribution is over WHICH ASPECT THE FIRE HOLDS, never over each round's bearing** — per-round is the degenerate model, because conservation makes every rotor accrue `amount/rotor_count` on every airframe and the frame ladder collapses to one number; that case is reported anyway as `spread_hits` (84 on every unplated quad, 125 on the hexa) precisely because it is the datum concentration is worth against. **Predicted before writing the code: 4 of 5 exact** (kestrel 27, atlas 57, condor 28, roc 42), hexa 39 against a predicted 41 — the miss was hand-computing ONE bearing where the sweep finds a worse one. **The headline claim HELD: no frame loses a rotor before it dies** (13/38/13/13/13 to death against 27/57/28/42/39 to first failure), so E7's whole skill surface is unreachable at `severity` 0.6 — a finding about the dial, not about geometry. Running it also caught a sampling bug in itself: an un-offset sweep lands on a quad's arms AND on its four rotor ties, skewing `spread_hits` 6% and making the Roc look different from the Kestrel when conservation says they are identical |
| 10 | `lethality_check` plants shots at NAMED LOCATIONS (E8) | DONE | Five named bearings x every roster frame = **25 planted cells, all matching the calculator on hit count AND on which rotor went** — the address is asserted separately because a model that gets the count right and the address wrong is the one failure E7 cannot survive. Four claims, and **the trap is `separation_check`'s one layer up**: "the calculator predicts a number and the drone takes a number" passes on a model that pooled every round and divided by four, so the discriminating claim is the frame ladder with plating OFF (kestrel 27, condor 21, roc 21 — bigger fails SOONER because its round is not divided). Claim 3 asserts the diffuse limit is exactly `rotor_count / per-hit` and **was written after it caught a real bug in the sweep that produces it**. Claim 4 verifies the bench's own PLUMBING instead of assuming it — `Health.damaged` carries the post-armour figure, so the Atlas's 8-point round arrives as 5, and had that wiring moved, Layer 1 and this bench would have used the same wrong number and agreed with each other forever. **5 mutations run, each failing a different claim and no other**: calculator single-nearest (claim 1, 15 cells — the frames whose rotors share a round), drop `- part.armor` (claim 1, 15 cells — the three plated frames), feed raw `enemy.damage` (claim 4 ALONE, which is why claim 4 is separate), un-offset the sweep (claim 3, reproducing 79-vs-84 while every per-bearing number stayed correct), and **LIVE-code single-nearest in `_apply_located`** (claim 2 collapses to 21/21/21 — the ladder has teeth against the shipped code, not only against the model) |
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

**PREDICTION, WRITTEN BEFORE THE ARITHMETIC EXISTS** (task 8's discipline, reused
because it costs one paragraph and makes the result falsifiable). Under sustained
raider fire — damage 8.0, shipped `severity` 0.6, shipped plating — held on the
airframe's worst bearing:

| frame | first failure | hits to it | hits to DEATH |
|---|---|---|---|
| kestrel | rotor, the one on the bearing | 27 | 13 |
| atlas | rotor | 57 | 38 |
| condor | rotor | 28 | 13 |
| roc | rotor | 42 | 13 |
| hexa | rotor | 41 | 13 |

**The claim with teeth is the last column: no frame loses a rotor before it
dies.** If that holds, "expected first failure" is a finding about `severity`
rather than about geometry, and E7's whole skill surface is unreachable at the
shipped dial. Rotors are named on every frame because they are the only `routed`
row in `AirframeComponents.TABLE` today.

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
