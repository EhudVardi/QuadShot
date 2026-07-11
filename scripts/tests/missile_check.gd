extends SceneTree

## Headless missile regression: plant a stationary enemy dead ahead on the
## camera axis, let the lock build, auto-fire on lock, and assert the homing
## missile kills it.
##
## Run: <godot> --headless -s scripts/tests/missile_check.gd --path .

const MAX_SECONDS: float = 10.0
const TARGET_DISTANCE: float = 30.0

var _main: Node3D
var _drone: FlightController
var _missiles: MissileSystem
var _ticks: int = 0
var _ticks_max: int
var _setup_done: bool = false
var _killed: bool = false
## Peak observed lock progress. The locked state itself lasts one tick
## (lock -> auto-fire -> reset inside a single physics callback), so the
## test asserts the buildup rather than the instantaneous flag.
var _max_lock_progress: float = 0.0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if not _setup_done:
		if not _main.is_node_ready():
			return
		_setup()
		return
	_ticks += 1
	_max_lock_progress = maxf(_max_lock_progress, _missiles.lock_progress)
	if _killed:
		var built_lock: bool = _max_lock_progress > 0.5
		print("[missile_check] enemy destroyed after %d ticks (peak lock %.2f)"
				% [_ticks, _max_lock_progress])
		print("[missile_check] %s" % ("PASS" if built_lock else "FAIL (lock never built)"))
		quit(0 if built_lock else 1)
		return
	if _ticks >= _ticks_max:
		print("[missile_check] FAIL: no kill within %.1f s (peak lock %.2f)"
				% [MAX_SECONDS, _max_lock_progress])
		quit(1)


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_missiles = _drone.get_node("FpvCamera/MissileSystem") as MissileSystem
	var config: CombatConfig = _main.get("combat_config")
	# Deterministic conditions on the shared config: the planted enemy cannot
	# move or hurt, turrets and wave enemies stay out of the fight.
	config.enemy_speed = 0.0
	config.enemy_accel = 0.0
	config.enemy_damage = 0.0
	config.turret_range = 0.0
	config.wave_base_enemies = 1.0

	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())

	var camera: Camera3D = _drone.get_node("FpvCamera") as Camera3D
	# The uptilt is normally applied on idle frames; force it now so the
	# enemy is planted on the axis the lock cone will actually use.
	var flight_config: FlightConfig = _drone.get("config")
	camera.rotation_degrees.x = flight_config.fpv_uptilt_deg
	var enemy: EnemyDrone = (load("res://scenes/combat/enemy_drone.tscn") as PackedScene) \
			.instantiate() as EnemyDrone
	_main.add_child(enemy)
	enemy.global_position = camera.global_position - camera.global_basis.z * TARGET_DISTANCE
	enemy.destroyed.connect(func(_points: float) -> void: _killed = true)

	_missiles.fire_override = true
	_setup_done = true
