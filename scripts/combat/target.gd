class_name PracticeTarget
extends StaticBody3D

## Destructible practice target (roadmap M1): one hit pops it — explosion,
## points, respawn after a delay so the practice loop stays populated.

signal destroyed(points: float)

@export var combat_config: CombatConfig

## Read by projectiles: neutral targets take hits from everyone.
var team: StringName = &"neutral"

var _alive: bool = true

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision


func take_hit(_damage: float) -> void:
	if not _alive:
		return
	_alive = false
	Effects.explosion(get_tree().root, global_position)
	destroyed.emit(combat_config.target_points)
	_mesh.visible = false
	# Called from projectile physics code — collision changes must defer.
	_collision.set_deferred(&"disabled", true)
	get_tree().create_timer(combat_config.target_respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	_alive = true
	_mesh.visible = true
	_collision.set_deferred(&"disabled", false)
