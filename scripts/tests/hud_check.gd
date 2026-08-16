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

	_check_attitude()

	if spread > 1.0:
		_failures.append("the rotor ring is %.1f px on one frame and %.1f px on another (%.2f%% apart) — it must be IDENTICAL on every frame, and it stops being so the moment the layout is normalised on the whole airframe instead of the rotor span. Measured, that mutation moves it 1.7%% today because the Condor's and Roc's lenses sit just past the rotor diagonal; a longer-nosed frame would move it far more, and the failure is that the picture changes shape at all"
				% [lowest, highest, spread])


## CLAIMS 7 TO 9 — THE ATTITUDE INSTRUMENTS, which are pure geometry and so are
## the one part of a HUD that CAN be checked headless.
##
## They exist because the sky-tick's sign was wrong in the first version and a
## rendered boot did not catch it: `world_up_screen` returned `(-sin, -cos)`
## instead of `(sin, -cos)`, which is IDENTICAL at zero roll and backwards
## everywhere else. Level flight looked perfect. So every claim below is asserted
## at a ROLL, never only at level.
func _check_attitude() -> void:
	var H := GameHud.HorizonLine
	print("")
	print("[hud] CLAIM 7 — THE SKY IS UP WHEN LEVEL, AND TILTS THE RIGHT WAY.")
	var level: Vector2 = H.world_up_screen(0.0)
	print("[hud] roll 0: world up projects to (%.2f, %.2f)" % [level.x, level.y])
	if level.distance_to(Vector2(0.0, -1.0)) > 0.001:
		_failures.append("at zero roll the sky must be straight up the screen (0, -1) and it reads (%.2f, %.2f)"
				% [level.x, level.y])
	# Roll is atan2(basis.x.y, basis.y.y), so a POSITIVE roll is the camera's own
	# right side lifted — and the sky must then lean to screen RIGHT.
	var rolled: Vector2 = H.world_up_screen(deg_to_rad(30.0))
	print("[hud] roll +30: world up projects to (%.2f, %.2f), x must be positive"
			% [rolled.x, rolled.y])
	if rolled.x <= 0.0:
		_failures.append("at +30 degrees of roll the sky leans to screen x %.2f — the sign is inverted, which is the exact bug this claim was written for and it is invisible at zero roll"
				% rolled.x)
	if absf(rolled.length() - 1.0) > 0.001:
		_failures.append("the projected sky direction is not a unit vector (%.3f long)"
				% rolled.length())

	print("")
	print("[hud] CLAIM 8 — TILT OFF VERTICAL IS THE ANGLE IT CLAIMS TO BE.")
	print("[hud] %14s %12s" % ["thrust axis", "tilt deg"])
	# cos(tilt) of the thrust is what still fights gravity, so these numbers are
	# the pilot's lift budget and not decoration.
	var cases: Array = [
		[Vector3.UP, 0.0],
		[Vector3(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), 0.0), 30.0],
		[Vector3(0.0, cos(deg_to_rad(60.0)), -sin(deg_to_rad(60.0))), 60.0],
		[Vector3(1.0, 0.0, 0.0), 90.0],
	]
	for case: Array in cases:
		var got: float = H.tilt_degrees(case[0] as Vector3)
		print("[hud] %14s %12.2f" % [str(case[0]).substr(0, 14), got])
		if absf(got - float(case[1])) > 0.05:
			_failures.append("a thrust axis %s is %.1f degrees off vertical and the instrument reads %.2f — the number is a lift budget (only cos(tilt) still fights gravity), so it cannot be approximate"
					% [str(case[0]), float(case[1]), got])
	if H.tilt_degrees(Vector3.ZERO) != 0.0:
		_failures.append("an unset thrust axis must read 0 rather than a NaN out of acos")

	print("")
	print("[hud] CLAIM 9 — LEVEL MEANS THE TWO LINES COINCIDE, EXACTLY.")
	print("[hud] The whole instrument is the GAP between the world horizon and the")
	print("[hud] airframe's own level line, so a level aircraft must close it to")
	print("[hud] nothing — by construction, never by tuning.")
	# THE THRUST AXIS IS DERIVED FROM AN AIRFRAME BASIS, exactly as the game
	# derives it (`_drone.global_basis.y`), and the tilt is SWEPT. Comparing a
	# level aircraft's axis against world up directly would be a tautology — the
	# two are the same vector by definition — so the claim would compare the
	# function to itself and could never fail. Sweeping the tilt is what gives it
	# teeth, and 0.5 degrees is in the sweep because the small-angle regime is
	# where an alignment instrument either works or is decoration.
	print("[hud] %10s %14s %14s" % ["tilt deg", "line gap deg", "printed deg"])
	for tilt_deg: float in [0.0, 0.5, 5.0, 30.0, 60.0]:
		var airframe := Basis(Vector3.RIGHT, deg_to_rad(-tilt_deg))
		var axis: Vector3 = airframe.y
		var world: Vector2 = H.reference_pitch_roll(Basis.IDENTITY, Vector3.UP)
		var frame: Vector2 = H.reference_pitch_roll(Basis.IDENTITY, axis)
		var gap: float = rad_to_deg(absf(frame.x - world.x))
		var printed: float = H.tilt_degrees(axis)
		print("[hud] %10.1f %14.3f %14.3f" % [tilt_deg, gap, printed])
		if absf(gap - tilt_deg) > 0.05:
			_failures.append("an aircraft tilted %.1f degrees separated the two lines by %.3f — the GAP IS THE TILT, and at level it must close to nothing or the instrument cannot be trusted at the small angles that alignment is actually about"
					% [tilt_deg, gap])
		# The picture and the number have to be the same claim. They come from
		# different arithmetic, so nothing but a check makes them agree.
		if absf(printed - tilt_deg) > 0.05:
			_failures.append("the line puts the aircraft %.1f degrees off level and the printed readout says %.3f — the picture and the number are telling the pilot different things"
					% [tilt_deg, printed])
	if H.reference_pitch_roll(Basis.IDENTITY, Vector3.ZERO) != Vector2.ZERO:
		_failures.append("an unset thrust axis must produce no line rather than a NaN")

	# CLAIM 9c — THE BRACKET'S PEG MARGIN CLEARS THE AIRFRAME PLATE. Found by
	# SCREENSHOTTING the HUD rather than by reasoning about it.
	#
	# `fpv_uptilt_deg` is 48 on a 94-degree lens, which puts the airframe's own
	# level plane 559 px below the boresight — off the bottom of a 1080 screen in
	# EVERY attitude, because in FPV the lens is bolted to the frame. So the
	# bracket is always pegged and where it pegs to matters.
	print("")
	print("[hud] CLAIM 9c — THE BRACKET'S PEG CLEARS THE AIRFRAME PLATE.")
	var margin: float = H.PEG_MARGIN
	var plate_top: float = GameHud.ComponentStatus.PLATE.y + 26.0
	print("[hud] peg margin %.0f px; the plate's top edge is %.0f px up."
			% [margin, plate_top])
	if margin < plate_top:
		_failures.append("a pegged line sits %.0f px from the edge while the AIRFRAME plate reaches %.0f px up, so the two overlap — the first screenshot ever taken of this line had it drawn straight through the middle of the plate"
				% [margin, plate_top])
	# And the peg must never be so deep that it eats the middle of the screen.
	if margin > 1080.0 * 0.5 * 0.75:
		_failures.append("the peg margin %.0f px pulls a clamped line most of the way to screen centre, where it reads as a true horizon rather than as a clamped one"
				% margin)

	# CLAIM 9d — THE WORLD HORIZON IS NEVER MOVED, AND THIS IS THE CLAIM THAT
	# REFUSES A CLAMP. The human flew the clamped version and reported both of its
	# failures: *"the entire horizon indicator first disconnects from the horizon
	# line... and if i pitch even more then the entire horizon indicator lines
	# disappear."*
	#
	# Asserting "the drawn offset equals tan(pitch) * f" would compare the function
	# to itself, which is the tautology round 4 wrote and caught. What cannot be
	# faked is BEHAVIOUR PAST THE EDGE: a clamp flattens, and a true projection
	# keeps growing however far off screen it goes. So the sweep runs well beyond
	# any screen and demands strict growth at every step.
	print("")
	print("[hud] CLAIM 9d — THE HORIZON IS NEVER CLAMPED.")
	var focal: float = H.focal_px(1080.0, 94.0)
	var half_screen: float = 540.0
	print("[hud] %10s %14s %14s %10s" % ["cam pitch", "drop px", "vs half-screen",
			"grew"])
	var previous_drop: float = -1.0
	var beyond: int = 0
	for pitch_deg: float in [0.0, 10.0, 30.0, 48.0, 60.0, 75.0, 85.0]:
		var got: float = H.horizon_drop(deg_to_rad(pitch_deg), focal)
		var grew: bool = got > previous_drop
		print("[hud] %10.0f %14.1f %14s %10s" % [pitch_deg, got,
				"off screen" if got > half_screen else "on screen",
				"yes" if grew else "NO"])
		if not grew:
			_failures.append("the horizon offset did not grow between the step below %.0f degrees and %.0f degrees (%.1f then %.1f) — it is being clamped, and a clamped horizon is a line drawn where the horizon is not"
					% [pitch_deg, pitch_deg, previous_drop, got])
		if got > half_screen:
			beyond += 1
		previous_drop = got
	if beyond < 3:
		_failures.append("only %d of the swept pitches put the horizon past the screen edge, so this claim never exercises the case it exists for"
				% beyond)
	# The zero-degree rung IS the horizon, and they are computed by different
	# expressions in different functions. If they ever disagree the ladder is
	# hanging off a line that is somewhere else.
	for pitch_deg: float in [12.0, 37.0]:
		var line: float = H.horizon_drop(deg_to_rad(pitch_deg), focal)
		var rung: float = H.rung_offset(pitch_deg, focal)
		if absf(line - rung) > 0.01:
			_failures.append("at %.0f degrees the horizon draws at %.2f px and the ladder places the same angle at %.2f px — the ladder must hang off the line it is drawn from"
					% [pitch_deg, line, rung])
	# NaN hygiene: `tan` runs away at the poles and an infinity would poison every
	# rung position downstream of it.
	for pitch_deg: float in [-90.0, 90.0]:
		var polar: float = H.horizon_drop(deg_to_rad(pitch_deg), focal)
		if not is_finite(polar):
			_failures.append("looking straight %s produced %s rather than a finite offset"
					% ["up" if pitch_deg > 0.0 else "down", polar])

	# CLAIM 9f — THE HORIZON ROLLS WITH THE AIRCRAFT, INCLUDING UPSIDE DOWN.
	#
	# The whole of round 6 passed with this broken, and it took a human rolling
	# inverted to find it: *"when i roll 180 degrees... the horizon dotted line and
	# the entire ladder seems to align itself IN REVERSE."* The offset was applied
	# down SCREEN Y instead of along the aircraft's own up axis, which is the same
	# answer at roll 0 and wrong at every other roll.
	#
	# Sweeping pitch at roll 0 could never have caught it. What catches it is
	# comparing the SAME pitch at different ROLLS, which is the same shape of claim
	# `separation_check` needed across frame sizes: one flight through the sweep
	# tells you nothing, and the comparison between two is the whole finding.
	print("")
	print("[hud] CLAIM 9f — THE OFFSET ROLLS WITH THE AIRCRAFT.")
	print("[hud] %10s %20s %14s" % ["roll deg", "offset px", "along the line?"])
	var pitch_rad: float = deg_to_rad(20.0)
	var upright: Vector2 = H.horizon_offset(pitch_rad, 0.0, focal)
	for roll_deg: float in [0.0, 45.0, 90.0, 180.0]:
		var roll_rad: float = deg_to_rad(roll_deg)
		var offset: Vector2 = H.horizon_offset(pitch_rad, roll_rad, focal)
		var line_dir := Vector2(cos(roll_rad), sin(roll_rad))
		# The offset must be PERPENDICULAR to the line. Any component along it
		# slides the line across itself and moves nothing, which is exactly how the
		# 90-degree case failed silently.
		var slide: float = absf(offset.dot(line_dir))
		print("[hud] %10.0f %20s %14.3f" % [roll_deg, str(offset.round()), slide])
		if slide > 0.01:
			_failures.append("at %.0f degrees of roll the horizon offset has a %.2f px component ALONG the line, which moves it nowhere — the offset must be perpendicular or the instrument stops responding to pitch"
					% [roll_deg, slide])
		if absf(offset.length() - upright.length()) > 0.01:
			_failures.append("rolling to %.0f degrees changed the horizon's DISTANCE from centre (%.2f against %.2f) — roll turns the line, it does not move it further away"
					% [roll_deg, offset.length(), upright.length()])
	# INVERTED IS THE CASE THE HUMAN FOUND. Upside down, the same pitch must put
	# the horizon on the OPPOSITE side of the screen, because the sky is now below.
	var inverted: Vector2 = H.horizon_offset(pitch_rad, PI, focal)
	print("[hud] upright %s, inverted %s" % [str(upright.round()), str(inverted.round())])
	if (upright + inverted).length() > 0.01:
		_failures.append("inverted, the horizon offset is %s where upright it is %s — rolling 180 degrees must NEGATE it, and drawing it the same way is a line that runs from the horizon at twice the rate you pitch"
				% [str(inverted), str(upright)])
	# And the screen's reach must follow the roll too: on its side the horizon runs
	# vertically and the screen is WIDER than it is tall.
	var wide: float = H.screen_extent(Vector2(1920.0, 1080.0), Vector2(1.0, 0.0))
	var tall: float = H.screen_extent(Vector2(1920.0, 1080.0), Vector2(0.0, 1.0))
	print("[hud] a 1920x1080 screen reaches %.0f px sideways and %.0f px vertically"
			% [wide, tall])
	if wide <= tall:
		_failures.append("the screen extent reads %.0f px sideways against %.0f px vertically on a landscape viewport — a height-only test calls a visible knife-edge horizon gone"
				% [wide, tall])

	# CLAIM 9e — THE TILT READOUT IS SIGNED, AND THE SIGN IS FORE/AFT ONLY.
	# The human's ask: *"if i pitch up (go backwards), the angle should be positive
	# and when i pitch down (go forward), it should be negative."*
	print("")
	print("[hud] CLAIM 9e — NOSE-DOWN READS NEGATIVE, NOSE-UP POSITIVE.")
	print("[hud] %16s %12s %12s" % ["attitude", "magnitude", "printed"])
	for pitch_deg: float in [-30.0, -10.0, 10.0, 30.0, 60.0]:
		# Nose DOWN is a negative rotation about body X in this convention, and
		# the nose is body -Z.
		var airframe := Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
		var axis: Vector3 = airframe.y
		var nose: Vector3 = -airframe.z
		var magnitude: float = H.tilt_degrees(axis)
		var printed: float = H.signed_tilt_degrees(axis, nose)
		var nose_down: bool = nose.y < 0.0
		print("[hud] %16s %12.1f %12.1f" % ["nose down" if nose_down else "nose up",
				magnitude, printed])
		if absf(absf(printed) - magnitude) > 0.001:
			_failures.append("the signed readout %.2f is not the magnitude %.2f with a sign on it — the number is a lift budget and signing it must not change what it measures"
					% [printed, magnitude])
		if nose_down and printed > 0.0:
			_failures.append("a nose-DOWN attitude printed %+.1f — the pilot asked for negative going forward"
					% printed)
		if not nose_down and printed < 0.0:
			_failures.append("a nose-UP attitude printed %+.1f — the pilot asked for positive going backwards"
					% printed)
	# Rolled level: the sign has nothing fore/aft to say, and must not invent one.
	var knife_edge := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	var rolled_printed: float = H.signed_tilt_degrees(knife_edge.y, -knife_edge.z)
	print("[hud] rolled 90 degrees with a level nose reads %+.1f" % rolled_printed)
	if rolled_printed < 0.0:
		_failures.append("a wings-vertical aircraft with its nose ON the horizon printed %+.1f — there is no fore/aft lean to be negative about"
				% rolled_printed)
	if H.signed_tilt_degrees(Vector3.UP, Vector3.ZERO) != 0.0:
		_failures.append("a level aircraft with no nose vector must read 0")

	# CLAIM 9b — THE COLOUR IS A RAMP, NOT A SWITCH. It was a single threshold at
	# 60 degrees and the human flew it and never saw it change: a switch fires
	# once, in an attitude you may never hold, with no warning that it is coming.
	print("")
	print("[hud] CLAIM 9b — THE TILT COLOUR RAMPS THE WHOLE WAY UP.")
	print("[hud] %10s %26s %12s" % ["tilt deg", "colour", "lift left"])
	var last: Color = H.tilt_tint(0.0)
	var moved: int = 0
	for tilt_deg: float in [0.0, 15.0, 30.0, 45.0, 60.0, 75.0]:
		var col: Color = H.tilt_tint(tilt_deg)
		print("[hud] %10.0f %26s %11.0f%%" % [tilt_deg, str(col).substr(0, 26),
				cos(deg_to_rad(tilt_deg)) * 100.0])
		if tilt_deg > 0.0 and col != last:
			moved += 1
		last = col
	print("[hud] the colour moved at %d of the 5 steps above level." % moved)
	if moved < 4:
		_failures.append("the tilt colour changed at only %d of 5 steps from level to 75 degrees — it is behaving like a threshold, and a threshold is what the pilot flew and never noticed"
				% moved)
	if H.tilt_tint(0.0) == H.tilt_tint(45.0):
		_failures.append("level and 45 degrees are the same colour, so the ramp says nothing at the angle where a quarter of the lift is already gone")

	# CLAIM 10 — THE PITCH LADDER IS THE REAL PROJECTION, not a spacing someone
	# liked the look of. A rung `d` degrees off level sits `tan(d) * f` from the
	# horizon, which is the SAME arithmetic that places the horizon itself — so
	# the two cannot drift apart. Even spacing is the tempting wrong answer and
	# it is wrong by 15% of a screen height by 60 degrees.
	print("")
	print("[hud] CLAIM 10 — THE PITCH LADDER USES THE REAL PROJECTION.")
	var f: float = H.focal_px(1080.0, 90.0)
	print("[hud] 1080p at 90 deg FOV: focal length %.1f px" % f)
	print("[hud] %8s %12s %14s" % ["degrees", "offset px", "even-spaced px"])
	var even: float = H.rung_offset(float(H.RUNG_STEP), f)
	var previous: float = 0.0
	var step: int = H.RUNG_STEP
	while step <= H.RUNG_MAX:
		var got: float = H.rung_offset(float(step), f)
		var want: float = tan(deg_to_rad(float(step))) * f
		print("[hud] %8d %12.1f %14.1f"
				% [step, got, even * float(step) / float(H.RUNG_STEP)])
		if absf(got - want) > 0.01:
			_failures.append("the %d degree rung is placed at %.2f px where the projection puts it at %.2f px"
					% [step, got, want])
		# Rungs must SPREAD with angle. Even spacing would keep this constant and
		# is exactly the shortcut this claim exists to refuse.
		if got - previous <= 0.0:
			_failures.append("the %d degree rung is not further from the horizon than the one below it (%.1f against %.1f) — the ladder must open out with angle, and a ladder at even pixel spacing is a ladder that lies about every angle except its first"
					% [step, got, previous])
		previous = got
		step += H.RUNG_STEP
	var spread_ratio: float = H.rung_offset(60.0, f) / maxf(H.rung_offset(10.0, f), 0.001)
	print("[hud] 60 deg sits %.2fx as far out as 10 deg (even spacing would be 6.00x)"
			% spread_ratio)
	if absf(spread_ratio - 6.0) < 0.5:
		_failures.append("the 60 degree rung sits %.2fx as far out as the 10 degree one, which is what EVEN spacing would give — the ladder is not being projected"
				% spread_ratio)
	if H.rung_offset(0.0, f) != 0.0:
		_failures.append("the zero-degree rung must sit exactly on the horizon")


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
