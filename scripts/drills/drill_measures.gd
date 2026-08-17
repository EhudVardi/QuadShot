class_name DrillMeasures
extends RefCounted

## SAMPLES IN, NAMED NUMBERS OUT — the whole of the drill instrument's
## arithmetic, and deliberately the only part of it that is pure.
##
## `DrillRunner` does nothing but collect a sample per physics tick and hand the
## array to `compute`. That split is what makes the instrument checkable: a
## headless check can feed a SYNTHETIC flight — a perfect hold, a hold that
## never captures, a call placed exactly 0.8 s after a failure — and assert the
## numbers that come out, without a scene, a controller or a human.
##
## It is also what keeps the runner honest. If the reduction lived inside the
## scene, "the measure" would be whatever the scene happened to accumulate, and
## nobody could tell a measurement bug from a flying one.
##
## A SAMPLE is a Dictionary:
##   t        seconds since the window opened
##   tilt_deg the airframe's tilt off vertical, EXACTLY as the HUD prints it
##            (GameHud.HorizonLine.tilt_degrees of the body +Y axis)
##   pos      world position
##   loss     the drilled rotor's lost capability, 0 healthy .. 1 dead

## Returned when a drill id has no reduction. Never silently zero: a measure
## that could not be computed must read as the worst case, not as a good score.
static func sentinels(drill_id: String) -> Dictionary:
	var out: Dictionary = {}
	for name: String in DrillBook.measure_names(drill_id):
		out[name] = float(DrillBook.measure(drill_id, name)["sentinel"])
	return out


## `context` carries the facts the samples cannot show: for `rotor_out`, the
## time the pilot called it (`call_t`, negative for "never called").
static func compute(drill_id: String, samples: Array,
		context: Dictionary = {}) -> Dictionary:
	match drill_id:
		"hold_tilt":
			return _hold_tilt(samples)
		"rotor_out":
			return _rotor_out(samples, float(context.get("call_t", -1.0)))
		"course":
			return _course(samples)
	return sentinels(drill_id)


## DID THIS STEP OF THE FLIGHT GO THROUGH THAT GATE — the whole of the course
## drill's gate logic, and it lives here rather than on an Area3D in the scene on
## purpose.
##
## An Area3D would work and would be untestable: the only way to ask whether a
## line was flown correctly would be to fly it. As arithmetic over two positions
## it takes a SYNTHETIC path, so `drill_check` can fly a perfect run, a run that
## misses one gate, and a run that goes through backwards, without a controller.
##
## The gate faces -Z, so crossing it means going from the +Z side to the -Z side.
## The direction matters: flying back through a gate the wrong way must NOT count
## it, or a pilot who overshoots and returns collects it twice.
static func crossed_gate(centre: Vector3, half: Vector2, from: Vector3,
		to: Vector3) -> bool:
	# Signed distance along the gate's facing. Positive is still short of it.
	var before: float = from.z - centre.z
	var after: float = to.z - centre.z
	if before <= 0.0 or after > 0.0:
		return false
	var span: float = before - after
	if span <= 0.0:
		return false
	var at: Vector3 = from.lerp(to, before / span)
	return absf(at.x - centre.x) <= half.x and absf(at.y - centre.y) <= half.y


## THE COURSE. Three numbers off one flown line, and they are deliberately three
## different questions: how fast (`time_s`), how clean (`contacts`) and how tight
## (`path_ratio`). A pilot can be quick and sloppy or precise and slow, and a
## single score would hide exactly that trade.
##
## Everything is measured BETWEEN the first and last gate, never from the mark:
## lining up before the start line is not part of the course, so time spent there
## must not be charged and distance flown there must not inflate the ratio.
static func _course(samples: Array) -> Dictionary:
	var out: Dictionary = sentinels("course")
	if samples.size() < 2:
		return out
	var gates: Array = DrillBook.drill("course")["gates"]
	var half: Vector2 = DrillBook.drill("course")["gate_half"]
	var next_gate: int = 0
	var start: int = -1
	var finish: int = -1
	var touches: int = 0
	var was_touching: bool = true  # Sitting on the pad is a contact; ignore it.
	var flown: float = 0.0
	for i: int in range(1, samples.size()):
		var from: Vector3 = samples[i - 1]["pos"]
		var to: Vector3 = samples[i]["pos"]
		if start >= 0 and finish < 0:
			flown += from.distance_to(to)
			# A TOUCH IS AN EDGE, NOT A TICK. Contact is sampled every frame, so
			# counting samples would price one scrape as fifty.
			var touching: bool = int(samples[i]["contacts"]) > 0
			if touching and not was_touching:
				touches += 1
			was_touching = touching
		if next_gate < gates.size() \
				and crossed_gate(gates[next_gate], half, from, to):
			if next_gate == 0:
				start = i
				was_touching = int(samples[i]["contacts"]) > 0
			next_gate += 1
			if next_gate >= gates.size():
				finish = i
				break
	if start < 0 or finish < 0:
		return out
	out["time_s"] = float(samples[finish]["t"]) - float(samples[start]["t"])
	out["contacts"] = float(touches)
	var ideal: float = DrillBook.course_length("course")
	out["path_ratio"] = flown / ideal if ideal > 0.0 else 3.0
	return out


## THE ATTITUDE HOLD. Three numbers off one channel:
##
## `capture_s` is how long it took to first get inside the band at all,
## `hold_s` is the longest UNBROKEN run inside it — unbroken matters, because a
## pilot who dips in and out for ten of twenty seconds has not held anything —
## and `rms_deg` is the steadiness, measured from first capture to the end of
## the window rather than only over the best run. That last choice is
## deliberate: an RMS taken only over the in-band samples is bounded by the
## band itself and would read ~2.9 for anyone, which is a number that cannot
## disagree with anything.
static func _hold_tilt(samples: Array) -> Dictionary:
	var out: Dictionary = sentinels("hold_tilt")
	if samples.is_empty():
		return out
	var d: Dictionary = DrillBook.drill("hold_tilt")
	var target: float = float(d["target_tilt_deg"])
	var tolerance: float = float(d["tolerance_deg"])
	var opened: float = float(samples[0]["t"])
	var capture_index: int = -1
	var best_run: float = 0.0
	var run_start: float = 0.0
	var in_run: bool = false
	for i: int in samples.size():
		var t: float = float(samples[i]["t"])
		var inside: bool = absf(float(samples[i]["tilt_deg"]) - target) <= tolerance
		if inside and capture_index < 0:
			capture_index = i
			out["capture_s"] = t - opened
		if inside:
			if not in_run:
				in_run = true
				run_start = t
			best_run = maxf(best_run, t - run_start)
		else:
			in_run = false
	out["hold_s"] = best_run
	if capture_index >= 0:
		var sum_squares: float = 0.0
		var count: int = 0
		for i: int in range(capture_index, samples.size()):
			var error: float = float(samples[i]["tilt_deg"]) - target
			sum_squares += error * error
			count += 1
		out["rms_deg"] = sqrt(sum_squares / float(count)) if count > 0 else 0.0
	return out


## THE ROTOR CALL. The failure's own start is READ OFF THE SAMPLES (the first
## tick where the drilled rotor has lost anything) rather than passed in, so a
## runner that fires the staircase late still measures from when it actually
## began.
##
## Never called: `detect_loss` takes its sentinel, and drift and sag are still
## reported — measured to the end of the run rather than to a call. They are
## context in that case, not a score, and the report says so.
static func _rotor_out(samples: Array, call_t: float) -> Dictionary:
	var out: Dictionary = sentinels("rotor_out")
	if samples.is_empty():
		return out
	var start: int = -1
	for i: int in samples.size():
		if float(samples[i]["loss"]) > 0.0:
			start = i
			break
	if start < 0:
		return out
	var at: int = samples.size() - 1
	if call_t >= 0.0:
		for i: int in range(start, samples.size()):
			if float(samples[i]["t"]) >= call_t:
				at = i
				break
		out["detect_loss"] = float(samples[at]["loss"])
	var from_pos: Vector3 = samples[start]["pos"]
	var to_pos: Vector3 = samples[at]["pos"]
	out["drift_m"] = Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z).length()
	out["sag_m"] = from_pos.y - to_pos.y
	return out


## BEST OF N ATTEMPTS, per measure, by that measure's own `better` direction.
##
## Best-of rather than mean or last, and the reason is what the drill is FOR: it
## asks what a pilot can do, and a mean is dragged down by the attempt where
## they were still working out the task. The cost is that it rewards grinding,
## which is why the artifact keeps every attempt and the report prints the
## attempt count and the spread beside the number — a pilot who needed nine
## tries to hit the band once has told us something the best figure hides.
static func best_of(drill_id: String, attempts: Array) -> Dictionary:
	if attempts.is_empty():
		return sentinels(drill_id)
	var out: Dictionary = {}
	for name: String in DrillBook.measure_names(drill_id):
		var better_high: bool = String(DrillBook.measure(drill_id, name)["better"]) == "high"
		var best: float = -INF if better_high else INF
		for attempt: Dictionary in attempts:
			var measured: Dictionary = attempt.get("measures", {}) as Dictionary
			if not measured.has(name):
				continue
			var value: float = float(measured[name])
			best = maxf(best, value) if better_high else minf(best, value)
		out[name] = best if is_finite(best) \
				else float(DrillBook.measure(drill_id, name)["sentinel"])
	return out


## The high-to-low spread of one measure across attempts — printed beside the
## best figure so a lucky single attempt cannot pass for a capability.
static func spread(drill_id: String, attempts: Array, name: String) -> float:
	var low: float = INF
	var high: float = -INF
	for attempt: Dictionary in attempts:
		var measured: Dictionary = attempt.get("measures", {}) as Dictionary
		if not measured.has(name):
			continue
		var value: float = float(measured[name])
		low = minf(low, value)
		high = maxf(high, value)
	return high - low if is_finite(low) and is_finite(high) else 0.0
