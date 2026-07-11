class_name Missile
extends Node3D

## Homing missile: pure-pursuit steering with a rate-limited turn toward the
## locked target, segment raycast against the world (no tunneling), and
## proximity detonation. If the target dies mid-flight it flies straight and
## expires. Missiles are infrequent — instantiate + free, no pool.

var _config: CombatConfig
var _target: Node3D
var _velocity: Vector3
var _team: StringName
var _exclude: Array[RID] = []
var _life: float = 0.0


func setup(target: Node3D, config: CombatConfig, team: StringName,
		exclude: Array[RID], direction: Vector3) -> void:
	_target = target
	_config = config
	_team = team
	_exclude = exclude
	_velocity = direction * config.missile_speed
	_life = config.missile_lifetime
	_orient()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_detonate(null)
		return
	var target_alive: bool = _target != null and is_instance_valid(_target) \
			and not _target.is_queued_for_deletion()
	if target_alive:
		_steer(delta)
		if global_position.distance_to(_target.global_position) <= _config.missile_prox_radius:
			_detonate(_target)
			return
	var step: Vector3 = _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.exclude = _exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		_detonate(hit["collider"])
		return
	global_position += step
	_orient()


func _steer(delta: float) -> void:
	var desired: Vector3 = (_target.global_position - global_position).normalized()
	var current: Vector3 = _velocity.normalized()
	var angle: float = current.angle_to(desired)
	if angle > 0.0001:
		var axis: Vector3 = current.cross(desired)
		if axis.length_squared() < 0.000001:
			axis = Vector3.UP
		var step: float = minf(angle, deg_to_rad(_config.missile_turn_rate_deg) * delta)
		current = current.rotated(axis.normalized(), step)
	_velocity = current * _config.missile_speed


func _detonate(victim: Object) -> void:
	if victim != null and victim.get("team") != _team and victim.has_method("take_hit"):
		victim.call("take_hit", _config.missile_damage)
	Effects.explosion(get_tree().root, global_position, 0.9)
	queue_free()


func _orient() -> void:
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)
