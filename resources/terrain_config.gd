class_name TerrainConfig
extends TunableConfig

## The voxel terrain's tunables (GAMEPLAY-DESIGN P1.9, phase 1).
##
## SMOOTH ROLLING GROUND over vast distances, which is the user's founding pillar
## — *"one of the stones on my original dream is truly vast environments"* — with
## Delta Force's sprawling outdoor maps as the reference.
##
## It is a HEIGHTMAP: one height per position, no overhangs, no caves, no digging.
## Nothing in the design asks for those, and a cave here is a placed structure
## rather than a terrain feature. The saving over a volumetric world is enormous
## and it is spent on reach instead — the ground is sampled by concentric detail
## rings, so a 6 km world costs about what a small dense one does.
##
## Every field here is a slider under the overlay's TERRAIN section, because a
## landscape is judged by flying it rather than by arithmetic.

@export_group("Extent")
## Nominal half-width of the world, metres. ADVISORY ONLY since the ground became
## ringed: the real reach is `TerrainMesh.reach_m()`, which falls out of how many
## detail rings there are. Kept because a sortie still wants to say how big its
## map is, and because the clearing and the checks want a sampling area.
@export var extent_m: float = 320.0

@export_group("Resolution")
## Spacing of the height samples in the FINEST detail ring, metres. Two triangles
## span one cell, so this is how finely the ground is described where the pilot
## is — and every ring outward doubles it.
##
## It is the cost dial and it bites quadratically, but not through the world's
## size: reach comes from `TerrainMesh.ring_count`, and each ring pays
## `ring_cells` squared however big the world is.
@export var cell_m: float = 4.0

@export_group("Shape")
## Peak-to-trough height range of the landscape, metres. It means what it says:
## the field is normalised against fractal noise's real span, not its nominal one.
@export var amplitude_m: float = 46.0
## How closely hills repeat. Higher = busier ground, lower = long open sweeps.
@export var noise_frequency: float = 0.0032
## Detail layers. 1 is a smooth swell; more adds finer relief on top.
@export var noise_octaves: int = 4
## Blend toward RIDGED noise, 0..1. At 0 the ground rolls like dunes; at 1 it
## grows ridges and canyon walls, which is what the canyon and mesa biomes want.
## The single most character-changing number here after the two scale dials.
@export_range(0.0, 1.0, 0.01) var ridge: float = 0.35
## Heights below this are clamped flat, forming basins and valley floors. It is
## what stops a landscape being uniformly bumpy, and it is where a city or an
## airbase would sensibly sit.
@export var floor_m: float = -6.0
## Radius from the origin, in metres, inside which the ground is forced flat at
## `floor_m`. THE ARENA'S OWN FLOOR — a sortie's objective, its garrison rings
## and its pads all need somewhere level to stand, and phase 1 has no way yet to
## flatten a footprint on demand. 0 disables it.
@export var clearing_radius_m: float = 0.0
## How far the clearing takes to blend back into the landscape, metres. A hard
## edge would be a cliff ringing every fight.
@export var clearing_falloff_m: float = 70.0


func save_path() -> String:
	return "user://terrain_config.tres"


func defaults_path() -> String:
	return "res://resources/default_terrain_config.tres"
