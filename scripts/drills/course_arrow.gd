class_name CourseArrow
extends Node3D

## THE WAY OUT OF THE GATE YOU ARE FLYING, as a solid thing standing in the
## world rather than a shape painted on the glass.
##
## It replaces a 2D HUD arrow, and the human's report is the whole specification:
## *"the arrow is 2D, i was looking for something more 3D (doesnt have to be
## round, but i have to feel like it have some volume to it) and it should be
## animated in some way, so the motion itself would help to recognize the
## direction it points to. a 2D arrow cannot give a depth feel so it helps but
## not so much."*
##
## They are right about the mechanism, not just the look. A HUD arrow is drawn at
## a screen angle, so the only depth information it can carry is its LENGTH, and
## length is also how it encodes turn severity — one channel doing two jobs. A
## chain of wedges standing in the world gets depth for free from perspective:
## the far ones are smaller and closer together, which is the same cue the ground
## grid gives, and it needs no interpretation at all.
##
## THE ANIMATION IS THE DIRECTION. A static arrowhead is ambiguous at a glance
## from behind — a wedge pointing away and a wedge pointing back differ only by
## shading. A pulse that TRAVELS along the chain cannot be read backwards, which
## is why runway centreline lights and every road-tunnel chevron sequence work
## the same way.
##
## No collision on any of it. You fly straight through the chain and that is
## intended: it is a sight line, not an obstacle, and a course marker you can
## crash into would put the marker into `contacts`.

## How many wedges the chain carries, how far the first sits past the gate, and
## how far apart they are. Four is enough to read a direction from and few enough
## that they do not screen the gate behind them.
const CHEVRONS: int = 4
## The first chevron sits clear of the gate rather than inside it: an arm pair
## spans about 2.9 m and the opening is 3.3 m, so parked at the gate it screened
## the very frame the pilot is trying to judge.
const LEAD_M: float = 4.0
const SPACING_M: float = 4.5
## EACH MARK IS A CHEVRON, NOT A SOLID ARROWHEAD, and that is a decision two
## screenshots argued me into.
##
## A wedge with an apex pointing away is a fine arrow on paper and useless in
## flight: the pilot approaches from BEHIND it, and any convex solid seen down
## its own axis shows only its cross-section — a block. Two arms meeting at a
## forward point show a V opening toward the pilot from exactly that angle, which
## is why every road tunnel and runway in the world marks direction this way.
##
## `ARM` is one bar's (thickness, thickness, length); `ARM_DEG` is how far each
## is swung off the travel axis.
const ARM_DEG: float = 34.0
## HOW WIDE A CHEVRON IS ALLOWED TO BE, as a fraction of the gate's own opening.
##
## Sized in absolute metres it spanned 2.9 m against a 3.3 m gate — 88% of the
## hole — and the human flew it and said so: *"they are way too large for the
## gate."* Tying it to the opening also means a course with tighter gates gets
## proportionally smaller marks for free, which is the whole point of the gate
## size being data.
const SPAN_FRACTION: float = 0.42
## Arm thickness as a fraction of its length, so a smaller chevron stays a
## chevron rather than becoming a wire.
const ARM_THICKNESS: float = 0.24
## Opacity at full range, and the floor it fades to as the pilot arrives. It is
## translucent at its brightest on the human's call — *"we can make it less
## opaque"* — because a marker you cannot see the gate through is worse than one
## you have to look for.
const ALPHA_FAR: float = 0.52
const ALPHA_NEAR: float = 0.06
## The fade band, in metres to the gate the chain stands at. Their design:
## *"let the arrows fade away the closer i get to them, so they wont take up
## screen space too much and too opaque while im close to them."* The marker has
## done its whole job by then — you are committed to the gate and flying it.
const FADE_NEAR_M: float = 7.0
const FADE_FAR_M: float = 30.0
## Seconds for one pulse to travel the whole chain.
const PULSE_S: float = 0.9
## How far a wedge slides forward at the peak of the pulse. Small: the slide is
## a hint of flow, and a big one reads as the marker itself moving away.
const SLIDE_M: float = 0.5

var _wedges: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []
var _clock: float = 0.0
## How visible the chain currently is, 0 at the gate to 1 at range.
var _fade: float = 1.0


## Where wedge `index` sits along the arrow's own forward axis, in metres.
## Static so the check can hold the chain's shape without building one.
static func wedge_offset(index: int) -> float:
	return LEAD_M + float(index) * SPACING_M


## How brightly wedge `index` burns at time `t`, 0 to 1, as a wave travelling
## from the gate OUTWARD along the chain.
##
## `index` is subtracted from the phase rather than added, which is the whole
## direction cue: add it and the wave runs backwards, toward the pilot, and the
## marker means the opposite of what it should. Pure and static precisely so a
## check can catch that sign.
static func pulse(t: float, index: int) -> float:
	var phase: float = t / PULSE_S - float(index) / float(CHEVRONS)
	return 0.5 + 0.5 * cos(TAU * (phase - floorf(phase)))


## One arm's length for a gate of this half-width, so the chevron always spans
## `SPAN_FRACTION` of the opening. Static so the check can hold the relationship
## across gate sizes without building anything.
static func arm_length(gate_half_width: float) -> float:
	return gate_half_width * 2.0 * SPAN_FRACTION / (2.0 * sin(deg_to_rad(ARM_DEG)))


## How visible the chain is from `metres` away: full at range, nearly gone by the
## time the pilot arrives. Returns 0 to 1.
static func nearness_fade(metres: float) -> float:
	if metres >= FADE_FAR_M:
		return 1.0
	if metres <= FADE_NEAR_M:
		return 0.0
	return (metres - FADE_NEAR_M) / (FADE_FAR_M - FADE_NEAR_M)


## Build the chain for a gate of this opening. Called once by the runner, so the
## marks are sized to the course they are marking.
func build_for(gate_half: Vector2) -> void:
	var length: float = arm_length(gate_half.x)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length * ARM_THICKNESS, length * ARM_THICKNESS, length)
	for i: int in CHEVRONS:
		var wedge := Node3D.new()
		var material := StandardMaterial3D.new()
		# Cyan: the palette assigns cyan and blue to navigation (CLAUDE.md), which
		# is exactly what this is.
		# ALBEDO CARRIES THE FORM AND EMISSION ONLY MARKS IT. The first version
		# ran the emission up to 3.6 and every wedge photographed as a white blob:
		# emission is unshaded, so a surface that is mostly glow has no light and
		# dark sides and therefore no readable shape at all. The sun does the
		# modelling now and the pulse rides on top of it.
		material.albedo_color = Color(0.16, 0.52, 0.72, ALPHA_FAR)
		material.emission_enabled = true
		material.emission = Color(0.25, 0.75, 1.0)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# FOUR ARMS MEETING AT A FORWARD POINT — two swung sideways, two swung up
		# and down. Two arms alone make a flat V, and a flat V lies in the
		# horizontal plane, which is edge-on to a pilot approaching level from
		# behind: exactly the commonest approach on this course. Adding the
		# vertical pair means there is a V to read from any angle you can arrive
		# at, and the four together converge to a point like the corner of a
		# pyramid, which is where the volume comes from.
		for swing: float in [-deg_to_rad(ARM_DEG), deg_to_rad(ARM_DEG)]:
			var sideways := MeshInstance3D.new()
			sideways.mesh = mesh
			sideways.material_override = material
			sideways.rotation.y = swing
			# A BoxMesh runs along its own Z, so after the turn the arm's axis is
			# (sin, 0, cos) — outward and BACKWARD from the apex at the origin.
			sideways.position = Vector3(sin(swing), 0.0, cos(swing)) * (length * 0.5)
			wedge.add_child(sideways)
			var upright := MeshInstance3D.new()
			upright.mesh = mesh
			upright.material_override = material
			upright.rotation.x = swing
			upright.position = Vector3(0.0, -sin(swing), cos(swing)) * (length * 0.5)
			wedge.add_child(upright)
		_materials.append(material)
		_wedges.append(wedge)
		add_child(wedge)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	for i: int in _wedges.size():
		var lit: float = pulse(_clock, i)
		_wedges[i].position = Vector3(0.0, 0.0,
				-(wedge_offset(i) + lit * SLIDE_M))
		# The pulse rides on BOTH channels now. Emission alone was enough while
		# the chain was opaque; once it fades toward the gate, a wedge whose glow
		# is pulsing but whose body is barely there reads as a flicker, so the
		# body follows the same wave and the mark stays one object.
		_materials[i].emission_energy_multiplier = (0.15 + lit * 1.45) * _fade
		var albedo: Color = _materials[i].albedo_color
		albedo.a = lerpf(ALPHA_NEAR, ALPHA_FAR, _fade)
		_materials[i].albedo_color = albedo


## Stand the chain at `at`, pointing along `direction`, seen from `pilot`.
## A zero or vertical direction hides it rather than guessing an orientation.
func aim(at: Vector3, direction: Vector3, pilot: Vector3) -> void:
	if direction.length_squared() < 0.000001:
		visible = false
		return
	visible = true
	_fade = nearness_fade(at.distance_to(pilot))
	global_position = at
	var forward: Vector3 = direction.normalized()
	# `looking_at` fails when the direction is parallel to the up vector, which a
	# course leg never is today and a vertical gate-to-gate hop would be.
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 \
			else Vector3.FORWARD
	look_at(at + forward, up)
