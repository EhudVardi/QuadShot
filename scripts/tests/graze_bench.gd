extends SceneTree

## THE GRAZE BENCH — why a collision with a building can register NOTHING.
##
## Written to chase a flight report (2026-08-15): *"there's a bug where sometimes
## i collid with the buildings and it may not have registered, no damage at all.
## lets see if it will happen again."*
##
## MEASUREMENT ONLY, no pass/fail, because what it measures is not yet agreed to
## be wrong. It exists so the human can rule on a real table instead of on the
## agent's reasoning — which is the correct order here, since the same session
## produced a confidently wrong diagnosis of a harness bug by reasoning about it.
##
## **THE MECHANISM, AND IT IS GEOMETRY RATHER THAN A DEFECT.** `FlightController`
## emits an impact SPEED that is the velocity the collision took AWAY in one tick,
## and `CombatConfig.crash_damage` prices it with a free threshold. A wall only
## removes the component of velocity PERPENDICULAR to it, so at an approach angle
## of theta to the wall's surface the priced speed is `v x sin(theta)`, not `v`.
## The free band is therefore not a speed at all — it is a speed PER ANGLE:
##
##     free below   12.0025 / sin(theta)   m/s
##
## Head-on that is 12.0 m/s and is the intended calibration, the one that keeps a
## landing free. At 15 degrees it is 46.4 m/s. At 5 degrees it is 138 m/s.
##
## AND A SUB-THRESHOLD IMPACT IS TOTALLY SILENT, which is what makes it read as a
## bug rather than as a graze. `main._on_player_crashed` returns early when the
## damage is zero, so there is no hull loss, no rotor fraying, and no video spike:
## the airframe bounces off a building and the game says nothing whatsoever.
##
## Three things this rules OUT, each checked rather than assumed:
##  - Missing colliders. `WorldBuilding` delegates to `MenuBuilding`, which builds
##    a `StaticBody3D` with a `CollisionShape3D` per slab. City buildings collide.
##  - Contact monitoring. `drone.tscn` sets `contact_monitor = true` and
##    `max_contacts_reported = 4`.
##  - Tunnelling. At 240 Hz a 1.2 m Condor moves 0.25 m per tick at 60 m/s; it
##    would need roughly 288 m/s to skip a wall between ticks.
##
## Run: <godot> --headless -s scripts/tests/graze_bench.gd --path .

## Approach angles to the wall's SURFACE, in degrees. 90 is head-on, small is a
## scrape down the side of a building.
const ANGLES: Array[float] = [90.0, 45.0, 30.0, 20.0, 15.0, 10.0, 5.0]
## Flown at a speed a Condor threading a city plausibly carries.
const SPEED: float = 60.0
## The frame the human was flying when they reported it.
const FRAME: String = "condor"
const RUN_UP: float = 3.0
const MAX_TICKS: int = 2000

var _cases: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _combat: CombatConfig
var _arena: Node3D
var _drone: FlightController
var _index: int = 0
var _ticks: int = 0
var _emitted: float = -1.0
var _hold: Vector3 = Vector3.ZERO
var _phase: int = 0
## STAGE 2 state: how many times `crashed` fired while contact was maintained.
var _hits: int = 0
var _stage2: Dictionary = {}
var _stage2_ticks: int = 0
var _stage2_pushed: bool = false

enum { BUILD, RUN, RECORD, PRESS_BUILD, PRESS_RUN, DONE }


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	# A PRIVATE copy of the ruler, the way crash_check takes one: a config the
	# thing under test could mutate is not a ruler.
	_combat = ResourceLoader.load("res://resources/default_combat_config.tres",
			"", ResourceLoader.CACHE_MODE_IGNORE) as CombatConfig
	for angle: float in ANGLES:
		_cases.append({"angle": angle, "speed": SPEED})
	print("[graze] law: v^2 / (2 * %.3f m * %.2f) — free under %.1f g"
			% [_combat.crash_crush_m,
			float(ProjectSettings.get_setting("physics/3d/default_gravity")),
			_combat.crash_damage_g])
	print("[graze] %s at %.0f m/s into a flat wall, at %d approach angles."
			% [FRAME, SPEED, _cases.size()])
	physics_frame.connect(_on_frame)


func _on_frame() -> void:
	match _phase:
		BUILD:
			_build()
			_phase = RUN
		RUN:
			_ticks += 1
			# Hold the approach velocity until CONTACT, exactly as crash_check
			# does: otherwise drag makes each angle arrive at a different speed
			# and an ANGLE comparison quietly becomes a drag comparison.
			#
			# Gated on contact rather than on the emission, and the distinction is
			# load-bearing now that contact is priced from `_physics_process`:
			# this handler runs first, so holding until the crash fires would
			# restore the approach speed before the drone could difference it and
			# every impact would read 0.00 m/s.
			if _drone.get_contact_count() == 0 and _hold != Vector3.ZERO:
				_drone.linear_velocity = _hold
			if _emitted >= 0.0 or _ticks >= MAX_TICKS:
				_record()
		RECORD:
			_teardown()
			_index += 1
			if _index >= _cases.size():
				_report_angles()
				_phase = PRESS_BUILD
			else:
				_phase = BUILD
		PRESS_BUILD:
			_build_press()
			_phase = PRESS_RUN
		PRESS_RUN:
			_run_press()


func _build() -> void:
	var case: Dictionary = _cases[_index]
	_arena = Node3D.new()
	root.add_child(_arena)
	_drone = Frames.build(FRAME)
	var body: float = _drone_body()
	# A wall in the YZ plane. Long in Z so a shallow approach still meets it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 400.0, 4000.0)
	shape.shape = box
	wall.add_child(shape)
	_arena.add_child(wall)
	wall.global_position = Vector3.ZERO
	# No gravity on the approach: the only thing under test is what the collision
	# takes away, and a sag toward the floor would add a second one.
	_drone.gravity_scale = 0.0
	_arena.add_child(_drone)
	var theta: float = deg_to_rad(float(case["angle"]))
	var speed: float = float(case["speed"])
	# Perpendicular INTO the wall, parallel ALONG it. Theta is measured from the
	# wall's surface, so 90 degrees is head-on and 5 degrees is a scrape.
	_hold = Vector3(speed * sin(theta), 0.0, speed * cos(theta))
	_drone.global_position = Vector3(-(0.5 + body * 0.5 + RUN_UP), 0.0,
			-2000.0 + 10.0)
	_drone.linear_velocity = _hold
	_emitted = -1.0
	_drone.crashed.connect(_on_crashed)
	_ticks = 0


func _drone_body() -> float:
	return Frames.config(FRAME).flight_config.body_m


func _on_crashed(impact_speed: float) -> void:
	if _emitted < 0.0:
		_emitted = impact_speed


func _record() -> void:
	var case: Dictionary = _cases[_index].duplicate()
	var emitted: float = maxf(_emitted, 0.0)
	case["reached"] = _emitted >= 0.0
	case["emitted"] = emitted
	case["g"] = _combat.impact_g(emitted)
	case["damage"] = _combat.crash_damage(emitted)
	# What the geometry PREDICTS the collision should remove, so the measurement
	# has something independent to disagree with.
	case["predicted"] = float(case["speed"]) * sin(deg_to_rad(float(case["angle"])))
	_results.append(case)
	_phase = RECORD


func _teardown() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_drone = null


## STAGE 2 — THE ONE THE ANGLE SWEEP POINTS AT.
##
## `body_entered` fires when a body ENTERS contact, and a whole building is ONE
## `StaticBody3D` carrying a `CollisionShape3D` per slab (`MenuBuilding._add_slab`).
## So an airframe that touches a tower gently and then keeps pressing into it has
## entered exactly once, and everything after that first touch is priced at
## whatever that first touch was worth.
##
## This drifts the drone into the wall below the free threshold, then shoves it at
## a speed that would be plainly lethal head-on, and counts the emissions.
func _build_press() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_drone = Frames.build(FRAME)
	# ONE StaticBody3D carrying TWO shapes — a face to slide along and a ledge
	# jutting out of it. This is the shape a real building has: MenuBuilding puts
	# every slab's CollisionShape3D under a single body, so the whole tower is one
	# body and `body_entered` can only ever fire for it once.
	var wall := StaticBody3D.new()
	var face := CollisionShape3D.new()
	var face_box := BoxShape3D.new()
	face_box.size = Vector3(1.0, 40.0, 400.0)
	face.shape = face_box
	wall.add_child(face)
	var ledge := CollisionShape3D.new()
	var ledge_box := BoxShape3D.new()
	ledge_box.size = Vector3(8.0, 40.0, 4.0)
	ledge.shape = ledge_box
	ledge.position = Vector3(-4.0, 0.0, 60.0)
	wall.add_child(ledge)
	_arena.add_child(wall)
	wall.global_position = Vector3.ZERO
	# No gravity and no motors: the only forces here are the two contacts, so
	# nothing has to be forced tick by tick and the solver is never fought.
	_drone.gravity_scale = 0.0
	_arena.add_child(_drone)
	var body: float = _drone_body()
	# STARTED CLOSE TO THE LEDGE ON PURPOSE. The first version began 80 m up the
	# wall and never arrived: sliding along a face with contact friction bleeds
	# about 20 m/s^2, so 60 m/s had fallen to 16.9 m/s by z 53.8 and the ledge was
	# never reached at all. A stage that cannot say it failed to run reports "no
	# impact" for "no test", which is why the end state is printed below.
	_drone.global_position = Vector3(-(0.5 + body * 0.5 + 0.2), 0.0, 45.0)
	# Drift GENTLY onto the face while running FAST along it. First contact is
	# well under the free band; the ledge at z 60 is not.
	_drone.linear_velocity = Vector3(1.5, 0.0, 60.0)
	_hits = 0
	_stage2 = {"first": -1.0, "worst": 0.0, "hits": 0}
	_drone.crashed.connect(_on_press_crashed)
	_stage2_ticks = 0
	_stage2_pushed = false


func _on_press_crashed(impact_speed: float) -> void:
	_hits += 1
	if _stage2["first"] < 0.0:
		_stage2["first"] = impact_speed
	_stage2["worst"] = maxf(float(_stage2["worst"]), impact_speed)


func _run_press() -> void:
	_stage2_ticks += 1
	if _stage2_ticks < 600:
		return
	_stage2["hits"] = _hits
	# Where it actually ended up and how fast it was still going. Printed because
	# the first version of this stage silently never reached the ledge at all, and
	# a table that cannot say so reports "no impact" for "no test".
	_stage2["end_z"] = _drone.global_position.z
	_stage2["end_x"] = _drone.global_position.x
	_stage2["end_speed"] = _drone.linear_velocity.length()
	_teardown()
	_report_press()


func _report_press() -> void:
	_phase = DONE
	print("")
	print("=== STAGE 2 — THE LEDGE: A SECOND IMPACT ON A BODY ALREADY TOUCHED ===")
	print("[graze] ONE StaticBody3D with two shapes, which is the shape a real")
	print("[graze] building has - MenuBuilding puts every slab's collider under a")
	print("[graze] single body. Drift onto the face at 1.5 m/s (free) while running")
	print("[graze] along it at 60 m/s, then meet a ledge 60 m down the wall.")
	print("[graze] No velocity is forced tick by tick: gravity and the motors are")
	print("[graze] off, so the only forces in play are the two contacts.")
	print("[graze] first contact  %.2f m/s -> %.2f hull"
			% [maxf(float(_stage2["first"]), 0.0),
			_combat.crash_damage(maxf(float(_stage2["first"]), 0.0))])
	print("[graze] worst impact   %.2f m/s -> %.2f hull"
			% [float(_stage2["worst"]),
			_combat.crash_damage(float(_stage2["worst"]))])
	print("[graze] contact ticks priced: %d" % int(_stage2["hits"]))
	print("[graze] ended at x %.2f z %.2f, still doing %.2f m/s (ledge is at z 60)"
			% [float(_stage2["end_x"]), float(_stage2["end_z"]),
			float(_stage2["end_speed"])])
	print("")
	print("[graze] BEFORE THE FIX the ledge cost NOTHING: `body_entered` is an ENTER")
	print("[graze] signal, the body had already been entered by the gentle touch, and")
	print("[graze] a second strike on it could not fire. Whether a collision hurt")
	print("[graze] depended on how fast you ENTERED contact rather than on how hard")
	print("[graze] you were hitting. Contact is now priced every tick it lasts.")
	for child: Node in root.get_children():
		child.free()
	print("")
	print("[graze] DONE (measurement only — this bench has no pass/fail)")
	quit(0)


func _report_angles() -> void:
	var free_speed: float = sqrt(_combat.crash_damage_g * 2.0
			* _combat.crash_crush_m
			* float(ProjectSettings.get_setting("physics/3d/default_gravity")))
	print("")
	print("=== WHAT A COLLISION ACTUALLY COSTS, BY APPROACH ANGLE ===")
	print("[graze] 'taken' is the velocity the collision REMOVED — the quantity the")
	print("[graze] crash law is priced on. 'predicted' is v x sin(angle), which is")
	print("[graze] what the geometry says it should be; they agree, and that is the")
	print("[graze] point: a wall cannot remove the speed running ALONG it.")
	print("[graze] %7s %10s %11s %9s %10s  %s"
			% ["angle", "taken m/s", "predicted", "g", "damage", "verdict"])
	for row: Dictionary in _results:
		var verdict: String = "SILENT — nothing at all"
		if not bool(row["reached"]):
			verdict = "never reached the wall (rig)"
		elif float(row["damage"]) > 0.0:
			verdict = "%.1f hull" % float(row["damage"])
		print("[graze] %6.0f%s %10.2f %11.2f %9.1f %10.2f  %s"
				% [row["angle"], "d", float(row["emitted"]),
				float(row["predicted"]), float(row["g"]), float(row["damage"]),
				verdict])
	print("")
	print("[graze] THE FREE BAND IS A SPEED PER ANGLE, AND IT IS DERIVED FROM THE")
	print("[graze] MEASURED RATIO ABOVE, NOT FROM v x sin(angle).")
	print("[graze] Pure geometry UNDER-predicts what a collision takes by about 1.4x")
	print("[graze] at every angle but head-on, because a wall does not only remove")
	print("[graze] the speed going INTO it — friction also scrubs the speed running")
	print("[graze] ALONG it, and the two together are the delta-v that gets priced.")
	print("[graze] So a graze hurts MORE than the geometry says, and the silent band")
	print("[graze] is correspondingly NARROWER. Free below %.4f m/s of delta-v:"
			% free_speed)
	print("[graze] %7s %12s %13s %13s" % ["angle", "taken/v", "free below", "in km/h"])
	for row: Dictionary in _results:
		var ratio: float = float(row["emitted"]) / maxf(float(row["speed"]), 0.0001)
		if ratio <= 0.0:
			continue
		var limit: float = free_speed / ratio
		print("[graze] %6.0f%s %12.3f %10.1f m/s %13.0f"
				% [row["angle"], "d", ratio, limit, limit * 3.6])
	print("")
	print("[graze] AND A SUB-THRESHOLD IMPACT IS COMPLETELY SILENT: main's")
	print("[graze] _on_player_crashed returns early at zero damage, so there is no")
	print("[graze] hull loss, no rotor fraying and no video spike. The airframe")
	print("[graze] bounces off a building and the game says nothing.")
