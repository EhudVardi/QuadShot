extends SceneTree

## Headless tuning bench: sweeps rate_p x angular_damping (on top of the
## pilot's loaded config) and prints, per combination, the response of an
## identical 50 ms roll flick to 5 rad/s — rise times, what rate is actually
## sustained, and post-transient ripple (the P-too-high tell). Feedforward
## is forced off so the sweep isolates the raw loop.
##
## Run: <godot> --headless -s scripts/tests/rate_tune_sweep.gd --path .

const STEP_RATE: float = 5.0
const RAMP_TICKS: int = 12
const SETTLE_TICKS: int = 120
const MEASURE_TICKS: int = 480

const P_VALUES: Array[float] = [0.004, 0.008, 0.012, 0.02]
const DAMP_VALUES: Array[float] = [0.02, 0.008, 0.002]

var _drone: FlightController
var _config: FlightConfig
var _phase: int = 0
var _run: int = 0
var _tick: int = 0
var _samples: Array[float] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/drone/drone.tscn")
	_drone = scene.instantiate() as FlightController
	root.add_child(_drone)
	physics_frame.connect(_on_physics_frame)


func _combo(run: int) -> Array[float]:
	return [P_VALUES[run / DAMP_VALUES.size()],
			DAMP_VALUES[run % DAMP_VALUES.size()]]


func _on_physics_frame() -> void:
	match _phase:
		0:
			if not _drone.is_node_ready():
				return
			_config = _drone.config
			print("[sweep] roll step %.1f rad/s over %d ms; ff off; baseline D=%.5f I=%.4f"
					% [STEP_RATE, int(RAMP_TICKS * 1000.0 / 240.0),
					_config.rate_d.x, _config.rate_i.x])
			print("[sweep] %-8s %-8s %6s %6s %8s %9s %7s"
					% ["P", "damp", "t63ms", "t90ms", "@100ms", "sustained", "ripple"])
			_start_run()
			_phase = 1
		1:
			_tick += 1
			if _tick >= SETTLE_TICKS:
				_drone.rate_override_enabled = true
				_tick = 0
				_samples.clear()
				_phase = 2
		2:
			_drone.rate_override = Vector3(
					STEP_RATE * minf(float(_tick) / float(RAMP_TICKS), 1.0), 0.0, 0.0)
			_samples.append(_drone.telemetry_measured_rates.x)
			_tick += 1
			if _tick >= MEASURE_TICKS:
				_report_run()
				_run += 1
				if _run >= P_VALUES.size() * DAMP_VALUES.size():
					quit(0)
					return
				_start_run()
				_phase = 1


func _start_run() -> void:
	var combo: Array[float] = _combo(_run)
	_config.rate_p = Vector3.ONE * combo[0]
	_config.angular_damping = combo[1]
	_config.rate_ff = Vector3.ZERO
	_drone.rate_override_enabled = false
	_drone.rate_override = Vector3.ZERO
	_drone.reset_to_spawn()
	_drone.global_position = Vector3(0, 30, 0)
	_drone.throttle_override = 0.0
	_drone.collective = 0.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	_tick = 0


func _report_run() -> void:
	var combo: Array[float] = _combo(_run)
	var tick_ms: float = 1000.0 / float(Engine.physics_ticks_per_second)
	var t63: float = -1.0
	var t90: float = -1.0
	for i: int in _samples.size():
		if t63 < 0.0 and _samples[i] >= STEP_RATE * 0.63:
			t63 = float(i) * tick_ms
		if t90 < 0.0 and _samples[i] >= STEP_RATE * 0.9:
			t90 = float(i) * tick_ms
			break
	var at_100ms: float = _samples[mini(int(100.0 / tick_ms), _samples.size() - 1)]
	# Sustained rate and ripple over the final half second.
	var tail: Array[float] = _samples.slice(_samples.size() - 120)
	var mean: float = 0.0
	for s: float in tail:
		mean += s
	mean /= float(tail.size())
	var ripple: float = 0.0
	for s: float in tail:
		ripple = maxf(ripple, absf(s - mean))
	print("[sweep] %-8.4f %-8.3f %6.1f %6.1f %8.2f %9.2f %7.3f"
			% [combo[0], combo[1], t63, t90, at_100ms, mean, ripple])
