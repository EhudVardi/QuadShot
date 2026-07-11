class_name Projectile
extends Node3D

## Pooled tracer projectile. Movement is integrated manually on the physics
## tick with a segment raycast per step, so fast projectiles can never tunnel
## through thin geometry. Hits call take_hit(damage) on the collider unless
## it shares the shooter's team.

@export var player_material: StandardMaterial3D
@export var enemy_material: StandardMaterial3D

@onready var _tracer: MeshInstance3D = $Tracer

var _velocity: Vector3
var _damage: float
var _team: StringName
var _gravity: float
var _life: float = 0.0
var _exclude: Array[RID] = []
var _pool: ProjectilePool

var _gravity_default: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	set_physics_process(false)
	visible = false


func setup(pool: ProjectilePool) -> void:
	_pool = pool


func launch(origin: Vector3, velocity: Vector3, damage: float, team: StringName,
		exclude: Array[RID], gravity_scale: float, lifetime: float) -> void:
	global_position = origin
	_velocity = velocity
	_damage = damage
	_team = team
	_exclude = exclude
	_gravity = _gravity_default * gravity_scale
	_life = lifetime
	_tracer.material_override = player_material if team == &"player" else enemy_material
	_orient_to_velocity()
	visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_velocity += Vector3.DOWN * (_gravity * delta)
	var step: Vector3 = _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.exclude = _exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_resolve_hit(hit)
		return
	global_position += step
	_life -= delta
	if _life <= 0.0:
		_deactivate()


func _resolve_hit(hit: Dictionary) -> void:
	var collider: Object = hit["collider"]
	# Feed the HUD's damage-direction indicator before the hit lands.
	if collider is FlightController:
		(collider as FlightController).last_hit_direction = -_velocity.normalized()
	# Same team: no damage, just fizzle (spawn offset + shooter exclusion
	# already prevent self-hits; this covers e.g. turret-on-turret fire).
	if collider.get("team") != _team and collider.has_method("take_hit"):
		collider.call("take_hit", _damage)
	Effects.impact(get_tree().root, hit["position"])
	_deactivate()


func _orient_to_velocity() -> void:
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(direction, up)


func _deactivate() -> void:
	visible = false
	set_physics_process(false)
	_pool.release(self)
