extends Node3D

## THE MENU TOWER (GAMEPLAY-DESIGN B5, Iteration 8) — the game's main menu,
## flown. Each open floor is a leaf option, lit per B2 (light is the
## enterability telegraph); fly in through the labeled window to pick it.
## Selection COMMITS on exiting the far side of the floor; re-threading the
## entry window cancels — a graze at speed is a scare, not a mis-pick.
##
## CHECKPOINT 1 SHELL (build order step 1): one open floor, lit + labeled,
## the real drone armable in front of it, auto-exposure wired through the
## look pass. No selection logic yet — the commit-on-exit verb is step 2,
## leaves launching their scenes is step 3, the keyboard side-view fallback
## rides with step 3. Run: <godot> --path . scenes/menu_tower.tscn
##
## Steering honored (v1.37): single-level first; leaf set START RUN /
## FLY FREE / DEV ROOM / AIM DRILL / QUIT; pure menu, home-ready — no
## briefing/hangar floors until P2/P5 ask for them.

@export var combat_config: CombatConfig
@export var input_bindings: InputBindings

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _hud: GameHud = $Hud

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
	_hud.show_title("MENU TOWER — arm and fly to the lit window")


func _process(_delta: float) -> void:
	if _drone.armed and _titled:
		_hud.hide_title()
		_titled = false
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])


## Crashing into the tower is expected window practice — respawn in place,
## no stakes. The menu never punishes; it only waits.
func _on_died() -> void:
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
			_drone.reset_to_spawn()
			_drone_health.revive()
			_hud.set_health(_drone_health.current, _drone_health.max_health))
