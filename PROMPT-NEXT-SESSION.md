# Prompt — the session after the pilot instrument

Paste the fenced block into a fresh session. It is self-contained: a new session
has none of the conversation that produced it.

**Read "Where to take it next" at the bottom of this file yourself before
choosing** — the fenced block deliberately does NOT pick a direction, because
that choice is the human's and it is the first thing the session should ask.

Delete this file once the next direction is under way.

---

```
QuadShot. Fresh session. I'm the pilot; the machine is yours.

READ IN THIS ORDER:
  1. CLAUDE.md — the project's own instructions, and they override defaults.
  2. WORK-LEDGER.md — the LIVING RECORD of everything done so far, newest
     findings at rows 7a-7l. `HANDOFF-NEXT.md` no longer exists; it went stale
     and was deleted on 2026-08-16, and git history holds the rest.
  3. TESTING.md — the run-everything manual. Section 5 covers the drills.
  4. BALANCE.md before touching anything the balance instrument measures.

WHERE THINGS STAND
  Board is 27 checks and GREEN. Tree clean, everything committed on `master`,
  nothing pushed. Iteration 17 (E) phase 1 is built; tasks 1-11 of the old
  ledger are DONE, including the Lethality Layer 1 rework and its witness.

  The PILOT-IN-THE-LOOP DRILL INSTRUMENT is finished and flown. It puts me in
  the measurement: a drill states a situation, a task and a success condition,
  the agent's prediction for what I will do is committed to git BEFORE I fly,
  and a report afterwards grades the flight and REFUSES to grade at all if the
  prediction moved. Five drills ship — `hold_tilt`, `rotor_out`, and a
  difficulty ladder of three courses (`course_wide`, `course`, `course_tight`).

  ASK ME WHICH DIRECTION TO TAKE BEFORE BUILDING ANYTHING. There is a list at
  the bottom of PROMPT-NEXT-SESSION.md in the repo; read it, form your own
  recommendation, and put it to me. Do not just start on one.

THE RULES THAT ARE EASY TO GET WRONG, ALL LEARNED THE HARD WAY:

  NEVER EDIT A COMMITTED PREDICTION. `drills/predictions/*.json` are live
  claims. If your work makes one wrong, that is a RESULT to report, not a file
  to fix. The report refuses to grade a prediction whose fingerprint moved.

  WAIT FOR VERIFICATION BEFORE COMMITTING. Always. The board takes over TEN
  MINUTES; run it in the background, keep working, commit when the verdict
  lands. "The last check is probably fine" is a prediction, and this project's
  whole discipline is that a prediction is not a measurement.

  CAPTURE THE BOARD'S OWN EXIT CODE. `./tools/board.sh > log; tail log` returns
  TAIL's status, so a RED board comes back as exit 0. That nearly shipped once.

  YOU CAN SEE THE GAME, SO LOOK AT IT. `scripts/tests/hud_shot.gd` boots a
  scene, poses the airframe and saves a PNG — run it WITHOUT --headless and READ
  the images. It takes `--scene`, `--drill`, `--at x,y,z`, `--lift` and arms the
  drone so the world is visible. Crop and zoom with Pillow if the thing is
  small. Nearly every visual bug this project has found was invisible to
  reasoning and obvious in a screenshot: a green line on green ground, an
  instrument off the bottom edge, collinear arrowheads that had never once
  drawn as arrows, emission so bright it erased the shape it was lighting.

  EVENTS SAMPLED AT 60 Hz OFF A 240 Hz TICK GET MISSED. Twice now. A rotor call
  at 25% recorded as 20%; a real collision recorded as ZERO touches, because the
  contact lasted 0.004 s — one tick — and fell between two samples. Anything
  event-like must be LATCHED across the gap, never read when the sample happens
  to fire.

  MEASURE, DO NOT REASON. The flight recorder, a two-minute probe script, or a
  screenshot will settle in one query what an hour of argument will not. A
  near-black patch that looked like a shader bug was the camera sitting 6 cm
  above the surface; a failing check that looked like a regression did not
  reproduce in four standalone runs. Do not state a cause you have not shown.

  MUTATION-TEST EVERY CHECK. Ask "would this still pass if the feature were
  deleted?" and record which mutation fails which claim. A claim that compares a
  function to itself has been written here twice and caught by reading, not by
  running.

CONSTRAINTS:
  - Never write to `user://` from a bench or check, and never read it either:
    set `TunableConfig.user_overrides_enabled = false` in anything that boots a
    scene. `scripts/tests/drill_report.gd` is the ONE argued exception.
  - Quads only. The hexa is FROZEN — report it, never tune it.
  - The menu tower renders the hexa very wrong. It is KNOWN and deliberately NOT
    to be fixed until the scale work is finished. Do not touch the menu.
  - DO NOT TOUCH flight-feel numbers (TWR, rates, PID gains, motor_lag_tau,
    yaw_authority, mass) or `severity`, which stays at 0.6.
  - Do file edits with Read/Write/Edit, never shell text slicing.

GIT: work on `master`, commit as you go without asking, use the commit-message
skill's nested format, NO Co-Authored-By trailer. Only PUSHING needs my say-so.

TELL ME THE EXPECTED DURATION before launching anything that takes minutes.

Report in plain language per the report-back skill, and define every term I have
not used myself.
```

---

## Where to take it next — the directions, and what each buys

Not part of the prompt. The agent should read this, form a view, and put it to
the human rather than choosing silently.

### 1. Fly the ladder and let the instrument earn its keep

**Cheapest, and it finishes what is already built.** Three courses are waiting
with committed predictions; `course_wide` and `course_tight` have never been
flown. The tight one is the first drill where `contacts` can say anything at
all, because it is scored on the WORST lap rather than the best.

What it buys: the first *comparative* reading the instrument has produced — the
same pilot across three difficulties, which is a curve rather than a point. If
`contacts` on the tight course still comes back at zero, 1.6 m gates are not
tight for this pilot and the ladder needs a fourth rung, which is itself worth
knowing.

Cost: minutes of the human's time and none of the agent's.

### 2. Iteration 18 — the macro scale-and-roster wishlist

**The human's own pinned item, and the biggest.** In their words: *"i want to
have a session of creative definition and construction of the full size scale of
items in the game... i want to see how the fighting in a fight scale of the
condor/roc can be... i imagine different turrets, missile sams, flak, i imagine
land vehicles that some can shoot me some not, humans shoot me. i need
creativity."* Also in scope: **player weapon upgrades**, and **sound as design**
rather than polish — *"the blaster sound right now sounds like a water gun, so a
roc cannon needs to sound respectively powerful."*

**The central question is theirs and everything hangs off it:** the Kestrel is
true to scale as a real racing quad and the scaled-down hobby playground *"is
still a true asset of this game"*. So does QuadShot become one continuous scale
ladder, or keep two honest registers — a models playground and a war?

**FORMAT: GAMEPLAY-DESIGN.md's own iteration format, not the `brainstorming`
skill.** Brainstorming converges on one design and terminates in a plan; this
needs the opposite motion. The iteration format (a letter, numbered sections,
open questions answered by ID) is what produced P3.3's roster and P4.8's
bestiary.

### 3. E7 — the skill surface, which the drills were the warm-up for

The design section the drill instrument actually serves: *"if in two different
runs i get the same engine hit — thats a lession to be learned"*, with three
requirements (legible, repeatable, recorded). The `Blackbox` already writes a
per-tick flight CSV and a sparse event log; achievements are queries over those
rather than a second bookkeeping system.

What it buys: the drills measure a pilot when you *ask* them to. E7 measures
them while they play, which is the same instrument pointed at the real game.

### 4. The pilot (L6.2, L10.2) and the single re-measure (L6.3)

Anticipatory planning, a per-class manoeuvre planner behind one shared pilot, a
competence benchmark, and a `PILOT_VERSION` bump. Then **one** re-measure of the
counter-web, which L7's risk 3 says must happen after both Phase 1 and Phase 2
or it happens twice. The delivery stamp is already deliberately stale.

What it buys: the bot ruler gets better, which every balance number depends on.
Cost: the largest engineering item on this list.

### 5. Small and real

- **`sag_m` is scored the wrong way** in `rotor_out`: low-is-better rewards a
  big CLIMB, so best-of picked the pilot's largest gain as their "best". It
  should score on magnitude. Cannot be fixed without a new prediction, since the
  committed one is against the current definition.
- **`hold_tilt` measures the rate loop as much as the pilot.** Past capture a
  centred stick holds the attitude, so 0.83 degrees of RMS over eighteen seconds
  is the aircraft. A version with a target that MOVES during the window would
  measure hands; it is a different drill and needs its own prediction.
- **The agent's bands have been too generous twice** and were tightened for the
  two new courses (3-8% of the plausible range against the old 8-35%). Whether
  that tightening was right is an open empirical question the ladder answers.

### The agent's recommendation, for what it is worth

**1 first, then 2.** The ladder is built, costs the human minutes, and turns a
pile of machinery into the first comparative reading it has ever produced —
finishing a thing before starting the next one. Then Iteration 18, because it is
the human's own pinned item, it is a DESIGN session rather than an engineering
one, and its central question gates most of what comes after it.
