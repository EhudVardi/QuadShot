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
    noise. **The Atlas cannot fly this jink.** That cell has no measurement in
    it, so the delivery bench FAILS and `tools/balance_report` stops there by
    design — the board is RED on purpose.
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

## The rulers

- **PILOT_VERSION** (in `reference_pilot.gd`): one AI brain flies every
  measured combatant, so improving it moves every cell at once. The pin makes
  that deliberate: every report prints the pilot version it was measured
  under; numbers from different pilot versions never share a table. Bump the
  version whenever pilot behavior changes, then re-measure on purpose.
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

## Known-inert fields

None. `EnemyConfig.armor` was the last one; it became live in Phase 4b, when
the Atlas needed flat reduction to exist. It is applied in `Health.take` (and
the gnat body's own damage path), modeled in `Lethality`, and verified by
planted-shot **probes** in `lethality_check.gd` — synthetic armored configs,
because every roster type is still `armor = 0.0` and checking the code against
zeros would verify nothing. Nothing balances off the probes; they exist so the
calculator and the damage code cannot drift on a rule the roster does not use
yet.
