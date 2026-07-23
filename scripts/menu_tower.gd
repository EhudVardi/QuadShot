extends Node3D

## THE MENU TOWER (GAMEPLAY-DESIGN B5, Iteration 8) — the game's main menu,
## flown. Each open floor is a leaf option, lit per B2 (light is the
## enterability telegraph); fly in through the labeled window to pick it.
## Selection COMMITS on exiting the far side of the floor; re-threading the
## entry window cancels — a graze at speed is a scare, not a mis-pick.
##
## STEP 2 (build order): the verb is live on the one open floor — fly in
## through the window (announced), exit the far side to COMMIT (logged),
## re-thread the entry window to cancel. Leaves launching their scenes is
## step 3, the keyboard side-view fallback rides with step 3.
## Run: <godot> --path . scenes/menu_tower.tscn
##
## Steering honored (v1.37): single-level first; leaf set START RUN /
## FLY FREE / DEV ROOM / AIM DRILL / QUIT; pure menu, home-ready — no
## briefing/hangar floors until P2/P5 ask for them.

@export var combat_config: CombatConfig
@export var input_bindings: InputBindings

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _hud: GameHud = $Hud
@onready var _floor: MenuFloor = $Tower/RoomZone

var _titled: bool = true


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	if input_bindings != null:
		if input_bindings.load_from_user():
			print("[config] loaded %s" % input_bindings.save_path())
		input_bindings.apply()
	# Menu flight is plain flight: no run, no draft multipliers.
	RunMods.reset()
	_drone_health.damaged.connect(func(_amount: float, remaining: float) -> void:
			_hud.set_health(remaining, _drone_health.max_health))
	_drone_health.died.connect(_on_died)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_floor.entered.connect(_on_floor_entered)
	_floor.committed.connect(_on_floor_committed)
	_floor.canceled.connect(_on_floor_canceled)
	_hud.show_title("MENU TOWER — arm and fly to the lit window")


func _process(_delta: float) -> void:
	if _drone.armed and _titled:
		_hud.hide_title()
		_titled = false
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])


func _leaf_name(leaf_id: StringName) -> String:
	return String(leaf_id).replace("_", " ").to_upper()


# --- The selection verb (step 2): the floor reports, the tower narrates.
# Step 3 replaces the committed log line with the leaf's actual launch. ---

func _on_floor_entered(leaf_id: StringName) -> void:
	_hud.add_kill_feed("%s — exit far side to commit, back out to cancel"
			% _leaf_name(leaf_id))


func _on_floor_committed(leaf_id: StringName) -> void:
	_hud.add_kill_feed("PICKED: %s (logged — step 3 makes it launch)"
			% _leaf_name(leaf_id))
	print("[menu] committed %s" % leaf_id)


func _on_floor_canceled(leaf_id: StringName) -> void:
	_hud.add_kill_feed("%s canceled" % _leaf_name(leaf_id))
	print("[menu] canceled %s" % leaf_id)


## Crashing into the tower is expected window practice — respawn in place,
## no stakes. The menu never punishes; it only waits.
func _on_died() -> void:
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_drone.reset_to_spawn()
			_drone_health.revive()
			_hud.set_health(_drone_health.current, _drone_health.max_health))
