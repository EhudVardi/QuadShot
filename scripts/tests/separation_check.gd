extends SceneTree

## THE SEPARATION CHECK (GAMEPLAY-DESIGN Iteration 17 / E4.3).
##
## E4.3 is the iteration's central symmetry and the strongest argument that a
## located damage model is the RIGHT answer to L3 rather than merely an
## interesting one:
##
##   *"A Kestrel's four rotors sit inside 0.28 m; a Roc's sit across 3.0 m. The
##   same geometry that makes the big frame easier to hit makes each hit less
##   concentrated — one round takes one component instead of straddling three.
##   So exposure grows with size and concentration falls with size, and they move
##   in the same ratio."*
##
## **THE TRAP THIS FILE HAD TO AVOID IS THE OBVIOUS ASSERTION.** "A hit damages
## at least one component" passes on the code separation replaced, and so does
## "a hit damages the right component". Neither says anything. The only claim
## that distinguishes the two is a COMPARISON ACROSS FRAME SIZES, so every stage
## here is the same round fired at different airframes.
##
## Four claims:
##
##  1. **A round straddles a small airframe and takes one part of a big one**,
##     and the count falls monotonically as the frame grows. This is the whole
##     mechanic; nothing else in the suite would notice it decaying.
##  2. **Damage is conserved.** Straddling three components must cost exactly
##     what landing on one costs, or separation is secretly a damage multiplier
##     and the balance instrument is measuring the wrong thing.
##  3. **A hit stays CONCENTRATED.** Spreading is not smearing: the struck
##     component still takes the clear majority, which is what keeps E7's *"if in
##     two different runs i get the same engine hit — thats a lession to be
##     learned"* true.
##  4. **A hit never vanishes**, including on the frame where nothing at all
##     falls inside the footprint — the large airframe's ordinary case, which is
##     served by a separate code path and would otherwise be silent.
##  5. **Plating reduces, and only reduces** (E4.2). Added when task 4 authored
##     the first non-zero `component_armor`, because until then the mechanism had
##     no witness on the board at all.
##
## **CLAIMS 1 TO 4 ARE MEASURED WITH PLATING OFF, AND THAT IS A STATEMENT RATHER
## THAN A CONVENIENCE.** Separation decides WHERE a round lands; plating decides
## how much of it survives the airframe. They are two mechanisms and this file is
## about the first. Left mixed, claim 2 stopped being a conservation test the
## moment the Atlas gained plating — it read the armour as a leak and failed,
## which is the check measuring the wrong thing rather than the code being wrong.
## The plating is stated here the way `Jamming.bench_override` lets a bench state
## its jam, and claim 5 turns it back on for a second pass.
##
## WOULD IT STILL PASS IF THE FEATURE WERE DELETED? No, and the mutations are on
## record in the commit: restore single-nearest (claim 1 collapses to 1 rotor
## everywhere), drop the weight normalisation (claim 2 fails), scale the footprint
## by `body_m` (claim 1 fails — every frame touches the same count, which is
## precisely the authored-symmetry mistake E4.3 forbids), widen the footprint
## until the round smears (claim 3 fails), and delete the `- part.armor` in
## `_damage_component` (claim 5 fails on all three plated frames).
##
## Run: <godot> --headless -s scripts/tests/separation_check.gd --path .

const HIT: float = 40.0
## The worst-hit component must take at least this share of the round.
const CONCENTRATION_MIN: float = 0.40
## Damage conservation, as a fraction of the total dealt.
const CONSERVATION_EPSILON: float = 0.001
## Frames walked for the monotonicity claim: quads only, so the comparison is
## SIZE alone. The hexa is the datum's size with six rotors, which is a different
## axis and is reported beside them rather than folded in.
const LADDER: Array[String] = ["kestrel", "condor", "roc"]

var _rows: Array[Dictionary] = []
var _plated_rows: Array[Dictionary] = []
var _drones: Dictionary = {}
## THE ROSTER'S SHIPPED PLATING, TAKEN BEFORE ANYTHING TOUCHES IT. `Frames.config`
## goes through `load`, which caches, so every drone built here shares ONE
## FrameConfig per frame — and this file writes to it to turn plating off. Read
## the value back afterwards and you get whatever the last pass left behind.
var _shipped: Dictionary = {}
var _failures: PackedStringArray = []
var _done: bool = false


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	for frame_id: String in Frames.ROSTER:
		_shipped[frame_id] = float(
				Frames.config(frame_id).component_armor.get(&"rotor", 0.0))
		var drone: FlightController = Frames.build(frame_id)
		root.add_child(drone)
		# Frozen: the only thing under test is where one round lands, and a
		# falling airframe would add a collision to it.
		drone.freeze = true
		_drones[frame_id] = drone
	physics_frame.connect(_on_frame)


## Everything runs on a PHYSICS FRAME, never in _initialize: `add_child` there
## defers `_ready`, so the motor model is still Nil and every reading is an
## engine error rather than a measurement.
func _on_frame() -> void:
	if _done:
		return
	_done = true
	for frame_id: String in Frames.ROSTER:
		_rows.append(_fire_at(frame_id, false))
	for frame_id: String in Frames.ROSTER:
		_plated_rows.append(_fire_at(frame_id, true))
	_report()


func _fire_at(frame_id: String, plated: bool) -> Dictionary:
	var drone: FlightController = _drones[frame_id]
	drone.repair_motors()
	# Stated, never inherited: claims 1 to 4 are about separation alone, and
	# plating would show up in them as damage going missing.
	drone.frame.component_armor = {} if not plated \
			else {&"rotor": float(_shipped[frame_id])}
	# One round, always the same bearing, always front-right of the airframe.
	drone.last_hit_direction = (drone.global_basis
			* Vector3(1.0, 0.0, -1.0)).normalized()
	drone.apply_hit_to_motors(HIT)
	var motors: MotorModel = drone.get_node("MotorModel") as MotorModel
	var touched: int = 0
	var total: float = 0.0
	var top: float = 0.0
	var healths: PackedStringArray = []
	for i: int in motors.rotor_count:
		var lost: float = 1.0 - drone.motor_health(i)
		total += lost
		top = maxf(top, lost)
		if lost > 0.0001:
			touched += 1
		healths.append("%.2f" % drone.motor_health(i))
	return {
		"frame": frame_id,
		"body": drone.config.body_m,
		"rotors": motors.rotor_count,
		"plating": float(_shipped[frame_id]) if plated else 0.0,
		"touched": touched,
		"total": total,
		"share": top / maxf(total, 0.000001),
		"healths": "/".join(healths),
	}


func _find(frame_id: String) -> Dictionary:
	for row: Dictionary in _rows:
		if row["frame"] == frame_id:
			return row
	return {}


func _report() -> void:
	var footprint: float = (_drones[Frames.KESTREL] as FlightController) \
			.damage_config.hit_footprint_m
	print("[separation] one %.0f-point round, arriving front-right, footprint %.2f m"
			% [HIT, footprint])
	print("[separation] The footprint is in METRES and does not scale with the")
	print("[separation] airframe. That is the entire mechanic: the frames differ")
	print("[separation] only in how far apart their own rotors sit.")
	print("[separation] PLATING IS OFF for this table: it is a separation")
	print("[separation] measurement, and armour would read as damage going missing.")
	print("[separation] %8s %7s %7s %8s %9s %9s  %s"
			% ["frame", "body m", "rotors", "touched", "top share", "dealt",
			"rotor health"])
	for row: Dictionary in _rows:
		print("[separation] %8s %7.2f %7d %8d %8.0f%% %9.4f  %s"
				% [row["frame"], row["body"], row["rotors"], row["touched"],
				float(row["share"]) * 100.0, row["total"], row["healths"]])
	_check()
	for child: Node in root.get_children():
		child.free()
	if _failures.is_empty():
		print("")
		print("[separation] PASS")
		quit(0)
	else:
		print("")
		for failure: String in _failures:
			print("[separation] FAIL: %s" % failure)
		print("[separation] FAIL")
		quit(1)


func _check() -> void:
	# CLAIM 1 — the symmetry, walked up the ladder. Quads only, so the only thing
	# varying is how big the airframe is.
	var previous: Dictionary = {}
	var smallest: int = 0
	var largest: int = 0
	for frame_id: String in LADDER:
		var row: Dictionary = _find(frame_id)
		if row.is_empty():
			_failures.append("frame '%s' is missing from the roster, so the ladder cannot be walked"
					% frame_id)
			return
		if frame_id == LADDER[0]:
			smallest = int(row["touched"])
		if frame_id == LADDER[LADDER.size() - 1]:
			largest = int(row["touched"])
		if not previous.is_empty() and int(row["touched"]) > int(previous["touched"]):
			_failures.append("%s (%.2f m) had one round reach %d rotors while the SMALLER %s (%.2f m) reached only %d — concentration must not rise with airframe size, that is E4.3 backwards"
					% [row["frame"], float(row["body"]), int(row["touched"]),
					previous["frame"], float(previous["body"]),
					int(previous["touched"])])
		previous = row
	print("")
	print("[separation] CLAIM 1 — A ROUND STRADDLES A SMALL FRAME AND TAKES ONE PART OF A BIG ONE.")
	print("[separation] %s reaches %d rotors, %s reaches %d."
			% [LADDER[0], smallest, LADDER[LADDER.size() - 1], largest])
	if smallest <= largest:
		_failures.append("the smallest frame's round reached %d rotors and the largest frame's reached %d — they must DIFFER, or the airframe's size is not affecting concentration at all and separation is doing nothing (single-nearest reads 1 everywhere; a footprint scaled by body_m reads the same count everywhere)"
				% [smallest, largest])

	# CLAIM 2 — conservation. Straddling is not a damage multiplier.
	var lowest: float = INF
	var highest: float = 0.0
	for row: Dictionary in _rows:
		lowest = minf(lowest, float(row["total"]))
		highest = maxf(highest, float(row["total"]))
	var drift: float = (highest - lowest) / maxf(highest, 0.000001)
	print("")
	print("[separation] CLAIM 2 — DAMAGE IS CONSERVED: every frame lost %.4f of rotor"
			% highest)
	print("[separation] capability from the same round, spread %.4f%%." % (drift * 100.0))
	if drift > CONSERVATION_EPSILON:
		_failures.append("the same round removed between %.4f and %.4f of rotor capability depending on the airframe (%.2f%% apart) — separation decides WHERE a hit lands and must never change how big it is, or every band in the balance instrument is measuring a different weapon per frame"
				% [lowest, highest, drift * 100.0])

	# CLAIM 3 — spreading is not smearing.
	print("")
	print("[separation] CLAIM 3 — A HIT STAYS CONCENTRATED (E7 repeatability):")
	for row: Dictionary in _rows:
		if float(row["share"]) < CONCENTRATION_MIN:
			_failures.append("on the %s the round put only %.0f%% of itself on its worst-hit rotor — spreading is not smearing, and a wound the pilot cannot attribute to a place is one they cannot learn from"
					% [row["frame"], float(row["share"]) * 100.0])
	print("[separation] worst share on any frame: %.0f%% (floor is %.0f%%)"
			% [_worst_share() * 100.0, CONCENTRATION_MIN * 100.0])

	# CLAIM 4 — and it never vanishes, including where nothing is in range.
	for row: Dictionary in _rows:
		if float(row["total"]) <= 0.0:
			_failures.append("the round did NOTHING to the %s — on a frame whose components all sit outside the footprint the nearest one has to take the whole hit, and that fallback is a separate code path nothing else exercises"
					% row["frame"])

	_check_plating()


## CLAIM 5 — the same round again, with each frame's SHIPPED plating on.
##
## Two halves, and the second is the one with teeth. Plating must never let more
## damage through than bare metal does — a sign error or an added-instead-of-
## subtracted armour term is the cheapest possible bug here and would otherwise
## sail through every other claim in this file. And on a frame that actually ships
## plating, something must be stopped: an armour value nobody applies is exactly
## the untested-code-wearing-a-comment shape the crash guard's surviving mutation
## taught this project to look for.
##
## The expectation comes from the `.tres`, never from a list here. A frame whose
## plating the human sets to zero stops being asserted the moment they save the
## file, which is correct — the VALUES are theirs and the MECHANISM is the board's.
func _check_plating() -> void:
	print("")
	print("[separation] CLAIM 5 — PLATING REDUCES, AND ONLY REDUCES (E4.2).")
	print("[separation] The same round, each frame's shipped component_armor on:")
	print("[separation] %8s %9s %9s %9s %9s  %s"
			% ["frame", "plating", "bare", "plated", "stopped", "rotor health"])
	var plated_frames: int = 0
	for row: Dictionary in _plated_rows:
		# Paired by NAME, not by index. The two passes walk the same roster in the
		# same order today, and an index pairing would go on comparing happily
		# while reporting one frame's armour against another frame's bare metal.
		var bare: float = float(_find(String(row["frame"]))["total"])
		var through: float = float(row["total"])
		var plating: float = float(row["plating"])
		print("[separation] %8s %9.4f %9.4f %9.4f %9.4f  %s"
				% [row["frame"], plating, bare, through, bare - through,
				row["healths"]])
		if through > bare + CONSERVATION_EPSILON:
			_failures.append("plating on the %s let MORE of the round through than bare metal did (%.4f against %.4f) — armour that adds damage is a sign error, and no other claim in this file would see it"
					% [row["frame"], through, bare])
		if plating <= 0.0:
			if absf(through - bare) > CONSERVATION_EPSILON:
				_failures.append("the %s ships no plating at all, yet the plated pass differs from the bare one (%.4f against %.4f) — zero armour has to be an exact no-op or the roster's unplated frames are being quietly modified"
						% [row["frame"], through, bare])
			continue
		plated_frames += 1
		if bare - through <= 0.0:
			_failures.append("the %s ships %.4f of rotor plating and it stopped NOTHING (%.4f through against %.4f bare) — the value is authored in default_frame_%s.tres and nothing is applying it"
					% [row["frame"], plating, through, bare, row["frame"]])
	if plated_frames <= 0:
		_failures.append("not one frame in the roster ships any component_armor, so this claim asserted nothing at all — the E4.2 mechanism is unguarded whether it works or not")


func _worst_share() -> float:
	var worst: float = 1.0
	for row: Dictionary in _rows:
		worst = minf(worst, float(row["share"]))
	return worst
