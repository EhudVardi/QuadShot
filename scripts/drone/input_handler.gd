class_name InputHandler
extends Node

## Gamepad input pipeline (handoff §7). Stick axes are read raw from the
## joypad — through the axis each InputMap action is bound to, so bindings
## stay remappable in one place — because a single InputMap action cannot
## report a full [-1, 1] axis via get_action_strength, and flight sticks
## need the full range. Shaping per §6.3: deadzone → expo → max rate.
## Buttons (arm/reset/…) are plain digital actions, polled where they are
## handled (flight_controller, main).

## Throttle after deadzone and the selected curve: [0, 1] normally,
## [-1, 1] in 3D mode (negative = reverse thrust).
var throttle: float = 0.0
## Target body rates in rad/s, pilot axes (x=roll+right, y=pitch+nose-up,
## z=yaw+right).
var rate_command: Vector3 = Vector3.ZERO
## Shaped stick deflections [-1, 1] after deadzone+expo, same axes —
## angle mode maps these to target attitudes instead of rates.
var stick_shaped: Vector3 = Vector3.ZERO
## Physical stick positions for the HUD display, raw (no deadzone/expo/curve):
## x = +right, y = +up, [-1, 1]. Left stick = yaw/throttle, right = roll/pitch.
var stick_left: Vector2 = Vector2.ZERO
var stick_right: Vector2 = Vector2.ZERO

var _axis_throttle: int = JOY_AXIS_LEFT_Y
var _axis_yaw: int = JOY_AXIS_LEFT_X
var _axis_pitch: int = JOY_AXIS_RIGHT_Y
var _axis_roll: int = JOY_AXIS_RIGHT_X

## Joypad name fragments that identify a USB radio handset (EdgeTX/OpenTX
## joystick mode). Matching is case-insensitive on Input.get_joy_name().
const _RADIO_NAME_HINTS: Array[String] = [
	"radiomaster", "tx16", "tx12", "boxer", "zorro", "pocket",
	"edgetx", "opentx", "taranis", "jumper", "frsky", "betafpv",
]


func _ready() -> void:
	_axis_throttle = _bound_axis(&"throttle", _axis_throttle)
	_axis_yaw = _bound_axis(&"yaw", _axis_yaw)
	_axis_pitch = _bound_axis(&"pitch", _axis_pitch)
	_axis_roll = _bound_axis(&"roll", _axis_roll)
	# Debug aid for radio setup: see what the OS actually calls each device.
	for device: int in Input.get_connected_joypads():
		print("[input] joypad %d: %s" % [device, Input.get_joy_name(device)])


func poll(config: FlightConfig, hover_throttle: float, delta: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		throttle = 0.0
		rate_command = Vector3.ZERO
		stick_shaped = Vector3.ZERO
		stick_left = Vector2.ZERO
		stick_right = Vector2.ZERO
		return
	var throttle_stick: float
	var roll_stick: float
	var pitch_stick: float
	var yaw_stick: float

	var radio: int = -1
	if config.input_profile != FlightConfig.InputProfile.GAMEPAD:
		radio = _radio_device()
	if radio >= 0:
		# EdgeTX/OpenTX joystick mode maps channels straight onto axes 0-3 in
		# the radio's channel order. Assumed signs: stick up/right = axis
		# positive, and pilot pitch = pulled back is positive (hence the one
		# negation). Any axis that runs backwards gets flipped on the radio
		# itself (Outputs page) — the radio is the remapping UI.
		var throttle_axis: int = 2
		var roll_axis: int = 0
		var pitch_axis: int = 1
		var yaw_axis: int = 3
		if config.input_profile == FlightConfig.InputProfile.RADIO_TAER:
			throttle_axis = 0
			roll_axis = 1
			pitch_axis = 2
			yaw_axis = 3
		throttle_stick = Input.get_joy_axis(radio, throttle_axis as JoyAxis)
		roll_stick = Input.get_joy_axis(radio, roll_axis as JoyAxis)
		pitch_stick = -Input.get_joy_axis(radio, pitch_axis as JoyAxis)
		yaw_stick = Input.get_joy_axis(radio, yaw_axis as JoyAxis)
	else:
		# Gamepad path (also the fallback when a radio profile is selected but
		# no radio is connected). Sign conventions (Mode 2, RC-style): stick up
		# reads negative on Godot/SDL Y axes, hence the throttle negation.
		# Pitch is NOT negated: stick forward = nose down (negative pilot
		# pitch), pulled back = nose up, exactly the raw axis sign.
		var device: int = pads[0]
		throttle_stick = -Input.get_joy_axis(device, _axis_throttle)
		roll_stick = Input.get_joy_axis(device, _axis_roll)
		pitch_stick = Input.get_joy_axis(device, _axis_pitch)
		yaw_stick = Input.get_joy_axis(device, _axis_yaw)
	stick_left = Vector2(yaw_stick, throttle_stick)
	stick_right = Vector2(roll_stick, -pitch_stick)

	var throttle_deadzoned: float = _apply_deadzone(throttle_stick, config.stick_deadzone)
	var raw_throttle: float
	match config.throttle_curve:
		FlightConfig.ThrottleCurve.HOVER_CENTERED:
			raw_throttle = _throttle_hover_centered_curve(throttle_deadzoned, hover_throttle)
		FlightConfig.ThrottleCurve.THREE_D:
			# 3D (§Betaflight-style): center = zero thrust, below = reverse.
			# The stick deadzone doubles as the center deadband.
			raw_throttle = throttle_deadzoned
		_:
			raw_throttle = _throttle_raw_curve(throttle_deadzoned)
	var raw_shaped := Vector3(
		_shape(roll_stick, config.stick_deadzone, config.expo.x),
		_shape(pitch_stick, config.stick_deadzone, config.expo.y),
		_shape(yaw_stick, config.stick_deadzone, config.expo.z)
	)
	# Optional RC smoothing (part of the epi-filtering set; 0 = raw sticks).
	if config.rc_smoothing_hz > 0.0:
		var alpha: float = 1.0 - exp(-TAU * config.rc_smoothing_hz * delta)
		throttle += (raw_throttle - throttle) * alpha
		stick_shaped += (raw_shaped - stick_shaped) * alpha
	else:
		throttle = raw_throttle
		stick_shaped = raw_shaped
	rate_command = Vector3(
		stick_shaped.x * deg_to_rad(config.max_rate_deg.x),
		stick_shaped.y * deg_to_rad(config.max_rate_deg.y),
		stick_shaped.z * deg_to_rad(config.max_rate_deg.z)
	)


func _bound_axis(action: StringName, fallback: int) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion != null:
			return motion.axis
	return fallback


## First connected joypad whose name looks like a radio handset, or -1.
func _radio_device() -> int:
	for device: int in Input.get_connected_joypads():
		var joy_name: String = Input.get_joy_name(device).to_lower()
		for hint: String in _RADIO_NAME_HINTS:
			if joy_name.contains(hint):
				return device
	return -1


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
static func _throttle_raw_curve(value: float) -> float:
	return (value + 1.0) * 0.5


## 'hover_centered' (§7): mid-stick = computed hover throttle, smoothstep
## blend to 0 and 1 at the extremes. Monotonic and C1 at center; the flat
## slope around mid-stick is deliberate — it makes hover holdable on a
## springy self-centering stick.
static func _throttle_hover_centered_curve(value: float, hover: float) -> float:
	var stick_fraction: float = (value + 1.0) * 0.5
	var center: float = clampf(hover, 0.05, 0.95)
	if stick_fraction < 0.5:
		return center * _smoothstep01(stick_fraction * 2.0)
	return center + (1.0 - center) * _smoothstep01(stick_fraction * 2.0 - 1.0)


static func _smoothstep01(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)
