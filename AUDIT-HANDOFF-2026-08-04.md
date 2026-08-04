# AUDIT HANDOFF — QuadShot, 2026-08-04

HEAD audited: `c10eb4304b6ddcb73bb1dafde0b99baa42f00e48` — matches the pinned sha in the
request. Working tree clean. **The repo path differs from the request**: this machine has it at
`c:\Git\PersonalRepos\QuadShot`, not `e:\Workspaces\Git\Clones\QuadShoot`. Content is the pinned
commit, so the audit stands.

**What I ran** (all of it against a *copy* of the repo in a scratch directory with
`config/use_custom_user_dir=true` / `custom_user_dir_name="QuadShotAudit"`, so nothing here
touched the repo or the real `user://`):

1. `--headless --import` then all **19 checks** by exit code. **All 19 pass** (`hover` 10s,
   `combat` 2, `wave` 2, `missile` 3, `run` 2, `repair` 2, `motor_damage` 21, `menu` 2,
   `manifest` 3, `sortie_compose` 1, `lethality` 254, `falx` 21, `screamer` 42, `composition` 17,
   `heat` 7, `ammo` 2, `sortie` 7, `war_loop` 1, `war_room` 2).
2. Two throwaway probe scripts (composer + runner, no arena) — F1 and F2 below are *executed*
   results, not readings.
3. Two source mutations, each run against `sortie_check` and then reverted — F3 and F4.
4. No bench, filtered or otherwise. No unfiltered anything. Nothing written to `balance/`.

**Environment notes, not findings.** Godot on this machine is at
`C:\Godot\Godot_v4.7-stable_win64_console.exe`; `CLAUDE.md` and `TESTING.md` say
`C:\Tools\Godot\` (which exists but holds no Godot). A `4.7.1-stable` build is also present; I
used `4.7-stable` as the docs specify. The real `user://` dir
(`%APPDATA%\Godot\app_userdata\QuadShot`) contains **only** `logs/`, `shader_cache/`,
`objectdb_snapshots/`, `vulkan/` — **no `war.save`, no `flight_*.tres`, no `presets/`, no
`input_bindings.tres`, no `profile.json`, no `blackbox/`**. There is no live campaign on this
machine to endanger, which is worth knowing before the next audit spends care on hazard (a).

## Coverage — read this before trusting the shape of this report

I planned nine parallel readers, one per track. **All nine died on an API session limit before
returning anything**, so this is a single-reader audit and its coverage is narrow and deep rather
than broad. Being explicit so the next pass does not assume ground is covered:

**Read in full:** `scripts/sortie/sortie_runner.gd` (717), `scripts/war/sortie_composer.gd` (451),
`scripts/war/war_manifest.gd` (365), `scripts/war/war_sim.gd` (584),
`scripts/tests/sortie_check.gd` (612), `scripts/warroom/war_debrief.gd` (88),
`scripts/warroom/war_launch.gd` (57), `TESTING.md` (441), `HANDOFF-NEXT.md` (378),
`project.godot`, `CLAUDE.md`.

**Read in part (targeted):** `scripts/warroom/war_room.gd` (the whole turn: `_unhandled_input`,
`_launch`, `_resolve_returning_sortie`, `_play_the_tick`, `_select`, `_update_card`),
`scripts/sortie.gd` (the finish/death/leash paths), `scripts/warroom/war_view.gd` (refusals only),
`scripts/combat/objective_asset.gd` (signals only), `GAMEPLAY-DESIGN.md` (the v2.01 audit entry,
Iteration 14, v2.14–v2.15 — ~450 lines of 10,723, per the request).

**Tracks I did NOT reach at all. Nothing below should be read as clearing them:**
- **Track 1a** — the twelve flight/combat checks (`hover`, `combat`, `wave`, `missile`, `run`,
  `repair`, `motor_damage`, `menu`, `lethality`, `falx`, `screamer`, `heat`). Not opened.
- **Track 1b, most of it** — `war_room_check.gd` (870 lines, still never externally reviewed),
  `composition_check.gd`, `ammo_check.gd`, `war_loop_check.gd`, `manifest_check.gd`,
  `sortie_compose_check.gd`. Only `sortie_check.gd` was read.
- **Track 2, most of it** — `war_view.gd` purity, `hex_table.gd` (503) owning no facts, the
  zero-save-fields claim, the fog-leak paths, `war_diff.gd`. I traced only the campaign-turn
  question (double-tick / apply-twice / stale-save), which is clean; see F5 for the one hole.
- **Track 3** — verified only that `snappedf` is absent from `war/` and `warroom/` and that no
  production path JSONs war state. The `quantize` arithmetic, the weather dice, and the
  user://-crossing inventory were not done.
- **Track 5 (the reproducibility question) — entirely untouched.** The 15 `static var`s were not
  enumerated. This was the request's joint-highest-value track and it is still open.
- **Track 6** — no systematic doc sweep. Incidental checks only (recorded below).
- **Track 7 (aegis)** and **Track 8 (motor/repair, debug_overlay, city_layout)** — not opened.

## Verdict in five lines

1. **A node whose garrison has been ground below one unit's price composes a dogfight with
   nothing in it, the war room offers it, and the runner can never end it** — pilot alive, empty
   field, no egress, forever. Executed and reproduced (F1).
2. **Destroying the objective dents the node by exactly zero**, so a flawless 3-of-3 strike
   reports `cleared 0.0%` — the metric v2.13's whole difficulty reading rests on cannot see the
   objective half of six of the seven archetypes (F2).
3. **Deleting one line from `SortieRunner.start()` restores v2.01's "AIRSPACE CLEAR while a wave
   is inbound" bug and the entire board stays green** — `sortie_check` hand-builds the very
   arrays the joint is about (F3).
4. **The ingress remap's "ORDER PRESERVED" claim is asserted nowhere**: inverting it so a city
   drops you farthest and open desert closest passes `sortie_check` (F4).
5. The campaign turn itself — double-tick, apply-twice, stale-state-over-newer-save — is
   **genuinely well guarded**; the only hole is a mouse click that reaches the map through the
   two gates written to stop it (F5).

---

## Findings

### F1 — A garrison ground below one unit's price yields a launchable dogfight that can never end

- **Where:** `scripts/war/war_manifest.gd:165-166` (returns `[]`), `:182` (fill loop never
  entered below `cheapest`); `scripts/sortie/sortie_runner.gd:239` (`phase = Phase.ENGAGED` with
  no completion test), `:649-654` (`_check_field_cleared` is reachable **only** from
  `_on_unit_gone` and `_release`), `:328-333` (`_physics_process` egress requires
  `phase == EGRESS`); `scripts/war/war_sim.gd:73` (garrison → exactly `0.0`), `:222`
  (`unsupplied_decay` drives it arbitrarily low), `:374` (a mauled defender × 0.8);
  `scripts/warroom/war_view.gd:140-164` (no refusal reason for it).
- **Severity:** campaign-destroyer
- **Confidence:** CONFIRMED (executed)
- **The failure:** `WarManifest.project()` returns an empty unit list when
  `budget <= 0.0`, and also whenever `budget < cheapest` (the fill loop's guard is
  `remaining >= cheapest - 0.0005`; the cheapest unit in the game prices at **1.000**). An
  `airspace` node composes `archetype: dogfight, assets: 0`, so with an empty projection the spec
  carries **zero placed units and zero triggers** — and `is_slice_ready` is still true, because it
  only tests the archetype name. `SortieRunner.start()` then sets `phase = ENGAGED` and returns.
  `_check_field_cleared()` is the only thing that can open a dogfight's egress and nothing ever
  calls it, because it is reached only when a unit dies or a reserve releases, and there are
  neither. The pilot is alive in an empty arena; flying out past `EGRESS_RADIUS` does nothing
  because `_physics_process` requires `phase == EGRESS`. The only exit is quitting, which by
  P1.q4 loses the sortie. I set node 0 (`airspace/city`, seed 4242) to garrison `0.0` and to
  `0.5` in turn; both produced `slice_ready=true archetype=dogfight assets=0 placed_units=0
  triggers=0`, both returned refusal `''` (**launchable**) from `WarView.refusals`, and after
  4.0 s of real physics both read `phase=ENGAGED, egress_opened fired 0 times,
  sortie_finished fired 0 times`. Reachable by ordinary play: clear a deep `airspace` node you
  have no adjacency to capture (so `apply_sortie` takes the `degraded` branch and it stays
  enemy-owned at or near zero garrison), then select it again.
- **How to prove it:** as above — generate seed 4242, set an enemy `airspace` node's `garrison`
  to `0.0`, `compose`, `start()` a runner on it with no player, pump ~960 physics frames, and
  assert `phase != ENGAGED`. It fails. Cheaper still: assert
  `WarView.refusals()[id] != REASON_NONE` for that node; it is currently `REASON_NONE`.
- **Blast radius:** the human's live campaign — a node that becomes a dead end they can only quit
  out of, and quitting is defined as losing the sortie. It also silently poisons `sortie_bench`:
  such a cell burns its full 300 s cap and reports a timeout with `dent 0.0`, which is exactly
  the "0 is equally consistent with a hard thing, a broken thing, and a thing that left the
  level" failure the project's second standard was written about. Any bench sweep that has ever
  visited a low-garrison airspace node has an unattributed timeout in it.

### F2 — The dent is blind to objective destruction, so a perfect strike measures as zero cleared

- **Where:** `scripts/sortie/sortie_runner.gd:301` (`"dent": WarManifest.dent_from_kills(kills)`),
  `:515` (`kills` is fed only by unit `destroyed` → `_on_points_scored`), `:620-633`
  (`_on_points_scored` is the sole writer of `kills`), `:695-702` (`_on_objective_destroyed`
  increments `_objectives_down` and emits points but never touches `kills`);
  `scripts/combat/objective_asset.gd:31,139`; consumed at
  `scripts/tests/sortie_bench.gd:403,412` and `scripts/war/war_sim.gd:73`.
- **Severity:** instrument
- **Confidence:** CONFIRMED (executed)
- **The failure:** a pilot who flies node 8's strike, flattens all three production structures
  and shoots no defender produces `objectives_destroyed=3/3, objective_complete=true,
  egressed=true, outcome=complete` — and `kills = {}`, **`dent = 0.000`**. I ran it. Fed to
  `WarSim.apply_sortie` the war does register it (the `degraded` branch spends
  `config.sortie_damage`: garrison 36.400 → 26.400), so the *campaign* is not blind — the
  *instrument* is. `sortie_bench` computes its `cleared` column as dent ÷ garrison, so that
  flawless sortie reports **`cleared = 0.0%`**, identical to a pilot who arrived and did nothing.
  Six of the seven archetypes carry objectives; only the dogfight's dent is complete by
  construction. This lands directly on v2.13's headline result — "54% cleared at depth 3 falling
  to 21% at depth 7" — which was adopted *because* the completion rate had saturated at zero. The
  replacement metric cannot see the objective half of the mission it replaced.
- **How to prove it:** compose any `factory` node, `start()` a runner, `take_hit(99999)` every
  entry in `runner.objectives`, `force_egress()`, and print `result()["dent"]`. It is `0.000`.
  Then check whether any archetype in the v2.13 sweep table has a `cleared` value that is
  explicable by objective progress the dent could not see.
- **Blast radius:** every SDI number for strike / sead / strike_cap / decapitation / interdiction
  / raid, i.e. the entire archetype-difficulty comparison, including the depth curve H7's
  127-sortie debt is being measured against. It does not corrupt saves.

### F3 — Deleting one line in `start()` restores v2.01's pacing bug, and the whole board stays green

- **Where:** `scripts/sortie/sortie_runner.gd:231-234` (`start()` populates three parallel arrays),
  `:254-259` (`reserves_held()` iterates `_trigger_released`), `:606-609` (`_release` writes it);
  the check that should guard it: `scripts/tests/sortie_check.gd:344-347`.
- **Severity:** instrument (a check that cannot fail, guarding a known-regression)
- **Confidence:** CONFIRMED (mutation executed)
- **The failure:** `_check_trigger_selection` never calls `start()`. It sets `runner.spec` and
  `runner.phase` by hand and then appends to `_triggers`, `_trigger_spent` **and**
  `_trigger_released` itself (lines 345-347) before driving the real `_fire_trigger` / `_release`.
  So the probe supplies the exact bookkeeping whose maintenance is the joint's whole
  responsibility. I deleted `_trigger_released.append(false)` from `start()` (line 234) and ran
  `sortie_check`: **exit 0, fully green**, including the four assertions whose text is about
  reserves being held. The consequence of that deletion in the real game is not cosmetic:
  `_trigger_released` stays empty, so `reserves_held()` returns 0 unconditionally, so
  `_check_field_cleared()` opens the egress the instant the field is clear **with a whole wave
  still on its timer** — which is v2.01's "announced `AIRSPACE CLEAR` in the same frame it
  announced `contact - reserves inbound`", the bug that also paid you to fly away from the fight.
  Part B does not catch it either, for the same reason: a dogfight whose `reserves_held()` is
  permanently 0 reaches `Phase.EGRESS` sooner and every downstream assertion still holds.
- **How to prove it:** delete `sortie_runner.gd:234` and run
  `<godot> --headless -s scripts/tests/sortie_check.gd --path .`. It passes. Revert.
- **Blast radius:** the one check standing over the reserve-pacing regression cannot see the
  regression. Nothing is currently broken — this is a hole in the net, not a hole in the boat.

### F4 — The ingress remap's "ORDER PRESERVED" claim is asserted nowhere

- **Where:** `scripts/sortie/sortie_runner.gd:355-364` (`ingress_range`), asserted (or not) at
  `scripts/tests/sortie_check.gd:265-274`; the claim is made at `sortie_runner.gd:114-123`,
  `CLAUDE.md`, `TESTING.md:225-228`, and GAMEPLAY-DESIGN v2.15 ("140 m (city) → 148
  (industrial) → 173 (hills) → 195 (desert/plains)").
- **Severity:** instrument / drift
- **Confidence:** CONFIRMED (mutation executed)
- **The failure:** the anti-constant assertion collects `ranges[ingress_m] = world_range` and then
  requires only `distinct_ranges.size() > 1` — i.e. that *at least two* distinct fiction values
  map to *at least two* distinct world values. It says nothing about which way round. I changed
  `lerpf(INGRESS_MIN_M, INGRESS_MAX_M, t)` to `lerpf(INGRESS_MAX_M, INGRESS_MIN_M, t)`, inverting
  the mapping so a city drops the pilot at 195 m and open desert at 140 m — the exact opposite of
  the documented behaviour and of the reasoning it was built on ("open ground still buys the
  longest exposed run and a city still drops you closest"). `sortie_check` passed: exit 0, with
  `different approaches give different ingress ranges (4 specs -> 4 ranges)` reading `ok`. The
  monotonicity itself is currently *correct* — `t = (fiction - 150) / 250` is increasing, and
  `clampf` keeps the output inside `[140, 195]` for any `ingress_m` the composer can emit,
  including a missing `approach` (defaults to `INGRESS_OPEN_M` → 195). The defect is that nothing
  holds it there.
- **How to prove it:** the mutation above, one 7-second run. The assertion that would catch it is
  a comparison of two specs' *ordering*, not their distinctness.
- **Blast radius:** the biome–range relationship is the entire content of the remap, and it is
  the one property a future retune could silently invert. Also note `INGRESS_COVER_M` appears in
  the denominator via `inverse_lerp(shortest, INGRESS_OPEN_M, ...)`: were it ever set to 0 the
  result is a NaN transform origin, unguarded and unasserted.

### F5 — A left-click reaches the map through the debrief and animation gates written to block it

- **Where:** `scripts/warroom/war_room.gd:111-116` (the click branch, which `return`s), versus
  `:117-123` (the debrief gate) and `:127-130` (the animation gate); effect at `:310-313`
  (`_select` → `_update_card`) and `:362-371` (`_update_card` reads `_state`).
- **Severity:** correctness
- **Confidence:** CONFIRMED (traced)
- **The failure:** the mouse-button branch is placed **above** both gates and returns
  unconditionally, so it runs while the debrief panel is up and while the tick is animating. The
  comment on the animation gate states the invariant it is protecting — *"selecting a node
  mid-animation would read the war it is halfway through becoming"* — and clicking does exactly
  that. Concretely: finish a sortie, and while the debrief is up (the map is deliberately drawing
  the **pre-tick** snapshot, `_rebuild(_pre_tick)` at `:87`) click any hex. `_select` runs,
  `_table.select(id)` moves the ring on the pre-tick board, and `_update_card` renders from
  `_state` — which is **post-tick** — while `_reasons` is still the pre-tick refusal set computed
  by the last `_rebuild`. The card then describes a garrison, weather and intel age from after
  the tick, with a flyability verdict from before it, over a map showing neither.
- **How to prove it:** click a hex with the debrief visible and compare the card's garrison line
  against the same node's card after dismissing the debrief and letting the animation finish.
  They differ. Or headlessly: assert that `_unhandled_input` ignores a
  `InputEventMouseButton` while `_debrief.visible` — it does not.
- **Blast radius:** no save corruption and no double-tick (launch *is* correctly gated — see the
  clean list). It misinforms the player at the one moment the room is deliberately showing them
  two different wars, and it breaks a stated invariant, so the next person to reason from that
  comment will be reasoning from something untrue.

### F6 — A reserve timer from a finished sortie releases into the next sortie on a reused runner

- **Where:** `scripts/sortie/sortie_runner.gd:602-603` (`create_timer(...).timeout.connect(
  _release.bind(pick))`), `:606-615` (`_release` guards only `phase == DONE`), `:224-234`
  (`start()` clears and repopulates the arrays the pending timer will index);
  exercised by `scripts/tests/sortie_check.gd:437` then `:461` (one runner, two sorties).
- **Severity:** correctness (bench/check-scoped)
- **Confidence:** LIKELY (mechanism traced end to end; I did not execute a demonstration)
- **The failure:** `_fire_trigger` hands a `SceneTreeTimer` a callable bound to an **index** into
  arrays that `start()` will clear and rebuild. The timer is owned by the tree, not by the runner,
  and `_release` only refuses to run when `phase == DONE`. So: sortie A fires a reserve with
  `after_s` of 1.5–10 s; the pilot egresses or dies first, `_finish()` sets `DONE`; the same
  runner instance is then given sortie B, which sets `phase = ENGAGED`. When A's timer fires,
  `_release(index)` proceeds against **B's** arrays — marking one of B's reserves as *arrived*
  without it ever having fired (which can open B's egress early, since `reserves_held()` gates
  it) and spawning **A's** reserve units into B's arena, where they are appended to `B.units` and
  will be credited to B's dent. If B has fewer triggers than `index + 1` it is an
  index-out-of-range instead. `sortie_check` performs exactly this sequence — its dogfight stage
  fires `wave_cleared` reserves at `after_s` 1.5 and 3.5 and then starts a strike on the same
  runner within a few frames — so the check is very likely already experiencing it silently.
  The shipped game is **not** affected: `sortie.gd:294` and `sortie_bench.gd:278` each build a
  fresh `SortieRunner` per sortie/rep and free the arena, so the callable's target dies with it.
- **How to prove it:** in `sortie_check`, log `(_cell, index)` on entry to `_release` and check
  whether any release is logged after `_stage_start_strike` has run with an index the strike did
  not fire. Or add a generation counter to `start()` and bind it alongside `pick`; a mismatch is
  the proof.
- **Blast radius:** today, `sortie_check`'s strike stage runs with unaccounted extra units and a
  falsely-arrived reserve — it still passes, which is the problem. It becomes a product bug the
  moment anything reuses a runner across sorties.

### F7 — A failed save leaves the player told the war moved when it did not

- **Where:** `scripts/warroom/war_room.gd:205-206` (`if persist and WarSave.save(_state)`), after
  `:194` has already applied the sortie and ticked, and `:199-201` has already shown the debrief.
- **Severity:** hygiene
- **Confidence:** SUSPECTED
- **The failure:** `WarDebrief.resolve` mutates `_state` (dent, capture, pilot decrement, a full
  `WarSim.tick`) and the debrief text and the pending animation are built from it, all before the
  save is attempted. If `WarSave.save` returns false — disk full, path unwritable, the
  moved-aside-unreadable-save path having failed — the player watches the tick play out on the
  map and the next launch reloads the previous save, so the sortie, its dent, its capture and a
  lost pilot all silently un-happen. The `false` return is used only to decide whether to print
  a line.
- **How to prove it:** make `WarSave.PATH` unwritable (or stub `save()` to return false), fly a
  sortie from the room, watch the debrief and the animation, return to the menu and back into the
  room, and compare the tick number against what the debrief said.
- **Blast radius:** one sortie's worth of campaign, silently. It is arguably consistent with
  P1.q4 ("exit without save") — the distinction is that P1.q4 is a choice the player makes and
  this one is a lie they are told.

---

## Checked and clean

| What | Verdict |
|---|---|
| The 19-check board | All 19 pass by exit code on a clean import of the pinned HEAD. `HANDOFF-NEXT.md:18`'s "19 headless checks, all passing" is true today. |
| `TESTING.md:290-300`'s check list | Exactly 19 `*_check.gd` files exist and the names match. The other `*_check.gd` files in `scripts/tests/` (`building_gen`, `city_layout`, `interior_gen`, `interior_lod`, `world_building`) are the procgen set `CLAUDE.md` explicitly describes as run on demand rather than on the board — consistent, not drift. |
| `snappedf` banned in `scripts/war/` | Holds. It appears nowhere in `scripts/war/` or `scripts/warroom/` except inside `war_sim.gd:130`'s comment explaining the ban. Remaining uses are all in `scripts/tests/` and `scripts/balance/` (display rounding and check-side expectations). |
| No JSON path for war state | Holds in production. `JSON` appears only in `scripts/profile.gd` (the arcade profile), `scripts/balance/prediction.gd`, and four test/bench files. `war_loop_check.gd:168` uses JSON *deliberately*, to assert it would break the save. `war_soak.gd:50` uses `hash(JSON.stringify(state))` as a state fingerprint and its own comment at `:47` names the type-drift blind spot — aware, not accidental. |
| Double-tick / apply-twice on the campaign turn | **Sound**, and better guarded than the request feared. `WarLaunch.take_result()` (`war_launch.gd:46-50`) clears `flew` and `result` as it consumes; `war_room.gd:184-188` then calls `WarLaunch.clear()` and returns early on `not flew or result.is_empty()`. Re-entering the room cannot re-price the same sortie. |
| Two paths pricing a sortie into a war | **Equivalent and mutually exclusive.** `sortie.gd:341-347` sets the result, and `if WarLaunch.from_room:` returns before `_resolve_standalone`, so exactly one of {room, standalone leg} resolves. Both go through the same `WarDebrief.resolve`, so there is one apply-and-tick implementation, not two. |
| Stale in-memory state over a newer save | **Cannot happen by the traced route.** The room reloads from disk in `_ready` (`war_room.gd:69`) *before* `_resolve_returning_sortie` runs, so the returning result is applied to the freshly loaded war, not to a snapshot held across the scene change. `war_launch.gd:11-15` deliberately carries only the seed and the persist flag, never the state. |
| A bogus result advancing the war | **Guarded.** `WarDebrief.resolve:24-27` returns `{}` without ticking when `apply_sortie` cannot find the node, and `apply_sortie:64-66` returns `{}` before mutating anything. `war_room.gd:195-196` then returns early, so no `_pre_tick`, no animation, no save. |
| Launching during a debrief or mid-animation | **Guarded.** `war_room.gd:117-123` gives the debrief every key, and `:127-130` blocks the map while `_table.is_playing()`; both `return`. `_launch` also re-reads `_reasons` (`:167-170`) so the card and the button cannot disagree. Only the *click* path escapes — F5. |
| `ingress_range` bounds | **Cannot be violated by any spec the composer can emit.** `_approach` (`sortie_composer.gd:382`) emits `400 - cover*250`, and `COVER` (`war_manifest.gd:71-74`) is `[0.00, 1.00]`, so `ingress_m ∈ [150, 400]`; `clampf` on the `inverse_lerp` pins the output to `[140, 195]` even for out-of-band or missing input. Above `EGRESS_RADIUS` 105 by 35 m and below `sortie.gd:64`'s `signal_warn_m` 220 by 25 m. The four documented stops reproduce from the constants (city 1.00→140, industrial 0.85→148, hills 0.40→173, desert/airfield_plains 0.00→195), and `TESTING.md:211`'s sample briefing line `148 m ... [spec says 187 m]` is arithmetically consistent. |
| `sortie_check`'s trigger source-scan | **Sound.** `sortie_check.gd:103-113` matches the literal `'_fire_trigger(&"%s")'` against `sortie_runner.gd`'s `source_code`. All three live values (`objective_damaged`, `wave_cleared`, `detected`) have real call sites at `:641`, `:687`, `:691`. It *could* in principle be satisfied by the string appearing in a comment or a dead branch — but `_check_every_archetype_can_end` (`:126-182`) is the behavioural half and actually observes `reserves_unfired()` fall for every one of the seven archetypes, so the pair is not fooled by text alone. |
| `_split_reserve` cannot reserve the whole garrison | **Sound.** The `reserved_units + 1 < total_units` guard (`sortie_composer.gd:291`) leaves at least one unit placed whenever the projection is non-empty. The empty-projection case is F1 and is upstream of this function. |
| `WarManifest.project` determinism | Reads clean. Its RNG is seeded from `(theater_seed, node id)` only (`:341`), the greedy fill has no dice, and ties break on `ROSTER` order (`:193-197`) rather than dictionary order. Reading a manifest cannot move the war. |
| `WarSim.weather_after` dice | Reads clean *as a pure function*: seeded from `(theater_seed, node id, tick_index)` with multipliers deliberately different from `sortie_seed`'s (`:175-176`), takes no `RandomNumberGenerator` from the caller, and `_weather_and_intel:403` computes the real tick's weather through the same function — so the forecast cannot be a lie by construction. I did **not** audit the rest of Track 3's RNG surface. |
| Objective destruction attribution | `ObjectiveAsset` emits only `destroyed(points)` and `first_damaged` (`:31`, `:36`), and the runner's `_on_objective_damaged` fires `objective_damaged` **and** `_announce_yourself` (`:690-692`), so both trigger routes are live. Damage by a non-player agent is priced identically — which is intended (P2.q4) — but see F2 for what it does to the dent. |

## Could not determine

- **Whether F1 has ever silently corrupted a published bench number.** Settling it needs the
  archived `sortie_bench` logs read for cells on `airspace` nodes whose garrison had already been
  dented low, looking for `timeout` with `dent 0.0`. That is a log-reading job with a known
  signature and it costs one pass over `balance/`.
- **Whether F6 is currently firing inside `sortie_check`.** One `print` in `_release` decides it.
- **Track 5's reproducibility question — completely open.** I did not enumerate the 15
  `static var`s, the shared `.tres` instances, `ProjectilePool`, group residency across deferred
  frees, or per-process seeding. The one thing I can contribute is a *ruling out*: the mechanism
  in F6 (a tree-owned timer outliving its sortie) is **not** available to `delivery_bench` or
  `sortie_bench`, because both rebuild the runner and free the arena per rep. Anyone resuming
  Track 5 should start from the `static var` enumeration the request specified; it is unspent.
- **Whether `war_room_check` (870 lines) is real.** It passes, and I did not open it. Its two
  deliberately-awkward assertions (the independently-written strike-range walk, the four-node
  supply cut) are described in `TESTING.md:332-340` and were not verified against the code. Given
  that `sortie_check` — the other newest check — yielded F3 and F4 under two cheap mutations, the
  same treatment of `war_room_check` is the highest-value unspent hour in this audit.
- **The five never-measured archetypes.** `sead`, `strike_cap`, `decapitation`, `interdiction`
  and `raid` all pass the structural end-condition sweep in `sortie_check:126-182`, which
  flattens their objectives synchronously. That proves the egress opens; it does not prove a human
  can reach that state. F1 shows the assets-0 case is unendable, and by symmetry the assets>0
  archetypes are safe from *that* hang — but "an objective that cannot be reached or damaged" is a
  different failure and only a flight or a bench will find it.
- **Whether the objective's husk can block its own egress.** `objective_asset.gd:25-31` says a
  destroyed asset "goes dark and KEEPS its collision". I did not check whether a husk can trap a
  pad, an arriving reserve, or the pilot. Worth one read of that file in full.
