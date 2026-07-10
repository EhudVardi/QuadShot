class_name MotorModel
extends Node

## Four motors in quad-X layout. Motor order everywhere: FL, FR, BL, BR.
## Front is body -Z, left is body -X, thrust is along body +Y.
## FL/BR spin one way, FR/BL the other — the sign only matters for yaw
## reaction torque, which arrives with the rate controller in Phase 2.

const MOTOR_COUNT: int = 4
const SPIN_DIRECTIONS: Array[int] = [1, -1, -1, 1]
const _X_SIGNS: Array[float] = [-1.0, 1.0, -1.0, 1.0]
const _Z_SIGNS: Array[float] = [-1.0, -1.0, 1.0, 1.0]

var _commands: PackedFloat32Array
var _outputs: PackedFloat32Array


func _init() -> void:
	_commands.resize(MOTOR_COUNT)
	_outputs.resize(MOTOR_COUNT)


func set_command(index: int, value: float) -> void:
	_commands[index] = clampf(value, 0.0, 1.0)


func set_all_commands(value: float) -> void:
	for i: int in MOTOR_COUNT:
		set_command(i, value)


## Disarm behavior: motors die instantly, bypassing the lag (handoff §6.6).
func force_stop() -> void:
	for i: int in MOTOR_COUNT:
		_commands[i] = 0.0
		_outputs[i] = 0.0


## Jump the lag state straight to a value — for tests/setup, not flight.
func prime(value: float) -> void:
	for i: int in MOTOR_COUNT:
		_commands[i] = value
		_outputs[i] = value


func output(index: int) -> float:
	return _outputs[index]


## First-order low-pass toward the commanded value. Exact discretization
## (1 - e^(-dt/tau)) so behavior is identical at any physics tick rate.
func step(delta: float, config: FlightConfig) -> void:
	var alpha: float = 1.0
	if config.motor_lag_tau > 0.0:
		alpha = 1.0 - exp(-delta / config.motor_lag_tau)
	for i: int in MOTOR_COUNT:
		_outputs[i] += (_commands[i] - _outputs[i]) * alpha


func max_total_thrust(config: FlightConfig, gravity: float) -> float:
	return config.thrust_to_weight_ratio * config.mass * gravity


func motor_position(index: int, config: FlightConfig) -> Vector3:
	return Vector3(_X_SIGNS[index] * config.arm_length, 0.0, _Z_SIGNS[index] * config.arm_length)


## Per-motor thrust along body +Y at the motor's mounting point, so
## differential outputs naturally produce roll/pitch torque (handoff §6.2).
func apply_thrust(body: RigidBody3D, config: FlightConfig, gravity: float) -> void:
	var per_motor_max: float = max_total_thrust(config, gravity) / float(MOTOR_COUNT)
	for i: int in MOTOR_COUNT:
		var force: Vector3 = body.global_basis.y * (_outputs[i] * per_motor_max)
		var position_offset: Vector3 = body.global_basis * motor_position(i, config)
		body.apply_force(force, position_offset)
