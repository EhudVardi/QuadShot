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

**Layer 2 — delivery.** Whether shots actually land, split into two factors
that belong to different owners:
- `aim_quality` — per AGENT. Measured by the aim bench: the agent vs a
  static target. The FCS gear ladder and this axis are the same axis — one
  measured, one purchased (equipment shifts a delivery factor; it never adds
  a matrix dimension — P4.3: "FCS is not a column").
- `evasion` — per TARGET. Measured by the evasion bench: a fixed
  perfect-aim shooter vs the moving enemy. The target's slipperiness is not
  the shooter's skill, and conflating them is how Blaster×Raider spent a
  phase reporting the bot instead of the weapon.

**Validation — the duel harness** (`matchup_harness.gd`). The integrated
fight, demoted from source-of-truth to cross-check: predicted product
(lethality × aim_quality × evasion) vs dueled result. Divergence is not
noise — it NAMES an un-modeled factor (survival pressure, the deadline, the
economy) to go model or accept. NOT for: populating the table.

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
  no longer matches. **A new bestiary type must be added to the bench's stamp
  list the day it lands**, or its stats can drift without invalidating factors
  measured under them.
- **Rig asserts address cells BY NAME, never by index** — a positional assert
  silently re-aims itself when a matrix row is inserted, and an assert that can
  be misaimed is worse than none.
- **Band resolution is limited for unseeded enemies.** A type with no `ai_seed`
  (turret, aegis) fights an identical duel every rep, so its win rate can only
  be 0% or 100% and its cell can only read `++` or `--` — it *cannot* report
  `0` or `+` whatever the balance is. The report says so per cell; don't read
  that resolution limit as a measurement.
- **Human results are deviation data** (H5): they tell you how a skilled
  human deviates from the reference datum. Interesting, logged, labeled —
  and never merged into the base table. Hand-banded cells say out loud that
  the band is the human's.
- **Banding thresholds are stated constants** (H.q1), not fitted values — a
  ruler that does not drift when the thing it measures does.

## Known-inert fields

`EnemyConfig.armor` is declared and overlay-tunable but applied nowhere in
the damage pipeline yet; the lethality calculator mirrors the CODE, not the
schema, so armor does not appear in its arithmetic until it ships for real.
