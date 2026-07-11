class_name Health
extends Node

## Reusable hit-point component (roadmap M2). The owner forwards take_hit()
## here; whoever orchestrates the entity (main for the player, turret.gd for
## turrets) connects the signals.

signal damaged(amount: float, remaining: float)
signal died

@export var max_health: float = 100.0

var current: float
var alive: bool = true


func _ready() -> void:
	current = max_health


func take(amount: float) -> void:
	if not alive:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, current)
	if current <= 0.0:
		alive = false
		died.emit()


func revive() -> void:
	current = max_health
	alive = true
