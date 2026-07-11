class_name Effects
extends Object

## Static helpers for one-shot combat VFX. Explosions are infrequent enough
## that instantiate + self-free is fine; projectiles are the pooled hot path.

const EXPLOSION_SCENE: PackedScene = preload("res://scenes/combat/explosion.tscn")


static func explosion(parent: Node, position: Vector3, size: float = 1.0) -> void:
	var effect: ExplosionEffect = EXPLOSION_SCENE.instantiate() as ExplosionEffect
	parent.add_child(effect)
	effect.global_position = position
	effect.detonate(size)


## Small spark burst for non-lethal projectile impacts.
static func impact(parent: Node, position: Vector3) -> void:
	explosion(parent, position, 0.25)
