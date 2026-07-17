# QuadShot — Gameplay Design (Living Doc)

> **Status:** v1.18 (2026-07-18) — the pillar+harness paper phase is closed; **a
> completeness review surfaced one real gap, now PROPOSED as Iteration 7 (the
> damage model), awaiting steering.** Six iterations closed: five pillars (P1
> theater, P4 bestiary, P3 arsenal, P5 economy, P2 composition) + Iteration 6 (the
> balance harness + stated difficulty curve, H1–H9) all proposed *and* steered;
> all four forks (F1–F4) decided; the
> war-sim skeleton lives and runs green (v1.7). The model composes end to end and
> now *proves itself*: the war generates nodes, the manifest dresses them in the
> bestiary, the arsenal answers the matrix, the economy prices it, the composer
> projects it into sorties, and a four-layer harness (unit/sortie/economy/
> strategic) measures whether it all lands on the difficulty curve — SDI measured,
> not authored; a scripted reference pilot the hands calibrate.
>
> **One gap surfaced by the completeness review and got its own iteration:
> Iteration 7 — The Damage Model (PROPOSED, D1–D9).** The six iterations specced
> *enemy* durability richly but left the *player's* damage an abstract hit-point
> pool — a number, in a game whose north star is *the flight model is the
> product*. Iteration 7 makes damage a **flight-model event** (flying a wounded
> quad: asymmetric motor-out, prop vibration feeding the Filtering group, video
> breakup), ramped arcade↔sim for readability, and gives pads/repair (P2.6/P5.6)
> their missing referent. It must close before build. **Next: steer Iteration 7
> (react D1–D9, Dq1–q6), then the vertical-slice build** (P4.10/P3.10/P5.11/
> P2.13), the H9 harness cut making it measurable from its first commit.
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
