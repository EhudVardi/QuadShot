class_name FlightController
extends RigidBody3D

## Orchestrates the flight loop each physics tick (handoff §6.3):
## sticks → target rates → rate PID → quad-X mixer → motors.
## Pilot-convention axes everywhere outside the Godot-space conversion in
## _measured_rates(): x = roll (+right), y = pitch (+nose up), z = yaw (+right).

@export var config: FlightConfig

@onready var _motors: MotorModel = $MotorModel
@onready var _input: InputHandler = $InputHandler
@onready var _fpv_camera: Camera3D = $FpvCamera

var armed: bool = false
## Effective throttle [0, 1] this tick (gamepad, or the test override below).
var collective: float = 0.0
## Test hook (scripts/tests/hover_check.gd): >= 0 replaces gamepad throttle.
var throttle_override: float = -1.0

var _rate_controller: RateController = RateController.new()
var _spawn_transform: Transform3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	mass = config.mass
	_spawn_transform = global_transform


func _process(_delta: float) -> void:
	# Re-read every frame so the Phase 3 overlay can tune these live.
	_fpv_camera.fov = config.fpv_fov_deg
	_fpv_camera.rotation_degrees.x = config.fpv_uptilt_deg


func _physics_process(delta: float) -> void:
	_input.poll(config)
	collective = throttle_override if throttle_override >= 0.0 else _input.throttle
	_handle_buttons()
	if armed:
		_run_rate_control(delta)
	else:
		_rate_controller.reset()
		_motors.force_stop()
	_motors.step(delta, config)
	_motors.apply_thrust(self, config, _gravity)
	_apply_aerodynamics()


func arm() -> bool:
	if armed:
		return true
	if collective >= config.arm_throttle_threshold:
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
	print("[drone] reset to spawn")


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
	if Input.is_action_just_pressed(&"reset_drone"):
		reset_to_spawn()


func _run_rate_control(delta: float) -> void:
	var command: Vector3 = _rate_controller.update(
			_input.rate_command, _measured_rates(), delta, config)
	# Quad-X mixing: positive pilot roll lowers the right side, positive pitch
	# raises the nose, positive yaw spins the nose right (signs verified
	# against X_SIGNS/Z_SIGNS/SPIN_DIRECTIONS in motor_model.gd).
	for i: int in MotorModel.MOTOR_COUNT:
		var motor: float = collective
		motor -= command.x * MotorModel.X_SIGNS[i]
		motor -= command.y * MotorModel.Z_SIGNS[i]
		motor -= command.z * float(MotorModel.SPIN_DIRECTIONS[i])
		# Air-mode floor: attitude authority is retained at zero throttle.
		_motors.set_command(i, clampf(motor, config.motor_idle, 1.0))


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
