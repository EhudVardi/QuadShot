extends SceneTree

## Headless check for the P2 composer (SortieComposer).
##
## The composer is the war↔fight joint, so what is asserted here is that the
## joint conserves and that its promises are actually wired:
##   - purity/determinism (F4) and no mutation of the war state,
##   - CONSERVATION: layers + triggers sum to exactly the node's manifest, so
##     "every kill dents the node" (P2.q4) is arithmetic rather than a wish
##     and reinforcements can never be free bodies,
##   - node type reaches the archetype (P2.2) and the capture rule agrees with
##     the tick engine (P1.q2),
##   - layering, triggers, pads, approach and dares behave as designed,
##   - the briefing/truth split is real and fog-driven (P2.1/P1.3),
##   - the spec is serializable (F4).
##
## It deliberately asserts NO difficulty scalar: H6 makes SDI a measurement,
## and a composer that graded its own output would make organic difficulty a
## hand-tuned knob. The check enforces that absence.
##
## Run: <godot> --headless -s scripts/tests/sortie_compose_check.gd --path .

const THEATER_SEED: int = 909

var _failures: int = 0


func _init() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)

	_check_purity(state, config)
	_check_conservation(state, config)
	_check_archetypes(state, config)
	_check_capture_rule(state, config)
	_check_layering(state, config)
	_check_triggers(state, config)
	_check_pads(state, config)
	_check_approach_and_dares(config)
	_check_no_authored_difficulty(state, config)
	_check_briefing_vs_truth(config)
	_check_serializable(state, config)
	_check_over_a_running_war(config)

	if _failures == 0:
		print("[sortie_compose_check] PASS")
	else:
		print("[sortie_compose_check] FAIL — %d check(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_purity(state: Dictionary, config: WarConfig) -> void:
	var node: Dictionary = _find(state, &"factory")
	var before: String = var_to_str(state)
	var first: Dictionary = SortieComposer.compose(node, state, config)
	var second: Dictionary = SortieComposer.compose(node, state, config)
	_expect(var_to_str(first) == var_to_str(second), "composition is deterministic")
	_expect(var_to_str(state) == before, "composing does not mutate the war state")
	_expect(int(first["seed"]) == SortieComposer.sortie_seed(node, state),
			"the spec carries its own reproducible seed")


## THE load-bearing invariant. Everything the sortie can field — placed layers
## plus every reserve that could still arrive — must equal the node's manifest
## exactly. Reserves come out of the garrison, never on top of it.
func _check_conservation(state: Dictionary, config: WarConfig) -> void:
	var escalation: float = WarSim.escalation(state, config)
	var worst: float = 0.0
	var checked: int = 0
	for node: Dictionary in state["nodes"]:
		var manifest: Array = WarManifest.project(node, int(state["seed"]), escalation)
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		var drift: float = absf(SortieComposer.total_strength(spec)
				- WarManifest.strength_of(manifest))
		worst = maxf(worst, drift)
		checked += 1
	_expect(worst < 0.002,
			"%d nodes: layers + triggers = the manifest exactly (worst drift %.4f)"
			% [checked, worst])

	# And the manifest is itself the garrison, so a fully-cleared sortie dents
	# the node by its whole strength — the P2.q4 spectrum closes arithmetically.
	var node: Dictionary = _find(state, &"sam")
	var spec: Dictionary = SortieComposer.compose(node, state, config)
	var kills: Dictionary = {}
	for layer: StringName in SortieComposer.LAYER_ORDER:
		for unit: Dictionary in spec["layers"][layer]:
			kills[unit["type"]] = int(kills.get(unit["type"], 0)) + int(unit["bodies"])
	for trigger: Dictionary in spec["triggers"]:
		for unit: Dictionary in trigger["units"]:
			kills[unit["type"]] = int(kills.get(unit["type"], 0)) + int(unit["bodies"])
	_expect(is_equal_approx(WarManifest.dent_from_kills(kills),
			SortieComposer.total_strength(spec)),
			"clearing everything the sortie fields dents by its whole strength")


func _check_archetypes(state: Dictionary, config: WarConfig) -> void:
	var seen: Dictionary = {}
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		seen[node["type"]] = spec["archetype"]
		_expect(spec["objective"] != &"",
				"node %d (%s) gets an objective" % [int(node["id"]), node["type"]])
	_expect(seen.get(&"factory") == &"strike", "a factory is a Strike")
	_expect(seen.get(&"airspace") == &"dogfight", "contested airspace is a Dogfight")
	_expect(seen.get(&"radar") == &"sead" and seen.get(&"sam") == &"sead",
			"radar and SAM sites are SEAD")
	_expect(seen.get(&"command") == &"decapitation", "a command post is Decapitation")
	_expect(seen.get(&"hq") == &"raid", "the HQ is The Raid")

	# The P2.13 cut is stated in code, not discovered by a scene failing.
	var strike: Dictionary = SortieComposer.compose(_find(state, &"factory"), state, config)
	var raid: Dictionary = SortieComposer.compose(_find(state, &"hq"), state, config)
	_expect(SortieComposer.is_slice_ready(strike), "the Strike is slice-ready")
	_expect(not SortieComposer.is_slice_ready(raid),
			"the Raid composes but is not slice-ready (P2.13 defers it)")
	# The dogfight is the shipped wave loop's home (P2.12).
	var dogfight: Dictionary = SortieComposer.compose(_find(state, &"airspace"),
			state, config)
	_expect(int(dogfight["objective_assets"]) == 0,
			"a dogfight's objective IS the garrison, not a structure")


## P1.q2, read from the tick engine's own helper so briefing and war agree.
func _check_capture_rule(state: Dictionary, config: WarConfig) -> void:
	var agreed: int = 0
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if bool(spec["capture"]) \
				== WarSim.has_adjacent_owner(state, node, &"player"):
			agreed += 1
	_expect(agreed == state["nodes"].size(),
			"every node's capture flag matches the tick engine (%d)" % agreed)


func _check_layering(state: Dictionary, config: WarConfig) -> void:
	# A SAM site is layered: area denial in the middle, not milling about
	# outside. (Its garrison is turret-heavy by doctrine.)
	var sam: Dictionary = SortieComposer.compose(_find(state, &"sam"), state, config)
	_expect(_count_of(sam["layers"][&"mid"], &"turret")
			>= _count_of(sam["layers"][&"outer"], &"turret"),
			"a SAM site's turrets hold the middle ring, not the picket line")

	# A dogfight has no rings — the enemy comes to you (P2.12).
	var dogfight: Dictionary = SortieComposer.compose(_find(state, &"airspace"),
			state, config)
	_expect(dogfight["layers"][&"mid"].is_empty()
			and dogfight["layers"][&"inner"].is_empty(),
			"a dogfight places no rings; everything is inbound")

	# The heavy type guards the objective rather than picketing.
	var hq: Dictionary = SortieComposer.compose(_find(state, &"hq"), state, config)
	_expect(_count_of(hq["layers"][&"outer"], &"aegis") == 0,
			"the aegis guards the objective, it does not fly picket")

	# Layering never invents or loses a body.
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				if int(unit["count"]) <= 0:
					_expect(false, "node %d has an empty unit entry in %s"
							% [int(node["id"]), layer])


func _check_triggers(state: Dictionary, config: WarConfig) -> void:
	var strike: Dictionary = SortieComposer.compose(_find(state, &"factory"),
			state, config)
	_expect(not strike["triggers"].is_empty(), "a Strike holds a reaction force")
	_expect(strike["triggers"][0]["on"] == &"objective_damaged",
			"the Strike's escorts converge when you commit to the objective")

	var sead: Dictionary = SortieComposer.compose(_find(state, &"radar"), state, config)
	_expect(sead["triggers"][0]["on"] == &"detected",
			"the dish calls interceptors when it SEES you — staying unseen is "
			+ "counterplay (P2.3)")

	var dogfight: Dictionary = SortieComposer.compose(_find(state, &"airspace"),
			state, config)
	_expect(dogfight["triggers"].size() >= 2, "a dogfight's reserve arrives in waves")
	var wave_numbers: Array = []
	for trigger: Dictionary in dogfight["triggers"]:
		wave_numbers.append(int(trigger["wave"]))
		_expect(trigger["on"] == &"wave_cleared", "dogfight waves chain on clears")
	_expect(wave_numbers == [1, 2], "waves are numbered in order %s" % str(wave_numbers))

	# A reaction force is a GLOBAL split, not a per-type one: any node with
	# more than one unit must be able to hold something back, however small.
	# (Before this was fixed a light factory of one raider + one pack + one
	# turret reserved nothing at all, and the Strike's escorts never came.)
	var reserveless: int = 0
	var multi_unit: int = 0
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		var units: int = 0
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				units += int(unit["count"])
		for trigger: Dictionary in spec["triggers"]:
			for unit: Dictionary in trigger["units"]:
				units += int(unit["count"])
		if units < 2:
			continue
		multi_unit += 1
		if spec["triggers"].is_empty():
			reserveless += 1
	_expect(reserveless == 0,
			"every node of 2+ units holds a reaction force (%d of %d had none)"
			% [reserveless, multi_unit])

	# ...and something is always home when you arrive.
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if SortieComposer.total_strength(spec) <= 0.0:
			continue
		var placed: int = 0
		for layer: StringName in SortieComposer.LAYER_ORDER:
			placed += spec["layers"][layer].size()
		_expect_quiet(placed > 0,
				"node %d opens on an empty map — the whole garrison was reserved"
				% int(node["id"]))

	# Delays are seeded, so the same sortie always gives the same window.
	var again: Dictionary = SortieComposer.compose(_find(state, &"factory"),
			state, config)
	_expect(is_equal_approx(float(strike["triggers"][0]["after_s"]),
			float(again["triggers"][0]["after_s"])),
			"reinforcement timing is seeded, not rolled at runtime")


func _check_pads(state: Dictionary, config: WarConfig) -> void:
	var light: Dictionary = {"id": 1, "type": &"airspace", "biome": &"city",
			"garrison": 6.0, "fort": 1.0, "weather": &"clear", "intel_age": 0,
			"q": 99, "r": 99, "owner": &"enemy", "home": false, "hq": false}
	var heavy: Dictionary = {"id": 1, "type": &"airspace", "biome": &"city",
			"garrison": 40.0, "fort": 1.0, "weather": &"clear", "intel_age": 0,
			"q": 99, "r": 99, "owner": &"enemy", "home": false, "hq": false}
	var light_spec: Dictionary = SortieComposer.compose(light, state, config)
	var heavy_spec: Dictionary = SortieComposer.compose(heavy, state, config)
	_expect(int(light_spec["pads"]) > int(heavy_spec["pads"]),
			"hard nodes are pad-poor: %d pads at garrison 6, %d at garrison 40"
			% [int(light_spec["pads"]), int(heavy_spec["pads"])])
	_expect(int(SortieComposer.compose(_find(state, &"hq"), state, config)["pads"]) == 0,
			"the HQ offers no pad")
	for node: Dictionary in state["nodes"]:
		var pads: int = int(SortieComposer.compose(node, state, config)["pads"])
		_expect(pads >= 0 and pads <= SortieComposer.PAD_MAX,
				"node %d pads in range (%d)" % [int(node["id"]), pads])


func _check_approach_and_dares(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, 5150)
	var city: Dictionary = {"id": 3, "type": &"factory", "biome": &"city",
			"garrison": 20.0, "fort": 1.0, "weather": &"clear", "intel_age": 0,
			"q": 99, "r": 99, "owner": &"enemy", "home": false, "hq": false}
	var desert: Dictionary = {"id": 3, "type": &"factory", "biome": &"desert",
			"garrison": 20.0, "fort": 1.0, "weather": &"clear", "intel_age": 0,
			"q": 99, "r": 99, "owner": &"enemy", "home": false, "hq": false}
	var city_spec: Dictionary = SortieComposer.compose(city, state, config)
	var desert_spec: Dictionary = SortieComposer.compose(desert, state, config)
	_expect(float(desert_spec["approach"]["ingress_m"])
			> float(city_spec["approach"]["ingress_m"]),
			"open ground means a long exposed ingress: desert %.0f m > city %.0f m"
			% [float(desert_spec["approach"]["ingress_m"]),
			float(city_spec["approach"]["ingress_m"])])
	_expect(int(city_spec["approach"]["corridors"])
			> int(desert_spec["approach"]["corridors"]),
			"dense ground offers more lines to mask behind")

	# Dares are biome-weighted, optional and capped at one for the slice.
	var dares: int = 0
	var samples: int = 40
	for index: int in samples:
		var node: Dictionary = {"id": index, "type": &"factory", "biome": &"city",
				"garrison": 20.0, "fort": 1.0, "weather": &"clear", "intel_age": 0,
			"q": 99, "r": 99, "owner": &"enemy", "home": false, "hq": false}
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		_expect_quiet(spec["dares"].size() <= 1, "dares capped at one")
		dares += spec["dares"].size()
	_expect(dares > 0 and dares < samples,
			"dares are optional and not guaranteed (%d of %d city sorties)"
			% [dares, samples])


## H6: SDI is measured by the harness, never authored by the composer. The
## spec must carry the diagnosis vector and NO composite score.
func _check_no_authored_difficulty(state: Dictionary, config: WarConfig) -> void:
	var spec: Dictionary = SortieComposer.compose(_find(state, &"sam"), state, config)
	_expect(spec.has("difficulty_inputs"), "the spec carries the H.q2 axis vector")
	for axis: String in ["garrison_strength", "cover", "weather", "weather_penalty",
			"pads", "escalation", "fortification"]:
		_expect(spec["difficulty_inputs"].has(axis),
				"difficulty input '%s' is reported for diagnosis" % axis)
	for forbidden: String in ["sdi", "difficulty", "difficulty_score", "hardness"]:
		_expect(not spec.has(forbidden) and not spec["difficulty_inputs"].has(forbidden),
				"the composer does not author a '%s' score (H6: SDI is measured)"
				% forbidden)
	# Weather is an input the composer passes through, not one it invents.
	_expect(spec["weather"] == spec["difficulty_inputs"]["weather"],
			"the sortie inherits the node's weather (P2.8)")


## P2.1's two evaluations of one function. Fresh intel: briefing == truth.
## Stale intel: the briefing regresses to what intel can resolve, and the
## divergence is the designed surprise.
func _check_briefing_vs_truth(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, 31337)
	var node: Dictionary = _find(state, &"factory").duplicate(true)

	node["intel_age"] = 0
	var fresh: Dictionary = SortieComposer.compose_briefing(node, state, config)
	var truth: Dictionary = SortieComposer.compose(node, state, config)
	_expect(fresh["garrison_detail"] == &"exact",
			"fresh intel briefs the exact garrison")
	_expect(var_to_str(fresh["layers"]) == var_to_str(truth["layers"]),
			"with fresh intel the briefing and the truth agree")
	_expect(bool(truth["truth"]) and not bool(fresh["truth"]),
			"specs say which evaluation produced them")

	node["intel_age"] = 3
	var vague: Dictionary = SortieComposer.compose_briefing(node, state, config)
	_expect(vague["garrison_detail"] == &"families",
			"middling intel briefs families")
	_expect(vague.has("intel") and vague["intel"].has("families"),
			"the briefing reports what intel CAN resolve")
	_expect(var_to_str(vague["layers"]) != var_to_str(truth["layers"]),
			"a stale briefing diverges from the truth — the designed surprise")

	node["intel_age"] = 40
	var blind: Dictionary = SortieComposer.compose_briefing(node, state, config)
	_expect(blind["garrison_detail"] == &"strength",
			"blind intel briefs only the abstract strength")
	_expect(is_equal_approx(float(blind["garrison_strength"]),
			snappedf(float(node["garrison"]), 0.001)),
			"and that strength is the war-sim's own number")
	# The archetype and the ground are known even when the garrison is not —
	# you can see what KIND of place it is without knowing who is home.
	_expect(blind["archetype"] == truth["archetype"]
			and blind["biome"] == truth["biome"],
			"fog hides the garrison, not the geography")


func _check_serializable(state: Dictionary, config: WarConfig) -> void:
	for node_type: StringName in [&"factory", &"airspace", &"hq", &"sam"]:
		var spec: Dictionary = SortieComposer.compose(_find(state, node_type),
				state, config)
		var text: String = var_to_str(spec)
		var restored: Variant = str_to_var(text)
		_expect(restored != null and var_to_str(restored) == text,
				"a %s spec round-trips var_to_str bit-exactly" % node_type)


## The joint has to conserve while the war MOVES — garrisons grow, decay and
## change hands every tick, and a composed sortie must stay solvent against
## all of it.
func _check_over_a_running_war(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, 24601)
	var composed: int = 0
	var breaches: int = 0
	var slice_ready: int = 0
	for tick: int in 40:
		WarSim.tick(state, config, 0.7)
		if WarSim.winner(state) != &"":
			break
		var escalation: float = WarSim.escalation(state, config)
		for node: Dictionary in state["nodes"]:
			if node["owner"] != &"enemy":
				continue
			var spec: Dictionary = SortieComposer.compose(node, state, config)
			var manifest: Array = WarManifest.project(node, int(state["seed"]),
					escalation)
			if absf(SortieComposer.total_strength(spec)
					- WarManifest.strength_of(manifest)) > 0.002:
				breaches += 1
			if SortieComposer.is_slice_ready(spec):
				slice_ready += 1
			composed += 1
	_expect(breaches == 0,
			"%d sorties composed across a running war, none leaked strength"
			% composed)
	_expect(slice_ready > 0,
			"the running war offers slice-ready fights (%d of %d)"
			% [slice_ready, composed])


## ---------- helpers ----------

func _find(state: Dictionary, node_type: StringName) -> Dictionary:
	for node: Dictionary in state["nodes"]:
		if node["type"] == node_type:
			return node
	return state["nodes"][0]


func _count_of(units: Array, type_id: StringName) -> int:
	for unit: Dictionary in units:
		if unit["type"] == type_id:
			return int(unit["count"])
	return 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[sortie_compose_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[sortie_compose_check]  FAIL  %s" % message)


## For assertions inside loops, where printing every pass would bury the run.
func _expect_quiet(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("[sortie_compose_check]  FAIL  %s" % message)
