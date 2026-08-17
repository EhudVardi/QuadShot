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
		"title": "PITCH DOWN 30 AND HOLD IT",
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
			"THEN PITCH THE NOSE DOWN AND FLY FORWARD. The readout beside the",
			"  airframe bracket must reach -30 and stay there. Sitting level at 0",
			"  is NOT the task and scores nothing.",
			"The top of the screen turns green and counts while you are in the band.",
			"The window is 20 seconds. R resets you to the pad for another attempt.",
		],
		"success": "10 unbroken seconds with the readout between -25 and -35.",
		"window_s": 20.0,
		"target_tilt_deg": 30.0,
		"tolerance_deg": 5.0,
		"hold_target_s": 10.0,
		## The stated, ENFORCED initial condition. The brief already promised
		## "level and steady", and a gate that only checked attitude would let an
		## attempt begin in a 60 m/s dive off the end of the last one — which is a
		## different task wearing the same name.
		## High, and it is arithmetic: a quad tilted 30 degrees on hover collective
		## keeps only cos(30) of its lift, which is 262 m of descent across the
		## 20-second window.
		"pad_altitude": 250.0,
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
	"course": {
		"title": "FLY THE COURSE",
		"question": "How fast, how clean and how tight a line can a pilot fly through a fixed gate course?",
		"situation": [
			"Six gates in a fixed order over the pad, 350 m of course, climbing",
			"  then descending. Kestrel, ACRO, the repo's flight numbers.",
			"The gates are SOLID — clipping a bar costs you, it is not a curtain.",
			"Two pairs of pylons flank the line between gates. They do not block",
			"  the straight line; they punish a wide one.",
		],
		"task": [
			"Arm, lift off the pad, and settle behind the start gate.",
			"Squeeze FIRE to MARK, then fly gate 1 through gate 6 IN ORDER.",
			"The clock runs from the moment you cross gate 1 to the moment you",
			"  cross gate 6, so lining up beforehand costs you nothing.",
			"Miss a gate and it stays next — you have to come back for it.",
			"R resets you to the pad for another attempt.",
		],
		"success": "All six gates in order, without touching anything.",
		## The cap, not the task: an attempt that has not finished by here is over.
		"window_s": 120.0,
		## THE COURSE IS DATA, and both halves of the instrument read this one copy
		## — `DrillRunner` builds the gates from it and `DrillMeasures` scores the
		## line against it. A course built in the scene and a length written into
		## the reduction would drift the first time a gate moved.
		##
		## Every gate faces down -Z (the drone's own nose direction at spawn), so
		## the whole course is a slalom flown "north": weave left and right, climb,
		## then come back down. One heading keeps two runs comparable, which is the
		## entire reason this drill is a fixed course rather than an open field.
		## LOW, and that is a motion-feel decision rather than a layout one. The
		## other two drills need a pad 250 m up (hold_tilt spends 262 m of descent
		## in its window), and the human flew this course up there and could not
		## read their own speed: *"there are no grid lines so im having a very
		## difficult time feeling the motion."* Part of that was the ground shader
		## fading its grid out by 130 m, but the deeper half is that at 250 m there
		## is no near-field parallax at all. Down here the ground is 12 to 32 m
		## under the gates and the pylons are rooted in it, so the world moves.
		"gates": [
			Vector3(0.0, 15.0, -50.0),
			Vector3(25.0, 15.0, -110.0),
			Vector3(-25.0, 22.0, -170.0),
			Vector3(0.0, 32.0, -230.0),
			Vector3(35.0, 20.0, -290.0),
			Vector3(0.0, 12.0, -350.0),
		],
		## On the deck for this drill. Per-drill, because 250 m is what hold_tilt
		## needs and what a course cannot use.
		"pad_altitude": 0.5,
		## Half the gate opening, in metres, from `environment/gate.tscn`: the bars
		## are 3.6 x 3.0 outside with 0.3 thick members, so the hole is 3.3 x 2.7.
		"gate_half": Vector2(1.5, 1.2),
		## Pylon pairs, as (centre of the pair, half the gap). They straddle the
		## line rather than sitting on it — a tight line goes through untouched and
		## a wide one meets one, which is what makes them punish sloppiness instead
		## of forcing a detour and inflating everyone's path ratio equally.
		## Rooted in the ground rather than floating: `pylon_height * 0.5` puts the
		## base at y = 0, so they read as things standing in the world and give the
		## near-field parallax a course at altitude cannot.
		"pylons": [
			[Vector3(0.0, 20.0, -140.0), 9.0],
			[Vector3(17.0, 20.0, -260.0), 9.0],
		],
		## Tall enough that going OVER is a real climb rather than a free dodge,
		## short enough that the pair reads as pylons and not as a wall. At 70 m
		## they filled the sky from the pad and dominated the shot.
		"pylon_height": 40.0,
		"pylon_radius": 1.2,
		## MARK from behind the start gate and near the pad, so every run begins in
		## the same place.
		"mark_radius_max": 60.0,
		"measures": {
			"time_s": {
				"label": "seconds from gate 1 to gate 6",
				"unit": "s", "better": "low",
				"plausible": [0.0, 120.0], "sentinel": 120.0,
			},
			"contacts": {
				"label": "separate touches of gate or pylon during the run",
				"unit": "touches", "better": "low",
				"plausible": [0.0, 30.0], "sentinel": 30.0,
			},
			"path_ratio": {
				"label": "distance flown over the straight gate-to-gate length",
				"unit": "x", "better": "low",
				"plausible": [1.0, 3.0], "sentinel": 3.0,
			},
		},
	},
	## THE EASY RUNG. Fewer gates, wider gates, longer legs — the human's own
	## shape for the ladder: *"the tight course should have more gates and the
	## wide course should have less."* Difficulty here is not one dial but three
	## moving together, which is deliberate: this is a LADDER for a pilot to climb,
	## not a controlled experiment isolating gate size.
	"course_wide": {
		"title": "FLY THE WIDE COURSE",
		"question": "With room to spare, how fast can a pilot commit through a course?",
		"situation": [
			"Four gates, 4.4 m wide, over 267 m of open deck. One pair of pylons.",
			"Kestrel, ACRO, the repo's flight numbers. The easy rung of three.",
			"The gates are SOLID, but at 4.4 m they are not the constraint —",
			"  your own commitment to the throttle is.",
		],
		"task": [
			"Arm, lift off the pad, settle behind the start gate.",
			"Squeeze FIRE to MARK, then fly gate 1 through gate 4 IN ORDER.",
			"The clock runs from gate 1 to gate 4, so lining up costs nothing.",
			"R resets you to the pad for another attempt.",
		],
		"success": "All four gates in order, without touching anything.",
		"window_s": 120.0,
		"gates": [
			Vector3(0.0, 15.0, -60.0),
			Vector3(30.0, 18.0, -140.0),
			Vector3(-25.0, 22.0, -220.0),
			Vector3(0.0, 14.0, -300.0),
		],
		"gate_half": Vector2(2.2, 1.76),
		"pylons": [[Vector3(6.0, 20.0, -180.0), 11.0]],
		"pylon_height": 40.0,
		"pylon_radius": 1.2,
		"pad_altitude": 0.5,
		"mark_radius_max": 60.0,
		"measures": {
			"time_s": {
				"label": "seconds from the first gate to the last",
				"unit": "s", "better": "low",
				"plausible": [0.0, 120.0], "sentinel": 120.0,
			},
			"contacts": {
				"label": "touches on the WORST lap flown",
				"unit": "touches", "better": "low", "score": "worst",
				"plausible": [0.0, 30.0], "sentinel": 30.0,
			},
			"path_ratio": {
				"label": "distance flown over the straight gate-to-gate length",
				"unit": "x", "better": "low",
				"plausible": [1.0, 3.0], "sentinel": 3.0,
			},
		},
	},
	## THE HARD RUNG. Nine gates at 1.6 m over 435 m, with a direction change on
	## every leg and three pylon gates to thread.
	"course_tight": {
		"title": "FLY THE TIGHT COURSE",
		"question": "How much does a pilot give up in speed and cleanliness when the gates stop being generous?",
		"situation": [
			"Nine gates, 1.6 m wide, over 435 m — under six Kestrel spans of hole,",
			"  against fourteen on the wide course.",
			"Three pylon pairs with a 7 m gap. Kestrel, ACRO, repo numbers.",
			"CONTACTS IS SCORED ON YOUR WORST LAP HERE, not your best. Best-of",
			"  rewards one clean run; this asks how reliably clean you are.",
		],
		"task": [
			"Arm, lift off the pad, settle behind the start gate.",
			"Squeeze FIRE to MARK, then fly gate 1 through gate 9 IN ORDER.",
			"Miss a gate and it stays next — you have to come back for it.",
			"R resets you to the pad for another attempt.",
		],
		"success": "All nine gates in order. Clean on every lap, not just one.",
		"window_s": 150.0,
		"gates": [
			Vector3(0.0, 15.0, -40.0),
			Vector3(18.0, 15.0, -85.0),
			Vector3(-18.0, 20.0, -130.0),
			Vector3(14.0, 26.0, -175.0),
			Vector3(-14.0, 20.0, -220.0),
			Vector3(20.0, 14.0, -265.0),
			Vector3(-20.0, 18.0, -310.0),
			Vector3(12.0, 24.0, -355.0),
			Vector3(0.0, 14.0, -400.0),
		],
		"gate_half": Vector2(0.8, 0.64),
		"pylons": [
			[Vector3(0.0, 20.0, -107.0), 7.0],
			[Vector3(3.0, 20.0, -242.0), 7.0],
			[Vector3(-4.0, 20.0, -332.0), 7.0],
		],
		"pylon_height": 40.0,
		"pylon_radius": 1.2,
		"pad_altitude": 0.5,
		"mark_radius_max": 60.0,
		"measures": {
			"time_s": {
				"label": "seconds from the first gate to the last",
				"unit": "s", "better": "low",
				"plausible": [0.0, 150.0], "sentinel": 150.0,
			},
			"contacts": {
				"label": "touches on the WORST lap flown",
				"unit": "touches", "better": "low", "score": "worst",
				"plausible": [0.0, 40.0], "sentinel": 40.0,
			},
			"path_ratio": {
				"label": "distance flown over the straight gate-to-gate length",
				"unit": "x", "better": "low",
				"plausible": [1.0, 3.0], "sentinel": 3.0,
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
		"pad_altitude": 250.0,
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


## A drill is a COURSE if it names gates. Asking the data rather than matching
## the id is what lets a third or fourth course be a table entry and nothing
## else — `_drill_id == "course"` scattered through the runner is how a ladder
## ends up with one rung that works.
static func is_course(drill_id: String) -> bool:
	return not (drill(drill_id).get("gates", []) as Array).is_empty()


## The ids of every course, in ladder order (easiest first by gate width).
static func courses() -> Array:
	var out: Array = []
	for id: String in ids():
		if is_course(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
			return float((drill(a)["gate_half"] as Vector2).x) \
					> float((drill(b)["gate_half"] as Vector2).x))
	return out


static func prediction_path(drill_id: String) -> String:
	return "%s/%s.json" % [PREDICTION_DIR, drill_id]


## WHICH WAY THE COURSE GOES AFTER GATE `index`, as a unit vector in world
## space, or ZERO at the last gate because nothing follows it.
##
## Here rather than in the runner so it can be checked: the runner only projects
## this onto the screen, and a marker that pointed at the wrong gate would be
## invisible to every test that never drew a frame.
static func leg_direction(drill_id: String, index: int) -> Vector3:
	var gates: Array = drill(drill_id).get("gates", []) as Array
	if index < 0 or index + 1 >= gates.size():
		return Vector3.ZERO
	return ((gates[index + 1] as Vector3) - (gates[index] as Vector3)).normalized()


## The straight-line length of a gate course, gate centre to gate centre. The
## denominator of `path_ratio`, and derived from the same list the runner builds
## from so the two can never disagree about how long the course is.
static func course_length(drill_id: String) -> float:
	var gates: Array = drill(drill_id).get("gates", []) as Array
	var total: float = 0.0
	for i: int in range(1, gates.size()):
		total += (gates[i] as Vector3).distance_to(gates[i - 1] as Vector3)
	return total


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
