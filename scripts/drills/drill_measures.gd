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
	return sentinels(drill_id)


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
