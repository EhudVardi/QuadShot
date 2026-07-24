class_name BuildingGenerator
extends RefCounted

## Seeded, deterministic building generator (GAMEPLAY-DESIGN B3/B4, v1.46
## step 2). Pure function: given a seed, the leaves that MUST be reachable, and
## a height, it emits the floor-spec list MenuBuilding already consumes — no
## new rendering path (the v1.43 bet paying out a second time). Same seed +
## same inputs = same building forever, so F4's portable save reaches menu
## geometry: a save naming a seed names a building.
##
## First client: the menu's submenu towers (v1.44 "fill it, don't shrink the
## gap" — a two-option submenu is a full-height building with the options as
## open floors among sealed / under-construction ones). The SAME function
## fills the game-world skyline later (B3/B4 proper); the menu is the
## rehearsal. theater_generator.gd is the seeded discipline this mirrors.

## Chance a filler (closed) floor is under construction rather than sealed — a
## minority, so the silhouette reads mostly solid with the occasional gap.
const UNDER_CONSTRUCTION_CHANCE: float = 0.3


## required_leaves: open-floor spec dicts (leaf/label/window/sill/pixel, maybe
## submenu) — each is GUARANTEED exactly one open floor. target_floors: total
## height; clamped up if it cannot hold every required leaf. Returns the
## bottom-to-top floor list MenuBuilding.create() consumes.
static func generate(seed_value: int, required_leaves: Array,
		target_floors: int) -> Array:
	var open_count: int = required_leaves.size()
	var floor_count: int = maxi(target_floors, open_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Each required leaf owns one vertical BAND, so the options spread up the
	# tower instead of clumping; the seed places the open floor inside its band.
	# Bands are disjoint index ranges, so every band's pick is distinct — the
	# "exactly one open floor per leaf" guarantee falls out for free. Leaf
	# order is preserved bottom-to-top (predictable menu navigation).
	var open_at: Dictionary = {}
	for i: int in open_count:
		var band_start: int = i * floor_count / open_count
		var band_end: int = (i + 1) * floor_count / open_count
		open_at[rng.randi_range(band_start, band_end - 1)] = required_leaves[i]

	var floors: Array = []
	for k: int in floor_count:
		if open_at.has(k):
			floors.append(open_at[k])
		elif rng.randf() < UNDER_CONSTRUCTION_CHANCE:
			floors.append({"state": MenuFloorFrame.STATE_UNDER_CONSTRUCTION})
		else:
			floors.append({"state": MenuFloorFrame.STATE_SEALED})
	return floors
