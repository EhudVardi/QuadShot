extends SceneTree

## THE CRASH CHECK (GAMEPLAY-DESIGN Iteration 17 / E6, as corrected by the E
## steering). Crash damage is peak deceleration, `v^2 / (2 * s * g)`, and this
## file is the guard that landed with it.
##
## Every claim is TWO RUNS DIFFERING IN ONE THING, because every single-run
## assertion available here (it hurt, it scaled, it killed) is passed just as
## happily by a constant. Four claims:
##
##  1. **Mass is not a shield.** The Kestrel and the Atlas are the roster's only
##     pair with the SAME body (0.28 m) and different mass (0.65 vs 1.24 kg), so
##     they are the one controlled comparison the roster can offer — everything
##     else changes size and mass together. The whole ladder is walked beside
##     them, at a held speed so drag cannot masquerade as mass.
##  2. **A landing is free and a wall is not**, separated by orders of magnitude.
##  3. **Faster is worse, QUADRATICALLY.** This is the stage that proves the law
##     actually changed: the old delta-v law was linear, so it also passed
##     "doubling the speed more than doubles the damage" — a threshold makes any
##     linear law convex. Only the g RATIO tells the two apart, and it must be 4.
##  4. **A crash loads every component; a bullet loads one.** The opposite of a
##     bullet is the whole content of the model, and it is the stage a naive
##     implementation gets wrong. It boots `main.tscn` rather than re-wiring the
##     path here, because the crash -> hull -> rotors chain lives in main and a
##     check that rebuilt it would be marking its own homework.
##
## WOULD IT STILL PASS IF THE FEATURE WERE DELETED? No. Six mutations are on
## record, each run and each failing a different sentence:
##
##  - the old LINEAR delta-v law restored -> claim 3 reads a ratio of 2.00
##  - `crash_crush_m` scaled with `body_m` -> claim 1's ladder spans 19 g to 204 g
##  - a crash frays only rotor 0 -> claim 4a reads 1 of 4
##  - the hit direction ignored, so everything frays -> claim 4b reads 4 of 4
##  - `crash_damage` returns 0 -> claims 2, 3 and 4 all fail
##  - main's `last_hit_direction = Vector3.ZERO` deleted -> claim 4c reads 1 of 4
##
## THE LAST ONE IS THE ONE WORTH KNOWING, because it PASSED the first version of
## this file and is the reason claim 4c exists at all. The crash stage was flown
## on a clean airframe, where the bearing field happens to be empty anyway, so
## deleting the guard changed nothing and the guard was untested code wearing a
## comment. The crash is now flown with a stale bearing deliberately planted on
## the drone — the state an armour-absorbed hit really leaves behind — and the
## mutation fails immediately. Same family as the Phalanx's tracking mutation:
## *fixing what a test fires on does not fix what it reads.*
##
## Run: <godot> --headless -s scripts/tests/crash_check.gd --path .

## Held approach speeds, m/s. 20 and 40 are claim 3's doubling pair.
const SPEEDS: Array[float] = [20.0, 40.0]
## The frame the speed and landing claims are made on.
const DATUM: String = "kestrel"
## Metres in front of the wall. Only has to exceed a couple of ticks of travel —
## the approach speed is HELD every tick, so the run-up costs nothing to drag.
const RUN_UP: float = 1.0
const MAX_TICKS: int = 900

## Claim 1: same-body frames of different mass must agree this closely, in
## percent of peak g. They are hit at a held speed, so anything above noise here
## is mass leaking into the law.
const MASS_TOLERANCE_PCT: float = 1.0
## Claim 1, the whole ladder: 0.28 m to 3.00 m and 0.65 kg to 500 kg. Same bound,
## because at a held speed neither size nor mass may enter the law at all.
const LADDER_TOLERANCE_PCT: float = 1.0
## Claim 3: g must go as v^2, so doubling the speed must quadruple it.
const QUADRATIC_TOLERANCE: float = 0.15
## Claim 2: a set-down and a wall must not be the same kind of event.
const LANDING_WALL_RATIO: float = 50.0
## Claim 4: rotors are frayed equally by a crash, to within this much capability.
const EVEN_FRAY_EPSILON: float = 0.001
## Claim 4b: the rotor a front-right hit belongs to. `MotorModel`'s order is
## FL, FR, BL, BR, and the planted bearing is +X / -Z, so it is FR.
const BULLET_EXPECTS: int = 1

enum { ARENA_BUILD, ARENA_RUN, ARENA_RECORD, MAIN_BULLET, MAIN_CRASH, MAIN_READ }

var _combat: CombatConfig
var _cases: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []

var _index: int = 0
var _phase: int = ARENA_BUILD
var _ticks: int = 0
var _arena: Node3D
var _drone: FlightController
var _hold: Vector3 = Vector3.ZERO
var _emitted: float = -1.0
var _speed_before: float = 0.0

var _main: Node3D
var _main_drone: FlightController
var _bullet_healths: PackedFloat32Array
var _crash_healths: PackedFloat32Array
var _main_impact: float = -1.0
var _main_wait: int = 0


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning. This
	# file is where that leak was found: `main.gd:_ready` calls `load_from_user`
	# on the SHARED default_combat_config.tres, so booting main.tscn for claim 4
	# would have overwritten the very arithmetic claims 1 to 3 were measured with.
	TunableConfig.user_overrides_enabled = false
	# CACHE_MODE_IGNORE keeps this check's ruler a PRIVATE copy even so. Belt and
	# braces on purpose: the switch above is one line in a file anyone can edit,
	# and a ruler that can be mutated by the thing it is measuring is not a ruler.
	_combat = ResourceLoader.load("res://resources/default_combat_config.tres",
			"", ResourceLoader.CACHE_MODE_IGNORE) as CombatConfig
	for frame_id: String in Frames.ROSTER:
		var config: FlightConfig = Frames.config(frame_id).flight_config
		_cases.append(_case(frame_id, config, SPEEDS[0], "wall"))
	# The datum frame gets the rest: the doubling pair's second half, and the
	# set-down that claim 2 compares against.
	var datum: FlightConfig = Frames.config(DATUM).flight_config
	_cases.append(_case(DATUM, datum, SPEEDS[1], "wall"))
	_cases.append(_case(DATUM, datum, 0.0, "land"))
	print("[crash] law: v^2 / (2 * %.3f m * %.2f) — free under %.1f g, %.4f damage per g"
			% [_combat.crash_crush_m,
			float(ProjectSettings.get_setting("physics/3d/default_gravity")),
			_combat.crash_damage_g, _combat.crash_damage_per_g])
	print("[crash] %d arena cases, then main.tscn for the component claim"
			% _cases.size())
	physics_frame.connect(_on_physics_frame)


func _case(frame_id: String, config: FlightConfig, speed: float,
		kind: String) -> Dictionary:
	return {
		"frame": frame_id,
		"body": config.body_m,
		"mass": config.mass,
		"speed": speed,
		"kind": kind,
	}


func _on_physics_frame() -> void:
	match _phase:
		ARENA_BUILD:
			_build()
			_phase = ARENA_RUN
		ARENA_RUN:
			_ticks += 1
			# HOLD THE APPROACH SPEED until the moment of contact. Without it the
			# 500 kg frame arrives measurably faster than the 0.65 kg one from the
			# same launch — drag scales with frontal area over mass — and a mass
			# comparison silently becomes a drag comparison. Measured before this
			# line existed: a 6% spread across the ladder, entirely from the run-up.
			if _emitted < 0.0 and _hold != Vector3.ZERO:
				_drone.linear_velocity = _hold
			if _emitted < 0.0:
				_speed_before = _drone.linear_velocity.length()
			if _emitted >= 0.0 or _ticks >= MAX_TICKS:
				_record()
		ARENA_RECORD:
			_teardown()
			_index += 1
			if _index >= _cases.size():
				_report_arena()
				_build_main()
				_phase = MAIN_BULLET
			else:
				_phase = ARENA_BUILD
		MAIN_BULLET:
			_run_bullet()
		MAIN_CRASH:
			_run_crash()
		MAIN_READ:
			_read_components()


func _plate(size: Vector3, at: Vector3) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	_arena.add_child(wall)
	wall.global_position = at


func _build() -> void:
	var case: Dictionary = _cases[_index]
	_arena = Node3D.new()
	root.add_child(_arena)

	var body: float = float(case["body"])
	var span: float = maxf(body * 40.0, 200.0)
	_drone = Frames.build(String(case["frame"]))

	if String(case["kind"]) == "wall":
		_plate(Vector3(1.0, span, span), Vector3.ZERO)
		# No gravity on the approach: the only thing under test is what the
		# collision takes away, and a sag toward the floor would add a second one.
		_drone.gravity_scale = 0.0
		_arena.add_child(_drone)
		_drone.global_position = Vector3(-(0.5 + body * 0.5 + RUN_UP), 0.0, 0.0)
		_hold = Vector3(float(case["speed"]), 0.0, 0.0)
		_drone.linear_velocity = _hold
	else:
		_plate(Vector3(span, 1.0, span), Vector3.ZERO)
		_arena.add_child(_drone)
		# Released one body-height above the pad and allowed to fall: the arrival
		# a pilot makes when they set the aircraft down without flaring.
		_drone.global_position = Vector3(0.0, 0.5 + body * 1.5, 0.0)
		_hold = Vector3.ZERO
		_drone.linear_velocity = Vector3.ZERO

	_emitted = -1.0
	_speed_before = 0.0
	_drone.crashed.connect(_on_crashed)
	_ticks = 0


func _on_crashed(impact_speed: float) -> void:
	if _emitted < 0.0:
		_emitted = impact_speed


func _record() -> void:
	var result: Dictionary = _cases[_index].duplicate()
	result["emitted"] = _emitted
	result["before"] = _speed_before
	result["g"] = _combat.impact_g(maxf(_emitted, 0.0))
	result["damage"] = _combat.crash_damage(maxf(_emitted, 0.0))
	_results.append(result)
	_phase = ARENA_RECORD


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null


func _find(frame_id: String, kind: String, speed: float) -> Dictionary:
	for row: Dictionary in _results:
		if row["frame"] == frame_id and row["kind"] == kind \
				and is_equal_approx(float(row["speed"]), speed):
			return row
	return {}


func _report_arena() -> void:
	print("")
	print("[crash] 'before' is the speed the airframe carried into contact;")
	print("[crash] 'took' is what the collision removed in one tick. They agree when")
	print("[crash] the solver stops the body outright, which is where mass would show.")
	print("[crash] %8s %6s %7s %8s %9s %9s %10s %9s"
			% ["frame", "kind", "mass kg", "held m/s", "before", "took",
			"peak g", "damage"])
	for row: Dictionary in _results:
		print("[crash] %8s %6s %7.2f %8.0f %9.3f %9.3f %10.1f %9.2f"
				% [row["frame"], row["kind"], row["mass"], row["speed"],
				row["before"], row["emitted"], row["g"], row["damage"]])
	_check_arena()


## Claims 1 to 3. Claim 4 needs main's wiring and runs after this.
func _check_arena() -> void:
	for row: Dictionary in _results:
		if float(row["emitted"]) < 0.0:
			_failures.append("%s never reached the %s at all — the rig failed, not the law"
					% [row["frame"], row["kind"]])
			return

	# CLAIM 1a — the controlled pair. Same 0.28 m body, 1.9x the mass.
	var kestrel: Dictionary = _find("kestrel", "wall", SPEEDS[0])
	var atlas: Dictionary = _find("atlas", "wall", SPEEDS[0])
	var spread: float = absf(float(atlas["g"]) - float(kestrel["g"])) \
			/ maxf(float(kestrel["g"]), 0.001) * 100.0
	print("")
	print("[crash] CLAIM 1 — MASS IS NOT A SHIELD.")
	print("[crash] Kestrel 0.65 kg and Atlas 1.24 kg share a 0.28 m body, so they are the")
	print("[crash] roster's only pair that varies mass ALONE: %.1f g against %.1f g, %.2f%% apart."
			% [float(kestrel["g"]), float(atlas["g"]), spread])
	if spread > MASS_TOLERANCE_PCT:
		_failures.append("the Atlas (%.2f kg) and the Kestrel (%.2f kg) share a body size but pulled %.1f g and %.1f g from the same held %.0f m/s — %.2f%% apart, over the %.1f%% bound. Mass has entered a law it must not be in"
				% [float(atlas["mass"]), float(kestrel["mass"]), float(atlas["g"]),
				float(kestrel["g"]), SPEEDS[0], spread, MASS_TOLERANCE_PCT])

	# CLAIM 1b — the whole ladder, which is also the guard on the crush distance.
	# A stopping distance that scaled with the airframe would read here as the Roc
	# pulling a tenth of the Kestrel's g, and nothing else in the suite would see it.
	var lowest: float = INF
	var highest: float = 0.0
	for frame_id: String in Frames.ROSTER:
		var row: Dictionary = _find(frame_id, "wall", SPEEDS[0])
		lowest = minf(lowest, float(row["g"]))
		highest = maxf(highest, float(row["g"]))
	var ladder_spread: float = (highest - lowest) / maxf(lowest, 0.001) * 100.0
	print("[crash] Across the whole ladder — 0.28 m to 3.00 m, 0.65 kg to 500 kg — the")
	print("[crash] spread is %.2f%%: %.1f g to %.1f g. Neither size nor mass is in the law."
			% [ladder_spread, lowest, highest])
	if ladder_spread > LADDER_TOLERANCE_PCT:
		_failures.append("the roster spans %.1f g to %.1f g from the same held %.0f m/s (%.2f%%, over the %.1f%% bound) — something about the AIRFRAME is changing how hard it hits a wall, and a crush distance that scales with size is the likely culprit"
				% [lowest, highest, SPEEDS[0], ladder_spread, LADDER_TOLERANCE_PCT])

	# The mass claim at its source, and the one that is not arithmetic: the
	# collision must take the WHOLE velocity, whatever the body weighs. A frame
	# that kept some would be shielded by its mass at the solver, before any
	# formula got a chance to be mass-blind.
	for row: Dictionary in _results:
		if row["kind"] != "wall":
			continue
		var kept: float = float(row["before"]) - float(row["emitted"])
		if absf(kept) > float(row["before"]) * 0.02:
			_failures.append("%s (%.2f kg) carried %.2f m/s into the wall but the collision only took %.2f m/s — a heavier body is being stopped less completely, which is mass acting as a shield underneath the formula"
					% [row["frame"], float(row["mass"]), float(row["before"]),
					float(row["emitted"])])

	# CLAIM 2 — a set-down and a wall are not the same kind of event.
	var land: Dictionary = _find(DATUM, "land", 0.0)
	var wall: Dictionary = _find(DATUM, "wall", SPEEDS[1])
	var ratio: float = float(wall["g"]) / maxf(float(land["g"]), 0.001)
	print("")
	print("[crash] CLAIM 2 — A LANDING IS FREE AND A WALL IS NOT.")
	print("[crash] Set-down %.1f g (%.2f damage), wall at %.0f m/s %.1f g (%.2f damage):"
			% [float(land["g"]), float(land["damage"]), SPEEDS[1],
			float(wall["g"]), float(wall["damage"])])
	print("[crash] %.0fx apart, with the free threshold at %.1f g between them."
			% [ratio, _combat.crash_damage_g])
	if float(land["damage"]) > 0.0:
		_failures.append("a %.2f m/s set-down cost %.2f hull (%.1f g against a %.1f g threshold) — an ordinary landing has to be free or the threshold is doing nothing"
				% [float(land["emitted"]), float(land["damage"]), float(land["g"]),
				_combat.crash_damage_g])
	if float(wall["damage"]) <= 0.0:
		_failures.append("a %.0f m/s wall cost nothing at all — crash damage is not reaching the hull"
				% SPEEDS[1])
	if ratio < LANDING_WALL_RATIO:
		_failures.append("a set-down and a %.0f m/s wall are only %.0fx apart in peak deceleration (want %.0fx) — they should not read as the same kind of event"
				% [SPEEDS[1], ratio, LANDING_WALL_RATIO])

	# CLAIM 3 — the quadratic, and the stage that tells the new law from the old.
	var slow: Dictionary = _find(DATUM, "wall", SPEEDS[0])
	var fast: Dictionary = _find(DATUM, "wall", SPEEDS[1])
	var g_ratio: float = float(fast["g"]) / maxf(float(slow["g"]), 0.001)
	var d_slow: float = float(slow["damage"])
	var d_fast: float = float(fast["damage"])
	print("")
	print("[crash] CLAIM 3 — FASTER IS WORSE, QUADRATICALLY.")
	print("[crash] %.0f m/s -> %.0f m/s multiplies peak deceleration by %.2f (want 4.00)"
			% [SPEEDS[0], SPEEDS[1], g_ratio])
	print("[crash] and damage by %.2f (%.2f -> %.2f)."
			% [d_fast / maxf(d_slow, 0.001), d_slow, d_fast])
	print("[crash] THE RATIO IS THE POINT, not the damage growth. The old delta-v law was")
	print("[crash] LINEAR in speed and still more-than-doubled its damage on a doubled")
	print("[crash] speed, because a free threshold makes any linear law convex. Only a")
	print("[crash] ratio of 4 says the quantity is an acceleration.")
	if absf(g_ratio - 4.0) > QUADRATIC_TOLERANCE:
		_failures.append("doubling the speed multiplied peak deceleration by %.2f rather than 4.00 — the law is not quadratic in speed, so it is not an acceleration (a linear delta-v law reads 2.00 here)"
				% g_ratio)
	if d_fast <= d_slow * 2.0:
		_failures.append("doubling the speed took damage from %.2f to %.2f, which is not even double — nothing about this is superlinear"
				% [d_slow, d_fast])


func _build_main() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_main)
	_main_wait = 0


## Claim 4b, and it runs FIRST so the airframe is still level: a LOCATED hit,
## delivered exactly the way `projectile.gd` delivers one — set the direction it
## came from, then call `take_hit`. Exactly one rotor may move.
func _run_bullet() -> void:
	_main_wait += 1
	if not _main.is_node_ready():
		return
	if _main_drone == null:
		_main_drone = _main.get_node("Drone") as FlightController
		# AND PUT MAIN'S OWN CONFIG BACK TO THE REPO'S NUMBERS. `main.gd:_ready`
		# calls `combat_config.load_from_user()` on the shared
		# default_combat_config.tres, so every check that boots main.tscn measures
		# whatever the human last saved. It is harmless today only because the
		# saved file overrides four unrelated fields and everything else falls
		# back to the SCRIPT's defaults, which currently match the .tres — a leak
		# that agrees with the truth is one nobody notices on the day it stops.
		# `Frames.build` closes exactly this hole for the drone with
		# `load_user_overrides = false`; main has no such flag, so a check that
		# boots it has to say so itself.
		#
		# The per-config `reset_to_defaults` calls that used to sit here are gone:
		# `TunableConfig.user_overrides_enabled` is set false in `_initialize`,
		# which closes the leak for all seven configs main.tscn pulls in rather
		# than for the two this stage happens to ride on.
		if _main_drone.damage_config != null \
				and _main_drone.damage_config.severity <= 0.0:
			_fail("the repo ships DamageConfig.severity at 0, so a hit degrades nothing and this stage cannot distinguish a crash from a bullet")
			return
		# Never armed: an armed drone starts a run, and a run brings waves that
		# would shoot the rotors this stage is counting (repair_check's rule).
		_main_drone.last_hit_direction = (_main_drone.global_basis
				* Vector3(1.0, 0.0, -1.0)).normalized()
		_main_drone.take_hit(40.0)
		_bullet_healths = _healths(_main_drone)
		_main_drone.repair_motors()
		# CLAIM 4c — AND THE CRASH IS FLOWN WITH A STALE BEARING STILL ON THE
		# AIRFRAME, which is the harder case and the one a mutation exposed.
		#
		# `apply_hit_to_motors` reads `last_hit_direction` to choose a corner and
		# frays all four only when it finds none, so the "a crash is directionless"
		# property is really a property of that field being empty. It normally is,
		# because `_incoming_fire_side` clears it at the end of every damage event
		# — but a hit the PLATING EATS ENTIRELY never produces a damage event at
		# all (`Health.take` returns early once armor has taken the lot), so it
		# sets the bearing and nothing clears it. The Atlas ships with 3 armor, so
		# that is reachable in the game today, and the state it leaves is exactly
		# what is planted here.
		#
		# Without it, deleting main's `last_hit_direction = Vector3.ZERO` passed
		# this file unchanged: the sequence happened to clear the field anyway and
		# the guard was untested code wearing a comment.
		_main_drone.last_hit_direction = (_main_drone.global_basis
				* Vector3(-1.0, 0.0, 1.0)).normalized()
		# Dropped from a height that lands between the free threshold and the
		# lethal speed: it has to hurt, and the pilot has to survive to be read.
		_main_drone.global_position = Vector3(0.0, 10.0, 0.0)
		_main_drone.linear_velocity = Vector3(0.0, -12.0, 0.0)
		_main_drone.crashed.connect(_on_main_crashed)
		_phase = MAIN_CRASH
		_main_wait = 0
		return
	if _main_wait > 600:
		_fail("main.tscn never became ready")


## Claim 4a: a real collision, through main's own crash -> hull -> rotors chain.
func _run_crash() -> void:
	_main_wait += 1
	if _main_impact >= 0.0:
		# One tick of grace so main's handlers have certainly run before reading.
		_phase = MAIN_READ
		return
	if _main_wait > 1200:
		_fail("the drone never reached the ground in main.tscn")


func _on_main_crashed(impact_speed: float) -> void:
	if _main_impact < 0.0:
		_main_impact = impact_speed


func _read_components() -> void:
	_crash_healths = _healths(_main_drone)
	var bullet_hurt: int = 0
	var crash_hurt: int = 0
	for i: int in _rotor_count():
		if _bullet_healths[i] < 0.999:
			bullet_hurt += 1
		if _crash_healths[i] < 0.999:
			crash_hurt += 1
	var spread: float = 0.0
	var lowest: float = 1.0
	var highest: float = 0.0
	for i: int in _rotor_count():
		lowest = minf(lowest, _crash_healths[i])
		highest = maxf(highest, _crash_healths[i])
	spread = highest - lowest

	print("")
	print("[crash] CLAIM 4 — A CRASH LOADS EVERY COMPONENT; A BULLET LOADS ONE.")
	print("[crash] Flown in main.tscn, through the real crash -> hull -> rotors chain.")
	print("[crash] a located 40-point hit    -> rotors %s, %d of 4 damaged"
			% [str(_bullet_healths), bullet_hurt])
	print("[crash] a %.1f m/s crash (%.1f g) -> rotors %s, %d of 4 damaged"
			% [_main_impact, _combat.impact_g(_main_impact),
			str(_crash_healths), crash_hurt])

	if _main_impact <= 0.0 or _combat.crash_damage(_main_impact) <= 0.0:
		_fail("the drop landed at %.2f m/s, which this law prices at nothing — the stage cannot say anything about components until the crash actually hurts"
				% _main_impact)
		return
	# A dead pilot's rotor healths mean nothing: `_on_player_died` unwinds the run
	# and the drop was sized to be survivable, so this is the rig failing rather
	# than the claim.
	if not (_main_drone.get_node("Health") as Health).alive:
		_fail("the %.1f m/s drop KILLED the pilot, so the rotor readings below are from a dead airframe — the drop is meant to sit between the free threshold and the lethal speed"
				% _main_impact)
		return
	if bullet_hurt != 1:
		_failures.append("a located hit damaged %d rotors, not 1 — a bullet is supposed to be the LOCATED case, and if it frays the whole airframe then the crash stage below proves nothing"
				% bullet_hurt)
	# WHICH corner, not merely how many (E.q2's repeatability requirement, and the
	# regression guard for generalising the picker from "nearest rotor" to
	# "nearest component" over the registry). The hit is planted on the airframe's
	# front-right bearing, +X and -Z, and `MotorModel`'s order is FL, FR, BL, BR —
	# so it belongs to rotor 1 and to nothing else. Counting alone would pass just
	# as happily on a picker that always chose rotor 0.
	elif _bullet_healths[BULLET_EXPECTS] >= 0.999:
		_failures.append("a hit arriving from the front-right damaged some rotor other than %d (%s) — the count is right and the CHOICE is wrong, which is what E7's 'the same mistake produces the same wound' forbids"
				% [BULLET_EXPECTS, str(_bullet_healths)])
	if crash_hurt != _rotor_count():
		_failures.append("a %.1f m/s crash damaged %d of %d rotors — a crash is a whole-airframe event and every component has to feel it, which is the one thing that distinguishes it from a bullet"
				% [_main_impact, crash_hurt, _rotor_count()])
	if crash_hurt == _rotor_count() and spread > EVEN_FRAY_EPSILON:
		_failures.append("a crash frayed the four rotors by different amounts (spread %.4f) — peak deceleration has no direction, so it cannot prefer a corner"
				% spread)
	_finish()


## Asked of the airframe rather than assumed (E.q1): main.tscn flies a quad
## today, and this check should still mean what it says the day it does not.
func _rotor_count() -> int:
	if _main_drone == null:
		return 0
	var motors: MotorModel = _main_drone.get_node_or_null("MotorModel") as MotorModel
	return 0 if motors == null else motors.rotor_count


func _healths(drone: FlightController) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i: int in _rotor_count():
		out.append(drone.motor_health(i))
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	_finish()


func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	_main = null
	_main_drone = null
	if _failures.is_empty():
		print("")
		print("[crash] PASS")
		quit(0)
	else:
		print("")
		for failure: String in _failures:
			print("[crash] FAIL: %s" % failure)
		print("[crash] FAIL")
		quit(1)
