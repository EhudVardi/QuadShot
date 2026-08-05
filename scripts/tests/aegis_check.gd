extends SceneTree

## Headless behaviour check for the REWORKED AEGIS (Iteration 14 / A2, A.q1-A.q3).
## The twentieth check, and it lands the day the rework does — standing rule 2:
## *every new type or mechanic gets a behaviour check the day it lands*, because
## a results table can only ever say "this cell reads 0%", which is equally
## consistent with a tough enemy, a broken enemy, and an enemy that flew out of
## the level. The aegis has already been all three.
##
## THE SCAR IT EXISTS FOR is on the record. The aegis spent months aimed at the
## sortie's own centre, so the enemy's bomber flew into the middle of the base it
## was defending and detonated on its own objective — and the way that surfaced
## was `sortie_bench` reading node 16 as three reps of 300 s, 0% hull taken,
## nothing killed. Nothing there could threaten the pilot and the pilot could not
## threaten it. A behaviour check is what turns that from a mystery into a line.
##
## Six things it holds, each of which is a decision somebody made:
##
##   1. A2 - a bomber with a payload flies PASSES and survives them. It drops,
##      climbs away, comes back, and is not spent on arrival.
##   2. A.q2 - the payload is a MAGAZINE in the player's own vocabulary: it
##      spends, it refuses when dry, and it reports capacity the same way.
##   3. A2 - when the payload is gone it EGRESSES and `escaped` fires, which is a
##      different outcome from being killed.
##   4. A.q1 - the aegis appears ONLY where bombers are based (airbase, HQ) and
##      never in a defensive garrison.
##   5. A.q1 - a composed sortie aims it OUTWARD, not at its own objective.
##   6. A.q3 - an escaped bomber costs the PLAYER ground, and the war says which.
##
## Plus the hazard the magazine grammar introduced: an enemy magazine must not be
## refillable by the player's own resupply gates.
##
## Run: <godot> --headless -s scripts/tests/aegis_check.gd --path .

const THEATER_SEED: int = 4242
const MAX_SECONDS: float = 40.0

var _failures: int = 0
var _arena: Node3D
var _aegis: Aegis
var _drops: Array[Vector3] = []
var _escaped: int = 0
var _detonated: int = 0
var _ticks: int = 0
var _stage: int = 0
var _seen_two_passes: bool = false
var _alive_when_unit_ended: bool = false
var _drops_when_unit_ended: int = -1
var _height_between_passes: float = -1.0


func _initialize() -> void:
	_check_doctrine()
	_check_magazine_grammar()
	_check_outward_route()
	_check_escaped_bomber_costs_you()
	if _failures > 0:
		_report()
		return
	_fly_it()


## ---------- A.q1: where the aegis lives ----------

## A BOMBER AT AN AIRBASE IS A BOMBER AT HOME; a bomber ringing a radar dish is a
## design error you can see from the cockpit. Asserted over the doctrine table
## directly rather than through a generated theater, so it keeps working on a
## seed that happens not to roll a command post.
func _check_doctrine() -> void:
	var based: Array[StringName] = [&"airbase", &"hq"]
	var wrong: PackedStringArray = []
	for node_type: StringName in WarManifest.DOCTRINE:
		var has_aegis: bool = WarManifest.DOCTRINE[node_type].has(&"aegis")
		if has_aegis and not based.has(node_type):
			wrong.append(String(node_type))
	_expect(wrong.is_empty(),
			"the aegis appears only where bombers are BASED (stray: %s)"
			% ", ".join(wrong))
	# The other half, or "delete the aegis from doctrine entirely" would pass.
	for node_type: StringName in based:
		_expect(WarManifest.DOCTRINE[node_type].has(&"aegis"),
				"and it DOES appear at the %s" % node_type)
	# A4's warning, held rather than remembered: the HQ has to keep fielding a
	# heavy type or the escalation mechanic loses its anchor.
	_expect(WarManifest.HEAVY_TYPES.has(&"aegis"),
			"the aegis is still a heavy type, so escalation still has an anchor")


## ---------- A.q2: the payload is a magazine ----------

## THE SAME VOCABULARY THE PLAYER'S LAUNCHERS USE, asserted against the player's
## launchers rather than against a copy of the rules — if the two ever diverge
## the "one mechanism covers both" claim is what broke.
func _check_magazine_grammar() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	_expect(config.payload > 0,
			"the shipped aegis carries a payload (%d)" % config.payload)

	var bomber := Aegis.new()
	bomber.enemy_config = config
	for method: StringName in [&"magazine", &"unlimited", &"has_ammo", &"rearm"]:
		_expect(bomber.has_method(method),
				"a bomber answers `%s`, exactly as a flak pod does" % method)
	_expect(bomber.get(&"ammo_kind") != null, "and carries an ammo_kind")
	bomber.free()

	# THE HAZARD THE GRAMMAR INTRODUCED. `ResupplyGate` and `Salvage` refill
	# everything in the `magazines` group that matches their `kind`, so an enemy
	# bomber joining that group must not be refillable by the player's own gates.
	# Asserted as a property rather than trusted: gates are only ever laid as
	# `flak` or `missile`, and `bomb` matches neither.
	var kinds: Array[StringName] = [&"flak", &"missile"]
	_expect(not kinds.has(StringName(&"bomb")),
			"no resupply gate kind matches a bomb, so the player cannot rearm a bomber")


## ---------- A.q1: it flies OUTWARD ----------

## THE DRIFT A1 NAMED, held so it cannot come back. The runner used to aim the
## bomber at the sortie's own centre — the enemy's objective — and the assertion
## that catches that is not "the route is not the centre" but "the route is on
## the PLAYER'S side of it", because a route offset in any random direction would
## satisfy the weaker one.
func _check_outward_route() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var checked: int = 0
	var inward: int = 0
	var off_corridor: int = 0
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy":
			continue
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if not SortieComposer.is_slice_ready(spec):
			continue
		checked += 1
		var center := Vector3.ZERO
		var ingress: Vector3 = SortieRunner.ingress_direction(spec)
		var route: Vector3 = center + ingress * SortieRunner.BOMB_RUN_OUT_M \
				+ Vector3.UP * SortieRunner.BOMB_RUN_HEIGHT
		var flat := Vector3(route.x, 0.0, route.z)
		if flat.length() < 1.0:
			inward += 1
			continue
		# On the player's side: the run must point the same way the pilot came
		# from, not merely somewhere that is not the middle.
		if flat.normalized().dot(ingress) < 0.99:
			off_corridor += 1
	_expect(checked > 0, "the theater offers sorties to route a bomber on (%d)" % checked)
	_expect(inward == 0,
			"no bomb run ends on the objective the bomber is defending (%d did)" % inward)
	_expect(off_corridor == 0,
			"and every run heads out along the corridor the pilot came in on (%d off)"
			% off_corridor)
	# It has to LEAVE the base, or "outward" is a rounding error.
	_expect(SortieRunner.BOMB_RUN_OUT_M
			> float(SortieRunner.LAYER_RADIUS[&"outer"]) + SortieRunner.LAYER_JITTER,
			"the run ends past the outer ring (%.0f m vs %.0f m)"
			% [SortieRunner.BOMB_RUN_OUT_M,
			float(SortieRunner.LAYER_RADIUS[&"outer"]) + SortieRunner.LAYER_JITTER])


## ---------- A.q3: an escaped bomber costs YOU ----------

## Hand-built rather than generated, because the assertion is about WHICH node
## pays and a generated theater gives no control over adjacency. Two player nodes
## at different distances, so "the nearest one" is a claim with a wrong answer
## available — with one player node it would pass by having nowhere else to go.
func _check_escaped_bomber_costs_you() -> void:
	var config := WarConfig.new()
	var state: Dictionary = _raid_state()
	var near_before: float = float(WarSim.node_by_id(state, 1)["garrison"])
	var far_before: float = float(WarSim.node_by_id(state, 3)["garrison"])

	var clean: Dictionary = WarSim.apply_sortie(state, config, _raid_result(0))
	_expect(int(clean.get("bombers_escaped", -1)) == 0,
			"a sortie with no escape reports none")
	_expect(is_equal_approx(float(WarSim.node_by_id(state, 1)["garrison"]), near_before),
			"and costs the player nothing")

	state = _raid_state()
	var raided: Dictionary = WarSim.apply_sortie(state, config, _raid_result(2))
	var near_after: float = float(WarSim.node_by_id(state, 1)["garrison"])
	var far_after: float = float(WarSim.node_by_id(state, 3)["garrison"])
	_expect(int(raided["bombers_escaped"]) == 2, "two bombers away are reported as two")
	_expect(near_after < near_before,
			"the nearest player node pays for the raid (%.1f -> %.1f)"
			% [near_before, near_after])
	_expect(is_equal_approx(far_after, far_before),
			"and the far one does not (%.1f -> %.1f)" % [far_before, far_after])
	_expect(int(raided["bombed_node_id"]) == 1,
			"the summary names which of your nodes was hit (got %d)"
			% int(raided["bombed_node_id"]))
	_expect(is_equal_approx(float(raided["bombed_loss"]),
			config.bomber_damage * 2.0),
			"and how much it cost, scaled by how many got through (%.1f)"
			% float(raided["bombed_loss"]))
	# It must NOT be netted off the dent: what you did to them and what they did
	# to you are different sentences.
	_expect(is_equal_approx(float(raided["dent"]), 6.0),
			"while the dent still reports only what the PILOT destroyed (%.1f)"
			% float(raided["dent"]))

	var lines: String = "\n".join(WarDebrief.lines({
		"summary": raided, "outcome": &"partial", "kills": {},
		"objectives_destroyed": 0, "objective_assets": 0, "egressed": true,
		"pilot_lost": false, "tick_before": 0, "tick_after": 1,
		"pilots_left": 4, "winner": &"",
	}))
	_expect(lines.contains("GOT AWAY"),
			"the debrief tells the player a bomber got through")


func _raid_state() -> Dictionary:
	return {
		"seed": 77, "tick": 2, "pilots": 4, "sorties": 0, "winner": &"",
		"rng_state": 0, "aggression": 0.5, "caution": 0.4,
		"nodes": [
			_node(0, 0, 0, &"airbase", &"player", 20.0),
			_node(1, 2, 0, &"airspace", &"player", 12.0),
			_node(2, 3, 0, &"airbase", &"enemy", 20.0),
			_node(3, 8, 0, &"airspace", &"player", 12.0),
		],
	}


func _raid_result(escaped: int) -> Dictionary:
	return {
		"node_id": 2, "seed": 1, "archetype": &"strike_cap",
		"objective_assets": 2, "objectives_destroyed": 0,
		"objective_complete": false, "egressed": true, "pilot_lost": false,
		"outcome": &"partial", "kills": {&"raider": 6}, "dent": 6.0,
		"bombers_escaped": escaped, "bombs_dropped": escaped * 3,
	}


func _node(id: int, q: int, r: int, type_id: StringName, owner: StringName,
		garrison: float) -> Dictionary:
	return {
		"id": id, "q": q, "r": r, "type": type_id, "owner": owner,
		"garrison": WarSim.quantize(garrison), "fort": 1.0, "intel_age": 0,
		"biome": &"hills", "weather": &"clear", "home": id == 0,
		"hq": false,
	}


## ---------- A2: it actually flies passes, in a real arena ----------

func _fly_it() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var config: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	_aegis = (load("res://scenes/combat/aegis.tscn") as PackedScene).instantiate() as Aegis
	_aegis.enemy_config = config
	_aegis.position = Vector3(0.0, 20.0, 60.0)
	_aegis.route_end = Vector3(0.0, 20.0, 0.0)
	_arena.add_child(_aegis)
	_aegis.bomb_dropped.connect(func(at: Vector3) -> void: _drops.append(at))
	_aegis.escaped.connect(func() -> void: _escaped += 1)
	# THE UNIT ENDS WHILE THE BOMBER IS STILL FLYING, and that is the rule, not an
	# accident of timing. `composition_check` found the alternative as a 60 s
	# timeout with one unit left: a wave held open by an enemy that had already
	# dropped everything it had and was leaving.
	_aegis.detonated.connect(func() -> void:
		_detonated += 1
		_alive_when_unit_ended = is_instance_valid(_aegis)
		_drops_when_unit_ended = _drops.size())
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks > int(MAX_SECONDS * 240.0):
		_expect(false, "the bomber finished its payload inside %.0f s (dropped %d of %d)"
				% [MAX_SECONDS, _drops.size(),
				int((load("res://resources/default_enemy_aegis.tres") as EnemyConfig).payload)])
		_report()
		return
	# BETWEEN PASSES IT MUST CLIMB AWAY, or "it flies passes" is really "it sits
	# on the target". Sampled while it is alive and has dropped at least one.
	if is_instance_valid(_aegis) and _drops.size() == 1 and not _seen_two_passes:
		var distance: float = _aegis.global_position.distance_to(_aegis.route_end)
		_height_between_passes = maxf(_height_between_passes, distance)
	if _drops.size() >= 2:
		_seen_two_passes = true
	if _escaped > 0 or not is_instance_valid(_aegis):
		_verify()
		return


func _verify() -> void:
	var config: EnemyConfig = load("res://resources/default_enemy_aegis.tres")
	_expect(_drops.size() == config.payload,
			"a bomber drops exactly its payload and no more (%d of %d)"
			% [_drops.size(), config.payload])
	_expect(_seen_two_passes,
			"it SURVIVES its own bombs and comes back for another pass (%d passes)"
			% _drops.size())
	_expect(_height_between_passes > Aegis.ARRIVE_RADIUS * 3.0,
			"and it climbs away between passes rather than sitting on the target (%.1f m)"
			% _height_between_passes)
	_expect(_escaped == 1,
			"a spent bomber leaves, and says so exactly once (%d)" % _escaped)
	_expect(_detonated == 1,
			"and the unit is over exactly once, so a wave holding it can clear (%d)"
			% _detonated)
	_expect(_alive_when_unit_ended,
			"the unit ends while the bomber is still ALIVE and flying home")
	_expect(_drops_when_unit_ended == config.payload,
			"and it ends when the PAYLOAD is spent, not when the body leaves (%d of %d)"
			% [_drops_when_unit_ended, config.payload])
	# Every drop must land on the ROUTE, not wherever the bomber happened to be.
	var stray: int = 0
	for at: Vector3 in _drops:
		if at.distance_to(Vector3(0.0, 20.0, 0.0)) > Aegis.ARRIVE_RADIUS:
			stray += 1
	_expect(stray == 0, "every bomb lands on the target it was aimed at (%d stray)" % stray)
	_report()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[aegis_check]   ok   %s" % message)
	else:
		_failures += 1
		print("[aegis_check]  FAIL  %s" % message)


func _report() -> void:
	if _failures == 0:
		print("[aegis_check] PASS")
	else:
		print("[aegis_check] FAIL - %d check(s)" % _failures)
	quit(0 if _failures == 0 else 1)
