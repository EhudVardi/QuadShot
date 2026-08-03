# QuadShot — Gameplay Design (Living Doc)

> **Status:** v1.29 (2026-07-22) — paper phase complete; **the vertical-slice
> build is underway, Phases 1–3 landed and steered by playtest.** Done: the
> matchup harness + reference pilot (P1), P2 — the damage model + the
> fly-through **repair-gate** wounded-quad loop + the **FCS reticle**, and P3 —
> **the slice bestiary**: EnemyConfig migration, the **Gnat** swarm ("the cloud
> is the unit"), the **Aegis** shielded bomber (threshold-gate shield, a real
> barrier), the harness banding the measured mini-web against P4.3, and a
> **watchable harness** (drop `--headless` and see the duels, real HUD included).
> v1.23 is a **balance-model realignment**: the war is arithmetic, kinetics are
> player-only ("the war shapes your fights; your fights dent the war"), the
> harness is feel-promise CI — and the **layered balance model** (lethality ×
> aim × evasion, duel as validation) is adopted. New steering: **allied kinetic
> presence in player sorties is wanted** (composer-era; the sortie is our
> bubble). v1.24 **builds that instrument: Phase 3.5 is DONE** — BALANCE.md +
> `PILOT_VERSION`, the Layer 1 lethality calculator (planted-shot verified),
> the Layer 2 aim/evasion benches, and the mini-web rebanded as **paper →
> predicted → validated** behind `tools/balance_report`. It works: the model
> independently reproduced the human's hand band on the one cell the duel
> could never measure, and its first run raised four findings — three stale
> paper bands and a conflated cell — **awaiting the human's call**. v1.25 acts
> on that call: the **state split** (a shielded type is two targets in
> sequence, blaster `--` shielded / `++` cracked) makes **combos derivable**
> rather than tabulated; the harness **isolation fix** un-conflated
> `Missile × Aegis` (paper `++` is a combo band, missile-solo is `+`) — which
> exposed a hidden **pilot defect** (no standoff: it rams the non-evading
> bomber), left for a deliberate `PILOT_VERSION` bump; and **watch mode is now
> standing policy** (every bench watchable from its first commit). v1.26 fixes
> the pilot itself (**v2: standoff by orbit**, homing weapons only) — aiming a
> 44°-uptilted gun IS closing, so range is held in the roll axis by curving,
> never in pitch; `Missile × Aegis` goes 0/6 timeouts to **6/6 wins spending
> exactly the 3 missiles Layer 1 predicts**. v1.28 lands **Phase 4's first
> half: the flak pod** — the 3rd weapon column and the designed gnat answer.
> The paper `++` HOLDS and is the only cell in the table where paper, predicted
> and validated all agree: 9/9 gnats cleared for 2.7 shells and zero hull, where
> the chip gun manages 1.8 kills for half the player's hull. It also cost the
> model one honest extension (`splash`, a third delivery factor) and surfaced
> that the ruler's own aim datum — not the weapons — decides the flak-vs-gun
> single-target cells. v1.29 is the human flying it: positive feel ("flak
> absolutely destroys the gnats… really helps against groups of raiders"), and
> the blackbox — read back for the first time as deviation data rather than a
> debug channel — names a real coverage gap the paper couldn't: every
> `× Raider` cell, every weapon, is 1v1, while the shipped wave director spawns
> raiders in growing concurrent groups. Logged, not built — a Raider×N pack
> bench and a richer combat-event blackbox both queued behind Atlas, by the
> user's own call.
> **Next: Phase 4's second half** — Atlas, the 2nd frame. Design record below.
> Seven iterations closed: five pillars (P1 theater, P4 bestiary, P3 arsenal, P5
> economy, P2 composition) + Iteration 6 (the balance harness + stated difficulty
> curve, H1–H9) + Iteration 7 (the damage model — flying the wounded quad, D1–D9)
> all proposed *and* steered; all four forks (F1–F4) decided; the
> war-sim skeleton lives and runs green (v1.7). The model composes end to end and
> now *proves itself*: the war generates nodes, the manifest dresses them in the
> bestiary, the arsenal answers the matrix, the economy prices it, the composer
> projects it into sorties, and a four-layer harness (unit/sortie/economy/
> strategic) measures whether it all lands on the difficulty curve — SDI measured,
> not authored; a scripted reference pilot the hands calibrate.
>
> **Iteration 7 (the damage model) closed the one gap a completeness review
> surfaced:** the pillars specced *enemy* durability richly but left the
> *player's* damage an abstract hit-point pool — a number, in a game whose north
> star is *the flight model is the product*. It makes damage a **flight-model
> event** (flying a wounded quad: asymmetric motor-out, prop vibration feeding the
> Filtering group, video breakup), ramped arcade↔sim for readability, gives
> pads/repair (P2.6/P5.6) their missing referent, and locked the **anti-
> frustration guardrail** (no hopeless fight; denial never removes the skill path
> — the harness enforces it numerically). **Next is not paper: it's the
> vertical-slice build** (P4.10/P3.10/P5.11/P2.13 + D9's motor-out surface), the
> H9 harness cut making it measurable from its first commit — and per H.q4 the
> hands-on difficulty calibration, when the slice flies, is mine to initiate.
>
> **How this doc works:** this file is the design *and its history*. Nothing is
> deleted — decisions get dated entries in the [Decision Log](#decision-log),
> superseded ideas stay in place marked as such, and the doc is allowed to grow.
> It should BE the journey, not a polished snapshot of the end state.
> Pillars are **P1–P5**, load-bearing decisions are **F1–F4** (+ lettered
> sub-questions). Reference IDs when responding so we stay precise across
> iterations.

---

## Glossary

- **Headless** — running the Godot engine from the command line with no window
  and no rendering ("no head" = no display). The full game logic and physics
  run invisibly, as fast as the CPU allows. We already lean on this everywhere:
  the five automated checks (`hover_check`, `combat_check`, `wave_check`,
  `missile_check`, `run_check`) and the tuning benches (`step_response.gd`,
  `rate_tune_sweep.gd`) all run the *real game* headless and print measurements.
- **Theater** — one procedurally generated war: the strategic node-map plus its
  live war state. A playthrough = one theater fought to its end.
- **Node** — one location on the theater map (airfield, factory, radar site…)
  with a type, an owner, a garrison, and a strategic function.
- **War tick** — one advance of the strategic simulation (enemy moves,
  reinforcements, production). Per **F2**: ticks happen between sorties, not in
  real time.
- **Sortie** — one flight into one node; the FPV tactical gameplay we've built.
- **Frame** — a player drone airframe (mass, TWR, rates — a FlightConfig
  profile) with a fixed **hardpoint profile**.
- **Hardpoint profile** — the *mounting capacity* a frame offers: how many
  weapon slots, of what size/type, with what weight budget. Fixed per frame.
- **Loadout** — what you actually *mount* on those hardpoints for a given
  sortie. Chosen per mission; constrained by the frame's hardpoint profile.
- **Counter-web** — the designed rock-paper-scissors network between weapons/
  frames and enemy types; the deliberate absence of a universal answer.
- **War-sim** — the module that owns the strategic state and executes war
  ticks. Per **F4**: deterministic, seed-driven, fully serializable.

---

## 0. North star

The **sim-grade flight model is the unique selling point.** Almost every
roguelite shooter has shallow movement — dashes and strafes. QuadShot has a
real FPV acro flight model: a 240 Hz rate loop, Betaflight-style filtering,
feedforward, crash recovery. Nobody is combining *that* depth of flight with a
*Falcon 4.0-style living campaign*.

That combination is the game. The arcade look doesn't dilute the sim core — it
makes a hardcore core approachable:

> **Serious systems, readable presentation.**

---

## 1. M6 triage — RESOLVED (2026-07-15)

Everything stays tracked in [ROADMAP.md](ROADMAP.md) (reorganized into groups) —
nothing is dropped, everything can be reconsidered later.

| Item | Decision | Notes |
|---|---|---|
| **Real radio / HID** | **DO NOW** — the only backlog item pulled forward | Target hardware: **RadioMaster TX16S**. *Scope refined v1.1:* **basic capabilities first** — enough to experience the physics on a real radio. The gamepad may well remain the more fun way to play (user's hunch); the radio track exists to validate/tune the flight model on real gear, not to replace the pad. Extend later if it earns it. |
| **Wind** | Expanded into a **Weather** group, folded into gameplay (P1) | The dream: dynamic wind, rain, hail, fog, heat wave, sandstorm — battlefield modifiers that serve the gameplay model. See P1. |
| **Propwash / ground effect / turtle mode** | Roadmap **Physics** group, later | Turtle mode explicitly not needed now — 3D mode already recovers from upside-down. |
| **Settings / overlay UX** | Partial pull-forward | Collapsible overlay groups + hideability (QoL, cheap). Control remapping rides along with the radio work's binding layer, designed to extend easily as features grow. Graphics quality options (shadow res, glow toggle, resolution scale — scaling for weaker GPUs) stay deferred to pre-release. |
| **Replays / ghosts** | Sit as-is | The blackbox recorder already proved itself repeatedly as a debugging channel — keep it simple. Revisit as a player feature after the *second* graphics upgrade, with a proper cinematic camera director (random static cameras would kill it). |
| **VR / OpenXR** | Parked | Acro + VR = nausea. |

---

## 2. The gameplay design

### 2.1 Lineage / references

- **Falcon 4.0 (1998) — the dynamic campaign.** The childhood memory: a
  battlefield moving and developing in real time, mission options that move the
  battle forward. You were *one pilot in a war that had its own agenda*.
  (To confirm the memory: yes — Falcon 4.0 was one big continuous real-time map
  of the Korean peninsula, not nodes. Our node abstraction is a deliberate
  simplification of the same living-war idea; see F2.)
- **FTL.** A roguelike run = a journey across a generated map of meaningful
  choices, with escalating pressure.
- **Into the Breach.** Tight balance through *readable, near-deterministic*
  systems — our model for catching imbalance early.

Each reference serves a distinct pillar: Falcon → P1, FTL → run structure and
P5, Into the Breach → the balance methodology (2.4).

### 2.2 The core idea: a playthrough is a *campaign over a living theater*

You are a drone pilot embedded in a war. A **playthrough** is a procedurally
generated **theater** — a strategic map of nodes (airfields, factories,
radar/SAM sites, supply depots, command posts, contested airspace) — that is
**alive**: a war-sim runs underneath, the enemy expanding, reinforcing, and
launching its own operations.

Between sorties you see the theater and **choose which node to strike**. Flying
that sortie is the FPV combat we've built — composed and made difficult *by the
strategic state*. Winning a sortie **changes the battlefield**: capture a node,
sever a supply line, blind a sector's radar — and the war responds.

You win the playthrough by breaking the enemy's command structure. You can lose
it *strategically* (your forward base falls) even while personally surviving —
and per **F1**, you can also lose it by running out of pilots. Each generated
theater is **a war you fought and shaped**, not a level you cleared. The goal
feeling, in the user's words: **ownership of the playthrough**.

### 2.3 The five pillars

**P1 — The Living Theater** (strategic layer, new). *Endorsed v1.*
The generated node-graph plus the war tick. Nodes have type, ownership,
garrison strength, and *function* (a radar node extends enemy detection; a
factory reinforces nearby garrisons; a command node buffs a whole sector) —
giving sectors character and a clear desired goal. The enemy AI maneuvers
between ticks.

*Added v1 — Weather (from the M6 wind item, expanded):* weather is a
**battlefield modifier layer** on nodes/sectors: dynamic wind (flight
difficulty — gusts fight the rate loop honestly, no physics cheating), rain and
hail (visibility, maybe motor/prop stress), fog (sensor and visual range —
interacts with radar nodes and missile lock), heat wave (motor thermal limits /
efficiency), sandstorm (severe visibility + abrasion pressure). Weather makes
node choice richer ("the factory is exposed today — but so am I") and ties
into the LookConfig system visually. Design detail deferred to the P1
iteration.

**P2 — The Sortie** (tactical layer, mostly built). *Endorsed v1.*
One flight into one node, procedurally composed *from the node's type and the
war state*: a radar node plays like SEAD, a factory like a strike, contested
airspace like a dogfight. Flight + combat + the M4 draft/RunMods loop already
live here. **Difficulty falls out of the strategic state — organic balancing
instead of hand-tuned levels.** ("Organic" is the key word — fairness as an
emergent outcome of the balance web, not per-level tuning.)

*Added v1.6 — sortie scale & the land as gameplay (user):* sorties should
feel **big and expansive** — the current dev room is a testbed, not a sortie.
The terrain itself is a primary gameplay force: hills, dunes, buildings and
trees offer **cover and cooldown positions**; a long ingress over barren
ground toward a defended base builds tension (exposed, low-margin flying,
battle ahead); dense cities flip the economics — lots of cover for the
player, so the enemy must position and equip differently. Sortie maps get an
**approach-phase structure** (ingress corridor → target zone) and their
geometry comes from the node's biome (P1.9). Land = cover economics; the
counter-web (P4) must price it in.

*Added v1.6 — repair/re-arm pads (user):* forward landing pads inside sortie
maps where touching down repairs and re-arms — landing skill becomes
gameplay (the flight model is the product, and precision landings under fire
are peak flight model). Pad availability/count/quality is a **difficulty
knob** the strategic layer and biome can set; a pad can also be a capturable
or destructible asset, making "secure the pad first" a valid opening move.

*Added v1.6 — dares: opportunistic skill challenges (user):* sortie maps
sprinkle **one-time, optional, high-risk micro-challenges** that entice an
adventurous pilot: a stray gate, a building window, the gap between a
collapsed slab and a rebar arch over the rubble. Fly the gap cleanly →
unique reward (salvage cache, an extra draft pick, intel, a pilot?). Dares
are the flight model advertising itself: pure flying skill converted into
campaign currency, priced by risk (clipping the rebar at speed is a real
crash). Generated from biome geometry (P1.9 interest points), announced
subtly (a glint, a ring of light — no quest markers), never required.

**P3 — The Arsenal & Airframe** (build / loadout). *Endorsed v1.*
Multiple frames with *real* tradeoffs expressed directly in FlightConfig (mass,
TWR, rates, filtering): light interceptor vs. heavy gunship vs. stealth recon
as different flight-config + hardpoint profiles.

*Clarified v1 — hardpoints vs. loadouts:* the **hardpoint profile** is the
frame's fixed mounting capacity (slot count, slot size/type, weight budget);
the **loadout** is what you choose to mount in those slots for a sortie. Frame
fixes the possibilities, loadout is the per-mission choice — and mounted mass
genuinely affects flight via FlightConfig.

The measure ↔ counter-measure dynamic ("the right tool for the right job")
extends beyond weapons to vehicle domains (air primary; ground and sea assets
as targets/allies — see P4's naval note). **Intel-driven acquisition** endorsed:
within a playthrough, choices can reward the player with exactly the
measures/vehicles needed to keep winning — making intel and target selection
part of the build.

*Added v1.2 — Fire-Control Systems (FCS), born from the first real-radio
combat session:* flying real gimbals, the pilot's attention budget has no room
left for the trigger — which is exactly why real combat aircraft grew
fire-control computers. **Semi-auto fire moves the trigger to a lesser
concern: positioning becomes the skill.** Get the drone to the right point in
space — on the enemy's six, holding them on-reticle, sustaining a missile
lock — and the system converts that positional advantage into hits. This
subtly re-aims the whole gameplay ("feels like a different game" — in a good
way: most shooters make *aim* the skill; QuadShot makes *flying* the skill).

Crucially (user decision): aiming systems are **assets/tools/abilities/perks —
not an abstract gameplay mode.** FCS becomes an equipment family in the
arsenal, e.g. iron trigger (manual, baseline) → gun director (auto-fire on
ballistic solution — prototyped) → lead computer (wider solution, faster
convergence) → turret pods (fire off-boresight) — each competing for
hardpoints/mass against raw weaponry, each with counter-web implications
(EW/jammers should degrade FCS, making the manual trigger a *skill fallback*,
not dead content).

*Prototype shipped 2026-07-16:* `fire_assist_miss_m` / `fire_assist_range` in
CombatConfig (0 = off; a dev knob until the equipment system exists). Honest
ballistics — the assist sweeps the true projectile arc (muzzle + inherited
velocity + drop) against the hostile's predicted motion and fires only when
the predicted miss distance closes under the threshold, with line-of-sight
checked. No aim-bending, no homing bullets: the flight model stays the
product.

*Added v1.3 — the missile director (second FCS member, same session):* the
radio ergonomics finding repeated for missiles ("hard to mix flight with
realtime fight control" — the FCS thesis validated twice in one day), so
missiles gain their own director: **`missile_auto_switch`** (a two-position
stateful switch, like `arm_switch`; renamed from `missile_auto` in v1.3.1) —
with it on, a full lock held stable for `missile_auto_hold_s` auto-launches. The
HUD lock was made unmistakable (pulsing red double diamond + LOCK tag) and the
director winds an orange arc around it while the hold timer runs, so the pilot
always knows what the computer is about to do. Confirmed for the counter-web:
**EW/jammers should jam FCS members** (both gun director and missile
director), degrading or breaking their solutions — positioning gear vs.
denial gear becomes a real loadout axis.

*Added v1.6 — weapon design axes (user insight, the Firehawk lesson):* the
weapon roster is under-designed so far, and the user's Firehawk story is the
design compass: an energy weapon with charge-fire (hold = one powerful,
fast, flat shot; tap = cheap, slow, *ballistic-arc* shots) accidentally
enabled hovering-behind-a-hill lob-spam — dominant because it had **no cost
and no counter**, not because indirect fire is wrong. The lesson, adopted as
doctrine: **emergent tactics like that are treasures — design FOR them, with
prices and counters, instead of letting them be accidents.** Indirect fire
becomes a deliberate archetype (mortar/lob launcher: safe, slow, blind —
countered by interceptors that flush the camper); charge mechanics become a
weapon *axis*. The P3 iteration defines every weapon along explicit axes:
**trajectory** (direct / ballistic / homing), **fire model** (auto / burst /
charge), **economy** (ammo / energy / cooldown), **FCS compatibility**
(directable or manual-only), and **counter-web role** (which enemies it
answers, which punish it). "The right tool for the right job" is the leading
design hint for the whole roster.

**P4 — The Bestiary** (enemy ecosystem). *Endorsed v1.*
Enemy types built as a counter-web so composition matters and no loadout
dominates:

- **Interceptors** — fast, fragile; punish slow/heavy frames.
- **Shielded bombers** — need burst/missile to crack; ignore chip damage.
  *v1 note:* also work as **ticking bombs** — en route to friendly assets,
  forcing priority target calls before they deliver.
- **Swarms** — many weak units; need spray/AoE; punish single-target loadouts.
- **Static SAM / turrets** — punish straight lines, reward terrain-masking.
- **EW / jammers** — kill your lock-on, force gun kills.
- **Commanders** — buff nearby units; priority targets that force strategy
  adaptation per node.

**Design rule (locked):** every enemy has **≥1 good answer and ≥1 hard
counter**; no answer is universal.

*Added v1 — naval domain (post-core expansion):* sea nodes and ship classes for
variety and region control — e.g. **controlling the sea enables deploying
ground units to invade new nodes**, making naval superiority a strategic
enabler rather than a separate minigame. Design after the core air/ground web
is balanced; tracked here so the theater generator and node taxonomy reserve
space for it.

**P5 — The Reward Economy & Influence** (meta + agency). *Endorsed v1.1 — the
empty section in the v1 review pass turned out to be full agreement ("yes to
everything").*

Multiple reward axes so progress feels rich:

- *In-sortie*: the RunMods drafts we built (M4).
- *Campaign*: salvage → unlock new frames/weapons mid-run, repair, buy
  reinforcements for your side. (*v1 addition from F1:* extra **pilots** — 1-ups
  — join the reward pool.)
- *Cross-campaign meta*: permanent unlocks / mastery.

Plus **influence**: spend resources to direct the war — call an allied strike,
fortify a node, buy intel on a sector. Per **F3**, the deeper commander layer is
deferred and later enters as an *acquirable capability*.

### 2.4 Balance methodology (the rigor)

Complexity's real risk is balance. The approach — a direct extension of how the
physics was tuned with bench tools:

- **Every entity gets a stat config** (frames, enemies, weapons) as
  `TunableConfig` resources — every attribute explicit, versioned, and
  *live-tunable in the overlay*, exactly like FlightConfig. The human can
  re-balance continuously in play, then bake or parameterize what proves right
  (endorsed v1 — this mirrors the flight-tuning workflow that already works).
- **Design the counter-matrix first** — an explicit table of "how well does
  weapon/frame X answer enemy Y," built so the web has no dominant strategy.
  On paper before code.
- **A headless combat-sim harness** — the same trick as `step_response.gd` /
  `rate_tune_sweep.gd`, applied to battles: a script spawns loadout X against
  squad Y in the real game running invisibly (headless — see Glossary), lets
  the real weapons/AI/physics fight it out far faster than real time, repeats
  it hundreds of times across the whole matchup matrix, and prints
  time-to-kill / damage-taken / win-rate statistics. That's how "this weapon
  trivializes bombers" gets caught **numerically, before anyone flies it** —
  and re-caught automatically after every balance change.
- **A stated difficulty curve** the strategic layer must produce, validated by
  the sim.

### 2.5 Implementation discipline

Design the complexity fully on paper — many iterations, as expected — but
**implement the smallest vertical slice that delivers the feeling first**:

> One tiny theater (~5 nodes), 2 frames, 3 weapons, 4 enemy types forming a
> minimal counter-web, one influence action.

*(v1 note: slice composition is provisional — it may shift once the full
element definitions — frames, enemies, weapons — are complete. The principle is
what's locked: **design big, build in provable increments**, keeping smooth
back-and-forth while continuously steering toward the desired feel.)*

---

## 3. The forks — ALL DECIDED (2026-07-15)

**F1 — Stakes / permadeath → DECIDED: reinforcement-pilot lives economy.**
A playthrough grants **X pilot lives** (the old-school 1-up model). Death
consumes a reinforcement pilot; rewards can grant extra pilots; **running out
of pilots ends the player's road in the war** — alongside the strategic loss
condition (your forward base falls). This is the middle point: forgiving
enough not to frustrate, but death never loses its meaning (the anti-goal:
games where endless deaths make dying meaningless).
*Rationale:* merges "the war is what's at stake" with "my life still matters."

*Refined v1.1 (user):* running out of pilots is a **player** defeat, not the
war's end — "technically yes, spiritually it's the end of the player in the
road of the war." **The war model keeps existing and running.** Defeat should
feel like the war moving on without you, which is more immersive than a
game-over curtain — and it composes beautifully with **F4.a spectator mode**:
the natural defeat screen is *watching the theater conclude itself from its
seed*. (Adopted; design detail in Iteration 1, P1.5.)

Open sub-questions for the P5/P1 iterations:
- **F1.a** — difficulty. *v1.1 direction (user, still contemplating):* a
  **global knob** that scales things easier/harder may exist, but the *real*
  difficulty should be an **inherited quality of the war** — organic, with the
  war able to escalate when the player dominates. Hard constraint recorded:
  the acro-drone + firefight combination is niche, so the game **must offer
  newbies a feasible learning curve.** (Both threads picked up in Iteration 1,
  P1.7.)
- **F1.b** — should a death *also* cost tempo (the war ticks while you
  re-deploy)? *v1.1 (user):* interesting, likely a **cheap knob** — keep it as
  a tunable (default off) and decide when P1/P5 numbers exist.

**F2 — Time model → DECIDED: turn-based war ticks.**
A sortie is a well-defined, digestible chunk; finishing it returns you to the
**battle command room**, where the battlefield has changed while you fought.
No wall clock.
*Rationale (aligned both sides):* the node abstraction already discretizes the
map (vs. Falcon's continuous real-time terrain), turn-based is dramatically
easier to balance, reason about, and — critically for F4 — **serialize** (a
between-turns state snapshot is trivially saveable). Urgency can still be
designed in later *within* the turn model (e.g. operations that expire in N
turns) without real-time pressure.

**F3 — Scope of influence → DECIDED: kinetic-first; commander-lite deferred.**
At launch of the gameplay model, you affect the war primarily by what you
destroy/capture in sorties (plus the light economy actions in P5). The deeper
commander mode — macro agency over allied AI and the map — is **a future
gameplay branch**, and when it arrives it should be framed as an *acquirable
capability*: a special reward or purchasable "command authority" the player
earns in a playthrough (per the user's suggestion; mechanism TBD when we get
there). Tracked in ROADMAP.md.

**F4 — Campaign length → DECIDED: long persistent war across sessions.**
A playthrough is an extensive, deep war — a **pillar of the game**. The save is
a **single portable file** the player can physically move, back up, and share.
The deeper the playthrough, the stronger the ownership feeling (F4 is the
delivery mechanism for 2.2's "ownership").
*Architectural consequence (binding):* the war-sim must be a **deterministic,
seed-driven, self-contained, fully serializable module**. That's what makes the
portable save trivial — and it enables two pinned ideas for free:
- **F4.a (pinned, later):** *spectator mode* — the player can decline to fly and
  watch the theater unfold from its seed on its own. (Also doubles as a war-sim
  soak-test/debug tool during development.)
- **F4.b (pinned, far later):** *multiplayer* — players joining a running
  battlefield to help a player who asks for it. Parked at the very back of the
  roadmap; the deterministic war-sim keeps the door open.

---

## 4. Process

1. **This file is the living design doc *and* the changelog.** It records the
   dev journey; history is never cleaned out — the doc is allowed to bloat,
   because the accumulated reasoning is the value. (Adopted v1.)
2. Deepen **one pillar per iteration** — node taxonomy and war-tick rules,
   enemy stat blocks, the counter-matrix, the reward economy — in conversation,
   with decisions logged here.
3. The **headless balance harness** validates numbers as they're locked.
4. Implementation starts only when the vertical slice's design is solid.

### Proposed iteration order

| # | Topic | Why this order |
|---|---|---|
| 1 | **P1 — Living Theater deep dive**: node taxonomy, war-tick rules, theater generation, win/loss conditions, weather modifiers | It's the spine; F1/F2/F4 decisions all live here; everything else composes against it |
| 2 | **P4 + counter-matrix**: enemy stat blocks, the full web on paper | The bestiary defines what weapons/frames must answer |
| 3 | **P3**: frames, hardpoint profiles, weapon list vs. the matrix | Answers to P4 |
| 4 | **P5**: economy, rewards, pilots (F1), influence actions | Prices everything defined above |
| 5 | **P2**: mission composition rules (node state → encounter) | Needs all of the above as ingredients |
| 6 | **Balance harness spec** + difficulty curve | Then implementation of the slice begins |

### Parallel track (independent of design iterations)

- **TX16S radio support** + flexible input-binding layer (the "do now" from
  the M6 triage). Needs the human + hardware at the desk for testing.
- **Overlay QoL**: collapsible config groups, hideability polish.

---

## Iteration 1 — P1: The Living Theater (PROPOSED, 2026-07-16 — awaiting steering)

> The spine of the game. Everything below is a concrete opening proposal —
> creative, opinionated, and meant to be torn apart. Sections are **P1.1–P1.8**;
> react by ID.

### P1.1 — Theater generation & geography

A theater is generated from a **seed** (per F4, the seed + decisions = the
whole war, replayable and shareable):

- **20–40 nodes** laid out organically on a coastal landmass — land dominates,
  but the map always gets a **coastline** (reserving geography for the P4
  naval expansion: ports and sea lanes slot in without regenerating the world).
- Nodes connect by **edges** (roads/corridors); edges carry supply and define
  adjacency for the war-sim. The player's side starts in one corner with a
  **Home Airbase + a small secure pocket**; the enemy holds the far region with
  a deliberate **difficulty gradient**: garrisons near your pocket are light,
  deep territory is hard (this is half of the newbie-curve answer — see P1.7).
- A **front line** emerges from node ownership — not drawn by the generator,
  but by the war.
- **Sortie range**: you can only strike nodes within range of a friendly
  airbase. Capturing airbases extends your reach — geography as progression.

### P1.2 — Node taxonomy (the character of sectors)

Each node type = a strategic function + a sortie flavor + a capture payoff:

| Node | Strategic function (war-sim) | Sortie flavor (you fly it) |
|---|---|---|
| **Airbase** | Launch range for its owner; enemy airbases generate interceptor patrols on nearby nodes | Runway strike under CAP — kill patrols and ground assets |
| **Factory** | Produces garrison reinforcements each tick, shipped along supply edges | Strike: smash production before the escorts arrive |
| **Radar site** | Extends enemy **detection**: covered nodes show you degraded intel and spawn ambush waves against you | SEAD: kill the dish while it's calling interceptors onto you |
| **SAM battery** | Area denial: sorties into covered nodes take SAM fire; supply edges under cover are protected | SEAD: terrain-mask, break lock, kill launchers |
| **Supply depot** | Buffers supply; garrisons cut off from supply **decay** each tick | Strike/siege enabler: cut the artery, starve the sector |
| **Command post** | Buffs its sector's garrisons (aggression, coordination); part of the **command network** | Decapitation: kill the commander unit (P4) guarded by elites |
| **Theater HQ** | The war's brain; **win condition** (see P1.5); heavily defended, unlocked by degrading the command network | The final raid |
| **Contested airspace** | No owner; holding it shifts patrol pressure on neighbors | Pure dogfight — the M3 wave loop's natural home |
| *(reserved)* **Port / sea lane** | P4 naval expansion: sea control → amphibious invasions | Anti-ship / convoy strike |

### P1.3 — Node state & intel (the fog of war)

Every node carries: **owner · garrison composition** (an actual unit list drawn
from the P4 bestiary — not an abstract "strength 7") **· fortification ·
supply status · weather · intel freshness**.

The player doesn't see truth — they see **intel**: fresh after you overfly or
buy it, decaying each tick, degraded further under radar coverage. The
briefing shows *what intel believes* you'll face; the sortie shows the truth.
Stale intel = surprises. This makes recon flights, intel purchases (P5), and
radar kills *strategically* valuable, and it feeds P3's "loadout as a response
to intel" directly.

### P1.4 — The war tick (deterministic, seeded)

After each sortie (F2), the war advances in a fixed order — deterministic so
saves stay portable and replays honest (F4):

1. **Production** — factories generate units.
2. **Supply flow** — units and supply move along edges; cut nodes decay.
3. **Enemy operations** — the enemy AI acts by a priority system with
   seed-chosen **personality weights** (aggressive / defensive / opportunist),
   so different theaters *feel* like different opponents: reinforce threatened
   nodes, assault weakly-held player nodes, rebuild key infrastructure.
4. **Resolution** — off-screen battles (enemy assaulting your garrisons)
   resolve by war-sim odds. Your sorties are the thumb on this scale.
5. **Weather evolution** (P1.6) and **intel decay** (P1.3).

Allied garrisons **hold**; they don't launch offensives on their own (F3:
kinetic-first — *you* are the offense; commander mode later changes exactly
this). The **command room** replays the tick as visible map movement (P1.8) —
you watch the consequences of your sortie ripple.

### P1.5 — Win / loss / the war outliving you

- **Win**: destroy the **Theater HQ** — but it's shielded by the command
  network: only after enough command posts are dead is the HQ raid unlocked.
  "Break the enemy's command structure" is the arc of every campaign.
- **Strategic loss**: your Home Airbase falls.
- **Pilot loss** (F1, refined v1.1): your last pilot dies — *the player's road
  ends, the war does not.* The defeat screen is **F4.a spectator mode**: the
  theater keeps ticking from its seed and you watch the war conclude without
  you — your captured nodes slowly turning, or your side holding the line you
  built. Defeat as epilogue, not curtain. (Also the same machinery lets us
  soak-test the war-sim in development: generate 1,000 theaters, let them run
  headless, assert no degenerate stalemates.)

### P1.6 — Weather (the M6 wind item, grown up)

Weather is a **per-sector state** evolving each tick (seeded Markov chain —
deterministic like everything else): *clear · wind · rain · fog · heat wave ·
sandstorm* (hail as a rain intensifier). Each is a **modifier pack**:

- **Wind/gusts** — honest external forces on the airframe (never bending the
  flight model — the rate loop earns its keep), with the strength as the knob.
- **Rain** — visibility down, maybe camera-lens effects; mild sensor penalty.
- **Fog** — visual + lock range compression; radar nodes matter more; missile
  play weakens, gun play rises.
- **Heat wave** — motor thermal pressure: sustained full throttle sags (a
  MotorModel-level effect, physics-honest).
- **Sandstorm** — severe visibility + abrasion (slow chip damage at speed?).

The command room shows a **1-tick forecast** (intel-flavored): *when* to hit a
node becomes a decision — "the SAM site is blind in tomorrow's fog."

### P1.7 — Difficulty (answering F1.a's constraints)

Three layers, honoring "difficulty is an inherited quality of the war" + the
newbie-curve constraint:

1. **Organic base** — the generation gradient (P1.1: easy pocket, hard depth)
   plus economy pressure: the *enemy's production* is the escalating clock,
   not per-level stat tuning.
2. **Adaptive escalation** — if the player dominates (front line moving fast),
   the enemy AI escalates *through the fiction*: personality shifts toward
   desperate/elite, better unit mixes, counter-offensives — **never silent
   stat inflation**. Struggle, and the pressure relaxes the same honest way.
3. **A global knob** (the F1.a lean): one slider scaling starting pilots,
   enemy production rate, and intel generosity. Feasible-for-newbies lives
   here *plus* in the flight system we already built: the **rate-preset
   ladder** (Cinematic→Race) and **angle mode** are the real onboarding ramp —
   a new player flies angle-mode Cinematic into light garrisons and the same
   war stays playable.

*Guardrail (v1.6, user):* adaptive escalation must never become a counter
punishment for excellence. A player who has genuinely crushed the enemy
should *feel* dominant — the escalation gives an adequate challenge, it never
erases earned superiority. Concretely: escalation draws only on what the
enemy fictionally has left (production, reserves, desperation tactics), it's
**capped by the war state**, and a broken enemy stays broken. Desperate times
call for desperate means — but a defeated army doesn't conjure fresh elite
squadrons from nothing.

### P1.8 — The command room (where the theater lives)

The between-sorties screen — the "battle commanding room" (F2):

- The **theater map**: nodes, ownership, front line, supply edges, weather
  icons, your airbase range rings. *(v1.6, user: nodes render as **hexagons**
  — a beehive tessellation, not floating rectangles. Hexes also give the
  war-sim clean adjacency for free; the map and the graph agree.)*
- **Node inspection**: intel card (freshness-stamped), garrison estimate,
  forecast.
- **Pilot roster** (F1) and **hangar** (P3: frames + loadouts).
- **Sortie select → briefing** (what intel claims) **→ fly → debrief** (what
  actually happened, what you changed) **→ the war tick plays out as animated
  map movement** — the moment the player *feels* the theater being alive.
- Save/exit anywhere; the whole thing is one portable file (F4).

### P1.9 — Node biomes (added v1.5, user concept)

Nodes get an **environment archetype — a biome** (the term used broadly and
proudly): a well-defined env configuration set that gives each node character,
difficulty texture, geometry, and interest points. The node *type* (P1.2) says
what you're attacking; the *biome* says what flying there feels like. Type ×
biome is the variety multiplier — a radar site in fog-drenched green hills
plays nothing like a radar site on a desert ridge.

Starting palette (user's list, extended — each is: flight challenge / combat
texture / mood):

- **Cyberpunk city** — canyon streets, dense verticality; the flight-skill
  biome (terrain-masking heaven, SAM hell above the rooftops); neon-soaked,
  the look pass's home turf.
- **Industrial / factory sprawl** — pipes, gantries, chimneys, tight
  interiors; complex 3D obstacles, indoor-outdoor transitions; sodium haze.
- **Fortified airbase** — open approaches, layered defenses, hangars and
  revetments; the "plan your vector" biome — little cover, high SAM/turret
  density.
- **Desert dunes** — sparse cover, heat glare, sandstorm-prone (weather
  synergy, P1.6), rare oasis interest points; long sightlines favor missiles,
  storms flip it to knife-fight.
- **Green hills with ruins** — rolling terrain-masking, crumbled walls and
  arches to thread; fog-prone; the freestyle biome.
- **Coastal cliffs / port** — the sea seam (P4 naval): vertical cliff faces,
  cranes and containers, ship traffic; wind-prone.
- **Canyon / megastructure** *(imagination flying, as licensed)* — a natural
  slot canyon or the bones of some colossal ruin; the racing biome — one
  dominant line, brutal in wind.

Implementation shape (when we get there): each biome = an env configuration
set — a structure/prop palette (greybox-compatible), a LookConfig mood, a
weather-probability table, and encounter-composition biases — so the theater
generator assigns biomes per node/sector and the sortie builder composes
inside them. Biomes are content, not code: adding one is data.

### P1 open questions (react by ID)

- **P1.q1** — Theater size: is 20–40 nodes the right *campaign length* for the
  "long persistent war" (F4)? Bigger maps = longer wars = more content per
  theater.
- **P1.q2** — Capture mechanics: does winning an assault sortie flip a node
  outright, or does it need a supply-connected friendly neighbor (geography
  discipline — no island-hopping deep strikes that flip nodes behind lines)?
  My lean: the supply-connection rule; deep strikes *degrade*, adjacency
  *captures*.
- **P1.q3** — Should *your* side have off-screen forces retaking/defending
  nodes by odds too (you're the spearhead of a real army), or is all territory
  gain yours alone (purer roguelike agency)? My lean: allied defense yes,
  allied offense no (F3).
- **P1.q4** — Sortie failure/abort: if you retreat or die mid-sortie, does the
  node's garrison recover, stay damaged, or counter-attack next tick?
- **P1.q5** — How many sorties should a typical won campaign take? (My
  strawman: 25–40 sorties ≈ 8–15 hours across sessions — calibrate.)

### P1 steering — ANSWERED (v1.6, 2026-07-17)

Iteration 1 is steered. The proposal above stands as accepted, with:

- **P1.q1 → DECIDED: ~30 nodes default, exposed as a lever (20–40).**
  Theater size must track content variety — 40 nodes with three sortie
  flavors would drag. 30 fits the current complexity; the range becomes a
  new-campaign setting, trivially extensible later (it's a generator input).
- **P1.q2 → DECIDED: capture is earned, not tapped.** Adjacency/supply-
  connection rule adopted: deep strikes *degrade*, only supply-connected
  assaults *capture* — this is a war, not a tag game. User enrichment
  adopted with it: a captured node **forces the enemy to decide whether to
  divert forces to retake it**, which makes **diversion attacks a real
  strategy** — feint at a node the enemy can't ignore, pull its garrison out
  of position, strike the true objective. Ownership through outsmarting.
- **P1.q3 → DECIDED: allied defense always; allied offense only on the
  player's order.** Defense is a must (user) — garrisons hold and fight, and
  it lays the groundwork for command-room unit positioning later. For
  offense, the synthesis of both views: allied forces don't spearhead on
  their own initiative (protagonist clarity + F3 kinetic-first + one
  attacking AI to balance instead of two), but **P5 influence actions can
  order limited allied offensives** — spend resources, allies push a front.
  The war feels alive on both sides, the player remains its author, and the
  mechanism previews commander mode exactly where F3 parked it.
- **P1.q4 → DECIDED: mid-sortie exit, two doors (user design).**
  1. *Exit without save* — quit mid-sortie → the war reverts to the last
     war-room state, sortie achievements lost. Simple, honest, always
     available.
  2. *Abort mission* — the in-fiction retreat, tail between legs: you return
     to the war room alive (wounded run state stands), **and the war ticks
     anyway** — you chose your life over the war's tempo. The price scales
     with **battlefield context** (aborting over a node ringed by capable
     hostiles costs more than slipping out of a quiet sector), tuned to
     sting, never to frustrate. Abort is player agency with a price tag —
     a strategic decision, sometimes the right one.
- **P1.q5 → DECIDED: 25–40 sorties per campaign** as the starting
  calibration target; expected to move as content grows.

---

## Iteration 2 — P4: The Bestiary & the Counter-Matrix (PROPOSED, 2026-07-17 — awaiting steering)

> The enemy ecosystem, designed on paper before code (per 2.4). This iteration
> defines what P3's weapons and frames must answer — so the matrix's columns
> are provisional **answer archetypes**, not final gear; Iteration 3 (P3)
> instantiates them. Concrete, opinionated, meant to be torn apart. Sections
> are **P4.1–P4.10**; react by ID.

### P4.1 — The design grammar

Every enemy is defined along fixed axes — the bestiary's analogue of the P3
weapon axes:

- **Domain** — air / ground-mobile / static.
- **Threat vector** — *which player resource it taxes*: **hull** (direct
  fire), **position** (area denial), **time** (routes and clocks), **systems**
  (jamming), **economy** (lock/ammo bankruptcy), or **the war itself**
  (strategic targets that never shoot at you). A garrison that mixes vectors
  is a *problem*, not a target list — this is where sortie tension comes from.
- **Durability model** — the damage grammar below.
- **Mobility envelope** — can it out-turn, out-run, or out-climb the player?
  Stated relative to the baseline raider; absolute numbers belong to the
  harness (P4.9), not this paper.
- **Sensors** — sight range, line-of-sight discipline, lock behavior.
- **Counter-web role** — punishes X / answered by Y / hard-countered by Z.
  The locked ≥1-answer/≥1-hard-counter rule is held *per unit*, checked in
  the matrix (P4.3).
- **Terrain sensitivity** — how cover economics prices it (the P2 v1.6
  requirement, made explicit per unit and totaled in P4.5).
- **Strategic footprint** — garrison-strength cost, which production tag
  builds it (P4.7), what its presence signals in intel.

**The damage grammar** — the mechanical heart of the web. Four durability
models × three damage styles:

- **Light** — a plain hull pool. Dies to anything; numbers and speed are the
  only defense.
- **Shielded** — a regenerating shield gates the hull; hits below a **break
  threshold** are absorbed and healed back — chip fire *cannot* win, burst
  cracks it open. (The v1 "ignore chip damage" note, given a mechanism.)
- **Armored** — flat damage reduction per hit: spray is wasted, heavy single
  hits work. Armored units are slow — the tradeoff stays honest.
- **Distributed** — the pool is many bodies; per-target overkill is wasted,
  area economy wins.

Weapon styles land as **chip** (sustained small hits), **burst** (rare heavy
hits), **area** (cheap hits across many bodies). Every P3 weapon will sit
somewhere in this grammar — and the grammar is *visually explicit* (readable
presentation): shields shimmer, armor is plated, swarms are visibly many.
Reading a garrison IS reading its answer.

**Readability doctrine (proposed as a locked rule, Into-the-Breach lineage):**
every unit telegraphs before it hurts you. SAM locks growl before launch, a
falx pass commits to a visible line, bomber routes are drawn in intel, gnat
swarms are audible. Enemy fire stays *reaction-dodgeable* (bounded muzzle
speeds, honest aim jitter — the knob `enemy_aim_jitter_deg` already embodies
this); elites get smarter, never twitchier (see P4.q2). Dodging is informed;
deaths are lessons.

### P4.2 — The roster

Ten types — five air, five ground/static — absorbing both shipped enemies as
canon. Block format: role / durability / mobility / threat vector / behavior
& telegraph / web role / terrain / strategic footprint.

**Air:**

**Gnat — swarm drone.**
- *Durability:* distributed (packs of 6–12; each body is tissue).
- *Mobility:* slow per body (~0.6× raider) but omnidirectional pressure —
  the pack surrounds.
- *Threat:* economy + hull — collision sting (contact detonation) plus the
  sheer arithmetic of bodies; one missile per gnat is bankruptcy.
- *Behavior:* boils toward the player as a loose cloud, audible hum rising
  with proximity; individual gnats are trivially dodged, the *cloud* is the
  problem.
- *Web role:* punishes single-target loadouts and hover; answered by area
  weapons and kiting; hard counter to lock-based play.
- *Terrain:* tight spaces are gnat heaven (they envelop your cover); open
  ground lets you kite and rake the cloud.
- *Strategic:* cheap filler — light-industry production, the mass in
  low-value garrisons.

**Raider — line fighter** *(today's `EnemyDrone`, canonized: orbit slot,
led jittered bolts, LOS discipline — the `enemy_*` CombatConfig group).*
- *Durability:* light.
- *Mobility:* the baseline (1×) — deliberately human-beatable.
- *Threat:* hull — sustained led fire from an orbiting slot.
- *Behavior:* wander → engage on sight → orbit at preferred range. Orbit
  spacing is deliberately *peelable*: the sortie-18 finding (isolate one
  bandit, kill, next) is intended play, preserved by design — sticky lock +
  raider spacing make peeling the skill.
- *Web role:* the universal donor — answered by guns and missiles alike;
  punishes stationary play (orbits find your blind side).
- *Terrain:* breaking LOS resets its engagement — cover works.
- *Strategic:* the standing army; airframe production, everywhere.

**Falx — pursuit interceptor.**
- *Durability:* light (fragile is the price of speed).
- *Mobility:* fast (~1.8× raider), wide turns — it out-runs everything and
  out-turns nothing.
- *Threat:* hull + position — boom-and-zoom: long committed gun passes, then
  a climbing recovery arc.
- *Behavior:* telegraphs each pass (a drawn approach line / rising shriek);
  vulnerable and predictable during recovery. **The anti-camper**: falx wings
  launch to flush static players — the deliberate counter to indirect-fire
  camping that Firehawk doctrine demands (P3 v1.6).
- *Web role:* punishes slow/heavy frames and manual tracking (too fast for
  chip guns); answered by bait-and-overshoot (make it pass, kill the
  recovery), flak curtains, off-boresight FCS (P3's turret pods); hard
  counter to lob loadouts.
- *Terrain:* open sky is its home; obstacles are *your* answer — dragging a
  pass through geometry forces the overshoot.
- *Strategic:* airfield-based (P1.2: enemy airbases generate patrols);
  presence in intel = "bring agility, not tonnage."

**Aegis — shielded bomber (the ticking bomb).**
- *Durability:* shielded (high break threshold; chip fire regenerates away).
- *Mobility:* slow (~0.5× raider), route-bound, does not evade.
- *Threat:* time + the war — it ignores you and flies its strike route
  toward a friendly asset (your pad, an allied garrison, the exit gate's
  sector). Every second alive is a countdown; the v1 "ticking bomb" note,
  operationalized.
- *Behavior:* route drawn in intel/briefing; escort wings (raider/falx) fly
  cover; a screamer escort (below) jams your easy answer.
- *Web role:* punishes chip-only loadouts (hard counter) and forces priority
  calls; answered by burst weapons and missiles — *unless* the escort jams
  the lock: the aegis+screamer pair is the web's first designed combo.
- *Terrain:* indifferent (route-bound) — cover doesn't stop the clock.
- *Strategic:* heavy-industry production; enemy operations can commit them
  as **bomber raids** against your nodes (P4.7) — an intercept sortie the
  war generates.

**Screamer — EW escort.**
- *Durability:* light.
- *Mobility:* ~raider speed; holds standoff orbit at the edge of the fight.
- *Threat:* systems — a jam bubble: missile locks break/refuse inside it,
  FCS solutions degrade (gun director confidence collapses, director arcs
  stutter). The P3 counter-web note ("EW jams FCS — both directors") made
  flesh. HUD fuzz at bubble edge telegraphs it before it bites.
- *Web role:* hard counter to lock/FCS-dependent loadouts; the *designed
  reason* manual gunnery stays a skill fallback, not dead content. Answered
  by a masked approach + one burst kill — it's tissue once reached. Punishes
  players who bought positioning-gear and no trigger skill.
- *Terrain:* your approach cover is the counterplay; it prefers open standoff.
- *Strategic:* EW production tag — rare, high-value; intel showing a
  screamer rewrites your loadout before takeoff (P1.3 → P3 intel-driven
  choice, working as designed).

**Ground / static:**

**Turret — autocannon emplacement** *(shipped: lead-computed, rate-limited
head, respawn — the `turret_*` CombatConfig group).*
- *Durability:* light-armored (modest flat reduction; deliberate answers
  beat idle spray).
- *Threat:* position + hull — a direct-fire denial zone with honest lead
  computation; hover inside its envelope and it *will* out-trade you.
- *Behavior:* tracking head is visible; the rate-limited slew is the
  outplay — sharp geometry changes defeat the track.
- *Web role:* punishes straight lines and open hover; answered by
  terrain-masked approaches, standoff outside its range, and **lob weapons
  arcing over its LOS — the indirect-fire archetype's reason to exist**
  (Firehawk doctrine: the camper's tool gets a legitimate target).
- *Terrain:* wholly LOS-bound — cover negates it; open approaches are its
  kill box.
- *Strategic:* fortification value in the war-sim; garrison stiffener.

**SAM battery.**
- *Durability:* armored (launcher vehicles + radar van; spray bounces).
- *Threat:* position — the area-denial king: lock (audible growl, HUD
  warning swell), then a guided missile with real kinematics. A **dead zone**
  under/inside minimum range rewards getting close and low.
- *Behavior:* lock → launch telegraphed in stages; breaking LOS during
  guidance defeats the shot (terrain-masking is the counterplay, exactly as
  P1.2's SEAD flavor promises). No countermeasure gear at launch — see P4.q3.
- *Web role:* hard counter to high/slow/open flight and heavy frames;
  answered by masked ingress + lob/standoff SEAD, or knife-range dead-zone
  play *reached* via cover. Punishes gun-only loadouts in the open.
- *Terrain:* the most terrain-priced unit in the game — flat biomes make it
  a monster, canyon/city biomes half-blind it (P1.9 desert vs city, priced).
- *Strategic:* covers nodes AND supply edges (P1.2); the SEAD economy's
  anchor; heavy production tag.

**Convoy — supply crawler.**
- *Durability:* armored (trucks) + a light mobile-AA escort bubble.
- *Threat:* the war — it never hunts you; it moves garrison strength along
  supply edges (the war-sim's supply flow, embodied). Its AA escort punishes
  lazy strafing runs, not presence.
- *Web role:* strategic prey — interdiction is a sortie flavor (the P1.2
  siege/starve play made kinetic); answered by standoff/lob/missiles;
  punishes loitering inside the AA bubble.
- *Terrain:* road-bound and exposed — ambush geometry is the player's gift.
- *Strategic:* killing convoys is *edge* warfare: starve a sector without
  assaulting it. Intel freshness decides whether the convoy is even there.

**Commander — command track.**
- *Durability:* armored, escorted (elite raider/falx guard).
- *Threat:* systems + everything — a force multiplier: units in its datalink
  radius gain *coordination* (focus fire, flanking orbits, disciplined
  spacing), *not* stat buffs — see P4.q4. Kill it and the garrison visibly
  dumbs down mid-sortie: the decapitation payoff you can *feel*.
- *Web role:* punishes ignore-it play (everything nearby fights smarter);
  answered by decap strikes — a missile through a lock window or a
  knife-fight through the guard. Hard counter: lob (it repositions under
  escort).
- *Terrain:* hides in structure clutter; open biomes expose it.
- *Strategic:* garrisons command posts (P1.2) — the war-sim's command
  network gets its face; elite production only.

**Sentinel — radar dish.**
- *Durability:* light structure (the dish is fragile; the *node* is not).
- *Threat:* time + detection — while it spins, it calls ambush waves onto
  you and extends sector detection (P1.2/P1.3). Unarmed; its weapon is the
  clock and everything it summons.
- *Web role:* no weapon-level counter needed — its defense is layered
  (turrets/SAM ring + the ambush clock). The answer is *speed*: fast masked
  ingress, kill the dish, survive the outward leg. Loitering is the
  punished play.
- *Terrain:* sited on high ground by generation — the approach is always
  uphill/exposed unless the biome offers a seam.
- *Strategic:* the intel war's kinetic end — every dead sentinel widens
  your fog-of-war advantage (P1.3).

*(Naval rows stay reserved (v1): ship classes slot into this same grammar —
shielded capital ships, distributed boat swarms, armored convoys at sea —
when the P4 naval expansion opens. Nothing above needs regenerating.)*

### P4.3 — The counter-matrix (paper v0)

Columns are the six provisional **answer archetypes** (P3 will instantiate
them as real weapons/gear): **chip gun** (sustained direct fire — today's
blaster), **burst** (charge-shot / heavy single hits), **lob** (indirect
ballistic — mortar archetype), **missile** (lock-based homing — today's
missile), **flak** (area/spray), **terrain** (cover used *as* a weapon —
priced as a real column per P2 v1.6). FCS is not a column: it's a
*multiplier* on gun/missile columns, and the screamer is its dedicated
counter.

Rating = how well that answer handles that enemy: `++` excellent, `+` good,
`0` workable, `−` poor, `−−` hard-countered (building a loadout on this
answer is punished).

| Enemy | Chip gun | Burst | Lob | Missile | Flak | Terrain |
|---|---|---|---|---|---|---|
| **Gnat** | + | −− | − | −− | ++ | − |
| **Raider** | ++ | + | − | + | 0 | + |
| **Falx** | − | 0 | −− | + | ++ | ++ |
| **Aegis** | −− | ++ | − | ++ | −− | 0 |
| **Screamer** | + | ++ | 0 | −− | 0 | + |
| **Turret** | 0 | + | ++ | + | − | ++ |
| **SAM** | − | 0 | ++ | + | − | ++ |
| **Convoy** | − | + | ++ | ++ | 0 | + |
| **Commander** | + | + | − | ++ | − | + |
| **Sentinel** | ++ | + | + | + | 0 | ++ |

**Invariants this table must hold** (and the harness must re-verify
numerically, forever):

1. Every row has ≥1 `++` (every enemy has a great answer) and ≥1 `−`/`−−`
   (every enemy punishes some loadout). *(Sentinel's counter-pressure is the
   ambush clock, not a weapon rating — noted, accepted.)*
2. Every column has ≥1 `++` (no dead content) and ≥1 `−−` (no universal
   answer — the locked rule, now falsifiable).
3. No column dominates another (≥ in every row): if one does, the dominated
   archetype is dead content walking. *(Checked by inspection now, by the
   harness later.)*

Reading the table back out loud, the web's stories check out: missiles rule
until gnats bankrupt them and screamers jam them; guns rule until aegis
shields shrug them; lob rules the static ground game until falx wings flush
the camper; terrain answers almost everything except the clock-driven units
(aegis, sentinel) — cover can't stop a countdown. That last row of stories
is the game.

### P4.4 — Frame-class pressure

The same web priced against P3's frame classes (light interceptor /
all-rounder / heavy gunship) — what a garrison mix does to *frame* choice
before a single weapon is picked:

| Enemy | Light | All-round | Heavy |
|---|---|---|---|
| Gnat | − (one sting hurts) | 0 | ++ (tank + spray) |
| Falx | ++ (out-turn it) | 0 | −− (can't refuse the pass) |
| Aegis | − (no burst tonnage) | 0 | ++ (missile racks) |
| SAM | ++ (mask + sprint) | 0 | −− (slow in the open) |
| Turret/Sentinel | + (speed ingress) | 0 | − |

Swarm+bomber garrisons are heavy days; falx+SAM garrisons are light days;
mixed garrisons make the all-rounder honest — or split the answer across the
loadout instead. **Intel composition → frame choice** becomes a real
decision every briefing (P1.3 feeding P3, as designed), and the all-rounder
column being all zeros is intentional: it's the frame you pick when intel is
stale.

### P4.5 — Terrain pricing (cover economics, totaled)

The P2 v1.6 requirement, aggregated: each unit carries a terrain coefficient
(how much cover shifts the fight, visible in its block above), and the
**sortie composer must price biome × garrison jointly**:

- Enemy doctrine prefers suited ground: falx wings garrison open biomes,
  gnat clouds garrison dense ones — because the *enemy AI* also reads the
  matrix. Mismatches (falx trapped defending a canyon city) happen only when
  the war forces them — retreats, encirclements, production shortfalls — and
  stale-intel surprises aside, a mismatch is an *exploitable weakness intel
  can reveal* (P1.3 value, again).
- Which means terrain is a strategic weapon: **herd the war onto ground the
  enemy fights badly** — cut the desert supply lines so the falx production
  has to defend cities. The player who thinks in biomes fights easier
  sorties. This is P1's map and P4's web shaking hands.

### P4.6 — Escalation & veterancy (P1.7's mechanism, concretely)

Adaptive escalation gets its bestiary form — and its cap:

- **Veterancy tiers** per type (regular → veteran → elite): tighter aim
  jitter, faster reactions, smarter behavior selection — **never** more HP,
  never faster bolts (the readability doctrine outranks difficulty; see
  P4.q2). Elites are *visibly* marked (trim color/energy accents per the
  emissive palette — red family).
- **Escalation = mix shift + veterancy**, drawn only from surviving
  production of the matching tag (P4.7): kill the airframe plants and falx
  tiers *cannot* climb; a broken enemy stays broken — the v1.6 guardrail is
  now enforced by supply arithmetic, not by promise.
- Desperation (war going badly for the enemy) shifts *doctrine*, not stats:
  more combos (aegis+screamer pairs, commander-led packs), bolder bomber
  raids — desperate means, fictionally sourced.

### P4.7 — Strategic integration (garrisons get faces)

Reconciling P1.3's promise ("an actual unit list, not an abstract strength
7") with the v1.7 war-sim reality (garrisons ARE abstract floats — and the
soak harness is fast *because* they are):

- **Strength stays the war-sim currency.** The tick engine keeps trading
  abstract strength — proven, deterministic, fast.
- **Composition is a deterministic projection, not sim state:**
  `manifest(seed, node, strength, type, biome, escalation_tier, production
  surviving) → unit list`. Same tick, same manifest, always — briefings,
  sorties, and intel all derive the same truth without the war-sim carrying
  per-unit books. The portable save (F4) stays exactly as small and exactly
  as provable as it is today.
- **Factory product tags** at generation (airframe / heavy / EW /
  light-industry): production tints its sector's mixes, targeted strikes gain
  surgical meaning ("kill the EW plant → fewer screamers theater-wide"), and
  escalation caps (P4.6) fall out of the same arithmetic.
- **Intel shows the manifest through fog** (P1.3): freshness degrades
  composition detail first (exact counts → families → "strength ~7"),
  which quietly closes the loop — *stale intel literally regresses to the
  abstract number the war-sim actually keeps.*
- **Bomber raids:** the enemy-operations phase can commit aegis groups
  against your nodes; the war generates intercept sorties. (Sortie
  composition rules belong to Iteration 5 / P2 — flagged, not designed.)

### P4.8 — Stat configs & migration (2.4 discharged)

Per the balance methodology: every roster type gets an **`EnemyConfig`**
(`TunableConfig` subclass — one `.tres` per type under `resources/`), fields
mirroring the P4.1 axes: durability block (hull, shield, break threshold,
regen, armor), mobility block (speed, accel, turn), sensor block (sight,
engage, lock), weapon block (damage, rate, muzzle speed, jitter), behavior
block (preferred range, aggression, telegraph timings), strategic block
(strength cost, production tag, points/salvage — salvage *values* priced in
Iteration 4 / P5, not here). All live-tunable: the overlay grows a
**BESTIARY** section with the standard preset bar. Migration path: the
`enemy_*` and `turret_*` groups in CombatConfig become `raider.tres` and
`turret.tres` — CombatConfig keeps player-side weapons only. Wave/sortie
composition knobs move toward the P2 iteration's composer.

### P4.9 — The matchup harness (the matrix, falsifiable)

The 2.4 combat-sim harness, specced against this iteration: headless runs of
**every answer archetype × every roster type** (duels and escorted squads),
N seeds each, printing TTK / damage taken / ammo-energy spent / win rate —
assembled into a **measured matrix** in the same `++`…`−−` bands as P4.3.
The paper matrix is the spec; the measured matrix is the test; divergence
means a bug in the numbers or a lie in the design — either way, caught
numerically before anyone flies it, and re-caught after every balance edit
(the war-soak precedent, applied to combat). Red-flag automation: any row
losing its `++`, any column losing its `−−`, any dominance pair appearing.

### P4.10 — The vertical-slice four

2.5 asks for 4 enemy types forming a minimal web. The pick — chosen so three
durability models, both domains, and three threat vectors are all present on
day one:

> **Raider** (shipped) + **Turret** (shipped) + **Gnat** + **Aegis**

With the slice's 3 weapons (chip gun + missile exist; flak is the natural
third), the mini-web already has no universal answer: guns die on aegis,
missiles bankrupt on gnats, flak feeds on gnats but starves on aegis, the
turret punishes whoever stops moving. **Screamer is the designated fifth** —
it enters the moment FCS gear becomes acquirable (P3), because a counter
without a thing to counter is noise.

### P4 open questions (react by ID)

- **P4.q1** — Roster size: ten types + veterancy tiers as the 1.0 surface —
  right-sized? (My lean: yes — variety comes from tiers × biomes × combos,
  not more base types; every new type is another matrix row to balance
  forever.)
- **P4.q2** — Is *reaction-dodgeability* a locked rule even at elite tier
  (elites position smarter, never shoot faster/straighter than a stated
  ceiling)? My lean: lock it — it's the combat twin of "never silent stat
  inflation."
- **P4.q3** — Enemy homing missiles (SAM, and falx later?): terrain-only
  counterplay at launch, with flares/chaff arriving as P3 equipment — or do
  countermeasures need to exist from day one? My lean: terrain-only first;
  gear later (it makes early SEAD purely a flying problem, which is on
  brand).
- **P4.q4** — Commander buffs: behavior unlocks only (my strong lean —
  visible, readable, and decapitation visibly dumbs the garrison down), or
  also small stat nudges (easier to sim, invisible in play)?
- **P4.q5** — Gnat implementation reality: full physics bodies at 240 Hz ×
  12 will hurt; are gnats allowed a cheaper motion model (kinematic
  boids + collision sting only) — the one bestiary member that isn't a
  "real" combatant under the hood? My lean: yes, and it's not a cheat — the
  cloud is the unit.
- **P4.q6** — Allied forces: same roster palette-swapped (war-sim symmetry,
  cheap, readable) or a distinct allied identity later? My lean:
  palette-swap now, identity when commander mode (F3) arrives.

### P4 steering — ANSWERED (v1.9, 2026-07-17)

Iteration 2 is steered. The proposal above stands as accepted, with:

- **The domain axis gains WATER (user).** Not the full naval expansion —
  that stays post-core as reserved (v1) — but the *grounds* for it, laid
  now: the P4.1 domain axis becomes **air / ground-mobile / static /
  surface (water)**, and the roster gains the two minimum sea seats so the
  taxonomy, the matrix, and the theater generator's coastline (P1.1) all
  have something real to hold the door open with. This also partially
  answers P4.q1 — the roster is now twelve.

  A design insight falls out immediately: **open water is the no-cover
  domain.** The terrain column goes *negative* at sea — sea fights are open
  fights, the exact inversion of the city biome's cover economics, and the
  coastal-cliffs biome (P1.9) is the seam where both economies meet. Water
  doesn't just add units; it adds a place where the counter-web prices
  differently.

  The two sea-annex stat blocks (same format as P4.2):

  **Gunboat — patrol boat.**
  - *Durability:* light-armored surface combatant.
  - *Threat:* position + hull — an AA autocannon bubble over the water;
    patrols sea lanes, screens ports, escorts barges. Tracer arcs telegraph
    the bubble's edge.
  - *Web role:* punishes slow, low, over-water ingress and loitering gun
    runs; answered by missiles and standoff — there is nothing to mask
    behind out there.
  - *Terrain:* its power IS the open water; hug the cliffs and it loses you.
  - *Strategic:* sea-lane control; port production (the reserved P1.2 row's
    first tenant).

  **Barge — sea supply crawler.**
  - *Durability:* armored, near-defenseless; gunboat-escorted.
  - *Threat:* the war — moves garrison strength along sea lanes; later the
    carrier of the naval expansion's amphibious-invasion mechanic (v1 note),
    which is exactly why it exists now.
  - *Web role:* interdiction prey, the convoy's sea twin; answered by
    lob/missile standoff; punishes nothing but wasted time.
  - *Strategic:* killing barges is sea-lane warfare — starve coastal
    sectors without touching their garrisons.

  Their matrix rows (same columns and invariants as P4.3):

  | Enemy | Chip gun | Burst | Lob | Missile | Flak | Terrain |
  |---|---|---|---|---|---|---|
  | **Gunboat** | 0 | + | + | ++ | − | − |
  | **Barge** | − | + | ++ | ++ | 0 | − |

- **P4.q1 → DECIDED: right-sized at the archetype level.** Twelve types
  (ten + the two water seats) + veterancy tiers is the 1.0 surface; variety
  comes from tiers × biomes × combos, and every new base type is a matrix
  row balanced forever.
- **P4.q2 → LOCKED: reaction-dodgeability is a rule at every tier.** Elites
  position smarter; they never shoot faster or straighter than the stated
  ceiling. The combat twin of "never silent stat inflation" (P1.7).
- **P4.q3 → DECIDED: terrain-only counterplay first.** SAM (and any future
  homing threat) is answered by masking and geometry at launch;
  flares/chaff arrive later as P3 equipment. Early SEAD is purely a flying
  problem — on brand.
- **P4.q4 → DECIDED: behavior unlocks only.** Commander buffs are
  coordination, visible in how the garrison fights — and decapitation
  visibly dumbs it down. No invisible stat nudges.
- **P4.q5 → DECIDED: the cloud is the unit.** Gnats run a cheap kinematic
  boid model + collision sting — the one bestiary member that isn't a full
  combatant under the hood, and that's a design statement, not a cheat.
- **P4.q6 → DECIDED: palette-swap now, with a pinned refinement (user).**
  Allied forces mirror the roster for now (war-sim symmetry, readable,
  cheap). But the eventual identity should be *derived from characteristics
  that carry real force-level differences*: each identity fields **its own
  version of the same archetype** — the archetype seats (the matrix rows)
  are the shared grammar, and a faction expresses each seat with its own
  tradeoffs. Same seat, different answer. Pinned for the commander-mode /
  faction era (F3); the archetype-seat structure this iteration built is
  what makes it cheap later.

---

## Iteration 3 — P3: Frames, Hardpoints & the Arsenal (PROPOSED, 2026-07-17 — awaiting steering)

> The answers to the bestiary. Iteration 2 locked the matrix's columns as
> provisional *answer archetypes*; this iteration gives them bodies — real
> frames, real weapons, real equipment — and wires the whole thing into the
> config discipline the flight model already lives by. Concrete, opinionated,
> meant to be torn apart. Sections are **P3.1–P3.10**; react by ID.

### P3.1 — The design grammar (the v1.6 axes, locked)

Every weapon is defined along the axes the charge-shot lesson (P3 v1.6)
demanded:

- **Seat** — which matrix column it instantiates (chip gun / burst / lob /
  missile / flak; *terrain* is flying, not gear). The seat carries the P4.3
  column ratings as the weapon's **spec targets** — the harness holds each
  weapon to its column (P3.7).
- **Trajectory** — direct / ballistic / homing.
- **Fire model** — auto / burst / charge (charge is an axis, not a gimmick —
  the charge-shot doctrine (P3 v1.6) made canon in the Charge cannon, P3.5).
- **Economy** — one of two honest currencies:
  - **Heat** — energy weapons self-recharge but overheat: sustained fire hits
    a lockout. Chip's economy is *time*, never scarcity.
  - **Magazine** — ammo weapons carry finite rounds and **re-arm only at
    landing pads** (P2 v1.6) — the loadout economy lands on landing skill,
    exactly where this game wants every road to lead.
- **Damage style** — chip / burst / area, straight from the P4.1 damage
  grammar; the style is what the durability models price.
- **FCS compatibility** — which director (if any) can run it, and what the
  screamer's jam does to that (P3.6).
- **Hardpoint class** — which slot it needs (P3.2) and what it weighs.
- **Counter-web role** — which enemies it answers, which punish it.

Player fire stays **yellow** across the roster (emissive palette) — weapon
identity comes from form (bolt / slug / arc / trail / burst-cloud), not from
color drift.

### P3.2 — The hardpoint grammar & honest mass

The hardpoint profile (v1 clarification) gets its concrete shape:

- **Slot classes:** **S** (light — pods, small guns), **M** (standard — most
  weapons), **H** (heavy — racks and big tubes), **E** (equipment bay —
  internal: FCS modules, countermeasures, utility; no aerodynamic footprint).
  A bigger slot accepts smaller items (M takes S), never the reverse.
- **Mass budget:** each frame states a total mounted-mass cap *alongside* its
  slots — slots say what *fits*, the budget says what *flies*. Maxing every
  slot on a light frame busts the budget; the loadout screen makes you choose.
- **Honest mass (proposed as a locked rule):** mounted mass is **real
  rigidbody mass** — no stat-sheet abstraction. TWR sags, inertia grows,
  stopping distances stretch, because the physics says so; the flight model is
  the product, and the loadout screen is now a flight decision. The hangar
  shows a **predicted hover-throttle readout** per loadout so the price is
  visible before takeoff (and the P1.6 heat-wave modifier compounds it
  honestly — a heavy loadout in a heat wave is a real commitment).

Layering order (stated once, binding): **FlightConfig (frame base) → loadout
mass (physics) → RunMods (in-sortie drafts) → weather (P1.6)**. No ad-hoc
multipliers outside the stack.

### P3.3 — The frame roster

Four frames at 1.0. Block format: flight profile (relative to the shipped
baseline — absolute numbers belong to the `.tres` and the harness, per P4.1
doctrine) / hardpoints / signature / web role / the feel.

**Kestrel — the all-rounder** *(today's shipped drone, canonized. The kestrel
is the falcon that hunts from a hover — apt for the frame you hold station in.
Renamed from the v1.10 proposal's placeholder per P3.q2; see the inspiration
note at the end of P3.5.)*
- *Flight:* the baseline (1× mass, 1× TWR) — every other frame is stated
  against it. Current `default_flight_config.tres` IS this frame.
- *Hardpoints:* 1×M + 2×S + 1×E; medium budget.
- *Signature:* baseline.
- *Web role:* the all-zeros column of P4.4, on purpose — **the frame you fly
  when intel is stale.** Never the best answer, never punished.
- *Feel:* what the last three months of tuning already feel like.

**Dart — light interceptor.**
- *Flight:* ~0.65× mass, agility priority — highest rates, crispest response,
  Race-preset native; light frame, light legs.
- *Hardpoints:* 2×S + 1×E; tight budget — a Dart carrying tonnage stops being
  a Dart, and the physics enforces it (P3.2).
- *Signature:* small — spotted later, locked slower.
- *Web role:* falx days (out-turn the pass) and SAM days (mask + sprint);
  punished by gnat clouds (one sting is real damage) and aegis (no burst
  tonnage on S slots).
- *Feel:* the dare-chaser (P2 v1.6) — the frame you pick to fly the gap.

**Atlas — heavy gunship.**
- *Flight:* ~1.9× mass, TWR held modest, soft rates, heavy filtering — it
  *plants* in the air.
- *Hardpoints:* 1×H + 2×M + 2×S + 2×E; big budget. The only frame that lifts
  the H-class racks.
- *Signature:* huge — everything sees it coming.
- *Durability:* the one frame with innate armor (flat reduction — the P4.1
  grammar applied to the player's side).
- *Web role:* gnat days (tank the stings, carry the flak) and aegis days
  (missile racks + burst tonnage); hard-punished by falx (can't refuse the
  pass) and SAM in the open. Over water it is the boldest posture in the game
  — no cover, slow, loud (P4 steering's no-cover domain, priced).
- *Feel:* a stable gun platform — and honestly so: FCS solutions converge
  faster on a steady frame because miss-distance jitter shrinks. That's
  physics, not a stat: the heavy frame is the FCS frame *emergently*.

**Shade — stealth recon.**
- *Flight:* ~0.85× mass, smooth-tuned (Cinematic-adjacent), quiet motor
  profile (the SoundBank motor synthesis gets a hush variant — audio is part
  of the fantasy).
- *Hardpoints:* 1×S + 2×E; minimal budget. Nearly unarmed by design.
- *Signature:* the point — enemy sight/lock/detection ranges sharply reduced
  against it; SAM lock stages stretch.
- *Web role:* the intel war's vehicle: overflying a node **refreshes its
  intel** (P1.3's recon flights get their airframe); ++ against everything
  that can be *avoided* (turrets, SAM, sentinels — slip in, kill the dish,
  slip out), hard-punished by anything with a clock (aegis doesn't care that
  you're sneaky) and by clouds that hunt by proximity.
- *Feel:* the held-breath frame — flying *unseen* as its own skill
  expression.

**Frames vs. rate presets (boundary stated):** presets tune *feel within* a
frame; frames change the *airframe*. Orthogonal — each frame carries its own
FlightConfig, and the preset ladder (Cinematic→Race) rides on top of
whichever frame you fly. The overlay tuning loop works per-frame for free.

### P3.4 — Frame pressure, instantiated (P4.4 grown to the full roster)

| Enemy | Dart | Kestrel | Atlas | Shade |
|---|---|---|---|---|
| **Gnat** | − | 0 | ++ | − |
| **Raider** | + | 0 | 0 | 0 |
| **Falx** | ++ | 0 | −− | + |
| **Aegis** | − | 0 | ++ | −− |
| **Screamer** | + | 0 | − | ++ |
| **Turret** | + | 0 | − | ++ |
| **SAM** | ++ | 0 | −− | ++ |
| **Convoy** | 0 | 0 | + | + |
| **Commander** | + | 0 | + | + |
| **Sentinel** | + | 0 | − | ++ |
| **Gunboat** | + | 0 | − | + |
| **Barge** | 0 | 0 | + | + |

Same invariants as the weapon matrix: every frame has great days and punished
days; the Kestrel column staying flat is the design (the stale-intel
frame); no frame dominates another. **Intel composition → frame choice →
loadout** is now a three-step briefing decision, and the whole chain runs on
P1.3's fog.

### P3.5 — The weapon roster (one weapon per seat)

Five weapons at 1.0 — **one instantiation per matrix column.** Variety at 1.0
comes from loadout × equipment × frame combos (the P4.q1 logic applied to
gear); second instantiations per seat are the post-1.0 growth axis, reserved.
Weapons get functional names (the shipped blaster/missile precedent); frames
get proper names. Block format: seat / trajectory / fire model / economy /
damage style / FCS / slot / web role.

**Blaster** *(shipped, canonized)* — seat: **chip gun**.
- Direct · auto · **heat** (sustained fire overheats — chip's price is time,
  proposed as its missing economy) · chip · directable (gun director / lead
  computer) · S.
- *Web role:* the raider/sentinel answer, the universal donor's counterpart;
  dies on aegis shields and armor (P4.3 column, unchanged).

**Charge cannon** — seat: **burst**. *The charge-shot doctrine (P3 v1.6) made
a real weapon; see the inspiration note at the end of this section.*
- Direct · **charge** (tap = light bolt; full hold = a fast, flat,
  shield-cracking slug) · heat (a full slug drains most of the gauge — burst
  economy through depth of draw) · burst · director-compatible **at full
  charge only** (P3.q6) · M.
- *Web role:* the aegis-cracker and armor-beater (SAM vans, convoys,
  commanders, barges); punished by gnats (overkill per body is the
  distributed grammar working) and pressured by falx (charge time is
  exposure time).

**Mortar** — seat: **lob**. *The indirect-fire archetype, deliberate at last.*
- Ballistic · single-shot cycle · **magazine** · burst with a light splash ·
  **manual-only at 1.0** (the skill weapon — a ballistic computer is a
  reserved post-core module, P3.q7) · M.
- *Web role:* arcs over LOS — the turret/SAM/convoy/barge answer, the
  camp-behind-cover tactic *with its price attached*: falx wings flush the
  camper (P4.2), and the shell's flight time is honest.

**Missile** *(shipped, canonized)* — seat: **homing**.
- Homing · lock-gated single fire · magazine (scarce — the bestiary's economy
  vector has teeth) · burst · missile director · M (an H-rack carries more
  tubes, Atlas country).
- *Web role:* aegis/gunboat/commander killer; bankrupted by gnats, jammed by
  screamers — the two designed humiliations stand.

**Flak pod** — seat: **flak**. *The slice's third weapon (P4.10).*
- Direct with **proximity-fused burst** (shells detonate at computed range
  into a fragment cloud) · auto, slow cycle · magazine (generous) · area · S.
- *FCS note:* the fuse ranging is onboard computation — **a screamer degrades
  it to contact-only**, gracefully (the P4.3 `0` vs screamer, mechanized).
  EW pressures every computed solution in the game, uniformly.
- *Web role:* the gnat shredder and the falx curtain (`++` on both, per
  P4.3); useless tonnage against shields and armor.

> **Inspiration note (deep-docs credit, per P3.q2 — 2026-07-17).** The
> charge-shot mechanic at the heart of the Charge cannon — and the whole
> "design *for* emergent tactics with prices and counters" doctrine (P3 v1.6)
> that runs through this design — was sparked by a charge-fire energy weapon
> the user encountered in an existing game. That game's name is deliberately
> **not** carried onto any QuadShot element (no frame, weapon, or system bears
> it): it was the *inspiration*, and it stays credited here, quietly, rather
> than borrowed as a name. The internal design vocabulary in the locked
> history above (where prior versions nicknamed the lesson after it) is left
> as-written per the append-only rule; going forward the doctrine is referred
> to functionally (the *charge-shot* / *indirect-fire* doctrine).

### P3.6 — FCS & the equipment bay

The E-slot roster. FCS members are *acquirable gear competing for slots*
(the v1.2 rule — assets, not modes), and every one of them degrades inside a
screamer bubble:

- **Iron trigger** — the baseline, free, unjammable: your thumb. The manual
  fallback stays a skill path forever (the screamer guarantees it's never
  dead content).
- **Gun director** *(canonizes the shipped `fire_assist_miss_m` /
  `fire_assist_range` prototype)* — auto-fires the blaster on a ballistic
  solution. The dev knobs become this item's stats; knobs stay until the
  equipment system ships.
- **Lead computer** — the director upgrade: wider solution window, faster
  convergence, works at longer range. (The Atlas platform-stability synergy
  is emergent — see P3.3.)
- **Missile director** *(canonizes `missile_auto_switch`)* — the stateful
  switch becomes this module's function: stable full lock auto-launches.
- **Turret pod** — off-boresight FCS: occupies an **S weapon slot** (not E —
  it's a gun), a gimballed micro-chip-gun with a bounded rear/side cone. The
  designed falx answer for frames that can't out-turn the pass. Autonomy
  bounded and jam-vulnerable (P3.q5).
- **Flare/chaff pod** — the P4.q3 countermeasure, **explicitly a later-tier
  acquisition**: early SEAD stays a flying problem; this arrives as the
  war's SAM density escalates.
- **Ammo cassette / aux battery** — magazine depth / heat-pool depth. The
  boring-but-honest picks that fight the interesting ones for slots.
- **Armor plate** — hull + flat reduction, paid in real mass (P3.2 makes the
  price physical).
- **Recon suite** — widens intel-refresh radius and sharpens manifest detail
  (P1.3/P4.7); native to Shade, mountable anywhere — any frame can moonlight
  as a scout, Shade just does it while unseen.

### P3.7 — Matrix reconciliation (columns become gear)

The P4.3 + sea-annex matrix maps 1:1 — chip gun→Blaster, burst→Charge cannon,
lob→Mortar, missile→Missile, flak→Flak pod, terrain→the pilot. The paper
ratings transfer as each weapon's **spec targets**, and the P4.9 harness
gains its second axis: **weapon × enemy** measured runs land in the same
`++`…`−−` bands, plus **frame × enemy** runs against P3.4. Red-flag
automation extends accordingly: a weapon drifting off its column's ratings,
a frame column going flat (except the Kestrel's, which must *stay* flat),
any dominance pair — caught numerically, before anyone flies it, forever.

### P3.8 — The loadout loop & acquisition

The briefing-room chain, end to end: **intel manifest (P4.7, through P1.3's
fog) → frame pick (P3.4 pressure) → loadout fill (slots + budget, P3.2) →
sortie → pads repair & re-arm magazines (P2) → debrief → salvage.**

- **Campaign start:** the hangar holds a Kestrel, the Blaster, and the
  Missile — today's shipped kit, canonized as the starting spread. Everything
  else is **acquired in-campaign** (v1's intel-driven acquisition: what the
  war shows you shapes what you buy — screamers in intel sell lead computers).
- **Prices, salvage values, and acquisition mechanics belong to Iteration 4
  (P5)** — flagged, not designed here. Dares (P2 v1.6) can drop gear
  directly; that hook stands.
- **Cross-campaign meta unlocks** (P5's third axis) also deferred — this
  iteration only fixes *what exists* to be priced.

### P3.9 — Stat configs & migration (2.4 discharged, player side)

- **`FrameConfig`** (`TunableConfig`, one `.tres` per frame): hardpoint block
  (slot list, mass budget), signature block (visual/sensor/audio
  multipliers), durability block (hull, armor). **Each frame also carries its
  own `FlightConfig` `.tres`** — frames ARE flight configs (P3 v1), so the
  entire overlay FLIGHT section, preset bar, and tuning loop work per-frame
  with zero new machinery.
- **`WeaponConfig`** (one `.tres` per weapon): trajectory/fire/economy/damage
  /FCS blocks mirroring P3.1. Migration: CombatConfig's blaster and missile
  fields split out into `blaster.tres` / `missile.tres`; CombatConfig slims
  toward player-side plumbing (with `enemy_*`/`turret_*` already leaving for
  the bestiary per P4.8, it may dissolve entirely — fine).
- **`EquipmentConfig`** (one `.tres` per module): the P3.6 roster's stats.
- **Loadout state** is a small serializable dict (slot → item id) living in
  campaign state — portable-save-friendly by construction (F4).
- **Overlay:** a **HANGAR section** (frame/loadout picking, hover-throttle
  preview) + the P4.8 BESTIARY precedent extended with an **ARSENAL section**
  (live-tuning WeaponConfigs, standard preset bar). The balance workflow
  stays the flight-tuning workflow.

### P3.10 — The vertical-slice cut (2.5, updated)

- **2 frames: Kestrel + Atlas.** Against the slice bestiary (raider, turret,
  gnat, aegis — P4.10), the heavy/all-round choice is the one that matters:
  gnat+aegis days are Atlas days, and the Kestrel covers stale intel. Dart
  and Shade follow when falx and the intel war arrive to justify them.
- **3 weapons: Blaster + Missile + Flak pod** — confirmed from P4.10; the
  mini-web holds (guns die on aegis, missiles bankrupt on gnats, flak
  starves on aegis).
- **First acquirable: the gun director** (it's already prototyped as knobs) —
  and per P4.10, **the screamer enters alongside it**: the counter arrives
  with the thing it counters.
- Growth order after the slice: Charge cannon → falx+Dart (burst and the
  interceptor war), Mortar → SAM/convoy (the ground game), Shade+recon suite
  → sentinel/intel war, sea annex last.

### P3 open questions (react by ID)

- **P3.q1** — Frame roster: four at 1.0, with Shade included — or is Shade's
  signature model (new sensor tech) post-core, leaving three? My lean: keep
  Shade at 1.0 — it's the intel pillar's airframe, and P1.3 is load-bearing.
- **P3.q2** — Naming: proper names for frames, functional names for weapons
  (as proposed)? And is the **Firehawk homage** the right name for the
  all-rounder — the story lives in the doctrine, should it live on the
  airframe?
- **P3.q3** — Honest mass as a locked rule: mounted mass = real rigidbody
  mass/inertia, hangar shows predicted hover throttle. Any appetite for
  softening it (a % feel-dampener), or lock it pure? My lean: pure.
- **P3.q4** — Heat economy: per-weapon heat gauges (readable, independent) vs
  one shared power pool per frame (deeper loadout tradeoff, muddier HUD)? My
  lean: per-weapon at 1.0; shared-power as a possible Atlas-only quirk later.
- **P3.q5** — Turret pod autonomy: how bounded before it stops trivializing
  the falx bait-game? (Proposed: narrow rear/side cone, chip damage only,
  jam-vulnerable, and it eats an S weapon slot.) Does it need a harsher
  price?
- **P3.q6** — Lance × gun director: director releases only at full charge on
  a solution (tap stays manual) — or is charge-fire manual-only forever, as
  the skill identity of the burst seat? My lean: director-at-full-charge;
  the screamer keeps it honest.
- **P3.q7** — Mortar: manual-only at 1.0 (skill weapon identity), ballistic
  computer as a reserved post-core module — or ship the computer at 1.0 as
  the lob seat's FCS member? My lean: manual at 1.0; the lob seat's price is
  aim-by-feel.

### P3 steering — ANSWERED (v1.11, 2026-07-17)

Iteration 3 is steered. The proposal above stands as accepted, with the
naming folded through the live body (P3.1–P3.10) and the rest confirmed:

- **P3.q1 → DECIDED: keep Shade at 1.0.** Four frames ship; the stealth-recon
  airframe is the intel pillar's vehicle and P1.3 is load-bearing, so it earns
  its 1.0 seat rather than waiting post-core.
- **P3.q2 → DECIDED: proper names for frames, functional names for weapons —
  and the inspiration name is retired from every game element.** Two
  consequences, applied throughout P3:
  1. The all-rounder frame is **Kestrel** (the falcon that hunts from a hover
     — apt for a frame you hold station in), replacing the v1.10 placeholder.
  2. The burst weapon, proposed as a proper name, becomes the functional
     **Charge cannon** (parallel to Blaster / Mortar / Missile / Flak pod).
  **Hard rule (user):** the external game that inspired the charge-shot /
  indirect-fire doctrine is **never used as the name of any QuadShot frame,
  weapon, or system.** It is credited once, quietly, as an *inspiration note*
  deep in the docs (end of P3.5) — the source is honored, not borrowed. The
  locked historical sections that nicknamed the design lesson after it are
  left as-written (append-only); going-forward text names the doctrine
  functionally.
- **P3.q3 → DECIDED: honest mass is pure.** Mounted mass = real rigidbody
  mass and inertia, no feel-dampener, no softening percentage. TWR sag, grown
  inertia, and stretched stopping distances are the physics telling the truth;
  the hangar's predicted hover-throttle readout makes the price legible before
  takeoff. The flight model is the product — the loadout screen is a flight
  decision.
- **P3.q4 → DECIDED: per-weapon heat gauges at 1.0.** Independent, readable
  gauges — "more than enough" (user). The shared-power-pool idea stays parked
  as a possible later frame quirk, not 1.0 surface.
- **P3.q5 → DECIDED (delegated to me): the turret pod is insurance, not
  autopilot.** The proposed bounds are locked — narrow rear/side cone, chip
  damage only, jam-vulnerable (a screamer kills it), and it eats an **S weapon
  slot** (real opportunity cost against a gun). My added price to protect the
  bait-and-overshoot skill (P4.2): the pod's fire rate is **low enough that it
  *chips* a passing falx, rarely kills it outright** — so the clean kill still
  wants the deliberate bait, and the pod is the safety net that punishes the
  falx for the pass rather than the button that deletes it. If the harness
  (P4.9) ever shows turret-pod loadouts trivializing falx days, the fire rate
  is the first knob down.
- **P3.q6 → DECIDED: director-at-full-charge.** The gun director releases the
  Charge cannon only at full charge on a valid solution; the tap stays manual.
  The user's read is exactly the intent: **it automates the trigger so the
  pilot's attention returns to flight** — the FCS thesis (positioning is the
  skill), now on the burst seat too. The screamer keeps it honest (jam the
  director, fall back to manual charge-timing).
- **P3.q7 → DECIDED: Mortar is manual-only at 1.0; the ballistic computer is
  acquired, not given.** The lob seat's price is aim-by-feel. This crystallizes
  a **doctrine the user stated outright and is worth locking:** *anything that
  can enrich the gameplay model — like buying equipment to fly more
  efficiently — should be **earned in-campaign**, not handed out. The **dev
  room** is the exception: it gets everything unlocked, always* (it's the
  testbed, per CLAUDE.md). Acquisition-as-enrichment now guides the whole P5
  economy iteration: gear the player *wants* is a purchase/salvage/dare reward,
  never a default.

**Doctrine adopted this iteration (for the record):** *enrichment is acquired,
not given* (P3.q7) — the campaign hands you a baseline (Kestrel + Blaster +
Missile) and makes everything that makes you *better* a thing you earn; the dev
room alone is fully stocked. Prices, salvage values, and acquisition mechanics
are Iteration 4 (P5), which this doctrine now anchors.

---

## Iteration 4 — P5: The Reward Economy & Influence (PROPOSED, 2026-07-17 — awaiting steering)

> The price tags. Iterations 1–3 defined a theater, a bestiary, and an arsenal;
> none of it costs anything yet. P5 makes the war an *economy* — what you earn
> for fighting, what you spend it on, how lives work (F1), and how you bend the
> war with resources (F3's light influence layer). The anchor is the doctrine
> locked in v1.11: **enrichment is acquired, not given** — the campaign hands
> you a baseline and makes everything better a thing you earn. Sections
> **P5.1–P5.11**; react by ID. Per 2.4, this paper fixes the economic *grammar*
> — currencies, bands, rules — **not** absolute numbers: every price lives in a
> config and gets bench-tuned in the harness, exactly like a flight gain.

### P5.1 — The economic grammar (two loops and a life)

Three resources, deliberately mapped onto the pillars so each layer of play
funds its own agency:

- **Salvage** — the *tactical* currency. Dropped by the things that shoot at you
  (P4 combatants). Spent on the arsenal (P3): gear acquisition, repair, re-arm.
  The kinetic loop pays for kinetic power.
- **Influence** — the *strategic* currency. Earned by *strategic* achievement —
  capturing nodes, breaking the command network, killing the "war itself"
  targets (P4.1's threat vector: convoys, barges, production — the units that
  never fire at you). Spent on influence actions that bend the war tick (P5.3).
  The map loop pays for map power.
- **Pilots** — the *lives* economy (F1). Not spent by choice; consumed by death,
  granted rarely as a reward. Running out ends *your* road, not the war (P1.5).

The structural payoff (2.4 rigor applied to money): **the two spendable loops
are self-funding and can't cross-subsidize by grind.** You cannot farm gnats
into an allied blitz, or capture your way to free missiles — killing a *raider*
pays salvage, killing a *convoy* pays influence, and the wall between them is
what stops a single dominant farming strategy from buying the whole war.
Kinetic-first (F3) falls out naturally: salvage is the fat everyday loop;
influence is scarce and deliberate.

*The three reward axes (P5 pillar), reconciled with what's built:*
- **In-sortie** — transient boosts inside a single sortie (pad-side buffs / field
  pickups): the M4 RunMods layer, **narrowed to within-sortie scope** and
  evaporating at debrief. The run is gone; the campaign is the new persistence.
- **Campaign** — the persistent spine: salvage & influence, owned gear, pilots,
  the war state itself. The M4 between-wave *draft* graduates here — the
  **debrief** is the curated-choice moment (what the field yielded, what the
  depot now offers), but the goods are **persistent**, not run-scoped.
  Campaign > run.
- **Cross-campaign** — meta (P5.8): deliberately thin and mostly non-power, to
  protect each war's from-baseline integrity (F4).

### P5.2 — Salvage: the tactical economy (P4.8's deferral, discharged)

Every `EnemyConfig` gets two economy fields (the P4.8 strategic block, now
defined): `score_points` (the M4 combo/score currency — already live) and
`salvage_value` (the new campaign currency). They are **not** the same number
and **not** HP-scaled — you're paid for the *tactical value* of the kill, not
its hit-point sponge. The bands, relative (absolutes → config + harness):

| Tier | Types | Salvage | Why |
|---|---|---|---|
| Filler | Gnat (per body) | trivial | distributed grammar — area economy, never a farm |
| Line | Raider | small | the standing army; the baseline earner |
| Specialist | Falx · Screamer · Aegis · Turret · Sentinel | medium | units that *tax a specific resource* — killing the answer to your weakness pays |
| Heavy / static | SAM · Gunboat | large | expensive to build, dangerous to approach |
| Strategic | Convoy · Barge · Commander · production | *pays influence, not salvage* | the "war itself" vector — its reward is strategic (P5.3) |

Nuances that keep the loop honest:
- **Distributed = cheap on purpose.** A gnat cloud's total salvage is
  deliberately low: clouds cost you ammo and time, they don't reward you with
  riches (P4.2 "cheap filler," economically enforced). Area-clearing is
  *survival*, not income.
- **Strategic targets pay the *other* currency.** Convoys, barges, commanders,
  and production drop little salvage — their reward is **influence** and a
  changed war (P5.3, P5.7). The P5.1 wall, made concrete per-unit.
- **Veterancy pays** (P4.6): elites carry a salvage multiplier per tier — they
  cost the enemy more production, so they're worth more dead. Honestly sourced,
  like everything about escalation.
- **Style pays** (the in-sortie→campaign bridge): the M4 **combo multiplier
  scales salvage**, not just score — the clean, chained sortie literally funds
  the next loadout. The flight-model-is-the-product thesis given an *economic*
  reward, not only a dopamine one. *(Lean: adopt; knobbed, so it can be
  flattened if it snowballs.)*

Salvage is **credited at debrief**, banked to the campaign — which is what gives
the abort/death rules (P5.6) their teeth: uncollected salvage is *leverage the
battlefield holds over you.*

### P5.3 — Influence: the strategic economy (F3's light layer, P1.q3's mechanism)

Influence is scarce, strategic, and spent on **war-tick modifiers** — inputs the
deterministic war-sim consumes exactly like a sortie result, so every influence
action is seed-reproducible and serializable (the war/ module doctrine; F4 stays
trivially portable). The launch menu, deliberately tight (F3 kinetic-first — a
*preview* of commander mode, not commander mode):

| Action | Cost | Effect | Lineage |
|---|---|---|---|
| **Recon sweep** | cheap | refresh a sector's manifests through the fog (P1.3) — *pay instead of fly* the Shade | the common spend |
| **Fortify** | modest | harden a friendly node against the next enemy counter-offensive (war-tick defense buff) | holds what you captured (P1.q2) |
| **Allied strike** | mid | a one-shot allied strike degrades a target garrison's strength before you fly it — or kills a convoy you can't reach | interdiction from the map |
| **Allied offensive** | expensive | order allies to push a designated front for a tick or two — **the only way allied offense happens** (P1.q3) | the flagship; commander-mode preview (F3) |

Where influence comes from: **breaking the command structure** (P1.5 command
posts), **strategic-target kills** (the P5.2 "war itself" tier), and
**operation/objective completion**. The strategic game funds strategic agency;
the two loops stay walled (P5.1). *Fortify* + *Allied offensive* are also the
exact seam where F3's deferred commander layer later docks as an "acquirable
capability" — the mechanism is previewed here, priced small, and the door stays
open.

### P5.4 — The pilot economy (F1, priced)

- **Starting pilots:** `starting_pilots` (EconomyConfig), scaled by the P1.7
  global knob — part of the newbie ramp lives here. Strawman: 3–5.
- **Death** consumes one pilot; you redeploy fresh from Home Airbase. The
  *frame* is not lost (a dead pilot doesn't burn the airframe — you have a
  hangar), but the sortie's **uncollected salvage is forfeit** and redeploying a
  wrecked frame costs repair (P5.6). Losing a life shouldn't *also* strip your
  gear — that double-punish cheapens the loadout game.
- **Tempo cost (F1.b):** `death_war_ticks` — death can advance the war while you
  re-deploy. **Default 0** (F1.b's call); a knob, revisited once slice numbers
  exist.
- **Earning pilots (1-ups):** rare and meaningful, primarily **strategic** — a
  milestone of the command-network arc (P1.5) and the occasional top-tier
  **dare** reward (P2). *Purchasable* only at **steep influence** as a last
  resort (a desperate pilot trades war-agency for survival — an honest tension),
  and **never for salvage** (lives must not become a grind — the F1 anti-goal).
  *(Open: pilots-buyable-at-all — P5.q6.)*
- **Zero pilots** → the F1/P1.5 defeat: the player's road ends, the war keeps
  ticking, the defeat screen is **F4.a spectator mode** — the theater concludes
  from its seed while you watch. Epilogue, not curtain. The economy of lives is
  the one that ends the game.
- **Pilot identity:** at 1.0, pilots are **fungible lives** (the 1-up model).
  Named pilots with veterancy/perks — losing *Kestrel-lead Vega* hurting more
  than losing life #3 — is the richer long-game and is **reserved** post-core
  (P5.q3), not forced into the slice.

### P5.5 — Acquisition: how enrichment is earned

The doctrine (v1.11): everything past the baseline (Kestrel + Blaster + Missile,
P3.8) is earned. The mechanisms:

- **The Depot** (Home Airbase, command room): buy gear for salvage — but the
  catalog is **not** static. Two gates enforce "the war shapes what you buy":
  1. **Discovery gate (intel):** an item becomes *purchasable* only once the war
     has *shown you its reason* — screamers in intel unlock the lead computer's
     catalog entry; overflying an airframe plant reveals the Dart; a cache
     blueprint reveals a module. Intel unlocks the *entry*; salvage buys the
     *item* (P3.8's "screamers in intel sell lead computers," mechanized).
  2. **Salvage gate:** once unlocked, you pay — frames big-ticket, weapons mid,
     equipment small.
- **Production-capture blueprints** (the P1↔P5 handshake): overrunning an enemy
  **production node** (P4.7's factory tags) grants the blueprint for what it
  built — take their airframe plant, learn to field the interceptor. Capturing
  the war's means of production *is* the tech tree, and it makes P1.q2's
  supply-captures pay in gear, not just territory.
- **Direct drops** (P3.8, P2): **dares** drop gear straight into the hangar — a
  pure skill reward, bypassing salvage — and **salvage caches** (node rewards)
  yield free modules or blueprints. The curated-choice UX inherited from the M4
  draft lives here: the debrief offers what the field yielded.
- **The dev room stays fully stocked, always** (v1.11 exception; CLAUDE.md) —
  it's the testbed, not the campaign.

### P5.6 — Attrition: repair, re-arm, abort & death (P1.q4 discharged economically)

Where the flight-model-is-the-product thesis gets economic teeth: **flying well
is literally cheaper.**

- **In-sortie** (pads, P2): pads repair hull and re-arm magazines mid-sortie, as
  designed — the tactical reset, free within the fight.
- **Between sorties** (Home Airbase): full repair + re-arm costs salvage —
  `repair_cost_mult`, `rearm_cost_mult`. A sortie that chews your frame and
  dumps its missiles has a *bill*; efficient flying pays it down. **Tuned to
  friction, never grind** — cheap relative to acquisition, auto-paid when
  affordable. *(Open: real sink vs. free heal — P5.q4.)*
- **Abort mission** (P1.q4's "price scales with battlefield context," now
  priced): you extract alive, keep pilot and gear, **the war ticks anyway** (+
  optional F1.b tempo), and you **forfeit a fraction of the sortie's salvage** —
  `abort_salvage_forfeit`, scaled by battlefield context (aborting over a node
  ringed by capable hostiles leaves more materiel on the field than slipping out
  of a quiet sector). The abort price *is* forfeited salvage + tempo — agency
  with a legible tag.
- **Exit without save** (P1.q4): rewind to the last war-room state, no economy
  change. The honest escape hatch.
- **Death** (P5.4): lose the life + the sortie's uncollected salvage; redeploy in
  a repaired/fresh frame (a repair bill, not a lost airframe).

### P5.7 — The war itself as a reward surface (non-currency rewards)

Not every reward is a number in a wallet. The strategic layer *is* a reward
channel:
- **Escalation relief** (P1.7): killing enemy **production** doesn't just pay
  influence — it caps the escalation clock (P4.6: broken production can't climb
  veterancy or refill mixes). *The war getting easier is a reward you buy with
  kinetic work* — honestly sourced (the guardrail: a broken enemy stays broken,
  never silent re-inflation).
- **Terrain leverage** (P4.5): herding the war onto ground the enemy fights
  badly is a reward with no currency — easier sorties, earned by strategic
  thinking. P1's map and P4's web shaking hands, again.
- **Codex / mastery** (feeds P5.8): every bestiary entry seen, biome flown,
  weapon mastered fills a persistent record — recognition, not power.

*Enemy-economy symmetry (mostly P1, noted for interlock):* the enemy spends
**production** (the war-sim's existing strength currency) to rebuild and
escalate — the asymmetric mirror of your salvage/influence. You never
out-*produce* the enemy; you out-*fly* and out-*maneuver* them. The economies
interlock without symmetry — which is the whole game.

### P5.8 — Cross-campaign meta (scoped, with a fault line flagged)

A real tension to steer: P5's pillar endorsed "permanent unlocks / mastery"
(v1.1), but v1.11's doctrine is **enrichment is acquired *in-campaign*, not
given** — and F4's ownership rests on each war being *earned from baseline*.
Permanent power-unlocks carried across campaigns would quietly erode both.

Proposed resolution (P5.q2 to steer):
- **Default — non-power meta only:** a persistent **codex/mastery** layer
  (bestiary filled, biomes seen, personal-best wars, records) — recognition and
  collection, mechanically inert. Each new war still starts from the Kestrel
  baseline; purity preserved.
- **Reserved — optional "veteran start":** any *mechanical* meta (a wider
  starting catalog, bonus pilots) is an **opt-in toggle**, off by default and
  flagged non-canonical — so purists get the clean roguelike and collectors get
  progression, and the two never contaminate balance or the harness's guarantees.

This keeps the v1.1 endorsement alive (there *is* permanent progression) while
honoring v1.11 (power is earned each war).

### P5.9 — Stat configs & migration (2.4 discharged, economy side)

- **`EconomyConfig`** (`TunableConfig`): the global knobs — `starting_pilots`,
  `starting_salvage`, `starting_influence`, `repair_cost_mult`,
  `rearm_cost_mult`, `abort_salvage_forfeit`, `death_war_ticks` (F1.b),
  `combo_salvage_mult`, the influence-action cost table, per-tier veterancy
  salvage multipliers, and the P1.7 global-difficulty scalar's economy hooks.
  Live-tunable; the overlay grows an **ECONOMY** section with the standard
  preset bar. Re-balancing the whole economy in play is the flight-tuning
  workflow, again.
- **Per-item economy fields** (added to the existing configs): `salvage_value` +
  `score_points` on `EnemyConfig` (P4.8's block, filled in); `price` +
  `unlock_gate` on `WeaponConfig` / `FrameConfig` / `EquipmentConfig`.
- **Campaign economy state** (serializable, part of the portable save — F4):
  salvage & influence balances, pilot count, owned-gear set, unlocked-catalog
  set, per-frame hull/magazine state. It lives in the war-state dict and
  round-trips via `var_to_str` bit-exactly, like everything the war/ modules
  already carry. The economy adds fields to the save, never a second save.

### P5.10 — The economy harness (P4.9 / war_soak extended)

2.4's "validated by the sim," applied to money. The matchup harness (P4.9)
already fights loadouts; the **war_soak** already runs 200 theaters for
invariants. Extend the soak with an **autopilot economy**: a headless buyer
plays salvage/influence/pilots across hundreds of seeded campaigns and asserts
economic health —
- **Completable:** a reasonable player can acquire enough to keep pace with
  escalation and reach the HQ raid — no unwinnable money-starve.
- **No dominant farm:** no single kinetic loop (gnat-farming, raider-camping)
  snowballs the war — the P5.1 wall holds numerically.
- **No dead-ends:** you can always afford to redeploy/repair enough to continue;
  the pilot economy can't soft-lock.
- **Currency separation earns its keep:** if influence never binds (salvage
  alone would do), the harness says so — and P5.q1 collapses to one currency.
  The sim decides, not the paper.

Same trick as `step_response.gd`: catch "the economy trivializes / starves the
war" **numerically, before anyone plays it**, and re-catch it after every price
change.

### P5.11 — The vertical-slice cut (2.5, economy version)

The smallest economy that delivers the feeling, against the P3.10 / P4.10 slice:
- **One currency: salvage.** Influence and its menu wait unless the slice feels
  toothless without one action — in which case add **Allied strike** only (the
  most legible spend).
- **Pilots:** the F1 lives loop, `starting_pilots` set, death → redeploy →
  spectator on zero.
- **The Depot, intel-gated:** the slice's one acquisition — the **gun director**
  (P4.10's first acquirable), unlocked when the **screamer** shows in intel (the
  counter arrives with the thing it counters — P4.10, now with a price).
- **Attrition:** the repair/re-arm salvage sink (modest), the abort forfeit.
- **Cross-campaign meta:** codex only.
- **No production-capture blueprints, no allied offensive, no veteran-start** at
  slice — all reserved until the core loop proves out.

Growth order after the slice: influence + Allied strike → the full influence menu
(fortify, recon, allied offensive) → production-capture blueprints →
cross-campaign codex → the reserved power-meta toggle, last and optional.

### P5 open questions (react by ID)

- **P5.q1 — One currency or two?** Salvage + influence (separate
  tactical/strategic loops, walled against cross-subsidy) vs. salvage only
  (simpler, one number). My lean: **two**, but let the harness (P5.10) prove
  influence binds — collapse to one if it doesn't. The slice ships one currency
  regardless (P5.11).
- **P5.q2 — Cross-campaign meta power?** Non-power codex/mastery only (protect
  roguelike purity + F4 ownership) vs. optional reserved "veteran start" vs. full
  permanent power-unlocks (the literal v1.1 endorsement). My lean: **non-power
  default + reserved optional power-meta** (P5.8) — the synthesis that keeps both
  promises.
- **P5.q3 — Pilot identity?** Fungible lives at 1.0 (the 1-up model, clean) vs.
  named pilots with veterancy/perks (richer stakes — "death never loses its
  meaning" argues for it). My lean: **fungible at 1.0, identity reserved** — the
  slice shouldn't carry the emotional-stakes system yet, but it's the natural
  post-core depth.
- **P5.q4 — Repair/re-arm: real sink or free?** Modest salvage sink (attrition
  has teeth; flying well literally pays; loadout durability choices matter) vs.
  free heal at base (zero friction, pure arcade). My lean: **modest sink** —
  it's where the flight-model-is-product thesis earns economic meaning — tuned
  to friction, never grind, auto-paid when affordable.
- **P5.q5 — Acquisition gating: intel-discovery or flat catalog?** Intel-gate +
  salvage (the "war shapes what you buy" thesis, richer) vs. flat salvage catalog
  (simpler, everything for sale once affordable). My lean: **intel-gate** — it's
  load-bearing for the whole meta-loop's texture — accepting the extra
  bookkeeping (which the manifest/intel system P4.7 already carries).
- **P5.q6 — Pilots buyable?** Never (earned only — death stays scarce and
  meaningful) vs. buyable at steep influence as a last-resort desperation trade
  (never for salvage). My lean: **earned primarily, buyable at steep influence**
  — trading war-agency for one more life is an honest, painful choice, and it
  can't be ground out.

### P5 steering — ANSWERED (v1.13, 2026-07-18)

Iteration 4 is steered. The proposal above stands as accepted — every open
question resolved to its lean, plus one enrichment that earns its own doctrine:

- **P5.q1 → DECIDED: two currencies, harness-gated.** Salvage + influence ship as
  separate walled loops; the economy harness (P5.10) must *prove influence binds*
  — if salvage alone would do, it collapses to one. Two by default, falsifiable
  by the sim, never by assertion.
- **P5.q2 → DECIDED: non-power meta by default, power-meta reserved & optional.**
  The persistent layer is codex/mastery (mechanically inert); any cross-campaign
  *power* is an opt-in, off-by-default, non-canonical "veteran start." The v1.1
  endorsement (progression exists) and the v1.11 doctrine (power is earned each
  war) both stay intact.
- **P5.q3 → DECIDED: fungible lives at 1.0; named-pilot veterancy reserved.** The
  1-up model ships; named pilots, perks, and the weight of losing a specific ace
  are the natural post-core depth, not slice surface.
- **P5.q4 → DECIDED: modest currency sink + the flight itself as a *risk sink*
  (user enrichment).** Repair/re-arm stays a modest salvage cost — but the
  *decisive* attrition channel is the flying: a hard sortie already taxes you in
  danger (the frame, the pilot life, the uncollected salvage, all on the table).
  **Doctrine (locked): the flight challenge is a sink in its own right — paid in
  risk, not currency.** This is *why* the salvage sink stays genuinely modest:
  the product (the flight model) carries the attrition weight, the wallet only
  tops it off. Fly efficiently and you pay less on both channels; fly greedy and
  the danger is the price. The economy leans on the thing the game *is*.
- **P5.q5 → DECIDED: intel-gated acquisition.** The Depot catalog opens by what
  the war shows you — intel unlocks the entry, salvage buys the item. The manifest
  /intel system (P4.7) already carries the bookkeeping.
- **P5.q6 → DECIDED: pilots earned primarily.** 1-ups come from strategic
  achievement and top-tier dares; the steep-influence buy stays a last-resort
  desperation trade, **never** salvage. Lives don't grind.

**Also accepted (blanket endorsement — "all your instincts are well formed" —
logged for the record, append-only):**
- **M4 RunMods retired to in-sortie scope** — the run-scoped drafting layer
  becomes within-sortie temporary pickups; the campaign is the new persistence
  (P5.1). The one build-vs-design tension I resolved by fiat, now ratified.
- **Combo multiplier scales salvage** (P5.2) — style pays in currency, not just
  score. The in-sortie→campaign bridge stands.

**Doctrine adopted this iteration:** *the flight challenge is an attrition sink
priced in risk* (P5.q4) — the wallet-side economy is deliberately light because
the flying already extracts the real cost. Iteration 4 is closed; P5 is locked as
the pricing layer over P1/P3/P4. Next is Iteration 5 — P2 (mission composition:
node state → encounter), which consumes all four priced pillars as ingredients.

---

## Iteration 5 — P2: Mission Composition (PROPOSED, 2026-07-18 — awaiting steering)

> The capstone design iteration. P1 built a theater, P4 a bestiary, P3 an
> arsenal, P5 a price list — P2 is the **function that turns a node on the map
> into a sortie you fly**. Everything above is an ingredient; this is the recipe.
> The v1 promise stands: **difficulty falls out of the strategic state — organic
> balancing, not hand-tuned levels.** Sections **P2.1–P2.13**; react by ID. Per
> 2.4/2.5 this is paper: composition *grammar* and the harness that proves it,
> not authored missions.

### P2.1 — The composer (the deterministic spine)

Everything the last four iterations defined is an *ingredient*; P2 is the
**function that cooks them into a flyable sortie**:

> `compose(seed, node, war_state, escalation_tier) → sortie_spec`

- **Deterministic and pure** (F4): same seed + same war state → the same sortie,
  always — which is what lets the harness (P4.9) fight composed sorties headless
  and the portable save replay them honestly.
- **Two evaluations of one function** (P1.3's fog, mechanized): the **briefing**
  runs the composer against the *manifest-through-fog* (P4.7 projection filtered
  by intel freshness) — what you *think* you'll face; the **sortie** runs it
  against *truth*. Fresh intel: the two agree. Stale intel: the truth the
  composer bakes diverges from the briefing — the surprise is *designed*, not
  random.
- **Inputs → outputs:** node *type* (P1.2) picks the **objective & archetype**
  (P2.2); the *manifest* (P4.7) supplies the **garrison** (P2.3); the *biome*
  (P1.9) supplies the **map geometry & approach** (P2.4); *weather* (P1.6), *pad*
  and *escalation* state tune the **difficulty**, organically (P2.11). No
  hand-authored levels — the sortie is a *projection of the war*, exactly as P2
  promised at v1.

### P2.2 — Encounter archetypes (node type → objective)

Each P1.2 node type maps to an **archetype**: a primary objective + a doctrine
for how the garrison fights. The archetype is a *template the composer fills*,
not an authored mission:

| Node (P1.2) | Objective | Archetype feel |
|---|---|---|
| **Factory** | destroy production assets | **Strike** — smash it before escorts converge; the enemy's reinforcement tick is the clock |
| **Radar site** | kill the dish | **SEAD** — the dish calls interceptors *onto you* (triggered CAP); kill it to blind the sector |
| **SAM battery** | kill the launchers | **SEAD** — terrain-mask, break lock, close the area-denial bubble (terrain-only counterplay, P4.q3) |
| **Airbase** | crater the runway + ground assets | **Strike under CAP** — the most defended non-HQ target; patrols already up |
| **Command post** | kill the commander (P4) | **Decapitation** — an elite-guarded VIP; killing it dumbs the sector (P4.q4) |
| **Supply depot** | destroy the stores | **Interdiction** — cut the artery; the sector starves over ticks (P1.4) |
| **Contested airspace** | clear / hold | **Dogfight** — the shipped M3/M4 wave loop's natural home, the one archetype that *is* waves |
| **Theater HQ** | the final raid | **The Raid** — layered everything; unlocked only by breaking the command network (P1.5) |
| *(reserved)* **Port / sea lane** | anti-ship / convoy | naval expansion (P4 sea annex) — the door P1.1's coastline holds open |

The objective is what *captures/degrades* the node (P2.9); the archetype is what
it *feels like to fly*. Type × biome × garrison is the variety multiplier
(P1.9) — a radar site in a fog city plays nothing like one on a desert ridge,
and the composer honors both.

### P2.3 — Garrison placement & triggered reinforcements

The manifest (P4.7) hands the composer a *unit list*; placement turns the list
into a fight:

- **Doctrine-in-terrain** (P4.5): units garrison ground that suits them — falx
  wings hold open approaches, gnat clouds nest in dense cover, SAM/turret rings
  cover the objective. A *mismatch* (falx trapped in a canyon) happens only when
  the war forced it (retreat, encirclement, production shortfall) and is an
  intel-revealable weakness — P1.3's value, again.
- **Layered by role:** the objective sits behind concentric pressure — outer
  patrols/pickets → mid area-denial (SAM/turret/flak) → inner guard. Reading the
  layers *is* reading your ingress (P2.4).
- **Triggered reinforcements, not RNG spawns** (P2.q3 lean): radar detection
  *triggers* interceptor CAP (P1.2), an airbase launches patrols, a command post
  coordinates a counter-push — all **seed-deterministic responses to player
  action** (you were seen, you crossed a line), never dice. Keeps the sortie
  replayable (F4) and the harness honest. The "ambush waves" of P1.2 are *earned
  by detection*, and staying unseen (Shade, terrain-masking) is the counterplay
  — the intel war reaching into the sortie.

### P2.4 — The map: biome geometry & the approach phase

The dev room is a testbed; a sortie is **big and expansive** (P2 v1.6). The map
is generated, not authored:

- **Biome → geometry** (P1.9): the node's biome supplies a structure/prop palette
  (greybox-compatible), a LookConfig mood, a weather table, and encounter biases.
  The composer lays the objective and garrison into that palette. Biomes are
  *content, not code* — adding one is data.
- **The approach phase** (P2 v1.6): every assault has an **ingress → target
  zone** structure. A long, exposed ingress over barren ground toward a defended
  base *builds tension* (low-margin flying, battle ahead); a dense city flips it
  (cover everywhere, the enemy must position for it).
- **Open approach, chosen vector** (P2.q2 lean): ingress is *not* a rail — the
  biome defines natural corridors (a canyon line, a city street grid, a ridge to
  mask behind) and **you choose masking vs. speed vs. angle**. The geometry
  shapes the options; the pilot picks the line. The flight model is the product,
  so the approach is a *flying decision*, not a cutscene.

### P2.5 — Terrain as cover economics (P4.5, in the sortie)

The composer prices **biome × garrison jointly** (P4.5's aggregated requirement,
now the composer's job):

- **Cover is the player's currency.** Dense biomes (city, factory, ruins) hand
  you masking — the flight-skill biomes, where terrain-masking beats SAM and you
  dictate the merge. Open biomes (desert, airbase, open water) strip it — the
  "plan your vector" fights, where standoff and speed replace cover. Open water
  goes *negative* (P4 steering): no cover at all, the boldest posture in the game.
- **The enemy reads the same matrix** (P4.5): garrisons are composed to *exploit*
  their ground, so cover is contested, not gifted — and it makes terrain a
  *strategic weapon*: herd the war onto ground the enemy fights badly and the
  sorties there are easier. P1's map and P4's web shaking hands, inside the
  sortie now.

### P2.6 — Pads (repair/re-arm, priced as a knob)

Forward landing pads (P2 v1.6): touch down → repair hull + re-arm magazines.
Landing skill becomes gameplay — precision touchdowns under fire are peak flight
model (the product advertising itself).

- **The in-sortie side of P5.6's attrition:** pads are the *free tactical reset*
  inside the fight; the *between-sortie* repair bill (P5.6) is what's left. A
  pad-rich node is survivable; a pad-poor node makes every hit and every spent
  magazine *count* — the risk-sink (P5.q4) turned up.
- **A difficulty knob** the strategic layer & biome set (P2 v1.6): pad
  count/quality scales inversely with node difficulty. Hard nodes are pad-poor.
- **Capturable/destructible** (P2 v1.6): a contested pad is an *optional
  sub-objective* the composer can place — "secure the pad first" as a valid
  opening move, or deny the enemy theirs. Landing as a strategic act.

### P2.7 — Dares (skill challenges, risk-priced)

The flight model advertising itself (P2 v1.6): one-time, optional, high-risk
micro-challenges seeded from biome interest points (P1.9) — a stray gate, a
building window, the gap under a collapsed slab.

- **Announced without quest markers** — a glint, a ring of light; the adventurous
  pilot *notices*. Never required, never waypointed.
- **Priced by risk** (the P5.q4 doctrine in miniature): clipping the rebar at
  speed is a real crash — the dare *is* a risk sink, and clearing it cleanly is
  pure flying skill.
- **Rewards hook straight into P5:** a salvage cache, an intel refresh, a direct
  gear drop (P5.5's dares-drop-gear), or — the rare top-tier prize — a **pilot**
  (P5.4/P5.q6's earned 1-up). Pure flying converted into campaign currency,
  exactly the bridge P5.2 built for style.

### P2.8 — Weather in the sortie (P1.6, applied)

The sortie inherits the node's weather state (P1.6's seeded Markov chain) and
applies the **modifier pack**: wind as honest external force (never bending the
flight model), rain/fog compressing sensors and lock range (gun play rises,
missile play weakens), heat sagging sustained throttle (MotorModel-honest),
sandstorm abrasion. The command room's **1-tick forecast** makes *when* to strike
a decision — "hit the SAM in tomorrow's fog, when it's half-blind." Weather is
where P1's clock and P2's fight meet: the composer just reads the state the war
already evolved.

### P2.9 — Objectives, success & the degrade

- **Primary objective per archetype** (P2.2) is the *capture/decapitation gate*:
  complete it and the node flips or degrades per **P1.q2** — supply-connected
  assaults *capture*, deep strikes *degrade*.
- **No wasted sortie** (P2.q4 lean): *everything you destroy dents the node* —
  kills feed the garrison-strength attrition even if you don't complete the
  objective, so a hard-fought partial (or an abort, P5.6) still *weakens* the
  target for next time. The war remembers what you broke.
- **This composes the whole exit chain** (P1.q4 + P5.6): complete → capture +
  full salvage; partial/abort → degrade + reduced salvage + war tick; death →
  the sortie's uncollected salvage lost, the node dented by what you managed.
  Success is a spectrum, and the war-sim eats all of it.

### P2.10 — Defensive sorties (the enemy composes against you)

Composition runs *both ways* (P4.7's bomber raids, promised): the
enemy-operations phase (P1.4) can commit aegis groups or raider packs against
*your* nodes, and the composer generates the **intercept sortie** — the same
function, enemy as attacker, you as defender.

- **Optional, not forced** (P2.q5 lean): the war *offers* you the intercept;
  **decline and it resolves by war-sim odds** (P1.4 — your sorties are the thumb
  on the scale, and *not* flying is a real choice with a real cost). Forced
  scrambles would tax agency and make the war a chore; the strategic price of
  declining does the work instead.
- This is where allied defense (P1.q3) is *felt*: your garrisons hold and fight
  the odds; flying the intercept is you *reinforcing* them with the one thing the
  war-sim can't model — a human pilot.

### P2.11 — Organic difficulty & the harness that proves it

The thesis, finally assembled (P2 v1 + P1.7): **difficulty is not hand-tuned —
it falls out of the composer's inputs.** A sortie's hardness = garrison strength
× biome cover economics × weather × pad availability × escalation tier (P4.6) —
every term a projection of the war state, none a per-level knob.

- **The newbie curve** (P1.7, F1.a) is *generated*: light garrisons in the
  starting pocket, pad-rich, clear-weather, low-tier — a feasible on-ramp — with
  the rate-preset ladder (Cinematic→Race) and angle mode riding on top.
- **The harness closes the loop** (P4.9 + war_soak, extended to *composed
  sorties*): the headless sim fights the composer's actual outputs across
  hundreds of seeds and asserts the **P1.7 difficulty curve** — no unwinnable
  composition (a garrison the slice loadout literally cannot crack), no trivial
  one (a node that folds to any input), a monotone gradient from the pocket to
  the HQ. "This node is impossible / this node is free" gets caught
  **numerically, before anyone flies it** — the step-response trick, now on whole
  missions.

### P2.12 — Configs, migration & the composer's home

- **`SortieComposer`** lives beside the sim in `scripts/war/` (pure, static-func,
  deterministic over the war-state dict — the established war/ doctrine) or a
  sibling `scripts/sortie/`; it consumes `EnemyConfig`/`FrameConfig`/biome data
  and emits a `sortie_spec` the scene layer instantiates. The spec is
  serializable — a sortie can be *saved mid-flight* as seed + spec + progress.
- **The M3 `wave_director` becomes one archetype** (P2.2 contested-airspace
  dogfight), not the default sortie engine — the shipped wave loop keeps a home,
  demoted from "the game" to "one kind of node." Its composition knobs
  (P4.8/P4.10) migrate into the composer's difficulty inputs.
- **`BiomeConfig`** (new, P1.9 made real): structure/prop palette + LookConfig +
  weather table + encounter biases, one `.tres` per biome — content, not code.
  The overlay grows a **SORTIE/BIOME** section for live-tuning composition
  weights, standard preset bar.

### P2.13 — The vertical-slice cut (2.5, the sortie)

The smallest composer that delivers the feeling, against the P3.10/P4.10/P5.11
slices:
- **One biome** — the cyberpunk city (the flight-skill biome, the look pass's
  home turf, dense cover to prove terrain economics).
- **Two archetypes** — a **Strike** (factory) and a **Dogfight** (contested
  airspace, reusing the shipped wave loop) — the minimum to show node type →
  different fight.
- **The slice garrison** (P4.10: raider + turret + gnat + aegis) placed by
  doctrine-in-terrain; triggered CAP off a single radar/airbase.
- **Pads** (the P5.6 attrition made real) + **one dare** (a signature city gap,
  the flight model advertising itself) + **one weather state** (clear vs. the
  city's fog, to prove the modifier pack).
- **Deferred to post-slice:** SEAD/decapitation/raid archetypes, defensive
  intercepts, capturable pads, multi-biome composition, and the full
  difficulty-curve harness assertion (the P5.10 war_soak economy pass lands
  first).

### P2 open questions (react by ID)

- **P2.q1 — Sortie shape: placed garrison or waves?** A defended target you
  strike (placed garrison + objective, the assault archetypes) vs. the shipped
  M3 wave loop as the default. My lean: **placed garrison for assaults; waves
  only for contested-airspace dogfights** — the wave_director becomes one node
  type, not the game (P2.2/P2.12).
- **P2.q2 — Approach: open vector or authored corridor?** Player-chosen ingress
  through biome-defined natural corridors (agency) vs. a designed ingress rail
  (authored tension). My lean: **open, biome-shaped** — masking vs. speed is a
  flying decision; the geometry offers lines, the pilot picks one.
- **P2.q3 — Reinforcements: deterministic triggers or live spawns?** Seed-fixed
  responses to detection/line-crossing vs. dynamic RNG waves. My lean:
  **deterministic triggers only** — replayability (F4) and a honest harness
  demand it, and it makes staying unseen real counterplay.
- **P2.q4 — The degrade: does every kill count?** Everything destroyed dents the
  node even on partial/abort (no wasted sortie) vs. objective-binary (all or
  nothing). My lean: **kills always dent**; the objective is the capture gate,
  the degrade is emergent — ties P1.q2 + P5.6 into one honest spectrum.
- **P2.q5 — Defensive sorties: optional or forced?** The war offers an intercept
  you can decline (resolves by odds — the thumb on the scale) vs. a forced
  scramble (respond or lose the node). My lean: **optional** — declining is a
  priced strategic choice; forced scrambles tax agency and make the war a chore.
- **P2.q6 — Sortie length target?** A calibration strawman against the 25–40
  sorties / 8–15 hr campaign (P1.q5): **~4–8 min** typical, dogfights shorter,
  the HQ raid longer. My lean: that band — but this is a dial to set with hands
  on sticks, not on paper.

### P2 steering — ANSWERED (v1.15, 2026-07-18)

Iteration 5 is steered — all six P2.q resolved to their leans, with two
enrichments the user articulated worth locking:

- **P2.q1 → DECIDED: placed garrison for assaults; waves for dogfights only.**
  Assault nodes are a defended *target* you strike (placed, layered garrison +
  objective); the shipped M3 wave loop is *one archetype* — contested airspace —
  not the default sortie engine (P2.2/P2.12).
- **P2.q2 → DECIDED: open, biome-shaped ingress.** No approach rail; the biome
  offers natural corridors and the pilot chooses masking vs. speed vs. angle. The
  approach is a flying decision.
- **P2.q3 → DECIDED: deterministic triggers only.** Reinforcements are seed-fixed
  responses to detection/line-crossing, never RNG spawns — replayability (F4) and
  an honest harness demand it, and it makes staying unseen real counterplay.
- **P2.q4 → DECIDED: every kill dents the node** — "an important complexity to
  include" (user). No wasted sortie: the objective is the P1.q2 capture gate, the
  degrade is emergent, and a hard partial or an abort (P5.6) still weakens the
  target. Success is an honest spectrum the war-sim eats whole.
- **P2.q5 → DECIDED: intercepts are optional — and the *responsibility* is the
  point (user).** The player is a **pilot, not a commander** (F3): being *forced*
  to scramble to defend would be a commander's call imposed on you; the game
  keeps that big-picture decision in the player's hands as **felt
  responsibility.** Decline an intercept and a node may fall by the odds (P1.4) —
  that weight, owned, is the immersion. **Doctrine (locked):** *the player is
  never forced to defend; strategic defense is a responsibility the player
  carries, not a scramble the game imposes.* It previews commander mode exactly
  where F3 parked it — when command authority is later acquired, big-picture
  defense gets its tooling; until then the responsibility rests on the one
  decisive pilot, and is meant to be felt.
- **P2.q6 → DECIDED: ~4–8 min band, calibrated hands-on.** The strawman stands
  (dogfights shorter, the HQ raid longer), and — user, emphatically — it **is a
  dial set with hands on sticks, not on paper.** Logged as a calibration target
  for the slice, not a locked number.

**The design phase is complete.** Five iterations — P1 (theater), P4 (bestiary),
P3 (arsenal), P5 (economy), P2 (composition) — are proposed and steered; all four
forks (F1–F4) decided; the war-sim skeleton lives (v1.7). Everything composes:
the war generates nodes, the manifest dresses them in the bestiary, the arsenal
answers the matrix, the economy prices it, and the composer projects it into
sorties whose difficulty the harness will prove. **Next is Iteration 6 — the
balance-harness spec + the stated difficulty curve (2.4/P1.7) — after which the
vertical slice starts getting *built*.** Paper's edge, reached.

---

## Iteration 6 — The Balance Harness & the Difficulty Curve (PROPOSED, 2026-07-18 — awaiting steering)

> Not a pillar — the **bridge**. Five iterations built a theater, a bestiary, an
> arsenal, an economy, and a composer; each one ended by handing an IOU to *"the
> harness"* (P4.9, P5.10, P2.11) and deferring the stated difficulty curve
> (P1.7/F1.a). This iteration collects every one of those IOUs into a single
> **layered balance harness** and writes the **difficulty curve** it must
> assert — the last thing that has to exist on paper before the vertical slice
> starts getting *built*. It discharges §2.4 (the balance methodology) and P1.7
> (the stated curve). Concrete, opinionated, meant to be torn apart. Sections
> **H1–H9**; react by ID.

### H1 — The thesis: proven before flown

Iteration 6 invents nothing. It **unifies a trick the project has used since
M0**: the flight model was bench-tuned against `step_response.gd` /
`rate_tune_sweep.gd`, the war-sim was soak-proven against `war_soak.gd`, and the
five shipped checks (`hover`/`combat`/`wave`/`missile`/`run`) guard correctness —
all of it the *real game running headless* (Glossary), printing measurements far
faster than real time. The whole design leaned on the phrase "the harness will
prove it" five iterations running; H1 is where that phrase gets a body.

**Doctrine (locked): no balance number ships unmeasured, and every invariant is
re-checked forever.** Correctness has a test suite (the five checks); *balance*
gets one too. The paper is always the spec, the measurement is always the test,
and divergence is either a bug in the numbers or a lie in the design — caught
numerically, before anyone flies it, and re-caught after every config edit. This
is the flight-tuning workflow (§2.4) promoted from the rate loop to the entire
game.

### H2 — The four layers (the harness is a stack because the game is a stack)

The scattered harness promises are really **one harness with four layers**, each
feeding the one above it — unit results set sortie difficulty, sortie difficulty
sets campaign pace, campaign pace sets the war's shape:

| Layer | Harness | Question it answers | Status |
|---|---|---|---|
| **Unit** | the matchup harness (P4.9/P3.7) | does the counter-web hold? (every weapon×enemy, frame×enemy) | to build |
| **Sortie** | the composed-sortie harness (P2.11) | is *this composed node* winnable-but-not-trivial by its intended loadout? | to build |
| **Economy** | the autopilot-economy soak (P5.10) | can a reasonable buyer keep pace without a dominant farm? | to build (extends war_soak) |
| **Strategic** | `war_soak` (shipped, v1.7) | is the *war's* shape sound — determinism, losability, monotonic skill? | **lives** |

The layering is the point: a red flag at the unit layer (a weapon trivializes
bombers) *propagates upward* as a too-easy sortie, a too-fast campaign, a broken
war. Fixing balance at the lowest layer that shows the flag is the discipline —
and the bottom layer already runs green (v1.7), so the build works **downward
from a proven strategic skeleton into the sortie/unit detail the slice adds.**

### H3 — The measured matrix (P4.3 / P3.7 made falsifiable)

The unit layer's output is the paper matrices (P4.3 weapon×enemy, P3.4/P3.7
frame×enemy) **re-derived from measurement.** For every cell the harness runs N
seeded duels — and, where the web's stories demand it, escorted squads (the
aegis+screamer pair, commander-led packs; P4.3's combos are cells too) — under
the reference pilot (H5), then bands the result back into the same `++`…`−−`
scale by the function in H4. The paper matrix is the **spec targets** each config
is held to (P3.1); the measured matrix is the test; a diverging cell is the
alarm.

The three invariants (P4.3) stop being prose and become **automated
assertions** that fail a harness run:

1. every row keeps ≥1 `++` and ≥1 `−`/`−−` (every enemy has a great answer and
   punishes some loadout);
2. every column keeps ≥1 `++` and ≥1 `−−` (no dead content, no universal answer
   — the locked rule, now falsifiable);
3. no column dominates another (≥ in every row) — the dominated archetype is
   dead content walking.

**Red-flag automation (the regression teeth):** any row losing its `++`, any
column losing its `−−`, any dominance pair appearing → the run goes red and names
the cell. That's the P4.9/P3.7 promise, mechanized: caught before anyone flies
it, re-caught after every balance edit, forever.

### H4 — The measurement grammar (what each layer emits, and the banding function)

Every layer prints the same shape of output as `step_response.gd` does today — a
compact table of measured numbers, human-legible, diffable across runs:

- **Unit:** time-to-kill · damage-taken · economy-spent (rounds/heat/lock-time) ·
  **win-rate** — per cell, mean ± spread across seeds.
- **Sortie:** completion-rate · time-on-target · pad-dependency (win-rate with
  pads vs. without) · abort-rate · degrade-achieved-on-loss (P2.9's "every kill
  dents").
- **Economy:** acquisition-pace (sorties-to-first-director) · farm-ratio (best
  vs. median kinetic loop) · dead-end-rate (campaigns that soft-lock on
  repair/redeploy) · currency-binding (does influence ever gate progress, or
  would salvage alone do — P5.q1's falsifier).
- **Strategic (shipped):** sorties-to-win · spectator-loss-rate · front-line
  monotonicity · determinism/save round-trip.

**The banding function (H.q1 to steer):** win-rate is the primary driver — a cell
is `++`/`+`/`0`/`−`/`−−` by fixed, *stated* win-rate thresholds under the
reference pilot — with TTK and economy-spent as tiebreakers (two `++` win-rates
split by which one costs the pilot less hull and ammo). Fixed thresholds, not
percentiles, because a falsifiable spec needs a stable ruler that doesn't drift
as the roster grows. Sentinel's caveat (P4.3 invariant 1) carries over: its
counter-pressure is the ambush clock, scored as sortie-completion-under-time, not
a weapon band.

### H5 — The reference pilot (the instrument the whole thing hangs on)

**This is the hard problem the strategic soak never had to face.** `war_soak`
works because garrisons are abstract floats — nothing flies. The moment the
harness drops to the sortie and unit layers, *something has to be at the sticks*,
and here the project's founding tenet bites: **flight feel cannot be evaluated by
the agent — the human's hands are the test suite** (CLAUDE.md). A headless
harness has no hands.

The resolution is a **division of labor, stated as doctrine (locked): the harness
measures *balance*; the hands measure *feel*; neither substitutes for the
other.**

- The harness flies a **reference pilot** — a scripted, deterministic autopilot
  proxy (the M0 autopilot / pause-hold machinery and the war_soak `skill` scalar
  are the seed): it dodges on telegraph, masks on cover, holds a firing solution,
  lands on pads — *competently, not perfectly, and identically every seed.* It
  produces **relative** truth: weapon A beats weapon B on bombers, node X is
  harder than node Y. That is exactly what the counter-web and the difficulty
  curve are made of — comparisons.
- The reference pilot is **calibrated by the human**, not trusted blind. Periodic
  hands-on flights (the checkpoint protocol, §11) set where its competence datum
  sits against real skill — the sortie-layer analogue of choosing `skill 0.9` in
  war_soak. A pilot that can't dodge a SAM would report SAMs as impossible; one
  that flies perfectly reports everything as trivial. **The human's hands
  calibrate the ruler; the ruler then measures a thousand things the hands can't
  fly.** That is the honest scope of what the harness can and cannot prove — and
  writing it down now is what keeps H6's difficulty numbers from being fiction.

*(H.q3 is where the reference pilot's exact competence model gets steered — this
section commits to the division of labor, not the pilot's internals.)*

### H6 — The difficulty curve, stated (P1.7 / F1.a made numerical at last)

The deliverable §2.4 named and P1.7 deferred: **the curve the strategic layer
must produce.** The crux — and the thing that makes "organic balancing, not
hand-tuned levels" (P2/2.2) a real engineering claim instead of a hope:

**The Sortie Difficulty Index (SDI) is measured, not authored.** The composer
(P2.1) never sets difficulty; it sets *inputs* — garrison strength, biome cover,
weather, pads, escalation tier (P2.11). The harness flies the reference pilot
against the composed output and *measures* the resulting difficulty (chiefly
reference-pilot win-rate, shaded by hull-cost and pad-dependency). **SDI is a
readout of the fight, not a knob on it.** Difficulty is therefore a *verified
emergent property* — and the curve is the **assertion that emergent difficulty
lands in the right band at each point of the war**:

| Point in the war | Reference-pilot win band | Feel (the constraint it encodes) |
|---|---|---|
| **Starting pocket** (P1.1 easy gradient) | high (strawman **70–85%**) | the newbie floor (F1.a): feasible on **angle-mode Cinematic**, pad-rich, clear weather, tier-0 garrisons |
| **Mid theater** | middle (**~45–65%**) | the war has teeth; loadout and frame choice (P3.4) start to matter |
| **Deep territory / escalated** | low-but-real (**~30–50%**) | mask-or-die flying; the arsenal must be earned to keep pace (P5) |
| **HQ raid** (P1.5) | hard-but-possible (strawman **25–40%**) | layered everything; the campaign's peak, unlocked by breaking the command net |

The curve's four stated properties, each an assertion the harness checks:

1. **The floor holds** — no pocket node drops the *newbie datum* below feasible.
   The rate-preset ladder and angle mode (P1.7) ride on top as the real on-ramp;
   the harness proves the strategic layer *hands the newbie winnable ground*.
2. **The ceiling is real** — no node, even fully escalated, is unwinnable by the
   *skilled datum* with the *right earned loadout* (P2.11's "no unwinnable
   composition"), and none is trivial (P2.11's "no node folds to any input").
3. **The gradient rises** — SDI is monotone non-decreasing along pocket→HQ
   progression, as an *envelope* (local variety is welcome; the trend and the
   ceiling are the assertions).
4. **Escalation stays under its cap** — adaptive escalation (P4.6) may raise SDI,
   but only within what surviving production affords, and **never above the
   skilled-datum ceiling.** The P1.7 guardrail ("never punish excellence; a
   broken enemy stays broken") becomes numerical: escalation shifts the curve up,
   a hard ceiling clamps it, and a broken enemy's cap *falls* — the crushed war
   gets measurably easier, on purpose.

The **campaign-length target** rides on the same instrument: **25–40 sorties to
win at the skilled datum** (P1.q5). This is where H7's honesty lives.

### H7 — Calibration & the recalibration debt (owning v1.7's brutal number)

The design phase already produced one damning measurement and logged it plainly:
at v1.7, **skill 0.9 wins ~10% of the time at ~127 sorties** — against a 25–40
target, the war is *brutal*, and the win band far below H6's floor. Iteration 6
does not paper over that; it **names it as the debt the harness exists to
retire.**

The debt is deferred *honestly* (v1.7's own call): the 127-sortie war ran on
**abstract garrisons and a stopgap draft economy** — the exact systems P4/P5/P2
replace with real bestiary, real prices, and a real composer. Recalibrating
against the old skeleton would tune the wrong thing. The loop that closes it:
**build the slice → measure with the harness → tune *configs*, never physics or
code (§2.4) → re-measure.** Every difficulty lever is a `.tres` field
(EnemyConfig strength, EconomyConfig `starting_pilots`, the P1.7 global scalar,
composer weights) — live-tunable in the overlay, bench-verified in the harness,
baked only when the human says the feel is right (§14). **The harness makes the
war *re-tunable* from data; the hands say when it's right.** The 127→25–40 gap is
the first headline the slice's harness will chase.

### H8 — The harness's home, configs & the regression guarantee

- **Where it lives:** unit and sortie layers sit in `scripts/tests/` beside the
  five checks and the benches (the established home); the economy pass extends
  `war_soak.gd`; the composed-sortie runner reuses the P2.12 `SortieComposer`
  headless. All of it is the *real game* headless — no shadow simulation to drift
  from the shipped one (the war_soak precedent).
- **The knobs it turns are all data:** every balance lever is a `TunableConfig`
  field (EnemyConfig, WeaponConfig, FrameConfig, EquipmentConfig, EconomyConfig,
  BiomeConfig, composer weights). The harness reads them, the overlay writes them
  live, the human bakes them — the same triangle the flight model has lived in
  for three months, now spanning the whole game.
- **The regression guarantee (the green board):** the harness is *balance CI*.
  A run is **green** when every H3 invariant holds, every H6 curve property
  holds, and the H4 economy assertions (completable / no-dominant-farm /
  no-dead-ends / currency-binds) pass. Any red names the offending cell, node, or
  price. This is the balance twin of the correctness checks: run it after every
  config change, treat red as a build break.

### H9 — The slice's harness cut (2.5): measurable from day one

The slice (P4.10/P3.10/P5.11/P2.13: Kestrel+Atlas · Blaster+Missile+Flak pod ·
raider+turret+gnat+aegis · cyberpunk-city Strike+Dogfight · salvage-only) does
**not** need the whole harness — it needs the *smallest slice of the harness that
makes the slice build measurable from its first commit*:

- **Unit layer (day one):** the mini-matrix — 3 weapons × 4 enemies + 2 frames ×
  4 enemies — with the H3 invariants asserted on that sub-web. It's small enough
  to eyeball and large enough to catch the designed stories (guns die on aegis,
  missiles bankrupt on gnats, flak starves on aegis, the turret punishes anyone
  who stops). The reference pilot ships at a **single competence datum** here;
  the newbie/skilled split (H6) waits for the full curve.
- **Sortie layer (day one, minimal):** a composed-sortie runner over the two
  slice archetypes asserting **floor + ceiling only** — the city Strike is
  feasible, the hardest slice composition is non-trivial. Full-curve monotonicity
  is meaningless across ~5 nodes; it lands when the theater carries real composed
  nodes (H.q5).
- **Economy layer:** the P5.11 salvage-only economy is thin enough that the
  existing war_soak invariants plus a single "can the buyer afford the gun
  director by the time the screamer shows" check suffice; the full autopilot
  buyer (P5.10) waits for the two-currency menu.
- **Strategic layer:** already green (v1.7) — the slice inherits it.

Everything above the cut — the full 12-enemy matrix, the escorted-squad combos
beyond aegis+screamer, the full difficulty-curve assertion, the two-currency
autopilot — is **deferred to grow with the roster**, each new element arriving
*with its harness row*, never before it (the P4.10 "a counter without a thing to
counter is noise," applied to measurement). **That is the bridge:** the slice is
buildable the moment this cut exists, and it is *measurable* the same day.

### H open questions (react by ID)

- **H.q1 — the banding function.** Win-rate as the primary `++`…`−−` driver under
  the reference pilot, TTK/economy as tiebreakers, **fixed stated thresholds**
  (not percentiles)? My lean: fixed thresholds — a falsifiable spec needs a ruler
  that doesn't drift as the roster grows; percentiles would let power creep hide.
- **H.q2 — SDI: scalar, vector, or both?** A single composite index (clean
  monotonicity assertion) vs. the raw axis vector (garrison/cover/weather/pads/
  escalation — diagnosable) vs. both. My lean: **both** — the vector for *why a
  node is hard* (diagnosis, tuning), the scalar for the *curve rises* assertion
  (the one-number test).
- **H.q3 — the reference pilot's competence model.** A hand-scripted proxy
  (deterministic, cheap, the war_soak-skill analogue) vs. replaying recorded
  human blackbox runs (real skill, but brittle to map changes) vs. a bounded
  learned pilot (expensive, risks over-fitting to exploits). My lean: **scripted
  proxy at 1.0, human-calibrated (H5)** — it's the fast regression instrument;
  blackbox-replay is a reserved richer datum once the slice has real maps to
  record on.
- **H.q4 — the win-rate bands (H6's numbers).** Are 70–85% (pocket) → 25–40% (HQ)
  the right feasibility/challenge targets, or tune the spread? My lean: adopt as
  the strawman and **calibrate hands-on** — like the sortie-length dial (P2.q6),
  these are set with hands on sticks, not on paper; the table states the *shape*,
  the flying sets the *values*.
- **H.q5 — how much curve does the slice assert?** Floor+ceiling only (my H9
  cut — monotonicity is meaningless at ~5 nodes) vs. attempt a mini-gradient
  across the slice's handful of nodes. My lean: **floor+ceiling at slice**, full
  monotone-envelope assertion when a real theater's worth of composed nodes
  exists to draw a curve through.
- **H.q6 — does the harness gate the build, or advise it?** Balance-CI red = a
  hard build break (rigorous, but early slice churn may fight it) vs. an advisory
  board the human reads and overrides (flexible, but red can rot). My lean:
  **advisory through slice bring-up, hardening to a gate once the mini-web
  stabilizes** — you can't fail a test suite for a web that's still being born,
  but the day the four-enemy web is "right," red means stop.

### H steering — ANSWERED (v1.17, 2026-07-18)

Iteration 6 is steered — all six H.q resolved to their leans, closing the bridge
iteration and, with it, the paper phase entire:

- **H.q1 → DECIDED: fixed stated thresholds.** Win-rate is the primary `++`…`−−`
  driver under the reference pilot, TTK/economy as tiebreakers, banded by fixed
  thresholds — a falsifiable spec needs a ruler that doesn't drift as the roster
  grows, and percentiles would let power creep hide.
- **H.q2 → DECIDED: both scalar and vector.** The harness emits the raw axis
  vector (garrison/cover/weather/pads/escalation) for *why a node is hard* —
  diagnosis and tuning — and the composite SDI scalar for the *curve rises*
  monotonicity assertion. Diagnose with the vector, test with the number.
- **H.q3 → DECIDED: scripted proxy at 1.0, human-calibrated (H5).** The reference
  pilot is a deterministic scripted proxy — the fast regression instrument that
  produces *relative* truth; blackbox-replay stays a reserved richer datum for
  when the slice has real maps to record on. The H5 division of labor stands
  locked: **the harness measures balance, the hands measure feel.**
- **H.q4 → DECIDED: adopt the strawman bands, calibrate hands-on — and the
  calibration is *my* process to initiate and lead.** The H6 win bands (pocket
  70–85% → HQ 25–40%) ship as the shape; the values get set with hands on sticks,
  like the sortie-length dial (P2.q6). **Responsibility recorded (user): when the
  slice is flyable and it is time to calibrate, *I* initiate and lead the
  calibration process** — I don't wait to be asked. It is the sortie/economy-layer
  twin of the flight-tuning checkpoints (§14): I set up the harness runs and the
  hands-on flights, propose the config moves, and drive the loop until the human
  says the feel is right. The datum-setting is a scheduled duty, not an
  if-someone-remembers.
- **H.q5 → DECIDED: floor+ceiling at slice.** The slice asserts only that its
  pocket Strike is feasible and its hardest composition is non-trivial;
  full monotone-envelope assertion waits until a real theater's worth of composed
  nodes exists to draw a curve through. Monotonicity across ~5 nodes is noise.
- **H.q6 → DECIDED: advisory → gate.** Balance CI is an advisory board the human
  reads through slice bring-up (you can't fail a test suite for a web still being
  born), hardening into a hard build-break gate the day the four-enemy mini-web is
  "right." Red rots if it's never enforced; enforced too early it fights a web
  that's still forming — so it earns its teeth on a stated trigger.

**THE PAPER PHASE IS COMPLETE.** Six iterations — five pillars (P1 theater, P4
bestiary, P3 arsenal, P5 economy, P2 composition) proposed and steered, plus
Iteration 6 the balance harness + difficulty curve — all closed; four forks
(F1–F4) decided; the war-sim skeleton lives and runs green (v1.7). The model
composes end to end and, now, *proves itself*: the war generates nodes, the
manifest dresses them in the bestiary, the arsenal answers the matrix, the
economy prices it, the composer projects it into sorties, and the harness
measures whether the whole thing lands on the stated difficulty curve — with the
hands calibrating the ruler. **Next is not more paper. Next is the vertical-slice
build** (P4.10/P3.10/P5.11/P2.13), with the H9 harness cut making it measurable
from its first commit. Paper's edge crossed.

---

## Iteration 7 — The Damage Model: Flying the Wounded Quad (PROPOSED, 2026-07-18 — awaiting steering)

> A gap, surfaced by the completeness review the moment the paper phase was
> declared done — and true to this doc's charter (*"it should BE the journey, not
> a polished snapshot"*), it gets its iteration rather than a quiet patch. Six
> iterations specced *enemy* durability in loving detail (P4.1's four models) and
> left the *player's* damage an **abstract hit-point pool**: hull ticks down, hits
> zero, you die. That is a hit-point model inside a game whose north star is *the
> flight model is the product* — the one system where the USP should bite hardest,
> left as a number. This closes it. It **must** close before build: the slice has
> combat, pads, and a repair bill (P2.6/P5.6) that currently repair *nothing in
> particular*. Concrete, opinionated, meant to be torn apart. Sections **D1–D9**;
> react by ID.

### D1 — The thesis: damage is a flight-model event

**Doctrine (proposed as locked): a hit is a flight-model event, not only a
health-bar event.** The deepest expression of *the flight model is the product*
is **flying a wounded quad** — damage that changes *how the aircraft flies*, felt
through the sticks before it's read off any HUD. A raider's bolts don't just
subtract a number; they can degrade a motor until the rate loop is fighting a
persistent yaw bias you have to trim out or ride. Limping a hit-and-canting quad
through the exit gate is the single most on-brand moment this game can produce,
and nothing above lets it happen. This is the north star's *"serious systems,
readable presentation"* aimed at the airframe itself: serious because it's
physics-honest, readable because you *feel* it first and see it plainly second.

The old hull pool isn't discarded — it's **reframed as structural integrity**
(D2) and joined by subsystem degradation. The abstract number becomes the
*coarsest* layer of a model that has texture underneath.

### D2 — The damage surfaces (what a real quad can lose)

The airframe maps to damageable subsystems, each a **physics-honest**
degradation, not a debuff icon — everything routes through systems that already
exist (MotorModel, the Filtering group, FlightController, SoundBank):

| Surface | Hit effect | Routes through | Feel |
|---|---|---|---|
| **Motor (×4)** | thrust% loss → **asymmetric thrust**; full kill = a corner dead | MotorModel per-rotor output | the crown jewel — the rate loop fights a bias you must trim or ride |
| **Prop** | chipped → vibration + thrust loss on that rotor | the gyro-noise the **Filtering group** already fights | damage makes the LPF/notch *earn its keep* — a designed synergy, not a coincidence |
| **Frame integrity** | the old hull pool; low integrity → softer handling, next hit likelier catastrophic | FlightController stiffness / the health pool | the coarse layer; the "how close to death" read |
| **FPV camera / video** | feed breakup — static, rolling lines, brief blackout | a post/overlay effect on the pilot view | the *diegetic* cost of damage; real FPV video breakup, readable-not-blinding (D4) |
| **Equipment bay / FCS** | a hit degrades the gun/missile director, lock confidence | the P3.6 FCS solution quality | **unifies with the screamer**: EW *and* battle damage both degrade FCS — one mechanism |
| **Battery / power** | available power sags → TWR droop; hard hit risks cutoff | MotorModel headroom / the P3 heat economy | the quiet wound — you notice it in the climb, not the crash |

Hit **location matters** (ties to honest mass & frame geometry, P3.2): where the
bolt lands picks the surface. A frame is a layout of these parts, per-frame
(D8) — the Atlas's innate armor (P3.3) becomes *integrity depth + a chance to
shrug a subsystem hit*, the Dart's fragility becomes *thin everything*.

### D3 — Severity as a tunable ramp (the readable-presentation guardrail)

The model is a **config-driven severity dial**, because *"serious systems,
readable presentation"* and P1.7's newbie-feasibility constraint both live here:

- **Arcade end** — damage is mostly the integrity pool; subsystem effects
  cosmetic (video flicker, sound) but flight stays clean. Today's model, kept
  whole as the floor.
- **Sim end** — full asymmetric subsystem degradation: the wounded-quad fantasy,
  motor-out and all.
- One **`DamageConfig`** scalar family, live-tunable in the overlay (the standard
  workflow), riding the **P1.7 global difficulty knob**. The rate-preset ladder
  (Cinematic→Race) already ramps *control* difficulty; **the damage ramp is its
  combat twin** — a newbie flies angle-mode Cinematic with arcade damage and the
  same war stays playable; a sim pilot turns both up and flies a knife-edge.

This is the mechanism that lets the game be a hardcore sim *and* approachable
without lying about the physics — the severity is honest at every setting, only
the *dose* changes.

### D4 — Readability (telegraph your own wound)

Every degradation is **legible on three channels, felt before read** (the P4
readability doctrine turned inward — *reading your own damage is a skill*):

- **Sticks first** — the quad cants, pulls, sags; the pilot's hands know before
  the eyes. This is the flight model doing the telegraphing, which is the point.
- **Sight** — a compact airframe indicator (four motor pips, integrity, cam), the
  drone visibly damaged, video breakup scaled to camera health.
- **Sound** — the SoundBank motor synthesis reflects the wounded motor (tone
  drop / roughness on the dead corner); low-health audio was already queued
  (v1.5) — this gives it a source.

**Guardrail (locked): damage informs, never blinds.** Video breakup is brief and
recoverable, never a blackout you can't fly out of; the wound is always a
*handicap you fly through*, never a removed control. Peak flight model is a
pilot *overcoming* the wound, so the wound must stay overcome-able.

### D5 — Repair & pads, given a referent (P2.6 / P5.6 discharged)

"Repair" finally has an object:

- **Pads** (P2.6, in-sortie) restore integrity + re-arm and do a **field patch**
  of subsystems (motors/props back toward nominal) — the free tactical reset,
  now physical. Precision-landing a wounded quad onto a pad *under fire* is peak
  flight model advertising itself (P2.6's promise, deepened).
- **Between-sortie** (P5.6): the repair bill prices **subsystem restoration** —
  deep repair (a killed motor, a shattered cam) costs more than topping integrity.
  *Flying well is literally cheaper* (P5.q4) gains a second meaning: take fewer
  hits → pay less **and** fly a healthier quad next sortie. Pad-poor hard nodes
  (P2.6) mean flying wounded *longer* — the risk-sink (P5.q4) made physical.
- **Damage is sortie-scoped; repair is campaign-scoped** (Dq3 lean): you never
  keep a permanently crippled airframe (that double-punishes, cf. P5.4's "don't
  strip gear on death") — the persistence is the *bill*, not a scarred frame.

### D6 — The counter-web interaction (P4 damage styles → player subsystems)

Enemy damage styles (P4.1 chip/burst/area) stop being pool-drain and gain
**differentiated effects on how you now fly** — the threat-vector grammar (P4.1)
reflected onto the player's own airframe:

- **Chip** (raider) — attrition across integrity; the slow bleed.
- **Burst** (an aegis-cracker's inverse — a heavy enemy hit) — can knock out a
  *subsystem outright*: the motor kill, the cam blackout. Burst threats become
  "one hit changes your flight," raising the stakes of a single mistake.
- **Area** (gnat sting, flak) — spread nicks: props and camera, many small.
  The gnat cloud isn't just economy-tax (P4.2) — it *frays your quad*.

So **which enemy hit you** now shapes **how you're flying afterward** — a raider
duel and a gnat swarm leave you differently wounded, and that texture is free
depth the abstract pool threw away.

### D7 — Enemy symmetry (do they fly wounded too?)

Lean: **yes, at the archetype level, for the flyers** — raider/falx take handling
degradation from a solid hit (palette-consistent with the P4.6 escalation model
and the P4.q6 "same archetype seat" grammar), so a half-killed falx flies
*visibly* hurt and a good pilot can read it and finish it. Gnats (the cloud is
the unit, P4.q5) and statics (they don't fly) are exempt. Cheap — the same
`DamageConfig` model, applied symmetrically — and it keeps the sim honest both
ways. **Deferred past the slice** (Dq5): player-side first, the world's-flight
symmetry when the roster's flyers are real.

### D8 — Configs, geometry & the harness

- **`DamageConfig`** (`TunableConfig`): severity scalars per surface, subsystem
  thresholds, repair-cost multipliers, the arcade↔sim dial, the P1.7 hook. Live-
  tunable; overlay grows a **DAMAGE** section with the standard preset bar.
- **Per-frame subsystem layout** lives in `FrameConfig` (P3.9): where the motors,
  cam, and bay sit, so hit-location → surface is geometry, not a die roll — the
  same honest-geometry doctrine as honest mass (P3.2).
- **The harness (H) gains a damage dimension:** the reference pilot (H5) must
  **fly wounded**, and the H4 metrics grow a *degradation state* term — TTK and
  damage-taken now read as "how hurt, how flying," not just hull%. Damaged flight
  is measurable too; the difficulty curve (H6) must account for a wounded pilot's
  reduced capability (a hard node that also *cripples* you is harder than its
  garrison alone says — the harness should catch it).

### D9 — The vertical-slice cut (2.5)

The smallest wounded-quad that delivers the feeling, against the P4.10/P3.10
slice (Kestrel+Atlas · raider+turret+gnat+aegis · cyberpunk city):

- **Ship: integrity pool + one flagship subsystem — motor degradation** on the
  sim tier; arcade tier = today's clean HP model (the ramp, D3, proven with one
  real surface). Motor-out is *the* wounded-quad feel; one surface earns the
  whole thesis.
- **Ship: video breakup** as the readable telegraph (D4) — cheap, high-impact,
  and it sells the diegetic FPV fantasy from day one.
- **Ship: pad field-patch + the between-sortie subsystem bill** (D5) — gives the
  slice's economy its missing referent.
- **Defer:** prop/cam/bay/battery granularity, enemy wounded-flight (D7), full
  per-frame subsystem geometry — grow them in as the roster and biomes do.

The slice thus earns its USP-defining moment — *limp a canting, static-flecked
quad onto a pad under fire, patch it, and finish the strike* — without the full
subsystem matrix. One surface, done honestly, is the wedge.

### D open questions (react by ID)

- **Dq1 — default severity at 1.0: sim-leaning or arcade-leaning?** The game *is*
  the sim depth (north star), argues sim-default; the newbie constraint (P1.7)
  and *readable presentation* argue a generous arcade floor. My lean: **sim-
  leaning default with a generous arcade floor, ramped by the P1.7 knob** — never
  a hard wall, the depth is the draw but the door stays open.
- **Dq2 — motor-out recoverability.** A full motor kill: flyable-but-punishing
  (scaled — a controllable yaw-spin limp, a *story*) vs. effectively lethal
  (brutally realistic)? My lean: **flyable-but-punishing on sim tier, config-able
  toward lethal** — the skilled limp-home is exactly the moment we're building
  for; realism is a dial, not a mandate.
- **Dq3 — damage persistence.** Sortie-scoped degradation + campaign-scoped
  *repair bill* (my lean, D5) vs. a frame that stays mechanically scarred into
  the next sortie until repaired? My lean: **bill, not scar** — persistence is
  economic; a permanently crippled airframe double-punishes (cf. P5.4).
- **Dq4 — video/camera damage ceiling.** How far to push feed breakup before it's
  frustration, not immersion? My lean: **brief, recoverable, telegraph-not-
  blindfold** (D4 guardrail) — the wound you fly through, never the wound that
  removes the picture.
- **Dq5 — enemy wounded-flight timing.** Symmetric now (world honesty) or player-
  side first, symmetry post-slice? My lean: **player-side first** — the slice
  proves the model on the frame the human flies; the world flies wounded when its
  flyers are real (D7).
- **Dq6 — where the pool ends and the model begins at 1.0.** Is *integrity + one
  subsystem (motors)* the right slice surface (my D9 cut), or does the wounded-
  quad feel need a second surface (props, for the Filtering-synergy) on day one?
  My lean: **motors only at slice** — one surface done honestly beats two done
  thin; props follow fast because the Filtering synergy is nearly free.

### D steering — ANSWERED (v1.19, 2026-07-18)

Iteration 7 is steered — all six Dq resolved to their leans, and one of them
grew a doctrine worth more than the question that raised it:

- **Dq1 → DECIDED: sim-leaning default, generous arcade floor, P1.7-ramped.** The
  depth is the draw and the door stays open — the severity dial is never a wall.
- **Dq2 → DECIDED: flyable-but-punishing on the sim tier, config-able toward
  lethal.** A skilled motor-out limp-home is a *story*, and stories are the point;
  brutal realism stays a dial, not a mandate.
- **Dq3 → DECIDED: bill, not scar.** Damage is sortie-scoped, repair
  campaign-scoped — persistence is economic, never a permanently crippled frame
  (no double-punish, cf. P5.4).
- **Dq4 → DECIDED: brief, recoverable, telegraph-not-blindfold — and the
  frustration guardrail it implies is now doctrine (below).**
- **Dq5 → DECIDED: player-side first.** Enemy wounded-flight (D7) is deferred —
  teaching the AI to fight *well while crippled* is real work and premature now;
  the slice proves the model on the frame the human flies.
- **Dq6 → DECIDED: motors only at slice; props follow fast.** One surface done
  honestly is the wedge; the prop/Filtering synergy is nearly free to add next.

**Doctrine (locked) — the anti-frustration guardrail: no fight is hopeless, and
denial never removes the skill path.** The user's steering story, kept as the
design compass (the way the charge-shot lesson became doctrine in P3): in the game
that inspired the charge-shot mechanic, an overpowered EW/"hacker" drone —
*especially arriving in a pair* — produced fights with no counterplay, the pure
over-punishing frustration this game must avoid. It names an anti-pattern with
teeth, and it lands on three things already in the design:

- **The Screamer (P4.2) is the element most at risk of becoming it.** EW/jamming
  is exactly the "hacker drone," and the aegis+screamer pair is P4.3's *first
  designed combo* — so the guardrail is aimed straight at it. The screamer's
  design already answers the anti-pattern *by construction*: it's tissue once
  reached, jam is a bubble you can mask around, and the **manual trigger is the
  guaranteed skill fallback** (P3.6 iron trigger — never dead content precisely so
  denial can't be a dead end). This steering ratifies and sharpens that: **an EW
  or blinding effect must always leave a flyable, winnable path** — the wound you
  fly through (D4), never the wound that removes the game.
- **It extends the locked bestiary rules** (P4: every enemy has ≥1 answer and ≥1
  counter; reaction-dodgeability at every tier, P4.q2) **from single units to
  *combinations and denial*:** no pair or combo may compose a no-counterplay
  wall, and no denial effect (jam, blind, motor-out) may be total.
- **The harness makes it falsifiable, not a promise.** A hopeless pair is exactly
  what the Iteration 6 harness catches: it surfaces as a matrix cell or composed
  sortie the reference pilot *cannot* clear under any intended loadout (H3
  invariants, H6's "no unwinnable composition"). **The anti-frustration guardrail
  is enforced numerically** — the Firehawk-pair experience shows up as a red flag
  before anyone ever flies it. The harness Iteration 6 built is the instrument
  that prevents the frustration this iteration named.

**The last gap is closed.** The damage model was the one real hole a completeness
review surfaced; steered, it makes damage a flight-model event (the north star
reaching the airframe) and ties pads, repair, the counter-web, and the harness
together. **The paper phase is complete — genuinely this time, gap-checked. Next
is the vertical-slice build** (P4.10/P3.10/P5.11/P2.13 + D9's motor-out surface),
measurable from its first commit (H9). And per H.q4, when the slice is flyable the
hands-on difficulty calibration is *mine to initiate and lead.*

---

## Iteration 8 — B: Buildings, Indoors & the Flyable Menu (PROPOSED, 2026-07-23 — user-initiated)

> Origin: user steering after a Tryp FPV session, verbatim — "indoors is such
> a game changer... some have windows, can fly into, the environment get
> darker (hdr?)... small simple frame shapes like walls, desks, chairs...
> varied enough to generate rich interesting floors. some floors can simply
> lack windows and cannot be flying into, maybe floors under construction so
> blocked." And the image that names the menu: "a tree of buildings each
> offer the leaf options in the form of floors." Follow-up, same session:
> "neon lighted floors open fly through darker env hdr and cool neon lights
> shine the way." Sections are **B1–B6**; react by ID.

### B1 — The thesis: a building is a dungeon you fly

Indoors is FPV's dungeon crawl. Every knob the outdoor game tunes inverts
when a wall is two meters from each wingtip: sightlines collapse, speed
becomes risk instead of safety, and the 240 Hz flight model gets a second
form of expression — precision where the open sky rewards velocity. The
cyberpunk-city slice already promises towers (D9); this iteration makes some
of them *enterable*, which is the single cheapest way to multiply what one
city block is worth flying.

Ties, by ID: P2.4 (biome geometry — buildings stop being extruded rectangles
and become stacked volumes), P2.5 (cover economics — an interior is the
densest cover in the game, the terrain coefficient at its extreme), D4
(readability in the dark — the emissive palette was built for exactly this),
P1.6/P2.8 (weather stops at the window, which makes indoors a tactical
weather answer for free).

### B2 — The lighting answer: Godot supports this, and half of it already ships

Verified against the project, not guessed:

- The project runs **Forward+** (`project.godot`), so the full lighting
  toolbox is available — clustered omni lights, shadow-casting sun, SSAO
  (already in LOOK), SDFGI if ever wanted.
- **The "gets darker inside" moment is auto-exposure** — the user's "hdr?"
  guess is exactly right in spirit: it is the camera's eye adapting, not the
  world changing. Godot 4 does this with `CameraAttributesPractical`
  auto-exposure on the Environment/camera. `LookConfig` already owns
  `exposure`, `ambient_energy`, and the glow block; it grows an auto-exposure
  group and `LookController` applies it — **no new architecture**, the look
  pass was accidentally built for this.
- **True interior darkness is mostly free**: a shadow-casting
  DirectionalLight cannot reach inside a floor plate, so with ambient held
  low an interior is genuinely dark the moment you cross the window line.
  The neon-emissive look (bloom threshold 1.0, accents above it) reads
  *better* in the dark, not worse.
- **"Neon lights shine the way" (user's line) is the design key: LIGHT IS
  THE ENTERABILITY TELEGRAPH.** Open floors are lit — emissive strips at the
  window line, interior neon — and sealed floors are dark glass. The palette
  already assigns cyan/blue to *navigation*; interior wayfinding joins that
  family. The skyline becomes its own map: you read what is flyable from
  three blocks away, at speed, with no UI. Readability doctrine applied to
  architecture.
- Per-floor interior lights are sparse OmniLights (flickering fluorescent,
  exit signs, the odd desk lamp) — cheap in Forward+, in-palette.
- **Optional, later, not load-bearing**: SDFGI for real bounce light — it is
  bake-free, so it is the only GI that fits *generated* floors (VoxelGI and
  lightmaps want static scenes); its known weakness is light leaking through
  thin walls, and greybox walls can simply be built thick. Occlusion culling
  (`OccluderInstance3D`) when city-plus-interiors perf asks for it. Neither
  is needed for the first ship.
- Windows ship as **openings**, not glass — no transparency sorting, no
  refraction cost. Glass later as an emissive rim material if the look wants
  it.

### B3 — The interior kit (greybox furniture, generated floors)

- A kit of primitives, all in-doctrine (BoxMesh/CSG + the `neon_structure`
  shader family, zero external assets): wall segments, doorway frames,
  window frames, pillars, desks, chairs, shelving, crates, counters,
  half-walls. Variety comes from combination, not asset count — the P4.q1
  logic applied to furniture.
- **A floor generator: seeded and deterministic**, the same discipline as
  `theater_generator` — rooms, corridors, furniture placement all derived
  from a seed, so the same seed is the same floor forever. F4's
  portable-save doctrine extends to geometry with no extra machinery: a save
  that names a seed names a building.
- Openings sized for the fantasy: doorways ~1.5 m, windows generous. Tryp's
  lesson — tight enough to feel skillful, wide enough to feel possible. The
  drone is a 0.28 m box; the gap between "fits" and "feels good" is the
  whole tuning surface, and it is a config, not a constant.

### B4 — Buildings as floor stacks (enterability as a dial)

- A building is a stack of generated floors. Per-floor enterability states:
  **open** (windowed, lit, flyable), **sealed** (windowless dark glass —
  flown past, never into), **under construction** (blocked: scaffolding,
  bare slab, no entry — reads as texture for the city and honesty about
  budget). The mix per building is a generator dial the composer can
  eventually own (P2.3: garrison placement gets "which floors are open" as a
  defensive choice).
- Combat indoors is **deliberately not decided here** (B.q1). Traversal
  ships first. The counter-web implications are rich — gnats in a corridor
  are a horror film, turrets guard lobbies, the flak pod is suicide at
  point-blank — but the 1v1 void harness cannot price a corridor, and
  pretending it can is the exact conflation BALANCE.md exists to prevent.
  Interiors get priced by the sortie harness (P2.11) when composition
  arrives. Known scope limit, stated on day one.

### B5 — The flyable menu (the tech probe that ships as a feature)

The user's image, kept whole: a small cluster — a *tree* — of buildings,
where each floor is a leaf option. The main menu is a tiny hand-built **menu
tower**: each open floor is one leaf (FLY FREE / START RUN / DEV ROOM /
QUIT...), lit per B2 so the options literally shine the way; fly in through
the window to pick one. Why this is the right FIRST bite of the whole
iteration:

- **It is tiny.** One hand-built scene, no generator, three or four floors.
  Every B2 lighting question (auto-exposure feel, ambient floor, interior
  neon, window-line emissive) gets answered in a controlled room before the
  generator exists.
- **The menu is the tutorial.** Window ingress is the skill indoors runs on,
  and the game teaches it before the first sortie without a single tutorial
  prompt.
- **The fantasy from second zero**: the game about flying starts by flying.
  (An input fallback stays — a menu that needs a working radio to quit is a
  bug, B.q2.)
- **Pinned, not designed**: the briefing room (F2's "battle command room")
  and the hangar (P3.9's HANGAR section) want to be *floors of the same
  tower* one day — menu tower grows into the campaign's home address. That
  gravity is noted and resisted until P2/P5 need it.

### B6 — Sequencing: the wedge, placed

Where this sits relative to the live plan, decided deliberately (v1.32):

1. **Instrument pair first** (raider-pack bench + combat-event blackbox,
   v1.29's sized queue) — measuring what is already played outranks new
   content, and both are in flight.
2. **H.q4's human aim drill** whenever the human's hands are next free — it
   needs them, nothing else does.
3. **B5 menu tower** — the first content bite. Crucially it touches nothing
   the harness measures (no configs, no combat, no bestiary), so it can
   START the moment the instrument pair lands and INTERLEAVE with H.q4
   rather than queue behind it.
4. **B3+B4 kit and one generated specimen building in the dev room**
   (dev-room doctrine: every element gets a specimen the human can fly
   today).
5. **P2-era**: buildings enter sortie composition; interiors get priced by
   the sortie harness; enterability becomes a composer dial.

Balance note, restated so it cannot be lost: interiors will move *delivery*
in ways the 1v1 void cannot see (corridors kill standoff, windows are
chokepoints, crossfire dies at the wall line). That is the v1.25/v1.29
caveat family growing one member, priced at the sortie layer — not a reason
to distrust the current table, and not a number to guess.

### B open questions (react by ID)

- **B.q1** — Combat indoors in the vertical slice, or traversal-only first
  (fights stay outside, interiors are approach/escape/loot routes)?
- **B.q2** — First-ship menu leaf set? (FLY / DEV ROOM / QUIT is the
  minimum; START RUN implies the run flow boots from the tower.) And the
  input fallback: keyboard menu forever, or only until the tower is proven?
- **B.q3** — Does the menu tower become the campaign home (briefing +
  hangar as floors, P3.9/F2), or stay a pure menu and let the campaign build
  its own home later?
- **B.q4** — Indoor air feel: prop-wash/turbulence near walls (a
  WeatherConfig hook, P1.6) — fake it cheaply, sim it, or skip at 1.0?


### B steering — first depths (v1.34, 2026-07-23)

Two extensions from the user, hours after the proposal was written; both
deepen B5/B4 rather than redirect them.

**B5 deepened — the menu tree is FLOWN in depth.** The user's mechanic,
kept whole: the menu is real-time flight; every window carries its item's
text above it; flying THROUGH a window selects, and when you exit the floor
the NEXT menu level stands in front of you — the tree of buildings traversed
by momentum, no cuts, no cursor. The natural inverses come free: re-thread
the window you came from to go back up a level, and a selection only COMMITS
on exiting the far side (a short interior crossing), so a graze at speed is
a scare rather than a mis-pick. Precedent already in the game: the M4 exit
gate — fly-through-to-advance is a shipped, proven verb; the menu makes it
the whole grammar. Constraints owned up front: labels must be large,
emissive and face-on (readable on approach, B2's lighting); tree depth stays
shallow (two, at most three levels — which menus are anyway); and an input
fallback still exists (B.q2 stands).

**B7 (new section seed) — graded windows: difficulty as architecture.** The
user's mode idea: runs/routes through building series where each facade
offers SEVERAL windows, each neon-graded by the difficulty of the floor
behind it — red hard, yellow medium, green easy, blue beginner. What this
actually is, in the doc's own vocabulary: **P2.7's dares wearing B4's
enterability telegraph** — risk-priced skill challenges, self-selected in
real time at speed, no menu anywhere. It is also H6's difficulty curve made
spatial and per-second: the player states their own challenge level with a
flight decision, continuously, which is the most organic difficulty selector
this design has produced. Two consequences fall out for free: the floor
generator (B3) grows a difficulty dial — which P2.11's organic-difficulty
harness needs anyway — and the reward economy prices windows (P5: the red
window pays more), making risk-for-reward a literal doorway.

**B.q5 (new)** — the palette collision, flagged not solved: traffic-light
difficulty grading overlaps the emissive roles (red = threat, green = pads,
yellow = player fire, amber = pylons). Red-hard arguably AGREES with
red-threat (danger is the shared semantic), and green-easy sits near
green-pads' "safe" family — the collision may be harmony. Decide at B5
build time with eyes on it, not before.

### B steering — second ripple (v1.35, 2026-07-23)

Two more from the user, same day; both garnish the B7 grammar rather than
change it.

**B8 seed — meaning chains: routes that SAY something.** The user: "a chain
of words that make a meaningful sentence, say a famous line from a song...
or even more abstractly, any CHAIN of THINGS that have meaning together."
The window grammar (B7) already makes a route a sequence of choices; this
makes some sequences MEAN something — fly the line word by word, and the
route is the sentence. Strongest forms: memory-chain dares (the next word is
only findable if you know the line), collectible routes (the city hides
sentences), and composed chains (your flight WRITES one). One hard flag,
raised now so it never bites later: famous song lines are COPYRIGHTED —
shipping them as content is a licensing problem, so the chains ship as
public-domain lines, original writing, or the player's own text. The idea is
the CHAIN, not the quotation; it survives the flag intact.

**B9 seed — the building as a time/weather portal.** The user: "the time of
day and weather can change from entering a building and exiting it." The
implementation insight that makes this elegant rather than gimmicky: **the
interior masks the sky**, so the whole swap (sun angle, fog, ambient,
weather state) happens while nothing outdoor is visible — a scene transition
with no cut, no fade, no popping, hidden inside the one place the player
cannot see the sky. The machinery is already owned: LookController drives
Environment/Sun per frame from LookConfig (sun pitch/yaw, fog, ambient all
live there), and WeatherConfig (P1.6 stub) is the state that would swap.
Later gravity, pinned not designed: P2.8 puts weather in the sortie — a
building that exits into night is a STEALTH decision (Shade-era), and a
window could telegraph its destination sky by the tint of its glow (the B2
telegraph doctrine, extended from enterability to destination). B.q6: does
the portal ship as menu/dev-room magic first (aesthetic), or wait for
weather to be simulated so the swap changes play?

### B steering — the tower answered (v1.37, 2026-07-23)

The B5 build session opened by putting B.q2/B.q3 and the first-build scope to
the user directly; every answer landed, and one grew a design.

**B.q2 RESOLVED — the leaf set is ALL of them:** START RUN / FLY FREE /
DEV ROOM / AIM DRILL / QUIT, five floors. AIM DRILL gives H.q4's drill a
doorway (it is CLI-only today, and the human is about to need to fly it
repeatedly). FLY FREE is the one leaf with no scene behind it — arming in
main always starts the run — so it needs a small no-waves flag on main;
priced, accepted. QUIT is a floor like any other: flying out is leaving.

**B.q2's fallback RESOLVED — keyboard forever — and the answer grew a
design: THE SIDE VIEW.** The user's mechanic, kept whole: with no controller
detected, the menu shows the buildings *from the side* — center is the
current menu item, one to the left is the root menu, one to the right is the
current item's selected leaf (its sub-menu), maybe two more on both sides;
arrow keys move the selection, and the moment a controller is detected the
view drops into flight mode and the drone flies the same floors. What this
actually is: the menu has **two cameras onto one architecture** — the
fallback is not a second menu bolted on, it is the same tower(s) seen from
outside, so nothing is built twice and nothing can drift apart. And when the
depth tree exists, the side view IS the breadcrumb trail: your path through
the buildings, laid out left-to-right. A menu that needs a working radio to
quit is a bug; this makes the no-radio path a feature instead of an apology.

**B.q3 RESOLVED — pure menu, home-ready.** The doc's own "pinned and
resisted" stance, confirmed: no briefing/hangar floors until P2/P5 ask;
floors are additive by construction so the tower can become the campaign's
home address without a rebuild.

**Scope: single-level first.** One tower, every floor a leaf; the
commit-on-exit / re-thread-to-cancel verb ships (it IS the menu's grammar),
but sub-levels wait until the verb is proven in the human's hands. The depth
tree is build-order step 4, not a casualty.

### B steering — the depth answered (v1.40, 2026-07-24)

Checkpoint 3's verdicts, and the clarifications that reshape step 4.

**Escalation is PER-BUILDING, not per-floor — the v1.39 reading was wrong
and is corrected.** The user: ALL windows on the first building are easy;
the next building — a chosen item's submenu, which is ANOTHER building —
gets somewhat smaller windows, and so on down the tree. Difficulty grades
with menu DEPTH: the deeper you choose, the tighter the flying, which is
exactly right — deep menu items are committed choices made by pilots who
know what they want. The first tower's windows flatten to a uniform easy
baseline accordingly.

**Step 4's mechanic, concretized: the next building is DYNAMICALLY CREATED
in front of the player when a selection commits.** The tree is built as it
is flown — no pre-built city of menus, buildings materialize ahead. This is
squarely within Godot's runtime powers (everything is a mutable scene tree;
`MenuFloorFrame` and `GlowText3D` already build geometry in code), and it
is the reason the parametric-frame bet was made in v1.39. The B3 generator
inherits this shape: a building spawned from parameters at commit time is
the menu-sized rehearsal of generated floors.

**The exit guide is VOLUMETRIC — an arrow floating in the air, flown
through.** The user's design, kept whole: a 3D arrow hovering mid-room on
the entry-exit axis at window height, pointing at the far window — readable
from OUTSIDE before ingress so the pilot sets the attack angle early, and
crossed on the way through. The floor chevrons stay as secondary markings.

**The drama dream, recorded in full and deferred as nice-to-have (the
user's own call).** The real-world referent: sunlit exteriors blind you to
interiors (windows read black from outside); entering, darkness first, then
the pupils open; from inside, windows go blinding white; exiting, the world
overexposes then settles. Godot's honest limits, stated: auto-exposure is
full-frame average-metered (no local/retina model), so the fantasy is
staged, not switched on — a much brighter sun/sky against much darker
interiors and a wide sensitivity range would approximate it. Deferred; the
user notes the night/neon cyberpunk environment (D9/B9) may deliver the
same drama cheaper — dark outside makes lit interiors the bright side for
free.

**The way back is the SIGNAL LEASH, not a gate.** The user's simpler-better
idea: every game environment warns as the pilot strays (SIGNAL WEAK — and
static on the feed, the same glitch overlay, so the warning is diegetic
before it is text) and drops the link past range, returning to the menu
tower. An FPV drone flying out of video range IS the menu binding — no
button, no gate, no UI.

**Approved as-is:** the launches ("works perfect"), the side view ("works
like a charm, just like i wanted").

### B steering — the silhouette and the generator (v1.44, 2026-07-24)

Checkpoint 6 flown and approved (depth "way better and cooler", correct
frame selected, backwards cancels, ceiling chevrons "make it feel like a
room", clipping "100% solved", spacing fine "as long as it's easy — it
shouldn't be a challenge"). The one design thread it opened is the answer
to the shorter-silhouette flag, and it is the doorway to B3.

**The stubby sub-building is solved by FILLING it, not shrinking the gap.**
The user's design: a submenu building with only two options should still be
full-height — five floors, say — with just two OPEN (one per option) and
the rest SEALED or UNDER CONSTRUCTION. The silhouette fills, the skyline
reads as real architecture, and every option is still guaranteed its own
lit window. This is exactly B4's enterability states (open / sealed / under
construction) meeting the menu, and it is the natural FIRST CLIENT of B3's
seeded generator. Depth navigation stays easy (the user's spacing note):
the closed floors are texture, never a harder flight.

**The generator framework, sketched — a PLAN for later, at the user's
request ("just a thought"), not a build:**

- **Signature**: `generate_building(seed, required_leaves, target_floors)
  -> floor_list`. Given a seed, the leaves that MUST be reachable, and a
  height, it emits the SAME floor-spec list `MenuBuilding` already consumes.
  The generator is a pure function producing data the existing runtime
  builder turns into geometry — no new rendering path, the v1.43 bet paying
  out a second time.
- **Enterability as a per-floor state**: `MenuFloorFrame` grows a `state`
  (open / sealed / under_construction). Sealed = dark glass, no window
  opening, no `MenuFloor` zone (flown past, never into — B4). Under
  construction = scaffolding / bare slab, also no entry. Only OPEN floors
  carry a window, a `GlowText3D` label, and a commit zone. The frame is
  already parametric; this is one more parameter and two "skip the opening"
  branches.
- **Placement rule**: the required leaves are assigned to open floors; the
  remaining floors are filled sealed / under-construction by the seed —
  each leaf guaranteed exactly one open floor (the user's constraint,
  encoded).
- **Determinism**: seed-driven, `theater_generator`'s discipline extended
  to geometry — same seed = same building forever. F4's portable-save
  doctrine reaches menu geometry for free (a save naming a seed names a
  building). B7's graded windows and the B3 difficulty dial both hang off
  this same seed.
- **It is ALSO the game-world building generator** (B3/B4 proper): the menu
  is the tiny rehearsal, city blocks are the same function at scale. The
  menu proved the runtime builder; the generator is what fills a skyline.

Scope discipline: the menu ships HAND-AUTHORED floor lists until the
generator earns its place — likely when P2-era city composition needs
enterable buildings for real. The frame tower stays two floors until then;
the silhouette flag is logged, not yet patched, by the user's own call.

---

## Iteration 9 — S: The Symmetric Half (survivability, and the roster-first re-order) (PROPOSED, 2026-07-27 — user-initiated)

> Iteration 6 built an instrument that measures **your output on them**. It was
> never finished: there is no layer for **their output on you**, so durability —
> the entire point of an airframe roster — has never been measurable, and the
> war's exchange rate has never been validated. This iteration completes the
> mirror, and proposes a **milestone re-order**: finish and balance the ROSTER
> before building more of the WAR. Sections **S1–S11**; react by ID. Per 2.4
> this is paper — the model and the benches that prove it, not tuned numbers.

### S1 — The thesis: the instrument is half a model

The user's framing (2026-07-27), which is correct and sharper than the doc has
ever put it: balance is *how hard you hit*, *how well you deliver it*, **and
separately** *how much you can take*. Mapped onto what exists:

| | your output on them | their output on you |
|---|---|---|
| **does it hurt?** | **Layer 1** lethality ✅ | *nothing* ❌ |
| **does it connect?** | **Layer 2** delivery ✅ | *nothing* ❌ |

Layers 1 and 2 are one half of a symmetric model. BALANCE.md admits the hole in
a single line — *"prediction has no survival term (assumption 3: nobody shoots
back)"* — and then the **entire frame axis was built on top of it.** That is why
`Atlas × Aegis` is illegible (v1.72): a frame cell bands *destroyed minus hull
spent*, the Atlas's whole virtue lives in the hull term, and against an enemy
that never fires the hull term is pinned at zero.

**The Kestrel spends 0% hull in all four measured cells** and scores a perfect
1.00 in three of them. Since a frame cell is `Atlas − Kestrel`, the arithmetic
ceiling for the Atlas in those cells is **0.00**. It cannot win; it can only
fail to lose. No amount of good frame design changes that — it is a property of
the instrument, not of the airframe.

### S2 — Layer 3a: incoming lethality (arithmetic, cheap)

The exact mirror of Layer 1, and the existing calculator already has the shape:
`EnemyConfig.damage` / `fire_rate` against `FrameConfig.hull` / `armor` →
**shots-to-kill-YOU**, hits-to-kill, seconds-under-fire-to-kill. Armor is
already live in `Health.take` and already modeled in `Lethality`; the frame side
already carries `hull` and `armor` in `FrameConfig` (Kestrel 100/0, Atlas
190/3). Nothing new needs inventing — the numbers exist and have simply never
been pointed at the player.

Verified the same way Layer 1 was: planted shots into a real player `Health`,
so the calculator and the damage code cannot drift.

### S3 — Layer 3b: player evasion (measured, and it re-keys the frame axis)

`evasion` already exists in Layer 2 — **keyed per target.** The roster has
exactly one target nobody has ever measured: **you.** BALANCE.md says evasion is
deliberately not frame-keyed *because the bench freezes the shooter*; the
player-side twin has no such constraint, and **would** be frame-keyed. That is
precisely the axis that makes an Atlas legible.

Same bench, arrow reversed: a fixed perfect-aim shooter (or a real enemy at a
stated skill) firing at the reference pilot performing a standard task. Output:
hits-taken per second-of-exposure, per **pilot × frame**.

One factor, one owner, one bench that measures it alone — the discipline that
kept Layers 1–2 clean, and the test any new metric must pass here.

### S4 — Why 0% hull happens, and why "run the tests longer" will not fix it

The user's hypothesis: the enemy cannot connect on a moving pilot, so the duels
should run longer to give it a chance. **Half right, and the fix does not
follow** — worth recording because the reasoning generalizes.

The enemy *can* connect: the turret puts **12% of hull into the Atlas** over a
3.6 s engagement. It fails to touch the Kestrel because the Kestrel kills it in
**1.3 s** — exposure ≈ 0. So the mechanism is **time-in-the-threat-envelope,
not marksmanship.**

Which is why a longer cap changes nothing: **a duel ends when the enemy dies,
not when the clock expires.** The v1.72 probe demonstrated this from the other
side — doubling `MAX_SECONDS` 10 → 20 moved the Aegis cell not at all. Raising
the cap on a 1.3 s fight buys zero extra exposure.

What *does* create exposure, in ascending order of honesty:
1. **More enemies at once** (S5) — the one that matches the game.
2. **A task that holds you in the envelope** — "destroy the objective while the
   turret ring fires", i.e. a composed sortie rather than a duel.
3. Tougher enemies / longer TTK — happens naturally as the roster grows.

**The corollary matters for H6:** the unit layer is inherently a step-function
instrument. It will read `++` or `--` almost everywhere and cannot produce the
graded 45–65% middle the difficulty curve asks for. That is consistent with H9
(the graded signal was always specced to live at the *sortie* layer) — but it
means the curve genuinely cannot be calibrated from duels. Duels prove
feel-promises; sorties produce curves.

### S5 — Concurrency: the web is 1v1, the fight is 1vN

The v1.29 blackbox finding, now urgent: every `× Raider` cell is 1v1 while the
shipped wave director spawns growing concurrent groups. v1.33 added one pack
row. **v1.71's composer widened the gap deliberately** — a composed sortie is
1v(layered garrison + timed reserve waves).

Concurrency is not a fourth delivery factor; it is a **bench axis**. The same
cells, run at N. It matters here because *durability is exactly the property
that only appears when you are outnumbered* — S3 and S5 are the same fix
arriving from two directions, and neither is worth much alone.

### S6 — Cost per kill, and the ammo model behind it

"Missiles bankrupt on gnats" is one of the design's founding feel-promises. It
is **currently unfalsifiable**: there are no ammo, magazine or capacity fields
anywhere in `CombatConfig` — weapons are infinite. Nothing can bankrupt.

Cost-per-kill is trivial arithmetic *on top of* Layer 1 (shots-to-kill × cost
per shot) — but it drags a real system in behind it: magazines, re-arm, and
therefore pads (P2.6) and the between-sortie bill (P5.6). That is a scope
decision, not bookkeeping, so it is **S.q3** rather than an assumption.

### S7 — The engagement window: a constraint, NOT a factor

`Atlas × Aegis` is the proof case. A deadline (the bomber's ~8.6 s run) met a
quantized cadence (`missile_cooldown` 3.0 s) and turned a continuous quantity
into a **step function**: 0.6 s of deficit cost a whole missile and the entire
cell.

Multiplying a "time available" term into the prediction would smear that step
into a slope and lie about it. Instead: **tag cells whose outcome is decided by
a clock**, the way unseeded-enemy cells are already tagged as resolution-limited
(`can only read ++ or --`). A reader must never mistake a step for a gradient.

### S8 — Detectability: deferred, with a stated trigger (my call, per the user)

The user left this one to me. **Defer.** Not because it is unmeasurable — P2.3
already makes reinforcements fire on `detected`, and player-side signature is
programmable (range, speed, terrain masking). Defer because **it has exactly one
possible value today**: no frame, no equipment and no enemy varies it, and a
factor with one value measures nothing. This is P4.10's own rule ("a counter
without a thing to counter is noise") applied to measurement.

**Stated trigger for adoption:** the day a frame or a piece of equipment varies
signature — the Shade frame, EW gear, or the user's "invisibility" module — it
enters *with* its bench row, never before.

### S9 — Pricing `strength_cost` empirically: the melee bench

v1.70's manifest made `strength_cost` **load-bearing**: it is the exchange rate
converting kinetic results into war currency, and the composer's whole
conservation invariant is denominated in it. The shipped values — gnat 0.3,
raider 1.0, turret 2.0, aegis 4.0 — are **hand-set and have never been
validated against combat.** The war's arithmetic currently rests on four
guesses.

The user's instinct — *"start with an empty space, throw everything together,
and see an actual war"* — is exactly the instrument for this, and it
independently rediscovered a use case the project had already reserved: the
agent-vs-agent mirror bench was **demoted** during the v1.23 realignment with
one exception noted, *"only future use is empirically pricing `strength_cost`."*
That day has arrived.

**What it is:** side A of N units against side B of M units, in empty space,
kinetic, headless (and watchable per the standing policy). Sweep compositions;
find the ratios at which sides trade evenly; those ratios ARE the relative
strengths. Then compare against the hand-set numbers and reconcile.

**GUARDRAIL, non-negotiable (F2/P4.7):** this is an **instrument, not a game
mode, and not the war.** The war never fights kinetically — unattended battles
resolve by arithmetic, and the sortie is the only deaggregation bubble. The
melee bench exists to *price* the arithmetic, never to *replace* it. If this
bench ever starts being called during a war tick, the whole determinism and
speed argument for F2 has been thrown away. Recorded here so the temptation is
refused on purpose.

### S10 — The re-order: roster and balance BEFORE more war (the user's call)

The user's concern (2026-07-27), which I agree with: we have drifted into the
macro — generation, sorties, nodes, weather, biomes — while the micro is
incomplete and unmeasured. Their sequencing: **a complete roster, and a balance
model that gives that roster basic balance, before more war model.**

The strongest argument for it is one the user did not make, and it is decisive:
**the war's arithmetic is denominated in `strength_cost`** (S9). Building more
war on four unvalidated guesses means every strategic number — garrison values,
the 127-sortie campaign length, the whole H6 curve — is measured against a ruler
nobody has checked. Balance the roster first and the war layer inherits a real
exchange rate instead of a placeholder.

Proposed split of M6:

- **M6a — The Roster & The Symmetric Model** *(next)*
  1. Iteration 9 steered (this document).
  2. Layer 3 built: incoming lethality (S2) + player evasion (S3), with the
     concurrency axis (S5).
  3. Roster completed to the agreed scope (**S.q1**), each type arriving with
     its harness row (P4.10 doctrine).
  4. The melee bench (S9); `strength_cost` re-derived from measurement.
  5. **The calibration pass** — mine to initiate and lead (H.q4).
- **M6b — The War** *(resumes after)*: composer Beats 3–4, nodes, biomes,
  weather, the command room.

**What is already banked and is NOT wasted by the re-order:** the manifest
(v1.70) is *required* by M6a — it is the thing that consumes the exchange rate
the melee bench will price. The composer (v1.71) is complete, tested and inert;
it costs nothing to leave sitting. The F4 quantizer fix is a pure correctness
win. Only Beat 3 is actually paused, and it had not started.

### S11 — What this costs, and the ruler it disturbs

- **`ReferencePilot` does not evade.** Its own header says so: *"never evades —
  so v1 flew into the bomber."* Measuring player evasion (S3) against a pilot
  that makes no attempt to survive would measure nothing but its flight path.
  Giving it defensive behaviour is a **`PILOT_VERSION` bump (3 → 4), which
  invalidates every committed delivery factor** and forces a full deliberate
  re-measure. That is the single largest cost in this iteration and it is
  unavoidable — see **S.q5**.
- **Configs:** ammo fields on the weapon side only if S.q3 says yes; no new
  config classes are otherwise required — `FrameConfig.hull`/`armor` and
  `EnemyConfig.damage` already exist.
- **BALANCE.md becomes a three-layer document**, and its "Known-inert fields"
  section gets re-checked (armor stops being probe-only the moment player-side
  lethality is real).
- **The regression guarantee holds:** every new factor arrives with its bench
  and its assertion, or it does not arrive (H8).

### S open questions (react by ID)

- **S.q1 — Roster scope: how complete is "complete"?** The designed bestiary is
  roughly ten (Gnat, Raider, Falx, Aegis, Screamer, Turret, SAM, Convoy,
  Commander, Sentinel); **four** are shipped. Full designed roster, or a
  narrower "enough types to make the counter-web real" cut? My lean: **the web,
  not the census** — add Falx and Screamer (the two the counter-matrix actually
  leans on: the open-approach flyer and the EW threat FCS exists to answer),
  balance the resulting six, and let the rest arrive with the systems that need
  them. Ten unbalanced types is further from "basic balance" than six measured
  ones.
- **S.q2 — Does the melee bench PRICE `strength_cost`, or CHECK it?** Derive the
  numbers from measured even-trade ratios (the bench is the source of truth), or
  keep them hand-set as design statements and let the bench flag divergence? My
  lean: **price them** — a hand-set exchange rate is exactly the kind of
  unvalidated number the instrument exists to retire, and unlike a feel-promise
  there is no human sense to consult about whether a turret is worth two
  raiders.
- **S.q3 — Ammo now, or defer cost-per-kill?** Adopt magazines (making
  "bankrupt" falsifiable, and giving pads/re-arm their referent) vs. defer until
  P5's economy. My lean: **adopt a minimal capacity field now** — one number per
  weapon, no re-arm economy yet. It makes a founding feel-promise testable for
  almost nothing, and the pads already exist in the composer's output.
- **S.q4 — How is exposure created for the survivability bench?** N-vs-1
  (matches the game), a hold-station-under-fire task (cleanest isolation), or
  both. My lean: **the task for the FACTOR, N-vs-1 for the WEB** — isolate
  player evasion against a controlled shooter, then let concurrency show up as a
  bench axis on the real cells. Isolation for measurement, realism for
  validation, exactly as Layers 1–2 already split it.
- **S.q5 — Does the reference pilot learn to survive (PILOT_VERSION 3 → 4)?**
  Required for S3 to mean anything, and it invalidates every committed delivery
  factor. Options: bump and re-measure everything deliberately; or keep the
  pilot naive and measure *frame* survivability only (armor and hull, no
  evasive skill), accepting that "how well does this pilot avoid fire" stays
  unmeasured. My lean: **bump it, once, as part of this iteration** — do the
  re-measure deliberately and in one go rather than dribbling it, and never
  bump it again for the roster build.
- **S.q6 — After `strength_cost` is re-derived, do we re-run the war?** The
  127-sortie / ~10% headline was measured on the guessed rates. Re-running is
  cheap; the question is whether we *act* on the result during M6a or note it
  and wait for M6b. My lean: **re-run and record, act in M6b** — it is a
  strategic-layer number and the strategic layer is not what we are balancing
  yet, but leaving it stale would mislead the next person who reads it.
- **S.q7 — Detectability: confirm the S8 deferral?** I have taken the user's
  invitation and deferred it with a stated trigger. Overrule if you want it
  modeled now.

### S steering — ANSWERED (v1.74, 2026-07-27)

Iteration 9 is steered — all seven S.q resolved, six to their leans, with three
user enrichments that change the model rather than just confirming it.

- **S.q1 → DECIDED: the web, not the census.** Balance **six** types first
  (raider, turret, gnat, aegis + **Falx** + **Screamer**), then extend. The
  remaining four arrive with the systems that need them, each with its harness
  row (P4.10).
- **S.q2 → DECIDED: the melee bench PRICES `strength_cost` — but it must earn
  that authority first.** The user's question is the right one and had no answer
  in the proposal: *"how do we measure the reliability of the melee bench?"* You
  cannot validate a source of truth against a more authoritative measurement,
  because there isn't one. You validate it by **properties that can fail** —
  five, all cheap, all assertable (**S12**, added below). Sequencing: the bench
  is **step 4**, after the roster is complete — pricing a roster you are about
  to extend just means pricing it twice. And pricing is a **loop, not a
  one-shot**: price → rebalance stats → re-price.
- **S.q3 → DECIDED: adopt ammo — and the user's reason is better than the
  proposal's.** S6 argued only that "missiles bankrupt on gnats" is currently
  unfalsifiable. The user: capacity is **a balance LEVER in its own right** —
  "we can make a powerful weapon more expensive to use, or limit its fire
  count." That promotes ammo from bookkeeping to **a fourth design axis
  alongside damage, cadence and delivery**, and it is the axis that lets a
  weapon stay powerful *and* fair. Consequence worth flagging: ammo is a
  per-weapon property, which strengthens the case for the long-deferred GAP-1
  `WeaponConfig` split — `CombatConfig` is a player-side bag, and capacity per
  weapon wants a home.
- **S.q4 → DECIDED: task for the FACTOR, N-vs-1 for the WEB.** Isolation for
  measurement, realism for validation — the split Layers 1–2 already use.
- **S.q5 → DECIDED: bump `PILOT_VERSION` 3 → 4** and re-measure deliberately, in
  one go. User: "its a good practice."
- **S.q6 → DECIDED: re-run the war after re-pricing, and record it.** Act on the
  result in M6b, not M6a — but never leave the 127-sortie headline standing on
  rates that have been superseded.
- **S.q7 → DECIDED: detectability deferred**, trigger as stated in S8 — and the
  user reframed *why* the deferral is safe (**S13**, added below): a repeatable
  balance suite is what makes new mechanics cheap to introduce later.

### S12 — How the melee bench earns the right to price (S.q2, discharged)

A bench that is the source of truth cannot be checked against a better answer.
It is checked against **properties that can fail** — and each of these has
caught real bugs in instruments of this shape:

1. **Transitivity.** If the bench prices turret = 2× raider and aegis = 2×
   turret, then aegis must trade evenly against **4 raiders** — test that
   composed prediction *directly*. Non-composing ratios mean either the bench is
   noisy or "strength" is not a scalar at all. This is the strongest test
   because it is the one most likely to fail.
2. **Scale invariance.** If 3 raiders ≈ 1.5 turrets, does 6 ≈ 3? A ratio that
   drifts with N means strength is **N-dependent** (focus fire, swarm overwhelm,
   concentration) — which would be a *finding*, not merely a failure: the war's
   linear arithmetic would be wrong, and that is worth knowing before M6b builds
   more on it.
3. **Mirror symmetry.** Swap sides A and B in the arena. If A wins 70% and the
   mirrored B also wins 70%, the arena has a **positional bias** (spawn
   geometry, who acquires first) and every price is contaminated. The classic
   melee-bench bug.
4. **Determinism and a stated error bar.** Same seeds → same result (F4). Across
   seeds → report the **spread, not a point value**. A bench that cannot state
   its own variance cannot be relied on; a price is `2.0 ± 0.3` or it is a
   guess wearing a decimal point.
5. **Layer 1 sanity anchor.** Gross disagreement with the lethality arithmetic
   (total hull, damage throughput) means the bench is measuring behaviour, not
   stats. Weak test, catches only large errors — but free.

**And the ruler underneath it must be pinned.** In a melee, both sides are flown
by AI, so the bench measures *these types as currently implemented*. That is the
`PILOT_VERSION` problem with a second head: improving the raider's chase logic
would silently re-price the raider. **A `BESTIARY_AI_VERSION` pin is required
before any price is committed**, on the same rule as the pilot's — numbers
measured under different enemy brains never share a table.

### S13 — The repeatable suite as an ENABLER (the user's S.q7 reframe)

The user's argument for deferring detectability: once a **repeatable** balance
suite exists — "just like a unit test... let it run and get back the balancing
result" — then introducing a new mechanic (an invisibility module) becomes
tractable, because you run the suite, see the macro effect, and design the
counter (an advanced radar) against measured evidence.

This is **H8's green board and H.q6's advisory→gate, re-derived independently
from the user's own reasoning** — a good sign that the doctrine is load-bearing
rather than decorative. What the reframe *adds* is the motive: the harness is
not overhead protecting existing balance, it is **the thing that makes a large
roster affordable at all.** Every type after the sixth is cheap precisely
because the suite exists. That is the strongest argument yet for paying the S11
re-measure cost now rather than later.

Two refinements, recorded so the idea does not overreach:

- **The suite localizes; it never prescribes.** It says *which cell broke* and,
  via the H.q2 axis vector, *along which axis*. Choosing the counter is design
  judgment. A harness that proposed counter-modifications would be the
  expected-value oracle BALANCE.md exists to forbid — the user's phrase "find
  the best and most reasonable counter modification" is the human's job, with
  the suite supplying the evidence.
- **Runtime forces tiering, and the user already anticipated it** ("a full
  balancing run set will take a long time"). Today's 14-cell web takes ~10
  minutes. Six enemies × three weapons, plus frame cells, plus a concurrency
  axis, plus survivability cells, plus melee composition sweeps is plausibly
  5–10× that. So the suite ships in **two tiers**: a fast **smoke** set that
  runs after any config change, and the **full** set run deliberately (and
  reported with its pilot version, AI version and config stamp). A suite too
  slow to run is a suite that rots — H8's red-rots argument applied to wall
  clock.

### S14 — The Screamer's FCS question (PROPOSED, 2026-07-28 — awaiting steering)

> **STATUS: DISCHARGED 2026-07-28 (v1.83).** Steered in v1.80, built in v1.82–v1.83.
> S.q8 → **graded**, not binary: the user overruled my lean, and the build
> vindicated the overrule — the screamer's own standoff sits inside the fading
> part of its field, so closing to kill it walks you into a stronger jam.
> S.q9 → **a jam STATE on aim** (`<frame>:<weapon>:<clear|jammed>`), as leaned.
> S.q10 → **the bump was accepted**, and landed a step early (v1.82,
> `PILOT_VERSION` 6) so it could be batched with the frame-evasion edit and cost
> one re-measure instead of two. The prose below is left exactly as written; it
> is the question, and the log entries are the answer.

S.q1 decided the roster (raider, turret, gnat, aegis + **Falx** + **Screamer**).
Building Layer 3b (v1.78) surfaced a question about the Screamer that the roster
decision could not have anticipated, and it has to be settled *before* the type
is built rather than discovered halfway through. Three sub-questions,
**S.q8–S.q10**; react by ID.

**Why the Screamer is different from every type shipped so far.** It is the
first roster member whose effect is neither damage nor durability but **a
multiplier on the player's own delivery factors.** Run it through the three
layers and it disappears from two of them:

| layer | what the Screamer does |
|---|---|
| **1 — lethality** | nothing. `damage` 0. |
| **3a — incoming** | nothing. `mode: none` — it prices no frame's durability, which is the Aegis's illegibility (v1.72) exactly. |
| **2 — delivery** | **everything.** The jam is a degradation of `aim_quality` and an outright refusal of the missile lock. |

- **S.q8 — What does a jam DO, mechanically?** (a) **Binary**: inside the
  bubble the gun director is off, the missile lock refuses, and the flak fuse
  degrades to contact-only — the design's own prose (P4.2, P3.6's flak note),
  taken literally. (b) **Graded**: scale the director's solution window and the
  lock time with distance from the screamer. My lean: **(a), with the telegraph
  carrying the softness.** S7's rule is that a step must never be smeared into a
  slope to look continuous, and the design already specifies HUD fuzz at the
  bubble edge — the warning is the gradient, the effect is the step.
- **S.q9 — Does the instrument grow a JAM STATE axis, or does the screamer get
  a column?** BALANCE.md's own FCS rule says equipment shifts a delivery factor
  and never adds a matrix dimension; the screamer is the *negative* FCS, so the
  same rule points the same way. My lean: **a state axis on aim** —
  `<frame>:<weapon>:<clear|jammed>` — on the exact precedent of `Lethality.
  STATES` (shielded/cracked), which is how the Aegis was absorbed without a
  column. **Cost, stated:** the aim cells double, six to twelve.
- **S.q10 — Does the Screamer force `PILOT_VERSION` 5?** This is the expensive
  one and it was not visible from the roster decision. The reference pilot hands
  its trigger to the gun director (`use_director = true`). Turn the director off
  and **it fires nothing at all** — the manual path exists (`fire_cone_deg`) but
  there is no rule for falling back to it. Teaching it that switch is a
  behavioral edit, which is a version bump, which is a full deliberate
  re-measure — and **S.q5 promised the pilot would not be bumped again for the
  roster build.** Options: accept the bump and schedule it deliberately; or find
  a jam model the current brain survives. My lean: **accept it, and let the
  promise break loudly rather than quietly.** The Screamer's entire design
  purpose is that "the manual fallback stays a skill path forever" (P3.6, the
  iron trigger), so a measuring pilot that cannot hand-fire *cannot measure this
  type at all* — the bump is not incidental to the Screamer, it is the same
  fact as the Screamer.

**Sequencing lean, which follows from the above: build the Falx FIRST and
alone.** The Falx is a conventional flyer — an open-approach interceptor — and
costs the model nothing new: one evasion row, some lethality column entries,
exactly like the raider. The Screamer costs an axis *and* a pilot bump. Landing
them in one step would put two invalidations in one re-measure and make neither
attributable, which is the mistake the pinned-ruler discipline exists to
prevent.

## Iteration 10 — R: Ammo & the Resupply Gates (BUILT, 2026-07-31 — proposed 2026-07-30, steered same day)

> **STATUS: BUILT.** Proposed 2026-07-30 (v1.88), steered in full the same day
> (R9 / v1.90), and shipped across v1.91 (the blaster's heat sink and Layer 1's
> duty cycle) and v1.92 (magazines, resupply gates, salvage drops). **R2's
> "blaster: infinite" line is superseded by R9 — read R9 first.** Everything
> below stands as the reasoning that produced the build, including the parts
> the user overruled, because a paper that quietly edits itself to agree with
> the outcome stops being a record.

> Opened by the user after the first flight of the composed roster (v1.85):
>
> > *"i feel now that we can add more 'challanges' to get more 'resources', for
> > example flying through the green big gate repair, maybe now we can fly
> > through the smaller blue gates and get energy, so now maybe we can have the
> > ammo counter, maybe a gate type for each weapon ammo. the flak is effective
> > and once the fire rate is high it starts to be buffed, so we may limit its
> > usage to shorter bursts."*
>
> Sections **R1–R8**, open questions **R.q1–R.q6**; react by ID. Per 2.4 this
> paper fixes the *grammar* — what is consumable, what refills it, what the HUD
> owes you — **not** absolute magazine sizes. Every number lands in
> `CombatConfig` and gets bench-tuned like a flight gain.

### R1 — This is not a new pillar; it is a referent P2.6 has been missing

The design already assumes ammunition exists. **P2.6 says pads "repair hull +
**re-arm magazines**"; P5.6 prices a between-sortie "re-arm"; `SortieComposer`
already emits a `pads: int` per sortie, scaled inversely with node difficulty.**
None of it means anything today, because there are no magazines to re-arm — the
blaster, the flak pod and the missile rack all fire forever. The whole "pad-poor
node makes every spent magazine count" clause is currently a promise about a
resource that does not exist.

So this is not a new economy. It is the moment the *tactical* consumable becomes
real, which is what makes P2.6 a difficulty knob instead of a word.

**And the form factor is already decided, by playtest.** D5 revised the repair
**pad** into the repair **gate** for a stated reason: *"holding station on a
wounded quad under fire is a death sentence — you recover by flying through,
keeping your speed and your life."* Everything below inherits that. Resupply is
a gate you thread, never a pad you land on. The user asked for exactly this
shape, independently, which is a good sign the lesson generalised.

### R2 — The grammar: what is consumable, and what is not

The proposal's spine, and the one place I would push back on a literal reading
of the ask ("a gate type for each weapon ammo"):

| weapon | consumable? | why |
|---|---|---|
| **Blaster** | **No — infinite** | It is the floor. A pilot who runs out of everything must still be able to fight, or a dry run is an unlosable-but-unwinnable stalemate with the gate shut. It is also the weapon the whole balance instrument is calibrated around. |
| **Flak pod** | **Yes — magazine + reload** | Its power is uptime (see v1.86), and the user's own read is that it wants shortening. A magazine is the *right-shaped* limit: it caps a burst without touching damage or fuse, so the type stays exactly as good and stops being always-on. |
| **Missile** | **Yes — a small count** | Already cooldown-limited, which is a *rate* limit; a rack is a *quantity* limit, and they do different jobs. Four missiles that must be spent well is a better decision than infinite missiles on a timer. |

**Three consumables would be two too many.** One counter per weapon that has one
is legible; a fourth "energy" pool that also gates something is a second
currency inside a fight, and P5.1's whole discipline is that currencies stay
walled and few.

### R3 — The gate family: one verb, colour-coded by payload

The palette rule (CLAUDE.md) already assigns meaning to colour, and the two
existing gates use it: **blue = navigation (exit), green = repair.** The family
extends without inventing a new visual language:

- **Green — repair** *(exists)*: engines + hull.
- **Amber — flak resupply**: refills the pod's magazine.
- **Violet — missile resupply**: refills the rack.

Small, unmissable, and different from the exit gate at a glance, which is the
one confusion that would actually cost a run. **They should be smaller than the
exit gate and require more precision to thread** — that is the "challenge to get
resources" the user asked for, and it is the flight model advertising itself
(P2.6's original argument for landing skill, transposed onto the verb that
survived playtest).

### R4 — Where gates come from

The wave director already places a composition; resupply is the same table one
column over. A `GATES` plan beside `PLAN`, spawned per sortie rather than per
wave, so a sortie has a *layout* you learn and route around rather than a stream
of pickups.

**Pad-poor is the difficulty knob P2.6 promised**: gate count falls as the
sortie number rises. Sortie 1 is generous; sortie 5 gives you one violet gate
and a decision about when to spend it.

### R5 — The flak's burst problem, answered without a nerf

The user's *"limit its usage to shorter bursts"* is achievable three ways, and
they are not equivalent:

1. **Lower `flak_fire_rate`** — makes the weapon worse everywhere, including the
   cells the harness already validated. Rejected.
2. **Overheat** — a second resource with its own recovery curve, invisible to
   the resupply loop. Rejected: it solves the same problem while sharing nothing
   with the rest of the proposal.
3. **A magazine** *(recommended)* — caps the burst, leaves the weapon's
   per-shell numbers untouched, and *feeds the gates*. The pod becomes a thing
   you spend and go refill, which is precisely the loop being asked for.

Note the interaction with v1.86 and take it deliberately: the pod already got a
real nerf when it stopped riding the blaster's cards. **Fly that before stacking
a magazine on top**, or two changes land in one feel judgement and neither is
attributable — the same discipline as batching pilot behaviour edits.

### R6 — What the HUD owes

Two counters, and only for weapons that have one. The absence of a blaster
counter is information: it says *that one never runs out*. A magazine you cannot
see is a magazine that will run dry at the worst moment and read as a bug — the
same argument the aegis's shield bubble won (v1.25: "a player whose shots do
nothing must be able to SEE why").

### R7 — What this does to the balance instrument, stated before it is built

**Layer 1 assumes infinite ammunition.** `Lethality.versus` answers "how many
shots and how long to kill this", with no term for whether you *have* that many
shots. Magazines add one, and it is the same shape as the arithmetic that
already makes a swarm expensive for a missile (P4.3's bankruptcy row) — only now
it applies to every weapon that has a count.

The honest consequence: **a matchup can become unwinnable-per-magazine while
staying winnable**, and the instrument should say which. That is a Layer 1
addition (shots-to-kill vs magazine size), not a new layer, and it is cheap —
but it must land *with* the feature, or the first bench run after this ships
will report numbers that quietly assume a resource the game no longer gives you.

### R8 — The vertical-slice cut

Smallest thing that delivers the loop: **flak magazine + amber gate + one HUD
counter.** One weapon, one gate type, one number on screen. Missiles and the
violet gate follow only if the flak version feels right. Everything else in this
paper is grammar for later.

### R9 — STEERED 2026-07-30 (R.q1–R.q6 answered; this section overrides R2)

The user answered every question. Where an answer overrides this paper, the
answer wins and the original text is left standing above so the change of mind
is legible.

| | answer | vs. my lean |
|---|---|---|
| **R.q1** blaster | **A rechargeable charge meter that can OVERHEAT, needs cooldown, and is upgradeable** | overrides R2's "infinite" |
| **R.q2** magazine or pool | **Sortie resource** | agreed |
| **R.q3** wave-clear top-up | **Free re-arm** | overrides my "no top-up" |
| **R.q4** gate charges | **Finite per gate**, with the count written beside it | agreed |
| **R.q5** energy | **PINNED.** "Energy" for now *is* R.q1's blaster charge; a separate definition is a later conversation | deferred by the user |
| **R.q6** enemy drops | **Yes** — *"it would give the player a reason to take out the infinite turrets"* | overrides my "gates only" |

- **"Three consumables would be two too many." — "why?"** A fair challenge, and
  the answer is that **R2 counted the wrong thing.** The cost of a consumable is
  not a counter on the HUD, it is whether running out can STRAND you: a resource
  only a gate refills turns every empty moment into a forced disengage, and
  three of those — with your default weapon among them — means the weapon you
  fight with while hunting for a gate is the one that can be gone. That was the
  real objection, and it was written as if it were about legibility.
  - **R.q1's answer dissolves it rather than overruling it.** A self-recharging
    heat meter is not that kind of resource at all. It never strands you, it
    PACES you: it is firing discipline, the same family as trigger control, and
    it needs no gate because it refills itself. So the shape is **two economies
    and a tempo mechanic**, not three economies — flak and missile are what the
    gates are for, and heat is what the trigger is for. R2's table stands for
    the two; its "blaster: infinite" line does not.
  - **It also gives `Rapid Blaster` a real cost.** Faster fire means faster
    heat, so the upgrade that was a pure gain becomes a trade — and P4.3's
    chip-gun `+` against a screamer changes character, since the iron trigger
    now has a duty cycle. Both are consequences to measure, not to assume.
- **R.q2 AND R.q3 TOGETHER MOVE THE UNIT OF SCARCITY, and it is worth naming.**
  "Sortie resource" plus "free re-arm on wave clear" means the thing you can
  actually run dry inside is the WAVE, not the sortie — a sortie is ~3 waves and
  each one hands you back a full load. That is coherent and forgiving, and it is
  probably the better game: ammo becomes mid-fight pressure rather than a
  bookkeeping tax carried between fights. **But it costs P2.6's "pad-poor node"
  difficulty knob most of its bite**, because a node's gate count now only
  matters within a single wave. Recorded so nobody later reads the two answers
  as contradictory — they are not, they just relocate the pressure.
- **Gates get the menu tower's glyphs** (the user's ask: *"i want the health/ammo
  gates to use the text effect on them like the menu room gates. its really
  nice"*), partially transparent, with R.q4's remaining charges as a number
  beside the label. `GlowText3D` is the existing primitive — B5's window text —
  and it is already a MultiMesh of emissive cubes with no font asset. **It has
  no digits**: the font table is space and A–Z only, so 0–9 land with this work.
  That is the B8 "word chains" seed growing its first branch outside the tower.

### Open questions (R.q1–R.q6 — ANSWERED, see R9)

- **R.q1 — Does the blaster stay infinite?** My strong lean: yes (R2). The
  counter-case is that a fully consumable arsenal makes every gate matter and
  turns ammo discipline into the run's core tension — a real design, but a
  different game, and one where a bad draft can strand you.
- **R.q2 — Magazine-and-reload, or a pool that only gates refill?** A pod that
  reloads itself after a pause is a *burst* limit; a pod that only refills at a
  gate is a *sortie* resource. My lean: **sortie resource**, because it is the
  one that makes the gates matter. Burst-limit-only would deliver the flak fix
  without ever needing this iteration.
- **R.q3 — Does a wave-clear top you up?** Free re-arm between waves is
  forgiving and removes most of the tension; no top-up makes a long sortie a
  genuine attrition problem. My lean: **no top-up in the run loop**, since the
  gates are the answer.
- **R.q4 — Do gates respawn?** The repair gate has a 1.5 s cooldown and is
  permanent, which is spam-camp-proof but infinitely generous over a sortie. My
  lean: **finite charges per gate** (2–3), so route planning is real.
- **R.q5 — Is "energy" a third thing you meant, distinct from ammo?** The ask
  mentions energy *and* ammo. If energy is a separate resource (boost? shields?
  the video link?) it is a different paper; if it was a word for ammo, R2 covers
  it. **This one I genuinely cannot infer.**
- **R.q6 — Do enemies drop resupply?** P5.2 already says combatants drop
  salvage in the campaign. Drops-from-kills and gates are two answers to the
  same question and the run loop should probably pick one. My lean: **gates
  only**, because a drop rewards killing and a gate rewards *flying*, and this
  project's north star is the flight model.

## Iteration 11 — T: The Transit Gate (PINNED, 2026-07-30 — user-initiated, not scheduled)

> *"idea! a gate which would be a portal to another location on the map, (like
> the game portal) that forces the pilot to calculate the end's rotation and
> position so once it passes the physics on it changes according to the
> destination endpoint of the portal"*
>
> Pinned rather than proposed: it is a genuinely good idea and it is also the
> first mechanic on this list that could fight the flight model, which is the
> product. Recorded now, with the hard parts named, so that when it comes up
> it starts from the questions instead of from the shader.

**Why it belongs here at all.** Every mechanic in this project is judged by
whether it makes the flight model matter more. A transit gate does, in the
purest way available: a portal whose exit is rotated relative to its entrance
turns a hole in the air into a **spatial reasoning problem you solve with your
hands at 20 m/s.** You do not aim at the gate, you aim at what the gate is going
to make of you. That is P2.7's dare taken to its logical end, and it is the one
idea on the board that would be *worse* in a game with a lesser flight model.

**T1 — The transform is the whole mechanic.** Passing through maps the drone's
transform and velocity through `exit * entry.affine_inverse()`. Position and
orientation are easy. **Velocity is where the design lives**: rotate the vector
and a portal placed sideways converts your dive into a lateral slingshot with
the ground now in a direction your inner ear did not vote for. Preserve the
magnitude and it is a pure redirect; scale it and it becomes a booster, which is
a different and probably worse mechanic.

**T2 — The things that will actually be hard, in order.**

1. **The camera.** FPV is the product. Rotating the pilot's world 90° in one
   frame is, in a headset, an assault; on a monitor it is merely disorienting.
   Whether the transition is instantaneous, blended over ~100 ms, or *only ever
   yaw-aligned* (exits share the entrance's up-vector) is the first fork, and it
   is the one that decides whether this ships at all.
2. **The rate loop — CORRECTED 2026-07-31, and the correction is good news.**
   This section previously claimed a discontinuous basis would spike the D-term
   and that the loop's history needed reseeding. **That is wrong**, and reading
   the code rather than reasoning about it says why:
   `FlightController._measured_rates()` returns `global_basis.transposed() *
   angular_velocity`, so under a rigid rotation `R` applied to BOTH the basis
   and the world-space angular velocity, the body-space rate is invariant —
   `(RB)ᵀ(Rw) = BᵀRᵀRw = Bᵀw`. The pilot-axis rates the controller filters,
   differentiates and integrates therefore do not move at all through a
   transit. `RateController`'s history (`_last_measured`, `_gyro_filtered`, the
   integrator) is in those same body axes and needs no reseeding either.
   - **The condition is the whole of it: rotate `angular_velocity` with the
     basis.** A teleport that moves the transform and leaves angular velocity in
     the old world frame is the version that spikes.
   - **THE REAL RESEED IS SOMEWHERE ELSE, and it is one line.**
     `FlightController._previous_velocity` (declared :66, written :172) is a
     WORLD-space velocity, and `_on_body_entered` (:317) reports impact severity
     as `(_previous_velocity - linear_velocity).length()`. Rotate the velocity
     through a portal and that delta is spurious: 20 m/s through a 90° exit
     reads as ~28 m/s of delta-v, which is well past `crash_damage_speed` 12 and
     lands ~96 damage on the first thing clipped after transit. **A transit must
     rewrite `_previous_velocity` along with the rest, or it hands out a phantom
     crash.**
3. **Seeing through it.** A Portal-style see-through view needs a second camera
   rendering to a viewport texture on the gate's face. That is affordable for
   ONE pair; it is not obviously affordable for several, and a portal you cannot
   see through is a much weaker version of the idea (you would be jumping
   blind). The `blend_mix` pool surface built for the exit gate in v1.90 is the
   natural fallback look — and notice it is already the right shape.
3b. **The signal leash will fight it.** `main.gd`'s link range (`signal_lost_m`,
   300 m from the origin) drops the feed and yanks the pilot back to the menu
   tower. A transit gate whose far end is a long way out trips that on arrival,
   which would read as the portal killing the run. Either the exits stay inside
   the leash, or the leash learns that a transit is not a stray.
4. **Everything else that moves.** Do projectiles transit? Missiles mid-flight?
   Do enemies know the gate exists? "No" is a legitimate answer to all three and
   should be the starting assumption, but it has to be *decided*, because a
   player will absolutely try to shoot through it in the first minute.

**T2b — The user's own references, kept verbatim-in-substance** (2026-07-31), so
whoever picks this up starts from the recipe rather than from a blank shader:

- **Structure**: `Area3D` + `CollisionShape3D` for detection; a `Marker3D` child
  defining the exit point *and facing*; `@export var target_portal: NodePath` so
  pairs are linked in the inspector rather than in code.
- **Transfer**: on `body_entered`, set the body's `global_transform` from the
  destination marker, and **reorient linear and angular velocity relative to the
  exit's rotation** — momentum conserved, direction rewritten. That is T1's
  transform, arrived at independently.
- **The loop guard, which is the bug everyone hits**: a `just_teleported` flag
  cleared by a short `SceneTreeTimer` (0.5–1 s), **plus** spawning slightly
  forward along the exit marker's local direction so the body does not
  immediately re-trigger the destination's own area. Both, not either.

**T3 — What it is NOT.** Not a resupply gate (Iteration 10) and not the exit
gate (M4). Three fly-through objects with three meanings is already the ceiling
for one arena; a fourth needs its own colour and its own unmistakable silhouette
before it can exist.

---

## Iteration 12 — W: The Bridge (flying the war) (PROPOSED, 2026-07-31 — agent-initiated, steered in part the same day)

> **The war exists and has never been played.** `SortieComposer.compose()` is
> called by nothing but its own tests, and no scene has ever instantiated a
> `sortie_spec`. This is not a new pillar — all five are designed and four are
> built. It is the **introduction**: the function that turns the composer's
> output into ground a human flies over. Sections **W1–W11**, open questions
> **W.q1–W.q7**; react by ID.

### W1 — The state, stated plainly

Against the roadmap's vertical-slice target (~5 nodes · 2 frames · 3 weapons ·
4 enemies):

| target | have | gap |
|---|---|---|
| 2 frames | Kestrel, Atlas | **met** |
| 3 weapons | blaster, missile, flak | **met** |
| 4 enemies | six shipped | **exceeded** |
| ~5 playable nodes | **zero** | **the whole gap** |

Everything except the map is at or past target, and the map is not missing art
— it is missing a *function call*. `TheaterGenerator` makes nodes. `WarSim`
ticks them. `WarManifest` dresses a garrison in named units. `SortieComposer`
turns one node into a complete spec — archetype, objective, layered garrison,
triggered reserves, approach geometry, pads, dares, and the H.q2 difficulty
input vector — and `sortie_trace` prints thirty of them in under a second.
Nothing has ever built one.

That asymmetry is the finding. Four of the five pillars are further along than
the roadmap asked for, and the fifth is at zero, because it is the only one that
required the two halves of the project to be introduced to each other.

### W2 — The bridge must terminate in a STRIKE, not a Dogfight

`SLICE_ARCHETYPES` allows two, and they are not equally worth building first.

A **Dogfight is the wave director wearing a different hat**, and P2.12 says so
in as many words. Read the composer: for `dogfight` it collapses the entire
layered garrison into one flat `outer` layer (`_layer`: *"a dogfight has no
rings to hold"*) and splits the reserve into two timed waves triggered on
`wave_cleared`. That is `WaveDirector.PLAN` with different spelling. A bridge
that terminates there terminates in the game that already exists.

A **Strike is the thing this project has never had: an objective you must
destroy while a garrison shoots at you.**

The difference is not flavour, and Iteration 9 predicted it would matter. S4
asked why the Kestrel spends 0% hull in four measured cells and answered that
the mechanism is not marksmanship but **time in the threat envelope** — the
Kestrel kills the turret in 1.3 s, so exposure is ≈ 0, and raising `MAX_SECONDS`
buys nothing because *a duel ends when the enemy dies, not when the clock
expires*. Its list of what actually creates exposure has, as item 2: *"a task
that holds you in the envelope — 'destroy the objective while the turret ring
fires', i.e. a composed sortie rather than a duel."* And its conclusion is the
sentence this whole iteration should be steered by: **duels prove
feel-promises; sorties produce curves.**

Three named debts sit on the far side of that sentence:

- **H7's 127-sortie median.** H7 itself refuses to recalibrate against
  *"abstract garrisons and a stopgap draft economy"* — which is still exactly
  what `war_soak` runs on, because nothing has ever fed it a flown result.
- **The Atlas at −0.67 against three raiders** where P3.4's paper expects 0.
  Durability is precisely the property that only appears when you are
  outnumbered *and cannot leave*, and a duel always lets you leave.
- **H6's graded 45–65% middle**, which S4 says the unit layer structurally
  cannot produce: a win rate over a deterministic duel is a step function.

None of the three is touched by a Dogfight. All three are addressed by a Strike.
**The Dogfight still gets built** — it is the cheap end-to-end proof that the
pipe connects, and it is the wave director's stated migration path — but it is a
waypoint, not the destination.

### W3 — The spec, audited field by field

What `compose()` hands the scene layer, and what exists to receive it. This
table is the honest scope of the work:

| spec field | what it asks for | what exists today |
|---|---|---|
| `layers` outer/mid/inner | concentric placement by doctrine | one ring (`_air_point`/`_ground_point`); concentric is new |
| `triggers[]` | reserves arriving on a stated condition | nothing — the only trigger in the game is "the last wave died" |
| `objective` / `objective_assets` | 1–4 structures whose death is the sortie | **nothing.** `target.tscn` is a floating score object |
| `approach.ingress_m` (150–400) | an approach flown from a start line | nothing; every arena starts you in the middle |
| `pads` (0–3) | repair + re-arm inside the fight | **Iteration 10 built exactly this — see W4** |
| `dares[]` | one unmarked, risk-priced challenge | dev-room gates and a tunnel, all hand-placed |
| `biome` | which ground this is | `city.tscn` + seeded `CityLayout`; greybox |
| `weather` | the P1.6 modifier pack | `WeatherConfig` is a persisted stub, unsimulated |
| `capture` | flip the node, or only dent it | needs W7 |
| `garrison_strength` | the price the sortie settles at | `WarManifest.strength_of` — exists |
| `difficulty_inputs` | the H.q2 axis vector, for diagnosis | exists, consumed by nobody |

Two rows are worth reading twice. `objective_assets` is the only piece of
genuine *content* the bridge needs, and it is small. `pads` is the row where the
receiving hardware was built first and has been sitting idle.

### W4 — P2.6's pad count finally has a referent, and Iteration 10 built it early

`SortieComposer` has emitted `pads: int` since v1.71 — scaled inversely with
garrison load and escalation, zero at an HQ or a command post. It has never
meant anything, because nothing consumed it.

Then Iteration 10, for entirely unrelated reasons (a playtest ask about
resources), built **the repair gate, the amber flak gate and the violet missile
gate** — and R1 opened by noting that P2.6's *"pads repair hull + re-arm
magazines"* was a promise about a resource that did not exist. R1 was solving
the missing resource. It also, without meaning to, built the pad.

So the bridge does not design pads. It **spends `spec["pads"]` on gates that
already exist** (W.q4), and two systems built a month apart become one. The
sortie number is finally the *node's* difficulty rather than a counter in a run
— which is what P2.6 asked for and `WaveDirector.gate_count()` could only
approximate.

The same trick explicitly does **not** work for `dares`. Nothing built dare
hardware; the dev room's gates and tunnel are hand-placed scenery in a
hand-built map. A dare is a placement problem inside a *generated* map, which is
why W11 puts it last and why it is not smuggled in beside the pads.

### W5 — The objective asset: the smallest new thing that makes a Strike a Strike

A `StaticBody3D` with a `Health` and a `destroyed` signal — the turret's shape
minus the gun. Three of them for a factory, one for a radar dish. Constraints,
all of which are one-line to state and expensive to discover later:

- **Killable by every weapon in the arsenal.** A structure only the missile can
  crack converts a loadout *choice* into a loadout *lockout*, and P3's whole
  arsenal thesis is that answers are earned, not required.
- **Findable without a quest marker** (P2.7's doctrine, applied to the
  objective). The emissive palette has no colour for "the thing you came for"
  — W.q5.
- **Priced into the exchange** (W7). Destroying the objective and destroying the
  garrison are different currencies and the war must be told which it received.

**The trap worth naming now**: an objective that dies instantly makes the
garrison decoration; one that takes a minute makes the sortie a health bar. P2.9
already has the right answer — the objective is the **capture gate**, not the
fight. The fight is the garrison you have to survive while spending time on it.

### W6 — Triggers are the archetype, and they are the thing a wave loop cannot do

`TRIGGER_ON` says a Strike's reserve arrives on `objective_damaged`, a SEAD's on
`detected`, a dogfight's on `wave_cleared`. Only the third exists in the game.

That is the entire mechanical difference between a wave loop and a sortie: **a
wave arrives because the last one died; a reserve arrives because of something
you chose to do.** `objective_damaged` is the interesting one, because it turns
the objective from a task into a *decision about timing* — you may scout,
position, kill the pickets and pick your moment, since the clock only starts
when you touch the thing you came for. P2.3 framed this as *"staying unseen is
real counterplay"*; on a Strike it becomes *"hitting it early has a price."*

`detected` needs a detection model the game does not have, which is why W11
defers SEAD past the slice — consistent with `SLICE_ARCHETYPES` already
excluding it.

### W7 — The loop back into the war (the step that makes it a campaign)

Flying a composed sortie is a level. Settling it against the war is a campaign.
The chain, all of which already exists as arithmetic:

1. Kills are priced back through `EnemyConfig.strength_cost` —
   `WarManifest.strength_of` on what died. That is the exchange rate BALANCE.md
   names, finally paying out.
2. The node's `garrison` falls by that amount. **P2.q4 is already decided:
   every kill dents the node**, so a failed sortie is a partial rather than a
   waste, and a death still leaves the target weaker for next time.
3. `capture` (already in the spec, already computed from
   `WarSim.has_adjacent_owner`) decides flip versus degrade.
4. `WarSim` ticks. The enemy acts. Intel ages.
5. The state saves. `WarSim.quantize` already guarantees the dictionary
   round-trips `var_to_str` bit-exactly, so F4's portable save is a file write
   and nothing more.

Until step 5 exists there is no campaign, only a sortie generator. After it,
**H7's number becomes measurable against something real** for the first time.

### W8 — The war does not know two of its own enemies

`grep -rn "falx\|screamer" scripts/war/` returns nothing. `WarManifest.ROSTER`
is `[raider, turret, gnat, aegis]` while the game ships six types and
`WaveDirector.ROSTER` fields all six. The campaign's bestiary is therefore
strictly smaller than the arcade's, and the first composed sortie a human ever
flies could not contain the two most interesting enemies in the game.

**Steered 2026-07-31: both join the manifest now.** It is a `ROSTER` row, a
share in the `DOCTRINE` rows where the type belongs, and a `LAYERING` rule —
data, not code, exactly as P4.10 intends. Provisional and flagged for hands:

- **Falx** — an interceptor that owns open air, so it garrisons `airspace` and
  `airbase` and holds the **outer** layer. It is the type you bait rather than
  chase, which is a *picket's* job description.
- **Screamer** — an escort with no weapon at all, so it belongs only where there
  is something worth protecting: `sam`, `radar`, `command`. **Mid** layer, with
  the garrison beneath it. `WaveDirector.compose()` already enforces "a wave
  must hold something that threatens"; the manifest needs the same rule, or a
  small node can roll a garrison that cannot fight back.

**And it forces a naming decision before it becomes a silent bug.** The manifest
spells the swarm `gnat`; `WaveDirector.ROSTER` spells it `gnats`. The runner
needs a type → scene map, and that map is exactly where a typo deletes a type
from a fight. Standing rule 2: a missing enemy and a tough enemy read
*identically* from a results table, and four separate Falx bugs proved it. One
id, chosen once, asserted by the check — W.q6.

**It is not a hypothetical, and grep settles it.** The line
`var enemy_type: StringName = &"gnat" if type_id == &"gnats" else type_id`
already exists **verbatim in three separate check files** —
`ammo_check.gd:253`, `composition_check.gd:207`, `heat_check.gd:167`. The
workaround has been copy-pasted three times rather than fixed once, which is the
usual sign that the wart is in the data and not in the readers.

**And there is a trap in the obvious fix that a future session will otherwise
walk into.** `delivery_bench.gd` also contains `"gnats"`, and it must **NOT** be
renamed. There it is a *cell label*, not a roster key: `TYPE_IDS` translates the
bench's display names to roster ids at the boundary (with a comment saying so),
the labels are what a WATCH filter matches on, and they are baked into the keys
of `balance/delivery_factors.json`. Renaming them would silently invalidate
every measured delivery factor. **The bench already does the right thing — it
translates at the edge; the wave director is the one that leaked a display
spelling into a type key.** Scope of the rename is therefore exactly
`wave_director.gd` plus deleting the three dead translation lines.

### W9 — Three places where the composer's numbers collide with the shipped game

Found by reading the two halves against each other. Each is the class of defect
that can only appear when two systems are introduced.

1. **The signal leash cuts an open approach in half.** `main.gd` warns at 220 m
   and drops the FPV link at 300 m, returning the pilot to the menu tower.
   `_approach` emits `INGRESS_OPEN_M` = **400 m** for a desert or SAM node (a
   city gets 150 m, which fits comfortably). A composed desert Strike would lose
   its link *during the ingress* and read as the sortie killing itself. This is
   the same defect Iteration 11's T2/3b named for the transit gate, arriving
   from an unrelated direction — two independent features tripping one rule is
   evidence the **rule** is what needs revising, not either feature.
2. **`ARENA_CENTER` is a constant.** The wave director spawns around
   `(-18, 0, -15)` because that is where the greybox's usable air is. A composed
   sortie's centre is wherever the objective was laid, in a map generated from a
   seed. Anything that reads its centre from a `const` cannot host a generated
   map, and every placement routine in `wave_director.gd` does.
3. **Two wave counts describe the same thing.** A dogfight's reserve is split
   into exactly two triggered waves (`_triggers`: `wave_count = 2`) while
   `CombatConfig.sortie_waves` says three. They were authored a month apart and
   both claim to say how long a sortie is. Whichever wins, the other must stop
   existing, or they will drift and no one will notice which one a given fight
   obeyed.

### W10 — What this retires, and what it explicitly does not

**Makes retirable** (not retired — this iteration builds the instrument's
missing subject, it does not tune anything):

- H7's 127-sortie debt gets a real referent for the first time.
- The Atlas becomes legible, because a Strike creates the sustained exposure S4
  named and S5 could only approximate with `count: N`.
- H9's sortie layer — *"floor + ceiling only"* — becomes writable, since it
  needs a composed-sortie runner and that is exactly what W11 builds.

**Does not touch, and must not be blamed on:**

- The balance board's re-measure. The bridge changes no weapon, enemy or frame
  config, so the two are independent and can be sequenced freely.
- The human's director-off aim drill (H.q4's open half).
- Feel and pacing, which stay the human's in full.

**One honest warning, recorded before the first flight rather than after it:
the first composed sortie will not be balanced, and it must not be tuned to be.**
H6 is explicit that SDI is *measured, not authored*, and the composer deliberately
emits an input vector with no composite score precisely so that nobody is tempted
to author one. The first flight's job is to produce a *number*, not a good one.

### W11 — The build cut, and where the human's hands are needed

Each phase is a checkpoint: stop, summarize, hand it over.

| # | what | ends in |
|---|---|---|
| 1 | The manifest roster gap (W8) + the type-id decision | a check, no new flying |
| 2 | `SortieRunner` + `sortie_check.gd` (#17): layers placed, triggers armed, objective spawned, sortie resolved. Greybox ground, Dogfight then Strike | **the first composed sortie a human has ever flown** |
| 3 | The loop home (W7): kills priced, node dented, war ticked, state saved | **the war has been played** |
| 4 | The city as the biome (P2.13), `pads` spent on the gate family (W4), the real ingress (W9.1) | a sortie that is *about* its ground |
| 5 | Node selection + briefing (P2.1's two evaluations, fog included) | a campaign you sit down to |
| — | H7's recalibration | *after* 1–5, never before |

Phase 2 is the checkpoint that matters. Everything before it is plumbing;
everything after it is answering questions that only a flown sortie can ask.

### W open questions (react by ID)

- **W.q1 — Where does a sortie live: a new scene, or a mode inside `main.tscn`?**
  My lean: **a new `scenes/sortie.tscn`.** `main.gd` owns the M4 run's whole
  lifecycle (arm → waves → exit gate → draft → death ends run) and a sortie's is
  different at every step. `dev_map` and `city_map` already set the precedent for
  scenes that mirror main's wiring rather than extending it.
- **W.q2 — Does the M4 run survive alongside the campaign?** My lean: **yes,
  both.** The run is the arcade mode M7 already wants, it is what every bench
  and every balance factor was measured inside, and the menu tower has the leaf
  for it. Deleting it would invalidate the instrument to save a menu entry.
- **W.q3 — What ends a Strike?** (a) objective destroyed = immediate success;
  (b) destroyed, then **egress** — fly back out past the ingress line; (c)
  destroyed *and* garrison cleared. My lean: **(b)**. It is the only one that
  makes `objective_damaged` reserves mean anything (under (a) they arrive to an
  empty sky), it is a flying task rather than a kill task, and P2.9's spectrum
  needs somewhere for "got it, didn't get home" to live. But this is pacing, so
  it is the human's.
- **W.q4 — How does `pads: N` spend on the shipped gate family?** My lean:
  **one repair gate first, then resupply gates alternating flak/missile** — the
  hull is the resource you cannot fly without, so a one-pad node should hand you
  the green one. `ResupplyGate.charges` then carries the rest of P2.6's
  granularity for free. **→ DECIDED 2026-08-01 (v1.99), to the lean, and settled
  by play rather than on paper: the first hand-flown strike was a zero-pad node
  and the pilot flew it broken all the way.**
- **W.q5 — What colour is an objective asset?** The palette is full: cyan =
  navigation, red = threat, orange = score, amber = pylons/flak, green = pads,
  violet = missile, yellow = your fire. My lean: **white/hot-white**, unused and
  unmistakable, reading as "the thing you came for" rather than as any existing
  role. Alternative: no emissive at all — a dark structure the neon does *not*
  claim, which is arguably stronger and definitely riskier.
- **W.q6 — One type id, or a translation table?** My lean: **one id, `gnat`,
  renamed on the wave-director side**, and a check that asserts every
  `WarManifest.ROSTER` entry resolves to a scene. A translation table is a place
  for a typo to live forever.
- **W.q7 — Does the pilot fly the ingress, or start at the target zone?** My
  lean: **fly it** — P2.4 calls the approach a flying decision and it is ~10
  seconds at speed. It requires W9.1's leash fix first, which is the real cost
  of the answer.

- **W.q8 — What actually captures a node: SURVIVING, or HOLDING it?** Raised by
  the user 2026-08-01, and it reframes a problem rather than settling one. Today
  a capture requires `objective_complete and not pilot_lost`, so dying on the way
  out costs you a pilot *and* the ground. The user's objection is that this
  **double-punishes a death**, and P5.4 already states that principle in the
  player's favour for gear: *"Losing a life shouldn't also strip your gear — that
  double-punish cheapens the loadout game."* The same reasoning applies to the
  node.
  - **(a) Keep survival as the gate**, and price "got it, didn't get home" as a
    degrade rather than a capture (the W.q3 third outcome the war-sim can already
    price). Cheapest: one line in `WarSim.apply_sortie`, which currently ignores
    `egressed` entirely. But it leaves the double-punish intact, just softened.
  - **(b) A HOLD PHASE — the user's design, and the lean.** Flattening the
    objective does not end the sortie; it starts a clock. You **guard the ground**
    while friendly forces move in to take control, and the enemy — predictably,
    in war — pushes to reclaim it before they arrive. Capture is then a **task you
    completed**, not a state you survived: if you die during the hold, allies
    never arrived, the node is wrecked but not yours, and that is one outcome for
    one failure rather than two penalties for one death.
  - **Why (b) is the better shape, beyond the fairness argument.** It gives
    triggered reserves the job they do not currently have — today they arrive and
    then the sortie ends, which is exactly the pacing bug v2.01 fixed and only
    half of what reserves are for (P2.3). It replaces "fly 105 m from the centre"
    with an ending that reads in fiction rather than as a distance check. And it
    makes W.q3's third outcome fall out of the mechanic instead of needing its own
    rule.
  - **The risk, stated plainly:** a hold is a DEFEND task, a different skill from
    the strike that preceded it, and a timer with nothing attacking is the most
    boring thing this game could contain. (b) only works if the hold is when the
    pressure PEAKS — which means the reserve budget belongs there, not before it.
  - **Not necessarily every sortie** (user): a hold suits contested ground and
    would be noise on a deep raid nobody intends to occupy. Likely an
    archetype-level or capture-flag-level property rather than a global rule,
    which the composer is already shaped to express.
  - **Deliberately NOT decided, and nothing is built against it.** It touches the
    egress, the capture gate, the reserve budget and the death path at once, and
    three of those are load-bearing. The next honest step is the war room (P1.8),
    because "allies move in and take control" is only legible if there is a map
    that shows them doing it.

### W steering — ANSWERED IN PART (2026-07-31, same day)

Four of seven resolved, all to their leans; W.q2/W.q4/W.q7 gate later phases and
are deliberately left open until a sortie has actually been flown.

- **W.q6 → DECIDED: one id, `gnat`, everywhere.** The wave director's `gnats`
  key is renamed to match `default_enemy_gnat.tres`, `EnemyConfig.type_id` and
  `WarManifest.ROSTER` — the id every other system already keys off. A check
  asserts that **every** `WarManifest.ROSTER` entry resolves to a real scene, so
  the class of bug is closed rather than this instance of it. No translation
  table: a lookup between two spellings is a place for a typo to live forever,
  in the one spot standing rule 2 says is invisible from a results table.
- **W.q1 → DECIDED: a new `scenes/sortie.tscn`.** `main.gd` owns the M4 run's
  whole lifecycle and a campaign sortie differs at every step of it; `dev_map`
  and `city_map` are the standing precedent for scenes that mirror main's wiring
  instead of extending it. The cost is accepted knowingly — shared plumbing
  (HUD, cameras, damage feedback) will want extracting once the duplication is
  real rather than anticipated.
- **W.q3 → DECIDED: destroy, then EGRESS.** Killing the objective opens the way
  home; the sortie ends when you are back out past the line you came in on. It
  is the only option under which an `objective_damaged` reserve means anything —
  under "destroy = success" it arrives to an empty sky, which would make W6's
  entire distinction between a wave and a reserve decorative. It also gives
  P2.9's spectrum somewhere to put **"got it, didn't get home"**, which is a
  genuinely different outcome from both a clean success and a failure, and one
  the war-sim can price.
- **W.q5 → DECIDED: hot white.** The one unclaimed slot in the emissive palette,
  and it reads as *the thing you came for* rather than borrowing a role. Red was
  rejected for the specific reason that a building and a raider would then read
  identically at a glance — the one confusion that costs a whole sortie. The
  unlit-structure alternative is recorded as the braver option and declined for
  now: P2.7 forbids quest markers, so an objective the neon does not claim could
  be genuinely unfindable in a dark city, and that failure mode is discovered by
  a human wasting four minutes.

---

## Iteration 13 — C: The War Room (PROPOSED, 2026-08-01 — user-initiated)

> **The campaign is playable and has no face.** A theater generates, a node
> composes, a sortie flies, the result prices back into the war, the war ticks,
> and the state saves — and every one of those steps reports to a console the
> player never sees, while choosing where to fly is a command-line flag. This
> iteration proposes **no new systems**. It is the screen P1.8 has been
> describing since Iteration 1. Sections **C1–C10**, open questions
> **C.q1–C.q7**; react by ID.

### C1 — The thesis: the cheapest big feature this project will ever build

Every other iteration built a system and then found out whether it was any good.
This one builds a **view** of systems that are already correct, already
deterministic, already covered by checks, and already printing the exact numbers
the screen has to show. `sortie.gd` prints a full briefing before you arm and a
full debrief after you land. `WarManifest.project()` already produces the
intel-fogged garrison estimate an inspection card would show. `WarSave` already
does F4's portable file, byte-exactly.

The risk profile is therefore inverted from every previous iteration: the danger
is not that the war room will be wrong, it is that it will be **big**. C9's cut
exists to keep it small.

### C2 — The inventory, counted rather than remembered

| P1.8 asks for | the data | who computes it today | the screen |
|---|---|---|---|
| nodes, ownership | `state["nodes"]` | `TheaterGenerator` | none |
| hex adjacency, front line | `hex_distance` | `TheaterGenerator` | none |
| supply edges | `WarSim._supplied_set` | `WarSim` | none, **and private** |
| airbase range rings | `WarSim._strike_range` | `WarSim` | none, **and private** |
| weather per node | `node["weather"]` | `WarSim` | none |
| intel freshness | `node["intel_age"]` | `WarSim` | none |
| garrison estimate | `WarManifest.project` | `WarManifest` | none |
| the intel card's fog | `WarManifest.through_fog` + `SortieComposer.compose_briefing` | both | **never called outside tests** |
| 1-tick forecast | — | **nothing** | does not exist — C.q4 |
| pilot roster (F1) | `state["pilots"]`, an `int` | `TheaterGenerator` | none |
| hangar (P3) | `MenuLaunch.frame_id` | the menu tower | exists, in another scene |
| briefing | `sortie.gd._print_briefing` | console | console only |
| debrief | `sortie.gd._on_sortie_finished` | console | console only |
| the tick as animated map movement | — | **nothing** | does not exist |
| save / exit anywhere, one file | `WarSave` | `WarSave` | **done** |

Two rows carry the whole engineering cost: the **forecast** and the **tick
animation**. Everything above them is reformatting text that already exists, and
everything below is done.

**The briefing half of P2.1 has been correct and invisible since v1.71.**
`compose_briefing` and `through_fog` are called by `sortie_compose_check`,
`manifest_check` and `sortie_trace` — three tests and a bench. No human has ever
seen the fog work, which means the designed surprise P1.3 promises has never once
been delivered to a player.

**The war-side API change is two `_` characters.** `_supplied_set` and
`_strike_range` are private only because nothing outside the sim had needed them,
and both are exactly what a map draws; `war_trace` already reaches through the
underscore to call one. Publishing them is the entire change this iteration makes
to `war/`.

**The war room adds ZERO fields to `user://war.save`.** Nothing it shows is state
— it is all projection, derived on demand from the state that already exists.
`SAVE_VERSION` does not move, and every campaign in existence survives this
iteration. That is a design constraint, not an observation: any feature that
wants a new save field (named pilots, C.q7) is out of the cut.

### C3 — What the room physically IS (the fork that decides the cost)

Three shapes, and they are not equally expensive:

- **(a) A flat 2D screen.** `Control` nodes, hexes drawn with `_draw()`.
  Cheapest, most readable, most legible for text-heavy panels, and the one that
  looks least like this game.
- **(b) A 3D hex table under a fixed camera, with 2D panels on top.** Hex prisms
  on a plane, the look pass and `neon_structure.gdshader` already applied,
  `GlowText3D` labelling each cell — the B5 primitive already renders A–Z and
  0–9, because the resupply gates needed numerals in v1.92. Selection is a
  raycast from the camera through a cursor. It costs a little more than (a) and
  buys **garrison as prism height**, which is the single most useful thing a
  strategic map can encode.
- **(c) A flyable map room.** The drone hovers over the table; you pick a node by
  flying at it. Maximally diegetic, continuous with B5's flyable menu — and it
  taxes every one of P1.q5's 25–40 sorties with a flight to a menu item.

The tension is that B5 established this project's taste for diegetic menus, and a
war room is the one menu you use constantly. A menu tower is delightful once per
session; a war map is opened between every sortie.

**(b) is the lean**, and it is the compromise rather than the middle: it reads as
this game, it reuses shaders and a font primitive that already ship, it makes
garrison legible without a number, and the map is *data* either way — the
renderer is swappable, so (c) remains available later as a re-skin rather than a
rewrite. C.q1.

### C4 — The map, drawn

One formula, matching `TheaterGenerator`'s axial coordinates so the picture and
the graph cannot disagree (pointy-top):

```
x = size * sqrt(3) * (q + r / 2.0)
z = size * 1.5 * r
```

What each visual channel carries — deliberately assigned rather than decorated,
because a strategic map with six overlapping encodings is a map nobody reads:

| channel | meaning | source |
|---|---|---|
| fill colour | owner (player / enemy / contested) | `node["owner"]` |
| prism height | garrison strength | `node["garrison"]` |
| glyph | node type (P1.2's nine) + node id | `node["type"]`, `node["id"]` |
| rim glow | selectable this turn (in range, enemy-held, slice-ready) | derived |
| dimmed | out of strike range | `WarSim.strike_range` |
| edge line | supply connection | `WarSim.supplied_set` |
| heavy edge | the **front line** — an edge whose two ends differ in owner | derived |
| corner marks | weather, intel age | `node["weather"]`, `node["intel_age"]` |

The **front line is not drawn by the generator** (P1.1 is explicit about this) —
it is the boundary between owners, so it is computed from ownership every frame
and moves because the war moved.

**The map must be honest about the fifteen nodes it cannot fly.** With
`SLICE_ARCHETYPES` at two, half a theater composes correctly and cannot be
instantiated. Drawing those nodes as though they were targets would be the map
lying; hiding them would make the theater look half-sized and make the eventual
archetype work look like new territory rather than unlocking existing ground.
The lean is **drawn, inspectable, and refused at the launch button** with the
reason stated on the card. C.q3.

### C5 — The inspection card: where P1.3's fog finally reaches a human

`compose_briefing(node, state, config)` already returns everything the card
needs, already fogged. The card renders exactly what the spec says and **never
reaches past it to the truth**:

| intel age | `garrison_detail` | the card shows |
|---|---|---|
| ≤ 1 | `exact` | the named unit list, counts and all |
| 2–5 | `families` | air / swarm / static, by strength |
| > 5 | `strength` | one abstract number, which is all the war-sim itself keeps |

That last row is the design working: degrade intel far enough and the briefing
regresses to precisely the number the sim trades. The card also carries
archetype, objective, asset count, **pads** (the pilot's single most important
planning fact, and derived rather than authored), capture-or-degrade, weather,
and the H.q2 difficulty input vector — **never a difficulty score**, because H6
says SDI is measured by the harness and never authored, and a card that printed
one would quietly become the thing designers tune.

This is the one place in the room where a bug is invisible: a card that
accidentally shows truth still looks perfect. So the check for it is a
**mutation**: feed a node at `intel_age` 99 and assert no unit type name appears
anywhere in the card's own text.

### C6 — The forecast is not free, and pretending otherwise would be a lie

P1.6 promises a 1-tick weather forecast — *"the SAM site is blind in tomorrow's
fog"* — and it is the one P1.8 item with no data behind it. Weather is re-rolled
inside `_weather_and_intel` from the war's **shared RNG stream** at 15% per node
per tick. Predicting it means drawing from that stream, and drawing from it moves
the war.

The cheap honest answer: **run a tick on a deep copy.**
`state.duplicate(true)` → `WarSim.tick(copy, config)` → read the copy's weather.
The state is a plain Dictionary by construction, the sim is pure, and a copy's
`rng_state` advances in the copy alone. It costs one tick of arithmetic and needs
no change to the war at all.

Two caveats, both stated on the card rather than hidden: the forecast is *"if you
fly nothing"* (your own sortie dents a garrison before the tick and changes what
the enemy does with it), and the same dry run knows the enemy's next move — so
the room must read **only weather** off it. Showing the rest would hand the
player a perfect oracle and delete the fog this iteration exists to reveal. C.q4.

### C7 — The loop comes home, and the death path closes with it

Today `sortie.gd` owns the campaign loop: it loads the war, composes, flies,
applies the result, ticks, and saves. That was right when the sortie scene was
the only thing that existed. With a room, it is the wrong owner, for a reason
that is not tidiness:

**P1.8's sequence is `briefing → fly → debrief → the tick plays out as animated
map movement`.** The tick must happen where the map is, or the animation is
replaying something that already happened somewhere else.

So the proposal: the room owns `apply_sortie` → debrief → `tick` → animate →
`save`. `sortie.gd` hands back its `result()` through a cross-scene static
(`WarLaunch`, exactly the `MenuLaunch`/`RunMods` pattern) and stops touching the
war. Three things fall out of it for free:

1. **The death path closes** (P5.4, and the gap v2.02 refused to plaster). A
   dead pilot's sortie resolves, the room takes the pilot off the roster, and you
   redeploy from Home Airbase — because there is now a Home Airbase to redeploy
   from. The arcade respawn leaves the sortie scene entirely.
2. **P1.q4's two doors become buildable**: *exit without save* is "return to the
   room without handing back a result", and the war reverts to its last saved
   state by doing nothing at all.
3. **A quit mid-sortie loses the sortie**, which is not a bug — it is exactly
   what P1.q4 decided *exit without save* should mean.

**`scenes/sortie.tscn` must keep working standalone.** It is the repro command in
TESTING.md and the thing a human flies to check a fix. So the result always goes
to the static, and when no room launched it, the scene resolves the war itself
exactly as it does today — one `if`, and the check has to exercise **both** legs
or the standalone path rots silently.

Note for C.q6: `SortieRunner.abort()` sets `_pilot_lost = true` unconditionally,
so an abort currently costs a pilot. That is correct for a death and wrong for a
retreat, and it is a one-line distinction that has to be made *before* an abort
button exists, not after.

### C8 — The tick animation, without teaching the sim to narrate

The obvious implementation is to have `WarSim.tick` emit an event list. That
would be a mistake: it puts presentation concerns inside the one module whose
purity is load-bearing for determinism, the save, and the soak.

The alternative costs nothing: **diff two snapshots.** Deep-copy the state before
the tick, tick, and compare. Ownership flips, garrison deltas, front-line
movement, weather changes and intel decay are all visible in the difference, and
the differ lives in the room where it belongs. `war/` stays pure and the animation
can never disagree with the state, because it is derived *from* the state.

The animation itself is deliberately modest in the cut: sequenced pulses on the
nodes that changed, ownership fills that sweep, and the front line redrawing
last, because the front line moving is the thing the player is actually watching
for. It is the moment P1.8 calls *"the theater being alive"*, and it is the one
piece of this iteration that is genuinely new work.

### C9 — The build cut (five phases, each shippable, each with a check that can fail)

The standard v2.01 wrote and did not keep applies to every one of these: *would
this check still pass if the feature it tests were deleted?*

| phase | what ships | the check that can fail |
|---|---|---|
| **1 — the map that reads** | `scenes/war_room.tscn`, hex layout, ownership, front line, supply edges, range, cursor selection. No launching. | `war_room_check` A: every node gets a distinct cell; the room's derived strike-range set **equals** `WarSim.strike_range`; front-line edges are symmetric; the selectable set equals in-range ∧ enemy-held ∧ slice-ready |
| **2 — the card** | inspection card off `compose_briefing`, all three fog tiers, pads, difficulty inputs, weather | B: **mutation** — at `intel_age` 99 no unit type name appears in the card's text; at 0 they all do |
| **3 — the loop comes home** | `WarLaunch`, launch → fly → return, `apply_sortie` + `tick` + `save` in the room, **death path closed**, standalone `sortie.tscn` preserved | C: a handed-back result decrements pilots exactly once and saves once; a death still dents; the standalone leg still resolves without a room |
| **4 — the tick animation** | snapshot diff → event list → played on the map | D: the diff of a known before/after pair names exactly the nodes that changed and nothing else (mutate the "after" and assert it is caught) |
| **5 — roster, hangar, entry** | pilot count, frame pick, a CAMPAIGN leaf on the menu tower, save/exit anywhere | `menu_check` extension: the leaf resolves to a real scene |

Phases 1–3 are the vertical slice — after 3 the campaign is playable end to end
with no command line anywhere. 4 and 5 finish P1.8.

### C10 — What this iteration deliberately does NOT contain

- **The other five archetypes.** Named as the next job after this one, and
  deliberately second: opening them first only makes an unflyable map bigger.
- **W.q8's hold phase.** Still unresolved, still untouched. This iteration is
  the thing W.q8 was waiting for — *"allies move in and take control"* is only
  legible once a map can show them doing it — so it should be re-asked **after**
  the map exists, not answered inside this proposal.
- **P5's economy.** No salvage, no purchases, no intel buying, no influence
  actions. The room will have obvious places to put all four and must not grow
  them speculatively.
- **Weather simulation.** `WeatherConfig` is still a stub; the room *displays*
  weather and forecasts it, and nothing yet flies differently because of it.
- **F4.a spectator mode.** A won or lost war shows a banner. The war continuing
  to tick without you is a later, lovely thing.

### C open questions (react by ID)

- **C.q1 — What is the war room, physically?** (a) a flat 2D screen; (b) **a 3D
  hex table under a fixed camera with 2D panels over it** ← lean; (c) a flyable
  map room you pick nodes by flying at. See C3. The lean buys garrison-as-height
  and reuses shaders and `GlowText3D` that already ship, while keeping (c)
  available later as a re-skin — the map is data, the renderer is not the design.
- **C.q2 — Who owns `apply_sortie` → `tick` → `save`?** (a) **the war room** ←
  lean (C7: the tick must happen where the map is, and the death path and P1.q4's
  two doors fall out of it); (b) `sortie.gd` keeps it and the room re-reads the
  file afterwards, which is less code and cannot animate a tick it did not run.
- **C.q3 — The fifteen nodes the slice cannot fly.** (a) **drawn, inspectable,
  refused at the launch button with the reason on the card** ← lean; (b) hidden
  until their archetype ships, which makes the theater look half-sized; (c)
  resolved abstractly by the proxy sortie, which quietly puts a coin-flip in
  charge of half the campaign.
- **C.q4 — The 1-tick forecast.** (a) **dry-run tick on a deep copy, read weather
  only** ← lean; (b) no forecast in this cut, and P1.6's promise waits; (c) give
  weather its own per-node RNG stream so a forecast is a pure function — the
  cleanest long-term answer and a save-shape change, which C2 rules out of this
  iteration.
- **C.q5 — Where does the campaign live in the menu?** (a) **a new CAMPAIGN leaf
  on the menu tower; START RUN stays the arcade run** ← lean, and it is W.q2's
  answered "both" made concrete; (b) the campaign replaces START RUN, which
  deletes the mode every bench and every balance factor was measured inside.
- **C.q6 — Death only, or death and abort?** (a) **death in this iteration,
  abort in the next** ← lean; the death path is the gap that has been explicitly
  waiting, and abort needs P5.6's salvage forfeit to have a price to charge; (b)
  both now, accepting that abort's cost is a placeholder. Either way
  `SortieRunner.abort()` must stop conflating retreat with death first.
- **C.q7 — Named pilots, or a count?** (a) **the count that already exists** ←
  lean; F1's roster becomes interesting when pilots accumulate history, and
  history is a save-shape change this iteration has ruled out; (b) named pilots
  now, `SAVE_VERSION` 2, and every existing campaign moved aside on load.

### C steering — ANSWERED (2026-08-01, same day)

Four decided by the user, three taken to their leans and reversible until the
phase that needs them.

- **C.q1 → DECIDED: the 3D hex table under a fixed camera** (C3's lean b). Hex
  prisms with **garrison as height**, `GlowText3D` labels, the shipped neon
  shader and look pass, selection by cursor raycast; text panels stay 2D over the
  top. The flyable version (c) is not rejected so much as **deferred by
  architecture**: the map is data and the renderer is one file, so it stays a
  re-skin rather than a rewrite.
- **C.q2 → DECIDED: the war room owns `apply_sortie` → `tick` → `save`.**
  `sortie.gd` hands its result back through a cross-scene static and stops
  touching the war, except on its standalone leg, which TESTING.md's repro
  command depends on and which the check must exercise separately or it rots.
- **C.q3 → DECIDED: the unflyable nodes are drawn, inspectable, and refused at
  the launch button with the reason on the card.** Half a theater composes
  correctly and cannot be instantiated; a map that hid that would make the
  eventual archetype work look like new territory instead of unlocking ground
  that was always there.
- **C.q4 → DECIDED: weather gets its own dice** — option (c), **and the proposal
  above priced it wrongly.** C6 and C.q4 assert that a per-node weather stream is
  a save-shape change ruled out by C2. **It is not.** The seed, the node id and
  the tick are all already in the state, so the change is the same throwaway-RNG
  pattern `sortie_seed` and `WarManifest._weights` already use: seed a local
  generator from (theater seed, node id, tick), keep the same 15% odds and the
  same weather table, and only the *source* of the dice moves. `SAVE_VERSION`
  does not move and no campaign dies.
  - **What that buys is the removal of a trap, not just an exactness.** Under
    (a)'s dry-run tick the room would compute the enemy's entire next turn and
    then have to throw all but the weather away — one future line showing
    "predicted enemy attacks" and the game hands the player an oracle that
    deletes the fog this iteration exists to reveal. Under (c) the enemy's turn
    is never simulated, so there is nothing to leak: the forecast is
    `weather_at(node, tick + 1)` and it knows nothing else.
  - **The honest cost, stated:** pulling weather out of the shared stream shifts
    every draw after it, so a war in progress evolves a different weather
    sequence from the moment the change lands, and `war_soak`'s numbers move a
    little. Determinism is untouched — same seed, same war — and the soak asserts
    invariants rather than specific values, so this is a re-run, not a re-measure.
- **C.q5 / C.q6 / C.q7 → taken to their leans, provisionally**, because each
  gates a phase that has not started: a CAMPAIGN leaf beside the arcade run,
  death in this iteration with abort in the next, and the pilot count rather than
  a named roster. Any of the three can be re-steered before its phase without
  costing work already done.

## Decision Log

- **2026-07-14 — v0.** Opening proposal: north star, M6 triage draft, core idea
  (living theater), pillars P1–P5, balance methodology, vertical-slice
  discipline, forks F1–F4 posed.
- **2026-07-15 — v1.** First steering pass (user review) folded in:
  - **F1 decided** — reinforcement-pilot lives economy (1-ups; pilots as
    rewards; out-of-pilots = campaign loss). Sub-questions F1.a (difficulty
    model), F1.b (death costs tempo) opened.
  - **F2 decided** — turn-based war ticks; "battle command room" between
    sorties. Falcon 4.0 confirmed as continuous/real-time — our nodes are a
    deliberate abstraction.
  - **F3 decided** — kinetic-first; commander mode deferred, later enters as an
    acquirable capability (reward/purchase).
  - **F4 decided** — long persistent war; single portable/shareable save file;
    war-sim must be deterministic + serializable. Pinned: F4.a spectator mode,
    F4.b multiplayer (far future).
  - **M6 triage resolved** — radio (TX16S) pulled forward as the only "do now";
    wind expanded into a Weather group under P1; physics items grouped and
    deferred (turtle mode unnecessary with 3D mode); overlay QoL partially
    pulled forward; replays sit as-is (debug value proven); VR parked.
  - **P3 clarified** — hardpoint profile (frame capacity) vs. loadout
    (per-sortie choice); intel-driven acquisition endorsed.
  - **P4 extended** — bombers as ticking bombs; naval domain as post-core
    expansion (sea control enables ground invasions).
  - **P5 flagged** — awaiting user feedback (empty section in the review pass).
  - **Process** — doc adopted as permanent history/changelog; iteration order
    proposed (P1 first).
- **2026-07-16 — v1.1.** Second steering pass folded in + Iteration 1 opened:
  - **F1 refined** — out-of-pilots is the *player's* defeat, not the war's end:
    the war-sim keeps running; defeat becomes an epilogue via F4.a spectator
    mode (see P1.5).
  - **F1.a direction** — global scaling knob acceptable, but *real* difficulty
    is an inherited quality of the war (organic + adaptive escalation, never
    silent stat inflation); hard constraint: feasible newbie learning curve
    (niche genre combo). Addressed in P1.7; final call still open.
  - **F1.b** — recorded as a cheap tunable knob (default off); decide with
    P1/P5 numbers.
  - **P5 endorsed in full** (the empty v1 feedback section was agreement).
  - **Radio scope** — basic capabilities only, to experience the physics on the
    TX16S; gamepad expected to remain the primary fun controller.
  - **Iteration 1 opened** — P1 Living Theater proposal written (P1.1–P1.8 +
    open questions P1.q1–q5), status PROPOSED, awaiting steering.
- **2026-07-16 — v1.2.** First real-radio combat session (TX16S validated:
  "so responsive and super smooth — so much different than a controller"):
  - **P3 extended — Fire-Control Systems (FCS)**: semi-auto fire as an
    equipment family; positioning becomes the skill, aim assist becomes
    acquirable gear (never an abstract mode), EW counters it in the web.
    Ballistic fire-assist prototype shipped behind CombatConfig knobs
    (`fire_assist_miss_m`, `fire_assist_range`; 0 = off).
  - Input-bindings system + `arm_switch` shipped the same session (see
    ROADMAP M7 Input) — the "flexible binding layer" from the M6 triage.
- **2026-07-16 — v1.3.** Radio combat ergonomics, round two:
  - **P3/FCS extended — missile director**: stateful `missile_auto` switch;
    stable full lock for `missile_auto_hold_s` auto-launches. Lock HUD made
    unmistakable (pulsing double diamond + LOCK + director arc).
  - **Counter-web note confirmed**: EW/jammers jam FCS (gun + missile
    directors alike) — user-endorsed.
  - Standing finding: mixing manual fire control with acro flight on a real
    radio is hard — FCS is the deliberate gameplay answer, per the "assets,
    not modes" rule.
- **2026-07-16 — v1.3.1.** Terminology (user): the missile-director binding is
  `missile_auto_switch` — it's a two-position stateful switch exactly like
  `arm_switch`, and the name should say so. Saved binding configs carrying the
  old `missile_auto` key migrate automatically on load.
- **2026-07-17 — v1.4.** Pause mode + weather stub (user ideas):
  - **Pause = BeamNG-style slow-mo** (`pause_time_scale`), not a hard stop —
    time crawls as far as the sampling rate allows. Bindings gain a **second
    context** (paused): gameplay actions unbound there by default, so overlay
    typing is safe; players can deliberately bind slow-mo controls. System
    actions (pause/overlay) always stay live from the flight set. **Autopilot**
    holds position while paused (level-and-brake + hover collective) — player
    agency preserved while time crawls. Candidates for later gameplay use:
    slow-mo as an acquirable ability ("reflex module"?), autopilot as an
    equipment tier — parked, not designed.
  - **WEATHER overlay group added as an explicit TODO stub** (WeatherConfig:
    wind heading/speed/gust, precipitation, fog, heat) — persisted, tunable,
    driving nothing yet; exists to entice the P1.6 implementation.
- **2026-07-17 — v1.5.** Feedback batch (bug + polish + back-burner ideas):
  - **Bug fixed** — unpausing disarmed the drone: Godot's action state is
    event-driven, so stateful switches held through the binding-context swap
    read as released. InputBindings now re-derives stateful switch state from
    raw hardware after every apply (`STATEFUL_ACTIONS` sync).
  - **Pause muffle shipped** — Master-bus low-pass while slow-mo is active
    (`pause_muffle_hz`, AudioConfig): the stepped-out-of-the-club effect.
  - **Exit gate presence** — bigger, thicker frame + an animated additive
    portal-vortex shader filling the opening; it now reads as a doorway out
    of the world, which is what it is.
  - **P1.9 added — node biomes** (user concept): environment archetypes
    (cyberpunk city, factory sprawl, fortified airbase, desert, green-hill
    ruins, coastal cliffs, canyon/megastructure) as data-driven env config
    sets; node type × biome is the variety multiplier.
  - **Pinned — diegetic building-menu** (user concept, ROADMAP M7): menus
    rendered by the game engine as buildings seen side-on — the menu tree
    locally flattened left-to-right (parent building ← current ← selected
    child), a building's floors = its menu items; an AI-run battlefield
    (F4.a war-sim!) plays behind the title screen for character.
  - **Audio direction** — a high-ROI sound sweep is queued (ROADMAP M7):
    richer motor synthesis (harmonic stack + blade-pass tone driven by the
    motor model's live outputs), doppler on projectiles/missiles, low-health
    and lock/draft UI audio. **engine-sim (community edition) evaluated and
    declined**: it models combustion engines (pistons/exhaust — wrong physics
    for brushless electric quads), it's a standalone GPL C++ app (license
    contamination + no clean Godot embedding), and our motor audio is already
    physically driven by motor outputs — the *idea* (physics-driven audio
    synthesis) is adopted, the dependency is not.
- **2026-07-17 — v1.6.** Iteration 1 STEERED (user review) + a rich feedback
  batch folded in:
  - **P1.q1–q5 all answered** — see "P1 steering — ANSWERED": ~30-node
    default with a 20–40 lever; capture requires supply-connected assault
    (deep strikes only degrade) and enables diversion-attack strategy;
    allied defense always, allied offense only via P5 influence orders (the
    synthesis of both views); mid-sortie exit gets two doors — plain
    exit-without-save (revert to war room) and in-fiction **abort mission**
    (war ticks anyway; context-priced); 25–40 sorties per campaign.
  - **P1.7 guardrail** — adaptive escalation must never punish excellence:
    capped by what the enemy fictionally has left; a broken enemy stays
    broken.
  - **P1.8** — theater map renders as **hexagons** (beehive); hex adjacency
    doubles as the war-sim graph.
  - **P2 extended** — sortie scale ("the land itself becomes a very big
    effect": approach-phase structure, terrain as cover economics, biome-
    driven geometry); **repair/re-arm landing pads** as difficulty knobs and
    capturable assets; **dares** — one-time opportunistic skill challenges
    (fly the impossible gap, earn a unique reward) generated from biome
    geometry, announced without quest markers.
  - **P3 extended** — the Firehawk charge-shot lesson becomes doctrine:
    design FOR emergent tactics with prices and counters (indirect fire as a
    deliberate archetype); weapon roster to be defined along explicit axes
    (trajectory / fire model / economy / FCS compatibility / counter-web
    role).
  - **Next step proposed** — pull the **war-sim skeleton + theater soak
    harness** forward: implement P1's module headless (generation, tick, AI,
    win/loss, serialization) with abstract garrisons, run hundreds of
    seeded theaters to completion unattended, and validate the war's shape
    with data before Iteration 2 (P4) locks the bestiary.
- **2026-07-17 — v1.6.1.** Back-burner log (user): **interactive tutoring** —
  the game will grow complex enough to confuse; plan an opt-outable teaching
  layer that intervenes in-gameplay on first encounters (slow/freeze time,
  blur, one concise hint — visual cues preferred over text). The shipped
  pause/slow-mo + muffle machinery is the natural delivery vehicle. Parked
  for a late dev cycle (ROADMAP M7); next-step greenlit: **the war-sim
  skeleton is a go.**
- **2026-07-17 — v1.7. THE BIRTH: the war-sim skeleton lives.**
  `scripts/war/` (theater_generator + war_sim, pure deterministic modules
  over a serializable state Dictionary) + `war_soak.gd` (invariant soak:
  200 theaters fight themselves) + `war_trace.gd` (single-war trace). All
  invariants green: **determinism** (same seed = same history),
  **lossless portable saves** (F4 proven from day one), **spectator
  losability** (without you the enemy wins 33/40, median collapse 21 ticks —
  thematically perfect), **skill-monotonic outcomes**. The tuning loop
  itself produced doctrine, each finding forced by data:
  - **Anti-treadmill targeting** — never re-bomb rubble you can't capture.
  - **Decisive assaults** — a WON assault sortie IS the node cleared
    (matching what the M4 loop actually means).
  - **Frontier-projected strike range** — friendly ground is staging; reach
    projects `sortie_range_hops` beyond the front line, or drives starve.
  - **Decapitation doctrine** — without explicit command-post priority,
    campaigns conquer half the map and stall forever at a locked HQ.
  - **P5 influence orders are load-bearing** — idle allied mass (700
    strength watching the pilot fight alone) made wars unwinnable until
    the proxy could order allied offensives; the q3 synthesis is not
    optional flavor, it's structural. *Design validated by simulation.*
  - **The escalation clock kills stalemates** (P1.7 confirmed).
  Honest current calibration: skill 0.9 wins ~10% at ~127 sorties (vs the
  25–40 target) — the war is brutal; recalibration deferred until P4/P5
  replace abstract garrisons with real systems.
  Same-day playtest findings (sortie-18 radio run): **draft economy inverts
  difficulty** (fire-rate scaling + one Self-Repair pick ≈ invincible;
  regen nerfed 1.5→0.7 as a stopgap — the real fix is the P5 economy
  iteration); **sticky missile lock** shipped (1.5× cone hysteresis — locks
  are lost by escape, not stolen by crowds); the crowd-lock chaos had
  already birthed a real emergent strategy (isolate one bandit, kill, next)
  — a Firehawk-doctrine exemplar worth preserving, not patching away;
  **arcade mode** idea logged (ROADMAP M7): a dedicated mode growing from
  the dev room as capabilities grow.
- **2026-07-17 — v1.8.** Iteration 2 opened — **P4: Bestiary +
  counter-matrix proposal written** (P4.1–P4.10 + open questions P4.q1–q6),
  status PROPOSED, awaiting steering. Highlights:
  - **The design grammar** — enemies defined along fixed axes; threat
    vectors tax distinct player resources (hull / position / time / systems
    / economy / the war); a **damage grammar** of four durability models
    (light / shielded / armored / distributed) × three damage styles (chip /
    burst / area) as the web's mechanical heart; readability doctrine
    (telegraph everything; reaction-dodgeable fire) proposed as a locked
    rule.
  - **Ten-type roster** with stat blocks — air: Gnat (swarm), Raider (the
    shipped EnemyDrone, canonized — isolate-one-bandit preserved as intended
    play), Falx (pursuit interceptor, the designed anti-camper), Aegis
    (shielded ticking-bomb bomber), Screamer (EW escort, the FCS counter);
    ground/static: Turret (shipped, canonized), SAM battery (staged-telegraph
    area denial with a dead zone), Convoy (supply interdiction prey),
    Commander (coordination multiplier, decapitation payoff), Sentinel
    (radar dish — the clock as a weapon). Naval rows still reserved.
  - **The counter-matrix v0** — 10 enemies × 6 answer archetypes (chip gun /
    burst / lob / missile / flak / terrain-as-a-column), with three
    falsifiable invariants (every row a `++` and a `−`; every column a `++`
    and a `−−`; no column dominance) to be re-verified numerically forever
    by the matchup harness (paper matrix = spec, measured matrix = test).
  - **Frame-class pressure table** — garrison mix prices frame choice at
    briefing (intel → frame, P1.3 feeding P3).
  - **Escalation mechanics** — veterancy tiers (smarter, never spongier or
    twitchier) + mix shifts, capped by surviving tagged production: a broken
    enemy stays broken *by supply arithmetic*.
  - **Strategic integration** — garrison strength stays the war-sim
    currency; composition becomes a deterministic *projection*
    (seed × node × strength × tier → manifest), so P1.3's unit lists arrive
    without touching the proven portable save; factory product tags give
    strikes surgical meaning; intel decay regresses manifests back toward
    the abstract number.
  - **EnemyConfig** (`TunableConfig` per type + overlay BESTIARY section)
    specced; CombatConfig's `enemy_*`/`turret_*` groups to migrate into
    `raider.tres`/`turret.tres`.
  - **Vertical-slice four**: Raider + Turret (shipped) + Gnat + Aegis, with
    flak as the natural third weapon; Screamer enters alongside acquirable
    FCS gear.
- **2026-07-17 — v1.9.** Iteration 2 STEERED (user review):
  - **Water domain added (user)** — the P4.1 domain axis grows a fourth
    seat (surface/water), grounded minimally now: two sea-annex stat blocks
    (**Gunboat** patrol boat, **Barge** sea supply crawler) + their matrix
    rows. Full naval expansion stays post-core reserved; this lays its
    foundation. Roster: twelve. Design insight recorded: open water is the
    **no-cover domain** — the terrain column inverts at sea; coastal cliffs
    (P1.9) is the seam between the two cover economies.
  - **P4.q1 decided** — twelve archetypes + veterancy tiers is the 1.0
    surface; variety from tiers × biomes × combos.
  - **P4.q2 LOCKED** — reaction-dodgeability at every tier: elites get
    smarter positioning, never faster/straighter fire.
  - **P4.q3 decided** — terrain-only counterplay for homing threats at
    launch; countermeasures later as P3 equipment.
  - **P4.q4 decided** — commander buffs are behavior/coordination only,
    visibly lost on decapitation.
  - **P4.q5 decided** — gnats as kinematic boids + collision sting; the
    cloud is the unit.
  - **P4.q6 decided + pinned** — allied forces palette-swap the roster now;
    eventual faction identity = each identity fields *its own version of the
    same archetype seat* with real force-level differences (same matrix row,
    faction-specific tradeoffs). Pinned for the F3 commander-mode era.
  - **Next**: Iteration 3 — P3 (frames, hardpoint profiles, the weapon
    roster designed against the locked matrix).
- **2026-07-17 — v1.10.** Iteration 3 opened — **P3: Frames, Hardpoints &
  the Arsenal proposal written** (P3.1–P3.10 + open questions P3.q1–q7),
  status PROPOSED, awaiting steering. Highlights:
  - **Weapon grammar locked to the v1.6 axes** — seat (matrix column) /
    trajectory / fire model / economy / damage style / FCS compatibility /
    hardpoint class / web role; two honest economies (**heat** = time,
    **magazine** = pad re-arms — the loadout economy lands on landing skill).
  - **Hardpoint grammar** — S/M/H weapon slots + E equipment bays, per-frame
    mass budget, and **honest mass** proposed as a locked rule: mounted mass
    is real rigidbody mass (hangar shows predicted hover throttle); modifier
    stack stated once (frame → loadout → RunMods → weather).
  - **Four frames** — **Firehawk** (the shipped drone canonized as the
    all-rounder, name honoring the doctrine story), **Dart** (light
    interceptor, dare-chaser), **Atlas** (heavy gunship, innate armor,
    emergent FCS-platform synergy), **Shade** (stealth recon — signature
    model + overflight intel refresh; P1.3's recon flights get their
    airframe). Frame × enemy pressure table extended to the full twelve-row
    roster; frames ≠ rate presets (orthogonal, each frame carries its own
    FlightConfig).
  - **Five weapons, one per matrix seat** — Blaster (chip, canonized, gains
    heat), **Lance** (charge burst — the Firehawk homage as a real weapon),
    **Mortar** (deliberate indirect fire, manual-only, falx-priced),
    Missile (canonized), **Flak pod** (proximity-fused area; screamer
    degrades its fuse to contact-only — EW pressures every computed
    solution uniformly). Second instantiations per seat reserved post-1.0.
  - **E-bay roster** — iron trigger (free, unjammable) → gun director
    (canonizes `fire_assist_*`) → lead computer → missile director
    (canonizes `missile_auto_switch`) → turret pod (off-boresight, eats an
    S slot); flare/chaff explicitly later-tier (P4.q3 honored); ammo/battery
    /armor/recon-suite utility picks.
  - **Harness gains the player axis** — weapon × enemy and frame × enemy
    measured matrices against the paper spec targets; Firehawk's column must
    *stay* flat.
  - **Configs** — FrameConfig + per-frame FlightConfig, WeaponConfig,
    EquipmentConfig `.tres`; overlay HANGAR + ARSENAL sections; CombatConfig
    dissolves toward weapon files; loadout = serializable dict (F4-clean).
  - **Slice cut updated** — Firehawk + Atlas; Blaster + Missile + Flak pod;
    gun director as first acquirable with the screamer entering alongside
    it. Growth order sketched (Lance/Dart → Mortar → Shade → sea annex).
  - Prices and acquisition mechanics explicitly deferred to Iteration 4
    (P5).
- **2026-07-17 — v1.11.** Iteration 3 STEERED (user review). All P3.q decided;
  naming folded through the live proposal body (P3.1–P3.10):
  - **The all-rounder frame is renamed Kestrel** (was a v1.10 placeholder).
    **Hard rule (user, P3.q2):** the external game that inspired the
    charge-shot / indirect-fire doctrine is **never** the name of any QuadShot
    frame/weapon/system — it is credited once, quietly, as an *inspiration
    note* deep in the docs (end of P3.5). Locked historical sections that
    nicknamed the design lesson after it are left as-written (append-only);
    new text names the doctrine functionally.
  - **The burst weapon is renamed Charge cannon** (P3.q2: weapons get
    functional names; the v1.10 proper name retired).
  - **P3.q1** — Shade stays at 1.0 (four frames); the intel airframe earns its
    seat (P1.3 load-bearing).
  - **P3.q3** — honest mass is **pure**: mounted mass = real rigidbody
    mass/inertia, no feel-dampener; hangar shows predicted hover throttle.
  - **P3.q4** — per-weapon heat gauges at 1.0; shared-power pool parked.
  - **P3.q5 (delegated to me)** — the turret pod is **insurance, not
    autopilot**: proposed bounds locked (narrow cone, chip-only,
    jam-vulnerable, eats an S slot) + a low fire rate so it *chips* a passing
    falx and rarely kills outright, protecting the bait-and-overshoot skill;
    fire rate is the first harness knob if it ever trivializes falx days.
  - **P3.q6** — director-at-full-charge: the gun director releases the Charge
    cannon only at full charge on a solution (tap stays manual) — automating
    the trigger returns attention to flight (the FCS thesis on the burst
    seat); the screamer keeps it honest.
  - **P3.q7** — Mortar manual-only at 1.0; ballistic computer is acquired, not
    given. This crystallizes a **locked doctrine: *enrichment is acquired, not
    given*** — the campaign hands a baseline (Kestrel + Blaster + Missile) and
    makes everything that makes you *better* an earned purchase/salvage/dare
    reward; **the dev room alone is fully stocked** (it's the testbed). The
    doctrine now anchors the P5 economy iteration.
  - **Next**: Iteration 4 — P5 (economy, rewards, pilots (F1), influence
    actions — pricing everything P1/P4/P3 defined).
- **2026-07-17 — v1.12.** Iteration 4 opened — **P5: The Reward Economy &
  Influence** proposal written (P5.1–P5.11 + six open questions P5.q1–q6),
  anchored on the v1.11 doctrine *enrichment is acquired, not given*. Per 2.4 it
  fixes the economic *grammar*, not absolute numbers (every price is a config
  field, harness-tuned):
  - **Three resources on two walled loops + a life (P5.1):** **salvage**
    (tactical — dropped by combatants, buys arsenal/repair/re-arm), **influence**
    (strategic — from captures/command-breaks/"war itself" kills, buys war-tick
    actions), **pilots** (F1 lives). The wall — raiders pay salvage, convoys pay
    influence — stops any single farm from buying the whole war (2.4 rigor on
    money); kinetic-first (F3) falls out. M4 RunMods narrowed to in-sortie; the
    campaign is the new persistence.
  - **Salvage values discharged (P5.2 / P4.8):** `salvage_value` + `score_points`
    on EnemyConfig; tactical-value bands (filler→line→specialist→heavy), not
    HP-scaled; distributed cheap on purpose; strategic targets pay influence not
    salvage; veterancy pays; **combo multiplier scales salvage** (style pays —
    the in-sortie→campaign bridge).
  - **Influence menu (P5.3):** recon sweep / fortify / **allied strike** /
    **allied offensive** (P1.q3's "allied offense only on player order") as
    deterministic war-tick modifiers — the seam where F3's commander layer later
    docks.
  - **Pilots priced (P5.4):** `starting_pilots` (P1.7-scaled), death forfeits
    uncollected salvage + costs repair but not the frame, `death_war_ticks`
    (F1.b) default 0, 1-ups earned (steep-influence buy as last resort, never
    salvage), zero → F4.a spectator epilogue. Fungible at 1.0; named-pilot
    veterancy reserved (P5.q3).
  - **Acquisition (P5.5):** the **intel-gated Depot** ("war shapes what you buy":
    intel unlocks the entry, salvage buys it) + **production-capture blueprints**
    (P1↔P5 handshake) + dares/caches direct drops. Dev room stays fully stocked.
  - **Attrition & P1.q4 priced (P5.6):** between-sortie repair/re-arm salvage
    sink (flying well is literally cheaper), **abort = forfeit fraction +
    war-tick** (battlefield-context scaled), exit-without-save rewinds.
  - **War as reward surface (P5.7):** escalation relief (kill production → cap
    the P4.6 clock), terrain leverage, codex — non-currency rewards; enemy spends
    *production* (asymmetric mirror).
  - **Meta fault line flagged (P5.8):** v1.1 "permanent unlocks" vs. v1.11
    "acquired in-campaign" — proposed synthesis: non-power codex default +
    reserved optional "veteran start" (P5.q2).
  - **Configs & harness (P5.9/P5.10):** `EconomyConfig` + per-item `price`/
    `unlock_gate`; economy state in the war-state dict (F4-clean, `var_to_str`
    round-trip); **war_soak gains an autopilot-economy pass** asserting
    completable / no-dominant-farm / no-dead-ends / currency-separation-binds.
  - **Slice (P5.11):** salvage only, pilots, one intel-gated acquisition (gun
    director unlocked by the screamer in intel), modest attrition, codex-only
    meta.
  - **Next**: steer P5 (react to P5.q1–q6 + any section by ID), then Iteration 5
    — P2 (mission composition: node state → encounter), needing all of the above.
- **2026-07-18 — v1.13.** Iteration 4 STEERED (user review). All six P5.q decided
  to their proposed leans; the proposal body stands as accepted:
  - **P5.q1** — two currencies (salvage + influence), **harness-gated**: the
    economy soak (P5.10) must prove influence *binds* or it collapses to one.
  - **P5.q2** — non-power codex/mastery meta by default; cross-campaign *power*
    is a reserved, opt-in, non-canonical "veteran start."
  - **P5.q3** — fungible lives at 1.0; named-pilot veterancy reserved post-core.
  - **P5.q4** — modest salvage repair/re-arm sink **+ user enrichment: the flight
    challenge is itself a *risk sink*.** **Doctrine locked:** attrition is paid on
    two channels — a light wallet cost and the intrinsic danger of the flying
    (frame, pilot, uncollected salvage on the table). The salvage sink stays
    modest precisely because the flight model carries the real attrition weight;
    the economy leans on the thing the game *is*.
  - **P5.q5** — intel-gated acquisition (the Depot opens by what the war shows).
  - **P5.q6** — pilots earned primarily (strategic milestones + top-tier dares);
    steep-influence buy is last-resort only, never salvage.
  - **Ratified by blanket endorsement:** M4 RunMods retired to in-sortie scope
    (campaign is the new persistence); combo multiplier scales salvage (style
    pays currency, the in-sortie→campaign bridge).
  - **Next**: Iteration 5 — P2 (mission composition: node state → encounter),
    the last pure-design iteration before the balance-harness spec + slice build.
- **2026-07-18 — v1.14.** Iteration 5 opened — **P2: Mission Composition**
  proposal written (P2.1–P2.13 + six open questions P2.q1–q6). The capstone: a
  deterministic **composer**, `compose(seed, node, war_state, escalation_tier) →
  sortie_spec`, that projects the war state into a flyable sortie — consuming all
  four prior pillars as ingredients. Per 2.4/2.5 it's composition *grammar*, not
  authored missions:
  - **The spine (P2.1):** pure & deterministic (F4); **two evaluations of one
    function** — the briefing runs it against the manifest-through-fog (P1.3/
    P4.7), the sortie against truth, so stale intel makes the surprise *designed*.
  - **Archetypes (P2.2):** each P1.2 node type → an objective + doctrine (Strike,
    SEAD, Decapitation, Interdiction, Dogfight, the HQ Raid); contested airspace
    is the one archetype that *is* the shipped wave loop.
  - **Placement (P2.3):** manifest → doctrine-in-terrain units (P4.5), layered
    around the objective; **triggered reinforcements, not RNG** — radar/airbase
    CAP as seed-fixed responses to detection (staying unseen is counterplay).
  - **Map & approach (P2.4/P2.5):** biome → geometry (P1.9); the expansive
    ingress→target structure; **open, player-chosen ingress vector**; cover as
    the player's currency, priced biome × garrison (open water goes negative).
  - **Pads (P2.6):** in-sortie free reset + P5.6's between-sortie bill; a
    difficulty knob and a capturable sub-objective.
  - **Dares (P2.7):** biome-seeded skill gaps, quest-marker-free, risk-priced,
    rewarding straight into P5 (salvage/intel/gear/the rare pilot).
  - **Weather (P2.8):** the node's P1.6 state as a modifier pack; the forecast
    makes *when* to strike a decision.
  - **Success spectrum (P2.9):** objective = the P1.q2 capture/degrade gate; **no
    wasted sortie** — every kill dents the node; composes the P1.q4/P5.6 exit
    chain.
  - **Defensive sorties (P2.10):** the composer runs both ways (P4.7 raids);
    intercepts are **optional** — decline resolves by war-sim odds (P1.4).
  - **Organic difficulty + harness (P2.11):** hardness = garrison × cover ×
    weather × pads × escalation, no per-level knob; the war_soak/P4.9 harness,
    extended to composed sorties, asserts the P1.7 curve (no unwinnable/trivial
    node, monotone gradient) numerically before anyone flies it.
  - **Configs (P2.12):** `SortieComposer` (war/ doctrine) + new `BiomeConfig`;
    the M3 `wave_director` demoted to one archetype; overlay SORTIE/BIOME section.
  - **Slice (P2.13):** one biome (cyberpunk city), two archetypes (Strike +
    Dogfight), the slice garrison, pads + one dare + one weather state.
  - **Next**: steer P2 (react to P2.q1–q6 + any section by ID), then Iteration 6
    — the balance-harness spec + difficulty curve, and the slice build begins.
- **2026-07-18 — v1.15. THE DESIGN PHASE IS COMPLETE.** Iteration 5 STEERED (user
  review) — all six P2.q resolved to their leans, closing the fifth and last
  pillar iteration:
  - **P2.q1** — placed garrison for assault archetypes; the M3 wave loop is one
    archetype (contested-airspace dogfight), not the default.
  - **P2.q2** — open, biome-shaped ingress (no rail; masking-vs-speed is the
    pilot's call). **P2.q3** — deterministic triggers only (F4 + honest harness;
    unseen is counterplay). **P2.q4** — every kill dents the node (no wasted
    sortie; the P1.q2/P5.6 spectrum).
  - **P2.q5 (+ user doctrine)** — intercepts are **optional**; **the player is a
    pilot, not a commander (F3)** — never *forced* to defend. Strategic defense is
    a **responsibility the player carries**, not a scramble the game imposes;
    declining and watching a node maybe fall by the odds (P1.4) is the felt
    weight. Previews commander mode where F3 parked it.
  - **P2.q6** — ~4–8 min sortie band, explicitly a **hands-on-sticks dial, not a
    paper number** (user); a slice calibration target.
  - **Milestone:** five iterations (P1/P4/P3/P5/P2) proposed and steered; four
    forks decided; the whole model composes end to end. **Next**: Iteration 6 —
    the balance-harness spec + the stated difficulty curve (2.4/P1.7) — the
    bridge from paper to the vertical-slice build.
- **2026-07-18 — v1.16.** Iteration 6 opened — **The Balance Harness & the
  Difficulty Curve** proposal written (H1–H9 + six open questions H.q1–q6). Not a
  pillar — the *bridge*: it discharges §2.4's balance methodology and P1.7's
  stated curve, collecting every "the harness will prove it" IOU (P4.9, P5.10,
  P2.11) into one instrument before the slice gets built. Highlights:
  - **The thesis (H1):** unify the M0-era trick (step_response/rate_tune_sweep
    tuned flight; war_soak proved the war) into whole-game balance CI. **Doctrine
    (locked): no balance number ships unmeasured; every invariant re-checked
    forever** — paper is the spec, measurement is the test, divergence is a bug or
    a lie.
  - **Four layers (H2):** one harness, four tiers each feeding the next — **unit**
    (matchup matrix, P4.9/P3.7) → **sortie** (composed-node runner, P2.11) →
    **economy** (autopilot buyer, P5.10, extends war_soak) → **strategic**
    (war_soak, *shipped* v1.7, already green). Build works *downward* from the
    proven skeleton.
  - **Measured matrix (H3):** the P4.3/P3.7 paper matrices re-derived from N
    seeded duels + escorted-squad combos; the three counter-web invariants become
    **automated assertions** with red-flag naming (row loses `++`, column loses
    `−−`, dominance pair → red).
  - **Measurement grammar (H4):** every layer prints step_response-style tables —
    TTK/damage/economy/win-rate (unit), completion/pad-dependency/abort/degrade
    (sortie), acquisition-pace/farm-ratio/dead-end/currency-binding (economy).
    Banding by fixed win-rate thresholds, TTK/economy as tiebreakers (H.q1).
  - **The reference pilot (H5) — the hard problem the strategic soak never faced:**
    the sortie/unit layers need *something at the sticks*, and flight feel is the
    human's to judge (CLAUDE.md). **Doctrine (locked): the harness measures
    *balance*; the hands measure *feel*; neither substitutes for the other.** A
    scripted reference-pilot proxy produces *relative* truth (A beats B, X harder
    than Y); the human *calibrates its competence datum* (the sortie-layer analogue
    of war_soak's `skill` scalar). The hands calibrate the ruler; the ruler
    measures what the hands can't fly.
  - **The difficulty curve, numerical (H6) — P1.7/F1.a discharged:** the crux —
    **SDI (Sortie Difficulty Index) is *measured, not authored.*** The composer
    sets inputs (garrison/cover/weather/pads/escalation); the harness *measures*
    the emergent difficulty. Difficulty becomes a *verified emergent property*,
    making "organic balancing, not hand-tuned levels" an engineering claim.
    Stated win bands: pocket **70–85%** (newbie floor, angle-mode Cinematic) →
    HQ raid **25–40%** (hard-but-possible), with four asserted properties — floor
    holds, ceiling real, gradient rises (monotone envelope), escalation under a
    hard cap (P1.7's "never punish excellence" made numerical; a broken enemy's
    cap *falls*). Length target: 25–40 sorties at the skilled datum.
  - **Recalibration debt owned (H7):** v1.7's brutal number (skill 0.9 wins ~10%
    at ~127 sorties vs the 25–40 target) named as the debt the harness retires —
    deferred honestly because it ran on abstract garrisons P4/P5/P2 now replace.
    The loop: build slice → measure → tune *configs, never code* (§2.4) →
    re-measure → bake when the hands say right (§14).
  - **Home & CI (H8):** lives in `scripts/tests/` + extends `war_soak`; every
    lever is a `TunableConfig` field (overlay-writable, harness-readable,
    human-baked); a **green board** = all invariants + curve properties + economy
    assertions pass. Balance CI, the twin of the correctness checks.
  - **Slice cut (H9):** the smallest harness that makes the slice *measurable from
    day one* — the 3×4/2×4 mini-matrix with invariants, a floor+ceiling
    composed-sortie check, a single "can the buyer afford the gun director"
    economy check, inheriting the green strategic layer. Everything above the cut
    grows *with the roster* — each element arrives with its harness row.
  - **Next**: steer Iteration 6 (react H1–H9 + H.q1–q6 by ID), then the vertical
    slice starts getting *built* — paper's edge crossed.
- **2026-07-18 — v1.17. THE PAPER PHASE IS COMPLETE.** Iteration 6 STEERED (user
  review) — all six H.q resolved to their leans, closing the bridge iteration and
  the whole paper phase:
  - **H.q1** — fixed stated win-rate thresholds (not percentiles; a ruler that
    doesn't drift as the roster grows). **H.q2** — both SDI scalar (monotonicity
    test) and the raw axis vector (diagnosis). **H.q3** — scripted reference-pilot
    proxy at 1.0, human-calibrated; the H5 division of labor locked (**harness
    measures balance, hands measure feel**); blackbox-replay reserved.
  - **H.q4 (+ responsibility recorded)** — adopt the strawman win bands (pocket
    70–85% → HQ 25–40%), calibrate hands-on — **and the calibration is *my*
    process to initiate and lead:** when the slice is flyable, I set up the harness
    runs and the hands-on flights, propose the config moves, and drive the datum-
    setting loop until the human says the feel is right (the §14 flight-tuning
    checkpoint, extended to the sortie/economy layers). A scheduled duty, not an
    if-someone-remembers.
  - **H.q5** — floor+ceiling only at slice (monotonicity across ~5 nodes is
    noise; full-curve envelope waits for a real theater). **H.q6** — balance CI is
    advisory through slice bring-up, hardening to a hard build-break gate the day
    the four-enemy mini-web is "right."
  - **Milestone:** six iterations (P1/P4/P3/P5/P2 + the harness) proposed and
    steered; four forks decided; the war-sim runs green (v1.7); the model composes
    *and proves itself* end to end. **Next is not more paper — it's the
    vertical-slice build** (P4.10/P3.10/P5.11/P2.13), with the H9 harness cut
    making it measurable from its first commit.
- **2026-07-18 — v1.18.** Completeness review (user-invited gap pass, leaning to
  simulator depth, true to the north star) surfaced **one real gap** and opened
  **Iteration 7 — The Damage Model: Flying the Wounded Quad** (PROPOSED, D1–D9 +
  six open questions Dq1–q6). The hole: six iterations specced *enemy* durability
  (P4.1's four models) in detail and left the *player's* damage an **abstract
  hit-point pool** — a number, in a game whose north star is *the flight model is
  the product*. It must close before build (the slice's combat, pads, and repair
  bill currently repair *nothing in particular*). The proposal:
  - **Doctrine (proposed locked, D1):** *a hit is a flight-model event, not only a
    health-bar event* — the deepest expression of the USP is **flying a wounded
    quad**, damage felt through the sticks before it's read.
  - **Damage surfaces (D2):** motors (asymmetric thrust / motor-out — the crown
    jewel), props (vibration that feeds the **Filtering group** — a designed
    synergy), frame integrity (the old pool, reframed), FPV camera (diegetic video
    breakup), equipment/FCS (**unifies battle damage with the screamer's EW jam**),
    battery (TWR sag). Hit *location* matters (frame geometry, P3.2).
  - **Severity ramp (D3):** a `DamageConfig` arcade↔sim dial riding the P1.7 knob —
    *the combat twin of the rate-preset ladder*; hardcore sim depth without lying
    about physics, newbie floor preserved (*serious systems, readable presentation*).
  - **Readability (D4):** felt on sticks → sight → sound; **guardrail: damage
    informs, never blinds** (the wound is flown through, never a removed control).
  - **Repair referent (D5):** pads field-patch subsystems in-sortie; the P5.6
    between-sortie bill prices subsystem restoration — *flying well is literally
    cheaper* gains a second meaning; damage is sortie-scoped, repair campaign-scoped
    (bill, not scar).
  - **Counter-web (D6):** enemy chip/burst/area now differentiate *how you fly
    afterward* (chip bleeds integrity, burst knocks out a subsystem, area frays
    props/cam) — the P4.1 threat grammar reflected onto the player's airframe.
  - **Symmetry (D7):** flyers (raider/falx) fly wounded too, palette-consistent;
    deferred past slice.
  - **Configs & harness (D8):** `DamageConfig` + overlay DAMAGE section; per-frame
    subsystem layout in FrameConfig; the H harness gains a *degradation-state*
    dimension — the reference pilot flies wounded, the difficulty curve accounts
    for it.
  - **Slice cut (D9):** ship integrity + **motor degradation** (one flagship
    surface) + video breakup + pad-patch/repair-bill on the sim tier, arcade =
    today's model; defer the rest. The slice earns its USP moment — *limp a
    canting, static-flecked quad onto a pad under fire, patch it, finish the
    strike* — on one surface done honestly.
  - **Next**: steer Iteration 7 (react D1–D9 + Dq1–q6 by ID), then the
    vertical-slice build begins.
- **2026-07-18 — v1.19. THE PAPER PHASE IS COMPLETE (gap-checked).** Iteration 7
  STEERED (user review) — all six Dq resolved to their leans, and one grew a
  doctrine:
  - **Dq1** — sim-leaning default + generous arcade floor, P1.7-ramped (never a
    wall). **Dq2** — motor-out is flyable-but-punishing on the sim tier,
    config-able toward lethal (the skilled limp-home is the story). **Dq3** —
    bill, not scar (damage sortie-scoped, repair campaign-scoped). **Dq5** —
    player-side first; enemy wounded-flight deferred (teaching the AI to fight
    *well while crippled* is premature). **Dq6** — motors only at slice, props
    follow fast.
  - **Dq4 (+ locked doctrine)** — video/camera breakup is brief, recoverable,
    **telegraph-not-blindfold**; and the frustration guardrail it implies is now
    **doctrine: no fight is hopeless, and denial never removes the skill path.**
    From the user's steering story (the charge-shot game's overpowered EW/"hacker"
    drone that, *in a pair*, produced no-counterplay fights — the over-punishing
    frustration to avoid). It lands on three things: **the Screamer (P4.2) is the
    element most at risk of becoming it** (EW + the aegis+screamer combo, P4.3's
    first designed pair) and answers it *by construction* (tissue once reached,
    maskable jam bubble, the **manual iron trigger as the guaranteed skill
    fallback**, P3.6); it **extends the locked bestiary rules** (≥1 counter,
    reaction-dodgeability) from single units to *combinations and denial* (no pair
    is a no-counterplay wall, no denial is total); and **the harness makes it
    falsifiable** — a hopeless pair is a matrix/composition cell the reference
    pilot can't clear (H3/H6), so the guardrail is enforced numerically before
    anyone flies it. *The Iteration 6 harness is the instrument that prevents the
    frustration Iteration 7 named.*
  - **Milestone:** seven iterations (five pillars + harness + damage model) all
    proposed and steered; four forks decided; the war-sim runs green (v1.7); the
    model composes, prices, projects, *and proves itself* end to end, with damage
    now a flight-model event. **The last gap is closed. Next is not more paper —
    it's the vertical-slice build** (P4.10/P3.10/P5.11/P2.13 + D9), measurable from
    its first commit (H9); per H.q4 the difficulty calibration, when the slice
    flies, is mine to initiate and lead.
- **2026-07-18 — v1.20. THE SLICE BUILD BEGINS** (code, not paper — logged here
  in the v1.7 spirit of recording build milestones + findings):
  - **Phase 1 — the matchup harness + reference pilot v0** (H2 unit layer / H5).
    `scripts/tests/matchup_harness.gd` spins real duels headless; a scripted
    reference pilot (`reference_pilot.gd`) flies the *real* drone through the
    *real* rate loop (via `rate_override`), aims the true gun line (accounting
    for the 44° cam uptilt), and the rig prints win/TTK/damage. Proven on shipped
    content: **Missile×Raider 100%, Blaster×Turret 100%** (gun-line aim, zero
    damage). Data-driven so roster growth is one row each.
  - **Finding (real paper↔measured divergence): the v0 pilot cannot gun-kill an
    evasively-orbiting Raider** — it positions and fires but misses, *even with
    the shipped gun director (`fire_assist`) enabled*, because the director's
    **linear** lead solution is defeated by the Raider's curved orbit. P4.3 rates
    chip-gun-vs-Raider `++`; the measured cell is 0% for an AI proxy. This is
    **calibration task #1** and it is *substantial* (curved-prediction FCS,
    closer-range tactics, or a Raider-evasion balance lever) — flagged, deferred
    to Phase 3 (where Gnat + a richer mobile roster avoid over-fitting the pilot
    to one enemy), and reported by the harness rather than papered over. It also
    raises a genuine design question: is the gun director *load-bearing* for the
    chip-gun's rating, and how well should it predict maneuver?
  - **Phase 2 — the damage model** (D9): motors gain per-motor capability that
    scales delivered thrust + yaw torque (asymmetric thrust the rate loop fights —
    the wounded quad); hits degrade the motor on the struck side (`last_hit_
    direction`); a `DamageConfig` severity dial (D3) ramps arcade↔sim; the FPV
    feed breaks up on damage (D4, capped — informs, never blinds); HUD motor pips
    make the wound legible; field-patch repair on run/gate/respawn (D5). Wired,
    live-tunable (overlay DAMAGE section), and headless-verified (import clean,
    both scenes boot, all five checks + the harness pass). **Feel + visuals are
    the human's checkpoint — not claimed here.**
  - **Wounded-flight bench** (`motor_damage_check.gd`, D8): quantifies what feel
    can't be judged headless. First data under autopilot hold: healthy = perfect
    hold; ~75% motor = a mild correctable lean (13° tilt, 2 m/s drift); ≤50% =
    stable-hold lost (55°+ tilt, sinking). The **flyable-but-punishing band under
    autopilot is ~100%→~65% motor health** — signal the coupling may want to be
    gentler across the range (a hands-on call). Asserts the wound is real,
    asymmetric, bounded.
  - Commits: `71f9324` (P1 harness), `12d6f41` (P2 damage), `5cabf53` (bench).
    **Next checkpoint: the human flies Phase 2** (does the wounded quad *feel*
    right? tune the DAMAGE section live), then Phase 3 — Gnat + Aegis + the
    EnemyConfig migration, where the pilot's gun-run gap gets its proper pass.
- **2026-07-18 — v1.21. Phase 2 steered by playtest + a diagnosis corrected.**
  The human flew Phase 2; the wounded-quad loop is landed and steered, and one
  v1.20 claim is formally retracted:
  - **CORRECTION (supersedes v1.20 / the P1 finding): the reference pilot's
    gun-run failure is NOT "the Raider's curved orbit defeats the linear FCS."**
    That was a wrong diagnosis. Playtest evidence (the human routinely guns
    Raiders; probe traces of the v0 pilot) shows the real cause: **the v0 pilot
    engages at too-close range (~13–15 m), where an orbiter's angular rate is
    highest, and aims coarsely.** There is an effective **mid-range band** (too
    far = drop/spread, too close = high angular rate). The Raider's orbit is
    predictable and *meant* to be fun-but-not-trivial, not an annoyance. Fix
    (Phase 3, calibration task #1): give the pilot **range management** (hold the
    mid-band) + tighter aim, calibrated against Gnat *and* Raider to avoid
    over-fitting. The v1.20 "curved orbit" wording stays in place per append-only,
    marked superseded by this entry.
  - **The wounded-quad loop, steered by hands:** the hover **repair pad** was
    replaced by a fly-through green **repair gate** — hovering stationary on a
    wounded quad under fire was a death sentence; you recover by flying *through*
    now (`9ec2c5d`). Damage rebalanced fair (motor floor 0.15→0.30, gentle
    crash-to-motor scale) so it's challenge not death-spiral (`713d871`). The
    **repair-transition drift** (I-term windup unwinding after an instant repair)
    is fixed by clearing the rate integrator on repair — runtime state only, so
    every rate preset is preserved (`05d76b8`).
  - **FCS reticle shipped and simplified:** built CCIP + Funnel + Dot, then — per
    playtest — collapsed to **one** reticle (CCIP + integrated lock cone;
    `f64012a`→`05d76b8`). The **missile lock cone now shows the real zone** (an
    acquire ring + a wider hold ring at the 1.5× hysteresis), both scaling with
    `lock_cone_mult` so upgrades visibly widen it. No auto-lead — lead-compute
    stays a future FCS-gear tier, keeping aim a skill.
  - **Doctrine reaffirmed (F-word, verified twice now):** the wounded-quad damage
    model + a *skill-earned recovery* is a major USP asset — the human's words:
    "two major assets to the gameplay." Balance (fair-but-hard) is the gate to it
    paying off.
  - **Next: Phase 3** — the bestiary (Gnat + Aegis + EnemyConfig migration),
    harness rows for the P4.3 mini-web, and the reference-pilot gun-run pass.
- **2026-07-18 — v1.22. Phase 3: the bestiary lands — and the harness learns
  whose hands hold the ruler.** The slice's P4.10 four are all real (Raider +
  Turret shipped; Gnat + Aegis built this phase), the stat layer migrated, the
  measured mini-web is banded against P4.3, and one H-iteration doctrine got
  exercised for real rather than rhetorically. Commits `6ee184b`→`c9d7c10` +
  the banding. By sub-phase:
  - **P3.1 — EnemyConfig migration (P4.8)** (`6ee184b`): per-type
    `EnemyConfig` .tres (raider/turret values bit-exact), CombatConfig back to
    player-side only, overlay BESTIARY blocks with per-type preset bars, and
    per-rep `ai_seed` determinism for the harness. Pure refactor, proven by
    the matrix not moving. *Finding:* determinism is AI-level, not bit-exact —
    solver float variance across processes can still flip a knife-edge rep;
    stated in the harness header (read aggregate movement, not single reps).
  - **P3.2 — the Gnat** (`5f25405`): kinematic boids, one loop for the whole
    pack (P4.q5 — "the cloud is the unit"); bodies are shootable
    AnimatableBody3D tissue; stings are distance tests that feed the D2
    directional wound. **Playtest: landed** — "a very challenging and
    interesting enemy… I really liked it"; pack size/density stay tunable as
    difficulty dials. *Finding (the harness earning its keep):* the gnat
    cells' first 100% win rate was a lie — with no missile splash, the pack
    was stinging itself out on the player's hull and an empty pack read as
    victory. Fixed the accounting (a sting-spent gnat pays no points) and
    added a kills column; the truth was kills 1/9 with half the hull gone.
    **Win-rate saturates on suicide swarms** — the pack cells band by
    *exchange* (kills vs pack minus hull spent), an H4 amendment.
  - **P3.3 — the Aegis** (`9260a6b`, `e310586`): shields live in the shared
    Health as an opt-in **threshold gate** — under-threshold hits splash off
    entirely (no chipping), a breaking hit carries its excess to hull; regen
    after quiet. The bomber flies its route, ignores you, detonates on
    arrival: the harness scores that `bombed` — a loss at full hull, the
    outcome a health-bar harness would misread as safety. *Model fix found by
    measuring:* a 2-point regenerated shield sliver was swallowing a whole
    60-damage missile (the answer weapon got worse the closer it came to
    winning) — excess now penetrates; no numbers were softened. *Playtest
    steering:* the decorative shield bubble read as broken (you could fly
    inside it) → the shield is now a **physical barrier** (ShieldShell), and
    fixing that exposed a general bug: an enemy's own bodywork counted as
    cover against missile lock — multi-part enemies were un-targetable. LOS
    now accepts the target's own children; every multi-part type to come
    needs this. The intended loop taught itself in play: *"one missile breaks
    it and then the blaster kills it."*
  - **P3.4 — the pilot pass, resolved by steering rather than code.** The
    planned "give the pilot range management" pass ran into a wall the traces
    then explained: four real bugs fixed (44°-tilt throttle compensation —
    the pilot had been *sinking out of the world* every duel since v0;
    line-of-sight-rate feed-forward — pure P lags a mover by a constant ~2.5 m,
    a miss the trigger never forgives; a ground guard — it flew into the
    raider's face, tumbled inverted, and drove itself into the floor; and the
    trigger itself). **The decisive steering (user):** the FCS gun director
    is *how the game is actually played* — "with fire_assist at 0 I can't get
    a shot out"; the reticle answers *where bolts go*, the human supplies
    *where the target will be*, and the director closes that gap. **The chip
    gun's P4.3 ratings ASSUME the director** (the v1.20 question, answered
    yes). The pilot now does positioning only; `weapon.gd`'s arc solver pulls
    the trigger at the human's own 1.2 m setting, stated in the harness as
    `DIRECTOR_MISS_M`. Result: every cell improved (Missile×Aegis 8.1s→2.3s),
    except Blaster×Raider — still 0%, now losing honestly (alive all duel).
    **Final steering: leave the pilot.** The human's calibration — "a tough
    chance to hit, but the weapon itself is very powerful, specially with
    high fire rate" — bands the cell `++` by hand. H5's division of labor
    (*the harness measures balance, the hands measure feel*) now has its
    first hand-banded cell, printed as such in the matrix.
  - **The banded matrix (H3/H4, advisory per H.q6):** paper→measured per
    cell, fixed stated thresholds (win-rate bands for duel cells, exchange
    bands for pack cells, hands for the unmeasurable). Green where it
    matters: Aegis row exactly to spec (`--`/`++` — guns die on aegis,
    missiles crack it), Missile×Gnats one notch off its `--`. Known-cause
    divergences left visible: bare-arena duels overstate vs static targets
    (Blaster×Turret `0`→`++`: the paper band prices the denial zone in
    composed sorties — the sortie layer's job, not a duel's), and the pack
    cells under-band while the pilot cannot kite (parked with the pilot). One
    structural assert added with real teeth: a single Blaster×Aegis win means
    the threshold gate itself broke and fails the run.
  - **The instrument grew eyes (user request):** drop `--headless` and the
    harness renders every duel from the pilot's FPV camera — scenery, muted
    audio, and the **real HUD** via a new shared `ReticleSolver` (main.gd and
    the rig draw the same reticle *by construction*; the "never lies"
    guarantee survives only as one implementation). `tools/watch_matchups.cmd`
    double-clicks it. Watching found the ground crashes in minutes after
    traces had circled for an hour — the founding tenet applies to the
    instrument too. *Bonus finding from watching:* the bot's reticle
    collapses to a dot because the fall line only separates at speed — the
    degenerate reticle is a symptom of the bot's pottering, not a drawing
    bug.
  - Also: blackbox logs renamed to sortable `flight_YYYYMMDD_HHMMSS.csv`
    (`c3fee15`; the old name was ms-since-engine-start — session-relative
    noise).
  - **Open questions parked for later phases:** does `fire_assist_miss_m`
    stay a 0.0 default when the ratings assume it on (design call: FCS is
    acquirable gear — should baseline loadouts include a basic director?);
    lead-aware reticle as an FCS gear tier (the human aims by eye between
    boresight and pipper today — "a physics truth the FCS does not take into
    account"); aegis escorts (Phase 4) may justify revisiting the
    inside-the-bubble knife-range play once being inside costs something.
  - **Next: Phase 4** — the flak pod (3rd weapon column: the gnat answer) +
    Atlas (2nd frame), completing the slice mini-web; then the H.q4 hands-on
    difficulty calibration once the slice is flyable end to end.
- **2026-07-19 — v1.23. The balance-model realignment — and the sortie becomes
  the bubble.** A direction-setting discussion (no code this entry; the user's
  uncommitted `balance-model-handoff.md`, written with Claude chat, was the
  prompt). Three realignments, one new steering, one design question answered
  from the record, and the next build step fixed:
  - **Realignment 1 — what the war is:** reaffirmed F2/P4.7 — the war NEVER
    fights kinetically; unattended battles resolve by strength arithmetic, and
    kinetic combat exists only in the player's own sorties. The couplings are
    stated: `strength_cost` is the exchange rate converting kinetic results to
    war currency, and the composer/SDI closes the loop downward. Rule of
    thumb, adopted: **"The war shapes your fights; your fights dent the
    war."** Precedent check (user question): Falcon 4.0 did the same —
    aggregated statistical campaign resolution, with a deaggregation *bubble*
    of full-sim entities near the player; we are stricter (no radius bubble —
    the sortie is the bubble).
  - **Realignment 2 — what the matchup harness is:** CI for the design's
    feel-promises about the PLAYER's fights (guns die on aegis, missiles
    bankrupt on gnats) — NOT a war oracle, NOT a mux-everything
    average-outcome pipeline for predicting global battle results. The user
    had drifted into the latter reading; BALANCE.md (Phase 3.5 deliverable #0)
    exists to prevent recurrence.
  - **Realignment 3 — the layered balance model (from the handoff, adopted):**
    the integrated duel conflates lethality with the bot's delivery, so
    delivery-limited cells (Blaster×Raider) report the bot, not the weapon —
    the P3.4 loop, explained structurally. Split: **Layer 1 lethality**
    (config arithmetic — 25 dmg < 40 threshold = 0 forever — verified by
    planted-shot benches, no simulation), **Layer 2 delivery** (per-agent
    `aim_quality` × per-target `evasion`, each benched in isolation), with the
    existing duel harness demoted from source-of-truth to **validation** —
    divergence between predicted product and dueled result names an
    un-modeled factor (survival, deadline, economy) instead of being noise.
    Mirror agent-vs-agent fights (handoff suggestion): demoted — asymmetric
    unit layer has nothing to mirror; their real future use is empirically
    pricing `strength_cost` (P5 era). Pilot AI gets **version-pinned**; human
    results stay deviation data, never merged (H5, now with a mechanism).
  - **NEW STEERING (user): allied kinetic presence in player sorties —
    WANTED.** When the player flies a defense sortie, allied units should
    FIGHT — kinetically, in the scene — not resolve as tokens: "it would
    break the feeling of being a part of the war… making the player feel
    like HE IS THE WAR." Feasibility assessed as MODERATE, not pilot-hard,
    because of the bestiary's own idiom: enemies are kinematic steering
    agents ("flying turrets" — the user's exact and correct read), and an
    allied raider is the same code with `team = "ally"` and team-generalized
    targeting (projectile plumbing has been team-aware since M1; enemies
    currently hardcode the player as target — that hardcode is the work).
    The physics-pilot problem stays quarantined in the harness: the only
    physically-true aircraft is the player's. The "baked maneuvers" concern
    is absolved by precedent — P4.q5's "not a cheat, a design statement" is
    already the shipped and playtest-approved idiom. Scope: NOT slice;
    composer-era (P2) feature; it is also the substrate commander mode (F3)
    already needs, so it prepays a decided future. Allied kills/losses
    convert via `strength_cost` like everything else.
  - **Equipment muxing (user question) — answered from the record:** the
    matrix stays weapon × enemy. P4.3 decided it: "FCS is not a column: it's
    a multiplier on gun/missile columns." Equipment shifts a delivery FACTOR
    (measured once per gear tier), never multiplies table dimensions. NPCs
    are statically defined per EnemyConfig (variety = veterancy × biome ×
    combos, per P4.6/P4.q1); only the player has loadout variability. The
    user's auto-aiming-cannon idea is the existing FCS ladder: the shipped
    gun director times the trigger; the off-boresight/turret-pod tier (P3.6)
    bends the barrel; the layered model's `aim_quality` axis and the FCS gear
    ladder are the same axis — one measured, one purchased.
  - **NEXT BUILD STEP — Phase 3.5, the instrument refactor** (before Phase
    4's flak/Atlas, which must not be measured on the conflated instrument),
    in independently-committable steps: (1) `BALANCE.md` one-page primer
    (what each layer measures and is NOT for) + `PILOT_VERSION` pin printed
    in every report; (2) config-derived lethality calculator + planted-shot
    verification; (3) aim bench (agent vs static target) + evasion bench
    (fixed shooter vs moving enemy); (4) banding rewired to
    prediction-vs-validation + a one-command balance report
    (`tools/balance_report`). Queued separately: a risk-based review pass of
    P2-era code (motor_model damage coupling, repair_gate) next session.
    **To resume after a session cut: "Continue QuadShot — Phase 3.5 per the
    v1.23 entry."**
- **2026-07-20 — v1.24. Phase 3.5 shipped: the instrument, unconflated — and
  its first four findings.** The v1.23 plan built as specced, in four
  independently-committable steps, no design changes. What exists now:
  - **Step 1 — the contract.** `BALANCE.md`: one page stating what each layer
    measures and, as importantly, what it is NOT for (not a war oracle, not a
    mux-everything average-outcome pipeline — the v1.23 Realignment 2 drift,
    now written down where it can be re-read instead of re-derived).
    `ReferencePilot.PILOT_VERSION = 1` pins the measuring brain; every report
    header and every table prints it, and the prediction layer **blanks its
    column rather than mixing rulers** when the measured factors carry a
    different pilot version. Numbers from two pilots never share a table.
  - **Step 2 — Layer 1, lethality.** `scripts/balance/lethality.gd` derives
    kill-or-never / shots-to-kill / cadence-limited ttk from CombatConfig ×
    EnemyConfig by replaying `Health.take`'s exact rules. Verified by
    `lethality_check.gd`, which plants hits into a REAL Health node at the
    weapon's cadence and fails the run if replay and shipped code drift:
    8/8 cells match, including `blaster × aegis` never (300 absorbed hits —
    "25 dmg < 40 threshold = 0 forever", now a test) and `missile × aegis`
    3 hits through the regen window. Mirrors the CODE, not the schema:
    `EnemyConfig.armor` is declared and overlay-tunable but applied nowhere in
    the damage pipeline, so it stays out of the arithmetic and BALANCE.md says
    so under "known-inert fields".
  - **Step 3 — Layer 2, delivery.** `delivery_bench.gd`, both factors in the
    isolation that gives them meaning: **aim** = reference pilot vs a static
    immortal raider (the agent alone); **evasion** = the real drone *frozen in
    place* as a perfect shooter, its gun re-laid every tick onto the exact
    ballistic solution at full cadence (the target alone). Static-target
    control cells fail the run if the perfect shooter itself cannot shoot — so
    "it evaded" can never be the rig's own bug wearing a target's name.
    Measured at pilot v1: **aim 0.14 blaster / 1.00 missile; evasion 0.96
    raider, 0.99 turret, 0.12 gnats, 0.99–1.00 aegis.**
  - **Step 4 — the join.** `scripts/balance/prediction.gd` multiplies the
    layers into a predicted band, **with its four assumptions written into the
    file** so they can be argued with rather than absorbed: separability (aim
    and evasion multiply), cadence-is-the-economy, nobody-shoots-back (no
    survival term at all), and clock-starts-at-first-shot (acquisition and
    time-of-flight are outside the number, so predicted ttk is optimistic by
    ~one lock + one flight time — a definition, not a balance bug). The
    delivery factors land in `balance/delivery_factors.json`, a committed
    artifact stamped with its pilot version. The mini-web is now **paper →
    predicted → validated**, with the two gaps flagged as different things:
    paper-vs-predicted = *the shipped numbers disagree with P4.3*;
    predicted-vs-validated = *an un-modeled factor decided this cell*.
    `tools/balance_report` runs all three layers in dependency order and stops
    early when a lower one fails.
  - **THE VINDICATION — `Blaster × Raider`.** The cell the P3.4 loop died on,
    which the integrated duel scores 0/6 (six timeouts) and which H5 had to
    hand-band on the human's word. The layered model, from config arithmetic
    and two isolated benches with no duel anywhere in it, predicts **`++`
    (aim 0.14 × evasion 0.96 = 0.13 hit rate, 15 bolts, 1.4 s)** — *the same
    band the human's hands gave it.* The weapon was never the problem and the
    raider was never slippery: **the bot's aim was the whole story (0.14),
    and the old instrument was reporting it as the weapon's.** That is the
    v1.23 Realignment 3 diagnosis, now measured rather than argued.
  - **FINDINGS — the human's call, none acted on.** (1) *Three stale paper
    bands*: `Blaster × Turret` paper `0` but predicted **and** validated
    `++`; `Missile × Raider` paper `+`, both `++`; `Blaster × Gnats` paper
    `+`, both `--` (0.02 hit rate → 540 bolts to clear the cloud — though the
    flak pod is Phase 4's intended gnat answer, so this band may simply have
    been written for a weapon that does not exist yet). Either the configs
    move or the promises do. (2) *`Missile × Aegis` is a conflated cell*:
    predicted `0` (6.0 s), validated `++` (2.3 s) — because the harness arms
    `fire_assist_miss_m = 1.2` **unconditionally**, so the gun director is
    live during missile matchups. Verified by arithmetic, not assumed: lock
    0.9 s + 40 m at 50 m/s puts missile 1 at ~1.7 s where it strips the 60
    shield for *zero* hull (60 dmg − 60 shield = no excess), and missile 2
    cannot launch before the 3 s cooldown — a missile-only kill is ~7.9 s, so
    the 2.3 s kill is the blaster finishing an unshielded 80-hull bomber in
    four bolts. **This is P4.3's own designed combo** ("cracking opens a timed
    window where the gun finally matters — the combo, not the gun alone"), so
    the question is not a bug report but a definition: should that cell
    measure the missile *alone* (kill the director in missile matchups), or is
    the combo the honest integrated answer — in which case the paper `++` is a
    combo band and should say so? (3) *The pack cells are not commensurable*:
    predicted = ttk to clear the cloud, validated = exchange rate at the 10 s
    cap. The table now labels that instead of flagging a contradiction.
    (4) *The reference pilot connects 14% of its bolts on a **stationary**
    target* — that is the ruler's competence datum, and it is low. Improving
    it is a `PILOT_VERSION` bump and a deliberate re-measure of every cell
    (which is exactly what the pin is for), not a quiet edit.
  - **Also landed:** `Health.struck` — a signal that fires once per arriving
    hit, added because neither `damaged` nor `shield_absorbed` covers a
    shield-breaking hit with zero excess, which silently booked every first
    missile into an aegis as a *miss*. Instrumentation counters
    (`Weapon.shots_fired`, `MissileSystem.launches`) supply the benches'
    denominators. All seven headless suites stay green.
  - **Next: Phase 4** — the flak pod (the gnat answer, 3rd weapon column) +
    Atlas (2nd frame), measured on the unconflated instrument, per v1.23's
    "must not be measured on the conflated instrument". The queued risk-based
    review of P2-era code (motor_model damage coupling, repair_gate) is still
    open. **To resume after a session cut: "Continue QuadShot — Phase 4 per
    the v1.24 entry."**
- **2026-07-20 — v1.25. The state split, the isolation fix, and a pilot
  defect the conflation had been hiding.** A teaching session: the user asked
  the instrument to explain itself term by term, and two of the answers turned
  into code. No new design direction — this sharpens the v1.24 instrument and
  banks two decisions.
  - **Correction to the v1.24 findings (the user's read, adopted):** the
    "three stale paper bands" were over-claimed. Our duels are **1v1 in an
    empty void** — no groups, no cover, no crossfire — so two things that P4.3
    priced for the real game vanish: the ECONOMY (a 3 s missile cooldown costs
    nothing against a lone raider, which is *why* `Missile × Raider` reads
    `++` in the arena but `+` on paper) and the CONTEXT (`Blaster × Turret`
    reads `++` because our turret dies in 1.3 s before it can punish the hover
    P4.3's `0` assumes). Only `Blaster × Gnats` `+`→`--` is a real correction
    candidate — and even there the flak pod is the intended answer, so the
    band may predate its weapon. Recorded as a **stated limit of the
    instrument**, not a doc error: the void measures lethality and delivery
    honestly and says nothing about position or exposure.
  - **THE STATE SPLIT (user's framing: "the shield IS a target by itself, just
    like a hull of a ship").** A shielded type is not one cell but **two
    targets in sequence**, and a weapon's answer can INVERT between them: the
    blaster is `--` against a shielded aegis (25 < 40 threshold, never) and
    `++` against a cracked one (4 bolts, 0.3 s). Averaging those into one cell
    destroys both facts. `Lethality.versus_state` bands each state; the
    planted-shot bench verifies all ten cells (raider/turret/gnat + aegis ×
    {shielded, cracked}). This is the genre's standard model, arrived at from
    first principles and then confirmed against precedent — Halo (plasma
    strips, bullets kill), Mass Effect (per-layer weapon multipliers), Destiny
    (match-game shields): each defensive layer is its own target with its own
    row. **It was already on the books** — H3 line: "P4.3's combos are cells
    too" — so this activates a decided future, it does not invent one.
  - **COMBOS BECOME DERIVED, NOT TABULATED.** `Lethality.combo(strip, finish)`
    chains the two legs (missile strips the 60 shield for zero hull, gun
    finishes the exposed 80 hull in four bolts ≈ 1.5 s — which matches the
    2.3 s the old conflated duel measured, mystery dissolved). The rule this
    protects, and the answer to the user's "how do we do math on a combo
    cell": **the per-weapon table stays strictly single-weapon** so anything
    derived from it is clean; a combo is computed by chaining states, never
    stored as an exception. Writing combo() caught a bug in itself —
    `missile → missile` reported 3.0 s where the identical solo row says
    6.0 s, because the inter-leg cadence gap was missing (a same-weapon combo
    must wait out its own cooldown between legs; a two-weapon one does not).
    Fixed, and the invariant "a same-weapon combo IS that weapon's solo row"
    is now an assert.
  - **`Missile × Aegis` resolved (the user's call): the paper `++` is a COMBO
    band, the solo cell is `+`.** Missile-alone is good, not excellent —
    3 launches at a 3 s cadence is a long intercept — and the aegis's `++`
    answer is *missile-then-gun*, exactly the doc's own "the combo, not the
    gun alone". The harness no longer arms the gun director in missile cells
    (it did so **unconditionally** before, which is what conflated this cell);
    the missile row is held to the solo `+` band, the combo keeps `++` as a
    derived row.
  - **THE DEFECT THE CONFLATION HID.** With the director gone, `Missile ×
    Aegis` flipped from 100% wins to **0% — six timeouts, 1.0 missiles fired
    per duel**. Not a lethality problem: a probe traced the pilot flying
    *straight into the bomber* (39.7 m → 0.5 m), unable to lock a target it is
    touching (cone 82°), grinding down its hull with the gun until the floor
    guard hauls it out — while the stripped shield regenerates back. The
    reference pilot **has no standoff**: its aim loop pitches the uptilted gun
    line onto the target, which drives it forward ("closing range for free" —
    a documented feature), and every other type maneuvers away so the closure
    self-limits. The aegis flies straight at you at 7 m/s and never evades, so
    nothing stops the ram. The gun used to kill it at 2.3 s during the
    approach, masking this for the whole life of the harness. **This is what
    Phase 3.5 was for**: removing a contaminant exposed a real pilot defect
    that had been invisible underneath it. Left unfixed on purpose — a
    standoff behavior is pilot behavior, so it is a `PILOT_VERSION` bump and a
    deliberate re-measure of every cell, not a quiet edit (which is precisely
    the discipline the pin exists to enforce).
  - **WATCH MODE IS NOW STANDING POLICY (user: "essential, not just a
    nice-to-have").** `BenchView` extracts the watch-mode boilerplate into one
    helper every bench calls, so a new headless rig is watchable from its first
    commit rather than after something goes unexplained. The aegis ram is the
    argument made concrete: the numbers said "1.0 launches, timeout" for a
    whole reasoning session; thirty seconds of eyes would have said "it flew
    into the bomber". The delivery bench now renders under watch mode
    (`tools/watch_delivery`), announcing each cell.
  - **The separability caveat, stated for the record (re: the user's
    dynamic-per-pilot-balance idea).** Swapping the measured aim value does
    re-derive the whole table for any pilot — two of three factors are
    pilot-independent — so per-player balance is *mechanically* real. But it
    rests on three things not yet true: (a) separability is an **assumption**
    (`aim × evasion`), un-validated — tracking a jinking mover is a different
    skill than tracking a static one, so real human hit rate on a mover is
    likely below the product, making per-pilot derivation optimistic; (b) aim
    is **one axis of a many-axis skill** — `Blaster × Raider` predicts `++` and
    times out because the bot cannot hold a line *and survive*, which is
    positioning, not aim; (c) runtime auto-scaling is a **design hazard**
    (Oblivion) separate from the model. The immediate, safe payoff is
    **authoring the difficulty curve** knowing what a 0.3-aim vs 0.7-aim player
    experiences — which is H.q4's actual job.
  - **PARKED (user, to revisit): the long-cap pack duel.** Pack cells band an
    *exchange rate at the 10 s cap* (you cannot clear a 9-body cloud in 10 s),
    which is not commensurable with the predicted *ttk-to-clear*. Keep the
    10 s cap as the default ruler, but add — someday — an **optional,
    knowingly-expensive bench** that runs pack duels to completion to answer
    "who actually wins this," a question the short duel deliberately does not.
    Noted so it is not rediscovered; not built.
  - **Also parked (still): the human aim bench (H.q4).** Correct to defer —
    Phase 4 adds the flak column, so measuring the human's aim now means
    re-measuring after flak lands. It is the concrete "how the human helps":
    fly the same static-target drill the bot flew, get a human `aim_quality`,
    and the whole table re-speaks in human terms.
  - **Next: unchanged — Phase 4** (flak pod + Atlas), now on an instrument
    that is not only unconflated but state-aware and watchable. The P2-era
    risk review is still queued. **To resume after a session cut: "Continue
    QuadShot — Phase 4 per the v1.24/v1.25 entries."**
- **2026-07-21 — v1.26. Reference pilot v2: standoff by orbit — and the
  airframe truth underneath it.** The user's call: fix the pilot BEFORE flak,
  since flak is close-range and measuring it on a ramming pilot would repeat
  the aegis confusion deliberately. Done, but the road there produced a
  finding worth more than the fix.
  - **The airframe truth.** The gun carries a 44° uptilt, so aiming a target
    at your own altitude requires pitching ~44° nose-DOWN — which tilts thrust
    forward. **Aiming IS closing.** With a body-fixed gun that must point at
    the target, the thrust vector's horizontal component always points inward:
    the drone can never hover while aiming. v1's "closing range for free" was
    never a feature, it was this constraint, and it only looked benign because
    every enemy maneuvered away. The aegis — which flies straight at you and
    never evades — was simply the first target to expose it.
  - **What failed, measured not guessed.** (1) *Pitch standoff* (a velocity
    servo holding range in pitch): range control and gun-elevation are the
    SAME axis, so every correction swung the gun off target — blaster aim
    0.14 → 0.06, and the aegis still un-lockable. Rejected. (2) *Tight
    last-second breaks*: by 6 m there is no turning out, so they neither saved
    the range (still 0.3 m) nor spared the aim. Rejected. A nine-point sweep
    showed aim and closest-approach trade **strictly monotonically** — orbit
    off 0.17/0.3 m, engage 18 m 0.06/2.6 m, engage 22 m 0.00/3.6 m, engage
    45 m 0.00/6.5 m. **No setting does both.** That is the finding: for this
    airframe, holding standoff and aiming a ballistic gun are mutually
    exclusive.
  - **THE FIX — redirect, don't cancel.** Fly TANGENTIALLY and the same
    aim-driven inward acceleration becomes the centripetal force of a circle
    (v²/R = a_horizontal). Range is then held in the **roll** axis, leaving
    pitch free for aim — and it is the idiom the bestiary already flies
    (enemy_drone orbits its own `preferred_range`). v1's roll law was exactly
    backwards for this: it NULLED lateral velocity, killing the very
    tangential component the orbit needs.
  - **Scoped to homing weapons, from the data.** The ram only BREAKS the
    missile cells — you cannot lock a target you are touching — while the gun
    measures fine at 0.17 straight through it. And the orbit's cost is
    specifically BALLISTIC (circling makes every bolt a deflection shot from a
    turning platform) while the homing missile held 1.00 throughout. So the
    orbit goes exactly where the ram hurts and its cost does not apply. Not a
    fudge: a pilot carrying a homing weapon can afford to maneuver precisely
    *because* it need not point, and `aim_quality` is already keyed per
    weapon, so each is measured under the flying its own weapon wants.
  - **Two controller bugs found on the way.** (a) The roll law commanded a
    RATE proportional to velocity error with no bank ceiling — an 11 m/s error
    asked for ~113°/s of sustained roll, the drone banked past its lift budget
    and **sank 14 m → 3.9 m into the floor guard**. Now a bank-ANGLE loop
    ceilinged at 32°, and that ceiling is a *thrust budget*, not a taste:
    aiming already spends cos(44°), leaving cos(44°)·cos(bank) of lift.
    (b) Engaging the orbit late met the radius with ~13 m/s of inward momentum
    no swerve could absorb (traced flinging to 57 m); it now engages far out
    and spirals in. A spiral settles; a swerve does not.
  - **Result.** `Missile × Aegis`: 0/6 timeouts → **6/6 wins at 8.0 s,
    spending exactly the 3 missiles Layer 1 predicts.** The +2.0 s over the
    predicted 6.0 s is acquisition + flight — the prediction model's stated
    assumption 4, now **confirmed against a real fight rather than asserted**.
    Blaster aim 0.14 → 0.17 (the bank-angle loop is steadier than the old
    raw-rate damper). Evasion factors byte-identical by construction, since
    that bench freezes the drone — a clean proof the layers are isolated.
    `PILOT_VERSION` 2; `delivery_factors.json` re-measured and pinned to it.
  - **Harness sharpened:** PREDICTED vs VALIDATED now flags only a real
    OUTCOME disagreement (model says kill, fight says loss), not a letter
    mismatch between two different rulers. It had been firing on
    `Missile × Aegis`, where predicted 6.0 s and measured 8.0 s in fact agree
    — noise that buried the cells which genuinely diverge.
  - **Still open, unchanged:** the three paper-vs-predicted findings
    (`Missile × Raider` `+`→`++`, `Blaster × Turret` `0`→`++`,
    `Blaster × Gnats` `+`→`--`), all subject to the v1.25 caveat that the
    1v1 void has no economy and no context. `Missile × Aegis` solo now reads
    paper `+` vs predicted `0` — the missile alone is slower than "good"
    implies, which is itself an argument that the aegis's answer is the combo.
  - **Next: Phase 4** — the flak pod (3rd weapon column, the designed gnat
    answer) + Atlas, now on an instrument that is unconflated, state-aware,
    watchable, and flown by a pilot that does not ram. **To resume after a
    session cut: "Continue QuadShot — Phase 4 per the v1.24/v1.25/v1.26
    entries."**
- **2026-07-21 — v1.27. External review triage: the instrument hardened before
  Phase 4 touches the matrix.** The user commissioned an independent read-only
  analysis of the whole tree (`HANDOFF-REPORT-2026-07-21.md`, pinned at
  `6b2c25b` — i.e. before the v1.26 pilot work). It is a strong document; every
  finding acted on below was **verified against the source first**, and all
  six balance-instrument findings were real. Deliberately triaged *now*, while
  the report still matches the tree, rather than after Phase 4 drifts it.
  - **FIXED — RISK-H1, the one that was actually blocking.** The rig-sanity and
    shield-gate asserts addressed cells by POSITION (`_win_rate(1/2/5)`), while
    the harness header invites new rows as "one list entry". Phase 4's flak and
    Atlas rows would have silently repointed every assert at the wrong cell —
    the shield-gate check could have ended up guarding a row with no shield in
    it, passing forever while proving nothing. Now addressed **by name**, with
    a missing cell failing loudly instead of passing vacuously. *An assert that
    can be silently misaimed is worse than no assert.*
  - **FIXED — RISK-H2, the second ruler.** Delivery factors rotted against
    `PILOT_VERSION` only, but they are equally measured against muzzle speeds,
    lock cones and enemy speeds — so retuning any of those left the predicted
    column quoting measurements taken under different physics, silently. The
    artifact now carries a **config stamp** (a whitelist of the fields delivery
    is sensitive to; hull/damage are excluded because they belong to Layer 1,
    which recomputes live and cannot go stale). Verified by tripping it: a
    90→85 `muzzle_speed` edit blanks the column, and the restored config is
    byte-identical. **Phase 4 makes this urgent rather than theoretical — it
    edits `CombatConfig` to add a weapon column.**
  - **FIXED — BUG-H2 / SMELL-H1 / BUG-H1.** The delivery bench ceased fire once
    on entering GRACE, but GRACE keeps running the pilot, which re-arms
    `missile.fire_override` every tick — late launches booked as misses,
    biasing `aim:missile` down (invisible only because it reads 1.00). The
    turret evasion cell's comment called it "a second control" while the
    `control` flag was missing, so `CONTROL_MIN_RATE` never guarded it — *a
    control that does not guard is just a comment*. And the watch-mode HUD was
    built, fed by the shared `ReticleSolver`, and **never drawn** (`_update_hud`
    had no call site) — now wired, so watching a duel finally shows what the
    aim loop sees.
  - **FIXED, and it CORRECTS AN EARLIER FINDING — GAP-H1.** Turret and Aegis
    expose no `ai_seed`, so all six reps fight the identical duel and the
    win-rate ruler can only return 0% or 100%. Those cells therefore **cannot
    read `0` or `+` whatever the balance is.** The report now says so per cell
    — which means the v1.24 finding "`Blaster × Turret` paper `0` → validated
    `++`" is **partly a resolution artifact, not purely a stale paper band**.
    Detected structurally (does the type expose `ai_seed`) rather than by
    comparing outcomes, since unseeded reps still differ by a tick of float
    noise. This is the second time the 1v1-void caveat has bitten the same
    finding; treat that cell as unproven until it is measured in context.
  - **Also fixed (cheap, verified):** `damage_config` was the one config that
    never auto-loaded its `user://` override on boot, so saved damage tuning
    silently vanished between sessions (BUG-5); and `turret`/`enemy_drone`
    divided by `enemy_config.muzzle_speed` unguarded in their lead solutions
    while the player side guards with `maxf(…, 1.0)` — every non-shooting type
    ships `muzzle_speed 0` as its inert default, so this was one steering
    change away from feeding inf/NaN into a projectile velocity (RISK-9).
  - **Already resolved before the review landed:** its `REF-DEFECT` (the pilot
    rams the aegis) is **fixed in v1.26** — the report is pinned at `6b2c25b`
    and predates that work.
  - **NOT done, tracked here as the review's standing backlog** (its `file:line`
    ledger is the detail; this is the priority read): **RISK-1** — the
    in-mission layer is non-deterministic (`wave_director` `randomize()`,
    unseeded `ai_seed` on live spawns, `upgrades.shuffle()`, wall-clock combo
    timing that also misbehaves under slow-mo). *Not* a Phase 4 blocker since
    the harness seeds its own combatants, but it **blocks the composer and any
    replay**, and H6's "difficulty is measured, not authored" depends on it —
    build the run/encounter seed seam before P2. **GAP-A** — Gnat and Aegis are
    built, tuned and benched but **not in the live wave loop** (`wave_director`
    still spawns only Raiders), and the Aegis `detonated` → "you failed the
    intercept" outcome is not wired into scoring. **BUG-2/BUG-3** (war-sim:
    2 of 7 biomes unreachable; the HQ decapitation gate is bypassable via
    `_allied_offensive`). **RISK-6/7/8** (two uncoordinated pause mechanisms;
    gameplay actions firing while typing a preset name; core input setup living
    in the debug overlay, so any scene without it gets factory bindings).
    **GAP-H2 / OPPORTUNITY-H** (single-seed `evasion:raider`; the gnat evasion
    cell measured with pursuit disabled). Plus the war-sim serialization
    fragilities (RISK-2/3/4/5) and the `WarConfig` promotion (SMELL-1).
- **2026-07-21 — v1.28. Phase 4a: the flak pod lands, the paper `++` holds, and
  the ruler shows itself.** The 3rd weapon column, built and measured on the
  instrument Phase 3.5 exists to provide. The headline is a rare thing in this
  log: a paper band that survived contact with measurement, unchanged.
  - **THE ANSWER TO THE QUESTION ASKED.** `Flak × Gnats` is the only cell in
    the mini-web where **paper `++` → predicted `++` → validated `++`** all
    agree. Validated exchange **+1.00: nine of nine bodies shot down, zero hull
    spent, 2.7 shells, 1.3 s** — against the chip gun's 1.8 kills for 50% of the
    player's hull over 26 bolts. The gnat row now has an answer, which is what
    v1.24/v1.25/v1.26 all deferred to this phase to find out. Predicted 0.8 s vs
    measured 1.3 s is acquisition + flight, the model's stated assumption 4.
  - **The weapon, per P3.1, with nothing special-cased.** A ballistic shell with
    a proximity fuse (`flak_fuse_radius` 3.5 m) that bursts into a flat-damage
    fragment cloud (`flak_burst_radius` 6 m, 10 damage), auto at a slow cycle
    (2.5/s vs the blaster's 10). **The gap between the two radii IS the weapon**:
    a fuse tighter than the burst lets the shell get INTO a cloud before it goes
    off, so fragments come from the middle of the pack rather than its near face.
    And the P4.3 `--` against shields needs no code at all — 10 damage under the
    aegis's 40 break threshold reports NEVER through the same branch that
    hard-counters the chip gun. "Useless tonnage against shields" falls out of
    one number being small.
  - **Flat damage inside the burst, deliberately.** A falloff curve would make
    damage-per-connect a function of geometry — i.e. it would smear a delivery
    concern into Layer 1 — and the planted-shot bench could no longer check the
    arithmetic at all. Layer 1 stays "if this connects with a target, what
    happens to THAT target"; all 15 cells (3 weapons × 5 states) verify against
    the real `Health`, including 75 flak hits absorbed by a shielded aegis.
  - **THE MODEL EXTENSION THE COLUMN FORCED: `splash`, a third delivery
    factor.** An area weapon is paid per BURST while the target is priced per
    BODY, and nothing in the layered model expressed that. `splash` = bodies
    covered per ARRIVING burst, **measured** against a real pack (3.42 for
    flak × gnats), dividing the pack bill. Its owner is neither the agent (aim)
    nor the target (evasion) but the pair — the weapon's burst geometry meeting
    the target's dispersion — which is why it is a third factor rather than a
    fudge inside one of the first two. **It is 1.0 for every weapon that damages
    one body per connect, so it is inert everywhere except flak.** Layer 1 was
    NOT touched: flak is still priced per body there, like everything else.
  - **One shipped number moved, and it was a rounding bug.** Predicted shot
    counts used to ceil PER BODY and then multiply by pack size; a bolt that
    misses gnat 4 is not a shot "wasted on gnat 4" to be re-spent, it is one
    shot of an aggregate bill. Now one ceiling, on the total. Only
    `Blaster × Gnats` moves — 450 shots → 442, ttk 44.9 s → 44.1 s, band
    unchanged `--`. Flak forced the question because the pack bill is its whole
    economy.
  - **THE FINDING WORTH MORE THAN THE WEAPON: two of the flak column's four
    cells are reporting the BOT, not the gun.** `Flak × Raider` reads paper `0`
    → predicted `++` → validated `++`, and `Flak × Turret` reads paper `-` →
    `++` → `++`. The tempting read is "flak is overtuned against single
    targets." **The arithmetic says the opposite: on Layer 1 alone flak is the
    SLOWEST single-target weapon in the game** — 4 hits / 1.2 s on a raider
    against the blaster's 2 hits / 0.1 s. It only outranks the gun once delivery
    is applied, and delivery here is `aim: blaster 0.17` vs `aim: flak 0.99` —
    which is a statement about a pilot that cannot hold a gun line, meeting a
    fuse that does not require one. **This is the v1.24 `Blaster × Raider`
    vindication repeating in a new column**: the instrument reporting the ruler's
    competence as the weapon's property. So: do not tune flak to the paper bands
    on this evidence. The parked human aim bench (H.q4) just went from "nice to
    have" to load-bearing — it is now the thing that decides whether the flak
    column is honest.
  - **P4.3 INVARIANT 3 IS THE SHARPEST FORM OF THAT FINDING.** "No column
    dominates another (≥ in every row), or the dominated archetype is dead
    content walking." On the **measured** table flak now weakly dominates the
    chip gun: `++`/`++`/`++`/`--` against the gun's `++`(hand)/`++`/`-`/`--` —
    equal in three rows, better in the gnat row. On the **paper** table it does
    not, and cannot: P4.3 gives the gun `++` on raiders where flak has `0`, and
    the gun `+` on gnats where flak has `++`. So the two tables disagree about
    whether the slice has a dominance problem, and the entire disagreement sits
    in one number — the ruler's 0.17 blaster aim. **The invariant is not
    violated by the design; it is unverifiable by this instrument until the
    pilot can shoot.** That is the strongest argument yet for H.q4, and it is
    logged rather than acted on.
  - **`aim_quality` is hits-per-shot-FIRED, and that hid a conflation.** It says
    nothing about how OFTEN a shot is taken, so two weapons with different
    trigger policies produce non-comparable aim numbers: the blaster's trigger is
    the gun director (fires on any arc solution — duty 0.41, aim 0.17), the flak
    pod has none by design (the pilot fires only inside a 6° cone — duty 0.68,
    aim 0.99). The delivery bench now prints a **duty cycle** beside every rate.
    Deliberately NOT folded into the model: prediction assumes shots arrive at
    full cadence, so a sub-1.0 duty is a standing optimism in every predicted
    ttk — pre-existing, and it belongs in the report as a named factor rather
    than in a quiet correction coefficient.
  - **The pod carries no gun director, on purpose.** A bolt must intersect a
    body; a fused shell only has to arrive near one, and that forgiveness IS its
    assist. Giving it a second trigger-puller would hand the column an advantage
    P4.3 never priced ("FCS is not a column"). The reference pilot therefore
    pulls the flak trigger under the SAME 6° cone and range knobs the manual
    blaster path uses — widening them "because the fuse forgives" would be tuning
    the ruler to flatter the column it measures.
  - **`PILOT_VERSION` 3, and the bump proved its own point.** `use_missile`
    became `weapon_id`, plus a third branch (blaster aim loop, no orbit — that is
    homing-only — manual trigger, and leading by the shell's own 70 m/s rather
    than the bolt's 90). Behaviourally inert for the existing columns, and the
    re-measure **proved it rather than asserting it**: every v2 factor came back
    byte-identical (blaster 0.17, missile 1.00, all seven evasion cells), the
    file diff purely additive. That is what the pin is for.
  - **A wobbling factor, reduced but NOT eliminated — stated as measured.**
    `aim: flak` read 1.00 in one run and 0.92 in the next on identical code:
    cross-process float variance moving three shells across the 6° cone edge in
    a 36-shot sample. The cell's window went 20 s → 40 s, which halved the
    spread — three runs then read **0.99 / 0.99 / 0.94**. It did not fix it, and
    an earlier draft of this entry claimed it had after only two runs; the third
    run corrected that, which is the argument for running the report more than
    once before believing a factor. More time is not more independent samples
    here: the pilot flies one quasi-periodic trajectory, so a longer window
    largely re-measures the same oscillation. **Left as measured rather than
    chased** — the residual moves no band (this cell divides into single-digit
    shot counts) and sits inside the harness's already-stated contract:
    AI-level deterministic, not bit-exact. Logged so a future 0.94-vs-0.99
    diff is not read as a balance change. **This is the flak column's least
    stable number**; the chip gun's aim (0.17, 81 shots) does not move.
  - **Also landed:** `flak:*` config fields joined the delivery **config stamp**
    the day the weapon shipped (the v1.27 rule, honoured on its first test —
    Phase 4 was the exact scenario that made the stamp urgent); the shield-gate
    structural assert now guards **both** under-threshold columns by name; a
    two-counter **cross-check** in the bench fails the run if the pod's own
    body count and the target's `Health.struck` count ever disagree; the flak
    pod is wired into `drone.tscn`, the overlay COMBAT section, and the bindings
    (**RB** / **G**), so the human's hands can judge it. All seven correctness
    suites and all three balance layers green.
  - **DEFERRED, named rather than skipped: GAP-1, the `WeaponConfig` split.**
    The external review called the flak pod the forcing function for promoting a
    per-weapon resource (P3.9). It was not taken: flak's fields went onto
    `CombatConfig` beside the missile's, because doing the three-weapon
    refactor in the same change as the measurement would have meant re-measuring
    a moved config and a new weapon at once, with no way to tell which moved a
    number. The migration is mechanical and now has three columns' worth of
    fields to justify it — the right moment is with Atlas, where `FrameConfig`
    arrives anyway.
  - **Open, for the human's call (nothing acted on):** whether `Flak × Raider`
    `0`→`++` and `Flak × Turret` `-`→`++` are stale paper bands, a real config
    problem, or — the reading this entry argues for — an artifact of a ruler
    whose blaster aim is 0.17. Also unchanged from v1.26: `Missile × Raider`
    `+`→`++`, `Blaster × Turret` `0`→`++` (partly a resolution artifact per
    v1.27), `Blaster × Gnats` `+`→`--`. All still subject to the v1.25 caveat:
    the 1v1 void has no economy, no cover and no crossfire.
  - **Next: Phase 4b — Atlas** (2nd frame, the P3.4 frame axis), then the H.q4
    hands-on difficulty calibration, whose priority this entry just raised.
    **To resume after a session cut: "Continue QuadShot — Phase 4b (Atlas) per
    the v1.28 entry."**
- **2026-07-22 — v1.29. The human flies the flak pod, and the blackbox names a
  coverage gap the 1v1 harness cannot see.** Feel checkpoint on v1.28: "the
  flak is a great addition and it absolutely destroys the gnats. it also
  really helps destroy groups of raiders... since it does not have auto shot
  then i dont use it too much against the turrets, but it looks like it works
  also against the turrets." H5 territory — hands measure feel, logged as
  deviation data, no band or code changes follow from it.
  - **The blackbox as a deviation-data source, used for the first time this
    way.** Asked to look for something the numbers might be missing, the
    11.6-minute session (`flight_20260722_205136.csv`, 166,503 ticks) was read
    back. Flight-telemetry-only (position/rates/motor output — no weapon-fired,
    no hit, no enemy channel), so this is what it can honestly say, no more:
    almost no hovering (0.5% of the flight under 2 m/s; 67% above 15 m/s, avg
    17.1 m/s), roll commanded far harder and more often than pitch or yaw (avg
    80°/s vs 35°/s / 30°/s, p95 roll 281°/s), a path 123x longer than its net
    displacement (constant circling/weaving, not point-to-point flying), and
    frequent low passes (8.9% of the flight under 3 m) with a few brief
    single-point ground skims, speed recovering right after — buzzing, not
    crashing. **None of this is how the reference pilot flies a gun or the flak
    pod** — it holds close to wings-level for both (roll only damps drift; the
    v2 standoff-by-orbit is missile-only per `reference_pilot.gd`). The human is
    doing continuous evasive banking the instrument's flying style never
    attempts for these two weapons.
  - **THE GAP THIS NAMES: every `× Raider` cell in the matrix, every weapon, is
    1-VS-1.** `wave_director.gd:84-89` spawns `wave_base_enemies +
    wave_growth×(wave−1) + sortie_enemy_bonus×(sortie−1)` raiders
    SIMULTANEOUSLY, scaling every wave and sortie — "more and more raiders
    come up" is the shipped design, not a report of it. But only gnats get
    pack-mode banding; the raider row has never been measured against more than
    one body at a time. So "flak helps against groups of raiders" is a real
    gameplay benefit the instrument has **zero coverage of, for any weapon** —
    not a ruler artifact like the v1.28 aim-datum finding (where a bad blaster
    aim was inflating flak's apparent lead in a FAIR 1v1), but an honest scope
    limit: the thing being praised is not the thing being measured. Consistent
    with the v1.25 caveat (the duel is a 1v1 void with no crossfire) landing on
    real evidence rather than staying theoretical.
  - **Decision (user's call): a Raider×N pack bench, mirroring the gnat pack
    cells, is wanted — after Atlas, not before.** Logged so it is not
    rediscovered; not built. Candidate for the same session as, or right
    before, H.q4's human aim bench, since both are "make the instrument match
    what is actually played" work.
  - **A second, DISTINCT ask surfaced in the same conversation: richer
    per-tick combat instrumentation in the blackbox itself** (shots fired, hits
    landed, enemy identity/position) so a session can be reviewed for combat
    detail, not just flight dynamics. Not the same thing as the H.q3 DECIDED
    item ("blackbox-replay... reserved richer datum once the slice has real
    maps to record on") — that was about replaying a human's flight as a
    competence datum for the reference-pilot model; this is about instrumenting
    ANY session for after-the-fact diagnosis, which is what this very entry
    just did by hand from flight data alone.
    - **Sized, not guessed, before answering "will it inflate the files":**
      this session's file is 128.4 bytes/row at 240 Hz (21.4 MB for 11.6 min).
      A few sparse per-tick counters (shots fired per weapon, damage taken) are
      mostly zero and would add perhaps 5-10% — cheap. Logging the FULL enemy
      roster every tick would not be cheap and does not fit a fixed-width CSV
      schema anyway (the enemy count varies tick to tick). **The right shape is
      a sparse companion EVENT log** (one line per weapon-fired / hit-landed /
      enemy-spawned / enemy-killed, not one line per physics tick) — at
      real combat tempo that is hundreds to low thousands of lines per session,
      negligible next to the 21 MB flight recorder, and it is what would have
      let this entry report an actual hit rate instead of inferring "buzzing,
      not crashing" from position and contact-count alone.
    - **Deferred at the user's word** ("if this is planned for later then well
      done! we'll wait for the right time") — not built, not scheduled; logged
      here as a scoped, sized proposal so the shape is decided before the day
      it gets picked up, the same discipline BALANCE.md's config-stamp and
      pilot-version pins exist to protect elsewhere.
  - **Next: unchanged — Phase 4b, Atlas** (2nd frame). The raider-pack bench and
    the richer blackbox both wait behind it, by the user's explicit call.
    **To resume after a session cut: "Continue QuadShot — Phase 4b (Atlas) per
    the v1.28/v1.29 entries."**
- **2026-07-22 — v1.30. Phase 4b: the Atlas lands, the frame axis costs the
  model nothing — and the ruler turns out to have been reading the human's own
  config all along.** The 2nd frame, built and measured the way the flak pod
  was. Two headlines: a P3.3 promise that came true as physics, and an
  instrument bug that had been quietly inflating every number in the log.
  - **THE FRAME AXIS FORCED NO NEW FACTOR, and that was the open question.**
    The flak column had just forced `splash` into existence (v1.28), so the
    reasonable fear was that every new axis costs a dimension. It does not:
    `aim_quality` was always per AGENT, and an agent is a pilot flying an
    airframe — there had simply only ever been one airframe. So a frame is a
    **re-keying** of aim (`kestrel:blaster`, `atlas:blaster`), not a new factor.
    Evasion is deliberately NOT frame-keyed, and that is structural rather than
    thrift: the evasion bench freezes the shooter and lays its gun on the exact
    ballistic solution every tick, so a frozen Atlas and a frozen Kestrel fire
    identical shots. **Measured rather than asserted** — all eleven evasion
    cells and `splash` 3.42 came back byte-identical across the change.
  - **THE PROMISE THAT CAME TRUE: `aim: atlas/blaster` 0.19 vs
    `aim: kestrel/blaster` 0.05.** P3.3 wrote the Atlas's gun story as prose —
    *"a stable gun platform, and honestly so: FCS solutions converge faster on a
    steady frame because miss-distance jitter shrinks. That's physics, not a
    stat: the heavy frame is the FCS frame emergently."* The bench measured
    almost 4x the hit rate with nothing special-cased anywhere: the Atlas has no
    aim bonus, no FCS advantage, no wider cone. It is heavier and softer, so the
    same brain holds a line on it. This is the flak pod's `++` repeating in a new
    axis — a paper claim surviving contact with measurement, unchanged.
  - **Frame cells are ruled RELATIVELY, against the Kestrel.** A frame does not
    change whether the weapon kills; it changes what the kill COSTS, and win
    rate is nearly blind to that (both frames win, one bleeds). So frame cells
    band the **exchange delta** — fraction of the enemy unit destroyed minus
    fraction of your own hull spent — against a Kestrel twin flying *the same
    weapon at the same enemy*, asserted structurally, because a datum differing
    by loadout would report the loadout and call it the airframe (P4.3's "FCS is
    not a column", one axis over). The origin is not a convention: P3.3/P3.4
    define the Kestrel's whole column as zeros on purpose, so the design's own
    statement is the ruler's zero. It also **rescues** cells the outcome ruler
    cannot resolve — an unseeded enemy can only read `++` or `--` on win rate,
    but hull spent is continuous even in a deterministic duel.
  - **The predicted column cannot express a frame at all, and the report says so
    on every frame cell.** Prediction has no survival term (assumption 3: nobody
    shoots back), so it bands an absolute ttk while paper and validated are both
    deltas. Durability — the entire point of the Atlas — is visible only in the
    validated column. Not a defect to fix: a stated scope limit, printed rather
    than left for a reader to trip over.
  - **THE RULER BUG, and it is the biggest finding in this entry.** The benches
    instantiated `drone.tscn` directly, which auto-loads `user://` — so **every
    delivery factor ever committed was measured against whatever the human had
    last tuned into their own override file** (`rate_p` 0.007 against the repo's
    0.004, `rate_ff` 0.0008 against 0, `angular_damping` 0.013 against 0.02).
    The ruler was machine-local, `balance/delivery_factors.json` was not
    reproducible from a clean checkout, and no stamp could catch it because the
    drift lived in a file that is not in the repo. Benches now build through
    `Frames.build` with overrides off, and each frame's FlightConfig joined the
    config stamp — mass and rate gains were ALWAYS delivery inputs and were
    never stamped, so retuning the drone's PID silently invalidated every factor
    while the stamp reported a match. **An instrument measures the numbers that
    are committed.**
  - **What that cost, attributed by CONTROL RUN rather than by argument.** The
    harness was re-run once with overrides deliberately switched back on, and
    every moved cell returned to its v1.28 value: `Missile x Aegis` bombed 6/6
    -> win 6/6 at 8.0 s (v1.28: 8.0 s), `Blaster x Turret` 3.9 s -> 1.3 s
    (v1.28: 1.3 s), `Flak x Raider` 6.3 s -> 2.2 s (v1.28: 2.2 s),
    `Blaster x Gnats` exchange -0.51 -> -0.27 (v1.28: -0.30). So **100% of the
    movement is the flight config and none of it is the combat model** — the
    frame, armor and splash work moved no shipped number. `aim: kestrel/blaster`
    0.17 -> 0.05 is the same fact stated as a factor.
  - **A relative ruler has a moving zero, and the control proved that too.**
    `Atlas x Turret` reads `+` (delta +0.20) against the repo's Kestrel and `0`
    (delta -0.10) against the human's — **same Atlas, same six seeds, same
    weapon; only the datum changed.** On a responsive Kestrel the turret dies in
    1.3 s for zero hull, so the Atlas's armor buys nothing and its slowness
    costs 10%; on the committed Kestrel the turret lands three shells first and
    the armor pays. This is the sharpest argument that the frame axis cannot be
    read until the datum frame is the one people actually fly.
  - **THE DECISION THIS PUTS TO THE HUMAN (not taken here, per handoff §14).**
    `default_flight_kestrel.tres` is materially worse to fly than the config the
    human has had loaded for months, and the instrument had been hiding that by
    borrowing it. Baking the tuned values into the default would move the
    Kestrel datum, every aim factor and several validated cells — deliberately,
    once, with a re-measure. Only the human can say the feel is right, which is
    exactly what §14 reserves to them.
  - **Three of the four Atlas cells cannot report their paper band, each for a
    different and nameable reason — which is the instrument working.**
    - `Atlas x Gnats` paper `++` -> validated `0`, **because the ruler
      saturates.** The flak pod already scores a perfect +1.00 exchange on the
      Kestrel (nine of nine bodies, zero hull spent), and no frame can beat
      perfect. The gnat row has nothing left for a frame to win. A resolution
      limit of a relative ruler, mirroring the deterministic-enemy limit v1.27
      documented for the absolute one.
    - `Atlas x Aegis` paper `++` -> validated `0`, **because the band is bought
      with hardpoints and there is no loadout system.** P4.4 prices the heavy's
      aegis day as "missile racks + burst tonnage"; in the slice both frames
      carry the same single launcher, so the cell measures two identical
      loadouts and correctly reports no difference. The strongest concrete
      argument yet for P3.8's loadout loop being what makes the frame axis real.
    - `Atlas x Turret` paper `-` -> validated `+`, **sign inverted, because the
      1v1 rig has no ingress.** P4.4's `-` is bought by exposure — the heavy is
      slow in the open — and the duel starts at 40 m with the target already in
      the arena. The v1.25 caveat landing on a frame cell instead of a weapon
      one. (And subject to the moving-zero finding above.)
    - `Atlas x Raider` paper `0` -> validated `0` (delta -0.01). **The one row
      where paper predicts no difference is the one row that measured no
      difference** — worth stating, because a frame axis that reported a
      difference everywhere would be reporting noise.
  - **Armor stopped being schema-only**, which retires BALANCE.md's last
    known-inert field. Applied in `Health.take` layered UNDER the shield gate
    (so it never changes whether a weapon can crack a screen, only what gets
    through) and in the gnat body's own damage path, modeled in `Lethality`,
    verified by planted-shot **probes** — synthetic armored configs, because
    every roster type is still `armor = 0.0` and checking the code against zeros
    verifies nothing. One probe earned its keep immediately: `aegis+armor36`
    caught a real bug in the calculator's first draft, which verdicted NEVER on
    a shield carry-through swallowed by plating. The screen is down by then and
    the next hit lands whole; it kills at 21.0 s, and the bench proved it against
    the shipped `Health`.
  - **The Atlas is derived, not fitted.** 1.9x mass, TWR 3.2, soft rates, heavy
    filtering — P3.3's own words turned into numbers; hull 190 is the Kestrel's
    100 scaled by that same mass ratio (P3.2's honest-mass doctrine applied to
    durability); armor 3 is sized against what the slice actually throws (gnat
    sting 7 -> 4, raider bolt 8 -> 5, turret shell 10 -> 7). Flat reduction is
    worth most against many small hits and least against few big ones, so ONE
    number reproduces P4.4's shape for the heavy column with nothing
    special-cased per enemy. **Its rate PID is the Kestrel's, unchanged**:
    angular authority scales with TWR, so the same gains on a 1.9x frame give
    ~0.71x the loop gain and the aircraft plants itself as physics rather than as
    a tuned number — and the `rate_preset` ladder keeps working on it, which a
    hand-softened PID would have broken forever.
  - **GAP-1, half discharged and deliberately so** (the user's call this
    session): `FrameConfig` landed FIRST, as its own commit, Kestrel-only, with
    the proof being a re-measure that reproduced every band and every factor
    byte-identical except the one cell v1.28 had already logged as unstable
    (`aim: flak` 0.94 -> 0.99, back toward its own mode). Then Atlas. The
    `WeaponConfig` split waits behind this, under the same discipline — a moved
    config and new content never share a measurement.
  - **Also landed:** `FlightConfig` gained `frame_id` and per-frame
    save/defaults paths (`default_flight_config.tres` ->
    `default_flight_kestrel.tres`) with a one-time migration, so a pilot's tuned
    override is not discarded in silence; `TunableConfig.identity_fields()`
    stops `copy_from` carrying an id between instances, closing a bug the
    BESTIARY preset bars had always been exposed to; the frame applies its own
    hull and armor in `FlightController._ready`, which closed a hole where the
    benches read `Health`'s default while the game read
    `CombatConfig.player_max_health` (both 100, by luck); `hover_check` now flies
    every frame in the roster, because the cheapest way to ship a frame that
    cannot hold the air is to write the `.tres` and never fly it; the overlay
    grew a FRAME section; `<godot> --path . -- --frame atlas` flies it today, as
    a dev affordance and explicitly NOT the picker — that is P3.8's briefing
    chain and P3.9's HANGAR section.
  - **Open, for the human (nothing acted on):** whether to bake the tuned flight
    values into `default_flight_kestrel.tres` (above); whether `Atlas x Turret`'s
    inverted sign should be chased with an ingress phase in the rig or accepted
    as outside the 1v1 scope; and everything v1.28 left open, all of it now
    measured under a different — and for the first time reproducible — ruler.
  - **Next: the raider-pack bench and the richer combat blackbox** (both sized in
    v1.29, both waiting on the user's word), then H.q4's hands-on calibration,
    whose case the ruler bug just strengthened again.
    **To resume after a session cut: "Continue QuadShot per the v1.30 entry."**
- **2026-07-23 — v1.31. The Kestrel's tuned feel becomes its shipped default,
  and the frame axis sharpens the moment the datum is the real drone.** The
  §14 decision v1.30 handed the human, taken: bake the flight config they had
  flown for months into the repo, so the instrument measures what ships. Small
  change, large consequence — two Atlas cells that read neutral against a bad
  datum told the truth against a good one.
  - **What was baked, and what deliberately was NOT.** Four FEEL fields into
    `default_flight_kestrel.tres`: `rate_p` 0.004→0.007, `rate_ff` 0→0.0008
    (feedforward on), `max_angle_deg` 55→56, `angular_damping` 0.02→0.013. The
    baked set lands *exactly* on the `Cruise` `rate_preset` — months of hand
    tuning had converged onto a bench-tuned preset, so the overlay now reads
    `Cruise` rather than `Custom`. **`input_profile` (RADIO_AETR) was NOT
    baked**: it is the human's hardware, not a feel value, and shipping it as
    the repo default would break every gamepad player (CLAUDE.md's stated
    primary controller). Their radio pick is preserved by re-homing the
    override to the new per-frame path `user://flight_kestrel.tres`, whose feel
    values now match the default — so it shadows nothing that matters and only
    carries the controller choice. The legacy `user://flight_config.tres` is
    retired, which also ends the v1.30 migration shim's job for this profile.
  - **The re-measure is the proof.** Only the Kestrel cells and the stamp
    moved: `aim: kestrel/blaster` **0.05 → 0.17** (the drone flies well again),
    `aim: kestrel/flak` 1.0 → 0.99. Every evasion cell, `splash`, and all three
    `atlas:*` aim cells came back unchanged — frame-independent by construction,
    and the Atlas's own config did not move. **The `config_stamp` changed, and
    it SHOULD have**: the frame's flight config joined the stamp in Phase 4b, so
    a Kestrel PID edit now correctly invalidates the old factors instead of
    silently quoting them. This is the staleness guard firing on exactly the
    kind of change that used to slip past it — the v1.30 fix demonstrating
    itself on its first real use.
  - **THE FRAME AXIS TOLD THE TRUTH ONCE THE DATUM WAS REAL — both moving cells
    are v1.30's predicted "moving zero", now with the sign that matters.**
    - `Atlas x Turret` `+` → `0`. On the bad default the Kestrel bled 30% hull
      killing a turret slowly, so the Atlas's patience looked like an advantage.
      On the real Kestrel the turret dies in **1.3 s for zero hull**, so the
      Atlas's armor buys nothing and its sluggishness *costs* 10%. The cell
      moved toward paper's `-`.
    - `Atlas x Aegis` `0` → `--`, and this is the sharp one. The real Kestrel is
      fast enough to **catch the aegis bomber and win**; the Atlas is too slow to
      intercept before it bombs, 6/6. On the bad default BOTH frames bombed, so
      the cell read a neutral `0` and hid the gap entirely. This is a **third**
      instance of the 1v1 rig not seeing what a P4.4 band is about — the gnat
      row saturated the ruler, the aegis row lacked a loadout system, and now
      the aegis row *also* runs into a pure-intercept deadline where the paper
      band was about missile-rack tonnage. Logged, not tuned: the Atlas being
      slow is P3.3's design ("it plants in the air", P4.4's SAM/open-ground
      `--`), and a bomber on a clock is simply the scenario that prices it. The
      open question for the human is whether the slice wants the heavy to have a
      bomber answer that is not "out-fly it" — which is exactly the loadout
      (missile racks) and the composition (don't take the heavy on a naked
      intercept) that later phases add.
  - **The strongest vindication of the v1.30 ruler fix is that it changed a
    band.** `Atlas x Aegis` was `0` under the machine-local ruler and is `--`
    under the committed one — the bad datum was not just imprecise, it was
    hiding a whole-magnitude frame weakness behind a false neutral. A relative
    ruler is only as honest as its origin, and the origin is now the drone the
    human actually flies.
  - **Open / next: unchanged from v1.30.** The raider-pack bench and richer
    combat blackbox (sized in v1.29) wait on the user's word; H.q4's human aim
    bench is now unblocked *and* better-founded, since the reference bot and the
    human will fly the same committed Kestrel. GAP-1's `WeaponConfig` half stays
    deferred. **To resume after a session cut: "Continue QuadShot per the v1.31
    entry."**
- **2026-07-23 — v1.32. The indoor dream arrives from a Tryp FPV session, and
  Iteration 8 is written: buildings you fly into, and a menu you fly.** User
  steering, their words kept: "indoors is such a game changer", "a tree of
  buildings each offer the leaf options in the form of floors", "neon lighted
  floors open fly through darker env hdr and cool neon lights shine the way" —
  and the sentence that belongs in this log permanently: **"yes, it is a game
  my friend. we've built this together, and its great already!"**
  - **Feasibility answered against the project, not from memory.** The
    renderer is Forward+ (checked in `project.godot`), so the whole toolbox is
    real: the "gets darker inside" moment is auto-exposure (the user's "hdr?"
    guess is right — it is the camera's eye adapting), which Godot 4 does via
    CameraAttributes; true interior darkness is mostly free (a shadow-casting
    sun cannot reach past a floor plate, and the neon-emissive look reads
    better in the dark); SDFGI and occlusion culling exist as later options,
    neither load-bearing. `LookConfig` already owns `exposure`,
    `ambient_energy` and the glow block, so the architecture is half-shipped:
    the look pass was accidentally built for indoors.
  - **The design key came from the user's follow-up line: light IS the
    enterability telegraph.** Open floors are lit (window-line emissive,
    interior neon — joining cyan/navigation in the palette), sealed floors are
    dark. The skyline reads as its own map at speed with no UI. Readability
    doctrine applied to architecture.
  - **Iteration 8 written (B1–B6, B.q1–q4), status PROPOSED.** Thesis: a
    building is a dungeon you fly — indoors inverts every outdoor knob and
    gives the 240 Hz model its second expression, precision. Kit: greybox
    furniture primitives + a SEEDED deterministic floor generator
    (theater_generator's discipline extended to geometry — a save that names a
    seed names a building). Buildings are floor stacks with enterability as a
    dial (open / sealed / under-construction). Combat indoors deliberately
    undecided (B.q1): the 1v1 void cannot price a corridor, so interiors are
    priced by the sortie harness when P2 arrives — the v1.25/v1.29 caveat
    family growing one member, stated on day one.
  - **The flyable menu (B5) is the first bite, chosen because it is a tech
    probe that ships as a feature**: one tiny hand-built tower, each open floor
    a menu leaf, fly in the window to pick. It answers every lighting question
    in a controlled room before the generator exists, and it teaches window
    ingress — the menu is the tutorial. Pinned but resisted: the briefing room
    (F2) and hangar (P3.9) want to be floors of this tower someday.
  - **The wedge, placed (B6)**: instrument pair (raider-pack bench + combat
    blackbox, already sized) → H.q4 when the human's hands are free → B5 menu
    tower — which touches nothing the harness measures, so it interleaves with
    H.q4 rather than queuing behind it → dev-room specimen building → P2-era
    composition. The user's "add another slice in between", honored as the
    next content phase after the instrument debt clears.
  - **Also this session (housekeeping):** the drone now prints its frame at
    boot (`[frame] flying Atlas (mass 1.24 kg, hull 190, armor 3)`) after the
    user flew the "Atlas" with a missing `--` separator and correctly felt
    nothing — the airframe you fly is never again a guess. Their Atlas
    verdict once it actually loaded: "way way sluggish, as i believe it
    should be... it does feel way different, very cool!" — P3.3's plant,
    confirmed by hands.
  - **Next: the instrument pair, user's go-ahead received** ("i trust your
    decision on what's next, go ahead") — raider-pack bench and the combat
    event blackbox, then H.q4 + B5 interleaved. **To resume after a session
    cut: "Continue QuadShot per the v1.32 entry."**
- **2026-07-23 — v1.33. The v1.29 queue discharged: the raider-pack bench
  measures the group fight, and the blackbox learns to see combat.** Both
  instruments built to their v1.29 sizing, at the user's go-ahead, in the
  same session as Iteration 8's writing.
  - **THE RAIDER-PACK ROW EXISTS, and the human's feel report survives
    measurement.** New `RaiderPack` fixture (gnat_swarm's interface exactly —
    destroyed/cleared/nearest_body/ai_seed — 3 bodies = wave 2 of sortie 1, a
    measurement grouping and not a game entity), three pack-mode matchup
    cells, and a `splash_only` delivery cell so the group's one new number
    cannot overwrite the single-raider evasion key. Measured: **`splash
    flak:raider` = 1.90** — one arriving burst covers ~2 of 3 raiders,
    sitting between the single-target 1.0 and the gnat cloud's 3.42 exactly
    where "raiders orbit looser than a swarm boils" predicts. And
    `Flak x Raiders` validates `++` (exchange +0.71, 2.3/3 bodies for 7%
    hull): **"flak really helps destroy groups of raiders" (v1.29) is now a
    number, and the number agrees with the hands.**
  - **A proposed paper band died on first contact, which is the system
    working in the embarrassing direction too.** The row's paper bands are
    PROPOSED here (P4.3 has no raider-pack row): blaster `0`, missile `-`,
    flak `+`. The missile proposal was contradicted the same hour it was
    written — `Missile x Raiders` validated `++` (three launches sweep the
    pack in 8.1 s for 9% hull, six of six). A 3-raider group is NOT the gnat
    bankruptcy in miniature: nine gnat bodies at a 3 s cadence is 24 s of
    exposure, but three raider bodies is 9 s and every launch is a
    one-hit kill. The proposal-to-measurement gap is logged rather than
    silently corrected; **react-by-ID: should the missile pack band be `0` or
    `+`?** (The measured evidence says `+` at N=3; the band would degrade as
    N grows — the cadence bill is linear in bodies.)
  - **`Blaster x Raiders` validated `-`, and the cell says out loud that it
    is bot-bounded** — the 0.17-aim reference pilot under tripled return fire
    kills zero raiders in six reps. Same limitation as the single-raider cell
    (hand-mode `++` there), inherited and stated in the cell comment. H.q4's
    human aim bench gains its fourth client.
  - **The blackbox now sees combat** (v1.29's second ask, built to its
    sizing): a sparse `events_<stamp>.csv` beside each `flight_<stamp>.csv` —
    one line per fired / hit / player_hit / spawn / kill / wave, with the
    event's own position where it has one (impact point, spawn point — the
    datum the flight file cannot carry). Emitters call the null-safe static
    `Blackbox.log_event` (the SoundBank precedent), so combat code holds no
    references and headless bench runs drop events for free — all suites pass
    with the hooks live. Hit events are player-team only; the enemy's side of
    the story is the `player_hit` line. **The next session read-back reports
    an actual hit rate instead of inferring "buzzing, not crashing" from
    position alone** — the exact limit the v1.29 read-back stated. First real
    file lands on the human's next flight.
  - **Also:** `aim: atlas/flak` wobbled 0.90 → 1.00 across the re-measure —
    the documented least-stable cell family (single-digit shells crossing the
    6° cone edge), no band moved, logged so it is not read as a change.
  - **Next: H.q4's human aim drill and B5's menu tower, interleaved** (the
    v1.32 wedge): the drill needs the human's hands, the tower needs nothing
    the harness measures. **To resume after a session cut: "Continue QuadShot
    per the v1.32/v1.33 entries."**
- **2026-07-23 — v1.34. The event log's first night: the human's own hit rate,
  read straight off the instrument — and the menu learns to fly in depth.**
  Same-day follow-up to v1.32/v1.33: the user flew both frames, reacted to the
  raider-pack row, and sent the flyable menu two levels deeper.
  - **THE FIRST REAL READ-BACK, and it lands the number v1.29 could only wish
    for.** Six evening sessions, every one with its `events_*.csv` companion.
    The combat story of the night, aggregated: **blaster 10–16%
    hits-per-shot-fired; missile 23/23 = 100%**. The human's real-combat
    blaster rate sits at almost exactly the reference pilot's much-caveated
    0.17 static-drill aim — the number three entries have flagged as "reads
    the bot, not the gun" is, in live combat with return fire, roughly the
    HUMAN's number too. Different measurements (moving fight vs static drill)
    so this does not close H.q4 — but it moves the prior hard: the 0.17 datum
    is not an indictment of the bot, it is what a chip gun's trigger costs
    against jinking targets. Also readable at last: kills per session (16, 5,
    15), damage taken per wave, and three sessions that were armed false
    starts — visible AS false starts now instead of mystery files.
  - **The log's first night also exposed its own gap, which is the point of
    first nights**: nothing in either CSV said WHICH FRAME flew the session.
    Attribution took motor-median inference (fails on this pilot — 0.5% hover
    time, v1.29) and the arithmetic that 194 damage taken exceeds a Kestrel's
    entire hull, so that session must be the Atlas. Fixed the same hour: a
    `session` event now opens every events file with the frame_id and hull.
    Data should say its name.
  - **A quiet flak note**: zero flak lines in the evening sessions. If the pod
    was fired tonight, the log missed it and that is a bug to chase; if it
    simply was not fired, the log just demonstrated it can prove a negative.
    Asked, not assumed.
  - **`Missile x Raiders` paper: the user's react lands it at `0`** (from the
    contradicted proposed `-`): "the missiles... get very effective,
    persistent raider killer." Recorded as `0` rather than the measured `++`'s
    `+` because a paper band is a promise across the row's real range, not a
    fit to N=3 — the cadence bill is linear in bodies, so the measured `++`
    decays as packs grow. The row now reads paper `0` → predicted `0` →
    validated `++` at N=3, gap understood and stated.
  - **B steering, first depths (folded into Iteration 8 as its steering
    subsection):** (1) **the menu tree is FLOWN in depth** — fly through a
    labeled window to select, exit the floor and the next menu level stands in
    front of you; re-thread backwards to go up a level; commit-on-exit so a
    graze is a scare, not a mis-pick. The M4 exit gate proved the verb; the
    menu makes it the grammar. (2) **B7 seeded: graded windows** — facades
    offering several neon-graded windows (red hard → blue beginner), which is
    P2.7's dares wearing B4's enterability telegraph, H6's difficulty curve
    made spatial and self-selected per second, a difficulty dial the B3
    generator and P2.11 both need, and a doorway P5 can price. (3) **B.q5**:
    the traffic-light grading vs the emissive palette roles — possibly
    harmony (red-hard agrees with red-threat), decided when B5 builds.
  - **Next: unchanged — H.q4's drill and B5's tower, interleaved.** B5 just
    got richer and better-specified, which is what steering is for. **To
    resume after a session cut: "Continue QuadShot per the v1.32–v1.34
    entries."**
- **2026-07-23 — v1.35. The zero explained: the slice's third weapon was
  unreachable on the primary controller — plus meaning chains and weather
  portals.** Closing the question v1.34 asked out loud.
  - **THE FLAK ZERO WAS REAL, AND IT WAS AN ERGONOMICS BUG, not a preference.**
    The user's answer, verbatim: "its true i didnt shoot any flak, there's no
    autofire. i simply flew with the radio, with which i dont try to do any
    manual firing, and i cannot move my hand to the keyboard." On the radio the
    blaster fires itself (the gun director), the missile launches itself
    (missile_auto_switch) — and the flak pod, directorless BY DESIGN (v1.28),
    had no path to the trigger at all. G needs a keyboard hand; RB does not
    exist on a TX16S. The event log's very first negative found a real hole:
    the weapon the human praised in v1.29 has been unusable on the controller
    they actually fly since the day it shipped — every flak feel report so far
    was flown on the gamepad.
  - **Fixed with a switch, not a director: `flak_switch`.** A fourth stateful
    binding (arm_switch's family — switch position = trigger held; the pod
    cycles at its own rate). Ships unbound; bound via the overlay BINDINGS
    press-to-bind like every switch. Deliberately NOT an autofire/director:
    the v1.28 purity decision stands — no aim logic, no solution computation,
    nothing the P4.3 column did not price. A hand that cannot leave the sticks
    can leave a switch on; that is the entire feature. The measured column is
    untouched (the reference pilot does not use it), so no re-measure.
  - **The radio confusion, named so it stops costing weapons:** "this radio
    has way more buttons and switches that the driver sees." Correct, and by
    design — in USB joystick mode a radio exposes CHANNELS, not switches. A
    switch the driver "cannot see" is a switch not mixed onto a channel. The
    path: on the radio, put the switch on a spare channel (CH5–CH8 in the
    AETR profile's world); it then arrives as an axis, which the BINDINGS
    press-to-bind already captures as a switch (that is exactly how
    arm_switch got bound). The M6 radio scope was "basic capabilities only";
    the slice now has more weapons than the radio has configured channels,
    and a short radio-side setup session is the actual fix. Queued for the
    user's bench time, with flak_switch waiting to be bound.
  - **B steering, second ripple (folded into Iteration 8):** **B8 — meaning
    chains** (routes that SAY something: fly a line word by window; memory
    dares, collectible sentences; flagged hard: famous lyrics are copyrighted,
    so chains ship public-domain/original — the idea is the chain, not the
    quotation). **B9 — the building as a time/weather portal** (enter at noon,
    exit at dusk: the interior MASKS the sky, so the whole sun/fog/weather
    swap happens where no one can see it — a scene transition with no cut,
    and LookController/WeatherConfig already own every knob it needs). B.q6:
    portal ships as menu magic first, or waits for simulated weather.
  - **Next: H.q4's drill + B5's tower, interleaved — unchanged, and now
    unblocked**: the drill needs all three weapons reachable from the radio,
    which flak_switch just made true (pending one radio-side channel setup).
    **To resume after a session cut: "Continue QuadShot per the v1.32–v1.35
    entries."**
- **2026-07-23 — v1.36. H.q4 built: the aim drill, where the human flies the
  bot's own ruler.** The user's call on order: drill first, flak_switch on
  their own time, "i want to get to the towers" — B5 is next.
  - **The drill is the bot's aim bench, flown by hands** (`scenes/aim_drill.tscn`,
    `scripts/tests/aim_drill.gd` — interactive, not headless). Same static
    immortal raider with the real hitbox, same 40 m spawn, same windows
    (blaster 20 s / missile 45 s / flak 40 s), same definition: hits per shot
    FIRED, the window opening at each weapon's own first shot. The human flies
    THEIR config (user overrides, their fire_assist setting, their frame —
    `--frame atlas` works here too), because the question is how THIS pilot
    deviates from the pinned datum, not how they'd fly a stranger's drone.
  - **Protocol, HUD-narrated**: arm and shoot; each weapon's window opens on
    its first shot and announces itself in the kill feed; at window end the
    HUD calls HOLD FIRE and counts stragglers through a grace sized to the
    round's own lifetime; each completed cell announces its rate and rewrites
    the artifact, so a partial drill still records what it measured. Death
    (crashing — nothing in the drill shoots back) respawns in place with
    windows running.
  - **Attribution without phases**: all three weapons are live at once — the
    human is not marched through stations — and connects are told apart by
    their damage numbers read from the live config (25 bolt / 60 missile / 10
    fragment), with a warning if any two are tuned equal and the flak count
    cross-checked against the pod's own counter (the two-counter discipline,
    third appearance).
  - **The artifact is labeled deviation data in its own first field**
    (`"pilot": "human (H5 ... never merged into the base table)"`), lands in
    `user://blackbox/aim_drill_<stamp>.json` beside the session logs, and
    records the frame flown and `fire_assist_miss_m` — the v1.34 lesson (data
    says its name) applied at birth. BALANCE.md's H5 bullet now points at the
    drill.
  - **What the first flight will answer**: whether the bot's 0.17 blaster
    datum — flagged provisional in four entries — is an indictment of the bot
    or the price of a chip gun, on the exact ruler where the bot scored it.
    v1.34's live-combat read (human 10–16% under return fire) predicts the
    drill lands NEAR the bot; a big static-drill gap the other way would
    instead say the bot wastes its static aim in combat. Either answer
    recalibrates every flak-vs-gun comparison in the log.
  - **Next: B5, the menu tower** — the user's own priority ("i want to get to
    the towers"), and the drill needs nothing more from the build side, only
    their hands. **To resume after a session cut: "Continue QuadShot per the
    v1.32–v1.36 entries."**
- **2026-07-23 — v1.37. B5 begins: the steering answered, and the tower's
  shell stands (checkpoint 1, unflown).** The build opened by resolving
  B.q2/B.q3 and scope with the user before any scene work — feel work gets
  steered first, built second.
  - **The steering, all answered** (folded into Iteration 8 as "the tower
    answered"): the leaf set is ALL FIVE (START RUN / FLY FREE / DEV ROOM /
    AIM DRILL / QUIT — the drill leaf gives H.q4 a doorway; FLY FREE needs a
    small no-waves flag on main, the one leaf without a scene today); the
    keyboard fallback is FOREVER and grew a design — **the side view**: with
    no controller, the menu shows the buildings from the side (center =
    current item, left = root, right = the selected leaf; arrows move, a
    detected controller drops into flight) — two cameras onto one
    architecture, nothing built twice, and the future depth tree's breadcrumb
    trail for free; B.q3 lands pure-menu-home-ready; scope is single-level
    first, the depth tree waiting on the verb proven in hands.
  - **Auto-exposure grown into the look pass, exactly as B2 promised — no new
    architecture.** LookConfig gains an "Auto Exposure" group (a 0/1 float
    switch in the all-float tunable idiom, plus scale / speed / min / max
    sensitivity); LookController owns a `CameraAttributesPractical` assigned
    to the WorldEnvironment, so the FPV and chase cameras share one adapting
    eye and every scene with a LookController gets it. Five new LOOK rows in
    the overlay. **On by default, game-wide — flagged out loud: the baked
    outdoor look may shift slightly on next boot; the off switch is the first
    new row.** The "darker inside" moment now exists for the human to tune.
  - **The shell stands** (`scenes/menu_tower.tscn` + `scripts/menu_tower.gd`,
    build-order step 1): a five-band tower 30 m ahead of spawn — sealed bands
    in dark glass, slab lips in `neon_structure` seams — with ONE open floor
    ~10 m up: a 3.0×2.2 m window opening (no glass, B2), cyan window-line
    emissive bars, a START RUN Label3D above it, a genuinely dark interior
    (thick walls, shadow-casting sun, one cyan omni), and the far-side
    opening already cut so step 2's commit-on-exit has somewhere to exit.
    The real drone arms in front of it; crashing respawns in place — the
    menu never punishes, it only waits. No selection logic yet: that is
    step 2's verb, after the human flies the room.
  - **Checkpoint 1 is OPEN: the human flies the shell** (`<exe> --path .
    scenes/menu_tower.tscn`) and hand-tunes the four questions this room was
    built to ask — the darkening on ingress (the auto-exposure moment), the
    window-line glow, the window size feel, and label readability on
    approach. **To resume after a session cut: "Continue QuadShot B5 per
    v1.37 — checkpoint 1 awaiting/flown."**
- **2026-07-23 — v1.38. Checkpoint 1 flown ("im excited"), and the verb goes
  live: fly-through glyphs, escalating windows, commit-on-exit.** The human
  flew the shell the same day and returned four verdicts; two bake, two build.
  - **The lighting answers are IN: darkening on ingress "yes please",
    window-line glow "absolutely."** B2's auto-exposure bet and the
    enterability telegraph both survive first contact with hands, at their
    shipped defaults — nothing retuned, nothing to bake beyond leaving the
    numbers alone.
  - **Window size verdict is new steering: ESCALATING GAPS.** The user:
    windows get "smaller and smaller — not too hard at the bottom leafs
    though." The tower adopts B7's difficulty-as-architecture for its own
    floors: generous windows low, tightening with altitude, so the menu is
    also a skill ladder read at a glance. Proposed floor order for step 3,
    bottom→top: QUIT (ground lobby, trivial), START RUN (big), FLY FREE,
    DEV ROOM, AIM DRILL (tightest — the drill's doorway is itself a drill).
    Exact sizes are cut at step 3 and tuned by hands, not asserted.
  - **The label verdict redesigns it into the game's first world-glyph
    object.** The user: the text "hovers on the same plane as the warp
    animation does, you fly through... 3d glowing text built out of
    primitives." Built: `GlowText3D` (`scripts/menu/glow_text_3d.gd`) — a
    5x7 dot-matrix font rendered as one MultiMesh of emissive cubes, no font
    assets, no collision; the Label3D on the facade is gone and START RUN
    now floats INSIDE the window aperture, read against the dark interior,
    flown straight through on ingress. Noted out loud: this object is the
    **B8 enabler** — word chains are exactly strings of these hung in the
    world.
  - **Step 2's verb is live on the open floor** (`scripts/menu/menu_floor.gd`,
    an Area3D spanning the interior): entering through the window announces
    the leaf on the kill feed; exiting the FAR side commits (logged +
    announced — step 3 swaps the log line for the actual launch); re-threading
    the entry window cancels. A crash respawn outside reads as cancel — the
    honest verdict for dying mid-decision. The exit-side test is the drone's
    local z against the room's half-depth, so the verdict comes from geometry,
    not from bookkeeping that could desync.
  - **Checkpoint 2 is OPEN: the human flies the threshold feel** — does
    commit-on-exit feel deliberate, does the graze-scare read as designed,
    do the fly-through glyphs land? **To resume after a session cut:
    "Continue QuadShot B5 per v1.38 — checkpoint 2 awaiting/flown."**
- **2026-07-23 — v1.39. Checkpoint 2 flown; step 3 lands whole: five floors,
  five launches, the side view, and the game now OPENS at the tower.** The
  human's verdicts: verb "ok", glyphs "great for now, serves the purpose",
  plus two asks — an exit-vector arrow after a graze, and "more dramatic"
  darkness ("the hdr... not very noticeable"); windows "can be larger — it's
  the main menu... very wide easy and inviting."
  - **The drama diagnosis, owned**: the weak effect was only half the eye —
    the interior itself was never truly dark (light-gray walls eating flat
    ambient + a bright omni). Fixed at both ends: interior surfaces go
    near-black (`MenuFloorFrame.INTERIOR_ALBEDO`), the interior omni drops to
    an accent, and the adaptation defaults deepen — speed 0.5→0.35 (the eye
    adapts as a visible process) and min_sensitivity 0→10 (a floor that stops
    the eye from fully compensating, so interiors reveal but STAY dark).
    Caveat stated: if the human saved LOOK after v1.37, the stale
    auto-exposure numbers in `user://look_config.tres` override these
    defaults — one press of LOOK Defaults reconciles.
  - **The exit vector**: three flat cyan chevrons march the interior floor
    toward the far window — runway markings in the navigation palette, the
    checkpoint-2 ask verbatim.
  - **Five floors, ESCALATING GAPS from a wider baseline** (both v1.38
    steering and the new "wide easy inviting" verdict): bottom→top QUIT
    (ground lobby door 4.0×2.8, sill 0), START RUN (5.0×2.8 — the widest,
    the front door), FLY FREE (4.0×2.6), DEV ROOM (3.2×2.2), AIM DRILL
    (2.4×1.8 — the drill's doorway is itself a drill). Built by
    `MenuFloorFrame` (`scripts/menu/menu_floor_frame.gd`), a parametric
    enclosure — explicitly NOT the B3 generator (no seeds, no rooms; five
    hand-chosen parameter sets in a .tscn that stays diff-readable where
    five copies of box-soup would not). The sealed dark-glass bands are
    gone; five lit windows stacked ARE the menu, readable as a column.
  - **Five launches**: committed floors change scene — START RUN → main,
    FLY FREE → main with `MenuLaunch.free_fly` (a new static-layer flag,
    RunMods' pattern, since change_scene carries no arguments; main.gd arms
    without starting the run: no waves, no score, no summary — B.q2's
    priced leaf, paid), DEV ROOM → dev_map, AIM DRILL → aim_drill, QUIT →
    quit. A directly-booted scene sees default flags and behaves exactly as
    before the menu existed.
  - **The side view ships** (the v1.37 two-cameras design, single-tower
    form): no controller → an outside camera frames the tower, ↑/↓ walk the
    selection floor to floor (the floor's glyphs flare and its interior
    wakes), Enter launches, Esc quits; a controller appearing at any moment
    drops the menu into flight. `Input.joy_connection_changed` drives the
    swap live.
  - **The game now opens at the tower**: `run/main_scene` flips to
    `menu_tower.tscn` — the fantasy from second zero (B5's own words), and
    CLAUDE.md's run instructions follow. `scenes/main.tscn` stays directly
    bootable for dev muscle memory.
  - **Checkpoint 3 is OPEN: the human flies the whole menu** — the darker
    dark, the chevrons, all five thresholds at their sizes, a real launch of
    each leaf, and the keyboard side view (unplug the controller). **To
    resume after a session cut: "Continue QuadShot B5 per v1.39 —
    checkpoint 3 awaiting/flown."**
- **2026-07-24 — v1.40. Checkpoint 3 flown ("you are amazing my dear
  friend"): the depth clarified, the arrow goes volumetric, the leash
  replaces the gate, and the wounded feed learns to stutter.** Verdicts:
  launches "works perfect", side view "works like a charm"; three
  corrections and one new ask, all folded into Iteration 8 as "the depth
  answered."
  - **Escalation corrected to PER-BUILDING** (the v1.39 per-floor reading
    was wrong): the first tower's windows flatten to a uniform easy
    baseline (4.5–5.0 wide, all floors); difficulty tightens per DEPTH
    level, on the submenu buildings that step 4 will **dynamically create
    in front of the player at commit** — the tree built as it is flown,
    the parametric-frame bet paying out.
  - **The volumetric exit arrow ships**: a pulsing 3D arrow (box shaft +
    cone head, primitives) floating mid-room on the entry-exit axis at
    window height — visible through the entry window BEFORE ingress, so
    the attack angle is set early; flown through on the crossing. Chevrons
    stay as floor markings.
  - **The signal leash ships in every game environment** (main/dev via
    main.gd, the drill in its own script): past 220 m the feed gains
    static (the glitch overlay — diegetic before textual) and the HUD nags
    SIGNAL WEAK; past 300 m the link drops and the menu tower catches you.
    The user's own simpler-better idea, replacing the return-gate notion.
  - **The wounded feed flickers** (D4 grown per the user's ask): random
    breakup bursts between hits, odds AND strength scaling with missing
    integrity — a scratched feed stutters, a dying feed crackles. Two new
    DamageConfig tunables (`video_flicker_rate` / `video_flicker_strength`),
    overlay rows included; bursts decay through the existing pipeline.
  - **The full-drama eye is recorded and deferred** (nice-to-have, the
    user's call): sun-blind windows, darkness-then-reveal, blinding
    white on exit — approximable by staging (brighter sun, darker rooms,
    wider sensitivity range), not by a switch; the night/neon environment
    may buy the fantasy cheaper. No build.
  - **Checkpoint 4 is OPEN: the human flies v1.40** — the floating arrow
    (does the pre-entry read work?), the flattened easy windows, the leash
    from any environment (fly away until the static wins), and the flicker
    while wounded. **To resume after a session cut: "Continue QuadShot B5
    per v1.40 — checkpoint 4 awaiting/flown."**
- **2026-07-24 — v1.41. Checkpoint 4 flown ("again, amazing job!"): the arrow
  moves into the window, the feed becomes EQUIPMENT, and tuning survives the
  scene change.** Leash approved ("works great"); two corrections and a
  quality-of-life ask.
  - **The arrow hangs IN the window now** (the user's clarification, and the
    reason finally lands: just LOOKING at a window from outside must name the
    trajectory to fly once inside — the read happens before ingress, not
    after). Tail at the aperture plane, body reaching inward along the exit
    line, sized up; the label glyphs float in front at the plane; both are
    flown through. When step 4 bends a floor's exit sideways, this arrow is
    what says so from the street.
  - **The video feed is EQUIPMENT (D2 grows a third subsystem).** The user's
    model, now understood and honored: the transmitter degrades per hit like
    the motors — a PERMANENT glitch floor plus flicker bursts whose odds and
    strength all key off accumulated `_video_damage`, not current integrity —
    and it heals with the airframe at the field patch (pads / gate /
    respawn), exactly where the motors heal. New DamageConfig knob
    `video_damage_scale` (equipment damage per relative hit size), overlay
    row included. The v1.40 integrity-keyed flicker was the right texture on
    the wrong variable; re-keyed, not re-invented.
  - **Live tuning now survives scene changes** (the config-continuity ask):
    `TunableConfig.load_from_user` gains a session guard — every scene's
    _ready still asks, but only the FIRST ask per save path actually reads
    the file; the shared instances persist in the resource cache, so what
    the overlay tuned in the menu is what flies in the map. The overlay's
    LOAD button forces a real re-read; FlightConfig's legacy-migration shim
    is fenced by the same guard. Save still persists across sessions.
  - **Preferred settings, baked where safe**: `motor_volume` 0.05 becomes
    the repo default (the "motor mute" preference is a product opinion,
    audio is balance-inert) with the empty user audio file retired
    (bake-then-delete). The "easy" combat preset was NOT baked into repo
    defaults — it moves measured ground (muzzle speed, assists, wave size;
    the harness pins repo configs) — but its values were copied user-side
    into `user://combat_config.tres`, so every boot now starts where the
    user's per-boot ritual used to end. Flight sport/cruise stays a manual
    pick per controller; auto-selecting rate preset by detected input
    profile is noted as a possible later nicety.
  - **Checkpoint 5 is OPEN: the human flies v1.41** — the in-window arrow
    read from outside, the permanent feed degradation across a fight and
    its heal at the gate, tuning surviving a menu→map→menu round trip, and
    the quiet motors on a fresh boot. **To resume after a session cut:
    "Continue QuadShot B5 per v1.41 — checkpoint 5 awaiting/flown."**
- **2026-07-24 — v1.42. Checkpoint 5 flown; the arrow retires, the void
  between floors, and the transmitter gets a real health bar.** The user's
  verdicts: config continuity "survives well, enough to stop being
  annoying"; the in-window arrow "sluggish... its head looks like a sphere"
  — retired at their call ("not your fault, its mine" — an experiment the
  build cycle was FOR); the feed model still not felt as equipment. Also:
  autonomy granted for a working block ("freedom to do as much work as you
  want... multiple commits"), reviewed incrementally on their return.
  - **The arrow is gone; chevrons rule, now on floor AND ceiling** (their
    suggestion): the exit vector reads whichever surface the pilot's eye
    hugs.
  - **The see-through-floors clip is fixed with geometry, not physics**
    (their constraint: "avoid messing with the collision physics logic at
    all cost"). Cause named: when the camera's near plane crosses a slab
    surface, backface culling makes the whole slab invisible — the camera
    sees straight into the neighbor floor. Fix: a VOID LINER — a thin
    near-black unshaded box nested inside every slab. Clipping through the
    slab surface now reveals the liner's dark face: at most, void. Zero
    collision changes, zero visual change when not clipping.
  - **The transmitter has HEALTH now, and it is READABLE.** The v1.41
    accumulator was the right model at imperceptible strength (one bolt =
    ~2% noise — arithmetic nobody could feel), which is why it read as
    "settings only." Reshaped to the user's spec: the settings define how
    loud a WRECKED transmitter gets; the equipment's own health is the knob
    over the knobs. Severity now scales the CHIPPING (exactly as it scales
    motor damage) instead of triple-damping the visuals;
    `video_damage_scale` default rises to 3.0 (a raider bolt ≈ 14% of the
    transmitter at severity 0.6); and the HUD's motor pips gain a fifth
    gauge — a VTX bar that drains and reddens on the same ramp, so a frying
    transmitter reads exactly like a frying motor. Field patch heals it,
    as before.
- **2026-07-24 — v1.43. STEP 4 STANDS: the menu is a tree of buildings,
  flown in depth — the next tower materializes when you commit.** Built in
  the user's autonomy block, same day as v1.42.
  - **One construction, every building**: `MenuBuilding`
    (`scripts/menu/menu_building.gd`) assembles a building at runtime —
    slab lips, void liners, roof, a `MenuFloorFrame` per floor — and the
    ROOT TOWER now builds through it too (menu_tower.tscn shrinks to
    environment + drone + cameras; the tower is data). One code path, so
    the root and every spawned sub-building can never drift apart.
  - **The tree, as authored data** (`MENU_TREE` in menu_tower.gd): START
    RUN and FLY FREE are now PARENTS — committing one spawns the FRAME
    TOWER 55 m ahead (the v1.40 mechanic verbatim: dynamically created in
    front of the player), a two-floor building offering KESTREL and ATLAS.
    Committing a frame launches the pending parent's scene with that
    airframe; re-threading the parent floor backwards despawns the
    sub-tower and clears the choice. Per-building escalation lives in the
    data: the root is all-easy (4.5–5.0 windows), the frame tower cuts to
    4.0×2.4 — depth costs precision, exactly the v1.40 steering.
  - **The frame pick is real**: `MenuLaunch.frame_id`, sticky across
    launches (your frame follows you until re-picked), honored by
    FlightController INSIDE the load_user_overrides gate and outranking
    the `--frame` CLI flag — benches see neither, Frames.build still names
    its own airframe. The dev CLI keeps working.
  - **The side view walks the tree** (the v1.37 design, now with its
    left/right axis): ↑/↓ floors, → dives into a submenu (spawning its
    building — the side view and the flown path share ALL machinery),
    ← backs out and despawns, Enter launches (or dives on a parent), Esc
    backs out then quits. The camera refocuses per building, eye level
    scaled to its height.
  - **A test hole found by the user's own preset** (the v1.41 user-side
    bake): missile_check loads user configs, and `fire_assist_miss_m 1.2`
    made the gun director auto-kill the dead-center plant before lock ever
    built. The check now pins fire assist to zero — game-side checks that
    load user configs must pin every field they depend on; the "easy"
    preset becoming the boot state is what exposed it.
  - **Checkpoint 6 is OPEN: the human flies the depth** — commit START
    RUN, watch the frame tower stand up ahead, thread ATLAS, feel the run
    start on the heavy frame; re-thread backwards to cancel; unplug the
    controller and walk the same tree with arrows. **To resume after a
    session cut: "Continue QuadShot B5 per v1.43 — checkpoint 6
    awaiting/flown."**
- **2026-07-24 — v1.44. Checkpoint 6 flown and approved; the VTX heals at the
  gate now; the procgen framework is planned.** The user returned from the
  autonomy block and flew the depth tree.
  - **The whole B5 flown menu is APPROVED**: depth "way better and cooler",
    the correct frame selected, backwards cancels as described, the ceiling
    chevrons "make the rooms feel like rooms", the void fix "100% solved —
    sticking to the edges feels way better, like a real floor/ceiling", the
    depth spacing fine ("as long as it's easy — it shouldn't be a
    challenge", logged as a constraint on any future depth mechanic).
  - **The VTX-at-gate bug, fixed and GUARDED.** The transmitter did not heal
    at the green repair gate though the motors did — because the gate calls
    `drone.repair_motors()` directly (motors live on the drone) while
    `_video_damage` lives in main, and the gate's `_on_engines_restored`
    callback refreshed the HUD without clearing the feed. Fixed by extracting
    `_repair_video()` so every field-patch path (full repair, gate, respawn)
    heals the feed through ONE helper; `repair_check` now wrecks the
    transmitter before the gate transit and asserts it comes back, so the
    two-paths-one-forgets bug cannot silently return. (This is the
    main.gd/drone damage-ownership split the queued review flagged — the fix
    is local; the split itself is still worth the review.)
  - **The procgen framework is PLANNED, not built** (folded into Iteration 8
    as "the silhouette and the generator"): the shorter sub-building is
    solved by FILLING it — full height, most floors sealed / under
    construction, each option guaranteed one open floor — which is B4's
    enterability meeting the menu and B3's first client. The generator is a
    pure `generate_building(seed, required_leaves, target_floors) ->
    floor_list` feeding the existing `MenuBuilding`; seed-driven like
    `theater_generator`; the same function that will fill a game skyline.
    The menu ships hand-authored floor lists until P2-era composition needs
    real enterable buildings.
  - **B5 is COMPLETE as a vertical slice**: the flyable menu ships, flown in
    depth, with its keyboard side view, and touches nothing the harness
    measures. **Next is a fork the human chooses** (see the session's
    what's-next): (a) the human's H.q4 aim-drill data run — the drill has
    waited for hands since v1.36; (b) begin B3/B4 the generator per this
    plan; or (c) the deferred motor_model/repair_gate damage-ownership
    review, now that Opus is driving and the repair_gate was just in hand.
    **To resume after a session cut: "Continue QuadShot per v1.44 — B5
    complete, awaiting the next-fork choice."**
- **2026-07-24 — v1.45. The aim drill flown on BOTH inputs (H5 lands), the
  damage review's findings acted on, and the HUD learns to scale.** The user
  chose the aim-drill run and the review; this entry closes both and does a
  round of HUD work.
  - **H5 DEVIATION DATA, both inputs — the bot ruler is validated by hands.**
    Two drill runs on the Kestrel, same 1.2 m assist the bench uses, so the
    blaster cell is apples-to-apples with the reference pilot (v3):
    - **Radio, focused blaster: 0.21** (17/81) vs bot **0.17** — the human is
      marginally better on the identical static drill. The 0.17 was never an
      indictment of the bot; ~0.2 hits-per-shot is just what a ballistic chip
      gun costs against a small hitbox, and hands confirm it. Four entries of
      doubt closed.
    - **Controller blaster: 0.07** (4/54) — NOT a clean aim sample and flagged
      as such: the user flew this run one-handed to spam flak, divided
      attention off the gun. It measures focus, not the controller. The radio
      0.21 is the usable blaster datum.
    - **Flak: 1.03** (39/38, controller) vs bot **0.99** — the v1.44 "too thin
      at 7 bursts" cell is now resolved at 38 bursts: human flak delivery
      matches the bot almost exactly.
    - **Missile: ~1.0** both runs (every launch lands on a static target),
      same as the bot.
    - Conclusion: **the human's delivery matches the reference pilot on all
      three weapons when measured cleanly.** This is H5 data — it stays in
      `user://blackbox/aim_drill_*.json`, never merged into the base table
      (BALANCE.md). The drill's purpose is discharged: the ruler is trusted.
  - **The damage-ownership review's findings, ACTED ON.** motor_model.gd came
    back clean. The two findings:
    - **The landmine is DEFUSED by deletion** (the user's call): the pad will
      never exist — "hovering is very difficult both with flying and with
      being exposed to damage; the healing gate is very good for now" — so the
      dead, motors-only `FlightController.repair_motors_by` /
      `MotorModel.repair_by` are gone. The would-be next incarnation of the
      gate bug is removed with them.
    - **The root cause (three-owner split) becomes a PLANNED refactor** — the
      user's own richer framing, recorded below.
  - **THE EQUIPMENT MODEL (planned, not built — the user's design, refined).**
    The user: the drone should OWN its equipment (VTX, weapons) as separate
    things that take their own damage; the drone is hit and reflects damage to
    what it owns; maybe the props are equipment too; unsure about props/frame.
    Assessment — it is sound and it is where the code already leans:
    - **`MotorModel` is already a proto-equipment** (owns per-motor health,
      turns damage into a capability loss). The VTX is the odd one out — a
      float in main.gd. The user's instinct correctly makes the VTX a peer of
      the motors instead of a special case in the orchestrator, which is
      exactly D2 ("the damage surfaces") growing a proper home, and the
      structural fix the review's Finding 2 asked for.
    - **The clean shape:** an `Equipment` interface — owns health 0..1, a
      `take_damage(hit)` that decides how much of a hit reaches it, a repair,
      and a capability readout. The drone holds a list and a small DAMAGE
      ROUTER: a hit routes consequences by location (which motor),
      probability (the VTX), or type. This generalizes today's
      `apply_hit_to_motors` and folds in the ad-hoc `_video_damage`, so
      main.gd stops owning the feed and every repair path calls one
      `repair_equipment()` — the three-owner split collapses, the gate-bug
      class cannot recur.
    - **Props/frame, resolved:** the FRAME is NOT equipment — it is the
      chassis/hull, the `Health` node, the HP that is your LIFE. Motors, VTX,
      (later) weapons ARE equipment — health that degrades a CAPABILITY, not
      survival, healed at the field patch. Frame = life, equipment = function.
      That line is the whole model and it is SIMPLER than today's three
      owners, not more complex. Not overcomplicated: it pays down existing
      debt.
    - **Refinement / caution:** keep it data-driven, no speculative class
      tower. Motors stay `MotorModel` (a specialized equipment with four
      sub-units sharing a mixer); `VtxTransmitter` is the second
      implementation; weapons implement `Equipment` only when they need
      damage (a jammed/degraded weapon). **Trigger: do the refactor when a
      SECOND equipment type needs damage** (weapons, or D2's other surfaces),
      so it lands against several subsystems at once — not now.
  - **HUD work (built this session):** (1) **window-relative scaling** —
    `display/window/stretch/mode = canvas_items` (base 1920×1080), so the whole
    UI now scales with the window instead of staying pixel-fixed when
    maximized (the core complaint). (2) **The motor pips + VTX bar moved to
    the bottom-left**, grouped with the stick indicators, out from under the
    score / kill-feed text they overlapped at the top-left. (3) **A `ui_scale`
    knob** on the HUD → the window's `content_scale_factor`, the native
    UI-zoom that respects anchors and the reference frame (scales all Control
    UI consistently). **Now LIVE-tunable** (the user's ask, done): `ui_scale`
    moved onto `LookConfig`, so the overlay's LOOK section tunes it with a
    slider and it saves/loads with the look presets; `LookController` applies
    it to `content_scale_factor` guarded (re-layout only on change, free when
    static — no per-frame render cost, which was the user's condition).
  - **Next: the user's call.** Options on the table: wire `ui_scale` live;
    begin the B3/B4 generator (v1.44 plan); or start the equipment refactor
    when a second damaged subsystem justifies it. **To resume after a session
    cut: "Continue QuadShot per v1.45 — B5 done, aim ruler validated,
    equipment model planned."**

- **2026-07-24 — v1.46. B3/B4 step 1 flown and approved: enterability states,
  and the sub-building silhouette FILLED.** The user chose the generator over
  the equipment refactor; this entry is its first checkpoint — the states plus
  a hand-authored mixed stack, the seeded generator itself deferred to step 2.
  - **`MenuFloorFrame` grows a `state` (open / sealed / under_construction).**
    Open is unchanged. SEALED = a solid glazed facade, no opening / label /
    zone — flown past, never into. UNDER_CONSTRUCTION = a bare amber scaffold
    (corner posts + two perimeter rings) over the slab, no facade, no entry.
    A closed floor carries no window, so its spec collapses to `{"state":
    &"sealed"}` — the exact minimal shape the generator will emit;
    `MenuBuilding` reads every spec key with a default, and the keyboard
    side-view walker steps over closed floors.
  - **The frame tower is now a full-height MIXED stack** (hand-authored bottom
    to top: sealed · KESTREL · under-construction · ATLAS · sealed) — the
    v1.44 "fill it, don't shrink the gap" silhouette fix, proven where we fly.
  - **The user's verdict, flown:** the silhouette "way better… reads as real
    architecture… easy to fly" — the fix LANDS, the stubby-sub-building flag is
    cleared. Sealed "simply a block, good for now." Under-construction
    "hollow, easy to fly through — OK for now," with a NAMED gap: real
    scaffolding is DENSE, noticeable, and OBSTRUCTS. That density is
    **deferred to the building-content enrichment pass** (B3's interior /
    furniture kit — the same primitive-combination kit that grows walls /
    pillars / crates). Today's sparse frame is a placeholder STATE; the
    obstruction is content, not plumbing, and lands when the kit does.
  - **Next: step 2 — the generator.** `generate_building(seed,
    required_leaves, target_floors) -> floor_list`, pure and deterministic
    (`theater_generator`'s discipline), replacing the hand-authored
    `FRAME_FLOORS` literal with a seeded call that emits this same mixed list.
    **To resume after a session cut: "Continue QuadShot per v1.46 — B3/B4
    step 1 flown, the generator (step 2) is next."**

- **2026-07-24 — v1.47. B3/B4 step 2 flown and approved: the generator is
  LIVE, and the menu's frame tower is seeded, not hand-drawn.** The user
  approved the generated tower ("all good for now") and steered the arc
  forward: "see how far we can go with procedural generation."
  - **`BuildingGenerator.generate(seed, required_leaves, target_floors) ->
    floor_list`** (building_generator.gd) — pure, deterministic,
    `theater_generator`'s discipline. Each required leaf owns one vertical
    BAND (options spread up the tower, never clump); the seed places its open
    floor inside the band and fills every other floor sealed /
    under-construction. Every leaf is GUARANTEED exactly one open floor. Same
    seed = same building forever, so a save naming a seed names a building (F4
    reaches menu geometry). Invariants covered by tests/building_gen_check.gd.
  - **menu_tower.gd**: the hand-authored `FRAME_FLOORS` literal is gone;
    `FRAME_LEAVES` + `FRAME_SEED` (5) + `FRAME_TARGET_FLOORS` (5) feed the
    generator at runtime, injected into the START RUN / FLY FREE submenus (one
    shared seeded building). Seed 5 reproduces the approved step-1 stack
    (sealed · KESTREL · under-construction · ATLAS · sealed) — the same read,
    now generated.
  - **Next: push procgen (the user's steer).** Options on the table, all
    standalone (they touch nothing the balance harness measures): a game-world
    SPECIMEN building in the dev room — the bridge from menu-building to
    world-building, where "open" becomes a windowed/enterable floor WITHOUT a
    menu commit zone — plus generator VARIETY (footprints, heights, shapes);
    a procedural CITY block / skyline; or interiors (the B3 room / furniture
    kit). **To resume after a session cut: "Continue QuadShot per v1.47 — the
    B3/B4 generator is live in the menu; pushing procgen into the game world
    next."**

- **2026-07-24 — v1.48. B3/B4 step 3a flown and approved: the generator
  crosses from the menu into the game world.** The user approved the dev-room
  specimen ("yes yes and yes") and continues the arc toward variety.
  - **The menu→world bridge**: MenuFloorFrame's menu furniture (label, exit
    chevrons, MenuFloor commit zone) now renders only on a floor with an
    actual menu leaf. A LEAFLESS open floor is just a lit, windowed, enterable
    opening — a world building's floor. One class, both roles; menu floors
    unchanged, verified.
  - **WorldBuilding** (scripts/environment/world_building.gd): a reusable node
    — exported seed / height / open-floor count → the generator's floor list →
    the runtime MenuBuilding builder. The dev room places ONE specimen at
    (0,0,-60) (seed 16, 11 floors, 4 enterable) standing beside the old solid
    placeholder city boxes it will replace; the city (later) places many.
    Guarded by tests/world_building_check.gd (world floors stay leafless, no
    menu furniture leaks in).
  - **Next: 3b — generator / geometry VARIETY.** Per-floor footprint, height
    and setbacks/tiers so buildings stop being identical 12×12 boxes, plus a
    scatter of WorldBuildings to preview a generated skyline against the
    placeholder one. Split into 3b-i (footprint + height variety across a
    scatter, buildings stay box-shaped) then 3b-ii (setbacks). **To resume
    after a session cut: "Continue QuadShot per v1.48 — the generator is in the
    world (dev-room specimen); building variety (3b) is next."**

- **2026-07-24 — v1.49. B3/B4 step 3b-i flown and approved: buildings vary in
  size, open from every side, and stand as a small skyline.** The user: "feels
  great." Three follow-ups — two handled here, one deferred as its own step.
  - **Per-floor footprint** (MenuFloorFrame + MenuBuilding): buildings take any
    width; slab plates size to the wider of each floor's neighbors, so the
    setback-ledge plumbing is already in (a plain box when every floor matches).
    Window width auto-clamps so a narrow tower still frames its opening.
  - **Crossed windows** (the user's ask): a world building's open floors carry
    openings + neon frames on ALL FOUR sides — enter from any direction — while
    the menu keeps front-entry / back-commit (`cross_windows` defaults off). One
    axis-helper refactor serves both; menu geometry unchanged, verified.
  - **The dev room is now a 6-building `GeneratedCity`** — varied footprint
    (8–16) and height (6–18 floors) — beside the solid placeholder boxes it will
    replace. WorldBuilding grew `footprint` + `cross_windows` exports; spacing
    widened per feedback.
  - **Fixed: a generated building clipped a placeholder box** (B3 over TowerM2 —
    "a fun mistake" but reined in): the cluster now stays clear of the +X
    placeholder lane.
  - **DEFERRED as its own step — SCALE (the user's call): "the world doesn't
    feel large enough."** The open floors read as too airy because the windows
    are too easy AND the buildings are too small in width and height. Next is a
    scale / difficulty pass: bigger footprints and heights, a larger sense of
    world, and tighter windows so floors read as solid architecture, not flimsy
    pavilions. Setbacks / tiers (3b-ii) remain queued behind it. **To resume
    after a session cut: "Continue QuadShot per v1.49 — building variety flown;
    the SCALE pass (bigger buildings + world + tighter windows) is next, then
    setbacks."**

- **2026-07-25 — v1.50. The SCALE pass: the world is big now, and the buildings
  are richer.** Two flights (scale, then richness), both approved — "towers feel
  larger as they should," "buildings feel big and high," "open/close fine,"
  "FPS flowing great."
  - **Big-world scale**: WorldBuilding defaults jumped (footprint 12 → 24, 11 →
    28 floors) and the window tightened (4.5×2.8 → 3.0×2.4), so it reads as a
    punched opening in a big wall, not an open bay — floors are solid, entry is a
    skill. The dev-room city is five towers, footprint 22–36 m, 16–40 floors,
    64–160 m tall.
  - **Taller → wider** (the user's rule): footprints track height across the
    cluster, with variation. **Open > closed**: enterable floors are now the
    majority. **Denser scaffolding**: under-construction floors are a full
    perimeter cage (posts stepping around every edge, scaled to footprint, four
    ring beams). **Closed floors** are glazed on all four sides with a faint
    mullion grid (curtain-wall, not a blank slab).
  - **Perf**: the per-floor interior light became MENU-ONLY — world open floors
    are lit by the environment through their openings, so an open-floor majority
    doesn't add ~80 lights. FPS held. The crash wall was relocated deep (z-200)
    to clear the city footprint.
  - **New backlog from feedback (noted, not yet built):**
    - **Real STREETS need a layout, not just gaps** — "no continuity (a road, a
      walkway); they're not arranged by street blocks." The scatter is buildings,
      not a city. Wants a procedural CITY LAYOUT: a road / block grid the
      generator places buildings into (the B4 "city" proper).
    - **Under-construction floors read as the building FLOATING** over empty air
      (you see through the skeletal floor). Likely fix: place uc floors at the
      TOP of the building — the crown being built, realistic, nothing floats
      above them — a generator placement rule.
  - **Next (the user's call): VARIED FLOOR HEIGHT** (per-building interior height
    → skyline + interior variety), then setbacks, then the city-layout grid.
    **To resume after a session cut: "Continue QuadShot per v1.50 — the scale
    pass is in; varied floor height is next, then setbacks and a real
    street-grid city layout."**

- **2026-07-25 — v1.51. Varied floor height, flown and approved ("awesome").**
  Interior (floor-to-ceiling) height is now per-building; MenuBuilding derives
  the floor pitch from it (`pitch = interior + slab`), so the slab always fills
  the gap between a ceiling and the next deck and the stack stays sound at any
  height. The dev city spans 3.6 m tight office floors (Q1) to 5.6 m grand
  floors (Q4); the menu is unchanged (default 3.6). The user then went AFK
  (~90 min) and asked for an independent work set — executed and logged in
  v1.52 (built + headless-verified, pending the user's flight).

- **2026-07-25 — v1.52. Autonomous AFK batch (the user out ~90 min, "work in
  quiet… we'll assess together").** Four building-system advances, each
  committed with headless tests. STATUS: STRUCTURE verified headless; every
  LOOK / FEEL judgment is explicitly deferred to the user's flight — the agent
  asserts none of it. Nothing here touches the balance harness (configs /
  combat / bestiary), so it is standalone and safe, like all of B.
  - **v1.52a — under-construction crown (the "floating" fix).** The generator
    gains a world-only `crown_at_top`: scaffold floors cluster as a seeded crown
    at the TOP (the floors still being built), not sprinkled mid-stack where a
    see-through skeletal floor made the tower look like it floats. Menu mode
    unchanged (RNG draw order preserved → every menu building byte-identical).
    `building_gen_check` asserts the crown is always contiguous at the top.
  - **v1.52b — setbacks / tiers (3b-ii).** WorldBuilding gains `setback_tiers` +
    `top_footprint`: the footprint steps down in discrete tiers up the tower.
    The slab-ledge plumbing (v1.48, slab sized to its wider neighbour) turns
    each step into a real ledge — the stepped-skyscraper silhouette.
  - **v1.52c — procedural CITY LAYOUT (the "real streets" flag).** `CityLayout`
    places WorldBuildings on a seeded cols×rows block grid separated by roads,
    so the streets are a connected grid, not a scatter. No two footprints can
    overlap (each capped to its block, blocks a road-width apart); amber
    centerlines mark the roads; empty lots leave skyline gaps. The dev room
    swaps the hand-placed 5-tower cluster for a `City` node (3×2, seed 20 → 5
    buildings + 1 lot), clear of the +X placeholder boxes. `city_layout_check`
    asserts on-grid placement, no overlaps, determinism.
  - **What still wants the user's hands / eyes:** does the crown read right; do
    the setback tiers look good and stay flyable; does the block-grid city feel
    like a city (street width, block size, density, the amber road lines); FPS
    across the whole grid. Plus the OPEN design questions surfaced for us to
    assess together — see the session rundown.
  - **To resume: "Continue QuadShot per v1.52 — crown + setbacks + a block-grid
    city are in (headless-verified); the user is about to fly them and pick the
    next path."**

- **2026-07-25 — v1.53. Correction: the under-construction "floating" flag was
  the WRONG fix; the real one is visible SUPPORT.** The user clarified: the
  problem was never WHERE the scaffold floors sit (mid-building is fine) — it was
  that a skeletal floor had no columns / rebar carrying the load, so the mass
  ABOVE looked unsupported. The v1.52a crown was a misread.
  - **Fix:** under-construction floors now build a full GRID of floor-to-ceiling
    columns (perimeter AND interior) plus a joist grid under the ceiling where
    the slab above lands — the load path made legible. World buildings stopped
    using `crown_at_top` (uc sprinkles mid-stack again, as the user prefers); the
    generator's crown mode stays available for a future topping-out type.
  - **User verdicts this round:** setbacks "actually nice, I like it"; the
    block-grid city "looks better"; replacing the hand cluster + keeping the
    placeholder boxes both fine.
  - **Roadmap set by the user:** deepen the city (breadth) → go indoors (B3
    interiors) → gameplay + tuning later. Plus a standing wish (saved to agent
    memory): a dedicated future conversation to deeply design procedural
    generation.
  - **Immediate direction (the user's):** move OUT of the dev room into a
    dedicated CITY MAP — fly the procedural city at scale and build toward
    interior generation. "Let's make the city feel real."

- **2026-07-25 — v1.54. "Deepen the city" beat 1: ROAD HIERARCHY + varied grain
  (built + headless-verified, pending the user's flight).** First checkpoint of
  the user-set breadth push ("make the city feel real"); the user picked
  *districts & road hierarchy* as the first bite. The change is deliberately one
  structural variable so the flight read is interpretable.
  - **What changed (`city_layout.gd` only, plus its check):** the uniform-`pitch`
    coordinate model is gone. Block widths now vary per COLUMN and depths per ROW
    (`block_variation`, floored at `MIN_BLOCK`), so the grain isn't a stamp — but
    a whole column shares one width and a whole row one depth, which keeps the
    **streets straight** (a scatter would zigzag them). Centres are accumulated
    from those varied sizes (X centred on 0, row 0 held at `front_z`), roads and
    the asphalt base derived from the true block extents rather than a fixed
    pitch.
  - **The main avenue:** one interior vertical street (seeded, biased toward the
    middle via best-of-two) is widened to `avenue_mult × road_width` (2.4× by
    default) — a canyon that runs the flight direction (-Z), a "fly down the main
    drag" moment. Its centerline draws `AVENUE_LINE_MULT` (2.6×) thicker so the
    hierarchy reads from three blocks out. Needs cols ≥ 3; disabled otherwise.
  - **Invariants held:** footprints still cap to their block's smaller dimension
    minus `BUILDING_MARGIN`, so no two overlap by construction (proven: the gap
    between adjacent rects = street + margin > 0 regardless of variation).
    Deterministic — `city_layout_check` now also asserts the avenue street is
    valid and seed-stable. All checks green (city_layout / world_building /
    building_gen / menu), city_map + dev_map boot clean headless.
  - **Note:** a given seed's city changes vs v1.53b (new layout draws reorder the
    RNG stream) — fine, no save depends on it yet. Held to ONE avenue axis
    (vertical); a cross-avenue / alley tier and height-ZONING districts
    (downtown-core-taller) are the natural next bites, kept separate so each
    flies as its own variable.
  - **To resume: "Continue QuadShot per v1.54 — road hierarchy (a main avenue +
    varied block grain) is in, headless-verified; the user is about to fly it.
    Next breadth bites queued: height-zoning districts, then ground life
    (sidewalks/streetlights/haze), then B3 interiors."**
  - **v1.54 FLOWN & APPROVED** (same session): "coming nicely," 144 FPS solid,
    the avenue reads as the main street from above, the varied grain "looks more
    like a street instead of a messy random builds set." Committed. Housekeeping
    the user OK'd: the stale `balance-model-handoff.md` (the fully-adopted seed
    doc for the balance instrument) recycled; `city.tscn`'s ~20 dead duplication
    sub_resources trimmed (load_steps 37→14).

- **2026-07-25 — v1.55. "Deepen the city" beat 2: HEIGHT ZONING — a downtown
  core (built + headless-verified, pending the user's flight).** The *districts*
  half of the user's chosen bite (v1.54 was the road hierarchy). Building height
  now follows distance from a seeded DOWNTOWN CORE snapped to a real block
  flanking the avenue: tall downtown, tapering to low-rise at the fringe, so the
  skyline has a shape you read from the air. Still `city_layout.gd` only + its
  check — touches nothing the balance harness measures.
  - **Mechanism:** `_zone(c,r)` = pow(1 − normalised core-distance, `core_falloff`),
    1 at the core cell → 0 at the farthest corner. Floors = a zoned target
    lerp(min,max,zone) blended by `zone_strength` against a flat mid, plus
    bounded `zone_jitter` so a district reads as a cluster, not a smooth dome.
    Setbacks cluster downtown too (`setback_core_bonus` scaled by the zone). Four
    new Inspector knobs, all defaulted; zoning turns off at `zone_strength = 0`.
  - **The core must be a real cell:** the first pass floated it at a half-cell
    between blocks, so the tallest tower undershot max_floors (topped ~21/30).
    Snapping the core to a block adjacent to the avenue fixes it — seed-42 4×3
    (10–30 floors) now spans [10,11,12,13,16,18,21,23,28], a genuine core→fringe
    taper reaching near the top.
  - **Invariants held:** placement / no-overlap / determinism unchanged;
    `city_layout_check` now also asserts the core zone reads strictly taller than
    the fringe and is seed-stable. All checks green; city_map + dev_map boot clean.
  - **To resume: "Continue QuadShot per v1.55 — height-zoning districts (a
    downtown core along the avenue) are in, headless-verified; the user is about
    to fly it. Next breadth bites: ground life (sidewalks/streetlights/haze),
    then B3 interiors."**
  - **v1.55 FLOWN & APPROVED** (same session): recognizable skyline shape, clear
    from above AND below where downtown is; the core reads along the avenue;
    setback clustering makes downtown obvious. Committed. Two follow-ups the user
    raised → v1.56.

- **2026-07-25 — v1.56. Live CITY overlay + a lighter default (built + headless-
  verified, pending the user's flight).** Two things the v1.55 flight surfaced:
  (1) scaling the city map to 6×5 (~26 buildings) dropped FPS with deep hitches —
  the greybox floor-stacks are draw-call-heavy; and (2) the procgen knobs lived
  only in the Inspector, breaking the project's live-tuning workflow.
  - **Lighter default:** the city map is now **4×5** (~18 buildings), a perf-safe
    default after the 6×5 drop. Real scaling waits on a perf pass (LOD / culling /
    mesh-merge) — flagged, not yet done.
  - **The CITY overlay section (`debug_overlay.gd`):** live sliders for the whole
    `CityLayout` — grid (cols/rows/block/road/avenue/variation), floors, empties,
    setbacks, and all four zoning knobs — plus **Regenerate** and **Re-roll seed**
    buttons. The city rebuilds on the button, not per-slider, so dragging a big
    grid never hitches; the overlay's FPS readout up top makes this the **procgen
    perf-budget tool** (dial cols/rows/max_floors, Regenerate, watch FPS). Found
    via `find_children` (race-free, no scene wiring), so it lights up in the city
    map AND the dev room, and is skipped in main.tscn like LOOK.
  - **`CityLayout.rebuild()`:** `_ready` now delegates to a `rebuild()` that frees
    existing geometry first and re-runs grid + roads + buildings from the current
    exports; `_lay_grid` clears its arrays so it's idempotent. Determinism intact
    (`city_layout_check` still PASS).
  - **Not persisted (by design):** CityLayout isn't a `TunableConfig`, so the
    overlay's Save/Load/Defaults don't touch it — the .tscn Inspector stays the
    persistent home. Live-explore in the overlay; when a config feels right, bake
    it into `city.tscn` (the same bake-when-right pattern as flight defaults).
  - **To resume: "Continue QuadShot per v1.56 — a live CITY overlay section
    (Regenerate / Re-roll seed, doubles as the FPS-budget tool) + a 4×5 default
    are in, headless-verified; the user is about to fly/tune. Open: a perf pass
    (LOD/culling) before scaling the city up, then ground life, then B3
    interiors."**
  - **v1.56 FLOWN & APPROVED** ("awesome"): the CITY overlay works (sliders /
    Regenerate / Re-roll). Confirmed the section shows in the city map AND the
    dev room (any scene with a CityLayout), not just the city map. Committed.

- **2026-07-25 — v1.57. Perf pass: mesh-batching the buildings (built + headless-
  MEASURED, pending the user's flight).** The 6×5 FPS drop was a draw-call
  explosion: every wall, pier, window-bar, mullion, column, beam, joist, slab and
  liner was its own `MeshInstance3D` (`_add_box`), so one 25-floor building was
  ~800–1000 draw calls and the 4×5 city measured **10,314** MeshInstance3D.
  - **The fix — `BoxBatcher` (`scripts/menu/box_batcher.gd`):** a RefCounted that
    accumulates unit boxes by material via `SurfaceTool.append_from` (offset/yaw
    baked into the mesh) and commits one merged `MeshInstance3D` per material.
    `MenuFloorFrame._add_box` now batches the visual and commits once in `_ready`
    (a floor → ~1–2 draw calls, not dozens); `MenuBuilding` batches all slabs +
    all liners into one mesh each. Collision is untouched (still per-box).
  - **MEASURED: 10,314 → 651 MeshInstance3D at 4×5 — a 15.8× draw-call cut**
    (the rare headless-measurable win; FPS-in-engine is still the user's to
    confirm). All checks PASS (menu/world_building/building_gen/city_layout);
    city_map + menu_tower + dev_map boot clean.
  - **Why it's visually identical:** the `neon_structure` slab shader is
    world-space (`MODEL_MATRIX * VERTEX`); baking the box offset into a
    frame-local mesh and letting the MeshInstance's transform place it preserves
    the exact world position, so the seams don't shift. Standard-material walls/
    lines/glass keep their UVs/normals through `append_from`.
  - **Still per-box:** collision (4,183 shapes at 4×5) — untouched, static, and
    not the render bottleneck. If node-count/physics ever bites, merging a
    building's solids into one concave shape is the next lever; not needed yet.
  - **To resume: "Continue QuadShot per v1.57 — building meshes are batched by
    material (15.8× fewer draw calls, headless-measured); the user is about to
    fly it to confirm FPS is solid again and push the city bigger via the CITY
    overlay. Then: ground life, then B3 interiors."**
  - **v1.57 FLOWN & APPROVED** ("AMAZING JOB"): pushed the city to 10×10 with no
    FPS flinch (longer generate time, as expected and fine); no visual
    regression. Committed. Draw-call ceiling is gone — the path is open again.

- **2026-07-25 — v1.58. Ground life beat 1: sidewalks / curbs (flown plain, then
  refined; refined version pending re-flight).** First bite of the user-chosen
  ground-life pass (roadmap item 2). Each block lifts a raised sidewalk slab a
  curb (0.15 m) above the road, so the streets read as sunken roadways between
  raised blocks — the ground plane the streetlights and props will sit on.
  - **Flown-plain feedback → refinements this beat:** curbs read a touch thin
    (user suspects the world scale, will fly more to feel it — curb height held);
    "brighter color, and maybe their edges get colors" → sidewalk brightened to a
    pale concrete and a **cyan neon curb line** now runs each raised block's top
    edges (navigation palette: pedestrian ways glow cool, roads stay amber).
  - **Empty-lot variety (user's ask):** lots roll up front (`_roll_lots`) into
    OCCUPIED / PLAZA (raised) / SUNKEN, split by a new `plaza_chance` knob (X%
    plazas, rest sunken); sunken lots get an **amber painted border** so a gap
    reads as a deliberate plot, not a hole. `plaza_chance` joins the CITY overlay.
  - **Wide-road placement rule (user's rule):** a block's empty chance scales by
    `road_width / widest-bordering-road`, so blocks flanking the wide avenue are
    ~0.42× as likely to be empty — prime avenue frontage is built up, gaps fall
    on the narrow back streets (reinforcing the downtown core, which is also on
    the avenue). Parameter-free; measured over 600 seeds: avenue-flanking columns
    0.09 empty vs 0.19 elsewhere at `empty_chance` 0.2.
  - **Still batched:** slab / curb-trim / lot-marking each merge by material — 3
    draw calls for ALL ground life across the whole grid, even at 10×10. Lots are
    decided before both the sidewalk and building passes so they agree;
    determinism intact (`city_layout_check` PASS). city_map + dev_map + main boot
    clean. (Seed cities re-rolled: the plaza/sunken draws reorder the RNG — fine,
    no save depends on it.)
  - **Leash fix (bug surfaced this flight):** the FPV signal leash yanked the
    pilot to the menu past 300 m from origin — a combat-arena mechanic that a big
    city sprawls straight past. `RANGE_WARN_M`/`RANGE_LOST_M` are now
    `@export signal_warn_m`/`signal_lost_m` on `main.gd`, disabled at
    `signal_lost_m <= 0`; the exploration scenes (city_map, dev_map) set it 0.
    main.tscn (the combat slice) keeps the leash.
  - **Queued next (ground life):** streetlights (budgeted, emissive-forward), low
    props, distance haze. Plus the user's **measurement visual mode** (a toggle
    that labels building width/height, street width, etc.) — a standalone tool
    beat. Then B3 interiors.
  - **To resume: "Continue QuadShot per v1.58 — sidewalks + cyan curb trim +
    empty-lot variety (plaza/sunken) are in and the signal leash is off in the
    city, headless-verified; the user is about to re-fly. Next: the measurement
    visual mode (its own beat), then streetlights/props/haze, then B3 interiors."**

- **2026-07-25 — v1.59. Ground life beat 2: streetlights (built + headless-
  verified, pending flight).** Terminology got clarified first — a "plaza" is a
  raised empty lot with **no content yet** (bare, as the user noticed; a plaza
  earns its garden/park identity only once props land). The user then asked to
  "proceed with the other objects" for a scale reference. Streetlights first:
  amber lamp-posts at every block edge's midpoint, on the sidewalk facing the
  road — human vertical scale (~6 m), warm rhythm, light on the dark streets;
  both sides of every street lit by adjacent blocks' edge lights.
  - **Emissive heads, no real lights:** the head glows via bloom (energy 2.5), no
    OmniLight, so the count stays free. Pole + head batch into 2 meshes for the
    whole grid (measured: 4×5 draw calls 568 → 570, +2 total). Scenery:
    non-colliding for now (add collision later for a slalom hazard if wanted).
  - `city_layout_check` PASS; city_map + dev_map boot clean.
  - **Also pending from just before (v1.58b):** the empty-lot placement rule —
    wide-avenue frontage builds up (avenue-flanking columns ~0.42× as likely
    empty; measured 0.09 vs 0.19 at empty_chance 0.2).
  - **Queued next (ground life):** greenery / props — the bite that gives PLAZAS
    their garden/park identity (the user's mental model) and dresses the bare
    sidewalks. The aesthetic of greenery in a neon-noir city is the user's call —
    ASK before building. Then maybe the measurement mode (or skip it if the
    scaled objects give enough scale sense — user's call). Then B3 interiors.
  - **To resume: "Continue QuadShot per v1.59 — streetlights (amber emissive
    lamp-posts, batched, +2 draw calls) + the wide-road empty-lot rule are in,
    headless-verified; the user is about to fly. Next: greenery/props for plaza
    identity (ask the aesthetic first), then maybe the measurement mode, then B3
    interiors."**

- **2026-07-25 — v1.60. Streetlight placement + a LOOK preset spread (AFK batch,
  built + headless-verified).** The user flew v1.59 (poles "good" for scale),
  gave a placement rule, asked for lighting presets, and went AFK with "commit
  and go ahead — do anything you can without my input."
  - **Streetlights flank, not block (user's rule):** moved from edge-midpoints
    (dead in front of the centered ground-floor window) to the four block
    CORNERS, inset onto the sidewalk — a light now sits beside openings, and
    corners of adjacent blocks light every intersection. Same 2 draw calls.
    **Deferred** (needs the user's eyes + per-building opening data): the
    entrance-aware half — lit where a building actually opens, darker in blind
    alleys with no opening. Noted, not guessed.
  - **LOOK preset spread (user's ask — "nights with/without fog, how the city
    lights seam together"):** six LookConfig presets generated into
    `user://presets/look/` (loadable from the LOOK preset dropdown): Clear Night,
    Foggy Night, Dense Fog, Neon Overdrive, Dusk (the shipped default anchor),
    Clear Day. Each starts from defaults and overrides sun/ambient/fog/glow for a
    distinct mood — a spread to range over, not final looks. They live in user://
    (per-machine, uncommitted); bake favorites into `default_look_config` / the
    repo when the user picks winners (the usual bake-when-right pattern).
  - Also in this session's commit: the wide-road empty-lot rule (v1.58b) and the
    streetlights (v1.59). All headless-verified — `city_layout_check` PASS,
    city_map/dev_map boot clean, ground life stays cheap (sidewalks + curb trim +
    lot markings + streetlights ≈ 5 draw calls total across the whole grid).
  - **To resume: "Continue QuadShot per v1.60 — streetlights flank block corners,
    6 night/fog LOOK presets are in user://presets/look/, empty-lot rule live;
    the user is about to fly + range the look presets. Next: greenery/props for
    plaza identity (ASK the neon-vs-natural aesthetic first), the entrance-aware
    streetlight refinement, maybe the measurement mode, then B3 interiors."**

- **2026-07-25 — v1.61. CITY menu leaf + entrance-aware lighting (built +
  headless-verified, pending flight).** Two confirmations from the AFK-return.
  - **CITY on the boot menu:** a new root leaf (QUIT / START RUN / FLY FREE /
    **CITY** / DEV ROOM / AIM DRILL) launches `city_map.tscn` as free-fly — fly
    the city from the menu, no CLI. `_change_scene` sets free_fly for `city` as
    well as `fly_free` (the subtlety flagged last turn); `menu_check` updated to
    6 root floors.
  - **Entrance-aware lighting (user's rule — "the less central a side, the less
    lit"):** each block-corner streetlight is placed only if that corner faces
    the downtown core (dot of corner-dir vs core-dir > `STREETLIGHT_CENTRALITY_CUT`);
    blocks within `STREETLIGHT_CORE_RADIUS` of the core light all corners. The
    core glows; outward sides fade to dark blind alleys toward the rim. Still 2
    draw calls (gating just drops poles from the batch). **Coupled next step:**
    the building-side — actual entrances/windows facing the core, sealed
    outward — needs per-side opening control in `MenuFloorFrame` (today's
    `cross_windows` is all-4-or-nothing).
  - `menu_check` + `city_layout_check` PASS; menu_tower + city_map boot clean.
  - **To resume: "Continue QuadShot per v1.61 — CITY is a boot-menu leaf (free-
    fly) and streetlights gate by core-facing centrality; the user is about to
    fly. Next: the building-side of the centrality rule (core-facing entrances),
    then greenery/props starting with NATURAL (then cyberpunk-centre /
    urban-edge by zone), then B3 interiors."**

- **2026-07-25 — v1.62. Building-side of the centrality rule: core-facing
  entrances (built + headless-verified, pending flight).** The coupled other half
  of v1.61's lighting — buildings now OPEN toward the downtown core and SEAL the
  outward sides, so entrances face inward and the rim shows blind walls (the
  user's "the less central a side, the less entrance").
  - **Per-side openings:** `MenuFloorFrame` gains `open_sides` (4 bools
    [front +Z, back -Z, right +X, left -X]) — each side opened+windowed or a solid
    wall (new `_build_solid_wall`). When set it takes over from `cross_windows`;
    empty keeps the legacy menu path (front-entry / back-commit) **untouched**.
    Threaded `WorldBuilding` → `MenuBuilding` → frame; `CityLayout._facing_open_sides`
    (cut −0.35) computes each building's mask from its position vs the core:
    core-adjacent buildings open all four, axis-aligned edge buildings seal their
    one fully-outward side, diagonal-far ones seal the outward pair.
  - **Verified directional (probe, seed-42 4×5):** the core cell opens FBRL; the
    far −Z rows seal Back; the far +X column seals Right; the far corner opens
    only Front+Left (its two core-facing sides). Exactly the intended gradient.
  - Bonus: collision shapes dropped 3668 → 3014 (a sealed side is one wall, not
    several window piers) — lighter physics. Draw calls unchanged (batched).
  - `world_building` / `menu` / `building_gen` / `city_layout` checks PASS;
    menu_tower + city_map + dev_map boot clean; the MENU is untouched.
  - **To resume: "Continue QuadShot per v1.62 — buildings open toward the core /
    seal outward (entrances follow centrality), verified directional; the user is
    about to fly. Next: greenery/props starting with NATURAL (then
    cyberpunk-centre / urban-edge by zone), then B3 interiors."**

- **2026-07-25 — v1.63. Ground life: natural greenery (built + headless-verified,
  pending flight).** The first greenery bite — and the one that finally gives
  PLAZAS their identity. NATURAL style (matte trees + planters, not neon), placed
  everywhere for now; the zonal cyberpunk-centre / urban-edge split is the next
  layer on top.
  - **Plazas → little parks:** a jittered grid of mostly greybox trees (slim
    trunk + boxy canopy) plus the odd planter (box + hedge) on the raised slab —
    a "plaza" now reads as a garden, resolving the v1.58 naming confusion.
  - **Occupied blocks → street trees.** *Flown: plazas-as-parks approved; street
    trees at edge-centres were blocking the windows.* **v1.63b fix:** trees now
    go only on a building's **sealed** sides (the blank outward walls, from
    v1.62's `_facing_open_sides`), so they can never block an opening and they
    soften the rim-facing walls; core blocks (open all round) get none.
  - **Cheap + deterministic:** a private greenery seed (layout_seed·977+13) so
    the building RNG stream is untouched (the city is byte-identical, greenery
    lands on top); all trees/planters batch into 3 meshes (trunk / foliage /
    planter) for the whole grid — measured +3 draw calls at 4×5 (570 → 573).
    Non-colliding scenery for now.
  - `city_layout_check` PASS; city_map + dev_map boot clean.
  - **To resume: "Continue QuadShot per v1.63 — natural greenery (park plazas +
    street trees, matte, +3 draw calls) is in; the user is about to fly. Next:
    zonal styling (cyberpunk greenery in the centre, urban hardscape at the
    edges) layered on the same placement, then B3 interiors."**

- **2026-07-25 — v1.64. Ground life: zonal prop styling (built + headless-
  verified, pending flight).** The user's centre-lush / edge-gritty vision, on the
  v1.63 framework: a block's ground props follow its height-zone — CYBERPUNK
  bio-luminescent greenery at the lush core, NATURAL matte trees in the mid ring,
  URBAN hardscape (kiosks + benches, no green) at the rim.
  - **Shapes reused, materials swapped:** a "cyber tree" is the same tree with a
    glowing canopy; a cyber hedge is the planter with a glowing top. Only urban
    adds shapes (kiosk + lit sign, bench). Style picked by `_prop_style` off
    `_zone` (CYBER ≥ 0.6, NATURAL ≥ 0.3, else URBAN); plazas fill with the zone's
    park, occupied blocks get the zone's prop on each sealed side (still the
    v1.63b never-block-an-opening rule).
  - **Verified gradient (probe, seed-42 6×5):** a C cluster on the core, an N
    ring around it, U at every edge — exactly centre-lush → rim-gritty.
  - Batched: up to 7 prop materials → +4 draw calls vs the natural-only pass
    (573 → 577 at 4×5). `city_layout_check` PASS; city_map + dev_map boot clean.
  - **To resume: "Continue QuadShot per v1.64 — ground props style by zone (cyber
    core / natural mid / urban rim), verified gradient; the user is about to fly.
    BREADTH is deep now (layout, road hierarchy, districts, ground life, facing/
    lighting rules); the roadmap's next turn is DEPTH — B3 INTERIORS."**

- **2026-07-26 — v1.65. B3 INTERIORS, Beats 1–5 + wayfinding (autonomous AFK
  batch, built + headless-verified, pending the user's flight).** The depth turn:
  hollow open floors become flyable open-plan interiors. Designed design-only first
  (spec `docs/superpowers/specs/2026-07-25-b3-interiors-design.md`, plan
  `docs/superpowers/plans/2026-07-25-b3-interiors.md`); this is the implementation,
  run as a one-hour AFK batch to a "decent flyable level" (Beat 6's game-wide
  auto-exposure deliberately deferred to a hands-on pass). The four settled
  decisions (open-plan / district-linked / district-restructures-the-profile /
  refined-B) held.
  - **Beat 1 (b5ecd01) — two pure generators + a headless check.**
    `InteriorGenerator` (scripts/environment): channels between every open window →
    a hub (Fold 2, flyability), a sparse structural column grid (Fold 1, nothing
    floats), then a rejection-sampled furniture scatter, all seeded/deterministic.
    `BuildingProgram`: the per-district vertical profile (cyber → server-farm-heavy
    + sky-lobby, natural → lobby/warehouse/office/atrium, urban → dock/warehouse;
    ground always a lobby-atrium). `interior_gen_check` sweeps 6 programs × 4 side
    masks × 5 seeds asserting determinism, channel flyability, min-clearance, and a
    restructured profile. PASS.
  - **Beat 2 (cfee5cb) — the render hook (one path preserved).** `InteriorBuilder`
    (scripts/menu) expands a spec into a freeable **"Interior" child subtree**
    (batched boxes + per-box collision), districted palette reusing CityLayout's
    zonal colours. `MenuFloorFrame` gains `interior`/`district`/
    `interior_lod_managed` + `build_interior()`/`clear_interior()`; `MenuBuilding`
    threads them; `WorldBuilding` stamps a spec per OPEN floor (seed =
    `building_seed*1000003 + k`, F4; never touches the layout RNG). A 6-floor office
    specimen in `dev_map`. Probe: 6/6 floors furnished, 12 batched meshes, 225
    collision shapes.
  - **Beat 3 (88fefc7) — the full furniture kit.** Warehouse (racking/pallet/crate),
    atrium (planter/bench/feature/counter), server-farm (server-rack), dock
    (container) `_emit` cases; four more `dev_map` specimens, one per program at its
    home district. Variety by combination.
  - **Beat 4 (00bc576) — districted city plumbing.** `CityLayout.interiors_enabled`
    (default off): each building furnished, districted by its block's `_prop_style`
    zone, `interior_lod=true`. Defaults off → existing checks/perf untouched.
  - **Beat 5 (374e0df) — building-level distance LOD + the furnished city.**
    `WorldBuilding._process` furnishes open floors when the drone (group **"player"**
    — the plan's assumed "drone" was wrong, caught on verify) is within
    `interior_lod_radius` (140 m, +20 hysteresis), frees them beyond; rebuilds
    deterministically. `city.tscn` interiors ON → `city_map` + the CITY leaf show
    the furnished city (dev_room stays hollow bar its specimens). New
    `interior_lod_check`.
  - **Wayfinding (e192399) — the safe half of B2.** A faint emissive cyan strip down
    each keep-clear channel ("neon shines the way"), interior-local, visual-only.
  - **Verify:** all six checks PASS (`interior_gen_check`, `interior_lod_check`,
    `world_building_check`, `menu_check`, `building_gen_check`, `city_layout_check`);
    `menu_tower` / `dev_map` / `city_map` boot clean; import clean, no warnings.
    The MENU is untouched.
  - **Deferred to a HANDS-ON pass (feel is the human's):** Beat 6's game-wide
    auto-exposure "gets darker inside" (LookController is game-wide — not to be tuned
    blind); and all feel tuning — `channel_width`/`scatter_density`/`min_clearance`
    (generous-first defaults now), `interior_lod_radius` + pop-in tolerance, kit box
    dims, wayfinding energy.
  - **To resume: "Continue QuadShot per v1.65 — B3 interiors Beats 1–5 + wayfinding
    are built + headless-verified, pending the user's flight. FLY: `city_map` (or the
    CITY leaf) for the furnished city; `dev_map` for the five program specimens west
    at x≈−80..−175. Map feel → knobs on WorldBuilding/InteriorGenerator. Then Beat 6
    (game-wide auto-exposure, hands-on). After interiors feel decent, the user pivots
    back to the WAR CAMPAIGN (M6): H.q4 aim drill → roster/weapons calibration →
    sortie composition P2."**

- **2026-07-26 — v1.66. B3 interiors, feel pass 1 from the first flight (built +
  headless-verified, pending re-flight).** The user flew city_map + dev_map ("looks
  good so far") and gave five notes; four became config/code, the fifth (glass
  walls) is a pending design decision.
  - **Columns uneven → fixed.** The user was right: the column grid started at an
    offset (`-px + spacing*(i+1)`), so it was lopsided. Rewrote `_build_columns` to a
    grid **centred on the origin, symmetric about both axes**; channel-drops are now
    symmetric too. Probed: 4 columns at (±8, ±8) for the 26 m specimen.
  - **Ceilings a touch low → raised, + flyover headroom.** Specimens 4.0→5.0, city
    range 3.6–5.6 → 4.0–6.0; and tall furniture (racking/shelving/server/container/
    feature) now caps to `interior_height*0.62`, so a low floor never fully walls you
    off above the furniture (racking was a fixed 3.0 m — unflyable-over in a 3.6 m
    floor).
  - **Props invisible (same colour as the room) → fixed.** The palette reused the
    outdoor zonal base colours, which are tuned to be seen lit outdoors and vanish in
    the dark interior. Gave props a purpose-made mid-grey (visible against near-black
    walls even before lighting) and bumped accents well past the 1.0 bloom threshold
    so glow clearly glows. (The "bright green" is atrium/plaza greenery accents,
    working as intended; the "green but not glowing" was the city's outdoor trees seen
    through the open walls.) Overall brightness/mood remains the deferred Beat 6
    (auto-exposure) job.
  - **Wayfinding strips too subtle → bolder.** Wider (0.18→0.45 m) and brighter
    (energy ×1.3) cyan floor lines.
  - **PENDING DESIGN DECISION — glass walls.** The user asked to replace the opaque
    wall segments on open floors with transparent/full-window walls (offices, plazas).
    B2 deliberately shipped windows as openings, not glass ("no transparency sorting/
    refraction cost; glass later as an emissive rim if the look wants it"), and the
    wall build is shared with the menu + every building — so this is a real fork
    (true transparency vs emissive-tinted curtain-wall vs bigger openings), best
    sequenced with the lighting beat (glass reads completely differently under
    auto-exposure). Put to the user; not implemented.
  - All checks PASS; dev_map/city_map/menu_tower boot clean.
  - **Glass walls RESOLVED (same day):** the user chose **Tier A — emissive
    curtain-wall glass — bundled into the lighting beat (Beat 6)**, and reserved
    **true transparent glass (Tier B) as a VERY SPARSE landmark treatment** for
    fancy floors — penthouse / top-level boss office / conservatory-garden — a rare
    seed-gated program variant that doubles as a from-outside landmark telegraph (B2)
    and a natural future P2 objective floor. Both recorded as Beat-6 Task 6.3 in the
    plan; not built (bundled with lighting). A lovely emergent hook: glass becomes a
    scarcity signal, not a default.

- **2026-07-26 — v1.67. B3 interiors, Beat 6 (the lighting beat) — part 1: glass
  Tier A + the auto-exposure finding (built + headless-verified, pending flight).**
  - **Auto-exposure was ALREADY shipping.** Opening Beat 6, found `LookConfig` already
    carries the full Auto-Exposure group and `LookController` already assigns a
    `CameraAttributesPractical` to the WorldEnvironment and applies enabled/scale/
    speed/min+max-sensitivity every frame — built in the v1.38 look-lite pass, tuned
    "more dramatic" (slow adapt, min-sensitivity floor so interiors stay genuinely
    dark). So the "gets darker inside" B2 moment has been live the whole time; the
    interiors have been flown with it. No new exposure code — Beat 6's exposure task
    was already done. Darkness/exposure to taste is a LOOK-overlay tuning the human
    owns (auto_exposure_min_sensitivity, ambient_energy, auto_exposure_speed).
  - **Glass Tier A built.** Open-floor solid walls now render through a `_mat_wall`
    indirection on `MenuFloorFrame`: a reflective metallic glaze (SEALED_ALBEDO,
    metallic 0.6, roughness 0.22) when `glass`, else the matte `_mat_dark`.
    `InteriorGenerator.is_glassy()` gates it (office/atrium/lobby/server glassy;
    warehouse/dock opaque); `WorldBuilding` stamps `spec["glass"]`, `MenuBuilding`
    threads it. Menu + sealed/UC floors untouched (glass defaults false). Probe:
    office 4 glass / warehouse 0. All six checks PASS; menu_tower/dev_map/city_map/
    main boot clean.
  - **Still Beat 6, pending:** the human flies glass + tunes the darkness/exposure to
    taste (the game-wide knobs, live in the overlay); then Tier B (rare true-glass
    landmark floors) if wanted. Glass reads by reflection, so it needs eyes on it
    under the real lighting — the checkpoint the agent cannot stand in for.
  - **To resume: "Continue QuadShot per v1.67 — B3 Beat 6: auto-exposure was already
    shipping (v1.38); glass Tier A (curtain-wall glaze on office/atrium/lobby/server)
    is built + headless-verified, pending flight. FLY city_map/dev_map: judge the
    glass look + tune darkness (LOOK overlay: auto_exposure_min_sensitivity, ambient_
    energy). Then Tier B (rare true glass = penthouse/boss/garden landmarks). After
    interiors ship, pivot to the WAR CAMPAIGN (M6): H.q4 → roster/weapons calibration
    → sortie P2."**

- **2026-07-26 — v1.68. B3 Beat 6 part 2: glass = transparency (APPROVED) + the
  darkness diagnosis + an SDFGI toggle (built + headless-verified, pending flight).**
  - **Glass Tier A (metallic glaze) was invisible** — metallic reads as glass only
    with something to reflect (reflection probe / SDFGI / bright sky), and the scene
    has none, plus the albedo was near-black. Switched to **actual TRANSPARENCY**
    (alpha 0.18 blue tint + sub-bloom emissive rim, cull disabled); collision
    unchanged (fly the opening, not the pane). **Flown and APPROVED — "amazing, high
    ROI, no noticeable perf hit."** So the glassy programs now read as see-through
    window walls. (This is Tier B's technique applied broadly; the rare-fancy-floor
    idea survives as a KIT/landmark distinction, not a rendering one.)
  - **The "flat lighting / can't get dark inside" was NOT an engine limit.** Root
    cause: (1) flat `ambient_light_energy` fills every interior uniformly, ignoring
    the slab; (2) open-plan floors with big multi-side openings are lit pavilions, not
    caves; (3) **auto-exposure renormalises** — lowering ambient/sun uniformly just
    makes it crank exposure back up, so nothing reads darker. The effect needs
    *occlusion* (inside dark WHILE outside bright), which flat ambient cannot produce.
  - **SDFGI toggle added** (`LookConfig.sdfgi` 0/1, overlay LOOK row, default off):
    bake-free occlusion GI. On also disables the flat ambient fill so the occlusion
    isn't washed out; off restores the scene's captured ambient source. The
    human-judged "can this engine do the darker-inside vision" test — if it delivers,
    it fixes darkness AND gives glass/metal real reflections; if not, the honest
    fallback is to embrace interiors as lit neon rooms (and reserve true darkness for
    the enclosed rim floors, since a floor open on 3 sides to a lit city stays lit
    regardless).
  - All scenes boot clean; SDFGI off = no change until toggled.

- **2026-07-26 — v1.69. B3 interiors PAUSED here (shipping as-is); pivot to M6.**
  The user flew SDFGI ("interiors look somewhat different, for the better — as if
  their internal lights read better"; perf change not noticeable either way) and
  called it: leave the interiors work as-is and steer back to the war campaign. State
  at pause: open-plan flyable interiors — seeded/deterministic, district-programmed
  vertical profiles, sparse symmetric structural columns, seeded furniture scatter
  with flyover headroom, keep-clear window channels, bold cyan wayfinding, TRANSPARENT
  glass window-walls (approved), building-level distance LOD. SDFGI is an off-by-
  default LOOK toggle. **Deferred (not abandoned):** Tier B rare fancy landmark floors
  (penthouse/boss/garden), a glowing mullion grid on glass if wanted, and any deeper
  darkness work (accepted truth: open-plan floors open on 3–4 sides stay lit; real
  darkness lives in the enclosed rim floors). **Next: M6 — the war campaign.** The
  roster/frames/weapons exist at slice scale and the balance INSTRUMENT is built, but
  the difficulty-curve CALIBRATION (blocked on H.q4, the human aim drill) and SORTIE
  COMPOSITION (P2, the war↔fight loop) are unfinished — that is the resumption.

- **2026-07-26 — v1.70. M6 resumed: the state audited, H.q4 found already
  discharged, and P2 Beat 1 built — the MANIFEST (P4.7), where a garrison float
  grows faces.** The user steered back to the war and asked for everything that
  does not need their hands.
  - **AUDIT FINDING — H.q4 was not a blocker; it was discharged two days ago.**
    The session brief (and the resumption notes in v1.65/v1.67/v1.69) carried
    "calibration is BLOCKED on H.q4, the human aim drill" forward. It is not:
    the drill was flown 2026-07-24 and logged in **v1.45** — human blaster
    **0.21** vs bot 0.17, flak **1.03** vs bot 0.99, missile ~1.0 both, i.e.
    *"the human's delivery matches the reference pilot on all three weapons."*
    What kept re-importing the phantom blocker is **BALANCE.md**, whose last
    commit is the drill's *build* (v1.36), not its *flight*, so it still read
    *"until the human aim bench lands, read every flak-vs-gun comparison as
    provisional."* **Retired**, and replaced with the landed numbers.
  - **The nuance that survives, now stated in BALANCE.md:** the drill's ruler is
    a STATIC raider, so it discharged the *aim datum*, not *tracking*.
    `Blaster × Raider` is still rig-unflyable and hand-banded — the gun
    director's linear lead is defeated by a curved orbit (the v1.20 finding,
    calibration task #1, still open). A discharged aim ruler is not a
    discharged pilot.
  - **The real blocker for the difficulty curve is P2, not the drill.** H6
    defines SDI as a readout of *composed sorties*; with no composer there is
    nothing to take a readout of, and H7 forbids the fallback (recalibrating the
    abstract-garrison skeleton "would tune the wrong thing"). Re-measured this
    session, the strategic layer still prints v1.7's brutal number verbatim:
    **skill 0.9 → 4/40 wins, median 127 sorties** against the 25–40 target. That
    debt cannot be retired until the war projects into real fights.
  - **State of the joint, audited:** `WarSim`/`TheaterGenerator` are green,
    deterministic and **entirely unwired** — referenced only by `war_config.gd`,
    `war_soak.gd`, `war_trace.gd`. No game scene touches the war. No
    `SortieComposer`, no `BiomeConfig`, no `sortie_spec`. P5 economy unbuilt.
    Every ingredient exists in isolation; nothing connects them.
  - **BUILT — `WarManifest` (`scripts/war/war_manifest.gd`), P4.7's projection.**
    The abstract garrison becomes a named unit list, discharging P1.3's promise
    ("an actual unit list, not an abstract strength 7") without the war-sim
    carrying per-unit books. Pure static-func over the state dict, war/ doctrine:
    - **A projection, never sim state.** Nothing stored; the tick engine never
      calls it. Critically it does **not draw from the war's RNG stream** —
      looking at a node must not move the war. Character is seeded from
      (theater seed, node id), written out rather than via `hash()` so a
      portable save (F4) re-projects identically on a future engine.
    - **Node identity is persistent, quantity follows the war.** The SAM belt
      fields turrets at tick 3 and at tick 300; only the counts track the
      garrison float. That split is what makes the fog honest.
    - **`strength_cost` is no longer inert** — the last known-inert field in the
      bestiary block goes live as the exchange rate BALANCE.md always named.
      **The swarm's unit is the pack** (P4.q5), so a gnat unit prices at
      `strength_cost × pack_size` = 2.7, comparable to a turret's 2.0 — the
      field keeps meaning "per body" while the manifest counts units.
    - **The dent direction is the same price list read backwards** (P2.q4,
      "every kill dents the node"): `dent_from_kills` takes BODIES, so a
      half-cleared pack dents by half a pack — not nothing, not a whole one.
    - **Doctrine × cover × escalation.** Node type picks the mix (contested
      airspace fields no turrets — nothing to bolt one to; a depot gets no aegis
      guard); biome cover tints it (gnats nest in cover 0.63 city vs 0.28
      desert, raiders prefer open ground 0.72 desert vs 0.37 city); escalation
      (P4.6) shifts toward the heavy end rather than adding bodies, clamped so
      it can never *erase* a type (P1.7: pressure, not replacement).
    - **Fog degrades detail before quantity** (P1.3): exact list → families →
      the abstract strength, whose last stop is *exactly the number the war-sim
      keeps*. The briefing runs against this, the sortie against truth.
  - **`WarSim.escalation()` extracted** from `_enemy_operations` and made public
    — the manifest grades mixes by the same clock the tick engine attacks with,
    and two copies of that formula would let the war and its briefings disagree.
    Behaviour-preserving: war_soak reprints byte-identical.
  - **Verified:** new `scripts/tests/manifest_check.gd` — 100+ assertions, all
    PASS. Purity/determinism/non-mutation, budget solvency on all 30 nodes of a
    real theater (never overspends, always spends down to the last affordable
    unit), the exchange rate both ways, doctrine and cover reaching the mix,
    escalation inside budget, fog accounting for the whole garrison, var_to_str
    round-trip — plus **1800 projections across a 60-tick running war, none
    overspent** (the joint has to hold while garrisons grow, decay and change
    hands, not just at tick 0). war_soak unchanged; boot clean.
  - **Next: P2 Beat 2 — `SortieComposer.compose(seed, node, war_state, tier)
    → sortie_spec`**, the pure serializable function P2.1 specced, consuming
    this manifest. Then Beat 3 instantiates a spec in the city biome (Iteration
    8 handed P2.13 its "one biome — the cyberpunk city" already flyable), and
    Beat 4 closes the loop by pricing the result back into the war. Calibration
    rides on Beat 4, when there is finally something to measure.

- **2026-07-26 — v1.71. P2 Beat 2: the COMPOSER lands — a node on the map becomes
  the fight you fly. Plus an F4 bug the composer flushed out: the "provably
  lossless" portable save was not lossless.**
  - **BUILT — `SortieComposer` (`scripts/war/sortie_composer.gd`), P2.1–P2.13.**
    `compose(node, war_state, config) → sortie_spec`: pure, deterministic,
    serializable, and it knows nothing about Node3D — the scene layer
    instantiates the spec. Node TYPE picks archetype + objective (P2.2, all
    eight rows), the MANIFEST supplies the garrison (P4.7), the BIOME supplies
    approach geometry (P2.4), weather/pads/escalation tune difficulty
    organically (P2.11).
  - **The invariant that makes the loop honest: CONSERVATION.** Triggered
    reinforcements are taken **out of** the garrison, never added on top — the
    manifest is the node's whole strength and the reserve is part of it
    arriving later. So `layers + triggers == the manifest`, exactly, on all 30
    nodes and across a 40-tick running war (1092 composed sorties, zero
    leakage). Consequences: clearing everything a sortie fields dents the node
    by precisely its garrison (P2.q4 closes *arithmetically*, not as a wish),
    and escalation can never conjure free bodies (P4.6's "only within what
    surviving production affords" holds by construction rather than by a cap).
  - **What the composer REFUSES to emit: a difficulty number.** H6 makes SDI a
    measurement, so the spec carries the H.q2 axis vector (garrison / cover /
    weather+penalty / pads / escalation / fortification) for diagnosis and no
    composite score. `sortie_compose_check` asserts the *absence* of `sdi`,
    `difficulty`, `hardness` — a composer that graded its own output would turn
    "organic difficulty" back into a hand-tuned level knob, quietly.
  - **P2 decisions, now mechanized:** placed garrison for assaults / waves only
    for dogfights (P2.q1 — the M3 wave_director is one archetype, demoted from
    "the game"); open biome-shaped ingress, no rail (P2.q2 — 400 m exposed over
    desert vs 150 m and four corridors in the city); deterministic triggers
    only (P2.q3 — `detected` / `objective_damaged` / `wave_cleared`, with the
    delay seeded so the same sortie always gives the same window); capture vs
    degrade read from the tick engine's own `has_adjacent_owner` so briefing
    and war can never disagree (P1.q2). Pads scale inversely with difficulty
    and the HQ has none (P2.6). One dare max, biome-weighted (P2.7).
  - **The P2.1 double evaluation is real:** `compose` runs against truth,
    `compose_briefing` against the manifest through fog. Fresh intel and the
    two agree bit-for-bit; at 11 ticks stale the briefing reads *"strength
    ~16.2 (no composition resolved)"* against a truth of *2×raider 3×gnat(27)
    6×raider*. Fog hides the garrison, not the geography — you always know what
    KIND of place it is.
  - **A design flaw the TRACE caught that the check did not.** First trace run:
    light nodes held no reaction force at all, because "never reserve the whole
    garrison" was a per-TYPE guard — a factory of one raider + one pack + one
    turret could reserve nothing, so the Strike's "escorts converge" promise
    evaporated on exactly the light targets a new pilot flies first. Made
    global (at least one unit stays placed, whatever the type spread); now 0 of
    30 nodes of 2+ units go reserveless, and there is an assertion for it. The
    watch-mode doctrine (v1.25) earning its keep on a headless bench: the
    assertions were all green and the *output* was wrong.
  - **THE F4 BUG — the portable save was not textually lossless, and had never
    been.** Found while chasing a spec that would not round-trip.
    `snappedf(v, 0.001)` is `round(v / 0.001) * 0.001`, and the **multiply**
    lands on a double whose shortest decimal form needs 17 digits (29900 ×
    0.001 → 29.900000000000002); var_to_str prints all of them and Godot's
    float parser drops the tail. **40/40 soak seeds failed a textual
    round-trip at tick 0.** war_soak never saw it because its guard hashes
    `JSON.stringify` and was written against a *different* drift
    (StringName-vs-String), so it asserted behaviour and was blind to text.
    - **Fixed** by `WarSim.quantize(value, decimals)` — divide, don't multiply
      — and every war float (sim, generator, manifest, composer) now goes
      through it. `snappedf` is banned in `war/` and CLAUDE.md says so.
    - **war_soak grew the assertion that was missing**: a textual round-trip
      check over every seed it already generates. Now prints *"textual
      round-trip (F4 bit-exactness): OK"*.
    - **Blast radius, measured and reported rather than hidden:** the fix moves
      values by ~1 ULP, and the war is chaotic enough to feel it. skill 0.9
      went **W4/L29/S7 → W5/L27/S8** (one theater flipped loss→win, one
      loss→stalemate); pilots lost 2.4 → 2.3; **median win still 127 sorties**;
      skill 0.3 and 0.6 unchanged at zero wins. The H7 debt is untouched — this
      was a correctness fix, not a balance change, and it should not be read as
      one.
  - **Verified:** `sortie_compose_check.gd` (new) + `manifest_check.gd` +
    war_soak + the full 16-check suite all PASS; menu_tower / main / dev_map /
    city_map boot with zero error or warning lines. New readable bench
    `tests/sortie_trace.gd` prints the fights a running war is offering.
  - **Next: Beat 3 — instantiate a spec.** The scene layer that turns a
    `sortie_spec` into a flyable fight in the city biome (Iteration 8 already
    handed P2.13 its "one biome — the cyberpunk city", flyable, with
    interiors), starting with the two slice-ready archetypes the composer
    already flags. Then Beat 4 closes the loop: the sortie's result priced back
    into the war through `dent_from_kills`, which is already built and tested.
    **Only after that does calibration have something to measure** — and per
    H.q4 that pass is mine to initiate and lead.

- **2026-07-26 — v1.72. `Atlas × Aegis` diagnosed: not a bug, not a tuning
  target — the frame axis pointed at the one enemy that cannot exercise a
  frame. AWAITING THE HUMAN'S CALL (no number changed).**
  - **The cell:** `paper ++ → predicted 0 → validated --`, exchange **-1.00**
    vs the Kestrel. 0/6, outcome `bombed` all six reps, **2 missiles spent
    against a 3-missile kill**, `dmg-taken 0.0`. The Kestrel flying the SAME
    weapon at the SAME enemy wins 6/6 at ttk 8.0 s spending exactly the 3
    missiles Layer 1 predicts.
  - **Ruled out — the harness timeout.** A throwaway probe (a copy of the
    harness with `MAX_SECONDS` 10 → 20, everything else identical; run, read,
    deleted, never committed) reprints `Atlas × Aegis` **identically**: 0/6,
    spent 2.0, -1.00. `MAX_SECONDS` is not the deadline — the aegis's own bomb
    run is (~60 m of transit at speed 7.0 = ~8.6 s), and no rep cap touches
    that. The other Atlas cells moved by ±0.02–0.07 between the two runs, which
    is the cross-process float variance the harness header already warns about;
    `Atlas × Aegis` did not move at all. The result is robust, not noise.
  - **The mechanism, from committed numbers.** `missile_cooldown = 3.0`, so
    three launches need ≥6.0 s of window after the first lock; the Kestrel's
    third lands at 8.0 s, roughly **0.6 s inside** the bomb deadline. The Atlas
    is heavier and lazier by design (mass 1.24 vs 0.65, TWR 3.2 vs 4.5, rate_p
    0.004 vs 0.007, drag 0.045 vs 0.03), so its first lock comes later — and
    because the cadence is 3.0 s, **a sub-second deficit costs a whole
    missile.** The cell is a step function of a ~7% margin.
  - **The structural finding, which is the real one: the aegis never shoots at
    you.** `sight_range 0`, `muzzle_speed 0`, `preferred_range 0`, and the rig
    records `dmg-taken 0.0` — it is a **stopwatch, not a duel**. So the Atlas's
    entire virtue (hull 190, armor 3) is INERT here while its entire cost
    (tonnage) is fully paid. BALANCE.md already says a frame's durability "is
    visible only in the validated column"; the aegis is the one roster member
    where **even the validated column cannot see it**, because nothing is
    shooting. A frame cell against a non-shooting, timed enemy can only ever
    price tonnage. `--` is the honest answer to the question actually asked.
  - **So the PAPER band is what is wrong, not the frame and not the bench.**
    Three ways to close it, for the human to pick (nothing applied):
    - **(a) Re-paper the cell** *(my recommendation)* — P4.3/P3.4's `++`
      becomes a stated `-`/`--` with the reason recorded. Cheap, honest, no
      number moves, and it teaches the table something true.
    - **(b) Mark it structurally unmeasurable** — like the existing
      unseeded-enemy band limit (`can only read ++ or --`), state that the
      frame axis has nothing to say against an enemy that does not shoot.
    - **(c) Move the bench geometry** (push `BOMB_TARGET_Z` out until both
      frames fit three launches) — **worst option**, and named here so it is
      rejected on purpose: it tunes the ruler until it prints the answer paper
      expected, which is the exact move BALANCE.md's "do not fix a number to
      close a gap you have not explained" forbids.
  - **A separate design question this surfaced, logged not answered:** if
    intercepting a bomber is a race and the missile's 3.0 s cadence quantizes
    that race into whole-missile steps, then *any* frame slower than the
    Kestrel fails the intercept regardless of pilot skill. That is a fact about
    the **aegis + missile pairing**, not about the Atlas, and it sits close to
    the P4/Iteration-7 anti-frustration guardrail ("no fight is hopeless") —
    for the Atlas, this one currently is. Worth revisiting when the bestiary
    grows a second bomber or the arsenal a second anti-bomber answer.

- **2026-07-27 — v1.73. Iteration 9 PROPOSED (S1–S11): the symmetric half of the
  balance model, and a user-called re-order — roster and balance BEFORE more
  war.** The user read the `Atlas × Aegis` diagnosis, named the gap in their own
  terms, and steered the milestone.
  - **The user's framing, adopted as S1:** balance is how hard you hit, how well
    you deliver it, **and separately** how much you can take. Mapped onto the
    instrument it exposes that Layers 1–2 are *one half of a symmetric model* —
    there is no layer for their output on you, and the entire frame axis was
    built on that hole. The proof is arithmetic: the Kestrel spends **0% hull in
    all four cells** and scores a perfect 1.00 in three, so a frame delta's
    ceiling there is **0.00**. The Atlas cannot win, only fail to lose.
  - **A user hypothesis corrected, because the reasoning generalizes (S4).** The
    user proposed that enemies simply cannot connect on a moving pilot and the
    tests should run longer. Half right: the turret puts **12% of hull into the
    Atlas** over 3.6 s and misses the Kestrel only because the Kestrel kills it
    in **1.3 s**. The mechanism is *time-in-the-threat-envelope, not
    marksmanship* — and a longer cap buys nothing, because **a duel ends when
    the enemy dies, not when the clock expires** (the v1.72 probe showed the
    same thing from the other side). Exposure comes from more enemies at once,
    or from a task that holds you in the envelope. Corollary for H6: the unit
    layer is inherently a step-function instrument and **cannot** produce the
    graded 45–65% middle — that always belonged to the sortie layer (H9). Duels
    prove feel-promises; sorties produce curves.
  - **The re-order (S10), agreed.** The user: we have drifted into the macro
    while the micro is incomplete and unmeasured; finish and balance the ROSTER
    first. The decisive argument is one they did not make — **the war's
    arithmetic is denominated in `strength_cost`**, and v1.70's manifest just
    made that field load-bearing while its four values (0.3 / 1.0 / 2.0 / 4.0)
    remain hand-set guesses nobody has validated. More war on an unchecked ruler
    means every strategic number is measured against a placeholder. **M6a** (the
    roster + the symmetric model + calibration) now precedes **M6b** (the war:
    composer Beats 3–4, nodes, biomes, weather, command room). Nothing built is
    wasted: the manifest is *required* by M6a, the composer is complete, tested
    and inert, the F4 fix is a pure win. Only Beat 3 pauses, and it had not
    started.
  - **The melee bench returns, with a guardrail (S9).** The user's "empty space,
    throw everything together" instinct independently rediscovered the one use
    the v1.23 realignment reserved for the demoted agent-vs-agent mirror:
    *"only future use is empirically pricing `strength_cost`."* That day
    arrived. Recorded loudly: it is an **instrument, not a game mode and not the
    war** — F2/P4.7 keeps the war arithmetic, and this bench prices that
    arithmetic, never replaces it.
  - **Detectability deferred (S8) — my call, at the user's invitation.** Not
    unmeasurable; it simply has one possible value until a frame or equipment
    varies signature (Shade, EW gear, the user's "invisibility" idea). P4.10's
    rule applied to measurement. Stated trigger recorded so it enters *with* its
    bench row.
  - **The cost, named up front (S11): `ReferencePilot` does not evade** — its
    own header says so. Measuring player evasion against a pilot that never
    tries to survive would measure only its flight path, so S3 needs a
    **`PILOT_VERSION` 3 → 4 bump, which invalidates every committed delivery
    factor** and forces a deliberate full re-measure. Largest cost in the
    iteration, unavoidable, posed as S.q5.
  - **Seven open questions await steering:** S.q1 roster scope (my lean: *the
    web, not the census* — add Falx + Screamer to six total, balance those,
    rather than shipping ten unmeasured); S.q2 price vs check `strength_cost`;
    S.q3 ammo now or defer; S.q4 how exposure is created; S.q5 the pilot bump;
    S.q6 re-run the war after re-pricing; S.q7 confirm the detectability
    deferral.
  - No code changed this entry — paper only, per 2.4.

- **2026-07-27 — v1.74. Iteration 9 STEERED (S.q1–S.q7); two user enrichments
  changed the model, and S12/S13 were added to answer them.** M6a is now the
  live milestone.
  - **All seven answered**, six to their leans: six-type roster first (raider,
    turret, gnat, aegis + Falx + Screamer); the melee bench PRICES
    `strength_cost`; ammo adopted; task-for-factor / N-vs-1-for-web; PILOT_VERSION
    3 → 4; re-run and record the war after re-pricing; detectability deferred.
  - **The user's question the proposal could not answer — "how do we measure the
    reliability of the melee bench?"** — became **S12**. A source of truth
    cannot be checked against a better answer, so it is checked against
    **properties that can fail**: transitivity (turret=2×raider and
    aegis=2×turret must compose into aegis≈4 raiders), scale invariance (a ratio
    that drifts with N means strength is not a scalar — a *finding*, since the
    war's arithmetic is linear), mirror symmetry (catches arena positional
    bias), determinism plus a **stated error bar** (a price is `2.0 ± 0.3` or it
    is a guess wearing a decimal point), and a Layer 1 sanity anchor. Plus the
    ruler underneath: both sides are AI, so **a `BESTIARY_AI_VERSION` pin is
    required before any price is committed** — improving the raider's chase
    logic would otherwise silently re-price the raider.
  - **The user improved the ammo argument (S.q3).** S6 argued only
    falsifiability; the user argued capacity is **a balance LEVER** — "make a
    powerful weapon more expensive to use, or limit its fire count." That
    promotes ammo to a fourth design axis beside damage, cadence and delivery,
    and it is the axis that lets a weapon stay powerful *and* fair. It also
    strengthens the deferred GAP-1 `WeaponConfig` split, since capacity is
    per-weapon and `CombatConfig` is a player-side bag.
  - **The user reframed why deferring detectability is safe (S13):** a
    repeatable suite makes new mechanics cheap to introduce — add invisibility,
    run the suite, read the macro effect, design the counter (advanced radar)
    against evidence. This is **H8's green board and H.q6's advisory→gate
    re-derived independently**, which is a good sign the doctrine is
    load-bearing. What it adds is the motive: the harness is not overhead
    protecting existing balance, it is **what makes a large roster affordable at
    all.** Two refinements recorded so it does not overreach — the suite
    *localizes, never prescribes* (a harness proposing counters would be the
    forbidden oracle), and **runtime forces two tiers**, a fast smoke set and a
    deliberate full run, because a suite too slow to run is a suite that rots.
  - **Sequencing consequence recorded:** the pilot bump invalidates every
    committed delivery factor, so it lands EARLY — measuring anything else under
    v3 first would just buy a second re-measure. Order: incoming lethality
    (pilot-independent arithmetic) → pilot v4 → re-measure baseline → player
    evasion + concurrency → roster (Falx, Screamer) → ammo → melee bench +
    S12 → suite tiering → calibration.
  - No code this entry — paper only.

- **2026-07-27 — v1.75. M6a step 1: LAYER 3a lands — the instrument can finally
  see being shot at, and the roster turned out to have three damage-delivery
  modes rather than one.**
  - **The refactor was almost free, as S2 predicted.** `Lethality._exchange`
    never cared whose durability it was replaying — it reads six fields — so a
    "target" became a plain durability block (`target_from_enemy` /
    `target_from_frame`) and `incoming()` points the same verified arithmetic
    the other way. `FrameConfig.hull`/`armor` are live on the drone
    (`FlightController._ready` pushes both into its `Health`), so this mirrors
    shipped wiring rather than a schema. Every outgoing cell re-verified
    unchanged: the refactor is behaviour-preserving.
  - **THE FIRST NUMBERS EVER MEASURED FOR DURABILITY**, planted-shot verified
    against the real `Health`:

    | | Kestrel (100 hull, 0 armor) | Atlas (190 hull, 3 armor) |
    |---|---|---|
    | under raider fire | 13 hits, **8.0 s** | 38 hits, **24.7 s** |
    | under turret fire | 10 hits, **4.5 s** | 28 hits, **13.5 s** |
    | a full gnat pack (9 stings) | 63 of 100 hull — **63%** | 36 of 190 — **19%** |

    The Atlas survives **~3.1×** longer under a raider and **~3.0×** under a
    turret, and eats **3.3× less** hull fraction from a gnat pack. That is the
    P4.4 promise ("heavy is `++` against gnat stings") quantified for the first
    time — and it has been completely invisible to the instrument for the
    Atlas's entire life.
  - **THREE DELIVERY MODES, discovered rather than designed.** The first draft
    tested `damage <= 0 or fire_rate <= 0` for "weaponless" and would have been
    wrong on the roster it shipped against:
    - **`ranged`** (`fire_rate > 0`) — raider, turret. Cadence, so ttk and dps
      mean something.
    - **`contact`** — the **gnat**, which carries `damage 7.0` but
      `fire_rate 0.0`. It is not harmless: `gnat_swarm._resolve_stings` calls
      `take_hit(damage)` and then `body.die(false)`, so each body **spends
      itself** for one bite. A pack is a FINITE damage budget, not a rate, and
      its arrival timing is a DELIVERY property — reporting a ttk here would
      invent a cadence no config contains. Reading `fire_rate == 0` as
      "harmless" would have deleted precisely the cell that proves flat armor
      works.
    - **`none`** — the **aegis** (`damage 0`). The v1.72 finding as arithmetic,
      and now as an assertion: `_verify_weaponless` fails the run if a
      weaponless type ever kills a frame, or if two frames differ against one.
      **If a future roster arms the aegis, that check goes red on purpose** —
      the Atlas × Aegis band would have to be revisited.
  - **Two bugs the contact bench caught in its own first run**, both worth
    recording because they are lifecycle traps rather than logic slips:
    - **`_ready` had not run.** The bench plants during `_initialize`, before
      the first frame, so `Health.current` was still its `0.0` default and the
      first sting "killed" a full-hull frame — planted damage came back as
      exactly the hull on both frames, which is what made it obvious. The
      existing cell machine never hit this because it plants from
      `_on_physics_frame`. Fixed by stating the starting condition instead of
      inheriting a lifecycle assumption.
    - **A GDScript closure captured the `died` flag by VALUE**, so
      `died.connect(func(): died = true)` never reached the enclosing scope and
      the kill verdict silently read false. Replaced by reading `health.alive`
      directly. Worth knowing generally: latching a signal into a local through
      a lambda does not work in GDScript.
  - **Verified:** `lethality_check` PASS across every outgoing cell (unchanged),
    four new ranged incoming cells, two contact-pack cells, and the weaponless
    assertion.
  - **Next: step 2, `PILOT_VERSION` 3 → 4** — the pilot has to learn to survive
    before Layer 3b can measure how well it does.

- **2026-07-27 — v1.76. M6a steps 2+3: `PILOT_VERSION` 3 → 4, the pilot learns to
  survive — and the re-measure confirms the bump's prediction EXACTLY.**
  - **Why the bump was unavoidable (S11):** the reference pilot's own header said
    it "never evades", which made Layer 3b unmeasurable by construction — you
    cannot measure how well a pilot avoids fire when it makes no attempt to.
  - **v4 = a DEFENSIVE JINK, gated on having actually been hit.** A perfect-aim
    shooter misses a target whose ACCELERATION it cannot predict, so what
    defeats it is changing direction inside the round's flight time. The jink is
    a lateral bank oscillation (0.35 rad, 1.2 s) plus a vertical bob (1.5 m,
    0.9 s, deliberately a different period so the two axes do not phase-lock
    into a predictable ellipse), held for 2.5 s after any hull loss. It is
    re-clamped to `orbit_bank_max`, so it inherits the same thrust budget the
    orbit is ceilinged by and cannot bank the drone past what it can hold
    altitude at — the v2 sink-into-the-floor lesson, reused rather than
    relearned. The gate is purely local information (the pilot notices its own
    hull dropping), needs no knowledge of the enemy, and is deterministic.
  - **THE GATE IS THE DESIGN, and it made the bump falsifiable.** Because the
    aim bench's static target has `sight_range = 0.0` and genuinely cannot fire
    (verified in code, not taken from the header's wording), and because the
    evasion cells do not run this brain at all, the bump shipped with a stated
    prediction: **every committed delivery factor comes back unchanged, and only
    the duels move.**
  - **The prediction held to the byte.** The entire diff of
    `balance/delivery_factors.json` after a full 21-cell re-measure is ONE LINE:
    `"pilot_version": 3` → `4`. Every aim, evasion and splash value identical —
    `aim: kestrel/blaster` 0.17, `atlas/blaster` 0.19, `flak x gnats` 1.00 ×
    3.42, all of it. This is the third time the discipline has paid off the same
    way (v2 moved things and said so; v3 and now v4 moved nothing and proved
    it), and it is exactly what a pinned ruler is for: **a bump that changes
    nothing it should not change is the instrument working, not a no-op.**
  - **Regression:** the full check suite (combat, wave, missile, run, hover,
    repair, motor_damage, menu, manifest, sortie_compose, lethality) PASS. The
    Layer 3a refactor touched only the balance calculator, and the suite
    confirms shipped game code is undisturbed.
  - **The duels DID move, and they split by enemy type — the evasion/aim trade,
    visible for the first time.** Every cell where the pilot is never hit stayed
    put exactly as predicted (Atlas × Aegis −1.00, Blaster × Turret, Flak ×
    Gnats at 0% hull, Atlas × Gnats, Atlas × Raider). Among the cells where it
    IS hit:

    | cell | v3 | v4 |
    |---|---|---|
    | Blaster × Gnats | −0.24, kills 2.2/9, hull 48% | **−0.33**, kills **1.7**/9, hull 51% |
    | Missile × Gnats | −0.42, kills 1.2/9, hull 55% | **−0.45**, kills 1.0/9, hull 56% |
    | Flak × Raiders | +0.71, kills 2.3/3, hull 7% | **+0.88**, kills **2.8**/3, hull 7% |
    | Missile × Raiders | +0.89, hull 11% | **+0.92**, hull **8%** |
    | Blaster × Raiders | −0.19, hull 19% | −0.17, hull 17% |

    **The jink pays against RANGED shooters and costs against the CONTACT
    swarm**, which is mechanically coherent rather than surprising: jinking
    breaks a raider's firing solution, but it does not break a gnat cloud's
    approach — it only degrades your own gun, so you kill fewer bodies and get
    stung more. Evasion is not free, and this is the first time the instrument
    could see the price.
  - **PRELIMINARY, and honestly labelled.** The v1.72 clock probe — still pilot
    **v3** — reported `Atlas × Turret` at `dmg-taken 18.7` where the v3 10 s run
    said `22.2`. That cell resolves at 3.5 s, well inside both caps, so the cap
    did not cause it: that is **~16% run-to-run variance under an unchanged
    pilot**, exactly the cross-process float variance the harness header warns
    about. Small deltas therefore cannot be attributed to the jink. A second v4
    run is under way to establish a v4-vs-v4 noise floor; only deltas exceeding
    it are real, and the two large ones (Blaster × Gnats kills 2.2 → 1.7, Flak ×
    Raiders +0.71 → +0.88) are the ones to confirm. **Recorded as a direction
    with a mechanism, not as a measurement.**

- **2026-08-01 — v2.00. THE SORTIE LAYER EXISTS: difficulty is MEASURED for the
  first time.** H9's *"composed-sortie runner, day one"* — proposed 2026-07-18,
  built today, and the thing H7's debt has been waiting three weeks for.
  - **`sortie_bench.gd` flies composed sorties with the reference pilot** and
    reads the completion rate back out as the SDI. H6 has always insisted that
    *SDI is measured, never authored*; until now nothing measured it, so the
    project's only difficulty signal came from `war_soak`'s abstract proxy — a
    coin weighted by a `skill` float, calibrating a game nobody was playing.
  - **THE WEAPON IS AN AXIS, NOT AN ASSUMPTION, and finding that out was the
    first real result.** The initial cells flew blaster-only and read 0%
    everywhere — which looks like a crushing theater and was substantially a
    LOADOUT MISMATCH being labelled node difficulty. P4.3 wrote down years ago
    that a chip gun loses to a swarm, and the duel board already measures `Flak x
    Gnats` at 100% for 0% hull; a node fielding three gnat packs (27 bodies) was
    never going to fall to a blaster. **A node's SDI is what its BEST answer
    achieves**, so the bench sweeps all three weapons and the counter-matrix
    arrives at sortie scale.
    - The gap is not subtle. Node 8 (factory, garrison 36.4): blaster dents it
      **0.4**, flak dents it **9.6** — 24x — for the same 0% completion. *"Nothing
      completed"* and *"nothing touched it"* are different findings, and the
      dent is what separates them. The report tie-breaks on dent for exactly
      this reason.
  - **THREE RIG BUGS, and each is the same lesson in a different coat: a bench
    measures what it is actually configured to do, not what its author meant.**
    1. **The gun director was OFF.** `default_combat_config.tres` ships
       `fire_assist_miss_m = 0.0` and every other bench sets it per cell, so a
       bench that simply forgets inherits the MANUAL path — a bare 6 degree cone
       with no ballistic solution. **There is no symptom except bad numbers.**
       Node 8 read 0% with a dent of 0.6 and looked exactly like a crushing
       sortie.
    2. **The pilot spawned INSIDE the engagement envelope.** At 90 m from centre,
       against an outer ring reaching 83 m and turrets with 45 m sight, the fight
       started before the pilot had moved. Node 8 died in 5.3 s. Moved to 125 m,
       and there is an approach again.
    3. **The arena was built during `_initialize`**, where `root.add_child()` is
       accepted and the node is still not `is_inside_tree()` — so
       `global_position` silently returned identity and the drone's `_ready` had
       not resolved its frame. It presents as *"arm_throttle_threshold on a base
       object of type Nil"*, three calls from the cause. The duel harness has
       always built on the first physics frame; that was not decoration.
  - **THE CAP WAS MEASURING THE CAP.** At 75 s, flak TIMED OUT on 2 of 3 reps at
    node 8 while out-denting every other weapon 24 to 1 — the answer weapon was
    being cut off mid-answer. Raised to 150 s. **A rep that hits the cap is a
    measurement only when the cap is not the thing doing the failing**, and
    P2.q6's target sortie is 4-8 minutes for a human anyway.
  - **A composed sortie is EXPENSIVE to simulate**, and this is a planning fact
    for anything that wants to soak them: ~90 s of wall time per rep, dominated
    by gnat packs (27 rigid bodies each). A full 12-node x 3-weapon x 2-rep sweep
    is ~108 minutes. The bench therefore streams every rep as it completes rather
    than printing only at the end, so a run that has to be abandoned still leaves
    everything it had measured.
  - **DELIBERATELY NOT ASSERTED.** H6's bands are printed as a readout, not a
    build break. They describe a war fought with an EARNED loadout and a chosen
    frame; this bench flies a stock Kestrel at every node. Failing a board because
    the default loadout cannot crack a deep node would be asserting the wrong
    claim loudly. The assertion waits for P5's economy to exist.

- **2026-08-01 — v1.99. THE PADS ARE SPENT (W.q4 answered by play), and the
  intermittent `ammo_check` is caught and diagnosed.**
  - **THE FIRST HAND-FLOWN COMPOSED SORTIE VALIDATED THE DESIGN'S FOUNDING
    CLAIM, and the user found it without being told.** They flew node 8 and
    reported: *"was difficult as it should. no heal so i had to fly a broken
    drone."* **Node 8 earns ZERO pads** — its garrison is 36.4 against a cap of
    40, and `_pads()` prices a heavily garrisoned node as pad-poor. Nothing
    authored that; it fell out of the war state. That is P2/2.2's *"difficulty
    falls out of the strategic state — organic balancing, not hand-tuned
    levels"* happening in a human's hands on the very first flight, and it is
    the single strongest piece of evidence the model has produced.
    - **It was ALSO a real gap, and the two facts are compatible.** The runner
      never read `spec["pads"]`, so *every* node was pad-poor — node 8's zero
      was correct by accident. Connecting the field is what makes the knob a
      knob rather than a constant.
  - **W.q4 → DECIDED: repair gate first, then resupply alternating flak/missile.**
    The lean was already written; the play evidence settles it. **Hull is the
    resource you cannot fly without** — a pilot out of missiles is
    inconvenienced, a pilot out of hull is dead — so a node generous enough for
    exactly one pad hands you the green one. Pads ring between the inner and mid
    layers, so taking one is a detour INTO the fight rather than a trip to the
    edge of the map.
    - Measured across four seeds: slice-ready nodes get **0 pads (3), 1 pad (16),
      2 pads (41)**. The knob has real range and the extremes are rare, which is
      the right shape for a difficulty axis.
  - **A timing trap worth stating once, because it will recur.** Pad placement
    rejects spots near the objective structures **arithmetically**, not with the
    shape cast, because those structures were added to the tree microseconds
    earlier in the same call — and a body's collision shape is not registered
    with the physics space until the next physics step. A cast would sail
    straight through them and park a repair gate inside a factory.
  - **THE INTERMITTENT `ammo_check` IS CAUGHT, AND IT WAS THE CHECK.** Flagged in
    v1.98 as an unreproduced one-off; it reappeared with its assertion text this
    time: *"1 gates laid inside scenery across 6 sorties"*.
    - **The cause is a deferred free.** `_lay_gates()` disposes of the previous
      sortie's gates with `queue_free()`, which does not take effect until the
      end of the frame — and the check sweeps all six sorties **inside one
      frame**. The old gates are therefore still solid bodies in the physics
      space while having already been dropped from `_director.gates`, so the
      exclude list missed them, and a new gate landing near an old one reported
      as buried in scenery **because a `ResupplyGate` is itself a
      `StaticBody3D`**.
    - It only failed when the random placement happened to reuse a spot, which
      is exactly why it passed alone and failed in a batch. **The gates were
      always placed correctly** — the same category as `heat_check`'s two false
      failures, and the third time on this project that an intermittent check has
      turned out to be the check.
    - Fixed by excluding every gate the sweep has laid rather than only the
      current sortie's. **8 of 8 consecutive runs pass.**
    - **The lesson to carry: a test that drives many frames' worth of a system
      inside one frame does not get deferred frees**, and anything that
      `queue_free`s between iterations is still solid for the rest of that frame.

- **2026-07-31 — v1.98. ITERATION 12 PHASE 3: THE LOOP HOME. Your fights dent
  the war, the war ticks, and the campaign is a file on disk.** W7 built, and
  with it the doc's own rule of thumb is finally true in both directions —
  *"the war shapes your fights; your fights dent the war"* had only ever been
  the first half.
  - **`WarSim.apply_sortie(state, config, result)`** prices a flown sortie back
    into the theater. It sits beside `_proxy_sortie`, the abstract stand-in the
    soak has always swept with, and the two deliberately share an outcome
    vocabulary — otherwise the harness would be calibrating a different game
    from the one being played.
  - **P2.q4 is unconditional, and that is the point.** The dent is applied
    whether you completed the objective, gave up, or died: everything you
    destroyed weakens the node for next time. **Intel clears too, however it
    went** — dying over a node is a terrible way to buy a look at it and it is
    still a look.
  - **The capture gate re-reads adjacency from the LIVE state**, not from the
    spec that composed the sortie. The briefing's `capture` was true when it was
    written and a tick may have moved the front since. The ground is what it is
    when you get there.
  - **A DEAD PILOT'S SORTIE NOW RESOLVES, and until today it could not.** The
    runner only ever finished by egressing, so a pilot who died three structures
    deep emitted nothing, the war never heard about any of it, and P2.q4 quietly
    meant *"every kill on a sortie you survived"* — which is the exact opposite
    of the rule. `SortieRunner.abort()` closes it: the dent is kept, the
    objective is **not** credited, and a pilot comes off the roster (F1).
  - **`WarSave` writes F4's portable save at last** — provably serializable
    since v1.7, never once written to a file. `user://war.save`, human-readable,
    diffable, shareable by copying.
    - **It is `var_to_str`, NOT JSON, and that is the whole design decision.**
      The `user://profile.json` precedent is the wrong one here, for two
      reasons that are both silent: **JSON has no StringName**, so every
      `&"enemy"` returns as a String and `node["owner"] == &"enemy"` is false
      for a loaded war — every side in the theater quietly becomes neutral. And
      **JSON has no int**: `rng_state` is a 64-bit integer, a double cannot hold
      one, so a JSON round-trip forks the war's random stream and F4's "the same
      save replays the same war" dies without a symptom.
      - The check asserts **that JSON is broken here**, on purpose. If those two
        assertions ever start failing, Godot's JSON gained type fidelity and this
        file's rationale should be re-read rather than trusted.
  - **`war_loop_check.gd` is the eighteenth check, AND IT CAUGHT A REAL BUG ON
    ITS FIRST RUN** — the best possible outcome for a new check, and the
    v1.91 lesson paying out again. `FileAccess.get_as_text()` reads from the
    **start of the file regardless of the cursor**, so reading past the header
    with `get_line()` and then calling it fed the `# QuadShot war save` comment
    to `str_to_var`, which saw a leading `#` and tried to parse the entire
    campaign as a **Color**. Every save in the world would have been unreadable,
    and the failure mode was a save that wrote perfectly and never came back.
  - **End to end, in the check: 25 flown sorties took 6 nodes off the enemy,
    with a save and a reload between every single one** — which is what actually
    happens when a human closes the game.
  - **The tick after a flown sortie passes NO proxy skill**, so the sim runs
    production, supply, enemy operations, weather and intel without inventing a
    second abstract player sortie on top of the real one. Double-counting the
    player would have made every flown campaign easier than every measured one,
    which is precisely the kind of divergence H7 exists to prevent.
  - **Still not built:** the ingress (W.q7), `spec["pads"]` (W.q4), dares, and
    node selection — you fly what `--node` names or the first slice-ready node.
    A map screen is the obvious next thing and it is UI, not systems.
  - **W9.1's leash gets its real fix, and it is a reframing rather than a
    number.** The sortie scene measures link range from **the sortie's centre**
    instead of from the world origin, and the shipped radii then need no
    retuning at all: egress completes at 105 m, well inside the 220 m warning.
    **Measuring from the origin was always the accident** — the greybox arena
    simply happened to sit near it. That is the same reframing Iteration 11's
    transit gate needs (its far end is *somewhere else*, not *too far*), so the
    rule has now been fixed once and still wants applying to `main.gd`.
  - **One unreproduced flake, recorded rather than dismissed.** `ammo_check`
    failed once inside a full-suite batch and then passed 5 standalone runs and a
    second complete batch, with nothing in this change set touching it. Logged
    because this project has been bitten by exactly this shape before (v1.92's
    `run_check`: *"it passed alone and failed in a batch — the worst way for a
    regression check to behave"*). **The batch loop had swallowed the assertion
    text, which is why there is no diagnosis** — capture it next time.

- **2026-07-31 — v1.97. ITERATION 12 PHASE 2: A COMPOSED SORTIE HAS BEEN BUILT
  AND RUN. The campaign and the game have met.** `SortieComposer.compose()` now
  has a caller that is not a test.
  - **`SortieRunner` (`scripts/sortie/`) is the whole bridge**, and it is the
    only place in the project where a `sortie_spec` becomes a `Node3D` — which
    is what keeps `war/` pure, deterministic and serializable while the fight is
    full of physics. It places the garrison in concentric rings, spawns the
    objective structures, arms the reserves, watches for the egress, and emits a
    serializable result priced through `WarManifest.dent_from_kills`.
  - **`ObjectiveAsset` is the one piece of real CONTENT the bridge needed.** The
    composer has emitted `objective_assets: 1..4` since v1.71 and nothing could
    build one. Hot white (W.q5), because the palette had a hole exactly that
    shape and red would have made a building and a raider read alike at a glance.
    **It leaves a husk** — dark, and still solid — for the reason a spent
    resupply gate stays in the world, plus a new one: egress is a real phase now,
    so the ruins you made are cover on the way out.
  - **THE STRIKE'S EGRESS OPENS ON THE OBJECTIVE, NOT ON AN EMPTY FIELD**, and
    the check asserts exactly that. If it opened on a cleared garrison a strike
    would be a dogfight wearing a building, and W6's whole distinction between a
    wave and a reserve would be decorative.
  - **What a real composed strike looks like** (seed 4242, node 8) — this is the
    output, not a mock-up:

    ```
    STRIKE: destroy production x3      factory / industrial, clear
      outer  2xraider 3xgnat
      mid    6xturret 1xgnat
      inner  2xturret
      reserve on objective_damaged after 9.6s: 7xraider
    ```

    **Seven raiders scramble 9.6 s after you first touch the objective.** That
    is P2.3's "deterministic responses to player action" arriving as a thing you
    can be caught by, and it is the sentence W2 was written to earn.
  - **THE ROSTER WORK PAID OFF WITHIN THE HOUR.** The first dogfight the scene
    ever composed placed **3 falx** in its outer ring. Six hours earlier the war
    could not field a falx at all, so that sortie would have been raiders and
    gnats. v1.96 was not housekeeping; it was the difference between the
    campaign's first flight having the roster and not.
  - **`sortie_check.gd` is the seventeenth check**, and it guards three
    deadlocks a body count cannot see: a strike whose egress never opens, a
    dogfight — which has `assets: 0`, so the field-cleared branch is the ONLY
    thing that can end it — and a reserve that fires twice or never.
    - **One of those was a real bug caught by writing the check's reasoning
      down, before the check ran.** A dogfight carries two reserves both keyed
      `wave_cleared`, and the first draft tracked spent triggers in a Dictionary
      keyed by the trigger itself. **Godot hashes a Dictionary by CONTENT**, so
      two structurally identical waves collapse to one key and the second can
      never fire. Replaced with an index and a parallel flag array. The same
      draft also called a method that does not exist (`add_sibling_deferred`) and
      gave a dogfight no way to finish at all.
  - **THE EGRESS AND THE SIGNAL LEASH ARE IN DIRECT CONFLICT — W9.1, found in
    the build rather than on paper.** `main.gd` drops the FPV link at 300 m and
    returns the pilot to the menu tower; a strike now ENDS by deliberately flying
    away from the objective. **A leash that fires during a successful egress
    reads as the game punishing you for winning.** Disabled in this scene as a
    stopgap (`signal_lost_m = 0`, as the exploration scenes do). The real fix is
    that the leash must distinguish STRAYING from LEAVING — and that is the same
    fix Iteration 11's transit gate needs, which is now **three** independent
    features tripping one rule.
  - **Deliberately not built, each one a later phase rather than an oversight:**
    the ingress (W.q7), `spec["pads"]` spent on the gate family (W.q4), dares,
    node selection, and the loop that feeds the result back into `WarSim` and
    saves it (W7 — the step that turns this from a sortie generator into a
    campaign).
  - **NOT BALANCED, AND NOT TO BE TUNED YET.** Eight turrets on node 8 may well
    be brutal. H6 says SDI is measured and never authored, so the first flights
    exist to produce a number rather than a good one.
  - 17 checks PASS.

- **2026-07-31 — v1.95. THE BOARD IS GREEN, the Atlas debt is DIAGNOSED, and the
  config stamp is caught missing the ammo fields.** The re-measure HANDOFF §1
  demanded, run first and alone so no script recompiled under it.
  - **All three layers PASS under pilot v7** — lethality, delivery (both
    directions), and 29 duels. The first clean full board since the weapons
    changed, and `balance/delivery_factors.json` is rewritten. **No number
    measured before today should be quoted again.**
  - **`Atlas × Raiders` −0.67 REPRODUCED AND EXPLAINED, and it was never a
    durability failure.** Layer 3's survival line beside it settles what a year
    of exchange deltas could not: the Atlas spends **4% hull to the Kestrel's
    9%** and survives **76.7 s against 12.0 s**, so its durability is real and is
    exactly P3.4's promise. It loses the exchange because it **fired 0.8 missiles
    where the Kestrel fired 3**, at an identical 1.00 hit rate. A missile needs a
    lock, so the binding constraint is **acquisition** — against one raider the
    Atlas locks fine (ttk 4.2 s vs 1.7 s); against three that jink, ten seconds
    buys it less than one launch.
    - **The un-modeled factor, named:** a heavy frame pays for its stability in
      LOCK TIME, and nothing in the model prices that. `aim_quality` is keyed per
      frame and captures how well a frame holds a gun line; it does not capture
      how long a frame takes to *earn a launch*.
    - **It is S4's finding in a mirror.** S4's cells ended before damage could
      accumulate; this one never ends before the buzzer (timeout 6/6). Both are
      the 10 s cap deciding a frame cell, and S4's answer points the same way
      both times — a task that holds you in the envelope. **Another argument for
      W2, arrived at from the measurement instead of from the doc.**
    - Explicitly NOT to be fixed by raising `MAX_SECONDS`: a changed rig constant
      is a different measurement, not a better one.
  - **THE CONFIG STAMP DID NOT COVER THE HEAT SINK OR THE MAGAZINES, and the
    hash proved it by not moving.** `DELIVERY_FIELDS_COMBAT` listed ballistics,
    lock and fuse fields — nothing that can END a burst — so v1.91 and v1.92
    hashed IDENTICAL and the board would have quoted pre-heat factors as current
    forever. The only thing that caught it was a human writing the debt into the
    handoff by hand. **This is the second time this exact hole has opened** (the
    first was FlightConfig in Phase 4b), so the rule is restated harder: *anything
    that can stop a weapon firing is a delivery input*, because `aim_quality` is
    hits per shot FIRED and a weapon that quits mid-cell changes the denominator.
    - The proof it mattered is in the same run: **`Flak x Screamer` spent exactly
      24.0 rounds — the whole magazine** — the first cell in this project's
      history that is ammunition-bound rather than time-bound.
    - Fixed, and **re-measured a second time under the corrected stamp**, because
      a longer hash recipe over unchanged configs would otherwise blank the
      predicted column and read as drift that never happened.
  - **The jammed-blaster asymmetry is a DUTY story, not a broken cell — but the
    MAGNITUDE was one noisy sample and is retracted.** The direction reproduced
    across two runs (Atlas hand-aims better than the Kestrel under jam: 0.02 vs
    0.23, then 0.05 vs 0.20), and in the duels the Kestrel spent 49.5 rounds on a
    screamer where the Atlas spent 4.0. One mechanism explains all of it: the jam
    removes the director and leaves a fixed 6° cone, the light frame slews fast so
    the cone opens constantly and it fires while whipping around, the heavy frame
    fires rarely and only when actually pointed. BALANCE.md's flak-column rule —
    *read the duty beside the rate* — called it in advance.
    - **What is NOT supported: "eleven times better".** That came from 2 connects
      out of 90; the second run read 5 out of 95, which is the same claim at four
      times instead of eleven. **A cell resolving single-digit connects cannot
      carry two decimal places**, and quoting a ratio built on 2 events was the
      error. The ordering is the finding; the ratio is not.

- **2026-07-31 — v1.95b. THE DELIVERY BENCH DOES NOT REPRODUCE ACROSS PROCESSES,
  and the turret column is the whole of it.** Found for free: the stamp fix
  forced a second full report at identical settings, which is exactly the
  experiment BALANCE.md ran once to put a noise figure on the DUEL harness and
  had never run on the bench that feeds it.
  - **34 of 47 factor cells came back bit-identical. Six moved by more than
    0.04, and five by more than 0.09** — against a documented readability floor
    of ~0.04. Every mover that involves a threat is a **turret** cell:

    | cell | run 1 | run 2 | delta |
    |---|---|---|---|
    | `evade: kestrel x turret [jink]` | 0.08 | **0.36** | 0.28 |
    | `evade: kestrel x turret [steady]` | 0.40 | 0.22 | 0.18 |
    | `evade: atlas x turret [auto]` | 0.04 | 0.16 | 0.12 |
    | `evade: atlas x turret [steady]` | 0.04 | 0.16 | 0.12 |
    | `contact: kestrel x gnats` | 2.07 | 3.22 | 1.15 (a rate) |

  - **THE ORDERING INVERTED, which is the part that matters.** BALANCE.md's
    standing promise for this table is that *the ordering is stable and only the
    decimals move*. Read the Kestrel's turret triple in each run: run 1 says
    `[jink]` 0.08 against `[steady]` 0.40 — jinking cuts incoming fire fivefold.
    Run 2 says `[jink]` 0.36 against `[steady]` 0.22 — jinking makes you *easier*
    to hit. **Those are opposite design conclusions from the same command.** The
    promise holds for the raider column and fails for the turret one.
  - **EVERY raider cell reproduced exactly**, `[auto]`, `[jink]` and `[steady]`
    alike. So this is not "the bench is noisy"; it is specific, and it lands on
    the type that should be the MOST reproducible thing on the board — a turret
    has no `ai_seed` and fights an identical engagement every rep. The
    expectation is inverted, which is why it is worth a note rather than a shrug.
  - **It is also a DIFFERENT failure from v1.80's**, and worse. v1.80 found that
    a jink cell's result *"depends on what ran before it in the same process"* —
    history dependence, fixable by fixing the history. These two runs share an
    identical history and still disagree, so the divergence is **cross-process**.
  - **The most likely cause is sample size, and it is measurable rather than
    mysterious.** An `evade` cell fires 38–50 rounds and resolves 2–18 hits, so
    `0.04` versus `0.16` is *six rounds*. A cell that resolves single-digit events
    cannot support a two-decimal factor, and the ratios that look alarming are
    small integers wearing decimals. **The fix is a longer cell, which costs bench
    minutes — a scope call, not a code call, so it is not taken here.**
  - **What this does NOT touch:** the Atlas diagnosis above rests on the raider
    cells (identical across both runs), the duel's fired-missile counts, and Layer
    3a arithmetic. It stands. **What it DOES touch:** every survival time quoted
    against a turret, which is derived from a factor that just moved fourfold.
  - **THE DUEL HALF REPRODUCED, and better than the bench that feeds it.** All
    **29 of 29 win rates and 29 of 29 kill counts came back identical**; 20 of 29
    cells were bit-identical across every field, and the movers moved only on
    `dmg-taken` and `spent`. So the *validation* layer is steadier than the
    *measurement* layer underneath it, which is an awkward sentence and a true one.
  - **THE ATLAS FINDING IS REPRODUCED, essentially bit-for-bit**, which is what
    makes it safe to build on:

    | | run 1 | run 2 |
    |---|---|---|
    | `Atlas x Raiders` delta | −0.67 | **−0.65** |
    | Atlas missiles fired / kills | 0.8 / 0.8 | **0.8 / 0.8** |
    | Kestrel missiles fired / kills | 3.0 / 3.0 | **3.0 / 3.0** |
    | survival, kestrel / atlas | 12.0s / 76.7s | **12.0s / 76.7s** |
    | Atlas hull spent | 4% | **4%** |

    The 0.02 movement is well under the ~0.04 readability floor. **The lock-
    acquisition diagnosis is not a one-run artifact.**
  - **AND THE REAL PATTERN, visible only now that there are three observations:
    it is the TURRET, on both benches, across three pilot versions.** BALANCE.md
    already records `Atlas × Turret` reading `dmg-taken` 22.2 then 18.7 under an
    unchanged pilot v3, and filed it as generic *"~16% run-to-run variance"*. This
    pair of runs reads **23.3 then 18.7** on the same cell — nearly the same two
    numbers again — while every raider cell on both benches reproduces exactly.
    **It was never generic float variance. It is localised to one enemy type**,
    and it has been mis-attributed to the process three times because nobody
    compared two full runs cell by cell. What makes a turret engagement chaotic
    where a raider engagement is not is unexplained and is the thread to pull.
  - **BALANCE.md's "the board is RED on purpose" is DELETED as stale.** It
    described the window between `atlas × raider [jink]` saturating and the
    datum/factor split reaching that cell; `[jink]` is a forced mode and therefore
    a datum, and a saturated datum has not failed the run since v1.82. **A stale
    RED in a doc is worse than a stale number — it teaches people the board is
    supposed to be broken.**

- **2026-07-31 — v1.96. ITERATION 12 PHASE 1: the war learns its own bestiary,
  and one id replaces two spellings.**
  - **The falx and the screamer join `WarManifest`** (W8), with doctrine placed
    by what each type is FOR: falx garrisons `airspace`/`airbase` on the outer
    ring (an interceptor owning open air is a picket), screamer only `sam`,
    `radar` and `command` on the mid ring (it is never why a node is defended,
    always why the defence is hard to shoot at). Both **provisional pacing, flagged
    for hands.** Falx joins `FLYER_TYPES` so cover thins it like a raider;
    screamer joins neither cover list on purpose (it goes where its escortee
    goes, so tinting it would price one decision twice) and joins `HEAVY_TYPES`,
    which is a design claim: **EW is what a war fields once it has been running.**
  - **The screamer reports as plain `air` through fog**, deliberately. Give
    jamming its own family and a month-old report still warns you; folding it in
    makes "the lock will not build" the kind of surprise P1.3 says stale intel is
    for. Flagged as the line to change if it reads as a cheat rather than a
    consequence.
  - **`gnats` → `gnat`** (W.q6). The wave director was the only system spelling
    it plural, and the cost was **the same translation line copy-pasted into three
    separate checks** (`ammo_check`, `composition_check`, `heat_check`) — the
    usual sign that the wart is in the data, not the readers. All three deleted.
    `delivery_bench` keeps its `"gnats"` **untouched and on purpose**: there it is
    a cell LABEL that `TYPE_IDS` already translates at the boundary, it is what a
    WATCH filter matches, and it is baked into the keys of
    `delivery_factors.json` — renaming it would silently invalidate every measured
    factor. **The bench was always right; the wave director leaked a display
    spelling into a type key.**
  - **The escort rule is enforced in the manifest, not just stated** — the same
    discipline `WaveDirector.compose()` uses, and for the same reason (`DOCTRINE`
    is data, and data gets edited by someone not reading the function). A
    jammer-only garrison is rewritten into the cheapest threatening type its
    doctrine allows, strength-neutrally.
    - **And the guard is tested DIRECTLY, because it cannot fire today.** A
      2832-projection sweep found zero offenders — the greedy fill buys the
      highest-weighted affordable type first and the screamer's share never
      exceeds 0.20 in any row, so it is never bought first and therefore never
      alone. A guard that cannot fire is indistinguishable from a guard that does
      not work, so `manifest_check` exercises it with a mix no doctrine produces,
      **and asserts it leaves a mixed garrison alone** — v1.91's lesson (*a check
      that has never failed has not been tested either*) applied before it cost
      anything.
  - **`manifest_check` now asserts the two rosters against EACH OTHER**, in both
    directions, plus that every war-fieldable type resolves to a loadable scene
    and that the `threat` flags agree across the two tables. That is the assertion
    whose absence let the roster gap live for two weeks: a roster only ever
    compared against itself is self-consistent.
  - 16 checks PASS.

- **2026-07-31 — v1.94. ITERATION 12 PROPOSED (W1–W11, W.q1–W.q7): THE BRIDGE.
  The war has never been played, and that is now the whole roadmap gap.**
  - **The structural fact the iteration is built on:** `SortieComposer.compose()`
    is called by nothing but its own tests, and `grep` confirms **no scene code
    anywhere references `scripts/war/`**. Against the slice target (~5 nodes · 2
    frames · 3 weapons · 4 enemies) the state is 0 / 2 / 3 / 6 — everything
    except the map is at or past target, and the map is not missing art, it is
    missing a function call.
  - **W2 is the argument worth keeping: the bridge must terminate in a STRIKE,
    not a Dogfight.** The composer flattens a dogfight's garrison to one layer
    and splits its reserve into `wave_cleared` waves — that is `WaveDirector.PLAN`
    with different spelling, exactly as P2.12 says. S4 already named what a Strike
    adds and a duel cannot: **time in the threat envelope**, its own item 2, *"a
    task that holds you in the envelope."* H7's 127 sorties, the Atlas's −0.67 and
    H6's graded middle all sit on the far side of S4's conclusion — **duels prove
    feel-promises; sorties produce curves.** The Dogfight still gets built as the
    cheap proof the pipe connects; it is a waypoint, not the destination.
  - **W4 — P2.6's pad count has been waiting for hardware that Iteration 10
    built by accident.** The composer has emitted `pads: int` since v1.71 with
    nothing to spend it on; R1 then built the repair gate and the two resupply
    gates while observing that P2.6's re-arm clause described a resource that did
    not exist. R1 was solving the missing resource and also built the pad. The
    bridge designs no pads — it spends the field on the gates that exist.
  - **STEERED THE SAME DAY, three answers:**
    - **The balance re-measure runs FIRST and ALONE.** The bridge touches no
      weapon, enemy or frame config, so the two are independent — but editing
      `.gd` files under a 45-minute measurement risks a mid-run recompile, and
      BALANCE.md's whole discipline is about not contaminating a ruler. Design
      work continued in Markdown, which recompiles nothing.
    - **`jam_range` STAYS AT 55 m — the gap IS the counterplay** (user's call;
      the alternatives were raising it past `missile_lock_range` 60 or shortening
      every missile engagement in the game). So standing off at ~57 m and
      launching is now a *designed* answer to a Screamer rather than an
      oversight, and P4.3's missile row against it should be read as taxed by
      approach geometry, not by the jam. **Closes the open item that has sat in
      HANDOFF §3c since v1.84.**
    - **The Falx and the Screamer join `WarManifest` now** (W8). Provisional
      doctrine, flagged for hands: falx garrisons `airspace`/`airbase` on the
      outer layer (a picket's job description for the type you bait rather than
      chase); screamer only where there is something to protect —
      `sam`/`radar`/`command` — on the mid layer, with the manifest needing
      `compose()`'s escort rule so a small node cannot roll a garrison that
      carries no weapon at all.
  - **W9 — three collisions found by reading the two halves against each other**,
    each one only visible once the systems are introduced:
    1. **The signal leash cuts an open approach in half.** `main.gd` drops the
       FPV link at 300 m; `_approach` emits a **400 m** ingress for open ground
       (a city's 150 m fits). A composed desert Strike would lose its link during
       the ingress and read as the sortie killing itself. **Iteration 11's T2/3b
       named this same leash for the transit gate, independently** — two
       unrelated features tripping one rule is evidence the rule is what needs
       revising.
    2. **`ARENA_CENTER` is a `const`.** Every placement routine in
       `wave_director.gd` reads the greybox's usable air from it, and a generated
       map's centre is wherever the objective was laid.
    3. **Two wave counts describe the same thing** — a dogfight's reserve splits
       into exactly 2 triggered waves while `CombatConfig.sortie_waves` is 3,
       authored a month apart. One must stop existing or they will drift.
  - **W8's second half is a bug prevented rather than found:** the manifest spells
    the swarm `gnat` and the wave director spells it `gnats`. The runner needs a
    type → scene map and that map is precisely where a typo deletes a type from a
    fight — standing rule 2, and four separate Falx bugs, say a missing enemy and
    a tough enemy read identically from a results table.
  - **Recorded before the first flight rather than after it:** the first composed
    sortie will not be balanced and **must not be tuned to be**. H6 says SDI is
    measured, not authored, and the composer emits an input vector with no
    composite score for exactly that reason. The first flight's job is to produce
    a number, not a good one.
  - **W.q1/q3/q5/q6 STEERED the same day**, all four to their leans — one type id
    (`gnat`), a separate `scenes/sortie.tscn`, a Strike that ends on **egress**
    rather than on the objective's death, and **hot white** for an objective
    asset. The egress answer is the load-bearing one: it is the only reading
    under which a reserve triggered by `objective_damaged` has anything to arrive
    to, so W6's whole distinction between a wave and a reserve survives it.
    W.q2/q4/q7 are held open on purpose until a sortie has been flown.

- **2026-07-31 — v1.93. THREE ROUNDS FLOWN, and the ammo economy gets its first
  real corrections. R.q3 is RETRACTED.**
  - **THE WAVE-CLEAR RE-ARM IS GONE, and it is the most important change here.**
    v1.90 flagged the tension in writing — R.q2 makes ammo a sortie resource and
    R.q3 hands it all back every wave, so the unit of scarcity quietly became
    the wave and P2.6's pad-poor knob lost its bite. The user flew it and
    agreed: *"lets drop the wave clear refills, and only keep the gates/kills to
    provide ammo."* **Gates and kills are now the only ways to put rounds back**,
    and both cost you something — a route, or a body you have to go and stand
    over. `ammo_check` asserts the retraction rather than just deleting the code,
    because a free refill creeping back is the kind of regression that makes a
    whole economy feel pointless without any single line looking wrong.
    - Salvage was raised 0.25 → 0.34 of a magazine in the same breath. With the
      free refill gone, a drop has to be worth breaking off for.
  - **THE GATES ARE SOLID FRAMES NOW** (*"they should be like the small rectangle
    blue gates we already have. they should be collidable just like those small
    gates"*). They are the same body as `environment/gate.tscn` — four bars, four
    collision shapes — which reverses the hoop they shipped as. **A fly-through
    reward you cannot miss is not a piece of flying**; the frame is what makes
    taking a gate a thing you did.
  - **THE EXIT GATE IS CIRCULAR AND SOLID**, reversing a deliberate old choice:
    it was a "magic gate, not an obstacle" and is now a ring you can clip. Its
    collision is a **fan of 16 boxes** rather than a trimesh of the torus, and
    the segments overlap by 15% because the seam between two collision boxes is
    exactly where a fast body squeezes through. It goes non-solid while
    deactivated — an invisible gate must never be an invisible wall.
  - **PLACEMENT WAS BROKEN AND IS NOW REJECTION-SAMPLED.** *"the ammo gates were
    spawned clipping into each other."* They were sampled purely at random. Each
    candidate must now clear every already-placed gate by 16 m AND clear real
    scenery by a sphere cast, with 40 tries before giving up — **and failing to
    place is a fine outcome**: one fewer gate is a sortie that is slightly
    harder, where a badly placed one is a sortie that lies to you. Gates also
    face the arena centre, so the approach is a line you fly rather than an angle
    you have to discover.
  - **THE LABEL MOVED INSIDE THE FRAME, and the first attempt was wrong in an
    instructive way.** Two labels, one per face, renders as garbage: `GlowText3D`
    glyphs are emissive cubes with no backface culling, so from behind you read
    the far label MIRRORED and superimposed on the near one. It is one label,
    snapped to whichever face the pilot is on — not freely billboarded, because a
    sign that swivels inside a doorway reads as a loose object rather than as
    part of the gate. **Caught by a screenshot; invisible in the code.**
  - **SALVAGE GOT A BEACON** (*"i like the little ammo drops... they should be
    more visible, they are easy to miss"*). The cube went 0.36 → 0.55 m and now
    stands under a 9 m column of additive light that pulses while the cube spins:
    **the cube says WHAT it is, the beacon says WHERE it is.** Pickup radius went
    1.6 → 3.2 m, because half of missing a drop is flying near one without
    tripping it, which reads as the pickup being broken rather than the pass
    being wide. And to answer the question directly: **yes, they fall** — 2.2 m/s
    from wherever the body died down to 1.2 m, then they hang.
  - **THE REPAIR GATE IS IN A TUNNEL** (*"so the player will have to fly through
    a tunnel to get the health"*), a 26 m box around it in the greybox. The heal
    stops being something you drift over on the way somewhere and becomes a
    committed run with no room to correct — the flight model charging a price for
    what it hands you, which is the same argument D5 made when the repair PAD
    became a gate.
  - **Still provisional and still the user's:** every number in v1.92's list,
    minus the wave-clear line.

- **2026-07-31 — v1.92. THE MAGAZINES AND THE RESUPPLY GATES SHIP — Iteration 10
  is built.** Everything R.q2/R.q3/R.q4/R.q6 steered, in one slice, because the
  four refill paths are only meaningful together.
  - **The flak pod and the missile rack carry magazines; the blaster does not.**
    That split is R2's one surviving claim after R9 overrode the rest, and it is
    the load-bearing one: the blaster is the FLOOR, so a pilot out of everything
    can still fight rather than being stranded alive with the exit gate shut.
    A magazine of **0 means unlimited**, which is both the off switch and what
    every bench predating the feature would want.
  - **`ResupplyGate` is a gate, not a pad, and the user re-derived that
    unprompted.** D5 turned the repair pad into a gate because *"holding station
    on a wounded quad under fire is a death sentence"*; the ask for these said
    "flying through" without being told. Amber = flak, violet = missile, both
    colours nothing else in the palette claims, and the ring is deliberately
    **smaller than the exit gate's opening** — threading it IS the challenge the
    ask wanted ("more challanges to get more resources"), which is the flight
    model advertising itself.
  - **Finite charges, and the count is on the gate** (R.q4). A gate that
    refilled forever would delete P2.6's pad-poor difficulty knob before it ever
    got a referent, so the wave director now lays **fewer gates as the sortie
    number rises** — the first time this project has had a difficulty axis about
    ROUTE rather than about how many enemies arrive. A spent gate goes dark and
    **stays in the world**: a landmark for where you have already been, not
    litter that vanishes.
  - **The gates wear the menu tower's glyphs**, per the ask, which is why
    `GlowText3D` grew **digits** the same day. Its font table was space and A–Z
    only — B5's floors are words — so a charge count would have rendered as a
    row of hollow unknown-glyph boxes. First branch of B8's word chains outside
    the tower.
  - **Salvage drops, and the user's reason is the better argument.** I had
    leaned gates-only on the grounds that a drop rewards killing where a gate
    rewards flying. Their counter: *"it would give the player a reason to take
    out the infinite turrets."* The arena's turrets respawn on a 20 s cycle and
    were worth points nobody needed, so they were scenery you flew around —
    **this is the first time that respawn timer has meant anything.** A drop is
    a quarter magazine, drifts down, and expires, so a kill you do not go and
    take is a kill you did not finish.
  - **Two guards that exist to protect a careful pilot**, and both are asserted:
    a gate must not spend a charge against an already-full magazine, and salvage
    must not consume itself against one. Either would punish exactly the player
    who routed well, and both would read as the feature being broken.
  - **`ammo_check.gd` is the sixteenth check**, and it is `heat_check`'s mirror:
    not a gun that never comes back, but a magazine that never refills.
  - **IT CAUGHT A PRE-EXISTING INTERMITTENT FAILURE ON THE WAY IN**, which is
    the useful part. `run_check` asserts a draft pick changed `RunMods` by
    comparing a HAND-LISTED set of fields; the pool had grown four cards
    (v1.86's two flak, v1.91's two heat) that the list did not name, so the
    check passed or failed purely on whether `draft()`'s shuffle offered one at
    index 0. **It passed alone and failed in a batch** — the worst way for a
    regression check to behave. It now compares every script property
    generically and cannot drift out of date again.
  - **PROVISIONAL, all of it, and this is the part that needs hands:** 24 flak
    shells, a 6-missile rack, 3 gates at sortie 1 decaying to 1, 2 charges each,
    a 35% drop chance split 70/30 toward flak. None of these can be judged from
    a bench — they are pacing, and pacing is the user's call.

- **2026-07-31 — v1.91. THE BLASTER GETS A DUTY CYCLE (Iteration 10, R.q1 built),
  and Layer 1 stops assuming infinite ammunition.** The first slice of the ammo
  work, and deliberately the one that needs no gates: heat refills itself.
  - **The model, and why it is shaped for arithmetic.** `heat_per_shot` fills a
    `heat_capacity` sink; venting begins only after `heat_vent_delay` (0.35 s) of
    quiet, so **sustained fire never cools** — the gap between bolts at any
    usable cadence is shorter than the delay. That is not an accident of the
    numbers, it is what makes a burst an exact integer (`capacity / per_shot`)
    instead of a simulation, which is what lets Layer 1 model it in closed form.
    Shipping values: 30 bolts, then a 2.10 s vent. Provisional.
  - **`heat_reset_fraction` is the part that would be missed.** A lockout that
    cleared the moment heat dipped under the ceiling would let a held trigger
    stutter along AT the ceiling forever — one bolt, lock, one bolt, lock — which
    is the version of overheat that feels broken rather than tactical. The gun
    stays dead until the sink is back to 30%.
  - **R7's promise kept the same day, not later.** `Lethality._exchange` now
    carries a burst term and a REAL CLOCK: it used to report `hits x interval`,
    which is only correct for a weapon that never stops. A kill that needs more
    bolts than one burst holds now pays for the vents it crosses — **and because
    the pause runs through the same clock as the intervals, a shield regenerates
    during it for free.** That interaction was not designed; it fell out, and it
    is the right answer.
    - **No shipped Layer 1 cell moved**, because no blaster kill on the roster
      is longer than 2 bolts (the aegis's `NEVER` is a threshold verdict, not a
      long one). The arithmetic is now correct for a case the table does not yet
      contain, which is the only time it is safe to add.
  - **`heat_check.gd` is the fifteenth check**, and it exists for the worst
    failure available: a gun that locks out and never comes back leaves a pilot
    alive, armed, and unable to clear a wave. Nothing else in the suite would
    catch it — every other check either kills its enemies with `take_hit` or
    never holds the trigger long enough. It also asserts Layer 1's arithmetic
    against the LIVE weapon, which `lethality_check` structurally cannot do:
    that bench plants shots from the model itself and would agree with itself
    all the way to a wrong answer.
    - **It failed twice before passing, and both were the check, not the gun.**
      First it reported "the gun never came back" — the gun was fine, the drone
      was dead, because arming starts a real run and a real run shoots back.
      Then it reported a bolt fired DURING the lockout: it tested for stray
      bolts before testing whether the lockout had already ended, and the tick a
      lockout clears is a tick the gun legitimately fires on. **A behaviour
      check that has never failed has not been tested either.**
  - **THE BOARD OWES A RE-MEASURE, and this is the flag.** Unlike the cloak,
    this is not visual: the delivery bench and the duel harness fly the real
    `Weapon`, so every blaster cell now carries a vent. `PILOT_VERSION` does NOT
    bump — the pilot's brain is unchanged; the weapon under it is not — but no
    blaster number measured before today should be compared to one measured
    after it.
  - **PROVISIONAL and flagged for hands:** 30 bolts and a 2.10 s vent is a ~59%
    duty cycle. Two new draft cards answer it (`Heat Sinks` +45% capacity,
    `Vent Ports` +50% cooling; pool 9 → 11), and they exist because **`Rapid
    Blaster` now has a real cost** — it buys rounds per second and spends them
    out of the same sink, so a run that stacks fire rate without ever taking one
    of these is buying a shorter burst. That is a consequence to measure, not to
    assume.

- **2026-07-31 — v1.91b. The stargate is NOT what the user aimed for, recorded
  as a gap rather than closed.** *"its cool but not what i aimed for"*, with
  references. The difference is structural, not tuning: the reference recipe
  uses **polar UVs** (so detail wraps angularly around the disc, where concentric
  `sin()` rings alone read as a struck drum) and **two noise layers scrolling in
  opposite directions with the first displacing the second's UVs** — domain-warped
  noise, which is what churns. Periodic trigonometry cannot get there; the eye
  reads periodicity as machinery. **The blocker is the house rule**: proper noise
  needs either a procedurally-generated `NoiseTexture2D` (no file on disk, likely
  acceptable) or a hash-based value-noise function written by hand. That choice
  is the first decision of the rework and is why this is a note, not a patch.
  Both references are written into `portal.gdshader`'s header and Iteration 11's
  T2b, next to the code they would replace.

- **2026-07-30 — v1.90. THE FIRST FLIGHT OF THE CLOAK, Iteration 10 STEERED in
  full, and Iteration 11 PINNED.** All from one round of cockpit feedback.
  - **THE CLOAK'S OWN ANTENNA WAS GIVING IT AWAY** — *"its antena might be more
    invisible, maybe as a difficulty axis"*, and both halves of that were right.
    v1.89 left the dish emitter untouched at up to 5.5 energy, which is a bright
    red lamp towing an invisible aircraft: the hull's shimmer was decorative
    because the thing was findable at any range anyway. The dish now dims too.
    - **And the dial is the user's second half, taken literally.**
      `EnemyConfig.cloak_strength` (0..1, screamer ships at 0.8) scales BOTH the
      floor under the hull's shimmer and how far the dish may dim, so the two
      halves of "how hidden is it" can never disagree. It is one number in the
      overlay's BESTIARY block and it is a real difficulty axis: turn it down to
      make a sortie kinder. `DISH_HIDE_MAX` 0.88 stops even a full cloak from
      taking the last ember, because the palette rule (red = threat) outranks
      the dial — an enemy with no colour has no role written on it.
    - **Gotcha for anyone with saved bestiary tunings:** a `user://` EnemyConfig
      written before today has no `cloak_strength` and will load it as 0.0,
      which is the *uncloaked* dish. Defaults restores it.
  - **THE EXIT GATE IS A STARGATE NOW** — *"can we replace the exit gate from a
    2d whirrpul into something like the movie stargate, like a face of a quiet
    pool."* Done, and the reason it is an improvement rather than a reskin: a
    whirlpool SPINS, and spin reads as hazard, which is the wrong sentence for
    the one object in the arena that is a reward for clearing a sortie. A quiet
    pool reads as arrival. Same fly-through, opposite invitation.
    - **Three passes, and every one of them was a thing only a screenshot could
      say.** (1) Every colour was above the 1.0 bloom threshold, so the gate
      rendered as a featureless white disc — glow had eaten the ripples that
      were the entire point. The fix is a rule worth keeping: **the water stays
      under the threshold and only the caustic glints and the rim are allowed to
      burn**, because the glow pass blurs whatever it catches. (2) The frame
      bars at energy 3.0 bloomed into one white slab; a frame brighter than the
      surface it frames is not a frame. (3) `ripple_scale` was being read as
      RADIANS, which put one and a half broad bands across the whole disc — a
      radial gradient, not a pool. As a ring count times TAU it became water.
    - **The rig that caught them also had to be fixed twice**, and both are
      worth writing down: a camera transform set this frame does not reach the
      rendering server until the frame flushes, so `force_draw()` photographs
      the PREVIOUS aim; and the screamer overwrites its own shader uniforms
      every physics tick, so a rig that sets them in `process_frame` silently
      photographs the live value instead of the one it asked for. Both produce
      plausible screenshots of the wrong thing, which is the worst failure mode
      a look check has.
  - **Iteration 10 steered in full (R9): every R.q answered, and R2 overridden.**
    The blaster gets a rechargeable, overheatable, upgradeable charge meter
    instead of being infinite. **My "three consumables would be two too many"
    was challenged and it was wrong as written** — it counted HUD counters when
    the real cost is whether running dry can *strand* you. A self-recharging
    heat meter never strands, it paces: two economies (flak, missile) and a
    tempo mechanic (heat), which is a shape the objection does not touch.
    Flagged in the same pass: R.q2 + R.q3 together relocate the unit of scarcity
    from the sortie to the wave, which is likely the better game but costs
    P2.6's pad-poor knob most of its bite.
  - **Iteration 11 PINNED — the transit gate** (*"like the game portal"*).
    Pinned rather than proposed because it is the first idea on the board that
    could fight the flight model: a discontinuous basis at 240 Hz is a
    discontinuity in `_measured_rates` and an infinite D-term derivative, and a
    world that rotates 90° in one frame is an assault on an FPV camera. Both are
    solvable and neither is a shader problem, which is exactly why it is written
    down before anyone opens one.

- **2026-07-30 — v1.89. THE SCREAMER CLOAKS (the user's ask, handoff ITEM 2):
  *"maybe since it doesnt engage, maybe we should give it a new equipment of
  invisibility... like the predator from the movie, where reality is ever so
  slightly distorted."*** A screen-space refraction on the hull and mast
  (`resources/cloak.gdshader`), no textures and no assets — the pixels behind
  the surface, sampled at an offset weighted by the view-space normal and a
  fresnel term so the edges bend hardest.
  - **THE WHOLE TRICK IS THAT ZERO DISTORTION MEANS INVISIBLE.** At `shimmer` 0
    the offset is zero, so every fragment samples exactly the pixel it covers
    and the body is gone — not faded, not ghosted, *gone*. One number therefore
    spans "cannot be seen at all" to "unmissable heat haze", and the script
    hands that number **the jam level**. The interference wrecking your gear is
    the same thing that shows you where it is coming from: **what hides it is
    what finds it.** Deliberately not a distance curve of its own, for the same
    reason the audio tone is not left to 3D attenuation — a second curve that
    disagreed with the jam would teach the wrong edge, and here the wrong edge
    is *"I can see it, so my gun must work"*.
  - **The cloak drops on every hit** (`CLOAK_REVEAL_S` 0.3 s), and this was
    non-negotiable rather than polish: without it the player is firing at
    something they cannot see with no confirmation of contact, which reads as a
    broken weapon rather than a cloaked enemy. It fires on contact, not on
    damage — a round that glances off armor still has to *look* like it landed.
  - **The palette rule survives** (CLAUDE.md: red = threat). Two things keep the
    type legible as hostile: a faint hot rim on the silhouette that only appears
    where the cloak is already shimmering — so it never gives away a screamer
    the jam has not already announced — and the dish emitter, which was left
    un-cloaked and already ramps its emission with the same jam level. **A
    cloaked screamer at range is a floating red glint and nothing else**, which
    is exactly the read the item asked for and needed no new code.
  - **IT WAS LOOKED AT, NOT REASONED ABOUT.** A throwaway rig parked a camera
    3.2 m off the dev-room specimen against the ground grid and saved a frame
    per state. That is how two things were caught that a headless pass cannot
    see: the rig was silently fighting the screamer's own per-tick uniform
    writes (every "state" was rendering at the same shimmer floor until the
    specimen was frozen), and `unshaded` — required, since a lit surface would
    light the *screen sample* — means no light ever reaches the revealed hull,
    so the honest albedo read as a black cut-out and `body_color` was lifted to
    compensate. Neither was visible in the code.
  - **Confirmed visual-only.** All 14 checks pass, and a filtered duel LOOK at
    the four screamer cells reproduces v1.84 exactly (`Blaster --` 0%,
    `Missile ++` 100%, `Flak --` 0%). That was the stated bar: a "visual-only"
    change that moved a measured cell would not have been visual-only.
  - **PROVISIONAL, and the whole of it is the user's:** `distortion` 0.045,
    `edge_energy` 0.55, `CLOAK_REVEAL_S` 0.3, and `CLOAK_FLOOR` 0.15 — a floor
    under the shimmer so a screamer at the very edge of its field is *faint*
    rather than mathematically invisible. **Set the floor to 0.0 for the pure
    version**, where a screamer outside its own jam range genuinely cannot be
    seen and only the dish gives it away. Also unflown, and only the hands can
    judge it: the cloak and `jam_video_glitch` fight for the same screen, and
    they have to be read together rather than separately.

- **2026-07-30 — v1.88. Iteration 10 PROPOSED (R1–R8, R.q1–R.q6): AMMO & THE
  RESUPPLY GATES, opened by the user from the cockpit.** *"maybe we can have the
  ammo counter, maybe a gate type for each weapon ammo."* Written as a proposal
  and NOT built, because the ask carries four "maybe"s and at least one fork I
  cannot infer from it (R.q5: whether "energy" is a third resource or another
  word for ammo).
  - **The finding that shaped the paper: this is not a new pillar.** P2.6 has
    said pads *"repair hull + re-arm magazines"* since Iteration 5, P5.6 prices a
    between-sortie re-arm, and `SortieComposer` already emits a difficulty-scaled
    `pads` count. **None of it means anything, because there are no magazines.**
    The user has independently asked for the referent those three sections have
    been missing — which is why the proposal is short: the grammar was already
    written, it just had nothing to point at.
  - **The form factor was already decided by playtest, and the user re-derived
    it.** D5 turned the repair PAD into the repair GATE because *"holding station
    on a wounded quad under fire is a death sentence."* The ask says "flying
    through" without prompting. Resupply is a gate you thread, never a pad you
    land on.
  - **The one place the paper pushes back on a literal reading**: "a gate type
    for each weapon" would give the blaster a magazine too, and the blaster is
    the floor — a pilot out of everything must still be able to fight or a dry
    run is an unwinnable stalemate with the gate shut. Recommended split: blaster
    infinite, flak and missile consumable.
  - **Flagged before anyone builds it: Layer 1 assumes infinite ammunition.**
    `Lethality.versus` answers "how many shots to kill this" with no term for
    whether you have that many. Magazines add one — the same arithmetic that
    already makes a swarm bankrupt a missile, generalised. It must ship WITH the
    feature, or the first bench run afterwards reports numbers that quietly
    assume a resource the game stopped giving you.
  - **Sequencing warning carried over from v1.86:** the pod already took a real
    nerf when it stopped riding the blaster's draft cards. Fly that before
    stacking a magazine on it, or two changes land inside one feel judgement and
    neither is attributable.

- **2026-07-30 — v1.87. The plan cashes its own promise: GNATS EVERYWHERE.**
  From the same flight: *"the gnats does not show too much and i really like
  them."* True — v1.85's table put a cloud in 2 of 9 waves. Now 6 of 9, and
  **every wave of sortie 3+ carries one**, which is where a long run actually
  lives; the finale carries two. Sortie 1 wave 1 and sortie 2 wave 1 are left
  clean deliberately: the run's opening and the wave right after a draft are
  where a cloud reads as noise rather than pressure.
  - **The change is four lines of table and no code at all**, which is the v1.85
    shape being cashed in for the first time. `composition_check` re-derived
    every assertion from the new table without an edit, because it asserts
    properties (whole budget spent, a threat present, arena agrees with plan)
    rather than a hard-coded line-up. That is the whole reason it was written
    that way.

- **2026-07-30 — v1.86. THE FLAK WAS RIDING THE BLASTER'S UPGRADES, and the user
  caught it from the cockpit.** *"the flak is effective as the fire rate grows
  (its tied to the fire rate of the blaster, i think by mistake)."* It was, and
  it was two cards, not one: `Rapid Blaster` ("+35% blaster fire rate") and
  `Heavy Bolts` ("+40% blaster damage") set `RunMods.fire_rate_mult` and
  `damage_mult`, and **both `Weapon` and `FlakPod` read them**. One pick, two
  weapons upgraded, and the card text never said so.
  - **How it happened, because the shape will recur.** The mods were named
    generically (`fire_rate_mult`, not `blaster_fire_rate_mult`) at a time when
    there was one gun. The pod arrived later and reused the field that fit,
    which is the path of least resistance and reads as correct in the diff. The
    UI string was the only place the intent was written down, and strings do not
    fail tests. **A run-scoped modifier should be named for the thing it
    modifies, and a weapon added later should have to introduce its own.**
  - **The larger half was the free half.** Cadence is where a burst weapon's
    power lives — the pod fires 2.5/s against the blaster's 10, so a 1.35x on
    its interval is worth far more per pick than the same number on the gun that
    card was sold as. The user felt exactly this: *"once the fire rate is high it
    starts to be buffed."*
  - **The fix is the one the user proposed: its own cards.** `flak_fire_rate_mult`
    and `flak_damage_mult`, read only by the pod, fed by two new draft options
    (`Autoloader`, `Dense Fragments`). The pool goes 7 → 9. **Decoupling is also
    the nerf** — the pod's curve now costs a draft pick instead of arriving free
    — which is worth flying before adding any further limit on top of it.
  - **Nothing was re-measured, and nothing is owed.** Every bench passes
    `damage_mult = 1.0`, so Layer 1's table never saw either mod; the split moved
    no cell. `Lethality`'s header now states which mult belongs to which weapon,
    so a future caller that does pass live mods cannot repeat the bug inside the
    instrument that exists to catch it.
  - **NOT done, deliberately:** the user's *"we may limit its usage to shorter
    bursts."* That is ammo, and ammo is the proposal in Iteration 10 — building a
    magazine here would pre-empt a fork that is still open.

- **2026-07-30 — v1.85. M6a step 8: RUN MODE GETS THE ROSTER. Six types existed;
  one of them had ever been in a run.** The user flew the game and said it "might
  be stale". It was, and the cause was a single line: `wave_director.gd` held one
  `const ENEMY_SCENE`, so **every wave of every sortie was raiders** while the
  gnat swarm, aegis, falx, screamer and turret lived only in the dev room. A year
  of bestiary work had never reached the thing you actually play.
  - **A wave is now a BUDGET filled from a PLAN.** `WaveDirector.ROSTER` maps a
    type to its scene plus the three facts the director needs (air or ground, and
    whether it threatens you at all); `PLAN` is sortie × wave → the named units
    that wave spends its budget on; raiders fill the rest. **Adding a bestiary
    type to the run is a ROSTER row and a PLAN slot — if it ever needs code, the
    file has the wrong shape.** That is `matchup_harness.MATCHUPS`' discipline
    applied to the run.
  - **Named units come OUT of the budget, never on top of it** — SortieComposer's
    reserve rule (P2.3) borrowed on purpose. The war sim itself is deliberately
    NOT wired in: M4's run is not the M6 campaign and must not quietly become it.
    Only the vocabulary is shared, so the two cannot drift apart conceptually
    while they are still separate systems.
  - **THE UNIT IS THE UNIT, and three types can deadlock a wave in a way a body
    count cannot see.** `remaining` counts units, not bodies. A gnat **cloud** is
    one unit and nine bodies and announces its end with `cleared`, not
    `destroyed` — a director counting `destroyed` clears the wave eight bodies
    early and then never again. A **turret** respawns on a 20 s timer, so a wave
    holding one is unclearable for as long as the run lasts (it gained a
    per-instance `respawns` flag; arena furniture cycles, a wave's emplacement is
    spent). An **aegis** can leave the field WITHOUT dying, by reaching its
    target — the one exit that fires no `destroyed` and pays no points, and the
    one that would have hung a wave forever with the gate never opening.
  - **The escort rule is ENFORCED, not stated.** The screamer carries no weapon,
    so a wave of nothing but screamers is a wave with no fight in it. `compose()`
    reserves the budget's last slot for a raider and then re-checks the result,
    because PLAN is data and data gets edited by someone who is not reading
    `compose()`.
  - **Two latent bugs fell out of the rewrite, both invisible from the old code.**
    (1) The director positioned enemies AFTER `add_child`, so every wave raider in
    the game's history read its wander home as `(0,0,0)` — the harness had already
    learned to place before entering the tree and had written down why; this file
    never got the lesson. (2) The bomb run now flies level at **26 m, above the
    greybox's 24 m skyline**, because a bomber routed through the city at gate
    height can wedge against a tower, and an intercept clock that cannot arrive is
    a wave that cannot clear.
  - **`composition_check.gd` is the fourteenth check**, and it is the behaviour
    check the roster rule demands. Part A sweeps 320 compositions with no arena at
    all — the only way to cover sorties nobody has time to fly to — asserting that
    every wave spends its whole budget, names only real types, holds a threat, and
    that **every roster type actually reaches a wave**, which is precisely the bug
    being fixed and is invisible from anywhere else. Part B flies three real
    sorties, checks the arena against the table wave by wave, and **deliberately
    lets both bombers through** so the detonation path is the one under test.
    `wave_check` and `run_check` now assert on units rather than raw bodies; their
    flow assertions are untouched.
  - **NOTHING WAS RE-MEASURED, and nothing is owed.** Neither the duel harness nor
    the delivery bench goes anywhere near the wave director — they build their own
    arenas. No cell moved, no `PILOT_VERSION` bump.
  - **PROVISIONAL, and flagged for hands: the plan IS the pacing, and pacing is
    the user's call.** The table argues with the handoff's sketch on one point —
    the falx lands before the cloud, because one fast body teaches "bait the pass,
    kill it in the recovery" without also multiplying the body count, and a cloud
    is a better sortie finale than a mid-sortie surprise. Two things to watch
    while flying it: sortie 1 wave 3 is three raiders plus a nine-body cloud (12
    bodies, the run's first real jump), and **a bomber that gets through currently
    costs nothing but its points** — whether the player should take a hit for
    losing an intercept is a design decision, not a bug, and it is not mine.

- **2026-07-29 — v1.84. THE RE-MEASURE, and it found a defect in the pilot it was
  run to validate. `PILOT_VERSION` 6 → 7.** Two full three-layer runs were spent
  rather than the one planned, and the second was worth it: the first showed four
  harness cells measuring the BOT rather than the game.
  - **THE DEFECT: `Blaster × Screamer` spent ONE ROUND IN TEN SECONDS** across six
    reps, against 17 for the same gun versus a falx and 24 for the director-less
    flak pod in the same matchup. v6's iron trigger decided "is the director
    working" by thresholding its solution WINDOW at 0.25 m, reasoning that such a
    window is tighter than the target's own hitbox. At a mean jam of 0.64 the
    window sits at **0.43 m** — above the threshold, so the pilot dutifully
    deferred to a director that had effectively stopped firing. **The exact "brain
    standing still" the fallback was built to prevent, relocated from full jam to
    about 0.6.**
    - **The window was the wrong quantity.** It is an INPUT to the director's
      decision; what a pilot needs to know is whether the director is DECIDING to
      fire, which is observable and needs no guess. `Weapon.director_idle_s` counts
      seconds since its last solution — driven purely by the director, so a pilot
      that has taken the trigger back cannot make it look busy again — and the
      pilot falls back after `director_patience_s`.
    - **The replacement constant was MEASURED, after the first attempt guessed
      again and failed the same way.** It must exceed the longest gap a HEALTHY
      director leaves, or the pilot hand-fires inside clean cells and moves every
      factor in the table. Swept against the committed clear blaster cells:

      | patience | `kestrel/blaster` clear | `atlas/blaster` clear | verdict |
      |---|---|---|---|
      | 1.0 s | 115 shots / 0.13 | 53 / 0.19 | contaminated |
      | 2.0 s | 90 shots / 0.17 | 50 / 0.18 | still contaminated |
      | **3.0 s** | **81 shots / 0.17** | **57 / 0.19** | byte-identical |

      So a working director goes quiet for **over two seconds at a stretch** while
      the pilot repositions, and nothing shorter can tell that apart from a
      director that has stopped for good. The margin's cost is stated rather than
      hidden: a 10 s duel spends its first three seconds deferring, so every
      jammed cell reads PESSIMISTIC by about that much.
    - **The lesson, which outlives the constant:** a threshold chosen by reasoning
      about geometry is a HYPOTHESIS, and it stays one until a bench disagrees.
      Both of this session's guesses about the trigger were wrong in the same
      direction, and both were caught by counting rounds fired — the cheapest
      diagnostic in the file and the one neither guess would have survived.
  - **THE SCREAMER'S ROW IS INVERTED FROM PAPER, and the cause is the bot, not the
    balance.** Under v7 (trigger fixed, 69 rounds now spent in that cell):

    | cell | paper | validated |
    |---|---|---|
    | `Blaster × Screamer` | `+` | **`--`** (0/6, 69 rounds) |
    | `Missile × Screamer` | `--` | **`++`** (6/6 at 2.9 s) |
    | `Flak × Screamer` | `0` | **`--`** (0/6, 24 shells) |

    - **`screamer_check` grew a fifth phase to separate the three
      indistinguishable causes**, because a results table cannot tell "it outran
      me" from "I could not aim at it" from "it is simply tough". A real pilot
      chasing a real screamer for 18 s: **closes 40 m → 30 m and stalls, fires 145
      rounds, lands ZERO.** So the type does not outrun a committed pursuit —
      **the bot cannot hand-aim.** Its manual trigger is a 6° cone with no
      ballistic solution in it, which is a 3 m circle at 30 m: it scores 0.10
      against a STATIC target and approximately nothing against a mover.
    - **Phase 4 passed while the type was unwinnable, and that is the instructive
      part.** "Does it hold a standoff against a PARKED player" is a real question
      with a real answer (it settles at exactly 40 m) and it says nothing whatever
      about a player who is chasing. **A behaviour check is only as good as the
      behaviour it puts on the other side of the arena.**
    - **THE OPEN QUESTION THIS NAMES, and it is a good one.** P4.3 rates chip gun
      `+` against a screamer because "the manual fallback stays a skill path
      forever" (P3.6, the iron trigger). That is a claim about a HUMAN's hand-aim
      — and H.q4's drill was flown with the gun director ON (human 0.21 against the
      bot's 0.17), so the one number that would settle this row **has never been
      taken.** The drill it names: the aim bench with `fire_assist_miss_m` at 0.
      Until that exists, `--` in those cells is a fact about the bot's trigger and
      not about the weapon, and both rows are recorded as bot-bounded — the same
      standing `Blaster × Raider` has carried since v1.22, for a deeper reason.
    - **Not tuned, deliberately.** Nothing about the screamer's config was moved to
      make these cells read better. The measurement is of the ruler, and drifting a
      roster type to flatter a ruler is the mistake H.q1 exists to forbid.
  - **`Missile × Screamer` predicted `--` and duelled `++`, and that divergence is
    MINE rather than the model's.** The row is keyed `jammed` (aim 0.00, no lock
    possible) while the duels flew a mean jam of **0.51** — enough to double the
    lock time, nowhere near enough to refuse it. So either P4.3's `--` describes a
    fight inside the full-jam bubble that the config does not produce, or
    `jam_full_range` (20 m) is too tight to be met at the type's own 40 m standoff.
    **A one-line change either way, and a design call rather than a measurement.**
    The harness now prints the mean jam per row so the choice can be made on
    evidence: 0.51 / 0.64 / 0.65 / 0.56 across the four screamer cells.
  - **THE ATLAS FINALLY HAS A BAD DAY, and it is in the concurrency rows.** The
    frame axis was structurally unable to report a loss before S5; now it does:

    | cell | vs Kestrel |
    |---|---|
    | `Atlas × Raiders` (3) | **−0.67** |
    | `Atlas × Turrets` (3) | **−0.31** |
    | `Atlas × Turret` (1) | −0.10 |
    | `Atlas × Raider` (1) | −0.01 |

    P3.4's paper says `0` for both group rows — being outnumbered is precisely the
    case flat armor and a deep hull were bought for, so the expectation was that it
    reads BETTER outnumbered rather than far worse. **That is the sharpest
    paper-vs-measured disagreement on the board** and it is now the frame axis's
    open question, replacing "the frame axis cannot report a loss at all".
  - **Every other cell reproduced across the v6 and v7 runs**, which is what makes
    the v7 bump provably narrow: it can only act when a director goes quiet for
    three seconds, and outside a jam that never happens. The two readable movers
    were `Blaster × Turrets` exchange +0.60 → +0.55 and `Atlas × Turrets` −0.40 →
    −0.31, both at or inside the ~0.09 floor v1.77 established, and neither is
    quotable as a change.
  - **Also fixed, found by re-reading rather than by measuring:** the screamer's
    header claimed that losing sight of the player only stops it backing away,
    while the code sent it wandering home — the opposite of P4.3's terrain `+` for
    the row, since a masked approach is how you close on something that would
    otherwise retreat forever. `_can_engage` split into `_player_in_reach` +
    `_has_line_of_sight` so the two conditions can mean different things. **Cover
    freezes it now; it does not send it home.**
  - **Regression:** full check suite PASS, thirteen checks, twice (once per pilot
    version). `balance/delivery_factors.json` carries pilot_version 7.

- **2026-07-28 — v1.83. M6a step 7: THE SCREAMER SHIPS (P4.2, roster type six),
  and S14 is discharged — S.q8, S.q9 and S.q10 all built as steered.** The first
  roster member whose entire effect is a multiplier on the player's delivery, and
  the first that two of the three balance layers cannot see at all.
  - **S.q8 BUILT AS STEERED: the jam FADES.** The user overruled my binary lean
    and the implementation vindicates the overrule for a reason neither of us
    stated at the time — **the gradient is what makes the counterplay a cost.**
    The screamer's own standoff (`preferred_range` 40) sits inside the fading part
    of its own field (`jam_range` 55 → `jam_full_range` 20), so meeting it at all
    puts you at 0.43 jam, and closing to kill it — the counterplay P4.2 names —
    walks you into 1.00. **Your gear gets worse the closer you get to the thing
    you have to close on.** A hard bubble would have made the entire approach
    free and the edge a single unpleasant surprise.
    - It is ONE SCALAR with four consumers (`scripts/combat/jamming.gd`): the gun
      director's solution window, the missile lock's build rate, the flak fuse
      radius, and the video feed. Emitters join a `jammers` group and own their
      own falloff, so a second EW type costs the model nothing.
    - **Where a step DOES remain, deliberately.** S7's rule survives intact at the
      two places that are DECISIONS rather than warnings: `Weapon.director_active`
      (a 0.25 m floor, below which the director is demanding an intersection
      tighter than the target's hitbox and the pilot should reach for the manual
      trigger) and the lock, which BREAKS at full jam rather than freezing at 0.97
      — a stalled lock is a HUD that lies about why nothing is launching.
  - **S.q9 BUILT AS STEERED: aim grows a jam STATE, not the matrix a column.**
    `<frame>:<weapon>:<clear|jammed>`, on `Lethality.STATES`' precedent. Six aim
    cells become twelve and nothing else in the instrument changes — the entire
    Layer 2 cost of an EW type, exactly as the frame axis's was.
  - **S.q10 DISCHARGED, and it was the same fact as the Screamer** — the pilot
    bump landed one step early (v1.82) precisely so it could be batched with the
    frame-evasion edit instead of costing a second re-measure.
  - **WHAT THE JAM ACTUALLY DOES, measured.** *(Figures below are the COMMITTED
    full run — `balance/delivery_factors.json`, pilot v6. The filtered looks taken
    while building read 0.12 / 0.15 / 0.23 / 0.12 on the four jammed gun cells;
    those were LOOKs, they are superseded, and the ~0.03–0.06 spread between them
    and the measurement is the ordinary run-to-run movement BALANCE.md warns
    about. The ORDERING is identical in both.)*

    | cell | clear | jammed |
    |---|---|---|
    | `kestrel/blaster` | 14/81 = **0.17**, duty 0.41 | 14/135 = **0.10**, duty 0.68 |
    | `kestrel/flak` | 67/68 = **0.99**, duty 0.68 | 7/77 = **0.09**, duty 0.77 |
    | `kestrel/missile` | 15/15 = **1.00** | **0 shots fired** |
    | `atlas/blaster` | 11/57 = 0.19, duty 0.28 | 11/54 = 0.20, duty 0.27 |
    | `atlas/flak` | 17/17 = 1.00 | 2/20 = 0.10 |
    | `atlas/missile` | 11/11 = 1.00 | **0 shots fired** |

    - **The missile is deleted, and that is P4.3's `--` arriving as arithmetic
      rather than as a tuned band.** No lock, nothing to launch, zero shots. The
      bench treats that zero as a MEASUREMENT rather than a rig break — scoped to
      cells that declared a jam, and it is the opposite direction of danger from
      Layer 3b's forbidden 0.00, since it composes to `--` rather than to
      "invulnerable forever".
    - **The flak pair is where the jam really bites, and it is the only honest
      apples-to-apples comparison in the table** — the pod never had a director,
      so its trigger and duty are near-identical in both states (0.68 → 0.77) and
      **0.99 → 0.09** is the fuse degrading to contact-only and nothing else.
      P3.6's promise ("a screamer degrades it to contact-only, gracefully"),
      measured — and it is the largest single effect the jam has on any weapon.
    - **THE BLASTER RESULT WENT THE OTHER WAY FROM MY PREDICTION, and I am
      recording the wrong guess because it is the more useful half.** I expected
      the manual cone to fire less and hit better — the flak pod's shape. It fires
      **67% MORE (81 → 135 rounds) for exactly the same 14 hits.** The two triggers ask different
      questions: the director demands a real ballistic intersection inside 1.2 m
      including drop, while `fire_cone_deg` asks only whether the gun line is
      within 6° — a 4 m circle at 40 m, with no drop term at all. The manual
      trigger is the LOOSER of the two against a static target. **So the jam costs
      the chip gun DISCIPLINE, not accuracy** — nearly free today, and it stops
      being free the day the blaster gets the heat economy P3.5 already drafts for
      it. That is also, unprompted, why P4.3 rates chip gun `+` against a screamer
      while rating missile `--`.
  - **THE VTX JAM (the user's second steer), and why it belongs on DamageConfig.**
    The jam rides the SAME video-breakup overlay as battle damage and the range
    wash, as a floor rather than an addition. D6 predicted this exact unification
    — "EW *and* battle damage both degrade FCS, one mechanism" — and reusing the
    effect makes it literal: being shot and being jammed look the same on screen
    because they are the same failure, and the pilot's answer to both is to fly it
    manually. Deliberately NOT scaled by `severity`: that dial is how much a HIT
    costs you, and muting EW for a forgiving damage model would delete a roster
    type's readability.
  - **THE AUDIO CUE IS THE JAM LEVEL, not a proxy for it.** A looping detuned
    carrier under a band of hiss (`SoundBank.make_jam_loop`), whose volume and
    pitch are driven by the jam level sampled AT THE PLAYER. 3D attenuation would
    have been free and was rejected: distance falloff and the jam falloff are two
    different curves, and a cue that disagrees with the mechanic teaches the wrong
    edge.
  - **`screamer_check.gd`, because this type is the hardest one yet to read from
    a results table.** The falx taught the lesson four times over ("this cell reads
    0%" is equally consistent with a tough enemy, a broken enemy, and one that has
    left the level); the screamer is worse, because `dmg-taken 0.0` is its CORRECT
    reading and a jam field that silently failed to emit would leave the harness
    board looking completely normal. Three phases, one per way it can quietly
    break: does it STAY (leash from home with no player), does its jam FADE (both
    ends asserted — total inside `jam_full_range`, partial at its own standoff,
    absent past `jam_range` — plus the shipped systems read directly: director
    window, flak fuse, lock progress), and does it HOLD ITS DISTANCE WITHOUT
    ABSCONDING. That last one is the type's own failure mode: an EW asset that
    simply runs is unkillable rather than difficult, and the harness cannot tell
    those apart. Measured: spawned at 8 m, settles at exactly 40.
  - **Its harness rows will look strange, and BALANCE.md now says why.** Layer 1
    prices it as an ordinary 30-hull body; Layer 3a reports `mode: none` and its
    survival line says out loud that the cell cannot price durability (v1.72's
    Aegis finding, second occurrence); every duel reads `dmg-taken 0.0`.
    Everything it does is in Layer 2. Its `evasion` cells read 0.92–1.00 — it
    station-keeps and slides, so a perfect shooter hits it nearly every time. **Its
    defence is not motion, and only the clear-vs-jammed aim PAIR describes it.**
  - **The duels report the jam they actually flew.** `jam: jammed` on a matchup row
    is an AUTHORED input like `count`, so every rep records the mean jam level it
    experienced and the report prints it beside the bands. A row keyed `jammed`
    that spent its ten seconds at 0.3 now says so instead of quietly predicting
    from the wrong column — the gradient reported rather than pretended away.
  - **One named model gap, stated rather than closed:** `splash` is measured clear
    only. A contact-fused shell bursts on the near face of a cloud instead of
    inside it, so real pack coverage under jam is below the committed 3.42 by an
    unmeasured amount. The single-target half of that loss IS captured (the 0.99 →
    0.15 above); the pack half is not, and it costs nothing until P4.3's
    aegis+screamer pair grows a gnat escort.
  - **Provisional, flagged for hands** (feel numbers a bench cannot judge, all
    live in the overlay): `jam_range` 55 and `jam_full_range` 20 (how early the
    feed starts breaking up, how deep you must press before the gun goes manual),
    and `jam_video_glitch` 0.55 (how loud the interference reads — set under a
    wrecked transmitter's hit spike of 0.85 and above its permanent floor of 0.45,
    so a jam reads as "the feed is going" without claiming to be worse than actual
    damage). The audio cue's loudness likewise.
  - **Regression:** full check suite PASS, now THIRTEEN checks. The screamer joins
    both stamp lists (`ENEMIES_FOR_STAMP`, `lethality_check.ENEMIES`) the day it
    lands, per the v1.27 rule, and `preferred_range` joined the delivery stamp
    with it — a pre-existing hole rather than a new input, since an orbiting type's
    standoff radius has always set the geometry every evasion cell is measured at.

- **2026-07-28 — v1.82. M6a step 6: EVASION BECOMES A FRAME TRAIT, and the pilot
  learns the iron trigger. `PILOT_VERSION` 5 → 6, bumped ONCE for both.** Two
  behaviour edits landed in one commit pair on purpose: a bump costs a full
  deliberate re-measure, and two bumps would have cost two of them while making
  neither attributable.
  - **STEP 1 — heavy frames do not jink (`FrameConfig.evasion_style`).** v1.81
    measured the case and this spends it. The field carries two styles: `jink`
    (the v5 tactical break-settle-fire-break) and `hold` (fly the line, spend the
    hull you were bought with). Kestrel `jink`, Atlas `hold`, both stated in the
    `.tres` so a roster's evasion identity is readable in the roster's own files.
    - **The pilot ASKS THE AIRFRAME** (`ReferencePilot.frame_jinks`), inside AUTO
      only. The forced modes deliberately ignore the field, because
      `atlas × raider [jink]` saturating is the evidence the field was built on —
      a datum that the design it produced can switch off stops being a datum.
    - **Verified narrow, before the bump** (filtered bench runs, minutes not an
      hour — and a filtered run is a LOOK that cannot write the artifact):

      | Atlas cell (same run, so comparable) | rounds taken | its own gun |
      |---|---|---|
      | `raider [auto]` — v6, holds the line | **3 / 38 = 0.08** | **9/49 = 0.18** |
      | `raider [jink]` — what AUTO used to fly | 0 / 38 (saturated) | 1/26 = **0.03** |
      | `turret [auto]` — v6, holds the line | 8 / 50 = 0.16 | **11/63 = 0.17** |
      | `turret [jink]` — what AUTO used to fly | 5 / 50 = 0.10 | 0/28 = **0.00** |

      **The Atlas got its gun back.** Against the raider it takes FEWER rounds
      while shooting six times better; against the turret it takes more (0.16 vs
      0.10) and shoots where it previously scored nothing at all in 28 tries. That
      is the trade the design asks a heavy frame to make — durability is what its
      190 hull and armor 3 were bought for, and a cell reading "untouchable and
      harmless at once" was never an airframe doing anything.
      *(v1.81's published v5 `[auto]` figures — 0.11 taken with the gun at 0.03 —
      came from a different run and are quoted here only as direction, per the
      compare-within-one-run rule.)*
      The Kestrel is unmoved: `raider [auto]` 4/38 = 0.11 at a 0.09 jink duty with
      its gun at 0.18, still the best of its three modes on both axes. *(The
      committed run reads 9/38 = 0.24, duty 0.19, gun 0.25 — a 2x swing in the
      absolute value, and the CONCLUSION holds unchanged: 0.24 beats steady's 0.26
      and jink's 0.29 while out-shooting both. This is the jinking-cell
      amplification of v1.80, and it is why the rule is compare-within-a-run.)*
    - **Both Atlas `[auto]` cells read identically to their `[steady]` twins in
      the filtered run** — which is the property working, since for a `hold` frame
      the two are the same flying. **CORRECTED by the full re-measure below:** in
      the committed run the turret pair still matches exactly (8/50 both, gun
      11/63 both) while the raider pair reads 4/38 against 3/38. So "identical" was
      the filtered run's luck, not a law: two cells at different positions in a
      run list inherit different float state from the physics server (v1.80's
      amplification finding), and one round of 38 is exactly that size of
      difference. **The claim that survives is the one the bench actually
      asserts** — on the jink duty, which must be 0.00 and is exact — not on the
      rates, which carry the same noise everything else here does. The duty check
      was documented since v1.78 and
      unenforced until now; a state that failed to take would have printed a
      plausible number and passed.
  - **STEP 2 — the pilot can pull its own trigger (P3.6's iron trigger).** The
    brain handed its trigger to the gun director unconditionally, so anything that
    turned the director off made it fire NOTHING. The rule it was missing:
    **use the director while there is a director, pull the trigger yourself when
    there is not** — `Weapon.director_active()`, one question with one answer
    instead of a judgement at each call site.
    - **`DIRECTOR_MIN_M` = 0.25 m is a deliberate STEP at the bottom of a slope.**
      A director whose solution window has been squeezed below a quarter of a
      metre is demanding an intersection tighter than the target's own hitbox: it
      is not assisting, it is silent. Without a defined edge a degraded director
      produces a pilot holding a trigger it will never pull — S7's "never smear a
      step into a slope", applied to where the slope ends.
    - **It moves nothing that exists today, and that was the prediction.** Every
      shipped cell either has a live director or flies a weapon that never had
      one. Confirmed: all six aim cells came back unchanged (0.17 / 1.00 / 0.99 /
      0.19 / 1.00 / 1.00). The edit is a PREREQUISITE — S.q10 said the Screamer's
      bump "is not incidental to the Screamer, it is the same fact as the
      Screamer", and this is that fact: a measuring pilot that cannot hand-fire
      cannot measure the type at all.
    - **The two trigger paths are not comparable as hit rates**, and every future
      jammed cell has to be read with that in mind. The director fires on any arc
      solution and takes many marginal shots (duty ~0.4, aim 0.17); the manual
      cone is 6° wide and fires far less often at far better odds — the flak pod's
      policy exactly. Read the DUTY beside the rate, or repeat the
      Blaster × Raider mistake in a third column.
  - **Regression:** full check suite PASS, twelve checks. The committed delivery
    factors are stale by construction (pilot v5 → v6) and the predicted column
    blanks until the deliberate re-measure, which is held until the Screamer lands
    so that one re-measure covers all of it.

- **2026-07-28 — v1.81. THE TACTICAL JINK WORKS, and it is the user's design.
  `PILOT_VERSION` 5.** Plus the Falx's fourth bug, found from the cockpit.
  - **The user's rule, implemented:** jink while under fire, **stop jinking
    while the gun line is on the target** (`jink_hold_cone_deg`, 14°), resume
    the moment it is not. Break, settle, fire, break. One constant now prices
    survival against output directly, which makes it the first knob to reach for
    when a frame reads wrong on the survivability cells.
  - **Measured three ways in one run** (Kestrel vs a perfect raider at 18 m —
    all three cells share a run, which is the only fair comparison):

    | mode | rounds taken | connect | its own gun |
    |---|---|---|---|
    | **`[auto]` tactical** | **7 / 38** | **0.18** | **24/130 = 0.18** |
    | `[steady]` never dodge | 8–10 / 38 | 0.21–0.26 | 0.16–0.20 |
    | `[jink]` never stop | 11 / 38 | 0.29 | 7/64 = 0.11 |

    **The tactical jink is best on BOTH axes at once** — fewest rounds taken and
    the most shots fired at the best accuracy — while dodging only 17% of the
    time. It beats never dodging *and* it beats always dodging. That is a real
    result and it was the user's idea, not the instrument's.
  - **The ORDERING is the finding, not the decimals.** `[auto]` and `[jink]`
    reproduced byte-identically across two runs of the same command while
    `[steady]` moved (10 → 8 rounds). So: **compare modes WITHIN one run, never
    across runs.** Every one of these cells sits somewhere on a knife edge, and
    which one shows it varies — v1.80's "steady is history-independent" was two
    histories agreeing by luck, and is hereby narrowed to "the ranking is
    stable, the absolute values are not."
  - **THE ATLAS SHOULD NOT JINK AT ALL, and that is now measured rather than
    suspected.** Its three cells: `[auto]` 0.11 taken with the gun at **0.03**,
    `[steady]` 0.08–0.11 taken with the gun at **0.11–0.17**, `[jink]` still
    saturated (0 of 38, gun ~0.03). **Dodging buys the Atlas nothing** — the
    same rounds land either way — **and costs it nearly all of its gun**, even
    at a 23% duty. The user's call stands on evidence: *"the atlas, and any
    heavy moving frame cannot use jink as an evading means. maybe it should not
    even try."* **Proposed and NOT yet built:** make evasion style a FRAME
    property, so dodging becomes part of the P3.3 roster's identity rather than
    one behaviour for everyone. Awaiting steering.
  - **A saturated DATUM no longer fails the run.** A factor cell that cannot be
    measured is a broken instrument and still stops the report; a deliberate
    extreme saturating is its ANSWER, and holding the board red for it forever
    only teaches everyone to ignore red (H8's rots-argument turned on
    ourselves). `tools/balance_report` is green again.
  - **FALX BUG FOUR, reported from the cockpit and invisible to every test:**
    *"the falx was flying away regardless of what i did... tough time even
    finding it in the horizon."* With no target it flew straight ahead forever —
    and "no target" includes every second before the player ARMS, so it was
    already leaving at 25 m/s as the scene loaded. Now it flies a patrol circuit
    around its spawn (a circle, not the raider's random wander: at 25 m/s a
    random walk is just a body disappearing in a straight line).
  - **`falx_check.gd` added**, because all four bugs were invisible to the suite
    — the harness could only ever say "this cell reads 0%", which is equally
    consistent with a tough enemy, a broken enemy, and an enemy that has left
    the level. Two phases: does it stay (leash from home with no player), and
    does it attack (rounds in the air against a parked armed player).
  - **Regression:** full suite PASS, now twelve checks.

- **2026-07-28 — v1.80. M6a step 5a: the FALX ships; v1.79's headline is
  RETRACTED; and the user steered the jink, the jam and the build order.**
  - **v1.79's Kestrel numbers do not survive a second look, and I am retracting
    them.** The delivery bench gained a watch FILTER (run one cell by name), and
    running the same pair under a shorter cell list produced a different answer:

    | cell | in the full run | in a 2-cell run |
    |---|---|---|
    | `kestrel × raider [jink]` | 0.29 (11/38), gun 0.11 | **0.13** (5/38), gun **0.18** |
    | `kestrel × raider [steady]` | 0.18 (7/38), gun 0.17 | **0.18** (7/38), gun **0.17** |

    The steady cell is bit-identical across both. The jink cell is not — and
    repeating each history reproduces its own answer exactly, so this is not
    randomness: **the jink cell's result depends on what ran before it in the
    same process.** A jinking drone sits in a violent, high-gain oscillation
    that amplifies whatever trivial float state the physics server carries
    between arenas; a steady one does not. **So "the jink makes the Kestrel ~60%
    easier to hit and costs it its gun" was one history's answer.** In the other
    the jink cell reads BETTER than steady (0.13 vs 0.18) and costs the gun
    nothing (0.18 vs 0.17). No direction can be claimed for the Kestrel.
  - **What survives, and it is the important half.** The **Atlas** result was
    re-run under a fresh history and held: `atlas × raider [jink]` took **0 of
    38** with its gun at **1 of 26**, against `[steady]` at 0.11 with a gun of
    0.17 — reproduced exactly. It survives *because* it is saturated: an
    aircraft that is completely out of control cannot be nudged by float noise.
    **The Atlas cannot fly this jink, and that is measured, not inferred.**
  - **The lesson, which outlives the jink:** a chaotic manoeuvre makes an
    unmeasurable cell. Layer 3b's forced states fixed the *bistability* (a
    behaviour gate feeding back into the measurement) but a second, independent
    problem was hiding underneath — **amplification**. A cell whose answer moves
    with its own position in the run list is not a factor, and the tell is
    cheap: run it in isolation and see whether it agrees with itself.
  - **THE USER'S STEERING (2026-07-28), recorded before it is built:**
    - **The jink should be TACTICAL, not constant.** Their design: the pilot
      jinks *while being fired on* and **stops jinking to take its shot** — the
      trigger and the dodge take turns instead of fighting each other. That is a
      better model than either forced state, and it names what the current
      implementation actually got wrong: the jink was unconditional, so it
      degraded the gun during the exact moments the gun mattered.
    - **Heavy frames may simply not jink.** The user: *"the atlas, and any heavy
      moving frame cannot use jink as an evading means. maybe it should not even
      try."* If adopted this is a FRAME PROPERTY, which makes evasion style part
      of the P3.3 roster's identity rather than one constant for everyone.
    - **They want to WATCH it before deciding** — hence the filter, which is why
      it landed this step rather than later.
    - **S.q8 ANSWERED: the jam FADES with distance**, not a hard bubble edge,
      with an audio cue that rises as you close on the screamer. Fall back to
      binary only if the gradient proves expensive. This **overrules my lean**
      (I argued binary, from S7's "never smear a step into a slope"); the user's
      reading is that a *sensor* warning is exactly where a gradient belongs,
      and the S7 rule is about not smearing a decision boundary, which this is
      not.
    - **The screamer should also jam the VTX** — video-feed interference reusing
      the existing damaged-feed effect. That unifies EW with battle damage on
      one mechanism, which is precisely what D6 already predicted ("EW *and*
      battle damage both degrade FCS — one mechanism").
    - **Build order CONFIRMED:** Falx complete first (including the human
      flying against it), *then* teach the pilot manual fire, *then* the
      Screamer.
  - **THE FALX SHIPS** (P4.2, roster type five): `default_enemy_falx.tres`,
    `scripts/combat/falx.gd`, `scenes/combat/falx.tscn`, a dev-room specimen, a
    bestiary block in all three scenes' overlays, three harness rows plus a
    frame row, three evasion cells, and entries in both stamp lists.
    - **The bestiary's second flight idiom.** Every flyer so far ORBITS; the
      falx flies BOOM AND ZOOM — run-in, break off, climb away, swing wide,
      repeat. The wide arc is **emergent, not scripted**: `speed` 25 against
      `accel` 11 means a body that physically cannot turn tightly, because
      `accel` is what `move_toward` spends to change direction. That is what
      makes P4.2's counterplay honest — "bait the pass, kill the recovery" beats
      it through GEOMETRY rather than through a memorised timer.
    - **TWO BUGS THE HARNESS CAUGHT IMMEDIATELY**, both invisible without it:
      1. **It refused to attack.** Committing to a pass required 56 m of
         separation, so a falx spawned at the harness's 40 m spent the entire
         10 s duel flying *away* to set up, and every cell read `dmg-taken 0.0`.
         Fixed with a separate, shorter `RUN_IN_MIN_RANGE` — it attacks from
         wherever it can and only rebuilds distance when it has none.
      2. **It broke off on frame one.** The overshoot test asked whether the
         player was behind the BODY, but a freshly spawned falx has identity
         rotation and zero velocity, and the harness places every enemy at
         identity — so at a spawn facing world −Z with the player at +Z it
         declared "already overshot" before it had moved. Both the overshoot
         test and the gun cone now read the **heading** (the velocity), which
         also matches the type's own design sentence: *it shoots where it is
         going*.
    - **Early duels (REPS=2, directional only, not quotable):** Flak × Falx
      **`++`** matching paper — the designed answer works, three shells at
      1.4 s — and Atlas × Falx **`--`** matching P4.4's heavy column at −0.47
      against the Kestrel. **That second cell is the first time the frame axis
      has read NEGATIVE for the Atlas**, which matters: a roster in which the
      heavy frame has no bad day would make P4.4's table decoration.
    - **A delivery number worth keeping:** `evasion: missile x falx` connects
      **1.00 at a duty of 0.13** — the missile hits every time it is fired and
      almost never gets to fire, because a falx is inside lock geometry for about
      a second per pass. Layer 2 measures whether a shot CONNECTS, never whether
      you got to take it, and this is the cleanest example of that distinction in
      the roster.
    - **Layer 1 verified** with the falx included (planted shots vs the shipped
      `Health`). Note `kestrel <- falx` reads 12 hits / **2.8 s**, faster than a
      raider's 8.0 s — and that number OVERSTATES the threat, because Layer 3a
      assumes sustained fire while the falx only shoots during passes. Its
      `fire_rate` 4.0 is a burst cadence, not an uptime.
  - **The delivery bench gained a WATCH FILTER.** `-- <substring>` runs only the
    matching cells, so looking at a cell costs a minute instead of a quarter of
    an hour — which is the difference between the founding tenet ("some things
    are only visible to eyes") being policy and being decoration. **A filtered
    run never writes the artifact**: a partial measurement would silently delete
    every factor it did not run, and the file would look complete afterwards.
  - **Regression:** full check suite PASS (combat, wave, missile, run, hover,
    repair, motor_damage, menu, manifest, sortie_compose, lethality). The falx
    joins both stamp lists, so the committed factors are stale by construction
    and the predicted column blanks until a deliberate re-measure — deferred on
    purpose until the jink decision lands, since that decision changes the pilot.

- **2026-07-28 — v1.79. THE JINK IS A NET LOSS, and v1.77's two findings are
  narrower than they read.** *(Kestrel half RETRACTED by v1.80 — the jink cell
  turned out to amplify float noise into a 2× swing. The Atlas half stands.)* The measurement that Layer 3b was built to make
  possible, made — and it points at the pilot rather than the roster.
  - **Forced-state cells, Kestrel, perfect-aim threat at 18 m:**

    | pair | steady | jink | gun (steady → jink) |
    |---|---|---|---|
    | kestrel × raider | 0.18 | **0.29** | 0.17 (17/99) → 0.11 (7/64) |
    | kestrel × turret | 0.22 | **0.36** | 0.17 (17/99) → 0.11 (7/64) |

    **Jinking makes the Kestrel ~60% EASIER to hit and cuts its own hits by
    ~2.4×** (accuracy 0.17 → 0.11 *and* trigger rate 99 → 64 shots). Strictly
    worse on both axes, consistently across two threat types.
  - **The rig proves the jink mode is the only variable**: aim-under-fire is
    byte-identical across both threats within each mode (17/99 steady, 7/64
    jink), because the pilot's gun depends only on its own flying and the
    immortal player cannot be perturbed.
  - **The likely mechanism, stated as a hypothesis:** the jink REPLACES chaotic
    gun-platform flying with a periodic sinusoid, and a 1.2 s sinusoid is easier
    to lead over a 0.4 s flight time than an erratic pursuit is. Evasion that is
    regular is not evasion.
  - **THE ATLAS CANNOT FLY IT AT ALL.** `atlas × raider [jink]` took **0 of 38**
    rounds while its gun scored **0 of 28** — untouchable and harmless at once,
    a cell with no measurement in it. `atlas × turret [jink]` is the same story
    at 0.10 with a dead gun. Flying STEADY the Atlas is fine: 0.11 / 0.16, gun
    0.17, identical to the Kestrel's. **`jink_bank` is tuned to the Kestrel and
    is too much aircraft for a 1.9× mass on softer rates.**
  - **This does NOT overturn v1.77 — it bounds it.** Those duels fought a REAL
    raider carrying `aim_jitter_deg` 3.0 and its own tracking loop, at whatever
    range the fight produced; this bench fights a PERFECT solution at a fixed
    18 m. Both can be true, and together they bracket the answer: **the jink pays
    against a threat that aims badly and costs against one that aims well.**
    Which end the game sits at is decided by the threat's own marksmanship —
    the un-measured mirror of `aim_quality`, whose trigger (P4.q2 veterancy) just
    became a lot more interesting.
  - **The board is RED and deliberately so.** `tools/balance_report` now stops
    at the delivery bench, because `atlas × raider [jink]` produces no
    measurement and 0.00 must never reach the factor table — it composes into
    "this frame is invulnerable to this threat, forever", which the smoke harness
    printed verbatim before the guard landed. **Open for steering: retune
    `jink_bank` per frame, gate the jink on something better, or withdraw it and
    return the pilot to v3 behaviour.** Any of the three is a `PILOT_VERSION`
    event, so it should be decided once and measured once.

- **2026-07-28 — v1.78. M6a step 4: LAYER 3b + the concurrency axis — the model
  becomes symmetric, and the instrument caught three defects in itself before it
  would produce a number.**
  - **Layer 3b lands as a measured factor.** `player_evasion`, keyed THREAT ×
    FRAME (the mirror of `evasion`'s WEAPON × TARGET — the key order says which
    side owns which half), measured by new `survive` cells in the delivery
    bench: a BODILESS perfect-aim threat emitting one enemy type's real rounds
    while the pilot flies the aim bench's own task. Bodiless is the isolation —
    the pilot cannot acquire, orbit or shoot what has no collider. Frame-keyed,
    unlike its enemy-side twin, because nothing freezes the player.
  - **The contact mode gets its delivery term too** (`contact_rate`, stings per
    second). Layer 3a's `incoming()` refuses to invent an arrival rate from a
    config and names a bench for it; this is that bench, discharging a promise
    the code itself made.
  - **`BalancePrediction.survive` composes the two**, and assumption 3 ("nobody
    shoots back") is now true only of the BAND: a survival time is printed
    beside every cell whose enemy can shoot, never folded in, because a ttk band
    and a survival band are two rulers. **The frame axis is legible in the
    predicted column for the first time** — `kestrel 4.5s, atlas 46.5s under 3x
    turret`.
  - **The concurrency axis (S5)** is a `count: N` key on a matchup row, plus
    three cells (`Blaster x Turrets`, `Atlas x Turrets`, `Atlas x Raiders`). The
    frame-datum assert was extended: a datum must now match its cell's
    CONCURRENCY as well as its weapon and type, or the axis added to isolate
    exposure would be reported in the frame column.
  - **The stamp gotcha, discharged — with a twist worth recording.** Four fields
    joined: enemy `damage`/`fire_rate`/`muzzle_speed`/`sight_range`, and
    `FrameConfig.hull`/`armor`, **which the stamp had never read at all**. Under
    Layer 3b's first design all of them were load-bearing. Forcing the jink state
    (below) then removed that coupling, so `damage`, `hull` and `armor` are inert
    again and stay listed as a **deliberate conservatism**, not a necessity — a
    false positive costs one re-measure, a false negative costs a quoted stale
    number.
  - **THREE DEFECTS THE INSTRUMENT FOUND IN ITSELF**, each caught before a number
    was committed, and each generalizing:
    1. **The arena was picking the range.** A threat parked at a fixed arena
       point measured 0.03–0.08, composing into a Kestrel that survives a raider
       for four minutes against duels spending a fifth of its hull in ten. Range
       dominates this factor; the threat now station-keeps at a stated 18 m.
    2. **The pilot could hide behind its own practice target.**
       `Projectile._resolve_hit` fizzles a round on ANY collider, and the blaster
       path closes to nearly touching its target — so incoming rounds were being
       absorbed and scored as evasion the airframe never earned. Fixed with the
       shot's `exclude` list.
    3. **The factor fed back into itself.** The jink is hit-gated, so what is
       measured (do rounds connect) decides the behaviour (am I jinking). That
       loop is BISTABLE: `kestrel × raider` settled at 25 hits / 0.87 duty in one
       run and 4 hits / 0.23 duty in the next, a 6× swing, while `kestrel ×
       turret` reproduced to the integer. `ReferencePilot.Jink`
       (AUTO/ALWAYS/NEVER) forces it — **AUTO is the default and the shipped
       brain, so this is NOT a `PILOT_VERSION` event** — and every pair is now
       measured twice, `[jink]` and `[steady]`, whose difference is what the jink
       actually buys. Forcing it also retired a "counterintuitive" turret-vs-
       raider inversion I had flagged: it was the bistability, not the bestiary.
  - **A zero-hit cell is refused, not published.** 0.00 is the most dangerous
    number this table can carry, and the smoke harness demonstrated it verbatim
    before the guard landed: `atlas never (nothing connects: this threat cannot
    reach this frame)`. Such a cell now fails the run AND is omitted from the
    artifact, because a FAIL nobody reads still leaves a poisoned file behind.
  - **`survive()` is verified by properties that can fail** (S12's discipline
    applied to arithmetic): identity against Layer 1 at a perfect connect,
    monotone in concurrency, monotone in connect rate. Linearity in `count` is
    deliberately NOT asserted — it is a claim for the concurrency bench to
    falsify, and asserting a model against itself launders an assumption.
  - **Every pre-existing delivery factor reproduced byte-identically** across
    four bench runs under the new stamp (aim 0.17/1.00/0.99/0.19/1.00/1.00,
    every evasion cell, splash 3.42 and 1.90). The one wobble was
    `aim: atlas/flak` reading 0.90 in a single run against 1.00 in the others —
    the flak instability BALANCE.md already documents, not a change.
  - **Regression:** the full check suite (combat, wave, missile, run, hover,
    repair, motor_damage, menu, manifest, sortie_compose, lethality) PASS.
  - **S14 added, awaiting steering:** the Screamer's FCS question (S.q8–S.q10),
    surfaced by this work — it is the first roster member whose entire effect is
    a multiplier on the player's delivery factors, and it forces a jam-state axis
    on `aim_quality` plus, probably, `PILOT_VERSION` 5.

- **2026-07-27 — v1.77. The v1.76 noise caveat CORRECTED, and the two jink
  findings confirmed real.** A second v4 run at identical settings was made
  specifically to measure the floor before believing any delta.
  - **The harness is far more reproducible than its own header implies.** Two
    full v4 runs: **9 of 10 compared cells byte-identical** (Blaster × Gnats
    −0.33/1.7/51%, Missile × Gnats −0.45/1.0/56%, Flak × Gnats +1.00, Flak ×
    Raiders +0.88/2.8/7%, Atlas × Turret −0.10, Atlas × Aegis −1.00 — all
    reproduced exactly). The single mover was `Atlas × Gnats` at **0.04**.
  - **MY v1.76 CAVEAT WAS WRONG, and the correction matters more than the
    caveat did.** I claimed ~16% run-to-run variance from `Atlas × Turret`
    reading 22.2 damage in one v3 run and 18.7 in another. Those two runs did
    NOT have identical settings — the second was the v1.72 clock probe with
    `MAX_SECONDS` doubled. **A changed rig constant is not noise; it is a
    different measurement**, and I attributed to the solver what the ruler
    caused. Recorded in BALANCE.md as a standing rule: compare runs only at
    identical settings.
  - **So the readable floor is ~0.04, and two v3 → v4 deltas clear it:**
    - **Blaster × Gnats: kills 2.2 → 1.7, exchange −0.24 → −0.33** (Δ0.09).
      The jink **costs** you against the contact swarm.
    - **Flak × Raiders: kills 2.3 → 2.8, exchange +0.71 → +0.88** (Δ0.17).
      The jink **pays** against ranged shooters.
    - Missile × Gnats (Δ0.03), Missile × Raiders (Δ0.03) and Blaster × Raiders
      (Δ0.02) sit inside the floor and are **not** readable as changes.
  - **The finding, now standing on measurement:** evasion is not free, and its
    price depends on what is shooting you. Jinking breaks a raider's firing
    solution, so it pays against ranged threats; it does not break a gnat
    cloud's approach, so against a contact swarm it only degrades your own gun —
    fewer kills, more stings. That is a real design fact about the bestiary, it
    was invisible before Layer 3, and it is the first thing the symmetric half
    of the model has told us that the old instrument could not.

- **2026-08-01 — v2.01. AN OUTSIDE AUDIT, VERIFIED RATHER THAN ACCEPTED — and
  the checks were the weakest part of the project.** A second machine was given
  the code read-only and asked four questions: are any of the 18 checks *wrong*,
  where have the docs drifted, fresh eyes on the Iteration 12 bridge, and the
  open turret-reproducibility question. Every finding was re-derived here against
  the code before anything was changed; the ones below are the ones that survived
  that, and two of them were **latent campaign-destroyers**.
  - **THE STANDARD THE AUDIT APPLIED IS THE ONE THIS PROJECT WROTE AND DID NOT
    KEEP**: *"would this check still pass if the feature it tests were deleted?"*
    Three checks failed it, all written in the last two weeks, all mine.
    `war_loop_check` mocked **both** sides of the joint it exists to guard —
    `apply_sortie` reads every field through `.get()` with a default, so renaming
    a field in `SortieRunner.result()` produced no error and a war that silently
    stopped noticing the player. `sortie_check`'s "trigger rule, tested directly"
    never called `_fire_trigger` at all; it appended to two arrays by hand and
    asserted that a two-element array had two elements. `ammo_check`'s dry-fire
    refusal compared `shots_fired` to itself with **no physics step in between**,
    so failure mode #1 of the four that file names was unreachable. Each is now
    **mutation-tested**: rename `dent`, and `war_loop_check` fails; delete the
    flak pod's `has_ammo()` guard, and `ammo_check` fails. Both were verified to
    fail, then reverted.
  - **THE DOGFIGHT PAID YOU TO FLY AWAY FROM THE FIGHT.** `_fire_trigger` marked
    a reserve *spent* at fire time and then started a timer, while
    `reserves_held()` counted unspent triggers — so on the second wave-clear the
    field was empty, every trigger read as spent, and the sortie announced
    `AIRSPACE CLEAR` in the same frame it announced `contact - reserves inbound`,
    with a whole wave still 3.5 s out. Worse than the contradiction: `result()`
    computes `complete` at finish time, so leaving promptly scored **complete**
    and staying to fight the wave scored **partial** — the capture gate refusing
    the node *because* you killed everything. FIRED AND ARRIVED ARE DIFFERENT
    THINGS; `_trigger_released` now gates the egress and `_trigger_spent` only
    prevents double-firing.
  - **`SAVE_VERSION` would have shredded every campaign in existence.**
    `load_war` returns `{}` for a version mismatch, a truncated file, a parse
    failure *and* for no file at all — and `load_or_new` treated all four as "no
    save" and generated a fresh theater, which the next finished sortie wrote
    straight over the top of. The constant exists precisely for the event that
    would have triggered it. An unreadable save is now **moved aside**, never
    overwritten, and if it cannot even be renamed the sortie refuses to start.
    Separately, `war_loop_check` wrote to the real `user://war.save`, so **running
    the test suite deleted an in-progress war**; it now borrows and restores the
    file, as `run_check` has always done.
  - **THE TURRET QUESTION IS NARROWED, NOT CLOSED, AND THE FREE TEST PAID.** The
    audit's best move was to re-read the two archived run logs instead of running
    anything. The threat's shot counts are **bit-identical** across both runs (50
    turret, 38 raider), which kills every cadence-side explanation including the
    0.5 s float-boundary one. What actually moves is **the pilot's own gun shot
    count** — 112 bolts one run and 64 the next in `kestrel x turret [jink]` — and
    no hit-test threshold can change how many shots the pilot took. The drone flew
    a *different flight*, so this was never scoring noise and longer cells would
    never have fixed it. **v1.95b's "every raider cell reproduced exactly" was
    wrong**: `atlas x raider [steady]` moved 0.11 → 0.08. The live candidate is
    `ReferencePilot.jink_hold_cone_deg` — a 14° gate that stops the jink so the
    pilot can shoot, which **forcing `jink_mode` does not bypass**, so an epsilon
    of attitude flips jink-vs-shoot on a tick and diverges everything after it.
    Unproven, and recorded as a mechanism rather than a measurement.
  - **What the audit got wrong, and why it is recorded**: it eliminated pilot
    feedback on the grounds that `[steady]` has no feedback path, which is true of
    *behavioural* feedback and says nothing about the 14° gate above; and it
    proposed the projectile hit radius as the threshold when the shot-count
    evidence rules that out. A read-only reviewer with no ability to run anything
    produced 26 confirmed findings anyway. **The lesson is not that the reviewer
    was right — it is that "would this pass if the feature were deleted?" is
    cheap, mechanical, and was not being asked.**

- **2026-08-01 — v2.02. THE HOLD: a capture becomes something you DO, not
  something you survive (W.q8 raised, deliberately unresolved).** Three small
  decisions and one large question, all from the user reading v2.01's report.
  - **W.q8 raised by the user, and it is the good kind of question — it dissolves
    a problem instead of answering it.** I had offered "price a death that
    completed the objective as a degrade rather than a capture" as a fairness
    patch. The user's objection was that the pilot **already paid**, and their
    counter-proposal was a **hold phase**: clearing the objective starts a clock
    during which friendly forces move in to take control, while the enemy pushes
    to reclaim the ground. Their reasoning, verbatim in shape: *in war it is
    predictable that the enemy will try to move in quickly to reclaim the space,
    while ally forces move in to take control.* That converts the capture gate
    from a survival check into a **completed task**, which is why it stops being a
    double-punish without needing a fairness rule at all. Full options and risks
    at W.q8; **nothing is built against it.**
  - **Death returns to the war room, and we are WAITING for the war room rather
    than plastering over it (user).** P5.4 already decided this — *"you redeploy
    fresh from Home Airbase"* — and P1.q4 says the same for an abort. `sortie.gd`
    still runs `main.gd`'s arcade respawn, so a dead pilot revives into a sortie
    that has already resolved and saved, and can fly and kill indefinitely with
    nothing recorded. I offered three interim fixes and the user declined all of
    them: *"lets not use plasters over something that eventually will be built. i
    have patience."* Recorded as a KNOWN GAP with a decided destination, which is
    a better state than a temporary behaviour someone later mistakes for a design.
  - **The wave director's escort guard is DELETED, not tested.** `compose()` fills
    every wave's last slots with raiders, so the repair line below it could never
    execute once — and the comment above it said so. Deleting beat testing here
    because the backbone IS the enforcement and a second mechanism would be two
    things to keep in sync; the comment left behind says what to do if the
    backbone ever stops being unconditional. `composition_check`'s `has_threat`
    assertion stays exactly where it is: it tests the OUTPUT of the function, so
    it starts failing the moment the backbone goes. **Contrast with
    `WarManifest._enforce_escort_rule`, which was KEPT and given a direct test in
    v1.96** — that one can genuinely fire, because a doctrine mix is data.
  - **A reporting failure worth recording, because it cost the user a flight.** I
    told the user "dogfights are now longer" and they tested it on **node 8, which
    is a strike** — the one archetype the fix cannot touch, since only a dogfight
    carries two `wave_cleared` reserves. They correctly reported feeling no
    difference. The fix was right and the instruction was useless. **Naming an
    archetype is not naming a node**: seed 4242's dogfights are 0, 1, 4, 6, 7, 9,
    12, 15, 23, 24 and 28, and a repro command has to name one of them and pass
    `--no-persist` or it flies whatever the saved war has become.

- **2026-08-01 — v2.03. Iteration 13 opened: C, the war room (P1.8), proposed
  and awaiting steering.** The user named it as the next job after reading the
  v2.02 inventory. Sections C1–C10, open questions C.q1–C.q7, status PROPOSED.
  - **The inventory was counted rather than remembered, and two rows carry the
    whole cost**: the 1-tick forecast (P1.6) has no data behind it at all, and the
    tick-as-animated-map-movement is genuinely new work. Every other line in P1.8
    is either already computed and printed to a console nobody sees, or done.
  - **The briefing half of P2.1 has been correct and invisible since v1.71.**
    `compose_briefing` and `through_fog` are called by three tests and a bench and
    by nothing a human has ever looked at, so P1.3's designed surprise — stale
    intel diverging from truth — has never once been delivered to a player.
  - **The war-side API change is two underscores.** `_supplied_set` and
    `_strike_range` are private only because nothing outside the sim had needed
    them, and both are exactly what a map draws; `war_trace` already reaches
    through one. **And the room adds ZERO fields to the save** — everything it
    shows is projection, so `SAVE_VERSION` does not move and no campaign dies.
    That is a constraint on the cut, not a happy accident: named pilots (C.q7)
    are out of this iteration precisely because they would need a field.
  - **The forecast has a cheap honest answer and a trap next to it.** Weather is
    re-rolled from the war's shared RNG, so predicting it moves the war — but a
    tick run on `state.duplicate(true)` costs one tick of arithmetic and touches
    nothing. The trap is that the same dry run also knows the enemy's next move,
    so the room must read **weather only** off it or it hands the player the
    perfect oracle that deletes the fog.
  - **The tick animation must NOT be built by teaching `WarSim` to narrate.**
    Diffing two snapshots gets the same event list, keeps the one module whose
    purity is load-bearing for determinism and the save exactly as pure as it is,
    and makes an animation that cannot disagree with the state because it is
    derived from it.
  - **The loop is proposed to move into the room** (C.q2), because P1.8's own
    sequence puts the tick where the map is. Three things fall out of it: P5.4's
    death path finally closes, P1.q4's *exit without save* becomes "hand back
    nothing", and a quit mid-sortie loses the sortie — which is the decision, not
    a bug. `scenes/sortie.tscn` keeps its standalone leg or the repro command in
    TESTING.md rots.
  - **W.q8 is deliberately NOT answered here.** It was parked pending a map that
    can show allies moving in; the honest move is to re-ask it once the map
    exists rather than fold it into the proposal for the map.

- **2026-08-01 — v2.04. C steered, and phase 1 flies: THE THEATER HAS A FACE.**
  Four questions answered by the user (C.q1 the 3D hex table, C.q2 the room owns
  the loop, C.q3 the unflyable nodes drawn and refused, C.q4 weather gets its own
  dice), three taken to their leans, and C9's first phase built: `WarView`,
  `HexTable`, `scenes/war_room.tscn` and `war_room_check`. 19 checks, all green.
  - **The map adds nothing to the war and nothing to the save.** Two functions
    changed in `war/` and both were renames: `_supplied_set` → `supplied_set`,
    `_strike_range` → `strike_range`. The map draws the tick engine's own supply
    and the tick engine's own reach, because a second implementation of either
    would eventually promise ground the campaign does not have.
  - **A CHECK THAT COULD NOT FAIL, CAUGHT BY ITS OWN MUTATION TEST.** The supply
    assertion was first written as three nodes in a row — player, enemy, player —
    asserting that severing the middle leaves no supply edges. Deleting the
    supply test from `WarView` entirely did **not** break it: cutting the middle
    of three also removes every same-owner adjacency, so the zero it asserted was
    produced by the geometry rather than by the feature. Four nodes fixes it
    (home · enemy · player · player): the last two are neighbours AND cut off, so
    the edge between them must be absent for a reason only supply can supply.
    Verified failing under mutation, then reverted. **This is v2.01's standard
    catching a check written the same week the standard was written down** — and
    it is the second time the cheap mechanical question has paid.
  - **LOOKING AT IT CHANGED THE DESIGN, exactly as standing rule 6 promises.**
    The first build was numerically perfect and visually inverted: hex faces are
    large, the game's bloom threshold is 1.0, and at emission 1.8 every reachable
    node bloomed into a flat white shape with an unreadable glyph — while the
    *dimmed* out-of-range hexes, the ones meant to recede, came out as the most
    legible things on the table. Fixed by a rule worth keeping: **the surfaces do
    not glow, the marks on them do.** Colour lives in albedo; the glow budget
    goes to the glyphs, the front line, the spires and the selection ring.
  - **Two more things only a screenshot could have said.** Fifty-eight supply
    edges were drawn and not one was visible — they sat in a 0.35 m trench
    between prisms, invisible at a 62° pitch; they now share the shared-edge slot
    with the front line, which works because the two are mutually exclusive by
    construction. And the camera framed on `max(x, z)` against the VERTICAL fov,
    wasting half a 16:9 screen — a ground extent running away from the camera
    lands on screen-vertical scaled by `sin(pitch)`, and the across-screen extent
    gets the wider horizontal angle for free.
  - **The card withholds the garrison on purpose.** It would have been two lines
    to print the true number and it is exactly the number P1.3 says the player
    does not get. Phase 2 shows it fogged, or it does not show it. A placeholder
    that lies is worse than a placeholder that is quiet.

- **2026-08-01 — v2.05. Phase 2: THE FOG REACHES A HUMAN AT LAST, and weather
  gets its own dice.** C9's second phase, built on the user's "continue with your
  lean" — the inspection card off `compose_briefing`, all three fog tiers, and
  C.q4's forecast. 19 checks green, `war_room_check` now 38 assertions, and the
  soak re-run because the weather change moves the war's RNG sequence.
  - **P2.1's briefing half has finally been looked at.** `compose_briefing` and
    `through_fog` were written in v1.71, verified by three tests and a bench, and
    called by nothing a player could see. The card is the caller. Detail degrades
    exact → families → the abstract strength the war-sim itself keeps, and a
    fresh theater's enemy ground reads NONE - never scouted, so a new campaign
    starts at the bottom tier everywhere and the fog lifts only where you have
    flown.
  - **THE CARD IS CHECKED AS TEXT, because its only real bug is invisible.** A
    card that leaks truth through the fog still looks perfect on screen — it just
    quietly deletes the surprise the entire intel system exists to produce. So
    `card_lines` returns a `PackedStringArray` and the load-bearing assertion is
    a NEGATIVE one: at `intel_age` 99, no name from `WarManifest.ROSTER` may
    appear anywhere in the card. Verified by mutation — swap `compose_briefing`
    for `compose` and four assertions fail.
  - **The forecast is checked against the future actually happening.** Forecast
    every node, run a real tick, compare; plus a guard that the sweep contains
    real changes, because "tomorrow is the same as today" would satisfy the
    comparison and be useless. Mutation: forecast the current tick instead of the
    next and both fail. A third assertion re-states the manifest's rule for
    weather — forecasting a hundred times leaves `var_to_str(state)` identical,
    so reading the map cannot move the war.
  - **What the weather change cost, measured rather than assumed.** `war_soak`
    re-run: determinism OK, both round-trips OK, and **skill 0.9 still reads a
    median of 127 sorties — bit-identical to the number H7's debt is stated in.**
    Skill 0.3 is still zero wins; 0.6 moved from 0 wins to 1 of 40, which at that
    sample size is noise and not a change. The difficulty picture is undisturbed.
  - **A UX bug only the screenshot could show.** Selection was on mouse MOTION,
    so the ring chased the cursor: moving the mouse toward the card changed the
    node the card was describing, and any jiggle overrode an arrow-key pick. The
    screenshot rig caught it by accident — the window opened under the cursor and
    photographed node 21 selected instead of the node the code had chosen. Now a
    click selects, which phase 3 needs anyway, since it hangs a launch off
    exactly this selection.
  - **Pads are shown even under fog, and that is a decision.** The count is
    derived from the node's true garrison, so a pilot can infer "zero pads means
    heavily defended". That is an inference from your own logistics rather than a
    disclosure of their order of battle, and it is left in deliberately.

- **2026-08-01 — v2.07. Phase 3: THE LOOP COMES HOME, and the death path closes
  with it.** C9's third phase. The campaign is now playable end to end with no
  command line: the menu tower has a WAR ROOM floor, ENTER on a node flies it,
  and the room prices the result in, ticks, debriefs and saves. 19 checks green,
  `war_room_check` at 58 assertions.
  - **P5.4's death path is CLOSED, and waiting for the room was the right call.**
    v2.02 recorded it as a known gap with a decided destination after the user
    declined three interim fixes — *"lets not use plasters over something that
    eventually will be built. i have patience."* The wait cost nothing: the real
    fix is the DELETION of `sortie.gd`'s arcade respawn, which is shorter than
    any of the three patches offered. Death ends the sortie, the pilot leaves the
    roster, everything destroyed still dents (P2.q4), and you redeploy from a
    Home Airbase that now exists.
  - **P1.q4's *exit without save* arrives for free, by nothing happening.**
    Quitting or flying out of contact hands back no result, so the war reverts to
    its last saved state because it was never moved. The save is written only
    after a sortie resolves, which makes the decided behaviour the DEFAULT rather
    than a feature someone has to implement.
  - **A check that reached for the player's real campaign.** The scene-level
    assertion — the only one that proves the room and the sortie were ever
    introduced — first asserted straight after `add_child`, on the assumption
    that `_ready` runs synchronously from a `-s` script's `_init`. It does not.
    The assertions ran early against an unbuilt room, AND the teardown cleared
    `WarLaunch` before `_ready` read it, so the room fell back to `persist =
    true` and opened the real `user://war.save`. Restructured to `menu_check`'s
    wait-for-ready pattern. **A test that quietly reaches for the player's save
    is a bug whatever it concludes**, and this is the second time this project
    has caught one doing it (`war_loop_check` wrote to the real file, v2.01).
  - **An assertion that measured the war's whole turn and called it your
    sortie.** "A survived sortie dents the node" compared the node's garrison
    after `resolve` to its garrison before — but `resolve` ticks after it
    applies, and a tick runs production and reinforcement, so a node can finish
    the turn STRONGER than it started and still have been hit hard. It failed on
    its first run, which is the only reason it was noticed. The dent is now read
    off the summary, which records both sides of the moment it happened.
  - **`menu_check`'s floor count was a tripwire, not a check.** It asserted a
    literal 6 and fired the day a legitimate seventh menu entry was added. Now
    counted against `ROOT_FLOORS.size()`, which still catches the failure that
    matters — the tower BUILDING fewer floors than it was given — without firing
    on the data changing length.
  - **The fog lifting is visible, and it is the best thing on screen.** Fly a
    node and its card goes from `STRENGTH ONLY - estimated 19.6` to `INTEL: EXACT
    - 7x raider 3x gnat 3x falx`, because `apply_sortie` zeroes `intel_age` for
    ground you have looked at with your own eyes. Nobody designed that moment in
    this iteration; it fell out of P1.3 and W7 meeting a screen.

- **2026-08-01 — v2.08. THE MAP IS A BEEHIVE AT LAST — four looks-level faults,
  one of them a real geometry bug, all found by the user flying it.** Feedback
  verbatim: *"the hexagons does not align how i expected them to, there's gaps
  between them and they dont align like a beehive. also there are some wierd
  lines between them. there's also too much neon blinding light, and the texts
  over each hexagon are not all aligned to the same direction."* Every one was
  correct and none were taste.
  - **THE HEXES WERE ROTATED 30 DEGREES INTO FLAT-TOP, so no two could ever share
    an edge.** The cell mesh is a 6-segment `CylinderMesh` and the code rotated it
    by 30 degrees "to make it pointy-top". Probing the mesh settles it: Godot puts
    corners at 90, 30, -30, -90, -150 and 150 degrees from +X — **already**
    pointy-top, and exactly what `WarView`'s projection tiles. The rotation was
    turning every correct cell wrong. Deleted. This is the difference between
    checking a graphics API and reasoning about it, on a bug that no headless
    assertion in the file could see: the projection was right, the adjacency was
    right, and the *mesh* was turned.
  - **`HEX_FILL` 0.82 → 0.99.** The gaps were deliberate, on the theory that
    hexes need air between them to read as separate places. They do not; the
    height difference already does that, and P1.8 asked for a beehive because a
    beehive is what makes hex adjacency legible. Held under 1.0 only to keep two
    neighbours' shared faces from being coplanar and z-fighting.
  - **The "weird lines" were the supply strips**, floating at the taller
    neighbour's height alongside the front-line walls, so both marks lived at the
    same altitude and read as loose dashes. Now a front line is a WALL on top of
    the taller cell and a supply link is a SEAM tucked into the step at the
    shorter one — different heights for different meanings, which is legible
    without a legend.
  - **The neon came down at the SOURCE, not in the look pass.** `LookController`
    re-applies the human-tuned `default_look_config.tres` every frame, so the war
    room cannot turn the game's bloom down to suit itself and must not try. It
    turned itself down instead: labels now sit just UNDER the 1.0 bloom threshold
    so they read as crisp text rather than as light, and only the front line and
    the selection ring exceed it at all.
  - **The glyphs fanned out because each was aimed at the camera POINT.** Thirty
    labels each turning to face the viewer reads as a crowd looking at you; one
    shared orientation along the view direction reads as a printed map. One basis,
    computed once.
  - **A fifth fault the user did not mention and a screenshot did: the labels
    were casting shadows.** Solid emissive cubes floating 0.7 m over a lit surface
    printed a legible second copy of every label onto the hex beneath it. The
    hypothesis was tested rather than argued — `GlowText3D` gained an opt-out,
    default ON so the menu tower is untouched — and the ghosts vanished.

- **2026-08-01 — v2.09. Phase 4: THE WAR TAKES ITS TURN ON SCREEN.** C9's fourth
  phase, and the last genuinely new engineering P1.8 asked for. 19 checks green,
  `war_room_check` at 66 assertions.
  - **The sim was NOT taught to narrate, and that was the whole design decision
    (C8).** The obvious implementation has `WarSim.tick` emit an event list as it
    works, which would put presentation concerns inside the one module whose
    purity is load-bearing for determinism, the portable save and the soak.
    Diffing two snapshots costs nothing and is strictly better: `war/` stays
    pure, the differ is testable without a viewport, and the animation **cannot
    disagree with the state, because it is derived from it**.
  - **The sequence is P1.8's, exactly.** The map keeps showing the board you left
    while the debrief is up; dismissing it is what moves the front. Ground rises
    and falls, ownership cross-fades with a flash that peaks mid-move, and the
    borders redraw LAST — so the front line moving is the punctuation rather than
    a detail lost in the middle.
  - **Two things had to be un-pinned from heights that were changing**, both
    found by photographing a frame mid-animation rather than by reasoning about
    it. A glyph left at its build height hangs in the air over a node that shrank
    away underneath it, so labels now ride their own prism. And the front-line
    walls and supply seams are pinned to their neighbours' heights, so they come
    down for the duration and the rebuild puts them back — which is the reading
    the sequence wanted anyway.
  - **The map is inert while the tick plays.** Selecting a node halfway through
    would inspect a war that is halfway to existing.
  - **The diff's assertions are a matched pair**, because either alone is
    passable by a broken implementation: "names nothing when nothing changed" is
    satisfied by a function that always returns empty, and "names a planted
    change" is satisfied by one that reports everything. Both, plus a real
    five-tick war whose every event is verified against the two states, plus
    order stability — because F4's determinism should reach the screen too, and
    the same tick ought to play the same way twice.

- **2026-08-01 — v2.10. Phase 5, and P1.8 IS BUILT.** The roster and the hangar,
  plus the pacing the user asked for after flying phase 4. Five phases, 19 checks
  green, `war_room_check` at 75 assertions. Every line of P1.8 now has a screen.
  - **The tick is slower, and bounded.** *"it should slower to savour"* (user), so
    roughly double: 1.1 s per node, 0.24 s apart. But a heavy tick can move twenty
    nodes, and a fixed stagger would turn a moment into a wait — so the sequence
    COMPRESSES past 3.6 s of stagger rather than growing, with the last node still
    getting its full duration. Nothing is ever cut short; the war just deals its
    cards faster when it is holding more of them. Any key jumps to the end,
    because the pacing that suits a campaign's first tick does not suit its
    fortieth.
  - **The hangar is the smallest honest version of P3**, and it is PLACED rather
    than merely added: top right, across the screen from the intel card that
    should decide it, which is P3.8's *"loadout as a response to intel"* made
    literal in a layout. Frames differ in hull, armor, mass and evasion style;
    loadouts, hardpoints and the salvage economy stay out (C10).
  - **THE PICK RIDES `MenuLaunch.frame_id` — the static that already exists.**
    The menu tower's frame tower writes it and `FlightController` reads it, so
    the room joins an existing path instead of inventing a parallel one. What it
    does add is a second hand-written LIST of frames, which is the exact shape of
    the bug that hid the falx and the screamer from the war for two weeks
    (v1.96): two rosters nobody compares are always self-consistent. So
    `war_room_check` asserts the hangar's list against the tower's, and a junk
    frame id falls back to a real frame rather than being flown.
  - **The roster is marks, not a numeral** (`| | | | |`), because five of
    something reads faster than the digit 5 and because losing one should be
    visible. It is redrawn when the TICK finishes rather than when the sortie
    resolves, so a pilot's mark disappears as part of the war moving instead of
    before the player has been told.
  - **"Save/exit anywhere" needed nothing built, and that is worth stating rather
    than quietly ticking off.** The war state only changes when a sortie
    resolves, and that is exactly when it is written; between sorties there is
    nothing to save. ESC leaves at any time and loses nothing, which makes
    P1.q4's *exit without save* the natural behaviour rather than a feature.
  - **The user has not yet seen a node LOST**, so whether an enemy capture reads
    clearly on the map is still unmeasured. It is one of the four things the
    animation can show and the only one that has never been in front of the human
    who asked for the map.
  - **A doc edit went missing from the working tree and the commit had it.** The
    v2.09 entry above was present in `HEAD` and absent on disk — caught only
    because the next edit to the same file refused to apply against content it
    did not recognise. Restored from the commit rather than retyped. Recorded
    because "the file on disk is what I last wrote" is an assumption, and this is
    the second time this session that checking beat assuming.

- **2026-08-01 — v2.11. ALL SEVEN ARCHETYPES FLY: half the theater stops being
  scenery.** `SLICE_ARCHETYPES` was `[strike, dogfight]` for the whole of
  Iteration 12, so 15 of 30 nodes on seed 4242 composed correctly and could not
  be instantiated. It is now all seven. 19 checks green.
  - **The five cost almost nothing to open, and that is the composer's design
    paying out rather than a boast.** An archetype IS its objective count, its
    reserve fraction and its trigger — `ARCHETYPES`, `RESERVE` and `TRIGGER_ON`,
    all data in one file. The runner already placed layers, spawned objective
    structures, ran triggers and ended on egress. Nothing about a SEAD differs
    from a Strike in code; it differs in the numbers the war hands over.
  - **ONE THING WAS GENUINELY MISSING, and it was invisible from every direction
    a test normally looks: `detected` had no firing site.** SEAD, Strike-CAP and
    the Raid key their reserves to it, and `_fire_trigger` was only ever called
    with `wave_cleared` and `objective_damaged`. The failure is not a crash or a
    deadlock — the composer is correct, the runner is correct, the sortie
    completes — it is that reserves are taken OUT of the placed garrison (P2.3),
    so the held slice never arrives and **the fight is quietly easier than the
    node it was composed from**, with the exchange rate wrong by exactly that
    fraction. The three archetypes would have shipped feeling fine and lying to
    the war.
  - **So the check for it is STRUCTURAL, not behavioural**: every value in
    `TRIGGER_ON` must appear as a `_fire_trigger(&"...")` call in the runner's
    own source. Reading source text in a test is unusual and it is the only kind
    of assertion that can fail for a trigger nobody has thought to write a
    scenario for yet. The behavioural half sits beside it — each archetype's
    reserve is observed firing when the pilot announces themselves.
  - **What `detected` MEANS, decided rather than defaulted.** There is no ingress
    yet (W.q7), so "the enemy sees you crossing the line" is not expressible: the
    pilot starts at the centre. It fires instead on the first moment you announce
    yourself — first kill, or first touch of the objective — and both routes
    exist because both play styles do. Recorded as the line to revisit when the
    ingress lands, because that is when staying unseen becomes the real
    counterplay P2.3 describes.
  - **P1.5's HQ SHIELD was enforced for the proxy and not for the player**, which
    did not matter while the Raid was unflyable and became a way to skip the
    entire campaign arc the moment it opened. The war room now refuses an HQ raid
    while command posts stand, on the tick engine's own count
    (`WarSim.command_posts_alive`, published for it). *"Break the enemy's command
    structure is the arc of every campaign"* is now a rule rather than a
    sentence.
  - **Two checks in this change first passed without testing anything.** The HQ
    shield fixture used a GENERATED theater, where the HQ is the furthest node
    from home — so both assertions read `out_of_range` and the shield was never
    consulted; it needed a purpose-built four-node fixture with the HQ next door.
    And the archetype sweep hit `ObjectiveAsset.take_hit` before `_ready` had
    built the Health, so every archetype reported as unable to open its egress —
    the same deferred-`_ready` trap that bit the war room's scene check two
    entries ago. Both now mutation-verified.
  - **What this does NOT do: balance any of it.** Five new fights exist and none
    have been measured. H6 is explicit that difficulty is measured and never
    authored, and the sortie bench is the thing that reads it — which is now the
    next job, and has more to chew on than it did this morning.

- **2026-08-02 — v2.12. THREE BUGS FROM ONE FLIGHT, and the worst of them was
  half of every garrison standing three metres outside the fight.** All three
  reported by the user flying a campaign; all three real, though one turned out
  to be a question rather than a fault.
  - **HALF THE GARRISON COULD NOT SEE YOU.** `EnemyDrone._can_engage()` gates
    PURSUIT as well as fire, so a unit whose ring puts the centre outside its
    `sight_range` never advances on it — it wanders for the whole sortie. The
    arithmetic is embarrassing once seen: the mid ring is **48 m** and a turret's
    sight is **45 m**. Outer raiders: 74 m ring against 60 m sight. Outer gnats:
    74 m against 70 m. Quantified by mutation — with the fix disabled, **9 of 14
    units blind on a strike, 6 of 9 on a SEAD, 3 of 6 on a dogfight**.
  - **THE FIX MAY BE IN THE WRONG PLACE, and this is recorded BEFORE the
    measurement comes back rather than after.** Units are now pulled inside their
    own sight of what they guard, which also CONCENTRATES the garrison (outer
    raiders 74 m -> ~51 m). But the sortie bench spawns its pilot at 125 m and
    flies IN, so outer units were engaging it on approach all along — the bench
    never had this bug. The human has it because `sortie.tscn` starts the drone
    at the arena centre, INSIDE the rings, with the garrison facing away. That
    points at the real fix being W.q7's **ingress** — spawn the pilot on an
    approach, as the bench already does — with the clamp reverted, rather than
    moving a garrison that was correctly placed for a fight nobody was flying.
    **The A/B that decides it is queued behind the long bench run.**
  - **THE SORTIE SCENE HAS NEVER HAD A VIDEO FEED.** `main.gd` has run the
    damage/jam feed breakup since v1.41 and `sortie.gd` was written without it,
    so a composed sortie was missing both halves of D6: battle damage never
    degraded the picture, and a screamer's jam had no way to announce itself.
    **The EW was working the whole time** — the screamer scene joins the
    `jammers` group, so the missile lock and the gun director were obeying it —
    which is the worst available combination: a working feature that is invisible
    reads to the pilot as a broken one. *"the vtx does not get distorted and i
    think the missles still lock"* is exactly what that feels like from the
    cockpit. Duplicated from `main.gd` rather than extracted, with the debt
    recorded: the extraction wants doing when a third consumer arrives, not in
    the same change as a bug fix somebody is waiting on.
  - **The blaster's auto-fire is not missing; it is UNEQUIPPED.**
    `fire_assist_miss_m` ships at 0.0 and its own comment already says what the
    user guessed: *"Prototype of the FCS equipment family (P3) — a dev knob
    today, an acquirable asset later."* Recorded because the question is the
    design working: a player inferred from play that an implemented capability
    was gated behind equipment they had not earned, which is precisely what P3
    intends it to feel like.
  - **The aegis has no target in a composed sortie, and it was NOT changed.**
    `route_end` is set to the sortie centre, so the enemy's own bomber flies to
    the middle of the node it is defending and detonates on its own objective. It
    never threatens the pilot, which is four of the six units on a decapitation
    node. Left alone deliberately: changing difficulty while the bench is
    measuring difficulty produces a table nobody can interpret. The lean is to
    send it OUTWARD — an aegis launching a strike against your territory, so
    killing it is an intercept and letting it go means the enemy landed a blow,
    which keeps P4.2's *"does not care about you, flies a route, detonates on
    arrival"* intact.
  - **The bench's settings moved to the command line** (`-- --reps 3 --cap 300`).
    Rep count is a RESOLUTION decision rather than a patience one: at 2 reps a
    rate can only be 0%, 50% or 100%, and H6's bands are finer than that, so a
    2-rep sweep cannot say whether a node is in band. Settings in the invocation
    also keeps BALANCE.md's rule enforceable — runs compare only at identical
    settings, so the settings belong where the run records them.

- **2026-08-03 — v2.13. THE LONG SWEEP: H7's debt is finally addressed, the SDI
  turns out to SATURATE, and my own prediction about it was wrong.** 78 cells x
  3 reps at a 300 s cap, every enemy node of theater 4242 with all seven
  archetypes open — the run H7 has been waiting for since v1.7.
  - **234 reps, zero completions, at every depth from 3 to 10.** The completion
    rate IS the SDI (H6), and pinned at 0% it has no resolution: every node reads
    identical, so the curve cannot be seen. Not because it is absent — because
    the instrument is against its stop.
  - **I PREDICTED THE CAUSE AND I WAS WRONG, which is why the A/B was run before
    anything was concluded.** The night before, I wrote down that I expected my
    own sight-clamp (v2.12) to be the reason, since it concentrates a garrison.
    Node 12 re-flown with the clamp DISABLED: `best flak 0% (dent 9.7)` —
    **identical to the clamped run, to one decimal**, with per-cell dents
    matching within noise (blaster 3.0 vs 3.1, flak 9.7 vs 9.7, missile 3.6 vs
    4.2). The clamp is a near no-op for a pilot that approaches from outside,
    which is exactly what the bench does from 125 m. It changes only the case it
    was written for — a pilot starting INSIDE the rings — so it neither caused
    this result nor corrupted the measurement.
  - **THE SIGNAL WAS IN THE DENT ALL ALONG.** Priced as a fraction of the node's
    own strength, the same sweep gives a real gradient: **54% at depth 3, 52%,
    39%, 29%, 21% at depth 7**, then flat at 26-28% because `garrison_cap` is 40
    and every deep node sits at it. That is H6's SHAPE in a unit H6 never named,
    and `sortie_bench` now prints it as a `cleared` column beside `complete`. An
    instrument that reports a saturated metric and hides an unsaturated one is
    the instrument's bug, not the game's.
  - **The blaster is never a node's best answer: 0 of 26.** Flak 13, missile 13,
    an exact split. R.q1 called the blaster the FLOOR weapon that never runs out;
    this is that claim measured at sortie scale rather than asserted.
  - **The theater has no pocket to measure.** Its shallowest enemy node is 3 hops
    out because the player's pocket is 2, so H6's `pocket 70-85%` band has never
    been measurable on this seed. The 54% at depth 3 is the shallowest reading
    that EXISTS, not the shallow end of the band.
  - **Five cells are rig faults and the bench's own guard caught them.** Node
    16's blaster reps are the sharpest: **300 s, 0% hull taken, nothing killed.**
    The pilot flew for five minutes, was never shot at, and could not hurt what
    it was aiming at — an aegis, whose shield hard-counters a chip gun (P4.3), on
    a node garrisoned by aegis and screamers. **Nothing there can threaten the
    pilot and the pilot cannot threaten it.** That is the aegis passivity flagged
    in v2.12 arriving as a measurement, and it is the strongest argument yet for
    giving the aegis somewhere to go.
  - **What this does NOT license: tuning.** H6 is explicit that difficulty is
    measured, not authored, and the reading is against a STOCK KESTREL with one
    weapon and no earned loadout — un-comparable to bands that describe an
    equipped pilot. The finding is the SHAPE and the saturation, not a verdict on
    any node's number.

---

## Iteration 14 — A: The Bomber's Identity (PROPOSED, 2026-08-03 — user-initiated)

> **The aegis is currently two enemies wearing one name**, and the user noticed
> from play: *"the aegis seems to be a mix of two things: a bomber AND a suicide
> bomber? i was not aware of that quality."* Sections **A1–A6**, open questions
> **A.q1–A.q5**; react by ID.

### A1 — P4.2 ALREADY SAYS WHAT THE USER SAID, and that is the finding

Before proposing anything, the existing entry, quoted rather than paraphrased:

> **Aegis — shielded bomber (the ticking bomb).**
> *Threat:* time + the war — it ignores you and flies its strike route **toward a
> friendly asset (your pad, an allied garrison, the exit gate's sector)**.
> *Behavior:* route drawn in intel/briefing; **escort wings (raider/falx) fly
> cover**; a screamer escort jams your easy answer.
> *Strategic:* heavy-industry production; **enemy operations can commit them as
> bomber raids against your nodes (P4.7) — an intercept sortie the war
> generates.**

The user, independently, from flying it: *"i thought its purpose was to be a
bomber that drops bombs and heavy ammunition on ally targets, being a part of an
invasion to an ally teritory... protected by smaller, fly-like little and quick
frames that defend it."*

**Those are the same design.** Target is YOUR asset, escorts fly cover, the war
commits them as raids you intercept. The doc has said so since Iteration 2 and
nothing built has ever done it.

**So this iteration is not a redesign. It is a drift report**, and the drift has
two halves:

1. **The target inverted.** `SortieRunner` aims the aegis at the sortie's own
   centre — the enemy's own objective — so the enemy's bomber flies into the
   middle of the base it is defending and detonates on it. Measured 2026-08-03:
   node 16, three reps, **300 s each, 0% hull taken, nothing killed**.
2. **"Arrival" became SELF-DESTRUCTION.** P4.2 never says the aegis is expended.
   It says the arrival is bad for you and every second alive is a countdown. The
   implementation reads "arrives" as "detonates", which quietly makes it a
   kamikaze — a different enemy with a different counter-web position.

### A2 — What the aegis should be (the user's refinement, adopted)

A bomber that **carries ordnance, spends it, and leaves**:

- It flies **bombing passes** at its target rather than ending on one arrival.
- It carries a **payload** — a finite number of drops, the same grammar
  Iteration 10 gave the player's flak and missiles (R2's "what is consumable").
- **When the payload is spent it egresses**, and getting out counts as an ENEMY
  SURVIVING — a distinct outcome from being killed, and one the war can price.
- It is **escorted**, which P4.2 already specifies and the user restated
  independently: *"smaller, fly-like little and quick frames that defend it."*
  That is the gnat and the falx, and doctrine can already express it.

**Why this is better than the ticking bomb, beyond matching the doc.** A
kamikaze's threat ends when it arrives, so the fight has one deadline and then it
is over. A bomber that leaves gives the player a SPECTRUM: kill it before it
drops anything, kill it between passes, or fail and watch it go home having done
its damage. That is three outcomes where self-detonation offers two, and the
third is the one the war-sim can actually price differently.

### A3 — The suicide frame is a SEPARATE TYPE, and the user is right to want one

*"i think that a new dedicated suiciding frame would be a GREAT addition to our
roster. i dont see the ageis as a suicider."*

Agreed, and the roster already half-argues for it: the **gnat** is contact
detonation at swarm scale (P4.2: *"collision sting (contact detonation)"*). What
does not exist is a single body whose whole purpose is to reach you and go off —
fast, committed, unsubtle, answered by killing it at range or by not being where
it expects you.

That is a genuinely different web position from both: the gnat is cheap mass you
out-area; the aegis is a durable clock you out-prioritise; a dedicated suicider is
a **timer aimed at YOU personally** that you out-range or out-manoeuvre. Named
and specified in A5.

### A4 — What removing the aegis from garrisons actually costs

The user: *"a bomber attacks, not defends."* True, and it has consequences that
should be visible before the edit rather than discovered by a red board:

- **`manifest_check` asserts the HQ fields the aegis** (*"the HQ fields the heavy
  type"*). Delete the aegis from doctrine and the theater HQ loses its heavy
  anchor.
- **The escalation mechanic leans on it.** `HEAVY_TYPES` is `[aegis, screamer]`
  and P4.6's whole claim — a war under pressure fields heavier things rather than
  more things — is asserted through the aegis's share rising. Remove it and the
  screamer carries that alone, which is thin: the screamer has no weapon, so
  "escalation" would mean "more jamming" and nothing else.
- **The campaign loses a type until bomber raids exist.** The aegis's proper home
  (A1's quoted strategic note) is enemy operations attacking YOUR nodes, and that
  is unbuilt. Removed from garrisons today, the aegis simply vanishes from the
  campaign — it stays only in the arcade wave director, where its route already
  points at something of yours and where it has always worked correctly.

So there is a sequencing choice, and it is A.q1.

### A5 — The new type, specified enough to argue with

**Lance — the committed suicider.** (Name is a proposal; the roster's names are
short, hard nouns — gnat, raider, falx, aegis, screamer, sentinel.)

- *Durability:* light, but **fast enough that chip guns get one honest window**.
- *Mobility:* fastest thing in the roster on a straight line; poor turns. It
  commits to a run and cannot re-decide.
- *Threat:* hull, all at once. Contact detonation with a real blast, not a sting.
- *Behavior:* acquires, aligns, accelerates. **The telegraph is the alignment** —
  a visible, audible commitment before the run, so the counter is a decision and
  not a reflex (P4.4's readability rule).
- *Web role:* punishes **hovering and slow heavy frames** (it is aimed at where
  you are, so being somewhere else is the answer); answered by area weapons and
  by lateral speed; **hard-countered by not being predictable**.
- *Terrain:* open ground is its home; obstacles are your friend, because a
  committed run cannot follow you around a corner.
- *Strategic:* cheap and expendable — the type a losing enemy fields MORE of,
  which makes it a natural escalation partner and a candidate replacement for the
  aegis's `HEAVY_TYPES` role (A4).

### A6 — The ingress, decided in the same conversation

Separately and already settled by the user: **the player will spawn OUTSIDE the
target area and fly their own approach.** *"we should indeed put the player
outside of the battle area and let him make his own attack approach."*

They tie it back to P1.9's biomes, in their words: *"one of the bioms can be some
kind of an open field, where there are some hills that allow a smart player to use
it to his advantage, fly low to avoid SAM sites, until he gets close and then do a
suprise attack on the SAM defense, elevating the chance to complete the mission
and escape."*

That is W.q7's ingress and P2.4's approach as one thing, and it retires the
`SIGHT_COVERAGE` clamp (v2.12) rather than keeping it: the clamp exists only
because the pilot started inside the rings. On the extra work of making the
signal-lost leash agree with a spawn that is deliberately far out, the user was
unambiguous: *"i believe its worth it because we'll eventually want this anyways,
why wait?"*

### A7 — THE ESCALATION GAP, and why it needs a type that belongs in defence

Raised by the user while answering A.q1, and it is the sharpest point in the
conversation:

> *"in order to 'feel' an escalation we must introduce tougher enemies, and not
> simply spawn more and more raiders. however if it means we deploy an enemy unit
> that has no reason to be there it breaks the immersion, and simply feels off.
> why would the enemy deploy his bombers in his own teritory? doesnt make sense."*

That is a genuine hole and it was previously hidden by the bug. P4.6 says a
pressured enemy fields **heavier things rather than more things**, and
`HEAVY_TYPES` is `[aegis, screamer]` — but once the aegis correctly leaves
defensive garrisons (A.q1), the only heavy thing left in defence is a jammer with
no weapon. **"The war escalates" would mean "the war gets foggier", and nothing
else.** The roster has no heavy DEFENDER at all.

**Phalanx — the heavy gunship** (the user's sketch, named to the roster's own
convention). Their words: *"a heavy frame that moves slower and has multiple
turrets that fire at me at the same time, something like the aegis but faster,
carrying a shield/force field, and has multiple vectors of attack on the player."*

- *Durability:* shielded like the aegis, but the shield is a **facing** thing
  rather than a flat gate — the counter is to be where the guns are not.
- *Mobility:* slow (~0.6× raider) and deliberate; it does not chase, it holds
  ground and denies it.
- *Threat:* hull, from **several turrets at once**, which is what makes it
  different from every existing type: it has no blind side you can simply sit in.
  It is the first enemy that punishes a single orbit slot.
- *Behavior:* holds a station near what it guards. The telegraph is spin-up —
  turrets tracking before they fire, so the commitment is visible.
- *Web role:* the anti-orbit type. It punishes the peel-and-kill rhythm the
  raider deliberately allows (P4.2 calls raider spacing "peelable"), and is
  answered by stand-off weapons, by terrain, and by killing it from one arc while
  its shield faces another.
- *Terrain:* open ground is its best; cover is the player's whole answer.
- *Strategic:* **THIS is the escalation anchor.** A besieged enemy digging in
  behind heavier defensive hardware is immersive in a way that a bomber parked in
  its own back yard is not — which is exactly the user's objection, answered.

Not scheduled here. Recorded so the escalation hole has a named shape rather than
being rediscovered as a red board when A.q1 lands.

### A steering — ANSWERED (2026-08-03, same day)

- **A.q1 → DECIDED: (a) the aegis stays only where bombers are BASED** — enemy
  airbase and HQ — and flies OUTWARD from there. It reads as scrambling from its
  own field rather than guarding it, and the escalation and HQ assertions
  survive the change. The user's reasoning is the fiction, not the arithmetic:
  *"why would the enemy deploy his bombers in his own teritory?"* — a bomber
  sitting at an airbase is a bomber at home; a bomber ringing a radar dish is a
  design error you can see from the cockpit.
- **A.q2 → DECIDED: yes, the payload is a magazine**, in the same group and the
  same vocabulary Iteration 10 built for the player. A bomber out of bombs is
  then legible exactly like a pilot out of flak, and one mechanism covers both.
- **A.q3 → DECIDED to the lean, but the user's reasoning is BETTER than the lean
  and is recorded as the destination.** They pointed out that the intuitive
  consequence of killing a bomber is that **the node that LAUNCHED it gets
  weaker** — you did not just survive a raid, you destroyed hardware belonging to
  a specific place on the map. That is correct and it is not something the war
  can currently express: nothing in the state records which node a raid came
  from, so there is no provenance to price. Their own conclusion, having seen
  that: *"if not, and i guess its not in our design, then yes, your option is the
  simplest and most clean. it prices the player for both not being able to stop
  it AND failure to destroy it before it escapes."*
  - **So: an escaped bomber damages the node it flew AT, for now.**
  - **And a new item is on the board: raid PROVENANCE.** When bomber raids are
    built (P4.2's "intercept sortie the war generates"), the raid should carry the
    id of the node that launched it, so killing the bomber dents THAT node. It is
    a small field on a structure that does not exist yet, which is exactly when it
    is cheapest to add.
- **A.q4 → DECIDED: the Lance ships AFTER the aegis rework.** One at a time; the
  aegis is broken now and the new type needs its own behaviour check the day it
  lands (standing rule 2).
- **A.q5 → DECIDED: Lance**, chosen over the user's "daredevil" and "torpedo" and
  offered back with the reasoning, since they left it to me. The roster's names
  are weapon-and-armour nouns from antiquity — **falx** is a curved sword,
  **aegis** is a shield — so **lance** sits in the family and says "committed
  straight line" without saying "bomb". "Torpedo" was the close second and reads
  naval; "daredevil" describes a pilot's attitude rather than a machine.
- **The suicider's TARGET is left open on purpose.** The user expected it to be
  *"more like a ticking bomb that i need to stop before they hit their target
  which is not necessarily me"*, and on hearing the player-seeking version said
  *"a fast suicider coming at me sounds like a cool addition"*. Both are good and
  they are different enemies: one is a second aegis at small scale, the other is
  an evasion test aimed at you. **A.q6, to be answered when the Lance is
  scheduled.**

### A open questions (react by ID)

- **A.q1 — Where does the aegis live until bomber raids exist?** (a) **Leave it
  in doctrine only where bombers are BASED — airbase and HQ — and send it
  outward**, so it reads as scrambling from the field it sits on rather than
  guarding it; the escalation and HQ assertions survive. My lean, as the interim.
  (b) Remove it from doctrine entirely now, accept that it leaves the campaign
  until raids are built, and hand `HEAVY_TYPES` to the Lance. (c) Keep it
  everywhere until raids exist. I think (c) is the only wrong answer.
- **A.q2 — Does the payload make the aegis a magazine?** Iteration 10 built
  `magazines` for the player and the grammar fits exactly (`rounds`, spend,
  refuse when dry). My lean: **yes, the same group and the same vocabulary**, so
  a bomber that is out of bombs is legible in the same way a player out of flak
  is.
- **A.q3 — What does a bomber that ESCAPES do to the war?** It is a new outcome
  the sim has no verb for. My lean: it **damages the node it flew at** — the same
  `apply_sortie` arithmetic pointed the other way — because "the enemy landed a
  blow on your territory" should cost you something the map can show.
- **A.q4 — Does the Lance ship before or after the aegis rework?** My lean:
  **after.** The aegis is broken NOW and the fix is small; the Lance is a new
  bestiary type and standing rule 2 says it needs its own behaviour check the day
  it lands. One at a time.
- **A.q5 — Is "Lance" the right name?** Weak lean, offered to be overruled:
  short, hard, and it says "committed straight line" without saying "bomb".

- **2026-08-03 — v2.14. Iteration 14 steered the same day, and the user found the
  hole that the aegis bug had been hiding.** A.q1-A.q5 answered, A7 added, A.q6
  opened.
  - **A.q1 → the aegis stays only where bombers are BASED** (enemy airbase, HQ)
    and flies outward from there. The user's argument is fiction rather than
    arithmetic and is the right one: *"why would the enemy deploy his bombers in
    his own teritory?"* A bomber at an airbase is a bomber at home; a bomber
    ringing a radar dish is a design error visible from the cockpit.
  - **THE ESCALATION HOLE, which is the real find (A7).** The user: *"in order to
    'feel' an escalation we must introduce tougher enemies, and not simply spawn
    more and more raiders. however if it means we deploy an enemy unit that has no
    reason to be there it breaks the immersion."* Correct, and it was concealed by
    the bug: `HEAVY_TYPES` is `[aegis, screamer]`, so the moment the aegis
    properly leaves defensive garrisons, **the only heavy thing left in defence is
    a jammer with no weapon** — "the war escalates" would mean "the war gets
    foggier" and nothing else. **The roster has no heavy DEFENDER at all.**
    Recorded as the Phalanx: a slow, shielded, multi-turret gunship whose shield
    is a facing rather than a flat gate, and which is the first enemy that
    punishes a single orbit slot. It is the escalation anchor that belongs in its
    own territory.
  - **A.q3: the user's reasoning beat my lean, and the lean still stands.** They
    pointed out that killing a bomber should intuitively weaken **the node that
    LAUNCHED it** — you destroyed hardware belonging to a specific place. That is
    right and the war cannot express it: nothing records a raid's provenance. They
    reached the practical conclusion themselves — *"then yes, your option is the
    simplest and most clean"* — so an escaped bomber damages the node it flew AT
    for now, and **raid provenance goes on the board** as a field to add when
    bomber raids are built, which is the cheapest moment it will ever exist.
  - **A.q5 → Lance**, decided by me because the user left it to me, and offered
    back with the reasoning rather than just the pick: the roster's names are
    weapon-and-armour nouns from antiquity (**falx** a curved sword, **aegis** a
    shield), so **lance** joins the family and says "committed straight line"
    without saying "bomb". Their "torpedo" was the close second and reads naval;
    "daredevil" describes a pilot rather than a machine.
  - **A.q6 opened: what is the Lance actually aimed at?** The user expected a
    ticking bomb aimed at something that is *not necessarily the player*, and on
    hearing the player-seeking version liked that too. They are different enemies
    — one is a small aegis, the other is an evasion test — and the choice waits
    until the Lance is scheduled.
  - **Next: the INGRESS** (A6), decided and unblocked. The player will spawn
    outside the target area and fly their own approach, which retires the v2.12
    sight clamp rather than keeping it.

- **2026-08-03 — v2.15. THE INGRESS IS BUILT (A6 / W.q7), and the sight clamp is
  gone rather than kept.** The pilot now starts OUTSIDE the target area, on the
  bearing the spec has carried since v1.71, facing what they came to hit, and
  flies their own approach.
  - **What was actually wrong, stated once so it is not rediscovered.**
    `EnemyDrone._can_engage()` measures its distance to the PLAYER. The pilot
    started at the arena centre, so every ring was measuring from the wrong end:
    a garrison could be fully placed, fully alive, and engage nobody. That is the
    whole of *"some sorties seem open, but when i fly into them nothing engages
    with me"*.
  - **v2.12's `SIGHT_COVERAGE` clamp was the compensation, and it is deleted.**
    It pulled every defender inward until it could see the middle, which is only
    the right answer for a pilot who is standing in the middle. The A/B that
    justified deleting it rather than keeping both: `sortie_bench` has always
    spawned outside and flown in, and node 12 read `best flak 0% (dent 9.7)`
    clamped and unclamped — identical to one decimal. Two mechanisms for one
    problem, where the second is the real fix, is how a compensation becomes a
    rule nobody can remove later.
  - **The one number that is not a direct reading of the spec, and why.**
    `SortieComposer` emits `ingress_m` in FICTION units — 400 m over open desert,
    150 m through a city — and is right to, because `war/` is pure and cannot
    know how much air an arena has. This one has ~100 m of ground per direction
    and an FPV link that drops at 300 m. So `SortieRunner` remaps the composer's
    own band onto the band this arena can host, ORDER PRESERVED: 140 m (city) →
    148 (industrial) → 173 (hills) → 195 (desert/plains). The runner is already
    the only place a spec becomes a Node3D; it is therefore the only honest place
    for fiction units to become world units.
  - **The two constraints it had to fit between, both now asserted rather than
    remembered.** Above `EGRESS_RADIUS` (105 m) by 25 m, or the pilot spawns on
    the far side of the line a strike ends by crossing; below the FPV leash's
    220 m warning by 20 m, or the game says SIGNAL WEAK before the pilot has
    moved. Those two numbers live in two different files and nothing else
    connected them — `sortie_check` now reads the leash off `sortie.gd` and
    compares, so a later tuning pass cannot separate them silently.
  - **The check that used to live there is replaced, not just deleted.** *"A
    garrison that cannot see its own objective is not a garrison"* was the right
    assertion about the wrong world, and with an ingress it would FAIL a
    correctly placed mid-ring turret. What replaces it is the ingress geometry
    plus an anti-constant pair: the point must sit on the spec's own bearing, and
    two nodes with different `ingress_m` must land at different ranges. Without
    that pair a hard-coded spawn would pass every distance assertion and be
    invisible — which is exactly the state the approach block was in for two
    months.
  - **Detection-on-sight is now possible and was deliberately NOT built.** Firing
    `detected` when a garrison unit can see you is the obvious completion, and
    P2.3's staying-unseen counterplay wants it. It is held because the approach
    is flown over flat empty ground: with nothing to mask behind, a sight test
    fires at a fixed distance every time, so the only effect is reserves arriving
    ten seconds earlier with no new counterplay bought. **Detection and cover are
    one feature**, and shipping half of it ships the half that only takes. It
    lands with P1.9's terrain, which is A6's own motivation.
  - **`corridors` and `cover` are printed in the briefing and still unflown**, for
    the same reason: a corridor is a lane through terrain and there is no terrain
    yet. Printed rather than ignored, so the number a biome generator will have to
    honour is visible now instead of being rediscovered.
  - **The greybox ground went 200 m → 600 m.** Collision was always an infinite
    `WorldBoundaryShape3D`, so the mesh only ever governed how far you can SEE
    ground — and 200 m centred on the origin ran out ~85 m from the arena centre.
    Survivable while every spawn was in the middle; with the pilot put down at
    140-195 m and pointed inward, the first thing a sortie showed you was a drone
    parked over nothing. It now reaches as far as the leash lets you fly.
  - **`FlightController.place_at()` is new and the second half is the point.** A
    child's `_ready` runs before its parent's, so `_spawn_transform` was already
    captured by the time the scene moved the drone — B (reset) would have
    teleported the pilot into the middle of the enemy base.
