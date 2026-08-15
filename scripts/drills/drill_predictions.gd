class_name DrillPredictions
extends RefCounted

## THE COMMITTED CLAIM — one JSON file per drill under `drills/predictions/`,
## holding a band and a reason for every measure the drill declares.
##
## THE PREDICTION IS THE WHOLE POINT OF THE INSTRUMENT, and it only means
## anything if it was written down BEFORE the flight. The human said so and they
## are right: *"if the prediction is recorded after the fact, or can be edited
## after, it cannot embarrass you and the exercise is theatre."*
##
## Three mechanisms, in the order they bite:
##
## 1. **One file per drill, committed to git.** The prediction's timestamp is
##    then `git log -1 --format=%ct -- drills/predictions/<id>.json`, which is a
##    date the agent does not author. One file EACH, not one shared file, so
##    editing drill B's numbers does not move drill A's commit date and falsely
##    accuse an honest old run.
## 2. **A fingerprint stamped into the run artifact.** `DrillRunner` records
##    `fingerprint()` of the prediction it flew against. Edit any band or any
##    reason afterwards and the fingerprint moves, so `DrillReport` refuses to
##    compare and prints STALE instead of quietly grading the flight against a
##    prediction it was not flown against.
## 3. **An ordering check.** The artifact records the flight's unix time; the
##    report reads the prediction's commit time and refuses the comparison
##    outright if the prediction is the NEWER of the two.
##
## The fingerprint is tamper-EVIDENCE, not tamper-proofing: anyone with the repo
## can recompute it. That is the right strength. The thing being defended
## against is an agent quietly moving the goalposts after seeing the result, and
## a fingerprint that would have to be forged in a committed artifact makes that
## a deliberate act rather than an edit.

## FNV-1a, written out rather than using GDScript's `hash()`, because the
## fingerprint is stored in the human's artifact files and must still mean the
## same thing after an engine upgrade. `hash()` carries no such promise.
const FNV_OFFSET: int = 0x811c9dc5
const FNV_PRIME: int = 16777619
const MASK32: int = 0xFFFFFFFF


static func load_prediction(drill_id: String) -> Dictionary:
	var path: String = DrillBook.prediction_path(drill_id)
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


static func bands(prediction: Dictionary) -> Dictionary:
	return prediction.get("bands", {}) as Dictionary


static func band(prediction: Dictionary, name: String) -> Dictionary:
	return bands(prediction).get(name, {}) as Dictionary


## The canonical text a fingerprint is taken over: the drill id, the shared
## reasoning, and every band with its own reason, in sorted order.
##
## THE REASONS ARE INCLUDED ON PURPOSE. The claim is not only "between 7 and 10
## seconds", it is "between 7 and 10 seconds BECAUSE the rate loop has no
## attitude hold" — a rewritten reason is a different prediction even when the
## numbers do not move, and it must invalidate the same way.
static func canonical(prediction: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(String(prediction.get("drill", "")))
	lines.append(String(prediction.get("reasoning", "")))
	var names: Array = bands(prediction).keys()
	names.sort()
	for name: String in names:
		var b: Dictionary = band(prediction, name)
		lines.append("%s|%.6f|%.6f|%s" % [name, float(b.get("low", 0.0)),
				float(b.get("high", 0.0)), String(b.get("why", ""))])
	return "\n".join(lines)


static func fingerprint(prediction: Dictionary) -> String:
	var hash_value: int = FNV_OFFSET
	for byte: int in canonical(prediction).to_utf8_buffer():
		hash_value = (hash_value ^ byte) & MASK32
		hash_value = (hash_value * FNV_PRIME) & MASK32
	return "%08x" % hash_value


## Everything wrong with a prediction, as sentences. Empty means it is a
## well-formed, falsifiable claim about this drill.
##
## `drill_check` runs this over every shipped prediction, which is what stops a
## band being widened until it cannot miss — see `DrillBook.MAX_BAND_FRACTION`.
static func problems(drill_id: String, prediction: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if prediction.is_empty():
		out.append("%s: no prediction file at %s"
				% [drill_id, DrillBook.prediction_path(drill_id)])
		return out
	if String(prediction.get("drill", "")) != drill_id:
		out.append("%s: prediction names drill '%s'"
				% [drill_id, prediction.get("drill", "")])
	if String(prediction.get("reasoning", "")).strip_edges().is_empty():
		out.append("%s: no reasoning — a band with no argument teaches nothing when it misses"
				% drill_id)
	var declared: Array = DrillBook.measure_names(drill_id)
	for name: String in bands(prediction).keys():
		if not declared.has(name):
			out.append("%s: predicts '%s', which the drill does not measure"
					% [drill_id, name])
	for name: String in declared:
		var spec: Dictionary = DrillBook.measure(drill_id, name)
		var b: Dictionary = band(prediction, name)
		if b.is_empty():
			out.append("%s: no band for '%s'" % [drill_id, name])
			continue
		var low: float = float(b.get("low", 0.0))
		var high: float = float(b.get("high", 0.0))
		if String(b.get("why", "")).strip_edges().is_empty():
			out.append("%s.%s: no reason given" % [drill_id, name])
		if low > high:
			out.append("%s.%s: band is inverted (%.3f .. %.3f)" % [drill_id, name, low, high])
			continue
		var plausible: Array = spec["plausible"]
		var floor_value: float = float(plausible[0])
		var ceiling: float = float(plausible[1])
		if low < floor_value or high > ceiling:
			out.append("%s.%s: band %.3f .. %.3f leaves the plausible range %.3f .. %.3f"
					% [drill_id, name, low, high, floor_value, ceiling])
			continue
		var span: float = ceiling - floor_value
		var fraction: float = (high - low) / span if span > 0.0 else 1.0
		if fraction > DrillBook.MAX_BAND_FRACTION:
			out.append("%s.%s: band claims %.0f%% of the plausible range — that is a hedge, not a prediction (max %.0f%%)"
					% [drill_id, name, fraction * 100.0,
					DrillBook.MAX_BAND_FRACTION * 100.0])
	return out
