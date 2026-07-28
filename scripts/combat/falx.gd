class_name Falx
extends CharacterBody3D

## Falx — pursuit interceptor (GAMEPLAY-DESIGN P4.2, roster type five).
##
## The bestiary's second flight idiom. Every flyer shipped so far ORBITS: the
## raider holds a standoff radius and slides around you, the gnat cloud boils
## toward you, the aegis flies a fixed route. The falx does none of those — it
## flies BOOM AND ZOOM, the tactic of every aircraft that is faster than its
## target and cannot turn with it:
##
##   RUN-IN   pick a point, commit to a straight fast line, shoot on the way in
##   RECOVER  break off, climb away, DO NOT turn back — this is the window
##   SETUP    swing wide, rebuild distance, line up the next pass
##
## THE DESIGN LIVES IN THE CONFIG, NOT IN THIS FILE. `speed` 25 against `accel`
## 11 means a body that physically cannot turn tightly (accel is what
## `move_toward` spends to change direction), so the wide arc is emergent rather
## than scripted, and the recovery is long because the aircraft cannot make it
## short. That is what makes P4.2's counterplay honest: "answered by
## bait-and-overshoot — make it pass, kill the recovery." If the recovery were a
## timer, a player who learned the timer would beat it; because it is momentum, a
## player who learned the GEOMETRY beats it, which is the skill worth teaching.
##
## It is also why this type is the designed anti-camper (P3 v1.6, Firehawk
## doctrine): a player parked behind cover lobbing shells is exactly who a
## committed high-speed pass punishes, and standing still is the one thing that
## makes the falx's weakness — its turn radius — irrelevant.
##
## Counter-web position (P4.3 row): chip gun `-` (too fast to track), missile
## `+`, flak `++` (a burst across the committed line is the answer), terrain
## `++` (drag the pass through geometry and it must overshoot). Frame pressure
## (P4.4): light `++` (out-turn it), heavy `--` (cannot refuse the pass).

signal destroyed(points: float)

## Combat-AI feel constants (not flight/input physics), all in the same spirit
## as EnemyDrone's: shape constants that describe the manoeuvre, while every
## number a designer would TUNE lives in EnemyConfig.
##
## How far ahead of the player the run-in aims. The falx commits to a point in
## SPACE, not to the player — that is what "committed pass" means, and it is why
## sidestepping late works against it.
const LEAD_SECONDS: float = 0.55
## Climb angle during recovery. Steep enough to read as a zoom, shallow enough
## that it stays in the fight rather than leaving the arena.
const RECOVER_CLIMB: float = 0.55
## How long the recovery lasts, seconds. THE PLAYER'S WINDOW: the falx is
## flying a predictable line and not shooting for this whole time.
const RECOVER_SECONDS: float = 2.2
## Distance it rebuilds toward before the next run-in.
const SETUP_RANGE: float = 55.0
## The SHORTEST range a pass is worth committing from. Separate from
## SETUP_RANGE, and the separation is load-bearing: a falx that insists on a
## perfect setup distance flies AWAY from a player who is already in front of it,
## which is both wrong for the fiction and invisible in a fight (measured: at a
## 40 m spawn it spent the entire 10 s duel cap swinging out to 56 m and never
## attacked once — `dmg-taken 0.0` in every cell). It attacks from wherever it
## can and only rebuilds distance when it genuinely has none.
const RUN_IN_MIN_RANGE: float = 30.0
## Cone within which the guns will fire during a run-in, degrees. Narrow: the
## falx shoots along its flight path, it does not track across. Sized against
## the run-in geometry rather than picked — the pass is flown at a LEAD point,
## so the player sits a few degrees off the nose for the whole approach and that
## offset GROWS as the range closes. Too narrow and the type never fires at all.
const FIRE_CONE_DEG: float = 20.0
## Floor. A pass that ends in the ground is a crash, not a manoeuvre.
const MIN_ALTITUDE: float = 4.0
## Height above the player the setup arc climbs to, so passes come DOWN.
const SETUP_HEIGHT: float = 16.0

enum { RUN_IN, RECOVER, SETUP }

@export var enemy_config: EnemyConfig
## Fixed RNG seed for the harness (P4.8 determinism): -1 randomizes. Must be set
## before the node enters the tree.
@export var ai_seed: int = -1

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _visual: Node3D = $Visual
@onready var _stripe: MeshInstance3D = $Visual/Stripe
@onready var _health: Health = $Health

var _player: FlightController
var _pool: ProjectilePool
var _state: int = SETUP
var _cooldown: float = 0.0
var _state_time: float = 0.0
## The point in space this pass is committed to (see LEAD_SECONDS).
var _commit_point: Vector3
## Which side it swings out to on the setup arc. Fixed per body rather than
## re-rolled, so a wing of falx fans out instead of stacking.
var _setup_sign: float = 1.0
var _rng := RandomNumberGenerator.new()
var _stripe_material: StandardMaterial3D


func _ready() -> void:
	if ai_seed >= 0:
		_rng.seed = ai_seed
	else:
		_rng.randomize()
	_setup_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_health.max_health = enemy_config.hull
	_health.configure_defenses(enemy_config)
	_health.revive()
	_health.died.connect(_on_died)
	# Per-instance material so one falx lighting up does not light up the wing.
	if _stripe.mesh != null and _stripe.mesh.material is StandardMaterial3D:
		_stripe_material = (_stripe.mesh.material as StandardMaterial3D).duplicate() \
				as StandardMaterial3D
		_stripe.material_override = _stripe_material


func take_hit(damage: float) -> void:
	_health.take(damage)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_state_time += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
	if not _can_engage():
		_fly_toward(global_position + -global_basis.z * 10.0, delta)
		move_and_slide()
		_face_velocity(delta)
		return

	match _state:
		RUN_IN:
			_run_in(delta)
		RECOVER:
			_recover(delta)
		SETUP:
			_setup(delta)
	move_and_slide()
	_face_velocity(delta)
	_update_telegraph(delta)


func _can_engage() -> bool:
	if _player == null or _pool == null:
		return false
	# visible=false is the player's death state (main.gd).
	if not _player.armed or not _player.visible:
		return false
	return global_position.distance_to(_player.global_position) \
			<= enemy_config.sight_range


## THE PASS. Flies at a point committed to when the run-in began, not at the
## player's current position — so a late sidestep beats it, which is the
## counterplay P4.2 promises. Breaks off at `preferred_range`, or the moment the
## player ends up BEHIND it (the overshoot), whichever comes first.
func _run_in(delta: float) -> void:
	_fly_toward(_commit_point, delta)
	_try_fire()
	var to_player: Vector3 = _player.global_position - global_position
	# Overshoot is judged on where it is actually GOING, never on which way the
	# body happens to point. `_face_velocity` only yaws toward the velocity once
	# there is velocity to yaw toward, so a falx that has just spawned (or just
	# stopped) carries whatever orientation it was placed with — and the harness
	# places every enemy at identity. Measured: spawned 40 m away facing world
	# -Z with the player at +Z, the old body-facing test fired `overshot` on the
	# FIRST physics frame, so the type broke off into recovery before it had
	# moved and never attacked inside the duel cap.
	var overshot: bool = velocity.length() > 1.0 \
			and to_player.dot(velocity.normalized()) < 0.0
	if to_player.length() <= enemy_config.preferred_range or overshot:
		_enter(RECOVER)


## THE WINDOW. Climbs away on a straight line and does not shoot. Deliberately
## dumb: this is the phase the whole type is balanced around, and making it
## evasive here would delete the counterplay and the `++` flak row with it.
func _recover(delta: float) -> void:
	var away: Vector3 = (global_position - _player.global_position)
	away.y = 0.0
	if away.length() < 0.1:
		away = -global_basis.z
	var climb: Vector3 = away.normalized() + Vector3.UP * RECOVER_CLIMB
	_fly_toward(global_position + climb.normalized() * 40.0, delta)
	if _state_time >= RECOVER_SECONDS:
		_enter(SETUP)


## Rebuild distance and height, then commit to the next pass. The wide swing is
## not decoration — at `accel` 11 the aircraft needs the room to come around at
## all, so this phase is the config's turn radius made visible.
func _setup(delta: float) -> void:
	var from_player: Vector3 = global_position - _player.global_position
	var flat := Vector3(from_player.x, 0.0, from_player.z)
	if flat.length() < 0.1:
		flat = Vector3.FORWARD
	# Swing out and around rather than braking and reversing: a body this fast
	# cannot stop, and pretending it can would be the arcade answer.
	var tangent: Vector3 = flat.normalized().cross(Vector3.UP) * _setup_sign
	var station: Vector3 = _player.global_position \
			+ flat.normalized() * SETUP_RANGE + tangent * 25.0 \
			+ Vector3.UP * SETUP_HEIGHT
	if global_position.distance_to(_player.global_position) >= RUN_IN_MIN_RANGE:
		_commit_point = _player.global_position \
				+ _player.linear_velocity * LEAD_SECONDS
		_enter(RUN_IN)
		return
	_fly_toward(station, delta)


func _enter(state: int) -> void:
	_state = state
	_state_time = 0.0
	if state == RUN_IN:
		# The telegraph P4.2 asks for. A "rising shriek" belongs to the M7 audio
		# sweep; until then the pass announces itself with one cue and the
		# brightening stripe below, which is what a player actually reads at
		# 25 m/s.
		SoundBank.play_at(&"launch", global_position, -12.0, 0.8)


## Straight-line pursuit of a point, capped by the config's own numbers. The
## turn radius is NOT computed here — it emerges from `accel` being small
## relative to `speed`, which is the honest way to make a fast thing clumsy.
func _fly_toward(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	if offset.length() < 0.001:
		return
	var desired: Vector3 = offset.normalized() * enemy_config.speed
	velocity = velocity.move_toward(desired, enemy_config.accel * delta)
	# Floor guard, applied to the VELOCITY rather than the position, so the
	# aircraft pulls up like an aircraft instead of sliding along an invisible
	# plane.
	if global_position.y < MIN_ALTITUDE and velocity.y < 0.0:
		velocity.y = absf(velocity.y)


func _face_velocity(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var blend: float = 1.0 - exp(-8.0 * delta)
	if flat.length() > 2.0:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), blend)
	# Pitch with the climb/dive and bank into the turn: a falx should LOOK like
	# it is committed, because reading its line is the counterplay.
	var local_velocity: Vector3 = global_basis.inverse() * velocity
	_visual.rotation.x = lerpf(_visual.rotation.x,
			clampf(-velocity.y * 0.04, -0.6, 0.6), blend)
	_visual.rotation.z = lerpf(_visual.rotation.z,
			clampf(-local_velocity.x * 0.05, -0.7, 0.7), blend)


## Brightens through the run-in and goes dark on the recovery, so the phase the
## player must react to is the phase that glows.
func _update_telegraph(delta: float) -> void:
	if _stripe_material == null:
		return
	var target: float = 5.0 if _state == RUN_IN else 0.6
	_stripe_material.emission_energy_multiplier = lerpf(
			_stripe_material.emission_energy_multiplier, target,
			1.0 - exp(-6.0 * delta))


## Fires only along the flight path (see FIRE_CONE_DEG) — the falx shoots where
## it is going, it does not track across. That is the whole reason the chip gun
## rates `-` against it and terrain rates `++`: both answers are about making it
## point somewhere useless.
func _try_fire() -> void:
	if _cooldown > 0.0:
		return
	var to_player: Vector3 = _player.global_position - global_position
	if to_player.length() > enemy_config.sight_range:
		return
	# Against the HEADING, not the body: "it shoots along its flight path" is the
	# design sentence, and the flight path is the velocity. Same reason as the
	# overshoot test above — the body's yaw lags, and lags worst exactly when the
	# aircraft is manoeuvring hardest.
	if _heading().angle_to(to_player) > deg_to_rad(FIRE_CONE_DEG):
		return
	if not _has_line_of_sight():
		return
	# Guarded like every other bestiary ballistics path: a muzzle_speed of 0
	# would put inf/NaN into the lead solution and the projectile velocity.
	var flight_time: float = to_player.length() \
			/ maxf(enemy_config.muzzle_speed, 1.0)
	var lead: Vector3 = _player.global_position \
			+ _player.linear_velocity * flight_time
	var direction: Vector3 = _jitter((lead - global_position).normalized())
	var lifetime: float = enemy_config.sight_range \
			/ maxf(enemy_config.muzzle_speed, 1.0) * 1.6
	_pool.fire(global_position + direction * 0.8,
			direction * enemy_config.muzzle_speed,
			enemy_config.damage, team, [get_rid()], 0.0, lifetime)
	SoundBank.play_at(&"shot", global_position, -8.0, 0.25)
	_cooldown = 1.0 / maxf(enemy_config.fire_rate, 0.001)


## Where this aircraft is actually pointed, which is where it is going. Falls
## back to the body's forward only when it is barely moving — the one case where
## a velocity direction means nothing.
func _heading() -> Vector3:
	if velocity.length() > 1.0:
		return velocity.normalized()
	return -global_basis.z


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position,
			_player.global_position)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == _player


## Random cone around the aim direction — keeps enemy fire dodgeable (P4.q2).
func _jitter(direction: Vector3) -> Vector3:
	var spread: float = tan(deg_to_rad(enemy_config.aim_jitter_deg)) * _rng.randf()
	var perpendicular: Vector3 = direction.cross(Vector3.UP)
	if perpendicular.length_squared() < 0.000001:
		perpendicular = Vector3.RIGHT
	perpendicular = perpendicular.normalized().rotated(direction,
			_rng.randf_range(0.0, TAU))
	return (direction + perpendicular * spread).normalized()


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 1.3)
	destroyed.emit(enemy_config.points)
	queue_free()
