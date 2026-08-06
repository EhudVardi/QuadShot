extends Node3D

## The stand-in player `lance_check` flies its Lance at.
##
## Deliberately NOT a real drone. The check is about the Lance's behaviour, and
## putting a flight model in the loop would make every failure ambiguous between
## the two — the same reasoning that keeps the delivery bench's evasion shooter
## frozen. All the Lance asks of a target is the `player` group, a `team` that is
## not its own, a position, and something to call when the blast lands.

var team: StringName = &"player"
## Damage this body has absorbed. `lance_check` reads it to assert that a Lance
## killed during its telegraph costs the player nothing.
var taken: float = 0.0


func take_hit(damage: float) -> void:
	taken += damage
