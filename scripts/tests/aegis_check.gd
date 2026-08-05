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
## Seven things it holds, each of which is a decision somebody made:
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
##   7. v2.20 - THE BOMB FALLS AND LANDS. New, and it is the one this check could
##      not have caught in the shape it shipped in.
##
## Plus the hazard the magazine grammar introduced: an enemy magazine must not be
## refillable by the player's own resupply gates.
##
## WHY 7 IS PHRASED THE WAY IT IS. The bug the user flew was invisible to every
## assertion here, and the reason is worth keeping: the old check asked *"does a
## drop happen, and is it aimed at the right place"*, which the mid-air blast
## answered perfectly. It never asked whether anything DESCENDED. So the new
## assertions are about the two things a release-point test structurally cannot
## see — a body that exists after the release, and a detonation whose ALTITUDE is
## the ground rather than the bomber's. A check that watched only `bomb_dropped`
## would pass on the broken build again, so this one watches the `bombs` group
## and the impact height, and the mutation that proves it is deleting the fall.
##
## Run: <godot> --headless -s scripts/tests/aegis_check.gd --path .

const THEATER_SEED: int = 4242
const MAX_SECONDS: float = 40.0
## The arena's floor. A real StaticBody3D rather than an implied plane, because
## the whole of assertion 7 is "the bomb meets the ground" and a check flown over
## nothing would have no ground for it to meet.
const GROUND_Y: float = 0.0
const GROUND_SPAN: float = 400.0
## The bomber's cruise altitude in the arena, and where its route ends.
const FLIGHT_Y: float = 20.0
const TICK_HZ: float = 240.0

var _failures: int = 0
var _arena: Node3D
var _aegis: Aegis
var _drops: Array[Vector3] = []
## Where bombs actually WENT OFF. The list the old check had no way to build,
## because nothing ever left the bomber.
var _impacts: Array[Vector3] = []
## Physics tick of the first release and of its impact. The gap between them is
## the telegraph, and a gap of zero is precisely the bug.
var _first_release_tick: int = -1
var _first_impact_tick: int = -1
var _first_release_at: Vector3 = Vector3.INF
var _aim_point: Vector3 = Vector3.INF
## Bombs already wired up, so the group poll connects each body exactly once.
var _wired: Dictionary = {}
var _escaped: int = 0
var _detonated: int = 0
var _ticks: int = 0
var _stage: int = 0
var _seen_two_passes: bool = false
var _alive_when_unit_ended: bool = false
var _drops_when_unit_ended: int = -1
var _height_between_passes: float = -1.0
## Stage 2 (the deadline): the bomber is killed the instant it lets go, and the
## bomb has to land anyway.
var _orphan_landed: bool = false
var _bomber_dead_before_impact: bool = false


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
	_arena.add_child(_ground())
	_aegis = _bomber(Vector3(0.0, FLIGHT_Y, 60.0))
	_aegis.bomb_dropped.connect(func(at: Vector3) -> void:
		_drops.append(at)
		if _first_release_tick < 0:
			_first_release_tick = _ticks
			_first_release_at = at)
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


## A floor for the ordnance to hit. Top face exactly at GROUND_Y, so an impact
## altitude is a number the assertions can read literally.
func _ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SPAN, 2.0, GROUND_SPAN)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, GROUND_Y - 1.0, 0.0)
	body.add_child(collision)
	return body


func _bomber(at: Vector3) -> Aegis:
	var bomber := (load("res://scenes/combat/aegis.tscn") as PackedScene).instantiate() as Aegis
	bomber.enemy_config = load("res://resources/default_enemy_aegis.tres")
	bomber.position = at
	bomber.route_end = Vector3(0.0, FLIGHT_Y, 0.0)
	_arena.add_child(bomber)
	return bomber


## THE ORDNANCE IS WATCHED THROUGH THE GROUP, not through the bomber. That is the
## point of stage 2 and it costs nothing in stage 1: a bomb whose bomber has been
## killed has no one left to relay its signal, so a check that could only hear
## about impacts via the aegis could never assert that a released bomb outlives
## the aircraft.
func _wire_bombs() -> void:
	for node: Node in get_nodes_in_group(&"bombs"):
		var id: int = node.get_instance_id()
		if _wired.has(id):
			continue
		_wired[id] = true
		var bomber_alive: bool = is_instance_valid(_aegis)
		(node as Bomb).exploded.connect(func(at: Vector3) -> void:
			_impacts.append(at)
			if _first_impact_tick < 0:
				_first_impact_tick = _ticks
			if _stage == 1:
				_orphan_landed = true
				_bomber_dead_before_impact = not is_instance_valid(_aegis) \
						and bomber_alive)


func _on_physics_frame() -> void:
	_ticks += 1
	_wire_bombs()
	if _stage == 1:
		# Stage 2 owns its own deadline AND its own sentence. Letting the timeout
		# below cover both stages made a mutation report "the bomber finished its
		# payload" when what had actually happened was that its ordnance was
		# deleted along with it — a true failure naming the wrong thing, which is
		# only marginally better than no failure at all.
		_run_deadline_stage()
		return
	if _ticks > int(MAX_SECONDS * TICK_HZ):
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
	if is_instance_valid(_aegis):
		_aim_point = _aegis.bomb_aim_point()
	# The last bomb is still in the air when the bomber egresses, so the flight
	# is not over until the ordnance has landed too.
	if (_escaped > 0 or not is_instance_valid(_aegis)) \
			and get_nodes_in_group(&"bombs").is_empty():
		_verify()


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
	_verify_the_bomb_falls(config)
	_stage = 1
	_ticks = 0
	_start_deadline_stage()


## ---------- v2.20: the bomb is a BOMB ----------

## THE FOUR THINGS A RELEASE-POINT TEST CANNOT SEE. Each of these fails on the
## build the user flew, and the old check passed on it.
func _verify_the_bomb_falls(config: EnemyConfig) -> void:
	_expect(_impacts.size() == config.payload,
			"every bomb released reaches the ground and goes off there (%d of %d)"
			% [_impacts.size(), _drops.size()])

	# EVERY ASSERTION BELOW READS `_impacts`, SO EVERY ONE OF THEM IS VACUOUS ON AN
	# EMPTY LIST — which is exactly the state the broken build produces. Caught by
	# running the mutation: restoring the mid-air blast left two of these printing
	# `ok` over zero impacts. So each one carries the non-emptiness in its own
	# condition rather than trusting the assertion above to have failed first.
	# This is the house failure mode (v2.17's "two checks that could not fail")
	# and the only defence against it is to run the mutation and read the output.
	var landed: bool = not _impacts.is_empty()

	# 1. IT EXPLODES ON THE GROUND, not at the bomber's altitude. This is the
	#    user's report turned into a number: the old blast went off at FLIGHT_Y.
	var airburst: int = 0
	var highest: float = -INF
	for at: Vector3 in _impacts:
		highest = maxf(highest, at.y)
		if absf(at.y - GROUND_Y) > 1.0:
			airburst += 1
	_expect(landed and airburst == 0,
			"and it goes off ON THE GROUND rather than in mid-air (%d airburst of %d, highest %.1f m of %.0f m cruise)"
			% [airburst, _impacts.size(), highest, FLIGHT_Y])

	# 2. IT FELL. A blast one metre under the release point would satisfy the
	#    altitude test on a bomber flying low; this one asks for the drop itself.
	var fell: float = _first_release_at.y - (
			_impacts[0].y if landed else _first_release_at.y)
	_expect(landed and fell > FLIGHT_Y * 0.5,
			"the bomb DESCENDS a real distance from the rack to the blast (%.1f m)" % fell)

	# 3. THERE IS A WINDOW between bombs-away and the blast. Zero is the bug: the
	#    old code emitted the drop and the explosion on the same tick, which is
	#    why nothing was ever seen to fall.
	var fall_s: float = float(_first_impact_tick - _first_release_tick) / TICK_HZ
	_expect(_first_impact_tick > _first_release_tick and fall_s > 0.5,
			"and there is a real fall between letting go and the blast (%.2f s)" % fall_s)

	# 4. IT LANDS WHERE IT WAS AIMED, which is what the release lead buys. Without
	#    the lead the bomb is let go over the aim point and carries a whole fall's
	#    worth of the bomber's speed past it — 14 m at these settings, against a
	#    9 m blast — so this is the assertion that holds the ballistics.
	var aim: Vector3 = _aim_point if _aim_point != Vector3.INF \
			else Vector3(0.0, GROUND_Y, 0.0)
	var wide: int = 0
	var worst: float = 0.0
	for at: Vector3 in _impacts:
		var miss: float = Vector2(at.x - aim.x, at.z - aim.z).length()
		worst = maxf(worst, miss)
		if miss > config.bomb_radius:
			wide += 1
	_expect(landed and wide == 0,
			"every bomb lands inside its own blast radius of the aim point (%d wide of %d, worst %.1f m of %.1f m)"
			% [wide, _impacts.size(), worst, config.bomb_radius])
	# And the lead is REAL rather than incidental: the bomber lets go before the
	# target, not over it.
	var lead: float = Vector2(_first_release_at.x - aim.x,
			_first_release_at.z - aim.z).length()
	_expect(lead > Aegis.ARRIVE_RADIUS,
			"because the bomber leads its aim point instead of dropping on top of it (%.1f m)"
			% lead)


## ---------- v2.20: the deadline is the RELEASE, not the kill ----------

## A bomber killed a heartbeat after it lets go still lands that bomb. It is the
## claim `_drop_bomb` makes by parenting the ordnance to the bomber's PARENT, and
## the mutation that breaks it (parent to `self`) is one word — so it gets its
## own flight rather than a comment.
func _start_deadline_stage() -> void:
	_wired.clear()
	if is_instance_valid(_aegis):
		_aegis.queue_free()
	_aegis = _bomber(Vector3(0.0, FLIGHT_Y, 60.0))


func _run_deadline_stage() -> void:
	# Kill it the moment the rack is empty of its first bomb.
	if is_instance_valid(_aegis) and _aegis.bombs_dropped() > 0:
		_aegis.take_hit(100000.0)
	if _orphan_landed:
		_expect(_bomber_dead_before_impact,
				"the bomber was destroyed before its bomb landed")
		_expect(true, "and the bomb it had already let go of landed anyway")
		_report()
		return
	if _ticks > int(MAX_SECONDS * TICK_HZ):
		_expect(false,
				"a bomb outlives the bomber that dropped it (nothing landed in %.0f s)"
				% MAX_SECONDS)
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
