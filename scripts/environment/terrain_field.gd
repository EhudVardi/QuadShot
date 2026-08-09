class_name TerrainField
extends RefCounted

## THE HEIGHT OF THE GROUND, and nothing else (GAMEPLAY-DESIGN P1.9, phase 1).
##
## `height_at(x, z)` is the whole point of this class and it is the query the
## REST OF THE GAME will grow to depend on. Everything currently assumes the
## ground is a flat plane at y = 0 — enemy minimum altitude and station height,
## the aegis's bomb detonating "on the ground", the Lance's run, where a sortie
## places its units, where the ingress puts the pilot down on the deck, the city
## generator, crash damage. Phase 2 is teaching all of those to ask this
## function instead of assuming zero, which is why it lives on its own, is pure,
## and needs no tree, no node and no frames to answer.
##
## `height_at` RETURNS THE SURFACE THE MESH ACTUALLY DRAWS, which for a smooth
## terrain means bilinear interpolation across the finest ring's grid rather than
## the raw field. The mesh is flat between its vertices; a query that read the
## true field instead would sit slightly above the triangles in every valley and
## slightly below on every crest. Small, constant, and exactly the kind of drift
## that puts bombs underground — so the query is defined as the geometry, and
## `terrain_check` asserts it against the built mesh.
##
## Deterministic from (config, seed): the same pair always produces the same
## landscape, which is what lets a theater node name its ground with a number
## instead of shipping a heightmap.


## The practical peak-to-trough span of the fractal noise, as a fraction of its
## nominal -1..1. MEASURED rather than assumed: sampling the whole field at four
## octaves, an `amplitude_m` of 46 produced 33.9 m of relief, so the field spans
## 1.474 of 2.0. Dividing by half that makes `amplitude_m` mean the metres it
## says, which is what a slider has to do to be worth dragging.
##
## It is a constant rather than a per-build measurement on purpose: sampling the
## field to normalise the field would make the landscape's scale depend on how
## much of it you looked at, so two seeds would disagree about what 90 m means.
const FBM_SPAN: float = 0.737

## Mean of the RIDGED term, in the same normalised units. Also measured (0.5389
## over 160,000 samples), and subtracting it is what stops `ridge` doubling as an
## elevation dial.
##
## THIS WAS A COMMENT BEFORE IT WAS A CONSTANT, and that is the lesson. The line
## below used to say the recentring was handled "or the ridge dial would double
## as a raise-the-whole-world dial" — and the field's mean measured 0.6 m at
## ridge 0 against 33.4 m at ridge 0.9, so the comment described an intention
## rather than the code. Folding a symmetric field with `abs()` does not produce
## a symmetric result; it produces one biased toward its own crests.
const RIDGE_MEAN: float = 0.5389

## Everything that shapes the ground. Read live, so a slider drag re-generates.
var config: TerrainConfig
var seed_value: int = 0

var _noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()


func _init(terrain_config: TerrainConfig, terrain_seed: int = 0) -> void:
	config = terrain_config
	seed_value = terrain_seed
	_configure()


## Re-reads the config. Called when a slider moves; cheap, because the noise
## objects are configuration rather than data.
func _configure() -> void:
	# FastNoiseLite is a BUILT-IN Godot class generating values at runtime with
	# no file on disk, which is what keeps this inside the project's "no
	# third-party addons or external assets" rule. It is also the open house-rule
	# call the stargate rework parked (v1.91b); this is the first thing to spend
	# it, and it is spent on the cheapest possible reading of the rule.
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = maxi(config.noise_octaves, 1)
	_noise.frequency = maxf(config.noise_frequency, 0.00001)
	# A SECOND, INDEPENDENTLY SEEDED FIELD for the ridges. Folding one field with
	# `abs()` would put every ridge line exactly where the rolling terrain has a
	# zero crossing, so the two shapes would be locked together and the `ridge`
	# dial would only ever sharpen what was already there rather than introducing
	# a different landform.
	_ridge_noise.seed = seed_value + 7919
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_ridge_noise.fractal_octaves = maxi(config.noise_octaves, 1)
	_ridge_noise.frequency = maxf(config.noise_frequency, 0.00001)


## THE QUERY. Height of the ground under any world point, metres.
##
## This is what phase 2 will teach the whole game to ask instead of assuming
## zero, so it has to be exactly the surface the pilot can see.
func height_at(x: float, z: float) -> float:
	return height_for(x, z, effective_cell_m())


## The same query at an ARBITRARY grid resolution, which is what makes level of
## detail possible: a distant ring asks for the ground on 128 m spacing and gets
## a coarser but consistent answer from the same function. The fine answer — the
## one the game reasons about — is `height_at`.
##
## PLANAR ON THE CORRECT TRIANGLE, not bilinear, and the distinction is the whole
## reason this function is fiddly.
##
## The obvious answer is to bilinearly interpolate the four corner samples — and
## it is wrong, because a quad split into two triangles is NOT a bilinear patch.
## The two disagree everywhere except along the diagonal, by up to a quarter of
## however much the surface curves across one cell. Small, systematic, and
## exactly the kind of drift that eventually puts a bomb under the sand.
##
## So this reproduces `TerrainMesh._add_cell`'s own triangulation: the quad is
## split from the (x0, z0) corner to the (x1, z1) corner, and a point is planar
## on whichever half it falls in. The query IS the geometry, asserted against the
## built mesh by `terrain_check`.
func height_for(x: float, z: float, cell: float) -> float:
	cell = maxf(cell, 0.01)
	var ix: float = floorf(x / cell)
	var iz: float = floorf(z / cell)
	var fx: float = x / cell - ix
	var fz: float = z / cell - iz
	var x0: float = ix * cell
	var z0: float = iz * cell
	var x1: float = x0 + cell
	var z1: float = z0 + cell
	var h_a: float = raw_height_at(x0, z0)
	var h_c: float = raw_height_at(x1, z1)
	if fz >= fx:
		# Triangle (x0,z0) - (x0,z1) - (x1,z1).
		var h_b: float = raw_height_at(x0, z1)
		return h_a + (h_b - h_a) * fz + (h_c - h_b) * fx
	# Triangle (x0,z0) - (x1,z1) - (x1,z0).
	var h_d: float = raw_height_at(x1, z0)
	return h_a + (h_d - h_a) * fx + (h_c - h_d) * fz


## The surface NORMAL at a point, from central differences on the field. Analytic
## rather than averaged from triangles: it costs four samples, it is continuous
## across ring boundaries where face normals would visibly step, and it is what
## makes a dune read as a dune rather than as a fan of flat panels.
func normal_at(x: float, z: float, cell: float) -> Vector3:
	var d: float = maxf(cell, 0.01)
	var left: float = raw_height_at(x - d, z)
	var right: float = raw_height_at(x + d, z)
	var back: float = raw_height_at(x, z - d)
	var front: float = raw_height_at(x, z + d)
	return Vector3(left - right, 2.0 * d, back - front).normalized()


## The field at an exact point, before any grid sampling. Public because the mesh
## builder samples it at its own resolution and the checks want to talk about the
## landscape itself rather than about whichever ring happens to be drawing it.
func raw_height_at(x: float, z: float) -> float:
	var rolling: float = _noise.get_noise_2d(x, z)
	# Ridged: fold the second field about zero and invert, so its zero crossings
	# become crests rather than the flat middle of a swell.
	var ridged: float = 1.0 - absf(_ridge_noise.get_noise_2d(x, z))
	# `ridged` lives in 0..1 and `rolling` in -1..1, and the folded field is
	# biased toward its crests — so it is BOTH rescaled and de-meaned before
	# mixing. `ridge` then changes the landform and leaves the elevation alone,
	# which is what it is for.
	var blended: float = lerpf(rolling, (ridged * 2.0 - 1.0) - RIDGE_MEAN,
			clampf(config.ridge, 0.0, 1.0))
	# NORMALISED, because `amplitude_m` was lying by about 30%. Fractal noise does
	# not reach its nominal -1..1: measured over the whole field, an amplitude of
	# 46 m delivered 33.9 m of actual relief. A tunable whose number is not the
	# thing it produces is a tunable the human has to learn a fudge factor for, so
	# the fudge lives here instead. See `FBM_SPAN`.
	var height: float = (blended / FBM_SPAN) * config.amplitude_m * 0.5
	# THE ARENA'S FLOOR. A sortie needs level ground for its objective, its
	# garrison rings and its pads, and phase 1 has no way to flatten a footprint
	# on demand — so the middle of the world can be forced flat and blended out.
	if config.clearing_radius_m > 0.0:
		var distance: float = sqrt(x * x + z * z)
		var falloff: float = maxf(config.clearing_falloff_m, 0.01)
		var t: float = clampf(
				(distance - config.clearing_radius_m) / falloff, 0.0, 1.0)
		# Smoothstep rather than a linear blend: a linear ramp leaves a visible
		# crease exactly on the clearing's rim, which reads as a construction seam.
		height = lerpf(config.floor_m, height, t * t * (3.0 - 2.0 * t))
	return maxf(height, config.floor_m)


## The cell size actually used. A floor, nothing more — THE CELL BUDGET MOVED
## OUT OF THIS CLASS when the ground became ringed. It used to clamp cell size
## against the world's extent, which only made sense while the world was one
## uniform grid; with concentric rings the cost is `ring_cells` squared per ring
## and the world's reach is a consequence of how many rings there are, so there
## is nothing here left to clamp.
func effective_cell_m() -> float:
	return maxf(config.cell_m, 0.01)
