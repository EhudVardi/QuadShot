class_name BuildingProgram
extends RefCounted

## Per-district vertical PROGRAM PROFILE (spec §5): height fraction -> program.
## District RESTRUCTURES the profile (Q3), so each district stacks different
## programs. Pure + deterministic per building_seed. district ids equal
## CityLayout.PropStyle values (URBAN=0, NATURAL=1, CYBER=2).

const URBAN: int = 0
const NATURAL: int = 1
const CYBER: int = 2

## Ordered bands [top_fraction, program]: a floor at height fraction f (0 ground ->
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


## Bottom->top program list, one per floor. Short buildings collapse to base bands.
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
