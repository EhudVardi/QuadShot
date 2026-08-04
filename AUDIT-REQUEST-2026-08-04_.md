# AUDIT REQUEST — QuadShot, 2026-08-04

You are being asked to audit a codebase you did not write, on behalf of the agent
that wrote it. Read this whole file before opening any source.

**Repo:** `e:\Workspaces\Git\Clones\QuadShoot` (branch `master`)
**Pinned HEAD:** `5830192e5d62c0ade3f36f870f8352fddc5a96d3` — if `git rev-parse HEAD`
disagrees, say so at the top of your report and audit what is actually there.
**Engine:** Godot 4.7 stable, `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe`
**Deliverable:** one file, `AUDIT-HANDOFF-2026-08-04.md`, shape specified in §7.

> **Correction, recorded when this file was committed.** This request was handed out
> pinned to `c10eb4304b6ddcb73bb1dafde0b99baa42f00e48`, which was HEAD at the time and
> is HEAD~2 now; the pin above is corrected to the real HEAD so the file agrees with the
> repo. The audit that came back — `AUDIT-HANDOFF-2026-08-04.md`, in this same commit
> pair — was therefore performed at `c10eb43` and says so, correctly, in its own first
> line. The two commits that landed in between are `83afd05` (`BALANCE.md`,
> `HANDOFF-NEXT.md`, `scripts/tests/sortie_bench.gd`) and `5830192` (`GAMEPLAY-DESIGN.md`,
> `HANDOFF-NEXT.md`). **No source file any of the seven findings cites was touched**, so
> every finding is re-derivable at the corrected pin; only the two `sortie_bench.gd` line
> numbers in F2 and the `HANDOFF-NEXT.md` line numbers may have shifted.

---

## 1. What this project is, in one screen

QuadShot is a 3D FPV drone flight sandbox in Godot/GDScript that has grown into a
campaign game. Roughly 25k lines of GDScript, of which ~11k is a headless test and
measurement harness. Single author (an AI agent), single human reviewer, ~7 months
of history, no CI, no external dependencies, no addons.

Four layers, from oldest to newest:

| layer | what it is | where |
|---|---|---|
| **Flight model** | 240 Hz rate-controller quadcopter sim. The product. | `scripts/drone/` |
| **Combat** | player weapons, 6 enemy types, waves, damage, EW/jamming | `scripts/combat/` |
| **War campaign (M6)** | a pure, deterministic, seed-driven war sim over a serializable Dictionary; generates sorties; eats their results | `scripts/war/` |
| **The bridge + the face** | turns a war-sim sortie spec into a real flyable fight; and the war room screen that owns the campaign turn | `scripts/sortie/`, `scripts/warroom/` |

Line counts, so you can size your reading:

```
scripts/tests        10890      scripts/ui            1425
scripts/combat        3900      scripts/environment   1193
scripts/war           1734      resources             1206
scripts/warroom       1521      scripts/menu          1077
scripts/drone         1112      scripts/balance        954
scripts/sortie         717      scripts/audio          283
```

Largest single files: `ui/debug_overlay.gd` 756, `sortie/sortie_runner.gd` 717,
`environment/city_layout.gd` 659, `war/war_sim.gd` 584, `combat/wave_director.gd`
509, `warroom/hex_table.gd` 503.

---

## 2. Ground rules

1. **Read-only.** Do not edit, refactor, format, or fix anything. Do not commit,
   stage, branch, or stash. The only file you may write in the repo is your own
   `AUDIT-HANDOFF-2026-08-04.md`. Scratch files go in your own temp directory.
2. **You may run headless checks and benches** — see §6 for the safe command list
   and the two things that can damage the human's data. Running is optional;
   reading is the deliverable. The previous external audit ran nothing and still
   produced the most valuable findings this project has had.
3. **`GAMEPLAY-DESIGN.md` is append-only and is not yours to touch or rewrite.**
   It is 10,723 lines. Do not read it whole — that is roughly a third of your
   context for mostly-historical reasoning. Read the tail (`v2.03` onward, around
   line 9800 to the end) and `grep` it for specific claims you need to check.
4. **Do not propose features.** Not new mechanics, not new enemy types, not a UI
   you think would be nice. The design backlog is long and already prioritised.
5. **Do not propose balance or tuning numbers.** This project's house rule is that
   difficulty is *measured by a harness*, never authored, and that feel judgements
   belong to the human. "Enemy X should have 20% more health" is noise here. "The
   bench that measures enemy X cannot distinguish a tough enemy from a broken one"
   is exactly the kind of finding wanted.
6. **Do not report style that the project deliberately mandates.** Before flagging
   a convention, check `CLAUDE.md` — static typing everywhere, hand-edited `.tscn`
   text, no third-party addons or external assets, procedural/greybox art only,
   comments explaining *why* not *what*, `snake_case`. Suggesting a library, an
   addon, a linter, or a CI pipeline is out of scope and will be discarded.
7. **Being wrong is acceptable. Being vague is not.** Every finding must be
   located (`file.gd:123`), falsifiable, and state its own confidence. The author
   will re-derive every finding against the code before changing anything.

---

## 3. The standard to apply

This project's own standard, which it wrote and then failed to keep:

> **Would this check still pass if the feature it tests were deleted?**

Three of its checks failed that question in a previous audit. The question is
cheap, mechanical, and nobody was asking it. Apply it to everything you read, not
just to tests:

- For a **test**: name the concrete mutation (rename this field, delete this
  guard, invert this comparison) that *should* make it fail. If you cannot name
  one, that is the finding.
- For an **assertion**: does it compare a value against an independently derived
  expectation, or against the function under test / against itself?
- For a **claim in a doc**: is the number or behaviour it states still true in the
  code today, at a line you can cite?
- For a **guard**: is there a path that reaches the guarded state without passing
  the guard?

Second standard, specific to this project's failure history:

> **A result that reads "0" is equally consistent with a hard thing, a broken
> thing, and a thing that left the level.**

Anywhere a number is produced and consumed, ask which of those three it could be
and whether anything downstream could tell them apart.

---

## 4. What is already known — do not spend budget re-finding these

A previous external audit (recorded as `v2.01` in the design doc, around line
9808 — read that entry, it is one page and it will calibrate you) already found
and closed:

- three checks that could not fail (`war_loop_check`, `sortie_check`,
  `ammo_check`) — all three are now mutation-tested and fixed;
- a dogfight that scored you *better* for leaving the fight (fired-vs-arrived
  reserve bug);
- a `SAVE_VERSION` mismatch path that would have silently overwritten every
  campaign save;
- a test that wrote to the human's real `user://war.save`.

Known-open debts, already diagnosed, **not** wanted as findings unless you can
advance them (Track 5 is where to do that):

- **The delivery bench does not reproduce across processes**, and the pilot's own
  shot count moves between identical runs — so it is trajectory divergence, not
  scoring noise. Leading suspect is a threshold *inside the reference pilot*
  (`jink_hold_cone_deg`, 14°) that flips jink-vs-shoot on a tick. Unproven.
- **`sortie_bench` does not reproduce across processes either** (found 2026-08-03,
  same signature). The entire sortie difficulty sweep is therefore unattributed.
- **The bench pilot tows a screamer around the map** — its retargeting takes the
  nearest threat inside 60 m and can never let go, so against a standoff enemy it
  orbits for the whole sortie and drifts out of the arena. Diagnosed, and
  **HALF-SHIPPED**, not unshipped: `sortie_bench.IN_FIGHT_RADIUS_M` (2026-08-04,
  commit `83afd05`) now refuses to target anything dragged past `EGRESS_RADIUS` from
  the sortie centre, and the drift is gone — node 21's pilot went from swinging
  99-149 m out to holding 18-96 m. The other half, a give-up-on-a-target rule, was
  **DECLINED by the user** (*"no. lets keep it simple"*, recorded in GAMEPLAY-DESIGN
  v2.16) and is not coming. So the zero-dent cells remain, because the pilot is now
  stalemated in place against a screamer instead of towing one, and no arena rule can
  see that.
- **`SLICE_ARCHETYPES` / archetype coverage**: all seven mission archetypes now
  fly, five of them have never been measured.

Read `HANDOFF-NEXT.md` in full (400 lines) — it is the current state of play and
its §0 "standing rules" list is the accumulated scar tissue.

---

## 5. The audit tracks

Ranked by value. Spend the bulk of your budget on **Tracks 1, 2 and 5**. If you
are running multiple agents in parallel, one track per agent is a clean split;
merge and de-duplicate before writing the handoff.

### Track 1 — The check suite, against the house standard (highest value)

19 headless checks in `scripts/tests/*_check.gd`, listed in `TESTING.md` §4.
Three of them already failed the deletion question. The newest four have never
been externally reviewed: `war_room_check`, `sortie_check` (its ingress
assertions are two days old), `composition_check`, and the post-fix `ammo_check`.

For **each** check, produce a one-line verdict and, for anything that is not
clearly sound, the mutation that should break it. Look specifically for:

- assertions that mock both sides of the joint they exist to guard;
- assertions over data the test itself constructed by hand;
- comparisons of a value against itself with no simulation step in between;
- `.get(key, default)` on both the producer and the consumer of a field name, so
  that renaming the field breaks nothing loudly;
- checks that pass because of an incidental property of the fixture (the known
  example: a 3-node supply-cut test passed under mutation because severing the
  middle of three nodes removes every adjacency anyway — it took 4 nodes to make
  the assertion real);
- checks whose failure mode is a *hang* rather than an assert.

### Track 2 — Iteration 13, the war room (never externally reviewed)

`scripts/warroom/` — 1521 lines, shipped in one day, plus `scenes/war_room.tscn`.
It now **owns the campaign turn**: launch a node, fly it, price the result in,
tick the war, save. Claims made about it that are worth testing:

- `war_view.gd` is **pure and headless-checkable**, and `hex_table.gd` owns
  geometry and **no facts**. Is that actually true, or does the renderer decide
  anything the checks cannot see?
- The room adds **zero fields** to the save file.
- The inspection card runs `compose_briefing` (fogged intel) and never `compose`
  (ground truth). A card that leaks the truth through the fog looks perfect on
  screen — is there any path where truth reaches the card?
- **Death ends the sortie** and **quitting mid-sortie loses it**. Trace both paths
  through `war_launch.gd` / `war_debrief.gd` / `war_room.gd` / `sortie.gd`. What
  the author most wants to know: can the campaign be **double-ticked**, can a
  sortie result be **applied twice**, and can a stale in-memory state be written
  over a newer save?
- `war_diff.between` + `hex_table.play_changes` animate a diff of two snapshots.
  Can the animation ever disagree with the state, or leave the map showing the
  pre-tick world if a sortie ends unusually (death, quit, alt-F4, no kills)?
- `sortie.tscn` keeps a *standalone* leg that resolves the war itself, and the war
  room has its own. Two paths that price a sortie into a war is exactly the shape
  of a divergence bug — are they equivalent?

### Track 3 — Determinism and the save file

The war sim's purity is load-bearing: same seed must mean same war, and the save
must round-trip bit-exactly.

- Every evolving float is supposed to pass through `WarSim.quantize`, and
  `snappedf` is banned in `scripts/war/` because it is not decimal-exact. Verify
  both, by grep and by reading the arithmetic.
- The save is `var_to_str`, never JSON, because JSON loses `StringName` and turns
  an int RNG state into a float. Is there any other serialisation path (debug
  dump, profile, blackbox, presets) that could round-trip war state through JSON?
- Weather is supposed to have **its own dice**, seeded per (theater seed, node id,
  tick), specifically so that *looking at the map cannot move the war*. Confirm no
  path draws weather from the shared stream, and that a forecast cannot advance
  any RNG the campaign depends on.
- Does anything in the game read `user://` state that the *checks* also write?
  One test already deleted a live campaign this way.

### Track 4 — The bridge: sortie composition, the runner, and the ingress

`scripts/war/sortie_composer.gd` (451) → `scripts/sortie/sortie_runner.gd` (717).
The runner is the only place a spec becomes a Node3D. Newest code in the repo.

- **The ways a sortie can hang with the pilot alive and nothing to do.** That is
  the failure class this code has had twice. Each archetype's end condition:
  strike/sead/decapitation/raid end on egress after objectives; dogfight ends when
  the field and reserves are clear; interdiction and strike_cap are the two least
  exercised. Is there an archetype where a legal player action can leave the
  sortie unendable? Five of the seven have never been flown by a human or
  measured by a bench.
- **Triggers.** Every `TRIGGER_ON` value must have a firing site in the runner
  (`sortie_check` scans source text for this — is that scan sound, or can it be
  satisfied by a comment or a dead branch?). Can a reserve fire twice, or never?
  Note Godot hashes Dictionaries by content, which has already collapsed two
  structurally identical reserves into one.
- **The ingress** (2026-08-03, `SortieRunner.ingress_range()`): a remap of the
  composer's fiction units onto this arena's band, claimed to be **order
  preserving**, and required to sit above `EGRESS_RADIUS` and below the 220 m
  signal leash in `sortie.gd`. Verify the monotonicity claim over the real input
  range, including the degenerate ends, and verify the bounds cannot be violated
  by any spec the composer can emit.
- **The objective/egress coupling**: flatten the structures, fly back out. What
  happens if a structure is destroyed by something other than the player, or if a
  reserve arrives after egress opens?

### Track 5 — The instrument: why two benches do not reproduce across processes

The highest-value open question in the project, and the one where a fresh reader
has the best odds, because the author has a hypothesis and hypotheses are sticky.

The signature: identical command, identical settings, two separate processes,
different results — and the *pilot's own shot count* differs, which means the
drone flew a different flight. Cells run earlier in a process appear to change
cells run later.

The author's leading suspect is a 14° threshold inside the reference pilot. **Do
not simply restate it.** The specific thing wanted from you is an enumeration of
**process-global mutable state that survives between cells in one process**.
There are 15 `static var` declarations across 9 files:

```
scripts/audio/sound_bank.gd      scripts/war/war_manifest.gd
scripts/combat/jamming.gd        scripts/war/war_save.gd
scripts/combat/run_mods.gd       scripts/warroom/war_launch.gd
scripts/drone/blackbox.gd        resources/tunable_config.gd
scripts/menu/menu_launch.gd
```

For each: can a bench cell mutate it and the next cell read the mutation? Add to
that list anything else that is process-scoped rather than arena-scoped — shared
`.tres` resource instances (the project deliberately shares config instances so
that live edits propagate, which is exactly the hazard), pools, groups,
autoload-alikes, the physics server's state between arena teardowns, node
iteration order, and any seeding done once per process rather than once per cell.

Then propose **one cheap decisive test** that would separate "shared state" from
"chaotic divergence from an epsilon". Name the exact instrumentation and the exact
comparison. A test that costs one run and answers the question is worth more than
ten plausible mechanisms.

### Track 6 — Documentation drift

Four docs are load-bearing and were written by the same agent that wrote the code,
which is the classic drift setup: `CLAUDE.md` (60 lines, the operating manual),
`TESTING.md` (441), `BALANCE.md` (677), `HANDOFF-NEXT.md` (400).

Check the **specific factual claims**, not the prose. Every number, path, scene
name, group name, action name, class name, default value and command line in
those four files should exist in the code as stated. The last audit found real
drift here. Report drift as a table: claim → doc:line → reality → code:line.

### Track 7 — Fresh eyes on the aegis (design-adjacent, observational only)

The current iteration's premise is that the aegis "is two enemies wearing one
name" — a bomber that flies to a target and detonates, and something else. Read
`scripts/combat/aegis.gd`, `shield_shell.gd`, its `EnemyConfig`, and the
`Iteration 14` section at the tail of the design doc (around line 10365). You are
**not** being asked to design the rework. You are being asked: does the code
support the premise, is there a third behaviour nobody has named, and is there any
way its shield/detonation interacts with player weapons that the bestiary check
would not catch?

### If budget remains, in this order

1. `scripts/drone/motor_model.gd` damage coupling and `combat/repair_gate.gd` —
   a review of this pair was queued and deferred; it has never been done.
2. `scripts/ui/debug_overlay.gd` (756 lines) — the largest file, the one that
   writes live into every config, and the one with the most ways to corrupt a
   `.tres` the human then saves.
3. `scripts/environment/city_layout.gd` (659) and the procgen pair — determinism
   under seed, and whether its two checks are real.

---

## 6. Running things safely

Optional. If you do run anything:

```
# parse check one script
<godot> --headless --check-only -s scripts/<file>.gd --path .
# boot check
<godot> --headless --quit-after 10 --path .
# one headless check (exit code is the verdict — do NOT grep for a tag,
# several checks print a shortened tag and a tag-matching loop misreports them)
<godot> --headless -s scripts/tests/<name>_check.gd --path .
```

**Two hazards.** (a) The human has a live campaign in `user://war.save` and live
tuning in `user://flight_*.tres`, `user://presets/`, `user://input_bindings.tres`.
Checks are supposed to borrow-and-restore those; one of them didn't, once. Back
that directory up before running the suite, or don't run it. (b) The long benches
(`delivery_bench`, `matchup_harness`, `sortie_bench`, the full `balance_report`)
take tens of minutes and **overwrite measurement artifacts** in `balance/`. Do not
run an unfiltered bench. A *filtered* bench run is explicitly a look, not a
measurement, and writes nothing:

```
<godot> --headless -s scripts/tests/delivery_bench.gd --path . -- "kestrel x raider"
```

If you run something and it disagrees with a doc, that is a finding; say exactly
what you ran.

---

## 7. The deliverable

One file: **`AUDIT-HANDOFF-2026-08-04.md`**, written to the repo root. Nothing
else. It will be read cold by an agent with no access to your session, so it must
stand alone — no "as discussed above", no references to your reasoning process.

Required shape:

```markdown
# AUDIT HANDOFF — QuadShot, 2026-08-04
HEAD audited: <sha>.  What I ran: <commands, or "nothing">.
Coverage: <which tracks, which files read in full vs skimmed, what I did not reach>.

## Verdict in five lines
<The five things that matter most, in priority order, one line each.>

## Findings
<Ranked by blast radius. Use the template below. Number them F1, F2, ...>

## Checked and clean
<Table: what you examined and found sound. Negative results have real value —
they stop the next audit re-reading the same file. One line each.>

## Could not determine
<Things that need a run, a flight, or a human decision. Say what would settle each.>
```

Finding template — every field mandatory:

```markdown
### F<n> — <one-line claim, stated as a defect, not as a question>
- **Where:** `path/file.gd:LINE` (+ any other sites)
- **Severity:** campaign-destroyer | correctness | instrument | drift | hygiene
- **Confidence:** CONFIRMED (I traced it end to end) | LIKELY | SUSPECTED
- **The failure:** concrete inputs or sequence → the wrong outcome. Not "may cause
  issues". If you cannot write the sequence, downgrade the confidence.
- **How to prove it:** the exact mutation, run, or trace that decides it — cheap
  enough to be worth doing.
- **Blast radius:** what breaks downstream, including the human's saved campaign.
```

Ordering matters more than volume. Put anything that can destroy the human's save,
silently fork the war, or make a bench lie, above everything else. A finding you
are unsure of is still worth reporting **if** it is located and falsifiable — mark
it SUSPECTED and let the author kill it. Do not pad the list; twenty located
findings beat sixty guesses, and the "checked and clean" section is where thorough
reading gets credit.

Two things the author explicitly does **not** want in the file: praise, and
prescriptions. Report the defect and how to prove it, not the patch you would
write. Where a fix is genuinely non-obvious, one sentence naming the approach is
enough.

---

## 8. Vocabulary you will meet in the code and docs

Defined here so you do not have to reverse-engineer them:

- **sortie** — one flyable mission. **theater** — the generated 30-node campaign
  map. **node** — one place on it. **tick** — one turn of the war sim.
- **dent** — the damage a flown sortie prices back into a node's abstract garrison
  strength. **cleared fraction** — the dent expressed as a fraction of the node's
  strength; the difficulty signal that replaced completion rate when the latter
  saturated at zero.
- **spec / `sortie_spec`** — the Dictionary the composer emits describing a
  mission: archetype, objectives, layered garrison, triggered reserves, approach.
- **archetype** — mission type (strike, dogfight, sead, strike_cap, decapitation,
  interdiction, raid). **reserve** — enemies held back and released by a trigger.
- **ingress / egress** — where you start the approach, and the radius you must fly
  back out past to end a strike. **the leash** — the FPV signal-loss radius.
- **the board** — the 19 headless checks. **the harness / the instrument** — the
  balance measurement layer (`scripts/balance/` + the benches).
- **SDI** — sortie difficulty index, measured by the harness, never authored.
- **PILOT_VERSION** — the pinned version of the bot pilot that does the measuring;
  factors measured by a different pilot version are not comparable.
- **frame** — a player airframe (Kestrel, Atlas); a frame carries its own flight
  model plus hull/armor.
- **jam level** — one scalar, 0 clean to 1 fully jammed, read by four consumers
  (gun director, missile lock, flak fuse, video feed).
