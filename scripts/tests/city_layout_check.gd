extends SceneTree

## Headless check for the seeded city layout (B4, v1.52): buildings land on a
## block grid, no two footprints overlap (the streets never close up), and the
## same seed builds the same city.
##
## Run: <godot> --headless -s scripts/tests/city_layout_check.gd --path .

var _city: CityLayout
var _checked: bool = false


func _initialize() -> void:
	_city = _make_city(20)
	root.add_child(_city)
	process_frame.connect(_run_once)


func _make_city(seed_value: int) -> CityLayout:
	var city := CityLayout.new()
	city.layout_seed = seed_value
	city.cols = 3
	city.rows = 2
	return city


func _run_once() -> void:
	if _checked:
		return
	if not _city.is_node_ready():
		return
	_checked = true
	_check()


func _fail(message: String) -> void:
	print("[city_layout_check] FAIL: %s" % message)
	quit(1)


func _buildings(city: CityLayout) -> Array:
	return city.find_children("*", "WorldBuilding", false, false)


## The XZ footprint rect [min_x, max_x, min_z, max_z] of a placed building.
func _rect(b: WorldBuilding) -> Array:
	var half: float = b.footprint * 0.5 + 0.3  # + slab lip
	return [b.position.x - half, b.position.x + half,
			b.position.z - half, b.position.z + half]


func _check() -> void:
	var built: Array = _buildings(_city)
	if built.size() < 2:
		return _fail("expected several buildings on the grid, got %d" % built.size())

	# No two footprints overlap — the streets stay open.
	for i: int in built.size():
		for j: int in range(i + 1, built.size()):
			var a: Array = _rect(built[i])
			var b: Array = _rect(built[j])
			var apart: bool = a[1] <= b[0] or b[1] <= a[0] \
					or a[3] <= b[2] or b[3] <= a[2]
			if not apart:
				return _fail("buildings %d and %d overlap — a street closed up"
						% [i, j])

	# Determinism: a second city with the same seed is identical.
	var twin: CityLayout = _make_city(20)
	root.add_child(twin)
	var twin_built: Array = _buildings(twin)
	if twin_built.size() != built.size():
		return _fail("same seed gave a different building count (%d vs %d)"
				% [built.size(), twin_built.size()])
	for i: int in built.size():
		if not built[i].position.is_equal_approx(twin_built[i].position):
			return _fail("same seed placed building %d differently" % i)
		if not is_equal_approx(built[i].footprint, twin_built[i].footprint):
			return _fail("same seed sized building %d differently" % i)

	print("[city_layout_check] %d buildings on a grid, none overlapping, deterministic — ok"
			% built.size())
	print("[city_layout_check] PASS")
	quit(0)
