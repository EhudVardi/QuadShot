extends SceneTree

## Headless combat regression (roadmap M1): boots the full main scene,
## hovers the drone, force-fires the weapon at a target placed dead ahead
## on the camera axis, and asserts the kill lands, score is tallied, and
## the projectile pool never exhausts.
##
## Run: <godot> --headless -s scripts/tests/combat_check.gd --path .

const MAX_SECONDS: float = 5.0
const TARGET_DISTANCE: float = 25.0

var _main: Node3D
var _drone: FlightController
var _weapon: Weapon
var _pool: ProjectilePool
var _ticks: int = 0
var _ticks_max: int
var _setup_done: bool = false
var _killed: bool = false
var _pool_exhausted: bool = false


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
	if _pool.live_count() >= ProjectilePool.POOL_SIZE:
		_pool_exhausted = true
	if _killed:
		var score: int = _main.get("score")
		print("[combat_check] target destroyed after %d ticks, score %d, pool live %d"
				% [_ticks, score, _pool.live_count()])
		if score > 0 and not _pool_exhausted:
			print("[combat_check] PASS")
			quit(0)
		else:
			print("[combat_check] FAIL (score or pool)")
			quit(1)
		return
	if _ticks >= _ticks_max:
		print("[combat_check] FAIL: no kill within %.1f s (pool live %d)"
				% [MAX_SECONDS, _pool.live_count()])
		quit(1)


func _setup() -> void:
	_drone = _main.get_node("Drone") as FlightController
	_weapon = _drone.get_node("FpvCamera/Weapon") as Weapon
	_pool = _main.get_node("ProjectilePool") as ProjectilePool

	# Hover in place so the aim axis stays put while shots fly.
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())

	# Fresh target dead ahead on the weapon (camera) axis.
	var camera: Camera3D = _drone.get_node("FpvCamera") as Camera3D
	var target: PracticeTarget = (load("res://scenes/combat/target.tscn") as PackedScene) \
			.instantiate() as PracticeTarget
	_main.add_child(target)
	target.global_position = camera.global_position - camera.global_basis.z * TARGET_DISTANCE
	target.destroyed.connect(func(_points: float) -> void: _killed = true)
	# Registered after main._ready, so wire scoring up manually.
	target.destroyed.connect(_main._on_scorer_destroyed)

	_weapon.fire_override = true
	_setup_done = true
