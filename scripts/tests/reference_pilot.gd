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

## The pinned ruler (GAMEPLAY-DESIGN v1.23, BALANCE.md): one brain flies every
## measured combatant, so any change to this file's behavior — gains, guards,
## aim math, trigger policy — moves every cell of the measured table at once.
## Bump this on ANY behavioral edit, then re-measure deliberately; every
## report prints it, and numbers from different pilot versions never share a
## table. v1 = the pilot as of the v1.22 harness banding (director-fired gun,
## LOS feed-forward, ground guard, tilt-compensated hover).
const PILOT_VERSION: int = 1

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
## Only consulted when the pilot is shooting manually (use_director off).
var fire_cone_deg: float = 6.0
## Don't waste blaster rounds past this range, meters.
var fire_range: float = 55.0
## Let the FCS gun director pull the trigger (CombatConfig.fire_assist_miss_m)
## instead of deciding the shot here.
##
## This is how the game is actually played (user, 2026-07-18): the director
## sweeps the true ballistic arc — muzzle speed, inherited velocity, gravity
## drop — against the target's predicted motion and fires the instant they
## intersect. The pilot's job is POSITIONING; the trigger is the gear's job.
## Hand-rolling the trigger here meant re-deriving that solution badly and
## firing 679 rounds at a raider for zero hits, while the correct solver sat
## unused three metres away in weapon.gd.
var use_director: bool = true
## Recover if the ground is this close, meters. A firing solution is worth
## nothing to a pilot who is about to be part of the scenery — and a rig that
## flies itself into the floor measures the floor, not the balance.
var floor_guard_m: float = 7.0
## Seconds of descent looked ahead when deciding that. Reacting to altitude
## alone is too late at 15 m/s down.
var floor_lookahead_s: float = 1.2
## P gain from attitude error to commanded rate, used while recovering.
var attitude_p: float = 4.0


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

	# Line-of-sight rate: how fast the bearing to the target is swinging, given
	# both bodies are moving. A pure P aim loop LAGS a mover by a roughly
	# constant error proportional to this rate — traced settling at a permanent
	# ~2.5 m miss on an orbiting raider, which is a miss the director will never
	# fire on. Feed it forward; let P correct only the residual.
	var los_rate := Vector3.ZERO
	var relative_velocity: Vector3 = -drone.linear_velocity
	var measured_velocity: Variant = target.get(&"velocity")
	if measured_velocity is Vector3:
		relative_velocity += measured_velocity as Vector3
	if to_target.length_squared() > 0.01:
		los_rate = to_target.cross(relative_velocity) / to_target.length_squared()

	# Yaw: swing the gun line's heading onto the target's bearing.
	var yaw_error: float = 0.0
	if to_flat.length() > 0.1:
		yaw_error = gun_flat.signed_angle_to(to_flat.normalized(), Vector3.UP)
	var yaw_rate: float = clampf(-yaw_p * yaw_error - los_rate.dot(Vector3.UP),
			-max_yaw_rate, max_yaw_rate)

	# Pitch: raise/lower the gun line's elevation onto the target's. Target
	# above the gun line -> nose up; below -> nose down (which also closes).
	var pitch_error: float = asin(clampf(to_dir.y, -1.0, 1.0)) \
			- asin(clampf(gun.y, -1.0, 1.0))
	# Roll: null sideways velocity so the firing line stays steady (positive
	# roll accelerates right, so oppose rightward drift with negative roll).
	var right_flat: Vector3 = Vector3(drone.global_basis.x.x, 0.0,
			drone.global_basis.x.z).normalized()
	var pitch_rate: float = clampf(
			aim_p * pitch_error + los_rate.dot(right_flat),
			-max_pitch_rate, max_pitch_rate)
	var lateral_speed: float = drone.linear_velocity.dot(right_flat)
	var roll_rate: float = clampf(-roll_damp * lateral_speed,
			-max_roll_rate, max_roll_rate)

	# GROUND GUARD, above everything else. Traced flying into a raider's face at
	# 9.5 m, tumbling past vertical, and then driving itself into the floor:
	# once inverted, "more throttle to hold altitude" points at the ground. So
	# recovery outranks the shot — roll and pitch back to level and climb, and
	# let the aim loop have the aircraft back once it is safe.
	var predicted_altitude: float = drone.global_position.y \
			+ drone.linear_velocity.y * floor_lookahead_s
	if predicted_altitude < floor_guard_m:
		var body_pitch: float = asin(clampf(-drone.global_basis.z.y, -1.0, 1.0))
		var body_roll: float = asin(clampf(drone.global_basis.x.y, -1.0, 1.0))
		pitch_rate = clampf(attitude_p * -body_pitch, -max_pitch_rate, max_pitch_rate)
		roll_rate = clampf(attitude_p * body_roll, -max_roll_rate, max_roll_rate)

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
	elif use_director:
		# Hands off the trigger: weapon.gd fires itself whenever its own arc
		# solution says a hostile is about to be hit. Keeping the gun pointed
		# somewhere useful is this loop's entire contribution.
		_hold_blaster()
	else:
		weapon.fire_override = on_target and to_target.length() < fire_range


func _altitude_throttle(target_alt: float) -> float:
	var climb: float = drone.config.autopilot_climb_gain
	var error: float = target_alt - drone.global_position.y
	# PD around hover: seek the altitude, damp vertical speed.
	var demand: float = drone.hover_throttle() \
			+ climb * (clampf(error, -4.0, 4.0) - drone.linear_velocity.y)
	# Tilt compensation. hover_throttle() is the LEVEL hover figure, but this
	# pilot spends an engagement pitched ~44 deg nose-down putting the uptilted
	# gun line on target, where only cos(44) = 72% of its thrust is holding it
	# up. Without this it sinks the whole fight and eventually falls out of the
	# world — traced doing exactly that, altitude 13 m to -24 m in ten seconds,
	# which is most of why it could never finish a gun run.
	var lift_fraction: float = maxf(drone.global_basis.y.dot(Vector3.UP), 0.25)
	return clampf(demand / lift_fraction, 0.0, 1.0)


func _hold_fire() -> void:
	_hold_blaster()
	if missile != null:
		missile.fire_override = false


func _hold_blaster() -> void:
	if weapon != null:
		weapon.fire_override = false
