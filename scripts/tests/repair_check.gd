extends SceneTree

## Repair-gate regression (GAMEPLAY-DESIGN P2.6 / D5): boots main, breaks the
## drone's engines, then drives it THROUGH the green repair gate and asserts the
## engines come back — the fly-through recovery half of the wounded-quad loop.
##
## Run: <godot> --headless -s scripts/tests/repair_check.gd --path .

const MAX_SECONDS: float = 6.0

var _main: Node3D
var _drone: FlightController
var _gate: RepairGate
var _phase: int = 0
var _ticks: int = 0
var _ticks_max: int
var _broken_health: float


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
			_gate = get_first_node_in_group(&"repair_gates") as RepairGate
			if _gate == null:
				_fail("no repair gate in scene")
				return
			# Never arm: no auto-run means no field-repair to undo our damage.
			(_drone.get_node("MotorModel") as MotorModel).damage_motor(1, 0.7)
			_broken_health = _drone.motor_health(1)
			if _broken_health > 0.5:
				_fail("could not break the test engine")
				return
			# Coast the drone THROUGH the gate opening (Area needs real motion).
			_drone.global_position = _gate.global_position + Vector3(0, 0, 7)
			_drone.linear_velocity = Vector3(0, 0, -13)
			_phase = 1
			_ticks = 0
		1:
			var repaired: float = _drone.motor_health(1)
			if repaired > 0.98:
				print("[repair_check] engine1: broke to %.2f, flew gate -> %.2f"
						% [_broken_health, repaired])
				print("[repair_check] PASS")
				quit(0)
			elif _ticks > 180:
				_fail("gate did not restore engines (%.2f -> %.2f)"
						% [_broken_health, repaired])


func _fail(msg: String) -> void:
	print("[repair_check] FAIL: %s" % msg)
	quit(1)
