extends SceneTree

## THE DRILL RUNNER'S PLUMBING TEST — a scripted pilot flies a whole drill so
## that a broken state machine is found here rather than by the human, mid-flight,
## after they have already set aside twenty minutes for it.
##
## **IT IS NOT A MEASUREMENT AND ITS NUMBERS ARE NOT DATA.** The bot marks
## `rotor_out` by reading the rotor's health directly, which is the exact thing
## the drill exists to ask a human about; that is fine here because what is under
## test is whether the staircase fires, the window closes, the reduction runs and
## the artifact lands. Nothing it prints belongs anywhere near a prediction.
##
## OFF THE BOARD, and deliberately: it spends real seconds because Godot paces
## physics to wall-clock, so a 20-second window costs 20 seconds. Run it after
## touching `drill_runner.gd`.
##
##   <godot> --headless -s scripts/tests/drill_smoke.gd --path . \
##       -- --drill hold_tilt --out <dir> --pilot smoke-bot
##
## `--out` is passed straight through to the runner, so the test writes into a
## scratch directory and never touches `user://` — the standing rule that a
## harness must not borrow the human's files still applies to a test that happens
## to drive an interactive scene. `--pilot` is REQUIRED here and refused if
## missing: an artifact that says "human" is a claim about where a number came
## from, and a scripted run must never be able to make it.

const SCENE: String = "res://scenes/drill.tscn"
## Generous: hold_tilt needs its 20 s window plus the climb, rotor_out needs the
## random wait plus enough staircase to reach the bot's trigger.
const TIMEOUT_S: float = 75.0

var _runner: Node3D
var _drone: FlightController
var _drill_id: String = "hold_tilt"
var _out: String = ""
var _elapsed: float = 0.0
var _armed_at: float = -1.0
var _marked_at: float = 0.0
var _last_mark: float = -99.0
var _marked: bool = false
var _failures: PackedStringArray = []
var _settle_frames: int = -1
var _done: bool = false


func _initialize() -> void:
	TunableConfig.user_overrides_enabled = false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--drill")
	if at >= 0 and at + 1 < args.size():
		_drill_id = args[at + 1]
	at = args.find("--out")
	if at < 0 or at + 1 >= args.size():
		print("[smoke] FAIL: --out <dir> is required so this never writes into user://")
		quit(1)
		return
	_out = args[at + 1]
	if not args.has("--pilot"):
		print("[smoke] FAIL: pass `--pilot smoke-bot` too, so the artifact cannot be read as a human reading")
		quit(1)
		return
	_runner = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_runner)
	_drone = _runner.get_node("Drone") as FlightController
	print("[smoke] flying %s into %s" % [_drill_id, _out])
	physics_frame.connect(_on_frame)


func _on_frame() -> void:
	if _done:
		return
	_elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if _elapsed > TIMEOUT_S:
		_failures.append("timed out after %.0f s without finishing an attempt" % TIMEOUT_S)
		_finish()
		return
	if not _drone.armed:
		if _elapsed > 0.5:
			_drone.arm()
		return
	if _armed_at < 0.0:
		_armed_at = _elapsed
		_drone.rate_override_enabled = true
	# Latched, because the trigger that starts the wrap-up stops being true: the
	# runner repairs the rotor the moment the attempt ends.
	if _settle_frames >= 0:
		_settle_then_finish()
		return
	_fly()


## Altitude hold plus whatever the drill needs, in the shape `ReferencePilot`
## uses: a PD around hover, divided by how much of the thrust axis is still
## pointing up.
func _fly() -> void:
	var since_arm: float = _elapsed - _armed_at
	var hold_alt: float = 265.0
	var target_tilt: float = 0.0
	if _marked and _drill_id == "hold_tilt":
		target_tilt = float(DrillBook.drill("hold_tilt")["target_tilt_deg"])
	var tilt: float = GameHud.HorizonLine.tilt_degrees(_drone.global_basis.y)
	# Pilot axis: y is pitch, positive nose up. Nose DOWN to build tilt.
	var pitch_rate: float = clampf((tilt - target_tilt) * 4.0, -60.0, 60.0)
	_drone.rate_override = Vector3(0.0, pitch_rate, 0.0)
	_drone.throttle_override = _altitude_throttle(hold_alt)
	if not _marked:
		# Keep asking rather than counting seconds: the runner refuses a mark
		# until its own gate is satisfied, so this waits for the real condition
		# instead of a guess about how long settling takes.
		#
		# ONCE EVERY HALF SECOND, NOT EVERY FRAME. The runner consumes a mark on
		# its NEXT tick, so a mark queued every frame lands a second one INSIDE
		# the attempt it just started — which `rotor_out` correctly reads as
		# calling before the failure began, voids, and loops forever.
		if since_arm > 3.0 and _elapsed - _last_mark > 0.5:
			_last_mark = _elapsed
			_runner.mark()
		_marked = _runner.running()
		if _marked:
			_marked_at = _elapsed
		return
	if _drill_id == "rotor_out" and _drone.motor_health(0) <= 0.75:
		# A bot cannot FEEL anything, so it reads the rotor. See the header: this
		# is the plumbing under test, not the question the drill asks.
		_runner.mark()
		_settle_then_finish()
	elif _drill_id == "hold_tilt" and _elapsed - _marked_at > 26.0:
		_settle_then_finish()


func _altitude_throttle(target_alt: float) -> float:
	var error: float = target_alt - _drone.global_position.y
	var demand: float = _drone.hover_throttle() + _drone.config.autopilot_climb_gain \
			* (clampf(error, -4.0, 4.0) - _drone.linear_velocity.y)
	return clampf(demand / maxf(_drone.global_basis.y.dot(Vector3.UP), 0.25), 0.0, 1.0)


## A DELIBERATE COUNTDOWN, NOT A GUESS. `mark()` only sets a flag; the runner
## consumes it on its NEXT physics tick and writes the artifact from there. This
## signal fires after that tick, so reading the file in the same frame the mark
## was placed would always find the previous attempt or nothing at all.
func _settle_then_finish() -> void:
	if _settle_frames < 0:
		_settle_frames = 5
		return
	_settle_frames -= 1
	if _settle_frames <= 0:
		_finish()


func _finish() -> void:
	_done = true
	var path: String = _artifact()
	if path.is_empty():
		_failures.append("no artifact appeared in %s" % _out)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var artifact: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
		var attempts: Array = artifact.get("attempts", []) as Array
		print("[smoke] %s: %d attempt(s), %d voided, fingerprint %s"
				% [_drill_id, int(artifact.get("attempt_count", 0)),
				int(artifact.get("voided_count", 0)),
				artifact.get("prediction_fingerprint", "?")])
		if attempts.is_empty():
			_failures.append("the artifact records no completed attempt — the window never closed")
		else:
			var measures: Dictionary = (attempts[0] as Dictionary)["measures"]
			print("[smoke] measures: %s" % JSON.stringify(measures))
			for name: String in DrillBook.measure_names(_drill_id):
				if not measures.has(name):
					_failures.append("the attempt is missing '%s'" % name)
			if _drill_id == "rotor_out" \
					and float(measures.get("detect_loss", 0.0)) <= 0.0:
				_failures.append("detect_loss came back %.2f — the staircase never bit"
						% float(measures.get("detect_loss", 0.0)))
			if _drill_id == "hold_tilt" and float(measures.get("hold_s", 0.0)) <= 0.0:
				_failures.append("hold_s came back 0 — a bot commanding the tilt directly should hold it")
		if String(artifact.get("prediction_fingerprint", "")).is_empty():
			_failures.append("the artifact carries no prediction fingerprint, so nothing can be compared against it")
	_runner.queue_free()
	if _failures.is_empty():
		print("[smoke] PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("[smoke] FAIL: %s" % failure)
		print("[smoke] FAIL")
		quit(1)


func _artifact() -> String:
	var dir: DirAccess = DirAccess.open(_out)
	if dir == null:
		return ""
	var newest: String = ""
	for name: String in dir.get_files():
		if name.begins_with("%s_" % _drill_id) and name.ends_with(".json"):
			newest = "%s/%s" % [_out, name]
	return newest
