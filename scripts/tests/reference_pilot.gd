class_name ReferencePilot
extends RefCounted

## The balance harness's stand-in pilot (GAMEPLAY-DESIGN Iteration 6, H5).
##
## A scripted, deterministic combat autopilot that flies the *real* drone
## through the *real* rate loop and physics — it exists so the matchup harness
## (H2 unit layer) can measure combat outcomes headless, with no human hands.
## It produces RELATIVE truth (weapon A beats B on enemy Y); the human
## calibrates its competence datum so the numbers track real skill (H.q4).
## Per the H5 doctrine: the harness measures balance, the hands measure feel.
##
## It reuses the proven pause-mode autopilot math (flight_controller.gd
## _autopilot_rates): that controller nulls the drone's velocity to hold
## station; this one nulls the velocity ERROR toward a moving hold point, so
## the same sign-correct attitude loop chases a target instead of braking to
## zero. Rates are fed through the drone's rate_override hook, so every command
## still passes through the real PID -> mixer -> motors -> rigidbody.
##
## The competence datum below (preferred_range, aim, gains) is the ruler the
## human calibrates; the fields are deliberately plain knobs, not magic.

var drone: FlightController
var weapon: Weapon
var missile: MissileSystem
var use_missile: bool = false
var target: Node3D

# --- Competence datum (H5). Calibrated by the human against real skill. ---
## Altitude the pilot seeks, meters (harness spawns the duel around this).
var cruise_altitude: float = 14.0
## Yaw P gain (bearing the gun line onto the target).
var yaw_p: float = 4.0
## Pitch P gain (elevating the gun line onto the target).
var aim_p: float = 5.0
## Roll damping to kill lateral drift and hold a stable firing line
## (rad/s of roll rate per m/s of sideways velocity).
var roll_damp: float = 0.18
## Fire when the target sits within this cone of the GUN line, degrees.
var fire_cone_deg: float = 6.0
## Don't waste blaster rounds past this range, meters.
var fire_range: float = 55.0


## Drive one physics tick. Called by the harness each physics_frame; the
## overrides it sets are consumed by the drone on the next physics step (a
## one-frame lag, negligible at 240 Hz).
##
## The pilot flies as a GUN PLATFORM: it aims the weapon's own axis (the FPV
## camera line — which carries the 44 deg uptilt, so the nose is NOT the gun
## line) at the target with pitch+yaw, damps sideways drift with roll, and
## holds altitude with throttle. Pitching the tilted camera down onto a
## level target also drives the drone forward, closing range for free.
func update(_delta: float) -> void:
	if drone == null or not drone.armed:
		return
	drone.rate_override_enabled = true
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion() or weapon == null:
		# No target: level out and hold altitude, hold fire.
		drone.rate_override = Vector3.ZERO
		drone.throttle_override = _altitude_throttle(cruise_altitude)
		_hold_fire()
		return

	# Lead a moving target by the bolt's flight time (homing missiles don't
	# need it — aim at the true position so the lock cone stays centered).
	var aim_point: Vector3 = target.global_position
	if not use_missile:
		var raw: Vector3 = target.global_position - drone.global_position
		var target_vel: Variant = target.get(&"velocity")
		var flight_time: float = raw.length() \
				/ maxf(weapon.combat_config.muzzle_speed, 1.0)
		if target_vel is Vector3:
			aim_point += (target_vel as Vector3) * flight_time
	var to_target: Vector3 = aim_point - drone.global_position
	var to_dir: Vector3 = to_target.normalized()
	var to_flat := Vector3(to_target.x, 0.0, to_target.z)
	# The GUN LINE: the weapon sits under the FPV camera and fires along its
	# -Z, so the uptilt is baked into this basis. Aiming the body would miss
	# high by the uptilt angle.
	var gun: Vector3 = -weapon.global_basis.z
	var gun_flat := Vector3(gun.x, 0.0, gun.z).normalized()
	var max_roll_rate: float = deg_to_rad(drone.config.max_rate_deg.x)
	var max_pitch_rate: float = deg_to_rad(drone.config.max_rate_deg.y)
	var max_yaw_rate: float = deg_to_rad(drone.config.max_rate_deg.z)

	# Yaw: swing the gun line's heading onto the target's bearing.
	var yaw_error: float = 0.0
	if to_flat.length() > 0.1:
		yaw_error = gun_flat.signed_angle_to(to_flat.normalized(), Vector3.UP)
	var yaw_rate: float = clampf(-yaw_p * yaw_error, -max_yaw_rate, max_yaw_rate)

	# Pitch: raise/lower the gun line's elevation onto the target's. Target
	# above the gun line -> nose up; below -> nose down (which also closes).
	var pitch_error: float = asin(clampf(to_dir.y, -1.0, 1.0)) \
			- asin(clampf(gun.y, -1.0, 1.0))
	var pitch_rate: float = clampf(aim_p * pitch_error, -max_pitch_rate, max_pitch_rate)

	# Roll: null sideways velocity so the firing line stays steady (positive
	# roll accelerates right, so oppose rightward drift with negative roll).
	var right_flat: Vector3 = Vector3(drone.global_basis.x.x, 0.0,
			drone.global_basis.x.z).normalized()
	var lateral_speed: float = drone.linear_velocity.dot(right_flat)
	var roll_rate: float = clampf(-roll_damp * lateral_speed,
			-max_roll_rate, max_roll_rate)

	drone.rate_override = Vector3(roll_rate, pitch_rate, yaw_rate)
	drone.throttle_override = _altitude_throttle(cruise_altitude)

	# Fire when the GUN line is on the target and it is in reach.
	var on_target: bool = gun.angle_to(to_target) < deg_to_rad(fire_cone_deg)
	if use_missile:
		# The director launches the instant a lock completes; keeping the
		# target in the (camera-aligned) lock cone is the aim loop's job.
		if missile != null:
			missile.fire_override = true
		_hold_blaster()
	else:
		weapon.fire_override = on_target and to_target.length() < fire_range


func _altitude_throttle(target_alt: float) -> float:
	var climb: float = drone.config.autopilot_climb_gain
	var error: float = target_alt - drone.global_position.y
	# PD around hover: seek the altitude, damp vertical speed.
	return clampf(drone.hover_throttle()
			+ climb * (clampf(error, -4.0, 4.0) - drone.linear_velocity.y),
			0.0, 1.0)


func _hold_fire() -> void:
	_hold_blaster()
	if missile != null:
		missile.fire_override = false


func _hold_blaster() -> void:
	if weapon != null:
		weapon.fire_override = false
