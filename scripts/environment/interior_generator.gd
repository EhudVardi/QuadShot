class_name InteriorGenerator
extends RefCounted

## Seeded, deterministic OPEN-PLAN interior for one floor (B3, spec §4). Pure:
## (program, seed, footprint, height, open_sides, knobs) -> a plain-data interior
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


## The four side-window centres (SIDES order: front +Z, back -Z, right +X, left -X),
## keeping only OPEN sides. Empty open_sides = all four open (standalone default).
static func _window_centers(open_sides: Array, px: float) -> Array:
	var all_sides: Array = [Vector2(0.0, px), Vector2(0.0, -px), Vector2(px, 0.0), Vector2(-px, 0.0)]
	var out: Array = []
	for i: int in all_sides.size():
		if open_sides.is_empty() or (i < open_sides.size() and bool(open_sides[i])):
			out.append(all_sides[i])
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


## A sparse interior column grid that holds the slab (spec §4, Fold 1). The grid is
## CENTRED on the origin and symmetric about both axes, so the columns read as an
## even structural bay pattern; any that fall in a flight channel are dropped
## (symmetrically — the channels are axis-aligned), and the perimeter walls carry
## the edge load.
static func _build_columns(px: float, k: Dictionary, channels: Array) -> Array:
	var cols: Array = []
	var spacing: float = k["column_spacing"]
	var limit: float = px - COLUMN_W - 1.0   # keep columns off the walls
	if limit <= 0.0:
		return cols
	var count: int = maxi(2, int(floor(2.0 * limit / spacing)) + 1)
	var start: float = -float(count - 1) * 0.5 * spacing
	for ix: int in count:
		var gx: float = start + float(ix) * spacing
		if absf(gx) > limit:
			continue
		for iz: int in count:
			var gz: float = start + float(iz) * spacing
			if absf(gz) > limit:
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


## Which programs read as glazed curtain-wall interiors (Tier A glass, B3 v1.66):
## the human-facing programs go glassy; warehouse/dock stay opaque industrial.
static func is_glassy(program: StringName) -> bool:
	return program == PROGRAM_OFFICE or program == PROGRAM_ATRIUM \
			or program == PROGRAM_LOBBY_ATRIUM or program == PROGRAM_SERVER_FARM


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
