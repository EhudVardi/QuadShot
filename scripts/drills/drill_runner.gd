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
var _pilot: String = "human"

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
var _mark_pressed: bool = false
## Live in-band time for the status cue only. The RECORDED hold comes from
## `DrillMeasures`, which is the instrument's only arithmetic — this is a
## display, and it must never become the number.
var _band_s: float = 0.0
## When the course clock started, for the live readout only. -1 before gate 1.
var _gate_one_at: float = -1.0
## Highest contact count seen since the last sample. See `_physics_process`.
var _contact_peak: int = 0

var _arrow: CourseArrow
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
		_shutdown(0)
		return
	var at: int = args.find("--drill")
	if at >= 0 and at + 1 < args.size():
		_drill_id = args[at + 1]
	if not DrillBook.has(_drill_id):
		push_error("[drill] no such drill '%s' — try one of %s"
				% [_drill_id, ", ".join(DrillBook.ids())])
		_shutdown(1)
		return
	at = args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_artifact_dir = args[at + 1]
	# WHO FLEW IT, and it defaults to the human because they are the point. The
	# plumbing smoke test overrides it so a scripted run can never be mistaken for
	# a reading — an artifact that says "human" is a claim, not a filename.
	at = args.find("--pilot")
	if at >= 0 and at + 1 < args.size():
		_pilot = args[at + 1]
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
	_place_pad()
	if DrillBook.is_course(_drill_id):
		_build_course()
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
	_drone.airframe_reset.connect(_on_reset)
	_drone_health.died.connect(_on_died)
	_flown_unix = int(Time.get_unix_time_from_system())
	_artifact_path = "%s/%s_%s.json" % [_artifact_dir, _drill_id, _stamp()]
	for line: String in DrillBook.brief_lines(_drill_id):
		print("[drill] %s" % line)
	print("[drill] artifact -> %s" % _artifact_path)


## LEAVING BEFORE THE OVERLAY EXISTS, and the processing has to be turned off by
## hand. `SceneTree.quit()` sets a flag and execution carries straight on, so
## `--list` printed its two lines and then crashed every frame until the engine
## actually left — assigning `visible` on a null brief panel that `_ready` had
## returned before building. The same sentence bit `hud_check` on the day it
## landed; it is a GDScript fact worth writing down twice.
func _shutdown(code: int) -> void:
	set_physics_process(false)
	set_process(false)
	get_tree().quit(code)


## THE PILOT'S MARK, as a named entry point rather than only an inline input
## test. `Input.is_action_just_pressed` is keyed to the exact physics frame the
## press landed on, so a script driving this from a frame signal is always one
## frame late and the mark is silently swallowed — which is how a plumbing test
## ends up proving nothing. The flag is consumed on the next tick either way.
func mark() -> void:
	_mark_pressed = true


## Whether an attempt is actually under way. The smoke test marks repeatedly
## until this turns true rather than counting seconds, so it cannot be silently
## defeated by a mark gate it does not know about — which is exactly what a
## fixed delay did the moment `hold_tilt` gained a speed and clearance gate.
func running() -> bool:
	return _state == RUNNING


func _physics_process(delta: float) -> void:
	var pressed: bool = _mark_pressed or Input.is_action_just_pressed(&"fire")
	_mark_pressed = false
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
		_ready_state(pressed)
		return
	_clock += delta
	if _drill_id == "rotor_out":
		_step_failure()
	# PEAK-HELD EVERY TICK, NOT READ AT SAMPLE TIME. Contact is instantaneous and
	# sampling is 60 Hz off a 240 Hz tick, so a brief touch has three chances in
	# four of falling between two samples and never being seen at all.
	#
	# THAT IS NOT HYPOTHETICAL. The human reported a collision on their third lap
	# and the artifact recorded ZERO touches; the 240 Hz flight recorder settled
	# it in one query — the contact episode ran t=83.179 to t=83.183, which is
	# 0.004 s, a SINGLE tick. Holding the peak between samples means no tick can
	# be missed. Two distinct touches inside one 16.7 ms window still merge, and
	# that is this measure's honest resolution limit.
	_contact_peak = maxi(_contact_peak, _drone.get_contact_count())
	_tick += 1
	if _tick % SAMPLE_EVERY == 0:
		_take_sample()
	_running_state(pressed, delta)


## How many gates the flown line has been through, in order — read back out of
## the samples with the SAME function that scores the attempt, so the live
## readout and the recorded result cannot disagree.
func _gates_passed() -> int:
	var gates: Array = _drill.get("gates", []) as Array
	var half: Vector2 = _drill.get("gate_half", Vector2.ONE)
	var reached: int = 0
	for i: int in range(1, _samples.size()):
		if reached >= gates.size():
			break
		if DrillMeasures.crossed_gate(gates[reached], half,
				_samples[i - 1]["pos"], _samples[i]["pos"]):
			if reached == 0:
				_gate_one_at = float(_samples[i]["t"])
			reached += 1
	return reached


func _take_sample() -> void:
	_samples.append({
		"t": _clock,
		"tilt_deg": GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y),
		"pos": _drone.global_position,
		"loss": _loss,
		"contacts": _contact_peak,
	})
	# Consumed, so the next sample reports its OWN window rather than everything
	# that ever happened.
	_contact_peak = 0


func _process(_ignored: float) -> void:
	var sticks: Array[Vector2] = _drone.stick_positions()
	_hud.update_sticks(sticks[0], sticks[1])
	_hud.set_thrust_axis(_drone.global_basis.y, -_drone.global_basis.z)
	if _drill_id != "rotor_out":
		_hud.set_components(AirframeComponents.of(_drone))
		_hud.set_motor_drive(_drone.motor_drive(), _drone.motor_spins())
	if DrillBook.is_course(_drill_id):
		_aim_course_arrow()


# --- the two drills -------------------------------------------------------

## Waiting for the pilot's MARK, with the drill's own entry condition enforced.
## The gate is stated in the brief and refused out loud, so every attempt starts
## from the same place and a run is comparable with the one before it.
func _ready_state(pressed: bool) -> void:
	var refusal: String = _mark_refusal()
	_status_label.text = "%s — READY. squeeze FIRE to mark.%s" % [_drill["title"],
			"" if refusal.is_empty() else "   (%s)" % refusal]
	if not pressed:
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
	_gate_one_at = -1.0
	_drone.repair_motors()
	if _drill_id == "rotor_out":
		_wait_s = randf_range(float(_drill["wait_min_s"]), float(_drill["wait_max_s"]))
		_next_step_at = _wait_s
	_state = RUNNING
	_hud.add_kill_feed("MARK — attempt %d" % (_attempts.size() + 1))


## A COURSE IS ASKED FOR BY ITS DATA, not by its name. Matching on `"course"`
## worked while there was exactly one, and the moment there were three it would
## have left two rungs of the ladder with no mark gate at all.
func _mark_refusal() -> String:
	if DrillBook.is_course(_drill_id):
		var gates: Array = _drill["gates"]
		# BEHIND THE START LINE. Marking from past gate 1 would leave the clock
		# waiting for a gate the pilot has already flown through.
		if _drone.global_position.z < (gates[0] as Vector3).z:
			return "get back behind gate 1 before you mark"
		var from_pad: Vector3 = _drone.global_position - $Pad.global_position
		var out_m: float = Vector2(from_pad.x, from_pad.z).length()
		if out_m > float(_drill["mark_radius_max"]):
			return "closer to the pad — %.0f m, need under %.0f" % [out_m,
					float(_drill["mark_radius_max"])]
		return ""
	match _drill_id:
		"hold_tilt":
			var tilt: float = GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y)
			var gate: float = float(_drill["level_gate_deg"])
			if tilt > gate:
				return "get level first — %.0f deg of tilt, need under %.0f" % [tilt, gate]
			var settled: float = _drone.linear_velocity.length()
			if settled > float(_drill["mark_speed_max"]):
				return "settle first — %.1f m/s, need under %.1f" % [settled,
						float(_drill["mark_speed_max"])]
			var clearance: float = _drone.global_position.y - ($Pad as Node3D).global_position.y
			if clearance < float(_drill["mark_clearance_m"]):
				return "get off the pad — %.1f m clear, need %.1f" % [clearance,
						float(_drill["mark_clearance_m"])]
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


func _running_state(pressed: bool, delta: float) -> void:
	if DrillBook.is_course(_drill_id):
		_course_state()
		return
	match _drill_id:
		"hold_tilt":
			# THE PILOT MUST BE ABLE TO SEE WHETHER THEY ARE SCORING. Ten attempts
			# were flown at level, all reading zero, and nothing on screen ever
			# said so — the instrument watched a pilot fail twenty seconds at a
			# time in silence. An in-band cue costs nothing and the information
			# was already on the HUD; what was missing was the THRESHOLD.
			var tilt: float = GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y)
			var target: float = float(_drill["target_tilt_deg"])
			var inside: bool = absf(tilt - target) <= float(_drill["tolerance_deg"])
			if inside:
				_band_s += delta
			else:
				_band_s = 0.0
			_status_label.modulate = Color(0.5, 1.0, 0.6) if inside \
					else Color(1.0, 0.72, 0.4)
			# The SIGNED figure, so the status line and the HUD readout beside the
			# bracket are the same number rather than two that differ by a minus.
			_status_label.text = "NOSE DOWN to -%.0f  —  now %+.0f  —  %s  —  %4.1f s left" % [
					target, GameHud.HorizonLine.signed_tilt_degrees(
							_drone.global_basis.y, -_drone.global_basis.z),
					"IN BAND %4.1f s" % _band_s if inside else "OUT",
					maxf(0.0, float(_drill["window_s"]) - _clock)]
			if _clock >= float(_drill["window_s"]):
				_finish_attempt("window closed")
			elif _drone.global_position.y < FLOOR_M:
				_finish_attempt("ground")
		"rotor_out":
			_status_label.text = "HOLD STATION — squeeze FIRE the instant you feel it   (%4.1f s)" % _clock
			if pressed:
				if _loss <= 0.0:
					_void_attempt("called before the failure began")
					return
				_call_t = _clock
				_finish_attempt("called")
			elif _loss >= float(_drill["max_loss"]):
				_finish_attempt("staircase topped out, never called")


# --- recording ------------------------------------------------------------

## THE LAST SAMPLE IS TAKEN HERE, AT THE INSTANT THE ATTEMPT ENDS, and the
## plumbing smoke test is what found out why it has to be.
##
## Sampling runs at 60 Hz off a 240 Hz tick, so an event can land up to three
## ticks after the most recent sample — and `rotor_out` ends on an EVENT, the
## pilot's call. A scripted pilot that called at exactly 25% of a rotor was
## recorded at 20%, a whole staircase step low, because the last sample predated
## the step it called. One extra sample closes it for both drills.
func _finish_attempt(reason: String) -> void:
	_take_sample()
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


## DEATH DISARMS, and that is what makes the drill recoverable without a
## respawn timer. Left armed, a dead pilot's attempt would keep sampling a hull
## on the ground and they could still MARK; disarmed, the brief comes back and
## R puts them on the pad with a revived airframe, which is the loop the drill
## already uses between attempts.
func _on_died() -> void:
	_abort_attempt("destroyed")
	_drone.disarm()
	_hud.show_death(true)
	_hud.add_kill_feed("DESTROYED — press R to go back to the pad")


func _on_reset() -> void:
	_hud.show_death(false)
	_abort_attempt("reset")


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
	_band_s = 0.0
	_gate_one_at = -1.0
	_status_label.modulate = Color.WHITE
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
		"pilot": _pilot,
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


## ANY course, told by its gate list. The gate count is re-derived from the
## samples every tick rather than tracked as scene state, so what the pilot is
## told and what the artifact records can never be two different numbers.
func _course_state() -> void:
	var gates: Array = _drill["gates"]
	var reached: int = _gates_passed()
	if reached >= gates.size():
		_finish_attempt("course complete")
		return
	_status_label.modulate = Color(0.5, 1.0, 0.6) if reached > 0 else Color.WHITE
	var target: Vector3 = gates[reached]
	_status_label.text = "GATE %d of %d — %3.0f m — %s" % [reached + 1,
			gates.size(), _drone.global_position.distance_to(target),
			"%5.2f s" % (_clock - _gate_one_at) if _gate_one_at >= 0.0
					else "clock starts at gate 1"]
	if _clock >= float(_drill["window_s"]):
		_finish_attempt("ran out of time")


# --- the world ------------------------------------------------------------

## THE PAD'S ALTITUDE IS THE DRILL'S, not the scene's. `hold_tilt` needs 250 m
## because a quad tilted 30 degrees spends 262 m of it; a COURSE needs the
## opposite — the ground close enough to read your own speed against.
##
## `place_at` rather than setting the transform, because it also moves the point
## R sends you back to. Without that the reset key would put the pilot at
## whatever altitude the .tscn happened to author, which for the course is 250 m
## of empty sky above the start gate.
func _place_pad() -> void:
	var altitude: float = float(_drill.get("pad_altitude", 250.0))
	var pad: Node3D = $Pad
	pad.position.y = altitude
	_drone.place_at(Transform3D(Basis.IDENTITY,
			Vector3(0.0, altitude + 0.6, 0.0)))


# --- the course -----------------------------------------------------------

## STAND THE ARROW AT THE GATE THAT IS NEXT. Not decoration: SEARCHING for the
## next gate is not the skill this drill measures, and six gates at different
## heights and offsets are genuinely easy to lose against a sky. Time spent
## hunting would land in `time_s` and read as slow flying, which is a confound
## rather than a result.
##
## THE HUD BOX IS GONE FROM THIS DRILL and the widget is untouched. The human
## flew the pair and called it: *"the square indicator that was previously there
## is now redundant. we can keep it for future targeting systems for combat, but
## an arrow is way better to indicate a course path."* So `GateMarker` keeps its
## box and its flat arrow for the sortie's EXIT and for whatever targets a combat
## system marks later; a course just stops asking for one.
func _aim_course_arrow() -> void:
	var gates: Array = _drill.get("gates", []) as Array
	var reached: int = _gates_passed()
	if reached >= gates.size():
		_arrow.aim(Vector3.ZERO, Vector3.ZERO, _drone.global_position)
		return
	var onward: Vector3 = DrillBook.leg_direction(_drill_id, reached)
	if onward == Vector3.ZERO and reached > 0:
		# THE LAST GATE HAS NO NEXT LEG, so it borrows the one that arrives at
		# it: "straight on through and you are done". Pointing it anywhere else
		# would be inventing a waypoint past the finish.
		onward = ((gates[reached] as Vector3) - (gates[reached - 1] as Vector3)).normalized()
	_arrow.aim(gates[reached], onward, _drone.global_position)

## BUILT FROM `DrillBook`, NOT FROM THE SCENE FILE. The gate list is the same one
## `DrillMeasures` scores against, so a gate cannot move in the world without the
## scoring moving with it — which is the failure a course laid out by hand in a
## .tscn invites the first time someone nudges one.
##
## The gates are the shipped `environment/gate.tscn`, solid on purpose: a curtain
## you fly through is a checkpoint, and a frame that costs you if you clip it is
## a gate. The pylons only ever FLANK the line, so a tight run threads them
## untouched and the ideal path stays the straight one — otherwise every pilot's
## path ratio would carry the same forced detour and the measure would say less.
func _build_course() -> void:
	var gate_scene: PackedScene = load("res://scenes/environment/gate.tscn")
	# THE SHIPPED GATE IS ONE SIZE, so a course states the opening it wants and
	# the frame is scaled to it. `environment/gate.tscn` has a 3.0 m hole, which
	# is a `gate_half.x` of 1.5, so that is the divisor — and uniformly, because a
	# non-uniform scale on a collision shape is a Godot warning and a lie about
	# the hole the pilot is aiming at.
	var half: Vector2 = _drill["gate_half"]
	var gate_scale: float = half.x / 1.5
	for centre: Vector3 in _drill["gates"]:
		var gate: Node3D = gate_scene.instantiate() as Node3D
		gate.position = centre
		gate.scale = Vector3.ONE * gate_scale
		add_child(gate)
	var height: float = float(_drill["pylon_height"])
	var radius: float = float(_drill["pylon_radius"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var material := StandardMaterial3D.new()
	# Amber, because the palette says amber is course pylons (CLAUDE.md).
	material.albedo_color = Color(0.5, 0.32, 0.06)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.62, 0.15)
	material.emission_energy_multiplier = 1.8
	mesh.material = material
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_arrow = CourseArrow.new()
	add_child(_arrow)
	# Sized to the gate it marks, so a course with tighter gates gets smaller
	# marks without anybody editing the marker.
	_arrow.build_for(_drill["gate_half"])
	for pair: Array in _drill["pylons"]:
		for side: float in [-1.0, 1.0]:
			var body := StaticBody3D.new()
			body.position = (pair[0] as Vector3) + Vector3(float(pair[1]) * side, 0.0, 0.0)
			var view := MeshInstance3D.new()
			view.mesh = mesh
			body.add_child(view)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			add_child(body)


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
