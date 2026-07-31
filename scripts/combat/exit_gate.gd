class_name ExitGate
extends StaticBody3D

## Sortie exit gate (roadmap M4): invisible until the sortie's waves are
## cleared, then lights up; flying through it triggers the upgrade draft.
##
## SOLID AS OF v1.93, and that reverses a deliberate earlier choice. It used to
## be a "magic gate, not an obstacle" — non-solid, so you could pass through the
## frame as easily as the hole. The user's call after three rounds: gates
## "should always be collidable". They are right, and the reason is that a
## fly-through reward with no way to miss it is not a piece of flying; the ring
## is what makes taking the gate a thing you did.
##
## The ring's collision is a FAN OF BOXES rather than a trimesh of the torus.
## A concave shape for a body this simple is a bad trade, and the segments are
## exact enough that nothing can slip between two of them at any speed the
## drone reaches.

signal entered

## Segments in the collision ring. 16 leaves a chord sag of about 2% of the
## radius — well under the frame's own thickness, so the collision never sits
## inside the visible ring where it would read as clipping.
const RING_SEGMENTS: int = 16
const RING_RADIUS: float = 3.0
const RING_THICKNESS: float = 0.3

@onready var _area: Area3D = $Area

var active: bool = false

var _segments: Array[CollisionShape3D] = []


func _ready() -> void:
	_build_ring_collision()
	visible = false
	_area.monitoring = false
	_area.body_entered.connect(_on_body_entered)
	_set_solid(false)


func activate() -> void:
	active = true
	visible = true
	_area.set_deferred(&"monitoring", true)
	_set_solid(true)


func deactivate() -> void:
	active = false
	visible = false
	_area.set_deferred(&"monitoring", false)
	# An invisible gate must not be an invisible wall. The whole reason the
	# frame is solid is that you can see it.
	_set_solid(false)


func _build_ring_collision() -> void:
	var chord: float = TAU * RING_RADIUS / float(RING_SEGMENTS)
	for i: int in RING_SEGMENTS:
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		var box := BoxShape3D.new()
		# Slightly longer than the chord so neighbours overlap: a seam between
		# two collision boxes is exactly where a fast body squeezes through.
		box.size = Vector3(chord * 1.15, RING_THICKNESS, RING_THICKNESS)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(cos(angle) * RING_RADIUS,
				sin(angle) * RING_RADIUS, 0.0)
		# Lay each segment along the ring's tangent at its own angle.
		shape.rotation.z = angle + PI * 0.5
		add_child(shape)
		_segments.append(shape)


func _set_solid(solid: bool) -> void:
	for shape: CollisionShape3D in _segments:
		shape.set_deferred(&"disabled", not solid)


func _on_body_entered(body: Node3D) -> void:
	if active and body is FlightController:
		deactivate()
		entered.emit()
