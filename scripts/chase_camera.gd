extends Camera3D

## Smoothed third-person follow for debugging physics visually (handoff §10).
## Follows the drone's horizontal heading only, so rolls and flips don't
## whip the camera around.

@export var target: FlightController

var _heading: Vector3 = Vector3(0, 0, -1)


func _process(delta: float) -> void:
	if target == null:
		return
	var config: FlightConfig = target.config
	var forward: Vector3 = -target.global_basis.z
	forward.y = 0.0
	# Keep the last valid heading while the drone points straight up/down.
	if forward.length_squared() > 0.001:
		_heading = forward.normalized()
	var desired: Vector3 = target.global_position \
			- _heading * config.chase_distance \
			+ Vector3.UP * config.chase_height
	global_position = global_position.lerp(desired, 1.0 - exp(-config.chase_smoothing * delta))
	look_at(target.global_position, Vector3.UP)
