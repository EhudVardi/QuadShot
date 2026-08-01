class_name WarSim
extends RefCounted

## The war tick engine (GAMEPLAY-DESIGN Iteration 1: P1.4–P1.7).
## Deterministic and pure: the whole war lives in a serializable state
## Dictionary (var_to_str round-trips it — that IS the F4 portable save,
## RNG state included). Tick order is fixed: production → supply →
## player sortie (proxy) → enemy operations → weather/intel → end check.
##
## Garrisons are abstract strengths until Iteration 2 (P4) supplies the
## bestiary; the proxy player is a skill-parameterized stand-in for the
## FPV pilot so soak runs can sweep the difficulty curve.


## Advances the war one turn. proxy_skill < 0 = no player action this tick
## (spectator mode / the war moving on without you).
static func tick(state: Dictionary, config: WarConfig, proxy_skill: float = -1.0) -> void:
	if state["winner"] != &"":
		return
	var rng := RandomNumberGenerator.new()
	rng.state = state["rng_state"]
	state["tick"] = int(state["tick"]) + 1
	_production(state, config)
	_supply(state, config)
	if proxy_skill >= 0.0 and int(state["pilots"]) > 0:
		_proxy_sortie(state, config, rng, proxy_skill)
	if proxy_skill >= 0.0:
		# The P5 influence order, proxied: the player directs one allied
		# assault where local superiority is overwhelming (P1.q3 — allied
		# offense happens only on the player's order). This is how idle
		# allied mass converts into ground once sorties soften the line.
		# Order judgment is player skill too: better players order sharper.
		_allied_offensive(state, config, rng, proxy_skill)
	_enemy_operations(state, config, rng)
	_weather_and_intel(state, rng)
	_check_end(state, config)
	# Quantize all evolving floats: decimal-exact values round-trip through
	# var_to_str/str_to_var bit-for-bit, which is what makes the portable
	# save (F4) provably lossless.
	for node: Dictionary in state["nodes"]:
		node["garrison"] = quantize(float(node["garrison"]))
	state["rng_state"] = rng.state


static func winner(state: Dictionary) -> StringName:
	return state["winner"]


## THE LOOP HOME (GAMEPLAY-DESIGN Iteration 12, W7): a sortie a HUMAN actually
## flew, priced back into the war. `_proxy_sortie` above is the abstract
## stand-in that soak runs sweep with; this is the real thing, and the two must
## agree on their outcome vocabulary or the harness would be calibrating a
## different game from the one being played.
##
## `result` is `SortieRunner.result()` — serializable, so this function never
## needs to know a Node3D exists, exactly like the rest of `war/`.
##
## THE RULE OF THE WHOLE DOC IS THIS FUNCTION: "the war shapes your fights;
## your fights dent the war." Everything up to now was the first half.
##
## Returns a summary of what moved, for a briefing line or a check.
static func apply_sortie(state: Dictionary, config: WarConfig,
		result: Dictionary) -> Dictionary:
	var node: Dictionary = node_by_id(state, int(result.get("node_id", -1)))
	if node.is_empty():
		return {}
	var before: float = float(node["garrison"])
	state["sorties"] = int(state["sorties"]) + 1

	# P2.q4, and it is unconditional ON PURPOSE: everything you destroyed dents
	# the node, whether you completed the objective, aborted, or died on the
	# way out. A hard-fought failure still weakens the target for next time.
	node["garrison"] = quantize(maxf(before - float(result.get("dent", 0.0)), 0.0))

	# You just looked at this ground with your own eyes, so the fog clears
	# regardless of how the sortie went (P1.3). Dying over a node is a terrible
	# way to buy intel and it is still intel.
	node["intel_age"] = 0

	# P1.q2 / P2.9's capture gate. Adjacency is re-read from the LIVE state
	# rather than from the spec that composed this sortie: the spec's `capture`
	# was true when the briefing was written, and a tick may have moved the
	# front since. The ground is what it is when you get there.
	var captured: bool = false
	var degraded: bool = false
	if bool(result.get("objective_complete", false)) \
			and not bool(result.get("pilot_lost", false)):
		if has_adjacent_owner(state, node, &"player"):
			# A completed assault next to ground you hold IS the node taken.
			# Consolidated and dug in, so retaking it costs the enemy a real
			# decision rather than a reflex — same numbers the proxy uses.
			node["owner"] = &"player"
			node["garrison"] = quantize(10.0)
			node["fort"] = maxf(float(node["fort"]), 1.3)
			captured = true
			if node["hq"]:
				state["winner"] = &"player"
		else:
			# A deep strike with nothing to hold it only degrades (P1.q2).
			node["garrison"] = quantize(maxf(float(node["garrison"])
					- config.sortie_damage, 0.0))
			degraded = true

	if bool(result.get("pilot_lost", false)):
		state["pilots"] = maxi(int(state["pilots"]) - 1, 0)

	return {
		"node_id": int(node["id"]),
		"node_type": node["type"],
		"outcome": result.get("outcome", &"partial"),
		"garrison_before": quantize(before),
		"garrison_after": float(node["garrison"]),
		"dent": quantize(float(result.get("dent", 0.0))),
		"captured": captured,
		"degraded": degraded,
		"pilots_left": int(state["pilots"]),
	}


static func node_by_id(state: Dictionary, id: int) -> Dictionary:
	for node: Dictionary in state["nodes"]:
		if int(node["id"]) == id:
			return node
	return {}


## Quantize an evolving float so the state round-trips var_to_str EXACTLY —
## the F4 promise, and the reason every war float goes through one function.
##
## Not `snappedf(v, 0.001)`, which is `round(v / 0.001) * 0.001`: multiplying
## by 0.001 lands on a double whose shortest decimal form needs 17 digits
## (29900 * 0.001 → 29.900000000000002), var_to_str prints all of them, and
## Godot's float parser drops the tail on the way back in. Dividing instead
## lands on the nearest double to the 3-decimal value, which prints and parses
## as itself. Found 2026-07-26 while building the composer: 40/40 soak seeds
## failed a textual round-trip at tick 0, invisible to war_soak because its
## guard was written against StringName-vs-String drift, not float precision.
static func quantize(value: float, decimals: int = 3) -> float:
	var factor: float = pow(10.0, float(decimals))
	return roundf(value * factor) / factor


## The escalation clock (P1.7): the war never settles — a passive front
## eventually comes to you. Public because the manifest projection (P4.7)
## grades its mixes by the same number the tick engine attacks with; two
## copies of this formula would let the war and its briefings disagree.
static func escalation(state: Dictionary, config: WarConfig) -> float:
	return float(state["aggression"]) \
			+ float(state["tick"]) * config.escalation_per_tick


## ---------- tick phases ----------

## Factories feed the weakest same-owner node among themselves and their
## neighbors — production flows to where the line is thinnest instead of
## piling up uselessly at the factory.
static func _production(state: Dictionary, config: WarConfig) -> void:
	for node: Dictionary in state["nodes"]:
		if node["type"] != &"factory":
			continue
		var weakest: Dictionary = node
		for neighbor: Dictionary in _neighbors(state, node):
			if neighbor["owner"] == node["owner"] \
					and float(neighbor["garrison"]) < float(weakest["garrison"]):
				weakest = neighbor
		weakest["garrison"] = minf(float(weakest["garrison"]) + config.production_rate,
				config.garrison_cap)


## Supply flows from the home airbase (player) / HQ (enemy) through owned
## nodes; owned depots are extra sources, so a depot can keep a cut-off
## sector alive — and killing it starves the sector (P1.2 siege play).
static func _supply(state: Dictionary, config: WarConfig) -> void:
	for side: StringName in [&"player", &"enemy"]:
		var supplied: Dictionary = supplied_set(state, side)
		for node: Dictionary in state["nodes"]:
			if node["owner"] == side and not supplied.has(int(node["id"])):
				node["garrison"] = float(node["garrison"]) * config.unsupplied_decay


static func _proxy_sortie(state: Dictionary, config: WarConfig,
		rng: RandomNumberGenerator, skill: float) -> void:
	var in_range: Dictionary = strike_range(state, config)
	var command_alive: int = _command_posts_alive(state)
	var hq_cell := Vector2i.ZERO
	for node: Dictionary in state["nodes"]:
		if node["hq"]:
			hq_cell = Vector2i(int(node["q"]), int(node["r"]))
	var best: Dictionary = {}
	var best_score: float = -1.0
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy" or not in_range.has(int(node["id"])):
			continue
		if node["hq"] and command_alive > int(config.hq_unlock_command_posts):
			continue
		var capturable: bool = has_adjacent_owner(state, node, &"player")
		# Don't re-bomb rubble that can't be captured — the anti-treadmill
		# rule (degrading a node the enemy will just refill wins nothing).
		if not capturable and float(node["garrison"]) < 3.0:
			continue
		var score: float = _target_value(node) \
				+ minf(2.0 / maxf(float(node["garrison"]), 1.0), 1.0)
		if capturable:
			score += 2.0  # P1.q2: adjacency assaults are how ground is won
			# Strategic directionality: prefer captures that push the front
			# TOWARD the HQ — a campaign is a drive, not a random sprawl.
			var toward_hq: int = TheaterGenerator.hex_distance(
					Vector2i(int(node["q"]), int(node["r"])), hq_cell)
			score += maxf(1.5 - float(toward_hq) * 0.15, 0.0)
		# Decapitation doctrine: while the command network keeps the HQ
		# locked, a command post in reach outranks everything — land-grabbing
		# with an intact enemy brain is how campaigns stall forever.
		if node["type"] == &"command" \
				and command_alive > int(config.hq_unlock_command_posts):
			score += 6.0
		if score > best_score:
			best_score = score
			best = node
	if best.is_empty():
		return
	state["sorties"] = int(state["sorties"]) + 1
	var risk: float = _sortie_risk(state, best)
	var success_chance: float = clampf(0.15 + skill * 0.75 - risk * 0.1
			- float(best["garrison"]) * 0.002, 0.05, 0.95)
	var success: bool = rng.randf() < success_chance
	var capturable: bool = has_adjacent_owner(state, best, &"player")
	if success:
		if capturable:
			# A WON assault sortie IS the node cleared — that's what the M4
			# loop means (waves wiped, gate flown). Captured ground is then
			# consolidated and dug in, so recapturing costs the enemy a real
			# decision (P1.q2 diversion play), not a reflex.
			best["owner"] = &"player"
			best["garrison"] = 6.0 + skill * 8.0
			best["fort"] = maxf(float(best["fort"]), 1.3)
			if best["hq"]:
				state["winner"] = &"player"
		else:
			# Deep strike: no ground presence to hold it, so it degrades.
			best["garrison"] = maxf(float(best["garrison"])
					- config.sortie_damage * (0.5 + skill), 0.0)
	else:
		best["garrison"] = maxf(float(best["garrison"]) - config.sortie_damage * 0.2, 0.5)
	# Coming home clean halves the loss odds, and skill IS survivability —
	# the proxy's skill stands in for the human's actual flying.
	var loss_chance: float = (config.pilot_loss_base + risk * 0.02) \
			* (0.5 if success else 1.0) * clampf(1.2 - skill, 0.2, 1.2)
	if rng.randf() < loss_chance:
		state["pilots"] = int(state["pilots"]) - 1


static func _enemy_operations(state: Dictionary, config: WarConfig,
		rng: RandomNumberGenerator) -> void:
	var aggression: float = escalation(state, config)
	# Offensives: enemy frontline garrisons attack weaker player neighbors.
	var attacks: Array = []
	var supplied: Dictionary = supplied_set(state, &"enemy")
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy" or float(node["garrison"]) < 5.0:
			continue
		# Cut-off garrisons hold but can't mount offensives — sieges work.
		if not supplied.has(int(node["id"])):
			continue
		for neighbor: Dictionary in _neighbors(state, node):
			if neighbor["owner"] != &"player":
				continue
			var ratio: float = float(node["garrison"]) \
					/ maxf(float(neighbor["garrison"]) * float(neighbor["fort"]), 0.5)
			if ratio * aggression > config.attack_win_ratio:
				attacks.append({"from": node, "to": neighbor, "ratio": ratio})
	attacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["ratio"] == b["ratio"]:
			return int(a["to"]["id"]) < int(b["to"]["id"])
		return a["ratio"] > b["ratio"])
	for i: int in mini(int(config.enemy_op_budget), attacks.size()):
		_resolve_attack(state, attacks[i]["from"], attacks[i]["to"], config, rng)
	# Both sides shift rear strength toward their front: the enemy to press
	# the attack, the allies as the passive defense P1.q3 guarantees.
	_reinforce_front(state, &"enemy", &"player")
	_reinforce_front(state, &"player", &"enemy")


static func _allied_offensive(state: Dictionary, config: WarConfig,
		rng: RandomNumberGenerator, skill: float) -> void:
	var supplied: Dictionary = supplied_set(state, &"player")
	var best_from: Dictionary = {}
	var best_to: Dictionary = {}
	# Ordering an assault demands clear superiority; sharper players read
	# the moment better (lower threshold) — sloppier ones over-commit less
	# often because their bar is higher.
	var best_ratio: float = 2.6 - skill
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"player" or float(node["garrison"]) < 5.0 \
				or not supplied.has(int(node["id"])):
			continue
		for neighbor: Dictionary in _neighbors(state, node):
			if neighbor["owner"] != &"enemy":
				continue
			var ratio: float = float(node["garrison"]) \
					/ maxf(float(neighbor["garrison"]) * float(neighbor["fort"]), 0.5)
			if ratio > best_ratio \
					or (ratio == best_ratio and not best_to.is_empty()
					and int(neighbor["id"]) < int(best_to["id"])):
				best_ratio = ratio
				best_from = node
				best_to = neighbor
	if not best_to.is_empty():
		_resolve_attack(state, best_from, best_to, config, rng, &"player", &"enemy")


static func _resolve_attack(state: Dictionary, from: Dictionary, to: Dictionary,
		config: WarConfig, rng: RandomNumberGenerator,
		side: StringName = &"enemy", other: StringName = &"player") -> void:
	if from["owner"] != side or to["owner"] != other:
		return  # a previous op this tick already changed the picture
	var committed: float = float(from["garrison"]) * config.attack_commit_fraction
	var attack: float = committed * rng.randf_range(0.8, 1.2)
	if side == &"enemy" and _near_command(state, from):
		attack *= 1.2  # command network buff (P1.2)
	var defense: float = float(to["garrison"]) * float(to["fort"])
	from["garrison"] = float(from["garrison"]) - committed
	if attack > defense:
		to["owner"] = side
		to["garrison"] = maxf(committed - defense * 0.6, 1.0)
		if side == &"player" and to["hq"]:
			state["winner"] = &"player"
	else:
		# Mauled: attacker loses most of the committed force, defender bleeds.
		from["garrison"] = float(from["garrison"]) + committed * 0.35
		to["garrison"] = float(to["garrison"]) * 0.8


static func _reinforce_front(state: Dictionary, side: StringName,
		opponent: StringName) -> void:
	var distance_to_front: Dictionary = _distance_to_owner(state, opponent)
	var moved: int = 0
	for node: Dictionary in state["nodes"]:
		if moved >= 2:
			return
		if node["owner"] != side or float(node["garrison"]) < 12.0:
			continue
		var here: int = distance_to_front.get(int(node["id"]), 99)
		if here <= 1:
			continue  # already at the front
		for neighbor: Dictionary in _neighbors(state, node):
			if neighbor["owner"] == side \
					and distance_to_front.get(int(neighbor["id"]), 99) < here:
				var shifted: float = float(node["garrison"]) * 0.5
				node["garrison"] = float(node["garrison"]) - shifted
				neighbor["garrison"] = float(neighbor["garrison"]) + shifted
				moved += 1
				break


static func _weather_and_intel(state: Dictionary, rng: RandomNumberGenerator) -> void:
	var weathers: Array[StringName] = [&"clear", &"clear", &"wind", &"rain",
			&"fog", &"heat", &"sandstorm"]
	for node: Dictionary in state["nodes"]:
		if rng.randf() < 0.15:
			node["weather"] = weathers[rng.randi_range(0, weathers.size() - 1)]
		if node["owner"] == &"player" or has_adjacent_owner(state, node, &"player"):
			node["intel_age"] = 0
		else:
			node["intel_age"] = int(node["intel_age"]) + 1


static func _check_end(state: Dictionary, config: WarConfig) -> void:
	if state["winner"] != &"":
		return
	for node: Dictionary in state["nodes"]:
		if node["home"] and node["owner"] == &"enemy":
			state["winner"] = &"enemy"
			return
		if node["hq"] and node["owner"] == &"player":
			state["winner"] = &"player"
			return
	if int(state["tick"]) >= int(config.max_ticks):
		state["winner"] = &"stalemate"


## ---------- shared helpers ----------

static func _neighbors(state: Dictionary, node: Dictionary) -> Array:
	var result: Array = []
	var cell := Vector2i(int(node["q"]), int(node["r"]))
	for other: Dictionary in state["nodes"]:
		if TheaterGenerator.hex_distance(cell,
				Vector2i(int(other["q"]), int(other["r"]))) == 1:
			result.append(other)
	return result


## Public because P1.q2's capture rule ("supply-connected assaults capture,
## deep strikes only degrade") is read by the sortie composer as well as by
## the tick engine, and the two must never disagree about what is capturable.
static func has_adjacent_owner(state: Dictionary, node: Dictionary,
		side: StringName) -> bool:
	for neighbor: Dictionary in _neighbors(state, node):
		if neighbor["owner"] == side:
			return true
	return false


## BFS over owned nodes from the side's supply sources.
##
## Public because the war room DRAWS it (Iteration 13, C2): a supply edge on the
## map and a supply edge in the tick engine have to be the same edge, and the
## only way to guarantee that is for there to be one function. It was private
## purely because nothing outside this file had ever needed it.
static func supplied_set(state: Dictionary, side: StringName) -> Dictionary:
	var frontier: Array = []
	for node: Dictionary in state["nodes"]:
		if node["owner"] != side:
			continue
		var is_source: bool = (side == &"player" and node["home"]) \
				or (side == &"enemy" and node["hq"]) or node["type"] == &"depot"
		if is_source:
			frontier.append(node)
	var supplied: Dictionary = {}
	for node: Dictionary in frontier:
		supplied[int(node["id"])] = true
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_back()
		for neighbor: Dictionary in _neighbors(state, current):
			if neighbor["owner"] == side and not supplied.has(int(neighbor["id"])):
				supplied[int(neighbor["id"])] = true
				frontier.append(neighbor)
	return supplied


## Multi-source BFS: hex hops from every node owned by `side`.
static func _distance_to_owner(state: Dictionary, side: StringName) -> Dictionary:
	var distance: Dictionary = {}
	var frontier: Array = []
	for node: Dictionary in state["nodes"]:
		if node["owner"] == side:
			distance[int(node["id"])] = 0
			frontier.append(node)
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_front()
		var next_distance: int = distance[int(current["id"])] + 1
		for neighbor: Dictionary in _neighbors(state, current):
			if not distance.has(int(neighbor["id"])):
				distance[int(neighbor["id"])] = next_distance
				frontier.append(neighbor)
	return distance


## Strike reach (P1.1): sortie_range_hops beyond the FRIENDLY FRONTIER.
## Flying over your own territory is free staging (0-cost hops), hostile
## hexes cost 1 — so captured ground genuinely extends your reach and the
## drive toward the HQ can always project power past its own front line.
## 0/1-cost BFS (deque: free hops expand first).
##
## Public for the same reason as `supplied_set`: the war room's range shading and
## the proxy sortie's target list must be the same set of nodes, or the map
## promises reach the campaign does not have. `war_trace` was already reaching
## through the underscore to call it.
static func strike_range(state: Dictionary, config: WarConfig) -> Dictionary:
	var distance: Dictionary = {}
	var frontier: Array = []
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"player" and node["type"] == &"airbase":
			distance[int(node["id"])] = 0
			frontier.append(node)
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_front()
		var here: int = distance[int(current["id"])]
		for neighbor: Dictionary in _neighbors(state, current):
			var cost: int = 0 if neighbor["owner"] == &"player" else 1
			var next_distance: int = here + cost
			if next_distance > int(config.sortie_range_hops):
				continue
			if distance.get(int(neighbor["id"]), 9999) <= next_distance:
				continue
			distance[int(neighbor["id"])] = next_distance
			if cost == 0:
				frontier.push_front(neighbor)
			else:
				frontier.push_back(neighbor)
	return distance


static func _command_posts_alive(state: Dictionary) -> int:
	var alive: int = 0
	for node: Dictionary in state["nodes"]:
		if node["type"] == &"command" and node["owner"] == &"enemy" \
				and float(node["garrison"]) >= 1.0:
			alive += 1
	return alive


static func _near_command(state: Dictionary, node: Dictionary) -> bool:
	var cell := Vector2i(int(node["q"]), int(node["r"]))
	for other: Dictionary in state["nodes"]:
		if other["type"] == &"command" and other["owner"] == &"enemy" \
				and float(other["garrison"]) >= 1.0 \
				and TheaterGenerator.hex_distance(cell,
						Vector2i(int(other["q"]), int(other["r"]))) <= 2:
			return true
	return false


static func _target_value(node: Dictionary) -> float:
	match node["type"]:
		&"hq": return 10.0
		&"command": return 5.0
		&"airbase": return 4.5
		&"factory": return 4.0
		&"radar": return 3.5
		&"sam", &"depot": return 3.0
		_: return 1.0


## Radar/SAM/airbase pressure around a target raises sortie risk; fog blinds
## the sensor half of it (P1.6 — "the SAM site is blind in tomorrow's fog").
static func _sortie_risk(state: Dictionary, target: Dictionary) -> float:
	var cell := Vector2i(int(target["q"]), int(target["r"]))
	var risk: float = 0.0
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy" or float(node["garrison"]) < 1.0:
			continue
		var hops: int = TheaterGenerator.hex_distance(cell,
				Vector2i(int(node["q"]), int(node["r"])))
		var sensor_factor: float = 0.5 if node["weather"] == &"fog" else 1.0
		match node["type"]:
			&"radar":
				if hops <= 2:
					risk += 1.0 * sensor_factor
			&"sam":
				if hops <= 1:
					risk += 1.5 * sensor_factor
			&"airbase":
				if hops <= 3:
					risk += 1.0
	return risk
