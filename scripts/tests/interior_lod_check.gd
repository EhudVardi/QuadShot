extends SceneTree

## Headless check for the B3 building-level interior LOD (spec §9): with
## interior_lod on and no drone in range, open floors stay hollow; _set_interiors
## toggles the Interior subtrees on and off cleanly.
##
## Run: <godot> --headless -s scripts/tests/interior_lod_check.gd --path .

var _wb: WorldBuilding
var _step: int = 0


func _initialize() -> void:
	_wb = WorldBuilding.new()
	_wb.building_seed = 5
	_wb.target_floors = 8
	_wb.open_floors = 4
	_wb.footprint = 26.0
	_wb.interior_height = 4.0
	_wb.interiors_enabled = true
	_wb.interior_lod = true
	root.add_child(_wb)
	process_frame.connect(_run)


func _fail(message: String) -> void:
	print("[interior_lod_check] FAIL: %s" % message)
	quit(1)


func _interior_count() -> int:
	var n: int = 0
	for f: Node in _wb.find_children("*", "MenuFloorFrame", true, false):
		if f.find_child("Interior", false, false) != null:
			n += 1
	return n


func _furnishable() -> int:
	var n: int = 0
	for f: MenuFloorFrame in _wb.find_children("*", "MenuFloorFrame", true, false):
		if f.has_interior():
			n += 1
	return n


func _run() -> void:
	if not _wb.is_node_ready():
		return
	_step += 1
	match _step:
		1:
			# LOD on, no drone in range: open floors carry specs but are NOT built.
			if _furnishable() == 0:
				return _fail("no open floors carry an interior spec")
			if _interior_count() != 0:
				return _fail("interiors built despite LOD out of range")
			_wb._set_interiors(true)
		2:
			if _interior_count() != _furnishable():
				return _fail("LOD build did not furnish every open floor (%d/%d)"
						% [_interior_count(), _furnishable()])
			_wb._set_interiors(false)
		3:
			# queue_free processed across the frame boundary.
			if _interior_count() != 0:
				return _fail("LOD clear left interiors behind (%d)" % _interior_count())
			print("[interior_lod_check] furnishable=%d, build/clear toggles cleanly — ok"
					% _furnishable())
			print("[interior_lod_check] PASS")
			quit(0)
