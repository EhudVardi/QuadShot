class_name ExitGate
extends Node3D

## Sortie exit gate (roadmap M4): invisible until the sortie's waves are
## cleared, then lights up; flying through it triggers the upgrade draft.
## Non-solid on purpose — a magic gate, not an obstacle.

signal entered

@onready var _area: Area3D = $Area

var active: bool = false


func _ready() -> void:
	visible = false
	_area.monitoring = false
	_area.body_entered.connect(_on_body_entered)


func activate() -> void:
	active = true
	visible = true
	_area.set_deferred(&"monitoring", true)


func deactivate() -> void:
	active = false
	visible = false
	_area.set_deferred(&"monitoring", false)


func _on_body_entered(body: Node3D) -> void:
	if active and body is FlightController:
		deactivate()
		entered.emit()
