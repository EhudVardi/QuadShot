extends Node3D

## Scene orchestration: camera switching (camera_toggle / X: FPV ↔ chase),
## combat config startup load, and score keeping. Combat entities report in
## through their "destroyed" signals.

@export var combat_config: CombatConfig

@onready var _fpv_camera: Camera3D = $Drone/FpvCamera
@onready var _chase_camera: Camera3D = $ChaseCamera
@onready var _hud: GameHud = $Hud

var score: int = 0


func _ready() -> void:
	if combat_config.load_from_user():
		print("[config] loaded %s" % combat_config.save_path())
	for target: Node in get_tree().get_nodes_in_group(&"targets"):
		target.connect(&"destroyed", _on_scorer_destroyed)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"camera_toggle"):
		if _fpv_camera.current:
			_chase_camera.make_current()
		else:
			_fpv_camera.make_current()


func _on_scorer_destroyed(points: float) -> void:
	score += int(points)
	_hud.set_score(score)
