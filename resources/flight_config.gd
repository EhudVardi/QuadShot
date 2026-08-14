class_name FlightConfig
extends TunableConfig

## Every flight tunable lives here (handoff §5): scripts read it, the debug
## overlay (Phase 3) writes it live. Fields are added per phase — no dead
## tunables. Defaults per handoff §6.
##
## Vector3 fields use pilot axes: x = roll (+right), y = pitch (+nose up),
## z = yaw (+right).

enum ThrottleCurve { RAW, HOVER_CENTERED, THREE_D }
enum InputProfile { GAMEPAD, RADIO_AETR, RADIO_TAER }

@export_group("Airframe")
## Which frame's flight model this is (P3.9: frames ARE flight configs). Drives
## this resource's own save/defaults paths, so two frames tuned in the same
## session cannot overwrite each other's overrides. Matches the owning
## FrameConfig's `frame_id`.
@export var frame_id: StringName = &"kestrel"
@export var mass: float = 0.65
@export var arm_length: float = 0.12
## Body size across the frame (m), motor mounts excluded. The airframe's VISUAL
## and COLLISION size are built from this at runtime by
## `FlightController._apply_frame_geometry`, so one roster can hold a 0.28 m quad
## and a 3 m manned aircraft without a scene each.
##
## It lives here beside `mass` and `arm_length` rather than on FrameConfig for
## that class's own stated reason: a physics dimension with two homes has no rule
## for which one wins.
@export var body_m: float = 0.28

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
## Feedforward on the setpoint derivative (Betaflight FF): pushes rotation
## the instant the stick moves instead of waiting for error to build, so P
## can stay modest without mushy stick response. 0 = off (baked feel).
@export var rate_ff: Vector3 = Vector3.ZERO
## Low-pass on the FF term — gamepad ADC steps make the raw setpoint
## derivative spiky. 0 = unfiltered.
@export var ff_lpf_hz: float = 20.0
## Clamp on the I term's output contribution (anti-windup), motor units.
@export var integral_limit: float = 0.2
## Per-tick fraction of the I term discarded while in a crash condition:
## frame contact, or a per-axis rate error beyond iterm_error_gate_deg
## (Betaflight-style crash recovery). Windup during a crash tumble later
## forces an uncommanded drift while it unwinds over seconds. 1 hard-zeroes
## it, 0 keeps the old behaviour (A/B); at 240 Hz even 0.1 drains in ~30 ms.
@export var crash_iterm_decay: float = 1.0
## Rate error (deg/s, per axis) beyond which integration is a crash
## condition, not flying: honest tracking error stays under ~120 deg/s
## while crash tumbles run 500-2500 deg/s (blackbox-measured). 0 disables.
@export var iterm_error_gate_deg: float = 300.0
## I-term relax (Betaflight): during fast setpoint moves the airframe lags
## the sticks by design, and integrating that transient error causes
## bounce-back wobble at the end of flicks and flips. The setpoint is
## low-passed at this cutoff and I accumulation fades out as the live
## setpoint diverges from it. 0 disables.
@export var iterm_relax_hz: float = 15.0
## Setpoint divergence (deg/s) at which I accumulation is fully suppressed.
@export var iterm_relax_threshold_deg: float = 40.0

@export_group("Input")
## Input source. GAMEPAD reads the InputMap-bound gamepad axes (Mode 2
## sticks). RADIO_* reads a USB radio in EdgeTX/OpenTX joystick mode (e.g.
## RadioMaster TX16S) directly by channel order on axes 0-3: AETR =
## roll,pitch,throttle,yaw; TAER = throttle,roll,pitch,yaw. Assumed axis
## signs: stick up/right = positive — if an axis runs backwards, flip that
## channel's direction on the radio (Outputs page); the radio is the
## remapping UI. With a radio, run stick_deadzone near 0 and expo 0 — rates,
## expo and trims live on the radio. Falls back to GAMEPAD when no radio is
## detected.
@export var input_profile: InputProfile = InputProfile.GAMEPAD
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
## Where the lens sits on the airframe, in body-local metres.
##
## AUTHORED PER FRAME, NEVER DERIVED, and that is the whole point of the field.
## Every other dimension here scales with the body; this one does not, because
## its correctness depends on CLEARING GEOMETRY rather than on proportion. At
## 0.28 m the lens sits *inside* the hull and the near plane harmlessly clips the
## hull away; scale that same offset to 3 m by the same factor and the camera is
## buried in a solid airframe with the nose marker filling the screen. That bug
## was shipped once (PLAN-FULL-SCALE risk 3) and this field is what stops it
## coming back: **scaling a camera OFFSET is not the same as scaling a camera
## POSITION.**
@export var fpv_offset: Vector3 = Vector3(0.0, 0.03, -0.08)
## Camera tilt above the airframe's forward axis.
##
## THE SAME ON EVERY FRAME, AND THE REASON IS PHYSICS RATHER THAN TASTE — this
## corrects a wrong guess made on 2026-08-10, when the ladder's frames were given
## 44 / 22 / 12 degrees on the theory that a big aircraft flies flatter than a
## racing quad. It does not. **A multirotor flies forward by pointing its thrust
## backward**, so the faster it goes the further the nose drops, and the camera
## has to tilt UP by that much just to keep the horizon in frame. More thrust
## means MORE uptilt, not less. The user's correction, from flying all three:
## *"drones are meant to be flown forward, and the faster they go the more angle
## they need to compensate for the crazy thrust they push... so basically they
## all should have the same start angle."*
##
## 48 degrees is their number for all three, with the Roc sometimes wanting more.
@export var fpv_uptilt_deg: float = 48.0
@export var fpv_fov_deg: float = 115.0
@export var chase_distance: float = 3.5
@export var chase_height: float = 1.2
## Exponential smoothing rate (1/s) for the chase camera follow.
@export var chase_smoothing: float = 8.0

@export_group("Pause & Autopilot")
## BeamNG-style pause: time slows to this scale rather than stopping (the
## physics needs ticks to flow). Driven by the pause_toggle / pause_switch
## bindings; while paused the "paused" binding context is active.
@export var pause_time_scale: float = 0.03
## Pause-mode position hold: tilt (deg) commanded per m/s of horizontal
## drift — the autopilot brakes and levels the drone while time crawls.
@export var autopilot_tilt_deg_per_ms: float = 4.0
## Collective added per m/s of vertical drift (centered on hover throttle).
@export var autopilot_climb_gain: float = 0.08

@export_group("Arming")
## Arming is refused above this throttle fraction (safety, handoff §6.6).
@export var arm_throttle_threshold: float = 0.05


# Persistence machinery lives in TunableConfig; these paths steer it. Derived
# from frame_id rather than class constants, because there is now one of these
# per frame (EnemyConfig's precedent, same reason).

## The single-frame save path from before frames existed. Read once as a
## fallback, never written — see load_from_user().
const LEGACY_SAVE_PATH: String = "user://flight_config.tres"


## Roughly how fast this airframe can go: the speed at which aerodynamic drag
## eats the whole thrust budget. Drag is `drag_coefficient * |v| * v`, so setting
## it equal to `mass * g * TWR` and solving gives this.
##
## IT EXISTS BECAUSE "FAST" IS A PER-FRAME QUANTITY NOW and constants that assumed
## otherwise are quietly wrong across a size ladder. The wind rush saturated at a
## hard-coded 35 m/s, which is about right for the Kestrel (31) and means the Roc
## (131) flies four fifths of its envelope with the speed cue already pinned at
## maximum — the sound stops telling you anything exactly where it matters most.
##
## Approximate on purpose: it ignores the tilt needed to point thrust forward, so
## it reads high. It is a SCALE, not a speed limit, and nothing enforces it.
func terminal_speed() -> float:
	if drag_coefficient <= 0.0001:
		return 100.0
	return sqrt(mass * 9.8 * thrust_to_weight_ratio / drag_coefficient)


func identity_fields() -> PackedStringArray:
	return PackedStringArray(["frame_id"])


func save_path() -> String:
	return "user://flight_%s.tres" % frame_id


func defaults_path() -> String:
	return "res://resources/default_flight_%s.tres" % frame_id


## Migration shim, retiring itself after one Save. A pilot's user:// overrides
## are months of tuning at the sticks, and the rename to per-frame paths would
## otherwise discard them in silence — the one failure mode of this change that
## costs a human real work rather than a re-run. Only the Kestrel looks: it IS
## the drone that file was tuned for (P3.3).
func load_from_user(force: bool = false) -> bool:
	# The session guard must fence the legacy branch too, or a scene change
	# would re-migrate the old file over live tuning (v1.41).
	if not force and session_loaded():
		return false
	if super.load_from_user(force):
		return true
	if frame_id != &"kestrel" or not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return false
	var legacy: TunableConfig = ResourceLoader.load(
			LEGACY_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as TunableConfig
	if legacy == null:
		return false
	copy_from(legacy)
	loaded_from = "%s (pre-frame override, migrating)" % LEGACY_SAVE_PATH
	_mark_session_loaded()
	return true
