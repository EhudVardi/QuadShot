# Prompt — task 8, the pilot-in-the-loop instrument

Paste the block below to open a fresh session on WORK-LEDGER.md's task 8. It is
written to be self-contained: a new session has none of this conversation.

Delete this file once task 8 is done.

---

```
QuadShot. Continuing the unattended run. I'm the pilot; the machine is yours.

READ IN THIS ORDER:
  1. WORK-LEDGER.md — the task list and resume point. Read it FIRST and follow
     its protocol exactly (mark WIP, commit, do the work, commit, mark DONE with
     a one-line finding, commit; one task at a time, never a dirty tree).
  2. CLAUDE.md
  3. TESTING.md's check-suite section, and the "human aim drill" entry in it.
  4. HANDOFF-NEXT.md for how we got here.

YOUR TASK IS 8 — THE PILOT-IN-THE-LOOP INSTRUMENT. Tasks 1 to 7 are DONE.
Task 9 (Lethality Layer 1 rework, E8) and 10/11 come after; do not start them.

WHAT I ASKED FOR, in my words, because the phrasing is the specification:

  "i want to create an instrument that will put ME as the pilot of a reading you
  can run and test or recognize patterns, etc. you tell me the situation, what
  you want me to do, and then read the result and compare to your assertions. it
  would bring you a new source of results to argue on. after all, the player is
  here to be served."

THE PRECEDENT ALREADY EXISTS AND YOU SHOULD READ IT BEFORE DESIGNING ANYTHING:
`scenes/aim_drill.tscn` + `scripts/tests/aim_drill.gd` (H.q4). It puts me on the
bot aim bench's exact ruler — same static immortal raider, same windows — and
writes the result to `user://blackbox/aim_drill_*.json` as deviation data. What I
want is that shape GENERALISED: any question, not just aim.

THE THING THAT MAKES IT AN INSTRUMENT RATHER THAN A DEMO IS THAT YOUR PREDICTION
IS WRITTEN DOWN BEFORE I FLY. If the prediction is recorded after, or can be
edited after, it cannot embarrass you and the whole exercise is theatre. Design
for that first and everything else second.

WHAT I EXPECT IT TO DO, roughly — argue with any of it:
  - A named DRILL: a stated situation, a stated task, and a stated success
    condition, all visible to me before I arm.
  - Your PREDICTION for that drill, committed to the repo BEFORE I fly it.
  - A recorded run that lands somewhere durable and machine-readable.
  - A comparison pass that reads my run against your prediction and says plainly
    where you were wrong. A gap is the OUTPUT, not something to tune away — same
    discipline BALANCE.md already states for predicted-vs-validated.
  - More than one drill, or at least a shape that obviously takes a second one.

CONSTRAINTS:
  - Never write to `user://` from a bench or check, and never read it either
    (`TunableConfig.user_overrides_enabled = false` in anything that boots a
    scene). The drill itself is interactive and MAY write its own results — the
    aim drill already does — but it must not touch anything else's files.
  - The board must stay green. It is 26 checks: `./tools/board.sh` (~10 min,
    `fast` skips lethality). RUN IT ALONE — a second Godot process alongside it
    is how a previous session mis-blamed a harness bug on concurrency.
  - Do NOT write it as a shell `for` loop; one script is one command.
  - Whatever you build gets a check the day it lands, and the check must be
    mutation-tested. Ask of it: "would this still pass if the feature were
    deleted?"
  - Quads only. The hexa is FROZEN — report it, never tune it, never let it
    drive a decision.
  - DO NOT TOUCH flight-feel numbers (TWR, rates, PID gains, motor_lag_tau,
    yaw_authority) or `severity`, which stays at 0.6.

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

## Notes for whoever writes that session's design

Not part of the prompt — context the agent will want and would otherwise
re-derive.

- **The honest hard part is the prediction, not the drill.** Recording a human
  flight is easy; making the agent's expectation falsifiable and *timestamped
  before the flight* is the design. Committing the prediction to git before
  handing over the route is the cheapest mechanism that actually works, because
  the commit is dated by something the agent does not control.
- **`Blackbox` already writes per-tick flight CSVs and a sparse `events_*.csv`**
  on arm/disarm, and `Blackbox.log_event` is a null-safe static. A drill's
  recording is probably a query over that plus a small JSON summary, not a
  second bookkeeping system — the same reasoning E7 used for achievements.
- **E7 is the design section this serves**: *"if in two different runs i get the
  same engine hit — thats a lession to be learned"*, with its three requirements
  (legible, repeatable, recorded).
- **Do not let it become a second balance instrument.** `BALANCE.md` owns
  measured balance and `ReferencePilot.PILOT_VERSION` pins the measuring brain.
  This is a source of HUMAN readings to argue against those, and it must not
  silently start feeding the base tables — the aim drill's rule is that its
  results land as deviation data and never in the base table.
