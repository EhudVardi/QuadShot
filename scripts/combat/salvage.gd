class_name Salvage
extends Node3D

## A dropped re-arm pickup (GAMEPLAY-DESIGN Iteration 10, R.q6 — the user's
## call over my "gates only").
##
## Their reason for it is the better argument and it is worth keeping: *"it
## would give the player a reason to take out the infinite turrets."* The
## arena's own turrets respawn on a 20 s cycle and are worth points nobody
## needs, so until now they were scenery you flew around. A drop makes killing
## one an ammunition decision, which is the first time that respawn timer has
## meant anything.
##
## Collected by flying INTO it — same verb as the gates, no landing, no
## hovering. It drifts down and expires, so a kill you do not go and take is a
## kill you did not finish; that is the risk-priced flying P2.7 keeps asking
## for, arriving free with the drop rather than as a new mechanic.

## Kind -> colour, matching the gate that fills the same magazine so the two
## read as one supply language.
const PALETTE: Dictionary = {
	&"flak": Color(1.0, 0.62, 0.12),
	&"missile": Color(0.72, 0.35, 1.0),
}
## Fraction of a magazine a single pickup is worth. Small on purpose: a drop is
## a top-up that rewards aggression, not a substitute for routing to a gate.
##
## RAISED with the wave-clear re-arm's removal (v1.93): gates and kills are now
## the ONLY ways to put rounds back, so a drop has to be worth breaking off for.
const REFILL_FRACTION: float = 0.34
const LIFETIME_S: float = 18.0
## Generous, and deliberately so. The user's report was "they are easy to miss",
## and half of missing one is flying near it without tripping it — which reads
## as the pickup being broken rather than as the pass being wide.
const PICKUP_RADIUS: float = 3.2
## Yes, it falls: this is the answer to "do they fall slowly to the ground? or
## am i imagining?" It does, at this rate, from wherever the body died down to
## REST_HEIGHT, where it hangs for the rest of its life.
const FALL_SPEED: float = 2.2
const SPIN_S: float = 1.8
## Height above whatever it lands on, so a drop never sinks into the ground.
const REST_HEIGHT: float = 1.2
## The core cube's edge. Bigger than the 0.36 it shipped at, because at FPV
## speeds a 36 cm box against a neon grid is genuinely invisible past 20 m.
const CORE_SIZE: float = 0.55
## A column of light standing over the drop, which is what actually makes it
## findable: the cube says WHAT it is, the beacon says WHERE it is.
const BEACON_HEIGHT: float = 9.0
const BEACON_RADIUS: float = 0.13

@export var kind: StringName = &"flak"


## Roll for a drop and place it. EVERY call site comes through here, so the
## odds and the flak/missile split live in one place instead of drifting apart
## between the wave director and main's arena turrets.
static func maybe_drop(parent: Node, at: Vector3, chance: float) -> void:
	if parent == null or randf() > chance:
		return
	var drop := Salvage.new()
	# Flak-weighted: the pod burns its magazine several times faster than the
	# rack does, so an even split would starve the weapon that needs it most.
	drop.kind = &"flak" if randf() < 0.7 else &"missile"
	parent.add_child(drop)
	drop.global_position = at

var _age: float = 0.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _beacon_material: StandardMaterial3D
var _player: FlightController


func _ready() -> void:
	add_to_group(&"salvage")
	var color: Color = PALETTE.get(kind, Color.WHITE)
	_material = StandardMaterial3D.new()
	_material.albedo_color = color.darkened(0.5)
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 2.6
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CORE_SIZE
	box.material = _material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	add_child(_mesh)

	# The beacon. Unshaded and additive so it reads as light rather than as a
	# thin post, and it does NOT spin with the cube — a still column beside a
	# turning core is easier to pick out of a moving frame than either alone.
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beacon_material.albedo_color = Color(color.r, color.g, color.b, 0.30)
	_beacon_material.emission_enabled = true
	_beacon_material.emission = color
	_beacon_material.emission_energy_multiplier = 2.2
	var column := CylinderMesh.new()
	column.top_radius = BEACON_RADIUS
	column.bottom_radius = BEACON_RADIUS
	column.height = BEACON_HEIGHT
	column.material = _beacon_material
	var beacon := MeshInstance3D.new()
	beacon.mesh = column
	beacon.position.y = BEACON_HEIGHT * 0.5
	add_child(beacon)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME_S:
		queue_free()
		return
	_mesh.rotate_y(TAU / SPIN_S * delta)
	if global_position.y > REST_HEIGHT:
		global_position.y = maxf(global_position.y - FALL_SPEED * delta, REST_HEIGHT)
	# Blink out its last two seconds. A pickup that vanishes without warning
	# reads as a bug; one that flickers first reads as a deadline.
	var left: float = LIFETIME_S - _age
	var energy: float = 2.6 if left > 2.0 else 0.6 + 2.0 * absf(sin(left * 9.0))
	_material.emission_energy_multiplier = energy
	# The beacon pulses gently the whole time rather than only at the end: a
	# static glow blends into a neon skyline, a moving one does not.
	_beacon_material.emission_energy_multiplier = energy \
			* (0.75 + 0.25 * sin(_age * 4.0))
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as FlightController
	if _player == null or not _player.visible:
		return
	if global_position.distance_to(_player.global_position) <= PICKUP_RADIUS:
		_collect()


## Only takes what it can give. A pickup consumed by a full magazine is a
## pickup the pilot watched disappear for nothing, and they will read that as
## the drop being broken rather than as their own timing.
func _collect() -> void:
	var filled: bool = false
	for launcher: Node in get_tree().get_nodes_in_group(&"magazines"):
		if launcher.get(&"ammo_kind") != kind or bool(launcher.call(&"unlimited")):
			continue
		if int(launcher.get(&"rounds")) >= int(launcher.call(&"magazine")):
			continue
		launcher.call(&"rearm", REFILL_FRACTION)
		filled = true
	if not filled:
		return
	SoundBank.play_at(&"lock", global_position, -6.0, 0.02)
	queue_free()
