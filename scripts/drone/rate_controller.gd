class_name RateController
extends RefCounted

## Per-axis PID on angular-rate error (handoff §6.3), pilot axes
## (x=roll, y=pitch, z=yaw). D acts on the measurement, not the error, so
## stick steps cause no derivative kick. The integral state is stored as its
## output contribution and clamped there (anti-windup) — this also keeps it
## well-behaved when I gains are retuned live.

var _i_term: Vector3 = Vector3.ZERO
var _last_measured: Vector3 = Vector3.ZERO
var _has_last_measured: bool = false


func update(target: Vector3, measured: Vector3, delta: float, config: FlightConfig) -> Vector3:
	var error: Vector3 = target - measured
	var limit: Vector3 = Vector3.ONE * config.integral_limit
	_i_term = (_i_term + config.rate_i * error * delta).clamp(-limit, limit)

	var d_measured: Vector3 = Vector3.ZERO
	if _has_last_measured and delta > 0.0:
		d_measured = (measured - _last_measured) / delta
	_last_measured = measured
	_has_last_measured = true

	return config.rate_p * error + _i_term - config.rate_d * d_measured


## Called on disarm (handoff §6.3): integrators must not carry across flights.
func reset() -> void:
	_i_term = Vector3.ZERO
	_has_last_measured = false
