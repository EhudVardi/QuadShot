# B3 Interiors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn hollow open floors into seed-deterministic, flyable open-plan interiors — scattered greybox furniture over structural columns and keep-clear window channels, programmed by district and height.

**Architecture:** Two pure static generators (`BuildingProgram` → per-floor program list; `InteriorGenerator` → a floor's interior spec as plain data) feed one render hook: `MenuFloorFrame` builds the spec into a freeable "Interior" child subtree via `BoxBatcher`. `WorldBuilding` stamps specs per open floor and (later) drives distance LOD. One render path preserved; no new save state (interiors recompute from seed).

**Tech Stack:** Godot 4.7 stable (GDScript, static typing), `BoxMesh` + `BoxBatcher`, the `neon_structure`/`StandardMaterial3D` family. Headless verify only; **feel is the human's — the agent never asserts feel.**

**Spec:** [docs/superpowers/specs/2026-07-25-b3-interiors-design.md](../specs/2026-07-25-b3-interiors-design.md)

---

## Conventions for this plan (read once)

- **Godot exe (use the `_console` build):** `C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe`. Written `<godot>` below.
- **No magic numbers:** every tunable is a named `const` default or an `@export`/knob; the human tunes it in flight. Numbers shown are sensible **defaults**, not truths.
- **Static typing everywhere; `snake_case`; comments explain *why*.** Match the surrounding files.
- **Checkpoint protocol (handoff §11):** Beat 1 is fully agent-testable (a headless check). Beats 2–6 end at a **HUMAN FLIGHT CHECKPOINT** — build, verify headless (warnings = errors), commit *"built + headless-verified, pending flight,"* then **STOP**. The human flies; on approval, add a `GAMEPLAY-DESIGN.md` decision-log entry. An agent executor must not self-approve feel.
- **Commits:** per beat, on `master` (or the implementation worktree), **no `Co-Authored-By` trailer** (project rule).
- **Headless verify trio (run after every beat):**
  - `<godot> --headless --import --path .`
  - `<godot> --headless --quit-after 12 --path . scenes/dev_map.tscn` (and `scenes/city_map.tscn` from Beat 4)
  - `<godot> --headless -s scripts/tests/interior_gen_check.gd --path .` plus the existing `menu_check`, `building_gen_check`, `world_building_check`, `city_layout_check`.

---

## File Structure

| File | New/Mod | Responsibility |
|---|---|---|
| `scripts/environment/interior_generator.gd` | **new** | Pure static. A floor's interior spec: channels → columns → seeded scatter. Program kind-weights + extents. |
| `scripts/environment/building_program.gd` | **new** | Pure static. Per-district vertical program profile → per-floor program list. |
| `scripts/menu/interior_builder.gd` | **new** | Render helper. Expands an interior spec into a freeable "Interior" subtree (batched boxes + collision). The furniture kit lives here. |
| `scripts/tests/interior_gen_check.gd` | **new** | Headless check: determinism, flyability invariants, program profile. |
| `scripts/menu/menu_floor_frame.gd` | mod | `interior`/`district`/`interior_lod_managed` fields + `build_interior()`/`clear_interior()`; hook in `_build_open()`. |
| `scripts/menu/menu_building.gd` | mod | Thread `interior`/`district`/`interior_lod_managed` from the floor spec to the frame. |
| `scripts/environment/world_building.gd` | mod | `interiors_enabled`/`district`/`force_program`/`interior_lod`/knobs; stamp specs per open floor; drive LOD (Beat 5). |
| `scripts/environment/city_layout.gd` | mod | Set each building's `district` (from `_prop_style`) + enable interiors (Beat 4). |
| `scenes/dev_map.tscn` | mod | One furnished specimen `WorldBuilding` (Beat 2). |
| `resources/look_config.gd`, `scripts/environment/look_controller.gd` | mod | Auto-exposure group + apply (Beat 6). |

---

## Beat 1 — The pure generators + headless check (TDD, agent-verifiable)

Data only, no rendering. Mirrors how `BuildingGenerator` landed first (v1.46–47).

### Task 1.1 — `InteriorGenerator` skeleton + constants

**Files:** Create `scripts/environment/interior_generator.gd`

- [ ] **Step 1: Write the file with ids, knobs, and the `generate` shell.**

```gdscript
class_name InteriorGenerator
extends RefCounted

## Seeded, deterministic OPEN-PLAN interior for one floor (B3, spec §4). Pure:
## (program, seed, footprint, height, open_sides, knobs) → a plain-data interior
## spec InteriorBuilder renders. Same seed = same interior forever (F4). Mirrors
## theater_generator's purity. Layout order: keep-clear channels between every
## open window (flyability), a sparse structural column grid (nothing floats),
## then rejection-sampled furniture scatter.

## Program archetype ids (BuildingProgram assigns; this fills).
const PROGRAM_LOBBY_ATRIUM: StringName = &"lobby_atrium"
const PROGRAM_WAREHOUSE: StringName = &"warehouse"
const PROGRAM_OFFICE: StringName = &"office"
const PROGRAM_ATRIUM: StringName = &"atrium"
const PROGRAM_SERVER_FARM: StringName = &"server_farm"
const PROGRAM_DOCK: StringName = &"dock"

## Piece kinds — InteriorBuilder expands each into greybox boxes.
const KIND_DESK: StringName = &"desk"
const KIND_DESK_CLUSTER: StringName = &"desk_cluster"
const KIND_CUBICLE: StringName = &"cubicle"
const KIND_CABINET: StringName = &"cabinet"
const KIND_SHELVING: StringName = &"shelving"
const KIND_COUNTER: StringName = &"counter"
const KIND_RACKING: StringName = &"racking"
const KIND_PALLET: StringName = &"pallet"
const KIND_CRATE: StringName = &"crate"
const KIND_PLANTER: StringName = &"planter"
const KIND_BENCH: StringName = &"bench"
const KIND_FEATURE: StringName = &"feature"
const KIND_SERVER_RACK: StringName = &"server_rack"
const KIND_CONTAINER: StringName = &"container"

## Matches MenuFloorFrame.WALL (interior half-extent derivation) and the scaffold
## column so interior columns line up with the under-construction discipline.
const WALL: float = 0.4
const COLUMN_W: float = 0.4

## Tuning surface (spec §7). Defaults generous-first; the human tunes down.
const DEFAULT_KNOBS: Dictionary = {
	"channel_width": 2.4,        # the aisle you fly
	"min_clearance": 0.9,        # Poisson spacing between pieces
	"scatter_density": 0.018,    # pieces per m^2 of floor
	"column_spacing": 8.0,       # structural cadence
	"interior_fit_margin": 0.6,  # extra keep-clear at window mouths
	"scatter_attempts": 24,      # rejection tries per piece
}


## Returns {program, columns:Array[Vector2], pieces:Array[Dictionary],
## channels:Array[Dictionary], knobs}. piece = {kind, pos:Vector3, yaw, extent:Vector2};
## channel = {a:Vector2, b:Vector2, width}. All XZ local; origin = floor centre.
static func generate(program: StringName, floor_seed: int, footprint: float,
		interior_height: float, open_sides: Array, knobs: Dictionary = {}) -> Dictionary:
	var k: Dictionary = DEFAULT_KNOBS.duplicate()
	for key: String in knobs:
		k[key] = knobs[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var px: float = footprint * 0.5 - WALL
	var windows: Array = _window_centers(open_sides, px)
	var channels: Array = _build_channels(windows, k["channel_width"])
	var columns: Array = _build_columns(px, k, channels)
	var pieces: Array = _scatter(program, rng, px, k, channels, columns, windows)
	return {"program": program, "columns": columns, "pieces": pieces,
			"channels": channels, "knobs": k}
```

- [ ] **Step 2: Parse check.** Run: `<godot> --headless --check-only -s scripts/environment/interior_generator.gd --path .` → Expected: no errors. (Will warn about undefined `_window_centers` etc. until Task 1.2 — that is fine; fix in 1.2 before the full check.)

### Task 1.2 — Channels, columns, scatter, geometry helpers

**Files:** Modify `scripts/environment/interior_generator.gd`

- [ ] **Step 1: Append the layout functions.**

```gdscript
## The four side-window centres (SIDES order: front +Z, back -Z, right +X, left -X),
## keeping only OPEN sides. Empty open_sides = all four open (standalone default).
static func _window_centers(open_sides: Array, px: float) -> Array:
	var all: Array = [Vector2(0.0, px), Vector2(0.0, -px), Vector2(px, 0.0), Vector2(-px, 0.0)]
	var out: Array = []
	for i: int in all.size():
		if open_sides.is_empty() or (i < open_sides.size() and bool(open_sides[i])):
			out.append(all[i])
	return out


## A clear tube from every open window to the hub (origin), so any open side reaches
## any other (spec §4, Fold 2). With one open side, its single channel is enough.
static func _build_channels(windows: Array, width: float) -> Array:
	var channels: Array = []
	for c: Vector2 in windows:
		channels.append({"a": c, "b": Vector2.ZERO, "width": width})
	return channels


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	var t: float = 0.0
	if len2 > 0.0001:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _in_channel(p: Vector2, channels: Array, pad: float) -> bool:
	for ch: Dictionary in channels:
		if _dist_to_segment(p, ch["a"], ch["b"]) < ch["width"] * 0.5 + pad:
			return true
	return false


## A sparse interior column grid that holds the slab (spec §4, Fold 1). Skips
## columns falling in a channel; the perimeter walls carry the edge load.
static func _build_columns(px: float, k: Dictionary, channels: Array) -> Array:
	var cols: Array = []
	var spacing: float = k["column_spacing"]
	var n: int = maxi(1, int(floor(2.0 * px / spacing)))
	for ix: int in n:
		for iz: int in n:
			var gx: float = -px + spacing * (float(ix) + 1.0)
			var gz: float = -px + spacing * (float(iz) + 1.0)
			if absf(gx) > px - COLUMN_W or absf(gz) > px - COLUMN_W:
				continue
			var p := Vector2(gx, gz)
			if _in_channel(p, channels, COLUMN_W * 0.5):
				continue
			cols.append(p)
	return cols


## Rejection-sampled furniture: keep out of channels, window mouths, columns, and
## other pieces (min_clearance). Deterministic via the passed rng.
static func _scatter(program: StringName, rng: RandomNumberGenerator, px: float,
		k: Dictionary, channels: Array, columns: Array, windows: Array) -> Array:
	var pieces: Array = []
	var weights: Dictionary = _kind_weights(program)
	if weights.is_empty():
		return pieces
	var area: float = (2.0 * px) * (2.0 * px)
	var target: int = int(round(k["scatter_density"] * area * _program_density(program)))
	for _i: int in target:
		var kind: StringName = _weighted_pick(weights, rng)
		var extent: Vector2 = _kind_extent(kind, rng)
		var yaw: float = 0.0 if rng.randf() < 0.5 else deg_to_rad(90.0)
		var oriented: Vector2 = extent if yaw == 0.0 else Vector2(extent.y, extent.x)
		var half: Vector2 = oriented * 0.5
		for _a: int in int(k["scatter_attempts"]):
			var pos := Vector2(rng.randf_range(-px + half.x, px - half.x),
					rng.randf_range(-px + half.y, px - half.y))
			if _rejected(pos, half, k, channels, columns, pieces, windows):
				continue
			pieces.append({"kind": kind, "pos": Vector3(pos.x, 0.0, pos.y),
					"yaw": yaw, "extent": extent})
			break
	return pieces


static func _rejected(pos: Vector2, half: Vector2, k: Dictionary, channels: Array,
		columns: Array, pieces: Array, windows: Array) -> bool:
	var r: float = half.length()
	var clear: float = k["min_clearance"]
	if _in_channel(pos, channels, clear):
		return true
	var mouth: float = k["channel_width"] * 0.5 + k["interior_fit_margin"] + r
	for wc: Vector2 in windows:
		if pos.distance_to(wc) < mouth:
			return true
	for col: Vector2 in columns:
		if pos.distance_to(col) < COLUMN_W * 0.5 + clear + r:
			return true
	for pc: Dictionary in pieces:
		var pr: float = (pc["extent"] as Vector2).length() * 0.5
		if pos.distance_to(Vector2(pc["pos"].x, pc["pos"].z)) < r + pr + clear:
			return true
	return false
```

- [ ] **Step 2: Append the program tables** (kind weights, per-kind extents, density). These are the "variety by combination" palettes; sizes are defaults.

```gdscript
## Relative furniture mix per program (spec §5/§6). Atrium/lobby are sparse.
static func _kind_weights(program: StringName) -> Dictionary:
	match program:
		PROGRAM_OFFICE:
			return {KIND_DESK_CLUSTER: 4.0, KIND_CUBICLE: 3.0, KIND_DESK: 2.0,
					KIND_CABINET: 2.0, KIND_SHELVING: 1.0}
		PROGRAM_WAREHOUSE:
			return {KIND_RACKING: 5.0, KIND_PALLET: 2.0, KIND_CRATE: 2.0}
		PROGRAM_SERVER_FARM:
			return {KIND_SERVER_RACK: 6.0, KIND_CABINET: 1.0}
		PROGRAM_DOCK:
			return {KIND_CONTAINER: 4.0, KIND_CRATE: 3.0, KIND_PALLET: 2.0}
		PROGRAM_ATRIUM, PROGRAM_LOBBY_ATRIUM:
			return {KIND_PLANTER: 3.0, KIND_BENCH: 3.0, KIND_FEATURE: 1.0,
					KIND_COUNTER: 1.0}
		_:
			return {}


## Program clutter multiplier — warehouses/servers pack tight, atria breathe.
static func _program_density(program: StringName) -> float:
	match program:
		PROGRAM_WAREHOUSE, PROGRAM_SERVER_FARM: return 1.3
		PROGRAM_OFFICE, PROGRAM_DOCK: return 1.0
		PROGRAM_ATRIUM, PROGRAM_LOBBY_ATRIUM: return 0.45
		_: return 1.0


## Footprint (XZ) a kind reserves; the builder composes boxes within it. Jittered.
static func _kind_extent(kind: StringName, rng: RandomNumberGenerator) -> Vector2:
	match kind:
		KIND_DESK: return Vector2(1.6, 0.8) * rng.randf_range(0.9, 1.1)
		KIND_DESK_CLUSTER: return Vector2(3.4, 2.6) * rng.randf_range(0.9, 1.1)
		KIND_CUBICLE: return Vector2(2.4, 2.4) * rng.randf_range(0.9, 1.1)
		KIND_CABINET: return Vector2(1.0, 0.6) * rng.randf_range(0.9, 1.1)
		KIND_SHELVING: return Vector2(2.6, 0.6) * rng.randf_range(0.9, 1.2)
		KIND_COUNTER: return Vector2(3.0, 1.0) * rng.randf_range(0.9, 1.1)
		KIND_RACKING: return Vector2(6.0, 1.2) * rng.randf_range(0.9, 1.15)
		KIND_PALLET: return Vector2(1.2, 1.2) * rng.randf_range(0.9, 1.2)
		KIND_CRATE: return Vector2(1.0, 1.0) * rng.randf_range(0.8, 1.3)
		KIND_PLANTER: return Vector2(1.6, 1.6) * rng.randf_range(0.9, 1.2)
		KIND_BENCH: return Vector2(2.0, 0.6) * rng.randf_range(0.9, 1.1)
		KIND_FEATURE: return Vector2(3.0, 3.0) * rng.randf_range(0.9, 1.2)
		KIND_SERVER_RACK: return Vector2(2.4, 1.0) * rng.randf_range(0.9, 1.1)
		KIND_CONTAINER: return Vector2(4.0, 2.0) * rng.randf_range(0.9, 1.1)
		_: return Vector2(1.0, 1.0)


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total: float = 0.0
	for w: float in weights.values():
		total += w
	var roll: float = rng.randf() * total
	for kind: StringName in weights:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return weights.keys()[weights.size() - 1]
```

- [ ] **Step 3: Parse check.** Run: `<godot> --headless --check-only -s scripts/environment/interior_generator.gd --path .` → Expected: no errors, no warnings.

### Task 1.3 — `BuildingProgram` (per-district vertical profile)

**Files:** Create `scripts/environment/building_program.gd`

- [ ] **Step 1: Write the file.**

```gdscript
class_name BuildingProgram
extends RefCounted

## Per-district vertical PROGRAM PROFILE (spec §5): height fraction → program.
## District RESTRUCTURES the profile (Q3), so each district stacks different
## programs. Pure + deterministic per building_seed. district ids equal
## CityLayout.PropStyle values.

const URBAN: int = 0
const NATURAL: int = 1
const CYBER: int = 2

## Ordered bands [top_fraction, program]: a floor at height fraction f (0 ground →
## 1 top) takes the first band whose top_fraction >= f. Last band catches 1.0.
const PROFILES: Dictionary = {
	NATURAL: [[0.06, InteriorGenerator.PROGRAM_LOBBY_ATRIUM],
			[0.30, InteriorGenerator.PROGRAM_WAREHOUSE],
			[0.90, InteriorGenerator.PROGRAM_OFFICE],
			[1.01, InteriorGenerator.PROGRAM_ATRIUM]],
	CYBER: [[0.06, InteriorGenerator.PROGRAM_LOBBY_ATRIUM],
			[0.85, InteriorGenerator.PROGRAM_SERVER_FARM],
			[1.01, InteriorGenerator.PROGRAM_ATRIUM]],
	URBAN: [[0.12, InteriorGenerator.PROGRAM_DOCK],
			[1.01, InteriorGenerator.PROGRAM_WAREHOUSE]],
}

## Seeded jitter on band boundaries so towers of one district still vary.
const BAND_JITTER: float = 0.05


## Bottom→top program list, one per floor. Short buildings collapse to base bands.
static func programs_for(district: int, building_seed: int, floor_count: int) -> Array:
	var profile: Array = PROFILES.get(district, PROFILES[NATURAL])
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed * 31 + 7
	# Jittered but monotonic boundaries.
	var bounds: Array = []
	var prev: float = 0.0
	for band: Array in profile:
		var b: float = maxf(prev, clampf(band[0] + rng.randf_range(-BAND_JITTER, BAND_JITTER), 0.0, 1.01))
		bounds.append(b)
		prev = b
	var out: Array = []
	for i: int in floor_count:
		var f: float = 0.0 if floor_count <= 1 else float(i) / float(floor_count - 1)
		var chosen: StringName = profile[profile.size() - 1][1]
		for bi: int in profile.size():
			if f <= bounds[bi]:
				chosen = profile[bi][1]
				break
		out.append(chosen)
	return out
```

- [ ] **Step 2: Parse check.** Run: `<godot> --headless --check-only -s scripts/environment/building_program.gd --path .` → Expected: no errors.

### Task 1.4 — Headless check (the invariants)

**Files:** Create `scripts/tests/interior_gen_check.gd`

- [ ] **Step 1: Write the check** (pure, `_initialize()` style like `building_gen_check`).

```gdscript
extends SceneTree

## Headless check for the interior generators (B3, spec §4). Pure functions, so no
## scene: assert determinism + the flyability invariants + the program profile,
## then quit.
##
## Run: <godot> --headless -s scripts/tests/interior_gen_check.gd --path .

const FP: float = 24.0
const H: float = 4.0


func _initialize() -> void:
	_check_interior()
	_check_program()
	print("[interior_gen_check] PASS")
	quit(0)


func _fail(message: String) -> void:
	print("[interior_gen_check] FAIL: %s" % message)
	quit(1)


func _check_interior() -> void:
	var programs: Array = [InteriorGenerator.PROGRAM_OFFICE,
			InteriorGenerator.PROGRAM_WAREHOUSE, InteriorGenerator.PROGRAM_SERVER_FARM,
			InteriorGenerator.PROGRAM_DOCK, InteriorGenerator.PROGRAM_ATRIUM,
			InteriorGenerator.PROGRAM_LOBBY_ATRIUM]
	var side_masks: Array = [[], [true, false, false, false],
			[true, false, true, false], [true, true, true, true]]
	for prog: StringName in programs:
		for mask: Array in side_masks:
			for s: int in range(1, 6):
				_check_spec(prog, s * 17 + 3, mask)


func _check_spec(program: StringName, seed_value: int, mask: Array) -> void:
	var a: Dictionary = InteriorGenerator.generate(program, seed_value, FP, H, mask)
	var b: Dictionary = InteriorGenerator.generate(program, seed_value, FP, H, mask)
	if str(a) != str(b):
		return _fail("same seed produced different interiors (%s)" % program)
	var k: Dictionary = a["knobs"]
	var half_w: float = k["channel_width"] * 0.5
	# Channels join every open window to the hub.
	var open_count: int = mask.size() if not mask.is_empty() else 4
	if mask.is_empty():
		open_count = 4
	else:
		open_count = mask.count(true)
	if a["channels"].size() != open_count:
		return _fail("expected %d channels, got %d" % [open_count, a["channels"].size()])
	# No column or piece intrudes the clear channel tube (flyability).
	for c: Vector2 in a["columns"]:
		if _in_channel(c, a["channels"]) < half_w:
			return _fail("a column sits in a flight channel (%s)" % program)
	for p: Dictionary in a["pieces"]:
		var ctr := Vector2(p["pos"].x, p["pos"].z)
		if _in_channel(ctr, a["channels"]) < half_w:
			return _fail("a piece sits in a flight channel (%s)" % program)
	# Min-clearance holds between pieces.
	var pieces: Array = a["pieces"]
	for i: int in pieces.size():
		for j: int in range(i + 1, pieces.size()):
			var ci := Vector2(pieces[i]["pos"].x, pieces[i]["pos"].z)
			var cj := Vector2(pieces[j]["pos"].x, pieces[j]["pos"].z)
			var ri: float = (pieces[i]["extent"] as Vector2).length() * 0.5
			var rj: float = (pieces[j]["extent"] as Vector2).length() * 0.5
			if ci.distance_to(cj) < ri + rj:
				return _fail("two pieces overlap (%s seed %d)" % [program, seed_value])


## Nearest-channel distance for a point (mirrors the generator's segment test).
func _in_channel(p: Vector2, channels: Array) -> float:
	var best: float = 1e9
	for ch: Dictionary in channels:
		var a: Vector2 = ch["a"]
		var b: Vector2 = ch["b"]
		var ab: Vector2 = b - a
		var t: float = 0.0
		var len2: float = ab.length_squared()
		if len2 > 0.0001:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _check_program() -> void:
	# Determinism + ground floor is a lobby-atrium + district changes the mix.
	var nat_a: Array = BuildingProgram.programs_for(BuildingProgram.NATURAL, 4242, 20)
	var nat_b: Array = BuildingProgram.programs_for(BuildingProgram.NATURAL, 4242, 20)
	if str(nat_a) != str(nat_b):
		return _fail("same seed gave a different program profile")
	if nat_a[0] != InteriorGenerator.PROGRAM_LOBBY_ATRIUM:
		return _fail("ground floor should be a lobby-atrium, got %s" % nat_a[0])
	var cyb: Array = BuildingProgram.programs_for(BuildingProgram.CYBER, 4242, 20)
	if not cyb.has(InteriorGenerator.PROGRAM_SERVER_FARM):
		return _fail("a tall cyber tower should stack server-farm floors")
	if str(cyb) == str(nat_a):
		return _fail("district did not restructure the profile (cyber == natural)")
	# Short buildings collapse to base bands (no office/atrium in a 3-floor tower).
	var short: Array = BuildingProgram.programs_for(BuildingProgram.NATURAL, 9, 3)
	if short.has(InteriorGenerator.PROGRAM_ATRIUM) and short.size() == 3:
		return _fail("a 3-floor natural building should not reach the top atrium band")
```

- [ ] **Step 2: Run the check — expect PASS.**

Run: `<godot> --headless -s scripts/tests/interior_gen_check.gd --path .`
Expected: `[interior_gen_check] PASS`. If a flyability assert fires, the knobs (channel_width vs window-mouth math) need reconciling — fix the generator, not the check.

- [ ] **Step 3: Regression — the existing suite still passes.**

Run each: `building_gen_check`, `menu_check`, `world_building_check`, `city_layout_check` → all `PASS`. Then `<godot> --headless --import --path .` → clean.

- [ ] **Step 4: Commit.**

```bash
git add scripts/environment/interior_generator.gd scripts/environment/building_program.gd scripts/tests/interior_gen_check.gd
git commit -m "B3 interiors: pure generators + headless check (data only, no render)"
```

---

## Beat 2 — Render hook + one furnished specimen (HUMAN FLIGHT CHECKPOINT)

### Task 2.1 — `InteriorBuilder` with the office kit

**Files:** Create `scripts/menu/interior_builder.gd`

- [ ] **Step 1: Write the builder** (subtree + palette + `_box` + office `_emit` cases + fallback).

```gdscript
class_name InteriorBuilder
extends RefCounted

## Renders an InteriorGenerator spec into a fresh "Interior" child subtree under a
## MenuFloorFrame (spec §3/§6). Visual boxes batch by material (one BoxBatcher);
## collision is per box. Returned root is freeable for distance LOD. The furniture
## KIT lives here: each kind → greybox boxes. Variety is combination, not assets.

const COLUMN_W: float = InteriorGenerator.COLUMN_W


static func build(spec: Dictionary, district: int, parent: Node3D,
		interior_height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior"
	var body := StaticBody3D.new()
	root.add_child(body)
	var batch := BoxBatcher.new()
	var mats: Dictionary = _palette(district)
	for c: Vector2 in spec.get("columns", []):
		_box(batch, body, Vector3(COLUMN_W, interior_height, COLUMN_W),
				Vector3(c.x, interior_height * 0.5, c.y), 0.0, mats["structure"])
	for p: Dictionary in spec.get("pieces", []):
		_emit(batch, body, p, mats)
	batch.commit_into(body)
	parent.add_child(root)
	return root


## Interior palette by district — reuses CityLayout's zonal colours so inside and
## outside agree. Interior surfaces stay dark; accents glow (bloom > 1.0).
static func _palette(district: int) -> Dictionary:
	var structure := StandardMaterial3D.new()
	structure.albedo_color = MenuFloorFrame.INTERIOR_ALBEDO * 1.6
	structure.roughness = 0.9
	var prop := StandardMaterial3D.new()
	prop.roughness = 0.9
	var accent := StandardMaterial3D.new()
	accent.emission_enabled = true
	match district:
		BuildingProgram.CYBER:
			prop.albedo_color = CityLayout.CYBER_BASE_COLOR
			accent.albedo_color = CityLayout.CYBER_GLOW_COLOR
			accent.emission = CityLayout.CYBER_GLOW_COLOR
			accent.emission_energy_multiplier = CityLayout.CYBER_GLOW_ENERGY
		BuildingProgram.URBAN:
			prop.albedo_color = CityLayout.HARDSCAPE_COLOR
			accent.albedo_color = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission = CityLayout.HARDSCAPE_SIGN_COLOR
			accent.emission_energy_multiplier = CityLayout.HARDSCAPE_SIGN_ENERGY
		_:
			prop.albedo_color = CityLayout.PLANTER_COLOR
			accent.albedo_color = CityLayout.TREE_LEAF_COLOR
			accent.emission = CityLayout.TREE_LEAF_COLOR
			accent.emission_energy_multiplier = 1.2
	return {"structure": structure, "prop": prop, "accent": accent}


## One box: batched visual + a per-box collision shape under `body`.
static func _box(batch: BoxBatcher, body: StaticBody3D, size: Vector3, at: Vector3,
		yaw: float, mat: Material) -> void:
	batch.add(size, at, mat, yaw)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	col.rotation = Vector3(0.0, yaw, 0.0)
	body.add_child(col)


## Expand a piece into boxes. Office kit here; Beat 3 adds the rest. Positions are
## local to `at` and rotated by `yaw` via the box's own yaw (composites stay simple
## and axis-local — good enough at greybox fidelity).
static func _emit(batch: BoxBatcher, body: StaticBody3D, p: Dictionary,
		mats: Dictionary) -> void:
	var kind: StringName = p["kind"]
	var at: Vector3 = p["pos"]
	var yaw: float = p["yaw"]
	var e: Vector2 = p["extent"]
	match kind:
		InteriorGenerator.KIND_DESK:
			_box(batch, body, Vector3(e.x, 0.75, e.y), at + Vector3(0, 0.375, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_DESK_CLUSTER:
			var dw: float = e.x * 0.45
			var dd: float = e.y * 0.42
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(batch, body, Vector3(dw, 0.75, dd),
							at + Vector3(sx * e.x * 0.25, 0.375, sz * e.y * 0.26), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.9, 1.2, 0.1), at + Vector3(0, 0.6, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CUBICLE:
			_box(batch, body, Vector3(e.x, 1.3, 0.1), at + Vector3(0, 0.65, e.y * 0.5), yaw, mats["prop"])
			_box(batch, body, Vector3(0.1, 1.3, e.y), at + Vector3(e.x * 0.5, 0.65, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.8, 0.75, e.y * 0.5), at + Vector3(0, 0.375, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CABINET:
			_box(batch, body, Vector3(e.x, 1.4, e.y), at + Vector3(0, 0.7, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_SHELVING:
			_box(batch, body, Vector3(e.x, 2.2, e.y), at + Vector3(0, 1.1, 0), yaw, mats["prop"])
		_:
			# Fallback until Beat 3: a waist-high block the size of the reserved footprint.
			_box(batch, body, Vector3(e.x, 0.9, e.y), at + Vector3(0, 0.45, 0), yaw, mats["prop"])
```

- [ ] **Step 2: Parse check.** Run: `<godot> --headless --check-only -s scripts/menu/interior_builder.gd --path .` → Expected: no errors.

### Task 2.2 — `MenuFloorFrame` hook

**Files:** Modify `scripts/menu/menu_floor_frame.gd`

- [ ] **Step 1: Add exports** (after the existing `@export var open_sides`/`interior_height` block, ~line 96):

```gdscript
## Interior (B3): the InteriorGenerator spec + district for palette. Empty = no
## interior (menu floors, sealed/UC floors). When interior_lod_managed is true,
## WorldBuilding drives build_interior()/clear_interior() by distance (city LOD);
## when false, the interior builds at _ready (menu / dev-room specimen).
@export var interior: Dictionary = {}
@export var district: int = -1
@export var interior_lod_managed: bool = false
```

- [ ] **Step 2: Add the field** near `_batch` (~line 104):

```gdscript
var _interior_root: Node3D = null
```

- [ ] **Step 3: Hook the build** at the end of `_build_open()` (after the `if leaf_id != &"":` menu-furniture block):

```gdscript
	# B3 interior: build now unless the city LOD manager will drive it.
	if not interior.is_empty() and not interior_lod_managed:
		build_interior()
```

- [ ] **Step 4: Add the methods** (near `set_selected`):

```gdscript
func has_interior() -> bool:
	return not interior.is_empty()


## Build the interior subtree once (idempotent). Used both at _ready and by the
## city LOD manager on approach.
func build_interior() -> void:
	if _interior_root != null or interior.is_empty():
		return
	_interior_root = InteriorBuilder.build(interior, district, self, interior_height)


## Free the interior subtree (LOD, out of range). Deterministic to rebuild.
func clear_interior() -> void:
	if _interior_root != null:
		_interior_root.queue_free()
		_interior_root = null
```

- [ ] **Step 5: Parse check.** Run: `<godot> --headless --check-only -s scripts/menu/menu_floor_frame.gd --path .` → Expected: no errors.

### Task 2.3 — Thread through `MenuBuilding`

**Files:** Modify `scripts/menu/menu_building.gd`

- [ ] **Step 1: Add three lines** in the frame-stamping loop (after `frame.interior_height = spec.get(...)`, ~line 90):

```gdscript
		frame.interior = spec.get("interior", {})
		frame.district = spec.get("district", -1)
		frame.interior_lod_managed = spec.get("interior_lod_managed", false)
```

- [ ] **Step 2: Parse check.** Run: `<godot> --headless --check-only -s scripts/menu/menu_building.gd --path .` → Expected: no errors.

### Task 2.4 — `WorldBuilding` stamps specs (specimen mode)

**Files:** Modify `scripts/environment/world_building.gd`

- [ ] **Step 1: Add exports** (after `open_sides`, ~line 38):

```gdscript
## Interiors (B3): fill open floors with generated open-plan interiors.
@export var interiors_enabled: bool = false
## District (CityLayout.PropStyle: 0 urban / 1 natural / 2 cyber) — palette + profile.
@export var district: int = BuildingProgram.NATURAL
## Testbed override: force one program on every open floor (empty = use the
## per-district vertical profile). Wired out in Beat 4.
@export var force_program: StringName = &""
## When true, frames defer interior build to this node's distance LOD (Beat 5).
@export var interior_lod: bool = false
@export var interior_knobs: Dictionary = {}
```

- [ ] **Step 2: Stamp interior specs** inside the existing per-floor loop in `_ready()` — extend it (the loop that sets `spec["footprint"]` etc.). Full replacement of that loop:

```gdscript
	var programs: Array = []
	if interiors_enabled:
		programs = BuildingProgram.programs_for(district, building_seed, floors.size())
	for k: int in floors.size():
		var spec: Dictionary = floors[k]
		spec["footprint"] = _footprint_at(k, floors.size())
		spec["cross_windows"] = true
		spec["interior_height"] = interior_height
		if not open_sides.is_empty():
			spec["open_sides"] = open_sides
		# Interiors only on OPEN floors (sealed/UC unchanged).
		if interiors_enabled and spec.get("state", MenuFloorFrame.STATE_OPEN) == MenuFloorFrame.STATE_OPEN:
			var prog: StringName = force_program if force_program != &"" else programs[k]
			var fseed: int = building_seed * 1000003 + k
			spec["interior"] = InteriorGenerator.generate(prog, fseed,
					spec["footprint"], interior_height, spec.get("open_sides", []), interior_knobs)
			spec["district"] = district
			spec["interior_lod_managed"] = interior_lod
```

- [ ] **Step 3: Parse + world check.** Run: `<godot> --headless --check-only -s scripts/environment/world_building.gd --path .` then `<godot> --headless -s scripts/tests/world_building_check.gd --path .` → Expected: no errors, `PASS`.

### Task 2.5 — The dev-room specimen

**Files:** Modify `scenes/dev_map.tscn`

- [ ] **Step 1: Read the scene** to find how a `WorldBuilding` specimen is declared (its `ext_resource` script id and an existing instance to copy) and a clear ground spot away from the existing city.

Run: open `scenes/dev_map.tscn`; note the `[ext_resource ... path="res://scripts/environment/world_building.gd" id=...]` line (add one if absent).

- [ ] **Step 2: Add a furnished specimen node** — a short building so no LOD is needed. Use the scene's WorldBuilding script `ext_resource` id (shown as `WB` below) and place it on open ground:

```
[node name="InteriorSpecimen" type="Node3D" parent="." groups=[]]
script = ExtResource("WB")
building_seed = 777
target_floors = 6
open_floors = 6
footprint = 26.0
interior_height = 4.0
interiors_enabled = true
force_program = &"office"
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 60, 0, 20)
```

(Adjust the `transform` origin to a clear spot. `open_floors = 6` makes every floor enterable so the specimen is all-interior.)

- [ ] **Step 3: Import + boot.**

Run: `<godot> --headless --import --path .` then `<godot> --headless --quit-after 12 --path . scenes/dev_map.tscn`
Expected: boots clean, no errors/warnings.

- [ ] **Step 4: Commit (pending flight).**

```bash
git add scripts/menu/interior_builder.gd scripts/menu/menu_floor_frame.gd scripts/menu/menu_building.gd scripts/environment/world_building.gd scenes/dev_map.tscn
git commit -m "B3 interiors: render hook + office kit + dev-room specimen (built + headless-verified, pending flight)"
```

- [ ] **Step 5: 🛑 HUMAN FLIGHT CHECKPOINT.** Stop. Ask the human to fly `scenes/dev_map.tscn`, thread the specimen's windows, and judge: aisle feel, clutter density, that you can always reach an exit window, that nothing floats. Map feedback → knob changes (`channel_width`, `scatter_density`, `min_clearance`, kit box dims). On approval, add a `GAMEPLAY-DESIGN.md` decision-log entry (next `v1.6x`).

---

## Beat 3 — Kit breadth + all programs (HUMAN FLIGHT CHECKPOINT)

Fill the non-office kinds so warehouse / atrium / server-farm / dock read as themselves. Generator tables already list them (Beat 1); this beat renders them.

### Task 3.1 — Remaining `_emit` cases

**Files:** Modify `scripts/menu/interior_builder.gd`

- [ ] **Step 1: Add cases** before the `_:` fallback in `_emit()` (concrete defaults; tune in flight):

```gdscript
		InteriorGenerator.KIND_COUNTER:
			_box(batch, body, Vector3(e.x, 1.1, e.y), at + Vector3(0, 0.55, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x, 0.12, e.y), at + Vector3(0, 1.12, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_RACKING:
			# Tall shelving run — the warehouse aisle-former. Uprights + shelves.
			_box(batch, body, Vector3(e.x, 3.0, e.y), at + Vector3(0, 1.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PALLET:
			_box(batch, body, Vector3(e.x, 0.2, e.y), at + Vector3(0, 0.1, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.8, 1.0, e.y * 0.8), at + Vector3(0, 0.7, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CRATE:
			var ch: float = e.x * 0.9
			_box(batch, body, Vector3(e.x, ch, e.y), at + Vector3(0, ch * 0.5, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_CONTAINER:
			_box(batch, body, Vector3(e.x, 2.4, e.y), at + Vector3(0, 1.2, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_PLANTER:
			_box(batch, body, Vector3(e.x, 0.5, e.y), at + Vector3(0, 0.25, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.7, 0.8, e.y * 0.7), at + Vector3(0, 0.9, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_BENCH:
			_box(batch, body, Vector3(e.x, 0.45, e.y), at + Vector3(0, 0.225, 0), yaw, mats["prop"])
		InteriorGenerator.KIND_FEATURE:
			# Atrium centrepiece — a tapered glowing stack (never on the hub; placed by scatter).
			_box(batch, body, Vector3(e.x, 0.4, e.y), at + Vector3(0, 0.2, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.5, 2.2, e.y * 0.5), at + Vector3(0, 1.3, 0), yaw, mats["accent"])
		InteriorGenerator.KIND_SERVER_RACK:
			_box(batch, body, Vector3(e.x, 2.2, e.y), at + Vector3(0, 1.1, 0), yaw, mats["prop"])
			_box(batch, body, Vector3(e.x * 0.9, 2.0, 0.06), at + Vector3(0, 1.1, e.y * 0.5), yaw, mats["accent"])
```

- [ ] **Step 2: Parse check + regression check.** Run: `<godot> --headless --check-only -s scripts/menu/interior_builder.gd --path .`; then `<godot> --headless -s scripts/tests/interior_gen_check.gd --path .` → still `PASS` (the check already sweeps all programs).

### Task 3.2 — Cycle programs on the specimen

**Files:** Modify `scenes/dev_map.tscn` (temporary tuning aid)

- [ ] **Step 1:** Add 3–4 more short specimens (or change `force_program`) so one of each program stands side by side: `&"warehouse"`, `&"atrium"`, `&"server_farm"`, `&"dock"` — each on a clear spot, `district` matching the program's home zone (cyber for server_farm, urban for dock/warehouse, natural for atrium/office).

- [ ] **Step 2: Import + boot** (`--import`, then `--quit-after 12` on `dev_map.tscn`) → clean.

- [ ] **Step 3: Commit (pending flight).**

```bash
git add scripts/menu/interior_builder.gd scenes/dev_map.tscn
git commit -m "B3 interiors: full furniture kit — warehouse/atrium/server/dock (built + headless-verified, pending flight)"
```

- [ ] **Step 4: 🛑 HUMAN FLIGHT CHECKPOINT.** Human flies each program specimen: does a warehouse read as speed-aisles, an atrium as a breather, a server-farm as tight+bright? Tune extents/box dims/weights. Decision-log entry on approval.

---

## Beat 4 — Wire the vertical profile into the city (HUMAN FLIGHT CHECKPOINT)

Replace `force_program` with the real per-district profile, and let `CityLayout` furnish its buildings.

### Task 4.1 — `CityLayout` enables + districts its buildings

**Files:** Modify `scripts/environment/city_layout.gd`

- [ ] **Step 1: Add an export** (near the other interior-free knobs):

```gdscript
## Interiors (B3): furnish buildings' open floors. Off by default so existing
## city checks/perf are unchanged until flown.
@export var interiors_enabled: bool = false
```

- [ ] **Step 2: Set district + enable** in `_spawn_building()` (after `building.open_sides = _facing_open_sides(...)`, before `add_child`):

```gdscript
	if interiors_enabled:
		building.interiors_enabled = true
		building.district = _prop_style(c, r)   # inside matches the block's zone
		building.interior_lod = true             # city drives distance LOD (Beat 5)
```

- [ ] **Step 3: Import + city checks.** Run `<godot> --headless -s scripts/tests/city_layout_check.gd --path .` (`interiors_enabled` defaults off → unchanged, `PASS`).

### Task 4.2 — Turn interiors on for the dev-room city + city_map

**Files:** Modify `scenes/dev_map.tscn` and/or `scenes/city_map.tscn`

- [ ] **Step 1:** Set `interiors_enabled = true` on the `CityLayout` node in `scenes/city_map.tscn` (and the dev-room's `CityLayout` if desired). Remove the temporary `force_program` specimens from Beat 3 (keep one office specimen if handy).

> **Note on interior_lod_managed:** with `interior_lod = true`, frames will NOT self-build (they wait for the LOD manager from Beat 5, which does not exist yet). So for THIS beat, temporarily set `interior_lod = false` in `_spawn_building` (frames self-build at `_ready`) to fly a furnished tower now; flip it back to `true` in Beat 5 when the manager lands. Leave a `# TODO(Beat 5): interior_lod = true` marker.

- [ ] **Step 2: Import + boot city_map.** Run `--import`, then `<godot> --headless --quit-after 12 --path . scenes/city_map.tscn` → clean.

- [ ] **Step 3: Commit (pending flight).**

```bash
git add scripts/environment/city_layout.gd scenes/city_map.tscn scenes/dev_map.tscn
git commit -m "B3 interiors: per-district vertical profile wired into the city (built + headless-verified, pending flight)"
```

- [ ] **Step 4: 🛑 HUMAN FLIGHT CHECKPOINT.** Human flies `city_map` and a full tower: does the stack read lobby→warehouse→office→atrium, and cyber/natural/urban towers feel different inside? **Watch perf** — a fully furnished city with no LOD will be heavy; that is expected and motivates Beat 5. Decision-log entry on approval.

---

## Beat 5 — Distance LOD + perf pass (HUMAN FLIGHT CHECKPOINT)

Furnish only nearby buildings; free the rest. The real perf lever (spec §9).

### Task 5.1 — `WorldBuilding` LOD manager

**Files:** Modify `scripts/environment/world_building.gd`

- [ ] **Step 1: Add tunables** (with the interior exports):

```gdscript
## Distance LOD (B3, spec §9): furnish open floors only within this radius of the
## drone; free them beyond. Hysteresis avoids thrashing at the boundary.
@export var interior_lod_radius: float = 140.0
@export var interior_lod_hysteresis: float = 20.0

var _drone: Node3D = null
var _furnished: bool = false
```

- [ ] **Step 2: Find the drone + poll distance.** Add to `_ready()` (end) and a throttled `_process`:

```gdscript
func _ready() -> void:
	# ... existing body ...
	if interior_lod:
		set_process(true)
	else:
		set_process(false)


func _process(_delta: float) -> void:
	if not interior_lod:
		return
	if _drone == null:
		_drone = get_tree().get_first_node_in_group(&"drone") as Node3D
		if _drone == null:
			return
	var d: float = global_position.distance_to(_drone.global_position)
	if not _furnished and d < interior_lod_radius:
		_set_interiors(true)
	elif _furnished and d > interior_lod_radius + interior_lod_hysteresis:
		_set_interiors(false)


func _set_interiors(on: bool) -> void:
	_furnished = on
	for frame: MenuFloorFrame in find_children("*", "MenuFloorFrame", true, false):
		if frame.has_interior():
			if on:
				frame.build_interior()
			else:
				frame.clear_interior()
```

> **Prerequisite check:** confirm the drone node is in group `&"drone"`. Run: `<godot> --headless --check-only ...` is not enough — grep the drone scene/script. If the group differs, use the actual group or a node-path export. (Check `scripts/drone/flight_controller.gd` / `drone.tscn`.)

- [ ] **Step 3: Restore `interior_lod = true`** in `CityLayout._spawn_building` (undo the Beat 4 TODO).

- [ ] **Step 4: Headless LOD check.** Extend `scripts/tests/world_building_check.gd` (or add `interior_lod_check.gd`): instance a `WorldBuilding` with `interiors_enabled`, `interior_lod=true`, no drone in range → assert every `MenuFloorFrame.has_interior()` frame has NO `Interior` child; then call `_set_interiors(true)` → assert an `Interior` child exists; `_set_interiors(false)` → gone.

```gdscript
# in the check:
var wb := WorldBuilding.new()
wb.interiors_enabled = true
wb.interior_lod = true
wb.building_seed = 5
wb.target_floors = 8
wb.open_floors = 4
root.add_child(wb)
# after ready:
for f in wb.find_children("*", "MenuFloorFrame", true, false):
	if f.has_interior() and f.find_child("Interior", false, false) != null:
		return _fail("interior built despite LOD out of range")
wb._set_interiors(true)
# assert at least one Interior child now exists ... then _set_interiors(false) ... assert none
```

- [ ] **Step 5: Import + boot + checks.** `--import`, boot `city_map` (`--quit-after 12`), run `world_building_check`/`interior_lod_check` + `city_layout_check` → clean/`PASS`.

- [ ] **Step 6: Commit (pending flight).**

```bash
git add scripts/environment/world_building.gd scripts/environment/city_layout.gd scripts/tests/world_building_check.gd
git commit -m "B3 interiors: building-level distance LOD (built + headless-verified, pending flight)"
```

- [ ] **Step 7: 🛑 HUMAN FLIGHT CHECKPOINT.** Human flies `city_map`: is pop-in acceptable at `interior_lod_radius`? Perf headroom? Tune radius/hysteresis. (If pop-in is harsh, consider `GeometryInstance3D.visibility_range` cross-fade on the Interior meshes as a follow-up.) Decision-log entry on approval.

---

## Beat 6 — The B2 lighting moment (HUMAN FLIGHT CHECKPOINT)

Auto-exposure "gets darker inside" + neon wayfinding + genuine darkness. Extends the existing look pass — no new architecture.

### Task 6.1 — Auto-exposure in `LookConfig`/`LookController`

**Files:** Modify `resources/look_config.gd`, `scripts/environment/look_controller.gd`

- [ ] **Step 1: Read both files** to match the export/apply pattern (how `exposure`/`glow`/`ssao` are declared and pushed onto Environment/CameraAttributes each frame).

- [ ] **Step 2: Add an auto-exposure group to `LookConfig`** (mirror the existing group style):

```gdscript
@export_group("Auto Exposure")
@export var auto_exposure_enabled: bool = true
@export var auto_exposure_scale: float = 0.4      # target brightness
@export var auto_exposure_min: float = 0.05
@export var auto_exposure_max: float = 3.0
@export var auto_exposure_speed: float = 0.5      # adaptation rate
```

- [ ] **Step 3: Apply in `LookController`** — set `CameraAttributesPractical` auto-exposure fields on the camera/environment attributes each frame from those values (match how the controller already fetches the target). Show the concrete apply block matching the file's existing accessor.

- [ ] **Step 4: Boot check.** `--import`, boot `main.tscn`/`city_map.tscn`, open the overlay LOOK section → the new group appears and pushes live.

### Task 6.2 — Neon wayfinding channel strips  ✅ ALREADY LANDED (v1.65 bonus + v1.66)

Done ahead of Beat 6 as the safe, interior-local half. `InteriorBuilder._wayfinding`
draws a wide (0.45 m) bright cyan floor strip down each axis-aligned channel
(window→hub), visual-only. Remaining Beat-6 work here is just re-tuning energy/width
once the darkness lands. Original sketch kept for reference:

- [ ] **Step 1: Add faint emissive guide strips** along each channel in `build()` (behind a knob so it is tunable/removable), in the navigation-cyan palette (like the window-line/chevrons):

```gdscript
	# Wayfinding: a thin emissive strip on the floor down each keep-clear channel.
	var guide := StandardMaterial3D.new()
	guide.emission_enabled = true
	guide.albedo_color = MenuFloorFrame.LINE_COLOR
	guide.emission = MenuFloorFrame.LINE_COLOR
	guide.emission_energy_multiplier = MenuFloorFrame.LINE_ENERGY * 0.5
	for ch: Dictionary in spec.get("channels", []):
		var a: Vector2 = ch["a"]
		var b: Vector2 = ch["b"]
		var mid: Vector2 = (a + b) * 0.5
		var length: float = a.distance_to(b)
		var ang: float = (b - a).angle()   # rotate a Z-length strip to the segment
		_box(batch, body, Vector3(0.18, 0.04, length), Vector3(mid.x, 0.03, mid.y),
				-ang, guide)
```

(Verify the yaw sign against a booted floor; flip `-ang`→`ang` if the strip runs crosswise.)

- [ ] **Step 2: Darkness tuning:** in `LookConfig` defaults, drop `ambient_energy` low enough that interiors read dark once the sun can't reach them (value TBD by flight — start from the current default, lower in the checkpoint).

- [ ] **Step 3: Import + boot + checks** → clean. `interior_gen_check` unaffected (channels unchanged).

- [ ] **Step 4: Commit (pending flight).**

```bash
git add resources/look_config.gd scripts/environment/look_controller.gd scripts/menu/interior_builder.gd
git commit -m "B3 interiors: B2 lighting — auto-exposure + neon wayfinding + darkness (built + headless-verified, pending flight)"
```

- [ ] **Step 5: 🛑 HUMAN FLIGHT CHECKPOINT.** Human flies the "gets darker inside" beat: does crossing the window line read as the eye adapting? Do the channel strips shine the way? Is the interior genuinely dark yet readable? Tune auto-exposure speed/scale, ambient, strip energy. Decision-log entry on approval — B3 interiors ship.

### Task 6.3 — Glass walls (bundled with lighting; user decision v1.66)

The user asked for glassy open-floor walls; decided to **bundle it with this beat**
because glass reads completely differently under the auto-exposure/darkness pass.
Two tiers:

**Tier A — emissive curtain-wall glass (the default, everywhere it fits).** The
open-floor solid wall segments become dark glazed panels carrying a glowing mullion
grid — reuse the sealed-floor treatment (`MenuFloorFrame._build_facade_grid` +
`SEALED_ALBEDO`/`MULLION_*`), applied to the *solid* parts of an open floor's walls
(the piers/sill/header from `_build_opened_wall` and the whole face from
`_build_solid_wall`). Reads unmistakably as "glass office/atrium" with **no
transparency cost**. Gate by program (atrium/lobby/office/server glassy;
warehouse/dock stay opaque industrial) via a new `glass: bool` on the floor spec,
set in `WorldBuilding` from the program.

- [ ] Add `glass` to the floor spec + `MenuFloorFrame` (default false → menu/existing
  untouched). In `_build_open`, when `glass`, use the glazed panel + mullion material
  for the solid wall boxes instead of `_mat_dark`.
- [ ] `WorldBuilding`: set `glass = true` for the glassy programs when stamping.
- [ ] Guard: sealed/under-construction floors and the whole menu are unaffected.
- [ ] Tune glaze tint + mullion energy in the SAME checkpoint as auto-exposure.

**Tier B — true transparent glass, VERY SPARSE (landmark floors).** Reserved for rare
"premium" floors — a **penthouse / boss office / conservatory-garden** — as a special,
seed-gated program variant (at most one per tall building, typically the top). These
get an actual transparent material (accept the alpha-sorting cost precisely *because*
they are rare) and double as **landmark telegraphs** (a glass crown reads as "special"
from blocks away — B2 doctrine) and a natural future **P2 objective floor** (boss
office). Design seed recorded; implement only after Tier A + lighting feel right.

- [ ] Add a rare program (e.g. `PROGRAM_PENTHOUSE`) chosen by `BuildingProgram` for the
  very top band of a small fraction of tall buildings; give it a sparse fancy kit
  (lounge, garden planters, a feature) + true-glass walls.
- [ ] Keep it rare enough that transparency never accumulates into a perf problem.

---

## Self-Review

**Spec coverage:**
- §2 unit=open-plan → Beat 1 (no partitions; columns+scatter) ✓
- §2 district-linked / restructures → `BuildingProgram` (Task 1.3) + Beat 4 ✓
- §2 refined-B (scatter + Fold 1 columns + Fold 2 network) → Task 1.2 `_build_channels`/`_build_columns`/`_scatter` ✓
- §3 two generators + one render hook, spec is plain data → Tasks 1.1–1.3, 2.1–2.4 ✓
- §4 algorithm order + headless invariants → Task 1.2 + `interior_gen_check` (Task 1.4) ✓
- §5 per-district profile + ground=lobby + scales to height → Task 1.3 + program check ✓
- §6 kit, variety by combination → Tasks 2.1, 3.1 ✓
- §7 opening/aisle tunables (knobs, generous-first) → `DEFAULT_KNOBS` + `interior_knobs` export ✓
- §8 eligibility (open floors only) + building-level LOD + no save state → Task 2.4 guard + Beat 5 ✓
- §9 batching (own subtree per material) → `InteriorBuilder.build` ✓
- §10 F4 seed hierarchy (`building_seed*1000003+k`), no RNG-stream disturbance → Task 2.4 (interiors read building_seed, never draw from CityLayout rng) ✓
- §8 B2 lighting → Beat 6 ✓
- §11 boundaries (combat/sortie out) → nothing built for them; collision present, program is data ✓
- §12 six beats + checkpoint protocol → Beats 1–6 ✓

**Placeholder scan:** Beat 6 Step 2 leaves `ambient_energy` value "TBD by flight" — intentional and correct (feel is the human's; the plan can't assert a lux). All *code* steps show complete code. No "similar to Task N".

**Type consistency:** spec dict shape `{program, columns:Array[Vector2], pieces:[{kind,pos:Vector3,yaw,extent:Vector2}], channels:[{a,b,width}], knobs}` is identical across generator (1.2), builder (2.1), and check (1.4). `district:int` == `CityLayout.PropStyle` throughout. `build_interior()`/`clear_interior()`/`has_interior()` names match between `MenuFloorFrame` (2.2) and the LOD manager (5.1). `interiors_enabled`/`district`/`force_program`/`interior_lod` consistent WorldBuilding↔CityLayout.

**One flagged risk to verify during execution:** Task 5.1 assumes the drone is in group `&"drone"` — the plan makes the executor confirm this (grep the drone scene) before relying on it.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-25-b3-interiors.md`. **This is a design + planning session — do not start implementing until the human says go, ideally in a dedicated worktree.** When execution begins, two options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks. Note: Beats 2–6 each end at a HUMAN FLIGHT CHECKPOINT, so subagents run to "built + headless-verified, pending flight" and then hand back to the human — they never self-approve feel.
2. **Inline Execution** — tasks in one session with checkpoints (executing-plans), same flight gates.

Which approach (later, when you're ready to build)?
