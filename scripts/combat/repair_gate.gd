class_name RepairGate
extends Node3D

## Fly-through engine-repair gate (GAMEPLAY-DESIGN P2.6 / D5 — revised from the
## hover pad per playtest). Limp through the green gate and instantly regain
## control: engines restored, a hull top-up thrown in. A GATE, not a hover
## point, because holding station on a wounded quad under fire is a death
## sentence — you recover by *flying through*, keeping your speed and your life.
## Uniquely green so it never reads as the (blue) exit gate.

signal repaired

## Modest hull heal on pass-through — engines are the point, not a free full heal.
@export var hull_bonus: float = 30.0
## Re-arm delay so the gate can't be spam-camped back and forth.
@export var cooldown: float = 1.5

@onready var _area: Area3D = $Area

var _cool: float = 0.0


func _ready() -> void:
	add_to_group(&"repair_gates")
	_area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(_cool - delta, 0.0)


func _on_body_entered(body: Node3D) -> void:
	if _cool > 0.0 or not (body is FlightController):
		return
	var drone := body as FlightController
	drone.repair_motors()
	var health: Health = drone.get_node("Health") as Health
	if health != null and health.alive:
		health.heal(hull_bonus)
	_cool = cooldown
	SoundBank.play_at(&"lock", global_position, -4.0, 0.05)
	repaired.emit()
