class_name TheaterGenerator
extends RefCounted

## Seeded hex-theater generation (GAMEPLAY-DESIGN Iteration 1: P1.1–P1.3).
## Pure and deterministic: config + seed in, a fully serializable state
## Dictionary out (the state IS the save file — F4). Hex axial coordinates;
## adjacency doubles as the war-sim graph (P1.8's beehive).

const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Biome palette (P1.9) — tags only at this stage; sortie generation will
## consume them later.
const BIOMES: Array[StringName] = [
	&"city", &"industrial", &"airfield_plains", &"desert", &"hills",
	&"coastal", &"canyon",
]


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func generate(config: WarConfig, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Organic blob: random frontier growth from the origin hex.
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied: Dictionary = {Vector2i.ZERO: true}
	while cells.size() < int(config.node_count):
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var next: Vector2i = from + HEX_DIRECTIONS[rng.randi_range(0, 5)]
		if not occupied.has(next):
			occupied[next] = true
			cells.append(next)

	# Player home = westmost cell (axial x); enemy HQ = farthest from home.
	var home: Vector2i = cells[0]
	for cell: Vector2i in cells:
		if float(cell.x) + float(cell.y) * 0.5 < float(home.x) + float(home.y) * 0.5:
			home = cell
	var hq: Vector2i = home
	for cell: Vector2i in cells:
		if hex_distance(cell, home) > hex_distance(hq, home):
			hq = cell

	var types: Dictionary = _assign_types(config, cells, home, hq, rng)
	var biome_seeds: Array[Vector2i] = _pick_biome_seeds(cells, rng)

	var nodes: Array = []
	for i: int in cells.size():
		var cell: Vector2i = cells[i]
		var distance: int = hex_distance(cell, home)
		var node_type: StringName = types[cell]
		var owner: StringName = &"player" \
				if distance <= int(config.player_pocket_hops) else &"enemy"
		var garrison: float = config.garrison_base
		if owner == &"enemy":
			garrison += config.garrison_per_hop * float(distance)
			garrison *= _garrison_type_multiplier(node_type)
		# Quantized so the state round-trips var_to_str bit-exactly (F4).
		garrison = snappedf(minf(garrison, config.garrison_cap), 0.001)
		nodes.append({
			"id": i, "q": cell.x, "r": cell.y,
			"type": node_type, "owner": owner,
			"garrison": garrison,
			"fort": _fort_for_type(node_type),
			"biome": _nearest_biome(cell, biome_seeds),
			"weather": &"clear" if rng.randf() > 0.2 else &"fog",
			"intel_age": 0 if owner == &"player" else 999,
			"home": cell == home,
			"hq": cell == hq,
		})

	return {
		"tick": 0,
		"sorties": 0,
		"pilots": int(config.starting_pilots),
		"winner": &"",
		"nodes": nodes,
		# Seeded enemy character (P1.4): different theaters fight differently.
		"aggression": snappedf(rng.randf_range(0.4, 0.9), 0.001),
		"caution": snappedf(rng.randf_range(0.2, 0.7), 0.001),
		"rng_state": rng.state,
		"seed": seed_value,
	}


## Deep half gets command/factory infrastructure, the middle band gets the
## sensor/denial belt — the difficulty gradient is also an *infrastructure*
## gradient, so pushing in feels like peeling an onion.
static func _assign_types(config: WarConfig, cells: Array[Vector2i],
		home: Vector2i, hq: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var types: Dictionary = {}
	for cell: Vector2i in cells:
		types[cell] = &"airspace"
	types[home] = &"airbase"
	types[hq] = &"hq"
	var free: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if cell != home and cell != hq:
			free.append(cell)
	# Deterministic order: deepest first, id-stable tiebreak.
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = hex_distance(a, home)
		var db: int = hex_distance(b, home)
		if da == db:
			return a < b
		return da > db)
	var scale: float = config.node_count / 30.0
	var quotas: Array = [
		[&"command", maxi(int(3.0 * scale), 2)],
		[&"factory", maxi(int(3.0 * scale), 2)],
		[&"airbase", maxi(int(2.0 * scale), 1)],   # enemy forward airbases
		[&"depot", maxi(int(2.0 * scale), 1)],
		[&"radar", maxi(int(3.0 * scale), 2)],
		[&"sam", maxi(int(3.0 * scale), 2)],
	]
	# One pocket factory so the allied side produces something (P1.4 allied
	# defense needs some backbone).
	var pocket: Array[Vector2i] = []
	for cell: Vector2i in free:
		if hex_distance(cell, home) <= int(config.player_pocket_hops):
			pocket.append(cell)
	if not pocket.is_empty():
		var pick: Vector2i = pocket[rng.randi_range(0, pocket.size() - 1)]
		types[pick] = &"factory"
		free.erase(pick)
	# Deep-to-shallow: command/factory/airbase draw from the deep end (front
	# of the sorted list), radar/sam/depot interleave into the middle band.
	var cursor: int = 0
	for quota: Array in quotas:
		var node_type: StringName = quota[0]
		var count: int = quota[1]
		var step: int = 1 if node_type != &"radar" and node_type != &"sam" else 2
		var assigned: int = 0
		var index: int = cursor
		while assigned < count and index < free.size():
			if types[free[index]] == &"airspace":
				types[free[index]] = node_type
				assigned += 1
			index += step
		cursor = mini(cursor + count / 2, maxi(free.size() - 1, 0))
	return types


static func _pick_biome_seeds(cells: Array[Vector2i],
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	for i: int in mini(5, cells.size()):
		seeds.append(cells[rng.randi_range(0, cells.size() - 1)])
	return seeds


static func _nearest_biome(cell: Vector2i, seeds: Array[Vector2i]) -> StringName:
	var best: int = 0
	for i: int in seeds.size():
		if hex_distance(cell, seeds[i]) < hex_distance(cell, seeds[best]):
			best = i
	return BIOMES[best % BIOMES.size()]


static func _garrison_type_multiplier(node_type: StringName) -> float:
	match node_type:
		&"hq": return 3.0
		&"command": return 2.0
		&"airbase": return 1.5
		&"factory", &"depot": return 1.3
		_: return 1.0


static func _fort_for_type(node_type: StringName) -> float:
	match node_type:
		&"hq", &"sam", &"airbase": return 1.5
		&"command": return 1.3
		_: return 1.0
