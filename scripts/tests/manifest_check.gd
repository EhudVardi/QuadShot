extends SceneTree

## Headless check for the P4.7 manifest projection (WarManifest).
##
## The manifest is the joint between the war and the fight, so what is checked
## here is the joint's honesty, not a balance opinion:
##   - it is a PURE PROJECTION (same input, same output; reading it never
##     touches the war's RNG or mutates a node),
##   - it SPENDS the garrison it is handed and never overspends it,
##   - the exchange rate runs both ways (units → strength → dent),
##   - doctrine and cover actually reach the mix (a SAM site is not an
##     airspace node wearing a different label),
##   - it stays serializable (F4), and
##   - it degrades through fog to exactly the number the war-sim keeps.
##
## Run: <godot> --headless -s scripts/tests/manifest_check.gd --path .

const THEATER_SEED: int = 4242

var _failures: int = 0


func _init() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)

	_check_roster_costs()
	_check_purity(state)
	_check_budget(state, config)
	_check_exchange_rate(state)
	_check_doctrine()
	_check_cover()
	_check_escalation()
	_check_fog(state)
	_check_serializable(state)
	_check_over_a_running_war(config)

	if _failures == 0:
		print("[manifest_check] PASS")
	else:
		print("[manifest_check] FAIL — %d check(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## The projection prices off the COMMITTED configs (BALANCE.md's third ruler),
## and `strength_cost` is no longer inert.
func _check_roster_costs() -> void:
	var roster: Dictionary = WarManifest.roster()
	_expect(roster.size() == WarManifest.ROSTER.size(),
			"roster loads every slice type (got %d)" % roster.size())
	for type_id: StringName in WarManifest.ROSTER:
		var config: EnemyConfig = roster[type_id]
		_expect(config.strength_cost > 0.0,
				"%s has a strength cost (%.2f)" % [type_id, config.strength_cost])
	# The swarm's unit is the pack, so its unit price is the pack's price.
	var gnat: EnemyConfig = roster[&"gnat"]
	_expect(is_equal_approx(WarManifest.unit_strength(gnat),
			gnat.strength_cost * gnat.pack_size),
			"a gnat UNIT is priced as a pack of %d" % int(gnat.pack_size))
	_expect(WarManifest.unit_bodies(roster[&"raider"]) == 1,
			"a raider unit is one body")


## Same node, same manifest — and projecting must not mutate the node or the
## war's RNG stream (looking at the enemy cannot change the war).
func _check_purity(state: Dictionary) -> void:
	var node: Dictionary = _find_node(state, &"sam")
	var before: String = var_to_str(state)
	var first: Array = WarManifest.project(node, THEATER_SEED, 0.4)
	var second: Array = WarManifest.project(node, THEATER_SEED, 0.4)
	_expect(var_to_str(first) == var_to_str(second),
			"projection is deterministic")
	_expect(var_to_str(state) == before,
			"projection does not mutate the war state")
	# A different theater seed must produce different character somewhere in
	# the theater, or the per-node jitter is not wired.
	var differs: bool = false
	for other: Dictionary in state["nodes"]:
		if var_to_str(WarManifest.project(other, THEATER_SEED)) \
				!= var_to_str(WarManifest.project(other, THEATER_SEED + 1)):
			differs = true
			break
	_expect(differs, "theater seed changes node character")


## The garrison float is a budget: spend it, never exceed it, and leave less
## than the cheapest unit on the table.
func _check_budget(state: Dictionary, config: WarConfig) -> void:
	var checked: int = 0
	for node: Dictionary in state["nodes"]:
		var garrison: float = float(node["garrison"])
		var units: Array = WarManifest.project(node, THEATER_SEED, 0.5)
		var spent: float = WarManifest.strength_of(units)
		_expect(spent <= garrison + 0.001,
				"node %d (%s) does not overspend: %.3f <= %.3f"
				% [int(node["id"]), node["type"], spent, garrison])
		var cheapest: float = _cheapest_unit(node)
		if garrison >= cheapest:
			_expect(not units.is_empty(),
					"node %d (%s, garrison %.2f) fields something"
					% [int(node["id"]), node["type"], garrison])
			_expect(garrison - spent < cheapest,
					"node %d (%s) spends down to the last affordable unit "
					% [int(node["id"]), node["type"]]
					+ "(%.3f left, cheapest %.3f)" % [garrison - spent, cheapest])
		checked += 1
	_expect(checked == int(config.node_count),
			"every generated node projects (%d)" % checked)
	# An empty garrison is an empty manifest, not a free body.
	var empty: Dictionary = {"id": 0, "type": &"sam", "biome": &"city",
			"garrison": 0.0}
	_expect(WarManifest.project(empty, THEATER_SEED).is_empty(),
			"a zero garrison fields nothing")


## Units → strength → dent: the same price list read in both directions, which
## is what makes "your fights dent the war" payable (P2.q4).
func _check_exchange_rate(state: Dictionary) -> void:
	var node: Dictionary = _find_node(state, &"command")
	var units: Array = WarManifest.project(node, THEATER_SEED, 0.3)
	var total: float = WarManifest.strength_of(units)

	# Killing every body in the manifest dents by the manifest's whole price.
	var kills: Dictionary = {}
	for unit: Dictionary in units:
		kills[unit["type"]] = int(unit["bodies"])
	_expect(is_equal_approx(WarManifest.dent_from_kills(kills), total),
			"clearing the garrison dents by its full strength (%.3f)" % total)

	# A partially-cleared swarm dents by what you actually killed — half a
	# pack is half a pack, not nothing and not a whole one.
	var gnat: EnemyConfig = WarManifest.roster()[&"gnat"]
	var half: Dictionary = {&"gnat": int(gnat.pack_size) / 2}
	_expect(is_equal_approx(WarManifest.dent_from_kills(half),
			snappedf(gnat.strength_cost * float(int(gnat.pack_size) / 2), 0.001)),
			"a half-cleared pack dents by half a pack")
	_expect(WarManifest.dent_from_kills({}) == 0.0, "killing nothing dents nothing")
	_expect(WarManifest.dent_from_kills({&"not_a_type": 99}) == 0.0,
			"an unknown type prices at zero rather than throwing")


## Doctrine reaches the mix: node type decides who garrisons the ground.
func _check_doctrine() -> void:
	var airspace: Dictionary = _synthetic(&"airspace", &"city", 24.0)
	var sam: Dictionary = _synthetic(&"sam", &"city", 24.0)
	var hq: Dictionary = _synthetic(&"hq", &"city", 24.0)

	_expect(_share_of(airspace, &"turret") == 0.0,
			"contested airspace fields no turrets — nothing to bolt them to")
	_expect(_share_of(sam, &"turret") > _share_of(airspace, &"turret"),
			"a SAM site is turret-heavier than open airspace")
	_expect(_share_of(hq, &"aegis") > 0.0, "the HQ fields the heavy type")
	_expect(_share_of(_synthetic(&"depot", &"city", 24.0), &"aegis") == 0.0,
			"a supply depot does not get an aegis guard")


## Cover economics reach the mix (P4.5): dense ground nests swarms, open
## ground favours the flyers. Same node type, same budget, different biome.
func _check_cover() -> void:
	var dense: Dictionary = _synthetic(&"airspace", &"city", 30.0)
	var open: Dictionary = _synthetic(&"airspace", &"desert", 30.0)
	_expect(_share_of(dense, &"gnat") > _share_of(open, &"gnat"),
			"gnats nest in cover: city %.2f > desert %.2f"
			% [_share_of(dense, &"gnat"), _share_of(open, &"gnat")])
	_expect(_share_of(open, &"raider") > _share_of(dense, &"raider"),
			"raiders prefer open approaches: desert %.2f > city %.2f"
			% [_share_of(open, &"raider"), _share_of(dense, &"raider")])


## Escalation (P4.6) shifts the mix toward the heavy end — and may never
## delete a type outright (P1.7: pressure, not replacement).
func _check_escalation() -> void:
	var node: Dictionary = _synthetic(&"hq", &"city", 36.0)
	var calm: Array = WarManifest.project(node, THEATER_SEED, 0.0)
	var hot: Array = WarManifest.project(node, THEATER_SEED, 1.5)
	var calm_aegis: float = _share_in(calm, &"aegis")
	var hot_aegis: float = _share_in(hot, &"aegis")
	_expect(hot_aegis > calm_aegis,
			"escalation fields heavier: aegis share %.2f → %.2f"
			% [calm_aegis, hot_aegis])
	_expect(WarManifest.strength_of(hot) <= float(node["garrison"]) + 0.001,
			"escalation stays inside the garrison budget")
	# The light type is squeezed, not erased.
	var extreme: Array = WarManifest.project(
			_synthetic(&"airspace", &"city", 36.0), THEATER_SEED, 5.0)
	_expect(_share_in(extreme, &"gnat") > 0.0,
			"extreme escalation squeezes the light type without erasing it")


## Fog degrades detail before quantity, and its last stop is exactly the
## abstract number the war-sim keeps (P1.3 / P4.7).
func _check_fog(state: Dictionary) -> void:
	var node: Dictionary = _find_node(state, &"factory")
	var units: Array = WarManifest.project(node, THEATER_SEED, 0.2)
	var total: float = WarManifest.strength_of(units)

	var fresh: Dictionary = WarManifest.through_fog(units, 0)
	_expect(fresh["detail"] == &"exact" and fresh.has("units"),
			"fresh intel shows the unit list")
	_expect(var_to_str(fresh["units"]) == var_to_str(units),
			"fresh intel shows the TRUE unit list")

	var mid: Dictionary = WarManifest.through_fog(units, 3)
	_expect(mid["detail"] == &"families" and mid.has("families")
			and not mid.has("units"), "middling intel shows families only")
	var family_total: float = 0.0
	for family: StringName in mid["families"]:
		family_total += float(mid["families"][family])
	_expect(is_equal_approx(snappedf(family_total, 0.001), total),
			"families still account for the whole garrison (%.3f)" % total)

	var stale: Dictionary = WarManifest.through_fog(units, 99)
	_expect(stale["detail"] == &"strength" and not stale.has("units")
			and not stale.has("families"),
			"stale intel regresses to the abstract strength")
	_expect(is_equal_approx(float(stale["strength"]), total),
			"the abstract strength is the war-sim's own number")


## The manifest travels with the save (F4): var_to_str round-trips it.
func _check_serializable(state: Dictionary) -> void:
	var node: Dictionary = _find_node(state, &"hq")
	var units: Array = WarManifest.project(node, THEATER_SEED, 0.7)
	var text: String = var_to_str(units)
	var restored: Variant = str_to_var(text)
	_expect(restored != null and var_to_str(restored) == text,
			"a manifest round-trips var_to_str bit-exactly")


## The joint has to hold while the war MOVES, not just at tick 0: garrisons
## grow, shrink, decay and change hands every tick, and the projection has to
## stay solvent against all of it.
func _check_over_a_running_war(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, 77)
	var projections: int = 0
	var breaches: int = 0
	for tick: int in 60:
		WarSim.tick(state, config, 0.7)
		if WarSim.winner(state) != &"":
			break
		var escalation: float = WarSim.escalation(state, config)
		for node: Dictionary in state["nodes"]:
			var units: Array = WarManifest.project(node, int(state["seed"]),
					escalation)
			if WarManifest.strength_of(units) > float(node["garrison"]) + 0.001:
				breaches += 1
			projections += 1
	_expect(breaches == 0,
			"%d projections across a running war, none overspent" % projections)
	_expect(projections > 0, "the war ran long enough to project (%d)" % projections)


## ---------- helpers ----------

func _synthetic(node_type: StringName, biome: StringName,
		garrison: float) -> Dictionary:
	return {"id": 7, "type": node_type, "biome": biome, "garrison": garrison}


func _find_node(state: Dictionary, node_type: StringName) -> Dictionary:
	for node: Dictionary in state["nodes"]:
		if node["type"] == node_type:
			return node
	# Every generated theater has all these types; falling back keeps the
	# check readable if a quota ever changes.
	return state["nodes"][0]


func _cheapest_unit(node: Dictionary) -> float:
	var doctrine: Dictionary = WarManifest.DOCTRINE.get(node["type"],
			WarManifest.DOCTRINE[&"airspace"])
	var cheapest: float = INF
	for type_id: StringName in doctrine:
		cheapest = minf(cheapest,
				WarManifest.unit_strength(WarManifest.roster()[type_id]))
	return cheapest


func _share_of(node: Dictionary, type_id: StringName) -> float:
	return _share_in(WarManifest.project(node, THEATER_SEED), type_id)


func _share_in(units: Array, type_id: StringName) -> float:
	var total: float = WarManifest.strength_of(units)
	if total <= 0.0:
		return 0.0
	for unit: Dictionary in units:
		if unit["type"] == type_id:
			return float(unit["strength"]) / total
	return 0.0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[manifest_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[manifest_check]  FAIL  %s" % message)
