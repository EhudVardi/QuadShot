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

## Thin edge bars for directional damage, built in code (side -> ColorRect).
var _edges: Dictionary = {}
var _lock_indicator: LockIndicator


## Missile-lock diamond, drawn at the target's screen position: yellow and
## wide while acquiring, tight and red when locked.
class LockIndicator:
	extends Control

	var target_visible: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var progress: float = 0.0
	var locked: bool = false

	func _draw() -> void:
		if not target_visible:
			return
		var radius: float = lerpf(30.0, 14.0, progress)
		var color := Color(1, 0.2, 0.15, 0.95) if locked else Color(1, 0.85, 0.2, 0.8)
		var points := PackedVector2Array([
			target_position + Vector2(0, -radius),
			target_position + Vector2(radius, 0),
			target_position + Vector2(0, radius),
			target_position + Vector2(-radius, 0),
			target_position + Vector2(0, -radius),
		])
		draw_polyline(points, color, 2.0)


func _ready() -> void:
	_lock_indicator = LockIndicator.new()
	_lock_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_indicator)
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
		progress: float = 0.0, locked: bool = false) -> void:
	_lock_indicator.target_visible = target_visible
	_lock_indicator.target_position = screen_position
	_lock_indicator.progress = progress
	_lock_indicator.locked = locked
	_lock_indicator.queue_redraw()


func show_death(dead: bool) -> void:
	_death_label.visible = dead


func show_run_summary(sorties_cleared: int, waves_cleared: int, kills: int,
		score: int) -> void:
	_summary_label.text = "RUN OVER\n\nsorties cleared  %d\nwaves cleared  %d\nkills  %d\nscore  %d\n\narm to fly again" \
			% [sorties_cleared, waves_cleared, kills, score]
	_summary.visible = true


func hide_run_summary() -> void:
	_summary.visible = false
