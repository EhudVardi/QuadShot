# QuadShot — Gameplay Design (Living Doc)

> **Status:** v1.1 (2026-07-16) — two steering passes folded in, all four forks
> decided, **Iteration 1 (P1 — Living Theater) proposed and awaiting steering.**
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
missiles gain their own director: a **stateful `missile_auto` switch** — with
it on, a full lock held stable for `missile_auto_hold_s` auto-launches. The
HUD lock was made unmistakable (pulsing red double diamond + LOCK tag) and the
director winds an orange arc around it while the hold timer runs, so the pilot
always knows what the computer is about to do. Confirmed for the counter-web:
**EW/jammers should jam FCS members** (both gun director and missile
director), degrading or breaking their solutions — positioning gear vs.
denial gear becomes a real loadout axis.

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

### P1.8 — The command room (where the theater lives)

The between-sorties screen — the "battle commanding room" (F2):

- The **theater map**: nodes, ownership, front line, supply edges, weather
  icons, your airbase range rings.
- **Node inspection**: intel card (freshness-stamped), garrison estimate,
  forecast.
- **Pilot roster** (F1) and **hangar** (P3: frames + loadouts).
- **Sortie select → briefing** (what intel claims) **→ fly → debrief** (what
  actually happened, what you changed) **→ the war tick plays out as animated
  map movement** — the moment the player *feels* the theater being alive.
- Save/exit anywhere; the whole thing is one portable file (F4).

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
