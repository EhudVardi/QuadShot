class_name EnemyDrone
extends CharacterBody3D

## Enemy attack drone (roadmap M3). Kinematic flyer: accelerates toward a
## desired point (wander waypoint, or an orbit slot around the player when
## engaging), yaws into its velocity, banks visually, and fires led,
## jittered bolts. Spawned and reaped by the WaveDirector; no self-respawn.

signal destroyed(points: float)

## Combat-AI feel constants (not flight/input physics).
const MIN_ALTITUDE: float = 2.0
const WANDER_RADIUS: float = 25.0
const ORBIT_TANGENT_BIAS: float = 8.0

@export var combat_config: CombatConfig

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

@onready var _visual: Node3D = $Visual
@onready var _health: Health = $Health

var _player: FlightController
var _pool: ProjectilePool
var _home: Vector3
var _wander_target: Vector3
var _cooldown: float = 0.0
var _orbit_sign: float = 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_home = global_position
	_rng.randomize()
	_orbit_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_health.max_health = combat_config.enemy_health
	_health.revive()
	_health.died.connect(_on_died)
	_pick_wander_target()


func take_hit(damage: float) -> void:
	_health.take(damage)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
	var desired_point: Vector3
	if _can_engage():
		desired_point = _orbit_point()
		_try_fire()
	else:
		if global_position.distance_to(_wander_target) < 3.0:
			_pick_wander_target()
		desired_point = _wander_target
	desired_point.y = maxf(desired_point.y, MIN_ALTITUDE)
	_steer_toward(desired_point, delta)
	move_and_slide()
	_face_velocity(delta)


func _can_engage() -> bool:
	if _player == null or _pool == null:
		return false
	# visible=false is the player's death state (main.gd).
	if not _player.armed or not _player.visible:
		return false
	if global_position.distance_to(_player.global_position) > combat_config.enemy_sight_range:
		return false
	return _has_line_of_sight()


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, _player.global_position)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == _player


## Orbit slot: hold preferred range while sliding sideways around the player.
func _orbit_point() -> Vector3:
	var from_player: Vector3 = global_position - _player.global_position
	var flat := Vector3(from_player.x, 0.0, from_player.z)
	if flat.length_squared() < 0.25:
		flat = Vector3.FORWARD
	var radial: Vector3 = flat.normalized()
	var tangent: Vector3 = radial.cross(Vector3.UP) * _orbit_sign
	return _player.global_position + radial * combat_config.enemy_preferred_range \
			+ tangent * ORBIT_TANGENT_BIAS + Vector3.UP * 2.0


func _steer_toward(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	# Arrive: full speed far out, ease in over the last few meters.
	var desired_speed: float = minf(offset.length() * 1.5, combat_config.enemy_speed)
	var desired_velocity: Vector3 = offset.normalized() * desired_speed
	velocity = velocity.move_toward(desired_velocity, combat_config.enemy_accel * delta)


func _face_velocity(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var blend: float = 1.0 - exp(-6.0 * delta)
	if flat.length() > 2.0:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), blend)
	# Cosmetic banking: nose down with forward speed, roll into strafes.
	var local_velocity: Vector3 = global_basis.inverse() * velocity
	_visual.rotation.x = lerpf(_visual.rotation.x,
			clampf(local_velocity.z * 0.03, -0.5, 0.5), blend)
	_visual.rotation.z = lerpf(_visual.rotation.z,
			clampf(-local_velocity.x * 0.03, -0.5, 0.5), blend)


func _try_fire() -> void:
	if _cooldown > 0.0:
		return
	var flight_time: float = global_position.distance_to(_player.global_position) \
			/ combat_config.enemy_muzzle_speed
	var lead: Vector3 = _player.global_position + _player.linear_velocity * flight_time
	var direction: Vector3 = (lead - global_position).normalized()
	direction = _jitter(direction)
	var lifetime: float = combat_config.enemy_sight_range / combat_config.enemy_muzzle_speed * 1.6
	_pool.fire(global_position + direction * 0.6,
			direction * combat_config.enemy_muzzle_speed,
			combat_config.enemy_damage, team, [get_rid()], 0.0, lifetime)
	SoundBank.play_at(&"shot", global_position, -8.0, 0.25)
	_cooldown = 1.0 / combat_config.enemy_fire_rate


## Random cone around the aim direction — keeps enemy fire dodgeable.
func _jitter(direction: Vector3) -> Vector3:
	var spread: float = tan(deg_to_rad(combat_config.enemy_aim_jitter_deg)) * _rng.randf()
	var perpendicular: Vector3 = direction.cross(Vector3.UP)
	if perpendicular.length_squared() < 0.000001:
		perpendicular = Vector3.RIGHT
	perpendicular = perpendicular.normalized().rotated(direction, _rng.randf_range(0.0, TAU))
	return (direction + perpendicular * spread).normalized()


func _pick_wander_target() -> void:
	_wander_target = _home + Vector3(
			_rng.randf_range(-WANDER_RADIUS, WANDER_RADIUS),
			_rng.randf_range(2.0, 14.0),
			_rng.randf_range(-WANDER_RADIUS, WANDER_RADIUS))


func _on_died() -> void:
	Effects.explosion(get_tree().root, global_position, 1.2)
	destroyed.emit(combat_config.enemy_points)
	queue_free()
