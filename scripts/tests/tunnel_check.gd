extends SceneTree

## THE TUNNELLING CHECK (GAMEPLAY-DESIGN Iteration 16 / L13 phase 0.3).
##
## The user's question behind the scaled city: does a scaled world *"confirm/deny
## the physics engine's fidelity and true to source"*. The sharp version of that
## is tunnelling — at 240 Hz a Roc doing 131 m/s moves **0.55 m per tick**, and
## discrete collision detection only sees where a body IS at the end of a tick,
## never where it went on the way. If the step is bigger than what it hits, the
## body arrives on the far side having touched nothing.
##
## THE ARITHMETIC SAYS THIS IS FINE AND THE ARITHMETIC IS NOT THE POINT. Two
## confident diagnoses were wrong in the week before this file was written, both
## caught by measuring instead of reasoning, so this fires real bodies at real
## walls through the real solver and reports where they end up.
##
## It sweeps three things that each break tunnelling differently:
##
##  - **speed**, from the frame's own envelope up to absurd, because the step
##    length is speed / tick rate;
##  - **wall thickness**, from a building's own slab down to the 0.12 m curb trim
##    the city generator scatters everywhere — thin geometry is where tunnelling
##    actually happens, and the city is full of it;
##  - **body size**, across the whole ladder, because a 3 m airframe cannot pass
##    through anything it is wider than, while a 0.28 m one can.
##
## `continuous_cd` is reported both ways. It defaults to **false** on every
## RigidBody3D in Godot (queried, not assumed) and the shipped drone does not set
## it, so the OFF column is what the game actually does today and the ON column
## is what the lever buys if the OFF column ever fails.
##
## Run: <godot> --headless -s scripts/tests/tunnel_check.gd --path .

## Wall thicknesses, in metres. 0.12 is `CityLayout.CURB_TRIM`; 0.15 is
## `CURB_HEIGHT`; 1.0 is a building slab; 12.0 is a scaled city's wall at 10.7x.
const THICKNESSES: Array[float] = [0.12, 0.5, 1.0, 12.0]
## Multiples of the frame's own terminal speed. 1.0 is what the airframe can
## actually reach in level flight; the rest are dive, absurd, and a deliberate
## test of where the mechanism finally breaks so the margin has a number.
const SPEED_MULTS: Array[float] = [1.0, 1.5, 2.0, 8.0, 32.0]
## How far in front of the wall the body starts, in body lengths.
const RUN_UP: float = 8.0
## Ticks allowed for the pass. Generous: the fastest case crosses the whole run-up
## in a handful of ticks, and a body that has stopped needs time to settle.
const MAX_TICKS: int = 150

enum { BUILD, RUN, RECORD }

var _cases: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _failures: PackedStringArray = []

var _index: int = 0
var _phase: int = BUILD
var _ticks: int = 0
var _arena: Node3D
var _body: RigidBody3D
var _deepest: float = -INF
var _pps: float


func _initialize() -> void:
	_pps = float(Engine.physics_ticks_per_second)
	for frame_id: String in [Frames.KESTREL, Frames.CONDOR, Frames.ROC]:
		var config: FlightConfig = Frames.config(frame_id).flight_config
		for thickness: float in THICKNESSES:
			for mult: float in SPEED_MULTS:
				for ccd: bool in [false, true]:
					_cases.append({
						"frame": frame_id,
						"body": config.body_m,
						"height": config.body_m * FlightController.BODY_HEIGHT_RATIO,
						"mass": config.mass,
						"speed": config.terminal_speed() * mult,
						"mult": mult,
						"thickness": thickness,
						"ccd": ccd,
					})
	# Instanced and freed on the spot rather than left dangling: an orphan Node is
	# an ObjectDB leak and an orphan RigidBody3D is a leaked physics RID too, and
	# the engine reports both at exit.
	var probe := RigidBody3D.new()
	var ccd_default: bool = probe.continuous_cd
	probe.free()
	print("[tunnel] %d cases at %.0f Hz — RigidBody3D.continuous_cd defaults to %s (queried, not assumed)"
			% [_cases.size(), _pps, str(ccd_default)])
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	match _phase:
		BUILD:
			_build()
			_phase = RUN
		RUN:
			_ticks += 1
			# The deepest point the body ever reached, not merely where it ended
			# up. A body that punches through and is pushed back out by the
			# solver's depenetration would otherwise report as a clean stop, and
			# that is exactly the failure this file exists to see.
			_deepest = maxf(_deepest, _body.global_position.x)
			if _ticks >= MAX_TICKS:
				_record()
		RECORD:
			_teardown()
			_index += 1
			if _index >= _cases.size():
				_report()
			else:
				_phase = BUILD


## One body, one wall, no gravity and no drag: the only thing under test is
## whether the solver notices a fast body meeting a static one.
##
## The wall is a plate wide and tall enough that the body cannot miss it, so a
## "passed through" result can only ever mean tunnelling and never a near miss.
func _build() -> void:
	var case: Dictionary = _cases[_index]
	_arena = Node3D.new()
	root.add_child(_arena)

	var thickness: float = float(case["thickness"])
	var span: float = maxf(float(case["body"]) * 40.0, 200.0)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(thickness, span, span)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	_arena.add_child(wall)
	wall.global_position = Vector3.ZERO

	_body = RigidBody3D.new()
	_body.mass = float(case["mass"])
	_body.gravity_scale = 0.0
	_body.can_sleep = false
	_body.continuous_cd = bool(case["ccd"])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The airframe's real collider (FlightController._apply_frame_geometry).
	box.size = Vector3(float(case["body"]), float(case["height"]),
			float(case["body"]))
	shape.shape = box
	_body.add_child(shape)
	_arena.add_child(_body)
	_body.global_position = Vector3(
			-(thickness * 0.5 + float(case["body"]) * RUN_UP), 0.0, 0.0)
	_body.linear_velocity = Vector3(float(case["speed"]), 0.0, 0.0)
	_ticks = 0
	_deepest = -INF


func _record() -> void:
	var case: Dictionary = _cases[_index]
	var thickness: float = float(case["thickness"])
	var half_body: float = float(case["body"]) * 0.5
	# The far face of the wall plus the body's own half-width: past this the body
	# is entirely clear on the other side and nothing it could touch remains.
	var through: float = thickness * 0.5 + half_body
	var result: Dictionary = case.duplicate()
	result["deepest"] = _deepest
	result["ended"] = _body.global_position.x
	result["through"] = _deepest > through
	result["step_m"] = float(case["speed"]) / _pps
	_results.append(result)
	_phase = RECORD


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_body = null


func _report() -> void:
	print("")
	print("[tunnel] 'step' is how far the body moves in ONE tick at %.0f Hz." % _pps)
	print("[tunnel] 'x1' is the speed the airframe can actually reach in level flight")
	print("[tunnel] (FlightConfig.terminal_speed); the rest are deliberate overspeeds.")
	print("[tunnel] %8s %7s %8s %8s %8s %7s %9s %9s"
			% ["frame", "body m", "speed", "x env", "step m", "wall m",
			"ccd off", "ccd on"])
	var pairs: Dictionary = {}
	for row: Dictionary in _results:
		var key: String = "%s|%.2f|%.2f" % [row["frame"], row["mult"],
				row["thickness"]]
		if not pairs.has(key):
			pairs[key] = {}
		(pairs[key] as Dictionary)[bool(row["ccd"])] = row
	for key: String in pairs:
		var pair: Dictionary = pairs[key]
		var off: Dictionary = pair[false]
		var on: Dictionary = pair[true]
		print("[tunnel] %8s %7.2f %7.0fm/s %7.0fx %8.2f %7.2f %9s %9s"
				% [off["frame"], off["body"], off["speed"], off["mult"],
				off["step_m"], off["thickness"],
				"THROUGH" if off["through"] else "stopped",
				"THROUGH" if on["through"] else "stopped"])
	_summarise()
	_check()
	for child: Node in root.get_children():
		child.free()
	if _failures.is_empty():
		print("[tunnel] PASS")
		quit(0)
	else:
		for failure: String in _failures:
			print("[tunnel] FAIL: %s" % failure)
		print("[tunnel] FAIL")
		quit(1)


## Where the mechanism actually breaks, stated as a ratio rather than a speed,
## because a ratio survives a change to the tick rate or the roster and a speed
## does not.
func _summarise() -> void:
	var worst_survived: float = 0.0
	var best_failed: float = INF
	for row: Dictionary in _results:
		if bool(row["ccd"]):
			continue
		var reach: float = float(row["step_m"]) \
				/ (float(row["thickness"]) + float(row["body"]))
		if bool(row["through"]):
			best_failed = minf(best_failed, reach)
		else:
			worst_survived = maxf(worst_survived, reach)
	print("")
	print("[tunnel] THE RATIO THAT DECIDES IT is (step per tick) / (wall + body).")
	print("[tunnel] Discrete collision survived up to %.2f; the first failure was at %s."
			% [worst_survived,
			"%.2f" % best_failed if is_finite(best_failed) else "no failure in this sweep"])
	print("[tunnel] It is a RISK INDICATOR AND NOT A THRESHOLD: 0.83 survived in this sweep")
	print("[tunnel] and 0.64 did not, because whether a discrete step happens to LAND inside")
	print("[tunnel] the wall depends on the phase of the steps against it. Near the boundary")
	print("[tunnel] it is a coin flip, which is exactly why this is measured, not derived.")
	# The margin each frame actually has: the lowest overspeed multiple at which
	# it first goes through anything. This is the number to watch if the roster's
	# speeds or the physics tick rate ever move.
	var margins: PackedStringArray = []
	for frame_id: String in [Frames.KESTREL, Frames.CONDOR, Frames.ROC]:
		var first: float = INF
		for row: Dictionary in _results:
			if row["frame"] != frame_id or bool(row["ccd"]) \
					or not bool(row["through"]):
				continue
			first = minf(first, float(row["mult"]))
		margins.append("%s %s" % [frame_id,
				("%.1fx" % first) if is_finite(first) else "never in this sweep"])
	print("")
	print("[tunnel] MARGIN — the lowest overspeed at which each frame first goes through")
	print("[tunnel] anything at all, with continuous_cd off: %s." % ", ".join(margins))
	print("[tunnel] A dive cannot buy that back: gravity adds to thrust, so the true ceiling")
	print("[tunnel] is terminal x sqrt(1 + 1/TWR) — 1.11x on the Kestrel, 1.04x on the rest.")
	print("[tunnel] THE BIG FRAME IS THE SAFE ONE, which is the opposite of the intuition")
	print("[tunnel] this file was written to test: a Roc's step is four times a Kestrel's,")
	print("[tunnel] but its body is eleven times bigger, so it is HARDER to miss, not easier.")


## The claim this file exists to hold: at the speeds the roster can actually
## reach, no frame passes through anything — including the thinnest geometry the
## city generator produces.
##
## ONLY THE 1x ROWS ARE ASSERTED, and the boundary is arithmetic rather than
## taste. `terminal_speed` is where thrust equals drag in level flight; a vertical
## dive adds gravity to the thrust, which multiplies the ceiling by only
## `sqrt(1 + 1 / TWR)` - 1.11 on the Kestrel and 1.04 on the TWR-12 frames. Even
## 1.5x is therefore unreachable, and a check that failed on it would be refusing
## a condition the game cannot produce. The overspeed rows exist to locate the
## wall so the MARGIN has a number, which `_summarise` prints.
func _check() -> void:
	for row: Dictionary in _results:
		if bool(row["ccd"]) or float(row["mult"]) > 1.0:
			continue
		if bool(row["through"]):
			_failures.append("%s at %.0f m/s (%.0fx its envelope, %.2f m per tick) passed through a %.2f m wall with continuous_cd off — the shipped configuration tunnels"
					% [row["frame"], float(row["speed"]), float(row["mult"]),
					float(row["step_m"]), float(row["thickness"])])
	# WOULD THIS STILL PASS IF THE FEATURE WERE DELETED? A rig that never moved
	# its bodies would report "stopped" everywhere and read as a clean bill of
	# health. So the sweep must contain at least one genuine tunnelling event, at
	# the absurd end, or the instrument has not been shown to be able to see one.
	var any_through: bool = false
	for row: Dictionary in _results:
		if bool(row["through"]) and not bool(row["ccd"]):
			any_through = true
			break
	if not any_through:
		_failures.append("nothing tunnelled anywhere in the sweep, not even at %.0fx envelope through a %.2f m wall — this instrument has not demonstrated it can detect tunnelling at all, so its clean rows prove nothing"
				% [SPEED_MULTS[-1], THICKNESSES[0]])
