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
		if frame.state != MenuFloorFrame.STATE_OPEN:
			continue
		open += 1
		if frame.leaf_id != &"":
			return _fail("world open floor should be leafless, got '%s'"
					% frame.leaf_id)
		if not frame.find_children("*", "MenuFloor", false, false).is_empty():
			return _fail("world open floor must not build a MenuFloor commit zone")
		if not frame.find_children("*", "GlowText3D", false, false).is_empty():
			return _fail("world open floor must not build a GlowText3D label")
	if open != 4:
		return _fail("expected 4 open floors, got %d" % open)

	print("[world_building_check] 11 floors, 4 leafless enterable, no menu furniture — ok")
	print("[world_building_check] PASS")
	quit(0)
