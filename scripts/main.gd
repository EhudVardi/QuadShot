extends Node3D

## Scene orchestration: camera switching (camera_toggle / X: FPV ↔ chase),
## combat config startup load, run/score/combo keeping (roadmap M3), and the
## player's damage → death → respawn loop (M2). Combat entities report in
## through their "destroyed" signals; waves flow through the WaveDirector.

@export var combat_config: CombatConfig

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera
@onready var _hud: GameHud = $Hud
@onready var _wave_director: WaveDirector = $WaveDirector
@onready var _missiles: MissileSystem = $Drone/FpvCamera/MissileSystem

var score: int = 0

var _combo: float = 1.0
var _last_kill_time: float = -1000.0


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	for scorer: Node in get_tree().get_nodes_in_group(&"targets") \
			+ get_tree().get_nodes_in_group(&"turrets"):
		scorer.connect(&"destroyed", _on_scorer_destroyed)
	_wave_director.enemy_destroyed.connect(_on_scorer_destroyed)
	_wave_director.wave_changed.connect(_hud.set_wave)
	_wave_director.run_ended.connect(_on_run_ended)
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
	# Arming starts (or restarts) a run — the summary stays readable until then.
	if not _wave_director.running and _drone.armed and _drone_health.alive:
		_start_run()
	_update_lock_indicator()


func _update_lock_indicator() -> void:
	var target: Node3D = _missiles.target
	var camera: Camera3D = get_viewport().get_camera_3d()
	if target == null or not is_instance_valid(target) or camera == null \
			or camera.is_position_behind(target.global_position):
		_hud.update_lock(false)
		return
	_hud.update_lock(true, camera.unproject_position(target.global_position),
			_missiles.lock_progress, _missiles.is_locked())


func _start_run() -> void:
	score = 0
	_combo = 1.0
	_last_kill_time = -1000.0
	_hud.set_score(0)
	_hud.set_combo(1)
	_hud.hide_run_summary()
	_wave_director.start_run()


func _on_scorer_destroyed(points: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_kill_time <= combat_config.combo_window:
		_combo = minf(_combo + 1.0, combat_config.combo_max)
	else:
		_combo = 1.0
	_last_kill_time = now
	var awarded: int = int(points * _combo)
	score += awarded
	_hud.set_score(score)
	_hud.set_combo(int(_combo))
	var feed: String = "+%d" % awarded
	if _combo > 1.0:
		feed += "  x%d" % int(_combo)
	_hud.add_kill_feed(feed)


func _on_run_ended(waves_cleared: int, kills: int) -> void:
	_hud.show_run_summary(waves_cleared, kills, score)


func _on_player_crashed(impact_speed: float) -> void:
	var excess: float = impact_speed - combat_config.crash_damage_speed
	if excess > 0.0:
		_drone_health.take(excess * combat_config.crash_damage_scale)


func _on_player_damaged(_amount: float, remaining: float) -> void:
	_hud.set_health(remaining, _drone_health.max_health)
	_hud.flash_damage(_incoming_fire_side())


## Maps the last projectile's incoming direction to a screen edge for the
## HUD. Crash damage has no direction and flashes the whole screen.
func _incoming_fire_side() -> StringName:
	var from_direction: Vector3 = _drone.last_hit_direction
	_drone.last_hit_direction = Vector3.ZERO
	if from_direction == Vector3.ZERO:
		return &"all"
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return &"all"
	var local: Vector3 = camera.global_basis.inverse() * from_direction
	if absf(local.x) > absf(local.z):
		return &"right" if local.x > 0.0 else &"left"
	return &"front" if local.z < 0.0 else &"back"


func _on_player_died() -> void:
	_wave_director.end_run()
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
