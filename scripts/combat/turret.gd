class_name Turret
extends StaticBody3D

## Enemy turret (roadmap M2): acquires the armed player within range and
## line of sight, tracks with a rate-limited head, leads the shot by
## projectile flight time, and fires. Destructible; respawns after a config
## delay. Disarmed or dead players are never engaged — the spawn pad is safe.

signal destroyed(points: float)

## Combat-AI feel constant (not flight/input physics).
const AIM_TOLERANCE_DEG: float = 4.0

@export var combat_config: CombatConfig

## Read by projectiles: enemy fire never damages enemy structures.
var team: StringName = &"enemy"

@onready var _head: Node3D = $Head
@onready var _muzzle: Marker3D = $Head/Muzzle
@onready var _collision: CollisionShape3D = $Collision
@onready var _health: Health = $Health

var _player: FlightController
var _pool: ProjectilePool
var _cooldown: float = 0.0
var _alive: bool = true


func _ready() -> void:
	_health.max_health = combat_config.turret_health
	_health.revive()
	_health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _alive:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	if _pool == null:
		_pool = get_tree().get_first_node_in_group(&"projectile_pool") as ProjectilePool
	if _player == null or _pool == null:
		return
	# visible=false is the death state (main.gd) — corpses are not targets.
	if not _player.armed or not _player.visible:
		return
	if _head.global_position.distance_to(_player.global_position) > combat_config.turret_range:
		return
	if not _has_line_of_sight():
		return
	var lead: Vector3 = _lead_position()
	_track(lead, delta)
	if _cooldown <= 0.0 and _aimed_at(lead):
		_fire()
		_cooldown = 1.0 / combat_config.turret_fire_rate


func take_hit(damage: float) -> void:
	if _alive:
		_health.take(damage)


func _on_died() -> void:
	_alive = false
	Effects.explosion(get_tree().root, _head.global_position, 1.3)
	destroyed.emit(combat_config.turret_points)
	visible = false
	_collision.set_deferred(&"disabled", true)
	get_tree().create_timer(combat_config.turret_respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	_health.max_health = combat_config.turret_health
	_health.revive()
	_alive = true
	visible = true
	_collision.set_deferred(&"disabled", false)


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters3D.create(
			_head.global_position, _player.global_position)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == _player


## Aim where the player will be when a straight-line bolt arrives.
func _lead_position() -> Vector3:
	var flight_time: float = _muzzle.global_position.distance_to(_player.global_position) \
			/ combat_config.turret_muzzle_speed
	return _player.global_position + _player.linear_velocity * flight_time


func _track(point: Vector3, delta: float) -> void:
	var desired: Vector3 = point - _head.global_position
	var current: Vector3 = -_head.global_basis.z
	var angle: float = current.angle_to(desired)
	if angle < 0.0001:
		return
	var axis: Vector3 = current.cross(desired)
	# Directly opposite: any perpendicular axis works; use yaw.
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	var step: float = minf(angle, deg_to_rad(combat_config.turret_turn_speed_deg) * delta)
	_head.global_basis = (Basis(axis.normalized(), step) * _head.global_basis).orthonormalized()


func _aimed_at(point: Vector3) -> bool:
	var desired: Vector3 = point - _head.global_position
	return (-_head.global_basis.z).angle_to(desired) < deg_to_rad(AIM_TOLERANCE_DEG)


func _fire() -> void:
	var direction: Vector3 = -_head.global_basis.z
	# Zero projectile gravity: the lead solution assumes a straight bolt.
	var lifetime: float = combat_config.turret_range / combat_config.turret_muzzle_speed * 1.6
	_pool.fire(_muzzle.global_position + direction * 0.3,
			direction * combat_config.turret_muzzle_speed,
			combat_config.turret_damage, team, [get_rid()], 0.0, lifetime)
	SoundBank.play_at(&"shot", _muzzle.global_position, -4.0, 0.2)
