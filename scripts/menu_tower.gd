extends Node3D

## THE MENU TOWER (GAMEPLAY-DESIGN B5, Iteration 8) — the game's main menu,
## flown. Each open floor is a leaf option, lit per B2 (light is the
## enterability telegraph); fly in through the labeled window, cross the
## interior, and exit the far side to COMMIT the pick. Re-threading the
## entry window cancels — a graze at speed is a scare, not a mis-pick.
##
## STEP 3 (build order): five leaves bottom→top — QUIT (ground lobby),
## START RUN, FLY FREE, DEV ROOM, AIM DRILL — with ESCALATING GAPS (v1.38:
## generous low, tightening with altitude). Committing launches the leaf's
## scene; FLY FREE rides the MenuLaunch.free_fly static into main.
##
## THE SIDE VIEW (B.q2's forever-fallback, the user's design): with no
## controller connected the camera stands outside the tower, arrows move the
## selection floor to floor (the glyphs flare), Enter launches, Esc quits.
## The moment a controller appears the view drops into flight. Two cameras,
## one architecture — nothing is built twice.
## Run: <godot> --path .   (the tower is the boot scene)

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

var _frames: Array[MenuFloorFrame] = []
var _titled: bool = true
var _kb_mode: bool = false
## Bottom→top floor index; starts on START RUN, the likeliest pick.
var _selection: int = 1


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	if input_bindings != null:
		if input_bindings.load_from_user():
			print("[config] loaded %s" % input_bindings.save_path())
		input_bindings.apply()
	# Menu flight is plain flight: no run, no draft multipliers.
	RunMods.reset()
	for child: Node in $Tower.get_children():
		if child is MenuFloorFrame:
			var frame: MenuFloorFrame = child
			_frames.append(frame)
			frame.entered.connect(_on_floor_entered)
			frame.committed.connect(_on_floor_committed)
			frame.canceled.connect(_on_floor_canceled)
	_drone_health.damaged.connect(func(_amount: float, remaining: float) -> void:
			_hud.set_health(remaining, _drone_health.max_health))
	_drone_health.died.connect(_on_died)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_side_camera.look_at_from_position(
			Vector3(15.0, 12.0, -14.0), Vector3(0.0, 10.0, -36.0))
	Input.joy_connection_changed.connect(
			func(_device: int, _connected: bool) -> void: _update_input_mode())
	_kb_mode = not Input.get_connected_joypads().is_empty()  # force first apply
	_update_input_mode()


func _process(_delta: float) -> void:
	if _kb_mode:
		_process_keyboard_menu()
		return
	if _drone.armed and _titled:
		_hud.hide_title()
		_titled = false
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])


## The side view: same tower, outside camera, arrow keys walk the floors.
func _process_keyboard_menu() -> void:
	if Input.is_action_just_pressed(&"ui_up"):
		_move_selection(1)
	if Input.is_action_just_pressed(&"ui_down"):
		_move_selection(-1)
	if Input.is_action_just_pressed(&"ui_accept"):
		_launch(_frames[_selection].leaf_id)
	if Input.is_action_just_pressed(&"ui_cancel"):
		get_tree().quit()


func _move_selection(step: int) -> void:
	_selection = clampi(_selection + step, 0, _frames.size() - 1)
	_apply_selection()


func _apply_selection() -> void:
	for i: int in _frames.size():
		_frames[i].set_selected(_kb_mode and i == _selection)


func _update_input_mode() -> void:
	var keyboard_only: bool = Input.get_connected_joypads().is_empty()
	if keyboard_only == _kb_mode:
		return
	_kb_mode = keyboard_only
	_apply_selection()
	if _kb_mode:
		_side_camera.make_current()
		_hud.show_title("MENU — up/down select · Enter launch · Esc quit")
		_titled = true
	else:
		_fpv_camera.make_current()
		_hud.show_title("MENU TOWER — arm and fly through a lit window")
		_titled = true


func _leaf_name(leaf_id: StringName) -> String:
	return String(leaf_id).replace("_", " ").to_upper()


# --- The selection verb: the floor reports, the tower launches. ---

func _on_floor_entered(leaf_id: StringName) -> void:
	_hud.add_kill_feed("%s — exit far side to commit, back out to cancel"
			% _leaf_name(leaf_id))


func _on_floor_committed(leaf_id: StringName) -> void:
	_hud.add_kill_feed("LAUNCHING: %s" % _leaf_name(leaf_id))
	print("[menu] committed %s" % leaf_id)
	_launch(leaf_id)


func _on_floor_canceled(leaf_id: StringName) -> void:
	_hud.add_kill_feed("%s canceled" % _leaf_name(leaf_id))
	print("[menu] canceled %s" % leaf_id)


func _launch(leaf_id: StringName) -> void:
	if leaf_id == &"quit":
		get_tree().quit()
		return
	if not LEAF_SCENES.has(leaf_id):
		push_warning("[menu] unknown leaf %s" % leaf_id)
		return
	MenuLaunch.free_fly = leaf_id == &"fly_free"
	# Commit fires from a physics callback; the swap waits for the flush.
	get_tree().call_deferred(&"change_scene_to_file", LEAF_SCENES[leaf_id])


## Crashing into the tower is expected window practice — respawn in place,
## no stakes. The menu never punishes; it only waits.
func _on_died() -> void:
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_drone.reset_to_spawn()
			_drone_health.revive()
			_hud.set_health(_drone_health.current, _drone_health.max_health))
