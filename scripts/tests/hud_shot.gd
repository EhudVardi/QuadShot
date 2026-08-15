extends SceneTree

## SCREENSHOT RIG — boot a scene, put the airframe at a stated attitude, and save
## what the HUD actually looks like.
##
## Written because the agent kept saying "this cannot be judged from here, only
## `--headless` runs are available and it never calls `_draw`". That is true of
## HEADLESS and it is not true of the agent: a windowed run can capture its own
## viewport, and an image can be looked at. The human asked for exactly that
## after reporting they could not find a line the agent believed was on screen —
## *"are you sure we see the same? can you make a screen shot and show me."*
##
## RUN IT WITHOUT --headless, or there is no framebuffer to capture:
##   <godot> --path . -s scripts/tests/hud_shot.gd -- --out <folder>
##
## It writes one PNG per attitude, because the whole question is what the
## instruments do as the aircraft moves: level (where the airframe's line sits
## exactly on the world horizon by construction) and two tilts (where they
## separate). A single level shot would have shown one line and settled nothing.

const SCENE: String = "res://scenes/dev_map.tscn"
## Attitudes to capture: name, then roll and pitch in degrees.
const SHOTS: Array = [
	["level", 0.0, 0.0],
	["pitch15", 0.0, -15.0],
	["pitch30", 0.0, -30.0],
	["pitch45", 0.0, -45.0],
	["roll35_pitch15", 35.0, -15.0],
]
const SETTLE_FRAMES: int = 45
const HOLD_FRAMES: int = 6

var _root_node: Node3D
var _drone: Node3D
var _out: String = ""
var _index: int = 0
var _frames: int = 0
var _phase: int = 0

enum { BOOT, POSE, SHOOT, DONE }


func _initialize() -> void:
	# Instruments read the repo's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--out")
	_out = args[at + 1] if at >= 0 and at + 1 < args.size() else "user://hud_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	_root_node = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_root_node)
	print("[shot] booting %s, writing to %s" % [SCENE, _out])
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	match _phase:
		BOOT:
			_frames += 1
			if _frames < SETTLE_FRAMES:
				return
			_drone = _root_node.get_node_or_null("Drone") as Node3D
			if _drone == null:
				print("[shot] FAILED: no Drone in %s" % SCENE)
				quit(1)
				return
			# Frozen so physics does not fight the pose. The HUD reads
			# `global_basis.y`, so a held attitude is a held reading.
			(_drone as RigidBody3D).freeze = true
			_phase = POSE
			_frames = 0
		POSE:
			_pose()
			_phase = SHOOT
			_frames = 0
		SHOOT:
			_frames += 1
			if _frames < HOLD_FRAMES:
				return
			_capture()
			_index += 1
			if _index >= SHOTS.size():
				_phase = DONE
				print("[shot] DONE")
				quit(0)
				return
			_phase = POSE
			_frames = 0


func _pose() -> void:
	var shot: Array = SHOTS[_index]
	var basis := Basis(Vector3.FORWARD, deg_to_rad(float(shot[1]))) \
			* Basis(Vector3.RIGHT, deg_to_rad(float(shot[2])))
	_drone.global_transform = Transform3D(basis, _drone.global_position)


func _capture() -> void:
	var shot: Array = SHOTS[_index]
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/hud_%s.png" % [_out, shot[0]]
	var err: int = image.save_png(path)
	print("[shot] %s roll %.0f pitch %.0f -> %s (%s)"
			% [shot[0], float(shot[1]), float(shot[2]), path,
			"ok" if err == OK else "FAILED %d" % err])
