class_name MissileSystem
extends Node3D

## Missile lock + launcher, mounted under the FPV camera like the blaster so
## the lock cone follows the pilot's view. Hold an enemy near the reticle to
## build a lock (yellow diamond); once locked (red, tone) LT fires a homing
## missile. Losing the cone drops the lock.

const MISSILE_SCENE: PackedScene = preload("res://scenes/combat/missile.tscn")

@export var combat_config: CombatConfig

## Test hook (scripts/tests/missile_check.gd): fires as soon as locked.
var fire_override: bool = false

## Current lock candidate (enemy drone) and progress [0, 1]; 1 = locked.
var target: Node3D
var lock_progress: float = 0.0

var _drone: FlightController
var _cooldown: float = 0.0
var _lock_announced: bool = false


func _ready() -> void:
	_drone = owner as FlightController


func is_locked() -> bool:
	return target != null and lock_progress >= 1.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _drone.armed:
		target = null
		lock_progress = 0.0
		_lock_announced = false
		return
	var candidate: Node3D = _best_candidate()
	if candidate != target:
		target = candidate
		lock_progress = 0.0
		_lock_announced = false
	elif target != null:
		lock_progress = minf(lock_progress + delta / combat_config.missile_lock_time, 1.0)
		if is_locked() and not _lock_announced:
			_lock_announced = true
			SoundBank.play_at(&"lock", global_position, -6.0, 0.02)
	var trigger: bool = fire_override or Input.is_action_just_pressed(&"fire_missile")
	if trigger and is_locked() and _cooldown <= 0.0:
		_launch()


## Nearest-to-reticle enemy inside the lock cone, range, and line of sight.
func _best_candidate() -> Node3D:
	var best: Node3D = null
	var best_angle: float = deg_to_rad(combat_config.missile_lock_cone_deg)
	var forward: Vector3 = -global_basis.z
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy_3d: Node3D = enemy as Node3D
		if enemy_3d == null or enemy_3d.is_queued_for_deletion():
			continue
		var offset: Vector3 = enemy_3d.global_position - global_position
		if offset.length() > combat_config.missile_lock_range:
			continue
		var angle: float = forward.angle_to(offset)
		if angle >= best_angle:
			continue
		if not _has_line_of_sight(enemy_3d):
			continue
		best_angle = angle
		best = enemy_3d
	return best


func _has_line_of_sight(enemy: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, enemy.global_position)
	query.exclude = [_drone.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == enemy


func _launch() -> void:
	var missile: Missile = MISSILE_SCENE.instantiate() as Missile
	_drone.get_parent().add_child(missile)
	var direction: Vector3 = -global_basis.z
	missile.global_position = global_position + direction * 0.5
	missile.setup(target, combat_config, _drone.team, [_drone.get_rid()], direction)
	SoundBank.play_at(&"launch", global_position, -4.0, 0.1)
	_cooldown = combat_config.missile_cooldown
	lock_progress = 0.0
	_lock_announced = false
