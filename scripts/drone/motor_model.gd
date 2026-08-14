class_name MotorModel
extends Node

## N motors on a ring. Quad-X order is FL, FR, BL, BR and is unchanged.
## Front is body -Z, left is body -X, thrust is along body +Y.
## Alternating rotors spin opposite ways — the sign only matters for yaw
## reaction torque.
##
## THE PHYSICS NEVER ASSUMED FOUR (GAMEPLAY-DESIGN Iteration 17 / E.q1).
## `apply_thrust` applies each rotor's force AT its own mounting point, so roll
## and pitch torque fall out of GEOMETRY rather than out of a formula counting
## corners, and yaw is the summed signed reaction. What assumed four was the
## LAYOUT: a rotor count and three hand-written sign tables. Those are now a
## layout, and *"a hexacopter is not a different physics model; it is the same
## model with six entries"* is literally true.
##
## THE QUAD IS AUTHORED, NOT COMPUTED, and that is deliberate. A ring formula
## reproduces its four mounts, but it does not reproduce their ORDER — FL, FR,
## BL, BR is 315, 45, 225, 135 degrees, which no sequential walk produces — and
## the order is load-bearing: the mixer, `damage_motor(index)`, the HUD pips and
## every saved expectation are indexed by it. So the datum layout is written out
## and only the new ones are generated.

enum Layout {
	QUAD_X,  ## four rotors, X configuration: the datum, byte-for-byte unchanged
	HEX_X,   ## six on a ring at 30 degrees off the nose, alternating 3+3
}

## Mount offsets are in multiples of `FlightConfig.arm_length`, exactly as the
## old sign tables were, so `motor_position` is unchanged for the quad.
##
## A generated ring uses radius `sqrt(2)` in those units, which puts its rotors
## at the same distance from the hub as a quad-X's corners. That keeps
## `arm_length` meaning one physical thing across layouts: a hexa and a quad
## sharing an `arm_length` are the same span of aircraft.
const RING_RADIUS: float = 1.4142135623730951

var rotor_count: int = 4
## Public: the mixer in flight_controller.gd keys off these.
var x_offsets: PackedFloat32Array
var z_offsets: PackedFloat32Array
var spins: PackedFloat32Array

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
	configure(Layout.QUAD_X)


## Name a layout from a config's `rotor_layout` field. Unknown ids fall back to
## the quad rather than erroring: a frame with a typo should still fly.
static func layout_from_id(id: StringName) -> Layout:
	return Layout.HEX_X if id == &"hex_x" else Layout.QUAD_X


## Adopt a layout: rotor count, mounts and spin directions, and resize the
## per-rotor state to match. Called from `_init` and again whenever the airframe
## changes under us (`FlightController.swap_frame`).
func configure(layout: Layout) -> void:
	match layout:
		Layout.HEX_X:
			_ring(6, 30.0)
		_:
			# THE DATUM, WRITTEN OUT. FL, FR, BL, BR.
			x_offsets = PackedFloat32Array([-1.0, 1.0, -1.0, 1.0])
			z_offsets = PackedFloat32Array([-1.0, -1.0, 1.0, 1.0])
			spins = PackedFloat32Array([1.0, -1.0, -1.0, 1.0])
			rotor_count = 4
	_commands.resize(rotor_count)
	_outputs.resize(rotor_count)
	_health.resize(rotor_count)
	force_stop()
	repair()


## `count` rotors evenly around the hub, the first at `first_deg` clockwise from
## the nose, spins alternating around the ring.
##
## Alternating is what makes reaction torque cancel in the hover, and it is why
## this generator is only good for EVEN counts. Three rotors cannot cancel by
## counter-rotation at all — every arrangement leaves a net yaw — which is why a
## real tricopter tilts its tail rotor on a servo, and why the tri is a thrust
## VECTORING job rather than a table job (E steering round 2). Do not reach for
## this function to build one.
func _ring(count: int, first_deg: float) -> void:
	rotor_count = count
	x_offsets = PackedFloat32Array()
	z_offsets = PackedFloat32Array()
	spins = PackedFloat32Array()
	for i: int in count:
		var bearing: float = deg_to_rad(first_deg + 360.0 * float(i) / float(count))
		x_offsets.append(RING_RADIUS * sin(bearing))
		# Body -Z is the nose, so the nose-ward rotors carry a negative z.
		z_offsets.append(-RING_RADIUS * cos(bearing))
		spins.append(1.0 if i % 2 == 0 else -1.0)


## Effective thrust scale of a motor: healthy = 1, failed = the residual floor.
func _effective(index: int) -> float:
	return min_thrust_floor + (1.0 - min_thrust_floor) * _health[index]


func health(index: int) -> float:
	return _health[index]


func damage_motor(index: int, amount: float) -> void:
	_health[index] = clampf(_health[index] - amount, 0.0, 1.0)


func repair() -> void:
	for i: int in rotor_count:
		_health[i] = 1.0


## Lowest motor capability — for HUD/repair logic ("worst engine").
func min_health() -> float:
	var lowest: float = 1.0
	for i: int in rotor_count:
		lowest = minf(lowest, _health[i])
	return lowest


## Range [-1, 1]: negative only occurs in 3D throttle mode (reverse thrust);
## the mixer's clamp enforces the mode's actual floor.
func set_command(index: int, value: float) -> void:
	_commands[index] = clampf(value, -1.0, 1.0)


func set_all_commands(value: float) -> void:
	for i: int in rotor_count:
		set_command(i, value)


## Disarm behavior: motors die instantly, bypassing the lag (handoff §6.6).
func force_stop() -> void:
	for i: int in rotor_count:
		_commands[i] = 0.0
		_outputs[i] = 0.0


## Jump the lag state straight to a value — for tests/setup, not flight.
func prime(value: float) -> void:
	for i: int in rotor_count:
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
	for i: int in rotor_count:
		_outputs[i] += (_commands[i] - _outputs[i]) * alpha


func max_total_thrust(config: FlightConfig, gravity: float) -> float:
	return config.thrust_to_weight_ratio * config.mass * gravity


func motor_position(index: int, config: FlightConfig) -> Vector3:
	return Vector3(x_offsets[index] * config.arm_length, 0.0,
			z_offsets[index] * config.arm_length)


## Per-motor thrust along body +Y at the motor's mounting point, so
## differential outputs naturally produce roll/pitch torque (handoff §6.2).
## Yaw comes from simplified prop reaction torque: about body Y, proportional
## to the summed signed motor outputs — zero when the pairs are balanced.
func apply_thrust(body: RigidBody3D, config: FlightConfig, gravity: float) -> void:
	# Divided by the ACTUAL rotor count, so total available thrust is the frame's
	# TWR whatever it is spread across: six rotors each make a sixth.
	var per_motor_max: float = max_total_thrust(config, gravity) / float(rotor_count)
	var yaw_sum: float = 0.0
	for i: int in rotor_count:
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
		yaw_sum += spins[i] * _outputs[i] * effective
	body.apply_torque(body.global_basis.y * (config.yaw_authority * yaw_sum))
