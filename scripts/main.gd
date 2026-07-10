extends Node3D

## Scene-level camera switching (camera_toggle / X): FPV ↔ third-person
## chase, for debugging physics visually (handoff §10).

@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_chase_camera.make_current()
		else:
			_fpv_camera.make_current()
