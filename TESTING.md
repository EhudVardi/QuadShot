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
pilot. 6 reps per cell, 10 s cap.

**THE CAP BOUNDS WHAT SOME ROWS CAN SAY, and two types are past it.** The
Phalanx carries 1300 points of mounts and hull behind a shield that is shut
most of the time, so no weapon finishes it inside 10 s and all three of its
rows read `--`. The Aegis rows are bounded for a different reason (v2.22: the
intercept clock cannot resolve a bomber that needs three passes).

**This does NOT produce a false finding, and the harness is why.** The
un-modeled-factor flag only fires when the model and the fight DISAGREE, and
`model_kills` already requires the predicted ttk to fit inside the cap — so
for these bodies both columns say *no kill in 10 s* and agree. What you cannot
do is read their **paper** bands as refuted: a counter-web band is a claim
about a fight, and a 10 s duel is not a long enough fight to test it on a body
this size. If that needs settling, the honest fix is a per-row cap rather than
raising `MAX_SECONDS`, which would move every published band on the board. In watch mode you also get **the real game
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
| `phalanx` | the tracking arc, and a body the 10 s cap cannot finish |

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

**Read `cleared` before you believe a completion rate**, and read `dent` before
you believe either. The first full-theater sweep (2026-08-03) returned **0%
complete at every depth** — a saturated column with no resolution — while the
`cleared` fraction fell 54% -> 21% from depth 3 to depth 7. When the pilot always
dies, "how much of the node did it take apart" is the metric that still has a
gradient in it.

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

### The approach bench — what the garrison can do to you on the way IN

```
<godot> --headless -s scripts/tests/approach_bench.gd --path .
<godot> --headless -s scripts/tests/approach_bench.gd --path . -- --nodes 8,12 --speeds 6,14,26
```

Built 2026-08-04 to answer the one test **GAMEPLAY-DESIGN v2.16** named, after the
user flew the new ingress and reported *"on both cases the enemy did not attack me
until i engaged."* It flies a **sled** — a body moved along the spec's own ingress
bearing at a fixed speed, no return fire, no evasion — and logs what the garrison
manages to do to it.

**Speed is the independent variable**, not a constant, because the hypothesis
under test is about speed. Picking one "cruise speed" would beg the question.

**It is a SLED rather than `ReferencePilot` on purpose.** The question is what the
GARRISON can do to a crossing target; a fighting brain would orbit, shoot back and
change the geometry, and it carries the cross-process reproducibility debt that
makes every other bench number unattributed. Its `linear_velocity` is real, so the
enemies' lead solution is the real one.

Four readouts, and the last two are the ones that decide anything:

- **the engage gate, decomposed** — out of range / no line of sight / ENGAGED, as
  a percentage of gun-frames. This is what separates *"shoots and misses"* from
  *"never shoots"*, and it is what cleared `_has_line_of_sight` and the armed gate.
- **shots and hits by distance band** from the sortie centre.
- **how close the rounds came** — the closest approach of every enemy round.
  A round passing 2 m away and a round passing 30 m away are different problems
  wanting different answers, and this is the only column that tells them apart.
- **who contests, by bestiary type** — shots and engaged-frames per placed body,
  which is how A.q7's *"does the falx already do this job"* gets an answer instead
  of an opinion.

**Contact stings are counted separately from shots, and that is load-bearing.**
`gnat_swarm.gd` damages by distance test with no projectile and no cooldown, so
the shot counter cannot see it while `Health.struck` can. The first version fused
them and printed a **250% hit rate** on node 8 — the instrument saying out loud
that it was measuring two things and calling them one. A sting always kills the
gnat that delivered it and the sled never fires, so any gnat body lost is exactly
one sting; the split is exact rather than a proximity guess.

It writes **no artifact and asserts nothing**. It is a reading for a human, and
per H6 nothing it prints licenses a tuning change.

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

#### The reproduction instrument (Track 5, 2026-08-05)

```
<godot> --headless -s scripts/tests/delivery_bench.gd --path . -- --trace <dir> [filter]
<godot> --headless -s scripts/tests/delivery_bench.gd --path . -- --range 27:39 --trace <dir>
```

`--trace` writes one CSV per cell with the whole simulation state every physics
tick at full precision; `--range A:B` runs cells by INDEX so a history can be
bisected (a name filter cannot express a prefix). Both make the run a LOOK, so
neither can overwrite `delivery_factors.json`.

**What they are for, and what they found.** Diff two trace directories and read
the FIRST tick that disagrees — that names a mechanism instead of ranking
suspects. An isolated cell is **bit-for-bit identical across two processes**
(6720 ticks); a three-cell run is not, and measured `evade: kestrel x raider
[jink]` at **0.29 and 0.00** from the identical command. The divergence is a
binary **-0.0817 rad/s** pitch impulse on a cell's first tick, present or absent,
and **the first cell of a run never diverges**. Full reasoning in BALANCE.md and
GAMEPLAY-DESIGN v2.22.

**Two rules for using it.** Compare full float precision, never rounded — the
whole value is in the first differing tick. And check that the trace's own rows
CHANGE between ticks before believing an "identical": the first version of this
instrument formatted with `%.17g`, which GDScript's `%` operator does not
support, so it silently wrote the format string 6720 times and four separate
comparisons came back "bit-for-bit identical" on literal text.

### The feasibility bench — the engine's own walls

```
<godot> --headless -s scripts/tests/swarm_bench.gd --path .
<godot>            -s scripts/tests/swarm_bench.gd --path . -- "kill roc 20"
```

Iteration 16 / L13 phase 0.1, and it answers the user's own question — *"can ~10
kestrels level frames hurt a roc level frame"* — plus the one behind it: where
does this engine stop? Two tables, deliberately never conflated. **A** sweeps
unit counts and reports how many physics ticks per second the scene can supply;
**B** puts N raiders against one hovering frame of each size and reports how fast
they kill it. Takes about six minutes for the full board.

**Read the header before trusting a number here.** Three things it refuses to
do, each on purpose: it never measures the heavy frame shooting *back* (the
reference pilot is Kestrel-tuned, so "the Roc lost" would be a confound, not a
result); the target never evades, so table B is the swarm's *ceiling*; and
headless means no rendering, so table A is the floor of the real cost.

**The load measurement is not the obvious one, and the obvious one is a lie.**
Wall-clock between physics ticks reads 4.169 ms at every unit count, because
Godot paces physics to real time and simply waits when there is headroom — a
sweep of it is a flat line that looks like a beautifully optimised game.
`Performance.TIME_PHYSICS_PROCESS` is not the fix either (probed: it does include
the server step, but at 1600 bodies it claims 22 ms per tick while the simulation
demonstrably holds real time at 4.17). What works is raising
`Engine.physics_ticks_per_second` far above 240 so the pacing has nothing to wait
for; the engine then delivers as many ticks per second as the machine can
compute, and that number *is* the capacity. The distortion-free half — did the
cell hold a true 240 Hz — is reported beside it, and the two agree at the wall.

### The city load bench and the tunnelling check — the world's own limits

```
<godot> --headless -s scripts/tests/city_load_bench.gd --path .
<godot> --headless -s scripts/tests/tunnel_check.gd    --path .
```

`city_load_bench` sweeps `CityLayout` from the old 4x5 up to 20x20 and reports
triangles, meshes, colliders and generation time. **The cost is flat per block** —
about 4800 triangles and 30 meshes each across a 20x range — so the size ceiling
is a budget decision rather than a structural one. One thing it measures that a
naive reading would get wrong: interiors add **no geometry** in the sweep,
because they are distance-LOD'd and a bench has no pilot in it, so a separate
probe puts a stand-in in the `player` group to get the real figure. Its last row
is not content — it exercises `world_scale` so the generator cannot quietly stop
honouring `block_size` again.

`tunnel_check` fires each frame's real collider at real walls at real speeds and
reports where it ends up. **Nothing tunnels at any speed the roster can reach**,
and the margin is Kestrel 2.0x, Condor 8.0x, Roc 8.0x its own terminal speed
(a dive buys only `sqrt(1 + 1/TWR)`, so 1.11x at most). **The big frame is the
SAFE one**, which is the opposite of the intuition that prompted the test: a
Roc's step is four times a Kestrel's but its body is eleven times bigger.
`continuous_cd` is reported both ways and fixes every failing case; it is off by
default and the game does not need it today.

**Keep this file's result, not a dependency on it.** The user's standing position
(2026-08-15): tunnelling is a known property of discrete-step physics, the project
is **not committed to Godot**, and the engine is *"a base to design the game
identity and see how it feels"*. So this check is a measurement to carry forward
into whatever engine the game ends up on, not a constraint to design around.

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
<godot> --path . scenes/scale_map.tscn   the SCALE YARD - how big am I? (see below)
<godot> --path . scenes/desert_map.tscn  6 km of dunes - the terrain venue (see §4)
```

### The scale yard (PLAN-FULL-SCALE phase 2, branch `full-scale`)

```
<godot> --path . scenes/scale_map.tscn
```

**Three flyable airframes at three sizes, in one unchanged world** (V10). Arm and
fly; there is no combat, no run, no signal leash.

```
1   KESTREL   0.28 m,   0.65 kg,  TWR 4.5   — the original 5-inch quad, untouched
2   CONDOR    1.20 m,  32 kg,     TWR 12    — the middle rung
3   ROC       3.00 m, 500 kg,     TWR 12    — the manned aircraft
```

**Press 1, 2 or 3 at any time.** The airframe changes on the spot and you are put
back on the pad, disarmed. All three are parked side by side on the apron at true
size with a person standing beside them, so the ladder is visible before it is
flown. **Fly the same route twice on two frames** — that is the whole instrument,
and it is why the swap is instant rather than a scene reload.

**The overlay follows the swap** (fixed 2026-08-12). Every FLIGHT and FRAME
control rebinds to the frame you are now flying, so `fpv_uptilt_deg` and the rest
tune the airframe in your hands. Before the fix they kept writing to whichever
frame was loaded at boot, so the camera angle moved on the Kestrel and did
nothing on the other two. **The sliders also widen to admit values the spec table
never anticipated** — the flight rows were authored around a 0.65 kg quad, so on
the Roc the mass slider was pinned at its 2 kg maximum and the first drag would
have snapped a 500 kg airframe down to it.

**To boot straight into one airframe** instead of starting on the Kestrel — worth
it when you want a clean session on one frame with no chance of a stray keypress:

```
<godot> --path . scenes/scale_map.tscn -- --frame roc
<godot> --path . scenes/scale_map.tscn -- --frame condor
```

Keys 1/2/3 still work afterwards; `--frame` only picks what you start in.

V.q8 (is TWR 12 right?) was answered YES by hands on 2026-08-10 and is being left
open on purpose: *"nothing to solidify at the moment, more playing around."*

**It exists because the desert could not answer it.** *"The desert is not good to
feel the change"* — and that is correct, because **a dune has no known size**. So
this map is the opposite: every object in it is built at a **real measured
size**, and the whole map is a set of things you have stood next to.

What to look at, roughly in order:

- **On the pad**, press **X** for the chase camera, then **1 / 2 / 3** to walk
  the size ladder. The three parked frames are just west of the pad with a
  1.75 m person at the end of the row.
- **The arc in front of you at 45 m**: person (1.75 m), cars in 2.5 x 5 m bays,
  a 12 m bus, a 16.5 m truck, a stack of 12.19 m containers, an 8.5 m house.
  They are on an **arc, not a line**, so they are all at the same range and
  their apparent sizes are directly comparable.
- **The airfield, ~500 m north**: a 37.6 m airliner and a 70.6 m widebody parked
  beside a 45 m-wide runway. **This is the comparison the whole overhaul is
  about** — park next to the widebody.
- **The hangar's mouth is 60 x 18 m.** Fly into it.
- **The gate course** running north: 40 m, 32 m, 26 m, 20 m, 14 m apertures,
  labelled. Solid bars, so clipping one costs you. Find your own limit.
- **The height comb behind the pad**: poles at 10 / 25 / 50 / 100 / 200 / 400 m.
  Fly level with a labelled tip and you know your altitude without an
  instrument.
- **The ground grid is a ruler**: 10 m minor cells, 100 m majors, so ten small
  squares make one big one out to 2.4 km.
- Also out there: a 105 x 68 m football pitch, a 45 m pylon line at 220 m
  spacing (count towers to read distance), 135 m wind turbines, a 150 m mast,
  and a bridge with **32 m of clearance** to fly under.

**Every label turns to face you**, states the object's real size, and switches
off outside its own reading distance, so each group announces itself as you
approach. Nothing in this map is ever scaled by S — a ruler that gets scaled
stops being a ruler.

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

**ENTER flies the selected node, and that closes the campaign loop.** The room
owns the whole turn now: you launch, you fly, the result comes back, the room
prices it into the war, ticks, shows a debrief and saves. Reachable without a
command line at all — the menu tower has a **WAR ROOM** floor.

```
menu tower -> WAR ROOM -> pick a node -> ENTER -> fly it -> debrief -> the tick, played
```

**The map still shows the board you left while the debrief is up.** Dismiss it and
the war takes its turn *on screen*: hexes rise and fall as garrisons move, ground
that changed hands flashes and cross-fades, and the front line redraws last. The
caption names what moved (`THE WAR MOVES - 1 LOST - 3 WEAKENED - 5 REINFORCED`).
The map is inert while it plays, because selecting a node halfway through would
read a war that is halfway to existing — **any key jumps to the end** if you have
seen enough.

**Top right is the roster and the hangar**, across the screen from the intel card
that should decide it (P3.8): pilots remaining as marks, and your airframe with
its hull, armor and mass. **F changes airframe** and the pick rides the same
static the menu tower's frame tower writes, so the sortie flies what you chose.

Two consequences worth knowing before you fly one:

- **Death ends the sortie.** There is no respawn. The pilot comes off the roster,
  everything you destroyed still dents the node (P2.q4), and you redeploy from
  the war room (P5.4). The arcade respawn that used to revive you into an
  already-resolved sortie is gone.
- **Quitting or flying out of contact mid-sortie loses the sortie**, and that is
  P1.q4's *exit without save*: nothing was resolved, so the war reverts to its
  last saved state by nothing having happened.

`scenes/sortie.tscn` still works standalone with `--node`/`--seed` and resolves
the war itself on that leg, so the repro command above is unaffected.

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
[sortie]   ingress: 148 m from the SW (bearing 237), 4 corridor(s), cover 0.85  [spec says 187 m of open ground]
```

**YOU START OUTSIDE AND FLY YOUR OWN APPROACH** (A6, since 2026-08-03). The drone
is put down on the deck 140-195 m from the target, on the bearing the spec
carries, **facing what you came to hit** — so the whole brief is "it is straight
ahead, that far", and how you cross the gap is yours. There is no waypoint
marker: finding the target area by looking at it is the first decision of the
approach.

Two numbers make that band what it is, and both are asserted by `sortie_check`
rather than remembered: it stays **above the 105 m egress line** by 25 m (or you
would spawn on the far side of the line a strike ends by crossing) and **below
the FPV link's 220 m warning** by 20 m (or the game says SIGNAL WEAK before you
have moved). The distance itself comes from the biome: a city drops you at 140 m,
open plains at 195 m. The `ingress:` line prints the arena metres first and the
composer's own fiction figure in brackets — they differ on purpose, because
`war/` is arena-agnostic and 400 m of desert does not fit inside a 300 m link.

`corridors` and `cover` are printed and **not yet flown** — a corridor is a lane
through terrain and there is no terrain past the arena yet (P1.9).

**All seven archetypes fly** (since 2026-08-01; it was two for the whole of
Iteration 12). Everything except the dogfight ends the same way: flatten the
hot-white structures and **fly back out past 105 m** (W.q3 — a strike ends on
egress, so the reserve that scrambles when you touch the objective has something
to arrive to).

| node type | archetype | what it is |
|---|---|---|
| `airspace` | **dogfight** | no structure — clear the field and its reserves |
| `factory` | **strike** | 3 production structures |
| `radar` / `sam` | **sead** | the dish or the launchers, ringed by **screamers** — your lock breaks as you close |
| `airbase` | **strike_cap** | crater the runway while **falx** hold the outer ring and a scramble arrives on detection |
| `command` | **decapitation** | the commander, guarded by raiders, turrets and a **screamer**, and these nodes get **no pads** |
| `depot` | **interdiction** | 3 stores behind a turret belt |
| `hq` | **raid** | 4 structures, and **shielded until the command network is broken** (P1.5) |

On seed 4242 that takes the flyable count from 9 nodes to 15. Repro any of them:
`-- --seed 4242 --node 17` (SEAD), `--node 20` (Strike-CAP), `--node 21`
(Decapitation), `--node 3` (Interdiction).

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

### The hexa — the redundancy experiment (Iteration 17 / E.q1)

```
<godot> --path . -- --frame hexa
```

Six rotors on a ring at 30 degrees off the nose, alternating 3+3. It is the
**Kestrel in every respect except the layout** — same 0.28 m, 0.65 kg, TWR 4.5,
same rates — because a hexa that also changed mass or TWR would be an
interesting aircraft and a useless experiment: nothing it did could be
attributed to having six rotors.

It is deliberately **not** in the scale yard's 1/2/3 ladder (that map is about
SIZE, and this frame is the datum's size) and **not** in the campaign hangar or
the menu tower, on the same rule the Condor and Roc follow: an experimental
airframe on a branch has no business in the game's front door.

**TWO NUMBERS ARE KNOWN WRONG FOR IT AND WERE LEFT ALONE, because they are feel
and feel is the human's:**

- `yaw_authority` 1.5 is a quad number. Yaw torque is the summed signed rotor
  output, so a 3+3 split sums to ±6 at full differential where a quad sums to
  ±4 — **this frame has roughly 1.5x the Kestrel's yaw authority from the
  identical constant**, and the direction to tune is down.
- The rate gains are a quad's. The mixer commands each rotor in proportion to
  its real moment arm, and a generated ring sits at √2 arm-lengths where the
  quad-X's corners sit at 1 along each axis, so the same `rate_p` produces a
  wider commanded spread. **Expect it to feel twitchier than the Kestrel.**

The motor audio is the third thing wanting a human: the four-emitter detune was
tuned by ear in v2.43/v2.45, and the spacing rule generalises to six but six
sources at the same per-pair beat rate is a denser texture, not the same one.

## 4. The check suite — 27 headless checks

**Run the whole board with one command** (`tools/board.sh`, added 2026-08-15):

```
./tools/board.sh          all 27, about 5 minutes
./tools/board.sh fast     skips lethality, about 2-3 minutes
```

It prints one PASS/FAIL line per check and exits non-zero if any is not green.
It exists for a reason worth knowing: **a permission allowlist matches the
command STRING**, so running the board as a shell `for` loop can never match an
entry — the loop body contains a variable and is not statically knowable. Every
board run therefore prompted for permission, forever, however carefully the
allowlist was written. One script is one command, and one command is matchable.

`separation_check` (2026-08-15) guards E4.3, the iteration's central symmetry: a
round has a footprint in METRES, so a 0.28 m Kestrel whose rotors sit 0.24 m
apart has one round straddle **three** of them while a 3.0 m Roc whose rotors sit
2.6 m apart has the same round take **one**. Nobody authors that — it falls out
of building each airframe at true size.

**The trap the file had to avoid is the obvious assertion.** "A hit damages at
least one component" passes on the code separation replaced, and so does "a hit
damages the right component". The only claim that distinguishes them is a
**comparison across frame sizes**, so every stage is the same round fired at
different airframes. It also holds that damage is CONSERVED (straddling three
costs what landing on one costs — 0.2400 on every frame, to four decimals),
that a hit stays CONCENTRATED rather than smearing, and that a hit never
vanishes on the large frame where nothing at all falls inside the footprint —
that last one is a separate code path nothing else exercises.

Three mutations are on record and each fails a different sentence: scale the
footprint by `body_m` (every frame touches the same count — precisely the
authored-symmetry mistake E4.3 forbids), drop the weight normalisation (the same
round removes between 0.1178 and 0.3763 depending on the airframe), and widen
the footprint to 8 m (the worst-hit rotor takes only 26%).

**It gained a fifth claim on 2026-08-15, when the first non-zero
`component_armor` was authored** (E4.2). Claims 1 to 4 now run with plating
explicitly **OFF** — separation decides *where* a round lands and plating decides
how much survives the airframe, and left mixed the conservation claim read the
Atlas's armour as a leak and failed. Claim 5 turns each frame's shipped plating
back on for a second pass and holds two things: plating must never let **more**
through than bare metal (a sign error is the cheapest bug here and no other claim
would see it), and a frame that *ships* plating must stop **something** — an
armour value nobody applies is untested code wearing a comment. The expectation
is read from the `.tres`, so the human can change any value without the check
arguing; what it guards is the mechanism. Two more mutations on record: delete
the `- part.armor` in `_damage_component` (all three plated frames report they
stopped nothing) and flip its sign (all three report letting more through).

**`lethality_check` gained a LOCATED phase on 2026-08-16** (E8), and it is the
witness for Layer 1's component arithmetic — E8's own words are that without shots
planted *"at NAMED LOCATIONS rather than into an undifferentiated pool"*, that
arithmetic has none. It is the only phase in the file that needs a real
**airframe** rather than a real `Health`: what is under test is where a round
lands on a machine.

It plants raider rounds on five **named bearings** — nose, front-right arm,
starboard beam, tail, port quarter — into every roster frame, counting rounds
until a rotor actually fails, and requires the calculator to have named the same
component after the same number of hits. 25 cells, and the *front-right arm* is in
the list on purpose: it is the one bearing that lands squarely on a quad's rotor,
which is the single-rotor case a footprint model could most easily smear away.

Four claims, and the second is the one with teeth:

- **The mirror.** Predicted hits and planted hits agree, and so does the
  component's ADDRESS. A model that gets the count right and the address wrong is
  the failure E7's *"the same engine hit is a lession"* cannot survive.
- **E4.3's ladder, and no single-pool model can produce it.** With plating off, a
  round on a bigger airframe fails a rotor **sooner**, because it is not divided:
  kestrel **27** rounds, condor **21**, roc **21**. The same trap
  `separation_check` names, one layer up — "the calculator predicts a number and
  the drone takes a number" passes just as happily on a model that pooled every
  round and divided by four.
- **The diffuse limit is exactly conservation.** Fire from every bearing at once
  and no component concentrates anything, so an unplated frame must read
  `rotor_count / per-hit` and nothing else — **84** on the Kestrel, the Condor and
  the Roc alike, three airframes spanning 0.28 m to 3.0 m whose *held* numbers are
  27, 21 and 21; **125** on the hexa, which differs only in rotor count. (The
  Atlas reads 134 on the same sweep, and that is the figure moving with the ROUND
  rather than the airframe — its hull plating thins every raider bolt to 5 points
  before the components ever see it.) This claim was written after it caught a bug
  in the sweep that produced it (below).
- **The plumbing, verified rather than assumed.** `main._on_player_damaged` is
  wired to `Health.damaged`, which carries what reached the hull AFTER
  `FrameConfig.armor` — so the Atlas's 8-point round arrives as 5. If that wiring
  changed, Layer 1 and this bench would both go on using the wrong figure and
  agree with each other forever. The Atlas is the roster's only hull-plated frame,
  which makes it the one controlled test of it.

**Running it found a bug in the instrument itself.** The bearing sweep started at
0, which lands exactly on a quad's four arms *and* on the four bearings where two
rotors are equidistant — so the tie-break decided a twentieth of the samples, and
the Roc's diffuse figure read 79 hits where conservation says 84 while the Kestrel
read the correct 84. That looked like a real difference between two frames and was
an artefact of where the ruler's marks fell. The sweep is half-offset now, and
claim 3 exists to keep it that way.

**And it reports one finding it deliberately does NOT assert:** at the shipped
`severity` of 0.6, no frame on the roster loses a rotor before it dies — 13 rounds
to death against 27 to the first failure on a Kestrel, 13 against 42 on a Roc, 38
against 57 on an Atlas. Whether a pilot ever *sees* a component fail is a
consequence of the severity dial, and E.q8 names 1.0 as the model's design target
while 0.6 is what ships. Asserting it would turn a legitimate dial change into a
red board.

`drill_check` (2026-08-15) guards the **pilot-in-the-loop instrument** — the
drills the human flies and the predictions they are graded against (§5). What it
guards is not "does the drill fly", it is **whether the argument can be rigged**.

Ten claims. Four of them are the instrument's spine:

- **A predicted band may not exceed 40% of what could physically have
  happened.** Every measure declares a `plausible` range, and a band hedged wide
  enough that it cannot miss fails the board. This is the claim that keeps a
  prediction from being unfalsifiable by construction.
- **A sentinel sits at the WORST end of its measure.** A reading the pilot never
  produced must never score better than a bad one, and `hold_s` is the trap:
  zero is the natural default and high is what "better" means for it.
- **The refusals.** A prediction whose fingerprint does not match what was flown,
  a prediction committed AFTER the flight, and a run carrying no fingerprint at
  all must each produce a refusal **and no verdict rows** — a refusal that still
  prints a table is a refusal nobody reads.
- **The fingerprint covers the REASONS, not only the numbers.** The claim is not
  "between 10 and 17 seconds", it is "between 10 and 17 seconds BECAUSE the
  printed tilt closes a loop that eyeballing a horizon does not", so a rewritten
  argument must invalidate the same way a moved band does.

Two more have teeth because they refuse the obvious implementation. `hold_s` is
the longest **unbroken** run in the band, so a synthetic flight with runs of 5 s
and 4 s must read 5.00 and never 9.00. And `rotor_out` measures drift and sag
from **the failure's own start**, so the synthetic pilot flies 40 m and climbs
12 m *before* the rotor is touched — a window-start implementation reads 46 and
-9 where this reads 6 and 3.

Six mutations on record, each failing a different claim: widen `hold_s`'s band to
the full range (claim 2), make `verdict` always return HIT (4), count total
in-band time instead of the longest run (5), measure rotor drift from
`samples[0]` (6), drop the fingerprint test in `refusal` (9), and fingerprint the
numbers without the reasons (10).

### The plating bench — what an armour value is actually worth

```
<godot> --headless -s scripts/tests/armor_bench.gd --path .
```

**Measurement only, no pass/fail**, and deliberately so: E.q7 dissolved the
question of what the armour numbers should come out to, so a check asserting a
target would assert the thing the user refused to author. Five tables, and the
two that matter disagree with each other on purpose.

**Table B — per ROUND, plating is worth more on a small frame.** Separation
splits a round on a 0.28 m airframe into one large share and two small ones, and
flat plating eats the small ones *entirely*. Measured: 0.006 of plating stops
0.0163 on a Kestrel-sized frame (**2.71x its face value**) and exactly 0.0060 on
a Condor or Roc, which take the whole round on one rotor. That is the opposite of
where E4.2 assumes armour gets carried.

**Table D — per FIGHT, it inverts, and this is the level that matters.** A big
frame is hit far more often, so its plating fires far more often. Per 100 raider
bolts *fired*, the Roc's 0.024 saves 1.248 of rotor capability against the
Atlas's 0.006 saving 0.142 — **8.8x more protection from 4x the plating**. E4.2's
assumption holds; it just needed the right denominator.

Table C reads the roster against every bestiary round at **both** severities,
because plating is subtracted *after* severity has scaled the round: the round
shrinks as the dial comes down and the plating does not, so one authored value
turns away 50% of a raider bolt at the shipped 0.6 and 30% at E.q8's 1.0. Table E
is the E6 guard — plating blunts a crash's rotor fraying by at most 12% (the
Roc), and a crash's **hull** damage never comes through the component path at
all, so *"can even die if faster"* is untouched.

`hud_check` (2026-08-15) guards the **airframe plate** — the HUD's top-down
picture of the aircraft, with every component drawn where it physically sits.
It exists because that widget has already carried the size-ladder scar once: the
motor block was `for i: int in 4` over a hand-authored 2×2 table, so a six-rotor
frame drew four gauges and silently dropped two rotors. **That was found by an
audit, and an audit does not run again tomorrow.**

Five claims: every rotor gets a place whatever the count; the picture is
**nose-up** (a forward rotor draws above an aft one, which is what makes a lit
gauge mean *that corner*); nothing is drawn off the plate; the structure pool
gets no place at all (it is the whole airframe, and already has the health bar);
and **the rotor ring is the same size on every frame**.

That last one has teeth and earned its keep on its first run — it caught a real
flaw in the layout it was written to guard. The ring was normalised on
`max(|x|, |z|)`, which measures a *square* while the plate draws a *circle*, so a
quad-X's diagonal rotors sat at 65 px while a hexa's ring rotors sat at 46 px.
Mutation on record: normalise on the whole airframe instead of the rotor span and
the ring becomes frame-dependent (1.7% today, because the Condor's and Roc's
lenses sit just past the rotor diagonal).

### The graze bench — why a building strike can register nothing

```
<godot> --headless -s scripts/tests/graze_bench.gd --path .
```

**Measurement only, no pass/fail.** Written to chase a flight report: *"there's a
bug where sometimes i collid with the buildings and it may not have registered,
no damage at all."*

**Three things it rules OUT, each checked rather than assumed.** City buildings do
have colliders (`WorldBuilding` delegates to `MenuBuilding`, which builds a
`StaticBody3D` with a `CollisionShape3D` per slab); `drone.tscn` does set
`contact_monitor` with 4 contacts reported; and tunnelling is arithmetic-excluded
— at 240 Hz a 1.2 m Condor moves 0.25 m per tick at 60 m/s and would need roughly
288 m/s to skip a wall.

**Stage 1 — the angle sweep — corrected a prediction rather than confirming it.**
The agent expected the priced impact to be `v x sin(angle)`, since a wall only
removes the speed going *into* it. Measured, it is about **1.4x that** at every
angle but head-on: friction also scrubs the speed running *along* the wall, and
the two together are the delta-v that gets priced. So a graze hurts MORE than
geometry says and the silent band is narrower than predicted — at 60 m/s only a
5-degree scrape was free, not the 15 degrees claimed before the bench was run.

**Stage 2 is the actual finding, and it is a defect rather than a trade-off.**
`body_entered` is an ENTER signal, and a whole building is ONE `StaticBody3D`. So
drift into a tower at 4 m/s (under the free threshold, priced at 0.00 hull), hold
contact, then fly into it at 60 m/s without ever separating: **one** crash event,
**zero** damage. The 60 m/s impact costs nothing at all. Whether a collision hurts
depends on how fast you ENTERED contact, not on how hard you are hitting — which
is exactly the "sometimes" in the report.

And a sub-threshold impact is completely silent: `main._on_player_crashed` returns
early at zero damage, so there is no hull loss, no rotor fraying and no video
spike. The airframe hits a building and the game says nothing whatsoever.

Run all of them before believing anything:

```
<godot> --headless -s scripts/tests/<name>_check.gd --path .
```

`hover`, `combat`, `wave`, `missile`, `run`, `repair`, `motor_damage`, `menu`,
`manifest`, `sortie_compose`, `lethality`, `falx`, `screamer`, `composition`,
`heat`, `ammo`, `sortie`, `war_loop`, `war_room`, `aegis`, `lance`, `phalanx`,
`terrain`, `crash`.

`crash_check` (2026-08-15) is the newest and it landed the same day as the
mechanic it guards — GAMEPLAY-DESIGN Iteration 17 / E6, where crash damage
became **peak deceleration**, `v^2 / (2 * s * g)`, instead of a raw delta-v.
Four claims, each two runs differing in one thing:

1. **Mass is not a shield.** The Kestrel and the Atlas share a 0.28 m body and
   differ only in mass (0.65 vs 1.24 kg), which makes them the roster's one
   controlled comparison — everything else changes size and mass together. The
   whole ladder is walked beside them **at a held approach speed**, because
   without that the 500 kg frame arrives measurably faster than the 0.65 kg one
   (drag scales with area over mass) and a mass comparison quietly becomes a drag
   comparison. Measured before the hold existed: a 6% spread, all of it run-up.
2. **A landing is free and a wall is not** — 3.7 g against 816 g, 219x apart,
   with the 73.5 g free threshold between them.
3. **Faster is worse, QUADRATICALLY**, and this is the stage that tells the new
   law from the old one. The old delta-v law was *linear* in speed and still
   more-than-doubled its damage on a doubled speed, because a free threshold
   makes any linear law convex — so "superlinear damage" passes on both. Only
   the **g ratio** separates them, and it must read 4.00.
4. **A crash loads every component; a bullet loads one.** It boots `main.tscn`
   rather than re-wiring the crash -> hull -> rotors chain locally, because that
   chain lives in main and a check that rebuilt it would be marking its own
   homework.

**Six mutations are on record and each fails a different sentence** — restore
the linear law, scale the crush distance with `body_m`, fray one rotor on a
crash, ignore the hit direction, return zero damage, and delete main's
`last_hit_direction` clear.

**The last one PASSED the first version of this file, and that is the lesson.**
The crash was flown on a clean airframe, where the bearing field is empty
anyway, so deleting the guard changed nothing. A crash only frays all four
rotors because `apply_hit_to_motors` finds *no* direction — and a hit the
plating eats entirely never emits a damage event, so nothing clears the bearing
it set (the Atlas ships with 3 armor, so this is reachable in the game). The
crash is now flown with that stale bearing deliberately planted, and the
mutation fails immediately.

**It also found a live `user://` leak**, which is scar 1 again: `main.gd:_ready`
calls `load_from_user()` on the *shared* `default_combat_config.tres`, so every
check that boots `main.tscn` — `repair_check` and `run_check` too — measures
whatever the human last saved. Seven configs come in that way. It is harmless
today only because the saved files override unrelated fields and everything else
falls back to the script's defaults, which currently match the `.tres`.
`crash_check` defends itself (a `CACHE_MODE_IGNORE` private copy for its ruler,
and `reset_to_defaults()` on main's own config and damage config); **the leak
itself is still open and is not this check's to close.**

`terrain_check` (2026-08-08) is the newest and it guards the ground (P1.9). **The
ground is SMOOTH** — a terraced/voxel version was built, flown and rejected the
same day (*"voxels does not belong here, nor designing the ground as voxels"*),
and the check's blockiness stages were inverted into smoothness stages rather
than deleted, so nobody quietly puts the quantisation back. **The assertion that
matters is "the mesh agrees with the query"**, and it is worth
knowing why before the others: phase 2 teaches the whole game to stop assuming
the ground is flat at y = 0 — enemies hold station above `TerrainField.height_at`,
bombs detonate at it, sortie units are placed on it, the ingress puts a pilot
down on it. Every one of those trusts that the number is the surface a pilot can
SEE. The day they drift is the day bombs go off underground and turrets float,
and nothing else in the suite would notice. So it is compared against the real
built `ArrayMesh`, triangle by triangle, rather than against the generator that
produced it.

The other stages are the properties a landscape has to have to be one:
deterministic from (config, seed); `amplitude_m` meaning the metres it says;
`ridge` changing the LANDFORM and not the elevation; the terraces being exact
multiples of the step while still making a varied landscape; and every face
wound OUTWARD so the map is sealed.

**And one stage guards the architecture rather than the geometry.** The ground is
built as concentric detail rings, each doubling its cell size while covering four
times the area, so reach grows *exponentially* while cost grows *linearly*.
Measured: four extra rings buy **16x the world for 3.4x the triangles**, and six
rings reach **6.1 km**. That is the claim the design's "truly vast environments"
pillar rests on, and nothing else in the suite would notice it decaying.

**To fly the vast desert:** `<godot> --path . scenes/desert_map.tscn` - 6 km of
smooth rolling dunes with a stepped pyramid and four ruin fields, at about 93k
triangles (the smooth build is *cheaper* than the terraced one was, because there
are no wall quads).

**Two subtleties worth knowing before touching that check.** The height query is
PLANAR ON THE CORRECT TRIANGLE rather than bilinear - a quad split into two
triangles is not a bilinear patch, and the two disagree by up to a quarter of the
surface's curvature across a cell. And the LOD **seam skirts** are excluded from
the geometry stages by their footprint rather than their normal, because a skirt
deliberately wears the ground's normal so it shades invisibly.

**Three of those exist because the first version got them wrong**, which is the
argument for writing the check the same day: `amplitude_m` under-delivered by
26%, `ridge` raised the whole world 33 m under a comment claiming it was
handled, and the budget left the far quarter of the map missing. Six mutations
are on record and each fails a different sentence.

**And one failure was the CHECK's, not the feature's** — worth recording because
it looked exactly like a real bug. The mesh-agreement stage first compared
*vertices*, and a top quad's four corners sit ON cell boundaries which belong to
the next cell along; it reported 6285 disagreements against terrain that was
correct. It compares triangle CENTROIDS now, the only point guaranteed to be
strictly inside its own cell.

`falx`, `screamer`, `aegis`, `lance` and `phalanx` are **behaviour checks**, and every new enemy type
gets one the day it lands. The reason is scar tissue: the harness can only ever say *"this
cell reads 0%"*, which is equally consistent with a tough enemy, a broken enemy,
and an enemy that has flown out of the level. Four separate Falx bugs looked
identical from the results table.

`screamer_check` is the current example of how much that buys — five phases:
does it stay put, does a missile lock work at all (control), does its jam fade
across both ends of its field, does it hold a standoff, and **can it actually be
caught** by a pursuing pilot.

`aegis_check` (2026-08-05) is the newest, and it landed with the bomber rework
rather than after it. It holds seven decisions at once: the aegis flies PASSES and
survives its own bombs (A2), its payload is a magazine in the player's own
vocabulary (A.q2), a spent bomber EGRESSES and `escaped` fires (A2), it appears
only where bombers are BASED (A.q1), a composed sortie aims it OUTWARD along the
corridor the pilot came in on rather than at the objective it is defending
(A.q1), an escaped bomber costs the PLAYER ground with the war naming which
node paid (A.q3), and — added the day it was flown — **the bomb falls and lands**.

**The seventh is the one this check could not have caught in the shape it
shipped in, and that is the lesson rather than the fix.** It asked *"does a drop
happen, and is it aimed at the right place"*, which a blast at the bomber's own
altitude answers perfectly. It never asked whether anything DESCENDED. So the
new assertions are about what a release-point test structurally cannot see: a
body that still exists after the release, a detonation whose altitude is the
ground rather than the cruise height, a measurable gap between bombs-away and the
blast, and an impact inside its own blast radius of the aim point. There is also
a second flight whose whole purpose is one claim — the bomber is killed the
instant it lets go, and the bomb has to land anyway, because interception's
deadline is the release rather than the kill.

Running the mutation is what made it honest: restoring the mid-air blast left two
of the new assertions printing `ok` over an empty impact list, so each one now
carries the non-emptiness in its own condition. Three mutations are on record —
delete the falling body, delete the bombsight lead, parent the ordnance to the
bomber — and each fails a different sentence.

The scar it exists for is exactly rule 2's: the aegis spent months aimed at the
sortie's own centre, so the enemy's bomber flew into the middle of the base it
was defending and detonated on its own objective — and the way that finally
surfaced was `sortie_bench` reading node 16 as three reps of 300 s, 0% hull
taken, nothing killed. Nothing there could threaten the pilot and the pilot could
not threaten it.

`lance_check` guards the committed suicider, and its newest stage (A.q8) is the
one worth copying the SHAPE of. The Lance's proximity warning is a sound, and a
headless check cannot hear a sound — so the type exposes `warning_level()`, the
scalar the sound is made of, and the check holds that instead. **It flies the
same commitment twice and compares**: a 40 m dodge and a 6 m one, which peak at
`0.14` and `1.00`. That comparison is the whole point, because every single-run
assertion available (it opens, it rises, it stops) is passed just as happily by a
cue driven off a timer, off the phase, or off a constant — and a timer is exactly
the bug A.q8 was opened to fix. Four mutations are on record and each fails a
different sentence: drive it off a timer, make it a constant, delete the phase
guard, re-enable 3D rolloff on the emitter.

**To HEAR it rather than read it**, the dev room has a respawning specimen:

```
<godot> --path . scenes/dev_map.tscn
```

The Lance is at **(60, 14, 55)** — east and slightly south of the spawn. Arm,
hold still, and let it come: silence while it closes, a rising sweep and a soft
alarm when it stops and glows, then the alarm climbing in pitch and rate for the
whole run. It saturates at 11 m, which is the fuse radius, so full alarm always
means *inside the envelope*. `respawns = true` on the specimen, so it comes back
however it ends.

`phalanx_check` guards the heavy defender. **Its shield stages were rewritten
from scratch on 2026-08-08 (A.q10)**, because the ones they replaced asserted
that the screen TRACKED its attacker and that an orbit found a reachable
opening — and the type's screen is now two counter-rotating shells and a stern
vent, so both were meaningless. Leaving either would have left an assertion that
passes for a reason nobody intends.

What survived the rewrite is the **shape**: every claim is two runs differing in
one thing, and the beatability claim **flies the real geometry** rather than
asserting on a config field. Four claims:

1. **The screen is a pattern, not a facing.** It turns on a fixed bearing with
   nothing shooting it, and the whole pattern is identical whichever side the
   attacker stands on. That second half is the regression test for the mechanic
   that was *deleted* — if anyone re-adds tracking beside the rotation, it fails.
2. **One slot is not an answer** (P4.2's anti-orbit job). Camped on one bearing
   the screen is open **17%** of the time; flying with a shell's rotation, **42%**
   — so reading the pattern is worth 2.5x the damage.
3. **And it is still beatable from anywhere.** Twelve bearings are walked and the
   *worst* of them must still get a window worth shooting through inside a
   bounded wait.
4. **The stern vent is a weak point, not a hole.** A round on the plate reaches
   the hull while the window is open, past the whole battery, and does not while
   it is shut — plus a guard that camping astern on the vent stays worse than
   flying the pattern, which is the arithmetic of *"a permanently exposed stern
   is a camping spot"*.

It also holds the **aegis as a control**, and that control now says more than it
used to: the two shielded types no longer share a mechanism at all. The aegis is
a POOL you spend, gated on weapon choice; the phalanx is a BARRIER you time,
which is why `shield_max` is 0 on it.

**Six mutations are on record and each fails a different sentence:** delete the
second shell (camping reads 40% against 17%), stop both shells, re-add tracking,
vent never shuts, vent never opens, vent widened to 100 deg.

**The tracking mutation is the one worth knowing, because it PASSED the first
version of its own stage.** That stage watched a single bearing with the attacker
on either side; under a re-added tracker the bearing was blocked in both runs, so
two constant timelines compared equal and the headline assertion passed on a body
carrying exactly the defect it exists to refuse. Only the guard beside it noticed.
It now fingerprints eight bearings at once. Same family as the seventh unfailable
check: *fixing what a test fires on does not fix what it reads.*

**And one stage measured the wrong thing before it measured the right one.** The
camping assertion first parked the pilot on bearing (0,0,1) — dead astern, the
one bearing with a designed hole in it — and read 34% instead of 17%, nearly
failing the type's own role assertion by measuring the weak point.

**`lethality_check` runs about 8 minutes** — the fortress's cells simulate far
longer, and the board is dominated by that one check.

**To fly it**, the dev room has a specimen at **(-70, 16, 60)** — northwest,
in open sky over open ground, which is the terrain A7 says the type is best on
and therefore the honest place to judge it. It holds that station and never
follows.

Three things to try, in this order, and they are three different skills:

- **Camp one bearing and shoot.** Most of your rounds should visibly splash on a
  lit panel. This is the loadout the type exists to refuse; if it feels fine,
  the pattern is too generous.
- **Read the shells and fly WITH one.** The outer (cyan, 3 slots) turns one way
  at 26 deg/s, the inner (violet, 2 slots) the other at 16. Slide into a slot in
  either and hold its rate — about **14 m/s** around a 30 m orbit for the outer,
  **8 m/s** the other way for the inner. Your damage should roughly double.
- **Watch the stern.** A plate low on the aft face brightens across the whole
  9 s it is shut and goes white-hot for 2 s while a slot opens through both
  shells. A round that HITS the plate in that window goes straight to the hull,
  past all six guns. It is small on purpose — this is the accuracy skill.

**If it drags**, the shield fields are the ones to move and every one is a
slider under BESTIARY: gap widths set how OFTEN it is open, the rates set how
LONG each window lasts. Hull, mounts and the battery are signed off and were not
touched.

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

It also guards **the ingress** (2026-08-03), which replaced a check that had gone
wrong rather than one that was missing. The old assertion was *"every unit is
placed within sight of what it guards"* — right about a pilot who starts in the
middle, and with an approach to defend it would now FAIL a correctly placed
mid-ring turret, since a turret 57 m out is covering the annulus you have to
cross precisely by not hugging the centre. What replaces it: the spawn sits
between the egress line and the signal leash (the leash's radius is read out of
`sortie.gd` rather than retyped, so retuning one file cannot leave the check
agreeing with a number nobody flies), it sits on the spec's own bearing, the
pilot faces the target — and, the one that matters, **two nodes with different
approaches must land at different distances**. A hard-coded spawn passes every
distance assertion and is completely invisible, which is the state
`spec["approach"]` was actually in for two months.

Its newest stage (2026-08-07) holds that **units are not laid inside one
another**, and it is worth reading as a template for guarding a *probabilistic*
defect. Placement picked a uniform ring angle with no regard for what was already
there; measured over 90 real sorties and 3260 unit pairs, that produced 4 pairs
under 3 m — about **one sortie in twenty**. A check that built one ordinary
sortie would therefore have passed nineteen times out of twenty with the bug
fully present, which is worse than having no check, because an intermittent red
gets explained away.

So the stage builds a deliberately **crowded** ring to turn a rare failure into a
certain one. **It shipped at 16 bodies and the mutation passed it** — a 26 m ring
with 9 m of jitter is a wide annulus and sixteen draws usually miss each other
anyway. Sweeping the un-fixed placer across five seeds gave the closest pair as
6.25 m at 16 bodies, 4.83 at 24 and 32, and **2.86 at 48**, which is the first
count where every seed collides. Shipped at 48 with a 4 m threshold: 6.03 m
fixed, 2.83 m mutated. **Running the mutation is not sufficient on its own when
the defect is probabilistic — the stress case has to be tuned until the mutation
fails reliably, and that tuning is a measurement.**

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

### The pilot-in-the-loop drills (task 8, 2026-08-15)

The aim drill generalised: **any** question, not just aim. You fly a stated
task; the agent's prediction for what you will do is already in git; a report
afterwards says plainly where it was wrong.

```
<godot> --path . scenes/drill.tscn -- --list
<godot> --path . scenes/drill.tscn -- --drill hold_tilt
<godot> --path . scenes/drill.tscn -- --drill rotor_out
<godot> --headless -s scripts/tests/drill_report.gd --path .
```

The world is one thing: **a launch pad 250 m up over open ground**, no enemies,
no gates, no score. 250 m is arithmetic rather than taste — a quad tilted 30
degrees on hover collective keeps only `cos(30)` of its lift, which is 262 m of
descent across `hold_tilt`'s 20-second window, so a lower pad would be measuring
how much sky the map had.

**FIRE is the MARK button** in both drills and the weapons are disabled, so a
squeeze cannot put a bolt, a heat needle or recoil into the reading. The mark
is refused out loud unless the drill's stated entry condition is met.

- **`hold_tilt`** — hold 30 degrees of tilt for 10 unbroken seconds, flying the
  number printed beside the airframe's level bracket. It is the first test of
  the attitude instruments that landed in the HUD rounds, which were built and
  never judged by hands.
- **`rotor_out`** — one rotor fails in 5% steps every 2 seconds (about one raider
  bolt at severity 0.6) and you squeeze FIRE the instant you feel it. **The
  airframe plate is hidden on purpose**: the question is whether a located
  failure can be FELT, and a gauge drawing the rotor emptying answers a
  different question perfectly.

**The drill flies the REPO's flight numbers, not your saved tuning** — the
override switch goes off in `_enter_tree`, before the drone's `_ready`. Your
input bindings are the single exception, re-enabled around that one call, because
without your radio mapping there is no flight to measure.

Results land in `user://blackbox/drills/<drill>_<stamp>.json`, rewritten after
every completed attempt. **They are H5 deviation data like the aim drill's** and
never enter `balance/delivery_factors.json` or any base table: this instrument
exists to ARGUE with those numbers, which it cannot do if it is quietly folded
into them.

**Why the prediction is trustworthy**, in the order the mechanisms bite: one
committed JSON per drill, so `git log -1 --format=%ct` dates that prediction and
nothing else moves it; a fingerprint of the prediction stamped into the run, so
an edit afterwards makes the report print STALE instead of grading; and an
ordering test, so a prediction committed after the flight is refused outright
rather than compared.

**The plumbing smoke test** — off the board, because it spends real seconds:

```
<godot> --headless -s scripts/tests/drill_smoke.gd --path . \
    -- --drill hold_tilt --out <scratch dir> --pilot smoke-bot
```

A scripted pilot flies a whole drill so a broken state machine is found here
rather than by a human twenty minutes into a session. **Its numbers are not
data** — it marks `rotor_out` by reading the rotor's health, which is the exact
thing the drill asks a human about. `--pilot` is required and refused if missing:
an artifact that says "human" is a claim about where a number came from.

It earned its keep on its first run. Sampling is 60 Hz off a 240 Hz tick, and
`rotor_out` ends on an EVENT, so a call placed at exactly 25% of a rotor was
recorded at **20%** — a whole staircase step low, because the last sample
predated the step it called. The attempt now takes one final sample at the
instant it ends.

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
