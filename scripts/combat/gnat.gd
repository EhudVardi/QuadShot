class_name Gnat
extends AnimatableBody3D

## One body of a gnat swarm (GAMEPLAY-DESIGN P4.2 / P4.q5).
##
## Deliberately the dumbest node in the bestiary: it holds hit points, a
## collision shape and a velocity, and nothing else. All motion is decided by
## the GnatSwarm manager in ONE loop for the whole pack — the steered decision
## that "the cloud is the unit, and that is a design statement, not a cheat."
## A gnat has no _physics_process at all; twelve of these cost twelve position
## writes, not twelve AI agents.
##
## It stays a PhysicsBody3D (not an Area3D) for one concrete reason: projectiles
## resolve hits with intersect_ray, which does not see areas. Being shootable is
## the whole point of a body that exists to be shot.

## `scored` distinguishes the two ways a gnat leaves the fight: shot down (the
## player beat it) versus spent on a sting (it beat the player, for 7 hull).
## Only the first is a kill — scoring a suicide would pay the player for being
## bitten, and would let a pack that fully stung out read as a victory.
signal killed(gnat: Gnat, scored: bool)

## Read by projectiles: enemy fire never damages enemies.
var team: StringName = &"enemy"

## Written by the swarm manager each tick; kept here so the body carries its
## own state and the manager stays a pure function over the pack.
var velocity: Vector3 = Vector3.ZERO

var _health: float = 6.0
## Flat reduction, same rule as Health.armor — a body this cheap has no Health
## node, but the damage rule must not fork: two damage pipelines with different
## armor semantics is exactly the drift Lethality exists to catch.
var _armor: float = 0.0
var _alive: bool = true


func setup(hull: float, armor: float = 0.0) -> void:
	_health = hull
	_armor = armor
	_alive = true


func take_hit(damage: float) -> void:
	if not _alive:
		return
	_health -= maxf(damage - _armor, 0.0)
	if _health <= 0.0:
		die(true)


## Also the sting path (scored = false): a body that reaches the player spends
## itself, which is its attack succeeding, not the player's shot landing.
func die(scored: bool) -> void:
	if not _alive:
		return
	_alive = false
	Effects.explosion(get_tree().root, global_position, 0.45)
	killed.emit(self, scored)
	queue_free()
