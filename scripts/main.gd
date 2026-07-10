extends Node3D

## Scene-level camera switching (camera_toggle / X): FPV ↔ static overview.
## The static overview camera is a placeholder — it becomes a proper chase
## camera in Phase 3.

@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _debug_camera: Camera3D = $DebugCamera


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_debug_camera.make_current()
		else:
			_fpv_camera.make_current()
