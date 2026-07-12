class_name FlightConfig
extends TunableConfig

## Every flight tunable lives here (handoff §5): scripts read it, the debug
## overlay (Phase 3) writes it live. Fields are added per phase — no dead
## tunables. Defaults per handoff §6.
##
## Vector3 fields use pilot axes: x = roll (+right), y = pitch (+nose up),
## z = yaw (+right).

enum ThrottleCurve { RAW, HOVER_CENTERED, THREE_D }

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

@export_group("Filtering")
## Betaflight-style epi-filtering: shape the signals, never the physics.
## All cutoffs in Hz; 0 disables a filter. Nyquist at the 240 Hz tick is
## 120 Hz — keep cutoffs below that.
## First-order low-pass on the measured body rates before the PID.
@export var gyro_lpf_hz: float = 90.0
## Additional low-pass on the D-term (the classic anti-wobble knob).
@export var dterm_lpf_hz: float = 70.0
## Smoothing on stick commands; 0 = raw sticks.
@export var rc_smoothing_hz: float = 0.0

@export_group("Rate PID")
@export var rate_p: Vector3 = Vector3(0.004, 0.004, 0.004)
@export var rate_i: Vector3 = Vector3(0.002, 0.002, 0.002)
@export var rate_d: Vector3 = Vector3(0.00003, 0.00003, 0.00003)
## Clamp on the I term's output contribution (anti-windup), motor units.
@export var integral_limit: float = 0.2
## Fraction of the I term discarded on hard contact (Betaflight-style crash
## recovery). Collisions wind the integrator to its clamp within ticks and
## it bleeds off over seconds as a pull-away; 1 fully resets it on impact,
## 0 keeps the old behaviour (for A/B feel comparison).
@export var crash_iterm_decay: float = 1.0

@export_group("Input")
## Applied to every stick axis before expo (handoff §7).
@export var stick_deadzone: float = 0.08
## raw: stick maps linearly to [0,1] (rest = 50%). hover_centered: mid-stick
## = computed hover throttle. three_d: Betaflight-style 3D — center stick =
## zero thrust, below center = reverse thrust; the natural fit for a
## self-centering gamepad stick, and it allows inverted flight.
@export var throttle_curve: ThrottleCurve = ThrottleCurve.THREE_D
## Thrust multiplier when a motor pushes in reverse (3D mode): props are
## less efficient inverted. Feel over purity — tune it.
@export var reverse_thrust_scale: float = 0.8

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


# Persistence machinery lives in TunableConfig; these paths steer it.

const SAVE_PATH: String = "user://flight_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_flight_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH
