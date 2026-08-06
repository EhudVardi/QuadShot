class_name WarManifest
extends RefCounted

## The manifest projection (GAMEPLAY-DESIGN P4.7): the war-sim's abstract
## garrison float becomes a NAMED UNIT LIST drawn from the P4 bestiary — what
## P1.3 promised ("an actual unit list, not an abstract strength 7") without
## making the war-sim carry per-unit books.
##
## It is a pure deterministic PROJECTION, never sim state. Nothing here is
## stored and the tick engine never calls it: same node in, same manifest out.
## So the briefing, the sortie and the harness all derive one truth, and the
## portable save (F4) stays exactly as small and as provable as it is today.
##
## The projection does NOT draw from the war's RNG stream — doing so would
## make looking at a node change the war. Its character is seeded from
## (theater seed, node id), so a node keeps its identity for the whole
## campaign (the SAM belt fields turrets at tick 3 and at tick 300) while the
## COUNTS follow the garrison float the tick engine is actually trading. That
## split is what makes P1.3's fog honest: degrade the detail far enough and a
## manifest regresses to exactly the abstract number the war-sim keeps.
##
## It is also the exchange rate BALANCE.md names: `unit_strength` prices a
## kinetic result (bodies you killed in your sortie) back into war currency,
## which is how "your fights dent the war" actually gets paid.

## The slice roster (P4.10). A type joins the manifest the day it ships.
##
## THE FALX AND THE SCREAMER JOINED LATE, and the gap is worth remembering
## (Iteration 12 / W8). Both shipped as playable types, went into the wave
## director, got behaviour checks and delivery cells — and this file never heard
## about either, so for two weeks the CAMPAIGN's bestiary was strictly smaller
## than the arcade's and no test could see it, because a roster nobody compares
## against is self-consistent. A type joins the manifest the day it ships, and
## `manifest_check` now asserts that against `WaveDirector.ROSTER` rather than
## trusting it.
const ROSTER: Array[StringName] = [
	&"raider", &"turret", &"gnat", &"aegis", &"falx", &"screamer", &"lance",
]

## Doctrine weights (P2.3 "doctrine-in-terrain", at the strategic scale):
## node type → the mix that garrisons it. Shares are of the node's STRENGTH
## budget, not of body count — a share is a share of what the garrison costs.
## Weights need not sum to 1; they are normalized. A type absent from a row
## simply does not garrison that node: `airspace` has no turrets because
## there is nothing out there to bolt one to.
## PROVISIONAL, and this is pacing — the human's call (handoff §14). The two
## late arrivals are placed by what the TYPE is for, not by what reads well:
##   - FALX is an interceptor that owns open air, so it garrisons the node types
##     that launch or contest aircraft (`airspace`, `airbase`) and nothing that
##     sits on the ground. It is the type you bait rather than chase, which is a
##     picket's job description.
##   - SCREAMER carries no weapon at all, so it only belongs where there is
##     something worth protecting: the sensor/denial belt (`sam`, `radar`) and
##     the command net. It is never the reason a node is defended, always the
##     reason the defence is hard to shoot at.
const DOCTRINE: Dictionary = {
	&"airspace": {&"raider": 0.45, &"gnat": 0.25, &"falx": 0.20, &"lance": 0.10},
	&"radar": {&"raider": 0.40, &"turret": 0.30, &"gnat": 0.15, &"screamer": 0.15},
	&"sam": {&"turret": 0.50, &"raider": 0.15, &"gnat": 0.10, &"screamer": 0.15,
			&"lance": 0.10},
	&"depot": {&"turret": 0.50, &"raider": 0.30, &"gnat": 0.20},
	&"factory": {&"turret": 0.45, &"gnat": 0.35, &"raider": 0.20},
	# THE AEGIS SITS ONLY WHERE BOMBERS ARE BASED (Iteration 14 / A.q1, decided
	# 2026-08-03). An airbase and the theater HQ have hangars; a command post and
	# a radar dish do not. The user's argument is fiction rather than arithmetic
	# and it is the right one: *"why would the enemy deploy his bombers in his own
	# teritory?"* A bomber at an airbase is a bomber at home; a bomber ringing a
	# radar dish is a design error you can see from the cockpit.
	#
	# Removing it from `command` costs nothing that has to be re-authored, because
	# `_weights` NORMALISES — the 0.30 redistributes across the remaining three in
	# proportion, so this edit deletes a type rather than retuning a node.
	#
	# The escalation anchor survives: `HEAVY_TYPES` is [aegis, screamer] and the
	# command post keeps its screamer. A7 is the open hole underneath — once the
	# aegis leaves defence, "the war escalates" leans hard on a jammer with no
	# weapon — and the Phalanx is the named answer, not scheduled here.
	&"airbase": {&"raider": 0.40, &"falx": 0.25, &"turret": 0.20, &"aegis": 0.15},
	&"command": {&"raider": 0.30, &"turret": 0.20, &"screamer": 0.20,
			&"lance": 0.15},
	&"hq": {&"aegis": 0.30, &"raider": 0.20, &"turret": 0.15, &"gnat": 0.10,
			&"falx": 0.15, &"screamer": 0.10},
}

## Cover density per biome (P1.9 / P4.5 cover economics). Dense ground nests
## swarms and thins the open-approach flyers; open ground does the reverse.
## Turrets ignore it — they are bolted down either way.
const COVER: Dictionary = {
	&"city": 1.00, &"industrial": 0.85, &"canyon": 0.80, &"hills": 0.40,
	&"coastal": 0.15, &"desert": 0.00, &"airfield_plains": 0.00,
}

## Types the cover tint treats as swarm / as open-approach flyers. The FALX is a
## flyer: it holds open approaches, so dense ground should thin it exactly as it
## thins a raider. The SCREAMER is deliberately in NEITHER list — it goes
## wherever the thing it escorts goes, so letting cover tint it would price the
## same decision twice (once on the escort, once on the escorted).
const SWARM_TYPES: Array[StringName] = [&"gnat"]
const FLYER_TYPES: Array[StringName] = [&"raider", &"aegis", &"falx", &"lance"]

## Escalation (P4.6) shifts the mix toward the expensive end rather than
## simply adding bodies — a war that has been running fields heavier things,
## it does not field more of the same. Clamped so escalation can never delete
## a type from a doctrine row (P1.7's guardrail: pressure, not replacement).
## The SCREAMER is heavy for escalation purposes, and that is a design claim
## rather than a cost bracket: electronic warfare is what a war fields once it
## has been running a while, so a theater under pressure should start hiding its
## sensor belt behind a jammer. The falx is deliberately neutral — an
## interceptor is a peacetime asset as much as a wartime one.
const ESCALATION_HEAVY_GAIN: float = 0.80
const ESCALATION_LIGHT_LOSS: float = 0.30
const HEAVY_TYPES: Array[StringName] = [&"aegis", &"screamer"]
const LIGHT_TYPES: Array[StringName] = [&"gnat"]

## Per-node character jitter, as a fraction of a weight. Two SAM sites in one
## theater should not be the same SAM site; this is the whole of that.
const CHARACTER_JITTER: float = 0.25

## Guard against a pathological fill loop. A garrison at the WarConfig cap
## (40) buys ~15 units at the cheapest unit price, so this is slack, not a
## design limit.
const MAX_UNITS: int = 64

## Intel freshness tiers (P1.3 / P4.7): detail degrades before quantity does,
## and the last stop is the abstract number the war-sim keeps.
const FOG_EXACT_AGE: int = 1
const FOG_FAMILIES_AGE: int = 5

## Family each type reports as once the count detail is gone.
##
## The SCREAMER reports as plain `air`, which is a deliberate design choice and
## not an oversight: it means **knowing there is EW on a node requires FRESH
## intel**. Give jamming its own family and a month-old report would still warn
## you; folding it into `air` makes "the lock will not build" the kind of
## surprise P1.3 says stale intel is supposed to produce. If that turns out to
## feel like a cheat rather than a consequence, this line is the one to change.
const FAMILIES: Dictionary = {
	&"raider": &"air", &"aegis": &"air", &"falx": &"air", &"screamer": &"air",
	&"gnat": &"swarm", &"turret": &"static",
}

static var _roster_cache: Dictionary = {}


## type_id → EnemyConfig, loaded from the COMMITTED defaults. Per BALANCE.md's
## third ruler the projection reads repo configs, never `user://` overrides:
## the war is priced in the numbers that ship.
static func roster() -> Dictionary:
	if not _roster_cache.is_empty():
		return _roster_cache
	for type_id: StringName in ROSTER:
		var config: EnemyConfig = load(
				"res://resources/default_enemy_%s.tres" % type_id) as EnemyConfig
		if config != null:
			_roster_cache[type_id] = config
	return _roster_cache


## War-currency price of ONE unit of a type. For a swarm the unit is the pack,
## not the body (P4.q5: "the cloud is the unit"), so the pack's bodies are
## priced together — which leaves `EnemyConfig.strength_cost` meaning exactly
## what it says on the field (per body) while the manifest counts units.
static func unit_strength(config: EnemyConfig) -> float:
	return config.strength_cost * maxf(config.pack_size, 1.0)


## Bodies in one unit of a type — 1 for everything but a swarm pack.
static func unit_bodies(config: EnemyConfig) -> int:
	return maxi(int(config.pack_size), 1)


## The projection. Returns an ordered Array of
## `{type, count, bodies, strength}` — serializable, so it round-trips
## var_to_str with the rest of the war state.
##
## `escalation` is WarSim.escalation(state, config); pass 0.0 for the paper
## mix. The node dict is the war-sim's own node, read-only here.
static func project(node: Dictionary, theater_seed: int,
		escalation: float = 0.0) -> Array:
	var budget: float = float(node["garrison"])
	var weights: Dictionary = _weights(node, theater_seed, escalation)
	if weights.is_empty() or budget <= 0.0:
		return []

	var costs: Dictionary = {}
	var cheapest: float = INF
	for type_id: StringName in weights:
		var cost: float = unit_strength(roster()[type_id])
		costs[type_id] = cost
		cheapest = minf(cheapest, cost)

	# Deterministic greedy fill: each step buys the type furthest BELOW its
	# target share of the strength spent so far. No dice — the character
	# jitter above already happened, in the weights.
	var counts: Dictionary = {}
	var spent: float = 0.0
	var remaining: float = budget
	var guard: int = 0
	while remaining >= cheapest - 0.0005 and guard < MAX_UNITS:
		guard += 1
		var pick: StringName = &""
		var worst_deficit: float = -INF
		for type_id: StringName in weights:
			var cost: float = costs[type_id]
			if cost > remaining + 0.0005:
				continue
			var have: float = float(counts.get(type_id, 0)) * cost
			var share: float = have / spent if spent > 0.0 else 0.0
			var deficit: float = float(weights[type_id]) - share
			# Ties break on the roster's fixed order, never on dictionary
			# iteration order, so the fill is stable across engine versions.
			if deficit > worst_deficit:
				worst_deficit = deficit
				pick = type_id
		if pick == &"":
			break
		counts[pick] = int(counts.get(pick, 0)) + 1
		spent += costs[pick]
		remaining -= costs[pick]

	_enforce_escort_rule(counts, weights, costs)

	var units: Array = []
	for type_id: StringName in ROSTER:
		if not counts.has(type_id):
			continue
		var config: EnemyConfig = roster()[type_id]
		var count: int = int(counts[type_id])
		units.append({
			"type": type_id,
			"count": count,
			"bodies": unit_bodies(config) * count,
			# Quantized like every other evolving float in the war state, so
			# the manifest round-trips var_to_str bit-exactly (F4).
			"strength": WarSim.quantize(unit_strength(config) * float(count)),
		})
	return units


## War-currency total of a manifest (or of any subset of one — the same
## function prices what you KILLED, which is the dent direction).
static func strength_of(units: Array) -> float:
	var total: float = 0.0
	for unit: Dictionary in units:
		total += float(unit["strength"])
	return WarSim.quantize(total)


## Kinetic result → war currency (P2.q4: every kill dents the node). `kills`
## maps type_id → BODIES destroyed, which is what a sortie can actually count;
## a half-cleared gnat pack therefore dents by half a pack, not by nothing.
static func dent_from_kills(kills: Dictionary) -> float:
	var total: float = 0.0
	for type_id: StringName in kills:
		if not roster().has(type_id):
			continue
		var config: EnemyConfig = roster()[type_id]
		total += config.strength_cost * float(kills[type_id])
	return WarSim.quantize(total)


## How much of a manifest intel can resolve at this freshness (P1.3).
static func detail_for_age(intel_age: int) -> StringName:
	if intel_age <= FOG_EXACT_AGE:
		return &"exact"
	if intel_age <= FOG_FAMILIES_AGE:
		return &"families"
	return &"strength"


## The manifest as INTEL believes it (P4.7). Detail degrades before quantity:
## exact counts → families → the abstract strength the war-sim actually keeps.
## The briefing runs the composer against this; the sortie runs it against
## truth, and the divergence is the designed surprise.
static func through_fog(units: Array, intel_age: int) -> Dictionary:
	var detail: StringName = detail_for_age(intel_age)
	var report: Dictionary = {"detail": detail, "strength": strength_of(units)}
	if detail == &"exact":
		report["units"] = units.duplicate(true)
	elif detail == &"families":
		var families: Dictionary = {}
		for unit: Dictionary in units:
			var family: StringName = FAMILIES.get(unit["type"], &"air")
			families[family] = WarSim.quantize(
					float(families.get(family, 0.0)) + float(unit["strength"]))
		report["families"] = families
	return report


## ---------- internals ----------

## Types that put NO pressure on the player at all. The aegis is deliberately
## absent: it carries no gun but it is on a clock against you, so a garrison of
## bombers is a fight you can lose. The screamer is the only true escort — it
## cannot hurt you by any route, and a node defended entirely by jammers is a
## node you fly through untouched while your lock refuses to build.
##
## Mirrors `WaveDirector.ROSTER`'s `threat` flag on purpose. The two tables are
## the same design statement at two scales, and `manifest_check` asserts they
## agree so they cannot drift into disagreeing about what an escort is.
const NO_THREAT_TYPES: Array[StringName] = [&"screamer"]


## Guarantee a garrison contains something that can fight back (P4.3's escort
## rule, at the strategic scale). ENFORCED, not merely stated — `DOCTRINE` above
## is data, and data gets edited by someone who is not reading this function.
##
## Reachable because the fill is greedy over strength: a small garrison on a
## `sam` or `command` node can buy one expensive jammer and then have too little
## left for anything else. That sortie would be a walk-in with a broken lock and
## no threat, which reads as the composer being broken rather than as a quiet
## node.
##
## The swap is strength-neutral by construction — the escort's budget is spent
## on whole units of the cheapest thing that DOES threaten — so the manifest
## still spends exactly the garrison it was handed and the exchange rate stays
## exact.
static func _enforce_escort_rule(counts: Dictionary, weights: Dictionary,
		costs: Dictionary) -> void:
	if counts.is_empty():
		return
	for type_id: StringName in counts:
		if not type_id in NO_THREAT_TYPES:
			return

	# Cheapest threatening type this node's doctrine actually allows, so the
	# substitution never fields something the node type would never garrison.
	var swap: StringName = &""
	for type_id: StringName in ROSTER:
		if type_id in NO_THREAT_TYPES or not weights.has(type_id):
			continue
		if swap == &"" or float(costs[type_id]) < float(costs[swap]):
			swap = type_id
	if swap == &"":
		push_warning("[manifest] doctrine for this node has no type that threatens")
		return

	var freed: float = 0.0
	for type_id: StringName in counts:
		freed += float(costs[type_id]) * float(counts[type_id])
	var bought: int = int(floor(freed / maxf(float(costs[swap]), 0.0001)))
	if bought <= 0:
		return
	counts.clear()
	counts[swap] = bought


## Doctrine × biome cover × escalation × per-node character, normalized.
static func _weights(node: Dictionary, theater_seed: int,
		escalation: float) -> Dictionary:
	var doctrine: Dictionary = DOCTRINE.get(node["type"], DOCTRINE[&"airspace"])
	var cover: float = float(COVER.get(node["biome"], 0.5))
	# Seeded from the node's identity, NOT from the war's RNG: reading a
	# manifest must never move the war. The mix is written out rather than
	# using hash() so the seed is stable across engine versions — a portable
	# save (F4) that re-projects differently on a new Godot is not portable.
	var rng := RandomNumberGenerator.new()
	rng.seed = theater_seed * 1000003 + int(node["id"]) * 31

	var weights: Dictionary = {}
	var total: float = 0.0
	for type_id: StringName in ROSTER:
		if not doctrine.has(type_id) or not roster().has(type_id):
			continue
		var weight: float = float(doctrine[type_id])
		if type_id in SWARM_TYPES:
			weight *= 0.6 + cover * 0.8
		elif type_id in FLYER_TYPES:
			weight *= 1.25 - cover * 0.45
		if type_id in HEAVY_TYPES:
			weight *= 1.0 + maxf(escalation, 0.0) * ESCALATION_HEAVY_GAIN
		elif type_id in LIGHT_TYPES:
			weight *= maxf(1.0 - maxf(escalation, 0.0) * ESCALATION_LIGHT_LOSS, 0.2)
		weight *= 1.0 + rng.randf_range(-CHARACTER_JITTER, CHARACTER_JITTER)
		weight = maxf(weight, 0.0001)
		weights[type_id] = weight
		total += weight

	for type_id: StringName in weights:
		weights[type_id] = float(weights[type_id]) / total
	return weights
