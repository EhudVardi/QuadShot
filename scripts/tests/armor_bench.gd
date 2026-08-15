extends SceneTree

## THE PLATING BENCH (GAMEPLAY-DESIGN Iteration 17 / E4.2, E.q7).
##
## It exists because authoring `FrameConfig.component_armor` from a frame's ROLE
## — which is what E.q7 requires, *"say the Roc is heavy AND powerful, so i would
## equip it with medium armor"* — needs a ruler for what a plating value is
## WORTH, and that worth is not the number itself. Plating meets a round only
## after E4.3's separation has already split it, so the same value does different
## work on a 0.28 m airframe and a 3.0 m one.
##
## MEASUREMENT ONLY. There is no pass/fail here, deliberately: E.q7 dissolved the
## question of what the armour numbers should come out to, so a check that
## asserted a target would be asserting the thing the user refused to author.
## What this file does is make the consequences of an authored value readable.
##
## **THE FINDING IT WAS BUILT TO CATCH, AND IT RUNS BOTH WAYS.** Separation splits
## a round on a tightly-packed frame into one large share and several small ones,
## and flat plating eats the small ones ENTIRELY. So per ROUND, a point of plating
## is worth more on the small airframe than on the large one — the opposite of
## where E4.2 assumes armour is carried. But a large airframe is hit far more
## often (E2 measured 8.7% against 52.0%), so per FIGHT the same point of plating
## fires far more times. Table B measures the first, table D the second, and they
## point in opposite directions.
##
## Run: <godot> --headless -s scripts/tests/armor_bench.gd --path .

## Bearing every round arrives on: front-right of the airframe, so it meets one
## rotor squarely and the frame's own geometry decides what else is in reach.
const BEARING: Vector3 = Vector3(1.0, 0.0, -1.0)
## The plating values table B sweeps, in capability units. The top of the sweep is
## a raider bolt's whole rotor bite at the shipped severity, so the sweep spans
## "nothing" to "this round cannot touch the rotors at all".
const SWEEP: Array[float] = [0.0, 0.006, 0.012, 0.024, 0.048]
## Bestiary rounds, read from the enemy configs so this file cannot drift from the
## bestiary it is describing.
const ROUNDS: Array[String] = ["gnat", "raider", "falx", "turret"]
## The round table B sweeps against: the roster's standard small arm.
const PROBE: String = "raider"
## A crash big enough to be felt and small enough to survive, in hull points —
## the band E6's guard lives in.
const CRASH_HULL: float = 40.0
## The plate table F hangs on EVERY frame to isolate the square-cube law. It is
## the Roc's shipped value, so the heaviest frame's row is also its real one.
const UNIFORM_PLATING: float = 0.024

## HOW OFTEN EACH FRAME IS ACTUALLY HIT, measured by `swarm_bench` in v2.46
## against ten raiders (GAMEPLAY-DESIGN E2) and quoted rather than re-run, because
## re-running it costs two minutes to reproduce a number that is already in the
## design record.
##
## The Atlas and the hexa are NOT measured: both carry the Kestrel's 0.28 m body
## and 0.12 m arms, so they present the same target and inherit its rate. That is
## an inference from geometry, and it is labelled as one in the table.
const CONNECT: Dictionary = {
	"kestrel": 0.087,
	"atlas": 0.087,
	"condor": 0.371,
	"roc": 0.520,
	"hexa": 0.087,
}
const MEASURED_CONNECT: Array[String] = ["kestrel", "condor", "roc"]

## The shipped dial and E.q8's design target. Every armour figure is reported at
## both, because plating is subtracted AFTER severity has scaled the round: the
## round shrinks as the dial comes down and the plating does not, so one authored
## value is worth different fractions at the two settings.
const SEVERITIES: Array[float] = [0.6, 1.0]
const SHIPPED_SEVERITY: float = 0.6

var _drones: Dictionary = {}
var _damage: Dictionary = {}
## THE SHIPPED PLATING, SNAPSHOTTED BEFORE ANYTHING TOUCHES IT. `Frames.config`
## goes through `load`, which caches, so every frame in this process shares ONE
## FrameConfig — and table B's sweep writes to it. Reading the roster's own value
## back out afterwards returned the last value the sweep left behind, which made
## every frame look plated at 0.048 and every "stopped" cell read 100%. Snapshot,
## then never trust the live resource for a number this file is reporting.
var _shipped: Dictionary = {}
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
	for type_id: String in ROUNDS:
		var config: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % type_id) as EnemyConfig
		_damage[type_id] = config.damage
	physics_frame.connect(_on_frame)


## Everything runs on a PHYSICS FRAME, never in `_initialize`: `add_child` there
## defers `_ready`, so the motor model is still Nil and every reading is an engine
## error rather than a measurement.
func _on_frame() -> void:
	if _done:
		return
	_done = true
	_table_a()
	_table_b()
	_table_c()
	_table_d()
	_table_e()
	_table_f()
	for child: Node in root.get_children():
		child.free()
	print("")
	print("[armor] DONE (measurement only — this bench has no pass/fail)")
	quit(0)


## Fire one round and read every rotor. `plating` is stated by the caller rather
## than taken from the frame, so a sweep and the shipped roster go through exactly
## the same path.
func _fire(frame_id: String, damage: float, plating: float,
		severity: float, crash: bool = false) -> Dictionary:
	var drone: FlightController = _drones[frame_id]
	drone.repair_motors()
	drone.frame.component_armor = {} if plating <= 0.0 else {&"rotor": plating}
	drone.damage_config.severity = severity
	if crash:
		# A crash is directionless and carries a HEADING instead — the way the
		# airframe was travelling when it met the wall.
		drone.last_hit_direction = Vector3.ZERO
		drone.last_crash_heading = Vector3(0.0, 0.0, -1.0)
	else:
		drone.last_hit_direction = (drone.global_basis * BEARING).normalized()
	drone.apply_hit_to_motors(damage)
	var motors: MotorModel = drone.get_node("MotorModel") as MotorModel
	var lost: float = 0.0
	var worst: float = 0.0
	var touched: int = 0
	var healths: PackedStringArray = []
	for i: int in motors.rotor_count:
		var gone: float = 1.0 - drone.motor_health(i)
		lost += gone
		worst = maxf(worst, gone)
		if gone > 0.000001:
			touched += 1
		healths.append("%.3f" % drone.motor_health(i))
	return {
		"lost": lost,
		"worst": worst,
		"touched": touched,
		"healths": "/".join(healths),
		"offered": _offered(drone, damage, severity, crash),
	}


## What the round would have stripped with no plating in the way — the
## denominator every "stopped" figure here is a fraction of. Computed from the
## config rather than measured, so it is independent of the thing being measured.
##
## A CRASH GETS NO MODELLED FIGURE, and the first version of this file was wrong
## to give it one. `_apply_crash` normalises its weights to a mean of 1 across
## EVERY part on the airframe — fourteen of them on a quad, of which four are
## rotors — so the rotors' share of a crash is not `base × rotor_count` and the
## arithmetic here cannot know it without duplicating that loop. It read the
## unplated Kestrel as stopping −0.0066 of a round it had no plating for. Table E
## measures its own baseline instead; this returns −1 so a caller that forgets
## cannot quietly get a plausible number.
func _offered(drone: FlightController, damage: float, severity: float,
		crash: bool) -> float:
	if crash:
		return -1.0
	var config: DamageConfig = drone.damage_config
	var raw: float = damage * config.motor_damage_scale
	return minf(raw, config.motor_damage_max) * severity


## Float noise across four normalised weights lands a hair either side of zero,
## which printed as "-0%" in a table whose whole job is to say whether armour
## subtracts. Snapped well below any real effect: mutation-testing the sign of the
## armour term moved these cells by 7.5 points, not by a millionth.
func _snap(value: float) -> float:
	return 0.0 if absf(value) < 0.000001 else value


func _plating(frame_id: String) -> float:
	return float(_shipped[frame_id])


## TABLE A — where a round lands before any plating is involved. Everything below
## is read against this, because plating meets a round only after separation has
## already decided how many pieces it is in.
func _table_a() -> void:
	print("")
	print("=== TABLE A — WHAT SEPARATION DOES FIRST (E4.3), NO PLATING ===")
	print("[armor] One %s bolt at the shipped severity %.1f, arriving front-right."
			% [PROBE, SHIPPED_SEVERITY])
	print("[armor] 'offered' is the rotor capability the round carries; 'worst' is")
	print("[armor] what the struck rotor takes. The gap between them is what")
	print("[armor] separation spread onto the OTHER rotors, and it is the thing")
	print("[armor] flat plating gets to eat for free.")
	print("[armor] %8s %7s %6s %7s %9s %8s %8s  %s"
			% ["frame", "body m", "arm m", "touched", "offered", "worst",
			"spread", "rotor health"])
	for frame_id: String in Frames.ROSTER:
		var drone: FlightController = _drones[frame_id]
		var row: Dictionary = _fire(frame_id, float(_damage[PROBE]), 0.0,
				SHIPPED_SEVERITY)
		var note: String = "  (hexa: FROZEN experiment, reported not used)" \
				if frame_id == Frames.HEXA else ""
		print("[armor] %8s %7.2f %6.3f %7d %9.4f %8.4f %8.4f  %s%s"
				% [frame_id, drone.config.body_m, drone.config.arm_length,
				int(row["touched"]), float(row["offered"]), float(row["worst"]),
				float(row["lost"]) - float(row["worst"]), row["healths"], note])


## TABLE B — THE TRAP, MEASURED AT BOTH ENDS OF THE LADDER. The same plating on
## every frame, against the same round.
##
## `per point` is the number to read: capability stopped divided by the plating
## value. A frame that takes the whole round on one rotor can never stop more than
## one point per point, so 1.00 is the floor and anything above it is separation's
## small shares being eaten whole.
func _table_b() -> void:
	print("")
	print("=== TABLE B — THE SAME PLATING IS WORTH MORE ON A PACKED FRAME ===")
	print("[armor] One %s bolt (%.0f dmg), severity %.1f, plating swept."
			% [PROBE, float(_damage[PROBE]), SHIPPED_SEVERITY])
	print("[armor] 'per point' = capability stopped / plating value. 1.00 means the")
	print("[armor] plating stopped exactly what it was worth; above 1.00 it also ate")
	print("[armor] a small share whole, which only a frame with rotors inside the")
	print("[armor] %.2f m footprint can offer."
			% (_drones[Frames.KESTREL] as FlightController).damage_config.hit_footprint_m)
	print("[armor] %8s %9s %9s %9s %9s %9s"
			% ["frame", "plating", "offered", "through", "stopped", "per point"])
	for frame_id: String in Frames.ROSTER:
		for plating: float in SWEEP:
			var row: Dictionary = _fire(frame_id, float(_damage[PROBE]), plating,
					SHIPPED_SEVERITY)
			var offered: float = float(row["offered"])
			var through: float = float(row["lost"])
			var stopped: float = offered - through
			var per_point: float = stopped / plating if plating > 0.0 else 0.0
			print("[armor] %8s %9.4f %9.4f %9.4f %9.4f %9.2f"
					% [frame_id, plating, offered, through, stopped, per_point])


## TABLE C — the roster as it actually ships, against every round the bestiary
## fires, at both the shipped dial and E.q8's design target.
##
## The plating values are READ FROM THE `.tres`, never restated here: a bench that
## keeps its own copy of the number it is reporting cannot notice the number
## moving.
func _table_c() -> void:
	print("")
	print("=== TABLE C — THE AUTHORED ROSTER AGAINST THE BESTIARY ===")
	print("[armor] Plating is read from default_frame_<id>.tres. 'stopped' is the")
	print("[armor] share of that round's rotor bite the plating turned away.")
	print("[armor] TWO SEVERITIES, because plating is subtracted AFTER severity has")
	print("[armor] scaled the round: the round shrinks with the dial and the plating")
	print("[armor] does not, so one authored value means different things at each.")
	for severity: float in SEVERITIES:
		var label: String = "SHIPPED" if is_equal_approx(severity,
				SHIPPED_SEVERITY) else "E.q8 design target"
		print("")
		print("[armor] severity %.1f (%s)" % [severity, label])
		var header: PackedStringArray = ["frame", "plating"]
		for type_id: String in ROUNDS:
			header.append("%s %.0f" % [type_id, float(_damage[type_id])])
		print("[armor] %8s %9s %11s %11s %11s %11s" % [header[0], header[1],
				header[2], header[3], header[4], header[5]])
		for frame_id: String in Frames.ROSTER:
			var plating: float = _plating(frame_id)
			var cells: PackedStringArray = []
			for type_id: String in ROUNDS:
				var row: Dictionary = _fire(frame_id, float(_damage[type_id]),
						plating, severity)
				var offered: float = float(row["offered"])
				var stopped: float = _snap(offered - float(row["lost"]))
				cells.append("%.0f%%" % (stopped / maxf(offered, 0.000001) * 100.0))
			print("[armor] %8s %9.4f %11s %11s %11s %11s"
					% [frame_id, plating, cells[0], cells[1], cells[2], cells[3]])


## TABLE D — THE OTHER DIRECTION, and the one E4.2 is actually about.
##
## Table B measures a single round, where the packed frame wins. A fight is not
## one round: the exposed frame is hit several times as often, so its plating
## fires several times as often. This multiplies the per-round saving by the
## measured connect rate to give the saving per hundred rounds FIRED at the frame,
## which is the quantity a pilot actually lives inside.
func _table_d() -> void:
	print("")
	print("=== TABLE D — PER FIGHT, NOT PER ROUND ===")
	print("[armor] 100 %s bolts FIRED at each frame, severity %.1f. 'connect' is the"
			% [PROBE, SHIPPED_SEVERITY])
	print("[armor] measured share that actually hits (swarm_bench v2.46, ten raiders);")
	print("[armor] the Atlas and hexa inherit the Kestrel's, having its exact body.")
	print("[armor] %8s %9s %9s %11s %11s %11s"
			% ["frame", "plating", "connect", "taken/100", "saved/100", "saved %"])
	for frame_id: String in Frames.ROSTER:
		var plating: float = _plating(frame_id)
		var connect: float = float(CONNECT[frame_id])
		var bare: Dictionary = _fire(frame_id, float(_damage[PROBE]), 0.0,
				SHIPPED_SEVERITY)
		var plated: Dictionary = _fire(frame_id, float(_damage[PROBE]), plating,
				SHIPPED_SEVERITY)
		var hits: float = 100.0 * connect
		var taken: float = float(plated["lost"]) * hits
		var saved: float = (float(bare["lost"]) - float(plated["lost"])) * hits
		var share: float = saved / maxf(saved + taken, 0.000001) * 100.0
		var mark: String = "" if MEASURED_CONNECT.has(frame_id) else "  (inferred)"
		print("[armor] %8s %9.4f %8.1f%% %11.4f %11.4f %10.0f%%%s"
				% [frame_id, plating, connect * 100.0, taken, saved, share, mark])


## TABLE E — THE E6 GUARD. Plating sits in `_damage_component`, which the CRASH
## path also goes through, so armour authored against bullets silently applies to
## walls. E6's standing rule is that *"no amount of redundancy makes a Roc a
## battering ram"*, and the board cannot see this: `crash_check`'s rotor stage
## flies main.tscn, which is a Kestrel, and the Kestrel carries no plating.
##
## WHAT IT DOES NOT REACH, stated so the table is not over-read: a crash's HULL
## damage never comes through here at all. `_damage_component` is the motor path;
## `main.gd` sends the crash's integrity damage to `Health`, which reduces it by
## the frame's flat `armor` and knows nothing about plating. So E6's *"can even
## die if faster"* is untouched by anything task 4 authored — what plating can
## blunt is how badly a crash frays the rotors, and nothing else.
func _table_e() -> void:
	print("")
	print("=== TABLE E — DOES PLATING BLUNT A CRASH? (E6's guard) ===")
	print("[armor] A %.0f-point crash at severity %.1f, angled so it has a leading"
			% [CRASH_HULL, SHIPPED_SEVERITY])
	print("[armor] side. A crash loads EVERY rotor, so plating gets a bite at each of")
	print("[armor] them — this is the path an armour value authored against bullets")
	print("[armor] reaches without anybody aiming it there.")
	print("[armor] 'bare' is MEASURED, not modelled: a crash normalises its weights")
	print("[armor] across all 14 parts, so the rotors' share of it is not a figure")
	print("[armor] this file can compute without duplicating that loop.")
	print("[armor] %8s %9s %9s %9s %9s %8s  %s"
			% ["frame", "plating", "bare", "through", "stopped", "blunted",
			"rotor health"])
	for frame_id: String in Frames.ROSTER:
		var plating: float = _plating(frame_id)
		var bare: float = float(_fire(frame_id, CRASH_HULL, 0.0,
				SHIPPED_SEVERITY, true)["lost"])
		var row: Dictionary = _fire(frame_id, CRASH_HULL, plating,
				SHIPPED_SEVERITY, true)
		var through: float = float(row["lost"])
		var stopped: float = _snap(bare - through)
		print("[armor] %8s %9.4f %9.4f %9.4f %9.4f %7.0f%%  %s"
				% [frame_id, plating, bare, through, stopped,
				stopped / maxf(bare, 0.000001) * 100.0, row["healths"]])


## TABLE F — WHAT THE PLATING WEIGHS, and why the big frame is the one that can
## carry it (E.q7's loop, closed 2026-08-15 on the human's own model: *"armor is
## simply something that reduces damage taken, we can say its equivalent to the
## thickness of the shell. so the mass is roughly thickness times the shell plan
## area"*).
##
## THE SECOND HALF IS THE ONE THAT PROVES SOMETHING. Pricing the shipped roster
## only says what today's values cost. Pricing the SAME plate on every frame
## isolates the square-cube law: plate mass goes as area (S squared) and an
## airframe's mass goes as volume (S cubed), so an identical plate is a far
## smaller fraction of a big frame. That is E4.2's *"a 500 kg airframe can carry
## plating; a 650 g quad carries nothing"* stated as arithmetic rather than as a
## design preference, and it is the reason the authored ladder rises with size.
func _table_f() -> void:
	print("")
	print("=== TABLE F — WHAT PLATING WEIGHS, AND WHAT IT COSTS IN THRUST ===")
	print("[armor] Plate mass is areal density x armour x area x count. TWR droops")
	print("[armor] because the thrust budget is bought with the DRY airframe, so")
	print("[armor] nobody authors the penalty - it falls out.")
	print("[armor] %8s %8s %9s %9s %8s %7s %8s %9s"
			% ["frame", "dry kg", "plating", "plate kg", "of dry", "TWR", "-> TWR",
			"hover"])
	for frame_id: String in Frames.ROSTER:
		var drone: FlightController = _drones[frame_id]
		var frame: FrameConfig = Frames.config(frame_id)
		frame.component_armor = {} if _plating(frame_id) <= 0.0 \
				else {&"rotor": _plating(frame_id)}
		var dry: float = drone.config.mass
		var plate: float = drone.plate_mass()
		print("[armor] %8s %8.2f %9.4f %9.3f %7.1f%% %7.1f %8.2f %9.4f"
				% [frame_id, dry, _plating(frame_id), plate,
				plate / maxf(dry, 0.000001) * 100.0,
				drone.config.thrust_to_weight_ratio, drone.effective_twr(),
				drone.hover_throttle()])

	print("")
	print("[armor] THE SAME PLATE ON EVERY FRAME (%.4f, the Roc's), which is the"
			% UNIFORM_PLATING)
	print("[armor] comparison that isolates the square-cube law:")
	print("[armor] %8s %8s %8s %9s %8s %8s"
			% ["frame", "body m", "dry kg", "plate kg", "of dry", "vs roc"])
	var roc_share: float = 0.0
	var rows: Array[Dictionary] = []
	for frame_id: String in Frames.ROSTER:
		var drone: FlightController = _drones[frame_id]
		var frame: FrameConfig = Frames.config(frame_id)
		frame.component_armor = {&"rotor": UNIFORM_PLATING}
		var dry: float = drone.config.mass
		var plate: float = drone.plate_mass()
		var share: float = plate / maxf(dry, 0.000001) * 100.0
		if frame_id == Frames.ROC:
			roc_share = share
		rows.append({"frame": frame_id, "body": drone.config.body_m, "dry": dry,
				"plate": plate, "share": share})
	for row: Dictionary in rows:
		print("[armor] %8s %8.2f %8.2f %9.3f %7.1f%% %7.1fx"
				% [row["frame"], row["body"], row["dry"], row["plate"],
				row["share"], float(row["share"]) / maxf(roc_share, 0.000001)])
	# Restore, so anything printed after this reads the roster and not the demo.
	for frame_id: String in Frames.ROSTER:
		var frame: FrameConfig = Frames.config(frame_id)
		frame.component_armor = {} if _plating(frame_id) <= 0.0 \
				else {&"rotor": _plating(frame_id)}
