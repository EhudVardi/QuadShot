extends SceneTree

## Headless physics sanity check (handoff §12): with motors primed at the
## computed hover throttle, the drone must hold altitude. Guards the
## thrust/mass/gravity arithmetic, not flight feel.
##
## EVERY FRAME IN THE ROSTER, not just the shipped one (P3.3): a frame is a mass
## and a thrust-to-weight ratio, and the cheapest way to ship one that cannot
## hold the air is to write the .tres and never fly it. This runs on the repo
## defaults (Frames.build disables user:// overrides), so it checks the numbers
## that are committed rather than the ones on this machine.
##
## Run: <godot> --headless -s scripts/tests/hover_check.gd --path .

const SIM_SECONDS: float = 4.0
const TOLERANCE_M: float = 0.5
const START_ALTITUDE: float = 10.0

var _drone: FlightController
var _ticks_total: int
var _ticks: int = 0
var _setup_done: bool = false
var _frame_i: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_ticks_total = int(SIM_SECONDS * float(Engine.physics_ticks_per_second))
	_build_frame()
	physics_frame.connect(_on_physics_frame)


func _build_frame() -> void:
	_drone = Frames.build(Frames.ROSTER[_frame_i])
	root.add_child(_drone)
	_ticks = 0
	_setup_done = false


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
		print("[hover_check] %s: mass %.2f kg, TWR %.1f, hover throttle = %.4f, simulating %d ticks at %d Hz"
				% [_drone.frame.display_name, _drone.config.mass,
				_drone.config.thrust_to_weight_ratio, hover, _ticks_total,
				Engine.physics_ticks_per_second])
		_setup_done = true
		return
	_ticks += 1
	if _ticks < _ticks_total:
		return
	var drift: float = absf(_drone.global_position.y - START_ALTITUDE)
	print("[hover_check] %s: altitude after %.1f s: %.3f m (drift %.3f m, tolerance %.1f m)"
			% [_drone.frame.display_name, SIM_SECONDS,
			_drone.global_position.y, drift, TOLERANCE_M])
	if drift > TOLERANCE_M:
		_failures.append("%s drifted %.3f m (tolerance %.1f m)"
				% [_drone.frame.display_name, drift, TOLERANCE_M])
	_drone.queue_free()
	_frame_i += 1
	if _frame_i < Frames.ROSTER.size():
		_build_frame()
		return
	if _failures.is_empty():
		print("[hover_check] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[hover_check] FAIL: %s" % f)
		print("[hover_check] FAIL")
		quit(1)
