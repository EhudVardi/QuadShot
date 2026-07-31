class_name ResupplyGate
extends StaticBody3D

## Fly-through re-arm gate (GAMEPLAY-DESIGN Iteration 10, R3/R4/R.q4).
##
## A GATE, NOT A PAD, and that was decided by playtest before this existed: D5
## turned the repair pad into the repair gate because "holding station on a
## wounded quad under fire is a death sentence — you recover by flying through,
## keeping your speed and your life". The user re-derived the same shape
## unprompted when asking for these. Resupply inherits it whole: you thread it,
## you never park on it.
##
## IT IS A SOLID FRAME, not a hoop you can pass through anywhere (v1.93, the
## user's call after three rounds: "they should be like the small rectangle blue
## gates we already have. they should be collidable just like those small
## gates"). That is the same body the course gates in `environment/gate.tscn`
## are — four bars, four collision shapes — and it is what turns a resupply from
## a pickup you drift over into a line you have to actually fly. The opening is
## the only way through, and clipping a bar costs you.
##
## FINITE CHARGES (R.q4). A gate that refilled forever would make a sortie's
## gate COUNT meaningless, which is the difficulty knob P2.6 has been promising
## since Iteration 5. Each pass spends one charge; a spent gate goes dark and
## stays in the world as a used-up landmark rather than vanishing, because a
## thing that disappears teaches nothing about where you have already been.
##
## It labels itself with the menu tower's own glyphs (the user's ask: "i want
## the health/ammo gates to use the text effect on them like the menu room
## gates"), which is why GlowText3D grew digits — the label carries a
## remaining-charge count and a font of letters could not render it. The label
## hangs INSIDE the opening (v1.93), which reads as a sign in a doorway rather
## than a placard on a pole, and doubles as the thing you aim at.

signal resupplied(kind: StringName)

## Kind -> the palette this gate wears. Green is already the repair gate and
## blue is already navigation, so the two new ones take colours nothing else
## claims (CLAUDE.md's emissive palette by role).
const PALETTE: Dictionary = {
	&"flak": Color(1.0, 0.62, 0.12),
	&"missile": Color(0.72, 0.35, 1.0),
}
const LABEL: Dictionary = {&"flak": "FLAK", &"missile": "MSL"}

## Frame geometry. The opening is deliberately close to the course gates' 3.0 m
## — big enough to thread at speed, small enough that threading it is a thing
## you did rather than a thing that happened.
const BAR_THICKNESS: float = 0.3
const OPENING: float = 3.4

## Which magazine this gate fills. Matched against `ammo_kind` on every node in
## the `magazines` group, so a gate never needs to know what a drone is made of.
@export var kind: StringName = &"flak"
## Passes before it is spent (R.q4).
@export var charges: int = 2
## Fraction of a full magazine per pass. 1.0 = a whole reload.
@export var refill_fraction: float = 1.0
## Re-arm delay so a gate cannot be spam-camped back and forth.
@export var cooldown: float = 1.2

var _cool: float = 0.0
var _labels: Array[GlowText3D] = []
var _bars: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"resupply_gates")
	_build()
	_refresh()


func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(_cool - delta, 0.0)
	# Snapped to a face rather than freely billboarded: the label has to stay
	# flush inside the frame, and a sign that swivels in a doorway reads as a
	# loose object rather than as part of the gate.
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _labels.is_empty():
		return
	var behind: bool = global_basis.z.dot(camera.global_position - global_position) < 0.0
	_labels[0].rotation.y = PI if behind else 0.0


func spent() -> bool:
	return charges <= 0


## Half the outer width, for placement checks that need to know how much room
## this thing takes up.
func extent() -> float:
	return OPENING * 0.5 + BAR_THICKNESS


func _build() -> void:
	var color: Color = PALETTE.get(kind, Color(1.0, 1.0, 1.0))
	_material = StandardMaterial3D.new()
	_material.albedo_color = color.darkened(0.55)
	_material.emission_enabled = true
	_material.emission = color
	# Above the 1.0 bloom threshold so the frame is the part that glows.
	_material.emission_energy_multiplier = 2.2
	var span: float = OPENING + BAR_THICKNESS
	var offset: float = (OPENING + BAR_THICKNESS) * 0.5
	_add_bar(Vector3(span, BAR_THICKNESS, BAR_THICKNESS), Vector3(0.0, offset, 0.0))
	_add_bar(Vector3(span, BAR_THICKNESS, BAR_THICKNESS), Vector3(0.0, -offset, 0.0))
	_add_bar(Vector3(BAR_THICKNESS, OPENING, BAR_THICKNESS), Vector3(-offset, 0.0, 0.0))
	_add_bar(Vector3(BAR_THICKNESS, OPENING, BAR_THICKNESS), Vector3(offset, 0.0, 0.0))

	# ONE label, flipped to whichever face the pilot is on (_process). Two
	# labels — one per face — was the first attempt and it renders as garbage:
	# the glyphs are emissive cubes with no backface culling, so from behind you
	# read the far label MIRRORED, superimposed on the near one. A sign you have
	# to circle to read is a sign you read too late, so it flips instead.
	var label := GlowText3D.new()
	label.pixel_size = 0.09
	label.glow_color = color
	add_child(label)
	_labels.append(label)

	var area := Area3D.new()
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The trigger volume is the HOLE — slightly inset from the bars, and thin,
	# so it can only be tripped by actually going through.
	box.size = Vector3(OPENING - 0.2, OPENING - 0.2, 0.7)
	shape.shape = box
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _add_bar(size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)
	_bars.append(instance)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = at
	add_child(collision)


## The label says what it gives and how many passes are left, because a finite
## gate the pilot cannot count is a finite gate the pilot will fly to twice.
func _refresh() -> void:
	var text: String = "%s\n%d" % [LABEL.get(kind, "AMMO"), maxi(charges, 0)] \
			if not spent() else "%s\nOUT" % LABEL.get(kind, "AMMO")
	for label: GlowText3D in _labels:
		label.text = text
		# Dimmer once there is nothing left to take, but never invisible: the
		# frame is still something you can fly into.
		label.glow_energy = 0.9 if spent() else 3.0
	if _material != null:
		_material.emission_energy_multiplier = 0.4 if spent() else 2.2


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
