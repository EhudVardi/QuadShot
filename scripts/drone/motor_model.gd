class_name MotorModel
extends Node

## Four motors in quad-X layout. Motor order everywhere: FL, FR, BL, BR.
## Front is body -Z, left is body -X, thrust is along body +Y.
## FL/BR spin one way, FR/BL the other — the sign only matters for yaw
## reaction torque, which arrives with the rate controller in Phase 2.

const MOTOR_COUNT: int = 4
const SPIN_DIRECTIONS: Array[int] = [1, -1, -1, 1]
## Public: the quad-X mixer in flight_controller.gd keys off these.
const X_SIGNS: Array[float] = [-1.0, 1.0, -1.0, 1.0]
const Z_SIGNS: Array[float] = [-1.0, -1.0, 1.0, 1.0]

var _commands: PackedFloat32Array
var _outputs: PackedFloat32Array
## Per-motor capability [0, 1] (GAMEPLAY-DESIGN Iteration 7 / D2): 1 = healthy,
## 0 = failed. Battle damage lowers these, producing asymmetric thrust the rate
## loop must fight — the wounded quad, felt through the sticks. Undamaged (all
## 1.0) it is exactly the old model, so the harness and arcade tier are
## untouched. A failed motor still makes `min_thrust_floor` of its share.
var _health: PackedFloat32Array
var min_thrust_floor: float = 0.0


func _init() -> void:
	_commands.resize(MOTOR_COUNT)
	_outputs.resize(MOTOR_COUNT)
	_health.resize(MOTOR_COUNT)
	repair()


## Effective thrust scale of a motor: healthy = 1, failed = the residual floor.
func _effective(index: int) -> float:
	return min_thrust_floor + (1.0 - min_thrust_floor) * _health[index]


func health(index: int) -> float:
	return _health[index]


func damage_motor(index: int, amount: float) -> void:
	_health[index] = clampf(_health[index] - amount, 0.0, 1.0)


func repair() -> void:
	for i: int in MOTOR_COUNT:
		_health[i] = 1.0


## Partial repair toward full (the repair pad nurses engines back over time).
func repair_by(amount: float) -> void:
	for i: int in MOTOR_COUNT:
		_health[i] = clampf(_health[i] + amount, 0.0, 1.0)


## Lowest motor capability — for HUD/repair logic ("worst engine").
func min_health() -> float:
	var lowest: float = 1.0
	for i: int in MOTOR_COUNT:
		lowest = minf(lowest, _health[i])
	return lowest


## Range [-1, 1]: negative only occurs in 3D throttle mode (reverse thrust);
## the mixer's clamp enforces the mode's actual floor.
func set_command(index: int, value: float) -> void:
	_commands[index] = clampf(value, -1.0, 1.0)


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
	return Vector3(X_SIGNS[index] * config.arm_length, 0.0, Z_SIGNS[index] * config.arm_length)


## Per-motor thrust along body +Y at the motor's mounting point, so
## differential outputs naturally produce roll/pitch torque (handoff §6.2).
## Yaw comes from simplified prop reaction torque: about body Y, proportional
## to the summed signed motor outputs — zero when the pairs are balanced.
func apply_thrust(body: RigidBody3D, config: FlightConfig, gravity: float) -> void:
	var per_motor_max: float = max_total_thrust(config, gravity) / float(MOTOR_COUNT)
	var yaw_sum: float = 0.0
	for i: int in MOTOR_COUNT:
		# Damage scales delivered thrust AND yaw torque: a weak corner lifts
		# less (roll/pitch bias) and reacts less (yaw imbalance) — honest.
		var effective: float = _effective(i)
		var thrust: float = _outputs[i] * per_motor_max * effective
		if _outputs[i] < 0.0:
			# 3D mode reverse: props are less efficient pushing down.
			thrust *= config.reverse_thrust_scale
		var force: Vector3 = body.global_basis.y * thrust
		var position_offset: Vector3 = body.global_basis * motor_position(i, config)
		body.apply_force(force, position_offset)
		yaw_sum += float(SPIN_DIRECTIONS[i]) * _outputs[i] * effective
	body.apply_torque(body.global_basis.y * (config.yaw_authority * yaw_sum))
