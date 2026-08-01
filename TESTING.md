# TESTING.md — how to run everything, and how to WATCH it

Every bench in this project runs headless by default and prints numbers. Drop
`--headless` and it renders instead, from the rig's own FPV camera. That is
policy, not a nice-to-have (v1.25, the user's call: *"essential"*) — the aegis
ramming bug survived days of reasoning about numbers and thirty seconds of
watching would have caught it.

Godot lives at `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe`. Use the
`_console` build from a terminal so you see output. Everything below is run from
the repo root. `<godot>` means that path.

---

## 1. The fastest thing you can do: watch one cell

```
tools\watch_matchups.cmd  screamer
tools\watch_delivery.cmd  jammed
```

**Any words you pass are a filter** — only cells whose name contains them run.
Without a filter you get all 29 duels or all 49 delivery cells, which is 20–40
minutes of staring before the interesting one arrives. With one it is a minute.

A filtered run is a **LOOK, not a measurement**: the delivery bench refuses to
write its factors file, and the duel harness skips every pass/fail assert. Both
say so in a banner. Looking can never damage the ruler.

---

## 2. The two benches worth watching

### The duel harness — real fights

```
<godot> -s scripts/tests/matchup_harness.gd --path . -- <filter>
```

A real drone, a real weapon, a real enemy, flown by the scripted reference
pilot. 6 reps per cell, 10 s cap. In watch mode you also get **the real game
HUD**, fed by the same reticle solver the game uses — so what you see over the
bot's shoulder is what you would see over your own.

Useful filters:

| filter | what you will see |
|---|---|
| `screamer` | the four EW cells — **this is where to watch the pilot take its own trigger** |
| `falx` | boom-and-zoom passes, and the flak answer to them |
| `atlas` | the heavy frame, including the two outnumbered cells it loses badly |
| `gnats` | swarm behaviour and why the missile bankrupts against it |
| `aegis` | the shield gate: chip fire splashing off forever |

### The sortie bench — composed sorties, and where difficulty is MEASURED

```
<godot> --headless -s scripts/tests/sortie_bench.gd --path . -- <filter>
```

The reference pilot flies **composed sorties** — every slice-ready node of a
theater, against all three weapons — and the completion rate that comes out is
the **SDI**. H6 is explicit that difficulty is measured and never authored: the
composer sets inputs, and this is the thing that reads the difficulty back out.
Until it existed, the only difficulty signal in the project came from
`war_soak`'s abstract proxy, which is a coin weighted by a `skill` float.

**Read `dent` before you believe a completion rate.** A cell reading 0% is
equally consistent with a hard sortie and a broken rig, and the dent is the
cheapest way to tell them apart: it is the war-currency value of what the pilot
actually destroyed. 0% with a dent of 9.6 is a hard fight; 0% with a dent of 0.4
is a pilot that could not fight.

**The weapon is an axis, not an assumption**, and a node's SDI is what its BEST
answer achieves. Grading a node with a weapon it hard-counters measures the
loadout mismatch and calls it difficulty — a blaster against three gnat packs
reads 0% for reasons P4.3 wrote down years before this bench existed.

Three stated limits, all in the file header: it does **not** fly the egress (the
reference pilot has no egress behaviour, and teaching it one would cost a
`PILOT_VERSION` bump), the **retargeting policy is the bench's** rather than the
pilot's, and individual reps are **not** reproducible — the rate is the
measurement, no single rep is.

### The delivery benches — isolated measurements

```
<godot> -s scripts/tests/delivery_bench.gd --path . -- <filter>
```

Four kinds of cell, and they measure different things:

- **`aim:`** — the pilot shoots a target that cannot move, shoot, or die. This
  is the bot's marksmanship and nothing else.
- **`evasion:`** — the drone is FROZEN and its gun is re-laid onto the perfect
  firing solution every tick. Anything it misses, the *target* dodged.
- **`evade:`** — reversed: an invisible perfect-aim threat shoots at the pilot
  while it flies the aim task. How well the airframe dodges.
- **`contact:`** — a gnat cloud arriving. Measures *when*, not *whether*.

Useful filters: `jammed`, `evade: atlas`, `kestrel x raider`, `flak x gnats`.

---

## 3. Running the actual game

```
<godot> --path .                          the flyable menu tower (boot scene)
<godot> --path . scenes/main.tscn         straight into a run
<godot> --path . scenes/dev_map.tscn      the dev room — one of every element
<godot> --path . scenes/city_map.tscn     the procedural city
<godot> --path . scenes/sortie.tscn       a COMPOSED SORTIE from the war (see below)
<godot> --path . scenes/war_room.tscn     the WAR ROOM - the campaign as a map
<godot> --path . scenes/aim_drill.tscn    the human aim drill (see §5)
```

### The war room (Iteration 13, phase 1 of five)

```
<godot> --path . scenes/war_room.tscn                    resume the saved campaign
<godot> --path . scenes/war_room.tscn -- --no-persist    look without touching the save
<godot> --path . scenes/war_room.tscn -- --seed 99       a different theater
```

The theater as a hex table: **prism height is garrison**, green is yours, red is
theirs, dim red is out of strike range, slate is an archetype the slice cannot
build yet, the amber wall is the front line and the thin coloured plates are
supply. Click or arrows select; ESC returns to the menu.

**The card is the first place P1.3's fog has ever reached a human.** It runs
`compose_briefing`, not `compose` — what intel *believes*, not what is there:

| intel age | the card shows |
|---|---|
| current | `INTEL: EXACT` — the named unit list, counts and all |
| 2-5 ticks | `INTEL: FAMILIES` — air / swarm / static by strength |
| older | `INTEL: STRENGTH ONLY` — the abstract number the war-sim itself keeps |

A fresh theater's enemy ground reads **NONE - never scouted**, so every node
starts at the bottom tier and the fog lifts only where you have been. Your own
nodes skip intel entirely and report their real garrison.

The weather line carries a **1-tick forecast** (`fog, holding` / `clear, fog
forecast`) and it is exact rather than probable — C.q4 gave weather its own dice
precisely so "wait a tick for the fog" is a decision you can make.

**Phases 1-2 read and brief; nothing launches.** No sortie starts from here yet,
the war does not tick, and the save is never written — so opening it cannot cost
you a campaign.

### Flying a composed sortie (Iteration 12)

The first scene in this project whose contents came out of the war-sim rather
than out of a level. It generates a theater, composes one node into a
`sortie_spec`, and builds exactly what the spec describes.

```
<godot> --path . scenes/sortie.tscn                      first slice-ready node
<godot> --path . scenes/sortie.tscn -- --node 8          a specific node
<godot> --path . scenes/sortie.tscn -- --seed 99 --node 3
```

**It prints its own briefing before you arm**, which is the fastest way to see
what the composer actually produced:

```
[sortie] seed 4242, node 8 (factory / industrial, clear)
[sortie]   STRIKE: destroy production x3
[sortie]   outer  2xraider 3xgnat
[sortie]   mid    6xturret 1xgnat
[sortie]   inner  2xturret
[sortie]   reserve on objective_damaged after 9.6s: 7xraider
```

Two archetypes exist. A **dogfight** (`airspace` nodes) has no structure — clear
the field and its reserves. A **strike** (`factory`) has three hot-white
structures at the centre; flatten them and **fly back out past 105 m** to finish
(W.q3: a strike ends on egress, so the reserve that scrambles when you touch the
objective has something to arrive to). On seed 4242, nodes 8 and 11 are strikes
and most of the rest are dogfights.

**Read the `pads:` line before you arm — it is the sortie's difficulty in one
number.** A pad is a repair gate (always the first one) or a resupply gate, and
the count is *derived from the node's own garrison*, never authored: heavily
defended nodes are pad-poor (P2.6). Node 8 gets **zero**, which is why flying it
means flying a broken drone the whole way — that is the design working, not a
missing feature. Across seeds the spread is 0 pads (rare), 1, or 2 (most common).

**Nothing here is balanced and none of it should be tuned yet** — H6 is explicit
that difficulty is measured, not authored. The first flights exist to produce a
number, not a good one.

Fly a different frame without editing anything:

```
<godot> --path . scenes/dev_map.tscn -- --frame atlas
```

**Where the specimens are in the dev room:** Falx at (−95, 26, −70), Screamer at
(75, 24, 55), aegis at (70, 20, −90), gnat swarm at (−60, 12, 40), turrets and
the city block around the middle.

---

**It is a CAMPAIGN, not a level.** The result is priced back into the war
(`WarSim.apply_sortie`), the war takes a turn, and the state is written to
`user://war.save` — so the next launch resumes where you left it and says so:

```
[war] resumed tick 3, 5 pilots, 2 sorties flown
[war] node 8 (factory): garrison 35.80 -> 21.40 (dent 14.40)  degraded
[war] tick 4  pilots 5  war continues
```

Everything you destroy dents the node even if you die (P2.q4), so a failed
sortie still weakens the target. `-- --fresh` starts a new war; `-- --no-persist`
leaves the file alone entirely.

## 4. The check suite — 19 headless checks

Run all of them before believing anything:

```
<godot> --headless -s scripts/tests/<name>_check.gd --path .
```

`hover`, `combat`, `wave`, `missile`, `run`, `repair`, `motor_damage`, `menu`,
`manifest`, `sortie_compose`, `lethality`, `falx`, `screamer`, `composition`,
`heat`, `ammo`, `sortie`, `war_loop`, `war_room`.

`falx` and `screamer` are **behaviour checks**, and every new enemy type gets one
the day it lands. The reason is scar tissue: the harness can only ever say *"this
cell reads 0%"*, which is equally consistent with a tough enemy, a broken enemy,
and an enemy that has flown out of the level. Four separate Falx bugs looked
identical from the results table.

`screamer_check` is the current example of how much that buys — five phases:
does it stay put, does a missile lock work at all (control), does its jam fade
across both ends of its field, does it hold a standoff, and **can it actually be
caught** by a pursuing pilot.

`heat_check` guards the blaster's duty cycle (v1.91), and the failure it exists
for is the worst one available: a gun that locks out and **never comes back**
leaves a pilot alive, armed, and unable to clear a wave. Nothing else in the
suite would notice, because every other check either kills its enemies with
`take_hit` or never holds the trigger long enough to overheat. It also asserts
that Layer 1's duty-cycle arithmetic matches the real weapon — which
`lethality_check` structurally cannot do, since that bench plants shots from the
model itself and would agree with itself all the way to the wrong answer.

`war_room_check` is the nineteenth (Iteration 13), and it guards the map's
DERIVATION rather than its pixels — the hex projection tiling without collisions,
the front line being sound *and* complete, and the room's reach agreeing with the
war-sim's. **The card is checked as TEXT**, which is the only way to assert the
one bug it can have: a card that leaks the truth through the fog still looks
perfect on screen. So one node is rendered at three intel ages and the
load-bearing assertion is the negative one — *at 99 ticks no unit type name
appears anywhere in the card*. And because the forecast is a promise about the
future, it is checked against the future happening: forecast every node, run a
real tick, compare.

Two of its assertions are deliberately awkward to write, because the
easy versions cannot fail: the strike range is compared against a second,
independently written walk of the graph rather than against the function under
test, and the supply check severs a line and asserts the cut edge is **gone**.
The three-node version of that cut was written first and **passed under
mutation** — removing the supply test from `WarView` entirely did not break it,
because severing the middle of three nodes also removes every same-owner
adjacency. It takes four nodes to make the assertion real.

`war_loop_check` is the eighteenth, and it guards the joint that turns a sortie
generator into a campaign: the dent reaching the war, the capture gate flipping
ownership, a **dead** pilot's sortie still resolving, and the save surviving a
round trip. It asserts the save-format decision too — that JSON *would* lose
StringName and int — because that failure writes a perfect-looking file and
forks the war silently. **It caught a real bug on its first run**:
`FileAccess.get_as_text()` reads from the start of the file regardless of the
cursor, so the header comment was being fed to `str_to_var`, which tried to
parse the campaign as a Color.

`sortie_check` is the seventeenth (Iteration 12), and it guards the three ways a
composed sortie can hang with the pilot alive and nothing to do: a **strike**
whose egress never opens, a **dogfight** — which has no objective at all, so the
field-cleared path is the only thing that can end it — and a **reserve** that
fires twice or never. That last one is not hypothetical: a dogfight carries two
reserves both keyed `wave_cleared`, and Godot hashes a Dictionary by content, so
a spent-flag keyed by the trigger itself would collapse two structurally
identical waves into one and silently never fire the second.

`ammo_check` is `heat_check`'s mirror (v1.92): not a gun that never comes back,
but a magazine that never refills. There are four ways to put rounds back and
each is a separate way to be silently broken - firing spends and a dry launcher
refuses, a gate fills only its own kind and spends exactly one charge, a spent
gate is inert (or R.q4's finite charges mean nothing), and clearing a wave
re-arms both. Plus the two cases that punish a careful pilot if they regress: a
gate must not eat a charge against a full magazine, and salvage must not consume
itself against one.

`composition_check` is the same idea one level up, for the wave director's
roster (v1.85). Part A sweeps 320 compositions with no arena at all — every wave
spends its whole budget, names only real types, and contains something that
threatens you — and asserts that **every roster type actually reaches a wave**,
which is the exact bug the item fixed. Part B flies three real sorties, clears
every wave, and checks the arena against the table. Three types can deadlock a
wave in a way a body count cannot see, so all three are exercised on purpose: a
gnat **cloud** is one unit and nine bodies and reports `cleared`, a **turret**
respawns on a timer, and an **aegis** can leave the field without dying — the
bombers are deliberately let through so the detonation path is under test.

---

## 5. The full balance report

```
tools\balance_report.cmd
```

Runs the three layers in order — lethality arithmetic, then the delivery
benches, then the duels — and stops at the first failure, because nothing
downstream means anything after one. **Takes about 45 minutes.** Read
[BALANCE.md](BALANCE.md) before acting on anything it prints; in particular, a
gap between the predicted and validated columns is the instrument's *output*
(it names something the model does not know about), not a number to tune away.

### The human aim drill

```
<godot> --path . scenes/aim_drill.tscn
```

The bot's exact aim ruler, flown by your hands. Results land in
`user://blackbox/aim_drill_*.json` and are recorded as *deviation* data — they
never enter the base table. Flown 2026-07-24: human 0.21 with the blaster
against the bot's 0.17, human 1.03 with flak against the bot's 0.99.

**Currently missing, and it matters:** that drill was flown with the gun
director ON. Nobody has ever measured a human hand-aiming with it OFF, which is
exactly the number that would settle whether the Screamer hard-counters the chip
gun or merely taxes it.

---

## 6. Reading the output

- **duty cycle** is printed beside every rate, and you have to read it. `aim` is
  hits per shot *fired*, so two weapons with different trigger policies produce
  numbers that are not comparable. Flak reading 0.99 against the blaster's 0.17
  is two different rulers, not a better gun.
- **`evade:` rows read backwards from the word.** They are stored as a connect
  rate, so **low is evasive**.
- **Compare modes within a single run, never across runs.** The ordering is the
  finding; the decimals move. A jinking cell can swing 2× between runs.
- **A delta of ~0.09 or more is a real movement**; anything at or under ~0.04 is
  not readable.
- Every report prints the `PILOT_VERSION` it was measured under. Numbers from
  different pilot versions never belong in the same table.
