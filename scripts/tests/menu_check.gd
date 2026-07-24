extends SceneTree

## Headless menu-tree check (B5 step 4): the depth state machine the human can
## only see by flying — spawn/despawn, the pending parent, the frame pick.
## Drives the tower through each building's PUBLIC signals (the same signals a
## flown commit-on-exit fires), so it tests the tower's reaction logic without
## needing a physics fly-through.
##
## Run: <godot> --headless -s scripts/tests/menu_check.gd --path .

var _tower: Node3D
var _ready_checked: bool = false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/menu_tower.tscn")
	_tower = scene.instantiate() as Node3D
	root.add_child(_tower)
	process_frame.connect(_run_once)


func _run_once() -> void:
	if _ready_checked:
		return
	if not _tower.is_node_ready():
		return
	_ready_checked = true
	_check()


func _fail(message: String) -> void:
	print("[menu_check] FAIL: %s" % message)
	quit(1)


func _buildings() -> Array:
	return _tower.get("_buildings")


func _find_frame(building: MenuBuilding, leaf: StringName) -> MenuFloorFrame:
	for frame: MenuFloorFrame in building.frames:
		if frame.leaf_id == leaf:
			return frame
	return null


func _check() -> void:
	# Root tower stands with all five leaves.
	var root_building: MenuBuilding = _buildings()[0]
	if _buildings().size() != 1:
		return _fail("expected 1 building at start, got %d" % _buildings().size())
	if root_building.frames.size() != 5:
		return _fail("root tower should have 5 floors, got %d"
				% root_building.frames.size())

	# Committing a parent (START RUN) spawns the frame tower.
	var start_frame: MenuFloorFrame = _find_frame(root_building, &"start_run")
	if start_frame == null:
		return _fail("no start_run floor")
	root_building.floor_committed.emit(start_frame)
	if _buildings().size() != 2:
		return _fail("committing a parent should spawn a sub-building (got %d)"
				% _buildings().size())
	var frame_tower: MenuBuilding = _buildings()[1]
	if frame_tower.frames.size() != 2:
		return _fail("frame tower should have 2 floors, got %d"
				% frame_tower.frames.size())
	# The sub-building stands ahead of the root (deeper into -Z).
	if frame_tower.position.z >= root_building.position.z:
		return _fail("sub-building should stand ahead of the root")

	# Re-threading the parent backwards despawns the sub-tree.
	root_building.floor_canceled.emit(start_frame)
	if _buildings().size() != 1:
		return _fail("canceling the parent should despawn the sub-building (got %d)"
				% _buildings().size())

	# Commit START RUN again, then pick a frame: the pick lands and free_fly
	# stays off (START RUN is a run, not free flight).
	root_building.floor_committed.emit(start_frame)
	var atlas_frame: MenuFloorFrame = _find_frame(_buildings()[1], &"frame_atlas")
	if atlas_frame == null:
		return _fail("frame tower has no ATLAS floor")
	MenuLaunch.frame_id = &""
	MenuLaunch.free_fly = true
	_buildings()[1].floor_committed.emit(atlas_frame)
	if MenuLaunch.frame_id != &"atlas":
		return _fail("frame pick did not set MenuLaunch.frame_id (got '%s')"
				% MenuLaunch.frame_id)
	if MenuLaunch.free_fly:
		return _fail("START RUN frame pick must clear free_fly")

	# FLY FREE's frame pick, by contrast, sets free_fly.
	root_building.floor_committed.emit(_find_frame(root_building, &"fly_free"))
	var kestrel_frame: MenuFloorFrame = _find_frame(_buildings()[1], &"frame_kestrel")
	_buildings()[1].floor_committed.emit(kestrel_frame)
	if MenuLaunch.frame_id != &"kestrel":
		return _fail("FLY FREE frame pick did not set frame_id")
	if not MenuLaunch.free_fly:
		return _fail("FLY FREE frame pick must set free_fly")

	print("[menu_check] tree spawn/despawn, pending parent, frame pick — all ok")
	print("[menu_check] PASS")
	quit(0)
