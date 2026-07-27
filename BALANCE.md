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

**Layer 3 — survivability** (Iteration 9 / S1–S3, added 2026-07-27). The
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
- **3b — player evasion.** Per PILOT × FRAME, the twin of `aim_quality` and of
  the per-target `evasion` the enemy rows already carry — the player is a
  target too, and was the one nobody ever measured. Requires a pilot that
  tries to survive (`PILOT_VERSION` 4's jink); a pilot that never evades makes
  this unmeasurable by construction.

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
- **The third ruler is the checkout.** Benches build drones through
  `Frames.build`, which sets `load_user_overrides = false`. Before Phase 4b
  they instantiated `drone.tscn` directly, which auto-loads `user://` — so
  every committed delivery factor had been measured against whatever the human
  had last tuned into their own override file (here: `rate_p` 0.007 vs the
  repo's 0.004). The ruler was machine-local and no stamp could see it, because
  the drift lived in a file that is not in the repo. **An instrument measures
  the numbers that are committed.** Human tuning is deviation data (H5); it
  reaches the benches only when it is baked into a `default_*.tres`.
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
- **The predicted column cannot express a frame at all.** Prediction has no
  survival term (assumption 3: nobody shoots back), so it bands an absolute
  ttk while paper and validated are both deltas. Those three letters are not
  comparable, and the report says so on every frame cell rather than inviting
  the read. Durability — the point of the Atlas — is visible only in the
  validated column.

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
