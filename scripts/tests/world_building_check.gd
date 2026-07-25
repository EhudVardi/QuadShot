extends SceneTree

## Headless check for the menu→world bridge (B3/B4, v1.47 step 3a): a
## WorldBuilding produces a generated tower whose OPEN floors are leafless and
## carry NO menu furniture — no GlowText3D label, no MenuFloor commit zone,
## just a windowed, enterable opening. Guards against menu bits leaking into
## world buildings (find_children owned=false: the geometry is code-built, so
## none of it has a scene owner).
##
## Run: <godot> --headless -s scripts/tests/world_building_check.gd --path .

var _building: WorldBuilding
var _checked: bool = false


func _initialize() -> void:
	_building = WorldBuilding.new()
	_building.building_seed = 16
	_building.target_floors = 11
	_building.open_floors = 4
	_building.footprint = 10.0
	_building.interior_height = 5.0
	root.add_child(_building)
	process_frame.connect(_run_once)


func _run_once() -> void:
	if _checked:
		return
	if not _building.is_node_ready():
		return
	_checked = true
	_check()


func _fail(message: String) -> void:
	print("[world_building_check] FAIL: %s" % message)
	quit(1)


func _check() -> void:
	var built: Array = _building.find_children("*", "MenuBuilding", false, false)
	if built.size() != 1:
		return _fail("expected 1 MenuBuilding child, got %d" % built.size())
	var building: MenuBuilding = built[0]
	if building.frames.size() != 11:
		return _fail("expected 11 floors, got %d" % building.frames.size())

	var open: int = 0
	for frame: MenuFloorFrame in building.frames:
		# Geometry plumbing: WorldBuilding stamps footprint + interior height
		# onto every floor.
		if not is_equal_approx(frame.footprint, 10.0):
			return _fail("floor footprint should be 10.0, got %f" % frame.footprint)
		if not is_equal_approx(frame.interior_height, 5.0):
			return _fail("floor interior_height should be 5.0, got %f"
					% frame.interior_height)
		if frame.state != MenuFloorFrame.STATE_OPEN:
			continue
		open += 1
		if frame.leaf_id != &"":
			return _fail("world open floor should be leafless, got '%s'"
					% frame.leaf_id)
		if not frame.cross_windows:
			return _fail("world open floor should have crossed (4-side) windows")
		if not frame.find_children("*", "MenuFloor", false, false).is_empty():
			return _fail("world open floor must not build a MenuFloor commit zone")
		if not frame.find_children("*", "GlowText3D", false, false).is_empty():
			return _fail("world open floor must not build a GlowText3D label")
	if open != 4:
		return _fail("expected 4 open floors, got %d" % open)

	# Setbacks: a tiered building tapers its footprint up the tower (pure fn,
	# no tree needed — build a throwaway just to query it).
	var taper: WorldBuilding = WorldBuilding.new()
	taper.footprint = 30.0
	taper.setback_tiers = 3
	taper.top_footprint = 12.0
	var base_fp: float = taper._footprint_at(0, 30)
	var top_fp: float = taper._footprint_at(29, 30)
	taper.free()
	if not is_equal_approx(base_fp, 30.0):
		return _fail("setback base floor should be full width, got %f" % base_fp)
	if not is_equal_approx(top_fp, 12.0):
		return _fail("setback top floor should be the top width, got %f" % top_fp)
	if top_fp >= base_fp:
		return _fail("setback should narrow going up (%f -> %f)" % [base_fp, top_fp])

	print("[world_building_check] 11 floors, leafless enterable, no menu furniture, setback — ok")
	print("[world_building_check] PASS")
	quit(0)
