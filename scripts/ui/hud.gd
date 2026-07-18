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
var _gun_funnel: GunFunnel
var _stick_display: StickDisplay
var _pause_label: Label
var _motor_status: MotorStatus
var _video_glitch: ColorRect
var _repair_label: Label


## Four motor-capability pips in quad-X layout (GAMEPLAY-DESIGN Iteration 7 /
## D4): the legible half of the wound (the sticks tell you first). Green =
## healthy, red = failed; a damaged corner is exactly the one the drone now
## fights toward.
class MotorStatus:
	extends Control

	## FL, FR, BL, BR — matches MotorModel's order.
	var healths: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

	## Sharp green->yellow->red ramp: a motor at 0.6 must read as clearly hurt,
	## not near-green (the old lerp's flaw).
	static func ramp(h: float) -> Color:
		var green := Color(0.3, 1.0, 0.4)
		var yellow := Color(1.0, 0.85, 0.2)
		var red := Color(1.0, 0.2, 0.15)
		if h >= 0.6:
			return yellow.lerp(green, (h - 0.6) / 0.4)
		return red.lerp(yellow, h / 0.6)

	func _draw() -> void:
		var origin := Vector2(30.0, 94.0)
		var pip := 20.0
		var gap := 7.0
		var offsets: Array[Vector2] = [
			Vector2(0, 0), Vector2(pip + gap, 0),
			Vector2(0, pip + gap), Vector2(pip + gap, pip + gap)]
		draw_string(get_theme_default_font(), origin + Vector2(0, -7),
				"MOTORS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
		for i: int in 4:
			var h: float = healths[i]
			var box := Rect2(origin + offsets[i], Vector2(pip, pip))
			# Drained-gauge fill: the pip empties AND reddens as the motor fails,
			# so a wounded corner is unmissable at a glance.
			draw_rect(box, Color(0, 0, 0, 0.55))
			var fill: float = pip * h
			draw_rect(Rect2(box.position + Vector2(0, pip - fill), Vector2(pip, fill)),
					ramp(h))
			var hurt: bool = h < 0.95
			draw_rect(box, Color(1, 1, 1, 0.85) if hurt else Color(0, 0, 0, 0.6),
					false, 2.0 if hurt else 1.0)


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


## Gun funnel: shrinking rings along the blaster's predicted flight path
## (muzzle velocity + inherited drone velocity + drop), so the pilot sees
## where the bolts will actually go instead of where the nose points.
class GunFunnel:
	extends Control

	var points: PackedVector2Array = PackedVector2Array()

	func _draw() -> void:
		if points.size() < 2:
			return
		var color := Color(0.55, 1.0, 0.7, 0.45)
		draw_polyline(points, Color(0.55, 1.0, 0.7, 0.15), 1.0)
		for i: int in points.size():
			var radius: float = lerpf(13.0, 4.0, float(i) / float(points.size() - 1))
			draw_arc(points[i], radius, 0.0, TAU, 24, color, 1.5)


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
	_motor_status = MotorStatus.new()
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
	_gun_funnel = GunFunnel.new()
	_gun_funnel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gun_funnel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gun_funnel)
	_stick_display = StickDisplay.new()
	_stick_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stick_display)
	_repair_label = Label.new()
	_repair_label.text = "⟳ REPAIRING ENGINES — hold the hover"
	_repair_label.add_theme_color_override(&"font_color", Color(0.3, 1.0, 0.45))
	_repair_label.add_theme_font_size_override(&"font_size", 18)
	_repair_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_repair_label.position.y = 76.0
	_repair_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_repair_label.visible = false
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


func set_motor_health(healths: PackedFloat32Array) -> void:
	_motor_status.healths = healths
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
func update_gun_funnel(points: PackedVector2Array) -> void:
	_gun_funnel.points = points
	_gun_funnel.queue_redraw()


func update_gate_marker(marker_visible: bool,
		screen_position: Vector2 = Vector2.ZERO) -> void:
	_gate_marker.marker_visible = marker_visible
	_gate_marker.marker_position = screen_position
	_gate_marker.queue_redraw()


func set_repairing(active: bool) -> void:
	_repair_label.visible = active


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
