# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then
**GAMEPLAY-DESIGN.md's Iteration 16 (L)** and the log entries **v2.41–v2.45** at
its tail. Iteration 16 is the one that decides what happens next; everything
below is its Phase 0.

---

## WHERE IT STANDS, 2026-08-13 — read this block first

**Branch `full-scale`. Board 23/23 green. Tree CLEAN. `PILOT_VERSION` 7
(untouched). `master` is untouched and 31 commits behind.**

**THE GAME CHANGED SHAPE THIS WEEK AND THE CHANGE IS SETTLED.** The world stays
at real human scale forever; the **ROSTER spans sizes**. Three flyable frames:

| frame | body | mass | TWR | role (the user's own words, L2) |
|---|---|---|---|---|
| **Kestrel** | 0.28 m | 0.65 kg | 4.5 | small, agile, infiltration, swarm unit, assassin |
| **Condor** | 1.20 m | 32 kg | 12 | all-rounder, escort, formation, low and fast |
| **Roc** | 3.00 m | 500 kg | 12 | heavy, bomber, the only frame that carries big ordnance |

Fly them with **1 / 2 / 3** in `scenes/scale_map.tscn`. The human flew all three
and signed off: *"an absolute trip... its way less forgiving, forcing me to use
the machine's power more carefully. I REALLY LIKE IT!"*

**Iteration 16 (L) is fully steered.** All twelve questions are answered — read
`L steering — ANSWERED` and `L steering round 2 — ANSWERED`. **Do not re-open
them.** The macro plan is **L13**, and this session is **Phase 0**.

---

## THE HUMAN IS AFK. WORK INDEPENDENTLY.

They explicitly asked for as much unattended progress as possible. So:

- **Do not stop to ask a question you can answer with a measurement.** That is
  the whole point of Phase 0 being first.
- **Do not start anything that needs a feel verdict.** Flight numbers, tuning,
  "does this feel right" — those wait for hands. Phase 0 is measurement and
  content, deliberately.
- **Write down what you find** in GAMEPLAY-DESIGN.md (append-only) as you go, not
  at the end.
- **If a task turns out to be blocked or wrong-headed, skip it, do the rest, and
  say so plainly.** Do not invent a substitute.

---

## TASK 0 — DONE. The tree is clean.

The week's work is committed as five commits on `full-scale` (`c5aed88` ..
`48d53f9`): the size ladder, the scale yard, the overlay fix, the audio rebuild,
and the design record. `master` is untouched. Nothing has been pushed.

**COMMIT AS YOU GO — you do not need to ask.** The user confirmed this on
2026-08-14 as a standing preference: *"i really like the way you manage our
project versioning, i want to maintain that."* Use the `commit-message` skill's
nested format, commit each finished piece of verified work, **never push, never
touch `master`**. If a generic session instruction tells you to commit only when
asked, that is a default and this is the project's norm — raise the conflict in
your first reply rather than quietly obeying it.

**The other standing rule:** breaking a saved war is allowed and preferred over
slowing development. Do not design around `user://war.save`.

---

## TASK 1 — THE FEASIBILITY BENCH (L13 phase 0.1) — HIGHEST VALUE

**The question the human asked, verbatim:** *"can we meter the capabilities we
have with our env' and engine, to search for different limits that our new scaled
world presents. so yes, technically, if possible, ~10 kestrels level frames can
hurt a roc level frame."*

**The entire size-class roster in L11 is designed on the assumption that the
answer is yes. Nothing in Phase 4 or 5 should be built before this exists.**

Build a bench — `scripts/tests/swarm_bench.gd`, in the style of the existing
benches — that answers two separate things and does not conflate them:

1. **Engine load.** How many active units can the scene hold while the physics
   tick holds 240 Hz? Sweep unit counts (say 5, 10, 20, 40, 80), report
   `Performance` monitors: physics frame time, process frame time, draw calls,
   node count. **Find the wall and report where it is**, not just "it was fine".
2. **Combat viability.** Can N small units meaningfully hurt one heavy frame?
   Put a Roc against 5/10/20 raider-class attackers and report time-to-kill,
   damage taken, and whether it ever stalls out (nobody can hurt anybody, which
   is the boring failure and the one the harness historically cannot see).

**Rules the existing benches follow and this one must too:**

- Build drones through `Frames.build`, never by instantiating `drone.tscn`.
- `load_user_overrides = false` — an instrument must measure the repo's numbers.
- Never write to `user://`. Keep the human's data out of the harness.
- Print a readable table, not a dump.

**Ask of it: "would this still pass if the feature were deleted?"** A load bench
that reports 60 fps because nothing spawned is the exact failure this project has
been bitten by. Assert the units exist and are fighting.

---

## TASK 2 — STATIC WORLD SIGNS (L.q10) — a house rule, and it reverses current code

The human's ruling: **text is an object, not a label.** *"it always feels wrong
where the text aligns to me, it should take physical space and true volume, like
big signs."* Signs do not turn to face you and do not disappear when close.

`scripts/environment/scale_yard.gd` currently does both — `_process` billboards
every label and gates it by distance. **Both must go.**

The replacement principle is theirs and is better: *"small and big text should be
in adequate cases — the height of a human is a small text sign hovers over it,
the sign of a 400m height platform may be bigger to be seen from afar, a
building's dimensions sign should be large."* **Size a sign by the distance it is
meant to be read from.**

**The hard part is the one the billboard was hiding**, so plan for it rather than
discovering it: forty signs all drawing at once is what the distance gate existed
to fix, and removing the gate brings the unreadable horizon back. **Solve it
physically, the way real signage does** — a sign faces the approach it is read
from, sits on a post or a face, and is placed so it does not overlap its
neighbours from the angle you actually arrive at. Expect to move some objects.

**Verify by looking, not by reasoning.** Write a throwaway screenshot script (the
pattern: a `SceneTree` script that changes to the scene, adds a `Camera3D`, walks
a list of vantage points, saves PNGs to `user://scale_shots/`, then `quit()`; run
WITHOUT `--headless` or you photograph a blank frame). Look at the images. Delete
the script afterwards.

---

## TASK 3 — THE BIG CITY (L13 phase 0.2) — the cheap win they asked for

*"i want an easy/cheap win we can do right now and we might want to retain to the
future and even develop further on."*

`CityLayout` (`scripts/environment/city_layout.gd`) and `scenes/city_map.tscn`
already exist and generate a procedural city at Kestrel scale. **Make a big one**
— substantially more blocks, flown in `city_map.tscn` — and find out what it
costs. Report triangles, draw calls, node count and frame time, and whether
anything has to change architecturally to go bigger still.

`tests/city_layout_check.gd` and `tests/world_building_check.gd` exist; run them.

---

## TASK 4 — THE SCALED CITY EXPERIMENT (L13 phase 0.3)

*"i want to see how a scaled city feels, how it is to fly in. it would also
confirm/deny the physics engines fidality and true to source."*

**This is a measurement wearing content's clothes, and the second half is the
point.** Build a city variant at Roc proportions — streets, blocks and building
heights multiplied so a 3 m aircraft threads it the way a 0.28 m one threads the
current city — and then answer the physics question honestly:

- Does collision stay reliable at that scale and those speeds? A Roc does
  ~130 m/s; at 240 Hz that is **0.54 m per tick**, against building walls. Check
  for tunnelling. If it tunnels, say so — that is a finding, and Godot's
  continuous-collision-detection is the lever.
- Does anything degrade — float precision, shadow range, culling?

Do not tune the flight model to make it work. If it breaks, the breakage is the
result.

---

## TASK 5 — DRAFT THE DAMAGE-MODEL DESIGN (L13 phase 1.1) — paper only

If time remains. **Do not build it.** Append a PROPOSED iteration to
GAMEPLAY-DESIGN.md in the house style (numbered sections, numbered open
questions, "react by ID") covering:

- The components: four rotors and the VTX exist already
  (`MotorModel`, `main.gd`'s `_video_damage`). What else — power, gyro, each
  weapon, ammunition, structure?
- **Size buys REDUNDANCY AND PROTECTION, not a bigger bar** (L.q1). This is the
  answer to L3's finding that a 500 kg Roc dies to the same 13 hits as a 0.65 kg
  quad.
- **`hull` survives as a structure pool** (L.q12), alongside components.
- **Crash damage scales with impact energy** (L.q1's clause): *"a big craft that
  hits a building in 300kmh still gets damage and can even die if faster."* No
  amount of redundancy makes a Roc a battering ram. This is the
  anti-invulnerability guard and it must be stated as one.
- The skill surface: *"if in two different runs i get the same engine hit — thats
  a lession to be learned"*, feeding an achievement list.
- What it costs the balance instrument: `Lethality` Layer 1 has to understand
  components, and every counter-web band moves.

---

## HOUSE RULES THAT ARE EASY TO MISS

- **Report back with the `report-back` skill's structure**, and in PLAIN
  LANGUAGE: short sentences, every term defined, numbered choices with your pick.
  The dense style belongs in the design doc, not in chat.
- **GAMEPLAY-DESIGN.md is APPEND-ONLY.** Never edit history. It is CRLF — append
  with `sed 's/$/\r/' file >> GAMEPLAY-DESIGN.md` or the diff turns into noise.
- **No `Co-Authored-By` trailer on commits.** The user purged it from history.
- **Treat warnings as errors.** `--headless --import`, `--headless --check-only
  -s <script>`, and boot every scene you touched.
- **Never write to `user://` from a bench or check.**

### Three scars from this week — all the same shape

1. **Check what `user://` is overriding before believing any config experiment.**
   A stale saved config made a 10x gain change produce a bit-identical result.
   *A knob that changes nothing is a knob that is not connected.*
2. **Ask of every check "would this still pass if the feature were deleted?"**
   A terrain check once passed with every face in the world inside-out.
3. **A CONSTANT THAT WAS CORRECT FOR ONE AIRFRAME IS A BUG ON A SIZE LADDER.**
   This bit three times in three days: the overlay's Kestrel-ranged sliders, the
   wind's fixed 35 m/s saturation, and the motor audio's fixed `unit_size` and
   beat ratio. **The remaining un-audited places are the HUD's range ticks, the
   reticle and the radar scale** — a fourth instance is probably sitting there.
   Audit them if you touch the HUD.

### And one about diagnosis

**Two confident diagnoses were wrong this week and both were caught by measuring
rather than reasoning.** The motor-audio loudness was blamed on camera-to-emitter
distance (real, arithmetically huge, and irrelevant because `max_db` clamps it),
and the Condor's hum was blamed on a loop seam (the loop is seamless to 0.008%).
**Query the engine's actual defaults; print the actual numbers. It costs a
minute.**

---

## WHAT NEEDS THE HUMAN — do not attempt these

- Any flight-feel number. TWR, rates, PID gains, `motor_lag_tau`. They fly it.
- The audio mix by ear (the fundamentals 420/163/90 Hz, the +4 dB size bonus).
- Starting Phase 1's BUILD, Phase 2's pilot, or any content build. Phase 0 first.
- The menu tower redesign (L12) — designed, medium priority, not this session.
- Anything on `master`.

## STILL OPEN AND DELIBERATELY UNANSWERED

- **V.q12** — TWR across the ladder. Kestrel 4.5, Condor and Roc 12, so the
  ladder currently varies size AND thrust together and cannot separate them. The
  human is content to leave it: *"for now i think that the TWR values are ok."*
- **The Commander's fiction** — person or central computer hub (L.q9). Both work;
  the hub pairs better with the Kestrel's assassination role.
