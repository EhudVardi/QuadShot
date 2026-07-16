# QuadShot — Gameplay Design (Living Doc)

> **Status:** v1 — first steering pass folded in (2026-07-15). All four forks decided.
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
| **Real radio / HID** | **DO NOW** — the only backlog item pulled forward | Target hardware: **RadioMaster TX16S**. Full utilization from the start so the flight model is adjusted to perfection on real gear as the game grows. Brings a flexible, extensible input-binding layer with it (which is most of "remapping" anyway). |
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

**P5 — The Reward Economy & Influence** (meta + agency). *⚠ Awaiting feedback —
the v1 review pass skipped this pillar (feedback section was empty). Standing
content below; react when ready.*

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
of pilots loses the playthrough** — alongside the strategic loss condition
(your forward base falls). This is the middle point: forgiving enough not to
frustrate, but death never loses its meaning (the anti-goal: games where
endless deaths make dying meaningless).
*Rationale:* merges "the war is what's at stake" with "my life still matters."
Open sub-questions for the P5/P1 iterations:
- **F1.a** — difficulty: fixed (game escalates organically) vs. selectable
  (X pilots scales with difficulty)?
- **F1.b** — should a death *also* cost tempo (the war ticks while you
  re-deploy), making each loss strategically felt beyond the pilot count?

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
