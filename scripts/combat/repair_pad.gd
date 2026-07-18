class_name RepairPad
extends Node3D

## Forward repair pad (GAMEPLAY-DESIGN P2.6 / D5): the recovery half of the
## wounded-quad loop. Hold a precise, low hover inside the pad's zone and it
## nurses your engines (and hull) back toward full — landing skill under fire
## turned into gameplay, and the answer to "flying broken engines needs a
## remediation challenge." Self-contained: it finds the player, repairs while
## the hover holds, and glows to show it. A hard node makes pads scarce (P2.6);
## the dev room gets one to fly the loop.

signal repairing(active: bool, worst_motor: float)

## Horizontal capture radius — stay within this of the pad center.
@export var radius: float = 5.0
## Repair only below this height above the pad (you must come DOWN to it).
@export var height: float = 10.0
## Near-stationary requirement — a precise hover, not a fly-by (the skill).
@export var hover_speed_max: float = 5.0
## Engine capability restored per second while hovering (0..1 scale).
@export var motor_repair_rate: float = 0.30
## Hull restored per second while hovering.
@export var hull_repair_rate: float = 12.0

@onready var _ring: MeshInstance3D = $Ring
@onready var _beam: MeshInstance3D = $Beam

var _drone: FlightController
var _drone_health: Health
var _active: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	add_to_group(&"repair_pads")
	# Own the ring material so this pad's glow animates independently.
	if _ring.material_override != null:
		_ring.material_override = _ring.material_override.duplicate()
	_beam.visible = false


func _physics_process(delta: float) -> void:
	if _drone == null:
		_drone = get_tree().get_first_node_in_group(&"player") as FlightController
		if _drone == null:
			return
		_drone_health = _drone.get_node("Health") as Health
	var active: bool = _can_repair()
	if active:
		_drone.repair_motors_by(motor_repair_rate * delta)
		if _drone_health != null and _drone_health.alive:
			_drone_health.heal(hull_repair_rate * delta)
	if active != _active:
		_active = active
		_beam.visible = active
		if active:
			SoundBank.play_at(&"lock", global_position, -8.0, 0.25)
	repairing.emit(active, _drone.worst_motor_health())


func _process(delta: float) -> void:
	# Pulse the ring; brighter and faster while actively repairing.
	_pulse += delta * (7.0 if _active else 2.0)
	var base: float = 2.2 if _active else 0.7
	var material: StandardMaterial3D = _ring.material_override as StandardMaterial3D
	if material != null:
		material.emission_energy_multiplier = base + 0.6 * sin(_pulse)


func _can_repair() -> bool:
	if _drone == null or not _drone.armed or not _drone.visible:
		return false
	var offset: Vector3 = _drone.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius:
		return false
	if offset.y < -1.0 or offset.y > height:
		return false
	if _drone.linear_velocity.length() > hover_speed_max:
		return false
	return true
