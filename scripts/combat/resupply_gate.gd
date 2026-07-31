class_name ResupplyGate
extends Node3D

## Fly-through re-arm gate (GAMEPLAY-DESIGN Iteration 10, R3/R4/R.q4).
##
## A GATE, NOT A PAD, and that was decided by playtest before this existed: D5
## turned the repair pad into the repair gate because "holding station on a
## wounded quad under fire is a death sentence — you recover by flying through,
## keeping your speed and your life". The user re-derived the same shape
## unprompted when asking for these ("flying through the ... gates"). Resupply
## inherits it whole: you thread it, you never park on it.
##
## FINITE CHARGES (R.q4). A gate that refilled forever would make a sortie's
## gate COUNT meaningless, which is the difficulty knob P2.6 has been promising
## since Iteration 5. Each pass spends one charge; a spent gate goes dark and
## stays in the world as a used-up landmark rather than vanishing, because a
## thing that disappears teaches nothing about where you have already been.
##
## It labels itself with the menu tower's own glyphs (the user's ask: "i want
## the health/ammo gates to use the text effect on them like the menu room
## gates"), which is why GlowText3D grew digits the same day — the label
## carries a remaining-charge count and a font of letters could not render it.

signal resupplied(kind: StringName)

## Kind -> the palette this gate wears. Green is already the repair gate and
## blue is already the exit, so the two new ones take colours nothing else
## claims (CLAUDE.md's emissive palette by role).
const PALETTE: Dictionary = {
	&"flak": Color(1.0, 0.62, 0.12),
	&"missile": Color(0.72, 0.35, 1.0),
}
const LABEL: Dictionary = {&"flak": "FLAK", &"missile": "MSL"}

## Which magazine this gate fills. Matched against `ammo_kind` on every node in
## the `magazines` group, so a gate never needs to know what a drone is made of.
@export var kind: StringName = &"flak"
## Passes before it is spent (R.q4).
@export var charges: int = 2
## Fraction of a full magazine per pass. 1.0 = a whole reload.
@export var refill_fraction: float = 1.0
## Re-arm delay so a gate cannot be spam-camped back and forth.
@export var cooldown: float = 1.2
## Ring radius, m. Deliberately smaller than the exit gate's opening: threading
## it IS the challenge the user asked for ("more challanges to get more
## resources"), and it is the flight model advertising itself.
@export var radius: float = 1.9

var _cool: float = 0.0
var _ring: MeshInstance3D
var _label: GlowText3D
var _area: Area3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"resupply_gates")
	_build()
	_refresh()


func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(_cool - delta, 0.0)
	# Face the pilot, so the label is readable on any approach. A sign you have
	# to circle to read is a sign you read after you needed it.
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and _label != null:
		_label.global_rotation.y = atan2(
				camera.global_position.x - global_position.x,
				camera.global_position.z - global_position.z)


func spent() -> bool:
	return charges <= 0


func _build() -> void:
	var color: Color = PALETTE.get(kind, Color(1.0, 1.0, 1.0))
	_material = StandardMaterial3D.new()
	_material.albedo_color = color.darkened(0.6)
	_material.emission_enabled = true
	_material.emission = color
	# Above the 1.0 bloom threshold so the ring is the part that glows.
	_material.emission_energy_multiplier = 2.4
	var ring := TorusMesh.new()
	ring.inner_radius = radius
	ring.outer_radius = radius + 0.16
	ring.material = _material
	_ring = MeshInstance3D.new()
	_ring.mesh = ring
	# A torus lies flat by default; stand it up so it is a doorway, not a hoop
	# on the floor.
	_ring.rotation_degrees.x = 90.0
	add_child(_ring)

	_label = GlowText3D.new()
	_label.pixel_size = 0.075
	_label.glow_color = color
	_label.position.y = radius + 0.75
	add_child(_label)

	_area = Area3D.new()
	_area.monitoring = true
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 0.9
	shape.shape = cylinder
	# The opening faces the ring, so the trigger volume is the hole and not a
	# puck lying in it.
	shape.rotation_degrees.x = 90.0
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


## The label says what it gives and how many passes are left, because a finite
## gate the pilot cannot count is a finite gate the pilot will fly to twice.
func _refresh() -> void:
	if _label == null:
		return
	_label.text = "%s\n%d" % [LABEL.get(kind, "AMMO"), maxi(charges, 0)] \
			if not spent() else "%s\nSPENT" % LABEL.get(kind, "AMMO")
	# Partially transparent, per the ask, and dimmer once there is nothing left
	# to take.
	_label.glow_energy = 1.2 if spent() else 3.2
	if _material != null:
		_material.emission_energy_multiplier = 0.35 if spent() else 2.4
	if _ring != null:
		_ring.transparency = 0.55 if spent() else 0.25


func _on_body_entered(body: Node3D) -> void:
	if _cool > 0.0 or spent() or not (body is FlightController):
		return
	var filled: bool = false
	for launcher: Node in get_tree().get_nodes_in_group(&"magazines"):
		if launcher.get(&"ammo_kind") != kind or bool(launcher.call(&"unlimited")):
			continue
		# Already full is NOT a pass: a gate must never eat a charge for
		# nothing, or the pilot who routed carefully is punished for it.
		if int(launcher.get(&"rounds")) >= int(launcher.call(&"magazine")):
			continue
		launcher.call(&"rearm", refill_fraction)
		filled = true
	if not filled:
		return
	charges -= 1
	_cool = cooldown
	_refresh()
	SoundBank.play_at(&"lock", global_position, -4.0, 0.05)
	resupplied.emit(kind)
