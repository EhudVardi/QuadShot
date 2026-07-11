extends Control

## Screen-center reticle. Truthful because the weapon fires along the FPV
## camera axis (see weapon.gd).


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var center: Vector2 = size * 0.5
	draw_arc(center, 10.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5, true)
	draw_circle(center, 1.5, Color(1, 1, 1, 0.9))
