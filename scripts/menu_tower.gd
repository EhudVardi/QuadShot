extends Node3D

## THE MENU TOWER (GAMEPLAY-DESIGN B5, Iteration 8) — the game's main menu,
## flown. Each open floor is a leaf option, lit per B2; fly in through the
## labeled window, cross the interior, and exit the far side to COMMIT.
## Re-threading the entry window cancels — a graze is a scare, never a pick.
##
## STEP 4 (v1.43): the menu is a TREE OF BUILDINGS, flown in depth. A floor
## with a submenu spawns the NEXT BUILDING in front of the player when its
## selection commits (the v1.40 steering: dynamically created, the tree
## built as it is flown); re-threading the parent floor backwards despawns
## it. Escalation is PER-BUILDING: the root tower is all-easy, the frame
## tower's windows are cut smaller. START RUN and FLY FREE open the frame
## tower (KESTREL / ATLAS); the pick rides MenuLaunch.frame_id and is
## sticky across launches.
##
## THE SIDE VIEW (B.q2's forever-fallback): with no controller the camera
## stands outside; ↑/↓ walk a building's floors, → dives into a submenu
## (spawning its building), ← backs out, Enter launches, Esc quits. Two
## cameras, one architecture. Run: <godot> --path .   (the boot scene)

## Floor specs: leaf, label, window (Vector2), sill, pixel — MenuBuilding
## hands each to a MenuFloorFrame. "submenu" marks a parent floor; its
## value is the next building's floor list. Per-building escalation lives
## right here in the data: the frame tower's windows are the smaller cut.
const FRAME_FLOORS: Array = [
	{"leaf": &"frame_kestrel", "label": "KESTREL",
			"window": Vector2(4.0, 2.4), "sill": 0.6, "pixel": 0.09},
	{"leaf": &"frame_atlas", "label": "ATLAS",
			"window": Vector2(4.0, 2.4), "sill": 0.6, "pixel": 0.09},
]
const MENU_TREE: Array = [
	{"leaf": &"quit", "label": "QUIT",
			"window": Vector2(4.5, 2.8), "sill": 0.0, "pixel": 0.14},
	{"leaf": &"start_run", "label": "START\nRUN",
			"window": Vector2(5.0, 2.8), "sill": 0.4, "pixel": 0.14,
			"submenu": FRAME_FLOORS},
	{"leaf": &"fly_free", "label": "FLY\nFREE",
			"window": Vector2(5.0, 2.8), "sill": 0.4, "pixel": 0.14,
			"submenu": FRAME_FLOORS},
	{"leaf": &"dev_room", "label": "DEV\nROOM",
			"window": Vector2(4.5, 2.6), "sill": 0.5, "pixel": 0.13},
	{"leaf": &"aim_drill", "label": "AIM\nDRILL",
			"window": Vector2(4.5, 2.6), "sill": 0.5, "pixel": 0.12},
]

const ROOT_POSITION: Vector3 = Vector3(0.0, 0.0, -36.0)
## Center-to-center gap between depth levels — the next building stands a
## real approach away, not in your face.
const BUILDING_SPACING: float = 55.0

const LEAF_SCENES: Dictionary = {
	&"start_run": "res://scenes/main.tscn",
	&"fly_free": "res://scenes/main.tscn",
	&"dev_room": "res://scenes/dev_map.tscn",
	&"aim_drill": "res://scenes/aim_drill.tscn",
}

@export var combat_config: CombatConfig
@export var input_bindings: InputBindings

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _side_camera: Camera3D = $SideCamera
@onready var _hud: GameHud = $Hud

## Buildings by depth; index 0 is the root tower.
var _buildings: Array[MenuBuilding] = []
## leaf_id -> submenu floor list, for parents at any depth.
var _submenu_of: Dictionary = {}
## The submenu parent whose choice is being made (start_run / fly_free).
var _pending: StringName = &""
var _titled: bool = true
var _kb_mode: bool = false
var _kb_depth: int = 0
## Floor index per depth; root starts on START RUN, the likeliest pick.
var _kb_floor: int = 1


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	if input_bindings != null:
		if input_bindings.load_from_user():
			print("[config] loaded %s" % input_bindings.save_path())
		input_bindings.apply()
	# Menu flight is plain flight: no run, no draft multipliers.
	RunMods.reset()
	_index_submenus(MENU_TREE)
	_spawn_building(0, MENU_TREE)
	_drone_health.damaged.connect(func(_amount: float, remaining: float) -> void:
			_hud.set_health(remaining, _drone_health.max_health))
	_drone_health.died.connect(_on_died)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	Input.joy_connection_changed.connect(
			func(_device: int, _connected: bool) -> void: _update_input_mode())
	_kb_mode = not Input.get_connected_joypads().is_empty()  # force first apply
	_update_input_mode()


func _index_submenus(floors: Array) -> void:
	for spec: Dictionary in floors:
		if spec.has("submenu"):
			_submenu_of[spec["leaf"]] = spec["submenu"]
			_index_submenus(spec["submenu"])


func _process(_delta: float) -> void:
	if _kb_mode:
		_process_keyboard_menu()
		return
	if _drone.armed and _titled:
		_hud.hide_title()
		_titled = false
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])


# --- Buildings ---

func _spawn_building(depth: int, floors: Array) -> void:
	_despawn_below(depth - 1)
	var building: MenuBuilding = MenuBuilding.create(floors)
	building.position = ROOT_POSITION + Vector3(0.0, 0.0, -BUILDING_SPACING * depth)
	building.floor_entered.connect(_on_floor_entered)
	building.floor_committed.connect(_on_floor_committed)
	building.floor_canceled.connect(_on_floor_canceled)
	add_child(building)
	_buildings.append(building)


## Frees every building deeper than `depth` (pass -1 to keep only nothing,
## 0 to keep the root). The tree is rebuilt as it is flown.
func _despawn_below(depth: int) -> void:
	while _buildings.size() > depth + 1:
		_buildings.pop_back().queue_free()


func _leaf_name(leaf_id: StringName) -> String:
	return String(leaf_id).replace("_", " ").to_upper().trim_prefix("FRAME ")


# --- The selection verb: floors report, the tower decides. ---

func _on_floor_entered(frame: MenuFloorFrame) -> void:
	if _submenu_of.has(frame.leaf_id):
		_hud.add_kill_feed("%s — exit far side to open the next tower"
				% _leaf_name(frame.leaf_id))
	else:
		_hud.add_kill_feed("%s — exit far side to commit, back out to cancel"
				% _leaf_name(frame.leaf_id))


func _on_floor_committed(frame: MenuFloorFrame) -> void:
	var leaf: StringName = frame.leaf_id
	print("[menu] committed %s" % leaf)
	if _submenu_of.has(leaf):
		_pending = leaf
		_spawn_building(_depth_of(frame) + 1, _submenu_of[leaf])
		_hud.add_kill_feed("%s — pick your frame in the tower ahead"
				% _leaf_name(leaf))
		return
	_hud.add_kill_feed("LAUNCHING: %s" % _leaf_name(leaf))
	_launch(leaf)


func _on_floor_canceled(frame: MenuFloorFrame) -> void:
	_hud.add_kill_feed("%s canceled" % _leaf_name(frame.leaf_id))
	print("[menu] canceled %s" % frame.leaf_id)
	# Re-threading the pending parent backwards closes its sub-tree.
	if frame.leaf_id == _pending:
		_pending = &""
		_despawn_below(_depth_of(frame))


func _depth_of(frame: MenuFloorFrame) -> int:
	for depth: int in _buildings.size():
		if _buildings[depth].frames.has(frame):
			return depth
	return 0


func _launch(leaf_id: StringName) -> void:
	match leaf_id:
		&"quit":
			get_tree().quit()
		&"frame_kestrel", &"frame_atlas":
			MenuLaunch.frame_id = StringName(
					String(leaf_id).trim_prefix("frame_"))
			_change_scene(_pending if _pending != &"" else &"start_run")
		_:
			_change_scene(leaf_id)


func _change_scene(leaf_id: StringName) -> void:
	if not LEAF_SCENES.has(leaf_id):
		push_warning("[menu] unknown leaf %s" % leaf_id)
		return
	MenuLaunch.free_fly = leaf_id == &"fly_free"
	# Commit fires from a physics callback; the swap waits for the flush.
	get_tree().call_deferred(&"change_scene_to_file", LEAF_SCENES[leaf_id])


# --- The side view: same tree, outside camera, arrows walk it. ---

func _process_keyboard_menu() -> void:
	if Input.is_action_just_pressed(&"ui_up"):
		_kb_floor = clampi(_kb_floor + 1, 0,
				_buildings[_kb_depth].frames.size() - 1)
		_apply_selection()
	if Input.is_action_just_pressed(&"ui_down"):
		_kb_floor = clampi(_kb_floor - 1, 0,
				_buildings[_kb_depth].frames.size() - 1)
		_apply_selection()
	if Input.is_action_just_pressed(&"ui_right"):
		_kb_dive()
	if Input.is_action_just_pressed(&"ui_left"):
		_kb_back()
	if Input.is_action_just_pressed(&"ui_accept"):
		var leaf: StringName = _buildings[_kb_depth].frames[_kb_floor].leaf_id
		if _submenu_of.has(leaf):
			_kb_dive()
		else:
			_launch(leaf)
	if Input.is_action_just_pressed(&"ui_cancel"):
		if _kb_depth > 0:
			_kb_back()
		else:
			get_tree().quit()


func _kb_dive() -> void:
	var leaf: StringName = _buildings[_kb_depth].frames[_kb_floor].leaf_id
	if not _submenu_of.has(leaf):
		return
	_pending = leaf
	_spawn_building(_kb_depth + 1, _submenu_of[leaf])
	_kb_depth += 1
	_kb_floor = 0
	_apply_selection()
	_focus_side_camera()


func _kb_back() -> void:
	if _kb_depth == 0:
		return
	_kb_depth -= 1
	_pending = &""
	_despawn_below(_kb_depth)
	_kb_floor = clampi(_kb_floor, 0, _buildings[_kb_depth].frames.size() - 1)
	_apply_selection()
	_focus_side_camera()


func _apply_selection() -> void:
	for depth: int in _buildings.size():
		var building: MenuBuilding = _buildings[depth]
		for i: int in building.frames.size():
			building.frames[i].set_selected(
					_kb_mode and depth == _kb_depth and i == _kb_floor)


## Frame the current depth's building: eye level scales with its height so
## the two-floor frame tower is not filmed from a skyscraper's balcony.
func _focus_side_camera() -> void:
	var building: MenuBuilding = _buildings[_kb_depth]
	var mid: float = building.height() * 0.5
	var target: Vector3 = building.position + Vector3(0.0, mid, 0.0)
	_side_camera.look_at_from_position(
			target + Vector3(15.0, mid * 0.2 + 2.0, 22.0), target)


func _update_input_mode() -> void:
	var keyboard_only: bool = Input.get_connected_joypads().is_empty()
	if keyboard_only == _kb_mode:
		return
	_kb_mode = keyboard_only
	_apply_selection()
	if _kb_mode:
		_focus_side_camera()
		_side_camera.make_current()
		_hud.show_title("MENU — arrows walk the tree · Enter launch · Esc back/quit")
		_titled = true
	else:
		_fpv_camera.make_current()
		_hud.show_title("MENU TOWER — arm and fly through a lit window")
		_titled = true


## Crashing into a tower is expected window practice — respawn in place,
## no stakes. The menu never punishes; it only waits.
func _on_died() -> void:
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_drone.reset_to_spawn()
			_drone_health.revive()
			_hud.set_health(_drone_health.current, _drone_health.max_health))
