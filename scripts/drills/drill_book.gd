class_name DrillBook
extends RefCounted

## THE DRILL BOOK — the pilot-in-the-loop instrument's specification layer.
##
## The human's ask, quoted so it is not paraphrased away: *"i want to create an
## instrument that will put ME as the pilot of a reading you can run and test or
## recognize patterns, etc. you tell me the situation, what you want me to do,
## and then read the result and compare to your assertions. it would bring you a
## new source of results to argue on."*
##
## A DRILL is four things, all of them stated to the pilot BEFORE they arm:
## a **situation** (what the world is), a **task** (what they do), a **success
## condition** (what finishing looks like), and a set of named **measures** —
## the scalars the run records. Nothing else in the instrument invents a
## reading: `DrillRunner` samples, `DrillMeasures` reduces, and both work off
## the measure list below.
##
## EVERY MEASURE CARRIES A `plausible` RANGE, AND THAT FIELD IS THE ANTI-THEATRE
## DEVICE. A prediction is only falsifiable if its band is narrow relative to
## what could physically have happened — "somewhere between 0 and everything" is
## not a claim. `drill_check` divides each predicted band by its plausible range
## and refuses anything wider than `MAX_BAND_FRACTION`, so a hedged prediction
## fails the board rather than quietly passing as a prediction.
##
## `sentinel` is what a measure records when the pilot never produced it at all
## (never captured the attitude, never called the failure). It is always the
## WORST end of the plausible range, so a non-event reads as a miss and never as
## a good score.
##
## Adding a second drill is a row here, a branch in `DrillMeasures.compute`, a
## setup branch in `DrillRunner`, and a prediction file. Nothing else.

## Where a drill's committed prediction lives — one file per drill, so
## `git log -- drills/predictions/<id>.json` dates THAT prediction and is not
## disturbed by anyone editing a different drill's numbers.
const PREDICTION_DIR: String = "res://drills/predictions"

## The widest a predicted band may be, as a fraction of the measure's plausible
## range. See the class comment: this is what stops a prediction from being
## unfalsifiable by construction.
const MAX_BAND_FRACTION: float = 0.4

const DRILLS: Dictionary = {
	"hold_tilt": {
		"title": "HOLD THE TILT",
		"question": "Can a pilot hold a stated attitude on the HUD's tilt readout, in acro, with no attitude hold?",
		"situation": [
			"A launch pad floating 250 m over open ground. No enemies, no weapons.",
			"Kestrel, ACRO mode, the repo's flight numbers (not your saved tuning).",
			"The pitch ladder is forced ON. The attitude instruments are the point.",
		],
		"task": [
			"Arm, lift off the pad, and get level and steady.",
			"Squeeze the FIRE trigger to MARK the start. It refuses unless you are",
			"  level (under 12 deg), steady (under 8 m/s) and 5 m clear of the pad,",
			"  so every attempt starts from one place.",
			"Then pitch the nose DOWN to 30 degrees of tilt and hold it there.",
			"Fly the number printed beside the airframe's level bracket.",
			"The window is 20 seconds. R resets you to the pad for another attempt.",
		],
		"success": "10 unbroken seconds within 5 degrees of 30 degrees of tilt.",
		"window_s": 20.0,
		"target_tilt_deg": 30.0,
		"tolerance_deg": 5.0,
		"hold_target_s": 10.0,
		## The stated, ENFORCED initial condition. The brief already promised
		## "level and steady", and a gate that only checked attitude would let an
		## attempt begin in a 60 m/s dive off the end of the last one — which is a
		## different task wearing the same name.
		"level_gate_deg": 12.0,
		"mark_speed_max": 8.0,
		"mark_clearance_m": 5.0,
		"measures": {
			"capture_s": {
				"label": "time to first reach the band",
				"unit": "s", "better": "low",
				"plausible": [0.0, 20.0], "sentinel": 20.0,
			},
			"hold_s": {
				"label": "longest unbroken time inside the band",
				"unit": "s", "better": "high",
				"plausible": [0.0, 20.0], "sentinel": 0.0,
			},
			"rms_deg": {
				"label": "RMS tilt error from first capture to window end",
				"unit": "deg", "better": "low",
				"plausible": [0.0, 25.0], "sentinel": 25.0,
			},
		},
	},
	"rotor_out": {
		"title": "CALL THE ROTOR",
		"question": "How much of one rotor does a pilot lose before they FEEL it, with the airframe plate hidden?",
		"situation": [
			"The same pad, the same Kestrel, ACRO mode.",
			"The HUD's airframe plate is HIDDEN on purpose — this measures feel,",
			"  not whether you looked at the gauge.",
			"At some point after you MARK, one rotor starts failing in steps of 5%",
			"  every 2 seconds. One step is about one raider bolt at severity 0.6.",
		],
		"task": [
			"Arm, climb off the pad, and hold station near it — small corrections,",
			"  nothing violent.",
			"Squeeze FIRE to MARK once you are settled. It refuses if you are",
			"  moving faster than 4 m/s or more than 25 m from the pad.",
			"After the mark there is a random 3 to 8 second wait, then the rotor",
			"  begins to fail. Squeeze FIRE again the INSTANT you feel it.",
			"A call during the wait voids the attempt — settle and MARK again.",
		],
		"success": "A call placed after the failure starts. Earlier is better.",
		"wait_min_s": 3.0,
		"wait_max_s": 8.0,
		"step_loss": 0.05,
		"step_period_s": 2.0,
		"max_loss": 0.9,
		## Which rotor fails. 0 is front-left in the quad-X order (FL, FR, BL, BR)
		## and it is FIXED rather than random, because a drill whose answer moves
		## between attempts measures two things at once.
		"rotor_index": 0,
		"mark_speed_max": 4.0,
		"mark_radius_max": 25.0,
		"measures": {
			"detect_loss": {
				"label": "rotor capability lost when the call was made",
				"unit": "fraction", "better": "low",
				"plausible": [0.0, 1.0], "sentinel": 1.0,
			},
			"drift_m": {
				"label": "horizontal drift from where the failure began",
				"unit": "m", "better": "low",
				"plausible": [0.0, 60.0], "sentinel": 60.0,
			},
			"sag_m": {
				"label": "altitude lost between failure start and the call",
				"unit": "m", "better": "low",
				"plausible": [-20.0, 60.0], "sentinel": 60.0,
			},
		},
	},
}


static func ids() -> Array:
	var out: Array = DRILLS.keys()
	out.sort()
	return out


static func has(drill_id: String) -> bool:
	return DRILLS.has(drill_id)


static func drill(drill_id: String) -> Dictionary:
	return DRILLS.get(drill_id, {}) as Dictionary


static func measures(drill_id: String) -> Dictionary:
	return drill(drill_id).get("measures", {}) as Dictionary


## Measure names in a stable order, so the artifact, the check and the report
## all list them the same way.
static func measure_names(drill_id: String) -> Array:
	var out: Array = measures(drill_id).keys()
	out.sort()
	return out


static func measure(drill_id: String, name: String) -> Dictionary:
	return measures(drill_id).get(name, {}) as Dictionary


static func prediction_path(drill_id: String) -> String:
	return "%s/%s.json" % [PREDICTION_DIR, drill_id]


## The brief, as the lines the pilot reads before arming. Built here rather than
## in the runner so a headless check can assert a drill states its situation,
## its task and its success condition without booting anything.
static func brief_lines(drill_id: String) -> PackedStringArray:
	var d: Dictionary = drill(drill_id)
	if d.is_empty():
		return PackedStringArray(["unknown drill '%s'" % drill_id])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("DRILL: %s  (%s)" % [d["title"], drill_id])
	lines.append("")
	lines.append("QUESTION")
	lines.append("  %s" % d["question"])
	lines.append("")
	lines.append("SITUATION")
	for line: String in d["situation"]:
		lines.append("  %s" % line)
	lines.append("")
	lines.append("TASK")
	for line: String in d["task"]:
		lines.append("  %s" % line)
	lines.append("")
	lines.append("SUCCESS")
	lines.append("  %s" % d["success"])
	lines.append("")
	lines.append("RECORDED")
	for name: String in measure_names(drill_id):
		var m: Dictionary = measure(drill_id, name)
		lines.append("  %-14s %s (%s)" % [name, m["label"], m["unit"]])
	lines.append("")
	lines.append("My prediction for these three numbers is already committed to git.")
	lines.append("It is NOT shown here on purpose — a number on screen is a target.")
	lines.append("")
	lines.append("Throttle down, then ARM to begin.")
	return lines
