class_name FlightConfig
extends Resource

## Every flight tunable lives here (handoff §5): scripts read it, the debug
## overlay (Phase 3) writes it live. Fields are added per phase — no dead
## tunables. Defaults per handoff §6.
##
## Vector3 fields use pilot axes: x = roll (+right), y = pitch (+nose up),
## z = yaw (+right).

enum ThrottleCurve { RAW, HOVER_CENTERED }

@export_group("Airframe")
@export var mass: float = 0.65
@export var arm_length: float = 0.12

@export_group("Motors")
@export var thrust_to_weight_ratio: float = 4.5
## First-order lag time constant (s). Instant thrust feels arcade-y.
@export var motor_lag_tau: float = 0.05
## Air-mode floor: motors never drop below this while armed, so attitude
## authority is retained at zero throttle (handoff §6.3).
@export var motor_idle: float = 0.05
## Yaw reaction torque per unit of summed signed motor output (N·m).
## Simplified prop-torque model (handoff §6.2) — feel over physical purity.
@export var yaw_authority: float = 1.5

@export_group("Rates")
## Max stick-commanded body rates, degrees/s.
@export var max_rate_deg: Vector3 = Vector3(800.0, 800.0, 550.0)
## Expo per axis: out = (1-e)·x + e·x³. Softens center stick.
@export var expo: Vector3 = Vector3(0.3, 0.3, 0.3)

@export_group("Rate PID")
@export var rate_p: Vector3 = Vector3(0.004, 0.004, 0.004)
@export var rate_i: Vector3 = Vector3(0.002, 0.002, 0.002)
@export var rate_d: Vector3 = Vector3(0.00003, 0.00003, 0.00003)
## Clamp on the I term's output contribution (anti-windup), motor units.
@export var integral_limit: float = 0.2

@export_group("Input")
## Applied to every stick axis before expo (handoff §7).
@export var stick_deadzone: float = 0.08
## hover_centered: mid-stick = computed hover throttle — livable on a
## springy, self-centering gamepad stick (handoff §7). raw: linear [0,1].
@export var throttle_curve: ThrottleCurve = ThrottleCurve.HOVER_CENTERED

@export_group("Angle Mode")
## Max target attitude at full stick deflection (handoff §6.4).
@export var max_angle_deg: float = 55.0
## Attitude P: converts attitude error (rad) to a target rate (rad/s) that
## feeds the same rate controller as acro.
@export var angle_p: float = 6.0

@export_group("Aerodynamics")
## Quadratic drag: F = -c * |v| * v
@export var drag_coefficient: float = 0.03
## Explicit angular damping torque: T = -k * angular_velocity.
## Godot's built-in damping is disabled on the drone body so this stays tunable.
@export var angular_damping: float = 0.02

@export_group("Camera")
@export var fpv_uptilt_deg: float = 25.0
@export var fpv_fov_deg: float = 115.0
@export var chase_distance: float = 3.5
@export var chase_height: float = 1.2
## Exponential smoothing rate (1/s) for the chase camera follow.
@export var chase_smoothing: float = 8.0

@export_group("Arming")
## Arming is refused above this throttle fraction (safety, handoff §6.6).
@export var arm_throttle_threshold: float = 0.05
