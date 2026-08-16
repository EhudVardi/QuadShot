class_name GameHud
extends CanvasLayer

## Minimal in-flight HUD (roadmap M1–M3): reticle, score/combo, health,
## wave status, kill feed, damage-direction flashes, death banner and
## end-of-run summary. Function over beauty; every control ignores the
## mouse so the tuning overlay stays fully clickable.

const KILL_FEED_MAX: int = 5
const KILL_FEED_SECONDS: float = 3.0

@onready var _score_label: Label = $ScoreLabel
@onready var _combo_label: Label = $ComboLabel
@onready var _wave_label: Label = $WaveLabel
@onready var _ammo_label: Label = $AmmoLabel
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _death_label: Label = $DeathLabel
@onready var _kill_feed: VBoxContainer = $KillFeed
@onready var _summary: PanelContainer = $Summary
@onready var _summary_label: Label = $Summary/SummaryLabel
@onready var _title: VBoxContainer = $Title
@onready var _title_bests: Label = $Title/TitleBests

## Thin edge bars for directional damage, built in code (side -> ColorRect).
var _edges: Dictionary = {}
var _lock_indicator: LockIndicator
var _gate_marker: GateMarker
var _reticle: Reticle
var _stick_display: StickDisplay
var _horizon: HorizonLine
## Weapon state, all at the aiming point (the human: *"most weapon gauges should
## be at the center area of the hud"*). Heat owns the right half; the two
## magazines split the left into quarters, since a count is a shorter story than
## a duty cycle and two of them have to share a side.
var _heat_gauge: WeaponGauge
var _flak_gauge: WeaponGauge
var _missile_gauge: WeaponGauge
var _pause_label: Label
var _motor_status: ComponentStatus
var _video_glitch: ColorRect
var _repair_label: Label


## Per-component capability pips (GAMEPLAY-DESIGN Iteration 7 / D4, extended over
## the component registry in Iteration 17 / E.q5): the legible half of the wound —
## the sticks tell you first. Green = healthy, red = failed; a damaged corner is
## exactly the one the drone now fights toward.
##
## IT DRAWS WHAT THE REGISTRY SAYS IS BUILT, and knows nothing about what an
## airframe is made of. E.q5's answer was *"extend the existing widget, reuse the
## existing channels, and build no new panel"*, and the user's ruling on the
## enemy side was that per-body damage visuals cost the vastness — so this is the
## player's HUD and nothing else.
##
## THE LAYOUT IS DERIVED FROM THE ROTOR MOUNTS, not authored, and that is a bug
## fix rather than a flourish. It was `for i in 4` against a hard-coded 2x2 offset
## table, so a six-rotor frame (E.q1) would have drawn four pips and silently
## dropped two rotors — the fifth instance of *a constant that was correct for one
## airframe is a bug on a size ladder*, sitting in the HUD after all. Projecting
## each rotor's own body-space position reproduces the quad's pixel layout exactly
## and gives a hexa a hexagon for free.
class ComponentStatus:
	extends Control

	## Everything the airframe is built from, in AirframeComponents.TABLE order.
	var parts: Array[AirframeComponents.Part] = []
	## STRUCTURAL INTEGRITY, 0..1, drawn as the hull itself.
	##
	## Fed by `set_health` rather than read off the `structure` row of `parts`,
	## and the difference matters: only `main.gd` and the composed sortie feed the
	## component list, while SIX callers feed the health. Taking hull from the
	## registry would have left the menu tower, the aim drill and the duel
	## harness with no hull readout the moment the old bar was retired.
	var hull: float = 1.0

	## Sharp green->yellow->red ramp: a motor at 0.6 must read as clearly hurt,
	## not near-green (the old lerp's flaw).
	static func ramp(h: float) -> Color:
		var green := Color(0.3, 1.0, 0.4)
		var yellow := Color(1.0, 0.85, 0.2)
		var red := Color(1.0, 0.2, 0.15)
		if h >= 0.6:
			return yellow.lerp(green, (h - 0.6) / 0.4)
		return red.lerp(yellow, h / 0.6)

	## Radius the WIDEST ROTOR projects to. Everything else on the airframe is
	## placed by the same scale, so the picture keeps its proportions.
	const RING: float = 46.0
	const ROTOR_R: float = 15.0
	const PLATE := Vector2(168.0, 150.0)
	## The hull silhouette's half-extent, and the clearance every other component
	## keeps from it.
	const HULL_HALF := Vector2(15.0, 21.0)
	const HULL_CLEAR: float = 13.0
	## Anything this far from the hub is pulled back in. Only reachable by a lens
	## mounted further forward than the rotors, which is the Condor and the Roc.
	const EDGE: float = 62.0

	func _draw() -> void:
		# BOTTOM CENTRE, between the two stick boxes (the human's placement). The
		# sticks sit at +/- 230 px with a 38 px half-width, so their inner edges
		# are at +/- 192 and this 168-wide plate drops into the gap the old
		# hull/heat/ammo bars used to fill.
		var centre := Vector2(size.x * 0.5, size.y - PLATE.y * 0.5 - 26.0)
		draw_string(get_theme_default_font(),
				centre + Vector2(-PLATE.x * 0.5, -PLATE.y * 0.5 - 6.0),
				"AIRFRAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(1, 1, 1, 0.55))
		# THE HULL IS DRAWN EVEN WITH NO COMPONENT LIST, because six callers feed
		# the health and only two feed the parts. A scene that never calls
		# `set_components` still gets its integrity readout, which is what the
		# retired ProgressBar used to guarantee everywhere.
		if parts.is_empty():
			_hull_body(centre)
			return

		var points: Dictionary = layout(parts, centre)
		var rotors: Array[AirframeComponents.Part] = []
		for part: AirframeComponents.Part in parts:
			if part.kind == &"rotor":
				rotors.append(part)

		# THE AIRFRAME ITSELF, drawn before anything mounted on it: arms out to
		# every rotor, then the hull over the top. This is the half the human
		# asked for that the pip block never had — *"a projection of the craft
		# from top to bottom"* — and it is what makes a lit gauge mean "that
		# corner, over there" rather than "the third one in the list".
		for part: AirframeComponents.Part in rotors:
			draw_line(centre, points[part.id], Color(0.55, 0.62, 0.7, 0.5), 3.0)
		_hull_body(centre)

		# `layout` owns WHERE, this owns WHAT — so the check measures the same
		# positions the pilot sees. Splitting the two is how the gyro came to be
		# drawn clear of the hull while the check still read it dead centre.
		for part: AirframeComponents.Part in parts:
			if not points.has(part.id):
				continue
			var at: Vector2 = points[part.id]
			if part.kind == &"rotor":
				_rotor(at, part)
			elif part.kind == &"vtx":
				_transmitter(at, part)
			else:
				# Any OTHER built component. Nothing reaches this today; it is
				# what a new failure mode gets for free the day it flips `built`.
				_block(at, part)

	## WHERE EVERY PART GOES, keyed by `Part.id`.
	##
	## STATIC AND SEPARATE FROM `_draw` SO IT CAN BE MEASURED — a layout buried in
	## a draw call can only be checked by looking at it.
	##
	## NORMALISED ON THE ROTOR SPAN, not on the widest part of the whole airframe.
	## The rotors are what you read at a glance, so they keep the ring at a fixed
	## size on every frame and anything reaching past them is clamped to the plate.
	##
	## Scaling to fit EVERYTHING is the obvious alternative and it makes the ring
	## frame-dependent: measured, the Condor's and the Roc's would shrink by 1.7%,
	## because their lenses sit fractionally beyond the rotor diagonal (z -0.74
	## against 0.727). Small today and not the point — the point is that the
	## picture would change shape per frame at all, and a longer-nosed frame would
	## move it much further. `hud_check` claim 5 holds the ring identical.
	##
	## Body -Z is the nose and screen -Y is up, so z maps straight onto y and this
	## is the airframe seen from above, nose up.
	static func layout(parts: Array[AirframeComponents.Part],
			centre: Vector2) -> Dictionary:
		var out: Dictionary = {}
		# THE RADIUS, NOT THE WIDEST AXIS. Taking `max(|x|, |z|)` measures a
		# SQUARE and the plate draws a CIRCLE, so a quad-X — whose rotors sit on
		# the diagonal — pushed its corners out to RING x root 2 while a hexa's
		# ring rotors landed at exactly RING. 65 px against 46 px for the same
		# widget, caught by `hud_check`'s fifth claim on its first run.
		var reach: float = 0.0
		for part: AirframeComponents.Part in parts:
			if part.kind == &"rotor":
				reach = maxf(reach,
						Vector2(part.position.x, part.position.z).length())
		if reach <= 0.0:
			return out
		for part: AirframeComponents.Part in parts:
			# The structure pool has no location by design (E5): it is the whole
			# airframe, and it is drawn AS the airframe rather than placed on it.
			if not part.located or not part.built:
				continue
			var offset := Vector2(part.position.x, part.position.z) / reach * RING
			offset = Vector2(clampf(offset.x, -EDGE, EDGE),
					clampf(offset.y, -EDGE, EDGE))
			if part.kind != &"rotor":
				offset = _clear_hull(offset)
			out[part.id] = centre + offset

		# THE ROWS THAT CANNOT FAIL YET ARE NOT DRAWN AT ALL, and that is a
		# retreat from the previous version rather than an oversight.
		#
		# They were marked with a dim ring and a three-letter label at their real
		# mounts, spread sideways to stop them stacking on the centreline. Flown,
		# the labels collided with the rotor discs — GUN and AMMO reach across the
		# forward and aft arms — and the plate read as clutter twice running.
		#
		# Two things settle it. Half of E3's registry cannot fail, so every one of
		# those marks carried a POSITION and no reading, which is the weakest
		# thing a gauge can be. And the human has since placed the two that are
		# weapons: *"most weapon gauges should be at the center area of the hud"* —
		# so the gun and the magazine belong on the rings at the aiming point, not
		# on the airframe. Each of these comes back as a real gauge on the day it
		# can actually be lost.
		#
		# Props are excluded by the same rule for a second reason: a prop sits at
		# its rotor's exact mount, and when props become damageable they belong AS
		# a ring on the rotor rather than as a mark beside it.
		return out


	## PUSH A MOUNT CLEAR OF THE HULL SILHOUETTE.
	##
	## Once hull became the body itself, anything mounted ON the body was drawn
	## inside a filled box — and the lens is the case that bites, because
	## `fpv_offset` puts it a whisker forward of the hull's own top edge (-21.7 px
	## against a half-height of 21) so its glyph and its reading landed on the
	## silhouette. Reported from the cockpit: *"there's overlap with the drawing,
	## there's some text behind the body damage meters."*
	##
	## Pushed along the axis it already leans on, so the ORDER survives: the lens
	## and the gun stay forward of the hull, the pack and the magazine stay aft.
	## A part sitting exactly on the hub (the gyro, at 0,0,0) has no direction to
	## be pushed along and is left where it is — `_draw` spreads the unbuilt rows
	## sideways anyway, which clears it.
	static func _clear_hull(offset: Vector2) -> Vector2:
		var limit := HULL_HALF + Vector2(HULL_CLEAR, HULL_CLEAR)
		if absf(offset.x) > limit.x or absf(offset.y) > limit.y:
			return offset
		if absf(offset.y) >= absf(offset.x) and absf(offset.y) > 0.001:
			return Vector2(offset.x, signf(offset.y) * limit.y)
		if absf(offset.x) > 0.001:
			return Vector2(signf(offset.x) * limit.x, offset.y)
		return offset

	## THE HULL, DRAWN AS THE AIRFRAME'S OWN BODY — which is the creative bit the
	## human left open, and it falls out of what the structure pool already IS.
	##
	## E5 keeps `hull` as a **structural integrity pool** beside the components
	## rather than as one of them, and the registry marks it `located = false`
	## because it has no place on the airframe: it IS the airframe. So it gets no
	## pip and no bar — the hull silhouette in the middle of the plate drains and
	## reddens, and the number sits inside it. Losing integrity visibly empties the
	## picture of the aircraft, which is the one wound that should read that way.
	##
	## It is the only gauge here fed by a value rather than by the registry; see
	## `hull` for why.
	func _hull_body(centre: Vector2) -> void:
		var h: float = clampf(hull, 0.0, 1.0)
		var tint: Color = ramp(h)
		var half := HULL_HALF
		var box := Rect2(centre - half, half * 2.0)
		draw_rect(box, Color(0.10, 0.12, 0.16, 0.9))
		draw_rect(Rect2(box.position + Vector2(0.0, box.size.y * (1.0 - h)),
				Vector2(box.size.x, box.size.y * h)),
				Color(tint.r, tint.g, tint.b, 0.5))
		draw_rect(box, tint, false, 1.5)
		# The nose, so "up is forward" is stated by the picture and not only by
		# the fact that the lens happens to be drawn at the top.
		draw_line(centre + Vector2(0.0, -half.y), centre + Vector2(0.0, -half.y - 7.0),
				Color(0.55, 0.62, 0.7, 0.55), 2.0)
		_value(centre, h)


	## A rotor: a disc whose HUE is its state, with the reading inside it. The
	## human's shape, and it beats a square pip for the reason they gave — a rotor
	## is a disc on the real aircraft, so the picture reads as the machine.
	func _rotor(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		draw_circle(at, ROTOR_R, Color(0.0, 0.0, 0.0, 0.6))
		# The disc fills as it dies rather than only reddening: a ring that is
		# both emptier AND redder survives being glanced at.
		draw_circle(at, maxf(ROTOR_R * h, 2.0), Color(tint.r, tint.g, tint.b, 0.5))
		draw_arc(at, ROTOR_R, 0.0, TAU, 28, tint, 2.0)
		_plating(at, ROTOR_R + 3.0, part)
		_value(at, h)

	## The transmitter, as a thing that BROADCASTS: a hub with two arcs opening
	## forward. Hue is its state like everything else, so a failing feed reads the
	## same way a failing rotor does - which is D1's whole thesis, and is why the
	## jam effect reuses the damage overlay.
	func _transmitter(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		draw_circle(at, 3.5, tint)
		# The arcs THIN OUT as the transmitter dies, so a wrecked feed is a stub
		# rather than a full broadcast in an alarming colour.
		for i: int in 2:
			var radius: float = 7.0 + float(i) * 5.0
			draw_arc(at, radius, PI * 1.15, PI * 1.85, 14, tint,
					maxf(2.0 * h, 0.6))
		_plating(at, 15.0, part)
		# ABOVE THE SYMBOL, CENTRED, not beside it — the human's report: *"the vtx
		# text and number is to the right of its symbol and it overlaps the right
		# front rotor indication."* They are exactly right and the geometry says
		# why: the lens mounts forward of centre, which on a nose-up plate puts the
		# transmitter about 22 px above the hub, while the front rotors sit at
		# +/-32 px across with a 15 px radius — so a label running RIGHT from the
		# symbol drives straight into the front-right rotor disc. Straight up it
		# clears both, because the two front rotors leave a gap on the centreline.
		_label_above(at, 20.0, "%s %d" % [label_for(part.kind), roundi(h * 100.0)],
				tint)

	## Any other BUILT component: a small block at its mount with its label and
	## reading beside it. Nothing reaches this today, and it is what a new failure
	## mode gets for free the day it flips `built`.
	func _block(at: Vector2, part: AirframeComponents.Part) -> void:
		var h: float = clampf(part.health, 0.0, 1.0)
		var tint: Color = ramp(h)
		var box := Rect2(at - Vector2(6.0, 6.0), Vector2(12.0, 12.0))
		draw_rect(box, Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(box.position + Vector2(0.0, box.size.y * (1.0 - h)),
				Vector2(box.size.x, box.size.y * h)), tint)
		draw_rect(box, tint, false, 1.0)
		_plating(at, 11.0, part)
		draw_string(get_theme_default_font(), at + Vector2(10.0, 4.0),
				"%s %d" % [label_for(part.kind), roundi(h * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)

	## ARMOUR, SHOWN AS A RING AROUND WHAT IT PROTECTS (E4.2). Plating that
	## protects a NAMED thing is the whole argument for the mechanic — *"they got
	## my power bus through the plating"* — and a number in a config cannot say
	## that. Drawn only where there IS plating, so an unarmoured frame is not
	## covered in empty rings.
	func _plating(at: Vector2, radius: float, part: AirframeComponents.Part) -> void:
		if part.armor <= 0.0:
			return
		draw_arc(at, radius, 0.0, TAU, 24, Color(0.62, 0.78, 1.0, 0.75), 2.0)

	## A component's label and reading, centred ABOVE its symbol. Centring is done
	## from the measured string width rather than by eye, so a longer label than
	## "VTX 100" still sits on the centreline instead of drifting into a rotor.
	func _label_above(at: Vector2, gap: float, text: String, tint: Color) -> void:
		var font: Font = get_theme_default_font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10).x
		draw_string(font, at + Vector2(-width * 0.5, -gap), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)


	## The reading, as characters, centred in the shape it belongs to.
	func _value(at: Vector2, health: float) -> void:
		var font: Font = get_theme_default_font()
		var text: String = "%d" % roundi(clampf(health, 0.0, 1.0) * 100.0)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10).x
		draw_string(font, at + Vector2(-width * 0.5, 3.5), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.92))

	## Four characters or fewer: this sits in the corner of a flying pilot's eye.
	static func label_for(kind: StringName) -> String:
		match kind:
			&"vtx": return "VTX"
			&"power": return "PWR"
			&"gyro": return "FCS"
			&"weapon_mount": return "GUN"
			&"magazine": return "AMMO"
			&"prop": return "PROP"
		return String(kind).to_upper()


## Missile-lock diamond, drawn at the target's screen position: yellow and
## wide while acquiring; when locked it becomes an unmistakable pulsing red
## double diamond with a LOCK tag, and the missile director (auto-launch)
## winds an orange arc around it while its hold timer runs.
class LockIndicator:
	extends Control

	var target_visible: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var progress: float = 0.0
	var locked: bool = false
	var auto_progress: float = 0.0

	func _draw() -> void:
		if not target_visible:
			return
		if not locked:
			_diamond(lerpf(30.0, 14.0, progress), Color(1, 0.85, 0.2, 0.8), 2.0)
			return
		var pulse: float = 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.001 * TAU * 3.0)
		var radius: float = 14.0 * pulse
		var color := Color(1, 0.2, 0.15, 0.95)
		_diamond(radius, color, 2.5)
		_diamond(radius + 6.0, Color(1, 0.2, 0.15, 0.5), 1.5)
		draw_string(get_theme_default_font(),
				target_position + Vector2(-16.0, radius + 22.0), "LOCK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if auto_progress > 0.0:
			draw_arc(target_position, radius + 12.0, -PI / 2.0,
					-PI / 2.0 + TAU * auto_progress, 32,
					Color(1, 0.55, 0.1, 0.9), 3.0)

	func _diamond(radius: float, color: Color, width: float) -> void:
		var points := PackedVector2Array([
			target_position + Vector2(0, -radius),
			target_position + Vector2(radius, 0),
			target_position + Vector2(0, radius),
			target_position + Vector2(-radius, 0),
			target_position + Vector2(0, -radius),
		])
		draw_polyline(points, color, width)


## FCS reticle (GAMEPLAY-DESIGN Iteration 7 aiming pass). Three selectable
## styles, all built on the same truth — the blaster's real impact point
## (muzzle + inherited drone velocity + drop), so the pilot aims where the bolts
## actually go, not where the nose points — plus the missile lock cone. Player
## fire is yellow (emissive palette); the lock cone is navigation blue. No
## auto-lead: moving targets are led by hand (lead-compute is future FCS gear).
class Reticle:
	extends Control

	var active: bool = false
	var center: Vector2 = Vector2.ZERO      # boresight (camera axis)
	var pipper: Vector2 = Vector2.ZERO      # bolt impact point at target range
	var arc: PackedVector2Array = PackedVector2Array()
	var ticks: Array = []                   # [{"pos": Vector2, "label": String}]
	var lock_radius: float = 0.0            # missile ACQUIRE cone
	var hold_radius: float = 0.0            # wider cone where a lock is MAINTAINED
	var lockable: bool = false

	const GUN := Color(1.0, 0.9, 0.3)
	const NAV := Color(0.35, 0.75, 1.0)
	## Minimum vertical gap between two range labels, in pixels. An 11 px font
	## needs about this much before two numbers start touching.
	const LABEL_PITCH: float = 15.0

	func _draw() -> void:
		# Missile lock zone (always shown): the ACQUIRE ring — start a lock with
		# a bandit inside it — and the wider HOLD ring, out to which an existing
		# lock is maintained. Both grow with lock upgrades (lock_cone_mult), so
		# the pilot flies to keep the target inside the circle.
		if hold_radius > 4.0:
			_dashed_ring(center, hold_radius, Color(NAV, 0.22), 40)
		if lock_radius > 4.0:
			_dashed_ring(center, lock_radius,
					Color(NAV, 0.9 if lockable else 0.45), 40)
		if not active:
			return
		# CCIP gun reticle: boresight, the bolt fall-line + range ticks, and the
		# impact pipper where the bolts pass at the target's range.
		_cross(center, 4.0, Color(GUN, 0.5))
		if arc.size() >= 2:
			draw_polyline(arc, Color(GUN, 0.55), 1.5)
		# EVERY TICK IS DRAWN, BUT NOT EVERY LABEL. The fall-line compresses with
		# range, so the far ticks bunch together and their range numbers were
		# drawn on top of one another — reported from the cockpit as *"the
		# targeting indicator looks weird, like two texts overlap."*
		#
		# The MARKS stay at full density because they are the scale; only the text
		# is thinned, and dropping a label never moves the tick it belonged to.
		var last_label_y: float = -INF
		for tick: Dictionary in ticks:
			var p: Vector2 = tick["pos"]
			draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), Color(GUN, 0.7), 1.5)
			if absf(p.y - last_label_y) < LABEL_PITCH:
				continue
			last_label_y = p.y
			draw_string(get_theme_default_font(), p + Vector2(9, 4),
					tick["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GUN, 0.7))
		draw_arc(pipper, 7.0, 0.0, TAU, 24, GUN, 2.0)
		draw_rect(Rect2(pipper - Vector2(1, 1), Vector2(2, 2)), GUN)

	func _cross(at: Vector2, r: float, col: Color) -> void:
		draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), col, 1.0)
		draw_line(at + Vector2(0, -r), at + Vector2(0, r), col, 1.0)

	func _dashed_ring(at: Vector2, radius: float, col: Color, segments: int) -> void:
		for i: int in segments:
			if i % 2 == 1:
				continue
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			draw_line(at + Vector2(cos(a0), sin(a0)) * radius,
					at + Vector2(cos(a1), sin(a1)) * radius, col, 1.5)


## A WEAPON'S STATE AS A HALF RING AROUND THE AIMING POINT (the human's design,
## 2026-08-15): *"redo the blaster power gauge into some half ring at the right
## from the center, the aiming point at. at idle is gray half noticed, when used,
## flash a bit, fill it in some color like yellow from bottom as 0% up to the full
## up as 100%."*
##
## **IT IS DELIBERATELY GENERIC, because they said what it is for**: *"this
## concept can be used to show weapon state gauge like power/heat/ammunition or
## some another attribute of a weapon equipment."* So it carries a fraction, a
## tint, a short label and a side — nothing about heat — and a second weapon's
## magazine is another instance rather than another widget.
##
## WHY IT BELONGS AT THE RETICLE AND NOT AT THE BOTTOM OF THE SCREEN: it is the
## only readout you consult WHILE aiming. The old heat bar sat 58 px off the
## bottom edge, which is a glance away from the target at exactly the moment you
## cannot afford one.
##
## It fills from the BOTTOM UP, so "full" is up and "empty" is down — the reading
## a pilot already has for a fuel gauge, a magazine and a battery.
class WeaponGauge:
	extends Control

	## Far enough out to clear the reticle's own rings and the lock diamond.
	const RADIUS: float = 92.0
	const THICKNESS: float = 7.0
	## How fast a use-flash fades, in fractions per second.
	const FLASH_DECAY: float = 3.2

	## 0..1. What the gauge is showing.
	var fraction: float = 0.0
	## Fill colour. Yellow for the blaster because the palette says so
	## (CLAUDE.md): yellow = your fire.
	var tint: Color = Color(1.0, 0.85, 0.25)
	## Locked out / spent — pulses red instead of filling.
	var alarm: bool = false
	## +1 draws on the right of the aiming point, -1 on the left, so a second
	## weapon can sit opposite without either of them moving.
	var side: float = 1.0
	## HOW MUCH OF THE CIRCLE THIS GAUGE OWNS, in radians — PI for a half ring,
	## PI/2 for a quarter (the human: *"ammo counters can also be half ring, or
	## even quarter"*). Two quarters stack on one side where a half would not fit.
	var span: float = PI
	## Where the fill STARTS, in radians, measured the way `draw_arc` measures:
	## 0 is +X and +PI/2 is straight down, because screen Y grows downward. The
	## fill runs from here toward the top of the circle.
	var start_angle: float = PI * 0.5
	## Rings at different radii nest instead of colliding, so a frame carrying
	## three weapons reads as three concentric arcs.
	var radius: float = RADIUS
	var label: String = ""
	## Shown beside the label when >= 0: the count behind the fraction, because a
	## magazine is a NUMBER you spend deliberately and a bar cannot say "2 left".
	var count: int = -1

	var _flash: float = 0.0
	var _previous: float = 0.0

	func _process(delta: float) -> void:
		if _flash <= 0.0:
			return
		_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
		queue_redraw()

	## THE FLASH IS DERIVED FROM THE VALUE RISING, not from a "fired" signal.
	## Nothing has to tell this widget that the trigger was pulled: heat going up
	## IS the trigger being pulled, and a magazine going down is the same event
	## for a gauge that counts the other way. One less wire to keep in sync, and
	## it works for any attribute that moves when the weapon is used.
	func show_value(value: float, alarm_state: bool) -> void:
		var next: float = clampf(value, 0.0, 1.0)
		if absf(next - _previous) > 0.0005:
			_flash = 1.0
		_previous = next
		fraction = next
		alarm = alarm_state
		queue_redraw()

	func _draw() -> void:
		var at := size * 0.5
		# The fill always runs from `start_angle` TOWARD THE TOP of the circle,
		# which is what makes "full is up" true for a half on the right, a half on
		# the left and any quarter of either.
		var start: float = start_angle
		var finish: float = start_angle - span * signf(side if side != 0.0 else 1.0)
		# IDLE IS BARELY THERE. A gauge you are not currently managing must not
		# compete with the target, and the flash is what brings it back.
		var track: float = 0.10 + 0.30 * _flash
		draw_arc(at, radius, start, finish, 40, Color(0.75, 0.78, 0.85, track),
				THICKNESS)
		var fill: Color = tint
		if alarm:
			# A pulsing red ring is "the gun is dead, stop pulling" and must be
			# tellable from "you have a burst left" WITHOUT reading a number.
			var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.018)
			fill = Color(1.0, 0.22, 0.16).lerp(Color(1.0, 0.75, 0.3), pulse)
		if fraction > 0.001:
			draw_arc(at, radius, start,
					start + (finish - start) * fraction, 40,
					Color(fill.r, fill.g, fill.b, 0.55 + 0.45 * _flash), THICKNESS)
		# End caps: where 0% and 100% are, so a part-filled ring is readable
		# without having to remember which way it grows.
		_cap(at, start, Color(1, 1, 1, 0.18 + 0.25 * _flash))
		_cap(at, finish, Color(1, 1, 1, 0.18 + 0.25 * _flash))
		if label == "":
			return
		# THE TEXT SITS OFF THE MIDDLE OF THIS GAUGE'S OWN ARC, not at the
		# horizontal centreline. Two quarters on the same side share that
		# centreline, and anchoring both there is precisely how two readouts end
		# up drawn on top of each other.
		var font: Font = get_theme_default_font()
		var middle: float = start + (finish - start) * 0.5
		var text: String = label if count < 0 else "%s %d" % [label, count]
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 10).x
		var text_at := at + Vector2(cos(middle), sin(middle)) * (radius + 11.0)
		text_at.y += 4.0
		if cos(middle) < 0.0:
			text_at.x -= width
		draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(fill.r, fill.g, fill.b, 0.35 + 0.5 * _flash))

	func _cap(at: Vector2, angle: float, col: Color) -> void:
		var unit := Vector2(cos(angle), sin(angle))
		draw_line(at + unit * (radius - THICKNESS * 0.7),
				at + unit * (radius + THICKNESS * 0.7), col, 1.5)


## THE HORIZON, AND WHICH WAY IS UP (the human's ask, 2026-08-15): *"i also want
## a horizon line that will stay parallel to the horizon, and it would be pointing
## directly up, perpendicular to the frame so it points up so on the fpv view it
## would show at the top when the camera angle is high."*
##
## Two things in one instrument, and they answer different questions:
##
##  - **The LINE is the world's horizon**, drawn where it really is. It stays
##    parallel to the true horizon and slides DOWN the screen as you pitch up,
##    which is the sentence the ask ends on: at a high camera angle it sits near
##    the top edge, because that is where the ground actually is.
##  - **The TICK is world UP**, perpendicular to the line and pointing at the sky.
##    On an aircraft that can be inverted, "which of the two sides is the sky" is
##    a real question and a bare line cannot answer it.
##
## IT READS THE LIVE CAMERA rather than being fed by anyone, because it must be
## true of whatever the pilot is actually looking through — the FPV lens, the
## chase camera, or the war room. `get_viewport().get_camera_3d()` is the one
## source that cannot disagree with the picture.
##
## THE PROJECTION IS THE REAL ONE, not an eyeballed offset. `f` is the focal
## length in pixels for this viewport and this FOV, so the line lands where the
## horizon lands. Godot's `fov` is the VERTICAL angle under the default
## `keep_height` aspect mode, which is what makes `size.y` the right denominator —
## an implementation detail worth writing down, because using the width here is a
## bug that only shows on a non-16:9 window.
class HorizonLine:
	extends Control

	## Half the horizon's width, as a FRACTION of the viewport width — so it spans
	## about 80% of the screen on any window. A fraction rather than a pixel
	## count for the reason this project has learned five times over: a constant
	## that is right at one size is wrong at another.
	const REACH_FRACTION: float = 0.40
	## Dash geometry, in pixels. Long enough to read as one line at a glance,
	## broken enough to let the world through — a solid line this wide fights the
	## scene, which is why Liftoff's is dashed and why this one is too.
	const DASH: float = 14.0
	const DASH_GAP: float = 10.0
	## Clear space either side of the aiming point.
	const GAP: float = 16.0
	## Pitch ladder: a labelled rung every RUNG_STEP degrees out to RUNG_MAX, each
	## drawn at this fraction of the horizon's own width so the horizon stays the
	## dominant line.
	const RUNG_STEP: int = 10
	const RUNG_MAX: int = 60
	const RUNG_FRACTION: float = 0.34
	## A FINITE CAP ON THE HORIZON'S OFFSET, in pixels — not a clamp anyone can
	## read as a horizon. `tan` runs away near +/-90 degrees and would hand the
	## renderer an infinity; 40000 px is roughly forty screens away, so the line
	## is honestly gone while the arithmetic stays finite.
	const FAR: float = 40000.0
	## How close to the screen edge the world horizon may sit before the OFF-SCREEN
	## marker appears beside it. Small on purpose: the line itself is never moved.
	const EDGE_MARGIN: float = 14.0
	## HOW FAR IN FROM THE SCREEN EDGE THE AIRFRAME BRACKET PEGS.
	##
	## ONLY THE BRACKET PEGS NOW. It used to clamp the world horizon too, and the
	## two had to share this constant or the gap between them stopped being the
	## tilt — but the horizon is no longer moved at all, so the invariant is now
	## satisfied by construction rather than by a shared number. The bracket keeps
	## pegging because it is not a claim about the world: in FPV the lens is bolted
	## to the frame, so the airframe's own level plane sits at `tan(fpv_uptilt_deg)`
	## below the boresight FOREVER — 559 px on a 94-degree lens, which is off the
	## bottom of a 1080 screen in every attitude. Unpegged it would never be
	## visible at all, and the NUMBER riding it is the primary reading.
	##
	## 210 rather than something smaller because of what it must clear at the
	## BOTTOM: the AIRFRAME plate is 150 px tall sitting 26 px off the edge, so its
	## top is 176 px up. A 90 px margin pegged the line at y 990 on a 1080 screen
	## and drew it straight through the middle of the plate.
	const PEG_MARGIN: float = 210.0
	## How far the airframe's level BRACKET reaches past the aiming-point gap.
	## Short on purpose: it is a fixed mark, not a horizon, and drawing it long
	## made it read as a second horizon that had stopped working.
	const BRACKET: float = 26.0
	## Past this much tilt off vertical the arrow warns: `cos(60 deg)` is 0.5, so
	## half the rotors' push has stopped fighting gravity.
	const TILT_WARN_DEG: float = 60.0

	## WHICH WAY THE ROTORS ARE PUSHING, in world space — the drone's body +Y.
	##
	## Fed in rather than looked up, because the HUD has no idea which node is the
	## aircraft and several scenes fly one. Zero hides the arrow, which is what a
	## scene that never sets it gets.
	var thrust_axis: Vector3 = Vector3.ZERO
	## The airframe's NOSE in world space, and the only reason it is here is to
	## give the tilt readout a sign. Optional: a scene that never feeds it gets
	## the unsigned magnitude, exactly as before.
	var nose_axis: Vector3 = Vector3.ZERO
	## The pitch ladder, on the human's call — *"we can always add and set a
	## toggle. i want realism."* Bound to `hud_ladder_toggle`, default on.
	var ladder: bool = true

	## HOW FAR OFF THE HORIZON A GIVEN PITCH ANGLE SITS, in pixels.
	##
	## The one piece of arithmetic the whole instrument rests on, and it is the
	## real projection rather than a spacing someone liked the look of: a point
	## `degrees` above the horizon subtends `tan(degrees)` at the lens, so it
	## lands `tan(degrees) * f` off the horizon line, where `f` is the focal
	## length in pixels. Which is exactly how the horizon's own offset from screen
	## centre is computed, so the ladder and the horizon cannot drift apart.
	static func rung_offset(degrees: float, focal_px: float) -> float:
		return tan(deg_to_rad(degrees)) * focal_px


	## The focal length in pixels for a viewport of this height at this FOV.
	##
	## Godot's `fov` is the VERTICAL angle under the default `keep_height` aspect
	## mode, which is what makes height the right denominator — using the width
	## here is a bug that only shows on a non-16:9 window.
	static func focal_px(viewport_height: float, fov_degrees: float) -> float:
		return (viewport_height * 0.5) / tan(deg_to_rad(fov_degrees) * 0.5)


	## WHERE THE SKY IS ON SCREEN, for a given camera roll.
	##
	## STATIC SO IT CAN BE MEASURED, and it is static because the version that
	## was not got the sign wrong. World up is (0,1,0); in camera space that is
	## `(basis.x.y, basis.y.y, basis.z.y)`, and screen Y grows downward, so its
	## screen direction is `(basis.x.y, -basis.y.y)` — which with
	## `roll = atan2(basis.x.y, basis.y.y)` is exactly `(sin, -cos)`. The first
	## version wrote `(-sin, -cos)` and pointed the tick the wrong way under roll.
	## LEVEL FLIGHT LOOKED PERFECT EITHER WAY, which is how it survived a
	## rendered boot, and is why `hud_check` now asserts it at a roll.
	static func world_up_screen(roll: float) -> Vector2:
		return Vector2(sin(roll), -cos(roll))


	## THE PITCH AND ROLL OF THE CAMERA AGAINST ANY "UP", as (pitch, roll) radians.
	##
	## **This is the whole instrument in one function, and that is the point.** A
	## horizon is the plane perpendicular to some up-vector, projected. Feed it
	## WORLD up and you get the real horizon; feed it the airframe's THRUST axis
	## and you get the plane the rotors push against — the aircraft's own level,
	## which in FPV sits off the boresight by exactly the camera's uptilt.
	##
	## Two lines out of one piece of arithmetic, and that is what makes "align
	## them" exact rather than approximate: when the aircraft is level the two
	## up-vectors ARE the same vector, so the lines coincide by construction and
	## never by tuning.
	##
	## Both fall out of the reference up expressed in CAMERA space, `u = B⁻¹·U`:
	## its z says how far the camera's forward is tipped out of that plane, and
	## its x/y say where that up sits on screen.
	static func reference_pitch_roll(camera_basis: Basis,
			up_world: Vector3) -> Vector2:
		if up_world.length_squared() < 0.000001:
			return Vector2.ZERO
		var u: Vector3 = camera_basis.inverse() * up_world.normalized()
		return Vector2(asin(clampf(-u.z, -1.0, 1.0)), atan2(u.x, u.y))


	## THE AIRFRAME LINE'S COLOUR, AS A CONTINUOUS RAMP RATHER THAN A THRESHOLD.
	##
	## It was a single switch at 60 degrees and the human flew it and reported
	## *"didnt notice and color change"* — which is what a threshold gets you: a
	## change that happens once, in an attitude you may never hold, with nothing
	## in between to tell you it is coming.
	##
	## A ramp is a reading at every angle instead. It is keyed to the physics
	## rather than to taste: `cos(tilt)` is the share of thrust still fighting
	## gravity, so green through amber to red tracks lift being spent — amber at
	## 45 degrees is 71% of your lift left, red at 60 is half.
	## WHITE AT LEVEL, NOT GREEN, AND FOR TWO REASONS BOTH FOUND BY FLYING IT.
	##
	## The human could not see this line at all, and the screenshot said why:
	## *"hehe the green you see is the landing pad :)"* — dev_map's ground is a
	## neon green checker, so a green line on it is invisible in exactly the
	## attitude where you are closest to the ground and need it most.
	##
	## And it was against the project's own palette anyway. CLAIM.md assigns
	## **green = pads**; cyan/blue is navigation, red threat, orange score, amber
	## pylons, yellow your fire. White was the one unclaimed value, and it is also
	## what a real attitude indicator uses for the aircraft symbol.
	static func tilt_tint(tilt: float) -> Color:
		var level := Color(1.0, 1.0, 1.0, 0.95)
		var amber := Color(1.0, 0.8, 0.25, 0.95)
		var red := Color(1.0, 0.35, 0.2, 0.95)
		if tilt <= 0.0:
			return level
		if tilt < TILT_WARN_DEG * 0.75:
			return level.lerp(amber, tilt / (TILT_WARN_DEG * 0.75))
		return amber.lerp(red, clampf((tilt - TILT_WARN_DEG * 0.75)
				/ (TILT_WARN_DEG * 0.75), 0.0, 1.0))


	## HOW FAR THE ROTORS ARE PUSHING OFF VERTICAL, in degrees. 0 is level and
	## every degree past that is lift traded for speed: only `cos(tilt)` of the
	## thrust is still fighting gravity.
	static func tilt_degrees(axis: Vector3) -> float:
		if axis.length_squared() < 0.000001:
			return 0.0
		return rad_to_deg(acos(clampf(axis.normalized().y, -1.0, 1.0)))


	## THE SAME TILT, SIGNED THE WAY A PILOT THINKS ABOUT IT — negative nose-down
	## (going forward), positive nose-up (going backwards). The human's ask, and
	## it is a design choice rather than a convention: this readout is not a
	## real-HUD element at all, it is ours, so nothing outside says what its sign
	## should be.
	##
	## THE MAGNITUDE IS THE PHYSICS AND THE SIGN IS THE DIRECTION. `tilt_degrees`
	## is an `acos` and can never be negative: it answers "how much of your thrust
	## has stopped fighting gravity", which is `cos(tilt)` and is the same whether
	## you lean forward or back. So the sign has to come from somewhere else, and
	## the only honest source is which way the airframe is leaning — the thrust
	## axis tipping TOWARD the nose is nose-down.
	##
	## **It is a fore/aft sign on a quantity that is not purely fore/aft**, and
	## that is worth knowing rather than hiding: a wings-level aircraft rolled 90
	## degrees is 90 degrees off vertical with its nose on the horizon, and this
	## reports +90 because it is not leaning forward. That is the honest reading —
	## the number is a lift budget, and the sign only ever claims to say fore or
	## aft.
	##
	## Without a nose vector it returns the magnitude, which is what every caller
	## got before this existed.
	static func signed_tilt_degrees(axis: Vector3, nose: Vector3) -> float:
		var magnitude: float = tilt_degrees(axis)
		if magnitude <= 0.0 or nose.length_squared() < 0.000001:
			return magnitude
		var forward := Vector2(nose.x, nose.z)
		var lean := Vector2(axis.x, axis.z)
		if forward.length_squared() < 0.000001 or lean.length_squared() < 0.000001:
			return magnitude
		return -magnitude if lean.dot(forward.normalized()) > 0.0 else magnitude


	## WHERE THE WORLD HORIZON SITS, in pixels below screen centre. Pitch UP pushes
	## the horizon DOWN the screen and screen Y grows downward, so the sign works
	## out with no negation.
	##
	## THE ONLY CAP IS `FAR`, AND THAT IS ARITHMETIC HYGIENE RATHER THAN A CLAMP:
	## `tan` runs away at +/-90 degrees and would hand the renderer an infinity.
	## Forty screens away is gone by any measure, so nothing that survives this can
	## be mistaken for a horizon. It is a separate function so `hud_check` can
	## sweep it and refuse any clamp that creeps back in.
	static func horizon_drop(pitch: float, focal: float) -> float:
		var raw: float = tan(pitch) * focal
		if not is_finite(raw):
			return signf(pitch) * FAR
		return clampf(raw, -FAR, FAR)


	## THE HORIZON HAS LEFT THE SCREEN — say which way, without drawing anything
	## that could be read as the horizon itself.
	##
	## Two small chevron stacks out at the ends rather than one at the centre, for
	## a reason found by screenshotting the plate: the AIRFRAME plate owns the
	## bottom middle of the screen, so a centre marker at the bottom edge lands on
	## top of it. At 55% of the horizon's own reach these sit far outside it.
	func _horizon_gone(below: bool, along: Vector2, reach: float,
			tint: Color) -> void:
		var edge: float = size.y - EDGE_MARGIN if below else EDGE_MARGIN
		var toward := Vector2(0.0, 1.0 if below else -1.0)
		for side: float in [-1.0, 1.0]:
			# A FIXED offset, NOT one scaled by `along.x`. Rolling the marker's
			# POSITION with the aircraft looks tidy and collapses both markers onto
			# the screen centre at 90 degrees of roll — which is exactly where the
			# AIRFRAME plate lives. Only the arrowheads roll.
			var root := Vector2(size.x * 0.5 + reach * 0.55 * side, edge)
			_chevrons(root, along, toward, 8.0, tint)


	## A stack of three arrowheads pointing `toward`, tips leading. Shared by the
	## horizon's off-screen marker and the bracket's peg mark.
	##
	## IT EXISTS BECAUSE BOTH OF THEM WERE DRAWING FLAT DASHES. The old code ran
	## `draw_line(tip - along * 8, tip)` and `draw_line(tip + along * 8, tip)`,
	## which are COLLINEAR whenever the aircraft is level — the two arms lay in the
	## same straight line and the arrowhead was a 16 px dash. Three of them stacked
	## read as an equals sign, which is what a screenshot showed and what no amount
	## of reading the code had. The arms now step BACK from the tip, so it is an
	## arrowhead at every roll angle.
	func _chevrons(root: Vector2, along: Vector2, toward: Vector2, spread: float,
			tint: Color) -> void:
		for step: int in 3:
			var tip: Vector2 = root - toward * float(step) * 9.0
			draw_line(tip, tip - along * spread - toward * 7.0, tint, 2.0)
			draw_line(tip, tip + along * spread - toward * 7.0, tint, 2.0)


	func _draw() -> void:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera == null:
			return
		var basis: Basis = camera.global_basis
		# Forward is -Z on a Godot camera. Pitch is how far that is lifted off
		# the horizontal; roll is how far the camera's own up is turned from the
		# world's, measured in the plane the pilot sees.
		# The world horizon is the plane perpendicular to WORLD up, so it comes
		# out of the very same function the airframe's own level line does — see
		# `reference_pitch_roll` for why that is the point rather than a tidy-up.
		var pr: Vector2 = reference_pitch_roll(basis, Vector3.UP)
		var pitch: float = pr.x
		var roll: float = pr.y
		var f: float = focal_px(size.y, camera.fov)
		var drop: float = horizon_drop(pitch, f)
		# THE AIRFRAME'S LINE IS DRAWN LAST, ON TOP OF EVERYTHING — see the call at
		# the end of this function. It used to be drawn FIRST, so the horizon and
		# every ladder rung painted straight over it, which is half of why the
		# human could not find it: *"im not sure i see the green line."*
		#
		# THE WORLD HORIZON IS NEVER MOVED. It is drawn exactly where the horizon
		# projects, and when that is past the edge it simply leaves the screen with
		# a marker at the edge saying which way it went.
		#
		# It used to be CLAMPED 210 px inside the edge and then DROPPED entirely
		# past a threshold, and the human flew both and reported both: *"the entire
		# horizon indicator first disconnects from the horizon line... and if i
		# pitch even more then the entire horizon indicator lines disappear. i dont
		# feel this is the correct way its suppose to operate."* They were right on
		# both counts and the arithmetic says how badly. On a 94-degree lens the
		# focal length is about 503 px, so a 210 px clamp detached the line at 33
		# degrees of camera pitch — about 15 degrees of nose-down — and the drop
		# threshold fired at 78.7 degrees of camera pitch, which with 48 degrees of
		# lens uptilt is only 31 degrees NOSE UP. Both were reachable in ordinary
		# flight, and a reference that lies about where the horizon is is worse than
		# one that admits it has gone.
		#
		# The airframe BRACKET still pegs, and that is not the same thing: it is a
		# fixed mark reading "your level is here", not a claim about the world.
		var horizon_off_screen: bool = absf(drop) > size.y * 0.5 - EDGE_MARGIN
		var reach: float = size.x * REACH_FRACTION
		var at := Vector2(size.x * 0.5, size.y * 0.5 + drop)
		# WORLD UP, PROJECTED, AND THE SIGN IS DERIVED RATHER THAN EYEBALLED.
		# World up is (0,1,0); in camera space that is
		# `basis.transposed() * up = (basis.x.y, basis.y.y, basis.z.y)`, and screen
		# Y grows downward, so its screen direction is `(basis.x.y, -basis.y.y)` —
		# which with `roll = atan2(basis.x.y, basis.y.y)` is `(sin, -cos)`.
		# The first version wrote `(-sin, -cos)` and pointed the tick the wrong way
		# under roll; level flight looked perfect, which is exactly how it survived.
		var up: Vector2 = world_up_screen(roll)
		var along := Vector2(cos(roll), sin(roll))
		# BRIGHTER THAN IT WAS, because this is the line that FOLLOWS THE HORIZON
		# and therefore the one the pilot actually flies by. It was a 0.32-alpha
		# hairline while a long white line sat below it pretending to be the
		# horizon; the emphasis was on the wrong one of the two.
		var tint := Color(0.7, 0.92, 1.0, 0.75)
		# TWO DASHED RUNS WITH A GAP, so the horizon never draws through the
		# aiming point. Dashed on the human's reference: a solid line this wide
		# fights the scene, and the same length broken up reads as a SCALE while
		# letting the world through.
		_dashes(at - along * reach, at - along * GAP, tint, 2.0)
		_dashes(at + along * GAP, at + along * reach, tint, 2.0)
		# Wing marks at the ends, turned toward the sky, so the line reads as an
		# attitude instrument rather than as a stray scratch.
		for side: float in [-1.0, 1.0]:
			var end: Vector2 = at + along * reach * side
			draw_line(end, end + up * 7.0, tint, 1.5)
		if horizon_off_screen:
			_horizon_gone(drop > 0.0, along, reach, tint)
		if ladder:
			_draw_ladder(at, along, up, f, reach)
		# LAST, so nothing is drawn over the one line the pilot flies by. At level
		# it sits exactly on the world horizon by construction, so if it were not
		# on top it would be invisible in precisely the attitude a pilot checks
		# most often.
		_draw_frame_level(basis, f)


	## THE PITCH LADDER (the human: *"i want realism"*), in the convention a real
	## attitude indicator uses.
	##
	## A rung every RUNG_STEP degrees, labelled, drawn SHORTER than the horizon so
	## the horizon stays the dominant line — and **rungs above the horizon are
	## solid while rungs below are dashed**. That is not decoration: when the
	## horizon itself has slid off-screen, the only thing telling you whether you
	## are looking at sky or at ground is which style of rung is in front of you,
	## and fast-and-low is exactly when the horizon is off-screen.
	##
	## It rides `along` and `up`, so it rolls WITH the horizon rather than staying
	## screen-locked. A ladder that did not roll would be worse than none: it
	## would read as level attitude while the aircraft was on its side.
	func _draw_ladder(at: Vector2, along: Vector2, up: Vector2, f: float,
			reach: float) -> void:
		var font: Font = get_theme_default_font()
		var half: float = reach * RUNG_FRACTION
		var tint := Color(0.55, 0.85, 1.0, 0.26)
		var degrees: int = RUNG_STEP
		while degrees <= RUNG_MAX:
			for sign_up: int in [1, -1]:
				var offset: float = rung_offset(float(degrees * sign_up), f)
				# `up` points at the sky and screen Y grows downward, so a
				# POSITIVE pitch angle is drawn along +up.
				var mid: Vector2 = at + up * offset
				if mid.y < -40.0 or mid.y > size.y + 40.0:
					continue
				var a: Vector2 = mid - along * half
				var b: Vector2 = mid + along * half
				if sign_up > 0:
					draw_line(a, b, tint, 1.5)
				else:
					_dashes(a, b, tint, 1.5)
				# Ends turned toward the horizon, which is the other half of the
				# convention: the rung "points" back to level.
				var inward: Vector2 = -up * signf(float(sign_up)) * 6.0
				draw_line(a, a + inward, tint, 1.5)
				draw_line(b, b + inward, tint, 1.5)
				var text: String = "%d" % degrees
				draw_string(font, b + along * 6.0 + Vector2(0.0, 4.0), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)
			degrees += RUNG_STEP


	## A dashed run between two points. Godot has no dashed-line primitive, and
	## the alternative — one `draw_line` per dash computed at the call site — is
	## how three call sites end up with three different dash rhythms.
	func _dashes(from: Vector2, to: Vector2, col: Color, width: float) -> void:
		var span: Vector2 = to - from
		var length: float = span.length()
		if length < 0.001:
			return
		var step: Vector2 = span / length
		var travelled: float = 0.0
		while travelled < length:
			var end: float = minf(travelled + DASH, length)
			draw_line(from + step * travelled, from + step * end, col, width)
			travelled = end + DASH_GAP


	## THE DIRECTION THE ROTORS ARE PUSHING, drawn from the aiming point, with the
	## tilt off vertical printed beside it (the human's ask, 2026-08-15): *"an
	## indicator that points exactly to the same direction as the rotors push, so
	## i'll have a way to align with the horizon, not just with feel, useful
	## especially when i fly close to the ground"* — and then the case that
	## matters: *"close to the ground and fast."*
	##
	## **A LINE, NOT AN ARROW, ON THE HUMAN'S CALL** — *"i want a line that will
	## highlight the angle of the fpv tilt. instead of that arrow that drawn from
	## the center up."* They are right, and the reason is worth keeping: an
	## arrow-against-a-line is a coarse comparison, while LINE AGAINST LINE is a
	## precise one. Reading this HUD is reading the GAP between two lines, and a
	## gap closes visibly in a way an angle between two different shapes does not.
	##
	## IT IS ALSO LITERALLY THE FPV TILT. The lens is uptilted by
	## `fpv_uptilt_deg`, which is exactly why the airframe's own level plane does
	## not sit on the boresight — so where this line falls IS that angle, shown.
	##
	## **THE NUMBER RIDES IT** because only `cos(tilt)` of the thrust is still
	## fighting gravity: at 60 degrees over, half the rotors' push has stopped
	## holding you up. Fast and low is exactly the attitude where that is largest
	## and where feel reports nothing until the ground arrives.
	##
	## In FPV this line barely moves and the WORLD horizon moves against it, which
	## is correct rather than broken — it is the reference. In chase view the
	## camera is not frame-fixed and it swings on its own.
	func _draw_frame_level(camera_basis: Basis, f: float) -> void:
		if thrust_axis.length_squared() < 0.000001:
			return
		var pr: Vector2 = reference_pitch_roll(camera_basis, thrust_axis)
		var drop: float = tan(pr.x) * f
		# PEGGED TO THE EDGE RATHER THAN LOST OFF IT, and this is the fix for the
		# bug that made the whole instrument invisible.
		#
		# `fpv_uptilt_deg` is 48 degrees. At LEVEL HOVER the airframe's own level
		# plane therefore projects to `tan(48) * f` — about 600 px below centre on
		# a 1080 screen, which is off the bottom of it. The geometry was right and
		# the instrument was useless: a real 48-degree-uptilt quad hovering does
		# look mostly at sky, but a reference you cannot see in the most common
		# attitude in the game is not a reference. The human flew it and could not
		# find the line, and they were correct.
		#
		# So it clamps to the edge and SAYS SO with outward chevrons. A pegged
		# line is honest — "your level is further that way than the screen goes" —
		# where silently vanishing was not.
		var limit: float = size.y * 0.5 - PEG_MARGIN
		var pegged: bool = absf(drop) > limit
		drop = clampf(drop, -limit, limit)
		var tilt: float = tilt_degrees(thrust_axis)
		var tint: Color = tilt_tint(tilt)
		var along := Vector2(cos(pr.y), sin(pr.y))
		var up: Vector2 = world_up_screen(pr.y)
		var at := Vector2(size.x * 0.5, size.y * 0.5 + drop)
		# SHORTER THAN THE WORLD HORIZON, SOLID where that one is dashed, and
		# THICKER — it has to survive sitting exactly on top of the horizon, which
		# is where it lives whenever the aircraft is level.
		# A SHORT BRACKET, NOT A LONG LINE, AND THE HUMAN'S FLIGHT REPORT IS WHY:
		# *"i think it doesnt compensate for the pitch... once i lift off it
		# doesnt follow the horizon level."*
		#
		# They are right, and it is a fact about the configuration rather than a
		# bug. In FPV the lens is BOLTED TO THE FRAME, so the airframe's own level
		# plane sits at a CONSTANT screen position — `tan(fpv_uptilt_deg)` below
		# the boresight, whatever the aircraft does. It cannot follow the horizon;
		# only the horizon moves. Drawn as a long line it looked like a broken
		# horizon, because that is what a long horizontal line claims to be.
		#
		# So it is now what it actually is: a FIXED REFERENCE MARK reading "your
		# level is here", with the world horizon as the thing that travels to meet
		# it. Bring the horizon onto this bracket and you are level. The angle
		# rides it, because at 48 degrees of uptilt on a 94 degree lens that mark
		# lives off the bottom edge and the NUMBER is what survives the clamp.
		var shade := Color(0.0, 0.0, 0.0, 0.45)
		for pass_index: int in 2:
			var col: Color = shade if pass_index == 0 else tint
			var width: float = 5.0 if pass_index == 0 else 2.5
			for side: float in [-1.0, 1.0]:
				var inner: Vector2 = at + along * GAP * side
				var outer: Vector2 = at + along * (GAP + BRACKET) * side
				draw_line(inner, outer, col, width)
				draw_line(outer, outer + up * 8.0, col, width)
		if pegged:
			# Arrowheads pointing the way the mark really lies, so a clamped
			# reading can never be mistaken for a true one. The bracket is pegged
			# in essentially every attitude (see PEG_MARGIN), so this is on screen
			# almost always and it is worth it being an arrow rather than a dash.
			var toward := Vector2(0.0, signf(tan(pr.x)))
			_chevrons(at + toward * 15.0, along, toward, 6.0, tint)
		# SIGNED: negative nose-down, positive nose-up. The colour still ramps on
		# the MAGNITUDE, because lift lost does not care which way you lean.
		draw_string(get_theme_default_font(),
				at + along * (GAP + BRACKET) + Vector2(8.0, -6.0),
				"%d°" % roundi(signed_tilt_degrees(thrust_axis, nose_axis)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)


## Raw gamepad stick positions: two boxes flanking the health bar, a dot per
## stick (left = yaw/throttle, right = roll/pitch), x right / y up. Raw on
## purpose — no deadzone, expo or curve — so the pilot sees the hardware.
class StickDisplay:
	extends Control

	const HALF: float = 38.0
	const MARGIN: Vector2 = Vector2(230.0, 62.0)

	var left_stick: Vector2 = Vector2.ZERO
	var right_stick: Vector2 = Vector2.ZERO

	func _draw() -> void:
		var bottom_center := Vector2(size.x * 0.5, size.y)
		_draw_stick(bottom_center + Vector2(-MARGIN.x, -MARGIN.y), left_stick)
		_draw_stick(bottom_center + Vector2(MARGIN.x, -MARGIN.y), right_stick)

	func _draw_stick(center: Vector2, stick: Vector2) -> void:
		var frame := Color(1, 1, 1, 0.35)
		draw_rect(Rect2(center - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0),
				frame, false, 1.5)
		draw_line(center - Vector2(HALF, 0), center + Vector2(HALF, 0), frame, 1.0)
		draw_line(center - Vector2(0, HALF), center + Vector2(0, HALF), frame, 1.0)
		# Screen y grows downward; stick y is +up.
		var dot: Vector2 = center + Vector2(stick.x, -stick.y) * HALF
		draw_rect(Rect2(dot - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 0.9))


## Blue box drawn at the open exit gate's screen position (roadmap M4).
class GateMarker:
	extends Control

	var marker_visible: bool = false
	var marker_position: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if not marker_visible:
			return
		var half: float = 18.0
		var color := Color(0.3, 0.7, 1.0, 0.9)
		draw_rect(Rect2(marker_position - Vector2(half, half),
				Vector2(half, half) * 2.0), color, false, 2.0)
		draw_string(get_theme_default_font(),
				marker_position + Vector2(-18.0, half + 18.0), "EXIT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _ready() -> void:
	# Video-breakup overlay sits at the bottom of the layer so the crisp HUD
	# draws on top of it (the feed degrades, the instruments do not).
	_video_glitch = ColorRect.new()
	_video_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glitch_material := ShaderMaterial.new()
	glitch_material.shader = load("res://resources/video_glitch.gdshader") as Shader
	_video_glitch.material = glitch_material
	_video_glitch.visible = false
	add_child(_video_glitch)
	_motor_status = ComponentStatus.new()
	_motor_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_motor_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_motor_status)
	_lock_indicator = LockIndicator.new()
	_lock_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_indicator)
	_gate_marker = GateMarker.new()
	_gate_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gate_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gate_marker)
	_reticle = Reticle.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)
	_stick_display = StickDisplay.new()
	_stick_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stick_display)
	# The horizon, under the weapon rings so the instruments draw over it.
	_horizon = HorizonLine.new()
	_horizon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_horizon)
	# The blaster's heat: the right HALF, yellow because the palette says so
	# (CLAUDE.md): yellow = your fire.
	_heat_gauge = _add_gauge("HEAT", 1.0, PI, PI * 0.5, Color(1.0, 0.85, 0.25))
	# The two magazines split the LEFT side into quarters, drawn one radius apart
	# so they nest rather than collide. Both fill toward the top, so "full is up"
	# holds for every gauge on the screen.
	_flak_gauge = _add_gauge("FLAK", -1.0, PI * 0.5, PI * 0.5,
			Color(1.0, 0.62, 0.2))
	_missile_gauge = _add_gauge("MSL", -1.0, PI * 0.5, PI, Color(0.8, 0.5, 1.0))
	_repair_label = Label.new()
	_repair_label.text = "⟳ ENGINES RESTORED"
	_repair_label.add_theme_color_override(&"font_color", Color(0.3, 1.0, 0.45))
	_repair_label.add_theme_font_size_override(&"font_size", 20)
	_repair_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_repair_label.position.y = 76.0
	_repair_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_repair_label.modulate.a = 0.0
	add_child(_repair_label)
	_pause_label = Label.new()
	_pause_label.text = "|| SLOW-MO — autopilot holding"
	_pause_label.add_theme_color_override(&"font_color", Color(0.4, 0.85, 1.0))
	_pause_label.add_theme_font_size_override(&"font_size", 20)
	_pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pause_label.position.y = 48.0
	_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_label.visible = false
	add_child(_pause_label)
	for side: StringName in [&"front", &"back", &"left", &"right"]:
		var edge := ColorRect.new()
		edge.color = Color(1, 0, 0, 0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match side:
			&"front":
				edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
				edge.offset_bottom = 24.0
			&"back":
				edge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				edge.offset_top = -24.0
			&"left":
				edge.set_anchors_preset(Control.PRESET_LEFT_WIDE)
				edge.offset_right = 24.0
			&"right":
				edge.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
				edge.offset_left = -24.0
		add_child(edge)
		_edges[side] = edge


func set_score(total: int) -> void:
	_score_label.text = "SCORE %d" % total


func set_combo(multiplier: int) -> void:
	_combo_label.visible = multiplier > 1
	_combo_label.text = "x%d" % multiplier


func set_wave(sortie: int, wave: int, remaining: int) -> void:
	if remaining > 0:
		_wave_label.text = "SORTIE %d · WAVE %d — %d hostile%s" % [sortie, wave,
				remaining, "" if remaining == 1 else "s"]
	else:
		_wave_label.text = "SORTIE %d · WAVE %d CLEARED" % [sortie, wave]


func announce_gate(sortie: int) -> void:
	_wave_label.text = "SORTIE %d CLEAR — EXIT GATE OPEN" % sortie


## WHICH WAY THE ROTORS ARE PUSHING — the drone's body +Y in world space, which
## on a multirotor IS the thrust axis. Pass `Vector3.ZERO` to hide the arrow.
##
## Fed rather than looked up: the HUD does not know which node is the aircraft,
## and four scenes fly one.
func set_thrust_axis(world_up_of_airframe: Vector3,
		nose: Vector3 = Vector3.ZERO) -> void:
	_horizon.thrust_axis = world_up_of_airframe
	_horizon.nose_axis = nose
	_horizon.queue_redraw()


## The pitch ladder on or off, returning the new state so the caller can say so
## in the kill feed. The horizon and the thrust arrow are NOT toggled with it:
## they are the instrument, and the ladder is the detail around them.
func toggle_pitch_ladder() -> bool:
	return set_pitch_ladder(not _horizon.ladder)


## The ladder set rather than flipped, for a caller that needs a KNOWN state
## instead of the opposite of whatever it was. The drill runner is the first:
## a drill whose stated situation is "the ladder is on" cannot be run by
## toggling and hoping.
func set_pitch_ladder(on: bool) -> bool:
	_horizon.ladder = on
	_horizon.queue_redraw()
	return _horizon.ladder


## One weapon-state ring at the aiming point. `span` is how much of the circle it
## owns (PI a half, PI/2 a quarter) and `start_angle` is where its fill begins,
## measured the way `draw_arc` does — so two quarters can share a side by starting
## a quarter-turn apart.
func _add_gauge(text: String, at_side: float, span: float, start_angle: float,
		tint: Color) -> WeaponGauge:
	var gauge := WeaponGauge.new()
	gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.label = text
	gauge.side = at_side
	gauge.span = span
	gauge.start_angle = start_angle
	gauge.tint = tint
	add_child(gauge)
	return gauge


## STRUCTURAL INTEGRITY, now drawn as the airframe's own hull on the plate rather
## than as a bar under it (the human's call, 2026-08-15: *"we can now add the hull
## health to it in some creative way"*). The ProgressBar it replaced is gone.
##
## Still a value passed IN rather than read off the component registry, because
## six callers feed this and only two feed the parts list — the menu tower, the
## aim drill and the duel harness would all have lost their hull readout.
func set_health(current: float, maximum: float) -> void:
	_motor_status.hull = current / maximum if maximum > 0.0 else 0.0
	_motor_status.queue_redraw()


## The blaster's heat, 0..1, and whether it has locked out.
##
## Two states that must be tellable apart WITHOUT reading a number, because
## they mean opposite things to a trigger finger: yellow filling toward red is
## "you have a burst left", and a pulsing red bar is "the gun is dead, stop
## pulling". A heat meter you have to interpret is a heat meter that reads as a
## broken weapon the first time it bites.
##
## Yellow because the palette says so (CLAUDE.md): yellow = your fire.
##
## Now a half ring around the AIMING POINT instead of a bar 58 px off the bottom
## edge, because heat is the one readout you consult while aiming and the old
## placement cost a glance away from the target to read it.
func set_heat(fraction: float, overheated: bool) -> void:
	_heat_gauge.show_value(fraction, overheated)


## The two magazines. A weapon passing -1 has no magazine at all and is left
## off the readout entirely — the ABSENCE of a number is information: it says
## that weapon never runs out, which is exactly the blaster's contract.
func set_ammo(flak: int, missile: int, flak_max: int = 0,
		missile_max: int = 0) -> void:
	_magazine(_flak_gauge, flak, flak_max)
	_magazine(_missile_gauge, missile, missile_max)
	# The text stays as well as the rings, and deliberately: a ring answers "how
	# much is left" at a glance while you are aiming, and the exact count is a
	# number you spend deliberately. They are two different questions.
	var parts: PackedStringArray = []
	if flak >= 0:
		parts.append("FLAK %d" % flak)
	if missile >= 0:
		parts.append("MSL %d" % missile)
	_ammo_label.text = "   ".join(parts)
	# Dry is a state you must notice mid-fight, not one you read.
	var dry: bool = (flak == 0) or (missile == 0)
	_ammo_label.modulate = Color(1.0, 0.35, 0.25) if dry else Color(0.85, 0.85, 0.9)


## A magazine on a ring. `rounds` of -1 means the weapon has no magazine at all,
## which hides the gauge entirely — the ABSENCE is information, and it is the
## blaster's contract. `capacity` of 0 means the caller has not been taught to
## pass one yet, which also hides it rather than inventing a denominator.
func _magazine(gauge: WeaponGauge, rounds: int, capacity: int) -> void:
	if rounds < 0 or capacity <= 0:
		gauge.visible = false
		return
	gauge.visible = true
	gauge.count = rounds
	gauge.show_value(float(rounds) / float(capacity), rounds == 0)


## The whole component list, straight off the registry (E.q5). Replaces
## `set_motor_health(healths, vtx)`: the gauge no longer takes an array whose
## length it has to agree with and a transmitter threaded in beside it, so a new
## component is a `TABLE` row rather than another argument through this seam.
func set_components(parts: Array[AirframeComponents.Part]) -> void:
	_motor_status.parts = parts
	_motor_status.queue_redraw()


## Video-breakup intensity [0, 1]; 0 hides the overlay entirely (no cost).
## THE AIRFRAME PLATE, HIDDEN — for the one caller that needs the pilot NOT to
## have it. `rotor_out` asks how much of a rotor a human loses before they feel
## it, and a gauge that draws the rotor emptying answers a different question
## perfectly. Nothing in the game hides it; only the drill does.
func set_plate_visible(shown: bool) -> void:
	_motor_status.visible = shown


func set_video_glitch(intensity: float) -> void:
	var clamped: float = clampf(intensity, 0.0, 1.0)
	_video_glitch.visible = clamped > 0.001
	if _video_glitch.visible:
		(_video_glitch.material as ShaderMaterial).set_shader_parameter(
				&"glitch", clamped)


## side: front/back/left/right for an edge hint, anything else full-screen.
func flash_damage(side: StringName = &"all") -> void:
	var rect: ColorRect = _edges.get(side, _damage_flash)
	rect.color = Color(1, 0, 0, 0.35)
	create_tween().tween_property(rect, "color:a", 0.0, 0.45)


func add_kill_feed(text: String) -> void:
	var entry := Label.new()
	entry.text = text
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed.add_child(entry)
	_kill_feed.move_child(entry, 0)
	while _kill_feed.get_child_count() > KILL_FEED_MAX:
		_kill_feed.get_child(_kill_feed.get_child_count() - 1).free()
	var tween: Tween = entry.create_tween()
	tween.tween_interval(KILL_FEED_SECONDS)
	tween.tween_property(entry, "modulate:a", 0.0, 0.6)
	tween.tween_callback(entry.queue_free)


func update_lock(target_visible: bool, screen_position: Vector2 = Vector2.ZERO,
		progress: float = 0.0, locked: bool = false,
		auto_progress: float = 0.0) -> void:
	_lock_indicator.target_visible = target_visible
	_lock_indicator.target_position = screen_position
	_lock_indicator.progress = progress
	_lock_indicator.locked = locked
	_lock_indicator.auto_progress = auto_progress
	_lock_indicator.queue_redraw()


func update_sticks(left_stick: Vector2, right_stick: Vector2) -> void:
	_stick_display.left_stick = left_stick
	_stick_display.right_stick = right_stick
	_stick_display.queue_redraw()


## Empty array hides the funnel.
func update_reticle(center: Vector2, pipper: Vector2, arc: PackedVector2Array,
		ticks: Array, lock_radius: float, hold_radius: float,
		lockable: bool) -> void:
	_reticle.active = true
	_reticle.center = center
	_reticle.pipper = pipper
	_reticle.arc = arc
	_reticle.ticks = ticks
	_reticle.lock_radius = lock_radius
	_reticle.hold_radius = hold_radius
	_reticle.lockable = lockable
	_reticle.queue_redraw()


## Disarmed / no camera: keep the lock cone hint if one was passed, hide the gun.
func clear_reticle() -> void:
	_reticle.active = false
	_reticle.lock_radius = 0.0
	_reticle.hold_radius = 0.0
	_reticle.queue_redraw()


func update_gate_marker(marker_visible: bool,
		screen_position: Vector2 = Vector2.ZERO) -> void:
	_gate_marker.marker_visible = marker_visible
	_gate_marker.marker_position = screen_position
	_gate_marker.queue_redraw()


## Brief green confirmation flash when a repair gate restores the engines.
func flash_engines_restored() -> void:
	_repair_label.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(_repair_label, "modulate:a", 0.0, 0.7)


func show_pause(paused: bool) -> void:
	_pause_label.visible = paused


func show_death(dead: bool) -> void:
	_death_label.visible = dead


func show_title(bests_line: String) -> void:
	_title_bests.text = bests_line
	_title.visible = true


func hide_title() -> void:
	_title.visible = false


func show_run_summary(sorties_cleared: int, waves_cleared: int, kills: int,
		score: int, bests_line: String = "") -> void:
	_summary_label.text = "RUN OVER\n\nsorties cleared  %d\nwaves cleared  %d\nkills  %d\nscore  %d\n\n%s\n\narm to fly again" \
			% [sorties_cleared, waves_cleared, kills, score, bests_line]
	_summary.visible = true


func hide_run_summary() -> void:
	_summary.visible = false
