extends SceneTree

## Headless check for the VOXEL TERRAIN (GAMEPLAY-DESIGN P1.9, phase 1).
##
## THE ONE THAT MATTERS IS "THE MESH AGREES WITH THE QUERY", and it is worth
## saying why before the others. Phase 2 teaches the whole game to stop assuming
## the ground is a flat plane at y = 0: enemies will hold station above
## `height_at`, bombs will detonate at it, sortie units will be placed on it, the
## ingress will put a pilot down on it. Every one of those consumers trusts that
## the number the function returns is the surface a pilot can see. The day those
## drift is the day bombs go off underground and turrets float, and NOTHING else
## in the suite would notice — so it is asserted against the real built mesh
## rather than against the generator that produced it.
##
## The rest are the properties a landscape has to have to be a landscape:
##
##   1. It is deterministic from (config, seed), or a theater cannot name its
##      ground with a number.
##   2. `amplitude_m` means the metres it says. It did not: fractal noise never
##      reaches its nominal range, and the field delivered 34 m for an asked-for
##      46 until it was normalised.
##   3. `ridge` changes the LANDFORM and not the elevation — two runs, one
##      variable. It did not: folding a field with `abs()` biases it toward its
##      crests, and the mean sat 33 m high at ridge 0.9 under a comment claiming
##      it was handled.
##   4. The ground is SMOOTH, and every face is wound OUTWARD so the map is
##      sealed. The user found that second one from the cockpit and this check
##      did not, which is why it has a stage now.
##   5. VASTNESS IS CHEAP — reach grows exponentially with ring count while
##      triangle cost grows linearly. That is the founding claim of the whole
##      architecture, and if it ever stops being true the design's "truly vast
##      environments" pillar quietly stops being affordable.
##
## Run: <godot> --headless -s scripts/tests/terrain_check.gd --path .

## Height differences below this are the same height. Terrain heights are exact
## multiples of the step, so this only absorbs float noise.
const EPSILON: float = 0.001
## How far `amplitude_m` may be from the relief it actually produces, as a
## fraction. Generous, because quantisation and the ridge blend both nibble at
## the extremes — but far tighter than the 26% error it was written to catch.
const AMPLITUDE_TOLERANCE: float = 0.15

var _failures: int = 0
var _started: bool = false
var _arena: Node3D


func _initialize() -> void:
	# The pure half needs no tree and runs immediately.
	_check_determinism()
	_check_amplitude_is_honest()
	_check_ridge_changes_shape_not_height()
	_check_the_ground_is_smooth()
	# THE BUILT-MESH HALF WAITS FOR A REAL FRAME. A node added during
	# `_initialize` is not `is_inside_tree()` yet, so `_ready` has not run and the
	# terrain has no mesh at all — the trap that bit three separate rigs in one
	# day on 2026-08-07.
	process_frame.connect(_run_built_stages)


func _run_built_stages() -> void:
	if _started:
		return
	_started = true
	_check_every_face_points_outward()
	_check_the_mesh_agrees_with_the_query()
	_check_vastness_is_cheap()
	_check_the_collision_is_the_picture()
	_report()


func _config() -> TerrainConfig:
	return (load("res://resources/default_terrain_config.tres") as TerrainConfig)\
			.duplicate() as TerrainConfig


## ---------- a theater must be able to name its ground with a number ----------

func _check_determinism() -> void:
	var config: TerrainConfig = _config()
	var first := TerrainField.new(config, 99)
	var second := TerrainField.new(config, 99)
	var other := TerrainField.new(config, 100)
	var same: bool = true
	var differs: bool = false
	for i: int in 200:
		var x: float = -300.0 + float(i) * 3.0
		var z: float = 40.0 - float(i) * 2.0
		if absf(first.height_at(x, z) - second.height_at(x, z)) > EPSILON:
			same = false
		if absf(first.height_at(x, z) - other.height_at(x, z)) > EPSILON:
			differs = true
	_expect(same, "the same seed builds the same landscape, so a node can name its ground with a number")
	# Without this, a generator that ignored its seed entirely would pass the
	# assertion above perfectly.
	_expect(differs, "and a different seed builds a different one")


## ---------- a slider has to mean the thing it says ----------

## `amplitude_m` LIED BY 26% and this is the assertion that would have caught it.
## Fractal noise does not reach its nominal -1..1, so multiplying by the asked
## amplitude under-delivers; the field is normalised by a measured constant now.
## A tunable whose number is not what it produces is one the human has to learn a
## fudge factor for.
func _check_amplitude_is_honest() -> void:
	for asked: float in [40.0, 90.0, 160.0]:
		var config: TerrainConfig = _config()
		config.amplitude_m = asked
		config.ridge = 0.0
		# The floor and the clearing both clip the field, and this stage is about
		# the noise rather than about them.
		config.floor_m = -10000.0
		config.clearing_radius_m = 0.0
		var measured: Dictionary = _span(TerrainField.new(config, 7))
		var error: float = absf(float(measured["range"]) - asked) / asked
		_expect(error < AMPLITUDE_TOLERANCE,
				"amplitude %.0f m delivers %.1f m of relief (%.0f%% off)"
				% [asked, measured["range"], error * 100.0])


## ---------- two runs, one variable ----------

## `ridge` is the LANDFORM dial. It must change the shape of the ground and leave
## its elevation alone — and it did not: the folded field is biased toward its
## own crests, so the mean sat 33 m high at ridge 0.9 while a comment claimed the
## recentring was handled. A comment describing an intention rather than the code
## is the failure v2.33 named, and this is that lesson applied to new work on the
## day it lands rather than two weeks later.
func _check_ridge_changes_shape_not_height() -> void:
	var rolling: TerrainConfig = _config()
	rolling.ridge = 0.0
	rolling.floor_m = -10000.0
	rolling.clearing_radius_m = 0.0
	var ridged: TerrainConfig = rolling.duplicate() as TerrainConfig
	ridged.ridge = 0.9
	var flat: Dictionary = _span(TerrainField.new(rolling, 11))
	var sharp: Dictionary = _span(TerrainField.new(ridged, 11))
	var drift: float = absf(float(sharp["mean"]) - float(flat["mean"]))
	_expect(drift < rolling.amplitude_m * 0.1,
			"the ridge dial moves the LANDFORM, not the elevation — mean %.1f m against %.1f m"
			% [flat["mean"], sharp["mean"]])
	# AND IT MUST ACTUALLY DO SOMETHING. A dial that changed nothing would sail
	# through the assertion above, which is the whole point of asking.
	var moved: float = 0.0
	var rolling_field := TerrainField.new(rolling, 11)
	var ridged_field := TerrainField.new(ridged, 11)
	for i: int in 300:
		var x: float = -280.0 + float(i) * 1.9
		var z: float = 260.0 - float(i) * 1.7
		moved = maxf(moved, absf(rolling_field.height_at(x, z)
				- ridged_field.height_at(x, z)))
	_expect(moved > rolling.amplitude_m * 0.15,
			"while genuinely reshaping the ground — %.1f m of difference at its widest"
			% moved)


## ---------- it has to be SMOOTH ----------

## "Smooth" has to mean something testable rather than a wish, and a heightmap is
## one line of arithmetic away from being a staircase — so this asserts the
## absence of quantisation directly rather than trusting that nobody adds it.
func _check_the_ground_is_smooth() -> void:
	var config: TerrainConfig = _config()
	var field := TerrainField.new(config, 3)
	var cell: float = field.effective_cell_m()
	# A CELL IS NOT FLAT. Quantised ground returns one height for every point in a
	# cell by construction; a smooth surface must vary across one.
	var varying: int = 0
	for i: int in 200:
		var x: float = (floorf((-200.0 + float(i) * 2.7) / cell) + 0.5) * cell
		var z: float = (floorf((90.0 + float(i) * 1.3) / cell) + 0.5) * cell
		var base: float = field.height_at(x, z)
		if absf(field.height_at(x + cell * 0.45, z - cell * 0.45) - base) > 0.02:
			varying += 1
	_expect(varying > 150,
			"the surface varies WITHIN a cell — %d of 200 samples, so it is smooth ground"
			% varying)
	# AND NO STAIRCASE. Walking a line, the height must change on almost every
	# step; a quantised field would repeat the same value across whole runs.
	var repeats: int = 0
	var previous: float = field.height_at(-300.0, 12.0)
	for i: int in range(1, 400):
		var here: float = field.height_at(-300.0 + float(i) * 0.9, 12.0)
		if is_equal_approx(here, previous):
			repeats += 1
		previous = here
	_expect(repeats < 20,
			"and walking a line changes height almost every step (%d repeats in 400), so nothing is quantised"
			% repeats)


## ---------- the map has to be SEALED ----------

## THE USER FOUND THIS ONE FROM THE COCKPIT AND THIS CHECK DID NOT — *"i think
## there's a rendering issue, some faces are missing, the map is not sealed"*.
##
## Every wall quad was wound backwards: measured at 40,912 walls against 51,200
## correctly-wound tops, so with back-face culling the landscape had no sides at
## all and you could see straight through a hill into the geometry behind it.
##
## THE CHECK PASSED ANYWAY, and that is the lesson rather than the fix. It
## asserted the collision's triangle COUNT and the mesh's agreement with the
## height query, and both of those are blind to facing — the collider does not
## care about winding and the query only reads the tops. A mutation that inverted
## every wall in the game would have gone green. It is the same family as the
## eight unfailable checks before it: *what is asserted is one link short of what
## matters.*
##
## Compared as GEOMETRY against ITSELF: the right-hand normal off each triangle's
## winding must match the normal the builder declared for it. That is exact, needs
## no convention to be assumed, and is anchored by the tops — which were always
## correct and are visibly correct on screen.
func _check_every_face_points_outward() -> void:
	var terrain: TerrainMesh = _build(_config(), 17)
	var backwards: int = 0
	var ground: int = 0
	var skirts: int = 0
	# EVERY RING, not just the fine one: a distant ring drawn inside-out is just
	# as broken and much harder to notice from the cockpit.
	for mesh: ArrayMesh in _ring_meshes(terrain):
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in range(0, vertices.size() - 2, 3):
			if _is_skirt(vertices, i):
				skirts += 1
				continue
			ground += 1
			# UP rather than the declared normal, and that is the fix this stage
			# needed when the ground went smooth. Ground normals are now ANALYTIC
			# — taken from the field's slope rather than from the triangle — so
			# comparing a triangle's winding against its own shaded normal stopped
			# being a test of anything. Which way is up has not changed.
			var geometric: Vector3 = (vertices[i + 1] - vertices[i]).cross(
					vertices[i + 2] - vertices[i]).normalized()
			if geometric.y < 0.2:
				backwards += 1
	_expect(ground > 1000 and skirts > 100,
			"the landscape has %d ground faces and %d seam skirts" % [ground, skirts])
	_expect(backwards == 0,
			"and every ground face is wound UPWARD, so the map is sealed (%d backwards)"
			% backwards)
	_teardown()


## ---------- the one phase 2 depends on ----------

## THE MESH AND THE QUERY ARE THE SAME SURFACE. Every top-facing vertex in the
## built mesh is compared against `height_at` at its own position; they must
## agree exactly, because the mesh is built by sampling that function and any
## drift means the game reasons about ground the pilot cannot see.
##
## Sampled off the REAL built ArrayMesh rather than off the generator, which is
## the difference between checking the feature and checking the comment.
func _check_the_mesh_agrees_with_the_query() -> void:
	var terrain: TerrainMesh = _build(_config(), 21)
	var meshes: Array[ArrayMesh] = _ring_meshes(terrain)
	_expect(meshes.size() >= 2,
			"the terrain builds %d detail rings" % meshes.size())
	if meshes.is_empty():
		_teardown()
		return
	# THE INNERMOST RING ONLY, and that is the honest scope rather than a dodge.
	# `height_at` is the FINE answer - the surface the game reasons about and the
	# pilot stands on - while an outer ring deliberately draws a coarser version
	# of the same landscape. Asserting agreement across LOD levels would be
	# asserting that level of detail does not work.
	var mesh: ArrayMesh = meshes[0]
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var checked: int = 0
	var disagreed: int = 0
	var worst: float = 0.0
	# TRIANGLE CENTROIDS, not vertices. A top quad's four corners sit ON cell
	# boundaries, and a boundary belongs to the NEXT cell along — so comparing
	# vertices reported 6285 disagreements against a terrain that was correct.
	# The centroid of a top triangle is the only point guaranteed to be strictly
	# inside the cell that triangle belongs to.
	for i: int in range(0, vertices.size() - 2, 3):
		# SKIRTS ARE EXCLUDED, and it is not a dodge. A skirt hangs BELOW the
		# surface on purpose to hide the seam between two detail rings, so of
		# course its centroid does not sit on the ground — asserting otherwise
		# would be asserting that the crack cover does not cover the crack.
		if _is_skirt(vertices, i):
			continue
		var centroid: Vector3 = (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
		var query: float = terrain.height_at(centroid.x, centroid.z)
		var gap: float = absf(query - centroid.y)
		worst = maxf(worst, gap)
		if gap > EPSILON:
			disagreed += 1
		checked += 1
		if checked >= 20000:
			break
	_expect(checked > 1000,
			"with %d ground triangles to compare against the height query" % checked)
	_expect(disagreed == 0,
			"and the query matches the surface EXACTLY — %d disagreements, worst %.4f m"
			% [disagreed, worst])
	_teardown()


## ---------- the world must not have a hole in it ----------

## VASTNESS IS THE CHEAP PART, and this is the assertion that says so.
##
## The whole architecture rests on one claim: rings make reach grow
## EXPONENTIALLY while cost grows LINEARLY, because each ring doubles its cell
## size while covering four times the area for the same cell count. If that ever
## stops being true the design's founding pillar - truly vast environments -
## quietly stops being affordable, and nothing else would notice.
##
## Measured as a ratio between two builds rather than against a magic number, so
## it stays true if the ring size or the base cell is retuned.
func _check_vastness_is_cheap() -> void:
	var near: TerrainMesh = _build(_config(), 5, 2)
	var near_reach: float = near.reach_m()
	var near_tris: int = _count_triangles(near)
	_teardown()
	var far: TerrainMesh = _build(_config(), 5, 6)
	var far_reach: float = far.reach_m()
	var far_tris: int = _count_triangles(far)
	_teardown()
	# Four more rings is sixteen times the reach.
	_expect(far_reach > near_reach * 12.0,
			"four more rings reach %.0f m against %.0f m - %.0fx the world"
			% [far_reach, near_reach, far_reach / maxf(near_reach, 1.0)])
	# ...for at most three times the triangles. Linear cost, exponential reach.
	_expect(far_tris < near_tris * 4,
			"for %d triangles against %d - %.1fx the cost, so reach is exponential and cost is linear"
			% [far_tris, near_tris, float(far_tris) / maxf(float(near_tris), 1.0)])
	_expect(far_reach > 4000.0,
			"and six rings alone reach %.1f km, which is the scale the design asks for"
			% (far_reach / 1000.0))


func _count_triangles(terrain: TerrainMesh) -> int:
	var total: int = 0
	for mesh: ArrayMesh in _ring_meshes(terrain):
		total += mesh.surface_get_array_len(0) / 3
	return total


func _check_the_collision_is_the_picture() -> void:
	var terrain: TerrainMesh = _build(_config(), 33)
	var meshes: Array[ArrayMesh] = _ring_meshes(terrain)
	var shapes: Array[ConcavePolygonShape3D] = _ring_shapes(terrain)
	_expect(shapes.size() == terrain.collision_rings and shapes.size() < meshes.size(),
			"%d of the %d rings carry a collider - ground you can hit is ground near you"
			% [shapes.size(), meshes.size()])
	if shapes.is_empty():
		_teardown()
		return
	var shape: ConcavePolygonShape3D = shapes[0]
	var mesh_vertices: int = meshes[0].surface_get_array_len(0)
	# NOT "a collider exists" — the same COUNT of triangles, because the whole
	# reason this is a trimesh rather than the cheaper built-in heightmap shape is
	# that a pilot must be able to land on the ground they can see. A
	# HeightMapShape3D samples on its own grid rather than the ring's.
	_expect(shape.get_faces().size() == mesh_vertices,
			"built from the mesh's own triangles — %d against %d"
			% [shape.get_faces().size() / 3, mesh_vertices / 3])
	_teardown()


## Is this triangle part of a seam skirt rather than the ground?
##
## Told apart by GEOMETRY rather than by its normal, because a skirt deliberately
## carries the ground's normal so it shades invisibly. What it cannot hide is its
## footprint: a skirt is a vertical apron, so two of its three corners share an
## x/z position. No ground triangle does.
func _is_skirt(vertices: PackedVector3Array, i: int) -> bool:
	for pair: Array in [[0, 1], [1, 2], [0, 2]]:
		var a: Vector3 = vertices[i + int(pair[0])]
		var b: Vector3 = vertices[i + int(pair[1])]
		if is_equal_approx(a.x, b.x) and is_equal_approx(a.z, b.z):
			return true
	return false


## Every ring mesh the terrain built, innermost first.
func _ring_meshes(terrain: TerrainMesh) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for child: Node in terrain.get_children():
		var instance := child as MeshInstance3D
		if instance != null and instance.mesh != null:
			out.append(instance.mesh as ArrayMesh)
	return out


func _ring_shapes(terrain: TerrainMesh) -> Array[ConcavePolygonShape3D]:
	var out: Array[ConcavePolygonShape3D] = []
	for child: Node in terrain.get_children():
		var collision := child as CollisionShape3D
		if collision != null and collision.shape != null:
			out.append(collision.shape as ConcavePolygonShape3D)
	return out


## ---------- rig ----------

## Min, max and mean of the RAW surface over the whole field.
func _span(field: TerrainField) -> Dictionary:
	var lo: float = INF
	var hi: float = -INF
	var total: float = 0.0
	var count: int = 0
	var steps: int = 140
	var stride: float = 2.0 * field.config.extent_m / float(steps)
	for i: int in steps:
		for j: int in steps:
			var height: float = field.raw_height_at(
					-field.config.extent_m + float(i) * stride,
					-field.config.extent_m + float(j) * stride)
			lo = minf(lo, height)
			hi = maxf(hi, height)
			total += height
			count += 1
	return {"range": hi - lo, "min": lo, "max": hi, "mean": total / float(count)}


func _build(config: TerrainConfig, terrain_seed: int,
		rings: int = 0) -> TerrainMesh:
	_arena = Node3D.new()
	root.add_child(_arena)
	# The whole environment scene, kept intact. Reparenting the Terrain out of it
	# leaves its children owned by a node that is no longer their ancestor, which
	# Godot warns about and which buys nothing here.
	var scene: Node3D = (load("res://scenes/environment/terrain.tscn")
			as PackedScene).instantiate() as Node3D
	var terrain: TerrainMesh = scene.get_node("Terrain") as TerrainMesh
	terrain.terrain_config = config
	terrain.terrain_seed = terrain_seed
	if rings > 0:
		terrain.ring_count = rings
	# No `follow`, so the rings centre on the origin and the check is
	# deterministic rather than depending on where a drone happens to be.
	terrain.follow = null
	_arena.add_child(scene)
	return terrain


func _teardown() -> void:
	if _arena != null:
		_arena.free()
	_arena = null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[terrain_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[terrain_check]  FAIL  %s" % message)


func _report() -> void:
	if _failures == 0:
		print("[terrain_check] PASS")
	else:
		print("[terrain_check] FAIL - %d check(s)" % _failures)
	quit(0 if _failures == 0 else 1)
