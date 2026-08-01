extends SceneTree

## Headless check for THE LOOP HOME (Iteration 12, W7): a flown sortie priced
## back into the war, the war ticking, and the campaign surviving a save.
## The eighteenth check.
##
## This is the joint that turns a sortie generator into a campaign, and every
## failure it guards is silent:
##
##   - a dent that is never applied means "your fights dent the war" is a
##     slogan; nothing crashes, the war just never notices you;
##   - a capture that does not flip ownership means the campaign cannot be WON,
##     which no single sortie would ever reveal;
##   - a DEAD pilot whose sortie never resolves loses the dent entirely, which
##     is exactly the case P2.q4 was written for and exactly the one a happy-path
##     test never reaches;
##   - a save that round-trips through the wrong FORMAT looks perfect and forks
##     the war - JSON turns every StringName into a String (so every node is
##     suddenly neutral) and every int into a float (so `rng_state` cannot
##     survive, and the "same save replays the same war" promise dies quietly).
##
## No arena and no physics: the runner's result is a plain Dictionary by design,
## so the whole loop can be exercised as arithmetic. `sortie_check` covers the
## half that needs bodies.
##
## Run: <godot> --headless -s scripts/tests/war_loop_check.gd --path .

const THEATER_SEED: int = 4242

var _failures: Array[String] = []


func _init() -> void:
	var config := WarConfig.new()
	_check_dent_applies(config)
	_check_capture_gate(config)
	_check_pilot_lost(config)
	_check_save_round_trip(config)
	_check_save_format_would_catch_json(config)
	_check_campaign_advances(config)
	_report()


## P2.q4, the unconditional half: everything destroyed dents the node, whatever
## else happened.
func _check_dent_applies(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var node: Dictionary = _enemy_node(state)
	var before: float = float(node["garrison"])
	var summary: Dictionary = WarSim.apply_sortie(state, config,
			_result(int(node["id"]), {&"raider": 4}, false, false))
	_expect(not summary.is_empty(), "a flown sortie resolves against its node")
	var dent: float = WarManifest.dent_from_kills({&"raider": 4})
	_expect(dent > 0.0, "four raiders are worth something (%.2f)" % dent)
	_expect(is_equal_approx(float(node["garrison"]), WarSim.quantize(before - dent)),
			"the garrison falls by exactly the dent (%.2f -> %.2f)"
			% [before, float(node["garrison"])])
	_expect(int(node["intel_age"]) == 0,
			"flying over a node clears its fog, however the sortie went")
	_expect(int(state["sorties"]) == 1, "the war counts the sortie")

	# A partial that kills nothing still resolves; it just moves nothing.
	var quiet: Dictionary = WarSim.apply_sortie(state, config,
			_result(int(node["id"]), {}, false, false))
	_expect(not quiet.is_empty(), "a sortie that killed nothing still resolves")
	_expect(is_equal_approx(float(quiet["garrison_before"]),
			float(quiet["garrison_after"])), "and moves the garrison not at all")


## P1.q2 / P2.9: an assault next to ground you hold CAPTURES; a deep strike with
## nothing to hold it only degrades. Both directions, because a capture gate
## that always fires and one that never fires look identical from one sortie.
func _check_capture_gate(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var adjacent: Dictionary = _enemy_node_adjacent_to_player(state, true)
	_expect(not adjacent.is_empty(), "the theater has a capturable front node")
	if not adjacent.is_empty():
		var summary: Dictionary = WarSim.apply_sortie(state, config,
				_result(int(adjacent["id"]), {&"raider": 1}, true, false))
		_expect(bool(summary["captured"]), "completing a front assault takes the node")
		_expect(adjacent["owner"] == &"player", "and the map says so")
		_expect(float(adjacent["fort"]) >= 1.3, "captured ground is dug in")

	var deep: Dictionary = _enemy_node_adjacent_to_player(state, false)
	_expect(not deep.is_empty(), "the theater has a deep node with no player border")
	if not deep.is_empty():
		var before: float = float(deep["garrison"])
		var summary: Dictionary = WarSim.apply_sortie(state, config,
				_result(int(deep["id"]), {&"raider": 1}, true, false))
		_expect(not bool(summary["captured"]),
				"a deep strike cannot hold ground, so it does not capture")
		_expect(bool(summary["degraded"]), "it degrades the node instead")
		_expect(float(deep["garrison"]) < before, "and the garrison actually fell")
		_expect(deep["owner"] == &"enemy", "the node stays enemy")


## THE CASE A HAPPY PATH NEVER REACHES. A dead pilot's sortie must still resolve
## - the dent is kept, the objective is NOT credited, and a pilot comes off the
## roster (F1's lives economy).
func _check_pilot_lost(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var node: Dictionary = _enemy_node_adjacent_to_player(state, true)
	if node.is_empty():
		_fail("no capturable node to test a death against")
		return
	var pilots: int = int(state["pilots"])
	var before: float = float(node["garrison"])
	# Objective complete AND dead: the completion must not count.
	var summary: Dictionary = WarSim.apply_sortie(state, config,
			_result(int(node["id"]), {&"raider": 3}, true, true))
	_expect(float(node["garrison"]) < before, "a dead pilot still dents the node")
	_expect(not bool(summary["captured"]),
			"but dying on the way out does not capture the ground")
	_expect(node["owner"] == &"enemy", "the node stays enemy")
	_expect(int(state["pilots"]) == pilots - 1,
			"and it costs a pilot (%d -> %d)" % [pilots, int(state["pilots"])])


## F4: the save is the state, and it comes back byte-identical.
func _check_save_round_trip(config: WarConfig) -> void:
	WarSave.clear()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	# Run the war forward so the save carries evolved floats and a used RNG
	# stream rather than pristine generator output.
	for i: int in 12:
		WarSim.tick(state, config, 0.6)
	_expect(WarSave.save(state), "the war writes to %s" % WarSave.PATH)
	_expect(WarSave.exists(), "and the file is there")
	var loaded: Dictionary = WarSave.load_war()
	_expect(not loaded.is_empty(), "and it loads back")
	_expect(var_to_str(loaded) == var_to_str(state),
			"the loaded war is textually identical to the saved one")
	# The two that JSON would silently break.
	_expect(loaded.get("rng_state") is int and loaded["rng_state"] == state["rng_state"],
			"rng_state survives as an int (%s)" % typeof(loaded.get("rng_state")))
	var first: Dictionary = loaded["nodes"][0]
	_expect(first["owner"] is StringName,
			"a node's owner is still a StringName, so side comparisons still work")
	_expect(first["type"] is StringName, "and so is its type")

	# Resuming and ticking must not fork the war: same save, same future.
	var a: Dictionary = WarSave.load_war()
	var b: Dictionary = WarSave.load_war()
	for i: int in 5:
		WarSim.tick(a, config, 0.6)
		WarSim.tick(b, config, 0.6)
	_expect(var_to_str(a) == var_to_str(b),
			"two resumes of one save run the same war forward")
	WarSave.clear()
	_expect(not WarSave.exists(), "and the file can be cleared")


## Guards the FORMAT decision rather than the code, because the failure it
## prevents is invisible: a JSON save parses, loads, and produces a war whose
## every node is neutral and whose RNG has forked.
func _check_save_format_would_catch_json(config: WarConfig) -> void:
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var via_json: Variant = JSON.parse_string(JSON.stringify(state))
	if via_json == null:
		_expect(true, "JSON cannot even represent the war state")
		return
	var json_state: Dictionary = via_json
	var node: Dictionary = json_state["nodes"][0]
	# These are ASSERTIONS THAT JSON IS BROKEN HERE. If one of them ever starts
	# failing, Godot's JSON gained type fidelity and this file's whole rationale
	# should be re-read rather than trusted.
	_expect(not (node["owner"] is StringName),
			"JSON loses StringName, which is why the save is var_to_str")
	_expect(json_state["rng_state"] is float,
			"JSON turns rng_state into a float, which cannot hold a 64-bit seed")


## The end-to-end shape: several flown sorties in a row move the war, and the
## campaign survives being put down and picked up between each one.
func _check_campaign_advances(config: WarConfig) -> void:
	WarSave.clear()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var start_enemy: int = _count_owned(state, &"enemy")
	var captures: int = 0
	for i: int in 25:
		var target: Dictionary = _enemy_node_adjacent_to_player(state, true)
		if target.is_empty():
			break
		var summary: Dictionary = WarSim.apply_sortie(state, config,
				_result(int(target["id"]), {&"raider": 6, &"turret": 2}, true, false))
		if bool(summary["captured"]):
			captures += 1
		WarSim.tick(state, config)
		# Put the war down and pick it up again between every sortie, which is
		# what actually happens when a human closes the game.
		WarSave.save(state)
		state = WarSave.load_war()
		if state.is_empty():
			_fail("the campaign could not be resumed at sortie %d" % i)
			return
		if WarSim.winner(state) != &"":
			break
	_expect(captures > 0, "flown sorties take ground (%d captures)" % captures)
	_expect(_count_owned(state, &"enemy") < start_enemy,
			"the enemy holds less than it started with (%d -> %d)"
			% [start_enemy, _count_owned(state, &"enemy")])
	_expect(int(state["sorties"]) > 0, "and the war counted them (%d)"
			% int(state["sorties"]))
	WarSave.clear()


## ---------- helpers ----------

## A SortieRunner result, without needing a runner.
func _result(node_id: int, kills: Dictionary, complete: bool,
		lost: bool) -> Dictionary:
	return {
		"node_id": node_id,
		"seed": 1,
		"archetype": &"strike",
		"objective_assets": 3,
		"objectives_destroyed": 3 if complete else 1,
		"objective_complete": complete,
		"egressed": complete and not lost,
		"pilot_lost": lost,
		"outcome": &"lost" if lost else (&"complete" if complete else &"partial"),
		"kills": kills,
		"dent": WarManifest.dent_from_kills(kills),
	}


func _enemy_node(state: Dictionary) -> Dictionary:
	for node: Dictionary in state["nodes"]:
		if node["owner"] == &"enemy" and float(node["garrison"]) > 8.0:
			return node
	return {}


func _enemy_node_adjacent_to_player(state: Dictionary,
		adjacent: bool) -> Dictionary:
	for node: Dictionary in state["nodes"]:
		if node["owner"] != &"enemy" or bool(node["hq"]):
			continue
		if WarSim.has_adjacent_owner(state, node, &"player") == adjacent:
			return node
	return {}


func _count_owned(state: Dictionary, side: StringName) -> int:
	var count: int = 0
	for node: Dictionary in state["nodes"]:
		if node["owner"] == side:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[war_loop_check]   ok   %s" % message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	print("[war_loop_check]   FAIL %s" % message)


func _report() -> void:
	if _failures.is_empty():
		print("[war_loop_check] PASS")
	else:
		print("[war_loop_check] FAIL - %d check(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
