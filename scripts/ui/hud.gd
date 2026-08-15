class_name GameHud
extends CanvasLayer

## Minimal in-flight HUD (roadmap M1–M3): reticle, score/combo, health,
## wave status, kill feed, damage-direction flashes, death banner and
## end-of-run summary. Function over beauty; every control ignores the
## mouse so the tuning overlay stays fully clickable.

const KILL_FEED_MAX: int = 5
const KILL_FEED_SECONDS: float = 3.0

@onready var _score_label: Label = $ScoreLabel
@onready var _combo_label: Label = $ComboLabel
@onready var _wave_label: Label = $WaveLabel
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _heat_bar: ProgressBar = $HeatBar
@onready var _ammo_label: Label = $AmmoLabel
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _death_label: Label = $DeathLabel
@onready var _kill_feed: VBoxContainer = $KillFeed
@onready var _summary: PanelContainer = $Summary
@onready var _summary_label: Label = $Summary/SummaryLabel
@onready var _title: VBoxContainer = $Title
@onready var _title_bests: Label = $Title/TitleBests

## Thin edge bars for directional damage, built in code (side -> ColorRect).
var _edges: Dictionary = {}
var _lock_indicator: LockIndicator
var _gate_marker: GateMarker
var _reticle: Reticle
var _stick_display: StickDisplay
var _pause_label: Label
var _motor_status: ComponentStatus
var _video_glitch: ColorRect
var _repair_label: Label


## Per-component capability pips (GAMEPLAY-DESIGN Iteration 7 / D4, extended over
## the component registry in Iteration 17 / E.q5): the legible half of the wound —
## the sticks tell you first. Green = healthy, red = failed; a damaged corner is
## exactly the one the drone now fights toward.
##
## IT DRAWS WHAT THE REGISTRY SAYS IS BUILT, and knows nothing about what an
## airframe is made of. E.q5's answer was *"extend the existing widget, reuse the
## existing channels, and build no new panel"*, and the user's ruling on the
## enemy side was that per-body damage visuals cost the vastness — so this is the
## player's HUD and nothing else.
##
## THE LAYOUT IS DERIVED FROM THE ROTOR MOUNTS, not authored, and that is a bug
## fix rather than a flourish. It was `for i in 4` against a hard-coded 2x2 offset
## table, so a six-rotor frame (E.q1) would have drawn four pips and silently
## dropped two rotors — the fifth instance of *a constant that was correct for one
## airframe is a bug on a size ladder*, sitting in the HUD after all. Projecting
## each rotor's own body-space position reproduces the quad's pixel layout exactly
## and gives a hexa a hexagon for free.
class ComponentStatus:
	extends Control

	## Everything the airframe is built from, in AirframeComponents.TABLE order.
	var parts: Array[AirframeComponents.Part] = []

	## Sharp green->yellow->red ramp: a motor at 0.6 must read as clearly hurt,
	## not near-green (the old lerp's flaw).
	static func ramp(h: float) -> Color:
		var green := Color(0.3, 1.0, 0.4)
		var yellow := Color(1.0, 0.85, 0.2)
		var red := Color(1.0, 0.2, 0.15)
		if h >= 0.6:
			return yellow.lerp(green, (h - 0.6) / 0.4)
		return red.lerp(yellow, h / 0.6)

	## Radius the WIDEST ROTOR projects to. Everything else on the airframe is
	## placed by the same scale, so the picture keeps its proportions.
	const RING: float = 46.0
	const ROTOR_R: float = 15.0
	const PLATE := Vector2(168.0, 150.0)
	## Anything this far from the hub is pulled back in. Only reachable by a lens
	## mounted further forward than the rotors, which is the Condor and the Roc.
	const EDGE: float = 62.0

	func _draw() -> void:
		if parts.is_empty():
			return
		# Bottom-left, grouped with the input indicators (v1.45). `size` is the
		# reference frame (full-rect control under canvas_items stretch), so this
		# rides the window like the stick display does.
		var origin := Vector2(30.0, size.y - PLATE.y - 40.0)
		var centre := origin + PLATE * 0.5
		draw_string(get_theme_default_font(), origin + Vector2(0.0, -6.0),
				"AIRFRAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(1, 1, 1, 0.55))

		var points: Dictionary = layout(parts, centre)
		var rotors: Array[AirframeComponents.Part] = []
		for part: AirframeComponents.Part in parts:
			if part.kind == &"rotor":
				rotors.append(part)

		# THE AIRFRAME ITSELF, drawn before anything mounted on it: arms out to
		# every rotor, then the hull over the top. This is the half the human
		# asked for that the pip block never had — *"a projection of the craft
		# from top to bottom"* — and it is what makes a lit gauge mean "that
		# corner, over there" rather than "the third one in the list".
		for part: AirframeComponents.Part in rotors:
			draw_line(centre, points[part.id], Color(0.55, 0.62, 0.7, 0.5), 3.0)
		var hull_half := Vector2(13.0, 18.0)
		draw_rect(Rect2(centre - hull_half, hull_half * 2.0),
				Color(0.16, 0.19, 0.24, 0.85))
		draw_rect(Rect2(centre - hull_half, hull_half * 2.0),
				Color(0.55, 0.62, 0.7, 0.55), false, 1.0)
		# The nose, so "up is forward" is stated by the picture and not only by
		# the fact that the lens happens to be drawn at the top.
		draw_line(centre + Vector2(0.0, -hull_half.y),
				centre + Vector2(0.0, -hull_half.y - 7.0),
				Color(0.55, 0.62, 0.7, 0.55), 2.0)

		var ghosts: Array[AirframeComponents.Part] = []
		for part: AirframeComponents.Part in parts:
			if not points.has(part.id):
				continue
			var at: Vector2 = points[part.id]
			if part.kind == &"rotor":
				_rotor(at, part)
			elif part.kind == &"vtx":
				_transmitter(at, part)
			elif part.built:
				_block(at, part)
			else:
				# NOT A GAUGE, because nothing can move it yet. Four rows of the
				# registry are description-only, and drawing them with a reading
				# would be inventing one — so they get a dim mark that says the
				# equipment is aboard and where, and no number at all.
				ghosts.append(part)

		# GHOSTS LAST, AND SPREAD SIDEWAYS. Two collisions make this necessary and
		# both come from the registry being honest rather than from a bug. A prop
		# sits at its rotor's exact mount, so it would draw on top of the disc —
		# it is skipped, and when props become damageable they belong AS a ring on
		# the rotor rather than as a second mark beside it. And every singleton in
		# MOUNTS is on the centreline, so power, gyro, the gun and the magazine
		# would stack on one another and on the lens.
		#
		# The lateral offset is PRESENTATIONAL and the vertical position is not:
		# fore-and-aft is the axis that carries the information (the pack is aft,
		# the gun is forward), and that is the one kept true.
		var index: int = 0
		for part: AirframeComponents.Part in ghosts:
			if _shares_mount(part, points):
				continue
			var side: float = -1.0 if index % 2 == 0 else 1.0
			_ghost(Vector2(centre.x + side * 30.0, points[part.id].y), part, side)
			index += 1

	## Does this part sit exactly where something already drawn sits? True for
	## every prop, which shares its rotor's mount by design.
	static func _shares_mount(part: AirframeComponents.Part,
			points: Dictionary) -> bool:
		var at: Vector2 = points[part.id]
		for id: StringName in points:
			if id == part.id:
				continue
			if String(id).begins_with("rotor") and points[id].distance_to(at) < 1.0:
				return true
		return false

	## WHERE EVERY PART GOES, keyed by `Part.id`.
	##
	## STATIC AND SEPARATE FROM `_draw` SO IT CAN BE MEASURED — a layout buried in
	## a draw call can only be checked by looking at it.
	##
	## NORMALISED ON THE ROTOR SPAN, not on the widest part of the whole airframe.
	## The rotors are what you read at a glance, so they keep the ring at a fixed
	## size on every frame and anything reaching past them is clamped to the plate.
	##
	## Scaling to fit EVERYTHING is the obvious alternative and it makes the ring
	## frame-dependent: measured, the Condor's and the Roc's would shrink by 1.7%,
	## because their lenses sit fractionally beyond the rotor diagonal (z -0.74
	## against 0.727). Small today and not the point — the point is that the
	## picture would change shape per frame at all, and a longer-nosed frame would
	## move it much further. `hud_check` claim 5 holds the ring identical.
	##
	## Body -Z is the nose and screen -Y is up, so z maps straight onto y and this
	## is the airframe seen from above, nose up.
	static func layout(parts: Array[AirframeComponents.Part],
			centre: Vector2) -> Dictionary:
		var out: Dictionary = {}
		# THE RADIUS, NOT THE WIDEST AXIS. Taking `max(|x|, |z|)` measures a
		# SQUARE and the plate draws a CIRCLE, so a quad-X — whose rotors sit on
		# the diagonal — pushed its corners out to RING x root 2 while a hexa's
		# ring rotors landed at exactly RING. 65 px against 46 px for the same
		# widget, caught by `hud_check`'s fifth claim on its first run.
		var reach: float = 0.0
		for part: AirframeComponents.Part in parts:
			if part.kind == &"rotor":
				reach = maxf(reach,
						Vector2(part.position.x, part.position.z).length())
		if reach <= 0.0:
			return out
		for part: AirframeComponents.Part in parts:
			# The structure pool has no location by design (E5): it is the whole
			# airframe, and it already has the health bar.
			if not part.located:
				continue
			var offset := Vector2(part.position.x, part.position.z) / reach * RING
			out[part.id] = centre + Vector2(clampf(offset.x, -EDGE, EDGE),
					clampf(offset.y, -EDGE, EDGE))
		return out

	## A rotor: a disc whose HUE is its state, with the reading inside it. The
	## human's shape, and it beats a square pip for the reason they gave — a rotor
	## is a disc on the real aircraft, so the picture reads as the machine.
	func _rotor(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		draw_circle(at, ROTOR_R, Color(0.0, 0.0, 0.0, 0.6))
		# The disc fills as it dies rather than only reddening: a ring that is
		# both emptier AND redder survives being glanced at.
		draw_circle(at, maxf(ROTOR_R * h, 2.0), Color(tint.r, tint.g, tint.b, 0.5))
		draw_arc(at, ROTOR_R, 0.0, TAU, 28, tint, 2.0)
		_plating(at, ROTOR_R + 3.0, part)
		_value(at, h)

	## The transmitter, as a thing that BROADCASTS: a hub with two arcs opening
	## forward. Hue is its state like everything else, so a failing feed reads the
	## same way a failing rotor does - which is D1's whole thesis, and is why the
	## jam effect reuses the damage overlay.
	func _transmitter(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		draw_circle(at, 3.5, tint)
		# The arcs THIN OUT as the transmitter dies, so a wrecked feed is a stub
		# rather than a full broadcast in an alarming colour.
		for i: int in 2:
			var radius: float = 7.0 + float(i) * 5.0
			draw_arc(at, radius, PI * 1.15, PI * 1.85, 14, tint,
					maxf(2.0 * h, 0.6))
		_plating(at, 15.0, part)
		draw_string(get_theme_default_font(), at + Vector2(9.0, 4.0),
				"%s %d" % [label_for(part.kind), roundi(h * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)

	## Any other BUILT component: a small block at its mount with its label and
	## reading beside it. Nothing reaches this today, and it is what a new failure
	## mode gets for free the day it flips `built`.
	func _block(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		var box := Rect2(at - Vector2(6.0, 6.0), Vector2(12.0, 12.0))
		draw_rect(box, Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(box.position + Vector2(0.0, box.size.y * (1.0 - h)),
				Vector2(box.size.x, box.size.y * h)), tint)
		draw_rect(box, tint, false, 1.0)
		_plating(at, 11.0, part)
		draw_string(get_theme_default_font(), at + Vector2(10.0, 4.0),
				"%s %d" % [label_for(part.kind), roundi(h * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)

	## Equipment that is aboard but cannot fail yet: where it sits, what it is,
	## and deliberately no reading.
	func _ghost(at: Vector2, part: AirframeComponents.Part, side: float) -> void:
		var dim := Color(0.62, 0.68, 0.76, 0.4)
		draw_arc(at, 4.5, 0.0, TAU, 12, dim, 1.0)
		_plating(at, 8.0, part)
		# The label reads OUTWARD from the airframe, so it never runs back across
		# the hull it is annotating.
		var text: String = label_for(part.kind)
		var font: Font = get_theme_default_font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 9).x
		var dx: float = 8.0 if side > 0.0 else -8.0 - width
		draw_string(font, at + Vector2(dx, 3.5), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dim)

	## ARMOUR, SHOWN AS A RING AROUND WHAT IT PROTECTS (E4.2). Plating that
	## protects a NAMED thing is the whole argument for the mechanic — *"they got
	## my power bus through the plating"* — and a number in a config cannot say
	## that. Drawn only where there IS plating, so an unarmoured frame is not
	## covered in empty rings.
	func _plating(at: Vector2, radius: float, part: AirframeComponents.Part) -> void:
		if part.armor <= 0.0:
			return
		draw_arc(at, radius, 0.0, TAU, 24, Color(0.62, 0.78, 1.0, 0.75), 2.0)

	## The reading, as characters, centred in the shape it belongs to.
	func _value(at: Vector2, health: float) -> void:
		var font: Font = get_theme_default_font()
		var text: String = "%d" % roundi(clampf(health, 0.0, 1.0) * 100.0)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10).x
		draw_string(font, at + Vector2(-width * 0.5, 3.5), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.92))

	## Four characters or fewer: this sits in the corner of a flying pilot's eye.
	static func label_for(kind: StringName) -> String:
		match kind:
			&"vtx": return "VTX"
			&"power": return "PWR"
			&"gyro": return "FCS"
			&"weapon_mount": return "GUN"
			&"magazine": return "AMMO"
			&"prop": return "PROP"
		return String(kind).to_upper()


## Missile-lock diamond, drawn at the target's screen position: yellow and
## wide while acquiring; when locked it becomes an unmistakable pulsing red
## double diamond with a LOCK tag, and the missile director (auto-launch)
## winds an orange arc around it while its hold timer runs.
class LockIndicator:
	extends Control

	var target_visible: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var progress: float = 0.0
	var locked: bool = false
	var auto_progress: float = 0.0

	func _draw() -> void:
		if not target_visible:
			return
		if not locked:
			_diamond(lerpf(30.0, 14.0, progress), Color(1, 0.85, 0.2, 0.8), 2.0)
			return
		var pulse: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.001 * TAU * 3.0)
		var radius: float = 14.0 * pulse
		var color := Color(1, 0.2, 0.15, 0.95)
		_diamond(radius, color, 2.5)
		_diamond(radius + 6.0, Color(1, 0.2, 0.15, 0.5), 1.5)
		draw_string(get_theme_default_font(),
				target_position + Vector2(-16.0, radius + 22.0), "LOCK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if auto_progress > 0.0:
			draw_arc(target_position, radius + 12.0, -PI / 2.0,
					-PI / 2.0 + TAU * auto_progress, 32,
					Color(1, 0.55, 0.1, 0.9), 3.0)

	func _diamond(radius: float, color: Color, width: float) -> void:
		var points := PackedVector2Array([
			target_position + Vector2(0, -radius),
			target_position + Vector2(radius, 0),
			target_position + Vector2(0, radius),
			target_position + Vector2(-radius, 0),
			target_position + Vector2(0, -radius),
		])
		draw_polyline(points, color, width)


## FCS reticle (GAMEPLAY-DESIGN Iteration 7 aiming pass). Three selectable
## styles, all built on the same truth — the blaster's real impact point
## (muzzle + inherited drone velocity + drop), so the pilot aims where the bolts
## actually go, not where the nose points — plus the missile lock cone. Player
## fire is yellow (emissive palette); the lock cone is navigation blue. No
## auto-lead: moving targets are led by hand (lead-compute is future FCS gear).
class Reticle:
	extends Control

	var active: bool = false
	var center: Vector2 = Vector2.ZERO      # boresight (camera axis)
	var pipper: Vector2 = Vector2.ZERO      # bolt impact point at target range
	var arc: PackedVector2Array = PackedVector2Array()
	var ticks: Array = []                   # [{"pos": Vector2, "label": String}]
	var lock_radius: float = 0.0            # missile ACQUIRE cone
	var hold_radius: float = 0.0            # wider cone where a lock is MAINTAINED
	var lockable: bool = false

	const GUN := Color(1.0, 0.9, 0.3)
	const NAV := Color(0.35, 0.75, 1.0)

	func _draw() -> void:
		# Missile lock zone (always shown): the ACQUIRE ring — start a lock with
		# a bandit inside it — and the wider HOLD ring, out to which an existing
		# lock is maintained. Both grow with lock upgrades (lock_cone_mult), so
		# the pilot flies to keep the target inside the circle.
		if hold_radius > 4.0:
			_dashed_ring(center, hold_radius, Color(NAV, 0.22), 40)
		if lock_radius > 4.0:
			_dashed_ring(center, lock_radius,
					Color(NAV, 0.9 if lockable else 0.45), 40)
		if not active:
			return
		# CCIP gun reticle: boresight, the bolt fall-line + range ticks, and the
		# impact pipper where the bolts pass at the target's range.
		_cross(center, 4.0, Color(GUN, 0.5))
		if arc.size() >= 2:
			draw_polyline(arc, Color(GUN, 0.55), 1.5)
		for tick: Dictionary in ticks:
			var p: Vector2 = tick["pos"]
			draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color(GUN, 0.7), 1.5)
			draw_string(get_theme_default_font(), p + Vector2(9, 4),
					tick["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GUN, 0.7))
		draw_arc(pipper, 7.0, 0.0, TAU, 24, GUN, 2.0)
		draw_rect(Rect2(pipper - Vector2(1, 1), Vector2(2, 2)), GUN)

	func _cross(at: Vector2, r: float, col: Color) -> void:
		draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), col, 1.0)
		draw_line(at + Vector2(0, -r), at + Vector2(0, r), col, 1.0)

	func _dashed_ring(at: Vector2, radius: float, col: Color, segments: int) -> void:
		for i: int in segments:
			if i % 2 == 1:
				continue
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			draw_line(at + Vector2(cos(a0), sin(a0)) * radius,
					at + Vector2(cos(a1), sin(a1)) * radius, col, 1.5)


## Raw gamepad stick positions: two boxes flanking the health bar, a dot per
## stick (left = yaw/throttle, right = roll/pitch), x right / y up. Raw on
## purpose — no deadzone, expo or curve — so the pilot sees the hardware.
class StickDisplay:
	extends Control

	const HALF: float = 38.0
	const MARGIN: Vector2 = Vector2(230.0, 62.0)

	var left_stick: Vector2 = Vector2.ZERO
	var right_stick: Vector2 = Vector2.ZERO

	func _draw() -> void:
		var bottom_center := Vector2(size.x * 0.5, size.y)
		_draw_stick(bottom_center + Vector2(-MARGIN.x, -MARGIN.y), left_stick)
		_draw_stick(bottom_center + Vector2(MARGIN.x, -MARGIN.y), right_stick)

	func _draw_stick(center: Vector2, stick: Vector2) -> void:
		var frame := Color(1, 1, 1, 0.35)
		draw_rect(Rect2(center - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0),
				frame, false, 1.5)
		draw_line(center - Vector2(HALF, 0), center + Vector2(HALF, 0), frame, 1.0)
		draw_line(center - Vector2(0, HALF), center + Vector2(0, HALF), frame, 1.0)
		# Screen y grows downward; stick y is +up.
		var dot: Vector2 = center + Vector2(stick.x, -stick.y) * HALF
		draw_rect(Rect2(dot - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 0.9))


## Blue box drawn at the open exit gate's screen position (roadmap M4).
class GateMarker:
	extends Control

	var marker_visible: bool = false
	var marker_position: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if not marker_visible:
			return
		var half: float = 18.0
		var color := Color(0.3, 0.7, 1.0, 0.9)
		draw_rect(Rect2(marker_position - Vector2(half, half),
				Vector2(half, half) * 2.0), color, false, 2.0)
		draw_string(get_theme_default_font(),
				marker_position + Vector2(-18.0, half + 18.0), "EXIT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _ready() -> void:
	# Video-breakup overlay sits at the bottom of the layer so the crisp HUD
	# draws on top of it (the feed degrades, the instruments do not).
	_video_glitch = ColorRect.new()
	_video_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glitch_material := ShaderMaterial.new()
	glitch_material.shader = load("res://resources/video_glitch.gdshader") as Shader
	_video_glitch.material = glitch_material
	_video_glitch.visible = false
	add_child(_video_glitch)
	_motor_status = ComponentStatus.new()
	_motor_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_motor_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_motor_status)
	_lock_indicator = LockIndicator.new()
	_lock_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_indicator)
	_gate_marker = GateMarker.new()
	_gate_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gate_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gate_marker)
	_reticle = Reticle.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)
	_stick_display = StickDisplay.new()
	_stick_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stick_display)
	_repair_label = Label.new()
	_repair_label.text = "⟳ ENGINES RESTORED"
	_repair_label.add_theme_color_override(&"font_color", Color(0.3, 1.0, 0.45))
	_repair_label.add_theme_font_size_override(&"font_size", 20)
	_repair_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_repair_label.position.y = 76.0
	_repair_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_repair_label.modulate.a = 0.0
	add_child(_repair_label)
	_pause_label = Label.new()
	_pause_label.text = "|| SLOW-MO — autopilot holding"
	_pause_label.add_theme_color_override(&"font_color", Color(0.4, 0.85, 1.0))
	_pause_label.add_theme_font_size_override(&"font_size", 20)
	_pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_label.position.y = 48.0
	_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_label.visible = false
	add_child(_pause_label)
	for side: StringName in [&"front", &"back", &"left", &"right"]:
		var edge := ColorRect.new()
		edge.color = Color(1, 0, 0, 0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match side:
			&"front":
				edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
				edge.offset_bottom = 24.0
			&"back":
				edge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				edge.offset_top = -24.0
			&"left":
				edge.set_anchors_preset(Control.PRESET_LEFT_WIDE)
				edge.offset_right = 24.0
			&"right":
				edge.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
				edge.offset_left = -24.0
		add_child(edge)
		_edges[side] = edge


func set_score(total: int) -> void:
	_score_label.text = "SCORE %d" % total


func set_combo(multiplier: int) -> void:
	_combo_label.visible = multiplier > 1
	_combo_label.text = "x%d" % multiplier


func set_wave(sortie: int, wave: int, remaining: int) -> void:
	if remaining > 0:
		_wave_label.text = "SORTIE %d · WAVE %d — %d hostile%s" % [sortie, wave,
				remaining, "" if remaining == 1 else "s"]
	else:
		_wave_label.text = "SORTIE %d · WAVE %d CLEARED" % [sortie, wave]


func announce_gate(sortie: int) -> void:
	_wave_label.text = "SORTIE %d CLEAR — EXIT GATE OPEN" % sortie


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


## The blaster's heat, 0..1, and whether it has locked out.
##
## Two states that must be tellable apart WITHOUT reading a number, because
## they mean opposite things to a trigger finger: yellow filling toward red is
## "you have a burst left", and a pulsing red bar is "the gun is dead, stop
## pulling". A heat meter you have to interpret is a heat meter that reads as a
## broken weapon the first time it bites.
##
## Yellow because the palette says so (CLAUDE.md): yellow = your fire.
func set_heat(fraction: float, overheated: bool) -> void:
	_heat_bar.value = clampf(fraction, 0.0, 1.0) * 100.0
	if overheated:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018)
		_heat_bar.modulate = Color(1.0, 0.22, 0.16).lerp(Color(1.0, 0.75, 0.3), pulse)
		return
	_heat_bar.modulate = Color(0.95, 0.9, 0.35).lerp(Color(1.0, 0.45, 0.15), fraction)


## The two magazines. A weapon passing -1 has no magazine at all and is left
## off the readout entirely — the ABSENCE of a number is information: it says
## that weapon never runs out, which is exactly the blaster's contract.
func set_ammo(flak: int, missile: int) -> void:
	var parts: PackedStringArray = []
	if flak >= 0:
		parts.append("FLAK %d" % flak)
	if missile >= 0:
		parts.append("MSL %d" % missile)
	_ammo_label.text = "   ".join(parts)
	# Dry is a state you must notice mid-fight, not one you read.
	var dry: bool = (flak == 0) or (missile == 0)
	_ammo_label.modulate = Color(1.0, 0.35, 0.25) if dry else Color(0.85, 0.85, 0.9)


## The whole component list, straight off the registry (E.q5). Replaces
## `set_motor_health(healths, vtx)`: the gauge no longer takes an array whose
## length it has to agree with and a transmitter threaded in beside it, so a new
## component is a `TABLE` row rather than another argument through this seam.
func set_components(parts: Array[AirframeComponents.Part]) -> void:
	_motor_status.parts = parts
	_motor_status.queue_redraw()


## Video-breakup intensity [0, 1]; 0 hides the overlay entirely (no cost).
func set_video_glitch(intensity: float) -> void:
	var clamped: float = clampf(intensity, 0.0, 1.0)
	_video_glitch.visible = clamped > 0.001
	if _video_glitch.visible:
		(_video_glitch.material as ShaderMaterial).set_shader_parameter(
				&"glitch", clamped)


## side: front/back/left/right for an edge hint, anything else full-screen.
func flash_damage(side: StringName = &"all") -> void:
	var rect: ColorRect = _edges.get(side, _damage_flash)
	rect.color = Color(1, 0, 0, 0.35)
	create_tween().tween_property(rect, "color:a", 0.0, 0.45)


func add_kill_feed(text: String) -> void:
	var entry := Label.new()
	entry.text = text
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed.add_child(entry)
	_kill_feed.move_child(entry, 0)
	while _kill_feed.get_child_count() > KILL_FEED_MAX:
		_kill_feed.get_child(_kill_feed.get_child_count() - 1).free()
	var tween: Tween = entry.create_tween()
	tween.tween_interval(KILL_FEED_SECONDS)
	tween.tween_property(entry, "modulate:a", 0.0, 0.6)
	tween.tween_callback(entry.queue_free)


func update_lock(target_visible: bool, screen_position: Vector2 = Vector2.ZERO,
		progress: float = 0.0, locked: bool = false,
		auto_progress: float = 0.0) -> void:
	_lock_indicator.target_visible = target_visible
	_lock_indicator.target_position = screen_position
	_lock_indicator.progress = progress
	_lock_indicator.locked = locked
	_lock_indicator.auto_progress = auto_progress
	_lock_indicator.queue_redraw()


func update_sticks(left_stick: Vector2, right_stick: Vector2) -> void:
	_stick_display.left_stick = left_stick
	_stick_display.right_stick = right_stick
	_stick_display.queue_redraw()


## Empty array hides the funnel.
func update_reticle(center: Vector2, pipper: Vector2, arc: PackedVector2Array,
		ticks: Array, lock_radius: float, hold_radius: float,
		lockable: bool) -> void:
	_reticle.active = true
	_reticle.center = center
	_reticle.pipper = pipper
	_reticle.arc = arc
	_reticle.ticks = ticks
	_reticle.lock_radius = lock_radius
	_reticle.hold_radius = hold_radius
	_reticle.lockable = lockable
	_reticle.queue_redraw()


## Disarmed / no camera: keep the lock cone hint if one was passed, hide the gun.
func clear_reticle() -> void:
	_reticle.active = false
	_reticle.lock_radius = 0.0
	_reticle.hold_radius = 0.0
	_reticle.queue_redraw()


func update_gate_marker(marker_visible: bool,
		screen_position: Vector2 = Vector2.ZERO) -> void:
	_gate_marker.marker_visible = marker_visible
	_gate_marker.marker_position = screen_position
	_gate_marker.queue_redraw()


## Brief green confirmation flash when a repair gate restores the engines.
func flash_engines_restored() -> void:
	_repair_label.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(_repair_label, "modulate:a", 0.0, 0.7)


func show_pause(paused: bool) -> void:
	_pause_label.visible = paused


func show_death(dead: bool) -> void:
	_death_label.visible = dead


func show_title(bests_line: String) -> void:
	_title_bests.text = bests_line
	_title.visible = true


func hide_title() -> void:
	_title.visible = false


func show_run_summary(sorties_cleared: int, waves_cleared: int, kills: int,
		score: int, bests_line: String = "") -> void:
	_summary_label.text = "RUN OVER\n\nsorties cleared  %d\nwaves cleared  %d\nkills  %d\nscore  %d\n\n%s\n\narm to fly again" \
			% [sorties_cleared, waves_cleared, kills, score, bests_line]
	_summary.visible = true


func hide_run_summary() -> void:
	_summary.visible = false
