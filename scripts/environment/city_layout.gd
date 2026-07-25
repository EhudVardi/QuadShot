class_name CityLayout
extends Node3D

## A seeded city-block layout with ROAD HIERARCHY + HEIGHT ZONING (GAMEPLAY-
## DESIGN B4, v1.52 → v1.55). The grid is no longer uniform: block widths vary
## per column and depths per row (varied grain), and one interior street is a
## wide MAIN AVENUE running the flight direction (-Z) — a canyon you fly straight
## down. Building height follows a DOWNTOWN CORE seeded near the avenue: tall
## downtown, tapering to low-rise at the edges, so the skyline has a shape you
## read from the air (and setbacks cluster in the core). Straight streets are
## preserved — a whole column shares one width, a whole row one depth — so the
## network still reads as a grid, not a scatter. Deterministic: same seed = same
## city. No building overlaps another — each footprint is capped to its own
## block, and blocks sit a full street apart, so the streets never close up.
## Amber centerlines mark the roads (the avenue's is thicker). First client: the
## dev room; the game-world city is this node at scale.

@export var layout_seed: int = 1
@export var cols: int = 3
@export var rows: int = 2
## BASE buildable block size; the per-column width / per-row depth varies around
## it (see block_variation) so the grain isn't a uniform stamp. A building's
## footprint is capped to its block (minus a margin), which keeps streets open.
@export var block_size: float = 32.0
## Per-axis block-size variation: each column width / row depth is
## block_size × randf_range(1 - v, 1 + v·0.5), floored at MIN_BLOCK.
@export var block_variation: float = 0.28
## Base side-street width — the gap between blocks. Wide by design.
@export var road_width: float = 16.0
## The main avenue is this multiple of road_width. One interior vertical street,
## chosen near the middle, becomes the avenue (needs cols ≥ 3 and mult ≥ 2).
@export var avenue_mult: float = 2.4
## Row 0 sits at this local z; rows march into -Z (the flight direction).
@export var front_z: float = -64.0
@export var min_floors: int = 12
@export var max_floors: int = 34
## Chance a block is an empty lot — some gaps in the skyline.
@export var empty_chance: float = 0.1
## Of empty lots, the fraction that are raised PLAZAS; the rest are SUNKEN bare
## lots (marked). Variety in the gaps.
@export_range(0.0, 1.0) var plaza_chance: float = 0.5
## Chance a building is tiered (setbacks) rather than a plain box.
@export var setback_chance: float = 0.4
## HEIGHT ZONING — a downtown core. Height follows distance from a seeded core
## near the avenue: 0 = the old flat random height (no district); 1 = the full
## core→edge gradient.
@export_range(0.0, 1.0) var zone_strength: float = 1.0
## Gradient shape: >1 tightens a tall core with a sharp drop, <1 spreads height
## out. 1 = linear.
@export_range(0.25, 4.0) var core_falloff: float = 1.5
## Random height jitter on the zoned target, as a fraction of the floor range —
## so a district reads as a cluster, not a smooth dome.
@export_range(0.0, 0.5) var zone_jitter: float = 0.18
## Extra setback (tiering) chance added at the core — stepped towers cluster
## downtown, plain boxes at the fringe.
@export_range(0.0, 1.0) var setback_core_bonus: float = 0.35

const ROADLINE_COLOR: Color = Color(1.0, 0.75, 0.2)
const ROADLINE_ENERGY: float = 2.5
const ROADLINE_WIDTH: float = 0.5
## The avenue's centerline is this much thicker, so the hierarchy reads at speed.
const AVENUE_LINE_MULT: float = 2.6
## Minimum gap between a footprint and its block edge (keeps streets clear).
const BUILDING_MARGIN: float = 4.0
## A block never shrinks below this — always room for a real building.
const MIN_BLOCK: float = 20.0
## Dark paved base under the whole grid — the street surface, so the roads read
## as a continuous ground, not gaps between towers.
const ASPHALT_COLOR: Color = Color(0.035, 0.04, 0.05)
## Raised block platforms (v1.58 ground life): each block lifts a curb above the
## road, so the streets read as sunken roadways between raised sidewalks. A pale
## concrete so the curb reads even in the dark (SSAO grounds it).
const SIDEWALK_COLOR: Color = Color(0.20, 0.22, 0.26)
const CURB_HEIGHT: float = 0.15
## Cyan neon curb line along a raised block's top edges (navigation palette —
## pedestrian ways glow cool, roads amber).
const CURB_TRIM_COLOR: Color = Color(0.2, 0.7, 1.0)
const CURB_TRIM_ENERGY: float = 2.0
const CURB_TRIM: float = 0.12
## Amber painted border on a SUNKEN empty lot, so a gap reads as a deliberate lot
## (a construction plot), not a hole in the ground.
const LOT_MARK_COLOR: Color = Color(1.0, 0.7, 0.2)
const LOT_MARK_ENERGY: float = 2.0
const LOT_MARK: float = 0.25
## Streetlights (v1.59 ground life): amber lamp-posts down every block edge —
## human vertical scale + warm street rhythm. The lamp head is emissive (glows
## via bloom), no real OmniLight, so the count stays free and batched. Scenery:
## non-colliding for now.
const STREETLIGHT_POLE_H: float = 6.0
const STREETLIGHT_POLE_W: float = 0.22
const STREETLIGHT_LAMP: float = 0.55
## Poles stand this far in from the block edge, on the sidewalk facing the road.
const STREETLIGHT_INSET: float = 1.0
const STREETLIGHT_POLE_COLOR: Color = Color(0.09, 0.1, 0.12)
const STREETLIGHT_LAMP_COLOR: Color = Color(1.0, 0.72, 0.32)
const STREETLIGHT_LAMP_ENERGY: float = 2.5
## Entrance-aware lighting (user's rule): a corner is lit only if it faces the
## downtown core by more than this (dot of corner-dir vs core-dir). The two
## outward corners of an edge building stay dark — blind alleys toward the rim.
const STREETLIGHT_CENTRALITY_CUT: float = -0.15
## Blocks within this of the core are lit on all corners (direction to core is
## ill-defined at the centre — downtown is fully lit).
const STREETLIGHT_CORE_RADIUS: float = 24.0
## A building opens a side toward the core if that side's outward normal faces
## the core by more than this (v1.62) — the building half of the "less central,
## less entrance" rule. Gentle: axis-aligned edge buildings seal only their one
## fully-outward side; diagonal ones seal the outward pair.
const FACING_CUT: float = -0.35
## Natural greenery (v1.63 ground life): matte trees + planters — NOT neon (the
## user's "natural" style). Plazas become little parks; sidewalks get street
## trees. Batched into 3 meshes (trunk / foliage / planter) for the whole grid.
const TREE_TRUNK_COLOR: Color = Color(0.16, 0.12, 0.09)
const TREE_LEAF_COLOR: Color = Color(0.14, 0.34, 0.16)
const PLANTER_COLOR: Color = Color(0.18, 0.19, 0.21)
## Trees stand about this far apart when a plaza is filled like a park.
const TREE_SPACING: float = 6.0
## Prop style by height-zone (v1.64): the lush core glows cyberpunk, the mid ring
## is natural, the gritty rim is urban hardscape.
const CYBER_ZONE_CUT: float = 0.6
const NATURAL_ZONE_CUT: float = 0.3
## Cyberpunk greenery — bio-luminescent, blooms past the 1.0 threshold.
const CYBER_BASE_COLOR: Color = Color(0.05, 0.07, 0.08)
const CYBER_GLOW_COLOR: Color = Color(0.25, 0.95, 0.7)
const CYBER_GLOW_ENERGY: float = 2.6
## Urban hardscape — concrete grey with a small warm sign light.
const HARDSCAPE_COLOR: Color = Color(0.16, 0.17, 0.19)
const HARDSCAPE_SIGN_COLOR: Color = Color(1.0, 0.5, 0.25)
const HARDSCAPE_SIGN_ENERGY: float = 2.0

## Ground-prop kit chosen per block by its zone (v1.64).
enum PropStyle { URBAN, NATURAL, CYBER }

## A block is either built on, a raised empty plaza, or a sunken marked lot.
enum Lot { OCCUPIED, PLAZA, SUNKEN }

# Grid geometry, computed in _ready before any building spawns.
var _col_x: Array[float] = []       ## centre x of each column
var _col_w: Array[float] = []       ## block width of each column
var _row_z: Array[float] = []       ## centre z of each row
var _row_d: Array[float] = []       ## block depth of each row
var _avenue_street: int = -1        ## interior street index that is the avenue
var _core_c: float = 0.0            ## downtown core, in column-index space
var _core_r: float = 0.0            ## downtown core, in row-index space
var _core_world: Vector2 = Vector2.ZERO  ## the core's world XZ (streetlight gating)
var _max_zone_dist: float = 1.0     ## core→farthest-corner distance (normaliser)


func _ready() -> void:
	rebuild()


## (Re)build the whole city from the current exports, clearing any existing
## geometry first. Called on ready, and by the debug overlay's CITY section so
## the grid / avenue / zoning knobs (and the seed) can be re-rolled live.
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_lay_grid(rng)
	var lots: Array = _roll_lots(rng)
	_build_ground()
	_build_roads()
	_build_sidewalks(lots)
	_build_streetlights()
	_build_greenery(lots)
	for r: int in rows:
		for c: int in cols:
			if lots[r][c] == Lot.OCCUPIED:
				_spawn_building(rng, r, c)


## Decide every block's lot up front, so the sidewalk pass and the building pass
## agree: most are OCCUPIED; an empty_chance fraction are empty, split
## plaza_chance PLAZA (raised) vs SUNKEN (bare, marked) for gap variety.
func _roll_lots(rng: RandomNumberGenerator) -> Array:
	var lots: Array = []
	for r: int in rows:
		var row: Array = []
		for c: int in cols:
			# The wider the bordering road, the less likely a gap — prime avenue
			# frontage is built up; empty lots fall on the narrow back streets.
			var chance: float = empty_chance * road_width / _block_max_road(c)
			if rng.randf() < chance:
				row.append(Lot.PLAZA if rng.randf() < plaza_chance else Lot.SUNKEN)
			else:
				row.append(Lot.OCCUPIED)
		lots.append(row)
	return lots


## The widest road bordering column c's blocks — the avenue where a column flanks
## it, else a side street. Drives the "wide road → fewer empty lots" rule.
func _block_max_road(c: int) -> float:
	var left: float = _street_width(c) if c >= 1 else road_width
	var right: float = _street_width(c + 1) if c <= cols - 2 else road_width
	return maxf(maxf(left, right), road_width)


## Compute per-column widths + per-row depths (varied grain) and their cumulative
## centres, with one wide avenue street. Centres the grid on x = 0; row 0 stays
## at front_z. Interior vertical street `i` (i in 1..cols-1) sits left of column
## i; the avenue is one such street, so it runs the full depth in -Z.
func _lay_grid(rng: RandomNumberGenerator) -> void:
	_col_w.clear()
	_col_x.clear()
	_row_d.clear()
	_row_z.clear()
	for _c: int in cols:
		_col_w.append(_block_dim(rng))
	for _r: int in rows:
		_row_d.append(_block_dim(rng))
	# Pick the avenue: an interior street, biased toward the middle (best of two).
	if cols >= 3 and avenue_mult >= 2.0:
		_avenue_street = rng.randi_range(1, cols - 1)
		var alt: int = rng.randi_range(1, cols - 1)
		if absi(alt - cols / 2) < absi(_avenue_street - cols / 2):
			_avenue_street = alt
	# X centres: walk left→right accumulating block widths + streets, then shift
	# so the built span is centred on 0.
	var x: float = 0.0
	for c: int in cols:
		_col_x.append(x + _col_w[c] * 0.5)
		x += _col_w[c]
		if c < cols - 1:
			x += _street_width(c + 1)   # street to the right of column c
	var shift: float = x * 0.5
	for c: int in cols:
		_col_x[c] -= shift
	# Z centres: row 0 at front_z, march into -Z (side streets, no cross-avenue).
	_row_z.append(front_z)
	for r: int in range(1, rows):
		_row_z.append(_row_z[r - 1]
				- (_row_d[r - 1] * 0.5 + road_width + _row_d[r] * 0.5))
	# Downtown core: a real block flanking the avenue (so a genuine tower reaches
	# max_floors there), at a seeded middle-weighted depth. Snapping to a cell —
	# not a half-cell between blocks — is what lets the core actually peak; a
	# floating core leaves the tallest building undershooting max_floors.
	if _avenue_street >= 1:
		_core_c = float(_avenue_street - rng.randi_range(0, 1))   # either avenue neighbour
	else:
		_core_c = float((cols - 1) / 2)
	var mid_r: float = float(rows - 1) * 0.5
	_core_r = clampf(roundf(mid_r + rng.randf_range(-1.0, 1.0) * float(rows - 1) * 0.35),
			0.0, float(rows - 1))
	# The core→farthest-corner distance normalises the gradient to 0..1.
	_max_zone_dist = 0.0001
	for cc: int in [0, cols - 1]:
		for rr: int in [0, rows - 1]:
			_max_zone_dist = maxf(_max_zone_dist, _raw_zone_dist(cc, rr))
	# The core's world position — streetlights gate on how much each block corner
	# faces it, so lighting falls off toward the edges (the user's rule).
	var core_col: int = clampi(int(round(_core_c)), 0, cols - 1)
	var core_row: int = clampi(int(round(_core_r)), 0, rows - 1)
	_core_world = Vector2(_col_x[core_col], _row_z[core_row])


## A varied block dimension (column width or row depth), floored so it always
## holds a building.
func _block_dim(rng: RandomNumberGenerator) -> float:
	return maxf(MIN_BLOCK,
			block_size * rng.randf_range(1.0 - block_variation, 1.0 + block_variation * 0.5))


## Width of the interior vertical street with index `i` (between column i-1 and
## i) — the avenue if it was chosen, else a plain side street.
func _street_width(i: int) -> float:
	return road_width * avenue_mult if i == _avenue_street else road_width


func _spawn_building(rng: RandomNumberGenerator, r: int, c: int) -> void:
	# Height follows the district: a zoned target (tall core → short edge) blended
	# by zone_strength against a flat mid, plus bounded jitter so it's not a dome.
	var zone: float = _zone(c, r)
	var flat: float = float(min_floors + max_floors) * 0.5
	var zoned: float = lerpf(float(min_floors), float(max_floors), zone)
	var target: float = lerpf(flat, zoned, zone_strength)
	var jitter: float = rng.randf_range(-1.0, 1.0) * float(max_floors - min_floors) * zone_jitter
	var floors: int = clampi(int(round(target + jitter)), min_floors, max_floors)
	# Taller → wider, capped to the block's smaller dimension so a tower never
	# eats its street.
	var lean: float = float(floors - min_floors) / maxf(float(max_floors - min_floors), 1.0)
	var block: float = minf(_col_w[c], _row_d[r])
	var fp: float = clampf(16.0 + lean * 18.0 + rng.randf_range(-3.0, 3.0),
			16.0, block - BUILDING_MARGIN)
	var building := WorldBuilding.new()
	# A distinct, stable seed per block so each building is its own thing.
	building.building_seed = layout_seed * 131 + (r * cols + c)
	building.footprint = fp
	building.target_floors = floors
	building.open_floors = maxi(2, int(round(float(floors) * 0.55)))
	building.interior_height = rng.randf_range(3.6, 5.6)
	# Setbacks cluster downtown: base chance + a core bonus scaled by the zone.
	if rng.randf() < clampf(setback_chance + zone * setback_core_bonus, 0.0, 1.0):
		building.setback_tiers = rng.randi_range(3, 4)
		building.top_footprint = fp * rng.randf_range(0.45, 0.6)
	building.open_sides = _facing_open_sides(_col_x[c], _row_z[r])
	building.position = Vector3(_col_x[c], 0.0, _row_z[r])
	add_child(building)


## Which of a building's four sides open toward the downtown core (v1.62): the
## order is [front +Z, back -Z, right +X, left -X], matching MenuFloorFrame.SIDES.
## Core-adjacent buildings open all four (direction is ill-defined at the centre).
func _facing_open_sides(bx: float, bz: float) -> Array:
	var to_core: Vector2 = _core_world - Vector2(bx, bz)
	if to_core.length() < STREETLIGHT_CORE_RADIUS:
		return [true, true, true, true]
	var dir: Vector2 = to_core.normalized()
	var normals: Array = [Vector2(0.0, 1.0), Vector2(0.0, -1.0),
			Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]
	var sides: Array = []
	for n: Vector2 in normals:
		sides.append(n.dot(dir) > FACING_CUT)
	return sides


## Normalised height-zone at block (c, r): 1 at the downtown core, 0 at the
## farthest corner, shaped by core_falloff.
func _zone(c: int, r: int) -> float:
	var d: float = _raw_zone_dist(c, r) / _max_zone_dist
	return pow(1.0 - clampf(d, 0.0, 1.0), core_falloff)


## Grid-space distance from block (c, r) to the core, each axis normalised by its
## span so cols ≠ rows doesn't skew the gradient.
func _raw_zone_dist(c: int, r: int) -> float:
	var dc: float = (float(c) - _core_c) / maxf(float(cols - 1), 1.0)
	var dr: float = (float(r) - _core_r) / maxf(float(rows - 1), 1.0)
	return sqrt(dc * dc + dr * dr)


## A centerline down every street (both axes, incl. the perimeter), so the block
## grid reads as a connected road network; the avenue's line draws thicker.
func _build_roads() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROADLINE_COLOR
	mat.emission_enabled = true
	mat.emission = ROADLINE_COLOR
	mat.emission_energy_multiplier = ROADLINE_ENERGY
	var left: float = _col_x[0] - _col_w[0] * 0.5
	var right: float = _col_x[cols - 1] + _col_w[cols - 1] * 0.5
	var front: float = _row_z[0] + _row_d[0] * 0.5
	var back: float = _row_z[rows - 1] - _row_d[rows - 1] * 0.5
	var city_w: float = (right - left) + 2.0 * road_width
	var city_d: float = (front - back) + 2.0 * road_width
	var mid_z: float = (front + back) * 0.5
	# Vertical streets (run in Z): left perimeter, each interior street, right.
	_add_line(Vector3(ROADLINE_WIDTH, 0.05, city_d),
			Vector3(left - road_width * 0.5, 0.03, mid_z), mat)
	for c: int in cols - 1:
		var cx: float = ((_col_x[c] + _col_w[c] * 0.5)
				+ (_col_x[c + 1] - _col_w[c + 1] * 0.5)) * 0.5
		var lw: float = ROADLINE_WIDTH * (AVENUE_LINE_MULT if (c + 1) == _avenue_street else 1.0)
		_add_line(Vector3(lw, 0.05, city_d), Vector3(cx, 0.03, mid_z), mat)
	_add_line(Vector3(ROADLINE_WIDTH, 0.05, city_d),
			Vector3(right + road_width * 0.5, 0.03, mid_z), mat)
	# Horizontal streets (run in X): front perimeter, each interior, back.
	_add_line(Vector3(city_w, 0.05, ROADLINE_WIDTH),
			Vector3(0.0, 0.03, front + road_width * 0.5), mat)
	for r: int in rows - 1:
		var cz: float = ((_row_z[r] - _row_d[r] * 0.5)
				+ (_row_z[r + 1] + _row_d[r + 1] * 0.5)) * 0.5
		_add_line(Vector3(city_w, 0.05, ROADLINE_WIDTH), Vector3(0.0, 0.03, cz), mat)
	_add_line(Vector3(city_w, 0.05, ROADLINE_WIDTH),
			Vector3(0.0, 0.03, back - road_width * 0.5), mat)


## Ground life per block (v1.58): OCCUPIED / PLAZA blocks get a raised sidewalk
## with a cyan neon curb line; SUNKEN lots get an amber painted border instead.
## Everything batches by material (slab / trim / marking → 3 draw calls for the
## whole grid, even at 10×10). Buildings sit on their raised block.
func _build_sidewalks(lots: Array) -> void:
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = SIDEWALK_COLOR
	slab_mat.roughness = 0.95
	var trim_mat := _emissive_mat(CURB_TRIM_COLOR, CURB_TRIM_ENERGY)
	var mark_mat := _emissive_mat(LOT_MARK_COLOR, LOT_MARK_ENERGY)
	var batch := BoxBatcher.new()
	for r: int in rows:
		for c: int in cols:
			var w: float = _col_w[c]
			var d: float = _row_d[r]
			var at: Vector3 = Vector3(_col_x[c], 0.0, _row_z[r])
			if lots[r][c] == Lot.SUNKEN:
				_mark_lot(batch, at, w, d, mark_mat)
			else:
				batch.add(Vector3(w, CURB_HEIGHT, d),
						Vector3(at.x, CURB_HEIGHT * 0.5, at.z), slab_mat)
				_curb_trim(batch, at, w, d, trim_mat)
	batch.commit_into(self)


## Cyan neon along the four top edges of a raised block — the curb line.
func _curb_trim(batch: BoxBatcher, at: Vector3, w: float, d: float, mat: Material) -> void:
	var y: float = CURB_HEIGHT
	batch.add(Vector3(w, CURB_TRIM, CURB_TRIM), Vector3(at.x, y, at.z - d * 0.5), mat)
	batch.add(Vector3(w, CURB_TRIM, CURB_TRIM), Vector3(at.x, y, at.z + d * 0.5), mat)
	batch.add(Vector3(CURB_TRIM, CURB_TRIM, d), Vector3(at.x - w * 0.5, y, at.z), mat)
	batch.add(Vector3(CURB_TRIM, CURB_TRIM, d), Vector3(at.x + w * 0.5, y, at.z), mat)


## An amber painted border on a sunken lot, inset like a real plot line, so the
## gap reads as a deliberate empty lot rather than a hole.
func _mark_lot(batch: BoxBatcher, at: Vector3, w: float, d: float, mat: Material) -> void:
	var y: float = 0.045
	var iw: float = w - 1.5
	var id: float = d - 1.5
	batch.add(Vector3(iw, 0.05, LOT_MARK), Vector3(at.x, y, at.z - id * 0.5), mat)
	batch.add(Vector3(iw, 0.05, LOT_MARK), Vector3(at.x, y, at.z + id * 0.5), mat)
	batch.add(Vector3(LOT_MARK, 0.05, id), Vector3(at.x - iw * 0.5, y, at.z), mat)
	batch.add(Vector3(LOT_MARK, 0.05, id), Vector3(at.x + iw * 0.5, y, at.z), mat)


func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## Amber lamp-posts at each block's four CORNERS, inset onto the sidewalk — a
## light flanks the windows rather than blocking a centered opening (v1.60). Each
## corner is lit only if it faces the downtown core (v1.61, the user's rule: the
## less central a side, the less lit) — so the core glows and the outward sides
## fade to dark blind alleys toward the rim. Pole + emissive head only, batched
## into 2 meshes for the whole grid.
func _build_streetlights() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = STREETLIGHT_POLE_COLOR
	pole_mat.roughness = 0.8
	var lamp_mat := _emissive_mat(STREETLIGHT_LAMP_COLOR, STREETLIGHT_LAMP_ENERGY)
	var batch := BoxBatcher.new()
	for r: int in rows:
		for c: int in cols:
			var ix: float = _col_w[c] * 0.5 - STREETLIGHT_INSET
			var iz: float = _row_d[r] * 0.5 - STREETLIGHT_INSET
			var x: float = _col_x[c]
			var z: float = _row_z[r]
			var to_core: Vector2 = _core_world - Vector2(x, z)
			var central: bool = to_core.length() < STREETLIGHT_CORE_RADIUS
			var dir: Vector2 = to_core.normalized()
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					if central or dir.dot(Vector2(sx, sz).normalized()) > STREETLIGHT_CENTRALITY_CUT:
						_add_streetlight(batch, x + sx * ix, z + sz * iz, pole_mat, lamp_mat)
	batch.commit_into(self)


func _add_streetlight(batch: BoxBatcher, x: float, z: float,
		pole_mat: Material, lamp_mat: Material) -> void:
	batch.add(Vector3(STREETLIGHT_POLE_W, STREETLIGHT_POLE_H, STREETLIGHT_POLE_W),
			Vector3(x, STREETLIGHT_POLE_H * 0.5, z), pole_mat)
	batch.add(Vector3(STREETLIGHT_LAMP, STREETLIGHT_LAMP, STREETLIGHT_LAMP),
			Vector3(x, STREETLIGHT_POLE_H, z), lamp_mat)


## Natural greenery (v1.63): plazas become little parks (a jittered grid of trees
## + planters), occupied blocks get a couple of street trees at the curb. Uses a
## private seed so it never disturbs the building RNG stream — the city is
## byte-identical, greenery just lands on top. All batched (3 draw calls).
## Ground props STYLED BY ZONE (v1.64): the downtown core gets cyberpunk
## bio-luminescent greenery, the mid ring natural matte trees, the rim urban
## hardscape (kiosks/benches, no green) — the user's centre-lush / edge-gritty
## vision. Plazas fill like the zone's kind of park; occupied blocks get a prop
## on each sealed side. Private seed (the city is untouched); all batched.
func _build_greenery(lots: Array) -> void:
	var g_rng := RandomNumberGenerator.new()
	g_rng.seed = layout_seed * 977 + 13
	var mats: Dictionary = _prop_materials()
	var batch := BoxBatcher.new()
	for r: int in rows:
		for c: int in cols:
			var style: int = _prop_style(c, r)
			var x: float = _col_x[c]
			var z: float = _row_z[r]
			var w: float = _col_w[c]
			var d: float = _row_d[r]
			match lots[r][c]:
				Lot.PLAZA:
					_fill_plaza(batch, g_rng, style, x, z, w, d, mats)
				Lot.OCCUPIED:
					_dress_sidewalk(batch, g_rng, style, x, z, w, d, mats)
	batch.commit_into(self)


## A block's ground-prop style from its height-zone: cyberpunk at the lush core,
## natural in the mid ring, urban hardscape at the gritty rim.
func _prop_style(c: int, r: int) -> int:
	var zone: float = _zone(c, r)
	if zone >= CYBER_ZONE_CUT:
		return PropStyle.CYBER
	if zone >= NATURAL_ZONE_CUT:
		return PropStyle.NATURAL
	return PropStyle.URBAN


## Shared material set for every prop kit — each material is one batched draw call.
func _prop_materials() -> Dictionary:
	return {
		"trunk": _flat_mat(TREE_TRUNK_COLOR, 0.9),
		"leaf": _flat_mat(TREE_LEAF_COLOR, 0.85),
		"planter": _flat_mat(PLANTER_COLOR, 0.9),
		"cyber_base": _flat_mat(CYBER_BASE_COLOR, 0.6),
		"cyber_glow": _emissive_mat(CYBER_GLOW_COLOR, CYBER_GLOW_ENERGY),
		"concrete": _flat_mat(HARDSCAPE_COLOR, 0.9),
		"sign": _emissive_mat(HARDSCAPE_SIGN_COLOR, HARDSCAPE_SIGN_ENERGY),
	}


func _flat_mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


## A plaza filled like the zone's kind of park: a jittered grid of that style's
## props on the raised slab.
func _fill_plaza(batch: BoxBatcher, g_rng: RandomNumberGenerator, style: int,
		cx: float, cz: float, w: float, d: float, mats: Dictionary) -> void:
	var inset: float = 3.0
	var iw: float = w - 2.0 * inset
	var id: float = d - 2.0 * inset
	if iw < 2.0 or id < 2.0:
		return
	var nx: int = clampi(int(round(iw / TREE_SPACING)), 1, 4)
	var nz: int = clampi(int(round(id / TREE_SPACING)), 1, 4)
	for i: int in nx:
		for j: int in nz:
			var fx: float = 0.5 if nx == 1 else float(i) / float(nx - 1)
			var fz: float = 0.5 if nz == 1 else float(j) / float(nz - 1)
			var px: float = cx - iw * 0.5 + iw * fx + g_rng.randf_range(-0.8, 0.8)
			var pz: float = cz - id * 0.5 + id * fz + g_rng.randf_range(-0.8, 0.8)
			_add_prop(batch, style, px, pz, g_rng, mats)


## A prop on each of an occupied block's SEALED sides (blank outward walls) — the
## v1.63b rule (never blocks an opening), now styled by zone. Core blocks (open
## all round) get none; their greenery is the plaza parks. Side order matches
## _facing_open_sides / SIDES: front +Z, back -Z, right +X, left -X.
func _dress_sidewalk(batch: BoxBatcher, g_rng: RandomNumberGenerator, style: int,
		cx: float, cz: float, w: float, d: float, mats: Dictionary) -> void:
	var open: Array = _facing_open_sides(cx, cz)
	var inset: float = 1.2
	var spots: Array = [
		Vector2(cx, cz + d * 0.5 - inset),
		Vector2(cx, cz - d * 0.5 + inset),
		Vector2(cx + w * 0.5 - inset, cz),
		Vector2(cx - w * 0.5 + inset, cz),
	]
	for i: int in 4:
		if not open[i]:
			_add_prop(batch, style, spots[i].x, spots[i].y, g_rng, mats)


## Place one prop of the given style. Natural + cyber reuse the tree/hedge shapes
## with different materials (a cyber tree is a tree with a glowing canopy); urban
## has its own kiosk/bench.
func _add_prop(batch: BoxBatcher, style: int, x: float, z: float,
		g_rng: RandomNumberGenerator, mats: Dictionary) -> void:
	match style:
		PropStyle.CYBER:
			if g_rng.randf() < 0.6:
				_add_tree(batch, x, z, g_rng, mats["cyber_base"], mats["cyber_glow"])
			else:
				_add_hedge(batch, x, z, mats["cyber_base"], mats["cyber_glow"])
		PropStyle.NATURAL:
			if g_rng.randf() < 0.75:
				_add_tree(batch, x, z, g_rng, mats["trunk"], mats["leaf"])
			else:
				_add_hedge(batch, x, z, mats["planter"], mats["leaf"])
		_:
			if g_rng.randf() < 0.5:
				_add_kiosk(batch, x, z, g_rng, mats["concrete"], mats["sign"])
			else:
				_add_bench(batch, x, z, g_rng, mats["concrete"])


## A greybox tree: a slim trunk under a boxy canopy, standing on the sidewalk.
func _add_tree(batch: BoxBatcher, x: float, z: float, g_rng: RandomNumberGenerator,
		trunk_mat: Material, leaf_mat: Material) -> void:
	var h: float = g_rng.randf_range(3.0, 4.5)
	var trunk_h: float = h * 0.4
	var canopy_h: float = h - trunk_h
	var canopy_w: float = g_rng.randf_range(1.6, 2.2)
	batch.add(Vector3(0.3, trunk_h, 0.3), Vector3(x, CURB_HEIGHT + trunk_h * 0.5, z),
			trunk_mat)
	batch.add(Vector3(canopy_w, canopy_h, canopy_w),
			Vector3(x, CURB_HEIGHT + trunk_h + canopy_h * 0.5, z), leaf_mat)


## A low planter box with a hedge on top — natural (concrete + green) or cyber
## (dark base + glowing top), by the materials passed.
func _add_hedge(batch: BoxBatcher, x: float, z: float, base_mat: Material,
		top_mat: Material) -> void:
	batch.add(Vector3(1.4, 0.5, 1.4), Vector3(x, CURB_HEIGHT + 0.25, z), base_mat)
	batch.add(Vector3(1.2, 0.5, 1.2), Vector3(x, CURB_HEIGHT + 0.75, z), top_mat)


## Urban hardscape: a chest-high kiosk / utility cabinet with a thin lit sign.
func _add_kiosk(batch: BoxBatcher, x: float, z: float, g_rng: RandomNumberGenerator,
		body_mat: Material, sign_mat: Material) -> void:
	var h: float = g_rng.randf_range(1.8, 2.6)
	var bw: float = g_rng.randf_range(1.1, 1.7)
	batch.add(Vector3(bw, h, bw * 0.7), Vector3(x, CURB_HEIGHT + h * 0.5, z), body_mat)
	batch.add(Vector3(bw * 0.85, 0.28, 0.06),
			Vector3(x, CURB_HEIGHT + h * 0.78, z + bw * 0.36), sign_mat)


## Urban hardscape: a low bench, randomly oriented.
func _add_bench(batch: BoxBatcher, x: float, z: float, g_rng: RandomNumberGenerator,
		mat: Material) -> void:
	var length: float = g_rng.randf_range(1.6, 2.2)
	var size: Vector3 = Vector3(0.5, 0.45, length) if g_rng.randf() < 0.5 \
			else Vector3(length, 0.45, 0.5)
	batch.add(size, Vector3(x, CURB_HEIGHT + 0.225, z), mat)


func _add_line(size: Vector3, at: Vector3, mat: Material) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	line.mesh = box
	line.position = at
	add_child(line)


## A dark paved slab under the whole grid (plus a road-width margin) — the road
## surface the streets and blocks sit on, so the city reads as ground, not gaps.
func _build_ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ASPHALT_COLOR
	mat.roughness = 0.95
	var left: float = _col_x[0] - _col_w[0] * 0.5 - road_width
	var right: float = _col_x[cols - 1] + _col_w[cols - 1] * 0.5 + road_width
	var front: float = _row_z[0] + _row_d[0] * 0.5 + road_width
	var back: float = _row_z[rows - 1] - _row_d[rows - 1] * 0.5 - road_width
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(right - left, front - back)
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3((left + right) * 0.5, 0.02, (front + back) * 0.5)
	add_child(ground)
