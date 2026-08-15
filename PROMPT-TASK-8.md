# Prompt — task 8, the pilot-in-the-loop instrument

Paste the fenced block below into a fresh session. It is written to be
self-contained: a new session has none of this conversation.

Delete this file once task 8 is done.

---

```
QuadShot. Continuing an unattended run. I'm the pilot; the machine is yours.

READ IN THIS ORDER:
  1. WORK-LEDGER.md — the task list and resume point. Read it FIRST and follow
     its protocol exactly: mark the task WIP and commit that one-line change
     BEFORE starting, do the work, commit it, mark it DONE with a one-line
     finding, commit, move on. One task at a time. Never a dirty tree.
  2. CLAUDE.md
  3. TESTING.md's check-suite section, and the "human aim drill" entry.
  4. HANDOFF-NEXT.md for how we got here.

YOUR TASK IS 8 — THE PILOT-IN-THE-LOOP INSTRUMENT. Tasks 1 to 7 are DONE.
Do not start task 9 (the Lethality Layer 1 rework) or anything after it.

WHAT I ASKED FOR, in my words, because the phrasing is the specification:

  "i want to create an instrument that will put ME as the pilot of a reading you
  can run and test or recognize patterns, etc. you tell me the situation, what
  you want me to do, and then read the result and compare to your assertions. it
  would bring you a new source of results to argue on. after all, the player is
  here to be served."

THE PRECEDENT EXISTS — READ IT BEFORE DESIGNING ANYTHING:
`scenes/aim_drill.tscn` + `scripts/tests/aim_drill.gd` (H.q4). It puts me on the
bot aim bench's exact ruler — same static immortal raider, same windows — and
writes the result to `user://blackbox/aim_drill_*.json`. I want that shape
GENERALISED: any question, not just aim.

THE THING THAT MAKES IT AN INSTRUMENT RATHER THAN A DEMO IS THAT YOUR PREDICTION
IS WRITTEN DOWN BEFORE I FLY. If the prediction is recorded after the fact, or
can be edited after, it cannot embarrass you and the exercise is theatre. Design
for that first and everything else second. Committing the prediction to git
before you hand me the route is the cheapest mechanism that actually works,
because the commit is dated by something you do not control.

WHAT I EXPECT IT TO DO, roughly — argue with any of it:
  - A named DRILL: a stated situation, a stated task, and a stated success
    condition, all visible to me before I arm.
  - Your PREDICTION for that drill, committed BEFORE I fly it.
  - A recorded run landing somewhere durable and machine-readable.
  - A comparison pass that reads my run against your prediction and says plainly
    where you were wrong. A gap is the OUTPUT, not something to tune away — the
    same discipline BALANCE.md already states for predicted-vs-validated.
  - More than one drill, or at least a shape that obviously takes a second one.

YOU CAN SEE THE GAME. THIS IS NEW AND THE LAST SESSION LEARNED IT THE HARD WAY.
`scripts/tests/hud_shot.gd` boots a scene, poses the airframe and saves a PNG per
attitude — run it WITHOUT --headless and then READ the images. The previous
session spent several rounds insisting the HUD could not be judged without my
eyes; that was true of --headless and false of the agent, and three real bugs
(a green line on green ground, an instrument sitting off the bottom edge, and two
constants that disagreed) were all invisible to reasoning and obvious in a
screenshot. If this task produces anything visual, LOOK AT IT.

CONSTRAINTS:
  - Never write to `user://` from a bench or check, and never read it either:
    set `TunableConfig.user_overrides_enabled = false` in anything that boots a
    scene. The drill itself is interactive and MAY write its own results — the
    aim drill already does — but it must not touch anything else's files.
  - The board must stay green: 26 checks, `./tools/board.sh` (~10 min; `fast`
    skips lethality). RUN IT ALONE and do NOT write it as a shell `for` loop.
  - Whatever you build gets a check the day it lands, and the check gets
    MUTATION-TESTED. Ask of it: "would this still pass if the feature were
    deleted?" Last session wrote a check that compared a function against itself
    and could never have failed; it was caught by reading it, not by running it.
  - Do file edits with Read/Write/Edit. Last session corrupted a 1200-line file
    with a python text slice whose index matched in two places.
  - Quads only. The hexa is FROZEN — report it, never tune it, never let it
    drive a decision.
  - DO NOT TOUCH flight-feel numbers (TWR, rates, PID gains, motor_lag_tau,
    yaw_authority, mass) or `severity`, which stays at 0.6.

GIT: work on `master`, commit as you go without asking, use the commit-message
skill's nested format, NO Co-Authored-By trailer. Any local git action is fine;
only PUSHING needs my say-so.

TELL ME THE EXPECTED DURATION before launching anything that takes minutes.

WHEN YOU HAND IT BACK, give me the exact command and the exact route: which
scene, which key, where the thing I am judging will be, what counts as success
and what would count as the feature being broken. Report in plain language per
the report-back skill — define every term I have not used myself.

Start by reading the ledger, then mark task 8 WIP and commit that before any
other work.
```

---

## Notes for whoever designs that session

Not part of the prompt — context the agent would otherwise re-derive.

- **The hard part is the prediction, not the drill.** Recording a human flight is
  easy; making the agent's expectation falsifiable and *timestamped before the
  flight* is the design.
- **`Blackbox` already writes** a per-tick flight CSV and a sparse `events_*.csv`
  on arm/disarm, and `Blackbox.log_event` is a null-safe static. A drill's
  recording is probably a query over that plus a small JSON summary, not a second
  bookkeeping system — the same reasoning E7 used for achievements.
- **E7 is the design section this serves**: *"if in two different runs i get the
  same engine hit — thats a lession to be learned"*, with its three requirements
  (legible, repeatable, recorded).
- **Do not let it become a second balance instrument.** `BALANCE.md` owns measured
  balance and `ReferencePilot.PILOT_VERSION` pins the measuring brain. This is a
  source of HUMAN readings to argue against those, and it must not silently feed
  the base tables — the aim drill's rule is that its results land as deviation
  data and never in the base table.
- **Candidate drills worth proposing**, since the HUD work just made two of them
  measurable: can the pilot hold a stated tilt using the new attitude bracket;
  can they thread a gap at a stated speed; can they tell a rotor failure from the
  sticks alone before reading the plate.

## Still on the human's flight list

- **`fpv_uptilt_deg` 48 on a 94-degree lens puts level flight 19 px BELOW the
  screen edge**, so both attitude lines peg in level flight. That is realistic for
  the camera angle and it is a flight-feel call, so it was left alone. If they
  want the horizon to sit naturally in view at hover, `fpv_uptilt_deg` or
  `fpv_fov_deg` moves and the agent bakes whichever they pick.
- **The armour values** (atlas 0.006, condor 0.012, roc 0.024) are PROVISIONAL and
  authored from role, never from a ratio. Plating costs mass now; the Condor is
  the roster's most rotor-fragile frame in a fight and that is reported, not
  tuned.
- **`severity` 1.0** is E.q8's design target and ships at 0.6 by their decision.
