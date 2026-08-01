class_name HexTable
extends Node3D

## THE THEATER AS A TABLE (GAMEPLAY-DESIGN Iteration 13, C.q1 → the 3D hex
## table). One hex prism per node, laid on `WarView`'s axial projection, lit by
## the shipped look pass.
##
## THE CHANNELS ARE ASSIGNED, NOT DECORATED (C4). A strategic map with six
## overlapping encodings is a map nobody reads, so each visual carries exactly
## one fact:
##
##   height   garrison strength      the thing you most need at a glance
##   colour   owner                  green friendly, red hostile
##   dimming  out of strike range    unreachable ground recedes
##   glyph    node id + type tag     `GlowText3D`, the B5 primitive that already
##                                   renders A-Z and 0-9 (it learned numerals in
##                                   v1.92 for the resupply gates)
##   spire    home airbase / enemy HQ  cyan navigation, hot-white objective
##   bar      the FRONT LINE         drawn along the shared hex edge, because
##                                   that is where a front line actually is
##   thin line  supply connection    the tick engine's own `supplied_set`
##
## Everything it draws comes from `WarView`, which is pure and checkable. This
## file owns geometry and materials and no facts at all — if the map is ever
## wrong, it is wrong in a headless-testable function rather than in here.

## Centre-to-corner of one hex, in metres. Everything else scales off it.
const HEX_SIZE: float = 2.2
## IT IS A BEEHIVE (P1.8, the user's word, and the point of hexes at all): the
## cells TESSELLATE. Held a hair under 1.0 only so two neighbours' shared faces
## are not exactly coplanar, which z-fights; the resulting seam is ~2 cm and
## reads as a joint rather than as a gap.
##
## It was 0.82 for two builds, on the theory that hexes need air between them to
## read as separate places. They do not — the height difference already does
## that — and the gaps cost the tessellation the whole shape was chosen for.
const HEX_FILL: float = 0.99
## Garrison → prism height. The floor exists so an emptied node is still a place
## you can see and click, not a hole in the map.
const HEIGHT_MIN: float = 0.35
const HEIGHT_SPAN: float = 3.2

const SPIRE_HEIGHT: float = 3.0
const SPIRE_WIDTH: float = 0.28
const LABEL_PIXEL: float = 0.07
const LABEL_CLEARANCE: float = 0.7

const EDGE_THICKNESS: float = 0.16
const FRONT_BAR_HEIGHT: float = 0.7
const SUPPLY_BAR_HEIGHT: float = 0.1

const COLOR_PLAYER := Color(0.16, 0.86, 0.42)
const COLOR_ENEMY := Color(0.90, 0.18, 0.18)
const COLOR_FRONT := Color(1.0, 0.62, 0.15)
const COLOR_HOME := Color(0.25, 0.75, 1.0)
const COLOR_HQ := Color(1.0, 1.0, 1.0)
const COLOR_SELECT := Color(1.0, 1.0, 1.0)
const COLOR_LABEL := Color(0.95, 0.97, 1.0)

## THE SURFACES DO NOT GLOW; THE MARKS ON THEM DO. Learned by looking at the
## first build (standing rule 6): hex faces are large, and at emission energies
## over the game's 1.0 bloom threshold they bloomed into flat white shapes with
## unreadable glyphs — while the *dimmed* out-of-range hexes, which were supposed
## to recede, came out as the most legible things on the table. The hierarchy was
## exactly inverted. So a prism carries its colour in ALBEDO and gets only enough
## emission to be visible in a dark room.
##
## AND THE MARKS GLOW LESS THAN THEY DID (user, after flying it: *"too much neon
## blinding light"*). The glow budget is not the shipped look pass's to spend
## here — `LookController` re-applies the human-tuned `default_look_config.tres`
## every frame, so the war room cannot and must not turn the game's bloom down to
## suit itself. It turns ITSELF down instead: only the front line and the
## selection ring now sit above the 1.0 bloom threshold at all, and the glyphs
## deliberately sit just under it so they read as crisp text rather than as light.
const ENERGY_FLYABLE: float = 0.22
const ENERGY_HELD: float = 0.16
const ENERGY_DIM: float = 0.05
const ENERGY_LABEL: float = 0.95
const ENERGY_LABEL_DIM: float = 0.4
const ENERGY_FRONT: float = 1.3
const ENERGY_SUPPLY: float = 0.35
const ENERGY_SPIRE: float = 1.15
const ENERGY_SELECT: float = 1.6

## How long one node takes to move, and how far apart consecutive nodes start.
## Staggered rather than simultaneous: thirty hexes moving at once is a shrug,
## thirty moving in sequence is a war taking its turn.
##
## SLOWED TO SAVOUR (user, after flying it: *"it should slower to savour"*).
## Roughly double the first pass, which was quick enough to be over before you
## had found the node that moved.
const CHANGE_DURATION_S: float = 1.1
const CHANGE_STAGGER_S: float = 0.24
## …but bounded, because a heavy tick can move twenty nodes and a fixed stagger
## would turn a moment into a wait. Past this the sequence compresses instead of
## growing: the LAST node still gets its full duration, so nothing is ever cut
## short — the war just deals its cards faster when it has more of them.
const MAX_STAGGER_TOTAL_S: float = 3.6
## A node that changed hands lingers at full brightness before settling, so an
## ownership flip is not just a colour swap you can miss while looking elsewhere.
const FLIP_FLASH: float = 2.2

## Emitted when the tick has finished playing out on the map.
signal changes_played

## id → the prism, kept so a later phase can move one without rebuilding the
## table (C8's tick animation is the reason this is a Dictionary and not a list).
var prisms: Dictionary = {}
## id → its world centre, so picking never has to re-derive the projection.
var centers: Dictionary = {}
## id → its glyph, so a moving prism carries its label instead of leaving it
## hanging in the air where the node used to be.
var labels: Dictionary = {}
## The front-line walls and supply seams, hidden while the ground moves and
## rebuilt afterwards — they are pinned to heights that are changing.
var _edge_marks: Array[MeshInstance3D] = []

var _select_ring: MeshInstance3D
var _selected: int = -1

## In-flight animation: one entry per moving node, each with its own window.
var _moves: Array = []
var _move_clock: float = 0.0
var _move_ends: float = 0.0


## Rebuild the whole table. Cheap enough to call on every war tick (30 nodes),
## and rebuilding beats mutating while the map is still growing features.
##
## `view_from` is where the camera stands: the glyphs are turned to face it once
## here rather than billboarded every frame, because the camera does not move.
func build(state: Dictionary, config: WarConfig, view_from: Vector3) -> void:
	for stale: Node in get_children():
		stale.queue_free()
	prisms.clear()
	centers.clear()
	labels.clear()
	_edge_marks.clear()
	_select_ring = null
	_moves.clear()
	set_process(false)

	var reasons: Dictionary = WarView.refusals(state, config)
	# ONE ORIENTATION FOR EVERY GLYPH (user: *"the texts over each hexagon are
	# not all aligned to the same direction"*). Aiming each label at the camera
	# POINT fans them out across the table like a crowd turning to look at you;
	# aiming them all along the one view direction reads as a printed map, which
	# is what a map should read as.
	var label_basis: Basis = _facing(
			WarView.bounds(state, HEX_SIZE).get_center(), view_from)
	for node: Dictionary in state["nodes"]:
		_build_node(node, config, reasons, label_basis)
	for edge: Dictionary in WarView.supply_edges(state):
		_build_supply(edge)
	# The front line goes on last so it draws over the supply lines it crosses.
	for edge: Dictionary in WarView.front_line_edges(state):
		_build_front_bar(edge)

	_select_ring = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = HEX_SIZE * 0.74
	ring.outer_radius = HEX_SIZE * 0.86
	ring.material = _emissive(COLOR_SELECT, ENERGY_SELECT)
	_select_ring.mesh = ring
	_select_ring.visible = false
	add_child(_select_ring)
	if _selected >= 0:
		select(_selected)


## PLAY THE TICK (C8, and P1.8's *"the moment the player feels the theater being
## alive"*). The table must currently be built from the BEFORE state; each event
## then moves its node to where the war left it.
##
## Heights move and owners cross-fade. Nothing here recomputes anything: the
## events come from `WarDiff`, which derived them from the two states, so the
## animation cannot claim something the war did not do.
func play_changes(events: Array, after: Dictionary, config: WarConfig) -> void:
	_moves.clear()
	_move_clock = 0.0
	_move_ends = 0.0
	if events.is_empty():
		changes_played.emit()
		return

	var reasons: Dictionary = WarView.refusals(after, config)
	var stagger: float = minf(CHANGE_STAGGER_S,
			MAX_STAGGER_TOTAL_S / maxf(float(events.size() - 1), 1.0))
	var index: int = 0
	for event: Dictionary in events:
		var id: int = int(event["node_id"])
		if not prisms.has(id):
			continue
		var node: Dictionary = WarSim.node_by_id(after, id)
		if node.is_empty():
			continue
		var prism: MeshInstance3D = prisms[id]
		var material: StandardMaterial3D = (prism.mesh as CylinderMesh).material
		var starts: float = float(index) * stagger
		var target: StandardMaterial3D = _node_material(
				node, reasons.get(id, WarView.REASON_NONE))
		_moves.append({
			"id": id,
			"from_h": (prism.mesh as CylinderMesh).height,
			"to_h": _height_for(node, config),
			"from_c": material.emission,
			"to_c": target.emission,
			"from_a": material.albedo_color,
			"to_a": target.albedo_color,
			"from_e": material.emission_energy_multiplier,
			"to_e": target.emission_energy_multiplier,
			"flip": event["kind"] == WarDiff.KIND_CAPTURED
					or event["kind"] == WarDiff.KIND_LOST,
			"starts": starts,
		})
		_move_ends = maxf(_move_ends, starts + CHANGE_DURATION_S)
		index += 1

	if _moves.is_empty():
		changes_played.emit()
		return
	# The borders are pinned to heights that are about to change, so they come
	# down for the duration and the caller redraws them afterwards. That is also
	# the reading P1.8 wants: the ground moves, THEN the front line follows.
	for mark: MeshInstance3D in _edge_marks:
		mark.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if _moves.is_empty():
		set_process(false)
		return
	_move_clock += delta
	for move: Dictionary in _moves:
		var progress: float = clampf(
				(_move_clock - float(move["starts"])) / CHANGE_DURATION_S, 0.0, 1.0)
		if progress <= 0.0:
			continue
		var eased: float = ease(progress, 0.4)
		var prism: MeshInstance3D = prisms[int(move["id"])]
		var mesh: CylinderMesh = prism.mesh
		var height: float = lerpf(float(move["from_h"]), float(move["to_h"]), eased)
		mesh.height = height
		# The mesh is centred on its own origin, so a growing prism has to rise by
		# half of what it grew or it sinks through the table as it gets taller.
		prism.position.y = height * 0.5
		# The glyph rides its own prism. Left behind, it hangs in the air over a
		# node that has shrunk away from underneath it.
		if labels.has(int(move["id"])):
			(labels[int(move["id"])] as Node3D).position.y = height + LABEL_CLEARANCE
		var material: StandardMaterial3D = mesh.material
		material.emission = (move["from_c"] as Color).lerp(move["to_c"], eased)
		material.albedo_color = (move["from_a"] as Color).lerp(move["to_a"], eased)
		var energy: float = lerpf(float(move["from_e"]), float(move["to_e"]), eased)
		if bool(move["flip"]):
			# A half-cycle of extra brightness, peaking mid-move and gone by the
			# end, so ground changing hands announces itself.
			energy += FLIP_FLASH * sin(progress * PI)
		material.emission_energy_multiplier = energy
	if _move_clock >= _move_ends:
		_moves.clear()
		set_process(false)
		changes_played.emit()


func is_playing() -> bool:
	return not _moves.is_empty()


## Jump to the end. Savouring is the default and skipping is the escape hatch —
## the pacing that suits the first tick of a campaign is not the pacing that
## suits the fortieth.
func finish_changes() -> void:
	if _moves.is_empty():
		return
	_move_clock = _move_ends
	_process(0.0)


## Lift the ring onto a node. -1 clears the selection.
func select(id: int) -> void:
	_selected = id
	if _select_ring == null:
		return
	if not centers.has(id):
		_select_ring.visible = false
		return
	var prism: MeshInstance3D = prisms[id]
	var height: float = (prism.mesh as CylinderMesh).height
	_select_ring.position = Vector3(centers[id].x, height + 0.05, centers[id].z)
	_select_ring.visible = true


## Nearest node to a point on the table, or -1 if the point is off every cell.
## Compared against the hex INRADIUS so the cells tile the plane without gaps —
## a click between two hexes belongs to one of them, never to neither.
func pick(point: Vector3) -> int:
	var best: int = -1
	var best_distance: float = HEX_SIZE * WarView.SQRT3 * 0.5
	for id: int in centers:
		var distance: float = Vector2(point.x - centers[id].x,
				point.z - centers[id].z).length()
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


## The top face of a node's prism — where its glyph sits, and the point the room
## picks against in screen space (a tall prism's top is what the eye aims at,
## and it is metres away from the cell's footprint at this camera pitch).
func top_of(id: int) -> Vector3:
	if not centers.has(id):
		return Vector3.ZERO
	return centers[id] + Vector3.UP * (prisms[id].mesh as CylinderMesh).height


## The table's footprint, for framing a camera on it.
func bounds() -> AABB:
	var box := AABB()
	var first: bool = true
	for id: int in centers:
		if first:
			box = AABB(centers[id], Vector3.ZERO)
			first = false
		else:
			box = box.expand(centers[id])
	return box.grow(HEX_SIZE)


## ---------- geometry ----------

func _build_node(node: Dictionary, config: WarConfig, reasons: Dictionary,
		label_basis: Basis) -> void:
	var id: int = int(node["id"])
	var center: Vector3 = WarView.node_world(node, HEX_SIZE)
	centers[id] = center

	var height: float = _height_for(node, config)

	var prism: CylinderMesh = CylinderMesh.new()
	prism.radial_segments = 6
	prism.rings = 0
	prism.top_radius = HEX_SIZE * HEX_FILL
	prism.bottom_radius = HEX_SIZE * HEX_FILL
	prism.height = height
	prism.material = _node_material(node, reasons.get(id, WarView.REASON_NONE))

	var instance := MeshInstance3D.new()
	instance.mesh = prism
	# NO ROTATION, and the 30 degrees that used to be here was the bug behind
	# "they don't align like a beehive". Godot's 6-segment cylinder already puts
	# corners at ±Z (probed: 90, 30, -30, -90, -150, 150 degrees from +X), which
	# is pointy-top and exactly what WarView's projection tiles. Rotating by 30
	# turned every cell flat-top, so no two neighbours could share an edge.
	instance.position = center + Vector3.UP * height * 0.5
	add_child(instance)
	prisms[id] = instance

	if bool(node["home"]) or bool(node["hq"]):
		_build_spire(center, height, COLOR_HOME if bool(node["home"]) else COLOR_HQ)

	# Near-white glyphs on a coloured face: the hex already says whose it is, and
	# a label tinted to match the surface under it is a label you cannot read.
	# Out-of-range nodes get a dim one, so "recedes" survives at glyph level too.
	var label := GlowText3D.new()
	label.text = "%d\n%s" % [id, WarView.type_tag(node["type"])]
	label.pixel_size = LABEL_PIXEL
	label.glow_color = COLOR_LABEL
	# A glyph floating over a lit surface prints a second, ghostly copy of itself
	# onto that surface. On the map that reads as a rendering fault.
	label.cast_shadows = false
	label.glow_energy = ENERGY_LABEL_DIM if reasons.get(id, WarView.REASON_NONE) \
			== WarView.REASON_RANGE else ENERGY_LABEL
	label.transform = Transform3D(label_basis,
			center + Vector3.UP * (height + LABEL_CLEARANCE))
	add_child(label)
	labels[id] = label


## A marker you can find from across the table: the two nodes the campaign is
## actually about (P1.5 — your home falling loses the war, their HQ winning it).
func _build_spire(center: Vector3, height: float, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(SPIRE_WIDTH, SPIRE_HEIGHT, SPIRE_WIDTH)
	mesh.material = _emissive(color, ENERGY_SPIRE)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center + Vector3.UP * (height + SPIRE_HEIGHT * 0.5)
	add_child(instance)


## BOTH EDGE MARKINGS LIVE IN THE SAME SLOT, and they can because they are
## mutually exclusive: an edge whose ends disagree about ownership is a front
## line, an edge whose ends agree AND are both supplied is a supply link, and
## nothing can be both. So every gap between two hexes shows at most one mark —
## an amber wall, a coloured plate, or nothing — which is a legible encoding
## rather than two systems fighting over the same pixels.
##
## They are drawn along the SHARED HEX EDGE rather than between the two centres.
## For a regular hexagon that edge is exactly `HEX_SIZE` long and sits at the
## midpoint, perpendicular to the line joining the centres — a front line reads
## as a wall between two places instead of a rope tying them together.
##
## THE TWO MARKS SIT AT DIFFERENT HEIGHTS ON PURPOSE, now that the cells
## tessellate and there is no trench to hide in. A front line is a WALL and goes
## on top of the taller neighbour, where it breaks the skyline. A supply link is
## a SEAM and sits at the shorter neighbour's shoulder, tucked into the step
## between the two — which is what stops it reading as the loose dashes the user
## called "weird lines" when both floated at the same height.
func _build_front_bar(edge: Dictionary) -> void:
	_build_edge_mark(edge, HEX_SIZE * 0.98, FRONT_BAR_HEIGHT,
			_emissive(COLOR_FRONT, ENERGY_FRONT), true)


## Kept deliberately below the nodes it joins in brightness. At 1.6 the enemy's
## rear supply network was the brightest thing on the table, which told the eye
## that the lines mattered more than the ground — the ordering the map wants is
## front line, then what you can attack, then how it is fed.
func _build_supply(edge: Dictionary) -> void:
	var color: Color = COLOR_PLAYER if edge["side"] == &"player" else COLOR_ENEMY
	_build_edge_mark(edge, HEX_SIZE * 0.62, SUPPLY_BAR_HEIGHT,
			_emissive(color * 0.75, ENERGY_SUPPLY), false)


func _build_edge_mark(edge: Dictionary, span: float, thickness: float,
		material: StandardMaterial3D, on_top: bool) -> void:
	var a: Vector3 = centers[int(edge["a"])]
	var b: Vector3 = centers[int(edge["b"])]
	var along: Vector3 = (b - a).normalized()
	# UP × along, not along × UP: the other order builds a mirrored basis.
	var across: Vector3 = Vector3.UP.cross(along).normalized()
	var height_a: float = _height_of(int(edge["a"]))
	var height_b: float = _height_of(int(edge["b"]))
	var at: float = maxf(height_a, height_b) if on_top else minf(height_a, height_b)

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(span, thickness, EDGE_THICKNESS)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(Basis(across, Vector3.UP, along),
			(a + b) * 0.5 + Vector3.UP * (at + thickness * 0.5))
	add_child(instance)
	_edge_marks.append(instance)


func _height_of(id: int) -> float:
	if not prisms.has(id):
		return 0.0
	return (prisms[id].mesh as CylinderMesh).height


## Garrison → prism height, in one place because the animation has to be able to
## ask for a node's height WITHOUT building it.
func _height_for(node: Dictionary, config: WarConfig) -> float:
	var load_fraction: float = clampf(
			float(node["garrison"]) / maxf(config.garrison_cap, 1.0), 0.0, 1.0)
	return HEIGHT_MIN + load_fraction * HEIGHT_SPAN


## ---------- materials ----------

func _node_material(node: Dictionary, reason: StringName) -> StandardMaterial3D:
	if node["owner"] == &"player":
		return _emissive(COLOR_PLAYER * 0.8, ENERGY_HELD)
	match reason:
		WarView.REASON_NONE:
			return _emissive(COLOR_ENEMY, ENERGY_FLYABLE)
		WarView.REASON_RANGE:
			# Out of reach recedes rather than disappearing: the ground exists,
			# you just cannot get there from the airbases you hold.
			return _emissive(COLOR_ENEMY * 0.42, ENERGY_DIM)
	# Reachable, hostile, and its archetype is not built yet (C.q3). Pushed most
	# of the way to slate rather than merely dimmed, so it reads as "not yet"
	# instead of "too far" — at a gentler lerp it was a slightly different pink
	# and the two refusals were indistinguishable on screen.
	return _emissive(COLOR_ENEMY.lerp(Color(0.42, 0.44, 0.52), 0.8), ENERGY_DIM * 2.0)


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## A basis whose +Z points from `at` toward `toward` — GlowText3D's glyphs face
## +Z, and the camera never moves, so this is done once at build rather than
## billboarded every frame.
static func _facing(at: Vector3, toward: Vector3) -> Basis:
	var forward: Vector3 = toward - at
	if forward.length_squared() < 0.0001:
		return Basis.IDENTITY
	forward = forward.normalized()
	var right: Vector3 = Vector3.UP.cross(forward)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, forward.cross(right), forward)
