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
var _room: Node


## Everything except the last sub-check is pure arithmetic and runs here. The
## scene-level one cannot: a node's `_ready` does not run synchronously on
## `add_child` from a `-s` script's `_init`, so asserting straight afterwards
## reads a room that has not been built yet.
##
## That is not a hypothetical - it is what the first version did, and it failed
## in the worst available way: the assertions ran early AND the teardown cleared
## `WarLaunch` before `_ready` saw it, so the room fell back to `persist = true`
## and opened the real `user://war.save`. A test that quietly reaches for the
## player's campaign is a bug regardless of what it concludes.
func _initialize() -> void:
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
	_check_card_fog(state, config)
	_check_forecast(config)
	_check_debrief(config)
	_check_no_pilots(state, config)
	_check_menu_leaves()
	_check_diff(config)
	_check_hangar()
	_open_the_room(config)
	process_frame.connect(_probe_room)


func _probe_room() -> void:
	if _room == null or not _room.is_node_ready():
		return
	process_frame.disconnect(_probe_room)
	_check_the_loop_closed()
	_finish()


func _finish() -> void:
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


## The verdicts a real theater produces, and they must all be reachable or the
## refusal path is dead code nobody notices until the day it fires.
##
## `archetype_unbuilt` DROPPED OUT of this sweep on 2026-08-01, when the other
## five archetypes opened and every node type became flyable. That does not make
## the refusal dead — `SLICE_ARCHETYPES` is data, and it guards the next
## archetype somebody adds to `ARCHETYPES` without teaching the runner to build
## it — so it moved to a DIRECT test below rather than being deleted.
##
## Contrast with the wave director's escort guard, which was deleted in v2.02
## for looking similar: that one could never fire because the backbone above it
## made it unreachable in code. This one is one data edit away from firing.
func _check_refusal_coverage(config: WarConfig) -> void:
	var seen: Dictionary = {}
	for theater_seed: int in SWEEP_SEEDS:
		var state: Dictionary = TheaterGenerator.generate(config, theater_seed)
		for reason: StringName in WarView.refusals(state, config).values():
			seen[reason] = int(seen.get(reason, 0)) + 1
	for reason: StringName in [WarView.REASON_NONE, WarView.REASON_FRIENDLY,
			WarView.REASON_RANGE]:
		var label: String = "flyable" if reason == WarView.REASON_NONE else String(reason)
		_expect(seen.has(reason),
				"the sweep produces '%s' nodes (%d)" % [label, int(seen.get(reason, 0))])
	_expect(not seen.has(WarView.REASON_ARCHETYPE),
			"NO node type is unflyable any more (%d still refused)"
			% int(seen.get(WarView.REASON_ARCHETYPE, 0)))

	# The guard itself, tested where it lives rather than through a theater that
	# no longer produces it.
	var unbuildable: PackedStringArray = []
	for node_type: StringName in SortieComposer.ARCHETYPES:
		var archetype: StringName = SortieComposer.ARCHETYPES[node_type]["archetype"]
		if not SortieComposer.is_slice_ready({"archetype": archetype}):
			unbuildable.append("%s -> %s" % [node_type, archetype])
	_expect(unbuildable.is_empty(),
			"every node type composes to an archetype the runner can build (%s)"
			% ", ".join(unbuildable))
	_expect(not SortieComposer.is_slice_ready({"archetype": &"not_an_archetype"}),
			"and the slice guard still refuses an archetype nobody built")
	_check_hq_shield(config)


## P1.5 IS THE ARC OF THE CAMPAIGN, so the map has to enforce it: the HQ is
## shielded until the command network is broken. The tick engine has always
## enforced this for its own proxy sortie and nothing enforced it for the player,
## which was invisible while the Raid was an archetype nobody could fly — and
## became a way to skip the entire campaign the moment it opened.
##
## Tested from both sides, because "always refuse the HQ" would pass the first
## assertion and quietly make the war unwinnable.
func _check_hq_shield(config: WarConfig) -> void:
	# A PURPOSE-BUILT theater, because a generated one puts the HQ at the far end
	# of the map: the first version of this check read `out_of_range` on both
	# sides and passed without the shield ever being consulted. The HQ sits next
	# door to the player's airbase here, so the SHIELD is the only thing that can
	# refuse it and the assertion has somewhere to fail.
	var state: Dictionary = _hq_state()
	var alive: int = WarSim.command_posts_alive(state)
	_expect(alive > int(config.hq_unlock_command_posts),
			"the fixture has a live command network (%d posts)" % alive)

	var shielded: StringName = WarView.refusals(state, config).get(1)
	_expect(shielded == WarView.REASON_HQ_LOCKED,
			"an intact command network shields the HQ (got '%s')" % shielded)

	# Break the network and the shield must LIFT, or the campaign has no ending
	# and "always refuse the HQ" would have passed the assertion above.
	for node: Dictionary in state["nodes"]:
		if node["type"] == &"command":
			node["garrison"] = 0.0
	_expect(WarSim.command_posts_alive(state) == 0, "the command network can be broken")
	var after: StringName = WarView.refusals(state, config).get(1)
	_expect(after == WarView.REASON_NONE,
			"and a broken network opens the raid (got '%s')" % after)


## Player airbase, the enemy HQ next to it, and two enemy command posts further
## out. Four nodes in a row: 0 and 1 adjacent, so the HQ is one hop from a
## friendly airbase and comfortably in strike range.
func _hq_state() -> Dictionary:
	var nodes: Array = []
	var types: Array[StringName] = [&"airbase", &"hq", &"command", &"command"]
	for i: int in types.size():
		nodes.append({
			"id": i, "q": i, "r": 0, "type": types[i],
			"owner": &"player" if i == 0 else &"enemy",
			"garrison": 10.0, "fort": 1.0,
			"biome": &"hills", "weather": &"clear", "intel_age": 0,
			"home": i == 0, "hq": i == 1,
		})
	return {
		"tick": 0, "sorties": 0, "pilots": 5, "winner": &"",
		"nodes": nodes, "aggression": 0.5, "caution": 0.4,
		"rng_state": 0, "seed": 1,
	}


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


## THE CARD'S ONLY REAL BUG IS INVISIBLE, so it gets the check that can see it.
##
## A card that leaks the truth through P1.3's fog still looks perfect on screen —
## it just quietly deletes the surprise the whole intel system exists to produce.
## So: take ONE node, show it at three intel ages, and assert on the TEXT.
##
## The load-bearing assertion is the negative one. At `intel_age` 99 no unit type
## name may appear anywhere in the card. Delete the fog from `card_lines` and
## that fails immediately, while every "does it show the right tier" assertion
## would keep passing.
func _check_card_fog(state: Dictionary, config: WarConfig) -> void:
	var target: Dictionary = {}
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"enemy" and float(node["garrison"]) > 8.0:
			target = node
			break
	if target.is_empty():
		_expect(false, "the theater has an enemy node to inspect")
		return

	var fresh: String = "\n".join(_card_at_age(target, state, config, 0))
	var mid: String = "\n".join(_card_at_age(target, state, config, 3))
	var stale: String = "\n".join(_card_at_age(target, state, config, 99))

	_expect(fresh.contains("EXACT"), "fresh intel resolves exact units")
	_expect(mid.contains("FAMILIES"), "week-old intel resolves families only")
	_expect(stale.contains("STRENGTH ONLY"),
			"stale intel resolves nothing but the abstract strength")

	var named_when_fresh: int = 0
	var named_when_stale: int = 0
	for type_id: StringName in WarManifest.ROSTER:
		if fresh.contains(String(type_id)):
			named_when_fresh += 1
		if stale.contains(String(type_id)):
			named_when_stale += 1
	_expect(named_when_fresh > 0,
			"a fresh card names the units that are there (%d types)" % named_when_fresh)
	_expect(named_when_stale == 0,
			"A STALE CARD NAMES NO UNIT AT ALL (%d types leaked)" % named_when_stale)
	# Families are a coarser vocabulary than types on purpose; if a family name
	# ever equalled a type name the negative assertion above would go blind.
	var leaked_by_family: int = 0
	for type_id: StringName in WarManifest.ROSTER:
		if mid.contains(String(type_id)):
			leaked_by_family += 1
	_expect(leaked_by_family == 0,
			"and a families card names no type either (%d leaked)" % leaked_by_family)

	# Your own ground is not intel, so it reports plainly and offers no sortie.
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"player":
			continue
		var own: String = "\n".join(WarView.card_lines(node, state, config,
				WarView.REASON_FRIENDLY))
		_expect(own.contains("garrison") and not own.contains("INTEL"),
				"a friendly node reports its own garrison rather than an intel estimate")
		break


func _card_at_age(node: Dictionary, state: Dictionary, config: WarConfig,
		age: int) -> PackedStringArray:
	var copy: Dictionary = state.duplicate(true)
	var target: Dictionary = WarSim.node_by_id(copy, int(node["id"]))
	target["intel_age"] = age
	return WarView.card_lines(target, copy, config, WarView.REASON_NONE)


## THE FORECAST IS A PROMISE ABOUT THE FUTURE, so it is checked against the
## future actually happening (C.q4). Forecast every node, run a real tick, and
## compare. This is the assertion that would catch the weather seed drifting out
## of step with the tick engine — which is a silent failure, because a wrong
## forecast still looks like weather.
func _check_forecast(config: WarConfig) -> void:
	var wrong: int = 0
	var changes: int = 0
	for theater_seed: int in SWEEP_SEEDS:
		var state: Dictionary = TheaterGenerator.generate(config, theater_seed)
		# Several ticks in, so the check is not resting on tick 0 being special.
		for i: int in 3:
			WarSim.tick(state, config)
		var forecast: Dictionary = {}
		for node: Dictionary in state["nodes"]:
			forecast[int(node["id"])] = WarSim.weather_forecast(node, state)
			if forecast[int(node["id"])] != node["weather"]:
				changes += 1
		WarSim.tick(state, config)
		for node: Dictionary in state["nodes"]:
			if node["weather"] != forecast[int(node["id"])]:
				wrong += 1
	_expect(wrong == 0, "every forecast is what the next tick actually did (%d wrong)" % wrong)
	# A forecast that always says "same as today" would satisfy the above and be
	# useless, so the sweep has to contain real changes to have proved anything.
	_expect(changes > 0,
			"the sweep contains weather that actually changes (%d forecast changes)" % changes)

	# Reading the map must not move the war (the manifest's rule, applied to
	# weather): forecasting is a pure function, so doing it a hundred times
	# changes nothing about the war it was asked about.
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var before: String = var_to_str(state)
	for i: int in 100:
		for node: Dictionary in state["nodes"]:
			WarSim.weather_forecast(node, state)
	_expect(var_to_str(state) == before, "forecasting does not touch the war state")


## THE LOOP, NOW THAT THE ROOM OWNS IT (C.q2). `WarDebrief.resolve` is where a
## flown sortie becomes war, so what is checked is the arithmetic that can go
## wrong silently: a pilot counted twice, a war ticked by a result it could not
## apply, or a death that stopped denting.
##
## The result is built by a REAL `SortieRunner`, not by this file. That is the
## v2.01 lesson applied to a new joint: `resolve` reads every field through
## `.get()` with a default, so a rename in `result()` would produce no error and
## a war that silently stopped noticing the player.
func _check_debrief(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var node: Dictionary = {}
	for candidate: Dictionary in state["nodes"]:
		if candidate["owner"] == &"enemy":
			node = candidate
			break

	var runner := SortieRunner.new()
	runner.start({
		"version": 1, "seed": 7, "truth": true, "node_id": int(node["id"]),
		"archetype": &"dogfight", "objective": &"clear_airspace",
		"objective_assets": 0, "pads": 0, "triggers": [],
		"layers": {&"outer": [], &"mid": [], &"inner": []},
	})
	runner._on_points_scored(100.0, &"raider")
	runner.phase = SortieRunner.Phase.EGRESS
	runner.force_egress()
	var real: Dictionary = runner.result()
	runner.free()

	var missing: Array[String] = []
	for key: String in ["node_id", "outcome", "kills", "objectives_destroyed",
			"objective_assets", "egressed", "pilot_lost", "dent"]:
		if not real.has(key):
			missing.append(key)
	_expect(missing.is_empty(),
			"a real runner result carries every field the debrief reads (missing %s)"
			% str(missing))

	var pilots_before: int = int(state["pilots"])
	var tick_before: int = int(state["tick"])
	var debrief: Dictionary = WarDebrief.resolve(state, config, real)
	_expect(not debrief.is_empty(), "the room resolves a runner's own result")
	_expect(int(state["tick"]) == tick_before + 1,
			"resolving advances the war exactly one tick (%d -> %d)"
			% [tick_before, int(state["tick"])])
	_expect(int(state["pilots"]) == pilots_before,
			"a surviving pilot stays on the roster (%d)" % int(state["pilots"]))
	# READ THE DENT OFF THE SUMMARY, NOT OFF THE STATE AFTERWARDS. `resolve`
	# ticks after it applies, and a tick runs production and reinforcement - so a
	# node can finish the turn STRONGER than it started and still have been hit
	# hard. Comparing the post-tick garrison to the pre-sortie one measures the
	# war's whole turn and calls it your sortie; this assertion caught itself
	# doing exactly that on its first run.
	var summary: Dictionary = debrief["summary"]
	_expect(float(summary["dent"]) > 0.0,
			"a survived sortie dents the node it named (dent %.2f)"
			% float(summary["dent"]))
	_expect(float(summary["garrison_after"]) < float(summary["garrison_before"]),
			"and the dent lands before the war takes its turn (%.2f -> %.2f)"
			% [float(summary["garrison_before"]), float(summary["garrison_after"])])
	_expect(not "\n".join(WarDebrief.lines(debrief)).is_empty(),
			"the debrief renders to text")

	# A DEATH STILL DENTS (P2.q4), and costs exactly one pilot. "Exactly" is the
	# assertion: apply_sortie decrements and so could a room that also counted.
	var dead_state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var roster_before: int = int(dead_state["pilots"])
	var lost: Dictionary = real.duplicate(true)
	lost["pilot_lost"] = true
	lost["outcome"] = &"lost"
	var dead_debrief: Dictionary = WarDebrief.resolve(dead_state, config, lost)
	_expect(int(dead_state["pilots"]) == roster_before - 1,
			"a death costs exactly one pilot (%d -> %d)"
			% [roster_before, int(dead_state["pilots"])])
	_expect(float(dead_debrief["summary"]["dent"]) > 0.0,
			"and a dead pilot's kills still dent the node (dent %.2f)"
			% float(dead_debrief["summary"]["dent"]))
	_expect("\n".join(WarDebrief.lines(dead_debrief)).contains("PILOT LOST"),
			"and the debrief says so")

	# A RESULT THE WAR CANNOT APPLY MUST NOT MOVE THE WAR. Ticking first and
	# checking second would look identical in every other assertion here.
	var spare: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var spare_tick: int = int(spare["tick"])
	var bogus: Dictionary = real.duplicate(true)
	bogus["node_id"] = 9999
	_expect(WarDebrief.resolve(spare, config, bogus).is_empty(),
			"a result naming no node resolves to nothing")
	_expect(int(spare["tick"]) == spare_tick,
			"AND DOES NOT TICK THE WAR (%d -> %d)" % [spare_tick, int(spare["tick"])])


## P1.5: your last pilot dying ends your road, not the war. The room must stop
## offering sorties, and the war-sim deliberately does not declare a winner for
## it, so nothing else in the project would notice.
func _check_no_pilots(state: Dictionary, config: WarConfig) -> void:
	var grounded: Dictionary = state.duplicate(true)
	grounded["pilots"] = 0
	_expect(WarView.flyable_ids(grounded, config).is_empty(),
			"a grounded roster offers no sorties (%d offered)"
			% WarView.flyable_ids(grounded, config).size())
	var reasons: Dictionary = WarView.refusals(grounded, config)
	_expect(reasons[int(state["nodes"][0]["id"])] == WarView.REASON_NO_PILOTS,
			"and says why")


## C.q5's leaf, and the class of bug it belongs to: a menu entry pointing at a
## scene that does not exist fails only when somebody flies through that window.
func _check_menu_leaves() -> void:
	var tower: Dictionary = (load("res://scripts/menu_tower.gd") as GDScript) \
			.get_script_constant_map()
	var scenes: Dictionary = tower.get("LEAF_SCENES", {})
	var broken: PackedStringArray = []
	for leaf: StringName in scenes:
		if not ResourceLoader.exists(String(scenes[leaf])):
			broken.append(String(leaf))
	_expect(broken.is_empty(),
			"every menu leaf resolves to a real scene (broken: %s)" % ", ".join(broken))
	_expect(scenes.has(&"campaign"),
			"the menu has a door to the war room")


## THE ONE ASSERTION THAT PROVES THE CAMPAIGN IS A LOOP, and it needs the real
## scene rather than the pure layer: every other check here would pass with the
## room and the sortie never having been introduced.
##
## It stands the room up with a flown result waiting in `WarLaunch`, exactly as a
## returning sortie leaves it, and asserts the room ate it: the debrief is on
## screen and the handoff is empty. `persist` is false throughout, so this cannot
## touch a real campaign - the room is READ-ONLY unless it resolves something,
## and it must not resolve to disk in a test.
## THE TICK ANIMATION IS A DIFF (C8), so the diff is what gets asserted: it must
## name exactly what moved and nothing else.
##
## Both halves matter and for different reasons. "Names nothing when nothing
## changed" is what keeps the map from twitching every turn; "names a planted
## change" is what proves it is looking at all. An implementation returning `[]`
## unconditionally passes the first and fails the second.
func _check_diff(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	_expect(WarDiff.between(state, state).is_empty(),
			"a war compared with itself has not moved (%d events)"
			% WarDiff.between(state, state).size())

	# One planted capture, and nothing else touched.
	var flipped: Dictionary = state.duplicate(true)
	var victim: int = -1
	for node: Dictionary in flipped["nodes"]:
		if node["owner"] == &"enemy":
			node["owner"] = &"player"
			victim = int(node["id"])
			break
	var events: Array = WarDiff.between(state, flipped)
	_expect(events.size() == 1,
			"one flipped owner produces exactly one event (%d)" % events.size())
	if events.size() == 1:
		_expect(int(events[0]["node_id"]) == victim
				and events[0]["kind"] == WarDiff.KIND_CAPTURED,
				"and it names the node that flipped, as a capture")

	# Garrison movement is reported by DIRECTION, and movement under the epsilon
	# is deliberately not reported at all - thirty rounding-sized twitches read as
	# noise rather than as a war moving.
	var nudged: Dictionary = state.duplicate(true)
	var big: int = int(nudged["nodes"][0]["id"])
	nudged["nodes"][0]["garrison"] = float(state["nodes"][0]["garrison"]) + 5.0
	nudged["nodes"][1]["garrison"] = float(state["nodes"][1]["garrison"]) \
			+ WarDiff.GARRISON_EPSILON * 0.5
	var moves: Array = WarDiff.between(state, nudged)
	_expect(moves.size() == 1, "a sub-epsilon nudge is not an event (%d)" % moves.size())
	if moves.size() == 1:
		_expect(int(moves[0]["node_id"]) == big
				and moves[0]["kind"] == WarDiff.KIND_REINFORCED,
				"and a real gain reads as reinforcement")

	# A REAL TICK, not a hand-built pair: the diff has to survive whatever the
	# war actually does, including the case where it does very little.
	var live: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var before: Dictionary = live.duplicate(true)
	for i: int in 5:
		WarSim.tick(live, config)
	var real: Array = WarDiff.between(before, live)
	_expect(not real.is_empty(),
			"five ticks of a real war produce events (%d)" % real.size())
	var wrong: int = 0
	for event: Dictionary in real:
		var was: Dictionary = WarSim.node_by_id(before, int(event["node_id"]))
		var now: Dictionary = WarSim.node_by_id(live, int(event["node_id"]))
		var changed: bool = was["owner"] != now["owner"] \
				or absf(float(now["garrison"]) - float(was["garrison"])) \
						> WarDiff.GARRISON_EPSILON
		if not changed:
			wrong += 1
	_expect(wrong == 0, "every event names a node that really moved (%d spurious)" % wrong)
	# Determinism reaching the screen (F4): the same tick plays the same way.
	_expect(str(WarDiff.between(before, live)) == str(real),
			"and the event order is stable between calls")


## THE HANGAR, and the drift it is one list away from causing. The menu tower's
## frame tower and the war room's hangar are two hand-written lists of the same
## thing — which is precisely the shape of the bug that hid the falx and the
## screamer from the war for two weeks (v1.96). Two rosters nobody compares are
## always self-consistent.
func _check_hangar() -> void:
	var remembered: StringName = MenuLaunch.frame_id

	var broken: PackedStringArray = []
	for frame_id: StringName in Hangar.FRAMES:
		var frame: FrameConfig = Hangar.config_for(frame_id)
		if frame == null or frame.frame_id != frame_id:
			broken.append(String(frame_id))
	_expect(broken.is_empty(),
			"every hangar frame loads and knows its own id (broken: %s)"
			% ", ".join(broken))

	var tower: Dictionary = (load("res://scripts/menu_tower.gd") as GDScript) \
			.get_script_constant_map()
	var offered: Dictionary = {}
	for leaf: Dictionary in tower.get("FRAME_LEAVES", []):
		offered[String(leaf["leaf"]).trim_prefix("frame_")] = true
	var missing: PackedStringArray = []
	for frame_id: StringName in Hangar.FRAMES:
		if not offered.has(String(frame_id)):
			missing.append(String(frame_id))
	_expect(missing.is_empty() and offered.size() == Hangar.FRAMES.size(),
			"the hangar and the menu tower offer the same frames (%d vs %d, missing %s)"
			% [Hangar.FRAMES.size(), offered.size(), ", ".join(missing)])

	# The pick has to actually land on the static the SORTIE reads, or the room
	# offers a choice the fight ignores.
	MenuLaunch.frame_id = &""
	_expect(Hangar.selected() == Hangar.FRAMES[0],
			"an unset hangar defaults to a real frame rather than to nothing")
	var first: StringName = Hangar.selected()
	var second: StringName = Hangar.cycle()
	_expect(second != first, "cycling changes the airframe (%s -> %s)" % [first, second])
	_expect(MenuLaunch.frame_id == second,
			"and writes it where FlightController reads it")
	for i: int in Hangar.FRAMES.size():
		Hangar.cycle()
	_expect(Hangar.selected() == second, "cycling the whole list comes back around")

	MenuLaunch.frame_id = &"not_a_frame"
	_expect(Hangar.selected() in Hangar.FRAMES,
			"a junk frame id falls back to a real one rather than being flown")

	_expect(Hangar.roster_line(3).contains("3"), "the roster counts pilots")
	_expect(Hangar.roster_line(0).contains("none"), "and says when there are none")
	MenuLaunch.frame_id = remembered


func _open_the_room(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var target: int = int(WarView.flyable_ids(state, config)[0])

	var runner := SortieRunner.new()
	runner.start({
		"version": 1, "seed": 7, "truth": true, "node_id": target,
		"archetype": &"dogfight", "objective": &"clear_airspace",
		"objective_assets": 0, "pads": 0, "triggers": [],
		"layers": {&"outer": [], &"mid": [], &"inner": []},
	})
	runner._on_points_scored(100.0, &"raider")
	runner.phase = SortieRunner.Phase.EGRESS
	runner.force_egress()
	var result: Dictionary = runner.result()
	runner.free()

	# `persist` false all the way through, so the room generates its theater from
	# the seed and never opens or writes the player's save.
	WarLaunch.arm(target, THEATER_SEED, false)
	WarLaunch.flew = true
	WarLaunch.result = result

	_room = (load("res://scenes/war_room.tscn") as PackedScene).instantiate()
	root.add_child(_room)


func _check_the_loop_closed() -> void:
	var debrief: PanelContainer = _room.get_node(^"Ui/Debrief")
	var text: String = (_room.get_node(^"Ui/Debrief/Text") as Label).text
	_expect(debrief.visible, "the room shows a debrief for a sortie it was handed")
	_expect(text.contains("SORTIE"), "and the debrief names the outcome")
	_expect(not WarLaunch.flew and WarLaunch.result.is_empty(),
			"and the handoff is consumed, so the same sortie cannot be priced twice")
	_expect(not WarLaunch.from_room, "and the room is no longer in a launched state")

	_room.queue_free()
	WarLaunch.clear()


## A hand-built four-node theater: q = 0..3 on one row, so consecutive nodes are
## adjacent and the ends are three hops apart. Node 0 is the home airbase.
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
