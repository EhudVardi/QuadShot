class_name ShieldShell
extends AnimatableBody3D

## The physical surface of a shielded enemy's bubble (GAMEPLAY-DESIGN P4.1
## "shielded"). Exists so the shield is a THING rather than a rule: bolts
## splash on it where you can see them, and you cannot fly inside a barrier
## that is stopping your fire — which is what made the decorative version
## read as broken.
##
## It holds no state. Hits are forwarded to the owner's Health, which owns the
## threshold gate; the owner toggles this body with the shield.
##
## AnimatableBody3D (sync_to_physics off) for the same reason the gnats are:
## it rides along with a parent that moves itself, without being simulated.

signal hit(damage: float)

## Read by projectiles: enemy fire never damages enemy structures.
var team: StringName = &"enemy"


func take_hit(damage: float) -> void:
	hit.emit(damage)
