class_name CityLayout
extends Node3D

## A seeded city-block layout (GAMEPLAY-DESIGN B4, v1.52). Places WorldBuildings
## on a cols×rows grid of blocks separated by roads, so the "streets" are a real
## connected grid, not a scatter (the user's flag: "no continuity, not arranged
## by street blocks"). Deterministic: same seed = same city. No building can
## overlap another — each footprint is capped to its block, and blocks sit a
## full road-width apart, so the streets never close up. Amber centerlines mark
## the roads. First client: the dev room; the game-world city is this node at
## scale.

@export var layout_seed: int = 1
@export var cols: int = 3
@export var rows: int = 2
## Buildable area per block; a building's footprint is capped to it (minus a
## margin), which is what guarantees the streets stay open.
@export var block_size: float = 32.0
## Gap between blocks — the street. Wide by design (the user's ask).
@export var road_width: float = 16.0
## Row 0 sits at this local z; rows march into -Z.
@export var front_z: float = -64.0
@export var min_floors: int = 12
@export var max_floors: int = 34
## Chance a block is an empty lot — some gaps in the skyline.
@export var empty_chance: float = 0.1
## Chance a building is tiered (setbacks) rather than a plain box.
@export var setback_chance: float = 0.4

const ROADLINE_COLOR: Color = Color(1.0, 0.75, 0.2)
const ROADLINE_ENERGY: float = 2.5
const ROADLINE_WIDTH: float = 0.5
## Minimum gap between a footprint and its block edge (keeps streets clear).
const BUILDING_MARGIN: float = 4.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var pitch: float = block_size + road_width
	var col0_x: float = -(cols - 1) * 0.5 * pitch
	_build_roads(pitch, col0_x)
	for r: int in rows:
		for c: int in cols:
			if rng.randf() < empty_chance:
				continue
			_spawn_building(rng, r, c, col0_x + c * pitch, front_z - r * pitch)


func _spawn_building(rng: RandomNumberGenerator, r: int, c: int,
		bx: float, bz: float) -> void:
	var floors: int = rng.randi_range(min_floors, max_floors)
	# Taller → wider, capped to the block so a tall tower never eats its street.
	var lean: float = float(floors - min_floors) / maxf(float(max_floors - min_floors), 1.0)
	var fp: float = clampf(16.0 + lean * 18.0 + rng.randf_range(-3.0, 3.0),
			16.0, block_size - BUILDING_MARGIN)
	var building := WorldBuilding.new()
	# A distinct, stable seed per block so each building is its own thing.
	building.building_seed = layout_seed * 131 + (r * cols + c)
	building.footprint = fp
	building.target_floors = floors
	building.open_floors = maxi(2, int(round(float(floors) * 0.55)))
	building.interior_height = rng.randf_range(3.6, 5.6)
	if rng.randf() < setback_chance:
		building.setback_tiers = rng.randi_range(3, 4)
		building.top_footprint = fp * rng.randf_range(0.45, 0.6)
	building.position = Vector3(bx, 0.0, bz)
	add_child(building)


## Amber centerlines down every street (both directions, incl. the perimeter),
## so the block grid reads as a connected road network.
func _build_roads(pitch: float, col0_x: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROADLINE_COLOR
	mat.emission_enabled = true
	mat.emission = ROADLINE_COLOR
	mat.emission_energy_multiplier = ROADLINE_ENERGY
	var grid_w: float = cols * pitch
	var grid_d: float = rows * pitch
	var mid_z: float = front_z - (rows - 1) * 0.5 * pitch
	for c: int in cols + 1:
		var lx: float = col0_x + (float(c) - 0.5) * pitch
		_add_line(Vector3(ROADLINE_WIDTH, 0.05, grid_d), Vector3(lx, 0.03, mid_z), mat)
	for r: int in rows + 1:
		var lz: float = front_z - (float(r) - 0.5) * pitch
		_add_line(Vector3(grid_w, 0.05, ROADLINE_WIDTH), Vector3(0.0, 0.03, lz), mat)


func _add_line(size: Vector3, at: Vector3, mat: Material) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	line.mesh = box
	line.position = at
	add_child(line)
