# HANDOFF-NEXT.md — two items, paste-ready

A self-contained brief for a fresh session. Everything needed is here; read
[CLAUDE.md](CLAUDE.md), [TESTING.md](TESTING.md) and [BALANCE.md](BALANCE.md)
before starting, and the tail of [GAMEPLAY-DESIGN.md](GAMEPLAY-DESIGN.md)
(entries v1.82–v1.84) for how the current state was arrived at.

**HEAD when this was written: `8d386a5`. `PILOT_VERSION` is 7.**

---

## 0. Context you need before touching anything

### What just landed (2026-07-28/29, entries v1.82–v1.84)

- **Evasion style is a FRAME property** (`FrameConfig.evasion_style`: `jink` /
  `hold`). Kestrel dodges, Atlas holds the line. The reference pilot asks the
  airframe, inside its AUTO gate only — the bench's forced `[jink]`/`[steady]`
  modes deliberately ignore the field.
- **The reference pilot can hand-fire** (P3.6's "iron trigger"). It defers to
  the gun director while the director is actually firing and takes the trigger
  back after `director_patience_s` (3.0 s) of silence, measured via
  `Weapon.director_idle_s`.
- **The Screamer shipped** (P4.2, roster type six): no weapon at all, a jam
  field that fades with distance and degrades the gun director, the missile
  lock, the flak fuse and the video feed. One scalar, four consumers —
  `scripts/combat/jamming.gd`.
- `PILOT_VERSION` went 5 → 6 → 7. The 7 was a **defect fix**, not an
  improvement: v6 decided "is the director working" by thresholding its solution
  *window* at 0.25 m, and the duels caught the pilot deferring to a 0.43 m window
  while firing **one round in ten seconds**.

### Standing rules that cost real time to learn — do not rediscover them

1. **Compare modes/cells WITHIN a single run, never across runs.** The ordering
   is the finding; the decimals move. A jinking cell swung 2× between two runs of
   the same command.
2. **A cell that reads "0%" is equally consistent with a tough enemy, a broken
   enemy, and an enemy that flew out of the level.** Four separate Falx bugs
   looked identical from the results table. **Every new bestiary type gets a
   behaviour check the day it lands** — see `falx_check.gd`, `screamer_check.gd`.
3. **Never read an enemy's facing from its BODY basis.** A freshly spawned enemy
   has identity rotation and zero velocity. Read the heading (velocity).
4. **Any new bestiary type joins `ENEMIES_FOR_STAMP` (delivery_bench) AND
   `ENEMIES` (lethality_check) the same day**, or its stats drift without
   invalidating the factors measured under them.
5. **Watch one cell instead of all of them.** Both benches take a name filter:
   `tools\watch_matchups.cmd screamer`. A filtered run is a LOOK — it writes no
   artifact and skips every assert.
6. **Run the full 13-check suite before each commit.** Commit each item
   separately. **No `Co-Authored-By` trailer** (the user purged it from history).
7. **Any pilot behaviour change is a `PILOT_VERSION` bump**, which costs a full
   ~45 min re-measure. Batch behaviour edits and bump once. Verify narrow with
   filtered runs first.
8. **Feel judgements are the human's.** Pick a sensible default, say it is
   provisional, and flag it for them to fly. Never tune a roster number to make
   a bench cell read better.

### Open questions from that session (not part of these two items)

- **`jam_range` (55 m) is smaller than `missile_lock_range` (60 m)**, so a
  missile can lock from outside the Screamer's bubble entirely. This is why
  `Missile × Screamer` duels `++` against a paper `--`. User spotted it; the fix
  is one number and is **their call**.
- **Nobody has measured a human hand-aiming with the gun director OFF.** H.q4's
  drill was flown with it on. Until that exists, every jammed gun cell is
  bot-bounded — the bot fired 145 rounds at a chased-down Screamer and landed
  zero. P4.3's chip-gun `+` against a screamer rests on that unmeasured number.
- **The Atlas loses badly when outnumbered** (−0.67 vs the Kestrel against 3
  raiders, −0.31 against 3 turrets) where P3.4's paper expects `0`. Sharpest
  paper-vs-measured gap on the board.

---

## ITEM 1 — Run mode gets the roster ✅ *(DONE 2026-07-30, v1.85)*

Built as `WaveDirector.ROSTER` + `PLAN`, unit-based bookkeeping, and a
fourteenth check (`composition_check.gd`). See GAMEPLAY-DESIGN v1.85 for the
full record, including the two latent bugs it surfaced and the two things
flagged for the user's hands. The brief below is kept as written, because the
constraints it lists are the reason the implementation has the shape it does.

### The problem, verified

[`scripts/combat/wave_director.gd:15`](scripts/combat/wave_director.gd#L15) has
exactly one enemy scene:

```gdscript
const ENEMY_SCENE: PackedScene = preload("res://scenes/combat/enemy_drone.tscn")
```

**Every wave of every sortie is raiders.** Five of the six roster types — gnat
swarm, aegis, falx, screamer, turret — have never appeared in a run. The dev room
has a specimen of each; the actual game has none of them. The user flew it and
said it "might be stale"; it is.

### What to build

Teach the wave director a **composition** rather than a count. Structure it so a
new roster type is a table entry, not new code — the same discipline
`matchup_harness.MATCHUPS` follows.

Borrow the vocabulary that already exists rather than inventing one:
`scripts/war/sortie_composer.gd` already projects a garrison into layers
(`LAYERS`: outer patrols → mid area-denial → inner guard), holds a fraction back
as triggered reserves (`RESERVE_BY_ARCHETYPE`), and keys everything off an
archetype. **Do not wire the war-sim into the run** — M4's run flow is not the
M6 campaign — but do reuse its *shape* so the two never diverge conceptually.

A sketch, to be argued with rather than followed:

| sortie | wave 1 | wave 2 | wave 3 |
|---|---|---|---|
| 1 | raiders | raiders + gnat swarm | raiders + falx |
| 2 | raiders + turret | gnats + falx | raiders + **screamer** escort |
| 3+ | mixed | aegis (intercept clock) | mixed + screamer |

Constraints that are not negotiable:

- **The aegis is a CLOCK, not a health bar.** It flies a route and detonates on
  arrival; a wave containing one is a "kill it in time" wave and needs a route
  set (`route_end`) or it flies its own heading for 120 m.
- **The turret has `respawn_delay` 20 s.** A wave is only clear when everything
  is dead; a respawning body makes a wave unclearable. Either exclude it from
  wave counts or zero the delay for wave-spawned instances.
- **The gnat's UNIT is the cloud** (P4.q5), not the body. `gnat_swarm.tscn`
  emits `cleared`, not `destroyed` — the wave director currently only connects
  `destroyed`, so swarm bookkeeping needs the `cleared` path (the matchup harness
  already does this correctly; copy its `_on_body_gone` shape).
- **The screamer has no weapon.** A wave of only screamers is a wave with no
  threat in it. It is an ESCORT type — it should only ever appear alongside
  something that shoots, which is exactly what makes it interesting (P4.3: the
  aegis+screamer pair is the web's first designed combo).

### Verification

- `wave_check.gd` and `run_check.gd` must still pass — read them first; they
  assert on wave counting and the sortie/gate/draft flow.
- **Write the behaviour check the roster rule demands**: a wave containing a
  cloud must still become clearable, and a wave containing a screamer must not
  deadlock (nothing to kill → gate never opens).
- Fly it. This is a feel item as much as a code item: pacing, how a screamer
  reads mid-fight, whether the aegis clock is legible under pressure.

---

## ITEM 2 — Screamer cloak (Predator-style)

### The user's ask, verbatim

> *"maybe since it doesnt engage, maybe we should give it a new equipment of
> invisibility. would be cool if it'll have some cool invisibility effect, like
> the predator from the movie, where reality is ever so slightly distorted."*

The design reason it fits: the Screamer never shoots, holds a wide standoff, and
"is tissue once reached" — so its only defence is not being reached. A cloak
makes finding it the skill, which is coherent with a type whose whole content is
degrading your *sensors*.

### What to build

A screen-space refraction shader on the Screamer's body — no textures, no
external assets (house rule: greybox primitives and procedural materials only).
Godot 4 gives this cheaply via a `ShaderMaterial` sampling `SCREEN_TEXTURE` with
a UV offset weighted by the surface normal (a fresnel term makes edges distort
hardest, which is exactly the Predator look).

Design decisions to make deliberately, not by default:

- **Tie the distortion strength to the jam level**, so it shimmers harder as you
  close. That reuses `Jamming.level_at` and makes the cloak *readable* — the
  thing that hides it is the same thing that tells you it is near. This is the
  single best idea in the item; without it, a cloak is just an annoyance.
- **Break the cloak briefly when hit** (~0.3 s of full opacity), or the player
  gets no confirmation their rounds are landing. Non-negotiable for feel.
- **The palette rule is a real constraint** (CLAUDE.md): red = threat. A fully
  invisible enemy has no colour at all. Suggest keeping the dish emitter visible
  at reduced energy — a floating red glint — so the type still reads as hostile.
  **Flag this to the user; it is a look call.**
- **`jam_video_glitch` already fuzzes the feed.** Distortion plus feed breakup
  may compound into unreadable. Check them together, not separately.

### Verification

- `screamer_check.gd` must still pass (five phases; the cloak is visual, so it
  should be inert to all of them — if it is not, something is wrong).
- The duel harness cells must not move. A visual-only change that moves a
  measured cell means it was not visual-only.
- **This is a FEEL item.** Pick provisional numbers, say so, and hand it to the
  user's hands. Distortion strength and the glint's brightness are theirs.

---

## DROPPED — building path arrows *(considered 2026-07-30, dropped by the user)*

Recorded so it is not rediscovered and re-proposed. The request was "make the
paths with arrows, like the main menu building floors showing the path", and
looking into it turned up that **the menu tower already solved this and arrows
were already tried and rejected**: `MenuFloorFrame._build_chevrons`
([`scripts/menu/menu_floor_frame.gd:396`](scripts/menu/menu_floor_frame.gd#L396))
builds chevrons marching toward the far window on the floor and ceiling, and its
comment records *"the arrow experiment retired at the user's call"* (v1.42).

The real gap it exposed is still real and still unfixed: `InteriorBuilder
._wayfinding`
([`scripts/menu/interior_builder.gd:36`](scripts/menu/interior_builder.gd#L36))
gives generated world-building interiors a **plain emissive strip** down each
keep-clear channel — a line with no direction in it — while menu floors get
directional chevrons. **The user dropped it anyway.** Do not re-open it without
being asked; if it ever does come back, the job is "give world buildings the
menu tower's chevrons", not "add arrows".
