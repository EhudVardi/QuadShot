class_name FlightController
extends RigidBody3D

## Orchestrates the flight loop each physics tick (handoff §6.3):
## sticks → target rates → rate PID → quad-X mixer → motors.
## Pilot-convention axes everywhere outside the Godot-space conversion in
## _measured_rates(): x = roll (+right), y = pitch (+nose up), z = yaw (+right).

enum FlightMode { ACRO, ANGLE }

## Hard contact; main converts delta-v to crash damage (roadmap M2).
signal crashed(impact_speed: float)

@export var config: FlightConfig
## Damage model (GAMEPLAY-DESIGN Iteration 7). Null in the harness/tests, where
## motors stay undamaged and flight is the shipped model exactly.
@export var damage_config: DamageConfig

@onready var _motors: MotorModel = $MotorModel
@onready var _input: InputHandler = $InputHandler
@onready var _fpv_camera: Camera3D = $FpvCamera

var armed: bool = false
var flight_mode: FlightMode = FlightMode.ACRO
## Combat identity read by projectiles (same-team hits don't damage).
var team: StringName = &"player"
## World direction the last projectile hit came FROM (set by projectile.gd,
## consumed by main.gd for the HUD damage-direction indicator).
var last_hit_direction: Vector3 = Vector3.ZERO
## Effective throttle [0, 1] this tick (gamepad, or the test override below).
var collective: float = 0.0
## Test hook (scripts/tests/hover_check.gd): >= 0 replaces gamepad throttle.
var throttle_override: float = -1.0
## Test hook (scripts/tests/step_response.gd): replaces stick target rates.
var rate_override_enabled: bool = false
var rate_override: Vector3 = Vector3.ZERO
## Pause-mode position hold (set by main while slow-mo pause is active):
## overrides sticks with a level-and-brake controller so the drone parks
## itself while the pilot tunes/binds in peace.
var autopilot: bool = false

## For the overlay's target-vs-actual readout; zeroed while disarmed.
var telemetry_target_rates: Vector3 = Vector3.ZERO
var telemetry_measured_rates: Vector3 = Vector3.ZERO

var _rate_controller: RateController = RateController.new()
var _arm_switch_was: bool = false
var _spawn_transform: Transform3D
var _previous_velocity: Vector3 = Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	if config.load_from_user():
		print("[config] loaded %s" % FlightConfig.SAVE_PATH)
	mass = config.mass
	if damage_config != null:
		_motors.min_thrust_floor = damage_config.motor_min_thrust
	_spawn_transform = global_transform
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	# Re-read every frame so the Phase 3 overlay can tune these live.
	_fpv_camera.fov = config.fpv_fov_deg
	_fpv_camera.rotation_degrees.x = config.fpv_uptilt_deg


func _physics_process(delta: float) -> void:
	if damage_config != null:
		_motors.min_thrust_floor = damage_config.motor_min_thrust
	_input.poll(config, hover_throttle(), delta)
	collective = throttle_override if throttle_override >= 0.0 else _input.throttle
	if autopilot and armed:
		# Hold altitude around hover throttle; _autopilot_rates() holds level.
		collective = clampf(hover_throttle()
				+ config.autopilot_climb_gain * -linear_velocity.y, -1.0, 1.0)
	_handle_buttons()
	if armed:
		_run_rate_control(delta)
	else:
		_rate_controller.reset()
		_motors.force_stop()
		telemetry_target_rates = Vector3.ZERO
		telemetry_measured_rates = Vector3.ZERO
	_motors.step(delta, config)
	_motors.apply_thrust(self, config, _gravity)
	_apply_aerodynamics()
	_previous_velocity = linear_velocity


func arm() -> bool:
	if armed:
		return true
	# absf: in 3D mode zero thrust is center stick, and reverse counts as hot.
	if absf(collective) >= config.arm_throttle_threshold:
		print("[drone] arm refused: throttle %.0f%% is above the %.0f%% threshold - hold the throttle stick down"
				% [collective * 100.0, config.arm_throttle_threshold * 100.0])
		return false
	armed = true
	print("[drone] ARMED")
	return true


func disarm() -> void:
	armed = false
	_rate_controller.reset()
	_motors.force_stop()
	print("[drone] disarmed")


func reset_to_spawn() -> void:
	disarm()
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_motors.repair()
	print("[drone] reset to spawn")


## Battle damage to the airframe's flight (GAMEPLAY-DESIGN Iteration 7 / D2):
## a hit degrades the motor on the side it came FROM, so the wound is asymmetric
## and located, not an abstract number. Directionless damage (a crash) frays the
## whole frame. Gated by the severity dial; a no-op without a damage_config.
func apply_hit_to_motors(damage: float) -> void:
	if damage_config == null or damage_config.severity <= 0.0:
		return
	var amount: float = minf(damage * damage_config.motor_damage_scale,
			damage_config.motor_damage_max) * damage_config.severity
	if amount <= 0.0:
		return
	var from_body: Vector3 = global_basis.inverse() * last_hit_direction
	from_body.y = 0.0
	if from_body.length_squared() < 0.000001:
		for i: int in MotorModel.MOTOR_COUNT:
			_motors.damage_motor(i, amount)
		return
	from_body = from_body.normalized()
	var best: int = 0
	var best_dot: float = -2.0
	for i: int in MotorModel.MOTOR_COUNT:
		var pos: Vector3 = _motors.motor_position(i, config)
		pos.y = 0.0
		var d: float = pos.normalized().dot(from_body)
		if d > best_dot:
			best_dot = d
			best = i
	_motors.damage_motor(best, amount)


func motor_health(index: int) -> float:
	return _motors.health(index)


func repair_motors() -> void:
	_motors.repair()


## Throttle fraction at which total thrust equals weight. With the linear
## thrust model this is exactly 1/TWR; computed honestly so it stays correct
## if the thrust model gains a curve later.
func hover_throttle() -> float:
	return config.mass * _gravity / _motors.max_total_thrust(config, _gravity)


## Test/setup hook: skip motor spool-up (see scripts/tests/hover_check.gd).
func prime_motors(value: float) -> void:
	_motors.prime(value)


func _handle_buttons() -> void:
	if Input.is_action_just_pressed(&"arm_toggle"):
		if armed:
			disarm()
		else:
			arm()
	# FPV-style stateful arming (bindable in the overlay's BINDINGS section,
	# unbound by default): switch position IS the armed state — up arms, down
	# disarms — matching how a real radio's arm switch behaves.
	if InputMap.has_action(&"arm_switch") \
			and not InputMap.action_get_events(&"arm_switch").is_empty():
		var switch_on: bool = Input.is_action_pressed(&"arm_switch")
		if switch_on != _arm_switch_was:
			_arm_switch_was = switch_on
			if switch_on:
				arm()
			else:
				disarm()
	if Input.is_action_just_pressed(&"reset_drone"):
		reset_to_spawn()
	if Input.is_action_just_pressed(&"flight_mode_toggle"):
		if flight_mode == FlightMode.ACRO:
			flight_mode = FlightMode.ANGLE
		else:
			flight_mode = FlightMode.ACRO
		print("[drone] flight mode: %s" % FlightMode.keys()[flight_mode])


func motor_output(index: int) -> float:
	return _motors.output(index)


## Blackbox/overlay telemetry: the rate PID integrator state.
func telemetry_integrator() -> Vector3:
	return _rate_controller.integrator()


## HUD stick display: raw physical stick positions (x=+right, y=+up, [-1,1]).
func stick_positions() -> Array[Vector2]:
	return [_input.stick_left, _input.stick_right]


## Projectile hits land here; the Health component and its wiring (main.gd)
## decide the consequences — the flight controller stays combat-thin.
func take_hit(damage: float) -> void:
	($Health as Health).take(damage)


func _on_body_entered(_body: Node) -> void:
	# Delta-v across the collision approximates impact severity; gentle
	# landings fall under main's damage threshold.
	crashed.emit((_previous_velocity - linear_velocity).length())


func _run_rate_control(delta: float) -> void:
	telemetry_target_rates = _target_rates()
	telemetry_measured_rates = _measured_rates()
	var command: Vector3 = _rate_controller.update(
			telemetry_target_rates, telemetry_measured_rates, delta, config,
			get_contact_count() > 0)
	# Quad-X mixing: positive pilot roll lowers the right side, positive pitch
	# raises the nose, positive yaw spins the nose right (signs verified
	# against X_SIGNS/Z_SIGNS/SPIN_DIRECTIONS in motor_model.gd).
	# Air-mode floor keeps attitude authority at zero throttle. In 3D mode
	# there is no floor — thrust runs the full [-1, 1] range and PID
	# corrections around zero provide the authority.
	var motor_floor: float = config.motor_idle
	if config.throttle_curve == FlightConfig.ThrottleCurve.THREE_D:
		motor_floor = -1.0
	for i: int in MotorModel.MOTOR_COUNT:
		var motor: float = collective
		motor -= command.x * MotorModel.X_SIGNS[i]
		motor -= command.y * MotorModel.Z_SIGNS[i]
		motor -= command.z * float(MotorModel.SPIN_DIRECTIONS[i])
		_motors.set_command(i, clampf(motor, motor_floor, 1.0))


func _target_rates() -> Vector3:
	if rate_override_enabled:
		return rate_override
	if autopilot:
		return _autopilot_rates()
	if flight_mode == FlightMode.ACRO:
		return _input.rate_command
	# Angle mode (handoff §6.4): stick deflection → target attitude, and an
	# attitude P loop converts the error to a target rate for the SAME rate
	# controller. Yaw stays rate-based. The asin-based angles are only valid
	# within ±90°, fine for a ±55° self-level envelope.
	var max_angle: float = deg_to_rad(config.max_angle_deg)
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var current_pitch: float = asin(clampf(forward.y, -1.0, 1.0))
	var current_roll: float = asin(clampf(-right.y, -1.0, 1.0))
	var roll_rate: float = config.angle_p * (_input.stick_shaped.x * max_angle - current_roll)
	var pitch_rate: float = config.angle_p * (_input.stick_shaped.y * max_angle - current_pitch)
	# Never command faster than acro's rate limits.
	var max_roll: float = deg_to_rad(config.max_rate_deg.x)
	var max_pitch: float = deg_to_rad(config.max_rate_deg.y)
	return Vector3(
		clampf(roll_rate, -max_roll, max_roll),
		clampf(pitch_rate, -max_pitch, max_pitch),
		_input.rate_command.z)


## Pause-mode position hold: tilt against horizontal drift (braking), level
## out otherwise, yaw frozen; the collective override in _physics_process
## handles the vertical axis. Reuses the angle-mode attitude loop with
## computed target angles instead of stick input.
func _autopilot_rates() -> Vector3:
	var max_angle: float = deg_to_rad(config.max_angle_deg)
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var forward_flat: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var right_flat: Vector3 = Vector3(right.x, 0.0, right.z).normalized()
	var horizontal: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var tilt: float = deg_to_rad(config.autopilot_tilt_deg_per_ms)
	var target_pitch: float = clampf(horizontal.dot(forward_flat) * tilt,
			-max_angle * 0.6, max_angle * 0.6)
	var target_roll: float = clampf(-horizontal.dot(right_flat) * tilt,
			-max_angle * 0.6, max_angle * 0.6)
	var current_pitch: float = asin(clampf(forward.y, -1.0, 1.0))
	var current_roll: float = asin(clampf(-right.y, -1.0, 1.0))
	var max_roll: float = deg_to_rad(config.max_rate_deg.x)
	var max_pitch: float = deg_to_rad(config.max_rate_deg.y)
	return Vector3(
			clampf(config.angle_p * (target_roll - current_roll), -max_roll, max_roll),
			clampf(config.angle_p * (target_pitch - current_pitch), -max_pitch, max_pitch),
			0.0)


## Body angular velocity mapped to pilot axes. Godot body space: +X right,
## +Y up, +Z back (front is -Z); angular_velocity is world-space, and the
## basis transpose (= inverse, orthonormal) brings it into body space.
func _measured_rates() -> Vector3:
	var body_angular: Vector3 = global_basis.transposed() * angular_velocity
	return Vector3(-body_angular.z, body_angular.x, -body_angular.y)


func _apply_aerodynamics() -> void:
	# Explicit, config-driven — the body's built-in damping is disabled
	# (handoff §6.5) so everything the overlay can tune lives in our model.
	apply_central_force(-config.drag_coefficient * linear_velocity.length() * linear_velocity)
	apply_torque(-config.angular_damping * angular_velocity)
