class_name InputHandler
extends Node

## Gamepad input pipeline (handoff §7). Stick axes are read raw from the
## joypad — through the axis each InputMap action is bound to, so bindings
## stay remappable in one place — because a single InputMap action cannot
## report a full [-1, 1] axis via get_action_strength, and flight sticks
## need the full range. Shaping per §6.3: deadzone → expo → max rate.
## Buttons (arm/reset/…) are plain digital actions, polled where they are
## handled (flight_controller, main).

## Throttle [0, 1] after deadzone and curve.
var throttle: float = 0.0
## Target body rates in rad/s, pilot axes (x=roll+right, y=pitch+nose-up,
## z=yaw+right).
var rate_command: Vector3 = Vector3.ZERO

var _axis_throttle: int = JOY_AXIS_LEFT_Y
var _axis_yaw: int = JOY_AXIS_LEFT_X
var _axis_pitch: int = JOY_AXIS_RIGHT_Y
var _axis_roll: int = JOY_AXIS_RIGHT_X


func _ready() -> void:
	_axis_throttle = _bound_axis(&"throttle", _axis_throttle)
	_axis_yaw = _bound_axis(&"yaw", _axis_yaw)
	_axis_pitch = _bound_axis(&"pitch", _axis_pitch)
	_axis_roll = _bound_axis(&"roll", _axis_roll)


func poll(config: FlightConfig) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		throttle = 0.0
		rate_command = Vector3.ZERO
		return
	var device: int = pads[0]

	# Sign conventions (Mode 2, RC-style). Stick up reads negative on
	# Godot/SDL Y axes, hence the throttle negation. Pitch is NOT negated:
	# stick forward = nose down (negative pilot pitch), pulled back = nose up,
	# which is exactly the raw axis sign.
	var throttle_stick: float = -Input.get_joy_axis(device, _axis_throttle)
	var roll_stick: float = Input.get_joy_axis(device, _axis_roll)
	var pitch_stick: float = Input.get_joy_axis(device, _axis_pitch)
	var yaw_stick: float = Input.get_joy_axis(device, _axis_yaw)

	throttle = _throttle_raw_curve(_apply_deadzone(throttle_stick, config.stick_deadzone))
	rate_command = Vector3(
		_shape(roll_stick, config.stick_deadzone, config.expo.x) * deg_to_rad(config.max_rate_deg.x),
		_shape(pitch_stick, config.stick_deadzone, config.expo.y) * deg_to_rad(config.max_rate_deg.y),
		_shape(yaw_stick, config.stick_deadzone, config.expo.z) * deg_to_rad(config.max_rate_deg.z)
	)


func _bound_axis(action: StringName, fallback: int) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion != null:
			return motion.axis
	return fallback


## Deadzone with rescale, so output is continuous at the deadzone edge.
static func _apply_deadzone(value: float, deadzone: float) -> float:
	if absf(value) < deadzone:
		return 0.0
	return signf(value) * (absf(value) - deadzone) / (1.0 - deadzone)


## Handoff §6.3: out = (1-e)·x + e·x³
static func _apply_expo(value: float, expo: float) -> float:
	return (1.0 - expo) * value + expo * value * value * value


static func _shape(value: float, deadzone: float, expo: float) -> float:
	return _apply_expo(_apply_deadzone(value, deadzone), expo)


## 'raw' throttle curve (§7): stick [-1, 1] → [0, 1] linearly.
## 'hover_centered' (mid-stick = hover) arrives in Phase 3.
static func _throttle_raw_curve(value: float) -> float:
	return (value + 1.0) * 0.5
