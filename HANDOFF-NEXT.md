# HANDOFF-NEXT.md — where things stand, and what is waiting

A self-contained brief for a fresh session. Read [CLAUDE.md](CLAUDE.md),
[TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md) first, then the tail of
[GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md) (entries v1.94–v1.98, plus Iteration 12
itself) for how the current state was arrived at.

**HEAD when this was written: `fddea3c`, with Iteration 12 phases 1–3 in the
working tree and NOT yet committed. `PILOT_VERSION` is 7. 18 headless checks,
all passing. The balance board is GREEN on all three layers.**

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
   format — invoke the `commit-message` skill. **The user commits manually; hand
   the message over rather than running `git commit`.**
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

Three phases shipped, all covered by checks:

| phase | what |
|---|---|
| 1 (v1.96) | the falx and screamer join `WarManifest`; `gnats` → `gnat`; the escort rule enforced |
| 2 (v1.97) | `SortieRunner` + `ObjectiveAsset` + `scenes/sortie.tscn` + `sortie_check` |
| 3 (v1.98) | `WarSim.apply_sortie` + `WarSave` + `war_loop_check` |

**NOT YET FLOWN BY HANDS.** Nothing in a composed sortie is balanced, and per H6
it must not be tuned before it is measured. Node 8 fields eight turrets and may
well be brutal; that is a number to *read*, not to fix.

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
- **The delivery bench does not reproduce, and it is the TURRET** (v1.95b). 34
  of 47 factor cells came back bit-identical across two runs of the identical
  command; **all five movers over 0.09 are turret cells**, and the ORDERING
  inverted — `kestrel x turret [jink]` read 0.08 then 0.36 against a `[steady]`
  of 0.40 then 0.22, i.e. "dodging helps fivefold" and "dodging hurts" from the
  same command. Every raider cell reproduced exactly. Likely cause is sample
  size: an `evade` cell resolves 2–18 hits out of 38–50 rounds, so 0.04 vs 0.16
  is *six rounds*. **The fix is longer cells and it costs bench minutes — an
  unmade scope call.** Until then, read the turret column's order as unproven.
- **Nobody has measured a human hand-aiming with the gun director OFF.** Until
  that exists every jammed gun cell is bot-bounded.
- **`ammo_check` failed once inside a batch and could not be reproduced** — 5
  standalone runs and a second full batch all green, and nothing in the change
  set touches it. Recorded rather than dismissed because this project has been
  bitten by exactly this shape before (`run_check`, v1.92: *"it passed alone and
  failed in a batch"*). If it recurs, capture the failing assertion text — my
  batch loop had swallowed it, which is why there is no diagnosis here.

---

## 4. THE NEXT OBVIOUS THINGS

1. **Fly a composed sortie** (§1). Everything below is better informed after it.
2. **W.q4 / W.q7 / W.q2** are deliberately unanswered pending that flight: how
   `spec["pads"]` spends on the shipped gate family, whether the pilot flies the
   ingress, and whether the M4 arcade run survives alongside the campaign.
3. **A map / node-selection screen.** You currently fly what `--node` names.
   This is UI over systems that already work, and it is what makes the campaign
   feel like one.
4. **H9's sortie layer** — the reference pilot flying composed sorties to
   *measure* SDI. This is the instrument H7 has been waiting for, and it is the
   real path to the 127→25–40 recalibration.
5. **The signal leash, applied to `main.gd`.** The sortie scene now anchors it
   at the sortie centre rather than the world origin, which is the correct
   framing and needed no retuning. `main.gd` still measures from the origin, and
   **three separate features have now tripped that** (the egress, Iteration 11's
   transit gate, W9.1's 400 m ingress). Worth fixing the day anything moves an
   arena.

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
| v1.93 | the wave-clear re-arm retracted; solid gates; salvage beacons |
