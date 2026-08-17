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
##   <godot> --path . -s scripts/tests/hud_shot.gd -- --scene res://scenes/drill.tscn
##
## `--scene` because the rig is worth pointing at anything with a Drone in it —
## the drill runner's brief panel was checked this way, and the whole lesson of
## round 5 was that a picture settles in one look what reasoning had got wrong
## three times.
##
## It writes one PNG per attitude, because the whole question is what the
## instruments do as the aircraft moves: level (where the airframe's line sits
## exactly on the world horizon by construction) and two tilts (where they
## separate). A single level shot would have shown one line and settled nothing.

const DEFAULT_SCENE: String = "res://scenes/dev_map.tscn"
## Attitudes to capture: name, then roll and pitch in degrees.
## Negative pitch is NOSE DOWN, which is the direction that brings the world
## horizon up into view on a 48-degree uptilt lens. `pitchup30` is here because
## nose-UP is where the horizon runs off the BOTTOM of the screen, and that is
## the attitude the human reported the whole instrument vanishing in.
const SHOTS: Array = [
	["level", 0.0, 0.0],
	["pitch15", 0.0, -15.0],
	["pitch30", 0.0, -30.0],
	["pitch45", 0.0, -45.0],
	["pitchup30", 0.0, 30.0],
	# Steep enough to look DOWN. With 48 degrees of lens uptilt nothing shallower
	# than this points at the ground at all, so it is the only pose that can check
	# a surface the pilot flies over rather than toward.
	["pitch70", 0.0, -70.0],
	["roll35_pitch15", 35.0, -15.0],
	# INVERTED, and it is here because a whole round of this instrument shipped
	# with the horizon running BACKWARDS upside down and every claim green.
	["inverted_pitch15", 180.0, -15.0],
	["knife_edge", 90.0, -15.0],
]
## Per-rotor throttles to pose the drive rings at. Deliberately all different
## and deliberately including 0 and 1, so an empty ring, a full one and two
## partials are all in the same picture.
## FL and BR turn one way, FR and BL the other, so this deliberately puts a
## PARTIAL arc on both sides of that pair: at 0/0.35/0.75/1.0 the only two arcs
## whose direction was visible were the two that share a direction, and the
## picture could not have shown the rule it exists to check.
const DRIVES: Array[float] = [0.25, 0.6, 0.85, 1.0]
const SETTLE_FRAMES: int = 45
const HOLD_FRAMES: int = 6

var _root_node: Node3D
var _drone: Node3D
var _scene: String = DEFAULT_SCENE
var _lift: float = 0.0
var _spawn_y: float = 0.0
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
	at = args.find("--scene")
	if at >= 0 and at + 1 < args.size():
		_scene = args[at + 1]
	# Metres to lift the airframe before posing it. Sitting on a pad the camera
	# is centimetres off the surface, and a surface seen from 6 cm at a grazing
	# angle tells you nothing about what it looks like to fly over.
	at = args.find("--lift")
	if at >= 0 and at + 1 < args.size():
		_lift = float(args[at + 1])
	DirAccess.make_dir_recursive_absolute(_out)
	_root_node = (load(_scene) as PackedScene).instantiate() as Node3D
	root.add_child(_root_node)
	print("[shot] booting %s, writing to %s" % [_scene, _out])
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	match _phase:
		BOOT:
			_frames += 1
			if _frames < SETTLE_FRAMES:
				return
			_drone = _root_node.get_node_or_null("Drone") as Node3D
			if _drone == null:
				print("[shot] FAILED: no Drone in %s" % _scene)
				quit(1)
				return
			# Frozen so physics does not fight the pose. The HUD reads
			# `global_basis.y`, so a held attitude is a held reading.
			(_drone as RigidBody3D).freeze = true
			_spawn_y = _drone.global_position.y
			# FOUR DIFFERENT THROTTLES, so the drive rings can be JUDGED. Frozen
			# and disarmed every rotor sits at zero, which draws four identical
			# empty tracks and would have made this rig say nothing at all about
			# the readout it was added to look at.
			# ARMED, so the world is visible. A disarmed drone leaves the title
			# card up in the game scenes and the whole briefing panel up in the
			# drill, and a screenshot rig that can only photograph a menu cannot
			# check an instrument drawn over the world. Frozen and with physics
			# off it goes nowhere; `armed` is only a flag.
			(_drone as FlightController).arm()
			# Physics off FIRST, or the flight controller's own tick writes the
			# disarmed zeros straight back over the pose on the very next frame.
			_drone.set_physics_process(false)
			var motors: MotorModel = _drone.get_node("MotorModel") as MotorModel
			for i: int in motors.rotor_count:
				motors.set_command(i, DRIVES[i % DRIVES.size()])
			motors.step(1.0, (_drone as FlightController).config)
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
	# The lift is applied from the SPAWN height every pose, not accumulated, so
	# every shot in a run is taken from the same place.
	var at: Vector3 = _drone.global_position
	at.y = _spawn_y + _lift
	_drone.global_transform = Transform3D(basis, at)


func _capture() -> void:
	var shot: Array = SHOTS[_index]
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/hud_%s.png" % [_out, shot[0]]
	var err: int = image.save_png(path)
	print("[shot] %s roll %.0f pitch %.0f -> %s (%s)"
			% [shot[0], float(shot[1]), float(shot[2]), path,
			"ok" if err == OK else "FAILED %d" % err])
