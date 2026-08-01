extends SceneTree

## Headless behaviour check for the composed sortie (Iteration 12, phase 2).
## The seventeenth check, and it lands the day the runner does.
##
## The scar it exists for is the standing one: a results table can only ever
## say "this sortie did not finish", which is equally consistent with a hard
## sortie, a broken runner, and a unit that flew out of the level. This runner
## has THREE new ways to deadlock that no existing check can see:
##
##   - a STRIKE whose objective never dies never opens its egress, so the
##     sortie hangs with the pilot alive and nothing left to shoot;
##   - a DOGFIGHT has no objective at all (`assets: 0`), so the field-cleared
##     path is the only thing that can ever end it, and it is a separate branch;
##   - a RESERVE that fires twice, or never, silently changes the whole
##     archetype - and two structurally identical waves are exactly the case a
##     Dictionary-keyed spent-flag would collapse into one.
##
## Two halves, deliberately. Part A drives the runner with NO arena at all, by
## calling its outcome paths directly - the only way to cover specs nobody has
## time to fly. Part B builds a real greybox and flies two composed specs from
## a real theater, killing exactly what the spec placed.
##
## Run: <godot> --headless -s scripts/tests/sortie_check.gd --path .

const THEATER_SEED: int = 4242
const MAX_SECONDS: float = 90.0

var _failures: Array[String] = []
var _main: Node3D
var _runner: SortieRunner
var _ticks: int = 0
var _ticks_max: int
var _stage: int = 0
var _spec: Dictionary = {}
var _finished: Array[Dictionary] = []
var _egress_opened: int = 0


func _initialize() -> void:
	_check_spec_shape()
	_check_trigger_selection()
	if not _failures.is_empty():
		_report()
		return
	_ticks_max = int(MAX_SECONDS * float(Engine.physics_ticks_per_second))
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate() as Node3D
	root.add_child(_main)
	# The wave director owns main's own run; this check drives a SortieRunner
	# instead, so the two must not both be spawning into one arena.
	var director: Node = _main.get_node_or_null("WaveDirector")
	if director != null:
		director.set_process(false)
		director.set_physics_process(false)
	_runner = SortieRunner.new()
	_runner.center = Vector3(-18.0, 0.0, -15.0)
	_runner.sortie_finished.connect(func(r: Dictionary) -> void: _finished.append(r))
	_runner.egress_opened.connect(func() -> void: _egress_opened += 1)
	_main.add_child(_runner)
	physics_frame.connect(_on_physics_frame)


## ---------- Part A: the runner's contracts, without an arena ----------

## Every slice-ready spec a running war produces must be something the runner
## can actually read: named types it can build, layers it knows, and an
## objective count it can terminate on.
func _check_spec_shape() -> void:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	var seen: Dictionary = {}
	var slice_ready: int = 0
	var with_triggers: int = 0
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if not SortieComposer.is_slice_ready(spec):
			continue
		slice_ready += 1
		if not spec["triggers"].is_empty():
			with_triggers += 1
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				seen[unit["type"]] = true
				if not WaveDirector.ROSTER.has(unit["type"]):
					_fail("spec places %s, which has no scene" % unit["type"])
				if not SortieRunner.LAYER_RADIUS.has(layer):
					_fail("spec uses layer %s, which the runner cannot place" % layer)
		for trigger: Dictionary in spec["triggers"]:
			for unit: Dictionary in trigger["units"]:
				seen[unit["type"]] = true
				if not WaveDirector.ROSTER.has(unit["type"]):
					_fail("reserve names %s, which has no scene" % unit["type"])
	_expect(slice_ready > 0, "the theater offers slice-ready sorties (%d)" % slice_ready)
	_expect(with_triggers > 0,
			"slice-ready sorties carry reserves (%d of %d)" % [with_triggers, slice_ready])
	# The point of W8: if the war can field it, the runner can build it. A type
	# that reaches a spec and has no scene is the silent-deletion bug.
	_expect(seen.size() > 0, "sorties actually place units (%d types seen)" % seen.size())


## THE TRIGGER RULE, tested directly because it is the archetype. A dogfight
## holds two reserves both keyed `wave_cleared`; releasing both on the first
## clear collapses its pacing into one dump, and firing neither leaves the
## sortie unfinishable. Both failures are invisible from a body count.
##
## Driven through the public surface with a hand-built spec, so it does not
## depend on which node a seed happens to produce.
func _check_trigger_selection() -> void:
	var runner := SortieRunner.new()
	var spec: Dictionary = _bare_spec(&"dogfight", &"clear_airspace", 0)
	spec["triggers"] = [
		{"on": &"wave_cleared", "wave": 1, "after_s": 0.0, "units": []},
		{"on": &"wave_cleared", "wave": 2, "after_s": 0.0, "units": []},
	]
	runner.spec = spec
	# Reproduce start()'s trigger arming without needing a tree.
	for trigger: Dictionary in spec["triggers"]:
		runner._triggers.append(trigger)
		runner._trigger_spent.append(false)
	_expect(runner.reserves_held() == 2, "two structurally similar reserves stay distinct")
	runner._trigger_spent[0] = true
	_expect(runner.reserves_held() == 1,
			"spending one reserve leaves the other (got %d)" % runner.reserves_held())
	runner.free()


func _bare_spec(archetype: StringName, objective: StringName,
		assets: int) -> Dictionary:
	return {
		"version": 1, "seed": 7, "truth": true, "node_id": 0,
		"archetype": archetype, "objective": objective,
		"objective_assets": assets, "triggers": [],
		"layers": {&"outer": [], &"mid": [], &"inner": []},
	}


## ---------- Part B: two composed sorties, in a real arena ----------

func _on_physics_frame() -> void:
	_ticks += 1
	if _ticks < 30:
		return
	if _ticks > _ticks_max:
		_fail("timed out at stage %d after %.0fs" % [_stage, MAX_SECONDS])
		_report()
		return
	match _stage:
		0: _stage_start_dogfight()
		1: _stage_clear_dogfight()
		2: _stage_start_strike()
		3: _stage_flatten_objective()
		4: _stage_verify()


func _stage_start_dogfight() -> void:
	_spec = _find_spec(&"dogfight")
	if _spec.is_empty():
		_fail("the theater produced no dogfight to fly")
		_report()
		return
	_runner.start(_spec)
	_expect(_runner.remaining() > 0,
			"a composed dogfight places its garrison (%d units)" % _runner.remaining())
	_expect(not _runner.has_objective(), "a dogfight has no structure to flatten")
	_stage = 1


## Kill exactly what the runner placed, and nothing else in the arena. The
## reserves must then arrive on their own, or the sortie can never end.
func _stage_clear_dogfight() -> void:
	if _runner.phase == SortieRunner.Phase.EGRESS:
		_expect(_egress_opened == 1,
				"clearing the field opens the way home exactly once (%d)" % _egress_opened)
		_runner.force_egress()
		_stage = 2
		return
	if _runner.phase == SortieRunner.Phase.DONE:
		_stage = 2
		return
	_kill_one_unit()


func _stage_start_strike() -> void:
	if _finished.size() < 1:
		return
	var done: Dictionary = _finished[0]
	_expect(bool(done["objective_complete"]),
			"a cleared dogfight counts as complete")
	_expect(bool(done["egressed"]), "and it records that the pilot got out")
	_expect(float(done["dent"]) > 0.0,
			"the dogfight dents the node by what died (%.2f)" % float(done["dent"]))
	_sweep_arena()
	_spec = _find_spec(&"strike")
	if _spec.is_empty():
		_fail("the theater produced no strike to fly")
		_report()
		return
	_runner.start(_spec)
	_expect(_runner.has_objective(),
			"a composed strike places structures (%d)" % int(_spec["objective_assets"]))
	_expect(_runner.objectives.size() == int(_spec["objective_assets"]),
			"one body per objective asset (%d of %d)"
			% [_runner.objectives.size(), int(_spec["objective_assets"])])
	_stage = 3


## The strike's own deadlock: flatten the objective WITHOUT clearing the
## garrison, and the egress must still open. If it only opened on an empty
## field, a strike would be a dogfight wearing a building.
func _stage_flatten_objective() -> void:
	if _runner.phase == SortieRunner.Phase.EGRESS:
		_expect(_runner.remaining() > 0 or _spec["layers"][&"outer"].is_empty(),
				"the egress opened with the garrison still up - the objective is the gate")
		_runner.force_egress()
		_stage = 4
		return
	for asset: ObjectiveAsset in _runner.objectives:
		if is_instance_valid(asset) and asset.alive():
			asset.take_hit(40.0)
			return


func _stage_verify() -> void:
	if _finished.size() < 2:
		return
	var done: Dictionary = _finished[1]
	_expect(int(done["objectives_destroyed"]) == int(done["objective_assets"]),
			"every structure went down (%d of %d)"
			% [int(done["objectives_destroyed"]), int(done["objective_assets"])])
	_expect(bool(done["objective_complete"]), "which completes the strike")
	_expect(bool(done["egressed"]), "and the pilot got out")
	_expect(_egress_opened == 2, "each sortie opened its egress once (%d)" % _egress_opened)
	# P2.q4: the result is serializable, because the war has to eat it and the
	# save has to carry it (F4).
	var round_trip: Variant = str_to_var(var_to_str(done))
	_expect(round_trip != null and var_to_str(round_trip) == var_to_str(done),
			"a sortie result round-trips var_to_str")
	_report()


## ---------- helpers ----------

func _find_spec(archetype: StringName) -> Dictionary:
	var config := WarConfig.new()
	var state: Dictionary = TheaterGenerator.generate(config, THEATER_SEED)
	for node: Dictionary in state["nodes"]:
		var spec: Dictionary = SortieComposer.compose(node, state, config)
		if spec["archetype"] != archetype or not SortieComposer.is_slice_ready(spec):
			continue
		# Needs something to actually place, or the stage proves nothing.
		var placed: int = 0
		for layer: StringName in SortieComposer.LAYER_ORDER:
			for unit: Dictionary in spec["layers"][layer]:
				placed += int(unit["count"])
		if placed > 0:
			return spec
	return {}


func _kill_one_unit() -> void:
	for unit: Node in _runner.units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("take_hit"):
			unit.take_hit(9999.0)
			return
		# A cloud is a container: reach through to a body.
		for child: Node in unit.get_children():
			if child.has_method("take_hit"):
				child.take_hit(9999.0)
				return
		unit.queue_free()
		return


## Between sorties, clear whatever the last one left behind so the next one's
## counts mean what they say.
func _sweep_arena() -> void:
	for asset: ObjectiveAsset in _runner.objectives:
		if is_instance_valid(asset):
			asset.queue_free()
	for unit: Node in _runner.units:
		if is_instance_valid(unit):
			unit.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("[sortie_check]   ok   %s" % message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	print("[sortie_check]   FAIL %s" % message)


func _report() -> void:
	if _failures.is_empty():
		print("[sortie_check] PASS")
	else:
		print("[sortie_check] FAIL - %d check(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
