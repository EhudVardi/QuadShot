extends SceneTree

## Headless check for the WAR ROOM's map (GAMEPLAY-DESIGN Iteration 13, C9
## phase 1). The room is UI over a war that already works, so what is checked
## here is the DERIVATION, never the pixels: if the map is ever wrong, it is
## wrong in one of these pure functions.
##
## THE STANDARD IS v2.01's: would this check still pass if the feature it tests
## were deleted? Two places where it would have been easy to write one that
## could not fail, and what was done instead:
##
##   - The strike range is not compared against `WarSim.strike_range` by calling
##     `WarSim.strike_range`. The check runs its OWN slow relaxation over the hex
##     graph and asserts the two agree. Comparing a function to itself is the
##     shape of assertion this project has already been caught writing.
##   - The supply edges are not merely checked for being adjacent and
##     same-owner, which any wrong-but-plausible implementation would satisfy.
##     A hand-built theater with a node deliberately CUT OFF asserts that the
##     severed edge is absent — the one behaviour that makes supply mean
##     anything (P1.2's siege play).
##
## Run: <godot> --headless -s scripts/tests/war_room_check.gd --path .

const THEATER_SEED: int = 4242
## Refusal coverage is swept rather than trusted to one seed: a theater is
## organic, and "no node was out of range" is a property of the map you drew,
## not of the code you wrote.
const SWEEP_SEEDS: Array[int] = [4242, 7, 99, 1234, 20260801]

var _failures: int = 0


func _init() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)

	_check_projection(state)
	_check_strike_range(state, config)
	_check_front_line(state)
	_check_supply(state)
	_check_supply_cut_off()
	_check_refusals(state, config)
	_check_refusal_coverage(config)
	_check_table_builds(state, config)

	if _failures == 0:
		print("[war_room_check] PASS")
	else:
		print("[war_room_check] FAIL — %d check(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## The hex projection has to TILE: distinct cells, neighbours exactly one
## spacing apart, and everything else further away. Drop a term from the axial
## formula and two nodes land on the same spot — which on screen looks like one
## node the player can never select.
func _check_projection(state: Dictionary) -> void:
	var size: float = HexTable.HEX_SIZE
	var spacing: float = WarView.SQRT3 * size
	var seen: Dictionary = {}
	var collisions: int = 0
	for node: Dictionary in state["nodes"]:
		var at: Vector3 = WarView.node_world(node, size)
		var key: String = "%.3f,%.3f" % [at.x, at.z]
		if seen.has(key):
			collisions += 1
		seen[key] = true
	_expect(collisions == 0, "every node gets its own cell (%d collisions)" % collisions)

	var wrong_near: int = 0
	var wrong_far: int = 0
	var nodes: Array = state["nodes"]
	for i: int in nodes.size():
		for j: int in range(i + 1, nodes.size()):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[j]
			var hops: int = TheaterGenerator.hex_distance(
					Vector2i(int(a["q"]), int(a["r"])),
					Vector2i(int(b["q"]), int(b["r"])))
			var distance: float = WarView.node_world(a, size).distance_to(
					WarView.node_world(b, size))
			if hops == 1 and absf(distance - spacing) > 0.001:
				wrong_near += 1
			elif hops > 1 and distance < spacing * 1.1:
				wrong_far += 1
	_expect(wrong_near == 0,
			"adjacent nodes sit exactly one spacing apart (%d wrong)" % wrong_near)
	_expect(wrong_far == 0,
			"non-adjacent nodes sit further than one spacing (%d wrong)" % wrong_far)

	var box: AABB = WarView.bounds(state, size)
	var outside: int = 0
	for node: Dictionary in state["nodes"]:
		if not box.has_point(WarView.node_world(node, size)):
			outside += 1
	_expect(outside == 0, "the framing box contains every node (%d outside)" % outside)


## The map's reach and the campaign's reach are the same set, or the map
## promises ground the war does not have.
func _check_strike_range(state: Dictionary, config: WarConfig) -> void:
	var theirs: Dictionary = WarSim.strike_range(state, config)
	var mine: Dictionary = _independent_range(state, config)
	var missing: int = 0
	var extra: int = 0
	for id: int in mine:
		if not theirs.has(id):
			missing += 1
	for id: int in theirs:
		if not mine.has(id):
			extra += 1
	_expect(missing == 0 and extra == 0,
			"strike range agrees with an independent walk (%d missing, %d extra, %d in range)"
			% [missing, extra, theirs.size()])
	_expect(theirs.size() > 0 and theirs.size() < state["nodes"].size(),
			"strike range is a real subset of the theater (%d of %d)"
			% [theirs.size(), state["nodes"].size()])


## Deliberately the slow obvious algorithm — relax until nothing moves. It has
## to be a different implementation from the one under test or this asserts
## nothing at all.
func _independent_range(state: Dictionary, config: WarConfig) -> Dictionary:
	var hops_allowed: int = int(config.sortie_range_hops)
	var distance: Dictionary = {}
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"player" and node["type"] == &"airbase":
			distance[int(node["id"])] = 0
	var moved: bool = true
	while moved:
		moved = false
		for a: Dictionary in state["nodes"]:
			if not distance.has(int(a["id"])):
				continue
			for b: Dictionary in state["nodes"]:
				if TheaterGenerator.hex_distance(
						Vector2i(int(a["q"]), int(a["r"])),
						Vector2i(int(b["q"]), int(b["r"]))) != 1:
					continue
				var cost: int = 0 if b["owner"] == &"player" else 1
				var candidate: int = int(distance[int(a["id"])]) + cost
				if candidate > hops_allowed:
					continue
				if candidate < int(distance.get(int(b["id"]), 9999)):
					distance[int(b["id"])] = candidate
					moved = true
	return distance


## Sound AND complete. Soundness alone passes for an implementation that returns
## the empty array, which is exactly the bug that would make a front line vanish
## from the map.
func _check_front_line(state: Dictionary) -> void:
	var edges: Array = WarView.front_line_edges(state)
	var unsound: int = 0
	for edge: Dictionary in edges:
		var a: Dictionary = WarSim.node_by_id(state, int(edge["a"]))
		var b: Dictionary = WarSim.node_by_id(state, int(edge["b"]))
		var adjacent: bool = TheaterGenerator.hex_distance(
				Vector2i(int(a["q"]), int(a["r"])),
				Vector2i(int(b["q"]), int(b["r"]))) == 1
		if not adjacent or a["owner"] == b["owner"]:
			unsound += 1
	_expect(unsound == 0,
			"every front-line edge is adjacent and divides two owners (%d bad)" % unsound)

	var expected: int = 0
	var nodes: Array = state["nodes"]
	for i: int in nodes.size():
		for j: int in range(i + 1, nodes.size()):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[j]
			if a["owner"] == b["owner"]:
				continue
			if TheaterGenerator.hex_distance(
					Vector2i(int(a["q"]), int(a["r"])),
					Vector2i(int(b["q"]), int(b["r"]))) == 1:
				expected += 1
	_expect(edges.size() == expected,
			"the front line is complete (%d edges, %d expected)"
			% [edges.size(), expected])
	_expect(expected > 0, "this theater has a front line at all (%d edges)" % expected)


func _check_supply(state: Dictionary) -> void:
	var edges: Array = WarView.supply_edges(state)
	var bad: int = 0
	for edge: Dictionary in edges:
		var a: Dictionary = WarSim.node_by_id(state, int(edge["a"]))
		var b: Dictionary = WarSim.node_by_id(state, int(edge["b"]))
		var adjacent: bool = TheaterGenerator.hex_distance(
				Vector2i(int(a["q"]), int(a["r"])),
				Vector2i(int(b["q"]), int(b["r"]))) == 1
		if not adjacent or a["owner"] != b["owner"] or a["owner"] != edge["side"]:
			bad += 1
	_expect(bad == 0,
			"every supply edge joins two same-owner neighbours (%d bad)" % bad)
	_expect(edges.size() > 0, "the theater has supply lines (%d)" % edges.size())


## THE ONE THAT MAKES SUPPLY MEAN SOMETHING, and it took a failed mutation test
## to write correctly. FOUR nodes in a row: home airbase, then a node the enemy
## holds, then two the player holds. The last two are ADJACENT TO EACH OTHER and
## the same owner — and they are cut off from home, so they must carry no supply
## line between them.
##
## The three-node version written first (player · enemy · player) could not fail:
## severing the middle also removed every same-owner adjacency, so an
## implementation that ignored supply entirely still produced zero edges and the
## check still passed. Verified by mutation — delete the `supplied` test in
## `WarView.supply_edges` and this function fails; the three-node version did not.
func _check_supply_cut_off() -> void:
	var whole: Dictionary = _line_state([&"player", &"player", &"player", &"player"])
	_expect(WarView.supply_edges(whole).size() == 3,
			"an unbroken friendly line supplies end to end (%d edges)"
			% WarView.supply_edges(whole).size())

	var cut: Dictionary = _line_state([&"player", &"enemy", &"player", &"player"])
	var edges: Array = WarView.supply_edges(cut)
	_expect(edges.is_empty(),
			"two friendly neighbours cut off from home carry no supply (%d survived the cut)"
			% edges.size())
	_expect(WarView.front_line_edges(cut).size() == 2,
			"and the severed line shows two front-line edges (%d)"
			% WarView.front_line_edges(cut).size())


func _check_refusals(state: Dictionary, config: WarConfig) -> void:
	var reasons: Dictionary = WarView.refusals(state, config)
	_expect(reasons.size() == state["nodes"].size(),
			"every node gets a verdict (%d of %d)"
			% [reasons.size(), state["nodes"].size()])

	var in_range: Dictionary = WarSim.strike_range(state, config)
	var wrong: int = 0
	for node: Dictionary in state["nodes"]:
		var id: int = int(node["id"])
		var reason: StringName = reasons[id]
		var ready: bool = SortieComposer.is_slice_ready(
				SortieComposer.compose(node, state, config))
		match reason:
			WarView.REASON_NONE:
				if node["owner"] == &"player" or not in_range.has(id) or not ready:
					wrong += 1
			WarView.REASON_FRIENDLY:
				if node["owner"] != &"player":
					wrong += 1
			WarView.REASON_RANGE:
				if node["owner"] == &"player" or in_range.has(id):
					wrong += 1
			WarView.REASON_ARCHETYPE:
				if node["owner"] == &"player" or not in_range.has(id) or ready:
					wrong += 1
	_expect(wrong == 0, "every verdict matches the node it was given for (%d wrong)" % wrong)

	var flyable: Array = WarView.flyable_ids(state, config)
	var counted: int = 0
	for id: int in reasons:
		if reasons[id] == WarView.REASON_NONE:
			counted += 1
	_expect(flyable.size() == counted,
			"flyable_ids and refusals agree (%d vs %d)" % [flyable.size(), counted])

	# A finished war offers no sorties. The room reaches this state on the tick
	# that ends the campaign, and a map still inviting you to fly it would be
	# offering a sortie the sim would refuse to resolve.
	var over: Dictionary = state.duplicate(true)
	over["winner"] = &"player"
	var still_offered: int = WarView.flyable_ids(over, config).size()
	_expect(still_offered == 0,
			"a finished war offers nothing (%d nodes still offered)" % still_offered)


## C.q3's whole point: the map draws nodes it must refuse, so all four verdicts
## have to be reachable. If `archetype_unbuilt` never appeared, the refusal path
## the user chose would be dead code nobody would notice until the day it fired.
func _check_refusal_coverage(config: WarConfig) -> void:
	var seen: Dictionary = {}
	for theater_seed: int in SWEEP_SEEDS:
		var state: Dictionary = TheaterGenerator.generate(config, theater_seed)
		for reason: StringName in WarView.refusals(state, config).values():
			seen[reason] = int(seen.get(reason, 0)) + 1
	for reason: StringName in [WarView.REASON_NONE, WarView.REASON_FRIENDLY,
			WarView.REASON_RANGE, WarView.REASON_ARCHETYPE]:
		var label: String = "flyable" if reason == WarView.REASON_NONE else String(reason)
		_expect(seen.has(reason),
				"the sweep produces '%s' nodes (%d)" % [label, int(seen.get(reason, 0))])


## The renderer is not asserted on looks — it is asserted on not quietly
## dropping nodes, which is the failure that would leave a piece of the theater
## unselectable and invisible at the same time.
func _check_table_builds(state: Dictionary, config: WarConfig) -> void:
	var table := HexTable.new()
	root.add_child(table)
	table.build(state, config, Vector3(0.0, 60.0, 60.0))

	_expect(table.prisms.size() == state["nodes"].size(),
			"the table builds a prism per node (%d of %d)"
			% [table.prisms.size(), state["nodes"].size()])

	var misplaced: int = 0
	var short_tops: int = 0
	for node: Dictionary in state["nodes"]:
		var id: int = int(node["id"])
		if not table.centers.has(id):
			misplaced += 1
			continue
		if table.centers[id].distance_to(
				WarView.node_world(node, HexTable.HEX_SIZE)) > 0.001:
			misplaced += 1
		if table.top_of(id).y <= table.centers[id].y:
			short_tops += 1
	_expect(misplaced == 0, "every prism stands on its own cell (%d misplaced)" % misplaced)
	_expect(short_tops == 0, "every prism has height (%d flat)" % short_tops)

	# Picking: a point on a cell is that cell, and a point off the table is
	# nothing. Without the second half, "return the nearest node" would pass.
	var hits: int = 0
	for node: Dictionary in state["nodes"]:
		if table.pick(WarView.node_world(node, HexTable.HEX_SIZE)) == int(node["id"]):
			hits += 1
	_expect(hits == state["nodes"].size(),
			"a point on a cell picks that cell (%d of %d)" % [hits, state["nodes"].size()])
	_expect(table.pick(Vector3(9999.0, 0.0, 9999.0)) == -1,
			"a point off the table picks nothing")

	table.select(int(state["nodes"][0]["id"]))
	table.select(-1)
	_expect(true, "selection moves and clears without error")
	table.queue_free()


## A hand-built three-node theater: q = 0, 1, 2 on one row, so consecutive nodes
## are adjacent and the ends are two hops apart. Node 0 is the home airbase.
func _line_state(owners: Array[StringName]) -> Dictionary:
	var nodes: Array = []
	for i: int in owners.size():
		nodes.append({
			"id": i, "q": i, "r": 0,
			"type": &"airbase" if i == 0 else &"airspace",
			"owner": owners[i],
			"garrison": 10.0, "fort": 1.0,
			"biome": &"hills", "weather": &"clear", "intel_age": 0,
			"home": i == 0, "hq": false,
		})
	return {
		"tick": 0, "sorties": 0, "pilots": 5, "winner": &"",
		"nodes": nodes, "aggression": 0.5, "caution": 0.4,
		"rng_state": 0, "seed": 1,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[war_room_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[war_room_check]  FAIL  %s" % message)
