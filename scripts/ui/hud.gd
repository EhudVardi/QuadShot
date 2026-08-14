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

	const PIP: float = 20.0
	const GAP: float = 7.0
	## Half the pitch between adjacent pips — the radius the mount ring projects
	## onto. (PIP + GAP) / 2 is what reproduces the old 2x2 block exactly.
	const SPREAD: float = (PIP + GAP) * 0.5

	func _draw() -> void:
		if parts.is_empty():
			return
		# Bottom-left, grouped with the input indicators (v1.45): out from under
		# the score / kill-feed text it used to overlap at the top-left. size is
		# the reference frame (full-rect control under canvas_items stretch), so
		# this rides the window like the stick display does.
		var origin := Vector2(30.0, size.y - 150.0)
		var centre := origin + Vector2(SPREAD + PIP * 0.5, SPREAD + PIP * 0.5)
		var rotors: Array[AirframeComponents.Part] = []
		var bars: Array[AirframeComponents.Part] = []
		for part: AirframeComponents.Part in parts:
			if not part.built:
				continue
			if part.kind == &"rotor":
				rotors.append(part)
			elif part.located:
				# Everything built that is not a rotor and does have a place on
				# the airframe reads as a bar. The structure pool is excluded by
				# `located`: it already has the health bar, and showing it twice
				# would make the coarse layer look like a component.
				bars.append(part)

		if not rotors.is_empty():
			draw_string(get_theme_default_font(), origin + Vector2(0, -7),
					"MOTORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
		var boxes: Array[Rect2] = pip_rects(rotors, centre)
		for i: int in rotors.size():
			_gauge(boxes[i], rotors[i].health, true)

		# Bars under the ring: drain left-to-right, same ramp, so a frying
		# transmitter reads exactly like a frying motor.
		var bar_width: float = 2.0 * PIP + GAP
		var bar_top: float = origin.y + 2.0 * PIP + GAP + 8.0
		for part: AirframeComponents.Part in bars:
			draw_string(get_theme_default_font(), Vector2(origin.x, bar_top - 3.0),
					label_for(part.kind), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(1, 1, 1, 0.55))
			_gauge(Rect2(Vector2(origin.x, bar_top), Vector2(bar_width, 8.0)),
					part.health, false)
			bar_top += 20.0

	## Where each rotor's pip goes, projected from its own mount on the airframe.
	##
	## STATIC AND SEPARATE FROM `_draw` SO IT CAN BE MEASURED. A layout buried in
	## a draw call can only be checked by looking at it, and this one carries a
	## claim worth holding: it reproduces the hand-authored 2x2 block exactly for
	## a quad, and lays a hexa on a ring rather than dropping two rotors.
	##
	## The ring is normalised so the widest rotor sits at the edge. Body -Z is the
	## nose and screen -Y is up, so z maps straight onto y and the picture is the
	## airframe seen from above, nose up — which is what makes a lit pip mean
	## "that corner, over there" instead of "the third one in the list".
	static func pip_rects(rotors: Array[AirframeComponents.Part],
			centre: Vector2) -> Array[Rect2]:
		var out: Array[Rect2] = []
		var reach: float = 0.0
		for part: AirframeComponents.Part in rotors:
			reach = maxf(reach, maxf(absf(part.position.x), absf(part.position.z)))
		for part: AirframeComponents.Part in rotors:
			var offset := Vector2(part.position.x, part.position.z)
			if reach > 0.0:
				offset = offset / reach * SPREAD
			out.append(Rect2(centre + offset - Vector2(PIP, PIP) * 0.5,
					Vector2(PIP, PIP)))
		return out

	## One drained gauge. `vertical` fills bottom-up (a pip), otherwise
	## left-to-right (a bar); both empty AND redden, so a wounded component is
	## unmissable at a glance.
	func _gauge(box: Rect2, health: float, vertical: bool) -> void:
		var h: float = clampf(health, 0.0, 1.0)
		draw_rect(box, Color(0, 0, 0, 0.55))
		if vertical:
			var fill: float = box.size.y * h
			draw_rect(Rect2(box.position + Vector2(0.0, box.size.y - fill),
					Vector2(box.size.x, fill)), ramp(h))
		else:
			draw_rect(Rect2(box.position, Vector2(box.size.x * h, box.size.y)),
					ramp(h))
		var hurt: bool = h < 0.95
		draw_rect(box, Color(1, 1, 1, 0.85) if hurt else Color(0, 0, 0, 0.6),
				false, 2.0 if hurt else 1.0)

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
