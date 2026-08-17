extends SceneTree

## THE PILOT-IN-THE-LOOP INSTRUMENT'S GUARD (task 8).
##
## The instrument's product is an argument between a committed prediction and a
## human flight, so what has to be guarded is not "does it fly" — it is whether
## the argument can be RIGGED. Every claim below was written by asking the
## project's own question: *would this still pass if the feature were deleted?*
##
## Ten claims, in the order they would embarrass someone:
##
##  1. Every drill states a situation, a task and a success condition, and every
##     drill in the book has a runner that can actually fly it.
##  2. Every drill has a COMMITTED prediction with a band and a reason for every
##     measure it declares — and no band wider than 40% of what could physically
##     have happened. **That last part is the anti-theatre claim.** A prediction
##     hedged to "somewhere between nothing and everything" passes every other
##     test in this file and means nothing.
##  3. Sentinels sit at the WORST end of the plausible range, so a pilot who
##     never produced a reading can never score well by not producing it.
##  4. The verdict arithmetic: inside is a hit, outside is a miss with a
##     direction and a distance.
##  5. `hold_s` counts the longest UNBROKEN run. A flight that dips in and out
##     for nine of twenty seconds must read 5, not 9 — total-time-in-band is the
##     obvious implementation and it is wrong, and nothing else here would see
##     it.
##  6. `rotor_out` measures drift and sag from the FAILURE'S OWN START, not from
##     the window start. The synthetic flight below moves 40 m before the rotor
##     is touched, so a window-start implementation reads 40 and this reads 0.
##  7. `best_of` follows each measure's own direction: min where low is better,
##     max where high is better.
##  8. `compute` returns every measure the book declares, for every drill. A
##     measure added to the book and never wired reads as a missing key here.
##  9. THE REFUSALS, and they are why the instrument is not theatre: a
##     fingerprint that does not match what was flown, or a prediction committed
##     AFTER the flight, must produce a refusal and NO verdict rows at all.
## 10. The fingerprint covers the REASONS, not only the numbers. Rewriting an
##     argument while leaving a band alone is a different prediction and must
##     invalidate the same way.
##
## MUTATIONS ON RECORD (each fails a different claim):
##   widen hold_tilt's `hold_s` band to 0..20        -> claim 2
##   make `verdict` always return HIT                -> claim 4
##   count total in-band time instead of the run     -> claim 5
##   measure rotor drift from samples[0]             -> claim 6
##   drop the fingerprint test in `refusal`          -> claim 9
##   fingerprint the numbers without the reasons     -> claim 10
##
## Run: <godot> --headless -s scripts/tests/drill_check.gd --path .

const RUNNER_SOURCE: String = "res://scripts/drills/drill_runner.gd"

var _failures: PackedStringArray = []


func _initialize() -> void:
	# Pure arithmetic over repo files, but the switch is set anyway: this file
	# must never be able to read a human's tuning, whatever it grows into.
	TunableConfig.user_overrides_enabled = false
	_claim_1_drills_are_stated()
	_claim_2_predictions_are_falsifiable()
	_claim_3_sentinels_are_the_worst_case()
	_claim_4_verdicts()
	_claim_5_hold_is_unbroken()
	_claim_6_rotor_measures_from_the_failure()
	_claim_6b_course_gates()
	_claim_7_best_of_follows_direction()
	_claim_8_every_measure_is_computed()
	_claim_9_refusals()
	_claim_10_fingerprint_covers_reasons()
	if _failures.is_empty():
		print("")
		print("[drill] PASS")
		quit(0)
	else:
		print("")
		for failure: String in _failures:
			print("[drill] FAIL: %s" % failure)
		print("[drill] FAIL")
		quit(1)


## A drill nobody can fly is a drill that exists only in a table. The runner is
## read as SOURCE — the `sortie_check` precedent, and the only way to catch a
## book row with no code behind it without booting a scene and a controller.
func _claim_1_drills_are_stated() -> void:
	var source: String = FileAccess.get_file_as_string(RUNNER_SOURCE)
	if source.is_empty():
		_failures.append("cannot read %s" % RUNNER_SOURCE)
	for id: String in DrillBook.ids():
		var brief: String = "\n".join(DrillBook.brief_lines(id))
		for heading: String in ["SITUATION", "TASK", "SUCCESS", "RECORDED"]:
			if not brief.contains(heading):
				_failures.append("%s: the brief has no %s section" % [id, heading])
		if DrillBook.measure_names(id).is_empty():
			_failures.append("%s: declares no measures" % id)
		if not source.contains('"%s"' % id):
			_failures.append("%s: no branch in drill_runner.gd — the book declares a drill nothing can fly"
					% id)
	print("[drill] claim 1: %d drills, all stated and all reachable from the runner"
			% DrillBook.ids().size())


func _claim_2_predictions_are_falsifiable() -> void:
	for id: String in DrillBook.ids():
		var prediction: Dictionary = DrillPredictions.load_prediction(id)
		for problem: String in DrillPredictions.problems(id, prediction):
			_failures.append(problem)
		if prediction.is_empty():
			continue
		var widths: PackedStringArray = []
		for name: String in DrillBook.measure_names(id):
			var band: Dictionary = DrillPredictions.band(prediction, name)
			var plausible: Array = DrillBook.measure(id, name)["plausible"]
			var span: float = float(plausible[1]) - float(plausible[0])
			widths.append("%s %.0f%%" % [name, 100.0
					* (float(band.get("high", 0.0)) - float(band.get("low", 0.0))) / span])
		print("[drill] claim 2: %s prediction %s, band widths %s"
				% [id, DrillPredictions.fingerprint(prediction), ", ".join(widths)])


## A measure the pilot never produced must read as a failure, not as a zero that
## happens to be a good score. `hold_s` is the case that matters: low would be
## the natural default and high is what "better" means for it.
func _claim_3_sentinels_are_the_worst_case() -> void:
	for id: String in DrillBook.ids():
		for name: String in DrillBook.measure_names(id):
			var spec: Dictionary = DrillBook.measure(id, name)
			var plausible: Array = spec["plausible"]
			var worst: float = float(plausible[0]) if String(spec["better"]) == "high" \
					else float(plausible[1])
			if not is_equal_approx(float(spec["sentinel"]), worst):
				_failures.append("%s.%s: sentinel is %.2f but the worst plausible value is %.2f — a reading nobody produced would score better than a bad one"
						% [id, name, float(spec["sentinel"]), worst])
	print("[drill] claim 3: every sentinel sits at its measure's worst end")


func _claim_4_verdicts() -> void:
	var band: Dictionary = {"low": 2.0, "high": 5.0}
	var cases: Array = [
		[3.5, DrillCompare.HIT, 0.0],
		[2.0, DrillCompare.HIT, 0.0],
		[5.0, DrillCompare.HIT, 0.0],
		[1.25, DrillCompare.UNDER, 0.75],
		[6.5, DrillCompare.OVER, 1.5],
	]
	for case: Array in cases:
		var got: Dictionary = DrillCompare.verdict(band, float(case[0]))
		if String(got["result"]) != String(case[1]) \
				or not is_equal_approx(float(got["miss"]), float(case[2])):
			_failures.append("verdict(2..5, %.2f) gave %s by %.2f, expected %s by %.2f"
					% [case[0], got["result"], got["miss"], case[1], case[2]])
	print("[drill] claim 4: verdicts hit inside the band and miss with a direction outside it")


## THE ONE THAT REFUSES THE OBVIOUS IMPLEMENTATION. Nine of twenty seconds are
## spent inside the band, in two runs of 5 and 4 with a gap between them. A
## pilot who cannot stay in the band for more than five seconds has not held
## anything, and `hold_s` must say 5.
func _claim_5_hold_is_unbroken() -> void:
	var target: float = float(DrillBook.drill("hold_tilt")["target_tilt_deg"])
	var samples: Array = []
	var t: float = 0.0
	while t < 20.0:
		# 0..3 climbing in, 3..8 held, 8..11 broken out, 11..15 held, then out.
		var tilt: float = 0.0
		if t < 3.0:
			tilt = target - 20.0
		elif t < 8.0:
			tilt = target + 1.0
		elif t < 11.0:
			tilt = target + 18.0
		elif t < 15.0:
			tilt = target - 2.0
		else:
			tilt = target + 15.0
		samples.append({"t": t, "tilt_deg": tilt,
				"pos": Vector3(0.0, 250.0, 0.0), "loss": 0.0})
		t += 1.0 / 60.0
	var got: Dictionary = DrillMeasures.compute("hold_tilt", samples)
	print("[drill] claim 5: capture %.2f s, longest unbroken hold %.2f s, rms %.2f deg"
			% [got["capture_s"], got["hold_s"], got["rms_deg"]])
	if absf(float(got["capture_s"]) - 3.0) > 0.05:
		_failures.append("capture_s read %.2f on a flight that first entered the band at 3.00 s"
				% got["capture_s"])
	if absf(float(got["hold_s"]) - 5.0) > 0.05:
		_failures.append("hold_s read %.2f on a flight with runs of 5 s and 4 s — the measure is the LONGEST UNBROKEN run, and 9.00 means it is adding them up"
				% got["hold_s"])
	# A flight that never reaches the band takes sentinels, not zeros.
	var never: Array = []
	t = 0.0
	while t < 20.0:
		never.append({"t": t, "tilt_deg": 0.0, "pos": Vector3.ZERO, "loss": 0.0})
		t += 1.0 / 60.0
	var missed: Dictionary = DrillMeasures.compute("hold_tilt", never)
	if not is_equal_approx(float(missed["capture_s"]), 20.0) \
			or not is_equal_approx(float(missed["hold_s"]), 0.0) \
			or not is_equal_approx(float(missed["rms_deg"]), 25.0):
		_failures.append("a flight that never entered the band read capture %.2f hold %.2f rms %.2f, expected the sentinels 20.00 / 0.00 / 25.00"
				% [missed["capture_s"], missed["hold_s"], missed["rms_deg"]])


## THE ANTI-CONSTANT CLAIM FOR THIS DRILL. The synthetic pilot flies 40 m and
## climbs 12 m BEFORE the rotor is touched, and holds still afterwards apart
## from a planted 6 m of drift and 3 m of sag. Measuring from the window start
## gives 46 and -9; measuring from the failure gives 6 and 3.
func _claim_6_rotor_measures_from_the_failure() -> void:
	var samples: Array = []
	var t: float = 0.0
	var step: float = float(DrillBook.drill("rotor_out")["step_loss"])
	while t < 20.0:
		var before: bool = t < 5.0
		var loss: float = 0.0 if before else minf(step * floor((t - 5.0) / 2.0 + 1.0), 1.0)
		var travelled: float = 40.0 * (t / 5.0) if before else 40.0 + 6.0 * ((t - 5.0) / 15.0)
		var height: float = 250.0 + 12.0 * (t / 5.0) if before else 262.0 - 3.0 * ((t - 5.0) / 15.0)
		samples.append({"t": t, "tilt_deg": 0.0,
				"pos": Vector3(travelled, height, 0.0), "loss": loss})
		t += 1.0 / 60.0
	var called: Dictionary = DrillMeasures.compute("rotor_out", samples, {"call_t": 20.0})
	print("[drill] claim 6: detect_loss %.2f, drift %.2f m, sag %.2f m (40 m and 12 m of it flown BEFORE the failure)"
			% [called["detect_loss"], called["drift_m"], called["sag_m"]])
	if absf(float(called["drift_m"]) - 6.0) > 0.2:
		_failures.append("drift_m read %.2f, expected 6.00 — the 40 m flown before the rotor was touched is not the pilot missing a failure"
				% called["drift_m"])
	if absf(float(called["sag_m"]) - 3.0) > 0.2:
		_failures.append("sag_m read %.2f, expected 3.00 — the 12 m climbed before the failure is not sag"
				% called["sag_m"])
	# A call placed at 9 s is three steps in (5..7, 7..9, 9..11), so 0.15.
	var early: Dictionary = DrillMeasures.compute("rotor_out", samples, {"call_t": 9.0})
	if absf(float(early["detect_loss"]) - 0.15) > 0.001:
		_failures.append("a call 4 s into a 5%%-every-2-s staircase read %.3f, expected 0.150"
				% early["detect_loss"])
	var uncalled: Dictionary = DrillMeasures.compute("rotor_out", samples, {"call_t": -1.0})
	if not is_equal_approx(float(uncalled["detect_loss"]), 1.0):
		_failures.append("a run with no call read detect_loss %.2f, expected the 1.00 sentinel"
				% uncalled["detect_loss"])


## THE COURSE, FLOWN SYNTHETICALLY. Gate detection lives in `DrillMeasures`
## rather than on an Area3D precisely so this is possible: a perfect run, a run
## that skips a gate, and a run that goes back through one all get scored here
## without a scene, a controller or a pilot.
func _claim_6b_course_gates() -> void:
	var gates: Array = DrillBook.drill("course")["gates"]
	var half: Vector2 = DrillBook.drill("course")["gate_half"]
	# 1. THE DIRECTION MATTERS. A gate flown the wrong way must not count, or a
	#    pilot who overshoots and comes back collects it twice.
	var centre: Vector3 = gates[0]
	if not DrillMeasures.crossed_gate(centre, half, centre + Vector3(0, 0, 3),
			centre - Vector3(0, 0, 3)):
		_failures.append("a straight pass through the middle of gate 1 was not counted")
	if DrillMeasures.crossed_gate(centre, half, centre - Vector3(0, 0, 3),
			centre + Vector3(0, 0, 3)):
		_failures.append("flying BACKWARDS through a gate counted it — an overshoot and return would collect the same gate twice")
	# 2. THE OPENING IS THE OPENING. Passing the gate's plane outside the frame is
	#    a miss, and a check that only ever flies the centre would never say so.
	var wide: Vector3 = centre + Vector3(half.x + 1.0, 0.0, 0.0)
	if DrillMeasures.crossed_gate(centre, half, wide + Vector3(0, 0, 3),
			wide - Vector3(0, 0, 3)):
		_failures.append("crossing the gate PLANE %.1f m outside the frame counted as flying the gate"
				% (half.x + 1.0))
	# 3. A PERFECT RUN: straight from gate to gate, so the ratio is 1.00 and the
	#    time is the length over the speed.
	var speed: float = 20.0
	var clean: Array = _fly_course(gates, speed, -1, 0.0)
	var scored: Dictionary = DrillMeasures.compute("course", clean)
	var length: float = DrillBook.course_length("course")
	print("[drill] claim 6b: %.0f m of course; a clean %d m/s run reads %.2f s, %d touches, ratio %.3f"
			% [length, int(speed), scored["time_s"], int(scored["contacts"]),
			scored["path_ratio"]])
	if absf(float(scored["path_ratio"]) - 1.0) > 0.02:
		_failures.append("a run flown exactly down the gate centres read a path ratio of %.3f — the straight line IS the denominator, so it has to read 1.00"
				% scored["path_ratio"])
	if absf(float(scored["time_s"]) - length / speed) > 0.3:
		_failures.append("a %d m/s run over %.0f m read %.2f s, expected %.2f"
				% [int(speed), length, scored["time_s"], length / speed])
	if int(scored["contacts"]) != 0:
		_failures.append("a clean run recorded %d touches" % int(scored["contacts"]))
	# 4. SKIP A GATE AND THE COURSE IS NOT FLOWN. Sentinels, not a fast time —
	#    this is the claim that stops the drill rewarding a pilot for cutting the
	#    corner that a naive "did you reach the end" test would pass.
	var cheated: Array = _fly_course(gates, speed, 3, 0.0)
	var cheat_score: Dictionary = DrillMeasures.compute("course", cheated)
	if not is_equal_approx(float(cheat_score["time_s"]), 120.0):
		_failures.append("a run that flew PAST gate 4 instead of through it still scored a time of %.2f s — the gates are an ORDER, and skipping one must not finish the course"
				% cheat_score["time_s"])
	# 5. TOUCHES ARE EDGES, NOT TICKS. The same scrape sampled sixty times a
	#    second is one touch, and counting samples would price it as fifty.
	var scraped: Array = _fly_course(gates, speed, -1, 0.0)
	for i: int in range(40, 70):
		(scraped[i] as Dictionary)["contacts"] = 3
	var scrape_score: Dictionary = DrillMeasures.compute("course", scraped)
	if int(scrape_score["contacts"]) != 1:
		_failures.append("one unbroken 30-sample scrape counted as %d touches, expected 1"
				% int(scrape_score["contacts"]))
	# AND A SINGLE-SAMPLE BLIP MUST COUNT. This is the other half of a real bug:
	# the human reported a collision that the artifact scored as ZERO touches, and
	# the 240 Hz flight recorder showed the contact lasted 0.004 s — one physics
	# tick, which fell between two 60 Hz samples. The runner now peak-holds
	# between samples so the blip reaches the reduction; this claim is the half
	# that makes sure the reduction does not then throw it away by demanding two
	# consecutive samples before it believes a touch.
	var blipped: Array = _fly_course(gates, speed, -1, 0.0)
	(blipped[55] as Dictionary)["contacts"] = 2
	var blip_score: Dictionary = DrillMeasures.compute("course", blipped)
	if int(blip_score["contacts"]) != 1:
		_failures.append("a contact present in exactly ONE sample counted as %d touches, expected 1 — a real collision lasted a single 240 Hz tick and this is the last place it can be dropped"
				% int(blip_score["contacts"]))
	print("[drill] claim 6b: a skipped gate scores the sentinel, and a 30-sample scrape is 1 touch")
	# 6. THE MARKER POINTS AT THE NEXT GATE. The human's design is one mark doing
	#    two jobs — it sits on the gate you must fly and points where the course
	#    goes after it — so the direction has to be the REAL leg and not a guess.
	#    The runner only projects this onto the screen, so a marker aimed at the
	#    wrong gate would be invisible to any test that never drew a frame.
	for index: int in gates.size():
		var leg: Vector3 = DrillBook.leg_direction("course", index)
		if index + 1 >= gates.size():
			if leg != Vector3.ZERO:
				_failures.append("the LAST gate claims a heading of %s — nothing follows it, and an arrow there would point the pilot at a gate that does not exist"
						% str(leg))
			continue
		var want: Vector3 = ((gates[index + 1] as Vector3)
				- (gates[index] as Vector3)).normalized()
		if leg.distance_to(want) > 0.001:
			_failures.append("gate %d's marker heads %s where the next gate is %s"
					% [index + 1, str(leg), str(want)])
	# 7. THE PULSE TRAVELS OUTWARD, and its direction is the whole cue. A static
	#    wedge seen from behind is ambiguous — pointing away and pointing back
	#    differ only by shading — so the animation is what makes the marker
	#    unreadable backwards. Add the index to the phase instead of subtracting
	#    it and the wave runs at the pilot, meaning the exact opposite; nothing
	#    but this claim would notice.
	var previous_peak: float = -1.0
	for i: int in CourseArrow.CHEVRONS:
		if CourseArrow.wedge_offset(i) <= previous_peak:
			_failures.append("wedge %d sits at %.2f m, no further out than the one before it"
					% [i, CourseArrow.wedge_offset(i)])
		previous_peak = CourseArrow.wedge_offset(i)
		var lit: float = CourseArrow.pulse(0.0, i)
		if lit < -0.001 or lit > 1.001:
			_failures.append("wedge %d burns at %.3f, outside 0 to 1" % [i, lit])
	# The nearest wedge peaks FIRST. Sample the moment each one is brightest and
	# demand the peaks arrive in order, outward.
	var peak_times: Array[float] = []
	for i: int in CourseArrow.CHEVRONS:
		var best_t: float = 0.0
		var best: float = -1.0
		var steps: int = 200
		for step: int in steps:
			var t: float = float(step) / float(steps) * CourseArrow.PULSE_S
			var lit: float = CourseArrow.pulse(t, i)
			if lit > best:
				best = lit
				best_t = t
		peak_times.append(best_t)
	print("[drill] claim 6b: wedge peaks at %s s — the wave must run OUTWARD"
			% str(peak_times))
	for i: int in range(1, peak_times.size()):
		if peak_times[i] <= peak_times[i - 1]:
			_failures.append("wedge %d peaks at %.3f s, no later than wedge %d at %.3f — the pulse is running back toward the pilot, which means the opposite of what the marker says"
					% [i, peak_times[i], i - 1, peak_times[i - 1]])
	# The flat HUD arrow is KEPT, because the sortie's EXIT and any future combat
	# target still want a box and a screen-space pointer; it is only the COURSE
	# that stopped asking for one.
	var arrow: PackedVector2Array = GameHud.GateMarker.arrow_points(
			Vector2.ZERO, Vector2(10.0, 0.0), 30.0)
	if arrow.is_empty():
		_failures.append("a marker with a heading drew no arrow")
	elif arrow[1] != Vector2(30.0, 0.0):
		_failures.append("the arrow tip landed at %s for a 30 px arrow along +x, expected (30, 0)"
				% str(arrow[1]))
	if not GameHud.GateMarker.arrow_points(Vector2.ZERO, Vector2.ZERO, 30.0).is_empty():
		_failures.append("a marker with NO heading still drew an arrow — the sortie's exit has no next waypoint and must show the plain box")
	print("[drill] claim 6b: every gate heads at the next one, the last heads nowhere, and the chain runs outward")


## A synthetic flight: straight legs between gate centres at a fixed speed.
## `skip` names a gate to fly PAST (offset sideways so the plane is crossed
## outside the frame), which is how the order claim gets something to refuse.
func _fly_course(gates: Array, speed: float, skip: int, wander: float) -> Array:
	var samples: Array = []
	var step: float = 1.0 / 60.0
	var t: float = 0.0
	var at: Vector3 = (gates[0] as Vector3) + Vector3(0.0, 0.0, 12.0)
	for index: int in gates.size():
		var target: Vector3 = gates[index]
		if index == skip:
			target += Vector3(9.0, 0.0, 0.0)
		while at.distance_to(target) > speed * step:
			at = at.move_toward(target, speed * step)
			samples.append({"t": t, "tilt_deg": 0.0, "pos": at,
					"loss": 0.0, "contacts": 0})
			t += step
	# Run on past the last gate, so its crossing is a real step and not the
	# array simply ending on top of it.
	for i: int in 30:
		at += Vector3(0.0, 0.0, -speed * step)
		samples.append({"t": t, "tilt_deg": 0.0, "pos": at,
				"loss": 0.0, "contacts": 0})
		t += step
	return samples


func _claim_7_best_of_follows_direction() -> void:
	var attempts: Array = [
		{"measures": {"capture_s": 4.0, "hold_s": 3.0, "rms_deg": 9.0}},
		{"measures": {"capture_s": 1.5, "hold_s": 12.0, "rms_deg": 2.0}},
		{"measures": {"capture_s": 2.5, "hold_s": 7.0, "rms_deg": 5.0}},
	]
	var best: Dictionary = DrillMeasures.best_of("hold_tilt", attempts)
	if not is_equal_approx(float(best["capture_s"]), 1.5) \
			or not is_equal_approx(float(best["rms_deg"]), 2.0):
		_failures.append("best_of took %.2f / %.2f for the low-is-better measures, expected 1.50 / 2.00"
				% [best["capture_s"], best["rms_deg"]])
	if not is_equal_approx(float(best["hold_s"]), 12.0):
		_failures.append("best_of took %.2f for hold_s, expected 12.00 — high is better for that one and a blanket min would read 3.00"
				% best["hold_s"])
	if not is_equal_approx(DrillMeasures.spread("hold_tilt", attempts, "hold_s"), 9.0):
		_failures.append("spread of hold_s read %.2f across 3, 7 and 12, expected 9.00"
				% DrillMeasures.spread("hold_tilt", attempts, "hold_s"))
	print("[drill] claim 7: best-of took 1.50 / 12.00 / 2.00 from three attempts, spread 9.00 on hold_s")


## A measure declared in the book and never wired into the reduction would show
## up as a good score in the artifact (the sentinel path fills it) and as
## nothing at all in the report. It shows up here as a missing key.
func _claim_8_every_measure_is_computed() -> void:
	for id: String in DrillBook.ids():
		var got: Dictionary = DrillMeasures.compute(id, [
			{"t": 0.0, "tilt_deg": 30.0, "pos": Vector3.ZERO, "loss": 0.1},
			{"t": 1.0, "tilt_deg": 30.0, "pos": Vector3.ONE, "loss": 0.2},
		], {"call_t": 1.0})
		for name: String in DrillBook.measure_names(id):
			if not got.has(name):
				_failures.append("%s: the book declares '%s' and compute() never returns it"
						% [id, name])
	print("[drill] claim 8: every declared measure comes back from compute()")


## THE INSTRUMENT'S SPINE. Three ways the comparison must be refused, and in
## every one of them the report must carry NO verdict rows — a refusal that
## still prints a table is a refusal nobody reads.
func _claim_9_refusals() -> void:
	var id: String = "hold_tilt"
	var prediction: Dictionary = DrillPredictions.load_prediction(id)
	var flown: int = 1_760_000_000
	var honest: Dictionary = {
		"drill": id, "flown_unix": flown, "flown_utc": "test", "pilot": "test",
		"frame": "kestrel", "attempt_count": 1, "voided_count": 0,
		"prediction_fingerprint": DrillPredictions.fingerprint(prediction),
		"attempts": [{"measures": {"capture_s": 1.0, "hold_s": 12.0, "rms_deg": 3.0}}],
		"summary": {"capture_s": 1.0, "hold_s": 12.0, "rms_deg": 3.0},
	}
	if not DrillCompare.refusal(prediction, honest, flown - 3600).is_empty():
		_failures.append("an honest run against its own prediction was refused: %s"
				% DrillCompare.refusal(prediction, honest, flown - 3600))
	var good: PackedStringArray = DrillCompare.report_lines(id, prediction, honest, flown - 3600)
	if not "\n".join(good).contains("capture_s"):
		_failures.append("an accepted comparison printed no verdict row for capture_s")
	# 1. The prediction was edited after the flight.
	var stale: Dictionary = honest.duplicate(true)
	stale["prediction_fingerprint"] = "deadbeef"
	# 2. The prediction was committed after the flight.
	# 3. The run never recorded what it was flown against.
	var unstamped: Dictionary = honest.duplicate(true)
	unstamped["prediction_fingerprint"] = ""
	var refusals: Array = [
		["edited prediction", stale, flown - 3600],
		["prediction committed after the flight", honest, flown + 3600],
		["run with no fingerprint", unstamped, flown - 3600],
	]
	for case: Array in refusals:
		var artifact: Dictionary = case[1]
		var at: int = int(case[2])
		if DrillCompare.refusal(prediction, artifact, at).is_empty():
			_failures.append("%s was NOT refused" % case[0])
			continue
		var text: String = "\n".join(DrillCompare.report_lines(id, prediction, artifact, at))
		if not text.contains("COMPARISON REFUSED"):
			_failures.append("%s: the report does not say it refused" % case[0])
		if text.contains("HIT") or text.contains("inside the band"):
			_failures.append("%s: the report printed verdicts anyway — a refusal that still grades is not a refusal"
					% case[0])
	print("[drill] claim 9: an honest run compares; an edited prediction, a late prediction and an unstamped run are all refused with no verdicts")


## The claim is not only "between 10 and 17 seconds", it is "between 10 and 17
## seconds BECAUSE the printed tilt closes a loop that eyeballing a horizon does
## not". Rewriting the second half is a different prediction.
func _claim_10_fingerprint_covers_reasons() -> void:
	var prediction: Dictionary = DrillPredictions.load_prediction("hold_tilt")
	if prediction.is_empty():
		return
	var before: String = DrillPredictions.fingerprint(prediction)
	var reworded: Dictionary = prediction.duplicate(true)
	var bands: Dictionary = reworded["bands"]
	var first: String = DrillBook.measure_names("hold_tilt")[0]
	(bands[first] as Dictionary)["why"] = "a completely different argument, same numbers"
	if DrillPredictions.fingerprint(reworded) == before:
		_failures.append("rewriting a band's reason left the fingerprint at %s — the argument is part of the claim and must invalidate with it"
				% before)
	var renumbered: Dictionary = prediction.duplicate(true)
	(renumbered["bands"][first] as Dictionary)["high"] = \
			float((prediction["bands"][first] as Dictionary)["high"]) + 1.0
	if DrillPredictions.fingerprint(renumbered) == before:
		_failures.append("widening a band left the fingerprint at %s" % before)
	print("[drill] claim 10: fingerprint %s moves on a reworded reason and on a widened band"
			% before)
