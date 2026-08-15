extends SceneTree

## THE AIRFRAME PLATE'S LAYOUT (GAMEPLAY-DESIGN Iteration 17 / E.q5).
##
## The HUD draws the airframe from above and hangs every component where it
## physically sits — the human's design: *"have a top image of our craft (a
## projection of the craft from top to bottom) with equipment shown and what is
## mounted and where."*
##
## **THIS FILE EXISTS BECAUSE THE WIDGET IT GUARDS HAS ALREADY CARRIED THE
## SIZE-LADDER SCAR ONCE.** The motor block used to be `for i: int in 4` over a
## hand-authored 2x2 table, so a six-rotor frame would have drawn four gauges and
## silently dropped two rotors. That was found by an audit, not by a check, and an
## audit does not run again tomorrow.
##
## Five claims, and claim 5 is the one with teeth:
##
##  1. **Every rotor gets a place, whatever the count.** Four on a quad, six on
##     the hexa, taken from the frame rather than from a constant.
##  2. **The picture is nose-up.** A rotor mounted forward on the airframe must
##     draw above one mounted aft, or a lit gauge cannot mean "that corner".
##  3. **Nothing is drawn off the plate**, including a lens mounted further
##     forward than the rotors — which is the Condor and the Roc, not a
##     hypothetical.
##  4. **The structure pool gets no place at all.** It is the whole airframe (E5)
##     and already has the health bar; drawing it as a component would make the
##     coarse layer look like a part.
##  5. **THE ROTOR RING IS THE SAME SIZE ON EVERY FRAME.** The layout normalises
##     on the ROTOR SPAN, not on the widest part of the airframe. Scaling to fit
##     everything is the obvious implementation and it silently shrinks the ring
##     by a third on any frame whose lens reaches past its rotors, so the picture
##     changes shape between frames. Nothing else here would notice.
##
## Run: <godot> --headless -s scripts/tests/hud_check.gd --path .

var _drones: Dictionary = {}
var _failures: PackedStringArray = []
var _rows: Array[Dictionary] = []
var _done: bool = false


func _initialize() -> void:
	# An instrument measures the REPO's numbers, never one machine's tuning.
	TunableConfig.user_overrides_enabled = false
	for frame_id: String in Frames.ROSTER:
		var drone: FlightController = Frames.build(frame_id)
		root.add_child(drone)
		drone.freeze = true
		_drones[frame_id] = drone
	physics_frame.connect(_on_frame)


## On a PHYSICS FRAME, never in `_initialize`: `add_child` there defers `_ready`,
## so the motor model is still Nil and every reading is an engine error.
func _on_frame() -> void:
	if _done:
		return
	_done = true
	var centre := Vector2(100.0, 100.0)
	for frame_id: String in Frames.ROSTER:
		var drone: FlightController = _drones[frame_id]
		var parts: Array[AirframeComponents.Part] = AirframeComponents.of(drone)
		var points: Dictionary = GameHud.ComponentStatus.layout(parts, centre)
		_rows.append(_measure(frame_id, drone, parts, points, centre))
	_report(centre)


func _measure(frame_id: String, drone: FlightController,
		parts: Array[AirframeComponents.Part], points: Dictionary,
		centre: Vector2) -> Dictionary:
	var motors: MotorModel = drone.get_node("MotorModel") as MotorModel
	var placed_rotors: int = 0
	var ring: float = 0.0
	var forward_y: float = INF
	var aft_y: float = -INF
	var furthest: float = 0.0
	for part: AirframeComponents.Part in parts:
		if not points.has(part.id):
			continue
		var at: Vector2 = points[part.id]
		furthest = maxf(furthest, (at - centre).length())
		if part.kind != &"rotor":
			continue
		placed_rotors += 1
		ring = maxf(ring, (at - centre).length())
		# Body -Z is the nose; screen -Y is up.
		if part.position.z < -0.0001:
			forward_y = minf(forward_y, at.y)
		elif part.position.z > 0.0001:
			aft_y = maxf(aft_y, at.y)
	# CLAIM 6's raw material: how deep into the hull silhouette the worst-placed
	# non-rotor component sits. Rotors are exempt — they are out on the arms and
	# the hull is drawn between them by construction.
	var deepest: float = -INF
	var worst: String = ""
	for part: AirframeComponents.Part in parts:
		if not points.has(part.id) or part.kind == &"rotor":
			continue
		var d: Vector2 = points[part.id] - centre
		var half: Vector2 = GameHud.ComponentStatus.HULL_HALF
		# Negative = outside the box on at least one axis; positive = inside both.
		var inside: float = minf(half.x - absf(d.x), half.y - absf(d.y))
		if inside > deepest:
			deepest = inside
			worst = String(part.id)
	return {
		"frame": frame_id,
		"rotors": motors.rotor_count,
		"placed": placed_rotors,
		"ring": ring,
		"forward_y": forward_y,
		"aft_y": aft_y,
		"furthest": furthest,
		"has_structure": points.has(&"structure"),
		"deepest": deepest,
		"worst": worst,
	}


func _report(centre: Vector2) -> void:
	print("[hud] the airframe plate, projected from each frame's own mounts.")
	print("[hud] 'ring' is how far the widest rotor sits from the hub, in pixels;")
	print("[hud] 'furthest' is the most distant thing drawn, lens included.")
	print("[hud] %8s %8s %8s %8s %10s %10s"
			% ["frame", "rotors", "placed", "ring px", "furthest", "structure"])
	for row: Dictionary in _rows:
		print("[hud] %8s %8d %8d %8.1f %10.1f %10s"
				% [row["frame"], int(row["rotors"]), int(row["placed"]),
				float(row["ring"]), float(row["furthest"]),
				"drawn" if bool(row["has_structure"]) else "none"])
	_check(centre)
	for child: Node in root.get_children():
		child.free()
	# if/else, NOT an early `quit(0)`: SceneTree.quit sets a flag and execution
	# carries straight on, so the passing branch fell through and printed FAIL
	# underneath its own PASS. board.sh reads the LAST verdict line, so this check
	# would have reported every green run as a failure.
	if _failures.is_empty():
		print("")
		print("[hud] PASS")
		quit(0)
	else:
		print("")
		for failure: String in _failures:
			print("[hud] FAIL: %s" % failure)
		print("[hud] FAIL")
		quit(1)


func _check(_centre: Vector2) -> void:
	# CLAIM 1 — every rotor gets a place, whatever the count.
	print("")
	print("[hud] CLAIM 1 — EVERY ROTOR IS PLACED, WHATEVER THE COUNT.")
	for row: Dictionary in _rows:
		if int(row["placed"]) != int(row["rotors"]):
			_failures.append("the %s carries %d rotors and the plate placed %d of them — this widget has already dropped rotors once by assuming four, and a frame whose gauges silently vanish is worse than no gauges"
					% [row["frame"], int(row["rotors"]), int(row["placed"])])
	var hexa: Dictionary = _find(Frames.HEXA)
	if not hexa.is_empty() and int(hexa["placed"]) <= 4:
		_failures.append("the hexa placed only %d rotors — the layout is assuming a quad again"
				% int(hexa["placed"]))

	# CLAIM 2 — nose up, so a lit gauge means a place on the aircraft.
	print("[hud] CLAIM 2 — THE PICTURE IS NOSE-UP:")
	for row: Dictionary in _rows:
		var forward: float = float(row["forward_y"])
		var aft: float = float(row["aft_y"])
		if is_inf(forward) or is_inf(aft):
			continue
		if forward >= aft:
			_failures.append("on the %s a forward rotor drew at y %.1f and an aft one at y %.1f — forward must be UP the screen, or the plate is a list of gauges rather than a picture of the aircraft"
					% [row["frame"], forward, aft])
	print("[hud] forward rotors draw above aft ones on every frame.")

	# CLAIM 3 — nothing is drawn off the plate.
	var edge: float = GameHud.ComponentStatus.EDGE
	print("[hud] CLAIM 3 — NOTHING IS DRAWN OFF THE PLATE (edge %.0f px):" % edge)
	for row: Dictionary in _rows:
		if float(row["furthest"]) > edge * 1.45:
			_failures.append("on the %s something drew %.1f px from the hub against a %.0f px edge — a lens mounted further forward than the rotors has to be pulled back onto the plate, and the Condor and Roc both have one"
					% [row["frame"], float(row["furthest"]), edge])
	print("[hud] furthest anything reached: %.1f px." % _worst_reach())

	# CLAIM 4 — the structure pool is not a component.
	for row: Dictionary in _rows:
		if bool(row["has_structure"]):
			_failures.append("the %s drew the structure pool on the plate — it is the whole airframe (E5) and already has the health bar, so drawing it here makes the coarse layer look like a part"
					% row["frame"])

	# CLAIM 5 — THE ONE WITH TEETH. The ring is normalised on the ROTOR span, so
	# it is identical on every frame; normalising on the whole airframe is the
	# obvious alternative and would shrink it wherever the lens reaches furthest.
	print("")
	print("[hud] CLAIM 5 — THE ROTOR RING IS THE SAME SIZE ON EVERY FRAME.")
	var lowest: float = INF
	var highest: float = 0.0
	for row: Dictionary in _rows:
		lowest = minf(lowest, float(row["ring"]))
		highest = maxf(highest, float(row["ring"]))
	var spread: float = (highest - lowest) / maxf(highest, 0.001) * 100.0
	print("[hud] %.1f px to %.1f px, %.2f%% apart." % [lowest, highest, spread])
	# CLAIM 6 — nothing is drawn ON TOP OF THE HULL. Added after the human flew it:
	# once hull became the silhouette itself, the lens landed on the box edge and
	# its reading was drawn over the fill.
	#
	# IT ASSERTS A CLEARANCE, NOT MERELY "OUTSIDE THE BOX", and the difference is
	# the whole value of the claim. Dropping the clearance leaves the lens 0.7 px
	# beyond the hull's edge — technically outside, and the first version of this
	# assertion passed on it — while the transmitter's arcs reach 12 px and its
	# reading is drawn further out still. A mount point is not what gets drawn.
	print("")
	print("[hud] CLAIM 6 — NOTHING IS MOUNTED ON TOP OF THE HULL SILHOUETTE.")
	var wanted: float = GameHud.ComponentStatus.HULL_CLEAR
	print("[hud] every non-rotor mount must clear the silhouette by %.0f px, which is"
			% wanted)
	print("[hud] what the glyphs and their readings actually occupy.")
	print("[hud] %8s %10s %14s" % ["frame", "worst", "clearance px"])
	for row: Dictionary in _rows:
		var clear_by: float = -float(row["deepest"])
		print("[hud] %8s %10s %14.1f" % [row["frame"], row["worst"], clear_by])
		if clear_by < wanted - 0.5:
			_failures.append("on the %s the '%s' mount clears the hull silhouette by only %.1f px against the %.0f px its glyph and reading occupy — it is drawn over the integrity gauge. Being merely OUTSIDE the box is not enough: without the clearance the lens sits 0.7 px past the edge and still overlaps"
					% [row["frame"], row["worst"], clear_by, wanted])

	if spread > 1.0:
		_failures.append("the rotor ring is %.1f px on one frame and %.1f px on another (%.2f%% apart) — it must be IDENTICAL on every frame, and it stops being so the moment the layout is normalised on the whole airframe instead of the rotor span. Measured, that mutation moves it 1.7%% today because the Condor's and Roc's lenses sit just past the rotor diagonal; a longer-nosed frame would move it far more, and the failure is that the picture changes shape at all"
				% [lowest, highest, spread])


func _find(frame_id: String) -> Dictionary:
	for row: Dictionary in _rows:
		if row["frame"] == frame_id:
			return row
	return {}


func _worst_reach() -> float:
	var worst: float = 0.0
	for row: Dictionary in _rows:
		worst = maxf(worst, float(row["furthest"]))
	return worst
