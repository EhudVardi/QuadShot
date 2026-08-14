extends SceneTree

## THE CITY LOAD BENCH (GAMEPLAY-DESIGN Iteration 16 / L13 phase 0.2).
##
## The user asked for *"an easy/cheap win we can do right now"* — a big city —
## and the honest half of that request is the word CHEAP. This measures what one
## costs before anybody flies it, by sweeping `CityLayout` from the shipped
## 4 x 5 up to sizes nothing has ever built, and reporting the four numbers that
## decide whether a city can grow further: triangles, meshes, colliders and the
## time it takes to generate.
##
## HEADLESS BY DEFAULT, and unusually the headless numbers are the LOAD-BEARING
## ones here. Triangles and collision shapes are counted by walking the built
## tree, so they are exact and need no renderer. `Performance`'s draw-call and
## primitive monitors read 0 without a display, so those are reported only when
## one is attached — drop `--headless` for them.
##
## `mesh nodes` IS THE DRAW-CALL PROXY and the one to watch. `BoxBatcher` merges
## every box sharing a material into one ArrayMesh, so a city's ground life costs
## a handful of meshes however many blocks it has; the buildings do not batch,
## because each is its own node with its own window pattern. That difference is
## the whole scaling story and the sweep is what makes it visible.
##
## Run:   <godot> --headless -s scripts/tests/city_load_bench.gd --path .
## WITH RENDERING (adds real draw calls and the physics-capacity probe under a
## renderer):  <godot> -s scripts/tests/city_load_bench.gd --path .

## cols x rows. The shipped city is 4 x 5 = 20 blocks; the sweep runs to 400,
## which is twenty times the content, because the point is to find where it
## stops being cheap rather than to confirm the current one fits.
const GRIDS: Array = [
	[4, 5], [6, 8], [8, 10], [12, 15], [16, 20], [20, 20],
]
## Both, on every grid. Interiors are the single biggest cost multiplier in the
## generator and the shipped city has them ON, so a sweep that measured only one
## would answer the wrong question.
const INTERIOR_MODES: Array[bool] = [false, true]

## Matches scenes/environment/city.tscn, so the sweep measures the shipped city's
## parameters at other sizes rather than a bench's own invented city.
const SEED: int = 42
const BLOCK_SIZE: float = 32.0
const ROAD_WIDTH: float = 16.0
const MIN_FLOORS: int = 10
const MAX_FLOORS: int = 30

## The scaled city (L13 phase 0.3), matching scenes/environment/scaled_city.tscn:
## every length times the Roc's body over the Kestrel's, so a 3 m aircraft threads
## these streets the way a 0.28 m one threads the human city.
const SCALED_WORLD_SCALE: float = 10.714
const SCALED_BLOCK: float = 342.9
const SCALED_ROAD: float = 171.4
const SCALED_COLS: int = 5
const SCALED_ROWS: int = 6

var _rows: Array[Dictionary] = []
var _failures: PackedStringArray = []


## The sweep, flattened, one cell per frame.
##
## ONE CELL PER FRAME IS NOT STYLE, IT IS REQUIRED, and the first version of this
## file got it wrong in a way worth recording. It built and measured every grid
## inside `_initialize`, which produced a full table of zeroes: inside
## `_initialize` the tree has not started, so `add_child` does NOT run `_ready`
## and nothing generated at all. Every row read 0 triangles, 0 colliders and
## 1 node. The anti-deletion asserts are what turned that into a red run instead
## of a plausible-looking table — a generator that never ran and a generator with
## nothing in it are the same reading.
var _cells: Array = []
var _cell: int = 0
var _live: CityLayout


func _initialize() -> void:
	print("[city] load sweep — seed %d, block %.0f m, road %.0f m, %d-%d floors, display %s"
			% [SEED, BLOCK_SIZE, ROAD_WIDTH, MIN_FLOORS, MAX_FLOORS,
			DisplayServer.get_name()])
	for grid: Array in GRIDS:
		for interiors: bool in INTERIOR_MODES:
			_cells.append([int(grid[0]), int(grid[1]), interiors,
					1.0, BLOCK_SIZE, ROAD_WIDTH])
	# The shipped scaled city (scenes/environment/scaled_city.tscn), measured with
	# its own numbers rather than a bench's guess at them, so this row moves the
	# day that scene does.
	_cells.append([SCALED_COLS, SCALED_ROWS, false, SCALED_WORLD_SCALE,
			SCALED_BLOCK, SCALED_ROAD])
	process_frame.connect(_on_frame)


## The furnished-interior probe (see `_furnished_probe`): grid, and how many
## frames to let the LOD driver run before re-counting.
const FURNISH_GRID: Array = [16, 20]
const FURNISH_FRAMES: int = 4

var _phase: int = 0
var _furnish_city: CityLayout
var _furnish_wait: int = 0
var _bare_triangles: int = 0
var _bare_meshes: int = 0
var _furnished: Dictionary = {}


func _on_frame() -> void:
	match _phase:
		0:
			if _cell >= _cells.size():
				_phase = 1
				return
			var cell: Array = _cells[_cell]
			_measure(int(cell[0]), int(cell[1]), bool(cell[2]),
					float(cell[3]), float(cell[4]), float(cell[5]))
			_cell += 1
		1:
			_start_furnished_probe()
			_phase = 2
		2:
			_furnish_wait -= 1
			if _furnish_wait <= 0:
				_finish_furnished_probe()
				_report()


## WHAT THE SWEEP ABOVE CANNOT SEE, and it is the answer to "can the city go
## bigger".
##
## The sweep reports identical triangle counts with interiors on and off, which
## looks like a dead flag and is not: `WorldBuilding` manages its interiors by
## DISTANCE LOD, furnishing only within `interior_lod_radius` of whatever is in
## the `player` group. A bench with no pilot in it therefore measures a city
## whose interiors have all been generated and none built.
##
## So this puts a stand-in in the player group at the city's centre and lets the
## LOD driver run. That is the real in-game situation rather than a forced one,
## and it turns the interior question from "what does the city cost" into "what
## does the neighbourhood around the pilot cost" — which is a constant, not a
## function of city size.
func _start_furnished_probe() -> void:
	_furnish_city = CityLayout.new()
	_furnish_city.layout_seed = SEED
	_furnish_city.cols = int(FURNISH_GRID[0])
	_furnish_city.rows = int(FURNISH_GRID[1])
	_furnish_city.block_size = BLOCK_SIZE
	_furnish_city.road_width = ROAD_WIDTH
	_furnish_city.min_floors = MIN_FLOORS
	_furnish_city.max_floors = MAX_FLOORS
	_furnish_city.interiors_enabled = true
	root.add_child(_furnish_city)
	_furnish_city.rebuild()
	var bare: Dictionary = {"meshes": 0, "triangles": 0, "colliders": 0,
			"nodes": 0}
	_walk(_furnish_city, bare)
	_bare_triangles = int(bare["triangles"])
	_bare_meshes = int(bare["meshes"])
	# The stand-in sits at the middle of the grid, which under the generator's
	# zoning is the downtown core — the densest neighbourhood in the city, so the
	# figure this produces is the worst case rather than an average one.
	var pilot := Node3D.new()
	pilot.add_to_group(&"player")
	root.add_child(pilot)
	pilot.global_position = Vector3(0.0, 40.0,
			-BLOCK_SIZE * float(int(FURNISH_GRID[1])) * 0.5)
	_furnish_wait = FURNISH_FRAMES


func _finish_furnished_probe() -> void:
	var full: Dictionary = {"meshes": 0, "triangles": 0, "colliders": 0,
			"nodes": 0}
	_walk(_furnish_city, full)
	var near: int = 0
	for child: Node in _furnish_city.get_children():
		if child is WorldBuilding and (child as Node3D).global_position \
				.distance_to(Vector3(0.0, 0.0,
				-BLOCK_SIZE * float(int(FURNISH_GRID[1])) * 0.5)) \
				< (child as WorldBuilding).interior_lod_radius:
			near += 1
	_furnished = {
		"triangles": int(full["triangles"]) - _bare_triangles,
		"meshes": int(full["meshes"]) - _bare_meshes,
		"near": near,
	}


func _measure(cols: int, rows: int, interiors: bool, scale: float,
		block: float, road: float) -> void:
	var city := CityLayout.new()
	city.layout_seed = SEED
	city.cols = cols
	city.rows = rows
	city.world_scale = scale
	city.block_size = block
	city.road_width = road
	city.min_floors = MIN_FLOORS
	city.max_floors = MAX_FLOORS
	city.interiors_enabled = interiors
	root.add_child(city)
	# Timed EXPLICITLY rather than by wrapping `add_child`, so the figure is the
	# generator's own cost and does not depend on when the engine chose to run
	# `_ready`. `rebuild()` clears first, so calling it after a `_ready` that
	# already fired measures a clean second build rather than doubling the city.
	var started: int = Time.get_ticks_usec()
	city.rebuild()
	var build_us: int = Time.get_ticks_usec() - started
	var tally: Dictionary = {"meshes": 0, "triangles": 0, "colliders": 0,
			"nodes": 0}
	_walk(city, tally)
	var extent: Vector2 = _extent(city)
	_rows.append({
		"cols": cols, "rows": rows, "blocks": cols * rows,
		"interiors": interiors, "scale": scale,
		"build_ms": float(build_us) / 1000.0,
		"meshes": int(tally["meshes"]),
		"triangles": int(tally["triangles"]),
		"colliders": int(tally["colliders"]),
		"nodes": int(tally["nodes"]),
		"span_m": extent,
		"draw_calls": Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	})
	# queue_free rather than free: freeing a node mid-frame while its own children
	# are still being processed is how a bench crashes for a reason that has nothing
	# to do with what it measures.
	_live = city
	city.queue_free()


## Sum the built geometry. Triangles come from the mesh's own index buffer where
## it has one and from its vertex count where it does not — a primitive like
## BoxMesh reports both, an ArrayMesh committed by SurfaceTool reports indices.
func _walk(node: Node, tally: Dictionary) -> void:
	tally["nodes"] = int(tally["nodes"]) + 1
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			tally["meshes"] = int(tally["meshes"]) + maxi(mesh.get_surface_count(), 1)
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.size() > 0:
					tally["triangles"] = int(tally["triangles"]) + indices.size() / 3
				else:
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					tally["triangles"] = int(tally["triangles"]) + verts.size() / 3
	elif node is CollisionShape3D:
		tally["colliders"] = int(tally["colliders"]) + 1
	for child: Node in node.get_children():
		_walk(child, tally)


## How much ground the city covers, which is what turns a block count into a
## flying distance — the number that actually decides whether a city is "big".
func _extent(city: Node) -> Vector2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for child: Node in city.get_children():
		if child is not Node3D:
			continue
		var at: Vector3 = (child as Node3D).position
		low.x = minf(low.x, at.x)
		low.y = minf(low.y, at.z)
		high.x = maxf(high.x, at.x)
		high.y = maxf(high.y, at.z)
	if low.x > high.x:
		return Vector2.ZERO
	return high - low


func _report() -> void:
	print("")
	print("[city] %5s %7s %4s %9s %8s %10s %9s %9s %11s"
			% ["grid", "blocks", "int", "span m", "meshes", "triangles",
			"colliders", "nodes", "build ms"])
	for row: Dictionary in _rows:
		if not is_equal_approx(float(row["scale"]), 1.0):
			print("[city] ---- the SCALED city, every length x %.3f ----"
					% float(row["scale"]))
		print("[city] %2dx%-2d %7d %4s %4.0fx%-4.0f %8d %10d %9d %9d %11.1f"
				% [int(row["cols"]), int(row["rows"]), int(row["blocks"]),
				"yes" if row["interiors"] else "no",
				(row["span_m"] as Vector2).x, (row["span_m"] as Vector2).y,
				int(row["meshes"]), int(row["triangles"]),
				int(row["colliders"]), int(row["nodes"]),
				row["build_ms"]])
	print("")
	_per_block()
	print("[city] interiors are DISTANCE-LOD'd, so the two rows of each pair carry the same")
	print("[city] geometry: the specs are generated at build (which is the extra build time)")
	print("[city] and the furniture waits until a pilot is within %.0f m."
			% _lod_radius())
	print("[city] With a pilot in the downtown core of a %dx%d city: %d buildings inside the"
			% [int(FURNISH_GRID[0]), int(FURNISH_GRID[1]),
			int(_furnished.get("near", 0))])
	print("[city] radius furnish %d extra triangles across %d extra meshes."
			% [int(_furnished.get("triangles", 0)),
			int(_furnished.get("meshes", 0))])
	print("[city] THAT FIGURE IS A CONSTANT, NOT A FUNCTION OF CITY SIZE — which is the")
	print("[city] architectural answer to whether the city can keep growing.")
	if DisplayServer.get_name() == "headless":
		print("[city] draw calls: 0 (headless). 'meshes' is the proxy — re-run without --headless for the real figure.")
	else:
		for row: Dictionary in _rows:
			print("[city] %2dx%-2d int %-3s  draw calls %.0f"
					% [int(row["cols"]), int(row["rows"]),
					"yes" if row["interiors"] else "no", row["draw_calls"]])
	# Freed before quitting, or the engine reports leaked ObjectDB instances at
	# exit — and a bench that prints warnings teaches people to ignore warnings.
	for child: Node in root.get_children():
		child.free()
	_check()
	if _failures.is_empty():
		print("[city] PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("[city] FAIL: %s" % failure)
		print("[city] FAIL")
		quit(1)


## The cost of ONE MORE BLOCK, which is the only number that answers "can this go
## bigger". A flat per-block cost means the generator scales linearly and the
## limit is just how much you are willing to pay; a rising one means something in
## it is quadratic and the size ceiling is structural.
## Read from the class rather than restated as a constant here, so a bench cannot
## quote a radius the generator has stopped using. Instanced and freed on the
## spot: an orphan Node is an ObjectDB leak at exit, and this file prints a "no
## warnings" claim it has to keep.
func _lod_radius() -> float:
	var probe := WorldBuilding.new()
	var radius: float = probe.interior_lod_radius
	probe.free()
	return radius


func _per_block() -> void:
	print("[city] per block — the number that says whether this scales:")
	for interiors: bool in INTERIOR_MODES:
		var line: PackedStringArray = []
		for row: Dictionary in _rows:
			if bool(row["interiors"]) != interiors 					or not is_equal_approx(float(row["scale"]), 1.0):
				continue
			line.append("%d:%.0ftri/%.1fmesh" % [int(row["blocks"]),
					float(row["triangles"]) / float(row["blocks"]),
					float(row["meshes"]) / float(row["blocks"])])
		print("[city]   interiors %-3s  %s"
				% ["yes" if interiors else "no", "  ".join(line)])


## Anti-deletion asserts. A sweep whose biggest city costs the same as its
## smallest is measuring a generator that never ran — which is exactly what a
## silent exception inside `rebuild()` would look like from out here, since
## `_ready` cannot fail loudly.
func _check() -> void:
	for row: Dictionary in _rows:
		if not is_equal_approx(float(row["scale"]), 1.0):
			# THE ANTI-CONSTANT ASSERT. `world_scale` only means anything if the
			# generator's hard-coded lengths go through it: a scaled city whose
			# buildings came out human-sized would look almost right from the air
			# and be completely wrong to fly. So the scaled row must cover ground
			# in proportion to its scale, which a stuck footprint law cannot fake.
			var want: float = float(SCALED_COLS) * SCALED_BLOCK
			if (row["span_m"] as Vector2).x < want * 0.5:
				_failures.append("the scaled city spans only %.0f m across %d columns of %.0f m blocks — world_scale is not reaching the generator"
						% [(row["span_m"] as Vector2).x, SCALED_COLS,
						SCALED_BLOCK])
		if int(row["triangles"]) <= 0 or int(row["meshes"]) <= 0:
			_failures.append("%dx%d (interiors %s) built no geometry at all"
					% [int(row["cols"]), int(row["rows"]), row["interiors"]])
		if int(row["colliders"]) <= 0:
			_failures.append("%dx%d (interiors %s) built no colliders — a city you fly through is not a city"
					% [int(row["cols"]), int(row["rows"]), row["interiors"]])
	if _rows.size() >= 3:
		var first: Dictionary = _rows[0]
		var last: Dictionary = _rows[-2]
		if int(last["triangles"]) <= int(first["triangles"]) * 2:
			_failures.append("the sweep is flat: %d blocks cost %d triangles and %d blocks cost %d — the grid size is not reaching the generator"
					% [int(first["blocks"]), int(first["triangles"]),
					int(last["blocks"]), int(last["triangles"])])
	# Interiors must cost something, or `interiors_enabled` is a dead flag. They
	# cost it in BUILD TIME, not in geometry: `InteriorGenerator.generate` runs
	# for every open floor at build, while the geometry waits on the distance LOD.
	# Asserting on triangles here is what the first version did, and it failed a
	# perfectly healthy generator — the reading it wanted lives in the furnished
	# probe below.
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		if not bool(row["interiors"]) 				or not is_equal_approx(float(row["scale"]), 1.0):
			continue
		var plain: Dictionary = _rows[i - 1]
		if float(row["build_ms"]) <= float(plain["build_ms"]):
			_failures.append("%dx%d: interiors cost no extra build time (%.1f ms vs %.1f) — InteriorGenerator is not running"
					% [int(row["cols"]), int(row["rows"]),
					float(row["build_ms"]), float(plain["build_ms"])])
	# And the LOD must actually furnish something when a pilot is present. Zero
	# here means either the driver is dead or the probe never found the city, and
	# both read exactly like "interiors are free".
	if int(_furnished.get("triangles", 0)) <= 0:
		_failures.append("the furnished probe added no geometry with a pilot in the core — the interior LOD driver never fired, so the whole interior cost is unmeasured")
	if int(_furnished.get("near", 0)) <= 0:
		_failures.append("the furnished probe found no buildings inside the LOD radius — the stand-in pilot is not where the city is")
