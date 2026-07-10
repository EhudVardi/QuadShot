extends SceneTree

## Headless physics sanity check (handoff §12): with motors primed at the
## computed hover throttle, the drone must hold altitude. Guards the
## thrust/mass/gravity arithmetic, not flight feel.
##
## Run: <godot> --headless -s scripts/tests/hover_check.gd --path .

const SIM_SECONDS: float = 4.0
const TOLERANCE_M: float = 0.5
const START_ALTITUDE: float = 10.0

var _drone: FlightController
var _ticks_total: int
var _ticks: int = 0
var _setup_done: bool = false


func _initialize() -> void:
	var drone_scene: PackedScene = load("res://scenes/drone/drone.tscn")
	_drone = drone_scene.instantiate() as FlightController
	root.add_child(_drone)
	_ticks_total = int(SIM_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	# The tree is not running during _initialize (the drone is not inside the
	# tree yet and its @onready vars are unresolved), so setup waits for the
	# first physics frame after the node is ready.
	if not _setup_done:
		if not _drone.is_node_ready():
			return
		_drone.global_position = Vector3(0.0, START_ALTITUDE, 0.0)
		_drone.arm()
		var hover: float = _drone.hover_throttle()
		_drone.throttle_override = hover
		# Prime past the spool-up: we are testing hover equilibrium, and the
		# ~0.5 m/s sink picked up while motors lag from zero would never decay
		# (at exact hover thrust the net force on any residual velocity is zero).
		_drone.prime_motors(hover)
		print("[hover_check] hover throttle = %.4f, simulating %d ticks at %d Hz"
				% [hover, _ticks_total, Engine.physics_ticks_per_second])
		_setup_done = true
		return
	_ticks += 1
	if _ticks < _ticks_total:
		return
	var drift: float = absf(_drone.global_position.y - START_ALTITUDE)
	print("[hover_check] altitude after %.1f s: %.3f m (drift %.3f m, tolerance %.1f m)"
			% [SIM_SECONDS, _drone.global_position.y, drift, TOLERANCE_M])
	if drift <= TOLERANCE_M:
		print("[hover_check] PASS")
		quit(0)
	else:
		print("[hover_check] FAIL")
		quit(1)
