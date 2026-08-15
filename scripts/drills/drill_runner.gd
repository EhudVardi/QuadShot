extends Node3D

## THE DRILL RUNNER — the interactive half of the pilot-in-the-loop instrument.
##
## It states a drill, watches the human fly it, and writes what it saw. It does
## NOT grade: grading is `DrillReport`, run afterwards from the console, so the
## number the pilot is being measured against is never on screen while they fly.
## That is deliberate — a target you can see is a target you aim at, and the
## reading stops being about the aircraft.
##
##   <godot> --path . scenes/drill.tscn -- --drill hold_tilt
##   <godot> --path . scenes/drill.tscn -- --list
##
## THE AIRCRAFT IS THE REPO'S, NOT THE MACHINE'S. `user_overrides_enabled` goes
## off in `_enter_tree`, before the drone's `_ready` runs, so the drill flies the
## committed flight numbers and a prediction made about the shipped Kestrel is a
## prediction about the thing that actually flew. The single exception is the
## human's own input bindings, loaded by hand below: without their radio mapping
## there is no flight at all.
##
## STRUCTURE (`DrillBook` -> `DrillMeasures` -> artifact) is what keeps this file
## small enough to trust. Everything here is sampling and state; every number
## comes out of the pure reduction, which the board checks against synthetic
## flights.

const ARTIFACT_DIR: String = "user://blackbox/drills"
## 240 Hz physics, every 4th tick: 60 Hz is far finer than any measure here and
## keeps a 36-second attempt at ~2200 samples instead of ~8600.
const SAMPLE_EVERY: int = 4
## A hold_tilt attempt that gets this close to the ground has ended, whatever
## the clock says. The pad is at 250 m; see the scene file for why.
const FLOOR_M: float = 10.0

enum { BRIEF, READY, RUNNING }

@export var input_bindings: InputBindings

@onready var _drone: FlightController = $Drone
@onready var _drone_health: Health = $Drone/Health
@onready var _hud: GameHud = $Hud
@onready var _motors: MotorModel = $Drone/MotorModel

var _drill_id: String = "hold_tilt"
var _drill: Dictionary = {}
var _state: int = BRIEF
var _artifact_path: String = ""
var _artifact_dir: String = ARTIFACT_DIR

var _samples: Array = []
var _tick: int = 0
var _clock: float = 0.0
var _attempts: Array = []
var _voided: int = 0
var _flown_unix: int = 0

## rotor_out state: when the failure starts, how much has been taken, and when.
var _wait_s: float = 0.0
var _loss: float = 0.0
var _next_step_at: float = 0.0
var _call_t: float = -1.0

var _brief_root: Control
var _brief_label: Label
var _status_label: Label


## BEFORE THE DRONE'S `_ready`, which is why this is `_enter_tree` and not
## `_ready`: children are readied before their parent, so a flag flipped in the
## parent's `_ready` would arrive one whole airframe too late.
func _enter_tree() -> void:
	TunableConfig.user_overrides_enabled = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--list"):
		for id: String in DrillBook.ids():
			print("[drill] %-12s %s" % [id, DrillBook.drill(id)["title"]])
		get_tree().quit()
		return
	var at: int = args.find("--drill")
	if at >= 0 and at + 1 < args.size():
		_drill_id = args[at + 1]
	if not DrillBook.has(_drill_id):
		push_error("[drill] no such drill '%s' — try one of %s"
				% [_drill_id, ", ".join(DrillBook.ids())])
		get_tree().quit(1)
		return
	at = args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_artifact_dir = args[at + 1]
	_drill = DrillBook.drill(_drill_id)
	# The ONE user:// file a drill reads: their sticks. Re-enabled around the
	# single call rather than left on, so nothing else can follow it in.
	if input_bindings != null:
		TunableConfig.user_overrides_enabled = true
		input_bindings.load_from_user(true)
		TunableConfig.user_overrides_enabled = false
		input_bindings.apply()
	RunMods.reset()
	# FIRE is the drill's MARK button, so the weapons must not answer it: a bolt,
	# a gun sound and a heat needle are all feedback about the wrong thing, and in
	# `rotor_out` a squeeze that also fired would put recoil into the reading.
	for weapon: Node in [$Drone/FpvCamera/Weapon, $Drone/FpvCamera/MissileSystem,
			$Drone/FpvCamera/FlakPod]:
		weapon.set_physics_process(false)
	_build_overlay()
	_hud.hide_title()
	_hud.set_pitch_ladder(true)
	# The plate is hidden for `rotor_out` and only for it: that drill asks
	# whether a failure can be FELT, and a gauge showing the rotor emptying
	# answers a different question perfectly.
	_hud.set_plate_visible(_drill_id != "rotor_out")
	_hud.set_health(_drone_health.current, _drone_health.max_health)
	_drone_health.damaged.connect(func(_amount: float, remaining: float) -> void:
			_hud.set_health(remaining, _drone_health.max_health))
	_drone.airframe_reset.connect(_abort_attempt.bind("reset"))
	_drone_health.died.connect(_abort_attempt.bind("destroyed"))
	_flown_unix = int(Time.get_unix_time_from_system())
	_artifact_path = "%s/%s_%s.json" % [_artifact_dir, _drill_id, _stamp()]
	for line: String in DrillBook.brief_lines(_drill_id):
		print("[drill] %s" % line)
	print("[drill] artifact -> %s" % _artifact_path)


func _physics_process(delta: float) -> void:
	_brief_root.visible = not _drone.armed
	if not _drone.armed:
		if _state != BRIEF:
			_abort_attempt("disarmed")
		_status_label.text = ""
		return
	if _state == BRIEF:
		_state = READY
		_hud.add_kill_feed("ARMED — %s" % _drill["title"])
	if _state == READY:
		_ready_state()
		return
	_clock += delta
	if _drill_id == "rotor_out":
		_step_failure()
	_tick += 1
	if _tick % SAMPLE_EVERY == 0:
		_samples.append({
			"t": _clock,
			"tilt_deg": GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y),
			"pos": _drone.global_position,
			"loss": _loss,
		})
	_running_state()


func _process(_ignored: float) -> void:
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])
	_hud.set_thrust_axis(_drone.global_basis.y)
	if _drill_id != "rotor_out":
		_hud.set_components(AirframeComponents.of(_drone))


# --- the two drills -------------------------------------------------------

## Waiting for the pilot's MARK, with the drill's own entry condition enforced.
## The gate is stated in the brief and refused out loud, so every attempt starts
## from the same place and a run is comparable with the one before it.
func _ready_state() -> void:
	var refusal: String = _mark_refusal()
	_status_label.text = "%s — READY. squeeze FIRE to mark.%s" % [_drill["title"],
			"" if refusal.is_empty() else "   (%s)" % refusal]
	if not Input.is_action_just_pressed(&"fire"):
		return
	if not refusal.is_empty():
		_hud.add_kill_feed("MARK REFUSED — %s" % refusal)
		return
	# Acro is part of the situation, so it is enforced at the mark rather than
	# hoped for: an angle-mode attempt would measure a different aircraft.
	_drone.flight_mode = FlightController.FlightMode.ACRO
	_samples.clear()
	_clock = 0.0
	_tick = 0
	_loss = 0.0
	_call_t = -1.0
	_drone.repair_motors()
	if _drill_id == "rotor_out":
		_wait_s = randf_range(float(_drill["wait_min_s"]), float(_drill["wait_max_s"]))
		_next_step_at = _wait_s
	_state = RUNNING
	_hud.add_kill_feed("MARK — attempt %d" % (_attempts.size() + 1))


func _mark_refusal() -> String:
	match _drill_id:
		"hold_tilt":
			var tilt: float = GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y)
			var gate: float = float(_drill["level_gate_deg"])
			if tilt > gate:
				return "get level first — %.0f deg of tilt, need under %.0f" % [tilt, gate]
		"rotor_out":
			var speed: float = _drone.linear_velocity.length()
			if speed > float(_drill["mark_speed_max"]):
				return "settle first — %.1f m/s, need under %.1f" % [speed,
						float(_drill["mark_speed_max"])]
			var pad: Vector3 = _drone.global_position - $Pad.global_position
			var range_m: float = Vector2(pad.x, pad.z).length()
			if range_m > float(_drill["mark_radius_max"]):
				return "closer to the pad — %.0f m, need under %.0f" % [range_m,
						float(_drill["mark_radius_max"])]
	return ""


## The staircase: one 5% bite out of one rotor every couple of seconds, which is
## about one raider bolt at the shipped severity of 0.6. Stepwise rather than
## continuous because that is how real damage arrives — round by round — and
## because a step has a transient a pilot could plausibly feel.
func _step_failure() -> void:
	if _clock < _next_step_at or _loss >= float(_drill["max_loss"]):
		return
	var step: float = float(_drill["step_loss"])
	_motors.damage_motor(int(_drill["rotor_index"]), step)
	_loss = minf(_loss + step, 1.0)
	_next_step_at += float(_drill["step_period_s"])


func _running_state() -> void:
	match _drill_id:
		"hold_tilt":
			var tilt: float = GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y)
			_status_label.text = "HOLD %.0f deg — tilt %5.1f — %4.1f s left" % [
					float(_drill["target_tilt_deg"]), tilt,
					maxf(0.0, float(_drill["window_s"]) - _clock)]
			if _clock >= float(_drill["window_s"]):
				_finish_attempt("window closed")
			elif _drone.global_position.y < FLOOR_M:
				_finish_attempt("ground")
		"rotor_out":
			_status_label.text = "HOLD STATION — squeeze FIRE the instant you feel it   (%4.1f s)" % _clock
			if Input.is_action_just_pressed(&"fire"):
				if _loss <= 0.0:
					_void_attempt("called before the failure began")
					return
				_call_t = _clock
				_finish_attempt("called")
			elif _loss >= float(_drill["max_loss"]):
				_finish_attempt("staircase topped out, never called")


# --- recording ------------------------------------------------------------

func _finish_attempt(reason: String) -> void:
	var measures: Dictionary = DrillMeasures.compute(_drill_id, _samples,
			{"call_t": _call_t})
	_attempts.append({
		"n": _attempts.size() + 1,
		"ended": reason,
		"seconds": snappedf(_clock, 0.01),
		"measures": _rounded(measures),
	})
	var parts: PackedStringArray = PackedStringArray()
	for name: String in DrillBook.measure_names(_drill_id):
		parts.append("%s %.2f" % [name, float(measures[name])])
	_hud.add_kill_feed("ATTEMPT %d: %s" % [_attempts.size(), " | ".join(parts)])
	print("[drill] attempt %d (%s): %s" % [_attempts.size(), reason,
			" | ".join(parts)])
	_reset_for_next()
	_write_artifact()


func _void_attempt(reason: String) -> void:
	_voided += 1
	_hud.add_kill_feed("VOID — %s. settle and MARK again." % reason)
	print("[drill] void: %s" % reason)
	_reset_for_next()


## A run cut short by something that is not the drill — a reset, a crash, a
## disarm. Recorded as voided rather than as a bad score, because a number
## produced by an interrupted attempt is not a reading.
func _abort_attempt(reason: String) -> void:
	if _state != RUNNING:
		_state = BRIEF
		_drone.repair_motors()
		return
	_void_attempt(reason)
	_state = BRIEF


func _reset_for_next() -> void:
	_drone.repair_motors()
	_loss = 0.0
	_call_t = -1.0
	_samples.clear()
	_state = READY


func _rounded(measures: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for name: String in measures:
		out[name] = snappedf(float(measures[name]), 0.01)
	return out


## Rewritten after EVERY completed attempt — the aim drill's discipline, and for
## the same reason: a pilot who stops after three of five attempts still has a
## file worth reading.
##
## H5 DEVIATION DATA. This is a HUMAN reading and it never enters
## `balance/delivery_factors.json` or any base table; the balance instrument is
## measured by `ReferencePilot` and pinned to its version. This file exists to
## ARGUE with those numbers, which it cannot do if it is quietly folded into
## them.
func _write_artifact() -> void:
	var config: FlightConfig = _drone.config
	var payload: Dictionary = {
		"drill": _drill_id,
		"pilot": "human",
		"note": "H5 deviation data — a human reading, never merged into the balance base table",
		"flown_utc": Time.get_datetime_string_from_system(true),
		"flown_unix": _flown_unix,
		"prediction_fingerprint": DrillPredictions.fingerprint(
				DrillPredictions.load_prediction(_drill_id)),
		"frame": String(_drone.frame.frame_id),
		"aircraft": {
			"mass_kg": config.mass,
			"loaded_mass_kg": snappedf(_drone.loaded_mass(), 0.001),
			"twr": snappedf(_drone.effective_twr(), 0.001),
			"body_m": config.body_m,
			"rate_preset": FlightPresets.active_name(config),
			"user_overrides": TunableConfig.user_overrides_enabled,
		},
		"attempt_count": _attempts.size(),
		"voided_count": _voided,
		"attempts": _attempts,
		"summary": _rounded(DrillMeasures.best_of(_drill_id, _attempts)),
	}
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_artifact_dir))
	var file: FileAccess = FileAccess.open(_artifact_path, FileAccess.WRITE)
	if file == null:
		push_warning("[drill] cannot write %s" % _artifact_path)
		return
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.close()


func _stamp() -> String:
	var now: Dictionary = Time.get_datetime_dict_from_system(false)
	return "%04d%02d%02d_%02d%02d%02d" % [now["year"], now["month"], now["day"],
			now["hour"], now["minute"], now["second"]]


# --- the brief ------------------------------------------------------------

## Built in code rather than in the .tscn because the text IS the drill, and a
## second copy of it in a scene file is a second copy to drift.
##
## THE BACKDROP IS A SIBLING OF THE TEXT, NOT ITS CHILD, and that is a bug fixed
## by LOOKING at it rather than by reasoning about it. A Control draws itself
## first and its children over the top, so a ColorRect parented to the label
## painted 82% black straight across the brief. The screenshot rig showed it in
## one frame; nothing in the code reads wrong.
##
## The panel starts at 96 px for the same reason: the HUD's own SCORE label
## lives at 16 and the brief's title was printing through it.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_brief_root = Control.new()
	_brief_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brief_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_brief_root)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.05, 0.93)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brief_root.add_child(backdrop)
	_brief_label = Label.new()
	_brief_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brief_label.offset_left = 60.0
	_brief_label.offset_top = 96.0
	_brief_label.offset_right = -60.0
	_brief_label.offset_bottom = -40.0
	_brief_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brief_label.add_theme_font_size_override("font_size", 17)
	_brief_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	_brief_label.text = "\n".join(DrillBook.brief_lines(_drill_id))
	_brief_root.add_child(_brief_label)
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.offset_top = 52.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	layer.add_child(_status_label)
