class_name RateController
extends RefCounted

## Per-axis PID on angular-rate error (handoff §6.3), pilot axes
## (x=roll, y=pitch, z=yaw), with Betaflight-style filtering: the measured
## rates pass a gyro low-pass before the PID, and the derivative passes its
## own low-pass — wobble is fought in the filters, never in the physics.
## D acts on the (filtered) measurement, not the error, so stick steps cause
## no derivative kick. The integral state is stored as its output
## contribution and clamped there (anti-windup) — this also keeps it
## well-behaved when I gains are retuned live.

var _i_term: Vector3 = Vector3.ZERO
var _gyro_filtered: Vector3 = Vector3.ZERO
var _d_filtered: Vector3 = Vector3.ZERO
var _setpoint_filtered: Vector3 = Vector3.ZERO
var _last_measured: Vector3 = Vector3.ZERO
var _has_last_measured: bool = false


func update(target: Vector3, measured: Vector3, delta: float, config: FlightConfig,
		in_contact: bool = false) -> Vector3:
	if config.gyro_lpf_hz > 0.0:
		_gyro_filtered += (measured - _gyro_filtered) * _lpf_alpha(config.gyro_lpf_hz, delta)
	else:
		_gyro_filtered = measured

	var error: Vector3 = target - _gyro_filtered
	# Crash-condition gating (per axis): during contact, or while the rate
	# error is far beyond anything flight produces (a crash tumble), the
	# motors can't meaningfully track — integrating only banks a bias that
	# later forces an uncommanded drift of i/P rad/s while it unwinds over
	# ~P/I seconds. Blackbox-verified: windup happens in the ~0.5 s tumble
	# AFTER contact, at 3-8x the gate; honest tracking error stays under it.
	# I-term relax (Betaflight): while the live setpoint runs ahead of its
	# own low-passed shadow — i.e. during a stick flick — fade I accumulation
	# out, because the airframe's lag there is by design, not a trim error.
	var relax: Vector3 = Vector3.ONE
	if config.iterm_relax_hz > 0.0:
		_setpoint_filtered += (target - _setpoint_filtered) \
				* _lpf_alpha(config.iterm_relax_hz, delta)
		var threshold: float = deg_to_rad(config.iterm_relax_threshold_deg)
		for axis: int in 3:
			relax[axis] = clampf(
					1.0 - absf(target[axis] - _setpoint_filtered[axis]) / threshold,
					0.0, 1.0)
	else:
		_setpoint_filtered = target

	var gate: float = deg_to_rad(config.iterm_error_gate_deg)
	var keep: float = 1.0 - clampf(config.crash_iterm_decay, 0.0, 1.0)
	for axis: int in 3:
		if in_contact or (gate > 0.0 and absf(error[axis]) > gate):
			_i_term[axis] *= keep
		else:
			_i_term[axis] = clampf(
					_i_term[axis] + config.rate_i[axis] * error[axis] * delta * relax[axis],
					-config.integral_limit, config.integral_limit)

	var d_raw: Vector3 = Vector3.ZERO
	if _has_last_measured and delta > 0.0:
		d_raw = (_gyro_filtered - _last_measured) / delta
	_last_measured = _gyro_filtered
	_has_last_measured = true
	if config.dterm_lpf_hz > 0.0:
		_d_filtered += (d_raw - _d_filtered) * _lpf_alpha(config.dterm_lpf_hz, delta)
	else:
		_d_filtered = d_raw

	return config.rate_p * error + _i_term - config.rate_d * _d_filtered


## Telemetry view of the integrator's output contribution (overlay/blackbox).
func integrator() -> Vector3:
	return _i_term


## Called on disarm (handoff §6.3): integrators and filter state must not
## carry across flights.
func reset() -> void:
	_i_term = Vector3.ZERO
	_gyro_filtered = Vector3.ZERO
	_d_filtered = Vector3.ZERO
	_setpoint_filtered = Vector3.ZERO
	_has_last_measured = false


## Exact first-order low-pass coefficient — tick-rate independent.
static func _lpf_alpha(cutoff_hz: float, delta: float) -> float:
	return 1.0 - exp(-TAU * cutoff_hz * delta)
