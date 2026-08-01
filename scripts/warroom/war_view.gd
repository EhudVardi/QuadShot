class_name WarView
extends RefCounted

## THE MAP, DERIVED (GAMEPLAY-DESIGN Iteration 13, C4). Everything the war room
## draws, computed as pure functions over the war state Dictionary.
##
## Nothing here knows what a Node3D is, for the same reason nothing in `war/`
## does: the picture is a projection of the state, so it can be asserted in a
## headless check without a viewport, and a second renderer (C.q1's flyable map
## room, deferred rather than rejected) is a new file rather than a rewrite.
##
## IT ADDS NO STATE. Not one field of `user://war.save` exists for the map's
## benefit — ownership, garrison, weather and intel age were all already there,
## and the front line was never stored because P1.1 is explicit that it emerges
## from ownership rather than being drawn by the generator. `SAVE_VERSION` does
## not move for this iteration (C2), and that is a constraint on what may be
## built, not a coincidence.
##
## WHERE IT REFUSES TO HAVE ITS OWN OPINION: supply and strike range come from
## `WarSim.supplied_set` and `WarSim.strike_range`, the tick engine's own
## functions, published for this purpose. A map that computed its own reach
## would eventually promise ground the campaign does not have.

## Axial → world, pointy-top. The projection matches `TheaterGenerator`'s own
## use of the coordinates (it picks the westmost cell by `q + r * 0.5`), so the
## picture and the adjacency graph agree by construction rather than by care.
const SQRT3: float = 1.7320508075688772

## Reasons a node cannot be flown, as ids rather than sentences so a check can
## assert on them without matching display text (C.q3: the refusal is part of
## the design, so it is data).
const REASON_NONE: StringName = &""
const REASON_FRIENDLY: StringName = &"friendly"
const REASON_RANGE: StringName = &"out_of_range"
const REASON_ARCHETYPE: StringName = &"archetype_unbuilt"
const REASON_WAR_OVER: StringName = &"war_over"

## Short map labels for P1.2's node taxonomy. Four characters is what a hex top
## holds at a readable pixel size; the full name lives on the inspection card.
const TYPE_TAG: Dictionary = {
	&"airbase": "BASE", &"factory": "FCTY", &"radar": "RDR", &"sam": "SAM",
	&"depot": "DEPO", &"command": "CMD", &"hq": "HQ", &"airspace": "SKY",
}


static func hex_to_world(q: int, r: int, size: float) -> Vector3:
	return Vector3(size * SQRT3 * (float(q) + float(r) * 0.5), 0.0,
			size * 1.5 * float(r))


static func node_world(node: Dictionary, size: float) -> Vector3:
	return hex_to_world(int(node["q"]), int(node["r"]), size)


## The table's footprint, derived without building anything — the camera has to
## be framed before the table exists, because the glyphs are turned to face it.
static func bounds(state: Dictionary, size: float) -> AABB:
	var box := AABB()
	var first: bool = true
	for node: Dictionary in state["nodes"]:
		var at: Vector3 = node_world(node, size)
		if first:
			box = AABB(at, Vector3.ZERO)
			first = false
		else:
			box = box.expand(at)
	return box.grow(size)


static func type_tag(node_type: StringName) -> String:
	return TYPE_TAG.get(node_type, String(node_type).to_upper().substr(0, 4))


## Every adjacent pair exactly once, ordered `a < b` so an edge is one edge and
## not two facing opposite ways.
static func adjacent_pairs(state: Dictionary) -> Array:
	var pairs: Array = []
	var nodes: Array = state["nodes"]
	for i: int in nodes.size():
		var a: Dictionary = nodes[i]
		for j: int in range(i + 1, nodes.size()):
			var b: Dictionary = nodes[j]
			if TheaterGenerator.hex_distance(
					Vector2i(int(a["q"]), int(a["r"])),
					Vector2i(int(b["q"]), int(b["r"]))) == 1:
				pairs.append({"a": mini(int(a["id"]), int(b["id"])),
						"b": maxi(int(a["id"]), int(b["id"]))})
	return pairs


## THE FRONT LINE IS NOT DRAWN BY THE GENERATOR (P1.1) — it is the boundary
## between owners, so it is computed from ownership and it moves because the war
## moved. An edge is on the front when its two ends disagree about who owns them.
static func front_line_edges(state: Dictionary) -> Array:
	var edges: Array = []
	for pair: Dictionary in adjacent_pairs(state):
		var a: Dictionary = WarSim.node_by_id(state, int(pair["a"]))
		var b: Dictionary = WarSim.node_by_id(state, int(pair["b"]))
		if a["owner"] != b["owner"]:
			edges.append(pair)
	return edges


## Supply, as the tick engine understands it: an edge between two same-owner
## nodes that are both connected to that side's sources. Cut a depot and this
## thins out, which is the siege play P1.2 promises made visible.
static func supply_edges(state: Dictionary) -> Array:
	var edges: Array = []
	var supplied: Dictionary = {
		&"player": WarSim.supplied_set(state, &"player"),
		&"enemy": WarSim.supplied_set(state, &"enemy"),
	}
	for pair: Dictionary in adjacent_pairs(state):
		var a: Dictionary = WarSim.node_by_id(state, int(pair["a"]))
		var b: Dictionary = WarSim.node_by_id(state, int(pair["b"]))
		if a["owner"] != b["owner"]:
			continue
		var side: StringName = a["owner"]
		if supplied[side].has(int(a["id"])) and supplied[side].has(int(b["id"])):
			edges.append({"a": int(pair["a"]), "b": int(pair["b"]), "side": side})
	return edges


## node id → why it cannot be flown, `REASON_NONE` for the ones that can.
##
## Composing every node costs a little (the composer is pure and cheap, and this
## runs on build and after a tick, never per frame) and it is the only honest way
## to answer C.q3: whether a node is flyable is a property of the SPEC it
## produces, not of a list of node types kept in sync by hand.
static func refusals(state: Dictionary, config: WarConfig) -> Dictionary:
	var reasons: Dictionary = {}
	var over: bool = state["winner"] != &""
	var in_range: Dictionary = WarSim.strike_range(state, config)
	for node: Dictionary in state["nodes"]:
		var id: int = int(node["id"])
		if over:
			reasons[id] = REASON_WAR_OVER
		elif node["owner"] == &"player":
			reasons[id] = REASON_FRIENDLY
		elif not in_range.has(id):
			reasons[id] = REASON_RANGE
		elif not SortieComposer.is_slice_ready(
				SortieComposer.compose(node, state, config)):
			reasons[id] = REASON_ARCHETYPE
		else:
			reasons[id] = REASON_NONE
	return reasons


static func flyable_ids(state: Dictionary, config: WarConfig) -> Array:
	var ids: Array = []
	var reasons: Dictionary = refusals(state, config)
	for id: int in reasons:
		if reasons[id] == REASON_NONE:
			ids.append(id)
	ids.sort()
	return ids


## The sentence the card shows. Separate from the reason id on purpose: the
## wording is presentation and changes freely, the id is what a check asserts.
static func refusal_line(reason: StringName, config: WarConfig,
		archetype: StringName = &"") -> String:
	match reason:
		REASON_FRIENDLY:
			return "YOUR GROUND - no sortie to fly here"
		REASON_RANGE:
			return "OUT OF RANGE - no friendly airbase within %d hops" \
					% int(config.sortie_range_hops)
		REASON_ARCHETYPE:
			# C.q3: stated plainly rather than hidden. Half a theater composes
			# correctly and cannot be instantiated yet, and a map that concealed
			# that would make opening the other archetypes look like new
			# territory instead of unlocking ground that was always here.
			return "NO SORTIE AVAILABLE - %s is not flyable yet" \
					% String(archetype).to_upper()
		REASON_WAR_OVER:
			return "THE WAR IS OVER"
	return ""
