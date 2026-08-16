# Prompt — task 9, the `Lethality` Layer 1 rework (E8)

Paste the fenced block below into a fresh session. It is written to be
self-contained: a new session has none of this conversation.

**This runs alongside a second, already-committed dev line — the pilot-in-the-loop
drill instrument (task 8).** The drill line is finished as code and is waiting on
a human flight that has not happened yet. The fenced block tells the new session
exactly what it must not touch and why. Read "Why the two lines can collide"
at the bottom of this file before changing anything in the prompt.

Delete this file once task 9 (and its witness, task 10) are done.

---

```
QuadShot. Continuing an unattended run. I'm the pilot; the machine is yours.

READ IN THIS ORDER:
  1. WORK-LEDGER.md — the task list and resume point. Read it FIRST and follow
     its protocol exactly: mark the task WIP and commit that one-line change
     BEFORE starting, do the work, commit it, mark it DONE with a one-line
     finding, commit, move on. One task at a time. Never a dirty tree.
  2. CLAUDE.md
  3. BALANCE.md — READ IT BEFORE TOUCHING THE INSTRUMENT. It owns what the
     balance model is allowed to claim, and this task edits its Layer 1.
  4. GAMEPLAY-DESIGN.md, Iteration 17 (E): sections E3 (the component
     registry), E4.2 and E4.3 (located armour and hit separation), E7 (the
     skill surface), E8 (THIS TASK, stated as a bill) and E9 (what this must
     NOT change). Then the two entries after Iteration 17, `E steering —
     ANSWERED` and `E steering round 2 — ANSWERED`, which correct the draft.
  5. TESTING.md's check-suite section.
  6. HANDOFF-NEXT.md for how we got here.

YOUR TASK IS 9 — THE `Lethality` LAYER 1 REWORK. Tasks 1 to 8 are DONE.
Task 10 is its WITNESS and should follow immediately if the session has room:
E8's own words are that `lethality_check` must plant shots at named locations
"or Layer 1's new arithmetic has no witness". Mark and commit them as two
separate ledger tasks. DO NOT start task 11.

WHAT THE TASK IS, from E8:

  Layer 1 is pure config arithmetic — damage per shot against hull/armor gives
  hits-to-kill and time-to-kill, with no pilot, no physics and no scene in it.
  A component model breaks the assumption underneath it: "hits to kill" stops
  being one number and becomes a distribution over WHERE the hits land.

  The rework, in E8's order:
    - keep a scalar EXPECTED hits-to-kill, computed under the hit-location
      distribution, so every existing band still has something to compare
      against;
    - gain a second output that matters more for feel: EXPECTED FIRST FAILURE —
      which component goes first, and after how many hits. "That is the number
      a pilot experiences, and nothing in the instrument reports it today."

  The live code it must MIRROR (not change) is `FlightController._apply_located`
  plus `AirframeComponents` and `DamageConfig.hit_footprint_m`: a round arrives
  on a bearing, meets the hull edge, and every routed component within a
  footprint measured in METRES shares the damage, weighted by closeness and
  normalised so damage is conserved. That footprint being frame-independent is
  the whole of E4.3's symmetry and is not up for revision here.

  E9 says explicitly what this must NOT change: enemy durability (components are
  the PLAYER's model), the flight model's architecture, the war layer, and the
  severity dial.

  SCHEDULE CONSTRAINT, and it is the reason this task is ahead of the pilot
  work: every counter-web band moves when this lands, and L6 schedules exactly
  ONE re-measure afterwards. This must land BEFORE that re-measure or the
  re-measure happens twice. Nothing has scheduled it yet, so there is room.

=========================================================================
THERE IS A SECOND DEV LINE IN THIS REPO. READ THIS BEFORE YOU EDIT ANYTHING.
=========================================================================

Task 8 built a PILOT-IN-THE-LOOP DRILL INSTRUMENT and it is committed and
finished as code. I have NOT FLOWN IT YET. It is a thing where the agent's
prediction about what I will do is committed to git BEFORE I fly, and a report
afterwards grades my flight against it and refuses to grade at all if the
prediction moved. See TESTING.md section 5 and CLAUDE.md for what it is.

1. NEVER EDIT `drills/predictions/*.json`. Not to fix a typo, not to reword a
   reason, not for any reason at all. Those two files are live claims about
   what I will do, they are fingerprinted into every run, and the report REFUSES
   to compare if they move. If your work makes one of those predictions wrong,
   THAT IS A RESULT and it gets reported, never edited away.

2. DO NOT TOUCH THE DRILL LINE'S FILES:
     drills/predictions/**            scenes/drill.tscn
     scripts/drills/**                scripts/tests/drill_check.gd
     scripts/tests/drill_report.gd    scripts/tests/drill_smoke.gd

3. THESE ARE READ-ONLY UNTIL I HAVE FLOWN, because the drills fly THROUGH them
   and my prediction was made about how they behave today. Task 9 is arithmetic
   in `scripts/balance/` and should need none of them:
     scripts/drone/motor_model.gd     — especially `_effective` and
                                        `damage_motor`; the rotor drill degrades
                                        a rotor through exactly those
     resources/default_damage_config.tres — `severity` (stays 0.6),
                                        `motor_min_thrust`, `hit_footprint_m`
     scripts/ui/hud.gd                — `HorizonLine.tilt_degrees`; the tilt
                                        drill calls that exact function, so
                                        changing it changes what was measured
     resources/default_flight_kestrel.tres and default_frame_kestrel.tres
   If task 9 GENUINELY needs one of these to change, STOP, say so, and ask me.
   Do not change it and mention it afterwards.

4. WE MAY BE SHARING ONE WORKING TREE. Another session may be open on this same
   folder. Before your first edit, run `git status`. If the tree is dirty, that
   is the other session mid-change: STOP and tell me, do not commit over it.
   Expect the drill line to produce at most one more commit — my flight results
   and what the prediction got wrong — touching WORK-LEDGER.md and TESTING.md
   and nothing under `scripts/balance/`.

5. THE BOARD IS 27 CHECKS AND `drill` IS ONE OF THEM. `tools/board.sh` must keep
   it. Task 9 will change `lethality_check`, which is the SLOWEST check on the
   board; do not "helpfully" trim the list.

=========================================================================

CONSTRAINTS:
  - Never write to `user://` from a bench or check, and never read it either:
    set `TunableConfig.user_overrides_enabled = false` in anything that boots a
    scene. `scripts/tests/drill_report.gd` is the ONE deliberate exception in
    the project and it is not yours to imitate.
  - The board must stay green: 27 checks, `./tools/board.sh`. **It takes OVER
    TEN MINUTES** — a run on 2026-08-16 blew through a 600 s timeout — so launch
    it in the BACKGROUND, tell me the estimate first, and do NOT write it as a
    shell `for` loop (a permission allowlist matches the command string, which is
    why the script exists).
  - Whatever you build gets a check the day it lands, and the check gets
    MUTATION-TESTED. Ask of it: "would this still pass if the feature were
    deleted?" and record which mutation fails which claim. For THIS task the
    trap is specific and E8 names it: an "expected hits to kill" that quietly
    equals the old undifferentiated number would pass every test written against
    the old behaviour. The claim that separates them has to be one no
    single-pool model can satisfy — and the frame ladder is where to look, since
    a Kestrel's rotors sit inside 0.28 m and a Roc's across 3.0 m.
  - Do file edits with Read/Write/Edit. A previous session corrupted a
    1200-line file with a python text slice whose index matched in two places.
  - Quads only. The hexa is FROZEN — report it, never tune it, never let it
    drive a decision.
  - DO NOT TOUCH flight-feel numbers (TWR, rates, PID gains, motor_lag_tau,
    yaw_authority, mass) or `severity`, which stays at 0.6.
  - A predicted-vs-validated gap is the instrument's OUTPUT, not a number to
    tune away. BALANCE.md says so and it applies to your own new numbers too.

YOU CAN SEE THE GAME. `scripts/tests/hud_shot.gd` boots a scene, poses the
airframe and saves a PNG per attitude — run it WITHOUT --headless, pass
`--scene res://scenes/whatever.tscn`, and then READ the images. If this task
produces anything visual, LOOK AT IT. Two sessions running have now each found
bugs that were invisible to reasoning and obvious in a screenshot.

GIT: work on `master`, commit as you go without asking, use the commit-message
skill's nested format, NO Co-Authored-By trailer. Any local git action is fine;
only PUSHING needs my say-so.

TELL ME THE EXPECTED DURATION before launching anything that takes minutes.

WHEN YOU HAND IT BACK: report in plain language per the report-back skill and
define every term I have not used myself. If anything you did could change what
the drill instrument measures, say so at the top, loudly.

Start by reading the ledger, then mark task 9 WIP and commit that before any
other work.
```

---

## Notes for whoever designs that session

Not part of the prompt — context the agent would otherwise re-derive.

### Where Layer 1 actually is today

- `scripts/balance/lethality.gd` (505 lines). `versus()` is the outgoing cell
  (your weapon vs an enemy), `incoming()` is Layer 3a (their weapon vs your
  frame), and both run through one shared `_exchange()` over a plain durability
  block — `target_from_enemy` / `target_from_frame`. **That block is a single
  undifferentiated pool**: `{hull, armor, shield_*}`. The component model has no
  representation in it at all.
- The player side is the half that breaks. `target_from_frame` reads
  `FrameConfig.hull` / `armor` and nothing else, so the whole of E3's registry —
  four live components, per-component armour, and separation — is invisible to
  the instrument that is supposed to price durability.
- `scripts/tests/lethality_check.gd` (518 lines) verifies the arithmetic by
  planting shots into a real `Health` node. It is the slowest check on the board
  (~8 min alone).

### Why the two lines can collide

The drill line and this task look unrelated — one is an interactive scene, the
other is static arithmetic — and there are exactly three places they meet:

1. **`drills/predictions/rotor_out.json` reasons about the damage model.** Its
   argument is that a rotor is a quarter of the lift, that holding altitude with
   a 40% wound costs about 2.5 percentage points of collective, and that the rate
   loop's integrator absorbs the asymmetry. If task 9 only MIRRORS the existing
   arithmetic in `Lethality`, none of that moves. If it "fixes" the live damage
   path while it is in there, the human flies a different aircraft from the one
   the prediction was made about and the reading is worthless. Hence the
   read-only list.
2. **The board.** Both lines added a check. 27 is the number.
3. **One working tree.** `git status` before the first edit is the whole of the
   mitigation, and it only works if the prompt says it.

### The thing worth predicting BEFORE writing the code

Task 8's whole point was that a prediction written down first can embarrass you.
That discipline is cheap to reuse here and there is an obvious candidate:
**which component does E8's "expected first failure" name for each frame, and
after how many raider bolts?** Writing that down in the ledger's WIP commit —
before the arithmetic exists — costs one sentence and makes the result
falsifiable. It is not required by the task. It is just the habit the previous
task built the machinery for.

### Still on the human's flight list

- **The two drills, unflown.** `<godot> --path . scenes/drill.tscn -- --drill
  hold_tilt` and `--drill rotor_out`. This is the pending item that everything
  above is protecting.
- **`fpv_uptilt_deg` 48 on a 94-degree lens** puts level flight 19 px below the
  screen edge, so both attitude lines peg in level flight. Realistic for the
  camera angle and a flight-feel call, so it was left alone.
- **The armour values** (atlas 0.006, condor 0.012, roc 0.024) are PROVISIONAL
  and authored from role, never from a ratio.
- **`severity` 1.0** is E.q8's design target and ships at 0.6 by their decision.
