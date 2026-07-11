class_name ProjectilePool
extends Node

## Fixed-size projectile pool shared by the player weapon and all turrets
## (found via the "projectile_pool" group). Exhaustion drops shots instead
## of allocating — the 240 Hz tick never pays for instantiation mid-fight.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")
const POOL_SIZE: int = 128

var _free: Array[Projectile] = []


func _ready() -> void:
	add_to_group(&"projectile_pool")
	for i: int in POOL_SIZE:
		var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
		projectile.setup(self)
		add_child(projectile)
		_free.append(projectile)


func fire(origin: Vector3, velocity: Vector3, damage: float, team: StringName,
		exclude: Array[RID], gravity_scale: float, lifetime: float) -> void:
	if _free.is_empty():
		return
	var projectile: Projectile = _free.pop_back()
	projectile.launch(origin, velocity, damage, team, exclude, gravity_scale, lifetime)


func release(projectile: Projectile) -> void:
	_free.append(projectile)


## For tests: projectiles currently in flight.
func live_count() -> int:
	return POOL_SIZE - _free.size()
