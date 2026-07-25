# B3 Interiors — Design Spec

**Status:** approved design (design-only session, 2026-07-25). Resumes after v1.64.
**Roadmap slot:** Iteration 8 → B3 (the "depth" turn — the city's breadth is deep
and flyable through v1.64; buildings are still hollow shells). Closes the gap
between a shell (walls, windows, slabs, columns) and a *flyable interior*.
**Authority read before building:** `CLAUDE.md`, `GAMEPLAY-DESIGN.md` Iteration 8
(B1–B6, B.q1), and the generation-order code (`building_generator.gd`,
`menu_floor_frame.gd`, `menu_building.gd`, `box_batcher.gd`, `world_building.gd`,
`city_layout.gd`, `theater_generator.gd`).

---

## 1. Thesis

Indoors is FPV's dungeon crawl (B1). A hollow shell becomes a place you fly
*into*: thread a lit window at speed, weave the open-plan volume, exit the far
side. The flight model is the product — interiors are the second form of its
expression (precision where the open sky rewards velocity). This spec makes open
floors *flyable interiors* while honoring every carried constraint: greybox only,
`BoxBatcher`-batched from the first line, one render path, deterministic/seed-
driven (F4), checkpoint protocol (the human's hands are the test).

Out of scope, on purpose: **combat indoors (B.q1)** — traversal ships first;
**sortie composition (P2)** — a boundary designed *toward*, not built.

---

## 2. The settled model (decision log — Q1–Q4)

These four choices, made with the user in the brainstorm, are the spine. Recorded
with rationale so a future reader knows *why*, not just *what*.

### Q1 — The unit of interior: **open-plan floors** (not chamber, not maze)

A floor is **one open volume**; structural columns + scattered furniture *are* the
maze. No interior partition-wall network.

- *Why:* smallest delta from today's hollow shell (the shell already has outer
  walls + window openings — we populate the volume); preserves FPV sightlines so
  lines are readable at speed; lightest on collision shapes (the real perf
  ceiling). Rejected: **chamber** (one room per window — too thin for the "depth"
  turn) and **floor-maze** (rooms + corridors — a real partition algorithm and the
  heaviest geometry; the dungeon thesis, but overkill for the first bite).

### Q2 — Variety source: **district-linked programs**

A floor has a *program* (office / warehouse / atrium / …). Which programs a
building draws from is gated by its **district** — the `_zone` scalar + core point
already built (v1.55, v1.64).

- *Why:* reuses a solved input for nearly free (the zone is known at generation
  time); makes the interior *extend the identity you already read from three
  blocks away* (B2 doctrine: the skyline is its own map). Rejected: district-
  agnostic programs (outside stops predicting inside) and abstract clutter (every
  floor is "some office-ish clutter" — texture varies, character doesn't).

### Q3 — District × height composition: **district RESTRUCTURES the profile**

District changes *which programs stack up the tower*, not just their skin. Each
district gets real program archetypes and its own vertical **program profile**.

- *Why (user's call, against the spec author's initial simplicity lean):* the
  bigger variety win — the district is *felt* inside (a cyber tower flies
  differently than a natural one), not just seen. Cost accepted: a few more real
  archetypes to author + a small per-district profile table (same deterministic
  machinery). Rejected: re-skin only (one universal profile, themed by paint —
  predictable, less variety).

### Q4 — Fill strategy: **refined-B (seeded scatter, both folds)**

Seeded scatter (organic, bando/warehouse feel) over a tidy grid — **plus two
folds** that keep the project's values:

- **Fold 1 — sparse structural columns.** A handful of load-bearing columns still
  hold the slab, so *nothing floats* (the value the under-construction floors
  already enforce). Structure, not a maze; furniture scatters around them.
- **Fold 2 — a keep-clear *network*, not one tube.** Clear channels join *every*
  open window through a central hub. A building opens 1–4 sides toward the core
  (v1.62) and the pilot may thread any of them, so any window must reach any
  other. This is the flyability guarantee — and it is headless-assertable.

- *Why:* scatter reads closer to the real freestyle-FPV fantasy than a grid that
  looks too neat at speed; the folds reconcile it with "nothing floats" and
  "provably flyable." Everything that makes it feel organic (density, jitter, mix,
  spacing, channel width) stays a seed-driven tunable tuned in flight.

---

## 3. Architecture — two pure generators + one render hook

Mirrors the existing split — `BuildingGenerator` (pure) → `MenuBuilding` /
`MenuFloorFrame` (render) — and `theater_generator`'s purity discipline (config +
seed in, serializable data out).

| New unit | Location | Kind | Responsibility |
|---|---|---|---|
| `BuildingProgram` | `scripts/environment/` | pure static (`RefCounted`) | `(district, building_seed, floor_count)` → per-floor **program list**. Owns the per-district profile table (§5). |
| `InteriorGenerator` | `scripts/environment/` | pure static (`RefCounted`) | `(program, floor_seed, footprint, interior_height, open_sides, knobs)` → **interior spec** `{columns[], pieces[], channels[]}`. All layout logic (§4). Deterministic. |
| `InteriorBuilder` | `scripts/menu/` | render helper (`RefCounted`) | Expands each spec `piece{kind, pos, size, yaw}` into greybox boxes (the kit, §6) + per-box collision, into the floor's **existing `BoxBatcher`**. |

**Data flow:**
`CityLayout` (knows district/zone per block) → sets `WorldBuilding.district`
(the **discrete 3-way classification** already computed by `CityLayout._prop_style`
→ `PropStyle.CYBER / NATURAL / URBAN`, so interior district == the ground-prop
zone the block already wears) → `WorldBuilding` calls `BuildingProgram` for the
per-floor program list, then
`InteriorGenerator` per **open** floor → stamps `spec["interior"]` (+ program /
palette hints) into the floor-spec dict → `MenuBuilding` threads it unchanged →
`MenuFloorFrame._build_open()` calls `InteriorBuilder` when a spec is present.

**One render path preserved.** Interiors are *more boxes in the same per-material
batch* a floor already commits (`_batch`), so a furnished floor stays ~1–3 draw
calls. Menu floors pass no interior spec → the menu is untouched. The spec is
plain data (Dicts/Arrays), so the environment→menu hand-off carries no code
coupling.

**Render-path decision (§6 of the brief):** *extend* `MenuFloorFrame`, do not
fork. `InteriorBuilder` is a *renderer helper* that adds to the one batch — not a
second render path. Deliberate: the doctrine (menu + world share
`MenuFloorFrame`) held through the whole building arc; interiors keep it.

---

## 4. The interior generation algorithm (refined-B)

`InteriorGenerator.generate()` — pure, deterministic from `floor_seed`, in order:

1. **Channels.** Clear tubes of width `channel_width` from each open window to a
   central hub, so every open side reaches every other. The flyability skeleton.
2. **Columns.** A sparse load-bearing grid (reusing the under-construction column-
   grid discipline, `SCAFFOLD_COLUMN_SPACING` as a starting cadence). Drop any
   column landing in a channel or a window opening. These hold the slab above.
3. **Scatter.** Draw furniture kinds from the program's palette; place with seeded
   jitter, a Poisson-style `min_clearance` (pieces never fuse), and rejection
   against channels + window openings + columns. Density from `scatter_density`.
4. **Emit** the spec as data — `{columns[], pieces[], channels[]}` — no meshes.

**Headless invariants** (`interior_gen_check.gd`, treat warnings as errors):
- Every open side connects to every other through clear space (flood-fill /
  channel-graph check).
- No piece overlaps a window opening.
- `min_clearance` holds between all pieces.
- Same `floor_seed` + inputs → byte-identical spec (F4).

---

## 5. Programs & the per-district vertical profile

"District" here is the discrete `PropStyle.CYBER / NATURAL / URBAN` a block
already wears (reused from `CityLayout._prop_style`, off `_zone`), so inside and
outside can never disagree.

**Program archetypes** (each = a kit subset + density + palette): `lobby_atrium`,
`warehouse`, `office`, `atrium`, `server_farm`, `dock`.

`BuildingProgram` holds a small **profile table per district**. Height fraction
`k / floor_count` selects the band; the profile **scales to height** (short
buildings collapse to their base bands). Sealed / under-construction floors
interleave exactly as today (unchanged). The **ground floor is always a
lobby-atrium** ("enter into a breather").

- **Natural (mid ring):** lobby-atrium → warehouse (base) → office (bulk) →
  atrium (top). The classic stack.
- **Cyber (core):** lobby → **server-farm-dominant** core → sky-lobby atrium
  (glowing). Flies tight and bright.
- **Urban (rim):** dock → **warehouse-dominant**; short rim buildings drop the
  upper bands entirely.

District also picks the **palette** — reuse `CityLayout`'s existing
`CYBER_*` / `NATURAL_*` (`TREE_*`) / `HARDSCAPE_*` colors so inside and outside
agree. Interior surfaces stay near-black (`INTERIOR_ALBEDO`) with emissive accents.

---

## 6. The greybox furniture kit (B3)

All `BoxMesh`, batched. **Variety by combination, not asset count** (the P4.q1
doctrine, applied to furniture): a small kind-set × jitter × orientation ×
program-weighting yields rich floors. Each kind is a function
`kind → boxes(+material)` inside `InteriorBuilder`.

- **Structural:** column, half-wall / partition stub.
- **Office:** desk, desk-cluster, cubicle (desks + partitions), cabinet, shelving,
  meeting-table, reception counter.
- **Warehouse:** racking-run (the aisle-formers), pallet-stack, crate-pile.
- **Atrium:** planter, bench, counter / kiosk, central feature block.
- **Server-farm (cyber):** server-rack (shelving + emissive front), cable-tray.
- **Dock (urban):** loading platform, container stack, roll-door frame.

**Reuse note:** `CityLayout` already has `_add_tree/_add_hedge/_add_bench/
_add_kiosk` shapes; atrium props can mirror them. A shared-kit refactor is
*possible later*, not required now (stay focused on the current goal).

---

## 7. Opening / aisle sizing — the tuning surface

Follows `CityLayout`'s **`@export` procgen-knob** pattern (not a physics `*Config`
resource — procgen knobs live on the driving node and re-roll live, like the CITY
overlay), exposed via an optional **INTERIOR overlay section**. The drone is a
0.28 m box; "fits vs feels good" is the whole surface, and it is a config, not a
constant (B3's explicit ask).

- `channel_width` — the aisle you fly. **Generous-first** (~2–2.5 m); the human
  tunes it *down* toward skillful.
- `min_clearance` — Poisson spacing between scattered pieces.
- `scatter_density` — pieces per unit floor area.
- `column_spacing` — structural cadence.
- furniture size-jitter ranges (per kind).
- `interior_fit_margin` — the explicit "fits vs feels good" gap.

All seed-driven and tuned by hand in flight (checkpoint protocol).

---

## 8. The B2 lighting moment

Extends the existing look pass — **no new architecture** (`LookController` already
applies `LookConfig` onto Environment/Sun every frame):

- **Auto-exposure** grows as a `LookConfig` group; `LookController` applies
  `CameraAttributesPractical` auto-exposure. Crossing the window line, the *eye
  adapts* → "gets darker inside," then brightens — the user's original "hdr?".
- **Genuine darkness:** ambient held low; a shadow-casting sun cannot reach inside
  a slab; interior surfaces are already near-black. Neon-emissive reads *better*
  in the dark (bloom threshold 1.0, accents above it).
- **Neon wayfinding:** the keep-clear channels carry faint emissive guide strips
  (navigation cyan, like the window-line / chevrons) so the flyable path *shines
  the way*; program props glow in the district palette. "Neon lights shine the
  way" — light is the path telegraph, the interior cousin of B2's enterability
  telegraph.

A distinct beat, tuned by hand.

---

## 9. Performance & LOD (the real constraint)

Batching handles *draw calls* (interiors fold into the floor's per-material batch).
The cost is **collision shapes + node count + `_ready` build cost**, which
multiply across a city (a 4×5 city is already ~3,000 collision shapes).

- **Eligibility:** only **open** floors furnish (sealed / under-construction
  unchanged).
- **Building-level distance LOD:** a building furnishes its open floors only within
  `interior_lod_radius` of the drone; beyond, hollow shells (today's behavior).
  `MenuFloorFrame` gains `build_interior(spec)` / `clear_interior()`;
  `WorldBuilding` toggles them by drone distance (with hysteresis). Interior nodes
  live under one child subtree so freeing is a single `queue_free`.
- **No new save state:** specs are pure functions of seed — free far interiors,
  rebuild identically on re-approach.
- **Pop-in** is a feel risk → **flagged for the human to judge in flight**; radius
  + hysteresis are tunables. The dev-room specimen needs no LOD at all.

---

## 10. F4 — determinism (a save that names a seed names every room)

Seed hierarchy: `layout_seed` → `building_seed` (already
`layout_seed*131 + cell`) → `floor_seed` (`building_seed · P + k`).
`InteriorGenerator` is a pure function of `floor_seed` + inputs → **same interior
forever**, recomputed not stored. Like the greenery private-seed trick (v1.63), it
never draws from the `CityLayout` RNG stream, so existing cities stay
byte-identical — interiors land on top. No new save machinery; F4's portable-save
doctrine reaches every room for free.

---

## 11. Boundaries (designed *toward*, not built)

- **Sortie composition (P2):** program-per-floor and "which floors open" are
  *data*; a future composer (P2.3 garrison placement) overrides them. The seam
  exists; the composer is not built now.
- **Combat indoors (B.q1):** deferred, traversal-only. Collision is real and
  channels are natural patrol lines, so the geometry is **combat-ready** when B.q1
  arrives. No combat logic now. (Interiors move *delivery* in ways the 1v1 void
  harness cannot price — priced at the sortie layer later, per BALANCE.md; not a
  number to guess now.)

---

## 12. Implementation beats (checkpoint protocol — the human flies each)

Each beat: **build → verify headless (warnings = errors) → STOP, the human flies →
commit per-beat on master + a GAMEPLAY-DESIGN decision-log entry, no
Co-Authored-By.**

1. **`InteriorGenerator` + `BuildingProgram`, pure + headless check.** Data only,
   no rendering. `interior_gen_check.gd` asserts the §4 invariants + determinism.
   (Mirrors how `BuildingGenerator` landed first, v1.46–v1.47.)
2. **`InteriorBuilder` + `MenuFloorFrame` hook — one specimen furnished floor in
   the dev room** (office program, one district skin). Batched + collision.
   *Stop, fly.*
3. **Kit breadth + programs** (warehouse, atrium, server-farm, dock) + district
   palettes. *Fly variety.*
4. **`BuildingProgram` wired into `WorldBuilding`** — a whole furnished tower
   (the per-district vertical profile). *Fly the stack.*
5. **City-wide distance LOD + perf pass** (`build_interior`/`clear_interior`,
   `interior_lod_radius`, hysteresis; optional INTERIOR overlay). *Fly the
   furnished city; tune radius / pop-in.*
6. **The B2 lighting moment** — auto-exposure into `LookConfig` + neon wayfinding
   channels + darkness tuning. *Fly the drama.*

**Verify commands (Godot 4.7 `_console` exe):**
- Re-import: `--headless --import --path .`
- Boot a scene: `--headless --quit-after 12 --path .` (dev_map, city_map,
  menu_tower)
- Checks under `scripts/tests/`: the new `interior_gen_check.gd` + existing
  `menu_check`, `building_gen_check`, `world_building_check`, `city_layout_check`
  (all currently PASS) + `hover/combat/wave/missile`.

---

## 13. Open tuning questions (for flight, not for the agent to assert)

Feel-owned by the human, resolved in the checkpoints — the agent never asserts
feel:
- `channel_width` / `interior_fit_margin`: where "fits" becomes "feels good".
- `scatter_density`: cluttered-dense vs sparse-fast.
- `interior_lod_radius` + hysteresis: pop-in tolerance vs perf headroom.
- Auto-exposure adaptation speed: how dramatic the "gets darker inside" beat is.
