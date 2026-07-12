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
var _last_measured: Vector3 = Vector3.ZERO
var _has_last_measured: bool = false


func update(target: Vector3, measured: Vector3, delta: float, config: FlightConfig) -> Vector3:
	if config.gyro_lpf_hz > 0.0:
		_gyro_filtered += (measured - _gyro_filtered) * _lpf_alpha(config.gyro_lpf_hz, delta)
	else:
		_gyro_filtered = measured

	var error: Vector3 = target - _gyro_filtered
	var limit: Vector3 = Vector3.ONE * config.integral_limit
	_i_term = (_i_term + config.rate_i * error * delta).clamp(-limit, limit)

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


## Crash recovery: contact spins the drone far beyond any commanded rate
## while the motors are powerless to track, winding the integrator to its
## clamp within a few ticks. The flight controller calls this every tick of
## the contact, discarding a fraction each time, so the seconds-long
## pull-away after recovery never builds up.
func decay_integrator(fraction: float) -> void:
	_i_term *= 1.0 - clampf(fraction, 0.0, 1.0)


## Telemetry view of the integrator's output contribution (overlay/blackbox).
func integrator() -> Vector3:
	return _i_term


## Called on disarm (handoff §6.3): integrators and filter state must not
## carry across flights.
func reset() -> void:
	_i_term = Vector3.ZERO
	_gyro_filtered = Vector3.ZERO
	_d_filtered = Vector3.ZERO
	_has_last_measured = false


## Exact first-order low-pass coefficient — tick-rate independent.
static func _lpf_alpha(cutoff_hz: float, delta: float) -> float:
	return 1.0 - exp(-TAU * cutoff_hz * delta)
