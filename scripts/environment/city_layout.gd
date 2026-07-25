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

# Grid geometry, computed in _ready before any building spawns.
var _col_x: Array[float] = []       ## centre x of each column
var _col_w: Array[float] = []       ## block width of each column
var _row_z: Array[float] = []       ## centre z of each row
var _row_d: Array[float] = []       ## block depth of each row
var _avenue_street: int = -1        ## interior street index that is the avenue
var _core_c: float = 0.0            ## downtown core, in column-index space
var _core_r: float = 0.0            ## downtown core, in row-index space
var _max_zone_dist: float = 1.0     ## core→farthest-corner distance (normaliser)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_lay_grid(rng)
	_build_ground()
	_build_roads()
	for r: int in rows:
		for c: int in cols:
			if rng.randf() < empty_chance:
				continue
			_spawn_building(rng, r, c)


## Compute per-column widths + per-row depths (varied grain) and their cumulative
## centres, with one wide avenue street. Centres the grid on x = 0; row 0 stays
## at front_z. Interior vertical street `i` (i in 1..cols-1) sits left of column
## i; the avenue is one such street, so it runs the full depth in -Z.
func _lay_grid(rng: RandomNumberGenerator) -> void:
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
	building.position = Vector3(_col_x[c], 0.0, _row_z[r])
	add_child(building)


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
