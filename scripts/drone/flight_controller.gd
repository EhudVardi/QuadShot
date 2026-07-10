class_name FlightController
extends RigidBody3D

## Phase 1 scope: arm/disarm, raw collective throttle to all four motors,
## explicit quadratic drag and angular damping. The rate controller, mixer,
## and gamepad pipeline arrive in Phase 2.

@export var config: FlightConfig

@onready var _motors: MotorModel = $MotorModel

var armed: bool = false
## Raw collective throttle [0, 1], fed equally to all motors in Phase 1.
var collective: float = 0.0

var _spawn_transform: Transform3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	mass = config.mass
	_spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	_read_temp_keyboard_throttle(delta)
	if armed:
		_motors.set_all_commands(collective)
	else:
		_motors.force_stop()
	_motors.step(delta, config)
	_motors.apply_thrust(self, config, _gravity)
	_apply_aerodynamics()


func arm() -> bool:
	if armed:
		return true
	if collective >= config.arm_throttle_threshold:
		print("[drone] arm refused: throttle %.0f%% is above the %.0f%% threshold"
				% [collective * 100.0, config.arm_throttle_threshold * 100.0])
		return false
	armed = true
	print("[drone] ARMED")
	return true


func disarm() -> void:
	armed = false
	_motors.force_stop()
	print("[drone] disarmed")


func reset_to_spawn() -> void:
	disarm()
	collective = 0.0
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	print("[drone] reset to spawn")


## Throttle fraction at which total thrust equals weight. With the linear
## thrust model this is exactly 1/TWR; computed honestly so it stays correct
## if the thrust model gains a curve later.
func hover_throttle() -> float:
	return config.mass * _gravity / _motors.max_total_thrust(config, _gravity)


## Test/setup hook: skip motor spool-up (see scripts/tests/hover_check.gd).
func prime_motors(value: float) -> void:
	_motors.prime(value)


func _apply_aerodynamics() -> void:
	# Explicit, config-driven — the body's built-in damping is disabled
	# (handoff §6.5) so everything the overlay can tune lives in our model.
	apply_central_force(-config.drag_coefficient * linear_velocity.length() * linear_velocity)
	apply_torque(-config.angular_damping * angular_velocity)


# ---------------------------------------------------------------------------
# TEMPORARY Phase 1 keyboard input — replaced by the gamepad input pipeline
# (input_handler.gd) in Phase 2. Enter: arm/disarm. W/S: throttle. R: reset.
# The rate constant below is temp code, exempt from the config rule; it dies
# with this block.
# ---------------------------------------------------------------------------
const _TEMP_THROTTLE_RATE: float = 0.4


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ENTER:
			if armed:
				disarm()
			else:
				arm()
		KEY_R:
			reset_to_spawn()


func _read_temp_keyboard_throttle(delta: float) -> void:
	var direction: float = 0.0
	if Input.is_key_pressed(KEY_W):
		direction += 1.0
	if Input.is_key_pressed(KEY_S):
		direction -= 1.0
	collective = clampf(collective + direction * _TEMP_THROTTLE_RATE * delta, 0.0, 1.0)
