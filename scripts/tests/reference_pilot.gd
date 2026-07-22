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
## v2 (v1.26) = STANDOFF BY ORBIT: range is held in the roll axis by curving
## into a circle, leaving pitch free for aim (see standoff_range). Fixes the
## v1 ram into the non-evading aegis. Every pilot-dependent factor is
## re-measured under v2; balance/delivery_factors.json carries pilot_version 2.
## v3 (v1.28) = THE FLAK COLUMN. `use_missile` becomes `weapon_id`, and a third
## branch flies the flak pod: identical aim loop to the blaster (a fused shell
## still has to be pointed), no orbit (that is homing-only), and a manual
## trigger — the pod has no gun director, because its fuse IS its assist. The
## blaster and missile paths are byte-for-byte the flying they were under v2,
## and the re-measure PROVED it (every v2 factor came back unchanged). The bump
## is the discipline working, not a claim that anything moved.
const PILOT_VERSION: int = 3

var drone: FlightController
var weapon: Weapon
var missile: MissileSystem
var flak: FlakPod
## Which weapon this pilot is being measured with: blaster | missile | flak.
## Each column is flown the way its own weapon wants (see the orbit note), and
## aim_quality is keyed per weapon, so that is a measurement choice rather than
## a favour.
var weapon_id: String = "blaster"
var target: Node3D

# --- Competence datum (H5). Calibrated by the human against real skill. ---
## Altitude the pilot seeks, meters (harness spawns the duel around this).
var cruise_altitude: float = 14.0
## Yaw P gain (bearing the gun line onto the target).
var yaw_p: float = 4.0
## Pitch P gain (elevating the gun line onto the target).
var aim_p: float = 5.0
## Roll authority: rad/s of roll rate per m/s of sideways-velocity ERROR.
## In v1 this only ever damped drift to zero; from v2 it also drives the orbit
## (see standoff_range), so it is a tracking gain, not just a damper.
var roll_damp: float = 0.18
## --- STANDOFF BY ORBIT (PILOT_VERSION 2) ---
## The radius the pilot circles a target at, meters.
##
## v1 had no standoff and relied on every enemy MANEUVERING AWAY to stop the
## closure. The aegis breaks that — it flies straight at you at walking pace
## and never evades — so v1 flew into the bomber (traced 39.7 m to 0.5 m),
## could not lock a target it was touching, and timed out.
##
## The fix is NOT to fight the closure in pitch. With a body-fixed gun that
## must point at the target, the thrust vector's horizontal component always
## points AT the target, so the drone can never hover while aiming — it is
## always accelerating inward. Pitching up to hold range just swings the gun
## off the target, which measured worse (blaster aim 0.14 -> 0.06) and broke
## the missile lock outright.
##
## So the inward acceleration is not cancelled, it is REDIRECTED: fly
## tangentially and that same aim-driven acceleration becomes the centripetal
## force of a circle (v^2 / R = a_horizontal). Range is then held in the ROLL
## axis, leaving pitch free for aim — and it is the idiom the bestiary already
## flies (enemy_drone orbits its own preferred_range).
var standoff_range: float = 16.0
## Tangential speed of that circle, m/s. Sized from the geometry: aiming a
## level target parks the drone near 44 deg nose-down, giving roughly
## g*tan(44) ~ 9.5 m/s^2 inward, so a stable 16 m orbit wants
## sqrt(9.5 * 16) ~ 12 m/s. Set slightly under, and let the range term below
## trim the rest.
var orbit_speed: float = 11.0
## Range at which the pilot starts curving into the orbit. Deliberately far
## out: the tangential speed must be BUILT during the run-in so the pilot
## ARRIVES already circling. Engaging late means meeting the radius with
## ~13 m/s of inward momentum that no swerve absorbs — a spiral settles, a
## swerve does not.
var orbit_engage_range: float = 45.0
## How much harder to orbit when inside the radius (multiplier ceiling on
## orbit_speed). Faster tangentially = more centrifugal = the circle widens
## back out, which is how the pilot pushes off a charger without touching
## pitch. Capped low, because this is the term that flings.
var orbit_push_max: float = 1.4
## Which way around. Fixed rather than random: rep-to-rep determinism (P4.8)
## matters more here than variety, and a coin flip would put two neighbouring
## reps on different sides of the same fight.
var orbit_sign: float = 1.0
## Bank commanded per m/s of tangential-speed error, radians.
var orbit_bank_per_error: float = 0.10
## Hard ceiling on that bank, radians. THIS IS A THRUST BUDGET, not a taste:
## the aim already parks the drone near 44 deg nose-down, so vertical lift is
## only cos(44)*cos(bank) of thrust. Commanding roll as a raw RATE (the first
## attempt) had no such ceiling — an 11 m/s error asked for ~113 deg/s of
## sustained roll, the drone banked past what it could hold altitude at, and
## it sank from 14 m to 3.9 m into the floor guard. At 32 deg the budget is
## cos(44)*cos(32) = 0.61 of hover thrust, which the tilt compensation covers.
var orbit_bank_max: float = 0.56
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
	if weapon_id != "missile":
		var raw: Vector3 = target.global_position - drone.global_position
		var target_vel: Variant = target.get(&"velocity")
		# Lead by the round's OWN flight time. A flak shell is slower than a bolt
		# (70 vs 90 m/s), and leading it at the bolt's speed would measure a
		# defect in this file wearing the flak column's name.
		var speed: float = weapon.combat_config.flak_muzzle_speed \
				if weapon_id == "flak" else weapon.combat_config.muzzle_speed
		var flight_time: float = raw.length() / maxf(speed, 1.0)
		if target_vel is Vector3:
			aim_point += (target_vel as Vector3) * flight_time
	var to_target: Vector3 = aim_point - drone.global_position
	var to_dir: Vector3 = to_target.normalized()
	var to_flat := Vector3(to_target.x, 0.0, to_target.z)
	# The GUN LINE: the weapon sits under the FPV camera and fires along its
	# -Z, so the uptilt is baked into this basis. Aiming the body would miss
	# high by the uptilt angle.
	#
	# The flak pod is a SIBLING of the weapon under the same camera with the same
	# identity local transform, so this basis is its gun line too — an equality
	# by construction, not a coincidence, but one that would break silently if
	# anything ever rotated the Weapon node in a pilot-driven path. Nothing does
	# (only the delivery bench's frozen perfect shooter re-lays these nodes, and
	# the pilot does not run in those cells). Read as: if that ever changes, the
	# flak branch needs `flak.global_basis` and a re-measure.
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
	# ORBIT (see standoff_range) — HOMING WEAPONS ONLY. Measured, not assumed:
	# a swept range of orbit settings against a static target traded aim
	# against closest-approach strictly monotonically, and every setting that
	# bought standoff cost the gun everything.
	#
	#   orbit off (v1)   aim 0.17   closest 0.3 m
	#   engage 18 m      aim 0.06   closest 2.6 m
	#   engage 22 m      aim 0.00   closest 3.6 m
	#   engage 45 m      aim 0.00   closest 6.5 m
	#
	# Tight last-second breaks were tried too and are the worst of both: by
	# 6 m there is no turning out, so they neither saved the range (still
	# 0.3 m) nor spared the aim. There is no setting that does both.
	#
	# But the ram only BREAKS the missile cells — you cannot lock a target you
	# are touching, which is the whole aegis failure — while the gun measures
	# fine at 0.17 through the ram. And the orbit's cost is specifically
	# BALLISTIC: circling makes every bolt a deflection shot from a turning
	# platform, while the homing missile held 1.00 throughout. So the orbit
	# goes exactly where the ram hurts and its cost does not apply. That is a
	# real tactical truth rather than a fudge — a pilot carrying a homing
	# weapon can afford to maneuver precisely because it need not point — and
	# aim_quality is already keyed per weapon, so each is measured under the
	# flying its own weapon wants.
	var range: float = drone.global_position.distance_to(target.global_position)
	var orbit_blend: float = 0.0
	if weapon_id == "missile":
		orbit_blend = clampf(
				(orbit_engage_range - range)
				/ maxf(orbit_engage_range - standoff_range, 0.1),
				0.0, orbit_push_max)
	var desired_lateral: float = orbit_sign * orbit_speed * orbit_blend
	var lateral_speed: float = drone.linear_velocity.dot(right_flat)
	# Bank-ANGLE loop, not a raw rate (see orbit_bank_max): ask for a bank
	# proportional to the tangential-speed error, ceiling it inside the thrust
	# budget, then rate-control toward that attitude. Banking right (to
	# accelerate right) is NEGATIVE body roll here, matching the sign the
	# ground guard levels with.
	var body_roll: float = asin(clampf(drone.global_basis.x.y, -1.0, 1.0))
	var desired_bank: float = -clampf(
			orbit_bank_per_error * (desired_lateral - lateral_speed),
			-orbit_bank_max, orbit_bank_max)
	var roll_rate: float = clampf(attitude_p * (body_roll - desired_bank),
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
		pitch_rate = clampf(attitude_p * -body_pitch, -max_pitch_rate, max_pitch_rate)
		roll_rate = clampf(attitude_p * body_roll, -max_roll_rate, max_roll_rate)

	drone.rate_override = Vector3(roll_rate, pitch_rate, yaw_rate)
	drone.throttle_override = _altitude_throttle(cruise_altitude)

	# Fire when the GUN line is on the target and it is in reach.
	var on_target: bool = gun.angle_to(to_target) < deg_to_rad(fire_cone_deg)
	var in_reach: bool = to_target.length() < fire_range
	if weapon_id == "missile":
		# The director launches the instant a lock completes; keeping the
		# target in the (camera-aligned) lock cone is the aim loop's job.
		if missile != null:
			missile.fire_override = true
		_hold_blaster()
	elif weapon_id == "flak":
		# The pod has no gun director to hand the trigger to (flak_pod.gd says
		# why: the proximity fuse is the assist), so this loop pulls it — under
		# the SAME cone and range knobs the manual blaster path uses. Widening
		# the cone "because the fuse forgives" would be tuning the ruler to
		# flatter the column it is measuring; if the fuse forgives, that must
		# show up as more BURSTS CONNECTING, not as an easier trigger.
		if flak != null:
			flak.fire_override = on_target and in_reach
		_hold_blaster()
	elif use_director:
		# Hands off the trigger: weapon.gd fires itself whenever its own arc
		# solution says a hostile is about to be hit. Keeping the gun pointed
		# somewhere useful is this loop's entire contribution.
		_hold_blaster()
	else:
		weapon.fire_override = on_target and in_reach


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
	if flak != null:
		flak.fire_override = false


func _hold_blaster() -> void:
	if weapon != null:
		weapon.fire_override = false
