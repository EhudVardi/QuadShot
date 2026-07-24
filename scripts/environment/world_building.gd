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
@export var target_floors: int = 11
## Enterable (windowed) floors, spread up the tower by the generator's bands;
## every other floor fills sealed / under-construction by the seed.
@export var open_floors: int = 4
## Generous by design (B3: "windows generous") — you fly straight through.
@export var window_size: Vector2 = Vector2(4.5, 2.8)
@export var sill: float = 0.5
## Building width (B3 variety, v1.48). Uniform across this building's floors
## for now; setbacks (per-floor footprint) arrive in the next step.
@export var footprint: float = 12.0


func _ready() -> void:
	# Leafless open specs: the generator places them like menu leaves, but with
	# no leaf they render as plain enterable windows (the menu→world bridge).
	var open_specs: Array = []
	for _i: int in open_floors:
		open_specs.append({"window": window_size, "sill": sill})
	var floors: Array = BuildingGenerator.generate(
			building_seed, open_specs, target_floors)
	# Stamp world-building geometry onto every floor (open + filler): the
	# footprint sizes walls and slabs, and crossed windows make open floors
	# enterable from any direction (not just front/back like the menu).
	for spec: Dictionary in floors:
		spec["footprint"] = footprint
		spec["cross_windows"] = true
	add_child(MenuBuilding.create(floors))
