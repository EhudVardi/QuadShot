# BALANCE.md — what the balance instrument measures (and what it is NOT for)

One page, per GAMEPLAY-DESIGN v1.23 (Phase 3.5 deliverable #0). Read this
before touching the harness, the benches, or a number in a config because a
report told you to. The doc's rule of thumb governs everything here:
**"The war shapes your fights; your fights dent the war."**

## The frame

- **The war never fights kinetically** (F2/P4.7). Unattended battles resolve
  by strength arithmetic in the war-sim. Kinetic combat exists only inside the
  player's own sorties — the sortie IS the deaggregation bubble (cf. Falcon
  4.0, minus the radius). `strength_cost` is the exchange rate converting
  kinetic results into war currency.
- **The balance instrument is CI for the design's feel-promises about the
  PLAYER's fights** — "guns die on aegis", "missiles bankrupt on gnats". It is
  NOT a war oracle, NOT an average-outcome pipeline for predicting global
  battle results. If you find yourself muxing loadouts × veterancy × biomes
  into one giant expected-value table, stop: you are rebuilding the mistake
  this file exists to prevent.

## The layers (each measured in isolation, each with its own bench)

**Layer 1 — lethality.** Pure config arithmetic: if this weapon CONNECTS,
what happens. Shots-to-kill, kill-or-never, cadence-limited TTK, derived
directly from CombatConfig × EnemyConfig by `scripts/balance/lethality.gd`
and verified against the shipped `Health` code by planted-shot benches
(`lethality_check.gd`) — no flying, no simulation, no pilot anywhere in it.
25 damage under a 40 break threshold is 0 forever, and no delivery skill
changes that. NOT for: predicting duels — connecting is the hard part.

**Layer 2 — delivery.** Whether shots actually land, split into factors that
belong to different owners:
- `aim_quality` — per AGENT, and the agent is **pilot × frame**. Measured by
  the aim bench: the agent vs a static target. The FCS gear ladder and this
  axis are the same axis — one measured, one purchased (equipment shifts a
  delivery factor; it never adds a matrix dimension — P4.3: "FCS is not a
  column"). The **frame** axis works the same way and cost the model nothing
  new: a second airframe re-keys aim (`kestrel:blaster`, `atlas:blaster`)
  rather than adding a factor, because "agent" always meant a pilot flying
  something — there was simply only ever one thing to fly. Contrast the flak
  pod, which did force a new factor (`splash`).
  **The JAM STATE is the third part of that key** (v1.83, S.q9):
  `<frame>:<weapon>:<clear|jammed>`. The Screamer is the negative of the FCS
  ladder, so the same rule points the same way — and the precedent is
  `Lethality.STATES` (shielded/cracked), which is how the Aegis was absorbed
  without a column. It doubles the aim cells, six to twelve, and that is the
  whole instrument cost of an EW type.
  - **The state is DISCRETE even though the field is graded.** A shield is a
    continuous pool modeled as two states because the two ENDS are what a
    weapon's answer inverts between; the jam is the same. The gradient lives in
    the fight, and the duel harness prints the **mean jam each row actually flew
    through** so a row keyed `jammed` that only ever met 0.3 says so instead of
    quietly predicting from the wrong column.
  - **A jammed blaster cell is a different TRIGGER, not a worse gun.** The
    director goes silent and the pilot falls back to its own 6° cone, so the two
    states are the flak-vs-gun comparison all over again: read the duty. Measured,
    and not in the direction predicted — `kestrel:blaster` goes 81 shots at 0.17
    (directed) to **135 shots at 0.12** (by hand). The manual cone is the LOOSER
    trigger against a static target: 6° at 40 m is a 4 m circle with no drop term,
    while the director insists on a real intersection inside 1.2 m. **The jam
    costs the chip gun discipline, not accuracy.**
  - **The flak pair is the honest apples-to-apples one**, because the pod never
    had a director: same trigger, same duty, **0.99 → 0.15**. That is the fuse
    degrading to contact-only, and it is where the jam actually bites.
  - **Zero shots is a MEASUREMENT in a jammed cell only.** A missile has no lock
    to launch on inside a full jam, so `*/missile:jammed` reads 0.00 and composes
    to `--` — P4.3's band arriving as arithmetic. That is the opposite direction
    of danger from Layer 3b's forbidden 0.00 (which composes to "invulnerable"),
    and the exemption is scoped to cells that DECLARED a jam. Everywhere else,
    firing nothing still fails the run.
- `evasion` — per TARGET. Measured by the evasion bench: a fixed
  perfect-aim shooter vs the moving enemy. The target's slipperiness is not
  the shooter's skill, and conflating them is how Blaster×Raider spent a
  phase reporting the bot instead of the weapon. Not frame-keyed, and that is
  structural rather than an economy: the bench freezes the shooter and lays
  its gun on the exact solution every tick, so a frozen Atlas and a frozen
  Kestrel fire identical shots.
- `splash` — per WEAPON×TARGET, and it belongs to neither of the above: it
  is the weapon's burst geometry meeting the target's dispersion. Bodies
  covered per ARRIVING burst, measured against a real pack. It divides the
  pack bill (an area weapon is paid per burst while the target is priced per
  body); it is 1.0 for every weapon that damages one body per connect, so it
  is inert everywhere except the flak column. NOT a damage multiplier —
  Layer 1 still prices flak per body, exactly like every other weapon.

**`aim_quality` is hits-per-shot-FIRED, which says nothing about how often a
shot is taken.** Two weapons with different trigger policies therefore
produce non-comparable aim numbers: the blaster's trigger is the gun director
(fires on any arc solution, so it takes many marginal shots — duty ~0.4, aim
0.17), the flak pod has no director (the pilot fires only inside a 6° cone —
duty ~0.7, aim 0.99). The delivery bench prints a **duty cycle** beside every
rate for exactly this reason. Reading 0.99 against 0.17 as "flak aims better"
is the Blaster×Raider mistake wearing a new column's name.

**Layer 3 — survivability** (Iteration 9 / S1–S3; 3a 2026-07-27, 3b and the
concurrency axis 2026-07-28). The
mirror of Layers 1–2: *their* output on *you*. Layers 1 and 2 were one half of
a symmetric model for a year, and that omission is why the frame axis was
illegible — a frame cell bands "destroyed minus hull spent", the Atlas's whole
virtue lives in the hull term, and nothing measured the hull term.
- **3a — incoming lethality.** `Lethality.incoming(enemy, frame)`: the same
  verified exchange loop pointed the other way, against
  `FrameConfig.hull`/`armor` (live on the drone — `FlightController._ready`
  pushes both into its `Health`). Planted-shot verified like Layer 1. It
  reports one of **three delivery modes**, because the roster has three:
  `ranged` (a cadence — raider, turret), `contact` (a CONSUMABLE sting — the
  gnat spends each body for one bite, so a pack is a finite damage budget and
  its arrival timing belongs to delivery, not to a config), and `none` (the
  aegis — no weapon, so it prices no frame's durability at all, which is the
  v1.72 finding in arithmetic). **Never read `fire_rate == 0` as harmless**:
  the gnat carries damage 7.0 at fire_rate 0.0 and is the type flat armor
  exists for.
- **3b — player evasion** (measured since v1.78). Per THREAT × FRAME — the twin
  of `aim_quality` and of the per-target `evasion` the enemy rows already carry.
  The player is a target too, and was the one nobody ever measured. Measured by
  the `survive` cells in the delivery bench: a bodiless perfect-aim threat
  emitting one enemy type's real rounds at the reference pilot while it flies
  the aim bench's own task. Stored as a **connect rate** like every other
  delivery factor, so **low is evasive** — it reads backwards from the word, and
  the compensation is that it multiplies straight into a hit rate on either side
  of the model. Frame-keyed, unlike its enemy-side twin, and that asymmetry is
  structural: the enemy-evasion bench freezes the shooter, so the airframe is
  inert by construction there; nothing freezes the player here.
  - **Every cell FORCES the jink state, and that is what makes it a factor.**
    The shipped gate is "I have been hit recently" — the right rule for a pilot
    and a ruinous one for a bench, because the thing being measured (do rounds
    connect) decides the behaviour (am I jinking). An un-forced cell is a
    feedback loop and it is **bistable in practice**: measured on this rig with
    one unrelated change between two runs, `kestrel x raider` settled at 25 hits
    / 0.87 duty once and 4 hits / 0.23 duty the next — a 6× swing — while
    `kestrel x turret` reproduced to the integer. Two of four cells moved.
    `ReferencePilot.Jink` (AUTO / ALWAYS / NEVER) forces it; **AUTO is the
    default and the shipped brain, so this is not a `PILOT_VERSION` event.**
    Each pair is measured twice: `[jink]` is the factor the model composes with
    (a pilot under fire has tripped the gate), `[steady]` is the datum it is
    worth against, in its own `player_evasion_steady` table so nothing can
    compose with it by accident. **Their difference is the only honest statement
    of what the jink buys** — and the gated cell could only ever answer that by
    accident. Jink duty is now a CHECK: 1.00 or 0.00, never in between.
  - **The threat station-keeps at a stated 18 m.** RANGE dominates this factor —
    a linear lead against a quad under aim-driven lateral acceleration misses by
    roughly the flight time squared — so the first attempt, which parked the
    threat at an arena coordinate ~30 m out, measured 0.03–0.08 and composed
    into a Kestrel surviving a raider for four minutes against duels that spend
    a fifth of its hull in ten. **That was not an un-modeled factor; it was a rig
    letting the arena pick the number.** Holding the range fixed makes the type
    axis mean the type's WEAPON. Where a type would *choose* to fight from is
    real and belongs to the duel.
  - **Its second output is the price of the jink — and it doubles as the cell's
    own lie detector.** The pilot flies the aim bench's task while dodging, so
    the same cell reports hits-per-shot under fire against the undisturbed aim
    cell. Read the printed fraction, not the rate: it is tens of shots, not
    hundreds. **A frame that is EVADING keeps shooting; a frame whose gun
    collapses is not dodging, it is coming apart** — and the two look identical
    in the headline "hard to hit" number while meaning opposite things about an
    airframe. The bench prints a WARNING (never a failure) when a cell's gun
    falls under a quarter of its clean aim rate.
  - **The threat's rounds pass THROUGH the pilot's own task target.**
    `Projectile._resolve_hit` fizzles a round on any collider — a same-team body
    takes no damage but still stops the shot — and the blaster path closes to
    nearly touching its target, so for much of a cell that target sits on the
    line of fire. Every round it absorbed would have scored as evasion the
    airframe never earned. The target is passed in the shot's `exclude` list for
    exactly this reason. **Generalize it: any bench that shoots at the pilot must
    ask what else is standing in the way.**
  - **Contact types get a RATE, not a fraction** (`contact_rate`). A gnat that
    arrives always stings, so there is nothing to miss with; the delivery term
    is arrival, in stings per second, and Layer 3a's `incoming()` refuses to
    invent it from a config and names this bench for it.
  - **The threat's own marksmanship is NOT in this number.** The bench lays a
    perfect solution, so `aim_jitter_deg`, tracking and lead logic sit outside
    the factor — the un-measured mirror of `aim_quality`. Until something varies
    it (P4.q2's veterancy is the stated trigger) it has one value and would
    measure nothing. **A survival time is therefore a FLOOR**: the real threat
    aims worse, and you live longer.
  - **No bench flies a wounded quad.** `apply_hit_to_motors` is wired in main.gd
    alone, which cost nothing while the player was never shot at and is a stated
    limit now that it is.
  - **THREE MODES, ONE FACTOR** (v1.81). `[auto]` is the shipped brain and the
    only one the model composes with; `[steady]` (never dodge) and `[jink]`
    (never stop) are datums in their own tables, because "what does dodging
    cost" is meaningless without both ends of the choice beside it. Under
    `PILOT_VERSION` 5 the tactical jink beats both extremes on both axes at once
    — fewest rounds taken AND the most shots at the best accuracy — while
    dodging 17% of the time.
  - **EVASION STYLE IS A FRAME PROPERTY** (`FrameConfig.evasion_style`, v1.82).
    `[auto]` now asks the AIRFRAME whether it dodges at all, because v1.81
    measured that the answer differs by frame: the tactical jink is best on both
    axes for the Kestrel and worth nothing to the Atlas. So the `[auto]` column
    is no longer one behaviour — it is each frame's own, which is what makes it
    the shipped brain rather than a shipped constant. **The forced modes
    deliberately ignore the field**: `atlas × raider [jink]` saturating is the
    evidence the property was built on, and a datum that the design it produced
    can switch off is not a datum. Consequence worth knowing before reading a
    board: for a `hold` frame `[auto]` and `[steady]` are the same flying and must
    agree — the bench enforces it exactly, on the jink duty (0.00), rather than
    by comparing two rates that carry noise.
  - **COMPARE MODES WITHIN ONE RUN, NEVER ACROSS RUNS.** All three cells of a
    pair share a run, and that is the only fair comparison: the ORDERING is
    stable, the absolute values are not. Two runs of the same command reproduced
    `[auto]` and `[jink]` byte-for-byte while `[steady]` moved by two rounds.
    - **AMENDED 2026-07-31: "the ordering is stable" holds for the RAIDER column
      and FAILS for the TURRET one.** Two more full runs at identical settings
      (forced by the stamp fix) put a number on the bench itself: **34 of 47
      factor cells bit-identical, 5 moving by more than 0.09** — and every mover
      that involves a threat is a turret cell. `kestrel x turret [jink]` read
      **0.08** then **0.36**; beside a `[steady]` of 0.40 then 0.22, that is
      "jinking cuts incoming fire fivefold" and "jinking makes you easier to hit"
      **from the same command**. Every raider cell reproduced exactly.
    - **This is not v1.80's bug.** That one was history dependence — *the result
      depends on what ran before it in the same process* — and these two runs
      share an identical history. The divergence is **cross-process**.
    - **The likely cause is sample size, and it is arithmetic rather than
      mystery.** An `evade` cell fires 38–50 rounds and resolves 2–18 hits, so
      0.04 against 0.16 is *six rounds*. **A cell resolving single-digit events
      cannot carry two decimal places.** Longer cells would fix it and cost bench
      minutes; that trade is unmade and deliberately so.
    - **Practical rule until it is:** read the turret column's ORDER as unproven
      and its absolute values as indicative only, and treat any survival time
      quoted against a turret as carrying a factor-of-a-few. The raider column is
      unaffected. **The irony is worth keeping: the least reproducible cells on
      the board belong to the one enemy with no `ai_seed`, which fights an
      identical engagement every rep.**
    - **IT IS THE TURRET, NOT THE PROCESS, AND THAT CORRECTS AN OLDER ENTRY.**
      The reproducibility note further down records `Atlas × Turret` reading
      `dmg-taken` 22.2 then 18.7 under an unchanged pilot and files it as generic
      *"~16% run-to-run variance"* — the warning every later reader inherited.
      The 2026-07-31 pair reads **23.3 then 18.7** on that same cell, nearly the
      same two numbers a third time, while every raider cell on both benches
      reproduces exactly. **Three observations, one enemy type, mis-attributed to
      the process each time because nobody had compared two full runs cell by
      cell.** Why a turret engagement is chaotic where a raider engagement is not
      is unexplained, and it is the thread to pull before trusting a turret
      number again.
    - **The duel harness itself is fine, and better than this bench.** The same
      pair of runs returned **29 of 29 win rates and 29 of 29 kill counts
      identical**, 20 of 29 cells identical on every field, with movement confined
      to `dmg-taken` and `spent`. The validation layer is steadier than the
      measurement layer feeding it.
  - **A saturated DATUM does not fail the run; a saturated FACTOR does.** A
    factor cell that cannot be measured is a broken instrument. A deliberate
    extreme saturating is its answer — "constant jinking throws this airframe so
    hard a perfect solution cannot find it" is a finding, and a board held red
    for it forever just teaches everyone to ignore red.
  - **A JINK CELL IS CHAOTIC, AND A CHAOTIC CELL IS NOT A FACTOR** (v1.80).
    Forcing the state fixed the bistability; a second problem was underneath it.
    `kestrel × raider [jink]` reads **0.29** inside the full run and **0.13**
    inside a two-cell run — while `[steady]` is bit-identical in both, and each
    history reproduces its own answer exactly. So it is not randomness: **the
    result depends on what ran before it in the same process.** A jinking drone
    is in a violent oscillation that amplifies whatever float state the physics
    server carries between arenas. **Any claim about what the jink does to the
    Kestrel is retracted** — one history says worse, the other says better.
    **The cheap test for this class of bug: run a cell in isolation and see
    whether it agrees with itself.**
  - **What survives, because it is saturated:** `atlas × raider [jink]` took
    **0 of 38** with its gun at **1 of 26**, reproduced under two independent
    histories. An aircraft that is completely out of control cannot be nudged by
    noise. **The Atlas cannot fly this jink.**
    - **CORRECTED 2026-07-31: the board is NOT red, and has not been since
      v1.82.** This paragraph used to end "that cell has no measurement in it, so
      the delivery bench FAILS and `tools/balance_report` stops there by design —
      the board is RED on purpose", and that was true only in the window between
      the cell saturating and the datum/factor split being applied to it. `[jink]`
      is a FORCED mode, so it is a **datum**, and the rule three bullets down
      already says a saturated datum does not fail the run. Two consecutive full
      reports on 2026-07-31 passed all three layers with this cell reading
      **0.00**. The finding stands untouched — the Atlas still cannot fly this
      jink — it simply is not a build break, which is exactly what the rule
      intends. **A stale RED in a doc is worse than a stale number: it teaches
      people the board is expected to be broken.**
  - v1.77's duel finding is not contradicted by any of this: those fought a real
    raider with 3° jitter and its own tracking loop, at fight geometry. Whatever
    replaces the jink has to be measured against both.

**The concurrency axis** (S5). Not a fourth factor and not a new matrix: the
**same cells, run at N**. It lives in the duel harness (`count` on a matchup
row), because what it changes is EXPOSURE and exposure is a fight property.
S4 is why it exists — the Kestrel spends 0% hull in four cells, which pins the
Atlas's arithmetic ceiling at 0.00, and the cause is time-in-the-envelope, not
marksmanship. A longer cap cannot fix that (a duel ends when the enemy dies);
more enemies can. A frame cell's datum must therefore match its concurrency as
well as its weapon and type, and the harness asserts that structurally.

**Validation — the duel harness** (`matchup_harness.gd`). The integrated
fight, demoted from source-of-truth to cross-check: predicted product
(lethality × aim_quality × evasion ÷ splash) vs dueled result. Divergence is
not noise — it NAMES an un-modeled factor (survival pressure, the deadline,
the economy) to go model or accept. NOT for: populating the table.

## The SDI saturates, and `cleared` is the column with the signal

**Measured 2026-08-03**, first full-theater sweep: 78 cells (every enemy node x
three weapons), 3 reps, 300 s cap, pilot v7, theater 4242, all seven archetypes
open. **234 reps, 184 lost, 50 timed out, ZERO completions at every depth from 3
to 10.**

A completion rate pinned at 0% has no resolution. Every node reads identical, so
the curve H6 asks for is invisible - not because it is absent, but because the
instrument is against its stop.

**The signal was in the dent the whole time.** Priced as a fraction of the node's
own strength - how much of it the pilot took apart before dying - the same sweep
produces a real gradient:

| depth | mean garrison | fraction of the node cleared |
|---|---|---|
| 3 | 15.5 | **54%** |
| 4 | 18.0 | 52% |
| 5 | 20.5 | 39% |
| 6 | 23.0 | 29% |
| 7 | 34.8 | **21%** |
| 8-10 | 37-40 | 26-28% (flat) |

It falls by more than half from the shallow band to depth 7, then flattens
because `garrison_cap` is 40 and the deep nodes are all at it. That is H6's SHAPE
in a unit H6 did not name, and `sortie_bench` now prints it as a `cleared` column
beside `complete` for exactly that reason.

### Three things to know before reading any of those numbers

1. **The pilot flies a STOCK KESTREL with ONE weapon**, no upgrades, no frame
   choice, no pads spent by a human's judgement. H6's bands (pocket 70-85%)
   describe an equipped pilot. 0% completion for a bare airframe against a full
   garrison is not obviously wrong; it is un-comparable to the band.
2. **The blaster is NEVER a node's best answer** - 0 of 26 nodes. Flak took 13
   and the missile 13, an exact split. The chip gun is the floor weapon (R.q1)
   and this is that statement measured at sortie scale.
3. **THE THEATER HAS NO POCKET.** Its shallowest enemy node is 3 hops out,
   because the player's pocket is 2. H6's pocket band cannot be measured on this
   seed at all, and the 54% at depth 3 is the shallowest reading that exists
   rather than the shallow end of the curve.

### Five cells are rig faults, and the bench said so itself

`dent 0.0 over 3 reps - the pilot never killed anything` fired on node 5 blaster,
node 10 flak, node 16 blaster AND flak, and node 17 blaster. Node 16's blaster
reps are the clearest: **300 s, 0% hull taken, nothing killed.** The pilot flew
for five minutes, was never shot at, and could not hurt what it was aiming at -
an aegis, whose shield hard-counters a chip gun (P4.3), on a node whose garrison
is aegis and screamers. Nothing there can threaten the pilot and the pilot cannot
threaten it. That is a stalemate the bench correctly refuses to call difficulty.

### The rig changed on 2026-08-03, so that whole table has a boundary under it

`sortie_bench` used to spawn the pilot at a rig-invented **125 m on a fixed +Z
bearing**, because the game had no ingress for it to borrow. The game has one now
(A6): the pilot is put down on the node's own approach, **140-195 m out depending
on the biome**, on the bearing the spec carries. The bench takes it — an
instrument that measures a different approach from the one the player flies is
measuring a different game.

**Numbers taken before that date and after it are not comparable**, exactly as
BALANCE.md's standing rule says of any settings change. Nothing else about the
sweep moved, so a run at identical settings (`--reps 3 --cap 300`) across the
boundary is a clean **A/B on the ingress itself**, and that is the only thing it
is: it says what moving the spawn did, not what the game is worth.

**The one deviation from the game, stated because it bounds every number here:**
the game puts the pilot on the DECK and the bench keeps them at 14 m cruise.
`ReferencePilot` has no take-off behaviour and teaching it one is a
`PILOT_VERSION` bump plus a full board re-measure. So the bench flies the right
distance on the right bearing at the wrong height, and a human's first seconds
are a climb this does not model.

## The rulers

- **PILOT_VERSION** (in `reference_pilot.gd`): one AI brain flies every
  measured combatant, so improving it moves every cell at once. The pin makes
  that deliberate: every report prints the pilot version it was measured
  under; numbers from different pilot versions never share a table. Bump the
  version whenever pilot behavior changes, then re-measure on purpose.
  - **BATCH THE BEHAVIOUR EDITS, BUMP ONCE.** A bump costs a full deliberate
    re-measure (~an hour), so two pilot edits landed separately cost two of them
    and make neither attributable. v6 carries both of its edits for exactly that
    reason (frame-keyed evasion + the iron trigger), and each was verified before
    the bump by **filtered** bench runs — `-- <substring>`, minutes rather than an
    hour, a LOOK that cannot write the artifact. **Verify narrow, measure once.**
  - **`Weapon.director_active()` is the pilot's trigger rule** (v6, P3.6's iron
    trigger): use the gun director while there is one, pull the trigger by hand
    when there is not. Before it, anything that switched the director off made the
    pilot fire *nothing* — a cell that reads as a hard-countered weapon while
    actually reporting a brain standing still. Any bench that turns the director
    off is measuring the manual path now, and a manual hit rate is not comparable
    with a directed one: read the DUTY beside it (the flak-column rule again).
- **The config stamp** (`BalancePrediction.config_stamp`): the *other* ruler.
  Delivery factors are measured against specific muzzle speeds, lock cones and
  enemy speeds, so retuning any of those invalidates them even though the pilot
  never changed. `balance/delivery_factors.json` carries a hash of every field
  delivery is sensitive to, and the harness blanks the predicted column when it
  no longer matches. **A new bestiary type or frame must be added to the
  bench's stamp list the day it lands**, or its stats can drift without
  invalidating factors measured under them. The stamp covers each frame's
  FlightConfig too — mass and rate gains were always delivery inputs and went
  unstamped until Phase 4b, so retuning the drone's PID silently invalidated
  every factor while the stamp reported a match.
  - **Layer 3b added four fields** (v1.78): the enemy's `fire_rate` and
    `muzzle_speed`/`sight_range` — cadence is the cell's sample size, and the
    other two are the threat's own ballistics and round lifetime — plus
    `damage`, and **`FrameConfig.hull`/`armor`, which the stamp had never read
    at all.** Phase 4b left those last two out with a stated reason (no bench
    that measures a delivery factor could be affected by them), and that reason
    was true right up until a bench pointed a gun at the player.
  - **THE HOLE OPENED A SECOND TIME, and the ammo work fell straight into it**
    (2026-07-31, Iteration 12). v1.91 gave the blaster a heat sink and v1.92 gave
    the pod and the rack magazines. Both are `CombatConfig` fields, both
    demonstrably move delivery — and **the stamp hashed identical across both**,
    because `DELIVERY_FIELDS_COMBAT` listed ballistics, lock and fuse fields and
    nothing that can END a burst. The board would have gone on quoting pre-heat
    factors as current indefinitely; the only thing that caught it was a human
    writing "the board owes a re-measure" into the handoff by hand.
    - The proof it was load-bearing is in the run that found it: **`Flak x
      Screamer` spent exactly 24.0 rounds — the whole magazine** — so that cell is
      ammunition-bound rather than time-bound, and no field in the old list could
      see that. Duty cycles moved across the board for the same reason.
    - `heat_per_shot`, `heat_capacity`, `heat_cool_rate`, `heat_vent_delay`,
      `heat_reset_fraction`, `flak_magazine` and `missile_rack` are now in the
      list.
    - **The generalization, now that it has happened twice:** the old rule was
      "a field is inert to delivery only for as long as no bench reads it." That
      is too weak. **Anything that can stop a weapon firing is a delivery input,
      because `aim_quality` is hits per shot FIRED and a weapon that quits
      mid-cell changes the denominator.** Ask of any new field: *can this end a
      burst?* If yes, it is stamped.
  - **Two of them are a conservatism, and the reasoning changed mid-build.**
    Under Layer 3b's first design `damage`, `hull` and `armor` were strictly
    load-bearing, because the jink was hit-gated: armor decided whether the pilot
    ever started evading, hull whether it survived the window. Forcing the jink
    state fixed the bistability *and* removed that coupling — under the shipped
    bench the player is immortal and the flight mode is stated by the cell, so
    those three are inert again. **They stay listed knowingly, not by
    necessity**: a false positive costs one re-measure, a false negative costs a
    quoted stale number, and the AUTO gate is one bench edit from making them
    load-bearing again. The general lesson survives the reversal intact: **a
    field is "inert to delivery" only for as long as no bench reads it, and
    adding or redesigning a bench is exactly the event that changes that.**
- **The third ruler is the checkout.** Benches build drones through
  `Frames.build`, which sets `load_user_overrides = false`. Before Phase 4b
  they instantiated `drone.tscn` directly, which auto-loads `user://` — so
  every committed delivery factor had been measured against whatever the human
  had last tuned into their own override file (here: `rate_p` 0.007 vs the
  repo's 0.004). The ruler was machine-local and no stamp could see it, because
  the drift lived in a file that is not in the repo. **An instrument measures
  the numbers that are committed.** Human tuning is deviation data (H5); it
  reaches the benches only when it is baked into a `default_*.tres`.
- **How reproducible the duel harness actually is (measured 2026-07-27).** The
  harness header warns that it is "not bit-exact" because the physics solver
  carries float variance between processes. Two full runs under identical
  settings were compared to put a number on that: **9 of 10 compared cells came
  back byte-identical**, and the single mover was a pack cell at **0.04**
  exchange. So a delta of ~0.09 or more is a real balance movement; anything at
  or under ~0.04 is not readable and must not be reported as a change. The
  warning is real but far smaller than it sounds — and the trap it hides is
  worse than noise: a v3-vs-v3 pair that appeared to differ by 16% turned out to
  differ because `MAX_SECONDS` had been changed between them. **Compare runs
  only at identical settings; a changed rig constant is not noise, it is a
  different measurement.**
- **Rig asserts address cells BY NAME, never by index** — a positional assert
  silently re-aims itself when a matrix row is inserted, and an assert that can
  be misaimed is worse than none.
- **Band resolution is limited for unseeded enemies.** A type with no `ai_seed`
  (turret, aegis) fights an identical duel every rep, so its win rate can only
  be 0% or 100% and its cell can only read `++` or `--` — it *cannot* report
  `0` or `+` whatever the balance is. The report says so per cell; don't read
  that resolution limit as a measurement.
- **The ruler's aim datum decides how weapons rank against each other, not
  just how fast they kill.** The reference pilot hits 0.17 with the chip gun
  and 0.99 with the fused flak shell, so any cell comparing the two is partly
  reporting the BOT. On Layer 1 alone flak is the *slowest* single-target
  weapon in the game (4 hits / 1.2 s on a raider vs the blaster's 2 / 0.1 s);
  it only outranks the gun once this pilot's aim is applied. **H.q4 settled
  this** (drill flown 2026-07-24, design-doc v1.45): on the identical static
  ruler the human reads **blaster 0.21** (17/81, radio, focused) against the
  bot's 0.17 and **flak 1.03** (39/38) against the bot's 0.99 — hands and bot
  agree on both weapons, so the flak-vs-gun gap is the WEAPONS, not the bot,
  and those comparisons are no longer provisional. ~0.2 hits-per-shot is
  simply what a ballistic chip gun costs against a small hitbox.
- **What H.q4 also did NOT settle, and the Screamer made it urgent (v1.84):
  hand-aim with the DIRECTOR OFF.** The drill was flown with it on — human 0.21
  against the bot's 0.17 — so both figures describe an *assisted* trigger. Turn
  the director off and the bot's manual path is a 6° cone with no ballistic
  solution in it: 0.10 against a static target, and **0 hits from 145 rounds**
  against a screamer it had chased down to 30 m (`screamer_check` phase 5). P4.3
  rates chip gun `+` against a screamer because "the manual fallback stays a skill
  path forever" — that is a claim about a HUMAN's hand-aim, and it has never been
  measured. **The drill this names: the aim bench with `fire_assist_miss_m` at 0.**
  Until it is flown, every jammed gun cell is bot-bounded and must be read as one.
- **What H.q4 did NOT settle: tracking a maneuvering target.** The drill's
  ruler is a *static* raider, so it validates the aim datum and nothing past
  it. `Blaster × Raider` remains rig-unflyable and hand-banded — the pilot
  positions and fires but the gun director's *linear* lead is defeated by a
  curved orbit (the v1.20 finding, calibration task #1, still open). Read a
  discharged aim ruler as exactly that; it is not a discharged pilot.
- **Human results are deviation data** (H5): they tell you how a skilled
  human deviates from the reference datum. Interesting, logged, labeled —
  and never merged into the base table. Hand-banded cells say out loud that
  the band is the human's. Measured by the interactive drill
  (`scenes/aim_drill.tscn` — the bot aim bench's exact ruler, flown by
  hands); artifacts land in `user://blackbox/aim_drill_*.json`.
- **Banding thresholds are stated constants** (H.q1), not fitted values — a
  ruler that does not drift when the thing it measures does.

## The frame axis is ruled RELATIVELY, and only the validated column can see it

A weapon cell asks "did it kill, and how fast". A frame cell cannot: a frame
does not change whether the weapon kills, it changes **what the kill costs**.
So frame cells (`Atlas × Gnats`, …) band the **exchange delta** — fraction of
the enemy unit destroyed minus fraction of your own hull spent — against a
Kestrel twin flying *the same weapon at the same enemy*. Three consequences
worth knowing before reading one:

- **The Kestrel is the origin by design, not by convention.** P3.3/P3.4 define
  its whole column as zeros ("the frame you fly when intel is stale"), so the
  ruler's zero is a design statement rather than a measurement.
- **A frame cell's datum must differ ONLY by frame.** Picking each row's *best*
  weapon would measure a loadout and label it an airframe. The harness asserts
  this structurally.
- **The predicted BAND cannot express a frame — the model now can** (v1.78).
  Prediction still bands an absolute ttk while paper and validated are both
  deltas, so those three letters remain incomparable and the report still says
  so on every frame cell. What changed is that assumption 3 ("nobody shoots
  back") is now only true of the BAND: `BalancePrediction.survive` composes
  Layer 3a's arithmetic with Layer 3b's measured connect rate into a survival
  time, printed BESIDE the bands on every cell whose enemy can shoot. So a
  frame's durability can be predicted and then checked, instead of only observed
  after the fact. **Not folded into the band, deliberately** — a ttk band and a
  survival band are two rulers, and H.q1 forbids drifting one to make the other
  agree.

Relative banding also *rescues* the cells the win ruler cannot resolve: an
unseeded enemy (turret, aegis) can only ever read `++` or `--` on win rate,
but hull spent is continuous even in a deterministic duel.

**`Atlas × Raiders` −0.67 is DIAGNOSED, and it was never a durability failure**
(2026-07-31). The sharpest paper-vs-measured gap on the board reproduced exactly
— and with Layer 3's survival line printed beside it, the cell now explains
itself. Read the two rows of the same datum together:

| | Atlas | Kestrel |
|---|---|---|
| exchange vs 3× raider | +0.24 | +0.91 |
| hull spent | **4%** | 9% |
| survival under 3× raider | **76.7 s** | 12.0 s |
| **missiles fired in 10 s** | **0.8** | **3.0** |
| aim once fired | 1.00 | 1.00 |

The Atlas takes less than half the damage and lives six times as long — **its
durability is measured, real, and exactly what P3.4 promised.** It loses the
exchange because it *fired 0.8 missiles where the Kestrel fired 3*, at identical
accuracy. A missile cannot launch without a lock, so the binding constraint is
**acquisition**: against one raider the Atlas does lock (ttk 4.2 s vs 1.7 s),
and against three that jink, ten seconds buys it less than one.

- **The un-modeled factor this names: a heavy frame pays for its stability in
  LOCK TIME, and nothing in the model prices that.** Layer 2 keys `aim_quality`
  per frame, which captures how well a frame holds a gun line — it does not
  capture how long a frame takes to *earn a launch*. That is a real gap and it
  is the frame axis's, not the Atlas's.
- **Read it as the mirror of S4.** S4's problem was fights ending before damage
  could accumulate; this is a fight that never ends before the buzzer (timeout
  6/6). Both are the fixed cap deciding a frame cell. S4's prescribed answer is
  the same in both directions: a task that holds you in the envelope — a
  composed sortie, not a duel.
- **Do not "fix" this by raising `MAX_SECONDS`.** A changed rig constant is not
  noise, it is a different measurement (see the reproducibility note above), and
  it would silently un-compare this board from every previous one.

## The Screamer reads strangely on purpose

It is the first roster member whose effect is neither damage nor durability, and
two of the three layers cannot see it at all: **Layer 1** prices it as an
ordinary 30-hull target and nothing more, **Layer 3a** reports `mode: none`
(damage 0 — it prices no frame's durability, exactly the Aegis's illegibility
from v1.72), and every duel row against it reads `dmg-taken 0.0`. All of its
content is in **Layer 2**, in the `jammed` half of the aim table. So:

- A screamer row with 0 damage taken is CORRECT, not a broken cell.
- Its survival line says "carries no weapon — this cell cannot price
  durability", and that sentence is the measurement.
- `evasion: * x screamer` reads ~0.92–1.00: it station-keeps and slides, so a
  perfect shooter hits it nearly every time. Its defence is not motion.
- What it costs you is only visible by reading the clear and jammed aim cells
  **as a pair**. One number in isolation from that table says nothing about it.

Its EW is deliberately absent from the evasion cells (`jam: 0.0` forced there):
the enemy-evasion bench freezes the shooter and lays its gun itself, so there is
no director, no lock timer and no onboard fuse for a jam to degrade — measuring
it there as well as on the aim axis would report it twice.

**One NAMED GAP, stated rather than papered over: `splash` is measured clear
only.** A jam degrades the flak fuse to contact-only, and a shell that must touch
a body bursts on the near face of a cloud instead of inside it — so the real
pack-coverage yield under jam is lower than the committed 3.42, by an amount
nobody has measured. The single-target half of that loss IS captured (it is the
0.99 → 0.15 in `aim: */flak:jammed`); the pack half is not. It costs nothing
today, because no shipped cell fights a swarm inside a bubble — and the day
P4.3's aegis+screamer pair grows a gnat escort, this is the line to come back to.

## Known-inert fields

None. `EnemyConfig.armor` was the last one; it became live in Phase 4b, when
the Atlas needed flat reduction to exist. It is applied in `Health.take` (and
the gnat body's own damage path), modeled in `Lethality`, and verified by
planted-shot **probes** in `lethality_check.gd` — synthetic armored configs,
because every roster type is still `armor = 0.0` and checking the code against
zeros would verify nothing. Nothing balances off the probes; they exist so the
calculator and the damage code cannot drift on a rule the roster does not use
yet.
