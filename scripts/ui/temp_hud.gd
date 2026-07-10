extends CanvasLayer

## TEMPORARY Phase 1 status readout — replaced by the real debug overlay
## (debug_overlay.tscn) in Phase 3. Exists so throttle/arm state is visible
## while there is no other UI.

@export var drone: FlightController

@onready var _label: Label = $StatusLabel


func _process(_delta: float) -> void:
	var armed_text: String = "ARMED" if drone.armed else "disarmed"
	_label.text = "%s\nthrottle: %3.0f%%  (hover ~%.0f%%)\naltitude: %.1f m\nspeed: %.1f m/s\n\n[Enter] arm/disarm   [W/S] throttle   [R] reset" % [
		armed_text,
		drone.collective * 100.0,
		drone.hover_throttle() * 100.0,
		drone.global_position.y,
		drone.linear_velocity.length(),
	]
