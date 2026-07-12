extends SceneTree

## Headless measurement tool (not a pass/fail check): injects an identical
## roll-rate step into the real drone at several rate_ff gains and prints
## the response latency of each — the deterministic answer to "does
## feedforward make it snappier, and by how much".
##
## Run: <godot> --headless -s scripts/tests/step_response.gd --path .

const STEP_RATE: float = 5.0
## Progress snapshots (ms after step start) printed alongside the crossings.
const SNAPSHOT_MS: Array[float] = [50.0, 100.0, 200.0, 400.0, 800.0]
## The commanded rate ramps over this many ticks (~50 ms) — the slew of a
## fast human flick; a 1-tick step would hand FF a single unreal impulse.
const RAMP_TICKS: int = 12
const SETTLE_TICKS: int = 120
const MEASURE_TICKS: int = 480
const FF_GAINS: Array[float] = [0.0, 0.0005, 0.001, 0.002]

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


func _on_physics_frame() -> void:
	match _phase:
		0:
			if not _drone.is_node_ready():
				return
			_config = _drone.config
			print("[step_response] rates from the loaded config, roll step %.1f rad/s"
					% STEP_RATE)
			_start_run()
			_phase = 1
		1:
			# Settle in a stable hover before the step.
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
				if _run >= FF_GAINS.size():
					quit(0)
					return
				_start_run()
				_phase = 1


func _start_run() -> void:
	_config.rate_ff = Vector3.ONE * FF_GAINS[_run]
	_drone.rate_override_enabled = false
	_drone.rate_override = Vector3.ZERO
	_drone.reset_to_spawn()
	_drone.global_position = Vector3(0, 30, 0)
	# Previous run's hover throttle is still latched in `collective` and
	# would make arm() refuse (throttle-not-zero safety).
	_drone.throttle_override = 0.0
	_drone.collective = 0.0
	_drone.arm()
	_drone.throttle_override = _drone.hover_throttle()
	_drone.prime_motors(_drone.hover_throttle())
	_tick = 0


func _report_run() -> void:
	var tick_ms: float = 1000.0 / float(Engine.physics_ticks_per_second)
	var marks: Dictionary = {}
	for fraction: float in [0.5, 0.63, 0.9]:
		for i: int in _samples.size():
			if _samples[i] >= STEP_RATE * fraction:
				marks[fraction] = float(i) * tick_ms
				break
	var peak: float = 0.0
	for s: float in _samples:
		peak = maxf(peak, s)
	var overshoot: float = maxf(peak - STEP_RATE, 0.0) / STEP_RATE * 100.0
	var snapshots: String = ""
	for at_ms: float in SNAPSHOT_MS:
		var index: int = mini(int(at_ms / tick_ms), _samples.size() - 1)
		snapshots += "  @%dms=%.1f" % [int(at_ms), _samples[index]]
	print("[step_response] ff=%.4f  t50=%5.1fms  t63=%5.1fms  t90=%5.1fms  overshoot=%4.1f%%%s"
			% [FF_GAINS[_run], marks.get(0.5, -1.0), marks.get(0.63, -1.0),
			marks.get(0.9, -1.0), overshoot, snapshots])
