class_name SortieComposer
extends RefCounted

## The composer (GAMEPLAY-DESIGN Iteration 5, P2.1–P2.13): the function that
## turns a node on the war map into the fight you fly.
##
##     compose(node, war_state, config) -> sortie_spec
##
## Everything the five pillars built is an ingredient; this is the recipe.
## Node TYPE picks the objective and archetype (P2.2), the MANIFEST supplies
## the garrison (P4.7/P2.3), the BIOME supplies map geometry and the approach
## (P2.4), and weather/pads/escalation tune the difficulty organically
## (P2.11). No hand-authored levels: a sortie is a projection of the war.
##
## Pure and deterministic (F4), like everything else in war/: same node in the
## same war state produces the same spec forever, which is what lets the
## harness fight composed sorties headless and a portable save replay them
## honestly. The spec is a plain serializable Dictionary — the scene layer
## instantiates it; nothing here knows what a Node3D is.
##
## TWO EVALUATIONS OF ONE FUNCTION (P2.1). `compose` runs against TRUTH — what
## is actually out there. `compose_briefing` runs against the manifest seen
## through intel fog (P1.3), which is what you *think* you'll face. Fresh
## intel: the two agree. Stale intel: they diverge, and the surprise is
## DESIGNED rather than random.
##
## WHAT THIS FILE DELIBERATELY DOES NOT EMIT: a difficulty scalar. H6 is
## explicit that SDI is *measured, not authored* — the composer sets INPUTS
## and the harness flies the reference pilot against the result to read the
## difficulty back out. So `difficulty_inputs` carries the raw H.q2 axis
## vector (garrison / cover / weather / pads / escalation / fortification) for
## diagnosis, and no composite number. A composer that scored its own output
## would be grading its own homework, and "organic difficulty" would quietly
## become a hand-tuned level knob.

## Bumped when the spec's SHAPE changes, so a saved sortie can be rejected
## rather than misread.
const SPEC_VERSION: int = 1

## Node type → the fight it becomes (P2.2). The objective is what captures or
## degrades the node (P2.9); the archetype is what it feels like to fly.
## `assets` is how many objective structures must die (0 = the garrison IS the
## objective, which is the dogfight).
const ARCHETYPES: Dictionary = {
	&"factory": {"archetype": &"strike", "objective": &"destroy_production", "assets": 3},
	&"radar": {"archetype": &"sead", "objective": &"kill_dish", "assets": 1},
	&"sam": {"archetype": &"sead", "objective": &"kill_launchers", "assets": 3},
	&"airbase": {"archetype": &"strike_cap", "objective": &"crater_runway", "assets": 2},
	&"command": {"archetype": &"decapitation", "objective": &"kill_commander", "assets": 1},
	&"depot": {"archetype": &"interdiction", "objective": &"destroy_stores", "assets": 3},
	&"airspace": {"archetype": &"dogfight", "objective": &"clear_airspace", "assets": 0},
	&"hq": {"archetype": &"raid", "objective": &"break_the_theater", "assets": 4},
}

## What the slice can actually INSTANTIATE (P2.13's cut: one Strike, one
## Dogfight). The composer emits a correct spec for every archetype because
## the table is data and costs nothing — but the boundary is stated here in
## code rather than discovered by a scene failing to build one.
const SLICE_ARCHETYPES: Array[StringName] = [&"strike", &"dogfight"]

## Fraction of the node's garrison held back as TRIGGERED REINFORCEMENTS
## (P2.3), by archetype. Reserves are taken OUT of the placed garrison, never
## added on top: the manifest is the node's whole strength, and reinforcements
## are part of it arriving later. That keeps the exchange rate exact — clear
## everything a sortie can field and you have dented the node by precisely its
## garrison — and it means escalation can never conjure free bodies (P4.6's
## "only within what surviving production affords").
const RESERVE: Dictionary = {
	&"strike": 0.20,        # escorts converge; their tick is your clock
	&"strike_cap": 0.35,    # an airbase launching is the whole archetype
	&"sead": 0.25,          # the dish calls interceptors onto you
	&"decapitation": 0.30,  # touch the VIP and the elites counter-push
	&"interdiction": 0.15,
	&"dogfight": 0.40,      # waves ARE the archetype (the M3 loop's home)
	&"raid": 0.35,
}

## What springs the reserve (P2.3: deterministic responses to player action,
## never RNG spawns — replayability and an honest harness demand it, and it
## makes staying unseen real counterplay).
const TRIGGER_ON: Dictionary = {
	&"strike": &"objective_damaged",
	&"strike_cap": &"detected",
	&"sead": &"detected",
	&"decapitation": &"objective_damaged",
	&"interdiction": &"objective_damaged",
	&"dogfight": &"wave_cleared",
	&"raid": &"detected",
}

## How each type distributes through P2.3's concentric layers: outer patrols
## and pickets → mid area-denial → inner guard. Reading the layers IS reading
## your ingress (P2.4).
const LAYERING: Dictionary = {
	&"raider": {&"outer": 0.6, &"inner": 0.4},
	&"gnat": {&"outer": 0.7, &"mid": 0.3},
	&"turret": {&"mid": 0.7, &"inner": 0.3},
	&"aegis": {&"inner": 1.0},
	# The falx holds open approaches (P2.3's doctrine-in-terrain), which is the
	# outer ring by definition — it is the thing you meet before you have
	# committed to a line, and the one you are supposed to bait rather than
	# chase.
	&"falx": {&"outer": 1.0},
	# The screamer sits with what it protects, so it rides the mid ring where the
	# area denial lives. Putting it outer would let a pilot kill the jammer
	# before entering the bubble, which is the opposite of the type's point;
	# putting it inner would mean the jam only bites after the hard part.
	&"screamer": {&"mid": 1.0},
}

const LAYER_ORDER: Array[StringName] = [&"outer", &"mid", &"inner"]

## Sensor/handling penalty per weather state (P1.6 modifier pack, P2.8). An
## input to difficulty, not a difficulty score.
const WEATHER_PENALTY: Dictionary = {
	&"clear": 0.0, &"wind": 0.10, &"rain": 0.20,
	&"fog": 0.30, &"heat": 0.15, &"sandstorm": 0.35,
}

## Pads (P2.6) are a difficulty knob the strategic layer sets: hard nodes are
## pad-poor. HQ and command posts have none at all.
const PAD_MAX: int = 3
const PADLESS_TYPES: Array[StringName] = [&"hq", &"command"]

## Approach geometry (P2.4): open ground means a long exposed ingress, dense
## ground a short one with lines to mask behind.
const INGRESS_OPEN_M: float = 400.0
const INGRESS_COVER_M: float = 250.0


## Compose the sortie you will actually fly — against TRUTH.
static func compose(node: Dictionary, state: Dictionary,
		config: WarConfig) -> Dictionary:
	return _compose(node, state, config, true)


## Compose what the BRIEFING believes (P2.1/P1.3): the same function run
## against the manifest through intel fog. Never instantiate this one — it is
## for the command room. Where fog has eaten the detail the spec says so
## (`garrison_detail`) instead of inventing bodies.
static func compose_briefing(node: Dictionary, state: Dictionary,
		config: WarConfig) -> Dictionary:
	return _compose(node, state, config, false)


## The sortie's own seed. Stable for a given (theater, node, tick) so a
## briefing and the sortie it previews lay out the same ground — and moving on
## a node a tick later is a genuinely different fight, because the war moved.
static func sortie_seed(node: Dictionary, state: Dictionary) -> int:
	return int(state["seed"]) * 1000003 + int(node["id"]) * 31 \
			+ int(state["tick"]) * 7919


## Is this archetype something the slice can build a scene for (P2.13)?
static func is_slice_ready(spec: Dictionary) -> bool:
	return spec["archetype"] in SLICE_ARCHETYPES


## Everything the sortie can field, flattened — the placed layers plus every
## reserve that could still arrive. This is the sum a completed sortie is
## priced against, and it must equal the node's garrison (P2.q4).
static func total_strength(spec: Dictionary) -> float:
	var total: float = 0.0
	for layer: StringName in LAYER_ORDER:
		total += WarManifest.strength_of(spec["layers"][layer])
	for trigger: Dictionary in spec["triggers"]:
		total += WarManifest.strength_of(trigger["units"])
	return WarSim.quantize(total)


## ---------- the recipe ----------

static func _compose(node: Dictionary, state: Dictionary, config: WarConfig,
		truth: bool) -> Dictionary:
	var seed_value: int = sortie_seed(node, state)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var escalation: float = WarSim.escalation(state, config)
	var recipe: Dictionary = ARCHETYPES.get(node["type"], ARCHETYPES[&"airspace"])
	var archetype: StringName = recipe["archetype"]
	var intel_age: int = int(node.get("intel_age", 0))
	var cover: float = float(WarManifest.COVER.get(node["biome"], 0.5))
	var weather: StringName = node.get("weather", &"clear")

	# The garrison, seen the way this evaluation is allowed to see it.
	var truth_units: Array = WarManifest.project(node, int(state["seed"]), escalation)
	var detail: StringName = &"exact" if truth \
			else WarManifest.detail_for_age(intel_age)
	var units: Array = truth_units if detail == &"exact" else []

	# Reserves come OUT of the garrison, so the books stay balanced.
	var split: Dictionary = _split_reserve(units, float(RESERVE.get(archetype, 0.2)))
	var pads: int = _pads(node, config, escalation)

	var spec: Dictionary = {
		"version": SPEC_VERSION,
		"seed": seed_value,
		"truth": truth,
		"node_id": int(node["id"]),
		"node_type": node["type"],
		"biome": node["biome"],
		"weather": weather,
		"archetype": archetype,
		"objective": recipe["objective"],
		"objective_assets": int(recipe["assets"]),
		# P1.q2 / P2.9: an assault next to ground you hold CAPTURES; a deep
		# strike with nothing to hold it only degrades. Read from the tick
		# engine's own helper so the two can never disagree.
		"capture": WarSim.has_adjacent_owner(state, node, &"player"),
		"intel_age": intel_age,
		"garrison_detail": detail,
		"garrison_strength": WarManifest.strength_of(truth_units) if truth \
				else WarSim.quantize(float(node["garrison"])),
		"layers": _layer(split["placed"], archetype),
		"triggers": _triggers(split["reserve"], archetype, rng),
		"approach": _approach(cover, rng),
		"pads": pads,
		"dares": _dares(cover, rng),
		# The H.q2 axis vector: WHY a node is hard, for diagnosis and tuning.
		# Deliberately no composite scalar — see the file header.
		"difficulty_inputs": {
			"garrison_strength": WarSim.quantize(float(node["garrison"])),
			"cover": WarSim.quantize(cover),
			"weather": weather,
			"weather_penalty": float(WEATHER_PENALTY.get(weather, 0.0)),
			"pads": pads,
			"escalation": WarSim.quantize(escalation),
			"fortification": WarSim.quantize(float(node.get("fort", 1.0))),
		},
	}
	# A fogged briefing still reports what intel CAN resolve, rather than
	# silently showing an empty node.
	if not truth:
		spec["intel"] = WarManifest.through_fog(truth_units, intel_age)
	return spec


## Hold back `fraction` of the garrison's STRENGTH as reserve, taking whole
## units from the outer-layer types first — a node commits its pickets and
## holds its reaction force, not the other way round.
static func _split_reserve(units: Array, fraction: float) -> Dictionary:
	var total: float = WarManifest.strength_of(units)
	var target: float = total * clampf(fraction, 0.0, 0.9)
	var placed: Array = []
	var reserve: Array = []
	var held: float = 0.0
	# Cheapest first, so the reserve lands close to its target instead of
	# overshooting on one expensive body.
	var order: Array = units.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: float = float(a["strength"]) / maxf(float(a["count"]), 1.0)
		var cb: float = float(b["strength"]) / maxf(float(b["count"]), 1.0)
		if is_equal_approx(ca, cb):
			return String(a["type"]) < String(b["type"])
		return ca < cb)

	# "Never reserve the entire garrison" is a GLOBAL constraint, not a
	# per-type one: a small node whose types are one unit each must still be
	# able to hold a reaction force, or the Strike's "escorts converge" promise
	# quietly evaporates on exactly the light targets a new pilot flies first.
	var total_units: int = 0
	for unit: Dictionary in units:
		total_units += int(unit["count"])
	var reserved_units: int = 0

	for unit: Dictionary in order:
		var count: int = int(unit["count"])
		var per_unit: float = float(unit["strength"]) / maxf(float(count), 1.0)
		var want: int = 0
		while want < count and held + per_unit <= target + 0.0005 \
				and reserved_units + 1 < total_units:
			want += 1
			held += per_unit
			reserved_units += 1
		if want > 0:
			reserve.append(_scaled(unit, want))
		if want < count:
			placed.append(_scaled(unit, count - want))
	return {"placed": _in_roster_order(placed), "reserve": _in_roster_order(reserve)}


## Concentric placement (P2.3). The objective sits behind outer pickets, mid
## area-denial and an inner guard; a type's doctrine says where it belongs.
static func _layer(units: Array, archetype: StringName) -> Dictionary:
	var layers: Dictionary = {&"outer": [], &"mid": [], &"inner": []}
	for unit: Dictionary in units:
		var count: int = int(unit["count"])
		if count <= 0:
			continue
		# A dogfight has no rings to hold — the enemy comes to you (P2.12: the
		# wave director is this archetype, demoted from "the game").
		var weights: Dictionary = {&"outer": 1.0} if archetype == &"dogfight" \
				else LAYERING.get(unit["type"], {&"outer": 1.0})
		for layer: StringName in LAYER_ORDER:
			if not weights.has(layer):
				continue
			var share: int = int(floor(float(count) * float(weights[layer])))
			if share > 0:
				layers[layer].append(_scaled(unit, share))
		# Remainders land in the type's heaviest layer, so rounding never
		# quietly deletes a body from the node's books.
		var placed: int = 0
		for layer: StringName in LAYER_ORDER:
			for entry: Dictionary in layers[layer]:
				if entry["type"] == unit["type"]:
					placed += int(entry["count"])
		if placed < count:
			var home: StringName = _heaviest_layer(weights)
			var found: bool = false
			for entry: Dictionary in layers[home]:
				if entry["type"] == unit["type"]:
					_grow(entry, count - placed, unit)
					found = true
					break
			if not found:
				layers[home].append(_scaled(unit, count - placed))
	for layer: StringName in LAYER_ORDER:
		layers[layer] = _in_roster_order(layers[layer])
	return layers


## The reserve, turned into deterministic trigger payloads (P2.3). A dogfight
## splits its reserve into successive waves; everything else commits its
## reaction force in one response.
static func _triggers(reserve: Array, archetype: StringName,
		rng: RandomNumberGenerator) -> Array:
	if reserve.is_empty():
		return []
	var on: StringName = TRIGGER_ON.get(archetype, &"detected")
	if archetype == &"dogfight":
		var waves: Array = []
		var wave_count: int = 2
		for index: int in wave_count:
			var slice_units: Array = []
			for unit: Dictionary in reserve:
				var count: int = int(unit["count"])
				var take: int = count / wave_count
				if index == wave_count - 1:
					take = count - (count / wave_count) * (wave_count - 1)
				if take > 0:
					slice_units.append(_scaled(unit, take))
			if not slice_units.is_empty():
				waves.append({
					"on": on, "wave": index + 1,
					"after_s": WarSim.quantize(1.5 + float(index) * 2.0),
					"units": _in_roster_order(slice_units),
				})
		return waves
	# Response delay is seeded, not random at runtime: the same sortie always
	# gives you the same window to work in.
	return [{
		"on": on, "wave": 1,
		"after_s": WarSim.quantize(rng.randf_range(4.0, 10.0)),
		"units": reserve,
	}]


## Ingress geometry (P2.4). Not a rail: the biome offers corridors and the
## pilot picks masking vs. speed vs. angle.
static func _approach(cover: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"ingress_m": WarSim.quantize(INGRESS_OPEN_M - cover * INGRESS_COVER_M, 1),
		"cover": WarSim.quantize(cover),
		"corridors": 1 + int(round(cover * 3.0)),
		"bearing_deg": WarSim.quantize(rng.randf_range(0.0, 360.0), 1),
	}


## Pads scale inversely with the node's difficulty (P2.6): hard nodes are
## pad-poor, and the enemy's brain-nodes have none.
static func _pads(node: Dictionary, config: WarConfig, escalation: float) -> int:
	if node["type"] in PADLESS_TYPES:
		return 0
	var load: float = clampf(float(node["garrison"]) / maxf(config.garrison_cap, 1.0),
			0.0, 1.0)
	var budget: float = float(PAD_MAX) - load * 2.5 - maxf(escalation, 0.0) * 0.5
	return clampi(int(round(budget)), 0, PAD_MAX)


## Dares (P2.7): optional, unmarked, risk-priced flying. Dense ground has gaps
## worth threading; a desert does not. Slice cap is one.
static func _dares(cover: float, rng: RandomNumberGenerator) -> Array:
	if rng.randf() > 0.35 + cover * 0.4:
		return []
	var kinds: Array[StringName] = [&"threading_gap", &"tunnel_run", &"slab_gap"]
	return [{
		"kind": kinds[rng.randi_range(0, kinds.size() - 1)],
		"reward": &"salvage_cache",
	}]


## ---------- small helpers ----------

## A copy of a manifest unit at a different count, re-priced from the roster
## so `strength` and `bodies` can never drift from `count`.
static func _scaled(unit: Dictionary, count: int) -> Dictionary:
	var config: EnemyConfig = WarManifest.roster()[unit["type"]]
	return {
		"type": unit["type"],
		"count": count,
		"bodies": WarManifest.unit_bodies(config) * count,
		"strength": WarSim.quantize(WarManifest.unit_strength(config) * float(count)),
	}


static func _grow(entry: Dictionary, extra: int, source: Dictionary) -> void:
	var grown: Dictionary = _scaled(source, int(entry["count"]) + extra)
	entry["count"] = grown["count"]
	entry["bodies"] = grown["bodies"]
	entry["strength"] = grown["strength"]


## Stable output ordering: the roster's fixed order, never dictionary or sort
## order, so two runs of the composer diff cleanly.
static func _in_roster_order(units: Array) -> Array:
	var ordered: Array = []
	for type_id: StringName in WarManifest.ROSTER:
		for unit: Dictionary in units:
			if unit["type"] == type_id and int(unit["count"]) > 0:
				ordered.append(unit)
	return ordered


static func _heaviest_layer(weights: Dictionary) -> StringName:
	var best: StringName = &"outer"
	var best_weight: float = -1.0
	for layer: StringName in LAYER_ORDER:
		if weights.has(layer) and float(weights[layer]) > best_weight:
			best_weight = float(weights[layer])
			best = layer
	return best
