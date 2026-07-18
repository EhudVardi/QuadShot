extends SceneTree

## Repair-pad regression (GAMEPLAY-DESIGN P2.6 / D5): boots main, damages the
## drone's engines, parks it in a low hover over the pad, and asserts the pad
## nurses the motors (and hull) back up — the recovery half of the wounded-quad
## loop. A fly-by (too fast / too high) must NOT repair.
##
## Run: <godot> --headless -s scripts/tests/repair_check.gd --path .

const MAX_SECONDS: float = 6.0

var _main: Node3D
var _drone: FlightController
var _pad: RepairPad
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _start_health: float
var _off_pad_health: float


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_main)
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	physics_frame.connect(_on_frame)


func _on_frame() -> void:
	_ticks += 1
	if _ticks > _ticks_max:
		_fail("timed out in phase %d" % _phase)
		return
	match _phase:
		0:
			if not _main.is_node_ready():
				return
			_drone = _main.get_node("Drone") as FlightController
			_pad = get_first_node_in_group(&"repair_pads") as RepairPad
			if _pad == null:
				_fail("no repair pad in scene")
				return
			_drone.arm()
			# Park a still hover OFF the pad (freeze so it holds for the test).
			_drone.global_position = _pad.global_position + Vector3(40, 4, 0)
			_drone.freeze = true
			_phase = 1
			_ticks = 0
		1:
			# Let the auto-started run finish its field-repair, THEN break an
			# engine — otherwise _start_run heals it back before we measure.
			if _ticks > 90:
				(_drone.get_node("MotorModel") as MotorModel).damage_motor(0, 0.6)
				_start_health = _drone.motor_health(0)
				_phase = 2
				_ticks = 0
		2:
			# ~0.5 s off the pad: motors must NOT recover.
			if _ticks > 120:
				_off_pad_health = _drone.motor_health(0)
				if _off_pad_health > _start_health + 0.02:
					_fail("motors repaired while OFF the pad")
					return
				# Now park in a low hover over the pad.
				_drone.global_position = _pad.global_position + Vector3(0, 3, 0)
				_phase = 3
				_ticks = 0
		3:
			# ~2 s hovering on the pad: motors must climb back toward full.
			if _ticks > 480:
				var repaired: float = _drone.motor_health(0)
				print("[repair_check] motor0: broke to %.2f, off-pad %.2f, on-pad %.2f"
						% [_start_health, _off_pad_health, repaired])
				if repaired > _start_health + 0.3:
					print("[repair_check] PASS")
					quit(0)
				else:
					_fail("pad did not repair engines (%.2f -> %.2f)"
							% [_start_health, repaired])


func _fail(msg: String) -> void:
	print("[repair_check] FAIL: %s" % msg)
	quit(1)
