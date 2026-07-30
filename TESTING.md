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
<godot> --path . scenes/aim_drill.tscn    the human aim drill (see §5)
```

Fly a different frame without editing anything:

```
<godot> --path . scenes/dev_map.tscn -- --frame atlas
```

**Where the specimens are in the dev room:** Falx at (−95, 26, −70), Screamer at
(75, 24, 55), aegis at (70, 20, −90), gnat swarm at (−60, 12, 40), turrets and
the city block around the middle.

---

## 4. The check suite — 13 headless checks

Run all of them before believing anything:

```
<godot> --headless -s scripts/tests/<name>_check.gd --path .
```

`hover`, `combat`, `wave`, `missile`, `run`, `repair`, `motor_damage`, `menu`,
`manifest`, `sortie_compose`, `lethality`, `falx`, `screamer`.

The last two are **behaviour checks**, and every new enemy type gets one the day
it lands. The reason is scar tissue: the harness can only ever say *"this cell
reads 0%"*, which is equally consistent with a tough enemy, a broken enemy, and
an enemy that has flown out of the level. Four separate Falx bugs looked
identical from the results table.

`screamer_check` is the current example of how much that buys — five phases:
does it stay put, does a missile lock work at all (control), does its jam fade
across both ends of its field, does it hold a standoff, and **can it actually be
caught** by a pursuing pilot.

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
