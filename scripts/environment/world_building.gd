class_name WorldBuilding
extends Node3D

## A generated building placed in the game world (GAMEPLAY-DESIGN B3/B4,
## v1.47 step 3a). Wraps the seeded BuildingGenerator + the runtime
## MenuBuilding builder: exported seed / height / open-floor count in, a
## flyable greybox tower out. Its origin is the building's base — place the
## node at ground level. The menu proved the builder; this is the same code
## in the world, minus the menu furniture (its open floors carry no leaf, so
## MenuFloorFrame gives them a plain windowed opening, no label or commit
## zone). The dev room places ONE as a specimen; the city (later) places many.

@export var building_seed: int = 1
@export var target_floors: int = 28
## Enterable (windowed) floors, spread up the tower by the generator's bands;
## every other floor fills sealed / under-construction by the seed.
@export var open_floors: int = 5
## Kept small against the big walls (v1.50 scale pass): a window you thread,
## not an open bay — so floors read as solid architecture, entry is a skill.
@export var window_size: Vector2 = Vector2(3.0, 2.4)
@export var sill: float = 0.8
## Big-world footprint (v1.50): the drone is a 0.28 m box, these are proper
## towers. Uniform across a building's floors for now; setbacks arrive next.
@export var footprint: float = 24.0
## Floor-to-ceiling height (v1.50). Varied across buildings for a richer
## skyline and interior — a taller value = fewer, grander floors per metre.
@export var interior_height: float = 4.0
## Setbacks / tiers (v1.52, 3b-ii): the footprint steps down in this many
## discrete tiers up the tower (1 = a plain box). The wider tier below leaves a
## ledge on the narrower tier above (MenuBuilding sizes each slab to its wider
## neighbour). The classic stepped-skyscraper silhouette.
@export var setback_tiers: int = 1
## Footprint at the top tier when tiered (0 = no setback, = base footprint).
@export var top_footprint: float = 0.0
## Per-side openings (v1.62): 4 bools [front +Z, back -Z, right +X, left -X],
## set by CityLayout to open only the sides facing the downtown core. Empty =
## all four sides open (cross_windows), the standalone / dev-room default.
@export var open_sides: Array = []

## Interiors (B3): fill open floors with generated open-plan interiors.
@export var interiors_enabled: bool = false
## District (CityLayout.PropStyle: 0 urban / 1 natural / 2 cyber) — palette + profile.
@export var district: int = BuildingProgram.NATURAL
## Testbed override: force one program on every open floor (empty = use the
## per-district vertical profile).
@export var force_program: StringName = &""
## When true, frames defer interior build to this node's distance LOD (Beat 5).
@export var interior_lod: bool = false
## Interior tuning knobs passed to InteriorGenerator (empty = its defaults).
@export var interior_knobs: Dictionary = {}
## Distance LOD (B3, spec §9): furnish open floors only within this radius of the
## drone; free them beyond. Hysteresis avoids thrashing at the boundary.
@export var interior_lod_radius: float = 140.0
@export var interior_lod_hysteresis: float = 20.0

## The player drone (group "player"), found lazily; interiors furnish near it.
var _drone: Node3D = null
var _furnished: bool = false


## The footprint of floor k of `total`, stepped down in discrete tiers from the
## base `footprint` to `top_footprint`. A box (no setback) when tiers <= 1.
func _footprint_at(k: int, total: int) -> float:
	if setback_tiers <= 1 or top_footprint <= 0.0 or total <= 1:
		return footprint
	var tier: int = mini(k * setback_tiers / total, setback_tiers - 1)
	return lerpf(footprint, top_footprint, float(tier) / float(setback_tiers - 1))


func _ready() -> void:
	# Leafless open specs: the generator places them like menu leaves, but with
	# no leaf they render as plain enterable windows (the menu→world bridge).
	var open_specs: Array = []
	for _i: int in open_floors:
		open_specs.append({"window": window_size, "sill": sill})
	# Under-construction floors sprinkle among the sealed ones (the user is fine
	# with them mid-building — they now carry a full column grid, so nothing
	# floats). The generator's crown_at_top mode stays available for a future
	# "topping-out" building type.
	var floors: Array = BuildingGenerator.generate(
			building_seed, open_specs, target_floors)
	# Interiors (B3): the per-district vertical program profile, one program per
	# floor (bottom->top). Only OPEN floors are furnished below.
	var programs: Array = []
	if interiors_enabled:
		programs = BuildingProgram.programs_for(district, building_seed, floors.size())
	# Stamp world-building geometry onto every floor (open + filler): a tapered
	# footprint sizes walls and slabs (setbacks), crossed windows make open
	# floors enterable from any direction, and the interior height sets the pitch.
	for k: int in floors.size():
		var spec: Dictionary = floors[k]
		spec["footprint"] = _footprint_at(k, floors.size())
		spec["cross_windows"] = true
		spec["interior_height"] = interior_height
		if not open_sides.is_empty():
			spec["open_sides"] = open_sides
		# Generate an interior for open floors only (sealed / under-construction
		# stay hollow). Seed derives from the building seed + floor index (F4), so
		# it never disturbs the layout RNG stream.
		if interiors_enabled and spec.get("state", MenuFloorFrame.STATE_OPEN) == MenuFloorFrame.STATE_OPEN:
			var prog: StringName = force_program if force_program != &"" else programs[k]
			var fseed: int = building_seed * 1000003 + k
			spec["interior"] = InteriorGenerator.generate(prog, fseed,
					spec["footprint"], interior_height, spec.get("open_sides", []), interior_knobs)
			spec["district"] = district
			spec["interior_lod_managed"] = interior_lod
	add_child(MenuBuilding.create(floors))
	# City LOD: only poll distance when this building manages its own interiors.
	set_process(interior_lod)


## Distance LOD driver: furnish open floors when the drone is within radius, free
## them when it leaves (with hysteresis). No-op unless interior_lod is set.
func _process(_delta: float) -> void:
	if not interior_lod:
		return
	if _drone == null:
		_drone = get_tree().get_first_node_in_group(&"player") as Node3D
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
