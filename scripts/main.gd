extends Node3D

## Scene orchestration: camera switching (camera_toggle / X: FPV ↔ chase),
## combat config startup load, score keeping, and the player's
## damage → death → respawn loop (roadmap M2). Combat entities report in
## through their "destroyed" signals.

@export var combat_config: CombatConfig

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera
@onready var _hud: GameHud = $Hud

var score: int = 0


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	for scorer: Node in get_tree().get_nodes_in_group(&"targets") \
			+ get_tree().get_nodes_in_group(&"turrets"):
		scorer.connect(&"destroyed", _on_scorer_destroyed)
	_drone_health.max_health = combat_config.player_max_health
	_drone_health.revive()
	_drone_health.damaged.connect(_on_player_damaged)
	_drone_health.died.connect(_on_player_died)
	_drone.crashed.connect(_on_player_crashed)
	_hud.set_health(_drone_health.current, _drone_health.max_health)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_chase_camera.make_current()
		else:
			_fpv_camera.make_current()


func _on_scorer_destroyed(points: float) -> void:
	score += int(points)
	_hud.set_score(score)


func _on_player_crashed(impact_speed: float) -> void:
	var excess: float = impact_speed - combat_config.crash_damage_speed
	if excess > 0.0:
		_drone_health.take(excess * combat_config.crash_damage_scale)


func _on_player_damaged(_amount: float, remaining: float) -> void:
	_hud.set_health(remaining, _drone_health.max_health)
	_hud.flash_damage()


func _on_player_died() -> void:
	Effects.explosion(get_tree().root, _drone.global_position, 1.6)
	_drone.disarm()
	_drone.visible = false
	# Death arrives mid-physics (projectile hit or crash contact) — body
	# state changes must defer.
	_drone.set_deferred(&"freeze", true)
	_hud.show_death(true)
	get_tree().create_timer(combat_config.respawn_delay).timeout.connect(_respawn_player)


func _respawn_player() -> void:
	_drone.freeze = false
	_drone.reset_to_spawn()
	# Re-read max health so live tuning applies from the next life on.
	_drone_health.max_health = combat_config.player_max_health
	_drone_health.revive()
	_drone.visible = true
	_hud.show_death(false)
	_hud.set_health(_drone_health.current, _drone_health.max_health)
