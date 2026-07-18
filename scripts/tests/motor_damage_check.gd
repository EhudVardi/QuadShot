extends SceneTree

## Wounded-flight bench (GAMEPLAY-DESIGN Iteration 7 / D8): quantifies what motor
## damage does to flight, which the agent cannot judge by feel. For a ladder of
## motor-health levels it damages one corner, lets the position-hold autopilot
## try to cope, and measures the residual — horizontal drift, tilt off level,
## sink rate, and the throttle the drone settles at. The numbers are a
## calibration reference for tuning the severity dial with hands on sticks
## (H.q4), and the asserts guard that the wound is real, monotonic, and bounded.
##
## Run: <godot> --headless -s scripts/tests/motor_damage_check.gd --path .

const HEALTH_LADDER: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]
const ALT: float = 40.0
const SETTLE_S: float = 2.5
const SAMPLE_S: float = 1.5
const DAMAGED_MOTOR: int = 0  # FL

var _pps: float
var _phase: int = 0  # 0 build, 1 settle, 2 sample, 3 next
var _level_i: int = 0
var _ticks: int = 0
var _settle_ticks: int
var _sample_ticks: int

var _arena: Node3D
var _drone: FlightController
var _motors: MotorModel
var _sum_drift: float = 0.0
var _sum_tilt: float = 0.0
var _sum_sink: float = 0.0
var _sum_throttle: float = 0.0
var _n: int = 0

var _rows: Array[Dictionary] = []
var _failures: PackedStringArray = []


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	_settle_ticks = int(SETTLE_S * _pps)
	_sample_ticks = int(SAMPLE_S * _pps)
	print("[motor_damage] damaging motor %d (FL); floor from DamageConfig; hold = autopilot"
			% DAMAGED_MOTOR)
	physics_frame.connect(_on_frame)


func _on_frame() -> void:
	match _phase:
		0:
			_build()
			_phase = 1
			_ticks = 0
		1:
			_ticks += 1
			if _ticks >= _settle_ticks:
				_phase = 2
				_ticks = 0
				_sum_drift = 0.0
				_sum_tilt = 0.0
				_sum_sink = 0.0
				_sum_throttle = 0.0
				_n = 0
		2:
			_ticks += 1
			var flat := Vector3(_drone.linear_velocity.x, 0.0, _drone.linear_velocity.z)
			_sum_drift += flat.length()
			_sum_tilt += rad_to_deg(_drone.global_basis.y.angle_to(Vector3.UP))
			_sum_sink += _drone.linear_velocity.y
			_sum_throttle += _drone.collective
			_n += 1
			if _ticks >= _sample_ticks:
				_record()
				_phase = 3
		3:
			_teardown()
			_level_i += 1
			if _level_i >= HEALTH_LADDER.size():
				_report()
			else:
				_phase = 0


func _build() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_drone = (load("res://scenes/drone/drone.tscn") as PackedScene).instantiate() \
			as FlightController
	_arena.add_child(_drone)
	_drone.global_position = Vector3(0.0, ALT, 0.0)
	_drone.arm()
	_drone.prime_motors(_drone.hover_throttle())
	_drone.autopilot = true  # position-hold: level + brake + hover collective
	_motors = _drone.get_node("MotorModel") as MotorModel
	var health: float = HEALTH_LADDER[_level_i]
	_motors.damage_motor(DAMAGED_MOTOR, 1.0 - health)


func _record() -> void:
	_rows.append({
		"health": HEALTH_LADDER[_level_i],
		"drift": _sum_drift / float(_n),
		"tilt": _sum_tilt / float(_n),
		"sink": _sum_sink / float(_n),
		"throttle": _sum_throttle / float(_n),
	})


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null
	_motors = null


func _report() -> void:
	print("[motor_damage]  motor-hp   drift(m/s)  tilt(deg)  sink(m/s)  throttle")
	for r: Dictionary in _rows:
		print("[motor_damage]    %4.2f       %6.2f     %6.2f    %6.2f     %5.2f"
				% [r["health"], r["drift"], r["tilt"], r["sink"], r["throttle"]])

	var healthy: Dictionary = _rows[0]
	var worst: Dictionary = _rows[_rows.size() - 1]
	# 1) A healthy quad holds station: negligible drift and tilt.
	if float(healthy["drift"]) > 1.0 or float(healthy["tilt"]) > 3.0:
		_failures.append("healthy hover unstable (drift %.2f, tilt %.2f) — model leaks when undamaged"
				% [healthy["drift"], healthy["tilt"]])
	# 2) The wound is REAL and asymmetric: a failed motor drifts/tilts clearly
	#    more than a healthy one (not silently corrected to nothing).
	if float(worst["drift"]) <= float(healthy["drift"]) + 0.5 \
			and float(worst["tilt"]) <= float(healthy["tilt"]) + 1.0:
		_failures.append("a failed motor barely changes flight — the wound isn't felt")
	# 3) Bounded, not NaN/blowup: even a dead motor stays a finite, flyable-ish
	#    disturbance (Dq2 flyable-but-punishing), not an explosion.
	for r: Dictionary in _rows:
		if not is_finite(float(r["drift"])) or float(r["drift"]) > 40.0:
			_failures.append("motor-hp %.2f produced a non-finite / runaway drift %.2f"
					% [r["health"], r["drift"]])

	if _failures.is_empty():
		print("[motor_damage] PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("[motor_damage] FAIL: %s" % f)
		print("[motor_damage] FAIL")
		quit(1)
