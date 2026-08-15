class_name DrillCompare
extends RefCounted

## WHERE THE PREDICTION MEETS THE FLIGHT — pure, so the board can check it.
##
## Two jobs, and the first one outranks the second.
##
## **Refusing to compare** comes first. A prediction whose fingerprint does not
## match the one the pilot flew against has been edited since; a prediction
## whose commit is NEWER than the flight was not a prediction at all. In either
## case this module prints why and prints no verdicts. A report that grades a
## flight against a moved goalpost is worse than no report, because it looks
## like evidence.
##
## **Grading** is the easy half: a band, a measured value, and a direction.
##
## A GAP IS THE OUTPUT, NOT A NUMBER TO TUNE AWAY. Same discipline BALANCE.md
## states for predicted-vs-validated: a miss names something the model does not
## know about, and the honest response is to write down what that was — not to
## widen the band and re-fly.

const HIT: String = "HIT"
const OVER: String = "OVER"
const UNDER: String = "UNDER"

const ORDER_OK: String = "OK"
const ORDER_AFTER: String = "AFTER"
const ORDER_UNKNOWN: String = "UNKNOWN"


## Where a measured value falls against a predicted band. `miss` is how far
## outside it landed, in the measure's own units, and is zero on a hit.
static func verdict(band: Dictionary, value: float) -> Dictionary:
	var low: float = float(band.get("low", 0.0))
	var high: float = float(band.get("high", 0.0))
	if value < low:
		return {"result": UNDER, "miss": low - value}
	if value > high:
		return {"result": OVER, "miss": value - high}
	return {"result": HIT, "miss": 0.0}


## Did the prediction exist before the flight? Both arguments are unix seconds,
## which is what makes this timezone-proof — `git log --format=%ct` and
## `Time.get_unix_time_from_system()` are both UTC epoch counts, so no string
## dates are ever compared.
##
## A prediction committed in the same second as the flight passes. That is not a
## loophole worth closing: the flight takes minutes and the artifact is written
## at its end, so a same-second commit is a clock artifact, not a cheat.
static func ordering(prediction_unix: int, flown_unix: int) -> String:
	if prediction_unix <= 0 or flown_unix <= 0:
		return ORDER_UNKNOWN
	return ORDER_AFTER if prediction_unix > flown_unix else ORDER_OK


## Why the comparison must be refused, or an empty string if it may proceed.
## Split out from `report_lines` so a check can assert the REFUSAL rather than
## having to parse a printed report for the absence of a table.
static func refusal(prediction: Dictionary, artifact: Dictionary,
		prediction_unix: int) -> String:
	if prediction.is_empty():
		return "no committed prediction for this drill — nothing to compare against"
	var flown: String = String(artifact.get("prediction_fingerprint", ""))
	var current: String = DrillPredictions.fingerprint(prediction)
	if flown.is_empty():
		return "the run records no prediction fingerprint, so what it was flown against cannot be established"
	if flown != current:
		return ("STALE: flown against prediction %s, the file now fingerprints %s — "
				+ "the prediction was edited after the flight and the comparison is void") \
				% [flown, current]
	var order: String = ordering(prediction_unix,
			int(artifact.get("flown_unix", 0)))
	if order == ORDER_AFTER:
		return "the prediction was committed AFTER the flight — that is not a prediction"
	if order == ORDER_UNKNOWN:
		return "the prediction's commit date could not be read, so it cannot be shown to predate the flight"
	return ""


## One row per measure: the band, the reason, the measured value and the
## verdict. Rows carry no formatting so a check can assert them directly.
static func rows(drill_id: String, prediction: Dictionary,
		summary: Dictionary) -> Array:
	var out: Array = []
	for name: String in DrillBook.measure_names(drill_id):
		var spec: Dictionary = DrillBook.measure(drill_id, name)
		var band: Dictionary = DrillPredictions.band(prediction, name)
		var value: float = float(summary.get(name, spec["sentinel"]))
		var call: Dictionary = verdict(band, value)
		out.append({
			"name": name,
			"label": String(spec["label"]),
			"unit": String(spec["unit"]),
			"low": float(band.get("low", 0.0)),
			"high": float(band.get("high", 0.0)),
			"why": String(band.get("why", "")),
			"value": value,
			"sentinel": is_equal_approx(value, float(spec["sentinel"])),
			"result": String(call["result"]),
			"miss": float(call["miss"]),
		})
	return out


static func hits(row_list: Array) -> int:
	var count: int = 0
	for row: Dictionary in row_list:
		if String(row["result"]) == HIT:
			count += 1
	return count


## The whole report as text, refusal and all. Rendered here rather than in the
## CLI for the reason `WarView.card_lines` exists: a report a headless check can
## read as strings is a report whose refusals can be asserted.
static func report_lines(drill_id: String, prediction: Dictionary,
		artifact: Dictionary, prediction_unix: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: Dictionary = DrillBook.drill(drill_id)
	out.append("=== DRILL REPORT — %s (%s) ===" % [d.get("title", "?"), drill_id])
	out.append("question   %s" % d.get("question", ""))
	out.append("flown      %s by %s on %s" % [artifact.get("flown_utc", "?"),
			artifact.get("pilot", "?"), artifact.get("frame", "?")])
	out.append("attempts   %d (%d voided)" % [int(artifact.get("attempt_count", 0)),
			int(artifact.get("voided_count", 0))])
	out.append("prediction %s committed %s" % [
			DrillPredictions.fingerprint(prediction) if not prediction.is_empty() else "(none)",
			Time.get_datetime_string_from_unix_time(prediction_unix, true) + "Z"
					if prediction_unix > 0 else "(commit date unreadable)"])
	out.append("")
	var stop: String = refusal(prediction, artifact, prediction_unix)
	if not stop.is_empty():
		out.append("COMPARISON REFUSED")
		out.append("  %s" % stop)
		return out
	out.append("reasoning  %s" % prediction.get("reasoning", ""))
	out.append("")
	var attempts: Array = artifact.get("attempts", []) as Array
	var row_list: Array = rows(drill_id, prediction, artifact.get("summary", {}) as Dictionary)
	out.append("%-14s %-18s %10s %8s   %s"
			% ["measure", "predicted", "best", "spread", "verdict"])
	for row: Dictionary in row_list:
		var predicted: String = "%.2f .. %.2f %s" % [row["low"], row["high"], row["unit"]]
		var verdict_text: String = String(row["result"])
		if String(row["result"]) != HIT:
			verdict_text += " by %.2f %s" % [row["miss"], row["unit"]]
		if bool(row["sentinel"]):
			verdict_text += "  (never produced)"
		out.append("%-14s %-18s %10.2f %8.2f   %s" % [row["name"], predicted,
				row["value"], DrillMeasures.spread(drill_id, attempts, String(row["name"])),
				verdict_text])
	out.append("")
	for row: Dictionary in row_list:
		if String(row["result"]) == HIT:
			continue
		out.append("MISSED %s — I said %s" % [row["name"], row["why"]])
	out.append("")
	out.append("%d of %d inside the band." % [hits(row_list), row_list.size()])
	out.append("A gap is the OUTPUT: it names something the model does not know")
	out.append("about. Write down what that was; do not widen the band and re-fly.")
	return out
